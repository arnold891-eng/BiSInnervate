-- BiS Innervate :: Window.lua
-- The one window everybody sees. Same layout on every screen in the raid:
--
--     +----------------------------------------+
--     | [~] BiS Innervate            cfg  _  x |
--     |  [tide][inn][lust][drums][rez]         |   <- ask (or cast, if it is yours)
--     |     the rez one: a healer's rez/heal/drink button; "rez me first" for the rest
--     |  [face][face][face][face][face][face]  |   <- everyone with the addon who uses mana
--     |  [face][face]                          |      callers pulse; a claimed one greys out
--     +----------------------------------------+
--
-- What differs per class is only what is lit: a mage can press the two ask
-- buttons and sees the grid greyed; a druid's grid is live - each face is a
-- secure button bound to that player, and clicking it casts Innervate on them.
--
-- Combat rules, unchanged from 2.x because they are what kept it working:
--   * the faces are bound OUT of combat, to the player's NAME (raid slots
--     renumber mid-fight; names do not), and never rebound during a fight
--   * during a fight only colour, alpha, texture size and text change
--   * the window holds secure children, so it is never shown, hidden, moved or
--     scaled in combat - closing it is alpha, and the rest waits for the pull
--     to end

local ADDON, NS = ...
local T = NS.T

local W = {}
NS.Window = W

-- Compact on purpose: raid screens are full. Icons carry the state, tooltips
-- carry the words. Faces are 20px, the two spell icons 26px, side by side.
W.SIZE, W.GAP, W.PER_ROW, W.MAX = 20, 3, 6, 40
W.PAD      = 5
W.HEADER   = 16
-- five 26px buttons in the row (the fifth is the rez module's) set the width
W.BTN_H    = 26
W.N_BTNS   = 5
W.width    = math.max(W.PAD * 2 + W.PER_ROW * (W.SIZE + W.GAP) - W.GAP,
                      W.PAD * 2 + W.N_BTNS * W.BTN_H + (W.N_BTNS - 1) * W.GAP, 120)
-- "mages only" (Odiss mode): no button row, just the mage faces in one strip
-- that wraps at 8, and the window is exactly as wide as they are
W.PER_ROW_MAGES = 8
W.MINW_MAGES    = 64       -- logo + H + M + x still have to fit in the title bar
W.BODY_A   = 0.01      -- the body is all but see-through; the title bar is half
W.HEAD_A   = 0.5
W.squares  = {}
W.byName   = {}
W.SH = { frame = "0d0b18", header = "141127", body = "1f1a3a", field = "17132e",
         hair = "2a2446", edge = "3a3260" }

--------------------------------------------------------------------
-- paint helpers (every colour call passes a full argument list)
--------------------------------------------------------------------

function W.col(name, a)
    local hex = W.SH[name]
    if hex then
        return tonumber(string.sub(hex, 1, 2), 16) / 255,
               tonumber(string.sub(hex, 3, 4), 16) / 255,
               tonumber(string.sub(hex, 5, 6), 16) / 255, a or 1
    end
    return T.rgba(name, a or 1)
end

function W.fill(parent, layer, name, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(W.col(name, a))
    return t
end

function W.border(frame, name, a, thick)
    local b = {}
    thick = thick or 1
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(W.col(name, a))
        b[side] = t
    end
    b.top:SetPoint("TOPLEFT");      b.top:SetPoint("TOPRIGHT");      b.top:SetHeight(thick)
    b.bottom:SetPoint("BOTTOMLEFT"); b.bottom:SetPoint("BOTTOMRIGHT"); b.bottom:SetHeight(thick)
    b.left:SetPoint("TOPLEFT");     b.left:SetPoint("BOTTOMLEFT");    b.left:SetWidth(thick)
    b.right:SetPoint("TOPRIGHT");   b.right:SetPoint("BOTTOMRIGHT");  b.right:SetWidth(thick)
    function b:set(n, alpha)
        local r, g, bl, al = W.col(n, alpha)
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            self[side]:SetColorTexture(r, g, bl, al)
        end
    end
    function b:alpha(a2)
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do self[side]:SetAlpha(a2) end
    end
    return b
end

function W.text(parent, str, size, name, justify)
    local f = parent:CreateFontString(nil, "OVERLAY")
    pcall(f.SetFont, f, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12)
    if not f:GetFont() then f:SetFontObject("GameFontHighlightSmall") end
    local r, g, b = W.col(name or "ink")
    f:SetTextColor(r, g, b, 1)
    f:SetText(str or "")
    f:SetJustifyH(justify or "LEFT")
    return f
end

-- a looping alpha pulse on a set of textures
function W.pulse(owner)
    local ag = owner:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetDuration(0.55)
    if a.SetFromAlpha then a:SetFromAlpha(1); a:SetToAlpha(0.25) else a:SetChange(-0.75) end
    return ag
end

-- click registration must match the client's cvar or a secure cast never fires
function W.ApplyClicks(b)
    local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    if down == nil and GetCVar then down = (GetCVar("ActionButtonUseKeyDown") == "1") end
    b:RegisterForClicks(down and "AnyDown" or "AnyUp")
end

--------------------------------------------------------------------
-- build (login, out of combat)
--------------------------------------------------------------------

function W:Build()
    if self.frame then return self.frame end
    if NS.InCombat() then return nil end

    local f = CreateFrame("Frame", "BiSInnervateWindow", UIParent)
    f:SetSize(self.width, self.HEADER + self.PAD + self.BTN_H + self.PAD + self.SIZE + self.PAD)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not NS.InCombat() and not NS.db.locked then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        if NS.InCombat() then return end
        s:StopMovingOrSizing()
        local point, _, rel, x, y = s:GetPoint()
        NS.db.pos = { point = point, rel = rel, x = x, y = y }
    end)
    W.fill(f, "BACKGROUND", "frame", self.BODY_A)
    self.frameEdge = W.border(f, "edge", 0.35)

    -- header
    local head = CreateFrame("Frame", nil, f)
    self.head = head
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT")
    head:SetHeight(self.HEADER)
    W.fill(head, "BACKGROUND", "header", self.HEAD_A)
    local hair = head:CreateTexture(nil, "BORDER")
    hair:SetPoint("BOTTOMLEFT"); hair:SetPoint("BOTTOMRIGHT"); hair:SetHeight(1)
    hair:SetColorTexture(W.col("edge", 1))

    -- the title is the BiS> prompt (the header law): no logo, the prompt is
    -- the brand. It cycles the standing slots - the name, who is online, what
    -- the window is doing - and events jump in over them. Wrapped below, once
    -- the H button exists to measure the budget against.
    local title = W.text(head, "BiS> ", 9, "ink")
    title:SetPoint("LEFT", head, "LEFT", 4, 0)
    self.title = title

    -- the console's words are a plain FontString with no hit area, so this
    -- invisible strip over the prompt keeps the title's interactions: the
    -- online list on hover, shift-click prints it, and a drag moves the window
    local online = CreateFrame("Button", nil, head)
    online:SetHeight(12)
    online:SetPoint("LEFT", head, "LEFT", 2, 0)
    -- shift-click prints; a plain drag on it moves the window like the rest
    -- of the title bar (the strip is a Button, and a Button eats the drag)
    online:SetScript("OnClick", function() if IsShiftKeyDown and IsShiftKeyDown() then W:PrintOnline() end end)
    online:RegisterForDrag("LeftButton")
    online:SetScript("OnDragStart", function() local h = f:GetScript("OnDragStart"); if h then h(f) end end)
    online:SetScript("OnDragStop",  function() local h = f:GetScript("OnDragStop");  if h then h(f) end end)
    online:SetScript("OnEnter", function(s)
        if not GameTooltip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine("With the addon")
        for _, e in ipairs(W:OnlineList()) do GameTooltip:AddLine(NS.ClassColored(e.name, e.class), 1, 1, 1) end
        GameTooltip:AddLine("Shift-click to print them. Drag to move.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    online:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.onlineBtn = online

    self.closeBtn = self:HeaderButton(head, -3,  "x",   "Close", "Reopen from the minimap button or /inn show.",
        function() W:ToggleShown() end, "warn")
    self.cfgBtn   = self:HeaderButton(head, -17, "cfg", "Options", "/inn config", function() NS.Config:Toggle() end)
    self.magesBtn = self:HeaderButton(head, -38, "M", "Mages only  (Odiss mode)",
        "Just the mage faces, no buttons; the window fits them and follows them in and out. /inn mages",
        function() W:SetMagesOnly(not NS.db.magesOnly) end)
    self.healerBtn = self:HeaderButton(head, -52, "H", "Healer mode  (Neb mode)",
        "Just the rez / heal / drink button, nothing else - no faces, no ask buttons. /inn healer",
        function() W:SetHealerOnly(not NS.db.healerOnly) end)
    online:SetPoint("RIGHT", self.healerBtn, "LEFT", -3, 0)
    -- header budget: the window is W.width (152) wide; H sits at RIGHT -52 and
    -- is 12 wide, so its left edge is 64 in from the right; the prompt starts
    -- 4 in from the left and wants 3 of air before H:
    --   152 - 64 - 4 - 3 = 81 clear, held at 76 so a long word has air
    self.TITLE_W = self.width - 64 - 4 - 3 - 5
    self.con = T.Console(title, { width = self.TITLE_W })
    if self.con then self.con:Set("name", "Innervate", "accent") end
    self:PaintHeader()

    -- body
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    W.fill(body, "BACKGROUND", "body", self.BODY_A)
    self.body = body

    -- the five icons in a row: Mana Tide, Innervate, Bloodlust, Drums, Rez
    self.buttons = {}
    local x = self.PAD
    for _, kind in ipairs({ "TIDE", "INNERVATE", "LUST", "DRUMS", "REZ" }) do
        self.buttons[kind] = self:BigButton(body, x, kind)
        x = x + self.BTN_H + self.GAP
    end
    self.tide, self.inn = self.buttons.TIDE, self.buttons.INNERVATE
    self.lust, self.drums, self.rez = self.buttons.LUST, self.buttons.DRUMS, self.buttons.REZ
    self:BuildKit()

    local grid = CreateFrame("Frame", nil, body)
    grid:SetPoint("TOPLEFT", body, "TOPLEFT", self.PAD, -(self.PAD + self.BTN_H + self.PAD))
    grid:SetSize(self.width - self.PAD * 2, self.SIZE)
    self.grid = grid
    for i = 1, self.MAX do self.squares[i] = self:Square(grid, i) end

    local pos = NS.db.pos
    if pos then
        f:SetPoint(pos.point or "CENTER", UIParent, pos.rel or "CENTER", pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 320, -80)
    end

    self.frame = f
    f:Show()
    self:ApplyScale(true)
    return f
end

function W:HeaderButton(head, x, label, tip, tip2, onclick, colour)
    local b = CreateFrame("Button", nil, head)
    b:SetSize(label == "cfg" and 18 or 12, 12)
    b:SetPoint("RIGHT", head, "RIGHT", x, 0)
    local bg = W.fill(b, "BACKGROUND", "field", 0.9)
    local edge = W.border(b, "edge", 1)
    local t = W.text(b, label, 8, colour or "muted", "CENTER")
    t:SetPoint("CENTER")
    b.edge, b.label = edge, t
    b:SetScript("OnClick", function() onclick() end)
    b:SetScript("OnEnter", function(s)
        edge:set(colour or "accent", 1)
        if GameTooltip then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tip)
            if tip2 then GameTooltip:AddLine(tip2, 1, 1, 1, true) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(s)
        edge:set(s.lit and "accent" or "edge", 1)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return b
end

-- everyone in the group with the addon, me first, then by name
function W:OnlineList()
    local out = { { name = NS.PlayerName(), class = select(2, UnitClass("player")) } }
    local names = {}
    NS.ForEachMember(function(unit, name, class)
        if name ~= NS.PlayerName() and NS.Comm:HasAddon(name) then names[#names + 1] = { name = name, class = class } end
    end)
    table.sort(names, function(a, b) return a.name < b.name end)
    for _, e in ipairs(names) do out[#out + 1] = e end
    return out
end

function W:PrintOnline()
    local list = self:OnlineList()
    local parts = {}
    for _, e in ipairs(list) do parts[#parts + 1] = NS.ClassColored(e.name, e.class) end
    NS.Print(#list .. " with the addon: " .. table.concat(parts, ", "))
end

-- the prompt's standing slots: the name (set once), who is online (green),
-- what the window is doing (PaintTitle). Ticked from Init: text and alpha
-- only, so it keeps going in a fight. Chat is for /inn answers; what the
-- window is up to is said here (con:Say).
function W:TickTitle()
    local con = self.con
    if not con or not self.title or not self.title:IsShown() then return end
    local n = #self:OnlineList()
    if n ~= self._onlineN then
        self._onlineN = n
        con:Set("online", n .. " online", "good")
    end
    con:Paint()
end

-- what the window is doing goes to the prompt; when the prompt is off screen
-- (compact modes, no window yet) chat is the fallback so nothing is swallowed
function W:Say(text, colour)
    if self.con and self.title and self.title:IsShown() then self.con:Say(text, colour)
    else NS.Print(text) end
end

-- the title bar per mode. Everything here is insecure, so it may run in a
-- fight: mages-only drops the title and cfg, and M moves in next to x.
function W:PaintHeader()
    local mages  = NS.db.magesOnly and true or false
    local healer = NS.db.healerOnly and true or false
    local compact = mages or healer
    local function lit(b, on)
        if not b then return end
        b.lit = on
        b.edge:set(on and "accent" or "edge", 1)
        local r, g, bl = W.col(on and "accent" or "muted")
        b.label:SetTextColor(r, g, bl, 1)
    end
    local m, h = self.magesBtn, self.healerBtn
    if not m then return end
    lit(m, mages); lit(h, healer)
    -- compact modes drop the title and cfg; the two mode glyphs move in next to x
    m:ClearAllPoints()
    m:SetPoint("RIGHT", self.head, "RIGHT", compact and -17 or -38, 0)
    if h then
        h:ClearAllPoints()
        h:SetPoint("RIGHT", self.head, "RIGHT", compact and -31 or -52, 0)
    end
    -- the narrow bar has room for the three glyphs and nothing else
    if compact then
        self.cfgBtn:Hide(); self.title:Hide()
        if self.con then self.con.words:Hide() end
        if self.onlineBtn then self.onlineBtn:Hide() end
    else
        self.cfgBtn:Show(); self.title:Show()
        if self.con then self.con.words:Show() end
        if self.onlineBtn then self.onlineBtn:Show() end
    end
end

-- Healer mode: the rez / heal / drink button and nothing else. No faces, no
-- ask buttons; the window is one button wide. Mutually exclusive with Odiss
-- mode. Protected (the row and the size), so it follows in Bind.
-- the mode nobody chose yet: a healing-tree priest / paladin / shaman starts
-- in Neb mode, a druid in Odiss mode - unless they carry a Mana Tide or
-- drums, then the full window. The first H, M, tick or slash the player
-- touches pins their choice (db.modeSet) and this never runs again.
function W:DefaultMode()
    if NS.db.modeSet then return false end
    local _, class = UnitClass("player")
    local want
    -- somebody with a tide or drums to hand out needs the full window: the
    -- faces are who they hand it to
    if NS.Provides("TIDE") or NS.Provides("DRUMS") then want = "main"
    elseif class == "DRUID" then want = "mages"
    elseif NS.MyHealerSpec() == true then want = "healer"
    else return false end
    local mages, healer = (want == "mages"), (want == "healer")
    if (NS.db.magesOnly and true or false) == mages and (NS.db.healerOnly and true or false) == healer then return false end
    NS.db.magesOnly, NS.db.healerOnly = mages, healer
    if self.frame then self:PaintHeader() end
    return true
end

function W:SetHealerOnly(on)
    on = on and true or false
    NS.db.modeSet = true
    if (NS.db.healerOnly and true or false) == on then return end
    NS.db.healerOnly = on
    if on then NS.db.magesOnly = false end
    self:PaintHeader()
    if NS.InCombat() then
        NS.Print((on and "Neb mode" or "everyone") .. " - when this fight ends.")
    else
        self:Bind()
        self:Say(on and "Neb mode" or "everyone", "muted")
    end
    if NS.Config and NS.Config.frame and NS.Config.frame:IsShown() then NS.Config:Refresh() end
end

-- Odiss mode on or off. The size and the button row are protected, so the
-- window itself follows in Bind - now, or when the fight ends.
function W:SetMagesOnly(on)
    on = on and true or false
    NS.db.modeSet = true
    if (NS.db.magesOnly and true or false) == on then return end
    NS.db.magesOnly = on
    if on then NS.db.healerOnly = false end
    self:PaintHeader()
    if NS.InCombat() then
        NS.Print((on and "mages only" or "everyone") .. " - when this fight ends.")
    else
        self:Bind()
        self:Say(on and "mages only" or "everyone", "muted")
    end
    if NS.Config and NS.Config.frame and NS.Config.frame:IsShown() then NS.Config:Refresh() end
end

-- One of the two big rows. The Mana Tide one is a secure self-cast button for
-- everybody (only a talented shaman gets a spell on it); its PostClick is the
-- ask for everyone else, which is legal because PostClick is plain Lua.
function W:BigButton(parent, y, kind)
    local secure = (NS.Provider(kind).scope ~= "target")
    -- the drum button also carries the secure enter/leave handlers that
    -- unroll a drummer's kit - in a fight too (see BuildKit)
    local tpl = secure and "SecureActionButtonTemplate" or nil
    if kind == "DRUMS" then tpl = "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate" end
    local b = CreateFrame("Button", "BiSInnervate" .. kind .. "Button", parent, tpl)
    b:SetSize(self.BTN_H, self.BTN_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", y, -self.PAD)    -- `y` is the x offset here
    b.kind = kind
    if secure then W.ApplyClicks(b) else b:RegisterForClicks("AnyUp") end

    b.bg   = W.fill(b, "BACKGROUND", "field", 1)
    b.edge = W.border(b, "edge", 1)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(NS.SpellIconFor(kind))
    if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    b.icon = icon

    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    if cd then
        cd:SetAllPoints(icon)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        -- the swipe only: the big built-in countdown (and OmniCC's) covered the
        -- whole icon; our small corner tag is the number
        if cd.SetHideCountdownNumbers then pcall(cd.SetHideCountdownNumbers, cd, true) end
        cd.noCooldownCount = true
        b.cd = cd
    end

    -- no words on the button: these strings feed the tooltip (and the tests)
    b.title = W.text(b, NS.Provider(kind).name, 10, "ink");  b.title:Hide()
    b.sub   = W.text(b, "", 10, "muted");                    b.sub:Hide()
    b.right = W.text(b, "", 8, "accent", "RIGHT")
    b.right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)   -- a tiny corner tag: "!" asked, timer on cd
    b.tag = W.text(b, "", 8, "ink")
    b.tag:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -1)             -- a drummer's bound type: B/W/R/S/P

    b.glow = CreateFrame("Frame", nil, b)
    b.glow:SetAllPoints()
    b.glowEdge = W.border(b.glow, "accent", 1, 2)
    b.anim = W.pulse(b.glow)
    b.glow:Hide()

    local onClick = function(_, button)
        if button == "RightButton" then
            local mine = NS.Calls:Mine(kind)
            if mine then NS.Calls:Cancel(mine, "manual"); NS.Print(NS.Provider(kind).short .. " call cancelled.") end
            return
        end
        if kind == "REZ" and NS.Rez:Active() then
            -- the macro just went out: remember whom it aimed at. The claim
            -- attaches when the cast STARTS, never here.
            NS.Rez:OnClick()
            return
        end
        if secure and NS.Provides(kind) then
            -- the cast just went out from the secure click: lock it for the group
            local c = NS.Calls:GroupCall(kind, NS.Subgroup(NS.PlayerName()))
            if c then NS.Calls:Claim(c) end
            return
        end
        NS.Calls:Ask(kind)
    end
    if secure then b:HookScript("PostClick", onClick) else b:SetScript("OnClick", onClick) end

    b:HookScript("OnEnter", function(s)
        if kind == "DRUMS" and not NS.Provides("DRUMS") then W:ShowFlyout() end
        if not GameTooltip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        if kind == "REZ" then
            GameTooltip:AddLine(NS.Rez:Enabled() and "Rez / heal / drink" or (NS.Rez:Active() and "Drink" or "Rez me first"))
            if NS.Rez:Active() then
                NS.Rez:Tooltip(GameTooltip)
                GameTooltip:Show()
                return
            end
            GameTooltip:AddLine("Click to ask the rezzers to take you next: you go to the front of the line, and the next rezzer to click gets you. This button is only here while you are dead.", 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine(NS.Provider(kind).name)
        end
        if kind == "DRUMS" and not NS.Provides("DRUMS") then
            GameTooltip:AddLine("Click: any drum. The five beside it ask for one in particular.", 0.7, 0.7, 0.7, true)
        elseif kind == "DRUMS" then
            GameTooltip:AddLine("Your drums. The five beside it are what you carry: out of a fight, click one to make it the drum this button uses; in a fight, the one your group asked for lights up and clicking it drums it.", 0.7, 0.7, 0.7, true)
        end
        if s.sub and s.sub:GetText() ~= "" then GameTooltip:AddLine(s.sub:GetText(), 0.78, 0.5, 1, true) end
        local ok, why = NS.Calls:CanAsk(kind)
        if secure and NS.Provides(kind) then
            GameTooltip:AddLine("You have it. It lights up when your group asks; click to use it.", 1, 1, 1, true)
        elseif NS.Calls:Mine(kind) then
            GameTooltip:AddLine("You asked. Right-click to cancel.", 1, 1, 1, true)
        elseif ok then
            GameTooltip:AddLine("Click to ask. " .. (why or ""), 1, 1, 1, true)
        else
            GameTooltip:AddLine(why or "", 0.8, 0.6, 0.7, true)
        end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
        if kind == "DRUMS" then W:FlyoutLeave() end
    end)
    return b
end

--------------------------------------------------------------------
-- the drum flyout: hover the drum button and the five types unfold under it.
-- Insecure from top to bottom - asking is plain Lua - so it may show and hide
-- in combat. Anchored to the (secure) drum button: an insecure frame hanging
-- off a secure one is the allowed direction.
--------------------------------------------------------------------

function W:BuildFlyout()
    if self.flyout then return self.flyout end
    local f = CreateFrame("Frame", "BiSInnervateDrumFlyout", self.buttons.DRUMS)
    local n = #NS.DRUM_TYPES
    f:SetSize(self.BTN_H, n * (self.BTN_H + 2) + 4)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    W.fill(f, "BACKGROUND", "frame", 0.92)
    W.border(f, "edge", 1)
    f.items = {}
    self.flyout = f
    for i, t in ipairs(NS.DRUM_TYPES) do
        local d = NS.DRUM[t]
        local b = CreateFrame("Button", nil, f)
        b:SetSize(self.BTN_H - 4, self.BTN_H - 4)
        b.index = i
        b.variant = t
        b.bg = W.fill(b, "BACKGROUND", "field", 1)
        b.edge = W.border(b, "edge", 1)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexture(d.icon)
        if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        b.icon = icon
        local letter = W.text(b, d.letter, 9, "ink", "RIGHT")
        letter:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 0)
        b:SetScript("OnClick", function(s)
            if NS.Provides("DRUMS") then
                W:PickDrum(s.variant)
            else
                NS.Calls:Ask("DRUMS", s.variant)
                W:HideFlyout()
            end
        end)
        b:SetScript("OnEnter", function(s)
            W.flyoutHover = true
            s.edge:set("accent", 1)
            if GameTooltip then
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:AddLine(d.name)
                if NS.Provides("DRUMS") then
                    local have = NS.MyDrums()[s.variant]
                    if not have then
                        GameTooltip:AddLine("you do not carry these", 0.8, 0.6, 0.7, true)
                    elseif W.buttons.DRUMS.drumType == s.variant then
                        GameTooltip:AddLine("the drum your button uses now", 0.78, 0.5, 1, true)
                    else
                        GameTooltip:AddLine(NS.InCombat() and "click to switch to these after the fight"
                                                           or "click to make these the drum your button uses", 1, 1, 1, true)
                    end
                else
                    local ok, why = NS.Calls:CanAsk("DRUMS", s.variant)
                    GameTooltip:AddLine(ok and ("Click to ask. " .. (why or "")) or (why or ""), 1, 1, 1, true)
                end
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(s)
            W.flyoutHover = false
            s.edge:set("edge", 1)
            if GameTooltip then GameTooltip:Hide() end
            W:FlyoutLeave()
        end)
        f.items[t] = b
    end
    f:SetScript("OnEnter", function() W.flyoutHover = true end)
    f:SetScript("OnLeave", function() W.flyoutHover = false; W:FlyoutLeave() end)
    f:Hide()
    self:PlaceFlyout()
    return f
end

-- up or down from the drum button, per the option. The flyout is insecure, so
-- re-anchoring it is fine at any time.
function W:PlaceFlyout()
    if not NS.InCombat() then self:PlaceKit() end
    local f = self.flyout
    if not f then return end
    local up = (NS.db.flyoutDir or "up") ~= "down"
    f:ClearAllPoints()
    if up then f:SetPoint("BOTTOM", self.buttons.DRUMS, "TOP", 0, 2)
    else       f:SetPoint("TOP",    self.buttons.DRUMS, "BOTTOM", 0, -2) end
    for _, b in pairs(f.items) do
        local off = 2 + (b.index - 1) * (self.BTN_H + 2)
        b:ClearAllPoints()
        -- first type nearest the button either way
        if up then b:SetPoint("BOTTOM", f, "BOTTOM", 0, off)
        else       b:SetPoint("TOP", f, "TOP", 0, -off) end
    end
end

function W:ShowFlyout()
    if NS.Provides("DRUMS") then return end        -- a drummer has the secure kit instead
    local f = self:BuildFlyout()
    for t, b in pairs(f.items) do
        -- an asker sees what the group can give: grey what nobody carries
        local ok = NS.Calls:CanAsk("DRUMS", t) and true or false
        b.edge:set("edge", 1)
        b.icon:SetAlpha(ok and 1 or 0.3)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(not ok) end
    end
    self.flyoutOpen = true
    f:Show()
end

--------------------------------------------------------------------
-- a drummer's kit: five SECURE item buttons hanging off the drum button,
-- one per drum type, bound out of combat to the drum they carry as
-- "/use [combat] item:<id>". Shown and hidden by secure enter/leave snippets,
-- so it unrolls mid-fight: the type the group asked for lights up and
-- clicking it drums it (the main button cannot be rebound in a fight). Out
-- of a fight the same click sets that drum as the button's default and the
-- kit rolls back in; the [combat] condition keeps it from drumming then.
--------------------------------------------------------------------

local KIT_ENTER = [[
    if self:GetAttribute("kit") ~= 1 then return end
    for i = 1, 5 do local d = self:GetFrameRef("kit" .. i) if d then d:Show() end end
]]
local KIT_LEAVE = [[
    local over = self:IsUnderMouse()
    local a = self:GetFrameRef("anchor")
    if a and a:IsUnderMouse() then over = true end
    for i = 1, 5 do local d = self:GetFrameRef("kit" .. i) if d and d:IsUnderMouse() then over = true end end
    if over then return end
    for i = 1, 5 do local d = self:GetFrameRef("kit" .. i) if d then d:Hide() end end
]]

function W:BuildKit()
    if self.kit then return self.kit end
    if NS.InCombat() then return nil end
    local anchor = self.buttons.DRUMS
    local kit = { items = {} }
    self.kit = kit
    for i, t in ipairs(NS.DRUM_TYPES) do
        local d = NS.DRUM[t]
        local b = CreateFrame("Button", "BiSInnervateDrumKit" .. i, anchor,
                              "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate")
        b:SetSize(self.BTN_H - 4, self.BTN_H - 4)
        b.index, b.variant = i, t
        W.ApplyClicks(b)
        b.bg = W.fill(b, "BACKGROUND", "frame", 0.95)
        b.edge = W.border(b, "edge", 1)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexture(d.icon)
        if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        b.icon = icon
        local letter = W.text(b, d.letter, 9, "ink", "RIGHT")
        letter:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 0)
        b.glow = CreateFrame("Frame", nil, b)
        b.glow:SetAllPoints()
        b.glowEdge = W.border(b.glow, "accent", 1, 2)
        b.anim = W.pulse(b.glow)
        b.glow:Hide()
        b:SetFrameRef("anchor", anchor)
        b:SetAttribute("_onleave", KIT_LEAVE)
        b:HookScript("PostClick", function(s)
            if NS.InCombat() then
                -- the drum just went out from the secure click: lock the call
                local c = NS.Calls:GroupCall("DRUMS", NS.Subgroup(NS.PlayerName()))
                if c and (not c.variant or c.variant == s.variant) then NS.Calls:Claim(c) end
            else
                W:PickDrum(s.variant)
            end
        end)
        b:HookScript("OnEnter", function(s)
            if not GameTooltip then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(d.name)
            if not NS.MyDrums()[s.variant] then
                GameTooltip:AddLine("you do not carry these", 0.8, 0.6, 0.7, true)
            elseif NS.InCombat() then
                GameTooltip:AddLine("click to drum these now", 1, 1, 1, true)
            elseif anchor.drumType == s.variant then
                GameTooltip:AddLine("the drum your button uses now", 0.78, 0.5, 1, true)
            else
                GameTooltip:AddLine("click to make these the drum your button uses", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:Hide()
        kit.items[t] = b
        kit[i] = b
        anchor:SetFrameRef("kit" .. i, b)
    end
    for i = 1, #NS.DRUM_TYPES do
        for j = 1, #NS.DRUM_TYPES do kit[i]:SetFrameRef("kit" .. j, kit[j]) end
    end
    anchor:SetAttribute("_onenter", KIT_ENTER)
    anchor:SetAttribute("_onleave", KIT_LEAVE)
    anchor:SetAttribute("kit", 0)
    self:PlaceKit()
    return kit
end

-- the kit unrolls up or down, touching the button (a gap would fire the
-- leave snippet on the way across). Protected: Bind-time only.
function W:PlaceKit()
    local kit = self.kit
    if not kit or NS.InCombat() then return end
    local up = (NS.db.flyoutDir or "up") ~= "down"
    local anchor = self.buttons.DRUMS
    local step = self.BTN_H - 4
    for i = 1, #NS.DRUM_TYPES do
        local b = kit[i]
        b:ClearAllPoints()
        if up then b:SetPoint("BOTTOM", anchor, "TOP", 0, (i - 1) * step)
        else       b:SetPoint("TOP", anchor, "BOTTOM", 0, -((i - 1) * step)) end
    end
end

-- bind the kit to what I carry (out of combat only)
function W:BindKit()
    local kit = self.kit
    if not kit or NS.InCombat() then return end
    local drummer = NS.Provides("DRUMS")
    local mine = drummer and NS.MyDrums() or {}
    for t, b in pairs(kit.items) do
        local id = mine[t]
        if id then
            b:SetAttribute("*type1", "macro")
            b:SetAttribute("*macrotext1", "/use [combat] item:" .. tostring(id))
        else
            b:SetAttribute("*type1", nil)
            b:SetAttribute("*macrotext1", nil)
        end
    end
    self.buttons.DRUMS:SetAttribute("kit", drummer and 1 or 0)
    if not drummer then self:HideKit() end
end

function W:HideKit()
    if not self.kit or NS.InCombat() then return end
    for _, b in ipairs(self.kit) do b:Hide() end
end

-- paint the kit: colour, alpha and the pulse only - legal in a fight
function W:PaintKit()
    local kit = self.kit
    if not kit or not NS.Provides("DRUMS") then return end
    local mine = NS.MyDrums()
    local c = NS.Calls:GroupCall("DRUMS", NS.Subgroup(NS.PlayerName()))
    local bound = self.buttons.DRUMS.drumType
    for t, b in pairs(kit.items) do
        local have = mine[t] and true or false
        b.icon:SetAlpha(have and 1 or 0.3)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(not have) end
        -- the group asked for this one and the main button holds another: it
        -- pulses, and clicking it is how the drummer answers mid-fight
        local wanted = have and c and c.variant == t and bound ~= t
                       and (not c.claimedBy or NS.Calls:ClaimExpired(c)) and NS.SpellCooldownFor("DRUMS") <= 0
        if wanted then
            b.edge:set("accent", 1)
            b.glow:Show()
            if not b.anim:IsPlaying() then b.anim:Play() end
        else
            b.edge:set((bound == t) and "accent" or "edge", 1)
            if b.anim:IsPlaying() then b.anim:Stop() end
            b.glow:Hide()
        end
    end
end

-- a drummer chose which of their drums the button should use. The binding is
-- a secure attribute, so out of combat it happens now; in a fight it waits.
-- The kit rolls back in either way.
function W:PickDrum(t)
    if not NS.MyDrums()[t] then NS.Print("you do not carry " .. NS.DRUM[t].name .. ".") return end
    self.drumPick = t
    if NS.InCombat() then
        self:Say(NS.DRUM[t].name .. " when this fight ends.", "muted")
        return
    end
    self:RebindDrums(true)
    self:HideKit()
    self:PaintKit()
    self:Say("drums: " .. NS.DRUM[t].name, "gold")
end

function W:HideFlyout()
    self.flyoutOpen = false
    if self.flyout then self.flyout:Hide() end
end

-- the mouse left the button or the flyout: close it unless it is over the
-- other one a moment later
function W:FlyoutLeave()
    if not self.flyoutOpen then return end
    NS.After(0.35, function()
        if W.flyoutOpen and not W.flyoutHover and not (W.buttons.DRUMS.IsMouseOver and W.buttons.DRUMS:IsMouseOver()) then
            W:HideFlyout()
        end
    end)
end

-- a drummer out of combat points the button at the drum the group asked for
-- which drum the button holds: the one the group asked for, else the one the
-- drummer picked from the flyout, else the best carried
function W:RebindDrums(force)
    local b = self.buttons and self.buttons.DRUMS
    if not b or NS.InCombat() or not NS.Provides("DRUMS") then return end
    local c = NS.Calls:GroupCall("DRUMS", NS.Subgroup(NS.PlayerName()))
    local itemId, t = NS.MyDrum((c and c.variant) or self.drumPick)
    if not itemId then return end
    local want = "item:" .. tostring(itemId)
    if not force and b:GetAttribute("*item1") == want then return end
    b:SetAttribute("*type1", "item"); b:SetAttribute("*item1", want)
    b.drumType = t
    if b.tag then b.tag:SetText(NS.DRUM[t] and NS.DRUM[t].letter or "") end
    self:BindKit()
end

-- the rez module re-aims its button: now if out of combat, else at the end
-- of the fight (the macro is a secure attribute)
function W:RebindRez()
    local b = self.buttons and self.buttons.REZ
    if not b then return end
    if NS.InCombat() then self.rezPending = true return end
    if NS.Tracker:RosterBlip() then return end
    self.rezPending = nil
    NS.Rez:Bind(b)
end

-- One face. Always a secure button, so a druid can cast from it and the demo
-- can wire it; for everybody else it carries no spell and takes no mouse.
function W:Square(grid, i)
    local b = CreateFrame("Button", "BiSInnervateFace" .. i, grid, "SecureActionButtonTemplate")
    b:SetSize(self.SIZE, self.SIZE)
    b:SetAttribute("unit", "none")
    W.ApplyClicks(b)

    b.back = W.fill(b, "BACKGROUND", "field", 1)
    local face = b:CreateTexture(nil, "ARTWORK")
    face:SetPoint("TOPLEFT", 2, -2); face:SetPoint("BOTTOMRIGHT", -2, 2)
    b.face = face

    local model = CreateFrame("PlayerModel", nil, b)
    model:SetPoint("TOPLEFT", 2, -2); model:SetPoint("BOTTOMRIGHT", -2, 2)
    pcall(model.SetFrameLevel, model, ((b.GetFrameLevel and b:GetFrameLevel()) or 0) + 1)
    model:Hide()
    b.model = model

    local ov = CreateFrame("Frame", nil, b)
    ov:SetAllPoints()
    pcall(ov.SetFrameLevel, ov, ((b.GetFrameLevel and b:GetFrameLevel()) or 0) + 4)
    b.ov = ov
    b.lock = ov:CreateTexture(nil, "ARTWORK")
    b.lock:SetAllPoints()
    b.lock:SetColorTexture(W.col("frame", 0.72))
    b.lock:Hide()
    -- a 3px strip along the bottom; its WIDTH is the mana. (A full-height
    -- overlay whose height was the mana painted over everybody healthy.)
    b.mana = ov:CreateTexture(nil, "OVERLAY")
    b.mana:SetPoint("BOTTOMLEFT", 2, 2)
    b.mana:SetSize(1, 2)
    b.mana:SetColorTexture(W.col("slate", 0.9))
    b.edge = W.border(ov, "line", 1, 2)
    b.anim = W.pulse(ov)

    b:HookScript("PostClick", function(s)
        if not s.pname then return end
        if NS.demoMode and s.demoName then
            NS.Print(T.text("good", "click registered") .. " - would innervate " .. s.demoName ..
                     (NS.InCombat() and (" " .. T.text("gold", "(in combat)")) or ""))
        end
        local c = NS.Calls:For(s.pname, "INNERVATE")
        if c then NS.Calls:Claim(c) end
    end)
    b:HookScript("OnEnter", function(s) W:FaceTooltip(s) end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- an insecure overlay for tooltips when the square itself takes no mouse
    local hover = CreateFrame("Frame", nil, ov)
    hover:SetAllPoints()
    hover:EnableMouse(false)
    hover:SetScript("OnEnter", function() W:FaceTooltip(b) end)
    hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b.hover = hover

    b:SetAlpha(0)
    b:Show()
    return b
end

function W:FaceTooltip(b)
    if not GameTooltip or not b.pname then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(NS.ClassColored(b.pname, b.pclass))
    local m = b.pmana
    if m then GameTooltip:AddLine(m .. "% mana", 1, 1, 1) end
    local c = NS.Calls:For(b.pname, "INNERVATE")
    if c then
        if c.claimedBy and not NS.Calls:ClaimExpired(c) then
            GameTooltip:AddLine((c.claimedBy == NS.PlayerName() and "yours - casting" or (c.claimedBy .. " is on it")), 0.8, 0.8, 0.5)
        else
            GameTooltip:AddLine("asking for innervate - " .. NS.TimeStr(NS.Now() - c.created) .. " ago", 0.73, 0.5, 1)
        end
    end
    if b.unbound then
        GameTooltip:AddLine("this client cannot target them by name - innervate them by hand", 0.9, 0.5, 0.6, true)
    elseif NS.Provides("INNERVATE") and NS.Shapeshifted() then
        GameTooltip:AddLine("leave your form to innervate", 0.9, 0.5, 0.6)
    elseif NS.Provides("INNERVATE") then
        GameTooltip:AddLine("Click to innervate them.", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

--------------------------------------------------------------------
-- bind (out of combat only: the one place anything protected is written)
--------------------------------------------------------------------

function W.classRank(class)
    if class == "MAGE" then return 1 end
    if class == "PRIEST" or class == "PALADIN" or class == "SHAMAN" or class == "DRUID" then return 2 end
    return 3
end

function W:Bind()
    if not self.frame or NS.InCombat() then return end
    if NS.Tracker:RosterBlip() then return end     -- a zone-in, not everyone leaving

    local isDruid = NS.Provides("INNERVATE")
    local spell   = NS.SpellNameFor("INNERVATE")
    local list = {}
    if NS.demoMode and NS.Demo then
        list = NS.Demo:People()
    else
        -- mages and healers only: a druid has their own innervate, and every
        -- face on the grid is one more thing a druid has to read past
        -- and a priest / paladin / shaman in a dps tree is not a healer:
        -- no face either (their client says H or X in its REZ blob)
        local rezzers = NS.Tracker.providers.REZ or {}
        NS.ForEachMember(function(unit, name, class)
            if NS.IsRequesterClass(class) and class ~= "DRUID" and NS.Comm:HasAddon(name) then
                local dps
                if name == NS.PlayerName() then dps = (NS.MyHealerSpec() == false)
                else dps = rezzers[name] and rezzers[name].dpsSpec end
                if not dps then list[#list + 1] = { unit = unit, name = name, class = class } end
            end
        end)
    end
    -- Odiss mode: mages, nothing else. Healer mode: no faces at all.
    local magesOnly  = NS.db.magesOnly and true or false
    local healerOnly = NS.db.healerOnly and true or false
    if magesOnly then
        local mages = {}
        for _, e in ipairs(list) do if e.class == "MAGE" then mages[#mages + 1] = e end end
        list = mages
    elseif healerOnly then
        list = {}
    end
    table.sort(list, function(a, b)
        local ra, rb = W.classRank(a.class), W.classRank(b.class)
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    local perRow = magesOnly and self.PER_ROW_MAGES or self.PER_ROW

    self.byName = {}
    for i = 1, self.MAX do
        local e, b = list[i], self.squares[i]
        if e then
            -- The binding is by NAME, never by raid slot: slots renumber the
            -- moment anyone leaves and cannot be rewritten mid-fight. A
            -- cross-realm player needs the Name-Realm token. If neither form
            -- resolves, the face stays UNBOUND - a face that does nothing is
            -- safe; one that innervates whoever inherited a slot is not.
            local token = W.NameToken(e)
            b.unbound = (isDruid and not e.demo and not token) or nil
            if isDruid and not e.demo and token then
                b:SetAttribute("*type1", "spell"); b:SetAttribute("*spell1", spell)
                b:SetAttribute("*type2", "spell"); b:SetAttribute("*spell2", spell)
                b:SetAttribute("unit", token)
            elseif e.demo then
                b:SetAttribute("*type1", "macro"); b:SetAttribute("*macrotext1", "")
                b:SetAttribute("*type2", "macro"); b:SetAttribute("*macrotext2", "")
                b:SetAttribute("unit", "player")
            else
                b:SetAttribute("*type1", nil); b:SetAttribute("*spell1", nil)
                b:SetAttribute("*type2", nil); b:SetAttribute("*spell2", nil)
                b:SetAttribute("*macrotext1", nil); b:SetAttribute("*macrotext2", nil)
                b:SetAttribute("unit", "none")
            end
            b.pname, b.pclass, b.punit, b.demoName = e.name, e.class, e.unit, e.demo and e.name or nil
            self.byName[e.name] = b
            local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.grid, "TOPLEFT", col * (self.SIZE + self.GAP), -(row * (self.SIZE + self.GAP)))
            -- only a druid (or the demo) may click a face; everyone else hovers.
            -- Both respect a closed window, or a roster change would put an
            -- invisible tooltip-catcher back over the screen.
            local live = (isDruid or e.demo) and not b.unbound
            local shown = not self:IsHidden()
            pcall(b.EnableMouse, b, live and shown and true or false)
            b.hover:EnableMouse((not live) and shown and true or false)
            self:SetPortrait(b, e.unit, e.demo)
        else
            b:SetAttribute("*type1", nil); b:SetAttribute("*spell1", nil)
            b:SetAttribute("*type2", nil); b:SetAttribute("*spell2", nil)
            b:SetAttribute("*macrotext1", nil); b:SetAttribute("*macrotext2", nil)
            b:SetAttribute("unit", "none")
            b.unbound = nil
            b.pname, b.pclass, b.punit, b.demoName = nil, nil, nil, nil
            pcall(b.EnableMouse, b, false)
            b.hover:EnableMouse(false)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.grid, "TOPLEFT", -5000, 0)
            self:SetPortrait(b, nil)
        end
    end

    local n = math.min(#list, self.MAX)
    self.count = n
    self:Layout(n, magesOnly, healerOnly)

    -- the group buttons: a spell (or the drum item) only for what I provide
    for kind, btn in pairs(self.buttons) do
        local p = NS.Provider(kind)
        -- Odiss mode has no button row. Secure buttons: shown and hidden here
        -- only, never in a fight.
        if kind == "REZ" then
            -- the rez module writes its own macro (or clears it) and decides
            -- whether the button is on screen at all. In healer mode it is
            -- the whole row, so it sits where the first button would.
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", self.body, "TOPLEFT", healerOnly and self.PAD or (self.PAD + 4 * (self.BTN_H + self.GAP)), -self.PAD)
            NS.Rez:Bind(btn)
            if btn.tag then btn.tag:SetText("") end
        elseif magesOnly or healerOnly then btn:Hide() else btn:Show() end
        if kind == "REZ" then
        elseif p.scope ~= "target" then
            if NS.Provides(kind) then
                if p.item then
                    local c = NS.Calls:GroupCall("DRUMS", NS.Subgroup(NS.PlayerName()))
                    local itemId, t = NS.MyDrum((c and c.variant) or self.drumPick)
                    btn:SetAttribute("*type1", "item"); btn:SetAttribute("*item1", "item:" .. tostring(itemId))
                    btn:SetAttribute("*spell1", nil)
                    btn.drumType = t
                    if btn.tag then btn.tag:SetText(NS.DRUM[t] and NS.DRUM[t].letter or "") end
                else
                    btn:SetAttribute("*type1", "spell"); btn:SetAttribute("*spell1", NS.SpellNameFor(kind))
                    btn:SetAttribute("*item1", nil)
                end
                btn:SetAttribute("unit", "player")
            else
                btn:SetAttribute("*type1", nil); btn:SetAttribute("*spell1", nil); btn:SetAttribute("*item1", nil)
                btn:SetAttribute("unit", "none")
                if btn.tag then btn.tag:SetText("") end
            end
        end
        pcall(btn.EnableMouse, btn, not self:IsHidden())
    end
    self:PlaceKit()
    self:BindKit()
    self:HeaderMouse(not self:IsHidden())
    self:Refresh()
end

-- The window's shape for n faces. Protected (the window holds the secure
-- faces), so only Bind calls it - out of combat. Everyone: fixed width, the
-- button row, six faces per row. Mages only: no button row, the width is the
-- faces (one row up to eight, then it wraps), never narrower than the title
-- bar's three glyphs. Whatever corner the window is anchored by stays put;
-- the other edges move.
function W:Layout(n, magesOnly, healerOnly)
    if healerOnly then
        -- one button under the bar, no grid: as narrow as the bar's glyphs allow
        local width = math.max(self.PAD * 2 + self.BTN_H, self.MINW_MAGES)
        self.grid:ClearAllPoints()
        self.grid:SetPoint("TOPLEFT", self.body, "TOPLEFT", self.PAD, -(self.PAD + self.BTN_H + self.PAD))
        self.grid:SetSize(1, 1)
        self.frame:SetSize(width, self.HEADER + self.PAD + self.BTN_H + self.PAD)
        self.layout = { width = width, rows = 0, cols = 0, healerOnly = true }
        return
    end
    local perRow = magesOnly and self.PER_ROW_MAGES or self.PER_ROW
    local rows   = math.max(1, math.ceil(n / perRow))
    local cols   = magesOnly and math.max(1, math.min(n, perRow)) or perRow
    local gridW  = cols * (self.SIZE + self.GAP) - self.GAP
    local gridH  = rows * (self.SIZE + self.GAP) - self.GAP
    local top    = magesOnly and self.PAD or (self.PAD + self.BTN_H + self.PAD)
    local width  = magesOnly and math.max(self.PAD * 2 + gridW, self.MINW_MAGES) or self.width

    self.grid:ClearAllPoints()
    self.grid:SetPoint("TOPLEFT", self.body, "TOPLEFT", self.PAD, -top)
    self.grid:SetSize(math.max(gridW, 1), gridH)
    self.frame:SetSize(width, self.HEADER + top + gridH + self.PAD)
    self.layout = { width = width, rows = rows, cols = cols, magesOnly = magesOnly }
end

-- the unit token a face is bound to: the short name when the client resolves
-- it, Name-Realm for a cross-realm player, nil when neither works
function W.NameToken(e)
    if not UnitExists or not UnitName then return nil end
    local short = e.name
    if UnitExists(short) and NS.Short(UnitName(short) or "") == short then return short end
    local n, realm = UnitName(e.unit or "")
    if n and realm and realm ~= "" then
        local full = n .. "-" .. realm
        if UnitExists(full) and NS.Short(UnitName(full) or "") == short then return full end
    end
    return nil
end

-- closed with the x - except while the demo runs, which always shows itself
-- without ever writing the user's setting
function W:IsHidden()
    return NS.db.hidden and not NS.demoMode and true or false
end

-- roster slots renumber mid-fight; the mana bar reads a slot, so re-resolve.
-- Plain table writes - legal in combat.
function W:Reunit()
    if not self.frame or NS.demoMode then return end
    local byName = {}
    NS.ForEachMember(function(unit, name) byName[name] = unit end)
    for i = 1, self.MAX do
        local b = self.squares[i]
        if b.pname and byName[b.pname] then b.punit = byName[b.pname] end
    end
end

function W:SetPortrait(b, unit, demo)
    b.faceOk, b.modelOk = false, false
    if not unit then
        b.face:SetTexture(nil)
        b.model:Hide()
        return
    end
    if SetPortraitTexture then
        local ok = pcall(SetPortraitTexture, b.face, unit)
        b.faceOk = ok and true or false
        if not ok then b.face:SetTexture(nil) end
    end
    if NS.db.portraits3d and not demo then
        local ok = pcall(function()
            b.model:SetUnit(unit)
            if b.model.SetPortraitZoom then b.model:SetPortraitZoom(1) end
            if b.model.SetCamDistanceScale then b.model:SetCamDistanceScale(1.1) end
        end)
        b.modelOk = ok and true or false
        if ok then b.model:Show() else b.model:Hide() end
    else
        b.model:Hide()
    end
end

function W:RefreshPortraits()
    if not self.frame or NS.InCombat() then return end
    for i = 1, self.MAX do
        local b = self.squares[i]
        if b.pname then self:SetPortrait(b, b.punit, b.demoName ~= nil) end
    end
end

--------------------------------------------------------------------
-- refresh (combat-safe: colour, alpha, texture size, text)
--------------------------------------------------------------------

function W:Refresh()
    if self._pending then return end
    self._pending = true
    if not NS.After(0.05, function() W._pending = false; W:DoRefresh() end) then
        self._pending = false
        self:DoRefresh()
    end
end

function W:DoRefresh()
    if not self.frame then return end
    local me     = NS.PlayerName()
    local hidden = self:IsHidden()
    self.frame:SetAlpha(hidden and 0 or 1)
    if hidden then self:ShowFaces(false); return end

    for kind, btn in pairs(self.buttons) do self:PaintButton(btn, kind) end
    self:PaintTitle()
    self:PaintKit()

    local isDruid = NS.Provides("INNERVATE")
    local shifted = isDruid and NS.Shapeshifted()
    for i = 1, self.MAX do
        local b = self.squares[i]
        if b.pname then
            local mana = b.punit and NS.ManaPct(b.punit)
            if b.demoName and NS.Demo then mana = NS.Demo:ManaFor(b.demoName) end
            b.pmana = mana
            b.mana:SetWidth(math.max(1, (self.SIZE - 4) * ((mana or 0) / 100)))

            local c = NS.Calls:For(b.pname, "INNERVATE")
            local locked = c and NS.Calls:IsLocked(c)
            local mine   = c and c.claimedBy == me and not NS.Calls:ClaimExpired(c)
            local dead = (not b.demoName) and b.punit and
                ((UnitIsDeadOrGhost and UnitIsDeadOrGhost(b.punit))
                 or (UnitIsConnected and not UnitIsConnected(b.punit)))

            if c and mine then
                b.edge:set("accent", 1); b.edge:alpha(1)
                if b.anim:IsPlaying() then b.anim:Stop() end
                b.lock:Hide()
                b:SetAlpha(1)
            elseif c and locked then
                b.edge:set("dim", 1)
                if b.anim:IsPlaying() then b.anim:Stop() end
                b.lock:Show()
                b:SetAlpha(0.75)
            elseif c then
                b.edge:set("accent", 1)
                if not b.anim:IsPlaying() then b.anim:Play() end
                b.lock:Hide()
                b:SetAlpha(1)
            else
                b.edge:set("line", 1); b.edge:alpha(1)
                if b.anim:IsPlaying() then b.anim:Stop() end
                b.lock:Hide()
                b:SetAlpha(dead and 0.25 or (isDruid and 0.7 or 0.45))
            end
            -- in bear or cat form a click cannot cast: the whole grid greys
            if shifted then b:SetAlpha(0.3) end
        end
    end
    self:ShowFaces(true)
end

-- the title bar reads the rez button's target while it has one: "one small
-- button, with the name of who it is about to rez next to it". Text only,
-- so it may run in a fight.
function W:PaintTitle()
    if not self.title then return end
    -- the action slot: plain words (the console trims plain words only, so
    -- no class colour inside), coloured by meaning
    local d = NS.Rez and NS.Rez:Active() and NS.Rez.last
    local txt, colour
    if d and d.action == "rez" then
        txt, colour = "rez " .. tostring(d.target), "good"
    elseif d and d.action == "heal" then
        txt, colour = "heal " .. tostring(d.target), "gold"
    elseif d and d.action == "drink" then
        txt, colour = "drink", "slate"
    end
    self._actionText = txt
    if self.con and (txt ~= self._actionShown) then
        self._actionShown = txt
        self.con:Set("action", txt, colour)
    end
end

-- 3D model frames ignore parent alpha: show and hide them by hand
function W:ShowFaces(on)
    for i = 1, self.MAX do
        local b = self.squares[i]
        if b.model then
            if on and b.pname and b.modelOk then b.model:Show() else b.model:Hide() end
        end
    end
end

function W:PaintButton(b, kind)
    local me = NS.PlayerName()
    local mine = NS.Calls:Mine(kind)
    local enabled, why
    local pulse = false
    local rightText, sub = "", ""

    local p = NS.Provider(kind)
    if kind == "REZ" and NS.Rez:Active() then
        -- the rez module's button: the icon is what the click will do
        local d = NS.Rez.last or NS.Rez:Decide()
        enabled = d.action ~= nil
        pulse = (d.action == "rez") or (d.action == "drink" and d.lowMana)
        sub = NS.Rez:Summary(d)
        if d.action == "rez" then rightText = T.text("good", "!")
        elseif d.action == "heal" then rightText = T.text("gold", "+")
        elseif d.action == "drink" then rightText = T.text("slate", "~") end
        if d.icon then b.icon:SetTexture(d.icon) end
        if b.cd then pcall(b.cd.SetCooldown, b.cd, 0, 0) end
        b.sub:SetText(sub)
        b.right:SetText(rightText)
        b.title:SetTextColor(W.col(enabled and "ink" or "muted"))
        b.sub:SetTextColor(W.col(enabled and "muted" or "dim"))
        b.icon:SetAlpha(enabled and 1 or 0.4)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(not enabled) end
        b.edge:set(d.action == "rez" and "good" or (d.action == "heal" and "gold") or (d.action == "drink" and "slate") or "hair", 1)
        b.bg:SetColorTexture(W.col(enabled and "field" or "frame", 1))
        if pulse then
            b.glow:Show()
            if not b.anim:IsPlaying() then b.anim:Play() end
        else
            if b.anim:IsPlaying() then b.anim:Stop() end
            b.glow:Hide()
        end
        return
    end
    if p.scope ~= "target" and NS.Provides(kind) then
        -- mine to use: lights when my group asks
        local c = NS.Calls:GroupCall(kind, NS.Subgroup(me))
        local cd = NS.SpellCooldownFor(kind)
        local blocked, dbLeft, dbDur = NS.Blocked(kind)   -- exhausted / tinnitus: it would do nothing
        enabled = not blocked
        local canFill = true
        if c and kind == "DRUMS" and c.variant and not NS.MyDrums()[c.variant] then canFill = false end
        local mineToCast = c and c.claimedBy == me and not NS.Calls:ClaimExpired(c)
        if mineToCast then
            -- I clicked: solid, not pulsing, like a claimed face
            sub = "yours - casting"
            rightText = T.text("accent", "!")
        elseif c and not NS.Calls:IsLocked(c) and cd <= 0 and not blocked and canFill then
            pulse = true
            sub = ((p.scope == "raid") and (c.target .. " asked") or ("group " .. tostring(c.group or "?") .. " asked")) ..
                  (c.variant and (" for " .. NS.DRUM[c.variant].name) or "") .. " - click to use it"
            if kind == "DRUMS" and c.variant and b.drumType ~= c.variant then
                sub = sub .. " (bound to " .. NS.DRUM[b.drumType or "BATTLE"].name .. " until the fight ends)"
            end
            rightText = T.text("accent", "!")
        elseif c and kind == "DRUMS" and not canFill then
            sub = "group asked for " .. NS.DRUM[c.variant].name .. " - you do not have that one"
        elseif c and NS.Calls:IsLocked(c) then
            sub = c.claimedBy .. " is on it"
        elseif blocked then
            sub = ((kind == "LUST") and "yours - but you are exhausted" or "yours - but you have tinnitus") ..
                  (dbLeft > 0 and (" (" .. NS.TimeStr(dbLeft) .. " left)") or "")
            rightText = T.text("warn", dbLeft >= 60 and (math.ceil(dbLeft / 60) .. "m") or (math.ceil(dbLeft) .. "s"))
        elseif cd > 0 then
            sub = "yours - back in " .. NS.TimeStr(cd)
            rightText = T.text("muted", cd >= 60 and (math.ceil(cd / 60) .. "m") or (math.ceil(cd) .. "s"))
        else
            sub = "yours - ready"
            rightText = ""
        end
        if b.cd then
            if blocked and dbLeft > 0 and dbDur > 0 then
                pcall(b.cd.SetCooldown, b.cd, NS.Now() - (dbDur - dbLeft), dbDur)   -- the debuff's swipe
            else
                local start = (cd > 0) and (NS.Now() - (p.cd - cd)) or 0
                pcall(b.cd.SetCooldown, b.cd, start, cd > 0 and p.cd or 0)
            end
        end
    elseif mine then
        enabled = true
        if mine.claimedBy and not NS.Calls:ClaimExpired(mine) then
            sub = mine.claimedBy .. " is on it"
            rightText = T.text("good", "*")
        else
            sub = "asked - waiting  (right-click cancels)"
            rightText = T.text("accent", "?")
        end
    else
        local cdLeft, reason
        enabled, why, cdLeft, reason = NS.Calls:CanAsk(kind)
        sub = why or ""
        if enabled then
            local m = NS.ManaPct("player") or 100
            pulse = m <= (NS.db.urgentAt or 20)
            rightText = ""
        elseif cdLeft and cdLeft > 0 then
            -- greyed for a cooldown (muted) or my own debuff (rose): the time in the corner
            rightText = T.text(reason == "debuff" and "warn" or "muted",
                               cdLeft >= 60 and (math.ceil(cdLeft / 60) .. "m") or (math.ceil(cdLeft) .. "s"))
        end
        if b.cd then
            if reason == "debuff" and cdLeft and cdLeft > 0 then
                local _, _, dbDur = NS.Blocked(kind)
                if dbDur and dbDur > 0 then pcall(b.cd.SetCooldown, b.cd, NS.Now() - (dbDur - cdLeft), dbDur) end
            else
                local dur = (cdLeft and cdLeft > 0) and p.cd or 0
                local start = (dur > 0) and (NS.Now() - (p.cd - cdLeft)) or 0
                pcall(b.cd.SetCooldown, b.cd, start, dur)
            end
        end
    end

    b.sub:SetText(sub)
    b.right:SetText(rightText)
    if enabled then
        b.title:SetTextColor(W.col("ink"))
        b.sub:SetTextColor(W.col(mine and "accent" or "muted"))
        b.icon:SetAlpha(1)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(false) end
        local solid = mine or (p.scope ~= "target" and NS.Provides(kind) and (function()
            local c = NS.Calls:GroupCall(kind, NS.Subgroup(me))
            return c and c.claimedBy == me and not NS.Calls:ClaimExpired(c)
        end)())
        b.edge:set(solid and "accent" or "edge", 1)
        b.bg:SetColorTexture(W.col("field", 1))
    else
        b.title:SetTextColor(W.col("muted"))
        b.sub:SetTextColor(W.col("dim"))
        b.icon:SetAlpha(0.35)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(true) end
        b.edge:set("hair", 1)
        b.bg:SetColorTexture(W.col("frame", 1))
    end
    if pulse then
        b.glow:Show()
        if not b.anim:IsPlaying() then b.anim:Play() end
    else
        if b.anim:IsPlaying() then b.anim:Stop() end
        b.glow:Hide()
    end
end

function W:Alert(c)
    if not c or c.state ~= "open" then return end
    if NS.db.chatAlert == false then return end
    if c.kind == "INNERVATE" and NS.Provides("INNERVATE") then
        NS.Print(NS.ClassColored(c.target, c.class) .. " needs innervate" ..
                 (c.mana and (" (" .. c.mana .. "%)") or "") .. " - click their face.")
    elseif c.kind == "REZ" then
        if NS.Rez:Enabled() and NS.Provides("REZ") then
            NS.Print(NS.ClassColored(c.target, c.class) .. " asks to be rezzed next.")
        end
    elseif c.kind ~= "INNERVATE" and NS.Provides(c.kind)
           and (NS.Provider(c.kind).scope == "raid" or c.group == NS.Subgroup(NS.PlayerName())) then
        NS.Print(((NS.Provider(c.kind).scope == "raid") and (c.target .. " wants ") or "your group wants ")
                 .. NS.Provider(c.kind).short ..
                 (NS.db.magesOnly and " - the buttons are off in mages-only mode (M in the corner)." or " - click the button."))
    end
end

--------------------------------------------------------------------
-- show / hide / scale (protected: out of combat, or deferred)
--------------------------------------------------------------------

function W:SetClickable(on)
    if not self.frame or NS.InCombat() then return false end
    local isDruid = NS.Provides("INNERVATE") or NS.demoMode
    for i = 1, self.MAX do
        local b = self.squares[i]
        local live = isDruid and b.pname and not b.unbound
        pcall(b.EnableMouse, b, (on and live) and true or false)
        b.hover:EnableMouse((on and b.pname and not live) and true or false)
    end
    for _, btn in pairs(self.buttons) do pcall(btn.EnableMouse, btn, on and true or false) end
    for _, b in ipairs(self.kit or {}) do pcall(b.EnableMouse, b, on and true or false) end
    self:HeaderMouse(on)
    return true
end

-- a closed window is alpha 0: its title bar must not stay an invisible drag
-- strip with three invisible buttons on it. The window itself is protected
-- (out of combat only: Bind and SetClickable); the buttons are not.
function W:HeaderMouse(on)
    pcall(self.frame.EnableMouse, self.frame, on and true or false)
    for _, hb in ipairs({ self.magesBtn, self.healerBtn, self.cfgBtn, self.closeBtn, self.onlineBtn }) do
        if hb then hb:EnableMouse(on and true or false) end
    end
end

-- the bags changed: if what I can provide changed (drums bought, sold, used
-- up), tell the raid and rewire the buttons - out of combat, else at the end
function W:RecheckKinds()
    local before = table.concat(NS.MyKinds(), ",")
    NS.ForgetSpellCache()
    local after = table.concat(NS.MyKinds(), ",")
    if before == after then return end
    NS.Tracker:UpdateRoster()
    if NS.InGroup() then NS.Comm:Hello() end
    if NS.InCombat() then self.rebindPending = true return end
    self:Bind()
end

function W:ToggleShown()
    if not self.frame then self:Build() end
    if not self.frame then NS.Print("the window appears when this fight ends.") return end
    if NS.InCombat() then
        NS.Print("the window cannot open or close mid-fight - try again when it ends.")
        return
    end
    NS.db.hidden = not NS.db.hidden
    self:SetClickable(not self:IsHidden())
    self:DoRefresh()
    NS.Print(NS.db.hidden and "window closed - the minimap button or /inn show brings it back." or "window shown.")
end

function W:Show()
    if NS.db.hidden then self:ToggleShown() end
end

-- keep the window where it is on screen when its scale changes
function W:ApplyScale(force)
    local f = self.frame
    if not f then return end
    local want = tonumber(NS.db.scale) or 1
    if want < 0.5 then want = 0.5 elseif want > 2 then want = 2 end
    local old = (f.GetScale and f:GetScale()) or 1
    if not force and math.abs(old - want) < 0.001 then return end
    if NS.InCombat() then self.scalePending = true return end
    self.scalePending = nil
    pcall(f.SetScale, f, want)
    if not force and old ~= want then
        local point, _, rel, x, y = f:GetPoint()
        if point then
            x, y = (x or 0) * old / want, (y or 0) * old / want
            pcall(f.SetPoint, f, point, UIParent, rel or point, x, y)
            NS.db.pos = { point = point, rel = rel or point, x = x, y = y }
        end
    end
end

function W:ResetPosition()
    NS.db.pos = nil
    if not self.frame or NS.InCombat() then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 320, -80)
end

-- the fight is over: everything that waited
function W:AfterCombat()
    self:Bind()
    if self.scalePending then self:ApplyScale() end
    self.rebindPending = nil
    if self.resetPending then self.resetPending = nil; NS.HandleSlash("reset") end
    self:RebindDrums()
    self:RebindRez()
    if self.clicksPending then self:ReapplyClicks() end
    self:SetClickable(not self:IsHidden())
    self:Refresh()
end

-- the click-registration cvar changed: every secure button must follow it,
-- which is protected, so out of combat or when the fight ends
function W:ReapplyClicks()
    if not self.frame then return end
    if NS.InCombat() then self.clicksPending = true return end
    self.clicksPending = nil
    for i = 1, self.MAX do W.ApplyClicks(self.squares[i]) end
    for kind, btn in pairs(self.buttons) do
        if NS.Provider(kind).scope ~= "target" then W.ApplyClicks(btn) end
    end
    for _, b in ipairs(self.kit or {}) do W.ApplyClicks(b) end
end
