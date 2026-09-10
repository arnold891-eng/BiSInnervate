-- BiS Innervate :: Assign.lua
-- Standing assignments: a raid lead pairs a provider with a player before the
-- pull. Nothing fires on its own - when that player presses their button, the
-- request goes to the provider standing-assigned to them instead of whoever the
-- sort order would have picked. Everything else (escalation if they ignore it,
-- handover, dedupe) works exactly as before.

local ADDON, NS = ...

local Assign = {}
NS.Assign = Assign

Assign.map     = {}      -- providerName -> { target = name }
Assign.editors = {}      -- name -> true: people the lead has let edit the board

-- the actual raid leader: the single authority for editor rights and for
-- answering "what is the board?" (assistants answering too made joiners get one
-- broadcast per assistant, last one winning at random)
function Assign:IsRaidLeader()
    if not NS.InGroup() then return true end
    return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false
end

function Assign:IsLeader()
    if self:IsRaidLeader() then return true end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return true end
    return false
end

function Assign:IsEditor(name)
    return self.editors[NS.Short(name or "")] and true or false
end

function Assign:CanEdit()
    if NS.db and NS.db.leaderOnly == false then return true end
    if self:IsLeader() then return true end
    return self:IsEditor(NS.PlayerName())
end

-- only the actual raid lead hands out or takes back editing rights
function Assign:SetEditor(name, on)
    name = NS.ResolveName(name)
    if not name then return false end
    if not self:IsRaidLeader() then
        NS.Print("only the raid lead can hand out assignment rights.")
        return false
    end
    self.editors[name] = on and true or nil
    NS.Print(name .. (on and " can now set assignments." or " can no longer set assignments."))
    self:Broadcast()
    if NS.AssignWindow then NS.AssignWindow:Refresh() end
    return true
end

-- called on roster changes: whoever is leader now owns the board
function Assign:OnRosterChange()
    -- During a zone-in the roster reads empty for a moment. Pruning then would
    -- delete the whole board on every client, and IsRaidLeader() answers true
    -- when not in a group, so everyone would think they were lead and publish
    -- their empty map. Sit that moment out.
    if not NS.InGroup() then return end
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n <= 1 then return end

    local isLead = self:IsRaidLeader()
    if isLead and not self._wasLead then
        self._wasLead = true
        NS.After(1.5, function() if Assign:IsRaidLeader() then Assign:Broadcast() end end)
    elseif not isLead then
        self._wasLead = false
    end
    -- A big raid zoning in reports 40 members while the last raid tokens are
    -- still empty, so half the board would be pruned on that client alone and
    -- nothing would ever restore it. Only prune when every slot resolves.
    local resolved = 0
    NS.ForEachMember(function() resolved = resolved + 1 end)
    if resolved < n then return end

    -- drop rights for anyone who left the raid
    for name in pairs(self.editors) do
        if not NS.UnitOf(name) then self.editors[name] = nil end
    end
    -- and assignments whose provider or target is gone
    for provider, a in pairs(self.map) do
        if not NS.UnitOf(provider) or not NS.UnitOf(a.target) then self.map[provider] = nil end
    end
end

function Assign:EditorList()
    local out = {}
    for name in pairs(self.editors) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function Assign:Denied()
    NS.Print("you are not allowed to change assignments - the raid lead can grant you rights in |cffffff00/inn assign|r.")
end

function Assign:For(provider)
    return self.map[NS.Short(provider or "")]
end

-- who is standing-assigned to cover this player?
function Assign:ProviderFor(target)
    target = NS.Short(target or "")
    for provider, a in pairs(self.map) do
        if a.target == target then return provider, a end
    end
    return nil
end

function Assign:Set(provider, target, quiet)
    provider, target = NS.ResolveName(provider), NS.ResolveName(target)
    if not provider or not target then return false end
    if not self:CanEdit() then
        self:Denied()
        return false
    end
    self.map[provider] = { target = target }
    if not quiet then
        NS.Print(string.format("%s covers %s.", provider, target))
        self:Broadcast()
    end
    if NS.UI then NS.UI:Refresh() end
    return true
end

function Assign:Clear(provider, quiet)
    provider = NS.ResolveName(provider)
    if not provider then return end
    if not self:CanEdit() then
        NS.Print("only the raid lead can change assignments.")
        return
    end
    self.map[provider] = nil
    if not quiet then
        NS.Print(provider .. " unassigned.")
        self:Broadcast()
    end
    if NS.UI then NS.UI:Refresh() end
end

function Assign:List()
    local out = {}
    for provider, a in pairs(self.map) do
        out[#out + 1] = { provider = provider, target = a.target }
    end
    table.sort(out, function(x, y) return x.provider < y.provider end)
    return out
end

--------------------------------------------------------------------
-- sync
--------------------------------------------------------------------

local function serialize()
    local parts = {}
    for provider, a in pairs(Assign.map) do
        parts[#parts + 1] = provider .. "," .. a.target
    end
    return table.concat(Assign:EditorList(), "~") .. ";" .. table.concat(parts, "~")
end

-- The board used to go out as one message. Eight assignments with real names
-- overflows 255 bytes, and the client drops it - or worse, the receiver applies
-- a truncated board and silently loses the assignments that fell off the end.
-- Send it in numbered pieces instead and only apply a complete set.
local CHUNK = 160

function Assign:Broadcast()
    local blob = serialize()
    local pieces = {}
    local i = 1
    while i <= #blob do
        -- break on a separator so a pair is never split down the middle
        local stop = math.min(i + CHUNK - 1, #blob)
        if stop < #blob then
            local cut = nil
            for j = stop, i, -1 do
                local ch = string.sub(blob, j, j)
                if ch == "~" or ch == ";" then cut = j break end
            end
            if cut then stop = cut end
        end
        pieces[#pieces + 1] = string.sub(blob, i, stop)
        i = stop + 1
    end
    if #pieces == 0 then pieces[1] = blob end
    self._seq = (self._seq or 0) + 1
    for n, piece in ipairs(pieces) do
        NS.Comm:Send("AMAP", piece, n, #pieces, self._seq)
    end
end

function Assign:AskForMap()
    NS.Comm:Send("AMAP?", "")
end

Assign._rx = {}

NS.Comm:Register("AMAP", function(sender, blob, part, total, seq)
    part, total = tonumber(part or "") or 1, tonumber(total or "") or 1
    if total > 1 then
        local key = NS.Short(sender) .. "#" .. tostring(seq or "")
        local rx = Assign._rx[key]
        if not rx then rx = { n = 0 }; Assign._rx = { [key] = rx } end
        if not rx[part] then rx[part] = blob or ""; rx.n = rx.n + 1 end
        if rx.n < total then return end        -- wait for the rest
        local whole = {}
        for i = 1, total do whole[i] = rx[i] or "" end
        blob = table.concat(whole)
        Assign._rx = {}
    end
    return Assign._applyMap(sender, blob)
end)

function Assign._applyMap(sender, blob)
    local unit = NS.UnitOf(sender)
    local senderIsLead = unit and ((UnitIsGroupLeader and UnitIsGroupLeader(unit)) or
                                   (UnitIsGroupAssistant and UnitIsGroupAssistant(unit)))
    -- Deliberately not consulting the local leaderOnly toggle: that is about
    -- what I may edit, not about whose board I accept. Letting it widen the
    -- accept rule desynced whoever flipped it from the rest of the raid.
    if not (senderIsLead or Assign:IsEditor(sender)) then return end

    local editorBlob, mapBlob = string.match(blob or "", "^([^;]*);(.*)$")
    if not mapBlob then editorBlob, mapBlob = "", blob or "" end

    -- the editor list itself is the lead's to set
    if senderIsLead then
        local editors = {}
        for name in string.gmatch(editorBlob, "([^~]+)") do editors[NS.Short(name)] = true end
        Assign.editors = editors
    end

    local map = {}
    for chunk in string.gmatch(mapBlob, "([^~]+)") do
        -- "provider,target" (older builds appended a threshold; ignore it)
        local provider, target = string.match(chunk, "^([^,]+),([^,]+)")
        if provider and target then
            map[NS.Short(provider)] = { target = NS.Short(target) }
        end
    end
    Assign.map = map
    NS.Debug("assignment board received from", sender)
    if NS.UI then NS.UI:Refresh() end
    if NS.AssignWindow then NS.AssignWindow:Refresh() end
end

NS.Comm:Register("AMAP?", function(sender)
    if not Assign:IsRaidLeader() then return end
    if next(Assign.map) == nil and next(Assign.editors) == nil then return end
    NS.After(0.5 + math.random(), function() Assign:Broadcast() end)
end)

--------------------------------------------------------------------
-- no automatic firing
--
-- Deliberate: a standing assignment never casts or pings on its own. It only
-- decides WHO gets a request once the player actually asks for one.
--------------------------------------------------------------------

function Assign:Tick() end
