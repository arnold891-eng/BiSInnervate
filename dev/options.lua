-- The shared options kit, on its own. Run from the addon root:
--     lua5.1 dev/options.lua
--
-- This tests Libs/BiSTheme/Options.lua itself - the window, the four control
-- kinds, the budgets - rather than any one addon's option list. Every adopter
-- copies the same file, so a break here breaks all of them at once.
local HERE = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
-- Nebbinator's harness, verbatim, as dev/kit.lua: Innervate's own harness.lua is a
-- different beast (a whole raid of clients), and this file tests the kit alone
local H = dofile(HERE .. "/kit.lua")
local ROOT = os.getenv("OPT") or (HERE .. "/..")

H.Load(ROOT, { "Libs/BiSTheme/Console.lua", "Libs/BiSTheme/Options.lua" })
local T = _G.BiSTheme
local O = T.OPTIONS

H.section("the kit loads clean")
H.eq(#H.leaked, 0, "no accidental globals", table.concat(H.leaked, ", "))
H.eq(T.OPTIONS_MINOR, 2, "minor 2")
H.ok(type(T.Options) == "function", "T.Options is the entry point")

-- a db and an option list that exercises all four kinds
local db = { minimap = true, sound = "first", cooldown = 10, resets = 0, nag = false }
local LONG = "nag me whenever anybody at all whispers about joining the guild"
local said = {}
local function tone(v) return v end

local OPTS = {
    { kind = "toggle", label = "minimap button",
      get = function(d) return d.minimap end,
      set = function(d, on) d.minimap = on and true or false end },
    { kind = "seg", label = "find sound", values = { "first", "always", "off" },
      get = function(d) return d.sound end,
      set = function(d, v) d.sound = v end },
    -- NOTE: this setter deliberately does NOT clamp. The stepper must.
    { kind = "step", label = "send cooldown", min = 5, max = 30, step = 5,
      get = function(d) return d.cooldown end,
      set = function(d, v) d.cooldown = v end,
      show = function(d) return d.cooldown .. " s" end },
    { kind = "button", label = "reset window position", button = "reset",
      action = function(d) d.resets = d.resets + 1 end },
    -- Deliberately far too long. Real labels are plain words a raider knows,
    -- under ~24 characters - but the budget only proves itself against a label
    -- that strains it, and a budget assert nothing strains is not an assert.
    { kind = "toggle", label = LONG,
      get = function(d) return d.nag end,
      set = function(d, on) d.nag = on and true or false end },
}

H.section("four control kinds, and no more")
local kinds = 0
for _ in pairs(T.OptionKinds) do kinds = kinds + 1 end
H.eq(kinds, 4, "exactly four kinds")
for _, k in ipairs({ "toggle", "seg", "step", "button" }) do
    H.ok(T.OptionKinds[k] ~= nil, k .. " is one of them")
end

H.section("the window")
local sectionOn = true
local f = T.Options("TestOptions", O.W, "Options")
H.ok(not f:IsShown(), "a new window is hidden; the toggle decides")
f:Section("nebbinator")
for _, opt in ipairs(OPTS) do f:Row(opt, db) end
f:Section("farm", { get = function() return sectionOn end,
                    set = function(on) sectionOn = on end })
f:Fit()

H.eq(#f.rows, 7, "one row per section header and per option")
H.eq(f:GetHeight(), O.HEADER + #f.rows * O.ROW + O.PAD,
     "height is header + rows + pad", f:GetHeight())
H.eq(f:GetWidth(), O.W, "and it stays narrow")

H.section("budgets")
-- the prompt gets the header minus the x's strip
H.ok(f.con ~= nil, "the header is a BiSTheme prompt")
H.ok(f.con:Width() <= O.W - 15 - 8, "the prompt fits its budget",
     f.con:Width() .. " of " .. (O.W - 15 - 8))
for _, r in ipairs(f.rows) do
    local budget = r.isSection and (O.W - 6 - O.CTL) or (O.W - O.INDENT - O.CTL)
    H.ok(r.name:GetStringWidth() <= budget,
         "label fits: " .. tostring(r.name:GetText()),
         math.floor(r.name:GetStringWidth()) .. " of " .. budget)
end
-- a label that fits outright must not have been trimmed: the ellipsis is the
-- net, not the plan
for _, r in ipairs(f.rows) do
    if not (r.opt and r.opt.label == LONG) then
        H.ok(not tostring(r.name:GetText()):find("%.%.%.$"),
             "label was not trimmed: " .. tostring(r.name:GetText()))
    end
end
-- and the net really is a net: the over-long one got cut down to the budget
do
    local long
    for _, r in ipairs(f.rows) do if r.opt and r.opt.label == LONG then long = r end end
    H.ok(long ~= nil, "the over-long label has a row")
    H.ok(tostring(long.name:GetText()):find("%.%.%.$"), "it was trimmed",
         tostring(long.name:GetText()))
    H.ok(long.name:GetStringWidth() <= O.W - O.INDENT - O.CTL,
         "and trimmed to the budget, not merely trimmed",
         math.floor(long.name:GetStringWidth()) .. " of " .. (O.W - O.INDENT - O.CTL))
end
-- every seg label whole
for _, r in ipairs(f.rows) do
    if r.opt and r.opt.kind == "seg" then
        for i, s in ipairs(r.ctl) do
            H.eq(s.label:GetText(), r.opt.values[i], "seg label whole: " .. r.opt.values[i])
        end
    end
end

H.section("the header holds one button and nothing else")
local heads = 0
for _, fr in ipairs(H.frames) do if fr:GetParent() == f.head then heads = heads + 1 end end
H.eq(heads, 1, "one frame in the header: the close button")

H.section("each kind round-trips into the db and repaints")
local function rowFor(label)
    for _, r in ipairs(f.rows) do if r.opt and r.opt.label == label then return r end end
end

-- toggle
local tog = rowFor("minimap button")
H.ok(tog.ctl.on == true, "the box starts painted on")
tog.ctl:Click()
H.eq(db.minimap, false, "clicking it writes the db")
H.ok(tog.ctl.on == false, "and the box repainted itself")
tog.ctl:Click()
H.eq(db.minimap, true, "and back")

-- seg
local seg = rowFor("find sound")
seg.ctl[2]:Click()
H.eq(db.sound, "always", "clicking a seg writes the db")
H.eq(seg.ctl[2].edge.name, "accent", "the live seg is accent-edged", tostring(seg.ctl[2].edge.name))
H.eq(seg.ctl[1].edge.name, "edge", "and the others are not")
-- hovering a dead seg and leaving must not steal the live one's edge
seg.ctl[1]:Fire("OnEnter")
seg.ctl[1]:Fire("OnLeave")
H.eq(seg.ctl[2].edge.name, "accent", "the live seg survives a hover next door")

-- step: THE STEPPER CLAMPS, not the setter
local step = rowFor("send cooldown")
step.ctl.plus:Click()
H.eq(db.cooldown, 15, "> steps up")
step.ctl.minus:Click()
H.eq(db.cooldown, 10, "< steps down")
for _ = 1, 20 do step.ctl.plus:Click() end
H.eq(db.cooldown, 30, "the stepper clamps at max even though the setter does not")
for _ = 1, 20 do step.ctl.minus:Click() end
H.eq(db.cooldown, 5, "and at min")
H.ok(step.ctl.val:GetStringWidth() <= O.STEP_V, "the value fits between < and >")

-- button
local btn = rowFor("reset window position")
btn.ctl:Click()
H.eq(db.resets, 1, "a button fires its action")

-- section box
local sec = f.rows[7]
H.ok(sec.isSection, "the last row is a section")
H.ok(sec.ctl.on == true, "its box starts on")
sec.ctl:Click()
H.eq(sectionOn, false, "the section box switches the thing off")
H.ok(sec.ctl.on == false, "and repaints")
sec.ctl:Click()

H.section("onChange fires for anything else that cares")
local rang = 0
f.onChange = function() rang = rang + 1 end
sec.ctl:Click()
H.eq(rang, 1, "a section box rings onChange")
sec.ctl:Click()

H.section("chat stays clean: it all goes to the prompt")
local before = H.chatCount
tog.ctl:Click() tog.ctl:Click()
seg.ctl[3]:Click()
step.ctl.plus:Click()
btn.ctl:Click()
sec.ctl:Click() sec.ctl:Click()
H.eq(H.chatCount, before, "not one line in the chat frame through a round of clicks")
H.ok(f.con:Width() <= O.W - 15 - 8, "and the prompt still fits after saying all that",
     f.con:Width())

H.section("an unknown kind is a crash, not a blank row")
local ok = pcall(function()
    f:Row({ kind = "slider", label = "nope" }, db)
end)
H.ok(not ok, "a fifth kind is refused outright")

H.section("Escape closes it (minor 2)")
local listed = 0
for _, n in ipairs(UISpecialFrames) do if n == "TestOptions" then listed = listed + 1 end end
H.eq(listed, 1, "the window is in UISpecialFrames once, by its name")
local f2 = T.Options("TestOptions", O.W, "Options")
listed = 0
for _, n in ipairs(UISpecialFrames) do if n == "TestOptions" then listed = listed + 1 end end
H.eq(listed, 1, "building it again does not list it twice")

H.section("toggle and recenter")
f:Toggle()
H.ok(f:IsShown(), "toggle shows it")
f:Toggle()
H.ok(not f:IsShown(), "and hides it")
f:Recenter()
local p = f:GetPoints()[1]
H.eq(p.point, "CENTER", "recenter puts it back in the middle")

H.report()
