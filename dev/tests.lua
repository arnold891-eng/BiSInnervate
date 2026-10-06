-- BiS Innervate 3.0 :: regression suite   (run: lua5.1 dev/tests.lua  from the addon folder)

package.path = "./dev/?.lua;" .. package.path
-- dev/theme.lua runs this file a second time with a hook on the harness: use
-- its instance when there is one
local H = _G.BIS_HARNESS or dofile("./dev/harness.lua")

local pass, fail = 0, 0
local function ok(cond, label, extra)
    if cond then
        pass = pass + 1
        print(string.format("  \27[32mPASS\27[0m %s", label))
    else
        fail = fail + 1
        print(string.format("  \27[31mFAIL\27[0m %s %s", label, extra and ("- " .. tostring(extra)) or ""))
    end
end
local function section(t) print("\n" .. t) end

--------------------------------------------------------------------
-- spec row: { name, class, hasAddon, mana, group, kind }
local function raid(spec, dbFor)
    local w = H.NewWorld(".")
    for _, p in ipairs(spec) do
        w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6])
        if p[4] then w.mana[p[1]] = p[4] end
    end
    -- everyone here chose their mode already; section 53 covers the default
    for _, n in ipairs(w.order) do local c = w.clients[n]; if c.env then c.env.BiSInnervateDB = { modeSet = true, dbVersion = 4 } end end
    if dbFor then
        for who, db in pairs(dbFor) do w.clients[who].env.BiSInnervateDB = db end
    end
    w:Login()
    w:Advance(4)   -- HELLO exchange
    return w
end

local BASE = {
    { "Kumlust", "MAGE",   true, 12, 1 },
    { "Healer3",   "DRUID",  true, 90, 1 },
    { "Healer4",  "DRUID",  true, 85, 2 },
    { "Tank1", "WARRIOR", true, nil, 1 },
    { "Healer1", "PRIEST", true, 60, 2 },
    { "Healer2",  "SHAMAN", true, 70, 1, "TIDE" },
    { "Dps6", "SHAMAN", true, 50, 2 },          -- no talent
}

local function face(c, name) return c.NS.Window.byName[name] end
local function pulsing(b) return b and b.anim and b.anim:IsPlaying() end
local function slash(c, s) c.env.SlashCmdList["BISINNERVATE"](s) end
local function click(b, button)
    local fn = b:GetScript("PostClick") or b:GetScript("OnClick")
    fn(b, button or "LeftButton")
end
local function callFor(c, name) return c.NS.Calls:For(name, "INNERVATE") end

--------------------------------------------------------------------
section("1. everybody gets the same window")
do
    local w = raid(BASE)
    local missing = {}
    for _, n in ipairs(w.order) do
        local c = w.clients[n]
        if not (c.NS.Window.frame and c.NS.Window.tide and c.NS.Window.inn) then missing[#missing + 1] = n end
    end
    ok(#missing == 0, "one window, two buttons, on every client", table.concat(missing, ","))

    local d = w.clients.Healer3
    local names = {}
    for name in pairs(d.NS.Window.byName) do names[#names + 1] = name end
    table.sort(names)
    ok(table.concat(names, ",") == "Dps6,Healer1,Healer2,Kumlust",
       "the grid is the mages and healers with the addon", table.concat(names, ","))
    ok(face(d, "Tank1") == nil, "the warrior is not on it")
    ok(face(d, "Healer3") == nil and face(d, "Healer4") == nil, "and neither are the druids - they have their own")

    local m = w.clients.Kumlust
    local mnames = {}
    for name in pairs(m.NS.Window.byName) do mnames[#mnames + 1] = name end
    ok(#mnames == #names, "and the mage sees exactly the same faces", #mnames)
end

section("2. only a druid's faces are live")
do
    local w = raid(BASE)
    local d, m = w.clients.Healer3, w.clients.Kumlust
    local df, mf = face(d, "Kumlust"), face(m, "Kumlust")
    ok(df._attrs["*spell1"] == "Innervate" and df._attrs["*type1"] == "spell", "a druid's face casts Innervate")
    ok(d.resolve(df._attrs.unit) == "Kumlust", "bound to the right player", tostring(df._attrs.unit))
    ok(df._attrs.unit == "Kumlust", "by NAME, not by raid slot", tostring(df._attrs.unit))
    ok(df._mouse == true, "and takes clicks")
    ok(mf._attrs["*type1"] == nil and mf._attrs["*spell1"] == nil, "a mage's face carries no spell")
    ok(mf._mouse == false, "and takes no clicks")
    ok(mf.hover._mouse == true, "but still gives a tooltip")
end

section("3. the two buttons grey out for the right reasons")
do
    local w = raid(BASE)
    local m, h, t, sh, en = w.clients.Kumlust, w.clients.Healer1, w.clients.Tank1, w.clients.Healer2, w.clients.Dps6
    ok(m.NS.Calls:CanAsk("INNERVATE"), "a mage may ask for innervate (druids in the raid)")
    ok(m.NS.Calls:CanAsk("TIDE"), "and for tide - the talented shaman is in group 1")
    local okT, why = h.NS.Calls:CanAsk("TIDE")
    ok(not okT, "the priest in group 2 cannot ask for tide", why)
    ok(h.NS.Calls:CanAsk("INNERVATE"), "but can ask for innervate")
    local okW, whyW = t.NS.Calls:CanAsk("INNERVATE")
    ok(not okW, "the warrior can ask for nothing", whyW)
    local okS, whyS = sh.NS.Calls:CanAsk("TIDE")
    ok(not okS, "the tide shaman does not ask for tide - they drop it", whyS)
    ok(sh.NS.Calls:CanAsk("INNERVATE"), "but may ask for innervate")
    ok(en.NS.Calls:CanAsk("INNERVATE"), "the untalented shaman may ask for innervate")
    local okE = en.NS.Calls:CanAsk("TIDE")
    ok(not okE, "and not for tide (no talented shaman in group 2)")

    -- a druid WITHOUT the addon does not light the button
    local w2 = raid({ { "Kumlust", "MAGE", true, 12 }, { "Silent", "DRUID", false, 90 } })
    local okN, whyN = w2.clients.Kumlust.NS.Calls:CanAsk("INNERVATE")
    ok(not okN, "no druid with the addon = innervate greyed", whyN)
end

section("4. a call pulses on every screen")
do
    local w = raid(BASE)
    local m = w.clients.Kumlust
    slash(m, "")            -- /inn
    w:Advance(1)
    local seen = 0
    for _, n in ipairs(w.order) do
        if callFor(w.clients[n], "Kumlust") then seen = seen + 1 end
    end
    ok(seen == #w.order, "every client has the call", seen)
    ok(pulsing(face(w.clients.Healer3, "Kumlust")), "the mage's face pulses on the druid's screen")
    ok(pulsing(face(w.clients.Healer4, "Kumlust")), "and on the other druid's")
    ok(pulsing(face(w.clients.Healer1, "Kumlust")), "and on the priest's, so everyone can see who asked")
    ok(not pulsing(face(w.clients.Healer3, "Healer1")), "nobody else pulses")
    ok(#w.clients.Healer3.sounds > 0, "a druid heard it")
    ok(#w.clients.Healer1.sounds == 0, "a priest did not")
end

section("5. the first click locks everyone else out")
do
    local w = raid(BASE)
    local m, a, b = w.clients.Kumlust, w.clients.Healer3, w.clients.Healer4
    slash(m, "")
    w:Advance(1)

    click(face(a, "Kumlust"))          -- Healer3 clicks; the secure cast is on its way
    w:Advance(0.5)
    local ca, cb = callFor(a, "Kumlust"), callFor(b, "Kumlust")
    ok(ca.claimedBy == "Healer3", "Healer3 holds the claim on his own screen")
    ok(cb.claimedBy == "Healer3", "and on Healer4's")
    ok(b.NS.Calls:IsLocked(cb), "Healer4 is locked out")
    ok(not pulsing(face(b, "Kumlust")), "the face stopped pulsing for Healer4")
    ok(face(b, "Kumlust").lock:IsShown(), "and is greyed")
    ok(not pulsing(face(a, "Kumlust")) and not face(a, "Kumlust").lock:IsShown(),
       "for Healer3 it is solid - his")
    ok(b.NS.Calls:Claim(cb) == false, "Healer4's own claim is refused")
    ok(callFor(m, "Kumlust").claimedBy == "Healer3", "the mage sees who is coming")
    ok(m.NS.Window.inn.sub:GetText() == "Healer3 is on it", "and the button says so",
       m.NS.Window.inn.sub:GetText())
end

section("6. the cast is what closes it")
do
    local w = raid(BASE)
    local m, a, b = w.clients.Kumlust, w.clients.Healer3, w.clients.Healer4
    slash(m, "")
    w:Advance(1)
    click(face(a, "Kumlust"))
    w:CastInnervate("Healer3", "Kumlust")
    w:Advance(1)
    ok(callFor(a, "Kumlust") == nil, "done on the druid's screen")
    ok(callFor(b, "Kumlust") == nil, "done on the other druid's")
    ok(callFor(m, "Kumlust") == nil, "done on the mage's")
    ok(not pulsing(face(b, "Kumlust")) and not face(b, "Kumlust").lock:IsShown(),
       "the face is back to idle")
    ok(w.clients.Healer3.NS.Tracker:CooldownLeft("Healer3", "INNERVATE") > 300, "and Healer3 is on cooldown")
end

section("7. a claim that never lands goes back to everyone")
do
    local w = raid(BASE)
    local m, a, b = w.clients.Kumlust, w.clients.Healer3, w.clients.Healer4
    slash(m, "")
    w:Advance(1)
    click(face(a, "Kumlust"))
    w:Advance(2)
    ok(b.NS.Calls:IsLocked(callFor(b, "Kumlust")), "locked right after the click")
    w:Advance(8)                        -- claimHold is 8
    ok(not b.NS.Calls:IsLocked(callFor(b, "Kumlust")), "unlocked once the hold ran out")
    ok(pulsing(face(b, "Kumlust")), "and pulsing again for the other druid")
    ok(b.NS.Calls:Claim(callFor(b, "Kumlust")) == true, "who may now take it")
end

section("8. cancelling")
do
    local w = raid(BASE)
    local m = w.clients.Kumlust
    slash(m, "")
    w:Advance(1)
    click(m.NS.Window.inn, "RightButton")   -- insecure button: OnClick
    w:Advance(1)
    ok(callFor(w.clients.Healer3, "Kumlust") == nil, "right-click on the button withdraws it everywhere")

    -- asked at 85%: a deliberate call is not killed a tick later
    w.mana.Kumlust = 85
    slash(m, "")
    w:Advance(3)
    ok(callFor(m, "Kumlust") ~= nil, "a call made at 85% survives")
    w.mana.Kumlust = 100
    w:Advance(2)
    ok(callFor(m, "Kumlust") == nil, "but a real recovery closes it")

    -- and a call from 12% closes once they are topped up
    w.mana.Kumlust = 12
    slash(m, "")
    w:Advance(1)
    w.mana.Kumlust = 75
    w:Advance(2)
    ok(callFor(w.clients.Healer4, "Kumlust") == nil, "a low call closes once they are back up")

    -- expiry
    w.mana.Kumlust = 12
    slash(m, "")
    w:Advance(45)
    ok(callFor(w.clients.Healer4, "Kumlust") == nil, "and an ignored call expires")
end

section("9. mana tide: group-scoped, the shaman drops it")
do
    local w = raid(BASE)
    local m, sh, en = w.clients.Kumlust, w.clients.Healer2, w.clients.Dps6
    slash(m, "tide")
    w:Advance(1)
    ok(sh.NS.Calls:TideForGroup(1) ~= nil, "the shaman's client has the group's call")
    ok(pulsing(sh.NS.Window.tide) or sh.NS.Window.tide.glow:IsShown(), "and their totem button lights")
    ok(sh.NS.Window.tide._attrs["*spell1"] == "Mana Tide Totem", "which really casts the totem")
    ok(not en.NS.Window.tide.glow:IsShown(), "the untalented shaman's does not light")

    -- the shaman clicks: the secure cast fires, PostClick claims for the group
    -- a second asker in the same group does not make a second call
    local w2ok, why = w.clients.Healer3.NS.Calls:CanAsk("TIDE")
    ok(not w2ok and why == "your group already asked", "one call per group", why)

    click(sh.NS.Window.tide)
    w:Advance(0.5)
    ok(sh.NS.Calls:TideForGroup(1).claimedBy == "Healer2", "the group's call is claimed")
    w:CastTide("Healer2")
    w:Advance(1)
    ok(sh.NS.Calls:TideForGroup(1) == nil, "the totem landing closes the call")
    ok(m.NS.Calls:Mine("TIDE") == nil, "on the mage too")

    -- and now the shaman is on cooldown: the mage's button says so instead of
    -- looking like another one could be asked for
    local okCd, whyCd, left = m.NS.Calls:CanAsk("TIDE")
    ok(not okCd and string.find(whyCd, "back in", 1, true) and left > 200, "asking again is refused with the timer", whyCd)
    m.NS.Window:DoRefresh()
    ok(m.NS.Window.tide.icon:GetAlpha() < 1, "and the mage's tide icon is greyed")
    ok(string.find(m.NS.Window.tide.right:GetText() or "", "m", 1, true) ~= nil, "with the minutes in the corner",
       m.NS.Window.tide.right:GetText())
end

section("10. combat: nothing protected is touched")
do
    local w = raid(BASE)
    local m, a, b = w.clients.Kumlust, w.clients.Healer3, w.clients.Healer4
    w:SetCombat(true)
    local okRun, err = pcall(function()
        slash(m, "")
        w:Advance(1)
        click(face(a, "Kumlust"))
        w:Advance(1)
        w:CastInnervate("Healer3", "Kumlust")
        slash(w.clients.Healer1, "")
        w:Advance(1)
        click(face(b, "Healer1"))
        w:Advance(1)
    end)
    ok(okRun, "ask, claim, cast, ask, claim - all mid-fight, no protected call", err)
    ok(callFor(a, "Kumlust") == nil, "the first landed")
    ok(callFor(a, "Healer1").claimedBy == "Healer4", "the second is Healer4's")

    -- the window must not open, close, move or rescale in combat
    local shownBefore = a.NS.Window.frame._shown
    slash(a, "hide")
    ok(a.NS.Window.frame._shown == shownBefore and not a.NS.db.hidden, "closing is refused mid-fight")
    slash(a, "scale 0.7")
    ok(a.NS.Window.frame:GetScale() == 1 and a.NS.Window.scalePending, "a rescale waits")
    w:SetCombat(false)
    w:Advance(1)
    ok(a.NS.Window.frame:GetScale() == 0.7, "and lands when the fight ends")
end

section("11. a raid slot renumbering mid-fight cannot re-aim a face")
do
    local w = raid({
        { "Kumlust", "MAGE",  true, 12 },
        { "Healer3",   "DRUID", true, 90 },
        { "Tank1", "WARRIOR", true },
        { "Healer1", "PRIEST", true, 9 },
        { "Tank3",  "WARRIOR", true },
    })
    local a = w.clients.Healer3
    local f = face(a, "Healer1")
    w:SetCombat(true)
    slash(w.clients.Healer1, "")
    w:Advance(1)
    w:RemovePlayer("Tank1")        -- Healer1 moves from raid4 to raid3, Tank3 takes raid4
    w:Advance(1)
    ok(a.resolve(f._attrs.unit) == "Healer1", "still aimed at Healer1", tostring(f._attrs.unit))
    a.NS.Window:DoRefresh()
    ok(a.resolve(f.punit) == "Healer1", "and the mana bar follows the same person", tostring(a.resolve(f.punit)))
    ok(pulsing(f), "and it is still the one pulsing")
    w:SetCombat(false)
end

section("12. the wire is defended")
do
    local w = raid(BASE)
    local m, a = w.clients.Kumlust, w.clients.Healer3
    slash(m, "")
    w:Advance(1)
    local id = callFor(a, "Kumlust").id

    w:Deliver("Rogueman", "Healer3", "4|CANCEL|" .. id .. "|lol")
    ok(callFor(a, "Kumlust") ~= nil, "a stranger outside the group is ignored")
    w:Deliver("Tank1", "Healer3", "4|CANCEL|" .. id .. "|lol")
    ok(callFor(a, "Kumlust") ~= nil, "a raid member who is not the caller cannot cancel it")
    w:Deliver("Tank1", "Healer3", "4|CLAIM|" .. id .. "|Healer4")
    ok(callFor(a, "Kumlust").claimedBy == nil, "nobody can claim on somebody else's behalf")
    w:Deliver("Healer1", "Healer3", "4|ASK|fake-1|INNERVATE|Kumlust|MAGE|5|1")
    ok(callFor(a, "Kumlust").id == id, "you may only call for yourself")
    w:Deliver("Healer4", "Healer3", "2|REQ|old-1|Healer4|Kumlust|MAGE|5|INNERVATE")
    local n = 0
    for _ in pairs(a.NS.Calls.list) do n = n + 1 end
    ok(n == 1, "a 2.x message is not parsed as a 3.0 one", n)
end

section("13. the demo")
do
    local w = raid({ { "Kumlust", "MAGE", true, 12 } })      -- a mage, solo
    local c = w.clients.Kumlust
    slash(c, "demo")
    w:Advance(1)
    ok(c.NS.demoMode == true, "demo is on")
    ok(face(c, "Dps4") ~= nil, "fake faces are on the grid")
    ok(face(c, "Dps4")._attrs["*type1"] == "macro" and face(c, "Dps4")._attrs["*macrotext1"] == "",
       "wired to a do-nothing macro")
    ok(pulsing(face(c, "Dps4")), "the caller pulses")
    ok(face(c, "Dps9").lock:IsShown(), "the one another druid took is greyed")
    ok(not pulsing(face(c, "Sparkle")), "the one not asking is quiet")
    ok(c.NS.Window.frame:GetAlpha() == 1, "visible while solo")
    local okClick = pcall(function() click(face(c, "Dps4")) end)
    ok(okClick, "a click prints instead of casting")

    w:SetCombat(true)
    slash(c, "demo")
    ok(c.NS.demoMode == true, "stopping mid-fight waits")
    w:SetCombat(false)
    w:Advance(1)
    ok(not c.NS.demoMode, "and stops when it ends")
    ok(face(c, "Dps4") == nil, "fake faces are gone")
    local n = 0
    for _, call in pairs(c.NS.Calls.list) do if call.demo then n = n + 1 end end
    ok(n == 0, "and so are the fake calls")
end

section("14. the options window: the shared kit, every set through its owner")
do
    local w = raid(BASE)
    local c = w.clients.Healer3
    local C, db = c.NS.Config, c.env.BiSInnervateDB
    local okB, err = pcall(function() C:Build() end)
    ok(okB, "it builds", err)
    ok(c.env.BiSTheme and c.env.BiSTheme.OPTIONS_MINOR == 2, "on Libs/BiSTheme/Options.lua minor 2, loaded the TOC way")
    local f = C.frame
    ok(not f:IsShown(), "hidden until asked")
    slash(c, "config")
    ok(f:IsShown(), "/inn config opens it")
    slash(c, "config")
    ok(not f:IsShown(), "and closes it")
    click(c.NS.Window.cfgBtn)
    ok(f:IsShown(), "the cfg tab opens it")
    click(f.closeBtn)
    ok(not f:IsShown(), "x closes it")
    local esc = false
    for _, n in ipairs(c.env.UISpecialFrames) do if n == "BiSInnervateOptions" then esc = true end end
    ok(esc, "and it is in UISpecialFrames, so Escape closes it")
    -- the shape: one narrow flat window, sections then rows, no tabs
    local O = c.env.BiSTheme.OPTIONS
    local sections, rows = 0, 0
    for _, r in ipairs(f.rows) do if r.isSection then sections = sections + 1 else rows = rows + 1 end end
    ok(sections == 5 and rows == 24, "five sections, twenty-four options", sections, rows)
    ok(f:GetWidth() == O.W and f:GetHeight() == O.HEADER + #f.rows * O.ROW + O.PAD, "230 wide, sized to its rows", f:GetHeight())
    ok(f.rows[1].isSection and f.rows[1].name:GetText():find("innervate", 1, true), "the addon's own section comes first")
    -- every label fits its budget untrimmed: the ellipsis is the net, not the plan
    local wide = {}
    for _, r in ipairs(f.rows) do
        local budget = r.isSection and (O.W - 6 - O.CTL) or (O.W - O.INDENT - O.CTL)
        if r.name:GetStringWidth() > budget or tostring(r.name:GetText()):find("%.%.%.$") then wide[#wide + 1] = tostring(r.name:GetText()) end
    end
    ok(#wide == 0, "every label fits the kit's budget, none trimmed", table.concat(wide, " | "))
    -- the settings, through the same owners the slash commands use
    C:Set("scale", 5)
    ok(db.scale == 2, "scale clamps at 2", db.scale)
    ok(c.NS.Window.frame:GetScale() == 2, "and the window actually resized")
    C:Set("scale", 1)
    C:Set("voice", #C:VoiceList())
    ok(db.voice == "off" and c.NS.Sound:ActivePack() == nil, "the voice stepper's last stop is off", db.voice)
    w:Advance(1)                 -- the same cue inside 0.2 s is one cue
    local heard = #c.sounds
    C:Set("voice", 1)
    ok(db.voice == "auto", "and its first is auto")
    ok(#c.sounds > heard, "landing on a pack plays it, so you hear what you picked", #c.sounds - heard)
    -- on a class that is not a druid too: the test cue is everyone's, not the druid's
    local m = w.clients.Kumlust
    m.NS.Config:Build()
    local heardM = #m.sounds
    m.NS.Config:Run("voiceTest")
    ok(#m.sounds > heardM, "the test button plays on a mage (someoneAsked was a druid-only cue)", #m.sounds - heardM)
    m.NS.Config:Run("voiceTest")
    ok(#m.sounds > heardM + 1, "and again straight away, no dedupe on a test", #m.sounds - heardM)
    m.NS.Config:Set("sound", false)
    local mute = #m.sounds
    m.NS.Config:Run("voiceTest")
    ok(#m.sounds == mute, "but not with sounds off")
    m.NS.Config:Set("sound", true)
    C:Set("claimHold", 1)
    ok(db.claimHold == 3, "claimHold clamps to 3", db.claimHold)
    C:Set("sound", false)
    ok(db.sound == false, "sound off")
    C:Set("sound", true)
    C:Set("locked", true)
    ok(db.locked == true, "lock")
    C:Set("locked", false)
    C:Set("portraits3d", true)
    ok(db.portraits3d == true and C:Get("portraits3d") == true, "faces 3D through the seg")
    C:Set("portraits3d", false)
    -- a side effect, not just the key: the minimap button really goes
    C:Set("minimap", false)
    ok(db.minimap == false and c.NS.Minimap.button and not c.NS.Minimap.button:IsShown(), "minimap off hides the button")
    C:Set("minimap", true)
    ok(c.NS.Minimap.button:IsShown(), "and on shows it")
    -- the slash and the row agree: /inn lock flips what the row reads
    slash(c, "lock")
    ok(C:Get("locked") == true, "/inn lock and the row read the same key")
    slash(c, "lock")
    -- who may call moved to a slash: seven classes are too many rows
    slash(c, "callers paladin")
    ok(c.NS.IsRequesterClass("PALADIN") == false, "/inn callers paladin switches a class off")
    slash(c, "callers paladin")
    ok(c.NS.IsRequesterClass("PALADIN") == true, "and back")
    ok(C.byKey.classPALADIN == nil, "and it is not a row")
    -- the BiS channel switch is the user's own, same as /biscomm
    C:Set("comm", false)
    ok(not c.env.LibBiSComm:Enabled(), "the channel toggle is the lib's switch")
    C:Set("comm", true)
    -- a real click on a row goes to the prompt, never to chat
    local before = #c.prints
    local row
    for _, r in ipairs(f.rows) do if r.opt and r.opt.key == "sound" then row = r end end
    click(row.ctl); click(row.ctl)
    ok(#c.prints == before, "a click says itself in the prompt, not in chat", #c.prints - before)
    ok(db.sound == true, "and round-trips")
    -- a fifth control kind is refused
    ok(not pcall(function() f:Row({ kind = "slider", label = "nope" }, db) end), "a fifth kind is refused outright")
    -- the About page is gone: the version lives on the minimap tooltip and /inn version
    slash(c, "version")
    ok((c.prints[#c.prints] or ""):find(c.NS.VERSION, 1, true) ~= nil, "/inn version prints the version", c.prints[#c.prints])
end

section("14b. every option clicked mid-fight: not one protected call")
do
    local w = raid(BASE)
    local c = w.clients.Healer1
    local C = c.NS.Config
    C:Build()
    w:SetCombat(true)
    local okOpen, err = pcall(function() C:Toggle(true) end)
    ok(okOpen and C.frame:IsShown(), "the window opens in combat (no secure children)", err)
    local errs, clicked = {}, 0
    for _, r in ipairs(C.frame.rows) do
        if r.opt then
            local ctls = {}
            if r.opt.kind == "seg" then for _, s in ipairs(r.ctl) do ctls[#ctls + 1] = s end
            elseif r.opt.kind == "step" then ctls[1], ctls[2] = r.ctl.plus, r.ctl.minus
            else ctls[1] = r.ctl end
            for _, b in ipairs(ctls) do
                local okC, e = pcall(function() click(b) end)
                clicked = clicked + 1
                if not okC then errs[#errs + 1] = r.opt.key .. ": " .. tostring(e) end
            end
            -- toggles and segs back to where they were, so one click's state
            -- does not hide the next one's fault
            if r.opt.kind == "toggle" then pcall(function() click(r.ctl) end) end
        end
    end
    ok(clicked >= 30, "every control got a click", clicked)
    ok(#errs == 0, "no LOCKDOWN VIOLATION from any of them", table.concat(errs, " | "))
    -- the deferred ones are pending, not done: the fight's end applies them
    ok(c.NS.Window.frame:GetScale() == 1, "the scale did not touch the protected frame mid-fight")
    w:SetCombat(false)
    w:Advance(1)
    ok(pcall(function() C:Refresh() end), "and a repaint after the fight is clean")
    slash(c, "reset")
end

section("15. a saved scale survives a reload in the same place")
do
    local w = raid(BASE)
    local c = w.clients.Healer3
    c.NS.Window.frame:SetPoint("CENTER", c.env.UIParent, "CENTER", 300, -120)
    slash(c, "scale 0.5")
    local _, _, _, x = c.NS.Window.frame:GetPoint()
    ok(x == 600, "offsets rescaled once", tostring(x))
    local saved = c.env.BiSInnervateDB
    for i = 1, 3 do
        local w2 = raid(BASE, { Healer3 = saved })
        local f2 = w2.clients.Healer3.NS.Window.frame
        local _, _, _, xi = f2:GetPoint()
        ok((xi or 0) * f2:GetScale() == 300, "reload " .. i .. " lands in the same pixel", tostring(xi))
        saved = w2.clients.Healer3.env.BiSInnervateDB
    end
end

section("16. upgrading from 2.x")
do
    local old = { dbVersion = 3, showAt = 90, small = true, sound = false, hidePanel = true,
                  gridHidden = true, roles = { Bob = { h = 1 } }, assignPos = { x = 1 }, whispers = true }
    local w = raid(BASE, { Healer3 = old })
    local db = w.clients.Healer3.env.BiSInnervateDB
    ok(db.dbVersion == 4, "schema is 4")
    ok(db.scale == 0.5, "half size carried over as scale 0.5", tostring(db.scale))
    ok(db.sound == false, "sound setting kept")
    ok(db.showAt == nil and db.roles == nil and db.assignPos == nil and db.whispers == nil,
       "the 2.x keys are gone")
    ok(not db.hidden, "and the window is shown (old close flags do not carry)")
end

section("18. a zone-in blip does not empty the grid")
do
    local w = raid(BASE)
    local d = w.clients.Healer3
    local before = 0
    for _ in pairs(d.NS.Window.byName) do before = before + 1 end
    ok(before == 4, "four faces before the zone", before)

    -- the group API reports nobody for a moment, then the roster is back
    w.blip = true
    w:FireAll("PLAYER_ENTERING_WORLD")
    w:FireAll("GROUP_ROSTER_UPDATE")
    w:Advance(1)
    w.blip = false
    w:FireAll("GROUP_ROSTER_UPDATE")
    w:Advance(0.5)

    -- immediately: the blip must never have been believed
    local after = 0
    for _ in pairs(d.NS.Window.byName) do after = after + 1 end
    ok(after == 4, "four faces the moment the roster is back - nothing was forgotten", after)

    ok(true, "(recovery of a wiped client is section 18b)")
    local users = 0
    for _ in pairs(d.NS.Comm.users) do users = users + 1 end
    ok(users == 6, "and everyone with the addon is still known", users)
    ok(d.NS.Calls:CanAsk("INNERVATE") or d.NS.Tracker:HasDruid(), "the innervate button is still lit")

    -- a real departure of everyone is still believed, eventually
    w.blip = true
    w:FireAll("GROUP_ROSTER_UPDATE")
    w:Advance(12)
    w:FireAll("GROUP_ROSTER_UPDATE")
    w:Advance(1)
    ok(not d.NS.Tracker:RosterBlip(), "ten seconds of nobody is not a blip any more")
    w.blip = false
end

section("18b. a client that forgot everyone gets it all back from one hello")
do
    -- a fresh raid, no roster events in flight: the ONLY way back is that the
    -- others answer a hello from somebody they already know
    local w = raid(BASE)
    local d = w.clients.Healer3
    d.NS.Comm.users = {}
    d.NS.Tracker:UpdateRoster(); d.NS.Window:Bind()
    local wiped = 0
    for _ in pairs(d.NS.Window.byName) do wiped = wiped + 1 end
    ok(wiped < 4, "a wiped client starts short", wiped)
    d.NS.Comm:Hello()
    w:Advance(8)
    local back = 0
    for _ in pairs(d.NS.Window.byName) do back = back + 1 end
    ok(back == 4, "and is whole again after one hello - mages included", back)
end

section("19. a face the client cannot aim by name stays unbound")
do
    local w = H.NewWorld(".")
    w.noNames = true                    -- a bare name is not a unit token here
    for _, p in ipairs(BASE) do w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6]); if p[4] then w.mana[p[1]] = p[4] end end
    w:Login(); w:Advance(4)
    local d = w.clients.Healer3
    local f = face(d, "Kumlust")
    ok(f ~= nil, "the face is on the grid")
    ok(f._attrs["*spell1"] == nil and f._attrs.unit == "none", "but carries no spell and no unit", tostring(f._attrs.unit))
    ok(f._mouse == false, "and takes no clicks - it cannot cast at the wrong person")
    ok(f.unbound == true, "and says so")
end

section("20. a hidden window stays deaf across a roster change")
do
    local w = raid(BASE)
    local m = w.clients.Kumlust
    slash(m, "hide")
    ok(face(m, "Healer1").hover._mouse == false, "hover frames off when closed")
    w:FireAll("GROUP_ROSTER_UPDATE")
    w:Advance(1)
    ok(face(m, "Healer1").hover._mouse == false, "and still off after a roster update")
    ok(m.NS.Window.inn._mouse == false, "buttons too")
    slash(m, "show")
    ok(face(m, "Healer1").hover._mouse == true and m.NS.Window.inn._mouse == true, "all back when shown")
end

section("21. a client that drops secure writes in combat: nothing is attempted")
do
    local w = raid(BASE)
    w.blockSecureWrites = true
    local m, a = w.clients.Kumlust, w.clients.Healer3
    w:SetCombat(true)
    local okRun, err = pcall(function()
        slash(m, ""); w:Advance(1)
        click(face(a, "Kumlust")); w:Advance(1)
        w:CastInnervate("Healer3", "Kumlust")
        slash(m, "tide"); w:Advance(1)
        click(w.clients.Healer2.NS.Window.tide); w:CastTide("Healer2")
        slash(a, "reset"); slash(a, "hide"); slash(a, "scale 0.8"); slash(a, "config")
        slash(m, "lust"); slash(m, "drums battle")
        w.clients.Healer1.NS.Window.buttons.DRUMS:GetScript("OnEnter")(w.clients.Healer1.NS.Window.buttons.DRUMS)
        w.clients.Healer1.NS.Window:HideFlyout()
        a.NS.Config:Set("sound", false); a.NS.Config:Set("scale", 1.2)
        w:Advance(3)
    end)
    ok(okRun, "the whole flow survives a write-blocking client", err)
    ok(face(a, "Kumlust")._attrs.unit == "Kumlust", "and no binding was touched")
    ok(a.NS.Window.resetPending == true, "reset waited for the fight to end")
    w:SetCombat(false)
    w:Advance(1)
    ok(not a.NS.Window.resetPending and a.NS.Window.inn._mouse == true, "and then happened")
end

section("22. a claim that arrives before its ask still locks")
do
    local w = raid(BASE)
    local m, a, b = w.clients.Kumlust, w.clients.Healer3, w.clients.Healer4
    slash(m, ""); w:Advance(1)
    local id = callFor(a, "Kumlust").id
    -- Healer4 never got the ASK
    b.NS.Calls.list[id] = nil
    w:Deliver("Healer3", "Healer4", "4|CLAIM|" .. id .. "|Healer3")
    ok(callFor(b, "Kumlust") == nil, "no call yet on Healer4")
    w:Deliver("Kumlust", "Healer4", "4|ASK|" .. id .. "|INNERVATE|Kumlust|MAGE|12|1")
    local c = callFor(b, "Kumlust")
    ok(c and c.claimedBy == "Healer3", "the ask lands already claimed", c and tostring(c.claimedBy))
    ok(b.NS.Calls:IsLocked(c), "and Healer4 is locked out")
end

section("23. a shaman gaining the talent gets a totem button")
do
    local w = raid(BASE)
    local en = w.clients.Dps6
    ok(en.NS.Window.tide._attrs["*spell1"] == nil, "no talent, no spell on the button")
    w.kinds.Dps6 = "TIDE"
    en.NS.ForgetSpellCache()
    w:Fire("Dps6", "PLAYER_TALENT_UPDATE")
    w:Advance(6)
    ok(en.NS.Window.tide._attrs["*spell1"] == "Mana Tide Totem", "after respeccing, the button casts it")
    ok(w.clients.Healer1.NS.Tracker:TideFor("Healer1") ~= nil, "and group 2 can now ask for tide")
    w.kinds.Dps6 = nil
    en.NS.ForgetSpellCache()
    w:Fire("Dps6", "PLAYER_TALENT_UPDATE")
    ok(en.NS.Window.tide._attrs["*spell1"] == nil, "and loses it again on respec")
end

section("24. the mana strip is a strip")
do
    local w = raid(BASE)
    local a = w.clients.Healer3
    a.NS.Window:DoRefresh()
    local full, low = face(a, "Healer2").mana, face(a, "Kumlust").mana
    ok(full._h == nil or full._h <= 3, "never taller than 3px")
    ok((full._w or 0) > (low._w or 0), "wider for more mana", tostring(full._w) .. " vs " .. tostring(low._w))
end

section("25. buttons are actions, not settings")
do
    local w = raid(BASE)
    local C = w.clients.Healer3.NS.Config
    C:Build()
    ok(C.byKey.reset and C.byKey.reset.kind == "button" and C.byKey.reset.action ~= nil, "reset is a button row with an action")
    ok(C:Set("reset", true) == false, "so Config:Set cannot fire it")
    ok(C:Run("reset") == true, "Config:Run does")
end

section("26. it stays small")
do
    local w = raid(BASE)
    local W = w.clients.Healer3.NS.Window
    ok(W.width <= 160, "narrow enough to live on a raid screen", W.width)
    ok(W.SIZE == 20, "faces are 20px", W.SIZE)
    ok(W.BODY_A <= 0.05 and W.HEAD_A == 0.5, "body all but transparent, title bar half")
    ok(not W.inn.title:IsShown() and not W.inn.sub:IsShown(), "no words on the buttons")
    ok(W.inn.sub:GetText() ~= nil, "but the tooltip still has them")
end

section("27. bloodlust: any shaman in your group, greyed while exhausted")
do
    local w = raid(BASE)
    local m, sh, en, h = w.clients.Kumlust, w.clients.Healer2, w.clients.Dps6, w.clients.Healer1
    ok(sh.NS.Provides("LUST") and en.NS.Provides("LUST"), "every shaman provides bloodlust")
    ok(sh.NS.Provides("TIDE") and not en.NS.Provides("TIDE"), "and only the talented one provides tide")
    ok(sh.NS.Window.lust._attrs["*spell1"] == "Bloodlust", "the shaman's lust button casts it",
       tostring(sh.NS.Window.lust._attrs["*spell1"]))
    ok(m.NS.Calls:CanAsk("LUST"), "the mage can ask")
    ok(h.NS.Calls:CanAsk("LUST"), "the priest in group 2 can ask too - bloodlust is raid-wide")
    ok(w.clients.Tank1.NS.Calls:CanAsk("LUST"), "and so can the warrior - lust is for everyone")

    slash(m, "lust"); w:Advance(1)
    ok(sh.NS.Calls:GroupCall("LUST", 1) ~= nil, "Healer2's client has the call")
    ok(sh.NS.Window.lust.glow:IsShown(), "and the button lights")
    ok(en.NS.Window.lust.glow:IsShown(), "Dps6 in group 2 lights too - any shaman may answer")
    local okTwo, whyTwo = h.NS.Calls:CanAsk("LUST")
    ok(not okTwo and whyTwo == "someone already asked", "one bloodlust call for the whole raid", whyTwo)
    click(sh.NS.Window.lust); w:Advance(0.5)
    ok(sh.NS.Calls:GroupCall("LUST", 1).claimedBy == "Healer2", "the click claims it")
    ok(en.NS.Calls:IsLocked(en.NS.Calls:GroupCall("LUST", 2)), "and Dps6 is locked out")
    ok(not en.NS.Window.lust.glow:IsShown(), "his button stops pulsing")
    w:CastLust("Healer2"); w:Advance(1)
    ok(m.NS.Calls:Mine("LUST") == nil, "the cast closes it")
    ok(en.NS.Calls:GroupCall("LUST", 2) == nil, "for everyone")

    -- exhausted: asking is pointless, and the button says so
    w.debuffs = { Kumlust = { [57723] = 185 } }        -- 3:05 of exhaustion left
    local okE, why, left, reason = m.NS.Calls:CanAsk("LUST")
    ok(not okE and string.find(why, "exhausted", 1, true), "an exhausted mage cannot ask", why)
    ok(reason == "debuff" and left and left > 180, "and the reason carries the time left", tostring(left))
    m.NS.Window:DoRefresh()
    ok(m.NS.Window.lust.icon._alpha and m.NS.Window.lust.icon._alpha < 1, "and their lust icon is greyed")
    ok(string.find(m.NS.Window.lust.right:GetText() or "", "4m", 1, true) ~= nil, "with the debuff's minutes in the corner",
       m.NS.Window.lust.right:GetText())
    w.debuffs = { Healer2 = { [57724] = true } }        -- sated shaman
    sh.NS.Window:DoRefresh()
    ok(sh.NS.Window.lust.icon._alpha and sh.NS.Window.lust.icon._alpha < 1, "a sated shaman's own button greys too")
    w.debuffs = nil
end

section("28. drums: whoever in your group carries them")
do
    local w = H.NewWorld(".")
    w.drums = { Kumlust = 29529 }                      -- the mage is the leatherworker
    for _, p in ipairs(BASE) do w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6]); if p[4] then w.mana[p[1]] = p[4] end end
    w:Login(); w:Advance(4)
    local m, sh, h = w.clients.Kumlust, w.clients.Healer2, w.clients.Healer1
    ok(m.NS.Provides("DRUMS"), "the mage with drums in the bag provides drums")
    ok(m.NS.Window.drums._attrs["*type1"] == "item" and m.NS.Window.drums._attrs["*item1"] == "item:29529",
       "their drums button uses the item", tostring(m.NS.Window.drums._attrs["*item1"]))
    ok(sh.NS.Calls:CanAsk("DRUMS"), "the shaman in group 1 can ask for drums")
    local okH, why = h.NS.Calls:CanAsk("DRUMS")
    ok(not okH, "the priest in group 2 cannot - nobody there has drums", why)

    slash(sh, "drums"); w:Advance(1)
    ok(m.NS.Window.drums.glow:IsShown(), "the drummer's button lights")
    click(m.NS.Window.drums); w:CastDrums("Kumlust"); w:Advance(1)
    ok(sh.NS.Calls:Mine("DRUMS") == nil, "the drum cast closes it")
    ok(m.NS.Tracker:CooldownLeft("Kumlust", "DRUMS") > 100, "and the drums are on cooldown")

    -- tinnitus greys it
    w.debuffs = { Healer2 = { [51120] = true } }
    local okT, whyT = sh.NS.Calls:CanAsk("DRUMS")
    ok(not okT and string.find(whyT, "tinnitus", 1, true), "tinnitus: cannot ask", whyT)
    w.debuffs = nil

    -- selling the drums takes the button away from everyone
    w.drums = {}
    w:Fire("Kumlust", "BAG_UPDATE"); w:Advance(3)
    ok(not m.NS.Provides("DRUMS"), "no drums, no provider")
    ok(m.NS.Window.drums._attrs["*type1"] == nil, "and the button is unwired")
    local okS = sh.NS.Calls:CanAsk("DRUMS")
    ok(not okS, "and the group can no longer ask")
end

section("29. five icons in a row")
do
    local w = raid(BASE)
    local W = w.clients.Healer3.NS.Window
    ok(W.buttons.TIDE and W.buttons.INNERVATE and W.buttons.LUST and W.buttons.DRUMS and W.buttons.REZ, "all five exist")
    ok(W.width >= W.PAD * 2 + 5 * W.BTN_H + 4 * W.GAP, "and fit across the window", W.width)
    local _, _, _, rx = W.buttons.REZ:GetPoint()
    ok(rx + W.BTN_H <= W.width - W.PAD, "the fifth does not hang out of the frame", rx)
end

section("30. a specific drum: the flyout, the wire, the right drummer")
do
    local w = H.NewWorld(".")
    w.drums = { Kumlust = 29529, Healer3 = 29531 }       -- mage: Battle. druid: Restoration (both group 1)
    for _, p in ipairs(BASE) do w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6]); if p[4] then w.mana[p[1]] = p[4] end end
    w:Login(); w:Advance(4)
    local m, d, sh = w.clients.Kumlust, w.clients.Healer3, w.clients.Healer2

    -- the shaman (no drums) hovers the drum button: five types unfold
    sh.NS.Window.buttons.DRUMS:GetScript("OnEnter")(sh.NS.Window.buttons.DRUMS)
    local fly = sh.NS.Window.flyout
    ok(fly and fly:IsShown(), "the flyout opens on hover")
    ok(fly.items.BATTLE and fly.items.PANIC, "with all five drums")
    ok(fly.items.BATTLE.icon:GetAlpha() == 1, "Battle is lit - Kumlust has it")
    ok(fly.items.RESTORATION.icon:GetAlpha() == 1, "Restoration is lit - Healer3 has it")
    ok(fly.items.PANIC.icon:GetAlpha() < 1, "Panic is greyed - nobody has it")
    -- the drummer hovers too: their secure kit unrolls, with the bound one marked
    local mk = m.NS.Window.kit
    m.NS.Window.buttons.DRUMS:GetScript("OnEnter")(m.NS.Window.buttons.DRUMS)
    ok(mk and mk.items.BATTLE:IsShown() and mk.items.PANIC:IsShown(), "a drummer's hover unrolls the kit (no insecure flyout)")
    ok(m.NS.Window.flyout == nil, "the asker flyout is never built for a drummer")
    ok(mk.items.BATTLE.icon:GetAlpha() == 1 and mk.items.WAR.icon:GetAlpha() < 1, "carried drums lit, others greyed")
    ok(mk.items.BATTLE._attrs["*macrotext1"] == "/use [combat] item:29529" and mk.items.WAR._attrs["*macrotext1"] == nil,
       "a carried drum is bound, in combat only; an uncarried one is bound to nothing", tostring(mk.items.BATTLE._attrs["*macrotext1"]))
    ok(m.NS.Window.buttons.DRUMS.drumType == "BATTLE", "the button is bound to Battle")
    ok(m.NS.Window.buttons.DRUMS.tag:GetText() == "B", "and wears the letter")
    w.mouseOver = nil
    m.NS.Window.buttons.DRUMS:GetScript("OnLeave")(m.NS.Window.buttons.DRUMS)
    ok(not mk.items.BATTLE:IsShown(), "and rolls back in when the mouse leaves")

    -- ask for Restoration in particular
    fly.items.RESTORATION:GetScript("OnClick")(fly.items.RESTORATION)
    w:Advance(1)
    local c = sh.NS.Calls:GroupCall("DRUMS", 1)
    ok(c and c.variant == "RESTORATION", "the call carries the type", c and tostring(c.variant))
    ok(d.NS.Window.buttons.DRUMS.glow:IsShown(), "Healer3's button lights - he has Restoration")
    ok(not m.NS.Window.buttons.DRUMS.glow:IsShown(), "Kumlust's does not - Battle is not what was asked")
    ok(d.NS.Window.buttons.DRUMS._attrs["*item1"] == "item:29531", "and Healer3's button is bound to that drum")

    -- Kumlust drumming Battle does not close a Restoration call; Healer3 does
    w:CastDrums("Kumlust"); w:Advance(1)
    ok(sh.NS.Calls:GroupCall("DRUMS", 1) ~= nil, "a Battle drum does not answer a Restoration call")
    w._clog = nil
    w:Cast("DRUMS", "Healer3", "Healer3")
    -- the harness casts spell 35476 (Battle) by default; hand it the Restoration spell name instead
    w._clog = { nil, "SPELL_CAST_SUCCESS", false, "GUID-Healer3", "Healer3", 0, 0, "GUID-Healer3", "Healer3", 0, 0, 999999, "Greater Drums of Restoration", 8 }
    w:FireAll("COMBAT_LOG_EVENT_UNFILTERED"); w:Advance(1)
    ok(sh.NS.Calls:GroupCall("DRUMS", 1) == nil, "Greater Drums of Restoration, by name, closes it")

    -- and a plain click on the drum button asks for any (once a drum is back up)
    w:Advance(125)
    slash(sh, "drums"); w:Advance(1)
    local any = sh.NS.Calls:GroupCall("DRUMS", 1)
    ok(any and any.variant == nil, "a plain click asks for any drum")
    ok(m.NS.Window.buttons.DRUMS.glow:IsShown() or m.NS.Tracker:CooldownLeft("Kumlust", "DRUMS") > 0,
       "any drummer may answer it")
end

section("31. the drum flyout unfolds the way you asked")
do
    local w = raid(BASE)
    local c = w.clients.Healer1
    local W = c.NS.Window
    W:BuildFlyout()
    local point, rel, relPoint = W.flyout:GetPoint()
    ok(point == "BOTTOM" and relPoint == "TOP", "up by default", tostring(point))
    c.NS.Config:Set("flyoutDir", "down")
    point, rel, relPoint = W.flyout:GetPoint()
    ok(point == "TOP" and relPoint == "BOTTOM", "down when asked", tostring(point))
    ok(c.env.BiSInnervateDB.flyoutDir == "down", "and it is saved")
    c.NS.Config:Set("flyoutDir", "up")
end

section("32. a 25-man, in combat, everything at once")
do
    -- 5 groups of 5: a shaman in every group (three talented), three druids,
    -- two drummers, the rest mana users and melee. Combat the whole time, on
    -- a client that drops secure writes.
    local spec = {}
    local classes = { "SHAMAN", "MAGE", "PRIEST", "WARRIOR", "DRUID" }
    for g = 1, 5 do
        for i, cls in ipairs(classes) do
            local name = cls:sub(1, 2) .. g .. i
            local kind = (cls == "SHAMAN" and g <= 3) and "TIDE" or nil
            if cls == "DRUID" and g > 3 then cls = "ROGUE" end
            spec[#spec + 1] = { name, cls, true, (cls == "MAGE") and 15 or 80, g, kind }
        end
    end
    local w = H.NewWorld(".")
    w.drums = { MA12 = 29529, WA44 = 29531 }        -- group 1's mage has Battle, group 4's warrior Restoration
    for _, p in ipairs(spec) do w:AddPlayer(p[1], p[2], p[3], p[5], p[6]); if p[4] then w.mana[p[1]] = p[4] end end
    for _, n in ipairs(w.order) do local c = w.clients[n]; if c.env then c.env.BiSInnervateDB = { modeSet = true, dbVersion = 4 } end end
    w:Login(); w:Advance(5)
    w.blockSecureWrites = true

    local anyDruid = w.clients.DR15
    local faces = 0
    for _ in pairs(anyDruid.NS.Window.byName) do faces = faces + 1 end
    ok(faces == 15, "a druid's grid holds every mage and healer with the addon (5 shamans, 5 mages, 5 priests; not the druids)", faces)
    ok(w.clients.WA14.NS.Window.frame ~= nil, "a warrior has the window too")

    w:SetCombat(true)
    local okRun, err = pcall(function()
        -- three mages call for innervate, three druids each grab one
        slash(w.clients.MA12, ""); slash(w.clients.MA22, ""); slash(w.clients.MA32, ""); w:Advance(1)
        click(face(w.clients.DR15, "MA12")); click(face(w.clients.DR25, "MA22")); click(face(w.clients.DR35, "MA32"))
        w:Advance(0.5)
        -- group 2 wants tide; group 5 wants tide but has no talented shaman
        slash(w.clients.PR23, "tide"); slash(w.clients.PR53, "tide"); w:Advance(1)
        -- the warrior in group 4 wants bloodlust: every shaman sees it
        slash(w.clients.WA44, "lust"); w:Advance(1)
        -- a priest in group 1 wants any drum; a priest in group 4 wants Restoration
        slash(w.clients.PR13, "drums"); slash(w.clients.PR43, "drums restoration"); w:Advance(1)
        -- hover the flyout, get a debuff, change bags, respec - all mid-fight
        w.clients.WA24.NS.Window.buttons.DRUMS:GetScript("OnEnter")(w.clients.WA24.NS.Window.buttons.DRUMS)
        w.debuffs = { WA44 = { [57723] = true } }
        w:Fire("WA44", "UNIT_AURA", "player")
        w:Fire("MA12", "BAG_UPDATE")
        w:Fire("SH41", "PLAYER_TALENT_UPDATE")
        w:Advance(2)
    end)
    ok(okRun, "no protected call anywhere in that", err)

    ok(callFor(w.clients.DR15, "MA12").claimedBy == "DR15" and callFor(w.clients.DR15, "MA22").claimedBy == "DR25"
       and callFor(w.clients.DR15, "MA32").claimedBy == "DR35", "three innervates, three different druids")
    ok(w.clients.DR15.NS.Calls:IsLocked(callFor(w.clients.DR15, "MA22")), "and each druid is locked out of the others")

    ok(w.clients.SH21.NS.Window.tide.glow:IsShown(), "group 2's shaman sees the tide call")
    ok(not w.clients.SH11.NS.Window.tide.glow:IsShown(), "group 1's does not")
    ok(w.clients.PR53.NS.Calls:Mine("TIDE") == nil, "group 5 could not ask - no talented shaman there")

    local lit = 0
    for g = 1, 5 do if w.clients["SH" .. g .. "1"].NS.Window.lust.glow:IsShown() then lit = lit + 1 end end
    ok(lit == 5, "all five shamans see the bloodlust call", lit)
    click(w.clients.SH31.NS.Window.lust); w:Advance(0.5)
    lit = 0
    for g = 1, 5 do if w.clients["SH" .. g .. "1"].NS.Window.lust.glow:IsShown() then lit = lit + 1 end end
    ok(lit == 0, "one click and the other four go dark - and the clicker's is solid, not pulsing", lit)
    w:CastLust("SH31"); w:Advance(1)
    ok(w.clients.WA44.NS.Calls:Mine("LUST") == nil, "the cast closes it for the raid")

    ok(w.clients.MA12.NS.Window.buttons.DRUMS.glow:IsShown(), "group 1's drummer lights for 'any'")
    ok(w.clients.WA44.NS.Window.buttons.DRUMS.glow:IsShown(), "group 4's drummer lights for Restoration - he has it")
    w:SetCombat(false)
    w:Advance(1)
    ok(w.clients.MA12.NS.Window.buttons.DRUMS._attrs["*item1"] == "item:29529", "bindings intact after the fight")
end

section("33. a drummer with two drums picks which one the button uses")
do
    local w = raid(BASE)
    -- give Kumlust Battle now, then War as well via the bag scan fallback path
    w.drums = { Kumlust = 29529 }
    w:Fire("Kumlust", "BAG_UPDATE"); w:Advance(2)
    local m = w.clients.Kumlust
    ok(m.NS.Window.buttons.DRUMS.drumType == "BATTLE", "starts on the best drum")
    -- pretend the bag also holds War: the harness fallback only knows one item, so stub MyDrums
    local real = m.NS.MyDrums
    m.NS.MyDrums = function() return { BATTLE = 29529, WAR = 29528 } end
    local kit = m.NS.Window.kit
    m.NS.Window.buttons.DRUMS:GetScript("OnEnter")(m.NS.Window.buttons.DRUMS)
    ok(kit.items.WAR:IsShown(), "the kit unrolls")
    click(kit.items.WAR)                 -- out of combat: the click sets the default (the macro is [combat] only)
    ok(m.NS.Window.buttons.DRUMS._attrs["*item1"] == "item:29528", "picking War rebinds the button", tostring(m.NS.Window.buttons.DRUMS._attrs["*item1"]))
    ok(m.NS.Window.buttons.DRUMS.tag:GetText() == "W", "and the letter follows")
    ok(not kit.items.WAR:IsShown(), "and the kit rolls back in after the pick")
    -- mid-fight the pick waits
    w:SetCombat(true)
    m.NS.Window:PickDrum("BATTLE")
    ok(m.NS.Window.buttons.DRUMS._attrs["*item1"] == "item:29528", "in combat the binding does not move")
    w:SetCombat(false); w:Advance(1)
    ok(m.NS.Window.buttons.DRUMS._attrs["*item1"] == "item:29529", "and lands when the fight ends")
    -- a specific group call still wins over the pick
    m.NS.Window:PickDrum("WAR")
    slash(w.clients.Healer2, "drums battle"); w:Advance(1)
    ok(m.NS.Window.buttons.DRUMS._attrs["*item1"] == "item:29529", "a call for Battle overrides the pick")
    m.NS.MyDrums = real
end

section("33b. mid-fight the group wants a drum the button does not hold")
do
    local w = raid(BASE)
    w.drums = { Kumlust = 29529 }
    w:Fire("Kumlust", "BAG_UPDATE"); w:Advance(2)
    local m, sh = w.clients.Kumlust, w.clients.Healer2
    local real = m.NS.MyDrums
    m.NS.MyDrums = function() return { BATTLE = 29529, RESTORATION = 29531 } end
    m.NS.Window:Bind(); m.NS.Comm:Hello(); w:Advance(2)      -- the raid learns about both drums
    local kit, btn = m.NS.Window.kit, m.NS.Window.buttons.DRUMS
    ok(btn.drumType == "BATTLE" and kit.items.RESTORATION._attrs["*macrotext1"] == "/use [combat] item:29531",
       "button on Battle, Restoration bound in the kit for a fight")
    w.blockSecureWrites = true
    w:SetCombat(true)
    local okRun, err = pcall(function()
        slash(sh, "drums restoration"); w:Advance(1)
        w.mouseOver = btn
        btn:GetScript("OnEnter")(btn)                        -- the secure snippet unrolls it
    end)
    ok(okRun, "the ask and the hover mid-fight touch nothing protected", err)
    ok(kit.items.RESTORATION:IsShown() and kit.items.PANIC:IsShown(), "the kit unrolled in combat")
    ok(kit.items.RESTORATION.glow:IsShown() and kit.items.RESTORATION.anim:IsPlaying(), "Restoration - the one the group wants - pulses")
    ok(not kit.items.BATTLE.glow:IsShown(), "Battle does not")
    ok(btn._attrs["*item1"] == "item:29529", "the main button still holds Battle (it cannot be rebound in a fight)")
    -- the drummer clicks it: the secure macro drums Restoration, PostClick claims the call
    w.mouseOver = kit.items.RESTORATION
    btn:GetScript("OnLeave")(btn)
    ok(kit.items.RESTORATION:IsShown(), "moving from the button onto the kit keeps it open")
    click(kit.items.RESTORATION); w:Advance(0.5)
    local c = sh.NS.Calls:GroupCall("DRUMS", 1)
    ok(c and c.claimedBy == "Kumlust", "the click claims the group's call", c and tostring(c.claimedBy))
    ok(not kit.items.RESTORATION.glow:IsShown(), "and the pulse stops")
    w.mouseOver = nil
    kit.items.RESTORATION:GetScript("OnLeave")(kit.items.RESTORATION)
    ok(not kit.items.RESTORATION:IsShown(), "leaving the kit rolls it back in - in combat, by the snippet")
    w:SetCombat(false); w:Advance(1)
    ok(btn._attrs["*item1"] == "item:29531", "fight over: the open Restoration call rebinds the main button")
    m.NS.MyDrums = real
end

section("34. FojjiCore renamed its packs and dropped Brittney")
do
    local w = raid(BASE)
    local c = w.clients.Healer3
    local S = c.NS.Sound
    c.env.FojjiCore = {
        voicePackOrder = { "Community - Nobody", "Community - Ripley" },
        voicePacks = {
            ["Community - Nobody"] = { ["Table"] = "x.ogg" },                 -- no innervate lines
            ["Community - Ripley"] = { ["Fixate on You"] = "Interface\\AddOns\\FojjiCore\\voice\\r\\fixate.ogg" },
        },
    }
    c.env.BiSInnervateDB.voice = "auto"
    ok(S:ActivePack() == "Community - Ripley", "auto skips a pack without our lines", tostring(S:ActivePack()))
    -- Arn's pick, whatever Fojji prefixes it with: Illidan first when it has our lines
    c.env.FojjiCore.voicePackOrder = { "Community - Nobody", "Community - Ripley", "Flavour - Illidan", "Illidan <Old>" }
    c.env.FojjiCore.voicePacks["Flavour - Illidan"] = { ["Fixate on You"] = "i.ogg" }
    c.env.FojjiCore.voicePacks["Illidan <Old>"] = { ["Table"] = "x.ogg" }
    ok(S:ActivePack() == "Flavour - Illidan", "auto prefers Illidan when installed with our lines", tostring(S:ActivePack()))
    c.env.FojjiCore.voicePacks["Flavour - Illidan"]["Fixate on You"] = nil
    ok(S:ActivePack() == "Community - Ripley", "but not an Illidan pack without them", tostring(S:ActivePack()))
    c.env.FojjiCore.voicePackOrder = { "Community - Nobody", "Community - Ripley" }
    c.env.FojjiCore.voicePacks["Flavour - Illidan"] = nil; c.env.FojjiCore.voicePacks["Illidan <Old>"] = nil
    -- the short names the stepper shows: the voice, not Fojji's group and guild tags
    for full, short in pairs({ ["Flavour - Illidan"] = "Illidan", ["Community - Fojji <Numen>"] = "Fojji",
                               ["Chinese - Stacy"] = "Stacy", ["Joardee - Streamer"] = "Joardee",
                               ["Arabella"] = "Arabella", ["auto"] = "auto", ["off"] = "off" }) do
        ok(S:ShortPack(full) == short, "short name: " .. full .. " -> " .. short, S:ShortPack(full))
    end
    c.env.BiSInnervateDB.voice = "ripley"
    ok(S:ActivePack() == "Community - Ripley", "a saved name still matches through the new prefix")
    c.env.BiSInnervateDB.voice = "brittney"
    ok(S:ActivePack() == nil, "a pack that is gone picks nothing (kit sounds play)")
    c.env.FojjiCore.voicePacks["Community - Ripley"] = nil
    c.env.BiSInnervateDB.voice = "auto"
    ok(S:ActivePack() == "Community - Nobody", "no pack has the lines: first installed, never nil")
    local played = {}
    c.env.PlaySoundFile = function(p) played[#played + 1] = p; return false end
    local kit = 0
    c.env.PlaySound = function() kit = kit + 1 end
    S:Play("someoneAsked")
    ok(kit == 1, "a missing line falls back to the kit sound, no error")
    c.env.FojjiCore = nil
    c.env.BiSInnervateDB.voice = "auto"
end

section("35. Odiss mode: mages only, the window fits them")
do
    local w = raid(BASE)
    w:AddPlayer("Dps2", "MAGE", true, 2); w:AddPlayer("Dps1", "MAGE", true, 2)
    w:FireAll("GROUP_ROSTER_UPDATE"); w:Advance(4)
    local c = w.clients.Healer3
    local W, f = c.NS.Window, c.NS.Window.frame
    local SZ = W.SIZE + W.GAP
    local function wide(n) return math.max(W.PAD * 2 + n * SZ - W.GAP, W.MINW_MAGES) end
    local function tall(rows) return W.HEADER + W.PAD + rows * SZ - W.GAP + W.PAD end
    local function shownBtns()
        local n = 0
        for _, b in pairs(W.buttons) do if b:IsShown() then n = n + 1 end end
        return n
    end
    local fullW, fullH = f:GetWidth(), f:GetHeight()
    ok(fullW == W.width and shownBtns() == 4 and not W.buttons.REZ:IsShown() and face(c, "Healer1") ~= nil,
       "everyone: fixed width, four buttons (the rez one is off screen with nothing to do), the priest has a face")
    f:SetPoint("TOPLEFT", c.env.UIParent, "TOPLEFT", 40, -40)

    -- the M in the corner
    click(W.magesBtn)
    ok(c.env.BiSInnervateDB.magesOnly == true, "M turns Odiss mode on")
    ok(W.magesBtn.lit == true and not W.cfgBtn:IsShown() and not W.title:IsShown(), "M lit, cfg and title gone from the bar")
    ok(face(c, "Kumlust") and face(c, "Dps2") and face(c, "Dps1"), "three mage faces")
    ok(face(c, "Healer1") == nil and face(c, "Healer2") == nil and face(c, "Healer3") == nil, "nobody else")
    ok(shownBtns() == 0, "no button row")
    ok(f:GetWidth() == wide(3), "window is exactly three faces wide", f:GetWidth())
    ok(f:GetHeight() == tall(1), "and one row tall", f:GetHeight())
    local p1, _, _, x1, y1 = f:GetPoint()
    ok(p1 == "TOPLEFT" and x1 == 40 and y1 == -40, "the anchor did not move")
    local gp = { W.grid:GetPoint() }
    ok(gp[5] == -W.PAD, "faces start right under the bar", gp[5])
    -- faces are still live for the druid, in a row
    local pyro = face(c, "Dps1")
    ok(pyro._attrs["unit"] == "Dps1" and pyro._mouse == true, "a druid can still click a mage")
    local _, _, _, px = pyro:GetPoint()
    ok(px == 0, "the mage face sits in the first column", px)

    -- mages come and go: the window follows
    w:AddPlayer("Arcane", "MAGE", true, 1); w:FireAll("GROUP_ROSTER_UPDATE"); w:Advance(4)
    ok(f:GetWidth() == wide(4) and face(c, "Arcane") ~= nil, "a fourth mage joins: wider", f:GetWidth())
    w:RemovePlayer("Arcane"); w:RemovePlayer("Dps1"); w:RemovePlayer("Dps2"); w:Advance(1)
    ok(f:GetWidth() == W.MINW_MAGES and face(c, "Kumlust") ~= nil, "down to one mage: never narrower than the bar", f:GetWidth())
    for i = 1, 8 do w:AddPlayer("Mage" .. i, "MAGE", true, (i % 5) + 1) end
    w:FireAll("GROUP_ROSTER_UPDATE"); w:Advance(4)
    ok(W.count == 9 and f:GetWidth() == wide(8) and f:GetHeight() == tall(2), "nine mages wrap to a second row", f:GetWidth() .. "x" .. f:GetHeight())
    local last = face(c, "Mage8"); local _, _, _, lx, ly = last:GetPoint()   -- by name: Kumlust first, Mage8 ninth
    ok(lx == 0 and ly == -SZ, "the ninth starts the second row", lx .. "," .. ly)

    -- a call still pulses the face, and everyone else's window is unchanged
    slash(w.clients.Kumlust, ""); w:Advance(1)
    ok(pulsing(face(c, "Kumlust")), "a mage's call pulses in Odiss mode")
    ok(w.clients.Healer4.NS.Window.frame:GetWidth() == W.width, "the other druid's window is untouched")

    -- in combat: the setting flips, the bar repaints, the window waits
    w:SetCombat(true)
    local before = f:GetWidth()
    click(W.magesBtn)
    ok(c.env.BiSInnervateDB.magesOnly == false and W.magesBtn.lit == false, "M off mid-fight: saved and the bar repainted")
    ok(f:GetWidth() == before and shownBtns() == 0, "but the window did not touch anything protected")
    w:AddPlayer("Dps5", "MAGE", true, 3); w:FireAll("GROUP_ROSTER_UPDATE"); w:Advance(4)
    ok(f:GetWidth() == before, "a mage joining mid-fight does not resize either")
    w:SetCombat(false); w:Advance(1)
    -- 4 originals + 8 mages + the late one = 13 faces, three rows of six
    ok(f:GetWidth() == W.width and f:GetHeight() == fullH + 2 * SZ and shownBtns() == 4, "fight over: everyone is back, four buttons, full width", f:GetWidth() .. "x" .. f:GetHeight())
    ok(face(c, "Healer1") ~= nil and face(c, "Dps5") ~= nil, "priest and the late mage both have faces")
    ok(W.cfgBtn:IsShown() and W.title:IsShown(), "cfg and the title are back")
    local gp2 = { W.grid:GetPoint() }
    ok(gp2[5] == -(W.PAD + W.BTN_H + W.PAD), "faces sit under the button row again", gp2[5])

    -- the option and the slash write the same key
    local C = c.NS.Config
    C:Set("magesOnly", true)
    ok(C:Get("magesOnly") == true and shownBtns() == 0 and f:GetWidth() == wide(8) and f:GetHeight() == tall(2), "options tick: same thing, ten mages on two rows", f:GetWidth())
    slash(c, "mages")
    ok(C:Get("magesOnly") == false and shownBtns() == 4, "/inn mages: off again")
    ok(W.frame:GetScale() == 1, "scale untouched by any of it")

    -- the x: a closed window must not leave an invisible title bar behind
    click(W.closeBtn)
    ok(c.env.BiSInnervateDB.hidden == true and f:GetAlpha() == 0, "x closes it")
    ok(W.magesBtn._mouse == false and W.cfgBtn._mouse == false and W.closeBtn._mouse == false and f._mouse == false,
       "and nothing on the invisible bar takes the mouse")
    slash(c, "show")
    ok(W.magesBtn._mouse == true and f._mouse == true, "/inn show gives it back")
    -- logging in with it closed
    local w2 = raid(BASE, { Healer3 = { hidden = true, dbVersion = 4 } })
    local W2 = w2.clients.Healer3.NS.Window
    ok(W2.frame:GetAlpha() == 0 and W2.closeBtn._mouse == false and W2.frame._mouse == false, "closed at login: bar deaf from the start")
end

--------------------------------------------------------------------
-- the rez module (folded in from BiS Rez 3.0; its 161 checks live on here)
--------------------------------------------------------------------

local function rezBtn(c) return c.NS.Window.buttons.REZ end
local function decision(c) return c.NS.Rez.last or c.NS.Rez:Decide() end
-- a raid where the healers have real mana bars (the rez costs 1500)
local function rezRaid(extra)
    local w = H.NewWorld(".")
    for _, p in ipairs(BASE) do w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6]); if p[4] then w.mana[p[1]] = p[4] end end
    for _, p in ipairs(extra or {}) do w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6]) end
    w.manaMax = {}
    for _, n in ipairs({ "Healer1", "Healer2", "Dps6", "Healer3", "Healer4" }) do w.manaMax[n] = 10000; w.mana[n] = 8000 end
    w.bags.Healer1 = { 34062 }        -- a biscuit
    for _, n in ipairs(w.order) do local c = w.clients[n]; if c.env then c.env.BiSInnervateDB = { modeSet = true, dbVersion = 4 } end end
    w:Login(); w:Advance(4)
    return w
end

section("36. the fifth button: a healer's rez, everyone else's 'rez me first'")
do
    local w = rezRaid()
    local h, sh, d, m, t = w.clients.Healer1, w.clients.Healer2, w.clients.Healer3, w.clients.Kumlust, w.clients.Tank1
    ok(h.NS.Rez:Enabled() and sh.NS.Rez:Enabled() and d.NS.Rez:Enabled(), "priest, shaman and druid have the button")
    ok(not m.NS.Rez:Enabled() and not t.NS.Rez:Enabled(), "mage and warrior do not")
    ok(h.NS.Provides("REZ") and sh.NS.Provides("REZ"), "priest and shaman provide REZ")
    ok(not d.NS.Provides("REZ"), "a druid does NOT - Rebirth is never in the rez table")
    ok(h.NS.Rez:SpellName() == "Resurrection" and sh.NS.Rez:SpellName() == "Ancestral Spirit", "each class's own rez",
       tostring(sh.NS.Rez:SpellName()))
    local names = {}
    for n in pairs(m.NS.Tracker.providers.REZ) do names[#names + 1] = n end
    table.sort(names)
    ok(table.concat(names, ",") == "Dps6,Healer1,Healer2", "the mage's client knows the three rezzers from HELLO", table.concat(names, ","))
    ok(#m.NS.Rez:Rezzers() == 3 and m.NS.Rez:RezzersReady() == 3, "three standing, three ready")
    local hello
    for _, msg in ipairs(w.addonMsgs) do if msg.from == "Healer1" and string.find(msg.msg, "|HELLO|", 1, true) then hello = msg.msg end end
    ok(hello and string.find(hello, "REZ", 1, true) and string.match(hello, "^4|"), "HELLO carries REZ on protocol 4", hello)
    ok(rezBtn(h)._secure == true, "the button is secure")
    ok(rezBtn(h)._attrs["*type1"] == "macro", "and carries a macro for the priest", tostring(rezBtn(h)._attrs["*type1"]))
    ok(rezBtn(m)._attrs["*type1"] == nil and rezBtn(m)._attrs["*macrotext1"] == nil, "and nothing for the mage")
    -- a druid still gets heal and drink
    ok(decision(d).why and string.find(decision(d).why, "Rebirth", 1, true), "the druid's button says why it will not rez", decision(d).why)
    -- everyone standing and healthy: the button is not on screen
    local dh = decision(h)
    ok(dh.action == nil and rezBtn(h)._attrs["*macrotext1"] == "" and not rezBtn(h):IsShown(), "idle: nothing to do, the button is off screen")
    ok(w.drivers[rezBtn(h)] == "hide", "with its driver set to hide", tostring(w.drivers[rezBtn(h)]))
    ok(not rezBtn(m):IsShown(), "the mage's is off screen too - he is alive")
end

section("37. rez order is a throughput order")
do
    local w = rezRaid()
    local h = w.clients.Healer1
    w.dead = { Kumlust = true, Healer2 = true, Tank1 = true }
    w:Advance(1)
    local d = decision(h)
    ok(d.action == "rez" and d.target == "Healer2", "the shaman (a rezzer) goes before the mage and the warrior", tostring(d.target))
    ok(rezBtn(h)._attrs["*macrotext1"] == "/stopcasting\n/cast [target=Healer2,nocombat] Resurrection", "the macro aims by NAME", rezBtn(h)._attrs["*macrotext1"])
    local act = h.NS.Window.con and h.NS.Window.con.slots.action
    ok(act and string.find(act.text, "Healer2", 1, true), "and the title bar says who is next", act and act.text)
    ok(rezBtn(h).glow:IsShown(), "the button pulses: there is a rez to do")
    -- every standing rezzer dry: water beats another body
    w.dead = { Kumlust = true, Tank1 = true }
    w.mana.Healer1, w.mana.Healer2, w.mana.Dps6 = 2000, 2000, 2000
    w:Advance(1)
    ok(decision(h).target == "Kumlust", "with every rezzer dry, the mage goes first", tostring(decision(h).target))
    -- no mana reading at all: never assume dry
    w.dead = { Kumlust = true, Healer1 = false, Healer2 = true }
    w.mana.Healer1, w.mana.Healer2, w.mana.Dps6 = 8000, 8000, 8000
    w:Advance(1)
    ok(decision(h).target == "Healer2", "wet again: the rezzer is first", tostring(decision(h).target))
    -- a released player sorts behind every body on the floor
    w.dead = { Kumlust = true, Healer2 = true }
    w.ghost = { Healer2 = true }
    w:Advance(1)
    ok(decision(h).target == "Kumlust", "a released shaman sorts behind the mage's body", tostring(decision(h).target))
    w.ghost = {}
    -- nobody dead: back to idle
    w.dead = {}
    w:Advance(1)
    ok(decision(h).action ~= "rez", "no corpses, no rez")
    -- a dead priest casts nothing
    w.dead = { Healer1 = true, Kumlust = true }
    w:Advance(1)
    ok(decision(h).action == nil and decision(h).why == "you are dead", "a dead priest is offered nothing, not even themself", tostring(decision(h).why))
    w.dead = {}
end

section("38. a name the client cannot aim stays unaimed")
do
    local w = H.NewWorld(".")
    w.noNames = true
    for _, p in ipairs(BASE) do w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6]) end
    w.manaMax = { Healer1 = 10000 }; w.mana.Healer1 = 8000
    w:Login(); w:Advance(4)
    local h = w.clients.Healer1
    w.dead = { Kumlust = true }
    w:Advance(1)
    local d = decision(h)
    ok(d.target == "Kumlust" and d.action ~= "rez", "the corpse is known but the button does not rez it")
    ok(string.find(rezBtn(h)._attrs["*macrotext1"] or "", "Kumlust", 1, true) == nil, "no macro aims at a name the client cannot resolve")
    ok(d.why and string.find(d.why, "by name", 1, true), "and the tooltip says why", d.why)
end

section("39. the claim attaches when the cast starts, and everyone moves on")
do
    local w = rezRaid()
    local h, sh = w.clients.Healer1, w.clients.Healer2
    w.dead = { Kumlust = true, Tank1 = true }
    w:Advance(1)
    ok(decision(h).target == "Kumlust" and decision(sh).target == "Kumlust", "both rezzers aim at the mage")
    click(rezBtn(h))
    w:Advance(0.2)
    ok(sh.NS.Rez:ClaimedBy("Kumlust") == nil, "a click alone claims nothing (it may die on 'not enough mana')")
    w:StartCast("Healer1", "Resurrection", "Kumlust", 10)
    w:Advance(0.6)
    ok(sh.NS.Rez:ClaimedBy("Kumlust") == "Healer1", "the cast starting claims the corpse on the shaman's client")
    ok(decision(sh).target == "Tank1", "and the shaman's button moved to the next corpse at once", tostring(decision(sh).target))
    ok(rezBtn(sh)._attrs["*macrotext1"] == "/stopcasting\n/cast [target=Tank1,nocombat] Ancestral Spirit", "with the macro rebound", rezBtn(sh)._attrs["*macrotext1"])
    ok(sh.NS.Rez:RezzersReady() == 2, "a rezzer mid-cast is not counted ready", sh.NS.Rez:RezzersReady())
    -- an unrelated interrupt of the priest's does not free it
    w.addonMsgs = {}
    w:Fire("Healer1", "UNIT_SPELLCAST_INTERRUPTED", "player", "x", 25449)
    w:Fire("Healer1", "UNIT_SPELLCAST_STOP", "player", "x", 25449)
    local freed = false
    for _, m in ipairs(w.addonMsgs) do if string.find(m.msg, "|RFREE|", 1, true) then freed = true end end
    ok(not freed and sh.NS.Rez:ClaimedBy("Kumlust") == "Healer1", "an unrelated spell ending does not release the claim")
    -- the rez itself dying does
    w:StopCast("Healer1", "UNIT_SPELLCAST_INTERRUPTED")
    w:Advance(0.6)
    ok(sh.NS.Rez:ClaimedBy("Kumlust") == nil, "interrupting the rez frees the corpse everywhere")
    ok(decision(sh).target == "Kumlust", "and the shaman's button comes back to the mage", tostring(decision(sh).target))
    -- landing it
    click(rezBtn(sh)); w:StartCast("Healer2", "Ancestral Spirit", "Kumlust", 10); w:Advance(0.6)
    w:CastRez("Healer2", "Kumlust")
    ok(h.NS.Rez:RecentlyRezzed("Kumlust"), "the priest's client knows the mage has a rez incoming")
    ok(decision(h).target == "Tank1", "and moves on to the warrior", tostring(decision(h).target))
    ok(w.clients.Kumlust.NS.db.rezScores.Healer2 == 1, "the shaman scored one on everyone's board")
    w.dead = {}
end

section("39b. raid night 12 Sep: a rez from the raid frames still claims; a collision stops the later cast")
do
    local w = rezRaid()
    local h, sh = w.clients.Healer1, w.clients.Healer2
    w.dead = { Kumlust = true, Tank1 = true }
    w:Advance(1)
    ok(decision(h).target == "Kumlust" and decision(sh).target == "Kumlust", "both rezzers aim at the mage")
    -- the priest rezzes the mage from her raid frames: no click on our button, no pending
    w.addonMsgs = {}
    w:StartCast("Healer1", "Resurrection", "Kumlust", 10)
    w:Advance(0.6)
    local claimed = false
    for _, m in ipairs(w.addonMsgs) do if string.find(m.msg, "|RCLAIM|Kumlust", 1, true) then claimed = true end end
    ok(claimed, "a rez cast that did not come through our button still sends the claim (UNIT_SPELLCAST_SENT carries the target)")
    ok(sh.NS.Rez:ClaimedBy("Kumlust") == "Healer1", "the shaman's client has it")
    ok(decision(sh).target == "Tank1", "and the shaman's button moved on", tostring(decision(sh).target))
    w:StopCast("Healer1"); w:CastRez("Healer1", "Kumlust")
    w.dead = { Tank1 = true, Dps6 = true }
    w:Advance(1)
    local first = decision(h).target
    ok(first ~= nil and decision(sh).target == first, "next wipe: both aim at the same corpse first", tostring(first))
    local second = (first == "Dps6") and "Tank1" or "Dps6"
    -- the collision: the shaman clicks; in the half second before his cast bar is up the
    -- priest's claim lands; his cast then starts on a corpse somebody is already on -> stopped
    click(rezBtn(sh))
    w:StartCast("Healer1", "Resurrection", first, 10)
    w:Advance(0.1)
    ok(sh.NS.Rez:ClaimedBy(first) == "Healer1", "the priest's claim arrived first")
    w.forbidden = {}
    w.addonMsgs = {}
    w:StartCast("Healer2", "Ancestral Spirit", first, 10)
    ok((w.forbidden.Healer2 or 0) == 0, "the addon never calls SpellStopCasting (protected: ADDON_ACTION_FORBIDDEN, 13 Sep)")
    ok(w.casting.Healer2 ~= nil, "so the cast keeps running - the client does not let us stop it")
    ok(string.find(rezBtn(sh)._attrs["*macrotext1"] or "", "^/stopcasting\n"), "the button's macro starts with /stopcasting: the NEXT click cancels it", rezBtn(sh)._attrs["*macrotext1"])
    local mine = false
    for _, m in ipairs(w.addonMsgs) do if string.find(m.msg, "|RCLAIM|" .. first, 1, true) then mine = true end end
    ok(not mine, "and he sends no claim of his own")
    ok(sh.NS.Rez:ClaimedBy(first) == "Healer1", "the priest keeps the corpse")
    w:Advance(0.6)
    ok(decision(sh).target == second, "the shaman's button is on the next corpse", tostring(decision(sh).target))
    local said = false
    for _, line in ipairs(sh.prints) do if string.find(line, "already rezzing", 1, true) then said = true end end
    ok(said, "and says who has it")
    local again = false
    for _, line in ipairs(sh.prints) do if string.find(line, "click again", 1, true) then again = true end end
    ok(again, "and tells him the next click cancels it")
    -- the same cast when nobody else is on it: claimed as before
    click(rezBtn(sh)); w:StartCast("Healer2", "Ancestral Spirit", second, 10)
    ok(sh.NS.Rez:ClaimedBy(second) == nil and h.NS.Rez:ClaimedBy(second) == "Healer2", "and claims it for him")
    w.dead = {}
end

section("40. cast-bar claims: rezzers without the addon, and 'don't release'")
do
    local w = rezRaid({ { "Silent", "PRIEST", false, 2 } })      -- a priest without the addon
    local h, m = w.clients.Healer1, w.clients.Kumlust
    w.dead = { Kumlust = true, Tank1 = true }
    w:Advance(1)
    ok(decision(h).target == "Kumlust", "the priest aims at the mage")
    w.casting.Silent = { spell = "Resurrection", target = "Kumlust", endAt = w.time + 9 }
    w:Advance(0.6)
    local who, src = h.NS.Rez:ClaimedBy("Kumlust")
    ok(who == "Silent" and src == "cast", "a rez on somebody's cast bar claims their target", tostring(who))
    ok(decision(h).target == "Tank1", "and the button moves to the warrior")
    ok(#m.sounds > 0, "the mage heard the 'don't release' cue")
    ok(string.find(m.prints[#m.prints] or "", "release", 1, true) ~= nil, "and read it", m.prints[#m.prints])
    local n = #m.sounds
    w:Advance(2)
    ok(#m.sounds == n, "once per corpse, not once per tick")
    -- the claim lasts as long as the cast does, not a flat 3s
    w.casting.Silent = nil
    w:Advance(5)
    ok(h.NS.Rez:ClaimedBy("Kumlust") == "Silent", "the claim outlives the old flat 3 seconds")
    w:Advance(6)
    ok(h.NS.Rez:ClaimedBy("Kumlust") == nil, "and expires when the cast would have landed")
    ok(#m.NS.Tracker:Available("REZ") == 3, "the silent priest is not on the rezzer roster - no addon")
    w.dead = {}
end

section("41. heals: worst off, in range, minus what others already have in the air")
do
    local w = rezRaid()
    local sh = w.clients.Healer2
    w.hp = { Tank1 = 6000, Kumlust = 5000 }
    w.hpmax = { Tank1 = 12000, Kumlust = 7000 }
    w:Advance(1)
    local d = decision(sh)
    ok(d.action == "heal" and d.target == "Tank1", "two hurt: the group heal on the worst off (50% beats 71%)", tostring(d.target))
    ok(d.healSpell and string.find(d.healSpell, "Chain Heal", 1, true), "a shaman with 2+ hurt uses Chain Heal", tostring(d.healSpell))
    ok(rezBtn(sh)._attrs["*macrotext1"] == "/cast [@Tank1,help,nodead,nocombat] Chain Heal(Rank 5)",
       "the heal macro aims at ONE name - no mouseover/target/player fallback to land it on the wrong person", rezBtn(sh)._attrs["*macrotext1"])
    w.hp.Kumlust = 7000
    w:Advance(1)
    d = decision(sh)
    ok(d.target == "Tank1" and string.find(d.healSpell, "Healing Wave", 1, true), "one hurt: single target", tostring(d.healSpell))
    w.outOfRange = { Tank1 = true }
    w:Advance(1)
    ok(decision(sh).action ~= "heal", "out of range: not chosen")
    w.outOfRange = {}
    -- inbound from others
    w.hp.Kumlust = 5000
    w.incoming = { Tank1 = 6000 }
    w:Advance(1)
    ok(decision(sh).target == "Kumlust", "the tank is covered by others: it moves to the mage", tostring(decision(sh).target))
    w.incoming = { Tank1 = 6000, Kumlust = 2000 }
    w:Advance(1)
    ok(decision(sh).action == nil and not rezBtn(sh):IsShown(), "everyone covered: it stands down and leaves the screen")
    w.incoming = {}
    w.myIncoming = { Tank1 = 6000 }
    w:Advance(1)
    ok(decision(sh).target == "Tank1", "your own inbound heal is not subtracted", tostring(decision(sh).target))
    w.myIncoming = {}
    -- larger, not sum: LibHealComm and native describing the same heal
    sh.NS.Rez._hc = { CASTED_HEALS = 1, GetOthersHealAmount = function(_, guid) return (guid == "GUID-Tank1") and 6000 or 0 end }
    w.incoming = { Tank1 = 6000 }
    w.hp.Kumlust = 7000
    w:Advance(1)
    ok(decision(sh).action == nil, "both sources on one target take the larger, not the sum")
    sh.NS.Rez._hc = nil
    w.incoming = {}
    -- sizes include gear and talents
    w.bonusHealing.Healer2 = 1500
    w.talents.Healer2 = { { "Purification", 5 } }
    w:Fire("Healer2", "SPELLS_CHANGED")
    local lhw
    for _, h in ipairs(sh.NS.Rez.heals) do if string.find(h.cast, "Lesser", 1, true) then lhw = h.heal end end
    local want = (951 + 1500 * (1.5 / 3.5)) * 1.10
    ok(lhw and math.abs(lhw - want) <= 1, "gear + talents fold into the heal size", tostring(lhw) .. " vs " .. want)
    w.hp = { Tank1 = 10500 }; w.hpmax = { Tank1 = 12000 }
    w:Advance(1)
    ok(string.find(decision(sh).healSpell or "", "Lesser", 1, true), "a 1500 hole picks the small heal, not the big one", tostring(decision(sh).healSpell))
    -- a paladin has no group heal in TBC
    local w2 = rezRaid({ { "Healer6", "PALADIN", true, 2 } })
    w2.manaMax.Healer6 = 10000; w2.mana.Healer6 = 8000
    w2.hp = { Tank1 = 6000, Kumlust = 5000 }; w2.hpmax = { Tank1 = 12000, Kumlust = 7000 }
    w2:Advance(1)
    local dp = decision(w2.clients.Healer6)
    ok(dp.action == "heal" and string.find(dp.healSpell, "Light", 1, true), "a paladin with two hurt falls back to a single-target heal", tostring(dp.healSpell))
    w.hp, w.hpmax = {}, {}
end

section("42. drink when the next cast is unaffordable; the druid's button")
do
    local w = rezRaid()
    local h, d = w.clients.Healer1, w.clients.Healer3
    w.dead = { Kumlust = true }
    w.mana.Healer1 = 100
    w:Advance(1)
    local dh = decision(h)
    ok(dh.action == "drink" and dh.drinkId == 34062, "no mana for the rez: the biscuit", tostring(dh.action))
    ok(rezBtn(h)._attrs["*macrotext1"] == "/use [nocombat] 0 1", "as a bag/slot macro", rezBtn(h)._attrs["*macrotext1"])
    ok(dh.why and string.find(dh.why, "drinking", 1, true), "and the tooltip says so", dh.why)
    w.buffs.Healer1 = { { "Drink", 27089 } }
    w:Advance(1)
    ok(decision(h).action ~= "drink", "already drinking: not again")
    w.buffs.Healer1 = nil
    h.NS.db.rezDrink = false; h.NS.Rez.last = nil
    w:Advance(1)
    ok(decision(h).action == nil, "drink switched off: nothing")
    h.NS.db.rezDrink = true
    w.mana.Healer1 = 8000
    -- the druid: never a rez, but heals and drinks
    w.dead = { Kumlust = true }
    w:Advance(1)
    ok(decision(d).action ~= "rez" and decision(d).target == nil, "a druid is never offered a rez, corpses or not")
    w.dead = {}
    w.hp = { Tank1 = 1000 }; w.hpmax = { Tank1 = 12000 }
    w:Advance(1)
    ok(decision(d).action == "heal", "a druid still heals", tostring(decision(d).action))
    w.bags.Healer3 = { 22018 }
    w.mana.Healer3 = 10
    w:Advance(1)
    ok(decision(d).action == "drink", "and drinks", tostring(decision(d).action))
    w.mana.Healer3 = 8000
    w.hp, w.hpmax = {}, {}
end

section("43. combat: the rez button is re-aimed only when the fight ends")
do
    local w = rezRaid()
    w.blockSecureWrites = true
    local h = w.clients.Healer1
    w:Advance(1)
    local armed = rezBtn(h)._attrs["*macrotext1"]
    w:SetCombat(true)
    local okRun, err = pcall(function()
        w.dead = { Kumlust = true }
        w:Advance(2)
        click(rezBtn(h))
        w:Fire("Healer1", "UI_ERROR_MESSAGE", 1, "Not enough mana")
        w.hp = { Tank1 = 2000 }; w.hpmax = { Tank1 = 12000 }
        w:Advance(2)
        slash(h, "rez"); slash(h, "rezlist"); slash(h, "rezzers"); slash(h, "heals")
        h.NS.Config:Set("rez", false); h.NS.Config:Set("rez", true)
        rezBtn(h):GetScript("OnEnter")(rezBtn(h))
    end)
    ok(okRun, "a death, a click, an error, options and tooltips mid-fight touch nothing protected", err)
    ok(rezBtn(h)._attrs["*macrotext1"] == armed, "the macro is untouched in combat", rezBtn(h)._attrs["*macrotext1"])
    ok(h.NS.Window.rezPending == true, "the rebind is waiting for the fight to end")
    w:SetCombat(false)
    w:Advance(1)
    ok(not h.NS.Window.rezPending and rezBtn(h)._attrs["*macrotext1"] == "/stopcasting\n/cast [target=Kumlust,nocombat] Resurrection", "and lands when it does", rezBtn(h)._attrs["*macrotext1"])
    w.dead = {}
    w.hp, w.hpmax = {}, {}
end

section("44. 'rez me first': the ask goes to the front, the next click takes them")
do
    local w = rezRaid({ { "Dps2", "MAGE", true, 2 }, { "Dps1", "MAGE", true, 2 } })
    local h, sh, fr, py, t = w.clients.Healer1, w.clients.Dps6, w.clients.Dps2, w.clients.Dps1, w.clients.Tank1
    local okA, why = fr.NS.Calls:CanAsk("REZ")
    ok(not okA and why == "you are alive", "a living mage cannot ask", why)
    ok(not rezBtn(fr):IsShown(), "and has no button on screen")
    local okH, whyH = h.NS.Calls:CanAsk("REZ")
    ok(not okH and string.find(whyH, "button", 1, true), "a healer has the button instead", whyH)
    w.dead = { Dps2 = true, Dps1 = true, Tank1 = true, Healer2 = true }
    w:Advance(1)
    ok(decision(h).target == "Healer2", "the rezzer goes first by default", tostring(decision(h).target))
    ok(rezBtn(py):IsShown() and rezBtn(t):IsShown(), "the dead mage and warrior now have the ask button on screen")
    ok(py.NS.Calls:CanAsk("REZ"), "a dead mage may ask")
    click(rezBtn(py))                              -- the mage's button is the ask
    w:Advance(1)
    ok(h.NS.Calls:For("Dps1", "REZ") ~= nil, "the priest's client has the call")
    ok(decision(h).target == "Dps1", "Dps1 goes to the front of the line - ahead of the shaman", tostring(decision(h).target))
    ok(rezBtn(h)._attrs["*macrotext1"] == "/stopcasting\n/cast [target=Dps1,nocombat] Resurrection", "and the priest's next click takes Dps1", rezBtn(h)._attrs["*macrotext1"])
    ok(rezBtn(py).sub:GetText() and string.find(rezBtn(py).sub:GetText(), "waiting", 1, true), "the mage's button says asked", rezBtn(py).sub:GetText())
    click(rezBtn(t)); w:Advance(1)
    ok(decision(h).target == "Dps1", "the warrior asks too: Dps1 still first, he asked first", tostring(decision(h).target))
    -- the priest takes Dps1; the shaman moves to the warrior
    click(rezBtn(h)); w:StartCast("Healer1", "Resurrection", "Dps1", 10); w:Advance(0.6)
    ok(decision(sh).target == "Tank1", "the shaman's button moves to the warrior - the other asker", tostring(decision(sh).target))
    w:CastRez("Healer1", "Dps1"); w.dead.Dps1 = nil; w:Advance(1)
    ok(h.NS.Calls:For("Dps1", "REZ") == nil and py.NS.Calls:Mine("REZ") == nil, "the rez landing closes the call everywhere")
    ok(not rezBtn(py):IsShown(), "and Dps1's button leaves the screen once he is up")
    ok(decision(h).target == "Tank1", "the priest moves on to the warrior")
    w.dead = {}
end

section("44b. the rez button is never there in a fight")
do
    local w = rezRaid()
    local h, m = w.clients.Healer1, w.clients.Kumlust
    w.hp = { Tank1 = 2000 }; w.hpmax = { Tank1 = 12000 }
    w:Advance(1)
    ok(rezBtn(h):IsShown() and decision(h).action == "heal", "a hurt warrior: the priest's button is on screen with a heal")
    ok(w.drivers[rezBtn(h)] == "[combat] hide; show", "and its driver says: not in combat", tostring(w.drivers[rezBtn(h)]))
    w:SetCombat(true)
    ok(not rezBtn(h):IsShown(), "the pull starts: the button is gone")
    w.dead = { Kumlust = true }
    w:Advance(2)
    ok(not rezBtn(h):IsShown() and rezBtn(h)._attrs["*macrotext1"] ~= "/stopcasting\n/cast [target=Kumlust,nocombat] Resurrection", "a death mid-fight changes nothing on screen or in the macro")
    ok(not rezBtn(m):IsShown(), "the dead mage's ask button stays hidden too")
    w:SetCombat(false); w:Advance(1)
    ok(rezBtn(h):IsShown() and rezBtn(h)._attrs["*macrotext1"] == "/stopcasting\n/cast [target=Kumlust,nocombat] Resurrection", "fight over: it is back, aimed at the corpse")
    ok(rezBtn(m):IsShown(), "and the dead mage's ask button is back")
    w.dead = {}; w.hp, w.hpmax = {}, {}
    w:Advance(1)
    ok(not rezBtn(h):IsShown() and not rezBtn(m):IsShown(), "everyone up and healthy: both gone again")
    -- one hurt: the smallest heal that covers; two hurt: the group heal
    local sh = w.clients.Healer2
    w.hp = { Tank1 = 11100 }; w.hpmax = { Tank1 = 12000 }
    w:Advance(1)
    ok(string.find(decision(sh).healSpell or "", "Lesser", 1, true), "one person 900 down: Lesser Healing Wave, the smallest that covers", tostring(decision(sh).healSpell))
    w.hp = { Tank1 = 6000 }
    w:Advance(1)
    ok(string.find(decision(sh).healSpell or "", "Healing Wave", 1, true) and not string.find(decision(sh).healSpell or "", "Lesser", 1, true), "6000 down: the big one", tostring(decision(sh).healSpell))
    w.hp = { Tank1 = 11000, Kumlust = 6000 }; w.hpmax = { Tank1 = 12000, Kumlust = 7000 }
    w:Advance(1)
    ok(string.find(decision(sh).healSpell or "", "Chain Heal", 1, true), "two hurt: Chain Heal", tostring(decision(sh).healSpell))
    w.hp, w.hpmax = {}, {}
end

section("44c. the drink option: any mana user, under 75%, out of combat")
do
    local w = rezRaid()
    local m, t, h = w.clients.Kumlust, w.clients.Tank1, w.clients.Healer1
    w.manaMax.Kumlust = 10000; w.mana.Kumlust = 5000
    w.bags.Kumlust = { 27860, 22018 }               -- draenic water and glacier water, no biscuit
    w:Advance(1)
    ok(not rezBtn(m):IsShown() and not m.NS.Rez:Active(), "off by default: the mage has no button")
    m.NS.Config:Set("rezDrinkLow", true)
    w:Advance(1)
    local d = decision(m)
    ok(m.NS.Rez:Active() and d.action == "drink" and d.lowMana, "on, at 50%: the button is a drink", tostring(d.action))
    ok(d.drinkId == 22018 and rezBtn(m)._attrs["*macrotext1"] == "/use [nocombat] 0 2", "glacier water beats draenic water", tostring(d.drinkId))
    ok(rezBtn(m):IsShown() and rezBtn(m).glow:IsShown() and rezBtn(m).anim:IsPlaying(), "on screen and blinking")
    w.bags.Kumlust = { 27860, 22018, 34062 }
    m.NS.Rez.last = nil; w:Advance(1)
    ok(decision(m).drinkId == 34062, "a biscuit beats both", tostring(decision(m).drinkId))
    w.mana.Kumlust = 8000; w:Advance(1)
    ok(decision(m).action == nil and not rezBtn(m):IsShown(), "at 80% it is gone")
    w.mana.Kumlust = 7000; w:Advance(1)
    ok(decision(m).action == "drink", "under 75% it is back")
    m.NS.Config:Set("rezDrinkAt", 60); w:Advance(1)
    ok(decision(m).action == nil, "the threshold is an option")
    m.NS.Config:Set("rezDrinkAt", 75)
    w.buffs.Kumlust = { { "Drink", 27089 } }; w:Advance(1)
    ok(decision(m).action == nil, "already drinking: nothing")
    w.buffs.Kumlust = nil
    -- in combat it is gone; dead it is the ask again
    w:SetCombat(true)
    ok(not rezBtn(m):IsShown(), "gone in combat")
    w:SetCombat(false); w:Advance(1)
    ok(rezBtn(m):IsShown() and decision(m).action == "drink", "back after")
    w.dead = { Kumlust = true }; w:Advance(1)
    ok(not m.NS.Rez:Active() and m.NS.Calls:CanAsk("REZ") and rezBtn(m):IsShown(), "dead: the button is 'rez me first' again")
    w.dead = {}; w:Advance(1)
    -- a warrior has no mana bar: never
    t.NS.Config:Set("rezDrinkLow", true); w:Advance(1)
    ok(not t.NS.Rez:Active() and not rezBtn(t):IsShown(), "a warrior never drinks")
    -- a healer with it on drinks too, once nothing needs a rez or a heal
    h.NS.Config:Set("rezDrinkLow", true)
    w.mana.Healer1 = 5000; w:Advance(1)
    ok(decision(h).action == "drink" and decision(h).lowMana, "a priest at 50% with nothing to do drinks", tostring(decision(h).action))
    w.dead = { Kumlust = true }; w:Advance(1)
    ok(decision(h).action == "rez", "a corpse still comes first")
    w.dead = {}; w.mana.Healer1 = 8000
end

section("44d. heal sizes: measured beats estimated, and the group heal downranks")
do
    local w = rezRaid()
    local sh = w.clients.Healer2
    w.book.Healer2 = {
        { "Ancestral Spirit", "Rank 5", 2008 },
        { "Lesser Healing Wave", "Rank 1", 8004, "Heals a friendly target for 170 to 200." },
        { "Lesser Healing Wave", "Rank 6", 25420, "Heals a friendly target for 892 to 1010." },
        { "Healing Wave", "Rank 11", 25357, "Heals a friendly target for 1919 to 2190." },
        { "Chain Heal", "Rank 1", 1064,  "Heals a friendly target for 320 to 370." },
        { "Chain Heal", "Rank 3", 10623, "Heals a friendly target for 605 to 690." },
        { "Chain Heal", "Rank 5", 25423, "Heals a friendly target for 1055 to 1205." },
    }
    w.spellLevel = { [8004] = 20, [25420] = 66, [25357] = 70, [1064] = 40, [10623] = 60, [25423] = 70 }
    w.bonusHealing.Healer2 = 2000
    sh.NS.Rez:BuildHealTable()
    local R = sh.NS.Rez
    ok(#R.heals == 3 and #R.groupHeals == 3, "three single ranks, three Chain Heal ranks", #R.heals .. "/" .. #R.groupHeals)
    local function byId(id) for _, l in ipairs({ R.heals, R.groupHeals }) do for _, e in ipairs(l) do if e.id == id then return e end end end end
    -- the downrank penalty: rank 1 LHW (level 20) gets (20+11)/70 of the coefficient
    local r1, r6 = byId(8004), byId(25420)
    local full = (185 + 2000 * (1.5 / 3.5))
    local pen  = (185 + 2000 * (1.5 / 3.5) * (31 / 70))
    ok(math.abs(r1.est - pen) < 1 and r1.est < full, "a rank learned 50 levels ago is penalised on healing power", tostring(r1.est))
    ok(math.abs(r6.est - (951 + 2000 * (1.5 / 3.5))) < 1, "a current rank is not", tostring(r6.est))
    -- two hurt, small holes: the smallest Chain Heal that covers, not max rank
    w.hp = { Tank1 = 11300, Kumlust = 6500 }; w.hpmax = { Tank1 = 12000, Kumlust = 7000 }
    w:Advance(1)
    local d = decision(sh)
    ok(d.action == "heal" and d.healSpell == "Chain Heal(Rank 1)", "two people ~600 down: Chain Heal rank 1", tostring(d.healSpell))
    w.hp = { Tank1 = 9000, Kumlust = 6500 }
    w:Advance(1)
    ok(decision(sh).healSpell == "Chain Heal(Rank 5)", "one of them 3000 down: rank 5", tostring(decision(sh).healSpell))
    -- measurement: my own casts in the combat log
    local estR6 = r6.heal
    w:Heal2("Healer2", "Tank1", 25420, "Lesser Healing Wave", 1500, 0, true)     -- a crit
    ok(byId(25420).measured == nil, "a crit is thrown out")
    w:Advance(2)
    w:Heal2("Healer2", "Tank1", 25420, "Lesser Healing Wave", 1500, 900, false)  -- mostly overheal
    ok(byId(25420).measured == nil, "a cast that was mostly overheal is thrown out")
    w:Advance(2)
    w:Heal2("Healer2", "Tank1", 25420, "Lesser Healing Wave", 2400, 100, false)
    ok(byId(25420).measured == 2400 and byId(25420).heal == 2400, "a clean cast measures the rank", tostring(byId(25420).heal))
    ok(sh.NS.db.rezHealSizes[25420].n == 1, "and is saved")
    local cal = 2400 / estR6
    ok(math.abs(byId(25357).heal - byId(25357).est * cal) < 1, "the unmeasured rank is scaled by the same factor", tostring(byId(25357).heal))
    -- a chain's bounces do not count: only the first heal of a cast
    w:Advance(2)
    w:Heal2("Healer2", "Tank1", 25423, "Chain Heal", 2800, 0, false)
    w:Heal2("Healer2", "Kumlust", 25423, "Chain Heal", 1400, 0, false)
    ok(byId(25423).measured == 2800, "only the first target of a chain measures it", tostring(byId(25423).measured))
    -- a running average, and the picker uses the measured sizes
    w:Advance(2)
    w:Heal2("Healer2", "Tank1", 25420, "Lesser Healing Wave", 2600, 0, false)
    ok(byId(25420).measured == 2500, "two casts average", tostring(byId(25420).measured))
    w.hp = { Tank1 = 9700 }; w.hpmax = { Tank1 = 12000 }
    w:Advance(1)
    ok(decision(sh).healSpell == "Lesser Healing Wave(Rank 6)", "a 2300 hole now fits the measured LHW instead of Healing Wave", tostring(decision(sh).healSpell))
    slash(sh, "rezsizes")
    ok(byId(25420).measured == nil and next(sh.NS.db.rezHealSizes) == nil, "/inn rezsizes forgets the measurements")
    w.hp, w.hpmax = {}, {}
end

section("44e. a druid in bear or cat form cannot innervate, and everyone knows")
do
    local w = raid(BASE)
    local m, a, b = w.clients.Kumlust, w.clients.Healer3, w.clients.Healer4
    ok(m.NS.Calls:CanAsk("INNERVATE") and m.NS.Tracker:DruidsReady() == 2, "two druids up")
    w.form = { Healer3 = 1 }                             -- Healer3 goes bear
    w:Fire("Healer3", "UPDATE_SHAPESHIFT_FORM"); w:Advance(1)
    ok(m.NS.Tracker.providers.INNERVATE.Healer3.shifted == true, "the mage's client hears Healer3 is in a form")
    ok(m.NS.Tracker:DruidsReady() == 1 and m.NS.Calls:CanAsk("INNERVATE"), "one druid left to ask")
    -- Healer3's own grid greys
    a.NS.Window:DoRefresh()
    ok(face(a, "Kumlust"):GetAlpha() == 0.3, "on Healer3's screen the faces grey out", face(a, "Kumlust"):GetAlpha())
    ok(face(b, "Kumlust"):GetAlpha() ~= 0.3, "Healer4's do not")
    -- both in form: the ask greys with the reason
    w.form.Healer4 = 3
    w:Fire("Healer4", "UPDATE_SHAPESHIFT_FORM"); w:Advance(1)
    local okA, why = m.NS.Calls:CanAsk("INNERVATE")
    ok(not okA and string.find(why, "bear or cat", 1, true), "both in form: the mage cannot ask, and is told why", why)
    m.NS.Window:DoRefresh()
    ok(m.NS.Window.inn.icon:GetAlpha() < 1, "the innervate button is greyed")
    -- Healer3 shifts out: back
    w.form.Healer3 = nil
    w:Fire("Healer3", "UPDATE_SHAPESHIFT_FORM"); w:Advance(1)
    ok(m.NS.Calls:CanAsk("INNERVATE") and m.NS.Tracker:DruidsReady() == 1, "Healer3 leaves the form: askable again")
    a.NS.Window:DoRefresh()
    ok(face(a, "Kumlust"):GetAlpha() ~= 0.3, "and his grid is live again")
    -- it survives a HELLO round (the flag rides the kinds blob)
    b.NS.Comm:Hello(); w:Advance(3)
    ok(m.NS.Tracker.providers.INNERVATE.Healer4.shifted == true, "Healer4's HELLO still says in a form")
    w.form = nil
end

section("44f. healer mode: the rez button and nothing else")
do
    local w = rezRaid()
    local h = w.clients.Healer1
    local W, f = h.NS.Window, h.NS.Window.frame
    local function shownBtns() local n = 0; for _, b in pairs(W.buttons) do if b:IsShown() then n = n + 1 end end; return n end
    local function faces() local n = 0; for _ in pairs(W.byName) do n = n + 1 end; return n end
    ok(faces() == 4 and shownBtns() == 4, "everyone: four faces, four buttons (rez off screen, nothing to do)")
    click(W.healerBtn)
    ok(h.env.BiSInnervateDB.healerOnly == true and W.healerBtn.lit == true, "H turns healer mode on")
    ok(faces() == 0 and shownBtns() == 0, "no faces, no ask buttons")
    ok(f:GetWidth() == math.max(W.PAD * 2 + W.BTN_H, W.MINW_MAGES) and f:GetHeight() == W.HEADER + W.PAD + W.BTN_H + W.PAD,
       "the window is one button wide and one button tall", f:GetWidth() .. "x" .. f:GetHeight())
    ok(not W.cfgBtn:IsShown() and not W.title:IsShown(), "title and cfg leave the bar")
    -- the bar: H, M, x from the right - H must clear the left edge
    local _, _, _, hx = W.healerBtn:GetPoint()
    ok(W.logo == nil and f:GetWidth() + hx - 12 >= 4, "no logo (the prompt is the brand) and H clears the edge", f:GetWidth() + hx - 12)
    -- something to do: the rez button appears, in the first slot
    w.dead = { Kumlust = true }; w:Advance(1)
    ok(rezBtn(h):IsShown() and shownBtns() == 1, "a corpse: the rez button is the only thing on screen")
    local _, _, _, rx = rezBtn(h):GetPoint()
    ok(rx == W.PAD, "sitting where the first button would", rx)
    ok(rezBtn(h)._attrs["*macrotext1"] == "/stopcasting\n/cast [target=Kumlust,nocombat] Resurrection", "and aimed at the corpse")
    w.dead = {}; w:Advance(1)
    ok(shownBtns() == 0, "corpse up: gone again")
    -- mutually exclusive with mages-only
    click(W.magesBtn)
    ok(h.env.BiSInnervateDB.magesOnly == true and h.env.BiSInnervateDB.healerOnly == false, "M turns healer mode off")
    click(W.healerBtn)
    ok(h.env.BiSInnervateDB.healerOnly == true and h.env.BiSInnervateDB.magesOnly == false, "H turns mages-only off")
    -- mid-fight it waits
    w:SetCombat(true)
    click(W.healerBtn)
    ok(h.env.BiSInnervateDB.healerOnly == false and faces() == 0, "off mid-fight: saved, but the window did not move")
    w:SetCombat(false); w:Advance(1)
    ok(faces() == 4 and shownBtns() == 4 and f:GetWidth() == W.width, "fight over: everyone is back")
    -- the option and the slash write the same key
    h.NS.Config:Set("healerOnly", true)
    ok(h.NS.Config:Get("healerOnly") == true and faces() == 0, "options tick: same thing")
    slash(h, "healer")
    ok(h.NS.Config:Get("healerOnly") == false and faces() == 4, "/inn healer: off again")
    local _, _, _, rx2 = rezBtn(h):GetPoint()
    ok(rx2 == W.PAD + 4 * (W.BTN_H + W.GAP), "and the rez button is back in the fifth slot", rx2)
end

section("45. wipe protection")
do
    local w = rezRaid({ { "Healer6", "PALADIN", true, 2 } })
    local sh, m = w.clients.Healer2, w.clients.Kumlust
    ok(sh.NS.Rez:MyWipeProtection() == "", "a shaman with no Ankh has none")
    w.bags.Healer2 = { 17030 }
    ok(sh.NS.Rez:MyWipeProtection() == "R", "Reincarnation with an Ankh counts", sh.NS.Rez:MyWipeProtection())
    w.cd["Healer2#Reincarnation"] = w.time + 1800
    ok(sh.NS.Rez:MyWipeProtection() == "", "on cooldown it does not")
    w.cd["Healer2#Reincarnation"] = nil
    w.buffs.Healer2 = { { "Soulstone Resurrection", 27239 } }
    ok(sh.NS.Rez:MyWipeProtection() == "RS", "a soulstone on a rezzer counts too", sh.NS.Rez:MyWipeProtection())
    w.buffs.Kumlust = { { "Soulstone Resurrection", 27239 } }
    ok(m.NS.Rez:MyWipeProtection() == "", "a soulstone on a mage does not")
    -- over the wire, in the HELLO blob
    sh.NS.Comm:Hello(); w:Advance(1)
    local hp = w.clients.Healer6
    ok(hp.NS.Rez:MyWipeProtection() == "D", "a paladin brings Divine Intervention", hp.NS.Rez:MyWipeProtection())
    local n, detail = m.NS.Rez:WipeProtection()
    ok(n == 3, "the mage's client counts the shaman's two and the paladin's one", n)
    ok(detail[1].what == "Divine Intervention" and detail[2].what == "Reincarnation" and detail[2].name == "Healer2", "and names them", detail[1].what)
    w.buffs.Healer2 = nil
    sh.NS.Comm:Hello(); w:Advance(1)
    ok(m.NS.Rez:WipeProtection() == 2, "and drops one when the stone is gone", m.NS.Rez:WipeProtection())
    -- a HELLO with a kind this client does not know is harmless
    w:Deliver("Healer1", "Kumlust", "4|HELLO|9.9.9|REZ,FOO=X|0,0|70|2|6")
    ok(m.NS.Tracker.providers.REZ.Healer1 ~= nil and m.NS.Tracker.providers.FOO == nil, "an unknown kind in a HELLO is ignored, the known one lands")
end

section("46. the rez section of the options window")
do
    local w = rezRaid()
    local c = w.clients.Healer1
    local C, db = c.NS.Config, c.env.BiSInnervateDB
    ok(pcall(function() C:Build(); C:Refresh() end), "it builds and refreshes")
    for _, id in ipairs({ "rez", "rezHeal", "rezDrink", "rezKeepScores" }) do
        local was = C:Get(id)
        C:Set(id, false); local off = C:Get(id) == false
        C:Set(id, true);  local on  = C:Get(id) == true
        C:Set(id, was)
        ok(off and on, id .. " round-trips through the saved variable")
    end
    C:Set("rez", false)
    ok(db.rez == false and not c.NS.Rez:Enabled() and rezBtn(c)._attrs["*type1"] == nil, "switching the button off unwires it")
    C:Set("rez", true)
    ok(rezBtn(c)._attrs["*type1"] == "macro", "and on wires it again")
    ok(C.byKey.rezRescan.kind == "button", "rebuild is a button")
    ok(pcall(function() C:Run("rezRescan") end), "and runs")
    ok(C.byKey.rezRescan.label:find("all ranks", 1, true), "its label carries the show-all-ranks reminder", C.byKey.rezRescan.label)
    -- the scoreboard and the lists moved to chat: they were text, not controls
    ok(C.byKey.rezScore == nil and C.byKey.rezReset == nil, "print / clear scoreboard are /inn rezscore, rezreset")
end

section("47. an override keybind, stored and re-applied")
do
    local w = rezRaid()
    local c = w.clients.Healer1
    slash(c, "bind alt-r")
    ok(w.binds.Healer1 and w.binds.Healer1["ALT-R"] == "BiSInnervateREZButton", "bound as an override, to the button", tostring(w.binds.Healer1 and w.binds.Healer1["ALT-R"]))
    ok(c.env.BiSInnervateDB.rezBindKey == "ALT-R", "and remembered")
    w.binds.Healer1 = {}
    local w2 = raid(BASE, { Healer1 = c.env.BiSInnervateDB })
    ok(w2.binds.Healer1 and w2.binds.Healer1["ALT-R"] ~= nil, "re-applied after a reload")
    slash(c, "unbind")
    ok(next(w.binds.Healer1) == nil and c.env.BiSInnervateDB.rezBindKey == nil, "unbind clears both")
    w:SetCombat(true)
    slash(c, "bind alt-r")
    ok(c.env.BiSInnervateDB.rezBindKey == nil, "not in combat")
    w:SetCombat(false)
end

section("48. the rez wire is defended")
do
    local w = rezRaid()
    local h, sh = w.clients.Healer1, w.clients.Healer2
    w.dead = { Kumlust = true }
    w:Advance(1)
    w:Deliver("Dps7", "Healer1", "4|RCLAIM|Kumlust", "WHISPER")
    ok(h.NS.Rez:ClaimedBy("Kumlust") == nil, "a whispered claim from outside is ignored")
    w:Deliver("Nobody", "Healer1", "4|RCLAIM|Kumlust")
    ok(h.NS.Rez:ClaimedBy("Kumlust") == nil, "a claim from a non-member is ignored")
    w:Deliver("Healer2", "Healer1", "4|RCLAIM|Kumlust")
    ok(h.NS.Rez:ClaimedBy("Kumlust") == "Healer2", "a member's claim is honoured")
    w:Deliver("Dps6", "Healer1", "4|RFREE|Kumlust")
    ok(h.NS.Rez:ClaimedBy("Kumlust") == "Healer2", "only the claimant can free it")
    w:Deliver("Healer2", "Healer1", "4|RFREE|Kumlust")
    ok(h.NS.Rez:ClaimedBy("Kumlust") == nil, "and does")
    w:Deliver("Healer2", "Healer1", "3|RCLAIM|Kumlust")
    ok(h.NS.Rez:ClaimedBy("Kumlust") == nil, "another protocol is dropped")
    -- a red error right after our click frees the corpse we aimed at
    click(rezBtn(h)); w:StartCast("Healer1", "Resurrection", "Kumlust", 10); w:Advance(0.3)
    ok(sh.NS.Rez:ClaimedBy("Kumlust") == "Healer1", "claimed")
    w:Fire("Healer1", "UI_ERROR_MESSAGE", 1, "You are already in a party")
    ok(sh.NS.Rez:ClaimedBy("Kumlust") == "Healer1", "an unrelated red error is not blamed on the cast")
    w.casting.Healer1 = nil                        -- the cast never happened
    w:Fire("Healer1", "UI_ERROR_MESSAGE", 1, "Out of range.")
    w:Advance(0.3)
    ok(sh.NS.Rez:ClaimedBy("Kumlust") == nil, "a real cast error frees it")
    ok(string.find(h.prints[#h.prints] or "", "Out of range", 1, true) ~= nil, "and is reported once", h.prints[#h.prints])
    local n = #h.prints
    w:Advance(5)
    w:Fire("Healer1", "UI_ERROR_MESSAGE", 1, "Out of range.")
    ok(#h.prints == n, "an error long after the click is not")
    w.dead = {}
end

section("49. the scoreboard is per raid, and the slash commands print")
do
    local w = rezRaid()
    local h = w.clients.Healer1
    w.dead = { Kumlust = true }
    w:CastRez("Healer1", "Kumlust"); w.dead = {}
    w:CastRez("Healer1", "Tank1")
    ok(h.NS.db.rezScores.Healer1 == 2, "two rezzes, two points", tostring(h.NS.db.rezScores.Healer1))
    ok(h.NS.Rez:ChampionText() == "Healer1 2", "the champion", tostring(h.NS.Rez:ChampionText()))
    slash(h, "rezscore")
    ok(string.find(h.prints[#h.prints] or "", "Healer1", 1, true) ~= nil, "/inn rezscore prints it")
    -- a zone-in blip does not clear it; leaving for real does
    w.blip = true
    w:FireAll("GROUP_ROSTER_UPDATE"); w:Advance(1)
    ok(h.NS.db.rezScores.Healer1 == 2, "a zone-in blip keeps the board")
    w:Advance(11); w:FireAll("GROUP_ROSTER_UPDATE"); w:Advance(1)
    ok(next(h.NS.db.rezScores) == nil, "ten seconds of nobody clears it")
    w.blip = false
    slash(h, "rezzers"); slash(h, "rezlist"); slash(h, "heals"); slash(h, "rez")
    ok(#h.prints > 4, "the rez slash commands print")
end

section("50. a raider still on 3.2.0 sees everything but the rez")
do
    local w = H.NewWorld(".")
    w.rootFor = { Oldie = "./dev/old-3.2" }
    for _, p in ipairs(BASE) do w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6]); if p[4] then w.mana[p[1]] = p[4] end end
    w:AddPlayer("Oldie", "MAGE", true, 2)
    w.manaMax = { Healer1 = 10000, Healer2 = 10000 }; w.mana.Healer1, w.mana.Healer2 = 8000, 8000
    w.bags.Healer2 = { 17030 }
    w:Login(); w:Advance(4)
    local o, h = w.clients.Oldie, w.clients.Healer1
    ok(o.NS.VERSION == "3.2.0" and o.NS.Rez == nil, "the old client is really 3.2.0")
    ok(o.NS.PROTOCOL == 4 and h.NS.PROTOCOL == 4, "same protocol: nobody is told to update")
    ok(o.NS.Tracker:TideFor("Kumlust") ~= nil and o.NS.Tracker:HasDruid(), "it learned the tide shaman and the druids from the new HELLOs")
    ok(o.NS.Tracker.providers.REZ == nil, "and simply does not know REZ")
    local n = 0
    for _ in pairs(o.NS.Window.byName) do n = n + 1 end
    ok(n == 7, "its grid has every mana user, the new clients included", n)
    ok(face(h, "Oldie") ~= nil and h.NS.Tracker:Available("REZ")[1] ~= nil, "and the new clients have it on theirs")
    -- rez traffic goes past it without a word
    w.dead = { Kumlust = true }
    w:Advance(1)
    local before = #o.prints
    click(rezBtn(h)); w:StartCast("Healer1", "Resurrection", "Kumlust", 10); w:Advance(0.6)
    w:StopCast("Healer1", "UNIT_SPELLCAST_INTERRUPTED"); w:Advance(0.6)
    w:CastRez("Healer2", "Kumlust"); w.dead = {}
    slash(w.clients.Tank1, "rez")
    ok(#o.prints == before, "RCLAIM, RFREE, RDONE and a REZ ask print nothing on the old client")
    ok(not o.NS.Comm._warnedProto and not o.NS.Comm._warnedOld, "and raise no protocol warning")
    -- and the old client's calls still work on the new ones
    slash(o, ""); w:Advance(1)
    ok(pulsing(face(w.clients.Healer3, "Oldie")), "its innervate call pulses on a 3.3 druid's screen")
end

section("51. the options window is the kit's shape, and the layout checker still has teeth")
do
    local w = rezRaid()
    local sh = w.clients.Healer2
    local C = sh.NS.Config
    C:Build(); C:Refresh()
    local f = C.frame
    local O = sh.env.BiSTheme.OPTIONS
    -- no row runs under its control: label right edge <= W - CTL
    local bad = {}
    for _, r in ipairs(f.rows) do
        local x = r.isSection and 6 or O.INDENT
        if x + r.name:GetStringWidth() > O.W - O.CTL then bad[#bad + 1] = tostring(r.name:GetText()) end
    end
    ok(#bad == 0, "no label reaches its control", table.concat(bad, " | "))
    -- every step value fits between < and >
    for _, r in ipairs(f.rows) do
        if r.opt and r.opt.kind == "step" then
            ok(r.ctl.val:GetStringWidth() <= O.STEP_V, "step value fits: " .. r.opt.label, r.ctl.val:GetText())
        end
    end
    -- the check itself has teeth: a label made too long is caught
    local page = sh.NS.Window.frame
    local long = sh.env.CreateFrame("Frame", nil, page)
    long:SetSize(100, 20); long:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -5)
    local t = long:CreateFontString(); t:SetFont("Fonts\\FRIZQT__.TTF", 12); t:SetPoint("LEFT", long, "LEFT", 0, 0)
    t:SetText(string.rep("wide ", 40))
    local problems = H.CheckLayout(long, page)
    ok(#problems > 0, "a too-wide label and an overlapping frame are reported", #problems)
    long:Hide(); t:Hide()
end

section("52. the title is the BiS> prompt: slots, events, the fade, the hit strip")
do
    local w = rezRaid()
    local m = w.clients.Kumlust
    local W = m.NS.Window
    local con = W.con
    -- druids are off the grid: mages and healers only
    local classes = {}
    for _, f in ipairs(W.faces or {}) do if f.class then classes[f.class] = true end end
    ok(not classes.DRUID, "no druid face on the grid")
    local list = W:OnlineList()
    local withAddon = 0
    for _, e in ipairs(list) do if m.NS.Comm:HasAddon(e.name) then withAddon = withAddon + 1 end end
    ok(#list > 1 and withAddon == #list, "the online list is everyone with the addon, me included", #list, withAddon)
    ok(list[1].name == "Kumlust", "and I am first", list[1].name)
    -- the console is the real embedded one, loaded the TOC way (not a fallback)
    ok(con ~= nil and m.env.BiSTheme and m.env.BiSTheme.CONSOLE_MINOR == 4, "the header carries the BiS> console, Console.lua minor 4 (cursor is its own FontString)", m.env.BiSTheme and m.env.BiSTheme.CONSOLE_MINOR)
    ok(W.title:GetText() == m.NS.T.text("accent", "BiS> "), "the title itself is the prompt", W.title:GetText())
    -- the accent is read from the theme per call, never captured: under
    -- dev/theme.lua the wrong-on-purpose accent must show through everywhere
    local want = H.THEME_PASS or "b980ff"
    ok(m.NS.T.text("accent", "x") == "|cff" .. want .. "x|r", "NS.T reads the live palette (" .. want .. ")", m.NS.T.text("accent", "x"))
    ok(W.title:GetText():find(want, 1, true) ~= nil, "and the prompt wears it", W.title:GetText())
    local r = m.NS.T.rgb("accent")
    ok(math.abs(r - tonumber(want:sub(1, 2), 16) / 255) < 0.001, "rgb too", r)
    ok(W.logo == nil, "no logo: the prompt is the brand")
    local function shown() return (tostring(con:Text()):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function tick(n) for _ = 1, n do w.time = w.time + 0.05; W:TickTitle() end end
    ok(con.slots.name and con.slots.name.text == "Innervate" and con.slots.name.colour == "accent", "slot one is the name, in the accent")
    tick(1)
    ok(con.slots.online and con.slots.online.text == (#list .. " online") and con.slots.online.colour == "good", "the online count is a green slot", con.slots.online and con.slots.online.text)
    -- the slots rotate: name, then the count, with a fade between (>=3 mid frames)
    tick(6)
    ok(shown():find("Innervate", 1, true), "the name shows first", shown())
    local mid = 0
    for _ = 1, 80 do
        w.time = w.time + 0.05; W:TickTitle()
        local a = con.words:GetAlpha()
        if a > 0 and a < 1 then mid = mid + 1 end
    end
    ok(mid >= 3, "the words fade between slots, not a hard cut", mid)
    ok(shown():find("online", 1, true), "and the count is up after the cycle", shown())
    -- the action slot: what the window is doing, plain words coloured by meaning
    W._actionShown = nil
    m.NS.Rez.last = { action = "heal", target = "Dps10", targetClass = "MAGE" }
    local oldActive = m.NS.Rez.Active
    m.NS.Rez.Active = function() return true end
    W:PaintTitle()
    ok(con.slots.action and con.slots.action.text == "heal Dps10" and con.slots.action.colour == "gold", "a heal is a gold action slot", con.slots.action and con.slots.action.text)
    ok(not con.slots.action.text:find("|c", 1, true), "plain words: the trim never cuts a colour escape")
    m.NS.Rez.Active = oldActive; m.NS.Rez.last = nil; W:PaintTitle()
    ok(con.slots.action == nil, "nothing to do clears the action slot")
    -- an event jumps in over the slots, holds, then the rotation resumes
    W:Say("drums: War", "gold")
    tick(8)
    ok(shown():find("drums: War", 1, true), "a Say jumps into the prompt", shown())
    w.time = w.time + 4; tick(8)
    ok(not shown():find("drums", 1, true), "and leaves after the hold", shown())
    -- the header budget: the prompt never runs under H
    W:Say("Averyveryverylongname needs a very long heal", "ink2")
    tick(8)
    ok(con:Width() <= con.width, "a long line is trimmed to the budget", con:Width(), con.width)
    ok(shown():find("%.%.%."), "with an ellipsis", shown())
    -- the budget arithmetic: prompt start + budget + air <= H's left edge
    local _, _, _, hx = W.healerBtn:GetPoint()
    ok(4 + W.TITLE_W + 3 <= W.width + hx - 12, "the budget clears H", 4 + W.TITLE_W + 3, W.width + hx - 12)
    w.time = w.time + 4; tick(8)
    -- the hit strip keeps the title's interactions: hover list, shift-click, drag
    ok(W.onlineBtn and W.onlineBtn:IsShown(), "the hover strip over the prompt is there")
    local printed = {}
    local oldPrint = m.NS.Print
    m.NS.Print = function(msg) printed[#printed + 1] = msg end
    w.shift = false; W.onlineBtn:GetScript("OnClick")(W.onlineBtn)
    ok(#printed == 0, "a plain click on the title prints nothing", printed[1])
    w.shift = true;  W.onlineBtn:GetScript("OnClick")(W.onlineBtn)
    ok(#printed == 1 and string.find(printed[1] or "", "with the addon", 1, true) ~= nil, "shift-click prints the list", printed[1])
    w.shift = false; m.NS.Print = oldPrint
    ok(W.onlineBtn:GetScript("OnDragStart") ~= nil, "and it hands a drag to the window")
    local tipLines = {}
    m.env.GameTooltip.AddLine = function(_, line) tipLines[#tipLines + 1] = line end
    W.onlineBtn:GetScript("OnEnter")(W.onlineBtn)
    local named = 0
    for _, l in ipairs(tipLines) do for _, e in ipairs(list) do if tostring(l):find(e.name, 1, true) then named = named + 1 end end end
    ok(named == #list, "the tooltip lists everyone online", named, #list)
    -- ticking in a fight touches text and alpha only: no secure write
    w:SetCombat(true)
    local okc = pcall(function() tick(4) end)
    ok(okc, "ticking in combat is safe")
    w:SetCombat(false)
    -- compact modes take the prompt off the bar and Say falls back to chat
    W:SetHealerOnly(true)
    ok(not W.title:IsShown() and not con.words:IsShown(), "Neb mode hides the prompt and its words")
    printed = {}; m.NS.Print = function(msg) printed[#printed + 1] = msg end
    W:Say("hello", "muted")
    ok(printed[1] == "hello", "a Say with no prompt on screen goes to chat", printed[1])
    m.NS.Print = oldPrint
    W:SetHealerOnly(false)
    ok(W.title:IsShown() and con.words:IsShown(), "back in the full window the prompt returns")
end

section("53. spec on the grid, and the mode a class starts in")
do
    -- Healer1 went shadow (tab 3), Healer2 is resto (tab 3), Dps6 is
    -- enhance (tab 2), Healer6 is holy (tab 1)
    local w = H.NewWorld(".")
    for _, p in ipairs(BASE) do w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6]); if p[4] then w.mana[p[1]] = p[4] end end
    w:AddPlayer("Healer6", "PALADIN", true, 2)
    w:AddPlayer("Retpal",  "PALADIN", true, 2)
    w.tabs = { Healer1 = { 0, 0, 41 }, Healer2 = { 0, 0, 41 }, Dps6 = { 0, 41, 20 },
               Healer6 = { 41, 0, 20 }, Retpal = { 0, 0, 61 } }
    w:Login(); w:Advance(4)
    local m = w.clients.Kumlust
    local names = {}
    for name in pairs(m.NS.Window.byName) do names[#names + 1] = name end
    table.sort(names)
    ok(table.concat(names, ",") == "Healer2,Healer6,Kumlust",
       "only the healing-tree priests, paladins and shamans get a face (the mage too)", table.concat(names, ","))
    ok(m.NS.Tracker.providers.REZ.Healer1 and m.NS.Tracker.providers.REZ.Healer1.dpsSpec == true, "the shadow priest's blob says X")
    ok(m.NS.Tracker.providers.REZ.Healer2 and not m.NS.Tracker.providers.REZ.Healer2.dpsSpec, "the resto shaman's does not")
    -- the wipe count does not count the spec letters
    local n, detail = m.NS.Rez:WipeProtection()
    local stray = false
    for _, e in ipairs(detail or {}) do if e.what == "H" or e.what == "X" then stray = true end end
    ok(not stray and n == #(detail or {}), "H and X are not wipe protection", n)
    -- the modes nobody chose: the healers start in Neb mode, the druids in
    -- Odiss mode, the dps in the full window
    local function mode(c)
        local db = c.env.BiSInnervateDB
        return db.healerOnly and "neb" or (db.magesOnly and "odiss" or "main")
    end
    ok(mode(w.clients.Healer2) == "main", "the tide shaman keeps the full window (a tide to hand out)", mode(w.clients.Healer2))
    ok(mode(w.clients.Healer6) == "neb", "the holy paladin starts in Neb mode", mode(w.clients.Healer6))
    ok(mode(w.clients.Healer1) == "main", "the shadow priest gets the full window", mode(w.clients.Healer1))
    ok(mode(w.clients.Retpal) == "main", "so does the ret paladin", mode(w.clients.Retpal))
    ok(mode(w.clients.Healer3) == "odiss", "a druid starts in Odiss mode", mode(w.clients.Healer3))
    ok(mode(w.clients.Kumlust) == "main", "a mage in the full window", mode(w.clients.Kumlust))
    ok(not w.clients.Healer6.env.BiSInnervateDB.modeSet, "and nothing is pinned yet")
    -- the paladin turns it off: pinned, and a respec no longer moves it
    local hp = w.clients.Healer6
    hp.NS.Window:SetHealerOnly(false)
    ok(hp.env.BiSInnervateDB.modeSet == true and mode(hp) == "main", "H pins the choice", mode(hp))
    hp.NS.Window:DefaultMode()
    ok(mode(hp) == "main", "the default never runs again once pinned", mode(hp))
    -- the shadow priest respecs holy: their blob flips and the mage's grid grows
    w.tabs.Healer1 = { 0, 41, 20 }
    w:Fire("Healer1", "PLAYER_TALENT_UPDATE"); w:Advance(1)
    ok(m.NS.Window.byName.Healer1 ~= nil, "a respec to holy puts the priest on the grid")
    ok(mode(w.clients.Healer1) == "neb", "and, never having chosen, they land in Neb mode", mode(w.clients.Healer1))
    -- a druid with drums in the bag keeps the full window (drums to hand out)
    local w2 = H.NewWorld(".")
    w2:AddPlayer("Healer3", "DRUID", true, 1); w2:AddPlayer("Kumlust", "MAGE", true, 1)
    w2.drums = { Healer3 = 29529 }
    w2:Login(); w2:Advance(4)
    ok(mode(w2.clients.Healer3) == "main", "a druid with drums starts in the full window", mode(w2.clients.Healer3))
    -- no talent API at all (the 3.2 harness world): nobody is hidden
    ok(m.NS.MyHealerSpec() == nil, "a mage has no spec to read")
end

section("54. the shared BiS channel rides alongside, and nothing here can gate it")
do
    local w = rezRaid()
    local m = w.clients.Kumlust
    local lib = m.env.LibBiSComm
    ok(lib ~= nil and lib.MINOR == 8, "LibBiSComm is embedded, minor 8", lib and lib.MINOR)
    ok(lib._booted == true, "it boots from PLAYER_LOGIN")
    local tocVer = m.env.GetAddOnMetadata("BiSInnervate", "Version")
    ok(lib.addons and lib.addons.BiSInnervate == tocVer, "the addon is registered with the TOC's version, not a literal", lib.addons and lib.addons.BiSInnervate, tocVer)
    ok(m.NS.VERSION == tocVer, "and NS.VERSION is that same number", m.NS.VERSION)
    -- two pipes, disjoint: the lib's BiS / proto 1 next to Innervate's BiSInn / proto 4
    ok(lib.PREFIX == "BiS" and m.NS.PREFIX == "BiSInn" and lib.PROTO == 1 and m.NS.PROTOCOL == 4, "the prefixes and protocols are disjoint", lib.PREFIX, m.NS.PREFIX)
    ok(m.env.SLASH_BISCOMM1 == "/biscomm" and m.env.SLASH_BISINNERVATE1 ~= "/biscomm", "/biscomm is the lib's (never /bis: that is LoonBestInSlot's), /inn stays Innervate's", m.env.SLASH_BISCOMM1)
    -- the lib is not inert: every client said HI on the BiS pipe at login,
    -- and Innervate's own HELLO traffic is still there beside it
    local his, hellos = 0, 0
    for _, msg in ipairs(w.addonMsgs) do
        if msg.msg:find("^1|CORE|HI|") then his = his + 1 end
        if msg.msg:find("^4|HELLO|") then hellos = hellos + 1 end
    end
    ok(his > 0, "HI went out on the shared pipe", his)
    ok(hellos > 0, "and Innervate's HELLO still went out on its own", hellos)
    -- peers: another Innervate client is a lib peer, from the lib's own HI, not from BiSInn
    ok(lib:Peer("Healer1") ~= nil, "a raider with the addon is a lib peer", lib:Count())
    ok(lib:Peer("Kumlust") == nil, "my own echo is not (minor 3)")
    -- the wire is not confused: a BiS-pipe line never reaches Innervate's handlers
    local before = m.NS.Comm.users.Nobody
    w:Fire("Kumlust", "CHAT_MSG_ADDON", "BiS", "1|CORE|HI|3||0", "RAID", "Healer1")
    ok(m.NS.Comm.users.Nobody == before, "a BiS line is not parsed by Innervate's Comm")
    -- the off switch lives in BiSInnervateDB.comm; the lib obeys it and it survives a logout
    lib:SetEnabled(true)
    m.env.BiSInnervateDB.comm = false
    m.NS.Shared.Boot()
    ok(not lib:Enabled(), "BiSInnervateDB.comm=false boots the channel silent and deaf")
    lib:SetEnabled(true)
    w:Fire("Kumlust", "PLAYER_LOGOUT")
    ok(m.env.BiSInnervateDB.comm == true, "PLAYER_LOGOUT writes the live switch back for next login", m.env.BiSInnervateDB.comm)
    -- NO Innervate setting may gate the channel: flip every toggle and the lib stays on
    lib:SetEnabled(true)
    local gatedBy
    for _, cmd in ipairs({ "mages", "healer", "sound", "minimap", "faces", "lock", "hide", "debug", "rez", "set healerOnly", "set magesOnly" }) do
        slash(m, cmd)
        if not lib:Enabled() then gatedBy = gatedBy or cmd end
        slash(m, cmd)
        lib:SetEnabled(true)            -- reset so one probe cannot mask the next
    end
    for _, key in ipairs({ "rez", "rezHeal", "rezDrink", "healerOnly", "magesOnly", "sound", "minimap", "hidden" }) do
        m.env.BiSInnervateDB[key] = false
        m.NS.Shared.Boot()
        if not lib:Enabled() then gatedBy = gatedBy or ("db." .. key) end
        lib:SetEnabled(true)
    end
    ok(gatedBy == nil, "no feature toggle touches the shared channel", gatedBy)
    slash(m, "reset")
    -- the summon events the lib registers are none of Innervate's (no collision)
    local innervateFrames = 0
    for _, fr in ipairs(m.frames) do
        if fr._events and fr._events.CONFIRM_SUMMON and fr ~= lib._frame then innervateFrames = innervateFrames + 1 end
    end
    ok(innervateFrames == 0, "only the lib listens for CONFIRM_SUMMON")
end

section("17. hygiene")
do
    local w = raid(BASE)
    local allow = { BiSInnervateDB = true, SLASH_BISINNERVATE1 = true, SLASH_BISINNERVATE2 = true, SLASH_BISINNERVATE3 = true,
                    BiSTheme = true,          -- the embedded Console.lua installs the theme handle on purpose
                    LibBiSComm = true, SLASH_BISCOMM1 = true }   -- the shared channel's guard global and its one slash
    local leaks = {}
    local c = w.clients.Healer3
    for k in pairs(c.env) do
        if not c.envBefore[k] and not allow[k] then leaks[#leaks + 1] = tostring(k) end
    end
    ok(#leaks == 0, "no global leaks", table.concat(leaks, ","))
    slash(c, "status")
    ok(#c.prints > 0, "/inn status prints")
    slash(c, "nonsense")
    ok(string.find(c.prints[#c.prints] or "", "commands:", 1, true) ~= nil, "unknown command prints help")
    -- the version the raid hears (HELLO|ver, the lib's RegisterAddon) is the
    -- TOC's: NS.VERSION and every "x.y.z" version literal in the sources
    -- must match it, or a stale number ships to the whole raid
    local toc = assert(io.open("BiSInnervate.toc")):read("*a")
    local tocVer = toc:match("## Version:%s*([%d%.]+)")
    ok(tocVer ~= nil, "the TOC has a version", tocVer)
    ok(c.NS.VERSION == tocVer, "NS.VERSION is the TOC's", c.NS.VERSION, tocVer)
    local stale = {}
    for _, rel in ipairs(H.tocFiles(".")) do
        local f = io.open(rel); local src = f and f:read("*a"); if f then f:close() end
        for lit in (src or ""):gmatch('VERSION[^\n]-"(%d+%.%d+%.%d+)"') do
            if lit ~= tocVer then stale[#stale + 1] = rel .. ":" .. lit end
        end
    end
    ok(#stale == 0, "no source file carries a version literal other than the TOC's", table.concat(stale, ","))
    -- embedded libs are the canonical bytes. The lib is edited in _bisdev (the
    -- theme in BiSTheme) and copied out; a stale copy in an addon is how three
    -- addons were still announcing phantom OFFERs after minor 5 fixed it. When
    -- the sibling folders are there (they are, in the AddOns tree), every
    -- embedded file must be byte-identical - run _bisdev/sync.ps1 otherwise.
    local function bytes(path) local fh = io.open(path, "rb") if not fh then return nil end local b = fh:read("*a") fh:close() return b end
    for _, pr in ipairs({
        { "Libs/LibBiSComm-1.0/LibBiSComm-1.0.lua", "../_bisdev/LibBiSComm-1.0/LibBiSComm-1.0.lua" },
        { "Libs/BiSTheme/Console.lua",              "../BiSTheme/Console.lua" },
        { "Libs/BiSTheme/Options.lua",              "../BiSTheme/Options.lua" },
    }) do
        local mine, ref = bytes(pr[1]), bytes(pr[2])
        if ref then ok(mine == ref, "embedded " .. pr[1] .. " is byte-identical to " .. pr[2] .. " (run _bisdev/sync.ps1)")
        else print("   (canonical " .. pr[2] .. " not beside this checkout - embed check skipped)") end
    end
end

section("57. a Gamba-only rezzer's RezComm claim lands on an Innervate grid (debt 8)")
-- The emitter (_bisdev/RezComm-1.0, embedded in Gamba and Tools) never loads Innervate; it
-- speaks Innervate's BiSInn wire from a client that has no lib and no HELLO. The three
-- deciding assertions from bisgamba-rezcomm-status.md: claim lands in the same tick, the
-- rezzer's own FREE releases it, a stranger's FREE for that claim is refused. The wire
-- lines are built the way RezComm builds them (PROTO|CMD|name), with PROTO read off the
-- emitter file itself so a protocol bump on either side goes red here, not on raid night.
do
    local w = H.NewWorld(".")
    for _, p in ipairs(BASE) do w:AddPlayer(p[1], p[2], p[3] ~= false, p[5], p[6]); if p[4] then w.mana[p[1]] = p[4] end end
    w:AddPlayer("Dps13", "PALADIN", false, 2)      -- Gamba only: no Innervate, no HELLO
    w:AddPlayer("Stranger", "PRIEST", false, 2)      -- another lib-less raider
    w:Login(); w:Advance(4)
    local h = w.clients.Healer1
    -- the emitter's protocol, read off disk (canon beside this checkout; skip with a note if not)
    local proto = nil
    local fh = io.open("../_bisdev/RezComm-1.0/RezComm-1.0.lua", "rb")
    if fh then
        local src = fh:read("*a") fh:close()
        proto = tonumber(src:match("local%s+PROTO%s*=%s*(%d+)"))
        ok(proto == h.NS.PROTOCOL, "RezComm's PROTO equals Innervate's NS.PROTOCOL (bump one, bump both)", tostring(proto) .. " vs " .. tostring(h.NS.PROTOCOL))
    else
        print("   (canonical ../_bisdev/RezComm-1.0 not beside this checkout - PROTO cross-check skipped)")
        proto = h.NS.PROTOCOL
    end
    local function wire(cmd, name) return proto .. "|" .. cmd .. "|" .. name end
    w.dead = { Kumlust = true }
    w:Advance(1)
    ok(h.NS.Rez.claims.Kumlust == nil, "nobody has claimed the corpse yet")
    -- 1. claim lands in the same tick: no Advance between Deliver and the check
    w:Deliver("Dps13", "Healer1", wire("RCLAIM", "Kumlust"))
    local c = h.NS.Rez.claims.Kumlust
    ok(c ~= nil and c.who == "Dps13" and c.src == "comm", "the Gamba-only rezzer's RCLAIM is a claim on the Innervate grid, same tick", c and c.who)
    -- 2. the rezzer's own FREE releases it
    w:Deliver("Dps13", "Healer1", wire("RFREE", "Kumlust"))
    ok(h.NS.Rez.claims.Kumlust == nil, "his RFREE (interrupt) releases the corpse")
    -- 3. a stranger's FREE for someone else's claim is refused
    w:Deliver("Dps13", "Healer1", wire("RCLAIM", "Kumlust"))
    w:Deliver("Stranger", "Healer1", wire("RFREE", "Kumlust"))
    c = h.NS.Rez.claims.Kumlust
    ok(c ~= nil and c.who == "Dps13", "a stranger's RFREE for Dps13's claim is refused - the claim stands", c and c.who)
    -- and RDONE marks it rezzed
    w:Deliver("Dps13", "Healer1", wire("RDONE", "Kumlust"))
    ok(h.NS.Rez.claims.Kumlust ~= nil and h.NS.Rez.claims.Kumlust.who == "Dps13", "his RDONE keeps the guard claim in his name")
    -- the wrong protocol is silence, not a claim (the landmine the status doc warns about)
    h.NS.Rez:ClearClaim("Kumlust")
    w:Deliver("Dps13", "Healer1", (proto + 1) .. "|RCLAIM|Kumlust")
    ok(h.NS.Rez.claims.Kumlust == nil, "a claim on the wrong protocol number is ignored")
    w.dead = {}
end

--------------------------------------------------------------------
print(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
