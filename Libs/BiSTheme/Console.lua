--[[
  BiSTheme / Console.lua  --  the "BiS> _" prompt every BiS window carries in its header.

  Arn, 8 Sep 2026: "prompt `BiS> _` blinking should be in the header and cycle
  relevant messages: addon name, summoners at the stone, receiving summon,
  requesting summon, etc." Chat stays clean: what the addon is doing is said
  here, not in the chat frame. Chat is for /slash answers only.

  The title FontString of the window IS the console. It shows

      BiS> <text>_            cursor blinking at 2 Hz

  The words fade out and the next ones fade in (Arn: "fade in and out animations,
  not hard cuts"); the `BiS> ` prompt itself never moves. The console makes one
  extra FontString for the words, anchored to the right of the title.

  where <text> is either a standing SLOT (the addon's name, "2 at stone",
  "requesting...") - the slots rotate every `cycle` seconds - or a transient
  line pushed with Say ("Druid asks", "Druid accepted"), which jumps the queue,
  holds for `hold` seconds, then the rotation resumes.

  Usage from any addon:

      local con = BiSTheme.Console(titleFontString, { width = 110, size = 8 })
      con:Set("name", "Summon")                 -- slot 1: always the addon's name
      con:Set("stone", "2 at stone", "good")    -- a state slot; nil text clears it
      con:Say("Druid asks", "gold")             -- an event line, shown once
      con:Paint()                               -- from a ~0.2 s ticker: blink, rotate, expire

  Slots rotate in the order they were first Set. Pick words that fit the box:
  T.Fit trims with an ellipsis as the net, not the plan.

  Self-guarded like LibBiSComm: an addon may ship a copy under Libs\BiSTheme\ so
  the prompt works without BiSTheme installed. Newest CONSOLE_MINOR wins; the
  canonical file lives in the BiSTheme addon and is copied out, never edited in
  place. If BiSTheme itself is absent the palette falls back inline.
]]

BiSTheme = BiSTheme or {}
local T = BiSTheme
if (T.CONSOLE_MINOR or 0) >= 4 then return end
T.CONSOLE_MINOR = 4      -- 4: the cursor is its own FontString, blinked by alpha -- the words never move (11 Sep 2026)
                         -- 3: a toggled slot no longer re-appends itself to the rotation

-- palette fallback: only when this file is embedded and BiSTheme.lua never ran
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

-- defaults; an addon may override per console through opts
T.CONSOLE = {
  cycle  = 3,       -- seconds a standing slot shows before the next one
  hold   = 3,       -- seconds a Say line holds before the rotation resumes
  fade   = 0.25,    -- seconds to fade the words out, and again to fade the next in
  size   = 8,       -- font size of the words (the title's own size is the caller's)
  prompt = "BiS> ",
}

--- A label must fit its box: shrink with an ellipsis until GetStringWidth says so.
--- (Arn, 8 Sep: "summon requested - click to cancel" ran into the "all" button.)
--- Pick text that fits outright; the ellipsis is the net, not the plan.
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

local Con = {}
Con.__index = Con

--- Wrap a FontString (the window's title) as the prompt. The title keeps "BiS> ";
--- the words live in a second FontString to its right so they can fade on their own.
function T.Console(fs, opts)
  opts = opts or {}
  local D = T.CONSOLE
  local c = setmetatable({}, Con)
  c.fs, c.width = fs, opts.width
  c.cycle, c.hold, c.fadeT = opts.cycle or D.cycle, opts.hold or D.hold, opts.fade or D.fade
  c.slots, c.order, c.queue = {}, {}, {}
  c.idx, c.since = 1, GetTime()
  fs:SetText(T.text("accent", D.prompt))
  local w = fs:GetParent():CreateFontString(nil, "OVERLAY")
  -- THE USER'S FONT WHEN ONE IS LENT. T.SetFont is BiSTheme's, and falls back to the client's own
  -- when there is no lender or the path is refused - a FontString whose SetFont failed draws
  -- nothing at all, which is an invisible label rather than an ugly one.
  if T.SetFont then T.SetFont(w, opts.size or D.size) else w:SetFont(STANDARD_TEXT_FONT, opts.size or D.size, "") end
  w:SetPoint("LEFT", fs, "RIGHT", 0, 0)
  w:SetText("")
  c.words = w
  -- minor 4: the cursor is a FontString of its own, hung off the words' right
  -- edge and blinked by ALPHA. Up to minor 3 it was a "_"/" " swapped into the
  -- words text, and on the client that swap moved the words a hair every half
  -- second (Arn, on the Healing plate: "Heal_ moves like one space forward").
  local cur = fs:GetParent():CreateFontString(nil, "OVERLAY")
  if T.SetFont then T.SetFont(cur, opts.size or D.size) else cur:SetFont(STANDARD_TEXT_FONT, opts.size or D.size, "") end
  cur:SetPoint("LEFT", w, "RIGHT", 0, 0)
  cur:SetText(T.text("ink2", "_"))
  c.cur = cur
  if fs.GetStringWidth then
    c.promptW = fs:GetStringWidth()
    c.curW = cur:GetStringWidth()
  end
  c.alpha = 1
  c:Paint()
  return c
end

--- The whole line as text (prompt + words + cursor) and its width, for checks.
--- The cursor reads as "_" when lit and " " when blinked off, as it always did.
function Con:Text()
  return (self.fs:GetText() or "") .. (self.words:GetText() or "") .. (self.curOn and "_" or " ")
end
function Con:Width()
  if not self.fs.GetStringWidth then return 0 end
  return self.fs:GetStringWidth() + self.words:GetStringWidth() + (self.curW or 0)
end

--- A standing slot: shown in rotation while it has text. nil clears it.
function Con:Set(key, text, colour)
  if text == nil or text == "" then
    self.slots[key] = nil
  else
    -- minor 3: a key keeps its place in the rotation for good. Clearing a slot and
    -- setting it again used to append the key a second time (the slot was nil, so it
    -- looked new), and a slot that toggles - Nebbinator's `N new`, Tools' `asking` -
    -- ended up in `order` five or six times and hogged the rotation.
    local known = false
    for _, k in ipairs(self.order) do if k == key then known = true break end end
    if not known then self.order[#self.order + 1] = key end
    self.slots[key] = { text = tostring(text), colour = colour or "ink" }
  end
  self:Paint()
end

--- An event line: jumps the rotation, holds `hold` seconds, then the slots resume.
--- Several in a row queue up and show one after the other.
function Con:Say(text, colour)
  local q = self.queue
  q[#q + 1] = { text = tostring(text), colour = colour or "ink2" }
  self:Paint()
end

function Con:Clear()
  self.queue = {}
  self:Paint()
end

-- the slot in rotation right now, skipping cleared keys
function Con:Current(now)
  local live = {}
  for _, k in ipairs(self.order) do if self.slots[k] then live[#live + 1] = self.slots[k] end end
  if #live == 0 then return nil end
  if now - self.since >= self.cycle then
    self.idx = self.idx + 1
    self.since = now
  end
  if self.idx > #live then self.idx = 1 end
  return live[self.idx]
end

--- Blink the cursor, rotate the slots, expire the said line. Call from a ticker.
function Con:Paint()
  local now = GetTime()
  local line
  if self.saying then
    if now - self.saidAt >= self.hold then
      self.saying = nil
      self.since = now   -- the slot after a Say gets its full cycle
    else
      line = self.saying
    end
  end
  if not line and #self.queue > 0 then
    self.saying = table.remove(self.queue, 1)
    self.saidAt = now
    line = self.saying
  end
  if not line then line = self:Current(now) end
  -- fade: the words on screen go to 0 over fadeT, the new words come up from 0
  local same = (line == nil and self.line == nil) or
    (line and self.line and line.text == self.line.text and line.colour == self.line.colour)
  if not same and self.fading ~= "out" then
    self.fading, self.fadeAt = "out", now
  end
  local a = 1
  if self.fadeAt and self.fadeAt > now then self.fadeAt = now end   -- a clock that moved back
  if self.fading == "out" then
    a = 1 - (now - self.fadeAt) / self.fadeT
    if a <= 0 then
      a = 0
      self.line = line
      self.fading, self.fadeAt = "in", now
    end
  elseif self.fading == "in" then
    a = (now - self.fadeAt) / self.fadeT
    if a >= 1 then a = 1 self.fading = nil end
  end
  self.alpha = a
  self.words:SetAlpha(a)
  local shown = self.line
  local blink = math.floor(now * 2) % 2 == 0
  self.curOn = blink
  self.cur:SetAlpha(blink and 1 or 0)     -- the cursor blinks; the words stay put
  local words = shown and shown.text or ""
  if self.width and shown then
    -- trim the plain words only (never inside a colour escape); prompt and
    -- cursor keep their own width outside the trim
    words = T.Fit(self.words, words, self.width - (self.curW or 0) - (self.promptW or 0))
  end
  self.words:SetText(shown and T.text(shown.colour, words) or "")
end
