-- LibBiSComm-1.0
-- The shared BiS addon channel. EMBEDDED in every BiS addon, not installed as
-- one: a client with a single BiS addon carries the whole layer, which is the
-- entire point. Highest version present wins and upgrades in place.
--
--   Wire format:  PROTO|MOD|CMD|a1|a2|...
--
-- Every field is escaped on the wire (minor 6) so a payload may carry "|" - an
-- item link does: "\1" -> "\1\1", "|" -> "\1\2", undone on receipt. A field
-- with neither byte is sent as-is, so CORE and SUMMON traffic is byte-identical
-- to minor 5 and older copies still read it.
--
-- MOD is what lets unrelated addons share one prefix. An unknown MOD or CMD is
-- ignored in silence, so a client running an older or newer BiS addon is never
-- half-understood -- the same additive rule that let Rez fold into Innervate.
--
-- CORE is deliberately three commands. It carries only what a client knows
-- about ITSELF and nobody else can see:
--
--   HI    |libMinor|addonsBlob|known     who is here, running what
--   ASK   |what                          somebody wants WHERE (summoner)
--   WHERE |in|type|instName|zone|x|y|map am I inside an instance, and where
--   SUM   |state|summoner|area|left      OFFER / OK / NO on a summon offer
--
-- House rules, in the lib so they cannot drift addon to addon:
--   * draws nothing, prints nothing (one /biscomm for status and the off switch;
--     /bis belongs to LoonBestInSlot on the raid's clients - minor 4 gave it back)
--   * no periodic chatter: WHERE pushes on a real change, otherwise it answers
--   * every host callback is pcall'd -- a lib fault cannot kill the addon
--   * off means silent AND deaf

local MAJOR, MINOR = "LibBiSComm-1.0", 6

local lib = _G.LibBiSComm
if lib and (lib.MINOR or 0) >= MINOR then return end   -- an equal or newer copy won
lib = lib or {}
_G.LibBiSComm = lib
lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Upgrading in place: everything the old copy learned survives. Wiping these
-- on a reload-in-place would drop the raid off every grid at once.
lib.peers     = lib.peers     or {}    -- name -> peer table
lib.handlers  = lib.handlers  or {}    -- mod -> cmd -> fn
lib.callbacks = lib.callbacks or {}    -- event -> { fn, ... }
lib.addons    = lib.addons    or {}    -- name -> version, what this client runs
lib.guildMods = lib.guildMods or {}    -- mod -> true: may ride the GUILD channel (minor 6)
if lib.enabled == nil then lib.enabled = true end

lib.PREFIX = "BiS"
lib.PROTO  = 1

local PREFIX, PROTO, SEP = lib.PREFIX, lib.PROTO, "|"

local ANSWER_MIN, ANSWER_JITTER = 1, 2   -- 1-3s: 25 clients must not answer as one
local HI_THROTTLE    = 5
local WHERE_THROTTLE = 3
local ASK_COALESCE   = 3
local OFFER_FALLBACK = 120               -- summon offer lifetime if the API is quiet

--------------------------------------------------------------------
-- small helpers (self-contained: the lib must work in an addon that has none)
--------------------------------------------------------------------

local function Now()
    if GetTime then return GetTime() end
    return 0
end

local function After(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn); return true end
    return false
end

local function Short(name)
    if not name then return nil end
    return string.match(name, "^([^%-]+)") or name
end
lib.Short = Short

local function PlayerName()
    return Short(UnitName and UnitName("player") or nil)
end

local function InGroup()
    if IsInRaid and IsInRaid() then return true end
    if IsInGroup and IsInGroup() then return true end
    return false
end

-- A dungeon-finder group silently DROPS "RAID"/"PARTY" addon messages. Summon
-- work happens at instance doorsteps, which is exactly where this bites.
local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end
lib.GroupChannel = GroupChannel

local function ForEachMember(cb)
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do
            local unit = "raid" .. i
            if UnitExists and UnitExists(unit) then cb(unit, Short(UnitName(unit))) end
        end
    else
        cb("player", PlayerName())
        for i = 1, math.max(0, n - 1) do
            local unit = "party" .. i
            if UnitExists and UnitExists(unit) then cb(unit, Short(UnitName(unit))) end
        end
    end
end

local function UnitOf(name)
    name = Short(name)
    if not name then return nil end
    if name == PlayerName() then return "player" end
    local found
    ForEachMember(function(unit, n) if not found and n == name then found = unit end end)
    return found
end
lib.UnitOf = UnitOf

-- WindfuryComm++ shipped `tonumber(string.gsub(v, ".", "0"))`: "." matches every
-- character, so "2.1.3" became 0 for everybody and its update notice has never
-- once fired. Parse the numbers out; never pattern-mangle a version.
function lib.VersionCmp(a, b)
    local function parts(v)
        local t = {}
        for n in string.gmatch(tostring(v or ""), "(%d+)") do t[#t + 1] = tonumber(n) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

function lib.VersionGT(a, b) return lib.VersionCmp(a, b) > 0 end

-- MINOR 6: "|" inside a field. SEP is "|", and an item link is full of them, so a
-- field is escaped before it is joined and unescaped after the split. Two bytes
-- for "|", not one: with "|" -> "\1" alone, a field "||" and a field "\1" would
-- both go out as "\1\1" and could never be told apart again.
local ESC, PIPE = "\1", "\2"

local function escape(s)
    if not string.find(s, "[\1|]") then return s end
    return (string.gsub(s, "[\1|]", function(ch)
        if ch == ESC then return ESC .. ESC end
        return ESC .. PIPE
    end))
end

local function unescape(s)
    if not string.find(s, ESC, 1, true) then return s end
    return (string.gsub(s, "\1(.)", function(ch)
        if ch == ESC then return ESC end
        if ch == PIPE then return SEP end
        return ch
    end))
end
lib._escape, lib._unescape = escape, unescape

local function split(msg)
    local out, i = {}, 1
    for piece in string.gmatch(msg .. SEP, "([^" .. SEP .. "]*)%" .. SEP) do
        out[i] = unescape(piece); i = i + 1
    end
    return out
end
lib._split = split

-- MINOR 6: guild membership for guard 3 on the GUILD channel. Rebuilt lazily after
-- GUILD_ROSTER_UPDATE; a name the roster does not list is refused, never guessed.
function lib:InGuild(name)
    name = Short(name)
    if not name then return false end
    if not (IsInGuild and IsInGuild()) then return false end
    if self._guildDirty ~= false or not self._guild then
        local roster = {}
        local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
        for i = 1, n do
            local member = GetGuildRosterInfo and GetGuildRosterInfo(i)
            if member then roster[Short(member)] = true end
        end
        self._guild, self._guildDirty = roster, false
    end
    return self._guild[name] == true
end

local function fire(event, ...)
    for _, fn in ipairs(lib.callbacks[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then lib._lastError = err end   -- a host bug must not stop the next host
    end
end

--------------------------------------------------------------------
-- peers
--------------------------------------------------------------------

local function peer(name)
    local p = lib.peers[name]
    if not p then
        p = { name = name, addons = {}, where = nil, summon = nil }
        lib.peers[name] = p
    end
    return p
end

function lib:Peer(name) return self.peers[Short(name or "")] end
function lib:Peers() return self.peers end

function lib:Count()
    local n = 0
    for _ in pairs(self.peers) do n = n + 1 end
    return n
end

-- Does this group member run any BiS addon? Everything downstream hangs off
-- this: a name that answers is fact, a name that does not is a guess, and the
-- two must never look alike in a UI.
function lib:HasLib(name)
    name = Short(name or "")
    if name == PlayerName() then return true end
    return self.peers[name] ~= nil
end

function lib:PurgeAbsent()
    for name in pairs(self.peers) do
        if not UnitOf(name) then self.peers[name] = nil end
    end
end

--------------------------------------------------------------------
-- registration by host addons
--------------------------------------------------------------------

function lib:RegisterAddon(name, version)
    if not name then return end
    self.addons[name] = tostring(version or "?")
end

function lib:RegisterHandler(mod, cmd, fn)
    self.handlers[mod] = self.handlers[mod] or {}
    self.handlers[mod][cmd] = fn
end

-- MINOR 6: a MOD that may ride the GUILD channel (BiSLoot's LOOT). CORE never can:
-- HI / WHERE / SUM are about the group, and a guild line must not plant a peer.
function lib:RegisterGuildMod(mod)
    if not mod or mod == "CORE" then return false end
    self.guildMods[mod] = true
    return true
end

-- events: "PEER" (name, peer) | "WHERE" (name, where) | "SUM" (name, summon)
function lib:RegisterCallback(event, fn)
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], fn)
end

function lib:Enabled() return self.enabled and true or false end

-- Off is silent AND deaf. A client that still listened while claiming to be off
-- would be the same lie as Innervate's closed window that kept a live drag strip.
function lib:SetEnabled(on)
    self.enabled = on and true or false
    if not self.enabled then
        self.peers = {}
        lib.peers = self.peers
    end
    return self.enabled
end

--------------------------------------------------------------------
-- send / receive
--------------------------------------------------------------------

local GROUP_CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }

-- The group: RAID / PARTY / INSTANCE_CHAT, whichever this client is in.
function lib:Send(mod, cmd, ...)
    return self:SendTo(nil, mod, cmd, ...)
end

-- MINOR 6: an explicit channel. nil = the group (as Send). "GUILD" only for a MOD
-- registered with RegisterGuildMod - the guild reaches four raids at once, which is
-- what BiSLoot's ledger sync needs and exactly what CORE must never do.
function lib:SendTo(channel, mod, cmd, ...)
    if not self.enabled then return false end
    if not mod or not cmd then return false end
    local chan
    if channel == nil then
        chan = GroupChannel()
        if not chan then return false end
    elseif channel == "GUILD" then
        if not self.guildMods[mod] then
            self._lastError = "not guild-scoped: " .. tostring(mod)
            return false
        end
        if not (IsInGuild and IsInGuild()) then return false end
        chan = "GUILD"
    elseif GROUP_CHANNELS[channel] then
        chan = channel
    else
        self._lastError = "channel not allowed: " .. tostring(channel)
        return false
    end
    local parts = { PROTO, escape(tostring(mod)), escape(tostring(cmd)) }
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v == nil then v = "" elseif type(v) == "boolean" then v = v and "1" or "0" end
        parts[#parts + 1] = escape(tostring(v))
    end
    local msg = table.concat(parts, SEP)
    -- The client drops anything past 255 bytes and never tells the sender. Say
    -- so instead of losing it silently. Counted AFTER escaping: that is what goes out.
    if #msg > 250 then
        self._lastError = "message too long: " .. mod .. "/" .. cmd .. " " .. #msg
        return false
    end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, chan)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, msg, chan)
    else
        return false
    end
    return true
end

function lib:OnMessage(prefix, msg, channel, sender)
    if not self.enabled then return end
    if prefix ~= PREFIX or not msg then return end
    sender = Short(sender)
    if not sender then return end

    local p = split(msg)
    local proto, mod, cmd = tonumber(p[1] or ""), p[2], p[3]
    if not mod or not cmd then return end

    -- Guard 1: our framing only. A newer client's message parsed as ours would
    -- corrupt state rather than be rejected.
    if proto ~= PROTO then
        if proto and proto > PROTO then self._sawNewer = true end
        return
    end
    -- Guard 2: group channels only - or GUILD for a guild-scoped MOD (minor 6). A
    -- whisper from a stranger must not be able to plant a position or a summon state,
    -- and neither may a guild line: CORE is never guild-scoped.
    local guild = (channel == "GUILD")
    if channel and not GROUP_CHANNELS[channel] and not guild then return end
    if guild and not self.guildMods[mod] then return end
    -- Guard 3: a sender we can actually see - in the group, or for GUILD in the
    -- guild roster (minor 6).
    if sender ~= PlayerName() then
        if guild then
            if not self:InGuild(sender) then return end
        elseif not UnitOf(sender) then
            return
        end
    end
    -- Guard 4: my own echo. The client hands every group addon message back to
    -- its sender too; taking it would make me my own peer (MINOR 2 did: a
    -- summoner at the stone counted himself twice - Arn, 8 Sep). What I know
    -- about myself lives in self.where / self.summon, never in peers.
    if sender == PlayerName() then return end

    -- A guild sender is not a group peer: grids and summon lists are about the
    -- group, and forty officers across four raids must not appear on them.
    if not guild then
        local isNew = (self.peers[sender] == nil)
        local pr = peer(sender)
        pr.seen = Now()
        if isNew then fire("PEER", sender, pr) end
    end

    local args = {}
    for i = 4, #p do args[i - 3] = p[i] end

    local core = self._core[cmd]
    if mod == "CORE" and core then
        local ok, err = pcall(core, sender, unpack(args))
        if not ok then self._lastError = err end
        return
    end
    -- Guard 4: unknown MOD or CMD is ignored, not guessed at.
    local h = self.handlers[mod] and self.handlers[mod][cmd]
    if h then
        local ok, err = pcall(h, sender, unpack(args))
        if not ok then self._lastError = err end
    end
end

--------------------------------------------------------------------
-- CORE: identity
--------------------------------------------------------------------

function lib:AddonsBlob()
    local out = {}
    for name, ver in pairs(self.addons) do out[#out + 1] = name .. "=" .. ver end
    table.sort(out)
    return table.concat(out, ",")
end

function lib:Hi()
    if not InGroup() then return false end
    return self:Send("CORE", "HI", self.MINOR, self:AddonsBlob(), self:Count())
end

lib._core = {}

lib._core.HI = function(sender, minor, blob, known)
    local pr = peer(sender)
    pr.libMinor = tonumber(minor or "") or 0
    pr.addons = {}
    for entry in string.gmatch(blob or "", "([^,]+)") do
        local n, v = string.match(entry, "^(.-)=(.*)$")
        if n then pr.addons[n] = v end
    end
    fire("PEER", sender, pr)

    -- Answer a HI only when the sender is SHORT: it knows fewer of us than
    -- there are (a reload, a fresh join, a lost HI). A client that knows
    -- everybody already needs no answer - answering every HI "once per 5 s"
    -- (minor 2) turned 8 people zoning into Karazhan into 30 HIs on a 25-man
    -- (raid25.lua). HI_THROTTLE still spaces my own answers.
    local theyKnow = tonumber(known or "") or 0
    local short = theyKnow < (lib:Count() - 1)
    if not lib._hiPending and short then
        lib._hiPending = true
        local send = function()
            lib._hiPending = false
            lib._lastHi = Now()
            lib:Hi()
        end
        -- jittered like every answer; if my last HI is inside the throttle the
        -- answer waits it out instead of being dropped (a reload right after a
        -- join lost 7 of 21 peers that way - raid25.lua)
        local delay = ANSWER_MIN + math.random() * ANSWER_JITTER
        local wait = HI_THROTTLE - (Now() - (lib._lastHi or 0))
        if wait > delay then delay = wait end
        if not After(delay, send) then send() end
    end
end

--------------------------------------------------------------------
-- CORE: where am I
--------------------------------------------------------------------

-- Everything here is about the SELF. UnitPosition on somebody else goes nil the
-- moment they are in another instance -- which is precisely the case a summoner
-- cares about -- while a client's own position is never unknown.
function lib:MyWhere()
    local inInst, instType = false, "none"
    if IsInInstance then
        local a, b = IsInInstance()
        inInst, instType = a and true or false, b or "none"
    end
    -- mapId ALWAYS: outdoors it is the continent's instance id, the same number
    -- UnitPosition hands out, and the summoner compares against it to turn two
    -- positions into yards. MINOR 1 only sent it inside an instance, so a peer
    -- standing next to the summoner in Stormwind read as "far".
    local instName, mapId = "", ""
    if GetInstanceInfo then
        local n, _, _, _, _, _, _, id = GetInstanceInfo()
        mapId = id or ""
        if inInst then instName = n or "" end
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local x, y = "", ""
    if UnitPosition then
        local py, px = UnitPosition("player")
        if px and py then
            x = string.format("%.1f", px)
            y = string.format("%.1f", py)
        end
    end
    return {
        inInstance = inInst, instType = instType, instName = instName,
        zone = zone, x = tonumber(x), y = tonumber(y), mapId = mapId,
        at = Now(),
    }
end

local function whereKey(w)
    return tostring(w.inInstance) .. w.instType .. w.instName .. w.zone
end

function lib:SendWhere(force)
    if not InGroup() then return false end
    local w = self:MyWhere()
    local key = whereKey(w)
    -- Push only on a real change. Walking around is not news; zoning is.
    if not force and key == self._lastWhereKey and (Now() - (self._lastWhereAt or 0)) < WHERE_THROTTLE then
        return false
    end
    self._lastWhereKey, self._lastWhereAt = key, Now()
    self.where = w
    return self:Send("CORE", "WHERE", w.inInstance, w.instType, w.instName, w.zone,
                     w.x or "", w.y or "", w.mapId)
end

-- A summoner asking. Everyone answers once, spread over 1-3s; repeat asks
-- inside the window fold into the one answer already scheduled.
function lib:Ask()
    return self:Send("CORE", "ASK", "WHERE")
end

lib._core.ASK = function(sender, what)
    if what ~= "WHERE" then return end
    if lib._askPending then return end
    if (Now() - (lib._lastAnswer or 0)) < ASK_COALESCE and lib._lastAnswer then return end
    lib._askPending = true
    local send = function()
        lib._askPending = false
        lib._lastAnswer = Now()
        lib:SendWhere(true)
    end
    if not After(ANSWER_MIN + math.random() * ANSWER_JITTER, send) then send() end
end

lib._core.WHERE = function(sender, inInst, instType, instName, zone, x, y, mapId)
    local pr = peer(sender)
    pr.where = {
        inInstance = (inInst == "1"),
        instType   = instType or "none",
        instName   = instName or "",
        zone       = zone or "",
        x = tonumber(x or ""), y = tonumber(y or ""),
        mapId = mapId or "",
        at = Now(),
    }
    fire("WHERE", sender, pr.where)
end

--------------------------------------------------------------------
-- CORE: summon offers
--------------------------------------------------------------------
-- CONFIRM_SUMMON fires on the person being summoned, never on the summoner, and
-- clicking a meeting stone is a game-object interaction the client does not
-- expose at all. This is the only honest way a summoner learns what happened.

function lib:SendSummon(state, summoner, area, left)
    self.summon = (state ~= "NO") and
        { state = state, summoner = summoner, area = area, left = left, at = Now() } or nil
    return self:Send("CORE", "SUM", state, summoner or "", area or "", left or "")
end

-- MINOR 6: 2.5.6.69795 has these only at C_SummonInfo.* (BiSProbe, 16 Sep) - the
-- globals minor 5 read are gone. C_SummonInfo first, the old globals as the fallback,
-- looked up at call time in pair form (the API fence in _bisdev/audit reads that shape).
local function SummonAPI()
    local who  = (C_SummonInfo and C_SummonInfo.GetSummonConfirmSummoner) or GetSummonConfirmSummoner
    local area = (C_SummonInfo and C_SummonInfo.GetSummonConfirmAreaName) or GetSummonConfirmAreaName
    local left = (C_SummonInfo and C_SummonInfo.GetSummonConfirmTimeLeft) or GetSummonConfirmTimeLeft
    return who, area, left
end

function lib:OnConfirmSummon()
    local getWho, getArea, getLeft = SummonAPI()
    local summoner = getWho and getWho() or ""
    local area     = getArea and getArea() or ""
    local left     = getLeft and getLeft() or OFFER_FALLBACK
    -- MINOR 5: the 2.5.x client fires CONFIRM_SUMMON on bystanders too (Arn, 10 Sep:
    -- "randomly if any other person gets a summon it says SUMMON by someone") - with
    -- no summoner, no area, no clock. That is not an offer to ME; announcing it as
    -- one would put a phantom OFFER on every summoner's list. Ask the client.
    if not self:HasPendingSummon(summoner, area, left) then return end
    left = tonumber(left) or OFFER_FALLBACK
    if left <= 0 then left = OFFER_FALLBACK end
    self._offerId = (self._offerId or 0) + 1
    local id = self._offerId
    self:SendSummon("OFFER", Short(summoner), area, math.floor(left))
    -- An offer that lapses unanswered is the exact case that used to leave the
    -- summoner staring at the same name: say so when the clock runs out.
    After(left, function()
        if lib._offerId == id and lib.summon and lib.summon.state == "OFFER" then
            lib:SendSummon("NO", nil, nil, nil)
        end
    end)
end

-- Is there really a summon waiting on THIS client? Only the client's summon API can
-- say. MINOR 6: when neither C_SummonInfo nor the old globals exist the answer is NO -
-- minor 5 said yes there, and on 2.5.6.69795 (globals gone) that turned every
-- bystander's CONFIRM_SUMMON back into a phantom OFFER.
function lib:HasPendingSummon(summoner, area, left)
    local getWho, getArea, getLeft = SummonAPI()
    if not getWho then return false end
    summoner = summoner or (getWho() or "")
    area = area or (getArea and getArea() or "")
    left = tonumber(left or (getLeft and getLeft())) or 0
    return (summoner ~= "" or area ~= "" or left > 0) and true or false
end

function lib:OnConfirmed()      -- they clicked Accept
    if self.summon and self.summon.state == "OFFER" then
        self._offerId = (self._offerId or 0) + 1
        self:SendSummon("OK", self.summon.summoner, self.summon.area, nil)
    end
end

function lib:OnCancelSummon()   -- declined, or it timed out client-side
    if self.summon then
        self._offerId = (self._offerId or 0) + 1
        self:SendSummon("NO", nil, nil, nil)
    end
end

lib._core.SUM = function(sender, state, summoner, area, left)
    local pr = peer(sender)
    if state == "NO" then
        pr.summon = nil
    else
        pr.summon = {
            state = state, summoner = summoner, area = area,
            left = tonumber(left or ""), at = Now(),
        }
    end
    fire("SUM", sender, pr.summon)
end

--------------------------------------------------------------------
-- events
--------------------------------------------------------------------

function lib:Boot()
    if self._booted then return end
    self._booted = true

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, PREFIX)
    end

    local f = self._frame or (CreateFrame and CreateFrame("Frame"))
    if not f then return end
    self._frame = f

    local function reg(ev)
        -- An event this client does not have must not stop the rest registering.
        pcall(f.RegisterEvent, f, ev)
    end
    reg("CHAT_MSG_ADDON")
    reg("PLAYER_ENTERING_WORLD")
    reg("ZONE_CHANGED_NEW_AREA")
    reg("GROUP_ROSTER_UPDATE")
    reg("CONFIRM_SUMMON")
    reg("CANCEL_SUMMON")
    reg("GUILD_ROSTER_UPDATE")

    f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
        if event == "CHAT_MSG_ADDON" then
            lib:OnMessage(a1, a2, a3, a4)
        elseif event == "GUILD_ROSTER_UPDATE" then
            lib._guildDirty = true
        elseif event == "CONFIRM_SUMMON" then
            lib:OnConfirmSummon()
        elseif event == "CANCEL_SUMMON" then
            lib:OnCancelSummon()
        elseif event == "GROUP_ROSTER_UPDATE" then
            lib:OnRoster()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- login / reload: my table may be empty, say HI and let the short
            -- rule fill it
            lib:SendWhere(true)
            if not After(1 + math.random() * 2, function() lib:Hi() end) then lib:Hi() end
        else
            -- ZONE_CHANGED_NEW_AREA: a zone line is news about WHERE, not who
            -- I am; peers survive zoning (the blip rule), so no HI here
            lib:SendWhere(true)
        end
    end)

    -- Accept has no event of its own; the popup calls ConfirmSummon(). MINOR 6: on
    -- 2.5.6.69795 that is C_SummonInfo.ConfirmSummon - minor 5 looked only for the
    -- global, found nothing, and never saw an accept.
    if hooksecurefunc and C_SummonInfo and C_SummonInfo.ConfirmSummon then
        hooksecurefunc(C_SummonInfo, "ConfirmSummon", function() lib:OnConfirmed() end)
    elseif hooksecurefunc and type(_G.ConfirmSummon) == "function" then
        hooksecurefunc("ConfirmSummon", function() lib:OnConfirmed() end)
    end
end

-- A zone-in reads the roster as EMPTY for a moment. Wiping the peer table on
-- that blip took Innervate's whole grid out for a night; wait 10s before
-- believing an empty group.
function lib:OnRoster()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n > 0 then
        -- HI only when *I* just arrived (0 -> n). Somebody else joining is his
        -- HI to say, and everyone short-answers it; a leave is a purge, not a
        -- conversation. Minor 2 said HI on every roster tick - 22 messages per
        -- join / leave / promote on a 25-man (raid25.lua).
        local arrived = (self._lastN or 0) == 0
        self._lastN, self._emptySince = n, nil
        self:PurgeAbsent()
        if arrived then
            if not After(1 + math.random() * 2, function() lib:Hi() end) then self:Hi() end
        end
        return
    end
    if (self._lastN or 0) == 0 then return end
    self._emptySince = self._emptySince or Now()
    if (Now() - self._emptySince) < 10 then return end
    self._lastN, self._emptySince = 0, nil
    self.peers = {}
    lib.peers = self.peers
end

--------------------------------------------------------------------
-- the one slash: status and the honest off switch
--------------------------------------------------------------------

-- Always (re)set, even over an older copy's handler: minor 3 took "/bis", which
-- LoonBestInSlot also owns, so the newest copy must move the slash to /biscomm.
if SlashCmdList then
    _G.SLASH_BISCOMM1 = "/biscomm"
    SlashCmdList["BISCOMM"] = function(msg)
        msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local say = function(s)
            if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffb980ffBiS|r " .. s) end
        end
        if msg == "comm off" or msg == "off" then
            lib:SetEnabled(false); say("comm off - silent and deaf until /biscomm on")
        elseif msg == "comm on" or msg == "on" then
            lib:SetEnabled(true); lib:Hi(); say("comm on")
        else
            say(("comm %s, lib %d, %d peer(s), running %s")
                :format(lib:Enabled() and "on" or "off", lib.MINOR, lib:Count(),
                        lib:AddonsBlob() ~= "" and lib:AddonsBlob() or "nothing"))
            say("/biscomm on | /biscomm off")
        end
    end
end

return lib
