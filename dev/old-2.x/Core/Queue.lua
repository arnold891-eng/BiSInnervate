-- BiS Innervate :: Queue.lua
-- Request lifecycle + auto-assignment. Exactly ONE druid is on the hook for a
-- request at any moment; if they do nothing the request escalates to the next
-- druid. Everyone else sees the request as "taken" so nobody doubles up.

local ADDON, NS = ...

local Queue = {}
NS.Queue = Queue

Queue.requests = {}     -- id -> req
Queue._counter = 0

local function defaults()
    local db = NS.db or {}
    return {
        escalate   = db.escalate   or 7,    -- seconds before the next druid is pinged
        claimHold  = db.claimHold  or 8,    -- extra grace once a druid claims
        expire     = db.expire     or 40,   -- request lifetime
        cancelMana = db.cancelMana or 70,   -- auto-cancel if requester climbs above this
    }
end

local function newId()
    Queue._counter = Queue._counter + 1
    return string.format("%s-%d-%d-%d", NS.PlayerName() or "?", Queue._counter,
                         math.floor(NS.Now()), math.random(1000, 9999))
end

function Queue:Get(id) return self.requests[id] end

function Queue:ActiveFor(target)
    target = NS.Short(target)
    for _, r in pairs(self.requests) do
        if r.target == target and r.state == "pending" then return r end
    end
end

function Queue:ActiveList()
    local list = {}
    for _, r in pairs(self.requests) do
        if r.state == "pending" then list[#list + 1] = r end
    end
    return NS.SortRequests(list)
end

--------------------------------------------------------------------
-- creating
--------------------------------------------------------------------

function Queue:ActiveForKind(target, kind)
    target = NS.Short(target)
    for _, r in pairs(self.requests) do
        if r.target == target and r.state == "pending" and (r.kind or "INNERVATE") == kind then return r end
    end
end

-- an active mana tide request already covering this player's subgroup
function Queue:TideCovering(target)
    for _, r in pairs(self.requests) do
        if r.state == "pending" and r.kind == "TIDE" and NS.SameGroup(r.target, target) then return r end
    end
end

-- I need help. kind = "INNERVATE" (default) or "TIDE"
function Queue:RequestForSelf(kind)
    kind = kind or "INNERVATE"
    if not NS.InGroup() then NS.Print("not in a group.") return end
    local me = NS.PlayerName()

    if kind == "TIDE" then
        if not NS.Tracker:TideFor(me) then
            NS.Print("no shaman with mana tide up in your group.")
            return
        end
        local covered = self:TideCovering(me)
        if covered then
            -- one totem serves the whole group: ride along instead of pinging twice
            covered.riders = covered.riders or {}
            covered.riders[me] = NS.ManaPct("player") or 0
            NS.Comm:Send("RIDE", covered.id, me, NS.ManaPct("player") or "")
            NS.Print("mana tide already coming for your group.")
            return covered
        end
    end

    local existing = self:ActiveForKind(me, kind)
    if existing then
        NS.Print("already asked - " .. (existing.assigned and (existing.assigned .. " is up") or "waiting"))
        return existing
    end
    -- a Mana Tide in your group is not an innervate: it used to block one
    if kind == "INNERVATE" and NS.Tracker:RecentlyHelped(me, 20, "INNERVATE") then
        NS.Print("you were just topped up.")
        return
    end
    local req = self:Create(me, me, select(2, UnitClass("player")), NS.ManaPct("player"), true, kind)
    NS.Comm:Send("REQ", req.id, req.owner, req.target, req.class or "", req.mana or "", kind)
    self:Assign(req)
    return req
end

-- a non-addon player whispered me; I take ownership on their behalf
function Queue:RequestForOther(name, class, mana, kind)
    kind = kind or "INNERVATE"
    name = NS.Short(name)
    if not name then return end
    local existing = self:ActiveForKind(name, kind)
    if existing then return existing end
    local req = self:Create(name, NS.PlayerName(), class or NS.ClassOf(name), mana, false, kind)
    NS.Comm:Send("REQ", req.id, req.owner, req.target, req.class or "", req.mana or "", kind)
    -- small settle window: if another addon user also heard/owns this target and
    -- sorts earlier by name, they win and we become a mirror.
    NS.After(1.5, function()
        local r = Queue.requests[req.id]
        if r and r.state == "pending" and r.owner == NS.PlayerName() then Queue:Assign(r) end
    end)
    return req
end

function Queue:Create(target, owner, class, mana, hasAddon, kind)
    local req = {
        id       = newId(),
        kind     = kind or "INNERVATE",
        target   = NS.Short(target),
        owner    = NS.Short(owner),
        class    = class,
        mana     = tonumber(mana or "") or nil,
        created  = NS.Now(),
        -- what they had when they asked. Auto-cancel is measured against this,
        -- not against a fixed number: clicking the button at 85% used to create
        -- a request that the very next tick cancelled as "mana recovered".
        startMana = tonumber(mana or "") or nil,
        state    = "pending",
        attempt  = 0,
        hasAddon = hasAddon and true or false,
        group    = NS.Subgroup(target),
        riders   = {},
        whispered = {},
    }
    self.requests[req.id] = req
    if NS.UI then NS.UI:Refresh(); NS.UI:Alert(req) end
    return req
end

--------------------------------------------------------------------
-- assignment (owner only)
--------------------------------------------------------------------

function Queue:DruidBusy(druid, exceptId)
    for id, r in pairs(self.requests) do
        if id ~= exceptId and r.state == "pending" and not r.demo then
            -- mid-handover the request has no `assigned`, but the provider still
            -- holds the button until they release: they are not free
            if r.assigned == druid then return true end
            if r.releasing and r.prevAssigned == druid then return true end
        end
    end
    return false
end

function Queue:Assign(req, skipList, prefer)
    if req.owner ~= NS.PlayerName() then return end
    if req.state ~= "pending" then return end
    if req.releasing then return end          -- handover in progress: nobody is live
    -- already on somebody: only Escalate/FinishHandover may move it, otherwise a
    -- stray re-assign could hand the same request to a second provider
    if req.assigned then return end
    local cfg = defaults()

    skipList = skipList or req.tried or {}
    req.tried = skipList

    local order = NS.Tracker:AssignOrder(req.target, req.kind or "INNERVATE")
    local pick
    -- a standing assignment for this player wins if that provider is up
    if not prefer and NS.Assign then
        local standing = NS.Assign:ProviderFor(req.target)
        if standing and not (req.tried or {})[standing] then prefer = standing end
    end
    if prefer then
        for _, d in ipairs(order) do
            -- must pass the same busy check as everyone else, or a standing
            -- assignment (or a volunteer) could take a second request while
            -- already holding one - two live buttons, one cooldown
            if d.name == prefer and d.cd <= 0 and not self:DruidBusy(d.name, req.id) then
                pick = d
                break
            end
        end
    end
    for _, d in ipairs(order) do
        if pick then break end
        if d.cd <= 0 and not skipList[d.name] and not self:DruidBusy(d.name, req.id) then
            pick = d
            break
        end
    end

    if not pick then
        -- Second pass: someone already tried may take it again, but never the
        -- one we just released - handing it straight back produces a
        -- ping / stand-down loop and leaves them told to stand down.
        for _, d in ipairs(order) do
            if d.cd <= 0 and d.name ~= req.prevAssigned and not self:DruidBusy(d.name, req.id) then
                pick = d
                break
            end
        end
    end

    if not pick then
        if not req.noDruidWarned then
            req.noDruidWarned = true
            local soonest
            for _, d in ipairs(order) do
                if not soonest or d.cd < soonest then soonest = d.cd end
            end
            if req.target == NS.PlayerName() then
                local what = (NS.Provider(req.kind or "INNERVATE") or {}).short or "innervate"
                NS.Print(soonest and ("no " .. what .. " up - next one in " .. NS.TimeStr(soonest))
                                  or ("nobody available for " .. what .. "."))
            end
        end
        return
    end

    req.attempt     = req.attempt + 1
    req.assigned    = pick.name
    req.assignedAt  = NS.Now()
    req.claimedAt   = nil
    skipList[pick.name] = true

    NS.Comm:Send("ASSIGN", req.id, req.assigned, req.attempt)
    self:OnAssigned(req)

    -- non-addon provider: tell them in plain words
    if not NS.Comm:HasAddon(pick.name) then
        NS.Whisper:PingDruid(req, pick.name, self:HasAlternative(req, pick.name))
    end
    -- keep the requester in the loop when they have no addon
    if not req.hasAddon then
        NS.Whisper:TellRequester(req, pick.name)
    end
end

function Queue:OnAssigned(req)
    if NS.UI then NS.UI:Refresh(); NS.UI:Alert(req) end
end

-- Handing a request from one druid to the next is the one moment two buttons
-- could be live at once. So it is a two-step handover with a blackout in
-- between: the old druid is told to release (their button hides immediately and
-- they answer RELEASED), and only then is the next druid lit up. If the old
-- druid does not answer within the blackout window we move on anyway.
-- is there anyone else who could take this request right now?
function Queue:HasAlternative(req, exclude)
    for _, d in ipairs(NS.Tracker:AssignOrder(req.target, req.kind or "INNERVATE")) do
        if d.cd <= 0 and d.name ~= exclude and not self:DruidBusy(d.name, req.id) then
            return true, d.name
        end
    end
    return false
end

function Queue:Escalate(req, reason, prefer)
    if req.owner ~= NS.PlayerName() or req.state ~= "pending" then return end
    if req.releasing then return end
    local previous = req.assigned

    -- Nobody else is up: leave it where it is instead of churning. Releasing
    -- and re-assigning the same person would whisper them a stand-down and a
    -- fresh ping every few seconds for no reason.
    if previous and not prefer and not self:HasAlternative(req, previous) then
        req.assignedAt = NS.Now()
        req.claimedAt  = nil
        NS.Debug("no alternative for", req.id, "- leaving it with", previous)
        return
    end
    NS.Debug("escalating", req.id, reason or "")

    req.prevAssigned = previous
    req.prefer       = prefer
    req.assigned     = nil

    if previous then
        req.releasing   = true
        req.releasedOk  = false
        req.releaseTill = NS.Now() + 1.2
        NS.Comm:Send("RELEASE", req.id, previous)
        if not NS.Comm:HasAddon(previous) then
            NS.Whisper:StandDown(req, previous, "someone else is on it")
            req.releaseTill = NS.Now() + 0.3   -- no addon = no button to release
        end
        if NS.UI then NS.UI:Refresh() end
    else
        self:Assign(req, nil, prefer)
    end
end

-- called from Tick once the blackout is over
function Queue:FinishHandover(req)
    req.releasing = false
    local prefer, previous = req.prefer, req.prevAssigned
    req.prefer = nil

    -- A CLAIM can land inside the blackout and set req.assigned behind our back.
    -- Announce whatever we end up with: mirrors clear their own `releasing` only
    -- when an ASSIGN arrives, so staying quiet here leaves the whole raid dark.
    local claimed = req.assigned
    if not claimed then self:Assign(req, nil, prefer) end
    if not req.assigned and previous and not self:DruidBusy(previous, req.id) then
        req.assigned, req.assignedAt = previous, NS.Now()   -- nobody else: give it back
    end
    if req.assigned and (claimed or req.assigned == previous) then
        NS.Comm:Send("ASSIGN", req.id, req.assigned, req.attempt)
    end
    if NS.UI then NS.UI:Refresh() end
end

-- a druid volunteered for a request that is not theirs
function Queue:TakeOver(req, druid)
    if req.owner ~= NS.PlayerName() or req.state ~= "pending" then return end
    if req.assigned == druid then return end
    if NS.Tracker:CooldownLeft(druid) > 0 then return end
    self:Escalate(req, "volunteer", druid)
end

function Queue:AskToTake(req)
    if not req or req.state ~= "pending" then return end
    if req.assigned == NS.PlayerName() then return end
    if NS.SpellCooldown() > 0 then
        NS.Print("your innervate is not up.")
        return
    end
    if req.owner == NS.PlayerName() then
        self:TakeOver(req, NS.PlayerName())
    else
        NS.Comm:Send("TAKE", req.id, NS.PlayerName())
    end
end

--------------------------------------------------------------------
-- resolution
--------------------------------------------------------------------

function Queue:Resolve(req, state, druid)
    if not req or req.state ~= "pending" then return end
    req.state    = state
    req.resolved = NS.Now()
    req.by       = druid
    if req.owner == NS.PlayerName() then
        NS.Comm:Send(state == "done" and "DONE" or "CANCEL", req.id, druid or "")
    end
    NS.Whisper:CloseOut(req, druid)
    if req.target == NS.PlayerName() and state == "done" and druid then
        local p = NS.Provider(req.kind or "INNERVATE") or NS.Provider("INNERVATE")
        NS.Print(p.name .. " from " .. druid .. ".")
    end
    NS.After(3, function() Queue.requests[req.id] = nil; if NS.UI then NS.UI:Refresh() end end)
    if NS.UI then NS.UI:Refresh() end
end

function Queue:Cancel(req, reason)
    if not req then return end
    self:Resolve(req, "cancelled", nil)
    NS.Debug("cancelled", req.id, reason or "")
end

-- cancels every request I own for myself; returns how many
function Queue:CancelMine(reason)
    local n = 0
    for _, r in pairs(self.requests) do
        if r.state == "pending" and r.target == NS.PlayerName() then
            self:Cancel(r, reason or "manual")
            n = n + 1
        end
    end
    return n
end

function Queue:OnInnervateLanded(caster, target)
    local req = self:ActiveForKind(target, "INNERVATE")
    if req then self:Resolve(req, "done", caster) end
end

-- a totem is down: it covers everyone in that shaman's subgroup
function Queue:OnTideLanded(caster)
    for _, r in pairs(self.requests) do
        if r.state == "pending" and r.kind == "TIDE" and NS.SameGroup(caster, r.target) then
            self:Resolve(r, "done", caster)
        end
    end
end

-- I just cast one of my own provider spells
function Queue:OnSelfCast(kind, target)
    if type(kind) ~= "string" then kind, target = "INNERVATE", kind end
    local me = NS.PlayerName()
    for _, r in pairs(self.requests) do
        if r.state == "pending" and r.assigned == me and (r.kind or "INNERVATE") == kind then
            local match = (kind == "TIDE") or (not target) or (r.target == target)
            if match then
                NS.Comm:Send("CLAIM", r.id, me)
                if r.owner == me then self:Resolve(r, "done", me) end
                return
            end
        end
    end
end

function Queue:ClaimAssigned(req)
    if not req then return end
    req.claimedAt = NS.Now()
    NS.Comm:Send("CLAIM", req.id, NS.PlayerName())
    if NS.UI then NS.UI:Refresh() end
end

-- a tide request outlives its original asker if somebody else was riding it
function Queue:PromoteRider(req)
    if req.kind ~= "TIDE" or not req.riders then return false end
    if req.owner ~= NS.PlayerName() then return false end
    for rider in pairs(req.riders) do
        local u = NS.UnitOf(rider)
        if u and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost(u)) then
            req.riders[rider] = nil
            req.target = rider
            req.mana   = NS.ManaPct(u)
            req.class  = NS.ClassOf(rider)
            req.group  = NS.Subgroup(rider)
            NS.Comm:Send("REQ", req.id, req.owner, req.target, req.class or "", req.mana or "", req.kind)
            NS.Debug("tide request promoted to", rider)
            return true
        end
    end
    return false
end

--------------------------------------------------------------------
-- ticker
--------------------------------------------------------------------

function Queue:Tick()
    local cfg = defaults()
    local now = NS.Now()
    for id, r in pairs(self.requests) do
        if r.demo then
            -- pretend request: no roster, no owner, no expiry
        elseif r.state == "pending" then
            -- Every client, not just the owner, drops a request that has clearly
            -- died: the owner may have disconnected or left mid-request, and a
            -- mirror that never expires means a button glowing all raid.
            local ownerUnit = NS.UnitOf(r.owner)
            local ownerGone = not ownerUnit
                or (UnitIsConnected and ownerUnit and not UnitIsConnected(ownerUnit))
            if ownerGone then
                r.ownerGoneSince = r.ownerGoneSince or now
            else
                r.ownerGoneSince = nil
            end
            -- a zone-in or a lag spike reads as "gone" for a second or two, so
            -- only drop it once they have really been away
            local goneLong = r.ownerGoneSince and (now - r.ownerGoneSince) > 8
            if goneLong or (now - r.created) > (cfg.expire + 15) then
                r.state, r.resolved = "cancelled", now
                NS.Whisper:CloseOut(r, nil)
                if NS.UI then NS.UI:Refresh() end
            end
        end
        if r.state == "pending" and not r.demo then
            -- requester got mana some other way / died / left
            local unit = NS.UnitOf(r.target)
            if r.riders then
                for rider in pairs(r.riders) do
                    if not NS.UnitOf(rider) then r.riders[rider] = nil end
                end
            end
            if r.owner ~= NS.PlayerName() then
                -- mirrors never cancel: the owner will retarget or cancel it
            elseif not unit then
                if not self:PromoteRider(r) then self:Cancel(r, "left group") end
            elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
                if not self:PromoteRider(r) then self:Cancel(r, "dead") end
            end
            if r.state == "pending" and r.owner == NS.PlayerName() then
                local m = NS.ManaPct(unit)
                if m then r.mana = m end
                -- a tide request stays alive while ANY rider in the group is low
                if r.kind == "TIDE" and r.riders then
                    for rider in pairs(r.riders) do
                        local ru = NS.UnitOf(rider)
                        local rm = ru and NS.ManaPct(ru)
                        if rm and (not m or rm < m) then m = rm end
                    end
                end
                if r.releasing then
                    if r.releasedOk or now >= (r.releaseTill or 0) then self:FinishHandover(r) end
                elseif m and m >= cfg.cancelMana
                       and m >= ((r.startMana or 0) + 15) then
                    -- they have to have actually gained mana since asking
                    self:Cancel(r, "mana recovered")
                elseif (now - r.created) > cfg.expire then
                    self:Cancel(r, "expired")
                elseif r.assigned then
                    if (now - (r.lastEcho or 0)) > 10 then
                        r.lastEcho = now
                        NS.Comm:Send("REQ", r.id, r.owner, r.target, r.class or "", r.mana or "", r.kind)
                        NS.Comm:Send("ASSIGN", r.id, r.assigned, r.attempt)
                    end
                    -- the druid on the hook died or dropped: AssignOrder skips
                    -- them, so HasAlternative says "nobody else" and the request
                    -- would sit on a corpse until it expired
                    local du = NS.UnitOf(r.assigned)
                    local dgone = (not du)
                        or (UnitIsDeadOrGhost and UnitIsDeadOrGhost(du))
                        or (UnitIsConnected and not UnitIsConnected(du))
                    if dgone then
                        r.assigned, r.claimedAt = nil, nil
                        r.assignedAt = now
                        self:Assign(r)
                    end
                    local hold = r.claimedAt and cfg.claimHold or cfg.escalate
                    local since = now - (r.claimedAt or r.assignedAt or now)
                    if since > hold then self:Escalate(r, "no response") end
                elseif (now - (r.lastTry or 0)) > 2 then
                    r.lastTry = now
                    self:Assign(r)     -- nobody was free earlier, keep trying
                end
            end
        elseif r.resolved and (now - r.resolved) > 5 then
            self.requests[id] = nil
        end
    end
end

--------------------------------------------------------------------
-- incoming comm
--------------------------------------------------------------------

local Comm = NS.Comm

Comm:Register("REQ", function(sender, id, owner, target, class, mana, kind)
    if not id or not target then return end
    kind = (kind ~= "" and kind) or "INNERVATE"
    local mine = Queue.requests[id]
    if mine then
        -- the owner re-sent it: a tide request can change target when its
        -- original asker leaves and a group mate was riding along
        if NS.Short(sender) == mine.owner and target and NS.Short(target) ~= mine.target then
            mine.target = NS.Short(target)
            mine.mana   = tonumber(mana or "") or mine.mana
            mine.group  = NS.Subgroup(mine.target)
            if NS.UI then NS.UI:Refresh() end
        end
        return
    end
    -- duplicate ownership for the same non-addon requester: lowest name wins
    -- Two clients can both take ownership for the same non-addon player. Break
    -- the tie the same way everywhere - lowest owner name wins - or third
    -- parties end up mirroring different requests and one of them is orphaned.
    local dupe = Queue:ActiveForKind(target, kind)
    if dupe then
        local incoming = NS.Short(owner)
        if incoming < dupe.owner then
            if dupe.owner == NS.PlayerName() then
                NS.Comm:Send("CANCEL", dupe.id, "duplicate")
            end
            dupe.state, dupe.resolved = "cancelled", NS.Now()
            NS.Whisper:CloseOut(dupe, nil)      -- stand down anyone already pinged
            Queue.requests[dupe.id] = nil
        else
            return
        end
    end
    Queue.requests[id] = {
        id = id, kind = kind, target = NS.Short(target), owner = NS.Short(owner),
        class = (class ~= "" and class or nil), mana = tonumber(mana or "") or nil,
        created = NS.Now(), state = "pending", attempt = 0, hasAddon = true,
        group = NS.Subgroup(target), riders = {}, whispered = {}, mirror = true,
    }
    if NS.UI then NS.UI:Refresh() end
end)

-- somebody else in the group wants the same totem
Comm:Register("RIDE", function(sender, id, who, mana)
    local r = Queue.requests[id]
    if not r or r.state ~= "pending" then return end
    r.riders = r.riders or {}
    r.riders[NS.Short(who or sender)] = tonumber(mana or "") or 0
    if NS.UI then NS.UI:Refresh() end
end)

Comm:Register("ASSIGN", function(sender, id, druid, attempt)
    local r = Queue.requests[id]
    if not r or r.state ~= "pending" then return end
    if NS.Short(sender) ~= r.owner then return end
    if not druid or druid == "" then return end   -- a short message must not unassign
    r.assigned   = NS.Short(druid)
    r.assignedAt = NS.Now()
    r.attempt    = tonumber(attempt or "") or r.attempt
    r.claimedAt  = nil
    r.releasing  = false
    Queue:OnAssigned(r)
end)

-- owner -> raid: "whoever had this, drop it now"
Comm:Register("RELEASE", function(sender, id, druid)
    local r = Queue.requests[id]
    if not r or r.state ~= "pending" then return end
    if NS.Short(sender) ~= r.owner then return end
    if not druid or druid == "" then return end
    r.prevAssigned = NS.Short(druid) or r.assigned
    r.assigned  = nil
    r.releasing = true
    if NS.UI then NS.UI:DoRefresh() end          -- hide my button immediately, no delay
    if NS.Short(druid) == NS.PlayerName() then
        NS.Comm:Send("RELEASED", id, NS.PlayerName())
    end
end)

Comm:Register("RELEASED", function(sender, id, druid)
    local r = Queue.requests[id]
    if not r or r.owner ~= NS.PlayerName() then return end
    if NS.Short(druid or sender) ~= r.prevAssigned then return end
    r.releasedOk = true
end)

-- a druid with innervate up wants this one
Comm:Register("TAKE", function(sender, id, druid)
    local r = Queue.requests[id]
    if not r or r.owner ~= NS.PlayerName() then return end
    Queue:TakeOver(r, NS.Short(druid or sender))
end)

Comm:Register("CLAIM", function(sender, id, druid)
    local r = Queue.requests[id]
    if not r or r.state ~= "pending" then return end
    local who = NS.Short(druid or sender)
    -- only the sender may claim for themselves, and only if they are the one on
    -- the hook (or the request is mid-handover and they still hold the button)
    if who ~= NS.Short(sender) then return end
    if r.assigned and r.assigned ~= who and not r.releasing then return end
    -- and with no assignment at all (a fresh mirror, or mid-handover) only the
    -- people this request has actually been handed to may claim it
    if not r.assigned and who ~= r.prevAssigned and r.attempt > 0 then return end
    r.claimedAt = NS.Now()
    r.assigned  = who
    r.releasing = false
    if NS.UI then NS.UI:Refresh() end
end)

Comm:Register("DONE", function(sender, id, druid)
    local r = Queue.requests[id]
    if not r then return end
    -- only the owner or the druid who was actually on the hook. Request ids go
    -- out on the raid channel, so without this any client can close anyone's.
    local who = NS.Short(sender)
    if who ~= r.owner and who ~= r.assigned and who ~= r.prevAssigned then return end
    r.state, r.resolved, r.by = "done", NS.Now(), NS.Short(druid or sender)
    NS.Whisper:CloseOut(r, r.by)
    if NS.UI then NS.UI:Refresh() end
end)

Comm:Register("CANCEL", function(sender, id, reason)
    local r = Queue.requests[id]
    if not r then return end
    if NS.Short(sender) ~= r.owner then return end   -- the owner's call alone
    r.state, r.resolved = "cancelled", NS.Now()
    NS.Whisper:CloseOut(r, nil)
    if NS.UI then NS.UI:Refresh() end
end)
