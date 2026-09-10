-- BiS Innervate :: Whisper.lua
-- The bridge to everyone who does NOT run the addon.
--   out: a non-addon druid gets a plain-English "you're up" whisper, and a
--        "stand down" the moment somebody else covers it.
--   in : a non-addon mage whispering "inn plz" turns into a real queue entry.

local ADDON, NS = ...

local Whisper = {}
NS.Whisper = Whisper

local TAG = "<Innervate>"

Whisper._last = {}     -- name -> time

local function canSend(name)
    local t = Whisper._last[name] or 0
    if (NS.Now() - t) < 2 then return false end
    Whisper._last[name] = NS.Now()
    return true
end

function Whisper:Say(name, msg, urgent)
    if NS.demoMode then return end              -- never whisper anyone from a demo
    if not name or name == NS.PlayerName() then return end
    if NS.db and NS.db.whispers == false then return end
    if not canSend(name) then
        if not urgent or urgent == "retry" then return end
        -- a stand-down is worth waiting for; dropping it costs a cooldown.
        -- One retry only, so this can never bounce forever.
        NS.After(2.1, function() Whisper:Say(name, msg, "retry") end)
        return
    end
    if SendChatMessage then SendChatMessage(TAG .. " " .. msg, "WHISPER", nil, name) end
    NS.Debug("whisper ->", name, msg)
end

local function manaText(req)
    if req.mana then return string.format(" (%d%% mana)", req.mana) end
    return ""
end

-- tell a non-addon provider they are the one.  hasAlt = somebody else could
-- take it if they ignore this, which changes both the wording and whether we
-- will ever bother them again for this request.
function Whisper:PingDruid(req, druid, hasAlt)
    req.whispered = req.whispered or {}
    req.pingedAt  = req.pingedAt or {}
    -- Not "one whisper per person, ever". Escalation legitimately comes back
    -- round to the first druid when there are only two of them, and a hard lock
    -- meant nobody was told anything for the rest of the request - the request
    -- bounced between two silent druids until it expired. One ping per person
    -- per escalation cycle instead.
    local gap  = ((NS.db and NS.db.escalate) or 7) * 2
    local last = req.pingedAt[druid]
    if last and (NS.Now() - last) < gap then return end
    req.pingedAt[druid]  = NS.Now()
    req.whispered[druid] = true
    local p = NS.Provider(req.kind or "INNERVATE") or NS.Provider("INNERVATE")
    local extra = (req.attempt and req.attempt > 1) and " (no answer from the first one)" or ""
    local tail = hasAlt
        and string.format("cast it or ignore, I'll pass it on in %ds.", (NS.db and NS.db.escalate) or 7)
        or  "you are the only one up - cast it or ignore."

    if req.kind == "TIDE" then
        local n = 1
        for _ in pairs(req.riders or {}) do n = n + 1 end
        self:Say(druid, string.format("group %s needs %s - %s%s%s. %s",
            tostring(req.group or "?"), p.name, req.target, manaText(req),
            n > 1 and (" and " .. (n - 1) .. " more") or "", tail))
        return
    end

    self:Say(druid, string.format("%s needs %s%s. You are the only one asked%s - %s",
        req.target, p.name, manaText(req), extra, tail))
end

-- tell a druid to stop: somebody else has it
function Whisper:StandDown(req, druid, why)
    if not (req.whispered and req.whispered[druid]) then return end
    req.whispered[druid] = nil
    self:Say(druid, string.format("stand down on %s - %s.", req.target, why or "handled"), true)
end

-- keep a non-addon requester informed
function Whisper:TellRequester(req, druid)
    if req.hasAddon then return end
    if req.target == NS.PlayerName() then return end
    -- only when the answer actually changes, and never more than three times:
    -- a request that escalates for 40s used to send one of these per hop
    if req.toldRequester == druid then return end
    req.toldCount = (req.toldCount or 0) + 1
    if req.toldCount > 3 then return end
    req.toldRequester = druid
    local p = NS.Provider(req.kind or "INNERVATE") or NS.Provider("INNERVATE")
    self:Say(req.target, string.format("%s has your %s - do not ask in voice, it is assigned.", druid, p.name))
end

-- request is over: release everyone we pinged
function Whisper:CloseOut(req, druid)
    if not req or not req.whispered then return end
    for name in pairs(req.whispered) do
        if name ~= druid then
            self:Say(name, string.format("%s is handled%s - stand down.", req.target,
                druid and (" (" .. druid .. " got it)") or ""), true)
        end
    end
    req.whispered = {}
end

--------------------------------------------------------------------
-- incoming
--------------------------------------------------------------------

-- Matched on word boundaries. As plain substrings, "inn" turned "beginning
-- now" into an innervate request and "oom" turned "zoom in on the boss" into
-- one, which is where a good share of the whisper spam came from.
local KEYWORDS = {
    INNERVATE = { "innerv%a*", "innv", "inerv", "inv8", "inn" },
    TIDE      = { "mana ?tide", "tide", "mt" },
}

local function hasWord(m, word)
    return string.find(m, "%f[%a]" .. word .. "%f[%A]") ~= nil
end

-- returns the kind asked for, or nil
function Whisper:LooksLikeRequest(msg)
    if not msg then return nil end
    local m = string.lower(msg)
    if string.find(m, "^" .. string.lower(TAG), 1) then return nil end   -- our own traffic
    if string.find(m, "stand down", 1, true) then return nil end
    -- a real request is short; a sentence that happens to contain the word is not
    if #m > 60 then return nil end
    for _, k in ipairs(KEYWORDS.TIDE) do
        if hasWord(m, k) then return "TIDE" end
    end
    for _, k in ipairs(KEYWORDS.INNERVATE) do
        if hasWord(m, k) then return "INNERVATE" end
    end
    if (NS.db and NS.db.acceptOOM ~= false) and hasWord(m, "oom") then return "ANY" end
    return nil
end

function Whisper:OnWhisper(msg, sender)
    sender = NS.Short(sender)
    local myKind = NS.MyKind()
    if not sender or not myKind then return end
    -- a demo mutes every outbound message, so taking this request would swallow
    -- it: leave it for a druid whose client can actually answer
    if NS.demoMode then return end
    if NS.Comm:HasAddon(sender) then return end        -- their addon speaks for them
    local asked = self:LooksLikeRequest(msg)
    if not asked then return end
    -- I can only provide my own thing; "oom" means whatever I have
    if asked ~= "ANY" and asked ~= myKind then return end
    local unit = NS.UnitOf(sender)
    if not unit then return end                        -- not in my group
    if myKind == "TIDE" and not NS.SameGroup(sender, NS.PlayerName()) then return end
    local _, class = UnitClass(unit)
    if not NS.IsRequesterClass(class) then return end
    local mana = NS.ManaPct(unit)
    NS.Debug("whisper request from", sender, myKind)
    NS.Queue:RequestForOther(sender, class, mana, myKind)
end
