-- BiS Innervate :: Comm.lua
-- Addon-to-addon channel. Pipe separated:  PROTO|CMD|a1|a2|...
--
--   HELLO |ver|kind|cdLeft|mana|group     who is running the addon and what they can give
--   STATE |kind|cdLeft|mana|combat|group  provider state broadcast (kind: INNERVATE / TIDE)
--   REQ   |reqId|owner|target|class|mana|kind  a request exists (owner manages it)
--   ASSIGN|reqId|druid|attempt            owner tells raid which druid is up
--   CLAIM |reqId|druid                    druid says "mine, casting"
--   DONE  |reqId|druid                    innervate landed
--   CANCEL|reqId|reason                   request is over (got mana, died, timeout, manual)

local ADDON, NS = ...

local Comm = {}
NS.Comm = Comm

Comm.handlers = {}
Comm.users    = {}      -- name -> { version, isDruid, seen }

local SEP = "|"

local function split(msg)
    local out, i = {}, 1
    for piece in string.gmatch(msg .. SEP, "([^" .. SEP .. "]*)" .. "%" .. SEP) do
        out[i] = piece
        i = i + 1
    end
    return out
end
Comm._split = split

function Comm:Register(cmd, fn)
    self.handlers[cmd] = fn
end

function Comm:Send(cmd, ...)
    -- the demo pretends this client is a druid; that pretence must not reach
    -- the raid, but a real call or claim made while it runs still must
    if NS.demoMode and (cmd == "HELLO" or cmd == "STATE") then return false end
    local parts = { NS.PROTOCOL, cmd }
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v == nil then v = "" elseif type(v) == "boolean" then v = v and "1" or "0" end
        parts[#parts + 1] = tostring(v)
    end
    local msg = table.concat(parts, SEP)
    -- the client silently drops anything over 255 bytes, and the sender never
    -- hears about it. Say so rather than losing the message.
    if #msg > 250 then
        NS.Debug("message too long, not sent:", cmd, #msg)
        return false
    end
    local chan = NS.GroupChannel()
    if not chan then return false end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(NS.PREFIX, msg, chan)
    elseif SendAddonMessage then
        SendAddonMessage(NS.PREFIX, msg, chan)
    else
        return false
    end
    NS.Debug("send", msg)
    return true
end

function Comm:OnMessage(prefix, msg, channel, sender)
    if prefix ~= NS.PREFIX or not msg then return end
    sender = NS.Short(sender)
    if not sender then return end
    local p = split(msg)
    local proto = tonumber(p[1] or "")
    local cmd = p[2]
    if not cmd then return end
    -- only our own protocol, and only from the group: a 2.x client's REQ or
    -- ASSIGN parsed as 3.x would corrupt a call, and a realm whisper from a
    -- stranger must not be able to touch anything
    if proto ~= NS.PROTOCOL then
        if proto and proto > NS.PROTOCOL and not self._warnedProto then
            self._warnedProto = true
            NS.Print("someone in the raid runs a newer version - update BiS Innervate.")
        elseif proto and proto < NS.PROTOCOL and not self._warnedOld then
            self._warnedOld = true
            NS.Print(sender .. " runs an old BiS Innervate (2.x) - it cannot see 3.0 calls.")
        end
        return
    end
    if channel and channel ~= "RAID" and channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" then
        return
    end
    if sender ~= NS.PlayerName() and not NS.UnitOf(sender) then return end
    -- everyone who talks to us is an addon user, whether or not we caught their
    -- HELLO (a STATE broadcast alone used to leave them looking addon-less, and
    -- they got whispered like a stranger)
    local u = self.users[sender]
    local isNew = (u == nil)
    u = u or {}
    u.seen  = NS.Now()
    u.addon = true
    self.users[sender] = u
    -- a new addon user needs a face on everyone's grid: rebind (out of combat;
    -- Bind refuses otherwise and the fight's end does it)
    if isNew and NS.Window and not self._rebind then
        self._rebind = true
        if not NS.After(0.3, function() Comm._rebind = false; NS.Tracker:UpdateRoster(); NS.Window:Bind() end) then
            self._rebind = false
            NS.Tracker:UpdateRoster(); NS.Window:Bind()
        end
    end

    local fn = self.handlers[cmd]
    if fn then
        local args = {}
        for i = 3, #p do args[i - 2] = p[i] end
        local ok, err = pcall(fn, sender, unpack(args))
        if not ok then NS.Debug("handler error", cmd, err) end
    end
end

function Comm:HasAddon(name)
    name = NS.Short(name)
    if name == NS.PlayerName() then return true end
    local u = self.users[name]
    return (u and (u.addon or u.version)) and true or false
end

function Comm:Count()
    local n = 0
    for _ in pairs(self.users) do n = n + 1 end
    return n
end

-- HELLO carries how many addon users this client knows about, so a client
-- that lost its table (a reload, a zone-in) is recognisable and gets answered
-- even inside the normal throttle
-- "TIDE,LUST" and "0,45": everything this client can hand out and where each
-- cooldown stands. One player is several providers now.
function Comm:KindsBlob()
    local kinds, cds = {}, {}
    for _, kind in ipairs(NS.MyKinds()) do
        -- drums carry which types: "DRUMS=BWR"
        kinds[#kinds + 1] = (kind == "DRUMS") and ("DRUMS=" .. NS.MyDrumLetters()) or kind
        cds[#cds + 1] = NS.Round(NS.SpellCooldownFor(kind))
    end
    return table.concat(kinds, ","), table.concat(cds, ",")
end

-- apply a kinds blob from HELLO or STATE to the tracker; kinds the sender no
-- longer lists (sold their drums, respecced) are forgotten
function Comm:ApplyKinds(sender, kindsBlob, cdsBlob, mana, group)
    local seen = {}
    local cds = {}
    for cd in string.gmatch(cdsBlob or "", "([^,]+)") do cds[#cds + 1] = tonumber(cd) or 0 end
    local i = 0
    for entry in string.gmatch(kindsBlob or "", "([^,]+)") do
        i = i + 1
        local kind, extra = string.match(entry, "^(%u+)=?(.*)$")
        if kind and NS.PROVIDERS[kind] then
            seen[kind] = true
            NS.Tracker:SetState(sender, kind, cds[i] or 0, mana, nil, true, group, extra)
        end
    end
    for _, kind in ipairs(NS.KINDS) do
        if not seen[kind] then NS.Tracker:Forget(sender, kind) end
    end
end

function Comm:Hello()
    local kinds, cds = self:KindsBlob()
    self:Send("HELLO", NS.VERSION, kinds, cds,
              NS.ManaPct("player") or "", NS.Subgroup(NS.PlayerName()) or 1, self:Count())
end

Comm:Register("HELLO", function(sender, ver, kinds, cds, mana, group, known)
    local u = Comm.users[sender] or {}
    local isNew = not u.version
    u.version = ver
    u.kinds   = kinds
    u.seen    = NS.Now()
    Comm.users[sender] = u
    Comm:ApplyKinds(sender, kinds, cds, tonumber(mana), tonumber(group or ""))
    -- Answer EVERY hello, throttled - not only a newcomer's. A client that lost
    -- its user table (a zone-in blip, a reload) re-says hello and needs the
    -- whole raid to answer, or the mages never come back onto its grid.
    local theyKnow = tonumber(known or "") or 0
    local short = theyKnow < (Comm:Count() - 1)          -- they know fewer than we do: they lost it
    local throttled = (NS.Now() - (Comm._lastHelloBack or 0)) <= 5
    if not Comm._helloBack and (short or not throttled) then
        Comm._helloBack = true
        NS.After(1 + math.random() * 2, function()
            Comm._helloBack = false
            Comm._lastHelloBack = NS.Now()
            Comm:Hello()
        end)
    end
end)

Comm:Register("STATE", function(sender, kinds, cds, mana, combat, group)
    Comm:ApplyKinds(sender, kinds, cds, tonumber(mana), tonumber(group or ""))
end)

function Comm:PurgeAbsent()
    for name in pairs(self.users) do
        if not NS.UnitOf(name) then self.users[name] = nil end
    end
end
