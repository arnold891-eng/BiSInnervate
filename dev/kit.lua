-- Nebbinator headless harness.
--
-- STRICT on the paint methods on purpose. `cond and T.rgba(name) or shade(name)`
-- truncates a multi-return to one value; the live client throws on the spot and
-- takes the whole window with it, and a stub that accepts anything turns that
-- into a bug you only meet in a raid. Every colour setter below errors unless it
-- got real numbers, and every one of them RECORDS what it was given so tests can
-- assert on the paint rather than on the call.

local H = {}
_G.HARNESS = H
H.sent, H.prints, H.sounds, H.who = {}, {}, {}, {}

local function isnum(v) return type(v) == "number" end

--------------------------------------------------------------------
-- regions
--------------------------------------------------------------------

local function autoMethods(t)
    return setmetatable(t, { __index = function(_, k)
        -- WoW methods are UpperCamel; a lowercase miss is a plain field and
        -- must read nil, exactly like a real frame.
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end })
end

local function newTexture()
    local t = { _shown = true }
    function t:SetAllPoints() end
    function t:SetPoint() end
    function t:ClearAllPoints() end
    function t:SetWidth(w) self._w = w end
    function t:SetHeight(h) self._h = h end
    function t:SetSize(w, h) self._w, self._h = w, h end
    function t:SetColorTexture(r, g, b, a)
        if not (isnum(r) and isnum(g) and isnum(b)) then
            error(("SetColorTexture needs r,g,b(,a) numbers - got %s,%s,%s")
                :format(type(r), type(g), type(b)), 0)
        end
        if a ~= nil and not isnum(a) then error("SetColorTexture alpha must be a number", 0) end
        self._color = { r, g, b, a or 1 }
    end
    function t:SetVertexColor(r, g, b, a)
        if not (isnum(r) and isnum(g) and isnum(b)) then
            error("SetVertexColor needs r,g,b(,a) numbers", 0)
        end
        self._vertex = { r, g, b, a or 1 }
    end
    function t:SetTexture(...)
        if select("#", ...) > 1 then error("SetTexture(r,g,b,a) does nothing - use SetColorTexture", 0) end
        self._texture = (select(1, ...))
    end
    function t:SetTexCoord() end
    function t:Show() self._shown = true end
    function t:Hide() self._shown = false end
    function t:IsShown() return self._shown end
    return autoMethods(t)
end

local function newFontString(owner)
    local f = { _text = "", _shown = true, _alpha = 1, _size = 9, _parent = owner }
    function f:SetText(v) self._text = tostring(v or "") end
    function f:GetText() return self._text end
    function f:SetPoint(point, a, b, c, d)
        self._points = self._points or {}
        if type(a) == "table" then
            table.insert(self._points, { point = point, rel = a, relPoint = b, x = c or 0, y = d or 0 })
        else
            table.insert(self._points, { point = point, rel = nil, relPoint = point, x = a or 0, y = b or 0 })
        end
    end
    function f:OffsetFor(point)
        for _, p in ipairs(self._points or {}) do
            if p.point == point then return p.x, p.y end
        end
    end
    function f:ClearAllPoints() self._points = {} end
    function f:SetWidth(w) self._w = w end
    function f:SetHeight(h) self._h = h end
    function f:SetJustifyH() end
    function f:SetWordWrap() end
    function f:SetAlpha(a) self._alpha = a end
    function f:GetAlpha() return self._alpha end
    function f:GetParent() return self._parent end
    -- ~0.6 px per point per character: 9 pt = 5.4, 8 pt = 4.8. Close enough to
    -- catch a label that runs into the next control or off the window. Inline
    -- textures |T...:w:h...|t take their declared width; colour escapes take none.
    function f:GetStringWidth()
        local t, tex = tostring(self._text or ""), 0
        t = t:gsub("|T[^|]-:(%d+):%d+[^|]*|t", function(w) tex = tex + tonumber(w) return "" end)
        t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return #t * (self._size or 9) * 0.6 + tex
    end
    function f:SetTextColor(r, g, b, a)
        if not (isnum(r) and isnum(g) and isnum(b)) then
            error(("SetTextColor needs r,g,b(,a) numbers - got %s,%s,%s")
                :format(type(r), type(g), type(b)), 0)
        end
        self._color = { r, g, b, a or 1 }
    end
    function f:SetFont(path, size)
        if type(path) ~= "string" or type(size) ~= "number" then
            error("SetFont needs a path and a size", 0)
        end
        self._font, self._size = path, size
    end
    function f:GetFont() return self._font, self._size end
    function f:SetFontObject(o) self._fontObject = o; self._font = self._font or "Fonts\\FRIZQT__.TTF" end
    function f:SetWordWrap() end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    return autoMethods(f)
end

--------------------------------------------------------------------
-- frames
--------------------------------------------------------------------

H.frames = {}

local function newFrame(ftype, name, parent)
    local fr = {
        _type = ftype, _name = name, _parent = parent,
        _scripts = {}, _events = {}, _shown = true,
        _w = 200, _h = 24, _text = "", _enabled = true,
    }
    H.frames[#H.frames + 1] = fr

    function fr:GetName() return self._name end
    function fr:GetParent() return self._parent end
    function fr:SetSize(w, h) self._w, self._h = w, h end
    function fr:SetWidth(w) self._w = w end
    function fr:SetHeight(h) self._h = h end
    function fr:GetWidth() return self._w end
    function fr:GetHeight() return self._h end
    -- Enough anchor maths to catch a window that WALKS. These used to be flat
    -- constants, so `Relayout` could drop the frame by its own height on every
    -- call and no test could ever see it. A frame anchored to UIParent's
    -- bottom-left really does know where its own top edge is; anything else
    -- keeps the old constants.
    local function anchorToUIParent(self)
        for _, p in ipairs(self._points or {}) do
            if p.rel == _G.UIParent and p.relPoint == "BOTTOMLEFT" then return p end
        end
    end
    function fr:GetTop()
        local p = anchorToUIParent(self)
        if not p then return 600 end
        if p.point == "TOPLEFT" or p.point == "TOPRIGHT" then return p.y end
        if p.point == "BOTTOMLEFT" or p.point == "BOTTOMRIGHT" then return p.y + (self._h or 0) end
        return 600
    end
    function fr:GetLeft()
        local p = anchorToUIParent(self)
        if not p then return 100 end
        if p.point == "TOPLEFT" or p.point == "BOTTOMLEFT" then return p.x end
        return 100
    end
    function fr:GetEffectiveScale() return 1 end
    function fr:GetCenter() return 100, 100 end
    function fr:SetPoint(point, a, b, c, d)
        self._points = self._points or {}
        if type(a) == "table" then
            table.insert(self._points, { point = point, rel = a, relPoint = b, x = c or 0, y = d or 0 })
        else
            table.insert(self._points, { point = point, rel = self._parent, relPoint = point, x = a or 0, y = b or 0 })
        end
    end
    function fr:GetPoints() return self._points or {} end
    function fr:OffsetFor(point)
        for _, p in ipairs(self._points or {}) do
            if p.point == point then return p.x, p.y end
        end
    end
    function fr:ClearAllPoints() self._points = {} end
    function fr:SetAllPoints() end
    function fr:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function fr:GetNumPoints() return 1 end
    function fr:Show() self._shown = true end
    function fr:Hide() self._shown = false end
    function fr:IsShown() return self._shown end
    function fr:IsVisible()
        if not self._shown then return false end
        local up = self._parent
        while type(up) == "table" and up.IsShown do
            if not up._shown then return false end
            up = up._parent
        end
        return true
    end
    function fr:CreateTexture() local t = newTexture(); self._regions = self._regions or {}; table.insert(self._regions, t); return t end
    function fr:CreateFontString() local f = newFontString(self); self._regions = self._regions or {}; table.insert(self._regions, f); return f end
    function fr:SetScript(k, fn) self._scripts[k] = fn end
    function fr:GetScript(k) return self._scripts[k] end
    function fr:HookScript(k, fn) self._scripts["hook_" .. k] = fn end
    function fr:RegisterEvent(e) self._events[e] = true end
    function fr:UnregisterAllEvents() self._events = {} end
    function fr:Fire(script, ...) local fn = self._scripts[script]; if fn then return fn(self, ...) end end
    function fr:Click(button) return self:Fire("OnClick", button or "LeftButton") end
    function fr:SetEnabled(v) self._enabled = v and true or false end
    function fr:IsEnabled() return self._enabled end
    function fr:EnableMouse(v) self._mouse = v end
    function fr:SetVerticalScroll(v) self._scroll = v end
    function fr:GetVerticalScroll() return self._scroll or 0 end
    function fr:SetScrollChild(c) self._child = c end

    if ftype == "EditBox" then
        function fr:SetText(v)
            self._text = tostring(v or "")
            local fn = self._scripts.OnTextChanged
            if fn then fn(self, false) end
        end
        function fr:GetText() return self._text end
        function fr:Insert(v) self._text = (self._text or "") .. tostring(v) end
        function fr:HasFocus() return self._focus and true or false end
        function fr:SetFocus() self._focus = true end
        function fr:ClearFocus() self._focus = false end
        function fr:HighlightText() self._highlighted = true end
        function fr:SetCursorPosition() end
        function fr:SetAutoFocus() end
        function fr:SetMaxLetters() end
        function fr:SetNumeric(v) self._numeric = v end
        function fr:SetMultiLine() end
        function fr:SetJustifyH() end
        function fr:SetTextColor(r, g, b, a)
            if not (isnum(r) and isnum(g) and isnum(b)) then
                error("EditBox SetTextColor needs r,g,b numbers", 0)
            end
            self._color = { r, g, b, a or 1 }
        end
        function fr:SetFont(path, size)
            if type(path) ~= "string" or type(size) ~= "number" then error("SetFont needs a path and a size", 0) end
            self._font, self._size = path, size
        end
        function fr:GetFont() return self._font, self._size end
        function fr:SetFontObject(o) self._font = self._font or "Fonts\\FRIZQT__.TTF" end
        -- type into it the way a player would: userInput = true
        function fr:Type(v)
            self._text = tostring(v or "")
            local fn = self._scripts.OnTextChanged
            if fn then fn(self, true) end
        end
    end

    return autoMethods(fr)
end

function _G.CreateFrame(ftype, name, parent, template)
    local f = newFrame(ftype, name, parent, template)
    if name then rawset(_G, name, f) end
    return f
end

--------------------------------------------------------------------
-- globals
--------------------------------------------------------------------

_G.UIParent = newFrame("Frame", "UIParent")
_G.UIParent._w, _G.UIParent._h = 1920, 1080
_G.Minimap  = newFrame("Frame", "Minimap")
_G.UISpecialFrames = {}
_G.StaticPopupDialogs = {}
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.YES, _G.NO = "Yes", "No"
_G.SOUNDKIT = { TELL_MESSAGE = 3081, MURLOC_AGGRO = 416, RAID_WARNING = 8959,
                AUCTION_WINDOW_OPEN = 5274, MAP_PING = 3175, LEVELUP = 888 }
_G.SlashCmdList = {}

_G.GameTooltip = autoMethods({
    SetOwner = function() end, AddLine = function() end, Show = function() end,
    Hide = function() end, SetText = function() end,
})

_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) H.prints[#H.prints + 1] = msg end }
local realprint = print
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    H.prints[#H.prints + 1] = table.concat(parts, " ")
end
H.say = realprint

_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert = table.insert
_G.time = os.time
H.clock = 1000
_G.GetTime = function() return H.clock end
_G.GetCursorPosition = function() return 300, 400 end

_G.PlaySoundFile = function(path, channel)
    if path:find("LevelUp") then return false end
    H.sounds[#H.sounds + 1] = "file:" .. path .. "/" .. tostring(channel)
    return true
end
_G.PlaySound = function(id, channel)
    H.sounds[#H.sounds + 1] = "kit:" .. tostring(id) .. "/" .. tostring(channel)
    return true
end

H.timers = {}
_G.C_Timer = { After = function(delay, fn) H.timers[#H.timers + 1] = { delay = delay, fn = fn } end }
function H.RunTimers()
    local list = H.timers
    H.timers = {}
    for _, t in ipairs(list) do t.fn() end
end

_G.UnitName = function() return "Kumlust" end
_G.UnitLevel = function() return 70 end
_G.GetRealmName = function() return "Dreamscythe" end
_G.UnitFactionGroup = function() return "Alliance" end
_G.GetGuildInfo = function() return "The Heathens" end
_G.IsInGuild = function() return true end
_G.GetNumGuildMembers = function() return 1 end
_G.GetGuildRosterInfo = function() return "Kumlust" end
_G.C_GuildInfo = { GuildRoster = function() end }
_G.CanGuildInvite = function() return true end
_G.GuildInvite = function(n) H.guildInvited = n end
_G.InviteUnit = function(n) H.invited = n end
_G.C_PartyInfo = { InviteUnit = function(n) H.invited = n end }
_G.ChatFrame_OpenChat = function(t) H.chatOpened = t end
_G.StaticPopup_Show = function(n) H.popup = n end
H.filters = {}
_G.ChatFrame_AddMessageEventFilter = function(e, fn) H.filters[e] = fn end

_G.GetChannelList = function()
    return 1, "General - Shattrath City", false,
           2, "Trade - City", false,
           3, "LocalDefense", false,
           4, "LookingForGroup", false,
           5, "GuildRecruitment", false
end
_G.GetChannelName = function(n)
    local map = { general = 1, trade = 2, localdefense = 3, lookingforgroup = 4, guildrecruitment = 5 }
    return map[tostring(n):lower()] or 0
end
_G.SendChatMessage = function(msg, chatType, lang, target)
    H.sent[#H.sent + 1] = { msg = msg, chatType = chatType, target = target }
end

_G.GetPlayerInfoByGUID = function() return "Mage", "MAGE", "Gnome", "Gnome", "Male", "Kumlance", "Dreamscythe" end
_G.RAID_CLASS_COLORS = nil
_G.LOCALIZED_CLASS_NAMES_MALE = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
_G.LOCALIZED_CLASS_NAMES_FEMALE = _G.LOCALIZED_CLASS_NAMES_MALE

_G.C_FriendList = {
    SendWho = function(q) H.who[#H.who + 1] = q end,
    SetWhoToUI = function(v) H.whoToUI = v end,
    GetNumWhoResults = function() return 0 end,
    GetWhoInfo = function() return nil end,
}

--------------------------------------------------------------------
-- what LibBiSComm reaches for
--------------------------------------------------------------------

H.wire = {}            -- every addon message this client put on the wire
H.raid = { { name = "Kumlust" } }
H.inRaid = false

_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) H.prefix = p return true end,
    SendAddonMessage = function(prefix, msg, channel)
        H.wire[#H.wire + 1] = { prefix = prefix, msg = msg, channel = channel }
    end,
}
_G.SendAddonMessage = function(prefix, msg, channel)
    H.wire[#H.wire + 1] = { prefix = prefix, msg = msg, channel = channel }
end
_G.RegisterAddonMessagePrefix = function(p) H.prefix = p return true end

_G.IsInRaid = function() return H.inRaid end
_G.IsInGroup = function() return H.inRaid end
_G.GetNumGroupMembers = function() return H.inRaid and #H.raid or 0 end
_G.UnitExists = function(unit)
    if unit == "player" then return true end
    local i = tostring(unit):match("^raid(%d+)$") or tostring(unit):match("^party(%d+)$")
    return i ~= nil and H.raid[tonumber(i)] ~= nil
end
_G.UnitIsPlayer = function() return true end
_G.UnitPosition = function() return 1000, 1000, 0, 530 end
_G.IsInInstance = function() return false, "none" end
_G.GetInstanceInfo = function() return "Netherstorm", "none", 0, "", 0, 0, false, 530 end
_G.GetZoneText = function() return "Netherstorm" end
_G.GetSubZoneText = function() return "" end
_G.ConfirmSummon = function() H.confirmed = true end
_G.hooksecurefunc = function(name, fn) H.hooked = H.hooked or {}; H.hooked[name] = fn end
_G.GetAddOnMetadata = function(_, key) return key == "Version" and "test" or nil end

--------------------------------------------------------------------
-- loading, with a trap for accidental globals
--------------------------------------------------------------------

local ALLOWED_GLOBALS = {
    Nebbinator = true, NebbinatorDB = true, NubbinatorDB = true,
    SLASH_NEBBINATOR1 = true, SLASH_NEBBINATOR2 = true, SLASH_NEBBINATOR3 = true,
    NebbinatorFrame = true, NebbinatorCopyBox = true, NebbinatorMinimapButton = true,
    HARNESS = true, print = true,
    -- shared, embedded, and global by design
    BiSTheme = true, LibBiSComm = true, SLASH_BISCOMM1 = true,
}

--- The TOC is the truth for what loads and in what order. Every suite reads it
--- rather than keeping its own copy of the list: dev/theme.lua kept one, drifted,
--- and was still loading UI/Pages/Responders.lua a day after the TOC dropped it -
--- a suite testing an addon the client does not run. Same family as landmine 0c.
function H.TOC(root, name)
    local fh = assert(io.open(root .. "/" .. name, "r"))
    local list = {}
    for line in fh:lines() do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:match("^#") then list[#list + 1] = (line:gsub("\\", "/")) end
    end
    fh:close()
    return list
end

function H.Load(root, files)
    local before = {}
    for k in pairs(_G) do before[k] = true end

    local NS = {}
    for _, rel in ipairs(files) do
        local chunk, err = loadfile(root .. "/" .. rel)
        if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
        chunk("Nebbinator", NS)
    end

    H.leaked = {}
    for k in pairs(_G) do
        if not before[k] and not ALLOWED_GLOBALS[k] then H.leaked[#H.leaked + 1] = tostring(k) end
    end
    table.sort(H.leaked)
    return NS
end

--------------------------------------------------------------------
-- assertions
--------------------------------------------------------------------

H.pass, H.fail = 0, 0

function H.ok(cond, label, extra)
    if cond then
        H.pass = H.pass + 1
    else
        H.fail = H.fail + 1
        H.say("  FAIL  " .. label .. (extra and ("   [" .. tostring(extra) .. "]") or ""))
    end
end

function H.eq(got, want, label)
    H.ok(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end

-- compare a recorded paint against a palette colour
function H.isColor(recorded, r, g, b, label)
    if not recorded then return H.ok(false, label, "nothing painted") end
    local near = math.abs(recorded[1] - r) < 0.01
        and math.abs(recorded[2] - g) < 0.01
        and math.abs(recorded[3] - b) < 0.01
    H.ok(near, label, ("painted %.3f,%.3f,%.3f"):format(recorded[1], recorded[2], recorded[3]))
end

function H.section(name) H.say("\n" .. name) end

function H.report()
    H.say(("\n%d passed, %d failed"):format(H.pass, H.fail))
    if H.fail > 0 then os.exit(1) end
end

return H
