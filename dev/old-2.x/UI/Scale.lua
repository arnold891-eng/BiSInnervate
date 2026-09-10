-- BiS Innervate :: Scale.lua
-- The "_" tab in the top-right corner of every window: click it and the whole
-- addon renders at half size. Click it again and it comes back.
--
-- Two things make this safe:
--   * SetScale on a frame that holds (or is anchored to) a secure button is a
--     protected call. The grid and the druid panel are exactly that, so those
--     two are deferred to the end of the fight; the board, the assignment
--     window and the mage's request button are plain frames and shrink at once.
--   * Position offsets are stored in each frame's own units, so a scaled frame
--     would drift toward its anchor. On every change the offsets are rescaled
--     and written back, which keeps a window exactly where the user left it.

local ADDON, NS = ...

local Scale = {}
NS.Scale = Scale

Scale.SMALL  = 0.5
Scale.tabs   = {}

local function factor()
    return (NS.db and NS.db.small) and Scale.SMALL or 1
end

-- What the X does, per window. None of these hide a protected frame during a
-- fight: the grid and the panel go to alpha 0 through their own Update, which
-- is a texture-level change and legal at any time.
local CLOSE = {
    pos       = function() NS.UI:ToggleHidden() end,
    gridPos   = function() NS.Grid:Toggle() end,
    boardPos  = function() NS.Board:Toggle() end,
    barPos    = function() NS.Bar:ToggleHidden() end,
    -- the assignment window already carries its own close box
}

-- every top-level window, and where its position is remembered
function Scale:Groups()
    local out = {}
    local function add(posKey, protected, tabOn, ...)
        local frames = {}
        for i = 1, select("#", ...) do
            local f = select(i, ...)
            if f then frames[#frames + 1] = f end
        end
        if #frames == 0 then return end
        -- the position lives on the first frame that survived: for a druid that
        -- is the secure header, for anyone else the panel itself
        out[#out + 1] = { frames = frames, posKey = posKey, posFrame = frames[1],
                          protected = protected or nil, tab = tabOn or frames[1],
                          close = CLOSE[posKey] }
    end

    local header = NS.Secure and NS.Secure.header
    local panel  = NS.UI and NS.UI.frame
    -- the header carries the secure rows; the panel is anchored to it, so the
    -- two only ever move and scale together. The tab goes on the panel, which
    -- is the part anyone can see.
    add("pos", header ~= nil, panel, header, panel)
    add("gridPos",   true,  nil, NS.Grid and NS.Grid.frame)
    add("boardPos",  false, nil, NS.Board and NS.Board.frame)
    add("assignPos", false, nil, NS.AssignWindow and NS.AssignWindow.frame)
    add("barPos",    false, nil, NS.Bar and NS.Bar.frame)
    return out
end

-- keep a window where it looks like it is: own-unit offsets scale with the frame
local function reposition(g, old, new)
    local f = g.posFrame
    if not f or not f.GetPoint or old == new or new == 0 then return end
    local point, _, rel, x, y = f:GetPoint()
    if not point then return end
    x, y = (x or 0) * old / new, (y or 0) * old / new
    local ok = pcall(f.SetPoint, f, point, UIParent, rel or point, x, y)
    if ok and g.posKey and NS.db then
        NS.db[g.posKey] = { point = point, rel = rel or point, x = x, y = y }
    end
end

function Scale:Apply(force, noReposition)
    local want = factor()
    local deferred = false

    for _, g in ipairs(self:Groups()) do
        local live = {}
        for _, f in ipairs(g.frames) do if f and f.SetScale then live[#live + 1] = f end end
        if #live > 0 then
            local old = (live[1].GetScale and live[1]:GetScale()) or 1
            if force or math.abs(old - want) > 0.001 then
                if g.protected and NS.InCombat() then
                    deferred = true
                else
                    for _, f in ipairs(live) do pcall(f.SetScale, f, want) end
                    if not noReposition then reposition(g, old, want) end
                end
            end
        end
    end

    self:ReanchorPanel(want)
    self.pending = deferred
    self:UpdateTabs()
    return deferred
end

-- The druid panel is anchored to the secure header with a fixed offset in the
-- panel's own units, so scaling both by the same factor still halves the gap on
-- screen and the panel slides down over the first row. Re-set it in screen px.
function Scale:ReanchorPanel(want)
    local header = NS.Secure and NS.Secure.header
    local panel  = NS.UI and NS.UI.frame
    if not header or not panel or NS.InCombat() then return end
    pcall(panel.SetPoint, panel, "TOPLEFT", header, "TOPLEFT", -4 / want, 22 / want)
end

function Scale:Toggle()
    if not NS.db then return end
    NS.db.small = not NS.db.small
    local deferred = self:Apply()
    if deferred then
        NS.Print(NS.db.small and "shrinking - the innervate squares resize when this fight ends."
                              or "back to full size - the squares follow when this fight ends.")
    else
        NS.Print(NS.db.small and "half size. Click |cffffff00_|r again for normal."
                              or "normal size.")
    end
end

-- the fight is over: anything we had to hold back can happen now
function Scale:AfterCombat()
    if not self.pending then return end
    self:Apply()
end

--------------------------------------------------------------------
-- the tab itself
--------------------------------------------------------------------

-- A small insecure button sitting just above the window's top-right corner.
-- Outside the frame on purpose: every window already has something in that
-- corner (a close box, a dropdown, a hint), and nothing here may overlap a
-- secure square.
local function chromeButton(frame, xOff, label)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(16, 13)
    b:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", xOff, 1)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.4, 0.5, 0.7, 0.4)

    local t = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t:SetPoint("CENTER", 0, 0)
    t:SetText(label)
    b.text = t
    return b
end

function Scale:AddTab(frame, close)
    if not frame or frame._scaleTab then return frame and frame._scaleTab end

    -- the settings tab, on every window, so the options are one click from
    -- whatever you happen to be looking at
    local cog = chromeButton(frame, close and -35 or -18, "cfg")
    cog:SetWidth(22)
    cog:SetScript("OnClick", function() NS.Config:Toggle() end)
    cog:SetScript("OnEnter", function(s)
        if not GameTooltip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Options")
        GameTooltip:AddLine("Everything the slash commands do, in one window.", 1, 1, 1)
        GameTooltip:AddLine("/inn config", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    cog:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame._cfgTab = cog

    if close then
        local x = chromeButton(frame, -1, "|cffff6060x|r")
        x:SetScript("OnClick", function() close() end)
        x:SetScript("OnEnter", function(s)
            if not GameTooltip then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Close this window")
            GameTooltip:AddLine("The minimap button brings it back.", 1, 1, 1)
            GameTooltip:Show()
        end)
        x:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        frame._closeTab = x
    end

    local b = CreateFrame("Button", nil, frame)
    b:SetSize(16, 13)
    b:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", close and -18 or -1, 1)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.4, 0.5, 0.7, 0.4)

    local t = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t:SetPoint("CENTER", 0, 2)
    t:SetText("_")
    b.text = t

    b:SetScript("OnClick", function() Scale:Toggle() end)
    b:SetScript("OnEnter", function(s)
        if not GameTooltip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine((NS.db and NS.db.small) and "Back to full size" or "Half size")
        GameTooltip:AddLine("Shrinks every BiS Innervate window.", 1, 1, 1)
        GameTooltip:AddLine("/inn small does the same.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    frame._scaleTab = b
    self.tabs[#self.tabs + 1] = b
    return b
end

function Scale:UpdateTabs()
    local small = NS.db and NS.db.small
    for _, b in ipairs(self.tabs) do
        if b.text then
            b.text:SetText(small and "+" or "_")
        end
    end
end

-- called once, at the end of a successful boot
function Scale:Attach()
    for _, g in ipairs(self:Groups()) do
        if g.tab then self:AddTab(g.tab, g.close) end
    end
    -- At login the saved offsets are ALREADY in the units of the saved scale -
    -- they were rescaled when the user pressed "_". Rescaling them again here
    -- doubles them, and doubles them once more on every reload, which walks
    -- every window off the edge of the screen for good.
    self:Apply(true, true)
end
