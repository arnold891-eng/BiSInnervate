-- BiS Innervate :: Tracker.lua
-- Who in the raid can give mana: druids (Innervate) and resto shamans with the
-- Mana Tide talent. Whether their cooldown is up, which subgroup they sit in,
-- and every cast we see in the combat log.
--
-- Only people running the addon count. A druid without it cannot see a call,
-- so lighting the Innervate button on their account would be a lie.

local ADDON, NS = ...

local Tracker = {}
NS.Tracker = Tracker

-- kind -> name -> { name, kind, cd, cdStamp, mana, group, unit }
Tracker.providers = {}
for _, kind in ipairs(NS.KINDS) do Tracker.providers[kind] = {} end

local function entry(kind, name)
    local t = Tracker.providers[kind]
    if not t then return nil end
    local d = t[name]
    if not d then
        d = { name = name, kind = kind, cd = 0, cdStamp = NS.Now() }
        t[name] = d
    end
    return d
end

function Tracker:CooldownLeft(name, kind)
    local t = self.providers[kind or "INNERVATE"]
    local d = t and t[NS.Short(name or "")]
    if not d then return 0 end
    local left = (d.cd or 0) - (NS.Now() - (d.cdStamp or 0))
    return left < 0 and 0 or left
end

function Tracker:SetState(name, kind, cd, mana, combat, hasAddon, group, extra)
    name = NS.Short(name)
    if not name or not self.providers[kind] then return end
    local d = entry(kind, name)
    if cd then d.cd, d.cdStamp = cd, NS.Now() end
    if mana then d.mana = mana end
    if group then d.group = group end
    if kind == "DRUMS" and extra and extra ~= "" then
        d.drums = {}
        for letter in string.gmatch(extra, "%u") do
            if NS.DRUM_LETTER[letter] then d.drums[NS.DRUM_LETTER[letter]] = true end
        end
    elseif kind == "REZ" and extra then
        d.wipe = extra          -- "RS": their wipe protection letters (+ H/X: spec)
        local dps = (string.find(extra, "X", 1, true) ~= nil) or nil
        -- a respec moves a face on or off the grid: a rebind (after the
        -- fight, if there is one - Bind refuses in combat and AfterCombat
        -- runs it again)
        local rebind = (d.dpsSpec ~= dps) and d.unit ~= nil
        d.dpsSpec = dps
        if rebind and NS.Window then NS.Window:Bind() end
    elseif kind == "INNERVATE" then
        d.shifted = (extra == "F") or nil      -- bear / cat: cannot innervate
    end
    if NS.Window then NS.Window:Refresh() end
end

function Tracker:Forget(name, kind)
    local t = self.providers[kind]
    if t then t[NS.Short(name or "")] = nil end
end

--------------------------------------------------------------------
-- casts: the combat log is the truth about who innervated whom
--------------------------------------------------------------------

function Tracker:NoteCast(kind, caster, target, variant)
    caster = NS.Short(caster)
    if not caster or not self.providers[kind] then return end
    local p = NS.Provider(kind)
    if kind == "REZ" then
        -- a rez landing: the corpse is taken, and a "rez me first" call closes.
        -- Most rezzers do not run the addon; they must not land in the roster.
        NS.Rez:OnRezCast(caster, target and NS.Short(target) or nil)
        return
    end
    local d = entry(kind, caster)
    d.cd, d.cdStamp = p.cd, NS.Now()
    if NS.Provider(kind).scope ~= "target" then
        d.group = d.group or NS.Subgroup(caster)
        NS.Calls:OnCast(kind, caster, nil, d.group, variant)
    else
        NS.Calls:OnCast("INNERVATE", caster, target and NS.Short(target) or nil)
    end
    NS.Debug("cast seen:", kind, caster, "->", tostring(target))
    if NS.Window then NS.Window:Refresh() end
end

--------------------------------------------------------------------
-- roster
--------------------------------------------------------------------

-- true while the roster reads empty right after it had people: a zone-in, not
-- a real departure. After 10s of emptiness we believe it.
function Tracker:RosterBlip()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n > 0 then
        self._lastN, self._emptySince = n, nil
        return false
    end
    if (self._lastN or 0) == 0 or NS.demoMode then return false end
    self._emptySince = self._emptySince or NS.Now()
    if (NS.Now() - self._emptySince) < 10 then return true end
    self._lastN, self._emptySince = 0, nil
    return false
end

function Tracker:UpdateRoster()
    -- A zone-in reads the roster as EMPTY for a moment - IsInGroup() false and
    -- zero members. Wiping the provider and addon-user tables on that blip left
    -- every non-provider off the grid for the rest of the night, because only
    -- providers ever re-announce themselves. If we had a group a moment ago and
    -- now see nobody, wait.
    if self:RosterBlip() then return end
    -- really alone now (not a zone-in blip): the rez scoreboard was this raid's
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n == 0 and (self._hadN or 0) > 0 and NS.Rez then NS.Rez:OnNewGroup() end
    self._hadN = n
    NS.RefreshSubgroups()
    local seen = {}
    for _, kind in ipairs(NS.KINDS) do seen[kind] = {} end

    NS.ForEachMember(function(unit, name, class)
        for _, kind in ipairs(NS.KINDS) do
            local known = self.providers[kind][name]
            -- somebody counts for a kind once their addon has listed it in a
            -- HELLO or STATE - that is the only way to know about a talent or
            -- a drum in a bag
            local counts = known ~= nil and NS.Comm:HasAddon(name)
            if counts then
                seen[kind][name] = true
                local d = entry(kind, name)
                d.unit  = unit
                d.group = NS.Subgroup(name)
                local m = NS.ManaPct(unit)
                if m then d.mana = m end
            end
        end
    end)

    local me = NS.PlayerName()
    for _, myKind in ipairs(NS.MyKinds()) do
        local d = entry(myKind, me)
        d.unit  = "player"
        d.cd, d.cdStamp = NS.SpellCooldownFor(myKind), NS.Now()
        if myKind == "INNERVATE" then d.shifted = NS.Shapeshifted() or nil end
        if myKind == "DRUMS" then
            d.drums = {}
            for t in pairs(NS.MyDrums()) do d.drums[t] = true end
        end
        d.mana  = NS.ManaPct("player") or d.mana
        d.group = NS.Subgroup(me)
        seen[myKind][me] = true
    end

    for _, kind in ipairs(NS.KINDS) do
        for name in pairs(self.providers[kind]) do
            if not seen[kind][name] then self.providers[kind][name] = nil end
        end
    end
    if (self._lastN or 0) > 0 then NS.Comm:PurgeAbsent() end
    if NS.Window then NS.Window:Refresh() end
end

-- providers of one kind who could serve `target` right now, ready first
function Tracker:Available(kind, target, variant)
    local list = {}
    for name, d in pairs(self.providers[kind] or {}) do
        local ok = true
        if NS.Provider(kind).scope == "group" and target then ok = NS.SameGroup(name, target) end
        -- a specific drum: only somebody who carries that type
        if ok and kind == "DRUMS" and variant and variant ~= "ANY" then
            ok = d.drums and d.drums[variant] or false
        end
        if ok then
            local unit = d.unit or NS.UnitOf(name)
            local dead = unit and UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
            local online = (not unit) or (UnitIsConnected == nil) or UnitIsConnected(unit)
            -- a shapeshifted druid is not available; the count of them is
            -- kept so the asker's button can say why
            if not dead and online and not d.shifted then
                list[#list + 1] = { name = name, cd = self:CooldownLeft(name, kind), group = d.group }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.cd ~= b.cd then return a.cd < b.cd end
        return a.name < b.name
    end)
    return list
end

-- is there ANY druid with the addon in the raid? (up or not - the button is
-- about whether asking can reach somebody)
function Tracker:HasDruid()
    for name in pairs(self.providers.INNERVATE) do
        if name ~= NS.PlayerName() or NS.Provides("INNERVATE") then return true end
    end
    return false
end

-- the soonest a provider of this kind in reach will be ready (0 = one is ready now)
function Tracker:SoonestCooldown(kind, target, variant)
    local list = self:Available(kind, target, variant)
    if #list == 0 then return nil end
    return list[1].cd or 0          -- Available sorts ready first
end

-- druids with the addon who are standing but in a form right now
function Tracker:DruidsShifted()
    local n = 0
    for name, d in pairs(self.providers.INNERVATE) do
        if d.shifted then
            local unit = d.unit or NS.UnitOf(name)
            if not (unit and UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)) then n = n + 1 end
        end
    end
    return n
end

function Tracker:DruidsReady()
    local n = 0
    for _, d in ipairs(self:Available("INNERVATE")) do
        if d.cd <= 0 then n = n + 1 end
    end
    return n
end

-- the provider of a group-scoped kind in this player's subgroup, if there is
-- one (ready first, so a second shaman with lust up beats one on cooldown)
function Tracker:GroupProviderFor(kind, name, variant)
    local list = self:Available(kind, NS.Short(name or ""), variant)
    return list[1]
end
function Tracker:TideFor(name) return self:GroupProviderFor("TIDE", name) end

--------------------------------------------------------------------
-- events
--------------------------------------------------------------------

function Tracker:OnCombatLogEvent(...)
    local _, subEvent, _, _, srcName, _, _, _, dstName, _, _, spellId, spellName = ...
    if subEvent == "SPELL_RESURRECT" then
        NS.Rez:OnResurrect(srcName and NS.Short(srcName), dstName and NS.Short(dstName), spellName)
        return
    end
    if subEvent == "SPELL_HEAL" then
        -- my own heals size the rez module's heal table
        if srcName and NS.Short(srcName) == NS.PlayerName() then
            local amount, over, _, crit = select(15, ...)
            NS.Rez:OnHeal(spellId, amount, over, crit)
        end
        return
    end
    if subEvent ~= "SPELL_CAST_SUCCESS" then return end
    local kind = NS.KindOfSpellId(spellId)
    local variant
    if not kind then
        variant = NS.DrumTypeOfName(spellName)
        if variant then kind = "DRUMS" end
        -- a rez rank we do not list, by name
        if not kind and spellName and NS.Rez:RezNames()[spellName] then kind = "REZ" end
    elseif kind == "DRUMS" then
        variant = NS.DrumTypeOfName(spellName)
        if not variant then
            for i, id in ipairs(NS.PROVIDERS.DRUMS.ids) do
                if id == tonumber(spellId) then variant = NS.DRUM_TYPES[i] end
            end
        end
    end
    if not kind then return end
    self:NoteCast(kind, srcName, dstName, variant)
end

function Tracker:OnUnitCast(unit, _, spellId)
    local kind = NS.KindOfSpellId(spellId)
    if not kind or not unit or not UnitExists(unit) then return end
    -- the unit's current target is NOT the innervate target (that is the boss,
    -- usually); the combat log carries the real one. Only the cooldown is
    -- worth taking from here.
    local caster = NS.Short(UnitName(unit))
    local d = entry(kind, caster)
    if d then d.cd, d.cdStamp = NS.Provider(kind).cd, NS.Now() end
end

function Tracker:BroadcastState()
    if #NS.MyKinds() == 0 or not NS.InGroup() then return end
    local kinds, cds = NS.Comm:KindsBlob()
    NS.Comm:Send("STATE", kinds, cds, NS.ManaPct("player") or "", NS.InCombat(),
                 NS.Subgroup(NS.PlayerName()) or 1)
end
