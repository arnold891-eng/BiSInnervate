-- BiS Innervate :: Calls.lua
-- The whole model, in one sentence: somebody calls for mana, everyone with the
-- addon sees their face pulse, the first druid to click it locks everyone else
-- out, and the combat log says when it landed.
--
-- No assignment, no escalation, no owner picking a druid. The 2.x queue tried
-- to decide FOR the druids and it was the source of most of the trouble. Now
-- the addon only shows and locks; people decide.
--
-- Who does what:
--   * the caller owns their call: only they cancel it, and they cancel it when
--     their mana comes back, when it expires, or when they click cancel
--   * every client mirrors every call, and drops one on its own only if the
--     caller has clearly gone (left, disconnected) or it is absurdly old
--   * a CLAIM is a soft lock with a timer: the druid who clicked has claimHold
--     seconds to land it before the face pulses for everybody again
--   * a cast in the combat log is the hard resolve

local ADDON, NS = ...

local Calls = {}
NS.Calls = Calls

Calls.list = {}        -- id -> call

local counter = 0
local function newId()
    counter = counter + 1
    return NS.PlayerName() .. "-" .. tostring(math.floor(NS.Now() * 10)) .. "-" .. counter
end

local function cfg() return NS.db or NS.DEFAULTS end

--------------------------------------------------------------------
-- reading
--------------------------------------------------------------------

function Calls:Get(id) return self.list[id] end

function Calls:Active()
    local out = {}
    for _, c in pairs(self.list) do
        if c.state == "open" then out[#out + 1] = c end
    end
    table.sort(out, function(a, b) return a.created < b.created end)
    return out
end

function Calls:For(name, kind)
    name = NS.Short(name or "")
    for _, c in pairs(self.list) do
        if c.state == "open" and c.target == name and (not kind or c.kind == kind) then return c end
    end
end

-- an open call of a group-scoped kind in this subgroup - or, for a raid-wide
-- kind (bloodlust), the one open call anywhere
function Calls:GroupCall(kind, group)
    local raidWide = NS.Provider(kind).scope == "raid"
    for _, c in pairs(self.list) do
        if c.state == "open" and c.kind == kind and (raidWide or c.group == group) then return c end
    end
end
function Calls:TideForGroup(group) return self:GroupCall("TIDE", group) end

function Calls:Mine(kind) return self:For(NS.PlayerName(), kind) end

--------------------------------------------------------------------
-- may I ask? -> ok, reason
--------------------------------------------------------------------

function Calls:CanAsk(kind, variant)
    local me = NS.PlayerName()
    if not NS.InGroup() and not NS.demoMode then return false, "not in a group" end
    local p = NS.Provider(kind)
    if not p then return false, "unknown" end
    local _, class = UnitClass("player")
    -- mana things are for mana users; bloodlust and drums are for everyone
    if (kind == "INNERVATE" or kind == "TIDE") and not NS.IsRequesterClass(class) then
        return false, "your class does not use mana"
    end
    if self:Mine(kind) then return false, "already asked" end
    if p.scope ~= "target" then
        if NS.Provides(kind) then return false, "you have it - use it" end
        local blocked, left = NS.Blocked(kind)
        if blocked then
            return false, ((kind == "LUST") and "exhausted" or "tinnitus") ..
                          (left > 0 and (" - " .. NS.TimeStr(left) .. " left") or ""), left, "debuff"
        end
        local who = NS.Tracker:GroupProviderFor(kind, me, variant)
        if not who then
            if kind == "DRUMS" and variant and variant ~= "ANY" then
                return false, "nobody in your group has " .. NS.DRUM[variant].name
            end
            return false, ({ TIDE = "no mana tide shaman in your group", LUST = "no shaman with the addon in the raid",
                             DRUMS = "nobody in your group has drums" })[kind] or "nobody in your group has it"
        end
        if self:GroupCall(kind, NS.Subgroup(me)) then
            return false, (p.scope == "raid") and "someone already asked" or "your group already asked"
        end
        -- everyone in reach is on cooldown: the button greys and shows the timer
        if who.cd > 0 then return false, who.name .. " back in " .. NS.TimeStr(who.cd), who.cd end
        return true, who.name .. " ready"
    end
    if not NS.Tracker:HasDruid() then return false, "no druid with the addon in the raid" end
    local ready = NS.Tracker:DruidsReady()
    if ready == 0 then
        local soon = NS.Tracker:SoonestCooldown("INNERVATE") or 0
        return false, "next druid in " .. NS.TimeStr(soon), soon
    end
    return true, ready .. (ready == 1 and " druid up" or " druids up")
end

--------------------------------------------------------------------
-- writing (mine)
--------------------------------------------------------------------

function Calls:Ask(kind, variant)
    kind = kind or "INNERVATE"
    if kind ~= "DRUMS" then variant = nil end
    if variant == "ANY" then variant = nil end
    local ok, why = self:CanAsk(kind, variant)
    if not ok then NS.Print(why .. ".") return nil end
    local me = NS.PlayerName()
    local _, class = UnitClass("player")
    local mana = NS.ManaPct("player")
    local c = {
        id = newId(), kind = kind, target = me, owner = me, class = class,
        mana = mana, startMana = mana, created = NS.Now(), state = "open",
        group = NS.Subgroup(me), mine = true, variant = variant,
    }
    self.list[c.id] = c
    NS.Comm:Send("ASK", c.id, kind, me, class or "", mana or "", c.group or "", variant or "")
    NS.Sound:Play("asked")
    if NS.Window then NS.Window:Refresh() end
    return c
end

function Calls:Cancel(c, why)
    if type(c) == "string" then c = self.list[c] end
    if not c or c.state ~= "open" then return end
    c.state, c.resolved, c.why = "cancelled", NS.Now(), why
    if c.owner == NS.PlayerName() then NS.Comm:Send("CANCEL", c.id, why or "") end
    if NS.Window then NS.Window:Refresh() end
end

function Calls:CancelMine(why)
    local n = 0
    for _, c in pairs(self.list) do
        if c.state == "open" and c.owner == NS.PlayerName() then self:Cancel(c, why or "manual"); n = n + 1 end
    end
    return n
end

-- a druid (or a tide shaman) clicked this one. The cast is already on its way
-- from the secure click; this is the lock that greys the face for everyone.
function Calls:Claim(c)
    if type(c) == "string" then c = self.list[c] end
    if not c or c.state ~= "open" then return false end
    local me = NS.PlayerName()
    if c.claimedBy and c.claimedBy ~= me and not self:ClaimExpired(c) then
        return false          -- somebody beat me to it; my cast still fired, and that is the race we accept
    end
    c.claimedBy, c.claimedAt = me, NS.Now()
    NS.Comm:Send("CLAIM", c.id, me)
    if NS.Window then NS.Window:Refresh() end
    return true
end

function Calls:ClaimExpired(c)
    return c.claimedAt and (NS.Now() - c.claimedAt) > (cfg().claimHold or 8)
end

function Calls:IsLocked(c)
    if not c or not c.claimedBy then return false end
    if self:ClaimExpired(c) then return false end
    return c.claimedBy ~= NS.PlayerName()
end

--------------------------------------------------------------------
-- the combat log resolves
--------------------------------------------------------------------

function Calls:OnCast(kind, caster, target, group, variant)
    local hit = false
    for _, c in pairs(self.list) do
        if c.state == "open" and c.kind == kind then
            local scope = NS.Provider(kind).scope
            local match = (scope == "target" and target and c.target == target)
                       or (scope == "raid")
                       or (scope == "group" and c.group == (group or NS.Subgroup(caster)))
            -- a specific drum call is only answered by that drum
            if match and kind == "DRUMS" and c.variant and variant and c.variant ~= variant then match = false end
            if match then
                c.state, c.resolved, c.by = "done", NS.Now(), caster
                hit = true
                if c.owner == NS.PlayerName() then
                    NS.Print(NS.ClassColored(caster) .. " " ..
                        ({ TIDE = "dropped mana tide for your group.", LUST = "popped bloodlust.",
                           DRUMS = "drummed for your group.", INNERVATE = "innervated you." })[kind])
                    NS.Sound:Play("landed")
                end
            end
        end
    end
    if hit and NS.Window then NS.Window:Refresh() end
end

--------------------------------------------------------------------
-- ticker
--------------------------------------------------------------------

function Calls:Tick()
    local now, c0 = NS.Now(), cfg()
    local changed = false
    for id, c in pairs(self.list) do
        if c.demo then
            -- pretend call: no expiry, no owner checks
        elseif c.state == "open" then
            local unit = NS.UnitOf(c.target)
            local ownerUnit = NS.UnitOf(c.owner)
            local gone = not ownerUnit
                or (UnitIsConnected and not UnitIsConnected(ownerUnit))
            if gone then c.goneSince = c.goneSince or now else c.goneSince = nil end

            if c.owner == NS.PlayerName() then
                local m = NS.ManaPct("player")
                if m then c.mana = m end
                if (now - c.created) > (c0.expire or 40) then
                    self:Cancel(c, "expired")
                elseif m and m >= (c0.cancelMana or 70) and m >= ((c.startMana or 0) + 15) then
                    -- measured against what they had when they asked: a
                    -- deliberate ask at 85% is not cancelled a tick later
                    self:Cancel(c, "mana recovered")
                elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
                    self:Cancel(c, "dead")
                end
            else
                -- a mirror drops a call only when the caller has plainly gone
                if (c.goneSince and (now - c.goneSince) > 8)
                   or (now - c.created) > ((c0.expire or 40) + 15)
                   or (unit and UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)) then
                    c.state, c.resolved = "cancelled", now
                    changed = true
                end
            end
            -- a claim that never landed goes back to pulsing for everyone
            if c.state == "open" and c.claimedBy and self:ClaimExpired(c) then
                c.claimedBy, c.claimedAt = nil, nil
                changed = true
            end
        elseif c.resolved and (now - c.resolved) > 4 then
            self.list[id] = nil
            changed = true
        end
    end
    if changed and NS.Window then NS.Window:Refresh() end
end

-- the 10s heartbeat: a client that missed the ASK learns about it
function Calls:Heartbeat()
    for _, c in pairs(self.list) do
        if c.state == "open" and c.owner == NS.PlayerName() and not c.demo then
            NS.Comm:Send("ASK", c.id, c.kind, c.target, c.class or "", c.mana or "", c.group or "", c.variant or "")
            if c.claimedBy then NS.Comm:Send("CLAIM", c.id, c.claimedBy) end
        end
    end
end

--------------------------------------------------------------------
-- incoming
--------------------------------------------------------------------

local Comm = NS.Comm

Comm:Register("ASK", function(sender, id, kind, target, class, mana, group, variant)
    if not id or not target then return end
    kind = (kind ~= "" and kind) or "INNERVATE"
    target = NS.Short(target)
    if sender ~= target then return end            -- you may only call for yourself
    local c = Calls.list[id]
    if c then
        c.mana = tonumber(mana or "") or c.mana
        return
    end
    -- one open call per person per kind: a newer ASK replaces a stale mirror
    -- (a lost CANCEL used to make a re-ask invisible for 55s)
    local dupe = Calls:For(target, kind)
    if dupe and dupe.id ~= id then
        dupe.state, dupe.resolved = "cancelled", NS.Now()
    end
    Calls.list[id] = {
        id = id, kind = kind, target = target, owner = sender,
        class = (class ~= "" and class) or NS.ClassOf(target),
        mana = tonumber(mana or "") or nil, startMana = tonumber(mana or "") or nil,
        created = NS.Now(), state = "open",
        group = tonumber(group or "") or NS.Subgroup(target),
        variant = (kind == "DRUMS" and variant ~= "" and NS.DRUM[variant]) and variant or nil,
    }
    -- a drummer out of combat binds the asked-for drum right away
    if kind == "DRUMS" and NS.Provides("DRUMS") and NS.Window then NS.Window:RebindDrums() end
    -- a CLAIM that arrived before this ASK was kept aside
    local early = Calls.pendingClaims and Calls.pendingClaims[id]
    if early and (NS.Now() - early.at) < (cfg().claimHold or 8) then
        Calls.list[id].claimedBy, Calls.list[id].claimedAt = early.who, early.at
    end
    if Calls.pendingClaims then Calls.pendingClaims[id] = nil end
    NS.Sound:Play(kind == "INNERVATE" and "someoneAsked" or "groupAsked", Calls.list[id])
    if NS.Window then NS.Window:Refresh(); NS.Window:Alert(Calls.list[id]) end
end)

Comm:Register("CLAIM", function(sender, id, who)
    local c = Calls.list[id]
    who = NS.Short(who or sender)
    if not c then
        -- the ASK may simply not have arrived yet: keep the claim for it
        if who == sender then
            Calls.pendingClaims = Calls.pendingClaims or {}
            Calls.pendingClaims[id] = { who = who, at = NS.Now() }
        end
        return
    end
    if c.state ~= "open" then return end
    if who ~= sender and sender ~= c.owner then return end   -- only for yourself, or the owner echoing
    if c.claimedBy == who and not Calls:ClaimExpired(c) then return end   -- a repeat (the heartbeat) must not extend the lock
    if c.claimedBy and c.claimedBy ~= who and not Calls:ClaimExpired(c) then return end
    c.claimedBy, c.claimedAt = who, NS.Now()
    if c.owner == NS.PlayerName() then
        NS.Print(NS.ClassColored(who) .. " is on it.")
        NS.Sound:Play("claimed")
    end
    if NS.Window then NS.Window:Refresh() end
end)

Comm:Register("CANCEL", function(sender, id, why)
    local c = Calls.list[id]
    if not c or c.state ~= "open" then return end
    if sender ~= c.owner then return end
    c.state, c.resolved, c.why = "cancelled", NS.Now(), why
    if NS.Window then NS.Window:Refresh() end
end)
