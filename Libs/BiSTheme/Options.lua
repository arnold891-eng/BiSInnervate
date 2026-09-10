--[[
  BiSTheme / Options.lua  --  the one options window every BiS addon wears.

  Arn, 10 Sep 2026, looking at BiSTools' Hub: "this is beautiful ... I want all
  option windows to look like this." So it stopped being BiSTools' window and
  became this file. See claude/bis-options.md for the law it implements.

  One narrow flat window, no tabs, no rail, no logo, no Blizzard art:

      BiS> Options_                                   x     <- 16 px header, the prompt
      nebbinator                                      #     <- section (accent, header shade)
        minimap button                                #     <- toggle
        BiS channel (/biscomm)                        #
        reset window position                  [ reset ]    <- button
      recruiting                                            <- a section with no on/off box
        auto-reply                    [first][always][off]  <- seg
        send cooldown                      <  10 s  >       <- step

  Usage from any addon:

      local f = BiSTheme.Options("NebbinatorOptions", 230, "Options")
      f:Section("nebbinator")                          -- no box
      f:Section("farm", { get = ..., set = ... })      -- with an on/off box
      f:Row({ kind = "toggle", label = "minimap button", get = ..., set = ... }, db)
      f:Fit()                                          -- size the window to its rows
      f:Toggle()                                       -- show / hide
      f.onChange = function() ... end                  -- repaint anything else that cares

  THIS FILE CARRIES ITS OWN PRIMITIVES ON PURPOSE. It borrows no widget kit from
  its host - not BiSTools' Farm kit, not Nebbinator's Kit - so the third addon to
  adopt is a table and a TOC line, and so every options window in the family is
  the same pixels rather than the same intentions.

  Self-guarded like Console.lua: an addon may ship a copy under Libs\BiSTheme\ so
  the window works without BiSTheme installed. Newest OPTIONS_MINOR wins; the
  canonical file lives in the BiSTheme addon and is copied out, never edited in
  place. Load it AFTER Console.lua - it uses the prompt when there is one, and
  degrades to a plain title when there is not.
]]

BiSTheme = BiSTheme or {}
local T = BiSTheme
if (T.OPTIONS_MINOR or 0) >= 2 then return end
T.OPTIONS_MINOR = 2      -- 2: Escape closes the window (UISpecialFrames), Arn 10 Sep

-- palette fallback: only when this file is embedded and neither BiSTheme.lua nor
-- Console.lua ran. Same table, same values, deliberately duplicated - a shared
-- local between two embedded files is a load-order bet, and this file may be the
-- only one of the pair an addon ships.
if not T.rgb then
  local FALLBACK = {
    bg = "121020", surface = "1a1730", sunken = "221d3c", line = "2a2446",
    line2 = "3a3260", ink = "ece8f6", ink2 = "c6bedd", muted = "968ead",
    accent = "b980ff", accentSoft = "2c2148", good = "4fd0cf", warn = "f08cb0",
    gold = "e5c04a", slate = "8fb4d6", dim = "8e86a6",
  }
  T.hex = T.hex or FALLBACK
  local cache = {}
  function T.rgb(name)
    local hex = T.hex[name] or T.hex.ink
    local c = cache[hex]
    if c then return c[1], c[2], c[3] end
    c = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
    cache[hex] = c
    return c[1], c[2], c[3]
  end
  function T.rgba(name, a) local r, g, b = T.rgb(name) return r, g, b, a or 1 end
  function T.text(name, s) return "|cff" .. (T.hex[name] or T.hex.ink) .. tostring(s) .. "|r" end
end

-- Console.lua owns Fit; define it here too for an addon that ships Options
-- without the prompt.
if not T.Fit then
  function T.Fit(fs, text, width)
    fs:SetText(text)
    if not width or not fs.GetStringWidth then return text end
    local t = text
    while fs:GetStringWidth() > width and #t > 1 do
      t = t:sub(1, -2)
      fs:SetText(t .. "...")
    end
    return fs:GetText()
  end
end

-- The shape, in one table so an addon can read the numbers a test wants to
-- assert rather than repeating them.
T.OPTIONS = {
  W       = 230,   -- a narrow window; the label budget below is what keeps it narrow
  ROW     = 16,
  HEADER  = 16,
  BOX     = 10,
  SEG_W   = 36,    -- "always" at 8 pt is ~29 px; 36 leaves the ellipsis unused
  STEP_W  = 18,
  STEP_V  = 40,    -- the value text between < and >
  BTN_W   = 60,
  HEAD_A  = 0.5,
  BODY_A  = 0.45,
  PAD     = 4,
  CTL     = 110,   -- pixels reserved on the right for any control
  INDENT  = 12,    -- an option label's x; a section name sits at 6
}

-- The layered near-blacks. Not in BiSTheme.hex because they are chrome, not
-- palette: the same five names BiSTools' Farm kit and Nebbinator's Kit use, with
-- the same values, so a window built here matches the windows around it.
local SHADE = {
  frame = "0d0b18", header = "141127", field = "17132e", hair = "2a2446", edge = "3a3260",
}

local function colour(name)
  local hex = SHADE[name]
  if hex then
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
  end
  return T.rgb(name)
end

--------------------------------------------------------------------
-- primitives
--------------------------------------------------------------------

local P = {}

function P.tex(parent, layer, name, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetAllPoints()
  local r, g, b = colour(name)
  t:SetColorTexture(r, g, b, a or 1)
  return t
end

function P.fs(parent, text, size, name)
  local s = parent:CreateFontString(nil, "OVERLAY")
  s:SetFont(STANDARD_TEXT_FONT, size or 8, "")
  local r, g, b = colour(name or "ink")
  s:SetTextColor(r, g, b, 1)
  s:SetText(text or "")
  return s
end

function P.border(frame, name, a)
  local b = {}
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do
    local t = frame:CreateTexture(nil, "OVERLAY")
    local r, g, bl = colour(name)
    t:SetColorTexture(r, g, bl, a or 1)
    b[side] = t
  end
  b.top:SetPoint("TOPLEFT") b.top:SetPoint("TOPRIGHT") b.top:SetHeight(1)
  b.bottom:SetPoint("BOTTOMLEFT") b.bottom:SetPoint("BOTTOMRIGHT") b.bottom:SetHeight(1)
  b.left:SetPoint("TOPLEFT") b.left:SetPoint("BOTTOMLEFT") b.left:SetWidth(1)
  b.right:SetPoint("TOPRIGHT") b.right:SetPoint("BOTTOMRIGHT") b.right:SetWidth(1)
  -- The border remembers which colour name it is wearing. Four textures all
  -- holding the same three floats is not something a test can read back and
  -- name, and "assert on the paint, not the call" needs a name.
  b.name = name
  function b:set(n, alpha)
    local r, g, bl = colour(n)
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
      self[side]:SetColorTexture(r, g, bl, alpha or 1)
    end
    self.name = n
  end
  return b
end

-- a flat little button: field fill, edge border, accent on hover
function P.flat(parent, w, h, label, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  P.tex(b, "BACKGROUND", "field", 0.9)
  b.edge = P.border(b, "edge", 1)
  b.label = P.fs(b, label or "", size or 8, "muted")
  b.label:SetPoint("CENTER")
  b:SetScript("OnEnter", function(s) s.edge:set("accent", 1) end)
  b:SetScript("OnLeave", function(s) s.edge:set("edge", 1) end)
  return b
end

-- the 10 px on/off box: filled accent when on, empty edge when off
function P.box(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(T.OPTIONS.BOX, T.OPTIONS.BOX)
  b.fill = P.tex(b, "BACKGROUND", "accent", 1)
  b.edge = P.border(b, "edge", 1)
  function b:Set(on)
    self.on = on and true or false
    if self.on then
      self.fill:Show()
      self.edge:set("accent", 1)
    else
      self.fill:Hide()
      self.edge:set("edge", 1)
    end
  end
  b:Set(false)
  return b
end

T.OptionsPrimitives = P   -- an adopter may want the flat button for its own footer

--------------------------------------------------------------------
-- the four control kinds, and no more
--------------------------------------------------------------------
-- If a setting does not fit one of these four it is a slash command. No
-- sliders (230 px has no room for a track, and a stepper is exact), no
-- free-text fields, no dropdowns.

local KINDS = {}

function KINDS.toggle(f, row, opt, db)
  local b = P.box(row)
  b:SetPoint("RIGHT", -6, 0)
  b:SetScript("OnClick", function()
    opt.set(db, not opt.get(db))
    f:Paint()
    f:Say(opt.label .. (opt.get(db) and " on" or " off"), opt.get(db) and "good" or "warn")
  end)
  row.ctl = b
  row.paint = function() b:Set(opt.get(db) and true or false) end
end

function KINDS.seg(f, row, opt, db)
  local O, segs = T.OPTIONS, {}
  for i, v in ipairs(opt.values) do
    local s = P.flat(row, O.SEG_W, 12, v)
    s:SetPoint("RIGHT", -6 - (#opt.values - i) * (O.SEG_W + 2), 0)
    T.Fit(s.label, v, O.SEG_W - 4)
    s:SetScript("OnClick", function()
      opt.set(db, v)
      f:Paint()
      f:Say(opt.label .. ": " .. v, "ink2")
    end)
    segs[i] = s
  end
  row.ctl = segs
  row.paint = function()
    local cur = opt.get(db)
    for i, s in ipairs(segs) do
      local on = opt.values[i] == cur
      s.edge:set(on and "accent" or "edge", 1)
      local r, g, b = colour(on and "accent" or "muted")
      s.label:SetTextColor(r, g, b, 1)
      -- hover must not leave the live one looking dead
      s:SetScript("OnLeave", function(x) x.edge:set(on and "accent" or "edge", 1) end)
    end
  end
end

function KINDS.step(f, row, opt, db)
  local O = T.OPTIONS
  local plus = P.flat(row, O.STEP_W, 12, ">")
  plus:SetPoint("RIGHT", -6, 0)
  local val = P.fs(row, "", 8, "ink2")
  val:SetPoint("RIGHT", plus, "LEFT", -4, 0)
  local minus = P.flat(row, O.STEP_W, 12, "<")
  minus:SetPoint("RIGHT", plus, "LEFT", -(O.STEP_V + 6), 0)

  -- THE STEPPER CLAMPS, not the setter. A setting whose own setter clamps is
  -- welcome to, but this must hold for one that does not - otherwise every
  -- adopter has to remember, and one of them will not.
  local function bump(dir)
    local v = tonumber(opt.get(db)) or opt.min
    v = v + dir * opt.step
    if v < opt.min then v = opt.min elseif v > opt.max then v = opt.max end
    opt.set(db, v)
    f:Paint()
    f:Say(opt.label .. ": " .. opt.show(db), "ink2")
  end
  plus:SetScript("OnClick", function() bump(1) end)
  minus:SetScript("OnClick", function() bump(-1) end)

  row.ctl = { minus = minus, plus = plus, val = val }
  row.paint = function() T.Fit(val, opt.show(db), O.STEP_V) end
end

function KINDS.button(f, row, opt, db)
  local O = T.OPTIONS
  local b = P.flat(row, O.BTN_W, 12, opt.button or "go")
  b:SetPoint("RIGHT", -6, 0)
  T.Fit(b.label, opt.button or "go", O.BTN_W - 4)
  b:SetScript("OnClick", function()
    opt.action(db)
    f:Paint()
    f:Say(opt.label, "ink2")
  end)
  row.ctl = b
  row.paint = function() end
end

T.OptionKinds = KINDS   -- so a test can count them, and fail when a fifth appears

--------------------------------------------------------------------
-- the window
--------------------------------------------------------------------

local Opt = {}

--- Every change says itself in the prompt, never in the chat frame.
function Opt:Say(text, tone)
  if self.con then self.con:Say(text, tone) end
end

--- A section header: the addon's or tool's name, on the header shade. `box`
--- (optional) is a { get, set } pair - the thing this section switches on and off.
function Opt:Section(title, box)
  local O = T.OPTIONS
  local r = self:AddRow()
  r.isSection = true
  r.bg = P.tex(r, "BACKGROUND", "header", 0.6)
  r.name = P.fs(r, T.text("accent", title), 9, "ink")
  r.name:SetPoint("LEFT", 6, 0)
  T.Fit(r.name, T.text("accent", title), self.w - 6 - O.CTL)
  if box then
    local b = P.box(r)
    b:SetPoint("RIGHT", -6, 0)
    b:SetScript("OnClick", function()
      box.set(not box.get())
      self:Paint()
      if self.onChange then self.onChange() end
      self:Say(title .. (box.get() and " on" or " off"), box.get() and "good" or "warn")
    end)
    r.ctl = b
    r.paint = function() b:Set(box.get() and true or false) end
  end
  return r
end

--- One option row. `opt` is { kind, label, ... } per the four kinds above.
function Opt:Row(opt, db)
  local O = T.OPTIONS
  local build = KINDS[opt.kind]
  if not build then
    error("BiSTheme.Options: unknown control kind '" .. tostring(opt.kind) .. "' for '" ..
          tostring(opt.label) .. "'", 0)
  end
  local r = self:AddRow()
  r.opt = opt
  r.name = P.fs(r, opt.label, 8, "ink2")
  r.name:SetPoint("LEFT", O.INDENT, 0)
  -- Label budget: W - indent - control. Fit is the net, not the plan - pick
  -- plain words a raider understands and keep them under ~24 characters.
  T.Fit(r.name, opt.label, self.w - O.INDENT - O.CTL)
  build(self, r, opt, db)
  return r
end

--- The next 16 px row down the body, full width. Section and Row build on it;
--- a caller wanting a list rather than an options list (BiSTools' Hub) asks for
--- a "Button" and decorates it itself.
function Opt:AddRow(frameType, name)
  local O = T.OPTIONS
  local r = CreateFrame(frameType or "Frame", name, self.body)
  r:SetHeight(O.ROW)
  r:SetPoint("TOPLEFT", 0, -self._y)
  r:SetPoint("TOPRIGHT", 0, -self._y)
  self._y = self._y + O.ROW
  self.rows[#self.rows + 1] = r
  return r
end

--- Size the window to the rows it ended up with: header + rows + a little pad.
--- `footH` is for a caller that pinned something to the bottom itself (the Hub's
--- `options` bar); an options window proper has no footer.
function Opt:Fit(footH)
  local O = T.OPTIONS
  local body = math.max(self._y + O.PAD, 1)
  self.body:SetHeight(body)
  self:SetHeight(O.HEADER + body + (footH or 0))
  self:Paint()
  return self
end

function Opt:Paint()
  for _, r in ipairs(self.rows) do if r.paint then r.paint() end end
end

function Opt:Toggle(want)
  if want == nil then want = not self:IsShown() end
  if want then self:Paint() self:Show() else self:Hide() end
end

--- Drag the window back to the middle. "reset window position" wires to this.
function Opt:Recenter(y)
  self:ClearAllPoints()
  self:SetPoint("CENTER", UIParent, "CENTER", 0, y or 60)
end

--- Build the frame. Returns it with Section / Row / Fit / Paint / Toggle on it.
function T.Options(name, w, title)
  local O = T.OPTIONS
  w = w or O.W
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, O.HEADER)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  P.tex(f, "BACKGROUND", "frame", O.BODY_A)
  P.border(f, "edge", 0.35)

  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT") head:SetPoint("TOPRIGHT")
  head:SetHeight(O.HEADER)
  P.tex(head, "BACKGROUND", "header", O.HEAD_A)
  local hair = head:CreateTexture(nil, "BORDER")
  hair:SetPoint("BOTTOMLEFT") hair:SetPoint("BOTTOMRIGHT") hair:SetHeight(1)
  do local r, g, b = colour("edge") hair:SetColorTexture(r, g, b, 1) end

  -- Header budget, per the header law: 4 + prompt (<= w - 15 - 8) on the left,
  -- one 12 px x at -3 on the right. Nothing else goes in a 16 px bar.
  local fs = P.fs(head, "", 8, "ink")
  fs:SetPoint("LEFT", head, "LEFT", 4, 0)
  if T.Console then
    f.con = T.Console(fs, { width = w - 15 - 8 })
    f.con:Set("name", title or "Options", "accent")
  else
    T.Fit(fs, T.text("accent", title or "Options"), w - 15 - 8)
  end
  f.title = fs

  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function() if not InCombatLockdown() then f:StartMoving() end end)
  head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local close = P.flat(head, 12, 12, "x")
  close:SetPoint("RIGHT", head, "RIGHT", -3, 0)
  do local r, g, b = colour("warn") close.label:SetTextColor(r, g, b, 1) end
  close:SetScript("OnClick", function() f:Hide() end)
  close:SetScript("OnEnter", function(s) s.edge:set("warn", 1) end)
  f.closeBtn = close

  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
  body:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
  body:SetHeight(1)

  f.head, f.body, f.rows, f.w, f._y = head, body, {}, w, 0
  for k, v in pairs(Opt) do f[k] = v end

  -- A new frame is shown by default and the toggle is what decides. The harness
  -- caught this on the Hub's first day.
  f:Hide()

  -- Escape closes it, like every Blizzard panel (Arn, 10 Sep: "if you press esc
  -- it should close that option window" - on every BiS addon). The client
  -- closes the newest shown frame in UISpecialFrames on Escape; a name is
  -- required, and T.Options always has one.
  if name and UISpecialFrames then
    local listed = false
    for _, n in ipairs(UISpecialFrames) do if n == name then listed = true end end
    if not listed then table.insert(UISpecialFrames, name) end
  end

  if f.con then
    f:SetScript("OnUpdate", function(_, dt)
      f.elapsed = (f.elapsed or 0) + dt
      if f.elapsed >= 0.1 then f.elapsed = 0 f.con:Paint() end
    end)
  end
  return f
end
