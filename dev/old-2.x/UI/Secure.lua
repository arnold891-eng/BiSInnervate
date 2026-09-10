-- BiS Innervate :: Secure.lua
-- The only part that has to survive combat lockdown.
--
-- Everything protected (Show/Hide of the cast buttons, changing which unit a
-- button points at) happens inside a SecureHandler snippet, which is allowed to
-- run in combat. Insecure code only ever sets plain attributes on the header,
-- which is legal at any time. Buttons and their anchors are created ONCE at
-- login, so nothing has to be created or moved mid-fight.

local ADDON, NS = ...

local Secure = {}
NS.Secure = Secure

Secure.MAX_ROWS = 5
Secure.ICON      = 40      -- button is a square action-button-sized icon
Secure.STEP      = 46      -- vertical spacing between icons
Secure.LABEL_W   = 150     -- name text sits beside the icon, outside the button
Secure.rows     = {}
Secure.rowReq   = {}    -- row index -> request id (insecure bookkeeping)

local SNIPPET = [[
    if name ~= "refresh" then return end
    local n = tonumber(self:GetAttribute("count") or "0") or 0
    for i = 1, %d do
        local b = self:GetFrameRef("row" .. i)
        if b then
            local u = self:GetAttribute("unit" .. i)
            if i <= n and u and u ~= "" then
                b:SetAttribute("unit", u)
                b:Show()
            else
                b:Hide()
            end
        end
    end
]]

function Secure:ApplyClicks(b)
    local useDown = true
    if GetCVarBool then
        local ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        if ok and v ~= nil then useDown = v and true or false end
    elseif GetCVar then
        local ok, v = pcall(GetCVar, "ActionButtonUseKeyDown")
        if ok and v ~= nil then useDown = (v == "1") end
    end
    b:RegisterForClicks(useDown and "AnyDown" or "AnyUp")
end

-- A pulsing border around the icon. Blizzard's IconAlert proc art was tried
-- first and looked like a green smear stretched over a wide row; on these
-- square icons a clean 2px border reads better and cannot go wrong. Textures
-- are not protected, so this is safe to start and stop mid-fight.
local EDGE = 2

function Secure:AttachProcGlow(b)
    local g = CreateFrame("Frame", nil, b)
    g:SetAllPoints(b)

    local function edge(p1, p2, w, h)
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.35, 1.00, 0.45, 0.9)
        t:SetPoint(p1, g, p1, 0, 0)
        t:SetPoint(p2, g, p2, 0, 0)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    g.edges = {
        edge("TOPLEFT", "TOPRIGHT", nil, EDGE),
        edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, EDGE),
        edge("TOPLEFT", "BOTTOMLEFT", EDGE, nil),
        edge("TOPRIGHT", "BOTTOMRIGHT", EDGE, nil),
    }

    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetDuration(0.6)
    if a.SetFromAlpha then a:SetFromAlpha(0.45); a:SetToAlpha(1.0) end
    if a.SetChange then a:SetChange(-0.55) end

    g:Hide()
    b.procGlow, b.procAnim = g, ag
end

function Secure:Build(parent)
    if self.header then return self.header end
    if NS.InCombat() then return nil end
    if not NS.MyKind() then return nil end        -- warriors do not need 45 secure buttons

    -- The header is parented to UIParent AND positions itself on UIParent. The
    -- panel then anchors to the header. Both directions matter: a frame that
    -- holds a secure child is protected, and so is a frame a secure child is
    -- anchored to - hiding it would move the protected frame. Either mistake
    -- produces "tried to call the protected function BiSInnervateFrame:Hide()".
    local header = CreateFrame("Frame", "BiSInnervateSecureHeader", UIParent, "SecureHandlerAttributeTemplate")
    header:SetSize(200, self.MAX_ROWS * self.STEP)
    local pos = NS.db and NS.db.pos
    if pos then
        header:SetPoint(pos.point or "CENTER", UIParent, pos.rel or "CENTER", pos.x or 0, pos.y or 0)
    else
        header:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
    end
    header:SetAttribute("_onattributechanged", string.format(SNIPPET, self.MAX_ROWS))
    self.header = header

    -- my provider spell never changes during a session, so it can be baked into
    -- the buttons at login and never touched in combat
    local kind  = NS.MyKind() or "INNERVATE"
    local spell = NS.SpellNameFor(kind)
    self.kind = kind
    -- Mana Tide is a totem: it lands where the shaman stands and needs no unit.
    -- That means the button never has to be re-pointed, so it can simply exist
    -- from login and change nothing but its own artwork - immune to every
    -- lockdown rule, on any client.
    self.selfCast = (kind == "TIDE")

    for i = 1, self.MAX_ROWS do
        local b = CreateFrame("Button", "BiSInnervateRow" .. i, header, "SecureActionButtonTemplate")
        b:SetSize(self.ICON, self.ICON)
        b:SetPoint("TOPLEFT", header, "TOPLEFT", 4, -((i - 1) * self.STEP) - 4)

        -- Decursive landmine: a bare "type"/"spell" attribute is never resolved.
        b:SetAttribute("*type1", "spell")
        b:SetAttribute("*spell1", spell)
        b:SetAttribute("*type2", "spell")
        b:SetAttribute("*spell2", spell)
        b:SetAttribute("unit", "player")
        -- click registration must match the client's ActionButtonUseKeyDown cvar,
        -- otherwise the secure action silently never fires (InnervateMate does the
        -- same check; BiS Rez hit the AnyUp version of this bug)
        Secure:ApplyClicks(b)

        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.8)
        b.bg = bg

        -- the spell's own icon fills the button
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexture(NS.SpellIconFor(kind))
        if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        b.icon = icon
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        Secure:AttachProcGlow(b)
        b.glow, b.glowAnim = b.procGlow, b.procAnim

        -- cooldown swipe, so a druid can see their own timer on the row itself
        local cdf = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        if cdf then
            cdf:SetPoint("TOPLEFT", 2, -2)
            cdf:SetPoint("BOTTOMRIGHT", -2, 2)
            if cdf.SetReverse then cdf:SetReverse(false) end
            if cdf.SetDrawEdge then cdf:SetDrawEdge(false) end
            b.cd = cdf
        end

        local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("LEFT", b, "RIGHT", 6, 6)
        txt:SetJustifyH("LEFT")
        txt:SetWidth(Secure.LABEL_W)
        b.text = txt

        local sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("TOPLEFT", txt, "BOTTOMLEFT", 0, -2)
        sub:SetJustifyH("LEFT")
        sub:SetWidth(Secure.LABEL_W)
        b.sub = sub

        -- No PostClick claim. A click proves nothing - out of range, moving,
        -- silenced or on cooldown all click just fine, and claiming on the click
        -- used to push the escalation out by claimHold every time somebody
        -- mashed a dead button. The real cast fires UNIT_SPELLCAST_SUCCEEDED,
        -- which is what claims.
        b:HookScript("OnEnter", function(self_)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self_, "ANCHOR_RIGHT")
            GameTooltip:AddLine(("Click to cast %s%s"):format(spell,
                (Secure.kind == "TIDE") and " for your group" or (" on " .. (self_.playerName or "?"))))
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        if Secure.selfCast and i == 1 then
            b:SetAlpha(0.35)                 -- always available, dim until asked
            b:Show()
        else
            b:Hide()
        end
        header:SetFrameRef("row" .. i, b)
        self.rows[i] = b
    end

    if self.selfCast then self:AddGrip() end

    return header
end

-- A shaman's Mana Tide button is usually the only thing on screen: the panel
-- around it is hidden whenever nobody is asking, so there was nothing to drag.
-- The button itself cannot be the handle - it is a secure button, and a drag
-- would eat the click that casts. So it gets a small grip bar of its own.
function Secure:AddGrip()
    if self.grip or not self.header then return end

    -- To the LEFT of the icon, not above it: above is where the panel's title
    -- and its own _ / x tabs live, and the grip sat right on top of them.
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetSize(7, self.ICON)
    g:SetPoint("TOPRIGHT", self.header, "TOPLEFT", 3, -4)
    g:SetMovable(true)
    g:EnableMouse(true)
    g:RegisterForDrag("LeftButton")

    local bar = g:CreateTexture(nil, "BACKGROUND")
    bar:SetAllPoints()
    bar:SetColorTexture(0.35, 0.55, 0.75, 0.55)

    local hl = g:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.6, 0.8, 1.0, 0.45)

    g:SetScript("OnDragStart", function()
        if NS.InCombat() then return end        -- moving the header is protected
        Secure.header:SetMovable(true)
        Secure.header:StartMoving()
    end)
    g:SetScript("OnDragStop", function()
        if NS.InCombat() then return end
        Secure.header:StopMovingOrSizing()
        local point, _, rel, x, y = Secure.header:GetPoint()
        NS.db.pos = { point = point, rel = rel, x = x, y = y }
    end)
    g:SetScript("OnEnter", function(self_)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self_, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to move your Mana Tide button")
        GameTooltip:AddLine("Out of combat only.", 1, 1, 1)
        GameTooltip:AddLine("/inn reset puts it back.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    self.grip = g
    return g
end

function Secure:RefreshSpellName()
    if NS.InCombat() then return end
    NS.ForgetSpellCache()
    local kind = NS.MyKind()
    if not kind then return end
    self.kind = kind
    local spell = NS.SpellNameFor(kind)
    local icon  = NS.SpellIconFor(kind)
    local function apply(b)
        b:SetAttribute("*spell1", spell)
        b:SetAttribute("*spell2", spell)
        if b.icon and icon then b.icon:SetTexture(icon) end
    end
    for _, b in ipairs(self.rows) do apply(b) end
end

-- entries: { {unit=, name=, label=, sub=, id=, glow=bool}, ... }
function Secure:SetEntries(entries)
    if not self.header then return end
    local n = math.min(#entries, self.MAX_ROWS)

    -- Self-cast provider (Mana Tide): row 1 is permanently visible and always
    -- points at the caster, so nothing protected is ever touched. Only its
    -- artwork changes, which is legal in combat on any client.
    if self.selfCast then
        return self:SetSelfCastEntry(entries[1])
    end

    -- Druids do not cast from these rows any more - the grid does that, with
    -- bindings written out of combat and nothing but colours changed during a
    -- fight. So there is no reason to write a secure attribute mid-fight, and
    -- every reason not to: this client blocks the write and taints us for
    -- trying, several times a second, all fight. Blank the rows and wait.
    if NS.InCombat() then
        if not self.blanked then
            self.blanked = true
            self:BlankRows()
        end
        return self._lastN or 0
    end
    self.blanked = false

    for i = 1, self.MAX_ROWS do
        local e = entries[i]
        local b = self.rows[i]
        if e and i <= n then
            self.header:SetAttribute("unit" .. i, e.unit or "")
            self.rowReq[i] = e.id
            b.playerName = e.name
            if b.text then b.text:SetText(e.label or e.name or "") end
            if b.sub then b.sub:SetText(e.sub or "") end
            if b.icon and b.icon.SetDesaturated then b.icon:SetDesaturated(not e.glow) end
            if b.icon and b.icon.SetVertexColor then
                if e.glow then b.icon:SetVertexColor(1, 1, 1) else b.icon:SetVertexColor(0.5, 0.5, 0.5) end
            end
            self:SetGlow(b, e.glow)
        else
            self.header:SetAttribute("unit" .. i, "")
            self.rowReq[i] = nil
            if b then self:SetGlow(b, false) end
        end
    end

    self.header:SetAttribute("count", n)
    self._lastN = n
    -- the write below is what makes the snippet run (in or out of combat).
    -- A counter, not GetTime(): two refreshes in one frame share a timestamp,
    -- and an unchanged attribute value may not fire OnAttributeChanged.
    self._tick = (self._tick or 0) + 1
    self.header:SetAttribute("refresh", self._tick)

    -- Verify what actually landed: the count alone is not enough, because a
    -- handover can swap WHICH player row 1 points at while the count stays the
    -- same. That would relabel the button and leave it casting on the old
    -- target - the worst bug this addon could have.
    local landed = tonumber(self.header:GetAttribute("count") or -1)
    local unitOk = true
    for i = 1, n do
        if self.header:GetAttribute("unit" .. i) ~= (entries[i] and entries[i].unit) then
            unitOk = false
            break
        end
    end
    if landed ~= n or not unitOk then
        if not self.blocked then
            self.blocked = true
            -- remember it: a property of the client, not of this fight
            if NS.db then NS.db.secureBlocked = true end
            NS.Print("|cffff8040this client refuses secure writes here - the rows are a display only, cast from the squares.|r")
        end
    elseif self.blocked then
        -- it worked this time: do not stay latched, or the rows stay blank on a
        -- client where nothing is actually wrong
        self.blocked = false
        if NS.db then NS.db.secureBlocked = false end
    end
    if self.blocked then self:BlankRows() end
    return n
end

-- Strip every row of anything that says "click me". Used both when a write was
-- refused and for the whole of every fight: the rows cannot be re-pointed in
-- combat, so a row left over from before the pull is a lie. Textures and font
-- strings only - legal at any time.
function Secure:BlankRows()
    for i = 1, self.MAX_ROWS do
        local b = self.rows[i]
        if b then
            self:SetGlow(b, false)
            if b.text then b.text:SetText("") end
            if b.sub then b.sub:SetText("") end
            if b.icon and b.icon.SetVertexColor then b.icon:SetVertexColor(0.3, 0.3, 0.3) end
            self.rowReq[i] = nil
        end
    end
end

-- drive the swipe on each icon from the player's real cooldown
function Secure:UpdateCooldowns()
    local kind = NS.MyKind()
    if not kind then return end
    local left = NS.SpellCooldownFor(kind)
    local p = NS.Provider(kind)
    local start = (left > 0) and (NS.Now() - ((p.cd or 360) - left)) or 0
    for _, b in ipairs(self.rows) do
        if b.cd and b.cd.SetCooldown then
            pcall(b.cd.SetCooldown, b.cd, start, (left > 0) and (p.cd or 360) or 0)
        end
    end
end

-- the shaman's one button: dim when idle, lit when somebody asked
function Secure:SetSelfCastEntry(e)
    local b = self.rows[1]
    if not b then return 0 end
    self.rowReq[1] = e and e.id or nil
    b.playerName = e and e.name or nil

    if e then
        if b.text then b.text:SetText(e.label or e.name or "") end
        if b.sub then b.sub:SetText(e.sub or "") end
        b:SetAlpha(1)
        self:SetGlow(b, e.glow and true or false)
        if b.icon and b.icon.SetVertexColor then b.icon:SetVertexColor(1, 1, 1) end
    else
        if b.text then b.text:SetText("") end
        if b.sub then b.sub:SetText("") end
        b:SetAlpha(0.35)
        self:SetGlow(b, false)
        if b.icon and b.icon.SetVertexColor then b.icon:SetVertexColor(0.6, 0.6, 0.6) end
    end
    return e and 1 or 0
end

-- Colour the outline and decide whether it pulses. The state lives entirely in
-- this border now: nothing is painted over the portrait itself.
function Secure:SetBorder(b, r, g, bl, a, pulse)
    if not b or not b.procGlow then return end
    if not r then
        if b.procAnim and b.procAnim:IsPlaying() then b.procAnim:Stop() end
        b.procGlow:Hide()
        return
    end
    for _, t in ipairs(b.procGlow.edges or {}) do
        t:SetColorTexture(r, g, bl, a or 1)
    end
    b.procGlow:Show()
    if pulse then
        if b.procAnim and not b.procAnim:IsPlaying() then b.procAnim:Play() end
    else
        if b.procAnim and b.procAnim:IsPlaying() then b.procAnim:Stop() end
        b.procGlow:SetAlpha(1)
    end
end

function Secure:SetGlow(b, on)
    if not b then return end
    if on then
        if b.procGlow then b.procGlow:Show() end
        if b.procAnim and not b.procAnim:IsPlaying() then b.procAnim:Play() end
    else
        if b.procAnim and b.procAnim:IsPlaying() then b.procAnim:Stop() end
        if b.procGlow then b.procGlow:Hide() end
    end
end

-- combat is over: the rows can be written again
function Secure:LeaveCombat()
    self.blocked = false
    self.blanked = false
end
