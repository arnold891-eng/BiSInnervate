-- BiS Innervate :: RequestBar.lua
-- What a mage / healer sees: one button. Clicking it is not a spell cast, so it
-- works fine in combat with no secure plumbing. /inn does the same thing.

local ADDON, NS = ...
local T = NS.T

local Bar = {}
NS.Bar = Bar

function Bar:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Button", "BiSInnervateRequestButton", UIParent)
    f:SetSize(132, 30)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("AnyUp")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(s) if not NS.InCombat() then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local point, _, rel, x, y = s:GetPoint()
        NS.db.barPos = { point = point, rel = rel, x = x, y = y }
    end)
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            NS.Queue:CancelMine("manual")
        else
            NS.Queue:RequestForSelf()
        end
        Bar:Update()
    end)
    f:SetScript("OnEnter", function(s)
        if not GameTooltip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Ask for Innervate")
        GameTooltip:AddLine("One druid gets assigned - no voice chat needed.", T.rgb("ink"))
        GameTooltip:AddLine("Nothing is sent until you click this.", T.rgb("muted"))
        GameTooltip:AddLine("Right-click: cancel your request.", T.rgb("muted"))
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.rgba("surface", 0.95))
    f.bg = bg

    local glow = f:CreateTexture(nil, "BORDER")
    glow:SetPoint("TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", 3, -3)
    glow:SetColorTexture(T.rgba("warn", 0.55))
    glow:Hide()
    f.glow = glow

    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetDuration(0.6)
    if a.SetFromAlpha then a:SetFromAlpha(0.10); a:SetToAlpha(0.70) end
    if a.SetChange then a:SetChange(-0.6) end
    f.glowAnim = ag

    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER")
    txt:SetText("Innervate")
    txt:SetTextColor(T.rgb("ink"))
    f.text = txt

    local pos = NS.db.barPos
    if pos then
        f:SetPoint(pos.point or "CENTER", UIParent, pos.rel or "CENTER", pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    end
    f:Hide()

    -- Mana Tide button: only exists for people who actually have a resto shaman
    -- with the totem up sitting in their own raid subgroup.
    local t = CreateFrame("Button", "BiSInnervateTideButton", f)
    t:SetSize(132, 22)
    t:SetPoint("TOP", f, "BOTTOM", 0, -4)
    t:RegisterForClicks("AnyUp")
    local tbg = t:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints()
    tbg:SetColorTexture(0.08, 0.26, 0.26, 0.85)
    local tglow = t:CreateTexture(nil, "BORDER")
    tglow:SetPoint("TOPLEFT", -3, 3)
    tglow:SetPoint("BOTTOMRIGHT", 3, -3)
    tglow:SetColorTexture(T.rgba("warn", 0.50))
    tglow:Hide()
    t.glow = tglow
    local tag = tglow:CreateAnimationGroup()
    tag:SetLooping("BOUNCE")
    local ta = tag:CreateAnimation("Alpha")
    ta:SetDuration(0.6)
    if ta.SetFromAlpha then ta:SetFromAlpha(0.10); ta:SetToAlpha(0.70) end
    if ta.SetChange then ta:SetChange(-0.6) end
    t.glowAnim = tag
    local ttxt = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ttxt:SetPoint("CENTER")
    ttxt:SetTextColor(T.rgb("ink"))
    t.text = ttxt
    t:SetScript("OnClick", function()
        NS.Queue:RequestForSelf("TIDE")
        Bar:Update()
    end)
    t:SetScript("OnEnter", function(s)
        if not GameTooltip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Ask for Mana Tide")
        GameTooltip:AddLine("Your group's shaman has it up. Lights up their button.", T.rgb("ink"))
        GameTooltip:AddLine("Helps everyone in your group, and saves an innervate.", T.rgb("muted"))
        GameTooltip:AddLine("Nothing is sent until you click this.", T.rgb("muted"))
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    t:Hide()
    f.tide = t

    self.frame = f
    table.insert(NS.UI.refreshHooks, function() Bar:Update() end)
    return f
end

function Bar:ShouldShow()
    if NS.db.hideBar then return false end
    if not NS.InGroup() then return false end
    local _, class = UnitClass("player")
    if not NS.IsRequesterClass(class) then return false end
    if NS.db.barAlways then return true end
    local mana = NS.ManaPct("player")
    if not mana then return false end
    if NS.Queue:ActiveFor(NS.PlayerName()) then return true end
    -- visible early (90% by default) so the button is already there when it is
    -- wanted. Showing is all it does: nothing is requested until you click.
    return mana <= (NS.db.showAt or 90)
end

function Bar:ToggleHidden()
    NS.db.hideBar = not NS.db.hideBar
    self:Update()
    NS.Print("request button " .. (NS.db.hideBar and "closed." or "back."))
end

-- the tide line only appears if a shaman in MY subgroup has the totem ready
function Bar:UpdateTide()
    local t = self.frame and self.frame.tide
    if not t then return end
    local me = NS.PlayerName()
    local shaman = (NS.MyKind() ~= "TIDE") and NS.Tracker:TideFor(me) or nil
    local pending = NS.Queue:TideCovering(me)

    if not shaman and not pending then
        if t.glowAnim and t.glowAnim:IsPlaying() then t.glowAnim:Stop() end
        if t.glow then t.glow:Hide() end
        t:Hide()
        return
    end

    if pending then
        t.text:SetText(pending.assigned and (T.text("good", pending.assigned) .. " dropping tide")
                                          or "mana tide coming...")
        if t.glowAnim and t.glowAnim:IsPlaying() then t.glowAnim:Stop() end
        if t.glow then t.glow:Hide() end
    else
        t.text:SetText("Mana Tide  (" .. shaman.name .. ")")
        local mana = NS.ManaPct("player") or 100
        if mana <= (NS.db.urgentAt or 20) then
            if t.glow then t.glow:Show() end
            if t.glowAnim and not t.glowAnim:IsPlaying() then t.glowAnim:Play() end
        else
            if t.glowAnim and t.glowAnim:IsPlaying() then t.glowAnim:Stop() end
            if t.glow then t.glow:Hide() end
        end
    end
    t:Show()
end

function Bar:Update()
    if not self.frame then return end
    if not self:ShouldShow() then
        if self.frame.glowAnim and self.frame.glowAnim:IsPlaying() then self.frame.glowAnim:Stop() end
        if self.frame.glow then self.frame.glow:Hide() end
        local t = self.frame.tide
        if t then
            if t.glowAnim and t.glowAnim:IsPlaying() then t.glowAnim:Stop() end
            if t.glow then t.glow:Hide() end
            t:Hide()
        end
        self.frame:Hide()
        return
    end
    self:UpdateTide()

    local req = NS.Queue:ActiveForKind(NS.PlayerName(), "INNERVATE")
    local mana = NS.ManaPct("player") or 0
    local label, urgent

    if req then
        if req.assigned then
            label = T.text("good", req.assigned) .. " on it"
        else
            label = "waiting for druid..."
        end
        urgent = false
    else
        label = string.format("Innervate  (%d%%)", mana)
        urgent = mana <= (NS.db.urgentAt or 20)
    end

    self.frame.text:SetText(label)
    if urgent then
        if self.frame.glow then self.frame.glow:Show() end
        if self.frame.glowAnim and not self.frame.glowAnim:IsPlaying() then self.frame.glowAnim:Play() end
    else
        if self.frame.glowAnim and self.frame.glowAnim:IsPlaying() then self.frame.glowAnim:Stop() end
        if self.frame.glow then self.frame.glow:Hide() end
    end
    self.frame:Show()
end
