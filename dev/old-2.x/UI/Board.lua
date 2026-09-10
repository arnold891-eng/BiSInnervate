-- BiS Innervate :: Board.lua
-- Raid cooldown board: every innervate and every mana tide in the raid with a
-- live timer. Only useful when the raid is on the addon, which is the point.
-- Plain frames, no secure anything, so it is safe to build and update in combat.

local ADDON, NS = ...
local T = NS.T

local Board = {}
NS.Board = Board

local ROWS = 12

local KIND_TAG = {
    INNERVATE = "|cff7fdf7fINN|r",
    TIDE      = "|cff40d0d0TIDE|r",
}

function Board:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "BiSInnervateBoard", UIParent)
    f:SetSize(230, 30 + ROWS * 16)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(s) if not NS.InCombat() then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local point, _, rel, x, y = s:GetPoint()
        NS.db.boardPos = { point = point, rel = rel, x = x, y = y }
    end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.rgba("bg", 0.9))

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("Mana cooldowns")
    title:SetTextColor(T.rgb("accent"))

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", -8, -7)
    hint:SetText("/inn board")

    self.rows = {}
    for i = 1, ROWS do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 8, -24 - ((i - 1) * 16))
        fs:SetPoint("RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(T.rgb("ink"))
        fs:SetText("")
        self.rows[i] = fs
    end

    local pos = NS.db.boardPos
    if pos then
        f:SetPoint(pos.point or "CENTER", UIParent, pos.rel or "CENTER", pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -300, 100)
    end
    f:Hide()

    self.frame = f
    table.insert(NS.UI.refreshHooks, function() Board:Update() end)
    return f
end

function Board:Toggle()
    self:Build()
    NS.db.board = not NS.db.board
    if NS.db.board then self:Update() else self.frame:Hide() end
    NS.Print("cooldown board " .. (NS.db.board and "shown." or "hidden."))
end

function Board:Update()
    if not self.frame then return end
    if not NS.db.board or not NS.InGroup() then self.frame:Hide() return end

    local lines = {}
    for _, kind in ipairs(NS.KINDS) do
        for _, d in ipairs(NS.Tracker:AssignOrder(nil, kind)) do
            lines[#lines + 1] = { kind = kind, name = d.name, cd = d.cd, group = d.group, addon = d.hasAddon }
        end
    end
    table.sort(lines, function(a, b)
        if (a.cd > 0) ~= (b.cd > 0) then return a.cd < b.cd end
        if a.cd ~= b.cd then return a.cd < b.cd end
        return a.name < b.name
    end)

    local ready = 0
    for i = 1, ROWS do
        local l = lines[i]
        local fs = self.rows[i]
        if l then
            if l.cd <= 0 then ready = ready + 1 end
            fs:SetText(string.format("%s %s%s  %s%s",
                KIND_TAG[l.kind] or "?",
                l.name,
                l.group and (" " .. T.text("muted", "g" .. l.group)) or "",
                l.cd > 0 and T.text("gold", NS.TimeStr(l.cd)) or T.text("good", "ready"),
                l.addon and "" or (" " .. T.text("muted", "(no addon)"))))
        else
            fs:SetText("")
        end
    end
    self.frame:Show()
end
