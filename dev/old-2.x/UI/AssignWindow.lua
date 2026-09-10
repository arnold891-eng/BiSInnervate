-- BiS Innervate :: AssignWindow.lua
-- The assignment board as a window instead of a slash command:
--
--     [inn]  Barky    covers  [ Kumlust  v ]   x
--     [inn]  Treebo   covers  [ Healbot  v ]   x
--     [tide] Tidely   covers  [ Group 1  v ]   x
--
-- One row per provider actually in the raid. Nothing here fires on its own -
-- an assignment only decides who gets the request when that player asks.
-- Plain frames only, never touched in combat.

local ADDON, NS = ...
local T = NS.T

local AW = {}
NS.AssignWindow = AW

local ROWS      = 12
local ROW_H     = 24
local WIDTH     = 320

--------------------------------------------------------------------
-- who can a given provider be pointed at?
--------------------------------------------------------------------

function AW:TargetsFor(provider, kind)
    local out = {}
    NS.ForEachMember(function(unit, name, class)
        if name ~= provider and NS.IsRequesterClass(class) then
            if kind ~= "TIDE" or NS.SameGroup(name, provider) then
                out[#out + 1] = { name = name, class = class, group = NS.Subgroup(name) }
            end
        end
    end)
    table.sort(out, function(a, b)
        local aw = NS.ROLE_WEIGHT[a.class or ""] or 2
        local bw = NS.ROLE_WEIGHT[b.class or ""] or 2
        if aw ~= bw then return aw < bw end
        return a.name < b.name
    end)
    return out
end

function AW:Providers()
    local out = {}
    for _, kind in ipairs(NS.KINDS) do
        for _, d in ipairs(NS.Tracker:AssignOrder(nil, kind)) do
            out[#out + 1] = { name = d.name, kind = kind, group = d.group, cd = d.cd }
        end
    end
    return out
end

--------------------------------------------------------------------
-- dropdown
--------------------------------------------------------------------

function AW:Menu()
    if self.menu then return self.menu end
    local m = CreateFrame("Frame", "BiSInnervateAssignMenu", UIParent)
    m:SetFrameStrata("DIALOG")
    m:SetWidth(150)
    m:EnableMouse(true)                       -- do not leak clicks to whatever is behind
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.rgba("surface", 0.97))
    m.buttons = {}
    m:Hide()
    self.menu = m
    return m
end

-- items: { {text=, key=, checked=bool}, ... }   onPick(key, item)
function AW:OpenMenu(anchor, items, onPick, guard)
    local m = self:Menu()
    if m:IsShown() and m.owner == anchor then m:Hide() return end
    m.owner = anchor
    m.guard = guard

    for i, opt in ipairs(items) do
        local b = m.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, m)
            b:SetHeight(18)
            b:SetPoint("TOPLEFT", m, "TOPLEFT", 3, -3 - ((i - 1) * 18))
            b:SetPoint("RIGHT", m, "RIGHT", -3, 0)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(T.rgba("slate", 0.35))
            local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            t:SetPoint("LEFT", 4, 0)
            b.text = t
            m.buttons[i] = b
        end
        b.text:SetText((opt.checked and (T.text("good", "v") .. " ") or (T.text("dim", "-") .. " ")) .. (opt.text or "?"))
        b:SetScript("OnClick", function()
            m:Hide()
            -- rows re-sort as mana changes, so make sure the row this menu was
            -- opened on still belongs to the same provider before acting
            if m.guard and not m.guard() then
                NS.Print("that row changed - reopen the list.")
                AW:Refresh()
                return
            end
            onPick(opt.key, opt)
            AW:Refresh()
        end)
        b:Show()
    end
    for i = #items + 1, #m.buttons do m.buttons[i]:Hide() end

    m:SetHeight(6 + #items * 18)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    m:Show()
end

-- the "covers ..." dropdown on a provider row
function AW:OpenTargetMenu(anchor, provider, kind)
    local items = { { text = T.text("muted", "-- nobody --"), key = false } }
    for _, t in ipairs(self:TargetsFor(provider, kind)) do
        items[#items + 1] = {
            text = NS.ClassColored(t.name, t.class) .. (t.group and (" " .. T.text("muted", "g" .. t.group)) or ""),
            key  = t.name,
            checked = (NS.Assign:For(provider) or {}).target == t.name,
        }
    end
    self:OpenMenu(anchor, items, function(key)
        if key then NS.Assign:Set(provider, key) else NS.Assign:Clear(provider) end
    end, function() return anchor:GetParent().provider == provider end)
end

-- the raid-wide "who can edit this board" dropdown at the top
function AW:OpenEditorMenu(anchor)
    local items = {}
    NS.ForEachMember(function(unit, name, class)
        local lead = (UnitIsGroupLeader and UnitIsGroupLeader(unit))
                  or (UnitIsGroupAssistant and UnitIsGroupAssistant(unit))
        items[#items + 1] = {
            text = NS.ClassColored(name, class) .. (lead and (" " .. T.text("muted", "(lead)")) or ""),
            key  = name,
            checked = lead or NS.Assign:IsEditor(name),
            lead = lead,
        }
    end)
    table.sort(items, function(a, b) return a.key < b.key end)
    self:OpenMenu(anchor, items, function(key, item)
        if item.lead then return end          -- lead and assists always have it
        NS.Assign:SetEditor(key, not NS.Assign:IsEditor(key))
    end)
end

--------------------------------------------------------------------
-- window
--------------------------------------------------------------------

function AW:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "BiSInnervateAssignFrame", UIParent)
    f:SetSize(WIDTH, 58 + ROWS * ROW_H)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetScript("OnDragStart", function(s) if not NS.InCombat() then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local point, _, rel, x, y = s:GetPoint()
        NS.db.assignPos = { point = point, rel = rel, x = x, y = y }
    end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.rgba("bg", 0.95))

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Innervate assignments")
    title:SetTextColor(T.rgb("accent"))

    -- "who can edit" dropdown: whole raid, tick beside anyone allowed
    local who = CreateFrame("Button", nil, f)
    who:SetSize(150, 18)
    who:SetPoint("TOPRIGHT", -28, -7)
    local wbg = who:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints()
    wbg:SetColorTexture(T.rgba("sunken", 0.9))
    local whl = who:CreateTexture(nil, "HIGHLIGHT")
    whl:SetAllPoints()
    whl:SetColorTexture(T.rgba("slate", 0.35))
    local wt = who:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wt:SetPoint("LEFT", 5, 0)
    who.text = wt
    local wa = who:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wa:SetPoint("RIGHT", -4, 0)
    wa:SetText("v")
    who:SetScript("OnClick", function(s)
        if not NS.Assign:IsRaidLeader() then
            NS.Print("only the raid lead can hand out assignment rights.")
            return
        end
        AW:OpenEditorMenu(s)
    end)
    who:SetScript("OnEnter", function(s)
        if not GameTooltip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Who can set assignments")
        GameTooltip:AddLine("Lead and assists always can. Click a name to give or take it away.", T.rgb("ink"))
        GameTooltip:Show()
    end)
    who:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.who = who

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 10, -26)
    f.hint = hint

    local close = CreateFrame("Button", nil, f)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -6, -6)
    local ct = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ct:SetPoint("CENTER")
    ct:SetText(T.text("warn", "x"))
    close:SetScript("OnClick", function() AW:Hide() end)

    self.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(WIDTH - 16, ROW_H - 2)
        row:SetPoint("TOPLEFT", 8, -42 - ((i - 1) * ROW_H))

        local who = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        who:SetPoint("LEFT", 2, 0)
        who:SetWidth(110)
        who:SetJustifyH("LEFT")
        row.who = who

        local mid = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        mid:SetPoint("LEFT", who, "RIGHT", 2, 0)
        mid:SetText("covers")

        -- target dropdown
        local drop = CreateFrame("Button", nil, row)
        drop:SetSize(130, 18)
        drop:SetPoint("LEFT", mid, "RIGHT", 4, 0)
        local dbg = drop:CreateTexture(nil, "BACKGROUND")
        dbg:SetAllPoints()
        dbg:SetColorTexture(T.rgba("sunken", 0.9))
        local dhl = drop:CreateTexture(nil, "HIGHLIGHT")
        dhl:SetAllPoints()
        dhl:SetColorTexture(T.rgba("slate", 0.35))
        local dt = drop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dt:SetPoint("LEFT", 5, 0)
        drop.text = dt
        local arrow = drop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        arrow:SetPoint("RIGHT", -4, 0)
        arrow:SetText("v")
        drop:SetScript("OnClick", function(s)
            if not NS.Assign:CanEdit() then NS.Assign:Denied() return end
            AW:OpenTargetMenu(s, row.provider, row.kind)
        end)
        row.drop = drop

        local clear = CreateFrame("Button", nil, row)
        clear:SetSize(16, 16)
        clear:SetPoint("LEFT", drop, "RIGHT", 8, 0)
        local xt = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        xt:SetPoint("CENTER")
        xt:SetText(T.text("muted", "x"))
        clear:SetScript("OnClick", function()
            if not NS.Assign:CanEdit() then NS.Assign:Denied() return end
            NS.Assign:Clear(row.provider)
            AW:Refresh()
        end)
        row.clear = clear

        row:Hide()
        self.rows[i] = row
    end

    local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", 12, -46)
    empty:SetText("No druids or mana tide shamans found.")
    empty:Hide()
    f.empty = empty

    local pos = NS.db.assignPos
    if pos then
        f:SetPoint(pos.point or "CENTER", UIParent, pos.rel or "CENTER", pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    f:Hide()

    -- Escape closes the board like any other window
    if UISpecialFrames then table.insert(UISpecialFrames, "BiSInnervateAssignFrame") end
    f:SetScript("OnHide", function() if AW.menu then AW.menu:Hide() end end)

    self.frame = f
    table.insert(NS.UI.refreshHooks, function() if AW.frame and AW.frame:IsShown() then AW:Refresh() end end)
    return f
end

function AW:Refresh()
    if not self.frame then return end
    NS.Tracker:UpdateRoster()
    if self.menu and self.menu:IsShown() and self.menu.guard and not self.menu.guard() then
        self.menu:Hide()
    end

    local canEdit = NS.Assign:CanEdit()
    local editors = NS.Assign:EditorList()
    if self.frame.who then
        self.frame.who.text:SetText(#editors == 0 and T.text("muted", "lead only")
            or T.text("ink", "+" .. #editors .. " can edit"))
    end
    self.frame.hint:SetText(canEdit and T.text("muted", "click a name to set who covers them")
                                     or T.text("warn", "you cannot edit this board"))

    local list = self:Providers()
    for i = 1, ROWS do
        local row = self.rows[i]
        local p = list[i]
        if p then
            row.provider, row.kind = p.name, p.kind
            local tag = (p.kind == "TIDE") and "|cff40d0d0tide|r" or "|cff7fdf7finn|r"
            row.who:SetText(string.format("%s %s%s", tag, NS.ClassColored(p.name),
                p.group and (" " .. T.text("muted", "g" .. p.group)) or ""))

            local a = NS.Assign:For(p.name)
            row.drop.text:SetText(a and NS.ClassColored(a.target) or T.text("muted", "nobody"))
            row.clear:SetShown(a ~= nil)
            row:Show()
        else
            row.provider = nil
            row:Hide()
        end
    end

    self.frame.empty:SetShown(#list == 0)
end

function AW:Show()
    self:Build()
    self:Refresh()
    self.frame:Show()
end

function AW:Hide()
    if self.menu then self.menu:Hide() end
    if self.frame then self.frame:Hide() end
end

function AW:Toggle()
    self:Build()
    if self.frame:IsShown() then self:Hide() else self:Show() end
end
