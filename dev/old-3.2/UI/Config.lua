-- BiS Innervate :: Config.lua
-- The options window, in the FojjiCore flat style on the BiS palette.
--
-- No Blizzard templates and no backdrop art anywhere: every surface is a plain
-- SetColorTexture, every border is four 1px textures, and depth comes from each
-- surface being a shade lighter as it comes forward.
--
-- The rule that matters more than the look: every control here writes the SAME
-- saved variable the slash commands already write, through the same function
-- where one exists. A checkbox that flips `db.small` by hand instead of calling
-- Scale:Toggle would drift from `/inn small` the first time either changed.
--
-- Everything lives on one table. Lua 5.1 allows 200 locals per chunk and a
-- window like this is twenty names if you let it be.

local ADDON, NS = ...

local CFG = {}
NS.Config = CFG

CFG.W, CFG.H     = 700, 500
CFG.HEADER       = 64
CFG.SIDEBAR      = 168
CFG.ROW          = 34
CFG.controls     = {}
CFG.pages        = {}
CFG.tabs         = {}

-- NS.T is BiSTheme when it is installed and the same values inline when it is
-- not, so this window and every other frame in the addon share one palette.
CFG.T = NS.T

-- the layered near-blacks, darkest (furthest back) to lightest (forward)
CFG.SH = {
    frame   = "0d0b18",
    header  = "141127",
    sidebar = "191531",
    content = "1f1a3a",
    field   = "17132e",
    hair    = "2a2446",
    edge    = "3a3260",
    accent  = "b980ff",
    ink     = "ece8f6",
    ink2    = "c6bedd",
    muted   = "968ead",
    dim     = "8e86a6",
    warn    = "f08cb0",
    gold    = "e5c04a",
    good    = "4fd0cf",
}

--------------------------------------------------------------------
-- primitives
--------------------------------------------------------------------

function CFG.hx(hex)
    hex = tostring(hex or "ffffff")
    return tonumber(string.sub(hex, 1, 2), 16) / 255,
           tonumber(string.sub(hex, 3, 4), 16) / 255,
           tonumber(string.sub(hex, 5, 6), 16) / 255
end

-- always returns four numbers. Every SetColorTexture call in this file goes
-- through here: `r, g, b = cond and T.rgba(...)` truncates to one value and the
-- client throws on the spot, taking the whole window with it.
function CFG.shade(name, a)
    local hex = CFG.SH[name]
    if hex then
        local r, g, b = CFG.hx(hex)
        return r, g, b, a or 1
    end
    -- anything not in the layered near-blacks comes from the shared palette
    return CFG.T.rgba(name, a or 1)
end

function CFG.tex(parent, layer, name, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(CFG.shade(name, a))
    return t
end

-- four 1px textures, with :set(name, a) to recolour all of them at once
function CFG.border(frame, name, a)
    local b = { }
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(CFG.shade(name, a))
        b[side] = t
    end
    b.top:SetPoint("TOPLEFT");     b.top:SetPoint("TOPRIGHT");     b.top:SetHeight(1)
    b.bottom:SetPoint("BOTTOMLEFT"); b.bottom:SetPoint("BOTTOMRIGHT"); b.bottom:SetHeight(1)
    b.left:SetPoint("TOPLEFT");    b.left:SetPoint("BOTTOMLEFT");   b.left:SetWidth(1)
    b.right:SetPoint("TOPRIGHT");  b.right:SetPoint("BOTTOMRIGHT"); b.right:SetWidth(1)
    function b:set(n, alpha)
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            self[side]:SetColorTexture(CFG.shade(n, alpha))
        end
    end
    return b
end

function CFG.fs(parent, text, size, name)
    local f = parent:CreateFontString(nil, "OVERLAY")
    pcall(f.SetFont, f, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12)
    if not f:GetFont() then f:SetFontObject("GameFontHighlightSmall") end
    local r, g, b = CFG.shade(name or "ink")
    f:SetTextColor(r, g, b, 1)
    f:SetText(text or "")
    f:SetJustifyH("LEFT")
    return f
end

--------------------------------------------------------------------
-- widgets. Each returns the next y and registers itself in CFG.controls.
--------------------------------------------------------------------

-- the usable width of whatever a widget is placed on: a whole page, or one
-- of the two columns a busy page is split into
function CFG.colW(page)
    return (page and page.colW) or (CFG.W - CFG.SIDEBAR - 60)
end

-- Two columns on one page. A page that ran long used to draw straight past the
-- bottom of the window; this keeps it inside without making the window bigger.
function CFG:Columns(page, leftFrac)
    leftFrac = leftFrac or 0.5
    local total = CFG.colW(page)
    local gutter = 24
    local lw = math.floor((total - gutter) * leftFrac)
    local rw = total - gutter - lw
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    left:SetWidth(lw)
    left.colW = lw
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", page, "TOPLEFT", lw + gutter, 0)
    right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    right.colW = rw
    return left, right
end

function CFG:Register(id, get, set, sync)
    self.controls[id] = { get = get, set = set, sync = sync }
end

function CFG:Caption(page, y, text)
    local f = CFG.fs(page, string.upper(text), 10, "dim")
    f:SetPoint("TOPLEFT", page, "TOPLEFT", 2, y)
    return y - 22
end

function CFG:Check(page, y, id, label, tip, get, set)
    local b = CreateFrame("Button", nil, page)
    b:SetSize(CFG.colW(page), 24)
    b:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)

    local box = CreateFrame("Frame", nil, b)
    box:SetSize(18, 18)
    box:SetPoint("LEFT", b, "LEFT", 2, 0)
    local fill = CFG.tex(box, "ARTWORK", "field")
    local edge = CFG.border(box, "edge")

    local text = CFG.fs(b, label, 12, "ink2")
    text:SetPoint("LEFT", box, "RIGHT", 10, 0)

    local sync = function()
        local on = get() and true or false
        -- both branches pass a full argument list on purpose
        if on then
            fill:SetColorTexture(CFG.shade("accent", 1))
            edge:set("accent", 1)
            text:SetTextColor(CFG.shade("ink"))
        else
            fill:SetColorTexture(CFG.shade("field", 1))
            edge:set("edge", 1)
            text:SetTextColor(CFG.shade("ink2"))
        end
    end

    b:SetScript("OnClick", function() set(not get()); CFG:Apply() end)
    b:SetScript("OnEnter", function(s)
        edge:set("accent", 1)
        if tip and GameTooltip then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        sync()
        if GameTooltip then GameTooltip:Hide() end
    end)

    self:Register(id, get, set, sync)
    sync()
    return y - self.ROW
end

-- a right-anchored pill group. options: { {value, label}, ... }
function CFG:Seg(page, y, id, label, options, get, set)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(CFG.colW(page), 26)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)

    local text = CFG.fs(row, label, 12, "ink2")
    text:SetPoint("LEFT", row, "LEFT", 2, 0)

    local pills = {}
    local x = 0
    -- pills shrink to fit the row: six of them at 78px ran over the label
    local rowW = CFG.colW(page)
    local pw = math.min(78, math.floor((rowW - 120 - 4 * (#options - 1)) / #options))
    for i = #options, 1, -1 do
        local opt = options[i]
        local p = CreateFrame("Button", nil, row)
        p:SetSize(pw, 22)
        p:SetPoint("RIGHT", row, "RIGHT", -x, 0)
        x = x + pw + 4
        local fill = CFG.tex(p, "ARTWORK", "field")
        local edge = CFG.border(p, "edge")
        local pt = CFG.fs(p, opt[2], 11, "ink2")
        pt:SetPoint("CENTER")
        pt:SetJustifyH("CENTER")
        p.value, p.fill, p.edge, p.text = opt[1], fill, edge, pt
        p:SetScript("OnClick", function(s) set(s.value); CFG:Apply() end)
        pills[#pills + 1] = p
    end

    local sync = function()
        local v = get()
        for _, p in ipairs(pills) do
            if p.value == v then
                p.fill:SetColorTexture(CFG.shade("accent", 0.22))
                p.edge:set("accent", 1)
                p.text:SetTextColor(CFG.shade("accent"))
            else
                p.fill:SetColorTexture(CFG.shade("field", 1))
                p.edge:set("edge", 1)
                p.text:SetTextColor(CFG.shade("ink2"))
            end
        end
    end

    self:Register(id, get, set, sync)
    sync()
    return y - self.ROW
end

function CFG:Slider(page, y, id, label, lo, hi, step, fmt, get, set)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(CFG.colW(page), 40)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)

    local text = CFG.fs(row, label, 12, "ink2")
    text:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)

    local value = CFG.fs(row, "", 12, "accent")
    value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)
    value:SetJustifyH("RIGHT")

    local track = CreateFrame("Frame", nil, row)
    track:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -20)
    track:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -20)
    track:SetHeight(6)
    track:EnableMouse(true)
    CFG.tex(track, "ARTWORK", "field")
    CFG.border(track, "hair")

    local fill = track:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 1, 1)
    fill:SetColorTexture(CFG.shade("accent", 0.85))
    fill:SetWidth(1)

    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetSize(10, 16)
    thumb:SetPoint("LEFT", track, "LEFT", 0, 0)
    CFG.tex(thumb, "OVERLAY", "accent")

    local clamp = function(v)
        v = tonumber(v) or lo
        if step and step > 0 then v = math.floor((v / step) + 0.5) * step end
        if v < lo then v = lo elseif v > hi then v = hi end
        return v
    end

    local sync = function()
        local v = clamp(get())
        local w = (track.GetWidth and track:GetWidth()) or (CFG.colW(page) - 4)
        if not w or w <= 2 then w = CFG.colW(page) - 4 end
        local frac = (hi > lo) and ((v - lo) / (hi - lo)) or 0
        fill:SetWidth(math.max(1, (w - 2) * frac))
        thumb:SetPoint("LEFT", track, "LEFT", math.max(0, (w * frac) - 5), 0)
        value:SetText(string.format(fmt or "%d", v))
    end

    local fromCursor = function()
        if not GetCursorPosition then return end
        local cx = GetCursorPosition()
        local scale = (track.GetEffectiveScale and track:GetEffectiveScale()) or 1
        if not cx or not scale or scale <= 0 then return end
        local left = (track.GetLeft and track:GetLeft())
        local w    = (track.GetWidth and track:GetWidth())
        if not left or not w or w <= 0 then return end
        local frac = ((cx / scale) - left) / w
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        set(clamp(lo + frac * (hi - lo)))
        CFG:Apply()
    end

    track:SetScript("OnMouseDown", function(s) s.dragging = true; fromCursor() end)
    track:SetScript("OnMouseUp",   function(s) s.dragging = false end)
    track:SetScript("OnUpdate",    function(s) if s.dragging then fromCursor() end end)

    -- clamping lives in the setter too, so ConfigSet and the drag agree
    self:Register(id, get, function(v) set(clamp(v)) end, sync)
    sync()
    return y - 46
end

function CFG:Btn(page, y, id, label, tip, onclick, name)
    local b = CreateFrame("Button", nil, page)
    b:SetSize(150, 24)
    b:SetPoint("TOPLEFT", page, "TOPLEFT", 2, y)
    local fill = CFG.tex(b, "ARTWORK", "field")
    local edge = CFG.border(b, "edge")
    local t = CFG.fs(b, label, 12, name or "ink2")
    t:SetPoint("CENTER")
    t:SetJustifyH("CENTER")

    b:SetScript("OnClick", function() onclick(); CFG:Apply() end)
    b:SetScript("OnEnter", function(s)
        fill:SetColorTexture(CFG.shade(name or "accent", 0.18))
        edge:set(name or "accent", 1)
        if tip and GameTooltip then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        fill:SetColorTexture(CFG.shade("field", 1))
        edge:set("edge", 1)
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- a button is an action, not a setting: it is not in `controls`, so
    -- ConfigSet cannot fire it by accident and ConfigGet never lies about it
    self.actions = self.actions or {}
    self.actions[id] = onclick
    return y - 32
end

function CFG:Run(id)
    self:Build()
    local fn = self.actions and self.actions[id]
    if fn then fn(); self:Apply(); return true end
    return false
end

--------------------------------------------------------------------
-- live effects
--------------------------------------------------------------------

-- Reached through NS.*, never a bare local: the window module is declared in
-- a file that loads before this one, but the rule is the rule.
function CFG:Apply()
    if NS.Window then
        NS.Window:ApplyScale()
        NS.Window:Refresh()
    end
    self:Refresh()
end

function CFG:Refresh()
    for _, c in pairs(self.controls) do
        if c.sync then pcall(c.sync) end
    end
end

-- a toggle the slash command owns: only call it when the answer would change,
-- so the window and the command can never disagree about what "on" means
function CFG.flip(currentIsOn, want, toggle)
    if (want and true or false) ~= (currentIsOn and true or false) then toggle() end
end

--------------------------------------------------------------------
-- pages
--------------------------------------------------------------------

CFG.PAGES = { "Window", "Alerts", "Calls", "About" }

function CFG:BuildWindow(page0)
    local db = function() return NS.db end
    local page, right = self:Columns(page0, 0.56)
    local y = -4
    y = self:Caption(page, y, "size and place")
    y = self:Slider(page, y, "scale", "Window scale", 0.5, 2, 0.05, "%.2f",
        function() return db().scale or 1 end, function(v) db().scale = v end)
    y = self:Check(page, y, "shown", "Window shown",
        "Same as the x in the corner. Cannot change mid-fight - the faces are secure buttons.",
        function() return not db().hidden end,
        function(v) CFG.flip(not db().hidden, v, function() NS.Window:ToggleShown() end) end)
    y = self:Check(page, y, "locked", "Lock the window in place", nil,
        function() return db().locked and true or false end,
        function(v) db().locked = v and true or false end)
    y = self:Check(page, y, "minimap", "Minimap button",
        "Left-click shows or hides the window, right-click opens this.",
        function() return db().minimap ~= false end,
        function(v) NS.Minimap:Set(v) end)
    y = self:Check(page, y, "magesOnly", "Mages only  (Odiss mode)",
        "Just the mage faces, no button row, and the window is only as big as they are - it grows and shrinks as mages come and go. Same as the M in the corner. Mid-fight it waits for the fight to end.",
        function() return db().magesOnly and true or false end,
        function(v) NS.Window:SetMagesOnly(v) end)

    y = -4
    y = self:Caption(right, y, "drums")
    y = self:Seg(right, y, "flyoutDir", "Types unfold",
        { { "up", "Up" }, { "down", "Down" } },
        function() return db().flyoutDir or "up" end,
        function(v) db().flyoutDir = v; NS.Window:PlaceFlyout() end)

    y = self:Caption(right, y - 6, "faces")
    y = self:Seg(right, y, "portraits3d", "Portraits",
        { { false, "Flat" }, { true, "3D" } },
        function() return db().portraits3d and true or false end,
        function(v)
            db().portraits3d = v and true or false
            if not NS.InCombat() then NS.Window:RefreshPortraits() end
        end)

    y = self:Btn(right, y - 6, "reset", "Put the window back",
        "Default place and size, shown, unlocked.",
        function() NS.HandleSlash("reset") end, "warn")
    return page
end

function CFG:BuildAlerts(page)
    local db = function() return NS.db end
    local y = -4
    y = self:Caption(page, y, "sound")
    y = self:Check(page, y, "sound", "Play sounds",
        "A druid hears a ping when anyone calls; a caller hears when it is taken and when it lands.",
        function() return db().sound ~= false end,
        function(v) db().sound = v and true or false end)
    y = self:Check(page, y, "chatAlert", "Say it in chat too", nil,
        function() return db().chatAlert ~= false end,
        function(v) db().chatAlert = v and true or false end)

    y = self:Caption(page, y - 6, "voice pack  (FojjiCore, when installed)")
    local opts = { { "auto", "Auto" }, { "off", "Off" } }
    local packs = NS.Sound:VoicePacks()
    for i = 1, math.min(#packs, 4) do opts[#opts + 1] = { packs[i], packs[i] } end
    y = self:Seg(page, y, "voice", "Voice", opts,
        function() return db().voice or "auto" end,
        function(v) db().voice = v end)
    if #packs == 0 then
        local note = CFG.fs(page, "No voice packs found. Install FojjiCore and its packs; \"Auto\" picks the first pack that has our lines.", 10, "dim")
        note:SetPoint("TOPLEFT", page, "TOPLEFT", 2, y)
        y = y - 20
    elseif #packs > 4 then
        local note = CFG.fs(page, #packs .. " packs installed - /inn voice <name> for the rest.", 10, "dim")
        note:SetPoint("TOPLEFT", page, "TOPLEFT", 2, y)
        y = y - 20
    end
    y = self:Btn(page, y, "voiceTest", "Test the alert", nil, function() NS.Sound:Test() end)
    return page
end

function CFG:BuildCalls(page0)
    local db = function() return NS.db end
    local page, right = self:Columns(page0, 0.56)
    local y = -4
    y = self:Caption(page, y, "a call")
    y = self:Slider(page, y, "expire", "Give up after", 10, 300, 5, "%ds",
        function() return db().expire end, function(v) db().expire = v end)
    y = self:Slider(page, y, "cancelMana", "Cancel once back above", 30, 100, 1, "%d%% mana",
        function() return db().cancelMana end, function(v) db().cancelMana = v end)
    y = self:Slider(page, y, "urgentAt", "Nag me under", 1, 90, 1, "%d%% mana",
        function() return db().urgentAt end, function(v) db().urgentAt = v end)

    y = self:Caption(page, y - 6, "a druid's click")
    y = self:Slider(page, y, "claimHold", "Lock a face for", 3, 30, 1, "%ds",
        function() return db().claimHold end, function(v) db().claimHold = v end)
    local note = CFG.fs(page, "If it has not landed by then, the face pulses for everyone again.", 10, "dim")
    note:SetPoint("TOPLEFT", page, "TOPLEFT", 2, y)
    note:SetWidth(CFG.colW(page) - 4)
    if note.SetWordWrap then note:SetWordWrap(true) end
    y = y - 30

    -- the class list goes in the right-hand column
    y = -4
    y = self:Caption(right, y, "who may call")
    for _, class in ipairs({ "MAGE", "PRIEST", "PALADIN", "SHAMAN", "DRUID", "WARLOCK", "HUNTER" }) do
        local label = string.sub(class, 1, 1) .. string.lower(string.sub(class, 2))
        y = self:Check(right, y, "class" .. class, label, nil,
            function() return (db().requesterClasses or {})[class] and true or false end,
            function(v)
                db().requesterClasses = db().requesterClasses or {}
                db().requesterClasses[class] = v and true or false
                if not NS.InCombat() then NS.Window:Bind() end
            end)
    end
    return page
end

function CFG:BuildAbout(page)
    local y = -4
    y = self:Caption(page, y, "how it works")
    local lines = {
        "One window, the same on every screen in the raid.",
        "Four icons: Mana Tide, Innervate, Bloodlust, Drums. Grey = nobody in reach.",
        "Tide and Drums come from someone in YOUR group; Bloodlust from any shaman in the raid.",
        "Hover Drums to ask for one type in particular; a plain click asks for any.",
        "Bloodlust greys while you are Exhausted, Drums while you have Tinnitus.",
        "Below, everyone with the addon who uses mana. A caller's face pulses violet.",
        "A druid clicks a pulsing face to innervate them. That face greys for every",
        "other druid on the spot, so nobody gets three. The rest keep pulsing.",
        "Faces are bound before the pull and never touched during it - that is what",
        "lets a click cast in combat. New people in the raid appear after the fight.",
        "Only people with the addon take part. No whispers, no assignments.",
    }
    for _, l in ipairs(lines) do
        local t = CFG.fs(page, l, 11, "ink2")
        t:SetPoint("TOPLEFT", page, "TOPLEFT", 2, y)
        y = y - 16
    end
    y = self:Caption(page, y - 10, "commands")
    local t = CFG.fs(page, "/inn  /inn tide  /inn cancel  /inn show  /inn scale <n>  /inn voice  /inn demo  /inn reset", 11, "muted")
    t:SetPoint("TOPLEFT", page, "TOPLEFT", 2, y)
    y = y - 22
    self:Btn(page, y, "demo", "Show me the druid's view", "Fake callers, harmless clicks. /inn demo again to stop.",
        function() NS.Demo:Toggle() end)
    return page
end

--------------------------------------------------------------------
-- the frame
--------------------------------------------------------------------

function CFG:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "BiSInnervateConfig", UIParent)
    f:SetSize(self.W, self.H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    CFG.tex(f, "BACKGROUND", "frame")
    CFG.border(f, "edge")

    -- header
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(self.HEADER)
    CFG.tex(head, "BACKGROUND", "header")
    local hair = head:CreateTexture(nil, "BORDER")
    hair:SetPoint("BOTTOMLEFT"); hair:SetPoint("BOTTOMRIGHT"); hair:SetHeight(1)
    hair:SetColorTexture(CFG.shade("edge", 1))

    local logo = head:CreateTexture(nil, "ARTWORK")
    logo:SetSize(28, 28)
    logo:SetPoint("LEFT", head, "LEFT", 20, 0)
    logo:SetTexture("Interface\\Icons\\Spell_Nature_Lightning")
    if logo.SetTexCoord then logo:SetTexCoord(0.07, 0.93, 0.07, 0.93) end

    local title = CFG.fs(head, "", 18, "ink")
    title:SetPoint("LEFT", logo, "RIGHT", 12, 1)
    title:SetText("BiS |cffb980ffInnervate|r")

    local ver = CFG.fs(head, "v" .. (NS.VERSION or "?"), 11, "dim")
    ver:SetPoint("LEFT", title, "RIGHT", 10, -1)

    local close = CreateFrame("Button", nil, head)
    close:SetSize(26, 26)
    close:SetPoint("RIGHT", head, "RIGHT", -16, 0)
    local closeFill = CFG.tex(close, "ARTWORK", "field")
    local closeEdge = CFG.border(close, "edge")
    local closeText = CFG.fs(close, "x", 13, "ink2")
    closeText:SetPoint("CENTER")
    closeText:SetJustifyH("CENTER")
    close:SetScript("OnClick", function() CFG:Hide() end)
    close:SetScript("OnEnter", function()
        closeFill:SetColorTexture(CFG.shade("warn", 0.2))
        closeEdge:set("warn", 1)
        closeText:SetTextColor(CFG.shade("warn"))
    end)
    close:SetScript("OnLeave", function()
        closeFill:SetColorTexture(CFG.shade("field", 1))
        closeEdge:set("edge", 1)
        closeText:SetTextColor(CFG.shade("ink2"))
    end)

    -- sidebar
    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    rail:SetWidth(self.SIDEBAR)
    CFG.tex(rail, "BACKGROUND", "sidebar")
    local divider = rail:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPRIGHT"); divider:SetPoint("BOTTOMRIGHT"); divider:SetWidth(1)
    divider:SetColorTexture(CFG.shade("edge", 1))

    -- content
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", rail, "TOPRIGHT", 1, 0)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    CFG.tex(body, "BACKGROUND", "content")

    local builders = {
        Window = function(p) return CFG:BuildWindow(p) end,
        Alerts = function(p) return CFG:BuildAlerts(p) end,
        Calls  = function(p) return CFG:BuildCalls(p) end,
        About  = function(p) return CFG:BuildAbout(p) end,
    }

    for i, name in ipairs(self.PAGES) do
        local tab = CreateFrame("Button", nil, rail)
        tab:SetSize(self.SIDEBAR, 40)
        tab:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -12 - ((i - 1) * 42))

        local glow = tab:CreateTexture(nil, "ARTWORK")
        glow:SetAllPoints()
        glow:SetColorTexture(CFG.shade("accent", 0.10))
        glow:Hide()

        local mark = tab:CreateTexture(nil, "OVERLAY")
        mark:SetPoint("TOPLEFT"); mark:SetPoint("BOTTOMLEFT"); mark:SetWidth(3)
        mark:SetColorTexture(CFG.shade("accent", 1))
        mark:Hide()

        local label = CFG.fs(tab, name, 13, "muted")
        label:SetPoint("LEFT", tab, "LEFT", 20, 0)

        tab.glow, tab.mark, tab.label, tab.tabName = glow, mark, label, name
        tab:SetScript("OnClick", function(s) CFG:ShowTab(s.tabName) end)
        tab:SetScript("OnEnter", function(s)
            if CFG.shown ~= s.tabName then s.label:SetTextColor(CFG.shade("ink2")) end
        end)
        tab:SetScript("OnLeave", function(s)
            if CFG.shown ~= s.tabName then s.label:SetTextColor(CFG.shade("muted")) end
        end)
        self.tabs[name] = tab

        local page = CreateFrame("Frame", nil, body)
        page:SetPoint("TOPLEFT", body, "TOPLEFT", 24, -20)
        page:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -24, 20)
        pcall(page.SetClipsChildren, page, true)      -- never draw past the window again
        page:Hide()
        builders[name](page)
        self.pages[name] = page
    end

    if UISpecialFrames then table.insert(UISpecialFrames, "BiSInnervateConfig") end

    self.frame = f
    self:ShowTab(self.PAGES[1])
    f:Hide()
    return f
end

function CFG:ShowTab(name)
    if not self.frame or not self.pages[name] then return end
    self.shown = name
    for tabName, tab in pairs(self.tabs) do
        local on = (tabName == name)
        if on then
            tab.glow:Show(); tab.mark:Show()
            tab.label:SetTextColor(CFG.shade("accent"))
        else
            tab.glow:Hide(); tab.mark:Hide()
            tab.label:SetTextColor(CFG.shade("muted"))
        end
        if self.pages[tabName] then
            if on then self.pages[tabName]:Show() else self.pages[tabName]:Hide() end
        end
    end
end

function CFG:Open()
    self:Build()
    self:Refresh()
    self.frame:Show()
end

function CFG:Hide()
    if self.frame then self.frame:Hide() end
end

-- the header button and /inn config both land here; it toggles, so the same
-- click opens and closes
function CFG:Toggle()
    self:Build()
    if self.frame:IsShown() then self:Hide() else self:Open() end
end

--------------------------------------------------------------------
-- driving it without a screen
--------------------------------------------------------------------

function CFG:Set(id, value)
    self:Build()
    local c = self.controls[id]
    if not c then return false end
    c.set(value)
    self:Apply()
    return true
end

function CFG:Get(id)
    self:Build()
    local c = self.controls[id]
    if not c then return nil end
    return c.get()
end

function CFG:IDs()
    self:Build()
    local out = {}
    for id in pairs(self.controls) do out[#out + 1] = id end
    table.sort(out)
    return out
end
