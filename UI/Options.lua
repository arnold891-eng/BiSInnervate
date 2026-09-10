-- BiS Innervate :: UI/Options.lua
--
-- The options window, on BiSTheme's shared kit (Libs\BiSTheme\Options.lua).
-- Arn, 10 Sep 2026, looking at BiSTools' window: "this is beautiful ... I want
-- all option windows to look like this." Innervate is the third addon to wear
-- it, so the generic half lives in the lib and this file is only a list.
--
-- The old five-page Fojji-flat panel (UI/Config.lua) is gone. What did not fit
-- the four control kinds went where it belongs instead:
--
--   who may call (7 classes)   -> /inn callers [class]
--   the rez keybind            -> /inn bind <KEY> / unbind
--   rezzers, heals, scoreboard -> /inn rezzers, /inn rezheals, /inn rezscore
--   the About page             -> /inn help, /inn version, the minimap tooltip
--   the demo                   -> /inn demo (shift-right on the minimap button)
--
-- EVERY `set` HERE CALLS THE FUNCTION THE SLASH COMMAND ALREADY OWNS (the
-- NS.Set* family in Core/Options.lua, W:SetMagesOnly, Minimap:Set ...). None
-- writes a saved variable itself. Two paths that write the same key
-- separately drift; two paths through one function cannot.
--
-- COMBAT: this window holds no secure children, so it is safe to build, show
-- and paint mid-fight. The setters that reach the protected main window
-- (scale, the modes, faces, the rez switches, reset) each defer through the
-- Window function that already waits for AfterCombat; the row still repaints
-- from the db at once, which is right - the value changed, the frame catches
-- up when the fight ends.

local ADDON, NS = ...

local Config = {}
NS.Config = Config          -- the name every caller already uses (/inn config, cfg, minimap)

local T = NS.T

local function db() return NS.db end
local function pct(v) return math.floor(v + 0.5) .. "%" end

-- the voice stepper walks { auto, <installed packs...>, off }, built when the
-- window is built: FojjiCore renames and drops packs between releases, and
-- "auto" never names one - it takes the first pack that carries our lines
function Config:VoiceList()
    local list = { "auto" }
    for _, p in ipairs(NS.Sound:VoicePacks()) do list[#list + 1] = p end
    list[#list + 1] = "off"
    return list
end

function Config:VoiceIndex(list)
    local cur = db().voice or "auto"
    for i, v in ipairs(list) do if v == cur then return i end end
    return 1
end

--- The addon's own section first, then its settings by area. Labels are plain
--- words under ~24 characters: the kit's budget is W - 12 - 110 and
--- BiSTheme.Fit is the net, not the plan. `key` is what Config:Set / :Get
--- address (the slash commands and the tests go through the same setters).
function Config:OptionSections()
    local voices = self:VoiceList()
    return {
        { title = "innervate", options = {
            { key = "minimap", kind = "toggle", label = "minimap button",
              get = function() return db().minimap ~= false end,
              set = function(_, on) NS.Minimap:Set(on) end },
            { key = "comm", kind = "toggle", label = "BiS channel (/biscomm)",
              get = function() local l = _G.LibBiSComm return l and l:Enabled() or false end,
              set = function(_, on) local l = _G.LibBiSComm if l then l:SetEnabled(on and true or false) end end },
            { key = "reset", kind = "button", label = "put the window back", button = "reset",
              action = function() NS.HandleSlash("reset") end },
        } },

        { title = "window", options = {
            { key = "scale", kind = "step", label = "scale", min = 0.5, max = 2, step = 0.05,
              get = function() return db().scale or 1 end,
              set = function(_, v) NS.SetScale(v) end,
              show = function() return pct((db().scale or 1) * 100) end },
            { key = "locked", kind = "toggle", label = "lock it in place",
              get = function() return db().locked and true or false end,
              set = function(_, on) NS.SetLocked(on) end },
            { key = "magesOnly", kind = "toggle", label = "mages only (Odiss mode)",
              get = function() return db().magesOnly and true or false end,
              set = function(_, on) NS.Window:SetMagesOnly(on) end },
            { key = "healerOnly", kind = "toggle", label = "healer mode (Neb mode)",
              get = function() return db().healerOnly and true or false end,
              set = function(_, on) NS.Window:SetHealerOnly(on) end },
            { key = "portraits3d", kind = "seg", label = "faces", values = { "flat", "3D" },
              get = function() return db().portraits3d and "3D" or "flat" end,
              set = function(_, v) NS.SetFaces3D(v == "3D") end },
            { key = "flyoutDir", kind = "seg", label = "drum types unfold", values = { "up", "down" },
              get = function() return db().flyoutDir or "up" end,
              set = function(_, v) NS.SetFlyoutDir(v) end },
        } },

        { title = "rez button", options = {
            { key = "rez", kind = "toggle", label = "rez / heal / drink button",
              get = function() return db().rez ~= false end,
              set = function(_, on) NS.SetRez(on) end },
            { key = "rezHeal", kind = "toggle", label = "heal if nobody needs a rez",
              get = function() return db().rezHeal ~= false end,
              set = function(_, on) NS.SetRezHeal(on) end },
            { key = "rezDrink", kind = "toggle", label = "drink if a cast is too dear",
              get = function() return db().rezDrink ~= false end,
              set = function(_, on) NS.SetRezDrink(on) end },
            { key = "rezDrinkLow", kind = "toggle", label = "drink when my mana is low",
              get = function() return db().rezDrinkLow and true or false end,
              set = function(_, on) NS.SetRezDrinkLow(on) end },
            { key = "rezDrinkAt", kind = "step", label = "low means under", min = 20, max = 95, step = 5,
              get = function() return db().rezDrinkAt or 75 end,
              set = function(_, v) NS.SetNumber("drinkat", v) end,
              show = function() return pct(db().rezDrinkAt or 75) end },
            { key = "rezKeepScores", kind = "toggle", label = "keep the scoreboard",
              get = function() return db().rezKeepScores and true or false end,
              set = function(_, on) NS.SetRezKeepScores(on) end },
            -- "Show all ranks" in the spellbook first, or only the top rank of
            -- each heal is found and the button cannot downrank to save mana
            { key = "rezRescan", kind = "button", label = "heals (tick show all ranks)", button = "rebuild",
              action = function() NS.RebuildHeals() end },
        } },

        { title = "alerts", options = {
            { key = "sound", kind = "toggle", label = "play sounds",
              get = function() return db().sound ~= false end,
              set = function(_, on) NS.SetSound(on) end },
            { key = "chatAlert", kind = "toggle", label = "say it in chat too",
              get = function() return db().chatAlert ~= false end,
              set = function(_, on) NS.SetChatAlert(on) end },
            -- a stepper, not a grid: it plays the pack as you land on it, so
            -- you can walk the whole list without leaving the row
            { key = "voice", kind = "step", label = "voice pack", min = 1, max = #voices, step = 1,
              get = function() return Config:VoiceIndex(voices) end,
              set = function(_, v) NS.SetVoice(voices[v] or "auto"); NS.Sound:Play("someoneAsked") end,
              show = function() return string.sub(voices[Config:VoiceIndex(voices)] or "auto", 1, 9) end },
            { key = "voiceTest", kind = "button", label = "hear the alert", button = "test",
              action = function() NS.Sound:Play("someoneAsked") end },   -- Test() prints; the prompt says it here
        } },

        { title = "calls", options = {
            { key = "expire", kind = "step", label = "give up after", min = 10, max = 300, step = 5,
              get = function() return db().expire end,
              set = function(_, v) NS.SetNumber("expire", v) end,
              show = function() return db().expire .. " s" end },
            { key = "cancelMana", kind = "step", label = "cancel once back above", min = 30, max = 100, step = 5,
              get = function() return db().cancelMana end,
              set = function(_, v) NS.SetNumber("cancelmana", v) end,
              show = function() return pct(db().cancelMana) end },
            { key = "urgentAt", kind = "step", label = "nag me under", min = 1, max = 90, step = 5,
              get = function() return db().urgentAt end,
              set = function(_, v) NS.SetNumber("urgentat", v) end,
              show = function() return pct(db().urgentAt) end },
            { key = "claimHold", kind = "step", label = "a druid's click locks for", min = 3, max = 30, step = 1,
              get = function() return db().claimHold end,
              set = function(_, v) NS.SetNumber("claimhold", v) end,
              show = function() return db().claimHold .. " s" end },
        } },
    }
end

function Config:Build()
    if self.frame then return self.frame end
    local f = T.Options("BiSInnervateOptions", BiSTheme.OPTIONS.W, "Options")
    if not f then return nil end
    self.frame = f
    f:Recenter(60)
    self.byKey = {}
    for _, section in ipairs(self:OptionSections()) do
        f:Section(section.title)
        for _, opt in ipairs(section.options) do
            f:Row(opt, NS.db)
            self.byKey[opt.key] = opt
        end
    end
    f:Fit()
    -- a mode tick lights H or M on the main window; keep the two agreeing
    f.onChange = function() if NS.Window then NS.Window:Refresh() end end
    return f
end

function Config:Toggle(want)
    local f = self:Build()
    if f then f:Toggle(want) end
end

function Config:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- Repaint an open window so it agrees with a slash command that ran while it
--- was open. Alpha and text only: safe in a fight.
function Config:Refresh()
    if self.frame and self.frame:IsShown() then self.frame:Paint() end
end

-- the same rows by key, for the tests and for anyone scripting it: each goes
-- through the row's own setter, never the saved variable
function Config:Get(key)
    self:Build()
    local opt = self.byKey and self.byKey[key]
    if not opt or not opt.get then return nil end
    local v = opt.get(NS.db)
    if opt.kind == "seg" and key == "portraits3d" then return v == "3D" end
    return v
end

function Config:Set(key, v)
    self:Build()
    local opt = self.byKey and self.byKey[key]
    if not opt or not opt.set then return false end
    if opt.kind == "seg" and key == "portraits3d" then v = v and "3D" or "flat" end
    if opt.kind == "step" then
        v = tonumber(v) or opt.min
        if v < opt.min then v = opt.min elseif v > opt.max then v = opt.max end
    end
    opt.set(NS.db, v)
    self:Refresh()
    return true
end

function Config:Run(key)
    self:Build()
    local opt = self.byKey and self.byKey[key]
    if not opt or not opt.action then return false end
    opt.action(NS.db)
    return true
end
