-- BiS Innervate :: Minimap.lua
-- One button on the minimap ring, wearing the Innervate icon. It is how the
-- window comes back after somebody closes it.
--
--   left            show / hide the window
--   right           the options window
--   shift + left    /inn status in chat
--   shift + right   the demo
--
-- Insecure from top to bottom: it is a plain button on a Blizzard frame, and
-- every action behind it is one that is already legal in combat or defers
-- itself to the end of the fight.

local ADDON, NS = ...

local Mini = {}
NS.Minimap = Mini

local ICON   = "Interface\\Icons\\Spell_Nature_Lightning"
local RADIUS = 80

local function angle()
    local a = tonumber(NS.db and NS.db.minimapAngle)
    if not a or a ~= a then a = 205 end        -- a ~= a catches nan
    return math.rad(a)
end

function Mini:Place()
    local b = self.button
    if not b or not Minimap then return end
    local a = angle()
    pcall(b.ClearAllPoints, b)
    pcall(b.SetPoint, b, "CENTER", Minimap, "CENTER",
          RADIUS * math.cos(a), RADIUS * math.sin(a))
end

-- follow the cursor around the ring while dragging
local function dragUpdate(b)
    if not Minimap or not GetCursorPosition then return end
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    if not scale or scale <= 0 then return end     -- 0 would write nan to the db
    local cx, cy = GetCursorPosition()
    if not cx then return end
    cx, cy = cx / scale, cy / scale
    NS.db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
    Mini:Place()
end

--------------------------------------------------------------------
-- what the clicks do
--------------------------------------------------------------------

function Mini:OnClick(button)
    local shift = IsShiftKeyDown and IsShiftKeyDown()
    if button == "LeftButton" then
        if shift then NS.HandleSlash("status") else NS.Window:ToggleShown() end
    elseif button == "RightButton" then
        if shift then NS.Demo:Toggle() else NS.Config:Toggle() end
    elseif button == "MiddleButton" then
        NS.HandleSlash("status")
    end
end

function Mini:Tooltip(b)
    if not GameTooltip then return end
    GameTooltip:SetOwner(b, "ANCHOR_LEFT")
    GameTooltip:AddLine("BiS |cffb980ffInnervate|r")
    GameTooltip:AddLine("Left: show / hide the window", 1, 1, 1)
    GameTooltip:AddLine("Right: options", 1, 1, 1)
    GameTooltip:AddLine("Shift-left: status in chat", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Shift-right: the demo", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag to move me around the ring.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

--------------------------------------------------------------------

function Mini:Build()
    if self.button then return self.button end
    if not Minimap then return nil end
    if NS.db and NS.db.minimap == false then return nil end

    local b = CreateFrame("Button", "BiSInnervateMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    pcall(b.SetFrameLevel, b, 8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    -- trim the square icon's edges so it sits inside the ring
    pcall(icon.SetTexCoord, icon, 0.07, 0.93, 0.07, 0.93)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function(_, button) Mini:OnClick(button) end)
    b:SetScript("OnEnter", function(s) Mini:Tooltip(s) end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnDragStart", function(s) s:SetScript("OnUpdate", dragUpdate) end)
    b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)

    self.button = b
    self:Place()
    b:Show()
    return b
end

-- the options window sets a value; it must not route through a toggle whose
-- first branch builds a missing button and returns
function Mini:Set(on)
    NS.db.minimap = on and true or false
    if on then
        if self.button then self.button:Show() else self:Build() end
    elseif self.button then
        self.button:Hide()
    end
end

function Mini:Toggle()
    -- a login during combat defers the whole boot, so there is no button yet.
    -- Build it rather than "hiding" one that was never there.
    if not self.button and NS.db.minimap ~= false then
        self:Build()
        if self.button then NS.Print("minimap button shown."); return end
        NS.Print("the button appears when this fight ends.")
        return
    end
    NS.db.minimap = (NS.db.minimap == false)
    if NS.db.minimap == false then
        if self.button then self.button:Hide() end
        NS.Print("minimap button hidden. |cffffff00/inn minimap|r brings it back.")
    else
        if self.button then self.button:Show() else self:Build() end
        NS.Print("minimap button shown.")
    end
end
