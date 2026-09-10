-- BiS Innervate :: Rez.lua
-- The rez module, folded in from BiS Rez 3.0. One secure button per healer:
--
--   dead? -yes-> afford rez? -yes-> REZ the best corpse
--        |               `--no--> DRINK
--        `-no-> hurt? -yes-> afford heal? -yes-> HEAL (one hurt: the smallest
--              |                    |            heal that covers them; two or
--              |                    |            more: the group heal)
--              |                    `--no--> DRINK
--              `-no-> the button is not on screen
--
-- Never in combat: a secure state driver hides it the moment a fight starts.
-- For everyone else the same button is "rez me first", on screen only while
-- they are dead.
--
-- The design goal, in Arn's words: "get everyone rezzed faster to keep
-- raiding." Every ordering decision here answers to that.
--
-- Rules that came with the merge:
--   * a druid's Rebirth is NEVER spent here. It is not in the rez table at
--     all; a druid gets heal, drink and the window.
--   * a claim attaches on UNIT_SPELLCAST_START, never on click: a click that
--     dies on "not enough mana" never begins a cast and must not lock a corpse.
--   * cast-bar claims expire when the cast actually lands (UnitCastingInfo's
--     5th return), not on a flat timer.
--   * nothing protected is written in a fight: the macro is rebound in
--     Window:Bind / RebindRez, out of combat, or deferred to AfterCombat.
--   * everything is keyed by NAME. A macro aims at "[target=Name]", never at
--     a raid slot, and a name the client cannot resolve leaves the button
--     aimed at nobody rather than at whoever inherited the slot.
--
-- Wire (protocol 4, additive - a 3.2 client ignores these):
--   RCLAIM|name    I have started casting a rez on this corpse
--   RDONE |name    my rez landed on it
--   RFREE |name    my cast died; the corpse is open again
-- Who can rez, and their wipe protection, ride the HELLO/STATE kinds blob as
-- "REZ=RS" (R Reincarnation with an Ankh, D Divine Intervention, S Soulstone).

local ADDON, NS = ...
local T = NS.T

local Rez = {}
NS.Rez = Rez

--------------------------------------------------------------------
-- constants
--------------------------------------------------------------------

-- Lower number = rezzed first. A throughput order, not a favourites list:
--   1-3 the rezzers (every one you stand up multiplies the rate)
--   4-6 mana (Innervate, water, a soulstone for next time)
--   7-9 everyone else
Rez.PRIORITY = {
    PRIEST = 1, PALADIN = 2, SHAMAN = 3,
    DRUID = 4, MAGE = 5, WARLOCK = 6,
    HUNTER = 7, WARRIOR = 8, ROGUE = 9,
}
Rez.GHOST_PENALTY  = 100    -- a released player is running back anyway
Rez.REZ_GUARD      = 30     -- seconds to ignore a target after somebody rezzed it
Rez.CLAIM_LIFE     = 15     -- seconds a broadcast claim holds
Rez.CASTBAR_LIFE   = 3      -- when the cast bar will not say when it ends
Rez.CASTBAR_SLOP   = 1.5    -- grace after their cast lands
Rez.ASK_LIFE       = 120    -- a "rez me first" call lives this long
Rez.DRY_PCT        = 0.3    -- a rezzer under this much mana counts as dry

-- heals per class; ranks and sizes come from the spellbook at runtime
Rez.CLASS_HEALS = {
    SHAMAN  = { single = { "Lesser Healing Wave", "Healing Wave" }, group = "Chain Heal" },
    PRIEST  = { single = { "Flash Heal", "Heal", "Greater Heal" }, group = "Circle of Healing" },
    PALADIN = { single = { "Flash of Light", "Holy Light" } },
    DRUID   = { single = { "Regrowth", "Healing Touch" } },
}
-- the class-wide "+% healing" talents, by English name
Rez.HEAL_TALENTS = {
    SHAMAN  = { ["Purification"]      = 0.02 },
    PRIEST  = { ["Spiritual Healing"] = 0.02 },
    PALADIN = { ["Healing Light"]     = 0.04 },
    DRUID   = { ["Gift of Nature"]    = 0.02 },
}
Rez.HEAL_REACTION = 0.3     -- click-to-cast slop, same as BiS Healing

-- the level each rank is learned at (TBC), for the downrank penalty when the
-- client will not say (GetSpellLevelLearned missing or 0). Rank 1 first.
Rez.RANK_LEVELS = {
    ["Lesser Healing Wave"] = { 20, 28, 36, 44, 52, 60, 66 },
    ["Healing Wave"]        = { 1, 6, 12, 18, 24, 32, 40, 48, 56, 60, 63, 70 },
    ["Chain Heal"]          = { 40, 46, 54, 61, 68 },
    ["Flash Heal"]          = { 20, 26, 32, 38, 44, 50, 56, 61, 67 },
    ["Heal"]                = { 16, 22, 28, 34 },
    ["Greater Heal"]        = { 40, 46, 52, 58, 60, 63, 68 },
    ["Circle of Healing"]   = { 50, 56, 60, 65, 70 },
    ["Flash of Light"]      = { 20, 26, 34, 42, 50, 58, 66 },
    ["Holy Light"]          = { 1, 6, 14, 22, 30, 38, 46, 54, 60, 62, 70 },
    ["Regrowth"]            = { 12, 18, 24, 30, 36, 42, 48, 54, 60, 65 },
    ["Healing Touch"]       = { 1, 8, 14, 20, 26, 32, 38, 44, 50, 56, 60, 62, 69 },
}

-- mana consumables, best first: the biscuit does mana AND health, the rest
-- are the 7200-mana tier
Rez.CONSUMABLES = {
    { id = 34062, name = "Conjured Manna Biscuit" },
    { id = 22018, name = "Conjured Glacier Water" },
    { id = 27860, name = "Purified Draenic Water" },
    { id = 29395, name = "Ethermead" },
    { id = 29401, name = "Sparkling Southshore Cider" },
}
Rez.CONSUMABLE_RANK = {}
for i, c in ipairs(Rez.CONSUMABLES) do Rez.CONSUMABLE_RANK[c.id] = i end
Rez.DRINK_AURAS = { [27089] = true, [24707] = true, [430] = true, [431] = true,
                    [432] = true, [1133] = true, [1135] = true, [1137] = true }

-- wipe protection: the three ways back up without a corpse run
Rez.WIPE = {
    SHAMAN  = { name = "Reincarnation", letter = "R", reagent = 17030 },     -- needs an Ankh
    PALADIN = { name = "Divine Intervention", letter = "D" },
}
Rez.SOULSTONE_AURA = "Soulstone Resurrection"
Rez.WIPE_LABEL = { R = "Reincarnation", D = "Divine Intervention", S = "Soulstone (on a rezzer)" }

-- the cast errors worth blaming on our click (localised at load)
local CAST_ERROR_GLOBALS = {
    "SPELL_FAILED_OUT_OF_RANGE", "SPELL_FAILED_LINE_OF_SIGHT", "SPELL_FAILED_BAD_TARGETS",
    "SPELL_FAILED_TARGET_DEAD", "SPELL_FAILED_TARGET_NOT_DEAD", "SPELL_FAILED_NO_MANA",
    "SPELL_FAILED_SPELL_IN_PROGRESS", "SPELL_FAILED_NOT_READY", "SPELL_FAILED_MOVING",
    "SPELL_FAILED_INTERRUPTED", "SPELL_FAILED_TARGET_NOT_IN_PARTY", "SPELL_FAILED_TARGET_NOT_IN_RAID",
    "SPELL_FAILED_BAD_IMPLICIT_TARGETS", "SPELL_FAILED_REAGENTS", "SPELL_FAILED_CASTER_DEAD",
    "SPELL_FAILED_AFFECTING_COMBAT", "SPELL_FAILED_TRY_AGAIN", "SPELL_FAILED_ITEM_NOT_READY",
    "ERR_OUT_OF_MANA", "ERR_SPELL_COOLDOWN", "ERR_SPELL_OUT_OF_RANGE", "ERR_BADATTACKPOS",
    "ERR_GENERIC_NO_TARGET", "ERR_ITEM_COOLDOWN", "ERR_CLIENT_LOCKED_OUT",
}

--------------------------------------------------------------------
-- state (one table, not thirty locals)
--------------------------------------------------------------------

Rez.claims    = {}      -- name -> { expires, who, src = "cast" | "comm" }
Rez.recent    = {}      -- name -> time somebody's rez landed on them
Rez.heals     = {}      -- single-target ranks { cast, id, base, est, heal, level } smallest first
Rez.groupHeals = {}     -- the group heal's ranks, same shape, smallest first
Rez.groupHeal = nil     -- the biggest group heal's cast name (a probe for range and lead)
Rez.rezNames  = {}      -- every class's rez spell name, for cast-bar matching
Rez.last      = nil     -- the last decision (see Decide)
Rez.pending   = nil     -- { name, at } the corpse our click aimed at
Rez.errors    = nil     -- localised cast-error strings

local function cfg() return NS.db or NS.DEFAULTS end
local function me() return NS.PlayerName() end
local function myClass() local _, c = UnitClass("player"); return c end

--------------------------------------------------------------------
-- API shims
--------------------------------------------------------------------

local function spellInfo(idOrName)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, idOrName)
        if ok and type(info) == "table" then return info.name, info.iconID or info.icon, info.castTime end
        if ok and type(info) == "string" then return info end
    end
    if GetSpellInfo then
        local ok, n, _, icon, ct = pcall(GetSpellInfo, idOrName)
        if ok and type(n) == "string" then return n, icon, ct end
    end
    return nil
end

local PLAYER_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0

local function bookName(i)
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        return C_SpellBook.GetSpellBookItemName(i, PLAYER_BANK)
    end
    if GetSpellBookItemName then return GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell") end
    if GetSpellName then return GetSpellName(i, BOOKTYPE_SPELL or "spell") end
    return nil
end

local function numSpells()
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local total = 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then total = math.max(total, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0)) end
        end
        return total
    end
    return 1000     -- old API: walk until nil
end

local function bookSpellId(i)
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local info = C_SpellBook.GetSpellBookItemInfo(i, PLAYER_BANK)
        return info and (info.spellID or info.actionID)
    end
    if GetSpellBookItemInfo then
        local a, b = GetSpellBookItemInfo(i, "spell")
        if type(a) == "string" then return b end
        return a
    end
end

-- does the spellbook hold this name? (cached until ForgetSpellCache)
function Rez:KnowsSpell(name)
    self._book = self._book or {}
    if self._book[name] ~= nil then return self._book[name] end
    local found = false
    local limit = numSpells()
    for i = 1, limit do
        local n = bookName(i)
        if not n then
            if limit >= 1000 then break end
        elseif n == name then found = true break end
    end
    self._book[name] = found
    return found
end

-- "Chain Heal(Rank 5)" -> "Chain Heal": the suffix makes cost and texture
-- lookups return nil, which reads as cost 0
local function bareName(x)
    if type(x) ~= "string" then return x end
    return (x:gsub("%b()", ""):gsub("%s+$", ""))
end
Rez.BareName = bareName

local function spellCost(spell)
    local costs
    spell = bareName(spell)
    if C_Spell and C_Spell.GetSpellPowerCost then
        local ok, c = pcall(C_Spell.GetSpellPowerCost, spell)
        if ok then costs = c end
    elseif GetSpellPowerCost then
        local ok, c = pcall(GetSpellPowerCost, spell)
        if ok then costs = c end
    end
    if type(costs) == "table" then
        for _, c in ipairs(costs) do
            if c.type == 0 then return c.cost or 0 end
        end
    end
    return 0
end

local function spellIcon(spell)
    spell = bareName(spell)
    if not spell then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, spell)
        if ok and t then return t end
    end
    if GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, spell)
        if ok and t then return t end
    end
end

local function itemIcon(itemId)
    if not itemId then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemId) end
    if GetItemIcon then return GetItemIcon(itemId) end
end

-- 1 / 0 / nil (nil = the client would not say)
local function spellInRange(spell, unit)
    spell = bareName(spell)
    if not spell or spell == "" then return nil end
    local r
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, v = pcall(C_Spell.IsSpellInRange, spell, unit)
        if ok then r = v end
        if r == true then r = 1 elseif r == false then r = 0 end
    elseif IsSpellInRange then
        local ok, v = pcall(IsSpellInRange, spell, unit)
        if ok then r = v end
    end
    return r
end

-- live cast time, so haste falls out of it for free
local function castSeconds(spell)
    spell = bareName(spell)
    if not spell then return 0 end
    local _, _, ct = spellInfo(spell)
    if type(ct) == "number" then return ct / 1000 end
    return 0
end

-- bag walk: cb(bag, slot, itemId)
local function forEachBagItem(cb)
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not numSlots then return end
    for bag = 0, 4 do
        local okN, n = pcall(numSlots, bag)
        for slot = 1, (okN and tonumber(n)) or 0 do
            local id
            if C_Container and C_Container.GetContainerItemInfo then
                local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                id = ok and type(info) == "table" and info.itemID or nil
            elseif GetContainerItemInfo then
                local ok, a, b, c, d, e, f, g, h, i, j = pcall(GetContainerItemInfo, bag, slot)
                if ok then id = j end
            end
            if id and cb(bag, slot, id) then return end
        end
    end
end

-- player buffs: cb(name, spellId) -> true to stop
local function forEachBuff(cb)
    for i = 1, 40 do
        local name, spellId
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not a then return end
            name, spellId = a.name, a.spellId
        elseif UnitBuff then
            local ok, n, _, _, _, _, _, _, _, _, id = pcall(UnitBuff, "player", i)
            if not ok or not n then return end
            name, spellId = n, id
        else
            return
        end
        if cb(name, spellId) then return end
    end
end

local function spellOffCooldown(name)
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, name)
        if ok and type(info) == "table" then start, dur = info.startTime, info.duration end
    end
    if not start and GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, name)
        if ok then start, dur = s, d end
    end
    if type(start) ~= "number" or type(dur) ~= "number" then return true end
    if dur <= 1.5 then return true end
    return ((start + dur) - NS.Now()) <= 0
end

--------------------------------------------------------------------
-- who am I
--------------------------------------------------------------------

-- the button is the rez/heal/drink button for a healer class (a druid: heal
-- and drink), and can be switched off
function Rez:Enabled()
    if cfg().rez == false then return false end
    return NS.HEALER_CLASSES[myClass() or ""] and true or false
end

-- the drink option for everyone who uses mana: below the threshold, out of
-- combat, with nothing to rez or heal, the button is a drink and blinks
function Rez:DrinkLow()
    if not cfg().rezDrinkLow then return false end
    if UnitPowerType and UnitPowerType("player") ~= 0 then return false end
    return true
end

-- is the button mine to click right now (rez/heal/drink), as opposed to the
-- "rez me first" ask a corpse gets?
function Rez:Active()
    if self:Enabled() then return true end
    if not self:DrinkLow() then return false end
    return not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
end

-- my rez spell's bare name, or nil (a druid, or a non-rezzer)
function Rez:SpellName()
    if not NS.Provides("REZ") then return nil end
    return NS.SpellNameFor("REZ")
end

-- every class's rez name, for matching other people's cast bars
function Rez:RezNames()
    if next(self.rezNames) then return self.rezNames end
    for _, rc in pairs(NS.REZ_CLASS) do
        local n = spellInfo(rc.id)
        if n then self.rezNames[n] = true end
        self.rezNames[rc.name] = true
    end
    return self.rezNames
end

-- UNIT_SPELLCAST_* hands a name on old clients and an id on new ones
function Rez:IsRezSpell(arg)
    if arg == nil then return true end
    local names = self:RezNames()
    if type(arg) == "string" then return names[arg] and true or false end
    if type(arg) == "number" then
        if NS.RezIdClass(arg) then return true end
        local n = spellInfo(arg)
        return (n and names[n]) and true or false
    end
    return false
end

function Rez:ForgetCache()
    self._book = nil
    self.rezNames = {}
    self._wipeStamp = nil
end

--------------------------------------------------------------------
-- claims: who is already rezzing whom (by name)
--------------------------------------------------------------------

function Rez:Claim(name, who, life, src)
    if not name or not who then return end
    name = NS.Short(name)
    local expires = NS.Now() + (life or self.CLAIM_LIFE)
    local ex = self.claims[name]
    if ex and ex.src == "comm" and ex.expires > expires then return end
    self.claims[name] = { expires = expires, who = NS.Short(who), src = src or "comm" }
end

function Rez:ClearClaim(name)
    if name then self.claims[NS.Short(name)] = nil end
end

-- who is on this corpse, or nil. Our own claim never blocks us.
function Rez:ClaimedBy(name)
    name = NS.Short(name)
    local c = name and self.claims[name]
    if not c then return nil end
    if NS.Now() > c.expires then self.claims[name] = nil return nil end
    if c.who == me() then return nil end
    return c.who, c.src
end

function Rez:IsCasting(who)
    who = NS.Short(who)
    for _, c in pairs(self.claims) do
        if c.who == who and NS.Now() <= c.expires then return true end
    end
    return false
end

function Rez:MarkRezzed(name)
    if name then self.recent[NS.Short(name)] = NS.Now() end
end

function Rez:RecentlyRezzed(name)
    local t = self.recent[NS.Short(name or "")]
    if not t then return false end
    if NS.Now() - t > self.REZ_GUARD then self.recent[NS.Short(name)] = nil return false end
    return true
end

-- passive: anyone in the group with a rez on their cast bar claims their
-- target. This sees rezzers who are NOT running the addon, which is most of
-- them, and it is where the "don't release" cue earns its keep.
function Rez:ScanCastBars()
    if not UnitCastingInfo then return end
    local names = self:RezNames()
    NS.ForEachMember(function(unit, name)
        if unit == "player" then return end
        local ok, spell, _, _, _, endMS = pcall(UnitCastingInfo, unit)
        if not ok or not spell or not names[spell] then return end
        local tgt = NS.Short(UnitName(unit .. "target") or "")
        if not tgt or tgt == "" then return end
        if tgt == me() then self:IncomingOnMe(name) end
        local life = self.CASTBAR_LIFE
        if type(endMS) == "number" and endMS > 0 then
            local left = (endMS / 1000) - NS.Now()
            if left > 0 then life = left + self.CASTBAR_SLOP end
        end
        self:Claim(tgt, name, life, "cast")
    end)
end

-- the one cue: a rez is on its way to YOUR corpse - do not release
function Rez:IncomingOnMe(who)
    if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then return end
    if (NS.Now() - (self._cueAt or 0)) < 10 then return end
    self._cueAt = NS.Now()
    NS.Sound:Play("rezIncoming")
    if cfg().chatAlert ~= false then
        NS.Print(T.text("good", NS.ClassColored(who or "somebody") .. " is rezzing you") ..
                 T.text("gold", " - don't release."))
    end
end

--------------------------------------------------------------------
-- peers: Tracker.providers.REZ is the rezzer roster (HELLO/STATE fill it)
--------------------------------------------------------------------

-- rezzers with the addon who are standing, ready first
function Rez:Rezzers()
    return NS.Tracker:Available("REZ")
end

function Rez:RezzersReady()
    local n = 0
    for _, r in ipairs(self:Rezzers()) do
        if r.cd <= 0 and not self:IsCasting(r.name) then n = n + 1 end
    end
    return n
end

-- any rezzer with the addon at all, up or down (the ask button cares about
-- whether asking can reach somebody)
function Rez:AnyRezzer()
    for name in pairs(NS.Tracker.providers.REZ or {}) do
        if name ~= me() or NS.Provides("REZ") then return true end
    end
    return false
end

--------------------------------------------------------------------
-- wipe protection
--------------------------------------------------------------------

function Rez:HasItem(itemId)
    local found = false
    forEachBagItem(function(_, _, id) if id == itemId then found = true return true end end)
    return found
end

function Rez:HasSoulstone()
    local found = false
    forEachBuff(function(name) if name == self.SOULSTONE_AURA then found = true return true end end)
    return found
end

-- what THIS player brings, as letters: "R", "D", "S", or a combination
function Rez:MyWipeProtection()
    local out = {}
    local w = self.WIPE[myClass() or ""]
    if w and self:KnowsSpell(w.name) and spellOffCooldown(w.name) then
        -- Reincarnation without an Ankh is not protection, it is a dead button
        if (not w.reagent) or self:HasItem(w.reagent) then out[#out + 1] = w.letter end
    end
    -- a stone only counts on somebody who can pick the raid back up
    if NS.Provides("REZ") and self:HasSoulstone() then out[#out + 1] = "S" end
    return table.concat(out)
end

-- everything the raid has: count, and who has what
function Rez:WipeProtection()
    local n, detail = 0, {}
    local function add(name, letters)
        for letter in string.gmatch(letters or "", "%a") do
            if self.WIPE_LABEL[letter] then
            n = n + 1
            detail[#detail + 1] = { name = name, what = self.WIPE_LABEL[letter] }
            end
        end
    end
    for name, d in pairs(NS.Tracker.providers.REZ or {}) do
        add(name, (name == me()) and self:MyWipeProtection() or d.wipe)
    end
    table.sort(detail, function(a, b)
        if a.what ~= b.what then return a.what < b.what end
        return a.name < b.name
    end)
    return n, detail
end

--------------------------------------------------------------------
-- target selection
--------------------------------------------------------------------

-- the corpse's unit, if the client can see one
local function unitOf(name) return NS.UnitOf(name) end

function Rez:IsRezzable(unit, name)
    if not unit or not UnitExists(unit) then return false, "doesn't exist" end
    if unit == "player" or name == me() then return false, "that's you" end
    if UnitIsPlayer and not UnitIsPlayer(unit) then return false, "not a player" end
    local dead = (UnitIsDead and UnitIsDead(unit)) or (UnitIsGhost and UnitIsGhost(unit))
    if UnitIsDead == nil and UnitIsGhost == nil then dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) end
    if not dead then return false, "alive" end
    if UnitIsConnected and not UnitIsConnected(unit) then return false, "offline" end
    if UnitIsVisible and not UnitIsVisible(unit) then return false, "not visible / different zone" end
    if UnitCanAttack and UnitCanAttack("player", unit) then return false, "hostile" end
    if self:RecentlyRezzed(name) then return false, "rez already incoming" end
    local who, src = self:ClaimedBy(name)
    if who then return false, ((src == "cast") and "being rezzed by " or "claimed by ") .. who end
    if spellInRange(self:SpellName(), unit) == 0 then return false, "out of range" end
    return true, "ok"
end

-- true when no rezzer still standing has the mana to cast: at that point a
-- mage's water outranks another body. Never concluded from no readings.
function Rez:RezzersAreDry()
    local anyWet, sawAny = false, false
    NS.ForEachMember(function(unit, _, class)
        if not NS.REZ_CLASS[class or ""] then return end
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return end
        local mx = UnitPowerMax and UnitPowerMax(unit, 0) or 0
        if not mx or mx <= 0 then return end
        sawAny = true
        if ((UnitPower(unit, 0) or 0) / mx) > self.DRY_PCT then anyWet = true end
    end)
    if not sawAny then return false end
    return not anyWet
end

-- a "rez me first" call from the corpse goes to the front of the line, like
-- an innervate call: the next rezzer to click takes them. Several askers go
-- in the order they asked.
function Rez:AskBonus(name)
    local c = NS.Calls:For(name, "REZ")
    if not c then return 0 end
    local before = 0
    for _, o in pairs(NS.Calls.list) do
        if o.state == "open" and o.kind == "REZ" and o.created < c.created then before = before + 1 end
    end
    return -100 + before * 0.01
end

-- what this corpse is worth to the recovery, lower first
function Rez:Score(unit, name, class)
    local score = self.PRIORITY[class or ""] or 99
    if class == "MAGE" and self:RezzersAreDry() then score = 0.5 end
    score = score + self:AskBonus(name)
    if UnitIsGhost and UnitIsGhost(unit) and not (UnitIsDead and UnitIsDead(unit)) then
        score = score + self.GHOST_PENALTY
    end
    return score
end

-- best corpse -> unit, name, class, score; plus the interesting rejections
function Rez:FindBestTarget()
    local bestUnit, bestName, bestClass, bestScore
    local rejects = {}
    NS.ForEachMember(function(unit, name, class)
        local ok, why = self:IsRezzable(unit, name)
        if ok then
            local s = self:Score(unit, name, class)
            if not bestScore or s < bestScore then bestUnit, bestName, bestClass, bestScore = unit, name, class, s end
        elseif why ~= "alive" and why ~= "that's you" and why ~= "not a player"
               and why ~= "doesn't exist" and why ~= "hostile" then
            rejects[#rejects + 1] = { name = name, why = why }
        end
    end)
    self.rejects = rejects
    return bestUnit, bestName, bestClass, bestScore
end

-- every corpse on the floor, in the order the button would take them
function Rez:Corpses()
    local out = {}
    NS.ForEachMember(function(unit, name, class)
        local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
        if dead and unit ~= "player" then
            local ok, why = self:IsRezzable(unit, name)
            out[#out + 1] = { unit = unit, name = name, class = class, ok = ok, why = why,
                              score = self:Score(unit, name, class) }
        end
    end)
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.name < b.name
    end)
    return out
end

--------------------------------------------------------------------
-- heals
--------------------------------------------------------------------

local function healingPower()
    if type(GetSpellBonusHealing) == "function" then
        local ok, v = pcall(GetSpellBonusHealing)
        return ok and tonumber(v) or 0
    end
    return 0
end
Rez.HealingPower = healingPower

-- 1.0 when nothing matches, so this can only ever improve the estimate
function Rez:TalentMultiplier()
    local want = self.HEAL_TALENTS[myClass() or ""]
    if not want then return 1 end
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentInfo) ~= "function" then return 1 end
    local mult = 1
    local okAll = pcall(function()
        for tab = 1, (GetNumTalentTabs() or 0) do
            for i = 1, (GetNumTalents(tab) or 0) do
                local name, _, _, _, rank = GetTalentInfo(tab, i)
                local per = name and want[name]
                if per and rank and rank > 0 then mult = mult + per * rank end
            end
        end
    end)
    if not okAll then return 1 end
    return mult
end

-- the level a rank was learned at, when the client will say (nil otherwise)
local function spellLevel(id)
    if not id or type(GetSpellLevelLearned) ~= "function" then return nil end
    local ok, lvl = pcall(GetSpellLevelLearned, id)
    lvl = ok and tonumber(lvl) or nil
    return (lvl and lvl > 0) and lvl or nil
end

-- the spellbook tooltip is BASE healing only. Chain Heal reads "681 to 775"
-- and lands for 2800. effective = (base + healing power x coefficient) x talents
-- Coefficient = cast time / 3.5 from the LIVE cast time (haste folds in), then
-- the two TBC penalties on a rank's level: learned under 20 loses 3.75% per
-- level under, and a rank more than 11 levels below you is scaled by
-- (level + 11) / your level. Without a level from the client neither applies;
-- measurement (below) corrects whatever is left.
function Rez:Coefficient(castSpell, level)
    local ct = castSeconds(castSpell)
    if ct <= 0 then ct = 1.5 end
    if ct > 3.5 then ct = 3.5 end
    local coef = ct / 3.5
    if level then
        if level < 20 then coef = coef * (1 - (20 - level) * 0.0375) end
        local mine = (UnitLevel and UnitLevel("player")) or 70
        if mine > 0 and level + 11 < mine then coef = coef * ((level + 11) / mine) end
    end
    return coef
end

function Rez:EffectiveHeal(base, castSpell, level)
    if not base or base <= 0 then return base or 0 end
    local sp = healingPower()
    if sp <= 0 then return base end
    return (base + sp * self:Coefficient(castSpell, level)) * self:TalentMultiplier()
end

local function parseHeal(text)
    if not text then return nil end
    local lo, hi = string.match(text, "(%d+) to (%d+)")
    if lo then return (tonumber(lo) + tonumber(hi)) / 2 end
    local n = string.match(text, "[Hh]eal[^%d]-(%d+)")
    if n then return tonumber(n) end
    return nil
end

function Rez:TooltipHeal(index)
    if C_TooltipInfo and C_TooltipInfo.GetSpellBookItem then
        local ok, data = pcall(C_TooltipInfo.GetSpellBookItem, index, PLAYER_BANK)
        if ok and type(data) == "table" then
            if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, data) end
            for _, line in ipairs(data.lines or {}) do
                if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
                local n = parseHeal(line.leftText)
                if n then return n end
            end
        end
    end
    if not self.scanTip and CreateFrame then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "BiSInnervateRezScanTip", nil, "GameTooltipTemplate")
        if ok then self.scanTip = tip end
    end
    local tip = self.scanTip
    if tip and tip.SetSpellBookItem then
        pcall(tip.SetOwner, tip, UIParent, "ANCHOR_NONE")
        pcall(tip.SetSpellBookItem, tip, index, PLAYER_BANK)
        for i = 1, (tip.NumLines and tip:NumLines()) or 0 do
            local fs = _G["BiSInnervateRezScanTipTextLeft" .. i]
            local n = fs and parseHeal(fs:GetText())
            if n then return n end
        end
    end
    return nil
end

-- one entry per rank the spellbook shows (all of them with "Show all ranks"
-- ticked, else just the top rank of each heal). The group heal's ranks are
-- their own list, so it downranks too.
function Rez:BuildHealTable()
    self.heals, self.groupHeals, self.groupHeal = {}, {}, nil
    local spec = self.CLASS_HEALS[myClass() or ""]
    if not spec then return end
    local wanted = {}
    for _, n in ipairs(spec.single) do wanted[n] = true end
    local limit = numSpells()
    for i = 1, limit do
        local name, rank = bookName(i)
        if not name then
            if limit >= 1000 then break end
        else
            local cast = (rank and rank ~= "") and (name .. "(" .. rank .. ")") or name
            local isGroup = spec.group and name == spec.group
            if wanted[name] or isGroup then
                local id = bookSpellId(i)
                local rankNo = tonumber(string.match(rank or "", "(%d+)")) or 0
                local level = spellLevel(id) or (self.RANK_LEVELS[name] or {})[rankNo]
                local e = { cast = cast, id = id, base = self:TooltipHeal(i) or 0, level = level, rankNo = rankNo }
                local list = isGroup and self.groupHeals or self.heals
                list[#list + 1] = e
            end
        end
    end
    self:SizeHeals()
end

-- sizes: the estimate, then the measured value where there is one, then
-- one calibration factor from the measured ranks applied to the rest
-- (BiS Healing's method). A lower rank never reads bigger than a higher one.
function Rez:SizeHeals()
    local sizes = cfg().rezHealSizes or {}
    -- one calibration factor across every rank of every heal
    local ratios = {}
    for _, list in ipairs({ self.heals, self.groupHeals }) do
        for _, e in ipairs(list) do
            e.est = self:EffectiveHeal(e.base, e.cast, e.level)
            local m = e.id and sizes[e.id]
            e.measured = (m and m.n and m.n > 0) and m.size or nil
            if e.measured and e.est > 0 then ratios[#ratios + 1] = e.measured / e.est end
        end
    end
    local cal = 1
    if #ratios > 0 then
        local sum = 0
        for _, r in ipairs(ratios) do sum = sum + r end
        cal = sum / #ratios
        if cal > 2 then cal = 2 elseif cal < 0.5 then cal = 0.5 end
    end
    self.calibration = cal
    local function size(list)
        for _, e in ipairs(list) do
            e.heal = e.measured or (e.est * cal)
            if e.measured and e.heal > e.est * 2 then e.heal = e.est * 2 end
        end
        -- monotonic in rank, per spell: rank 3 of a heal never above its rank 4
        local bySpell = {}
        for _, e in ipairs(list) do
            local n = bareName(e.cast)
            bySpell[n] = bySpell[n] or {}
            table.insert(bySpell[n], e)
        end
        for _, ranks in pairs(bySpell) do
            table.sort(ranks, function(a, b) return a.rankNo < b.rankNo end)
            for i = 2, #ranks do
                if ranks[i].heal < ranks[i - 1].heal then ranks[i].heal = ranks[i - 1].heal end
            end
        end
        table.sort(list, function(a, b) return a.heal < b.heal end)
    end
    size(self.heals)
    size(self.groupHeals)
    local g = self.groupHeals[#self.groupHeals]
    self.groupHeal = g and g.cast or nil
end

-- my own heal landing (the combat log): the truth about what a rank does.
-- Crits are thrown out, not divided by 1.5; casts that were mostly overheal
-- are thrown out (they say nothing about the size); a chain's bounces are
-- half and a quarter, so only the first heal of a cast counts.
function Rez:OnHeal(spellId, amount, overheal, crit)
    spellId = tonumber(spellId or "")
    amount, overheal = tonumber(amount) or 0, tonumber(overheal) or 0
    if not spellId or amount <= 0 or crit then return end
    local now = NS.Now()
    if self._lastHealId == spellId and (now - (self._lastHealAt or 0)) < 1.25 then return end   -- a bounce
    self._lastHealId, self._lastHealAt = spellId, now
    if overheal > amount * 0.5 then return end
    local known = false
    for _, list in ipairs({ self.heals, self.groupHeals }) do
        for _, e in ipairs(list) do if e.id == spellId then known = true end end
    end
    if not known then return end
    local db = cfg()
    db.rezHealSizes = db.rezHealSizes or {}
    local m = db.rezHealSizes[spellId] or { size = 0, n = 0 }
    -- a running average over the last handful of casts
    local n = math.min(m.n, 9)
    m.size = (m.size * n + amount) / (n + 1)
    m.n = m.n + 1
    db.rezHealSizes[spellId] = m
    self:SizeHeals()
    self.last = nil
end

-- the smallest group heal that covers the worst-off, else the biggest
function Rez:PickGroupHeal(unit, lead)
    if #self.groupHeals == 0 then return nil end
    local deficit = self:Deficit(unit, lead)
    if deficit <= 0 then return nil end
    for _, h in ipairs(self.groupHeals) do
        if h.heal >= deficit then return h end
    end
    return self.groupHeals[#self.groupHeals]
end

-- LibHealComm-4.0, when it is there (Libs/). Without it the picker sees
-- only the client's own UnitGetIncomingHeals, which sees every healer but
-- is not time-filtered.
function Rez:HealComm()
    if self._hc == nil then
        self._hc = (LibStub and LibStub("LibHealComm-4.0", true)) or false
    end
    return self._hc or nil
end

-- what OTHER healers already have landing on this unit before ours would.
-- The LARGER of the two sources, never the sum: both describe the same heal.
function Rez:OthersIncoming(unit, lead)
    if not unit then return 0 end
    local best = 0
    local hc = self:HealComm()
    if hc and hc.GetOthersHealAmount then
        local guid = UnitGUID and UnitGUID(unit)
        if guid then
            local when = NS.Now() + (lead or 0) + self.HEAL_REACTION
            local ok, v = pcall(hc.GetOthersHealAmount, hc, guid, hc.CASTED_HEALS, when)
            if ok then best = tonumber(v) or 0 end
        end
    end
    if type(UnitGetIncomingHeals) == "function" then
        local all  = UnitGetIncomingHeals(unit) or 0
        local mine = UnitGetIncomingHeals(unit, "player") or 0
        if (all - mine) > best then best = all - mine end
    end
    return best
end

function Rez:Deficit(unit, lead)
    if not UnitHealthMax then return 0 end
    local d = (UnitHealthMax(unit) or 0) - (UnitHealth(unit) or 0) - self:OthersIncoming(unit, lead)
    if d < 0 then d = 0 end
    return d
end

-- smallest heal that covers the deficit; the biggest if nothing does; nil
-- when somebody else already has them covered
function Rez:PickHeal(unit, lead)
    if #self.heals == 0 then return nil end
    local deficit = self:Deficit(unit, lead)
    if deficit <= 0 then return nil end
    for _, h in ipairs(self.heals) do
        if h.heal >= deficit then return h end
    end
    return self.heals[#self.heals]
end

-- worst-off living member in reach, and how many are hurt at all
function Rez:FindMostHurt(rangeSpell, lead)
    local worst, worstName, worstPct, injured = nil, nil, 1, 0
    if not UnitHealthMax then return nil, nil, 0 end
    NS.ForEachMember(function(unit, name)
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return end
        if UnitIsConnected and not UnitIsConnected(unit) then return end
        if UnitIsVisible and not UnitIsVisible(unit) then return end
        if rangeSpell and spellInRange(rangeSpell, unit) == 0 then return end
        local hpMax = UnitHealthMax(unit) or 0
        if hpMax <= 0 then return end
        local pct = (hpMax - self:Deficit(unit, lead)) / hpMax
        if pct < 0.95 then
            injured = injured + 1
            if pct < worstPct then worst, worstName, worstPct = unit, name, pct end
        end
    end)
    return worst, worstName, injured
end

--------------------------------------------------------------------
-- drink
--------------------------------------------------------------------

function Rez:IsDrinking()
    local yes = false
    forEachBuff(function(_, id) if id and self.DRINK_AURAS[id] then yes = true return true end end)
    return yes
end

-- best mana consumable in bags: bag, slot, itemId
function Rez:FindDrink()
    local bBag, bSlot, bRank, bId
    forEachBagItem(function(bag, slot, id)
        local r = self.CONSUMABLE_RANK[id]
        if r and (not bRank or r < bRank) then bBag, bSlot, bRank, bId = bag, slot, r, id end
    end)
    return bBag, bSlot, bId
end

function Rez:DrinkName(id)
    for _, c in ipairs(self.CONSUMABLES) do if c.id == id then return c.name end end
    return "mana consumable"
end

--------------------------------------------------------------------
-- the decision: what one click does right now
--------------------------------------------------------------------

-- The rez macro aims by NAME. A name the client cannot resolve leaves the
-- button unaimed: a button that does nothing is safe, one that rezzes
-- whoever inherited a raid slot is not.
local function nameToken(name, unit)
    if not name or not UnitExists then return nil end
    if UnitExists(name) and NS.Short(UnitName(name) or "") == name then return name end
    local n, realm = UnitName(unit or "")
    if n and realm and realm ~= "" then
        local full = n .. "-" .. realm
        if UnitExists(full) and NS.Short(UnitName(full) or "") == name then return full end
    end
    return nil
end

-- "nocombat" on every macro: the button is hidden in a fight, but a keybind
-- still fires a hidden button, and what it held was whatever was armed at
-- the pull - a max-rank Healing Wave meant for somebody else, landing on
-- the shaman for 2900 overheal. Now the click does nothing in combat, full
-- stop.
local function rezMacro(token, spell)
    return "/cast [target=" .. token .. ",nocombat] " .. spell
end

-- ONE target, no fallbacks. The old chain ([@mouseover][@target][@player])
-- was for combat, where the button no longer exists; out of combat it put a
-- max-rank Healing Wave meant for a tank 4000 down onto the shaman himself
-- the moment the aimed name failed (range, line of sight). A cast that
-- cannot reach its target should fail with a red line, not heal the wrong
-- person for 2900 overheal.
-- The RANK stays on: "Healing Wave(Rank 8)". BiS Rez stripped it here (a
-- caution copied from the rez path), so every pick cast the top rank and the
-- downranking was a fiction - three "rank 8" heals landing for 3880 each.
-- The macro parser takes the (Rank N) form; it is how BiS Healing downranks.
local function healMacro(token, spell)
    if not spell or not token then return "" end
    return "/cast [@" .. token .. ",help,nodead,nocombat] " .. spell
end

-- returns a decision table; never touches a frame
function Rez:Decide()
    local d = { action = nil, macro = "", rejects = {} }
    if not self:Active() then self.last = d return d end

    local spell = self:Enabled() and self:SpellName() or nil
    local canRez = spell ~= nil
    self:ScanCastBars()
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        -- a corpse casts nothing; the button waits for a rez of its own
        d.why = "you are dead"
        d.icon = NS.SpellIconFor("REZ")
        self.last = d
        return d
    end
    local unit, name, class
    if canRez then unit, name, class = self:FindBestTarget() end
    d.rejects = self.rejects or {}
    if not canRez then
        d.why = (myClass() == "DRUID") and "no out-of-combat rez - Rebirth is yours to spend" or "no rez spell"
    end

    local mana = (UnitPower and UnitPower("player", 0)) or 0
    local wantDrink = false
    if unit then
        d.target, d.targetClass, d.targetUnit = name, class, unit
        if mana >= spellCost(spell) then
            local token = nameToken(name, unit)
            if token then
                d.action, d.macro = "rez", rezMacro(token, spell)
            else
                d.why = "cannot target " .. name .. " by name - rez by hand"
            end
        else
            d.why = "not enough mana"
            wantDrink = true
        end
    elseif self:Enabled() and cfg().rezHeal ~= false and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        local biggest = self.heals[#self.heals]
        local probe = (biggest and biggest.cast) or self.groupHeal
        local lead = castSeconds(probe)
        local hurt, hurtName, injured = self:FindMostHurt(probe, lead)
        if hurt then
            local healSpell, cost
            -- the group heal when the class has one and 2+ are hurt, else
            -- single target - a paladin never has one, a druid's is Tranquility
            if injured > 1 and #self.groupHeals > 0 then
                local pick = self:PickGroupHeal(hurt, lead)
                if pick then healSpell, cost = pick.cast, spellCost(pick.id or pick.cast) end
            else
                local pick = self:PickHeal(hurt, lead)
                if pick then healSpell, cost = pick.cast, spellCost(pick.id or pick.cast) end
            end
            local token = healSpell and nameToken(hurtName, hurt)
            if healSpell and not token then
                d.why = "cannot target " .. tostring(hurtName) .. " by name"
            elseif healSpell and mana >= cost then
                d.action, d.healSpell, d.target, d.targetUnit = "heal", healSpell, hurtName, hurt
                local _, hc = UnitClass(hurt)
                d.targetClass = hc
                d.macro = healMacro(token, healSpell)
            elseif healSpell then
                wantDrink = true
            end
        end
    end

    -- the drink option: nothing to rez or heal and the bar is low
    if not d.action and not wantDrink and self:DrinkLow() then
        local pct = NS.ManaPct("player")
        if pct and pct < (cfg().rezDrinkAt or 75) then
            wantDrink = true
            d.lowMana = true
            d.why = "mana " .. pct .. "%"
        end
    end
    if not d.action and wantDrink and (cfg().rezDrink ~= false or d.lowMana) and not self:IsDrinking() then
        local bag, slot, id = self:FindDrink()
        if bag then
            d.action, d.drinkId = "drink", id
            d.macro = ("/use [nocombat] %d %d"):format(bag, slot)
            d.why = (d.target and "not enough mana - drinking") or nil
        else
            d.why = (d.why or "not enough mana") .. ", nothing to drink"
        end
    end

    -- the icon: what the click will do
    if d.action == "heal" then d.icon = spellIcon(d.healSpell)
    elseif d.action == "drink" then d.icon = itemIcon(d.drinkId) end
    d.icon = d.icon or NS.SpellIconFor("REZ")

    self.last = d
    return d
end

-- has the decision changed in a way the button must follow?
local function differs(a, b)
    if not a or not b then return true end
    return a.macro ~= b.macro or a.action ~= b.action or a.target ~= b.target or a.icon ~= b.icon
end

-- should the button be on screen at all (out of combat)? A healer's: only
-- while there is something to do. Everyone else's: only while dead. The
-- rest of the time it is not there to be misclicked.
function Rez:Visible(d)
    if NS.db and NS.db.magesOnly then return false end
    if self:Active() then
        d = d or self.last or self:Decide()
        return d.action ~= nil
    end
    return (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) and true or false
end

-- Show / hide, and the combat rule. Registering a state driver is protected,
-- so this runs from Bind and RebindRez only (out of combat). The secure
-- environment evaluates "[combat] hide" itself, so the button vanishes for
-- the fight without this addon touching anything protected.
function Rez:ApplyVisibility(btn, d)
    if not btn or NS.InCombat() then return end
    local on = self:Visible(d)
    if type(RegisterStateDriver) == "function" then
        if type(UnregisterStateDriver) == "function" then pcall(UnregisterStateDriver, btn, "visibility") end
        pcall(RegisterStateDriver, btn, "visibility", on and "[combat] hide; show" or "hide")
    end
    if on then btn:Show() else btn:Hide() end
    self.shown = on
end

--------------------------------------------------------------------
-- the button (Window owns the frame; this writes its attributes)
--------------------------------------------------------------------

-- out of combat only: Window:Bind and Window:RebindRez are the callers
function Rez:Bind(btn)
    if not btn or NS.InCombat() then return false end
    local d = self:Decide()
    self:ApplyVisibility(btn, d)
    if not self:Active() then
        btn:SetAttribute("*type1", nil); btn:SetAttribute("*macrotext1", nil)
        btn:SetAttribute("*spell1", nil); btn:SetAttribute("*item1", nil)
        btn:SetAttribute("unit", "none")
        self.bound = nil
        return true
    end
    if btn:GetAttribute("*macrotext1") ~= d.macro or btn:GetAttribute("*type1") ~= "macro" then
        btn:SetAttribute("*type1", "macro"); btn:SetAttribute("*macrotext1", d.macro)
        btn:SetAttribute("*spell1", nil); btn:SetAttribute("*item1", nil)
        btn:SetAttribute("unit", nil)
    end
    self.bound = d
    return true
end

-- the half-second tick: claims expire, the decision follows the raid, and
-- the button is re-aimed out of combat (deferred to the fight's end otherwise)
function Rez:Tick()
    if not NS.Window or not NS.Window.frame then return end
    if not self:Active() then
        self:ScanCastBars()          -- the "don't release" cue is for everyone
        -- the ask button appears when you die and goes when you stand up
        if self.shown ~= nil and self.shown ~= self:Visible() then
            if NS.InCombat() then NS.Window.rezPending = true else NS.Window:RebindRez() end
        end
        return
    end
    local before = self.last
    local d = self:Decide()
    if differs(before, d) or differs(self.bound, d) or (self.shown ~= nil and self.shown ~= self:Visible(d)) then
        if NS.InCombat() then
            NS.Window.rezPending = true
        else
            NS.Window:RebindRez()
        end
        NS.Window:Refresh()
    end
end

-- the click went out from the secure button: remember whom we aimed at.
-- The claim attaches when the cast STARTS (UNIT_SPELLCAST_START), not here.
function Rez:OnClick()
    local d = self.bound or self.last
    if not d or not self:Active() then return end
    self.clickAt = NS.Now()
    if d.action == "rez" then
        self.pending = { name = d.target, at = NS.Now() }
        self.report = { name = d.target, at = NS.Now(), silent = false }
    elseif d.action == "heal" or d.action == "drink" then
        self.pending = nil
        self.report = { name = d.target, at = NS.Now(), silent = true }
    else
        NS.Print("nothing to do.")
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        self:Report("you're dead", "warn")
    elseif NS.InCombat() and d.action == "rez" then
        self:Report("in combat", "warn")
    end
end

-- one line per click, spent by whichever of success / error arrives first
function Rez:Report(text, colour)
    local r = self.report
    if not r then return end
    self.report = nil
    if (NS.Now() - (r.at or 0)) > 3 then return end
    NS.Print(T.text(colour or "ink2", text))
end

--------------------------------------------------------------------
-- events (Init routes these here)
--------------------------------------------------------------------

function Rez:OnCastStart(unit, spell)
    if unit ~= "player" or not self.pending then return end
    if not self:IsRezSpell(spell) then return end
    local name = self.pending.name
    self:Claim(name, me(), self.CLAIM_LIFE, "comm")
    NS.Comm:Send("RCLAIM", name)
    if NS.Window then NS.Window:Refresh() end
end

function Rez:OnCastStop(unit, spell)
    if unit ~= "player" or not self.pending or not self:IsRezSpell(spell) then return end
    self.pending = nil
end

function Rez:OnCastInterrupted(unit, spell)
    if unit ~= "player" or not self:IsRezSpell(spell) then return end
    local name = (self.pending and self.pending.name) or (self.last and self.last.action == "rez" and self.last.target)
    if name then self:ClearClaim(name); NS.Comm:Send("RFREE", name) end
    self.pending = nil
end

function Rez:OnCastFailed(unit, spell)
    if unit ~= "player" or not self:IsRezSpell(spell) then return end
    local name = (self.pending and self.pending.name) or (self.last and self.last.action == "rez" and self.last.target)
    if name then self:ClearClaim(name); NS.Comm:Send("RFREE", name) end
    self.pending = nil
    if (NS.Now() - (self.clickAt or 0)) < 1.5 then
        self:Report((name or "target") .. ": cast failed", "warn")
    end
end

-- our own cast landed (UNIT_SPELLCAST_SUCCEEDED for "player")
function Rez:OnCastSucceeded(unit, spell)
    if unit ~= "player" then return end
    if self:IsRezSpell(spell) then
        local name = (self.pending and self.pending.name) or (self.last and self.last.target)
        if name then
            self:MarkRezzed(name)
            NS.Comm:Send("RDONE", name)
            self:Report("rezzed " .. name, "good")
        end
        self.pending = nil
    elseif self.report and self.report.silent then
        self.report = nil            -- our heal or drink went through: say nothing
    end
end

-- the combat log: SPELL_CAST_SUCCESS of any rez (Tracker routes it) and
-- SPELL_RESURRECT (the score)
function Rez:OnRezCast(caster, target)
    if target then
        self:MarkRezzed(target)
        local c = NS.Calls:For(target, "REZ")
        if c then NS.Calls:Cancel(c, "rezzed") end
    end
    if NS.Window then NS.Window:Refresh() end
end

function Rez:OnResurrect(caster, target, spellName)
    if target then self:MarkRezzed(target) end
    if caster and ((not spellName) or self:RezNames()[spellName]) then
        local db = cfg()
        db.rezScores = db.rezScores or {}
        local n = NS.Short(caster)
        db.rezScores[n] = (db.rezScores[n] or 0) + 1
    end
end

-- a red error right after our click: the cast never began, free the corpse
function Rez:OnUIError(msg)
    if type(msg) ~= "string" then return end
    if (NS.Now() - (self.clickAt or 0)) > 1.5 then return end
    if not self:IsCastError(msg) then return end
    if self.pending then
        self:ClearClaim(self.pending.name)
        NS.Comm:Send("RFREE", self.pending.name)
        self.pending = nil
    end
    self:Report(((self.report and self.report.name) or "target") .. ": " .. msg, "warn")
end

function Rez:IsCastError(msg)
    if not self.errors then
        self.errors = {}
        for _, g in ipairs(CAST_ERROR_GLOBALS) do
            local v = _G[g]
            if type(v) == "string" and v ~= "" then self.errors[v] = true end
        end
    end
    if not next(self.errors) then return true end      -- no strings on this build: report everything
    if self.errors[msg] then return true end
    for pattern in pairs(self.errors) do
        local stem = string.match(pattern, "^([^%%]+)")
        if stem and #stem >= 8 and string.sub(msg, 1, #stem) == stem then return true end
    end
    return false
end

-- the spellbook changed, or gear: sizes move with +healing
function Rez:OnSpellsChanged()
    self:ForgetCache()
    self:BuildHealTable()
    self.last = nil
end

-- leaving one group for another: the scoreboard is per raid
function Rez:OnNewGroup()
    if cfg().rezKeepScores then return end
    local db = cfg()
    if db.rezScores and next(db.rezScores) then
        db.rezScores = {}
        NS.Print("new group - rez scoreboard cleared.")
    end
end

--------------------------------------------------------------------
-- scoreboard
--------------------------------------------------------------------

function Rez:Champions()
    local leaders, best = {}, nil
    for name, count in pairs(cfg().rezScores or {}) do
        if not best or count > best then best, leaders = count, { name }
        elseif count == best then leaders[#leaders + 1] = name end
    end
    table.sort(leaders)
    return leaders, best
end

function Rez:ChampionText(maxNames)
    local leaders, best = self:Champions()
    if #leaders == 0 then return nil end
    if #leaders <= (maxNames or 2) then return table.concat(leaders, " & ") .. " " .. best end
    return #leaders .. "-way tie " .. best
end

--------------------------------------------------------------------
-- keybinding: an override binding on top of the user's keybinds, so
-- uninstalling can never leave a dead "CLICK ..." in their bindings file.
-- Overrides clear on /reload, so the key is stored and re-applied at login.
--------------------------------------------------------------------

function Rez:ApplyBind(key)
    local btn = NS.Window and NS.Window.buttons and NS.Window.buttons.REZ
    if not key or key == "" or not btn then return false end
    if NS.InCombat() then return false end
    if type(SetOverrideBindingClick) ~= "function" then return false end
    local ok = pcall(SetOverrideBindingClick, btn, true, key, btn:GetName(), "LeftButton")
    return ok and true or false
end

function Rez:ClearBind()
    local btn = NS.Window and NS.Window.buttons and NS.Window.buttons.REZ
    if btn and type(ClearOverrideBindings) == "function" then pcall(ClearOverrideBindings, btn) end
end

--------------------------------------------------------------------
-- the tooltip on the button, and text for the window
--------------------------------------------------------------------

function Rez:Tooltip(tip)
    local d = self.last or self:Decide()
    if d.action == "rez" then
        tip:AddLine("Click: rez " .. NS.ClassColored(d.target, d.targetClass), 0.31, 0.82, 0.81)
    elseif d.action == "heal" then
        tip:AddLine(("Click: %s on %s"):format(bareName(d.healSpell), NS.ClassColored(d.target, d.targetClass)), 0.9, 0.75, 0.29)
    elseif d.action == "drink" then
        tip:AddLine("Click: drink " .. self:DrinkName(d.drinkId), 0.56, 0.71, 0.84)
    else
        tip:AddLine("Click: nothing to do", 0.59, 0.56, 0.68)
    end
    if d.target and d.action ~= "rez" and d.why then
        tip:AddLine("Rez target: " .. d.target .. " - " .. d.why, 0.94, 0.55, 0.69)
    elseif not d.target and d.why then
        tip:AddLine("No rez target - " .. d.why, 0.94, 0.55, 0.69)
    end
    if d.rejects and #d.rejects > 0 then
        tip:AddLine("Skipped:", 0.59, 0.56, 0.68)
        for i = 1, math.min(#d.rejects, 5) do
            tip:AddLine("  " .. d.rejects[i].name .. " - " .. d.rejects[i].why, 0.56, 0.53, 0.65)
        end
        if #d.rejects > 5 then tip:AddLine("  ...and " .. (#d.rejects - 5) .. " more", 0.59, 0.56, 0.68) end
    end
    local list = self:Rezzers()
    tip:AddLine(("%d rezzer(s) with the addon standing, %d ready"):format(#list, self:RezzersReady()), 1, 1, 1)
    local n, detail = self:WipeProtection()
    if n > 0 then
        tip:AddLine(("Wipe protection: %d"):format(n), 0.31, 0.82, 0.81)
        for i = 1, math.min(#detail, 6) do tip:AddLine("  " .. detail[i].name .. " - " .. detail[i].what, 0.7, 0.7, 0.7) end
    else
        tip:AddLine("No wipe protection up - a wipe is a corpse run", 0.94, 0.55, 0.69)
    end
    local ctext = self:ChampionText(3)
    if ctext then tip:AddLine("Rez champion: " .. ctext, 0.9, 0.75, 0.29) end
end

-- the short text that feeds the button's hidden sub string (and the tests)
function Rez:Summary(d)
    d = d or self.last
    if not d then return "" end
    if d.action == "rez" then return "rez " .. tostring(d.target) end
    if d.action == "heal" then return bareName(d.healSpell) .. " on " .. tostring(d.target) end
    if d.action == "drink" then return d.lowMana and ("drink - " .. (d.why or "low mana")) or "drink" end
    return d.why or "nothing to do"
end

--------------------------------------------------------------------
-- incoming
--------------------------------------------------------------------

local Comm = NS.Comm

Comm:Register("RCLAIM", function(sender, name)
    if not name or name == "" then return end
    Rez:Claim(name, sender, Rez.CLAIM_LIFE, "comm")
    if NS.Short(name) == me() then Rez:IncomingOnMe(sender) end
    -- the moment somebody starts a cast, everyone else's button moves on
    Rez:Tick()
    if NS.Window then NS.Window:Refresh() end
end)

Comm:Register("RDONE", function(sender, name)
    if not name or name == "" then return end
    Rez:MarkRezzed(name)
    Rez:Claim(name, sender, Rez.REZ_GUARD, "comm")
    Rez:Tick()
    if NS.Window then NS.Window:Refresh() end
end)

Comm:Register("RFREE", function(sender, name)
    if not name or name == "" then return end
    local c = Rez.claims[NS.Short(name)]
    if c and c.who ~= NS.Short(sender) then return end     -- only your own claim
    Rez:ClearClaim(name)
    Rez:Tick()
    if NS.Window then NS.Window:Refresh() end
end)
