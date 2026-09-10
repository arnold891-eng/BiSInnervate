-- BiS Innervate :: offline harness
-- Real Lua 5.1. Boots N independent "clients", each with its own copy of the
-- addon in its own environment, and routes addon messages / whispers / combat
-- log events between them the way the game would. Also enforces the combat
-- lockdown rule: no secure frame may be shown, hidden, created or moved by
-- insecure code while combat is on.

local M = {}

local ADDON_FILES = {
    "Core/Util.lua", "Core/Comm.lua", "Core/Tracker.lua", "Core/Sound.lua", "Core/Calls.lua",
    "Core/Rez.lua", "UI/Window.lua", "UI/Minimap.lua", "UI/Config.lua", "Core/Demo.lua", "Core/Options.lua", "Core/Init.lua",
}

local World = {}
World.__index = World

function M.NewWorld(root)
    local w = setmetatable({}, World)
    w.root     = root or "."
    w.time     = 1000
    w.combat   = false
    w.clients  = {}
    w.order    = {}
    w.roster   = {}          -- { {name=, class=} }
    w.mana     = {}          -- name -> pct
    w.cd       = {}          -- name -> ready-at time
    w.whispers = {}          -- { {from=, to=, msg=} }
    w.addonMsgs= {}
    w.timers   = {}
    w.prints   = {}
    -- the rez module's world: all optional, all by NAME
    w.hp       = {}          -- name -> current health (default 10000)
    w.hpmax    = {}          -- name -> max health (default 10000)
    w.ghost    = {}          -- name -> true: released (dead and a ghost)
    w.casting  = {}          -- name -> { spell, target, endAt }
    w.bags     = {}          -- name -> { itemId, ... }
    w.buffs    = {}          -- name -> { { name, spellId }, ... }
    w.incoming = {}          -- name -> heals other people have in the air
    w.myIncoming = {}        -- name -> what THIS client has in the air on them
    w.outOfRange = {}        -- name -> true: every spell reads out of range
    w.bonusHealing = {}      -- name -> +healing
    w.talents  = {}          -- name -> { { name, rank }, ... }
    w.assist   = {}          -- name -> true: raid assistant
    w.book     = {}          -- name -> spellbook override { { name, rank, id, tip }, ... }
    w.binds    = {}          -- name -> key -> button (override bindings)
    return w
end

--------------------------------------------------------------------
-- world helpers
--------------------------------------------------------------------

-- spells: "INNERVATE" for druids, "TIDE" for resto shamans who took the talent
local SPELL_IDS = { INNERVATE = { 29166 }, TIDE = { 16190, 17354, 17359 },
                    LUST = { 2825, 32182 }, DRUMS = { 35476, 35475, 35478, 35477, 35474 },
                    REZ = { 2006, 7328, 2008 } }
local SPELL_CDS = { INNERVATE = 360, TIDE = 300, LUST = 600, DRUMS = 120, REZ = 0 }
local DRUM_ITEMS = { 29529, 29528, 29531, 29530, 29532 }

-- the rez module: per-class rez spell, and the spellbook each class carries
-- (max rank only, as on the live client). world.book[name] overrides.
local REZ_OF = { PRIEST = { id = 2006, name = "Resurrection" }, PALADIN = { id = 7328, name = "Redemption" },
                 SHAMAN = { id = 2008, name = "Ancestral Spirit" } }
local REZ_NAME_ID = { Resurrection = 2006, Redemption = 7328, ["Ancestral Spirit"] = 2008, Rebirth = 20484 }
local CAST_MS = { ["Resurrection"] = 10000, ["Redemption"] = 10000, ["Ancestral Spirit"] = 10000, ["Rebirth"] = 2000,
                  ["Lesser Healing Wave"] = 1500, ["Healing Wave"] = 3000, ["Chain Heal"] = 2500,
                  ["Flash Heal"] = 1500, ["Heal"] = 3000, ["Greater Heal"] = 3000, ["Circle of Healing"] = 0,
                  ["Flash of Light"] = 1500, ["Holy Light"] = 2500, ["Regrowth"] = 2000, ["Healing Touch"] = 3500 }
local SPELL_COST = { ["Resurrection"] = 1500, ["Redemption"] = 1500, ["Ancestral Spirit"] = 1200,
                     ["Lesser Healing Wave"] = 265, ["Healing Wave"] = 620, ["Chain Heal"] = 540,
                     ["Flash Heal"] = 380, ["Heal"] = 500, ["Greater Heal"] = 825, ["Circle of Healing"] = 450,
                     ["Flash of Light"] = 180, ["Holy Light"] = 840, ["Regrowth"] = 675, ["Healing Touch"] = 800 }
local BOOKS = {
    SHAMAN  = { { "Ancestral Spirit", "Rank 5", 2008 }, { "Reincarnation", "", 20608 },
                { "Lesser Healing Wave", "Rank 6", 8004, "Heals a friendly target for 892 to 1010." },
                { "Healing Wave", "Rank 11", 25357, "Heals a friendly target for 1919 to 2190." },
                { "Chain Heal", "Rank 5", 25423, "Heals a friendly target for 1055 to 1205." },
                { "Lightning Bolt", "Rank 12", 25449 } },
    PRIEST  = { { "Resurrection", "Rank 6", 2006 },
                { "Flash Heal", "Rank 9", 25235, "Heals a friendly target for 1101 to 1279." },
                { "Greater Heal", "Rank 7", 25314, "Heals a friendly target for 2414 to 2803." } },
    PALADIN = { { "Redemption", "Rank 5", 7328 }, { "Divine Intervention", "", 19752 },
                { "Flash of Light", "Rank 7", 27137, "Heals a friendly target for 458 to 513." },
                { "Holy Light", "Rank 11", 27136, "Heals a friendly target for 2196 to 2447." } },
    DRUID   = { { "Rebirth", "Rank 6", 20484 },
                { "Regrowth", "Rank 10", 26980, "Heals a friendly target for 1215 to 1350." },
                { "Healing Touch", "Rank 13", 26979, "Heals a friendly target for 2267 to 2678." } },
}

function World:AddPlayer(name, class, hasAddon, group, kind)
    self.roster[#self.roster + 1] = { name = name, class = class, group = group or 1 }
    self.mana[name] = self.mana[name] or 100
    self.kinds = self.kinds or {}
    if kind then
        self.kinds[name] = kind
    elseif class == "DRUID" then
        self.kinds[name] = "INNERVATE"
    end
    local c = self:NewClient(name, class, hasAddon)
    self.clients[name] = c
    self.order[#self.order + 1] = name
    return c
end

function World:Schedule(at, fn, client)
    self.timers[#self.timers + 1] = { at = at, fn = fn, client = client }
end

function World:Advance(seconds, step)
    step = step or 0.25
    local target = self.time + seconds
    while self.time < target do
        self.time = math.min(self.time + step, target)
        -- fire due timers
        local due = {}
        for i = #self.timers, 1, -1 do
            local t = self.timers[i]
            if t.at <= self.time then
                table.insert(due, 1, t)
                if t.repeatEvery then
                    t.at = self.time + t.repeatEvery
                else
                    table.remove(self.timers, i)
                end
            end
        end
        for _, t in ipairs(due) do
            local ok, err = pcall(t.fn)
            if not ok then error("timer error: " .. tostring(err), 0) end
        end
    end
end

function World:Fire(name, event, ...)
    local c = self.clients[name]
    if not c or not c.frames then return end
    for _, fr in ipairs(c.frames) do
        if fr._events and fr._events[event] and fr._scripts and fr._scripts.OnEvent then
            fr._scripts.OnEvent(fr, event, ...)
        end
    end
end

function World:FireAll(event, ...)
    for _, n in ipairs(self.order) do self:Fire(n, event, ...) end
end

-- hand a raw addon message to one client, as if it came over the raid channel.
-- Used to test what happens when a stranger, or a broken build, talks to us.
function World:Deliver(from, to, msg, channel)
    self:Fire(to, "CHAT_MSG_ADDON", "BiSInn", msg, channel or "RAID", from)
end

function World:UnitIndex(name)
    for i, p in ipairs(self.roster) do if p.name == name then return i end end
end

function World:Login()
    for _, n in ipairs(self.order) do self:Fire(n, "PLAYER_LOGIN") end
    self:Advance(3)
end

-- secure visibility drivers: the secure environment shows and hides the
-- frame itself on a combat change, before any addon code runs
function World:ApplyDrivers()
    for fr, cond in pairs(self.drivers or {}) do
        if cond == "hide" then fr._shown = false
        elseif cond == "[combat] hide; show" then fr._shown = not self.combat
        elseif cond == "show" then fr._shown = true end
    end
end

function World:SetCombat(on)
    self.combat = on and true or false
    self:ApplyDrivers()
    self:FireAll(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    self:Advance(0.5)
end

-- somebody casts one of the provider spells
function World:Cast(kind, caster, target)
    local id = SPELL_IDS[kind][1]
    self.cd[caster] = self.time + SPELL_CDS[kind]
    self.cd[caster .. "#" .. kind] = self.time + SPELL_CDS[kind]
    if kind == "DRUMS" then self.cd[caster .. "#DRUMS"] = self.time + SPELL_CDS.DRUMS end
    -- caster's own client sees UNIT_SPELLCAST_SUCCEEDED for "player"
    self:Fire(caster, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", id)
    -- everyone (including caster) sees the combat log line
    self._clog = { nil, "SPELL_CAST_SUCCESS", false, "GUID-" .. caster, caster, 0, 0,
                   "GUID-" .. tostring(target), target, 0, 0, id, kind, 8 }
    self:FireAll("COMBAT_LOG_EVENT_UNFILTERED")
    self:FireAll("SPELL_UPDATE_COOLDOWN")
    self:Advance(0.5)
end

-- a combat log line that is not a provider cast: heals and damage, for roles
function World:LogEvent(subEvent, caster, target)
    self._clog = { nil, subEvent, false, "GUID-" .. caster, caster, 0, 0,
                   "GUID-" .. tostring(target), target, 0, 0, 0, subEvent, 0 }
    self:FireAll("COMBAT_LOG_EVENT_UNFILTERED")
end

function World:Heal(caster, target, n)
    for _ = 1, (n or 1) do self:LogEvent("SPELL_HEAL", caster, target or "Tankman") end
end

function World:Damage(caster, n)
    for _ = 1, (n or 1) do self:LogEvent("SPELL_DAMAGE", caster, "Boss") end
end

-- a rez landing: the caster's own SUCCEEDED, the combat log's CAST_SUCCESS
-- and SPELL_RESURRECT, and the corpse is up. world.dead is cleared by the
-- test when the target "accepts".
function World:CastRez(caster, target)
    local class
    for _, p in ipairs(self.roster) do if p.name == caster then class = p.class end end
    local rz = REZ_OF[class or ""] or REZ_OF.PRIEST
    self.casting[caster] = nil
    self:Fire(caster, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-r", rz.id)
    self._clog = { nil, "SPELL_CAST_SUCCESS", false, "GUID-" .. caster, caster, 0, 0,
                   "GUID-" .. tostring(target), target, 0, 0, rz.id, rz.name, 8 }
    self:FireAll("COMBAT_LOG_EVENT_UNFILTERED")
    self._clog = { nil, "SPELL_RESURRECT", false, "GUID-" .. caster, caster, 0, 0,
                   "GUID-" .. tostring(target), target, 0, 0, rz.id, rz.name, 8 }
    self:FireAll("COMBAT_LOG_EVENT_UNFILTERED")
    self:Advance(0.5)
end

-- somebody starts casting a spell at a target: on their cast bar for
-- `seconds`, and their own client sees UNIT_SPELLCAST_START
function World:StartCast(caster, spell, target, seconds)
    self.casting[caster] = { spell = spell, target = target, endAt = self.time + (seconds or 10) }
    self:Fire(caster, "UNIT_SPELLCAST_START", "player", "cast-s", REZ_NAME_ID[spell] or spell)
end

function World:StopCast(caster, how)
    local c = self.casting[caster]
    self.casting[caster] = nil
    local spell = c and (REZ_NAME_ID[c.spell] or c.spell)
    self:Fire(caster, how or "UNIT_SPELLCAST_STOP", "player", "cast-s", spell)
end

function World:Heal2(caster, target, spellId, spellName, amount, overheal, crit)
    self._clog = { nil, "SPELL_HEAL", false, "GUID-" .. caster, caster, 0, 0, "GUID-" .. tostring(target), target, 0, 0,
                   spellId, spellName, 8, amount, overheal or 0, 0, crit and true or false }
    self:FireAll("COMBAT_LOG_EVENT_UNFILTERED")
end

function World:CastInnervate(caster, target) return self:Cast("INNERVATE", caster, target) end
function World:CastTide(caster) return self:Cast("TIDE", caster, caster) end
function World:CastLust(caster) return self:Cast("LUST", caster, caster) end
function World:CastDrums(caster) return self:Cast("DRUMS", caster, caster) end

function World:Whisper(from, to, msg)
    self.whispers[#self.whispers + 1] = { from = from, to = to, msg = msg }
    if self.clients[to] then self:Fire(to, "CHAT_MSG_WHISPER", msg, from) end
end

function World:WhispersTo(name)
    local out = {}
    for _, w in ipairs(self.whispers) do if w.to == name then out[#out + 1] = w end end
    return out
end

--------------------------------------------------------------------
-- per-client environment
--------------------------------------------------------------------

local function makeAnimation()
    local a = {}
    function a:SetDuration() end
    function a:SetFromAlpha() end
    function a:SetToAlpha() end
    function a:SetChange() end
    return a
end

local function makeAnimGroup()
    local g = { _playing = false }
    function g:SetLooping() end
    function g:CreateAnimation() return makeAnimation() end
    function g:Play() self._playing = true end
    function g:Stop() self._playing = false end
    function g:IsPlaying() return self._playing end
    return g
end

-- somebody leaves the raid: every slot after them renumbers, which is exactly
-- what used to re-aim a bound square at the wrong player
function World:RemovePlayer(name)
    for i, p in ipairs(self.roster) do
        if p.name == name then table.remove(self.roster, i) break end
    end
    self.clients[name] = nil
    for i, n in ipairs(self.order) do
        if n == name then table.remove(self.order, i) break end
    end
    self:FireAll("GROUP_ROSTER_UPDATE")
end

function World:NewClient(name, class, hasAddon)
    local world = self
    local client = { name = name, class = class, frames = {}, prints = {}, NS = nil }
    if not hasAddon then return client end

    local env = setmetatable({}, { __index = _G })
    env._G = env                 -- addon code reads _G.FojjiCore / _G.BiSTheme: that is THIS client, not the host
    client.env = env

    ------------------------------------------------------------------
    -- unit API
    ------------------------------------------------------------------
    local function resolve(unit)
        if not unit then return nil end
        if unit == "player" then return name end
        local idx = string.match(unit, "^raid(%d+)$")
        if idx then
            if world.blip then return nil end
            local p = world.roster[tonumber(idx)]
            return p and p.name
        end
        idx = string.match(unit, "^party(%d+)$")
        if idx then
            if world.blip then return nil end
            local p = world.roster[tonumber(idx)]
            return p and p.name
        end
        -- "<unit>target": whoever that unit is casting at
        local base = string.match(unit, "^(.+)target$")
        if base then
            local n = resolve(base)
            local c = n and world.casting[n]
            return c and c.target or nil
        end
        -- a player's NAME is a valid unit id for anyone in your group, and
        -- unlike raid7 it does not change when somebody leaves
        if not world.noNames then
            for _, p in ipairs(world.roster) do
                if p.name == unit then return p.name end
            end
        end
        return nil  -- "<unit>target" etc: unknown in the harness
    end
    client.resolve = resolve

    env.UnitName   = function(u) return resolve(u) end
    env.UnitExists = function(u) return resolve(u) ~= nil end
    env.UnitClass  = function(u)
        local n = resolve(u); if not n then return nil end
        for _, p in ipairs(world.roster) do if p.name == n then return p.class, p.class end end
    end
    env.UnitIsDeadOrGhost = function(u)
        local n = resolve(u)
        return (n ~= nil) and ((world.dead and world.dead[n]) or world.ghost[n]) and true or false
    end
    env.UnitIsDead  = function(u) local n = resolve(u); return (n ~= nil and world.dead and world.dead[n] and not world.ghost[n]) and true or false end
    env.UnitIsGhost = function(u) local n = resolve(u); return (n ~= nil and world.ghost[n]) and true or false end
    env.UnitIsPlayer  = function(u) return resolve(u) ~= nil end
    env.UnitIsVisible = function(u) return resolve(u) ~= nil end
    env.UnitCanAttack = function() return false end
    env.UnitGUID      = function(u) local n = resolve(u); return n and ("GUID-" .. n) or nil end
    env.UnitHealth    = function(u) local n = resolve(u); return n and (world.hp[n] or 10000) or 0 end
    env.UnitHealthMax = function(u) local n = resolve(u); return n and (world.hpmax[n] or 10000) or 0 end
    env.UnitGetIncomingHeals = function(u, healer)
        local n = resolve(u)
        if not n then return 0 end
        if healer == "player" then return world.myIncoming[n] or 0 end
        return (world.incoming[n] or 0) + (world.myIncoming[n] or 0)
    end
    -- UnitCastingInfo's 5th return is when the cast lands, in ms
    env.UnitCastingInfo = function(u)
        local n = resolve(u)
        local c = n and world.casting[n]
        if not c then return nil end
        return c.spell, c.spell, nil, world.time * 1000, c.endAt * 1000
    end
    env.GetSpellBonusHealing = function() return world.bonusHealing[name] or 0 end
    env.UnitLevel = function() return 70 end
    -- world.form[name] = 1 (bear) / 3 (cat) ...: a druid in a form
    env.GetShapeshiftForm = function() return (world.form or {})[name] or 0 end
    env.IsUsableSpell = function() return ((world.form or {})[name] or 0) == 0 end
    env.GetSpellLevelLearned = function(id) return (world.spellLevel or {})[id] end
    -- a heal landing from this client's own cast, for the combat log
    -- (SPELL_HEAL: ..., spellId, spellName, school, amount, overheal, absorbed, critical)
    env.GetNumTalentTabs = function() return 1 end
    -- world.tabs[name] = { 5, 0, 41 }: points per tree (classic shape:
    -- name, icon, points, file)
    env.GetTalentTabInfo = function(tab)
        local t = (world.tabs or {})[name]
        if not t or t[tab] == nil then return nil end
        return "Tree " .. tab, "icon", t[tab], "file"
    end
    env.GetNumTalents = function() return #(world.talents[name] or {}) end
    env.GetTalentInfo = function(_, i)
        local t = (world.talents[name] or {})[i]
        if not t then return nil end
        return t[1], nil, nil, nil, t[2], 5
    end
    env.SetOverrideBindingClick = function(owner, prio, key, button, mouse)
        world.binds[name] = world.binds[name] or {}
        world.binds[name][key] = button
    end
    env.ClearOverrideBindings = function() world.binds[name] = {} end
    env.GetBindingAction = function() return "" end
    env.Enum = { SpellBookSpellBank = { Player = 0 } }
    local function book()
        return world.book[name] or BOOKS[class] or {}
    end
    env.C_SpellBook = {
        GetSpellBookItemName = function(i) local e = book()[i]; if not e then return nil end; return e[1], e[2] end,
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book() } end,
        GetSpellBookItemInfo = function(i) local e = book()[i]; if not e then return nil end; return { spellID = e[3] } end,
    }
    env.C_TooltipInfo = {
        GetSpellBookItem = function(i)
            local e = book()[i]
            if not e then return nil end
            if not e[4] then return { lines = { { leftText = e[1] } } } end
            return { lines = { { leftText = e[1] }, { leftText = e[4] } } }
        end,
    }
    env.TooltipUtil = { SurfaceArgs = function() end }
    env.C_Container = {
        GetContainerNumSlots = function(bag) return (bag == 0) and 16 or 0 end,
        GetContainerItemInfo = function(bag, slot)
            if bag ~= 0 then return nil end
            local id = (world.bags[name] or {})[slot]
            return id and { itemID = id } or nil
        end,
    }
    env.C_UnitAuras = {
        GetAuraDataByIndex = function(u, i)
            local n = resolve(u)
            local b = n and (world.buffs[n] or {})[i]
            if not b then return nil end
            return { name = b[1], spellId = b[2] }
        end,
    }
    env.C_Item = { GetItemIconByID = function() return "Interface\\Icons\\INV_Drink_04" end }
    env.UnitIsConnected   = function(u)
        local n = resolve(u)
        return not (world.offline and n and world.offline[n])
    end
    -- world.leader names the raid lead; with none set, everyone is lead
    env.UnitIsGroupLeader = function(u)
        local n = resolve(u or "player") or name
        if not world.leader then return true end
        return n == world.leader
    end
    env.UnitIsGroupAssistant = function(u)
        local n = resolve(u or "player")
        return (n ~= nil and world.assist[n]) and true or false
    end
    env.UnitPowerType     = function(u)
        local n = resolve(u)
        for _, p in ipairs(world.roster) do
            if p.name == n and (p.class == "WARRIOR" or p.class == "ROGUE") then return 1 end
        end
        return 0
    end
    env.UnitPower         = function(u) local n = resolve(u); return (world.mana[n] or 0) end
    env.UnitPowerMax      = function(u) local n = resolve(u); return n and (world.manaMax and world.manaMax[n]) or 100 end
    -- world.blip = true models the zone-in moment when the group API reports
    -- nobody at all; world.noNames = true models a client where a bare name is
    -- not a unit token (cross-realm)
    env.GetNumGroupMembers = function() if world.blip then return 0 end return #world.roster end
    env.IsInRaid  = function() return not world.blip and #world.roster > 5 end
    env.IsInGroup = function() return not world.blip and #world.roster > 1 end
    env.InCombatLockdown = function() return world.combat end
    env.GetTime = function() return world.time end
    env.GetRaidRosterInfo = function(i)
        local p = world.roster[i]
        if not p then return nil end
        return p.name, 0, p.group or 1, 70, p.class, p.class
    end

    local function kindOfId(id)
        for k, ids in pairs(SPELL_IDS) do
            for _, sid in ipairs(ids) do if sid == id then return k end end
        end
    end
    local function hasKind(k)
        local mk = (world.kinds or {})[name]          -- live: a respec changes it
        if type(mk) == "table" then
            for _, x in ipairs(mk) do if x == k then return true end end
            return false
        end
        return mk == k
    end
    env.IsPlayerSpell = function(id)
        local k = kindOfId(id)
        if k == "REZ" then
            local rz = REZ_OF[class or ""]
            return (rz ~= nil and rz.id == id) or false
        end
        return (k ~= nil and hasKind(k) and id == SPELL_IDS[k][1]) or false
    end
    -- drums: world.drums[name] = an item id from DRUM_ITEMS
    env.GetItemCount = function(itemId)
        return ((world.drums or {})[name] == itemId) and 1 or 0
    end
    env.GetItemCooldown = function(itemId)
        local ready = world.cd[name .. "#DRUMS"]
        if not ready or ready <= world.time then return 0, 0 end
        return ready - SPELL_CDS.DRUMS, SPELL_CDS.DRUMS
    end
    -- debuffs: world.debuffs[name] = { [spellId] = true }
    env.UnitDebuff = function(u, i)
        local n = resolve(u)
        local list = n and (world.debuffs or {})[n]
        if not list then return nil end
        local ids = {}
        for id in pairs(list) do ids[#ids + 1] = id end
        table.sort(ids)
        local id = ids[i]
        if not id then return nil end
        local names = { [57723] = "Exhaustion", [57724] = "Sated", [51120] = "Tinnitus" }
        local left = list[id]
        local dur = (type(left) == "number") and 600 or 0
        local expires = (type(left) == "number") and (world.time + left) or 0
        return names[id] or ("Debuff" .. id), nil, nil, nil, dur, expires, nil, nil, nil, id
    end

    env.C_Spell = {
        GetSpellInfo = function(id)
            if type(id) == "string" then
                if CAST_MS[id] then return { name = id, iconID = 99, castTime = CAST_MS[id] } end
                return nil
            end
            if id == 2006 then return { name = "Resurrection", iconID = 1, castTime = 10000 } end
            if id == 7328 then return { name = "Redemption", iconID = 2, castTime = 10000 } end
            if id == 2008 then return { name = "Ancestral Spirit", iconID = 3, castTime = 10000 } end
            if id == 20484 then return { name = "Rebirth", iconID = 4, castTime = 2000 } end
            local k = kindOfId(id) or "INNERVATE"
            local names = { INNERVATE = "Innervate", TIDE = "Mana Tide Totem", LUST = "Bloodlust", DRUMS = "Drums of Battle" }
            return { name = names[k] }
        end,
        GetSpellCooldown = function(id)
            if type(id) == "string" then
                -- a wipe-protection spell by name: world.cd["Name#Reincarnation"] = ready-at
                local ready = world.cd[name .. "#" .. id]
                if not ready or ready <= world.time then return { startTime = 0, duration = 0 } end
                return { startTime = ready - 1800, duration = 1800 }
            end
            local k = kindOfId(id) or "INNERVATE"
            if k == "REZ" then return { startTime = 0, duration = 0 } end
            local ready = world.cd[name .. "#" .. k] or world.cd[name]
            if not ready or ready <= world.time then return { startTime = 0, duration = 0 } end
            return { startTime = ready - SPELL_CDS[k], duration = SPELL_CDS[k] }
        end,
        GetSpellPowerCost = function(spell)
            if type(spell) == "number" then
                for _, b in pairs(BOOKS) do for _, e in ipairs(b) do if e[3] == spell then spell = e[1] end end end
            end
            local c = SPELL_COST[spell]
            if not c then return nil end
            return { { type = 0, cost = c } }
        end,
        GetSpellTexture = function(spell) return "Interface\\Icons\\" .. tostring(spell) end,
        IsSpellInRange = function(_, u)
            local n = resolve(u)
            if n and world.outOfRange[n] then return 0 end
            return 1
        end,
    }

    env.C_Timer = {
        After = function(delay, fn) world:Schedule(world.time + delay, fn, client) end,
        NewTicker = function(interval, fn)
            local t = { at = world.time + interval, fn = fn, client = client, repeatEvery = interval }
            world.timers[#world.timers + 1] = t
            return t
        end,
    }

    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, channel, target)
            world.addonMsgs[#world.addonMsgs + 1] = { from = name, msg = msg, channel = channel, target = target }
            if channel == "WHISPER" and target then
                world:Fire(target, "CHAT_MSG_ADDON", prefix, msg, channel, name)
            else
                for _, other in ipairs(world.order) do
                    if other ~= name then world:Fire(other, "CHAT_MSG_ADDON", prefix, msg, channel, name) end
                end
            end
        end,
    }

    env.SendChatMessage = function(msg, chatType, _, target)
        if chatType == "WHISPER" then world:Whisper(name, target, msg) end
    end

    env.SetPortraitTexture = function(tex, unit)
        if not resolve(unit) then error("no such unit", 0) end
        if tex then tex._portrait = resolve(unit) end
    end
    env.CombatLogGetCurrentEventInfo = function() return unpack(world._clog or {}) end
    client.sounds = {}
    env.PlaySound = function(id) client.sounds[#client.sounds + 1] = id; return true end
    env.PlaySoundFile = function() return false end     -- no FojjiCore voice files here
    env.SOUNDKIT = { RAID_WARNING = 8959 }
    env.GameTooltip = setmetatable({}, { __index = function() return function() end end })
    env.UIParent = { GetName = function() return "UIParent" end }
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.SPELL_FAILED_OUT_OF_RANGE = "Out of range."
    env.SPELL_FAILED_NO_MANA = "Not enough mana"
    env.SPELL_FAILED_LINE_OF_SIGHT = "Target not in line of sight"
    env.UISpecialFrames = {}
    -- Blizzard's minimap: a parent to hang a button on, nothing more
    env.Minimap = setmetatable({ GetName = function() return "Minimap" end },
        { __index = function(_, k)
            if type(k) == "string" and string.match(k, "^%u") then return function() return 0, 0 end end
            return nil
        end })
    env.GetCursorPosition = function() return 0, 0 end
    -- registering a driver is protected; the driver itself then owns Show/Hide
    env.RegisterStateDriver = function(fr, state, cond)
        if world.combat then error("LOCKDOWN VIOLATION: RegisterStateDriver during combat", 0) end
        world.drivers = world.drivers or {}
        world.drivers[fr] = cond
        if cond == "hide" then fr._shown = false elseif cond then fr._shown = not world.combat end
    end
    env.UnregisterStateDriver = function(fr)
        if world.combat then error("LOCKDOWN VIOLATION: UnregisterStateDriver during combat", 0) end
        if world.drivers then world.drivers[fr] = nil end
    end
    env.IsShiftKeyDown = function() return world.shift and true or false end
    env.IsControlKeyDown = function() return world.ctrl and true or false end
    env.SlashCmdList = {}
    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg)
            client.prints[#client.prints + 1] = msg
            world.prints[#world.prints + 1] = name .. ": " .. msg
        end,
    }

    ------------------------------------------------------------------
    -- frames
    ------------------------------------------------------------------
    local function isProtected(frame)
        -- Off-limits in combat if the frame IS secure, CONTAINS a secure frame,
        -- or is something a secure frame is ANCHORED to. The live client proved
        -- the third one: moving or hiding an anchor moves the protected frame
        -- that depends on it, so the client refuses.
        return (frame._secure or frame._hasSecureChild or frame._hasSecureDependent) and true or false
    end

    local function guard(frame, method)
        if isProtected(frame) and world.combat then
            error(("LOCKDOWN VIOLATION: %s on secure frame %s during combat"):format(method, frame._name or "?"), 0)
        end
    end

    local function newTexture(owner)
        local t = { _shown = false, _owner = owner }
        function t:SetAllPoints() end
        function t:SetPoint() end
        function t:SetHeight(h) self._h = h end
        function t:SetWidth(w) self._w = w end
        function t:SetSize(w, h) self._w, self._h = w, h end
        -- STRICT on purpose. `cond and T.rgba(name) or shade(name)` truncates to
        -- a single value, and the live client throws on the spot and takes the
        -- whole window with it. A stub that accepts anything turns that into a
        -- bug you only meet in the raid.
        function t:SetColorTexture(r, g, b, a)
            if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
                error("SetColorTexture needs r,g,b(,a) numbers - got "
                      .. type(r) .. "," .. type(g) .. "," .. type(b), 0)
            end
            self._color = { r, g, b, a or 1 }
        end
        function t:SetVertexColor(r, g, b, a)
            if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
                error("SetVertexColor needs r,g,b(,a) numbers", 0)
            end
            self._vertex = { r, g, b, a or 1 }
        end
        function t:SetTexture(...)
            if select("#", ...) > 1 then error("SetTexture(r,g,b,a) - use SetColorTexture", 0) end
            self._texture = (select(1, ...))
        end
        -- textures/regions are not protected frames: Blizzard's own action button
        -- glow shows and hides in combat, so this is legal.
        function t:Show() self._shown = true end
        function t:Hide() self._shown = false end
        function t:IsShown() return self._shown end
        function t:CreateAnimationGroup() return makeAnimGroup() end
        function t:SetTexCoord() end
        function t:SetBlendMode() end
        function t:SetAlpha(a) self._alpha = a end
        function t:GetAlpha() return self._alpha or 1 end
        -- unknown texture methods are harmless no-ops in the harness
        setmetatable(t, { __index = function(_, k)
            if type(k) == "string" and string.match(k, "^%u") then return function() end end
            return nil
        end })
        return t
    end

    local function newFontString(owner)
        local fs = { _text = "", _shown = true, _owner = owner, _points = {}, _size = 12, _kind = "text" }
        if owner and owner._regions then owner._regions[#owner._regions + 1] = fs end
        function fs:SetPoint(point, a, b, c, d)
            local rel, relPoint, x, y
            if type(a) == "table" then rel, relPoint, x, y = a, b, c, d
            elseif type(a) == "number" then relPoint, x, y = point, a, b
            elseif type(a) == "string" then relPoint, x, y = a, b, c
            else relPoint = point end
            self._points[#self._points + 1] = { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 }
        end
        function fs:ClearAllPoints() self._points = {} end
        function fs:SetWidth(w) self._w = w end
        function fs:SetHeight(h) self._h = h end
        function fs:SetSize(w, h) self._w, self._h = w, h end
        function fs:SetWordWrap(on) self._wrap = on and true or false end
        function fs:SetAlpha(a) self._alpha = a end
        function fs:GetAlpha() return self._alpha or 1 end
        function fs:Show() self._shown = true; self._hiddenX = nil end
        function fs:Hide() self._shown = false; self._hiddenX = true end
        function fs:IsShown() return self._shown end
        function fs:SetJustifyH() end
        function fs:SetText(t) self._text = t or "" end
        function fs:GetText() return self._text end
        function fs:SetTextColor(r, g, b, a)
            if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
                error("SetTextColor needs r,g,b(,a) numbers", 0)
            end
            self._color = { r, g, b, a or 1 }
        end
        function fs:SetFont(path, size)
            if type(path) ~= "string" or type(size) ~= "number" then
                error("SetFont needs a path and a size", 0)
            end
            self._font, self._size = path, size
        end
        -- estimated extent of the text: FRIZQT runs about half the font size
        -- per character; wraps when a width is set and wrapping is on
        function fs:Extent()
            local t = string.gsub(tostring(self._text or ""), "|c%x%x%x%x%x%x%x%x", "")
            t = string.gsub(t, "|r", "")
            local size = self._size or 12
            local longest, lines = 0, 0
            for line in string.gmatch(t .. "\n", "([^\n]*)\n") do
                lines = lines + 1
                if #line > longest then longest = #line end
            end
            if lines == 0 then lines = 1 end
            local w = longest * size * 0.5
            if self._w and w > self._w then
                if self._wrap then lines = lines + math.ceil(w / self._w) - 1; w = self._w
                else return w, lines * size * 1.25, true end      -- too wide, and it does not wrap
            end
            return (self._w or w), lines * size * 1.25, false
        end
        function fs:GetFont() return self._font, self._size end
        setmetatable(fs, { __index = function(_, k)
            if type(k) == "string" and string.match(k, "^%u") then return function() end end
            return nil
        end })
        return fs
    end

    local function newFrame(ftype, fname, parent, template)
        -- PlayerModel gets the model methods the grid uses
        local fr = {
            _type = ftype, _name = fname, _parent = parent, _template = template or "",
            _attrs = {}, _refs = {}, _events = {}, _scripts = {}, _hooks = {},
            _shown = false, _secure = (template and string.find(template, "Secure")) and true or false,
            _children = {}, _regions = {}, _points = {},
        }
        if type(parent) == "table" and parent._children then parent._children[#parent._children + 1] = fr end
        if world.combat and fr._secure then
            error("LOCKDOWN VIOLATION: created secure frame during combat", 0)
        end
        if fr._secure then
            -- mark our own ancestors only; UIParent is Blizzard's and is never
            -- something we would show or hide ourselves
            local up = parent
            while type(up) == "table" and up._type do
                up._hasSecureChild = true
                up = up._parent
            end
        end
        client.frames[#client.frames + 1] = fr

        function fr:GetName() return self._name end
        function fr:SetSize(w, h) guard(self, "SetSize"); self._w, self._h = w, h end
        function fr:SetWidth(w) guard(self, "SetWidth"); self._w = w end
        function fr:SetHeight(h) guard(self, "SetHeight"); self._h = h end
        function fr:GetWidth() return self._w or 0 end
        function fr:GetHeight() return self._h or 0 end
        function fr:SetPoint(point, a, b, c, d)
            guard(self, "SetPoint")
            -- remember the anchor so GetPoint can hand it back: the scale code
            -- reads its own offsets and writes rescaled ones
            if type(a) == "table" then
                self._point = { point, a, b, c, d }
            elseif type(a) == "number" then
                self._point = { point, nil, point, a, b }
            elseif type(a) == "string" then
                self._point = { point, nil, a, b, c }
            else
                self._point = { point, nil, point, 0, 0 }
            end
            local p = self._point
            self._points[#self._points + 1] = { point = p[1], rel = p[2], relPoint = p[3] or p[1], x = p[4] or 0, y = p[5] or 0 }
            local rel = a
            -- record the anchor dependency the client cares about
            if self._secure and type(rel) == "table" and rel._type then
                -- and everything that contains the anchor, since hiding a
                -- container moves/hides the anchor with it
                local up = rel
                while type(up) == "table" and up._type do
                    up._hasSecureDependent = true
                    up = up._parent
                end
            end
        end
        function fr:ClearAllPoints() guard(self, "ClearAllPoints"); self._point = nil; self._points = {} end
        function fr:SetAllPoints(rel)
            guard(self, "SetAllPoints")
            self._allPoints = rel or true
            if self._secure and type(rel) == "table" and rel._type then
                -- and everything that contains the anchor, since hiding a
                -- container moves/hides the anchor with it
                local up = rel
                while type(up) == "table" and up._type do
                    up._hasSecureDependent = true
                    up = up._parent
                end
            end
        end
        function fr:GetPoint()
            local p = self._point
            if not p then return "CENTER", nil, "CENTER", 0, 0 end
            return p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0
        end
        function fr:SetMovable() end
        function fr:RegisterForDrag() end
        function fr:RegisterForClicks(...) self._clicks = { ... } end
        function fr:SetClampedToScreen() end
        function fr:StartMoving() end
        function fr:StopMovingOrSizing() end
        function fr:SetScale(v) guard(self, "SetScale"); self._scale = v end
        function fr:GetScale() return self._scale or 1 end
        function fr:SetFrameStrata() end
        function fr:GetFrameLevel() return self._level or 1 end
        function fr:SetFrameLevel(v) self._level = v end
        function fr:Show() guard(self, "Show"); self._shown = true; self._hiddenX = nil end
        function fr:Hide() guard(self, "Hide"); self._shown = false; self._hiddenX = true end
        function fr:IsShown() return self._shown end
        function fr:CreateTexture() return newTexture(self) end
        if ftype == "PlayerModel" then
            function fr:SetUnit(u)
                if not resolve(u) then error("no such unit", 0) end
                self._unit = u
            end
            function fr:SetPortraitZoom() end
            function fr:SetCamDistanceScale() end
            function fr:SetRotation() end
        end
        function fr:CreateFontString() return newFontString(self) end
        function fr:SetScript(k, v) self._scripts[k] = v end
        -- SecureHandlerEnterLeaveTemplate: the _onenter / _onleave snippets
        -- run in the secure environment BEFORE the insecure scripts, and may
        -- show and hide secure frames in combat. Emulated: real Lua, a
        -- handle whose Show/Hide skip the guard, IsUnderMouse from
        -- world.mouseOver (a frame or a list of frames).
        local function handle(f)
            if not f then return nil end
            local h = {}
            function h:Show() f._shown = true end
            function h:Hide() f._shown = false end
            function h:IsShown() return f._shown end
            function h:GetAttribute(k) return f._attrs[k] end
            function h:GetFrameRef(k) return handle(f._refs[k]) end
            function h:IsUnderMouse()
                local m = world.mouseOver
                if type(m) == "table" and m._type then return m == f end
                for _, x in ipairs(m or {}) do if x == f then return true end end
                return false
            end
            return h
        end
        function fr:RunSnippet(name)
            local code = self._attrs[name]
            if type(code) ~= "string" then return end
            local chunk, err = loadstring(code, name)
            if not chunk then error("bad snippet " .. name .. ": " .. tostring(err), 0) end
            setfenv(chunk, { self = handle(self), ipairs = ipairs, pairs = pairs, tostring = tostring })
            chunk()
        end
        function fr:GetScript(k)
            local s = self._scripts[k]
            if string.find(self._template or "", "SecureHandlerEnterLeave", 1, true) and (k == "OnEnter" or k == "OnLeave") then
                local snippet = (k == "OnEnter") and "_onenter" or "_onleave"
                return function(f, ...)
                    f:RunSnippet(snippet)
                    if s then return s(f, ...) end
                end
            end
            return s
        end
        function fr:HookScript(k, v)
            local prev = self._scripts[k]
            self._scripts[k] = function(...) if prev then prev(...) end return v(...) end
        end
        function fr:RegisterEvent(e)
            local KNOWN = {
                ADDON_LOADED=1, PLAYER_LOGIN=1, PLAYER_ENTERING_WORLD=1, GROUP_ROSTER_UPDATE=1,
                CHAT_MSG_ADDON=1, CHAT_MSG_WHISPER=1, COMBAT_LOG_EVENT_UNFILTERED=1,
                UNIT_SPELLCAST_SUCCEEDED=1, SPELL_UPDATE_COOLDOWN=1,
                PLAYER_REGEN_ENABLED=1, PLAYER_REGEN_DISABLED=1,
                PLAYER_TALENT_UPDATE=1, CVAR_UPDATE=1, BAG_UPDATE=1, UNIT_AURA=1,
                UNIT_SPELLCAST_START=1, UNIT_SPELLCAST_STOP=1, UNIT_SPELLCAST_INTERRUPTED=1,
                UNIT_SPELLCAST_FAILED=1, UI_ERROR_MESSAGE=1, SPELLS_CHANGED=1,
                PLAYER_EQUIPMENT_CHANGED=1, PLAYER_DEAD=1, PLAYER_UNGHOST=1, PLAYER_ALIVE=1,
                UPDATE_SHAPESHIFT_FORM=1,
            }
            if not KNOWN[e] then error("unknown event: " .. tostring(e), 0) end
            self._events[e] = true
        end
        function fr:RegisterUnitEvent(e, ...) return self:RegisterEvent(e) end
        function fr:UnregisterEvent(e) self._events[e] = nil end
        function fr:CreateAnimationGroup() return makeAnimGroup() end
        function fr:SetAlpha(a) self._alpha = a end
        function fr:GetAlpha() return self._alpha or 1 end
        function fr:SetNormalTexture() end
        function fr:SetPushedTexture() end
        function fr:SetHighlightTexture() end
        function fr:SetFrameRef(k, v) self._refs[k] = v end
        -- unknown *methods* (CamelCase) are no-ops; unknown data fields stay nil
        setmetatable(fr, { __index = function(_, k)
            if type(k) == "string" and string.match(k, "^%u") then return function() end end
            return nil
        end })
        function fr:GetFrameRef(k) return self._refs[k] end
        function fr:GetAttribute(k) return self._attrs[k] end
        function fr:EnableMouse(on) guard(self, "EnableMouse"); self._mouse = on end
        function fr:SetAttribute(k, v)
            -- pessimistic client: insecure attribute writes on a protected frame
            -- are dropped during combat (InnervateMate assumes exactly this)
            if world.blockSecureWrites and world.combat and self._secure then return end
            self._attrs[k] = v
            -- emulate the secure handler snippet
            if k == "refresh" and self._attrs["_onattributechanged"] then
                local n = tonumber(self._attrs["count"] or 0) or 0
                local i = 1
                while self._refs["row" .. i] do
                    local b = self._refs["row" .. i]
                    local u = self._attrs["unit" .. i]
                    if i <= n and u and u ~= "" then
                        b._attrs["unit"] = u
                        b._shown = true          -- secure env: allowed in combat
                    else
                        b._shown = false
                    end
                    i = i + 1
                end
            end
        end
        return fr
    end

    env.CreateFrame = newFrame
    client.newFrame = newFrame

    ------------------------------------------------------------------
    -- load the addon into this environment
    ------------------------------------------------------------------
    local NS = {}
    client.NS = NS
    local before = {}
    for k in pairs(env) do before[k] = true end
    client.envBefore = before
    -- world.rootFor[name] loads an older build for this one client (a raider
    -- who has not updated): dev/old-3.2 has no Core/Rez.lua, so it is skipped
    local root = (world.rootFor and world.rootFor[name]) or world.root
    for _, rel in ipairs(ADDON_FILES) do
        local path = root .. "/" .. rel
        local chunk, err = loadfile(path)
        if not chunk and root ~= world.root and rel == "Core/Rez.lua" then chunk = function() end end
        if not chunk then error("load " .. path .. ": " .. tostring(err), 0) end
        setfenv(chunk, env)
        chunk("BiSInnervate", NS)
    end
    client.slash = env.SlashCmdList
    return client
end

--------------------------------------------------------------------
-- layout: estimated rectangles, and the overlap check. Coordinates are
-- WoW's (x right, y up), relative to the root you hand in. Every anchor
-- form the addon uses is understood: one point with offsets, two or more
-- points (TOPLEFT + BOTTOMRIGHT, TOPLEFT + TOPRIGHT + SetHeight), and
-- SetAllPoints. A font string's size is estimated from its text.
--------------------------------------------------------------------

local function edgesOf(rect, relPoint)
    local x, y
    if string.find(relPoint, "LEFT") then x = rect.left
    elseif string.find(relPoint, "RIGHT") then x = rect.right
    else x = (rect.left + rect.right) / 2 end
    if string.find(relPoint, "TOP") then y = rect.top
    elseif string.find(relPoint, "BOTTOM") then y = rect.bottom
    else y = (rect.top + rect.bottom) / 2 end
    return x, y
end

function M.Rect(obj, root, cache)
    cache = cache or {}
    if cache[obj] ~= nil then return cache[obj] or nil end
    if obj == root then
        local r = { left = 0, right = obj._w or 0, top = 0, bottom = -(obj._h or 0) }
        cache[obj] = r
        return r
    end
    local parent = obj._parent or obj._owner
    if obj._allPoints then
        local rel = (type(obj._allPoints) == "table") and obj._allPoints or parent
        local r = rel and M.Rect(rel, root, cache)
        cache[obj] = r or false
        return r
    end
    local w, h, tooWide
    if obj._kind == "text" then w, h, tooWide = obj:Extent() else w, h = obj._w, obj._h end
    local left, right, top, bottom, cx, cy
    for _, p in ipairs(obj._points or {}) do
        local rel = p.rel or parent
        local rr = rel and M.Rect(rel, root, cache)
        if rr then
            local ax, ay = edgesOf(rr, p.relPoint)
            ax, ay = ax + (p.x or 0), ay + (p.y or 0)
            if string.find(p.point, "LEFT") then left = ax
            elseif string.find(p.point, "RIGHT") then right = ax
            else cx = ax end
            if string.find(p.point, "TOP") then top = ay
            elseif string.find(p.point, "BOTTOM") then bottom = ay
            else cy = ay end
        end
    end
    if not left and not right and not cx then cache[obj] = false return nil end
    if left and right then w = right - left
    elseif w then
        if left then right = left + w elseif right then left = right - w else left, right = cx - w / 2, cx + w / 2 end
    else cache[obj] = false return nil end
    if top and bottom then h = top - bottom
    elseif h then
        if top then bottom = top - h elseif bottom then top = bottom + h else top, bottom = cy + h / 2, cy - h / 2 end
    else cache[obj] = false return nil end
    local r = { left = left, right = right, top = top, bottom = bottom, tooWide = tooWide }
    cache[obj] = r
    return r
end

local function overlaps(a, b)
    return a.left < b.right - 0.5 and b.left < a.right - 0.5 and a.bottom < b.top - 0.5 and b.bottom < a.top - 0.5
end

local function label(obj)
    if obj._kind == "text" then return "text '" .. string.sub(tostring(obj._text or ""), 1, 30) .. "'" end
    local t = obj._regions and obj._regions[1]
    for _, r in ipairs(obj._regions or {}) do if r._kind == "text" and r._text ~= "" then t = r break end end
    return (obj._name or obj._type or "frame") .. ((t and t._kind == "text") and (" '" .. string.sub(t._text, 1, 30) .. "'") or "")
end

-- Every problem on a page: siblings that overlap, and anything that runs
-- past the container it sits in (the page, or one of its columns).
-- `container` is the page to check; `root` a sized ancestor the anchors
-- resolve against (the config frame), defaulting to the container itself
function M.CheckLayout(container0, root)
    root = root or container0
    local problems, cache = {}, {}
    local rootRect = M.Rect(container0, root, cache)
    if not rootRect then return { "the page has no rectangle" } end
    -- a container is the page or a column (Config marks them `isColumn`):
    -- its children are laid out against each other, and everything under
    -- it has to fit inside it
    local function isContainer(f)
        return f == container0 or f.isColumn == true
    end
    local function within(r, box) return r.left >= box.left - 0.5 and r.right <= box.right + 0.5 and r.top <= box.top + 0.5 and r.bottom >= box.bottom - 0.5 end
    local function walk(container, box)
        local items = {}
        for _, c in ipairs(container._children) do
            local r = M.Rect(c, root, cache)
            if r and not c._hiddenX then
                if isContainer(c) then walk(c, r)
                else items[#items + 1] = { obj = c, rect = r } end
                if not within(r, box) then
                    problems[#problems + 1] = ("%s runs past its container (%d..%d x %d..%d in %d..%d x %d..%d)"):format(
                        label(c), r.left, r.right, r.bottom, r.top, box.left, box.right, box.bottom, box.top)
                end
            end
        end
        for _, t in ipairs(container._regions or {}) do
            if t._kind == "text" and t._text ~= "" and not t._hiddenX then
                local r = M.Rect(t, root, cache)
                if r then
                    items[#items + 1] = { obj = t, rect = r }
                    if not within(r, box) then
                        problems[#problems + 1] = ("%s runs past its container (right edge %d of %d)"):format(label(t), r.right, box.right)
                    end
                end
            end
        end
        for i = 1, #items do
            for j = i + 1, #items do
                if overlaps(items[i].rect, items[j].rect) then
                    problems[#problems + 1] = label(items[i].obj) .. " overlaps " .. label(items[j].obj)
                end
            end
        end
    end
    -- text inside a widget row must still fit the column the row sits in
    local function deepText(f, box)
        for _, t in ipairs(f._regions or {}) do
            if t._kind == "text" and t._text ~= "" and not t._hiddenX then
                local r = M.Rect(t, root, cache)
                if r and (r.right > box.right + 0.5 or r.tooWide) then
                    problems[#problems + 1] = ("%s is wider than its column (%d px past)"):format(label(t), r.right - box.right)
                end
            end
        end
        for _, c in ipairs(f._children) do
            local r = isContainer(c) and M.Rect(c, root, cache) or box
            deepText(c, r or box)
        end
    end
    walk(container0, rootRect)
    deepText(container0, rootRect)
    return problems
end

return M
