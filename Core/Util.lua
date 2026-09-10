-- BiS Innervate :: Util.lua
-- Constants, small helpers, API shims. No frames, no events.

local ADDON, NS = ...

NS.ADDON       = ADDON or "BiSInnervate"
-- the version the raid hears (HELLO|ver, the shared channel's RegisterAddon)
-- is the TOC's; the literal is only for a client that cannot read metadata
-- and dev/tests.lua holds it equal to the TOC
NS.VERSION     = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
                 or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "3.3.6"
NS.PROTOCOL    = 4      -- do NOT bump: other BiS addons (BiSGamba's RezComm) emit
                        -- RCLAIM/RDONE/RFREE on this number; a bump silences every one
NS.PREFIX      = "BiSInn"

--------------------------------------------------------------------
-- palette
--
-- BiSTheme when it is installed, and the same values inline when it is not:
-- this addon must never need a second addon to draw itself. Every file that
-- paints anything reads `NS.T`, so there is one palette, not eight opinions.
--------------------------------------------------------------------

local HEX = {
    bg = "121020", surface = "1a1730", sunken = "221d3c",
    line = "2a2446", line2 = "3a3260",
    ink = "ece8f6", ink2 = "c6bedd", muted = "968ead", dim = "8e86a6",
    accent = "b980ff", accentSoft = "2c2148",
    good = "4fd0cf", warn = "f08cb0", gold = "e5c04a", slate = "8fb4d6",
    epic = "c08cff", rare = "5fa8f0", uncommon = "5fd06f",
}

local Fallback = { hex = HEX }

function Fallback.rgb(name)
    local hex = HEX[name] or name or "ffffff"
    local r = tonumber(string.sub(hex, 1, 2), 16)
    local g = tonumber(string.sub(hex, 3, 4), 16)
    local b = tonumber(string.sub(hex, 5, 6), 16)
    if not r or not g or not b then
        NS.Debug("unknown colour", tostring(name))
        return 1, 1, 1
    end
    return r / 255, g / 255, b / 255
end

function Fallback.rgba(name, a)
    local r, g, b = Fallback.rgb(name)
    return r, g, b, a or 1
end

function Fallback.text(name, str)
    return "|cff" .. (HEX[name] or name or "ffffff") .. tostring(str or "") .. "|r"
end

-- The real theme addon may load after us, so it is looked up at call time.
-- Per NAME, not per function: a colour BiSTheme does not know falls back to
-- the inline table instead of returning nil into SetColorTexture.
NS.T = {}
function NS.T.rgb(name)
    local real = _G.BiSTheme
    if real and real.hex and real.hex[name] and real.rgb then return real.rgb(name) end
    return Fallback.rgb(name)
end
function NS.T.rgba(name, a)
    local r, g, b = NS.T.rgb(name)
    return r, g, b, a or 1
end
function NS.T.text(name, str)
    local real = _G.BiSTheme
    if real and real.hex and real.hex[name] and real.text then return real.text(name, str) end
    return Fallback.text(name, str)
end
NS.T.hex = HEX
-- the BiS> header prompt (Libs\BiSTheme\Console.lua, embedded; the BiSTheme
-- addon's copy wins when it is newer). nil only if the file never loaded.
function NS.T.Console(fs, opts)
    local real = _G.BiSTheme
    if real and real.Console then return real.Console(fs, opts) end
    return nil
end
-- the shared options window (Libs\BiSTheme\Options.lua, embedded the same way)
function NS.T.Options(name, w, title)
    local real = _G.BiSTheme
    if real and real.Options then return real.Options(name, w, title) end
    return nil
end

-- The two things a raider can hand out.
--   INNERVATE: druid, single target, 6 min.
--   TIDE:      resto shaman, totem, helps their own raid subgroup only, 5 min.
-- Four things a raid asks for. Innervate is aimed at a person (the faces).
-- Tide and Drums land on the caster's own subgroup, so the ask goes to whoever
-- in YOUR group has it. Bloodlust is raid-wide: every shaman with the addon
-- sees it and the first to click answers it. For all three the button is the
-- provider's own cast button.
NS.PROVIDERS = {
    INNERVATE = {
        kind = "INNERVATE", class = "DRUID", scope = "target",
        ids = { 29166 }, cd = 360, name = "Innervate", short = "innervate",
        icon = "Interface\\Icons\\Spell_Nature_Lightning",
    },
    TIDE = {
        kind = "TIDE", class = "SHAMAN", scope = "group",
        ids = { 16190, 17354, 17359 }, cd = 300, name = "Mana Tide Totem", short = "mana tide",
        icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
    },
    LUST = {
        -- raid-wide: any shaman with the addon sees the call and may answer it
        kind = "LUST", class = "SHAMAN", scope = "raid",
        ids = { 2825, 32182 }, cd = 600, name = "Bloodlust", short = "bloodlust",
        icon = "Interface\\Icons\\Spell_Nature_BloodLust",
    },
    DRUMS = {
        kind = "DRUMS", class = nil, scope = "group", item = true,
        -- Battle, War, Restoration, Speed, Panic: the item ids and the spell
        -- each one casts (the combat log shows the spell)
        items = { 29529, 29528, 29531, 29530, 29532 },
        ids   = { 35476, 35475, 35478, 35477, 35474 },
        cd = 120, name = "Drums", short = "drums",
        icon = "Interface\\Icons\\INV_Misc_Drum_02",
    },
    REZ = {
        -- "self": not an ask/claim kind and no group filter. The button is the
        -- rezzer's own: it rezzes the best corpse, else heals, else drinks
        -- (Core/Rez.lua decides). Everyone else's button is "rez me first".
        -- Rebirth is deliberately NOT here: an hour of cooldown and the raid's
        -- only combat rez. A druid gets heal and drink; their rez stays theirs.
        kind = "REZ", class = nil, scope = "self", cd = 0,
        ids = { 2006, 2010, 10880, 10881, 20770, 25435,      -- Resurrection
                7328, 10322, 10324, 20772, 20773,            -- Redemption
                2008, 20609, 20610, 20776, 20777, 25590 },   -- Ancestral Spirit
        name = "Resurrection", short = "rez",
        icon = "Interface\\Icons\\Spell_Holy_Resurrection",
    },
}
NS.KINDS = { "INNERVATE", "TIDE", "LUST", "DRUMS", "REZ" }

-- the out-of-combat rez per class: base-rank id (for the name lookup), the
-- English name as a fallback, and the icon
NS.REZ_CLASS = {
    PRIEST  = { id = 2006, name = "Resurrection",     icon = "Interface\\Icons\\Spell_Holy_Resurrection" },
    PALADIN = { id = 7328, name = "Redemption",       icon = "Interface\\Icons\\Spell_Holy_Resurrection" },
    SHAMAN  = { id = 2008, name = "Ancestral Spirit", icon = "Interface\\Icons\\Spell_Nature_Regenerate" },
}
-- who gets the rez/heal/drink button at all (a druid: heal and drink only)
NS.HEALER_CLASSES = { PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true }

-- the talent trees that heal, for the classes that can go either way. A
-- shadow priest, a ret paladin, an enhance shaman: no face on the grid.
NS.HEAL_TABS = { PRIEST = { [1] = true, [2] = true }, PALADIN = { [1] = true }, SHAMAN = { [3] = true } }

-- true: a healing tree is the biggest. false: a dps tree is. nil: not a class
-- this applies to, or nothing to read (no points yet, no talent API)
function NS.MyHealerSpec()
    local _, class = UnitClass("player")
    local heal = NS.HEAL_TABS[class or ""]
    if not heal or type(GetTalentTabInfo) ~= "function" then return nil end
    local best, bestHeal, total = 0, nil, 0
    for tab = 1, 3 do
        local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tab)
        if not ok or a == nil then break end
        -- classic: name, icon, POINTS, file.  retail-shaped: id, name, desc, icon, POINTS
        local pts = (type(c) == "number") and c or ((type(e) == "number") and e) or 0
        total = total + pts
        if pts > best then best, bestHeal = pts, (heal[tab] and true or false) end
    end
    if total == 0 then return nil end
    return bestHeal
end

-- who may ask for an innervate (default: mages + healer classes)
NS.REQUESTER_CLASSES = {
    MAGE    = true,
    PRIEST  = true,
    PALADIN = true,
    SHAMAN  = true,
    DRUID   = true,   -- a resto druid asking another druid is legit
    WARLOCK = false,
    HUNTER  = false,
}

--------------------------------------------------------------------
-- tiny helpers
--------------------------------------------------------------------

local function nowFn()
    if GetTime then return GetTime() end
    return 0
end
NS.Now = nowFn

function NS.Round(v) return math.floor((v or 0) + 0.5) end

function NS.Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- "Name-Realm" -> "Name" (we key everything on the short name)
function NS.Short(name)
    if not name then return nil end
    local n = string.match(name, "^([^%-]+)")
    return n or name
end

function NS.TimeStr(sec)
    sec = math.max(0, math.floor(sec or 0))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--------------------------------------------------------------------
-- print
--------------------------------------------------------------------

local TAG = "|cff33ff99BiS Innervate|r: "

function NS.Print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local msg = TAG .. table.concat(parts, " ")
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
end

function NS.Debug(...)
    if NS.db and NS.db.debug then NS.Print("|cff888888[dbg]|r", ...) end
end

--------------------------------------------------------------------
-- API shims (Anniversary client runs the modern engine: C_Spell / C_Container)
--------------------------------------------------------------------

function NS.Provider(kind) return NS.PROVIDERS[kind or ""] end

-- which of a provider's spell ids this player actually knows (nil = none)
-- The five drum types. Greater and normal are the same type here: the raid
-- asks for "battle", whoever has either answers. Priority is the order.
NS.DRUM_TYPES = { "BATTLE", "WAR", "RESTORATION", "SPEED", "PANIC" }
NS.DRUM = {
    BATTLE      = { letter = "B", name = "Drums of Battle",      icon = "Interface\\Icons\\INV_Misc_Drum_02" },
    WAR         = { letter = "W", name = "Drums of War",         icon = "Interface\\Icons\\INV_Misc_Drum_03" },
    RESTORATION = { letter = "R", name = "Drums of Restoration", icon = "Interface\\Icons\\INV_Misc_Drum_07" },
    SPEED       = { letter = "S", name = "Drums of Speed",       icon = "Interface\\Icons\\INV_Misc_Drum_06" },
    PANIC       = { letter = "P", name = "Drums of Panic",       icon = "Interface\\Icons\\INV_Misc_Drum_04" },
}
NS.DRUM_LETTER = {}
for t, d in pairs(NS.DRUM) do NS.DRUM_LETTER[d.letter] = t end

-- "Greater Drums of Battle" / "Drums of Battle" -> "BATTLE"
function NS.DrumTypeOfName(name)
    if not name then return nil end
    local t = string.match(name, "Drums of (%a+)")
    if not t then return nil end
    t = string.upper(t)
    return NS.DRUM[t] and t or nil
end

-- what this player carries: type -> item id (Greater preferred when both).
-- Found by NAME in the bags, so Greater drums count without knowing their ids.
function NS.MyDrums()
    if NS._myDrums then return NS._myDrums end
    local out = {}
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local linkAt   = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    if numSlots and linkAt then
        for bag = 0, 4 do
            local okN, n = pcall(numSlots, bag)
            for slot = 1, (okN and tonumber(n)) or 0 do
                local okL, link = pcall(linkAt, bag, slot)
                if okL and type(link) == "string" then
                    local t = NS.DrumTypeOfName(link)
                    if t then
                        local id = tonumber(string.match(link, "item:(%d+)"))
                        local greater = string.find(link, "Greater", 1, true) ~= nil
                        if id and (not out[t] or greater) then out[t] = id end
                    end
                end
            end
        end
    end
    -- the classic ids as a fallback for a client without container links
    if not next(out) and GetItemCount then
        local p = NS.PROVIDERS.DRUMS
        for i, itemId in ipairs(p.items) do
            local ok, cnt = pcall(GetItemCount, itemId)
            if ok and (tonumber(cnt) or 0) > 0 then out[NS.DRUM_TYPES[i]] = itemId end
        end
    end
    NS._myDrums = out
    return out
end

-- the drum to bind the button to: the asked-for type if carried, else the best
function NS.MyDrum(variant)
    local mine = NS.MyDrums()
    if variant and mine[variant] then return mine[variant], variant end
    for _, t in ipairs(NS.DRUM_TYPES) do
        if mine[t] then return mine[t], t end
    end
    return nil
end

-- "BWR": the types I carry, for the wire
function NS.MyDrumLetters()
    local out = {}
    local mine = NS.MyDrums()
    for _, t in ipairs(NS.DRUM_TYPES) do if mine[t] then out[#out + 1] = NS.DRUM[t].letter end end
    return table.concat(out)
end

-- which class a rez spell id belongs to (the id list is three classes' ranks)
local REZ_ID_CLASS = {}
for _, id in ipairs({ 2006, 2010, 10880, 10881, 20770, 25435 }) do REZ_ID_CLASS[id] = "PRIEST" end
for _, id in ipairs({ 7328, 10322, 10324, 20772, 20773 }) do REZ_ID_CLASS[id] = "PALADIN" end
for _, id in ipairs({ 2008, 20609, 20610, 20776, 20777, 25590 }) do REZ_ID_CLASS[id] = "SHAMAN" end
function NS.RezIdClass(id) return REZ_ID_CLASS[tonumber(id or "") or 0] end

function NS.KnownSpellId(kind)
    local p = NS.Provider(kind)
    if not p then return nil end
    if p.item then
        return NS.MyDrum() and p.ids[1] or nil     -- any drum at all: a token id
    end
    local _, class = UnitClass("player")
    if p.class and class ~= p.class then return nil end
    if kind == "REZ" then
        -- baseline for the three classes; the highest rank the client admits
        -- to, else the base rank (the cast goes out by bare name anyway)
        local rc = NS.REZ_CLASS[class or ""]
        if not rc then return nil end
        if IsPlayerSpell then
            local best
            for _, id in ipairs(p.ids) do
                local ok, known = pcall(IsPlayerSpell, id)
                if ok and known and NS.RezIdClass(id) == class then best = id end
            end
            if best then return best end
        end
        return rc.id
    end
    if IsPlayerSpell then
        for _, id in ipairs(p.ids) do
            local ok, known = pcall(IsPlayerSpell, id)
            if ok and known then return id end
        end
        -- talent not taken (mana tide) or API lied: innervate and bloodlust are
        -- baseline for their class
        if kind == "INNERVATE" or kind == "LUST" then return p.ids[1] end
        return nil
    end
    return p.ids[1]
end

local function spellNameOf(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if type(info) == "table" then return info.name elseif type(info) == "string" then return info end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok and type(n) == "string" then return n end
    end
end

function NS.SpellNameFor(kind)
    NS._names = NS._names or {}
    if NS._names[kind] then return NS._names[kind] end
    local p = NS.Provider(kind)
    if not p then return nil end
    local looked = spellNameOf(NS.KnownSpellId(kind) or p.ids[1])
    -- only cache a real answer from the client; the English literal is a
    -- placeholder we must be willing to replace once the spell data is warm
    if looked then NS._names[kind] = looked end
    if not looked and kind == "REZ" then
        local _, class = UnitClass("player")
        local rc = NS.REZ_CLASS[class or ""]
        return rc and rc.name or p.name
    end
    return looked or p.name
end

-- called when talents or the spellbook change, and on leaving combat
function NS.ForgetSpellCache()
    NS._myKinds = nil
    NS._myDrums = nil
    NS._names  = {}
    NS._myKind = nil
end

-- remaining cooldown in seconds for one of MY provider spells (0 = ready)
function NS.SpellCooldownFor(kind)
    local p = NS.Provider(kind)
    if p and p.item then
        -- drums share one cooldown and it lives on the item
        local itemId = NS.MyDrum()
        if not itemId or not GetItemCooldown then return 0 end
        local ok, start, dur = pcall(GetItemCooldown, itemId)
        if not ok or not start or start == 0 or not dur or dur <= 1.5 then return 0 end
        local left = (start + dur) - NS.Now()
        return left < 0 and 0 or left
    end
    local id = NS.KnownSpellId(kind)
    if not id then return 0 end
    local start, dur = 0, 0
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(id)
        if type(cd) == "table" then start, dur = cd.startTime or 0, cd.duration or 0 end
    elseif GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, id)
        if ok then start, dur = s or 0, d or 0 end
    end
    if not start or start == 0 or not dur or dur <= 1.5 then return 0 end
    local left = (start + dur) - NS.Now()
    if left < 0 then left = 0 end
    return left
end

function NS.SpellIconFor(kind)
    local p = NS.Provider(kind)
    if p and p.item then return p.icon end
    local id = NS.KnownSpellId(kind) or (p or {}).ids[1]
    if kind == "REZ" then
        local _, class = UnitClass("player")
        local rc = NS.REZ_CLASS[class or ""]
        if not rc then return p.icon end
        id = NS.KnownSpellId(kind) or rc.id
    end
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex then return tex end
    end
    if GetSpellTexture then
        local ok, tex = pcall(GetSpellTexture, id)
        if ok and tex then return tex end
    end
    return (p and p.icon) or "Interface\\Icons\\Spell_Nature_Lightning"
end

-- Everything this player can hand out, in KINDS order: a talented shaman
-- with drums is { TIDE, LUST, DRUMS }. Cached until ForgetSpellCache.
function NS.MyKinds()
    if NS._myKinds then return NS._myKinds end
    local out = {}
    if NS.demoKind then out[#out + 1] = NS.demoKind end   -- /inn demo pretends
    for _, kind in ipairs(NS.KINDS) do
        if kind ~= NS.demoKind and NS.KnownSpellId(kind) then out[#out + 1] = kind end
    end
    NS._myKinds = out
    return out
end

-- The "cannot benefit" debuffs: Exhaustion / Sated after Bloodlust, Tinnitus
-- after drums. While one is up, asking for that thing is pointless.
NS.BLOCK_DEBUFF = {
    LUST  = { ids = { [57723] = true, [57724] = true }, names = { Exhaustion = true, Sated = true } },
    DRUMS = { ids = { [51120] = true },                 names = { Tinnitus = true } },
}
-- returns blocked, secondsLeft, duration - so the button can show the timer
function NS.Blocked(kind, unit)
    local spec = NS.BLOCK_DEBUFF[kind]
    if not spec or not UnitDebuff then return false end
    unit = unit or "player"
    for i = 1, 40 do
        local ok, name, _, _, _, duration, expires, _, _, _, spellId = pcall(UnitDebuff, unit, i)
        if not ok or not name then break end
        if (spellId and spec.ids[spellId]) or spec.names[name] then
            local left = (tonumber(expires) and expires > 0) and (expires - NS.Now()) or 0
            if left < 0 then left = 0 end
            return true, left, tonumber(duration) or 0
        end
    end
    return false
end
function NS.HasExhaustion(unit) return NS.Blocked("LUST", unit) end

-- a druid in bear, cat, travel or flight form cannot innervate. True while
-- the form blocks the spell (Tree of Life does not, and IsUsableSpell says
-- so on a client that has it).
function NS.Shapeshifted()
    if not GetShapeshiftForm then return false end
    local ok, form = pcall(GetShapeshiftForm)
    if not ok or (tonumber(form) or 0) == 0 then return false end
    if IsUsableSpell then
        local ok2, usable = pcall(IsUsableSpell, NS.PROVIDERS.INNERVATE.ids[1])
        if ok2 and usable then return false end
    end
    return true
end

function NS.Provides(kind)
    for _, k in ipairs(NS.MyKinds()) do if k == kind then return true end end
    return false
end

-- the headline kind, for messages: a druid is a druid even with drums
function NS.MyKind()
    return NS.MyKinds()[1]
end

function NS.KindOfSpellId(id)
    id = tonumber(id or "")
    if not id then return nil end
    for _, kind in ipairs(NS.KINDS) do
        for _, sid in ipairs(NS.PROVIDERS[kind].ids) do
            if sid == id then return kind end
        end
    end
end

-- back-compat wrappers

function NS.PlayerName()
    return NS.Short(UnitName("player"))
end

function NS.InCombat()
    if InCombatLockdown then return InCombatLockdown() and true or false end
    return false
end

--------------------------------------------------------------------
-- group helpers
--------------------------------------------------------------------

-- iterate group members: cb(unit, name, class)
function NS.ForEachMember(cb)
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local name = NS.Short(UnitName(unit))
                local _, class = UnitClass(unit)
                cb(unit, name, class)
            end
        end
    else
        cb("player", NS.PlayerName(), select(2, UnitClass("player")))
        for i = 1, math.max(0, n - 1) do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = NS.Short(UnitName(unit))
                local _, class = UnitClass(unit)
                cb(unit, name, class)
            end
        end
    end
end

function NS.UnitOf(name)
    if not name then return nil end
    name = NS.Short(name)
    if name == NS.PlayerName() then return "player" end
    local found
    NS.ForEachMember(function(unit, n)
        if not found and n == name then found = unit end
    end)
    return found
end

-- raid subgroup (1-8) a player sits in; 1 for everyone in a plain party.
-- Mana Tide only reaches the shaman's own subgroup, so this decides eligibility.
function NS.RefreshSubgroups()
    NS._subgroup = {}
    if IsInRaid and IsInRaid() and GetRaidRosterInfo then
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n do
            local ok, rname, _, subgroup = pcall(GetRaidRosterInfo, i)
            if ok and rname then NS._subgroup[NS.Short(rname)] = subgroup or 1 end
        end
    else
        NS.ForEachMember(function(_, nm) NS._subgroup[nm] = 1 end)
    end
    return NS._subgroup
end

function NS.Subgroup(name)
    name = NS.Short(name)
    if not name then return nil end
    if not NS._subgroup then NS.RefreshSubgroups() end
    return NS._subgroup[name]
end

function NS.SameGroup(a, b)
    local ga, gb = NS.Subgroup(a), NS.Subgroup(b)
    return ga ~= nil and ga == gb
end

-- everyone in a subgroup, with their mana
function NS.GroupMates(name)
    local out = {}
    local g = NS.Subgroup(name)
    if not g then return out end
    NS.ForEachMember(function(unit, nm, class)
        if NS.Subgroup(nm) == g then
            out[#out + 1] = { name = nm, unit = unit, class = class, mana = NS.ManaPct(unit) }
        end
    end)
    return out
end

-- class colours, for the assignment window and menus
NS.CLASS_COLOR = {
    DRUID = "ff7d0a", HUNTER = "abd473", MAGE = "69ccf0", PALADIN = "f58cba",
    PRIEST = "ffffff", ROGUE = "fff569", SHAMAN = "0070de", WARLOCK = "9482c9",
    WARRIOR = "c79c6e",
}

function NS.ClassColored(name, class)
    if not name then return "" end
    class = class or NS.ClassOf(name)
    local c = NS.CLASS_COLOR[class or ""]
    if not c then return name end
    return "|cff" .. c .. name .. "|r"
end

-- accept sloppy capitalisation from slash commands: match the roster
function NS.ResolveName(name)
    if not name or name == "" then return nil end
    name = NS.Short(name)
    local lower = string.lower(name)
    local found
    NS.ForEachMember(function(_, nm)
        if not found and string.lower(nm) == lower then found = nm end
    end)
    return found or name
end

function NS.ClassOf(name)
    local unit = NS.UnitOf(name)
    if not unit then return nil end
    local _, class = UnitClass(unit)
    return class
end

-- mana percent 0-100 for a unit, or nil if unknown
function NS.ManaPct(unit)
    if not unit or not UnitExists(unit) then return nil end
    local powerType = UnitPowerType and UnitPowerType(unit) or 0
    if powerType ~= 0 then return nil end   -- 0 = mana
    local cur = UnitPower(unit, 0) or 0
    local max = UnitPowerMax(unit, 0) or 0
    if max <= 0 then return nil end
    return math.floor(cur / max * 100 + 0.5)
end

function NS.IsRequesterClass(class)
    if not class then return false end
    if NS.db and NS.db.requesterClasses and NS.db.requesterClasses[class] ~= nil then
        return NS.db.requesterClasses[class] and true or false
    end
    return NS.REQUESTER_CLASSES[class] and true or false
end

function NS.InGroup()
    if IsInRaid and IsInRaid() then return true end
    if IsInGroup and IsInGroup() then return true end
    return false
end

function NS.GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"          -- a dungeon-finder group drops RAID/PARTY messages
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

--------------------------------------------------------------------
-- timers
--------------------------------------------------------------------

function NS.After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
        return true
    end
    return false
end

