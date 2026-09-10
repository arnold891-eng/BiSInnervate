-- BiS Innervate :: Options.lua
-- Saved variables, their defaults and migrations, and the slash commands.

local ADDON, NS = ...

NS.DEFAULTS = {
    dbVersion   = 4,
    claimHold   = 8,      -- seconds a druid's claim locks a face before it pulses again
    expire      = 40,     -- a call lives this long
    cancelMana  = 70,     -- auto-cancel once back above this (and 15 above what you had)
    urgentAt    = 20,     -- your ask button pulses under this mana %
    scale       = 1,      -- the window
    hidden      = false,  -- closed with the x
    locked      = false,  -- no dragging
    portraits3d = false,  -- animated faces instead of flat portraits
    magesOnly   = false,  -- Odiss mode: just the mage faces, no button row, window fits them
    healerOnly  = false,  -- healer mode: just the rez / heal / drink button, nothing else
    modeSet     = false,  -- the player chose a mode themselves; until then the class/spec picks one
    flyoutDir   = "up",   -- the drum types unfold up or down from the button
    sound       = true,
    voice       = "auto", -- FojjiCore voice pack: auto | <name> | off
    chatAlert   = true,
    minimap     = true,
    minimapAngle = 205,
    debug       = false,
    -- the rez module (Core/Rez.lua)
    rez          = true,    -- the rez/heal/drink button, for healer classes
    rezHeal      = true,    -- heal whoever is worst off when nobody needs a rez
    rezDrink     = true,    -- drink when the next cast is unaffordable
    rezKeepScores = false,  -- keep the rez scoreboard across groups
    rezDrinkLow  = false,   -- everyone who uses mana: the button is a drink under rezDrinkAt %
    rezDrinkAt   = 75,
}

function NS.InitDB()
    BiSInnervateDB = BiSInnervateDB or {}
    local db = BiSInnervateDB

    -- read the stored version BEFORE defaults: dbVersion is in DEFAULTS too
    local hadData = next(db) ~= nil
    local stored  = db.dbVersion or (hadData and 1 or NS.DEFAULTS.dbVersion)

    -- 3.0: the 2.x schema is gone. Keep what still means something and drop
    -- the rest (assignments, per-window positions, whisper settings, roles).
    if stored < 4 and hadData then
        local keep = {
            sound = db.sound, chatAlert = db.chatAlert, debug = db.debug,
            minimap = db.minimap, minimapAngle = db.minimapAngle,
            urgentAt = db.urgentAt, cancelMana = db.cancelMana,
            expire = db.expire, claimHold = db.claimHold,
            scale = db.scale or (db.small and 0.5) or nil,
            requesterClasses = db.requesterClasses,
        }
        for k in pairs(db) do db[k] = nil end
        for k, v in pairs(keep) do db[k] = v end
        NS.After(3, function()
            NS.Print("3.0: one window for everyone. Assignments and whispers are gone; " ..
                     "/inn config for the rest.")
        end)
    end

    for k, v in pairs(NS.DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.requesterClasses = db.requesterClasses or {}
    for k, v in pairs(NS.REQUESTER_CLASSES) do
        if db.requesterClasses[k] == nil then db.requesterClasses[k] = v end
    end
    db.dbVersion = NS.DEFAULTS.dbVersion
    NS.db = db
    return db
end

NS.LIMITS = {
    claimhold  = { 3, 30 },
    expire     = { 10, 300 },
    cancelmana = { 30, 100 },
    urgentat   = { 1, 90 },
    drinkat    = { 20, 95 },
    scale      = { 0.5, 2 },
}
local KEY_ALIAS = { claimhold = "claimHold", expire = "expire", cancelmana = "cancelMana",
                    urgentat = "urgentAt", scale = "scale", drinkat = "rezDrinkAt" }

local function onoff(v) return v and "|cff4fd0cfon|r" or "|cfff08cb0off|r" end

--------------------------------------------------------------------
-- the setters. ONE owner per key: the options window and the slash command
-- both go through these, so the two can never drift. Each does the work and
-- says it in the prompt (W:Say); the slash handler adds its chat line.
-- Anything that touches the protected main window goes through the Window
-- function that already defers to AfterCombat - never a Layout from here.
--------------------------------------------------------------------

local function say(text, tone) if NS.Window then NS.Window:Say(text, tone) end end

function NS.SetNumber(key, v)
    -- claimHold / expire / cancelMana / urgentAt / rezDrinkAt / scale, clamped
    -- to NS.LIMITS (belt and braces: the options stepper clamps on its own)
    local lk = string.lower(key)
    local bounds, real = NS.LIMITS[lk], KEY_ALIAS[lk]
    if not bounds or not real then return nil end
    v = NS.Clamp(tonumber(v) or NS.DEFAULTS[real], bounds[1], bounds[2])
    NS.db[real] = v
    if real == "scale" then NS.Window:ApplyScale() end       -- defers in a fight
    if real == "rezDrinkAt" and NS.Rez then NS.Rez.last = nil end
    return v
end
function NS.SetScale(v) return NS.SetNumber("scale", v) end

function NS.SetLocked(on)
    NS.db.locked = on and true or false
    say(NS.db.locked and "window locked" or "window unlocked", NS.db.locked and "muted" or "ink2")
end

function NS.SetSound(on)
    NS.db.sound = on and true or false
end

function NS.SetChatAlert(on)
    NS.db.chatAlert = on and true or false
end

function NS.SetVoice(pack)
    NS.db.voice = pack
end

-- animated portraits or flat ones: the repaint is out of combat only
function NS.SetFaces3D(on)
    NS.db.portraits3d = on and true or false
    if not NS.InCombat() then NS.Window:RefreshPortraits(); NS.Window:Refresh() end
end

function NS.SetFlyoutDir(dir)
    NS.db.flyoutDir = (dir == "down") and "down" or "up"
    NS.Window:PlaceFlyout()        -- the secure kit part of it waits for the fight to end
end

function NS.SetRequesterClass(class, on)
    NS.db.requesterClasses = NS.db.requesterClasses or {}
    NS.db.requesterClasses[class] = on and true or false
    if not NS.InCombat() then NS.Window:Bind() end       -- else AfterCombat binds
end

-- the rez button's switches: a rebind where the button itself changes
function NS.SetRez(on)
    NS.db.rez = on and true or false
    if NS.Rez then NS.Rez.last = nil end
    if not NS.InCombat() then NS.Window:Bind() end
end
function NS.SetRezHeal(on)
    NS.db.rezHeal = on and true or false
    if NS.Rez then NS.Rez.last = nil end
end
function NS.SetRezDrink(on)
    NS.db.rezDrink = on and true or false
    if NS.Rez then NS.Rez.last = nil end
end
function NS.SetRezDrinkLow(on)
    NS.db.rezDrinkLow = on and true or false
    if NS.Rez then NS.Rez.last = nil; NS.Rez.shown = nil end
    if not NS.InCombat() then NS.Window:Bind() end
end
function NS.SetRezKeepScores(on)
    NS.db.rezKeepScores = on and true or false
end
function NS.RebuildHeals()
    NS.Rez:BuildHealTable(); NS.Rez.last = nil
end

function NS.SetDebug(on)
    NS.db.debug = on and true or false
end

function NS.HandleSlash(input)
    input = string.gsub(input or "", "^%s+", "")
    local cmd, rest = string.match(input, "^(%S*)%s*(.*)$")
    cmd  = string.lower(cmd or "")
    rest = rest or ""

    if cmd == "" or cmd == "inn" or cmd == "ask" or cmd == "please" then
        NS.Calls:Ask("INNERVATE")

    elseif cmd == "tide" or cmd == "manatide" or cmd == "mt" then
        NS.Calls:Ask("TIDE")
    elseif cmd == "lust" or cmd == "bl" or cmd == "bloodlust" or cmd == "heroism" or cmd == "hero" then
        NS.Calls:Ask("LUST")
    elseif cmd == "drums" or cmd == "drum" then
        local v = string.upper(rest)
        NS.Calls:Ask("DRUMS", (v ~= "" and NS.DRUM[v]) and v or nil)

    elseif cmd == "rez" then
        -- a corpse without the button: "rez me first". A healer: what the
        -- button would do right now.
        if NS.Rez:Enabled() then
            local d = NS.Rez:Decide()
            NS.Print("rez button: " .. NS.Rez:Summary(d))
            if NS.Window then NS.Window:RebindRez(); NS.Window:Refresh() end
        else
            NS.Calls:Ask("REZ")
        end
    elseif cmd == "rezzers" then
        local list = NS.Rez:Rezzers()
        NS.Print(("%d rezzer(s) with the addon standing, %d ready"):format(#list, NS.Rez:RezzersReady()))
        for _, r in ipairs(list) do
            local state = NS.Rez:IsCasting(r.name) and "casting" or ((r.cd > 0) and ("back in " .. NS.TimeStr(r.cd)) or "ready")
            NS.Print("  " .. NS.ClassColored(r.name) .. " - " .. state)
        end
        local n, detail = NS.Rez:WipeProtection()
        if n > 0 then
            NS.Print("wipe protection: " .. n)
            for _, d in ipairs(detail) do NS.Print("  " .. d.name .. " - " .. d.what) end
        else
            NS.Print("no wipe protection up - a wipe is a corpse run.")
        end
    elseif cmd == "rezlist" or cmd == "corpses" then
        local list = NS.Rez:Corpses()
        NS.Print(#list .. " corpse(s), in the order the button takes them:")
        for i, c in ipairs(list) do
            NS.Print(("  %d. %s  prio %.1f - %s"):format(i, NS.ClassColored(c.name, c.class), c.score, c.why))
        end
    elseif cmd == "rezheals" or cmd == "heals" then
        NS.Rez:BuildHealTable()
        NS.Print(("%d single heal(s), %d group heal rank(s)"):format(#NS.Rez.heals, #NS.Rez.groupHeals))
        for _, list in ipairs({ NS.Rez.heals, NS.Rez.groupHeals }) do
            for _, h in ipairs(list) do
                NS.Print(("  %s  ~%d heal  %s%s"):format(h.cast, h.heal or 0,
                         h.measured and ("measured (" .. (NS.db.rezHealSizes[h.id] or {}).n .. " casts)")
                                    or ("estimated" .. ((h.base and h.base > 0) and (", tooltip " .. math.floor(h.base)) or "")),
                         h.level and ("  lvl " .. h.level .. " coef %.2f"):format(NS.Rez:Coefficient(h.cast, h.level)) or ""))
            end
        end
        NS.Print(("  healing power %d, talents x%.2f, calibration x%.2f, LibHealComm %s"):format(
                 NS.Rez.HealingPower(), NS.Rez:TalentMultiplier(), NS.Rez.calibration or 1, NS.Rez:HealComm() and "loaded" or "not loaded"))
        local _, _, id = NS.Rez:FindDrink()
        NS.Print("  drink: " .. (id and NS.Rez:DrinkName(id) or "none in bags"))
    elseif cmd == "rezscore" or cmd == "score" then
        local list = {}
        for n, c in pairs(NS.db.rezScores or {}) do list[#list + 1] = { n = n, c = c } end
        table.sort(list, function(a, b) return a.c > b.c end)
        NS.Print("rez scoreboard:")
        if #list == 0 then NS.Print("  nobody yet") end
        for i, e in ipairs(list) do NS.Print(("  %d. %s - %d"):format(i, e.n, e.c)) end
    elseif cmd == "rezreset" then
        NS.db.rezScores = {}
        NS.Print("rez scoreboard cleared.")
    elseif cmd == "rezsizes" then
        NS.db.rezHealSizes = {}
        NS.Rez:SizeHeals(); NS.Rez.last = nil
        NS.Print("measured heal sizes cleared - back to estimates until you cast.")
    elseif cmd == "bind" then
        local key = string.upper(rest)
        if key == "" then NS.Print("usage: /inn bind ALT-R  (/inn unbind clears it)")
        elseif NS.InCombat() then NS.Print("cannot bind in combat.")
        else
            local existing = GetBindingAction and GetBindingAction(key)
            if existing and existing ~= "" and not string.find(existing, "BiSInnervateREZButton", 1, true) then
                NS.Print(key .. " already does " .. existing .. " - pick another key.")
            else
                NS.db.rezBindKey = key
                NS.Print(NS.Rez:ApplyBind(key) and ("rez button bound to " .. key .. " (override binding - your saved keybinds are untouched).")
                                                 or ("could not bind " .. key .. "."))
            end
        end
    elseif cmd == "unbind" then
        NS.db.rezBindKey = nil
        NS.Rez:ClearBind()
        NS.Print("rez button binding cleared.")

    elseif cmd == "cancel" or cmd == "stop" then
        local n = NS.Calls:CancelMine("manual")
        NS.Print(n > 0 and "call cancelled." or "nothing to cancel.")

    elseif cmd == "show" or cmd == "open" then
        NS.Window:Show()
    elseif cmd == "hide" or cmd == "close" or cmd == "toggle" then
        NS.Window:ToggleShown()

    elseif cmd == "lock" then
        NS.SetLocked(not NS.db.locked)
        NS.Print("window " .. (NS.db.locked and "locked." or "unlocked - drag the title bar."))

    elseif cmd == "scale" or cmd == "size" then
        local v = tonumber(rest)
        if v then
            NS.SetScale(v)
            NS.Print("scale " .. NS.db.scale .. (NS.InCombat() and " (applies when the fight ends)" or ""))
        else
            NS.Print("usage: /inn scale 0.5 - 2  (now " .. tostring(NS.db.scale) .. ")")
        end

    elseif cmd == "config" or cmd == "options" or cmd == "settings" then
        NS.Config:Toggle()

    elseif cmd == "minimap" or cmd == "button" then
        NS.Minimap:Toggle()

    elseif cmd == "sound" then
        NS.SetSound(not NS.db.sound)
        NS.Print("sound " .. onoff(NS.db.sound))
    elseif cmd == "voice" then
        local r = string.lower(rest)
        if r == "list" or r == "" then
            local packs = NS.Sound:VoicePacks()
            NS.Print("voice: " .. tostring(NS.db.voice) .. " (active: " .. tostring(NS.Sound:ActivePack() or "none") .. ")")
            NS.Print(#packs > 0 and ("packs: " .. table.concat(packs, ", ")) or "no FojjiCore voice packs installed.")
        elseif r == "test" then
            NS.Sound:Test()
        else
            NS.SetVoice(rest)
            NS.Print("voice: " .. rest .. " -> " .. tostring(NS.Sound:ActivePack() or "none"))
        end
    elseif cmd == "mages" or cmd == "odiss" then
        NS.Window:SetMagesOnly(not NS.db.magesOnly)
    elseif cmd == "healer" then
        NS.Window:SetHealerOnly(not NS.db.healerOnly)

    elseif cmd == "faces" or cmd == "3d" then
        NS.SetFaces3D(not NS.db.portraits3d)
        NS.Print("3D faces " .. onoff(NS.db.portraits3d))

    elseif cmd == "callers" then
        -- who may ask for an innervate. Seven classes is too many rows for the
        -- options window, so this lives here: /inn callers lists, /inn callers
        -- warlock flips one
        local class = string.upper(rest)
        if class ~= "" and NS.REQUESTER_CLASSES[class] ~= nil then
            NS.SetRequesterClass(class, not NS.IsRequesterClass(class))
        elseif class ~= "" then
            NS.Print("usage: /inn callers [mage|priest|paladin|shaman|druid|warlock|hunter]")
            return
        end
        local parts = {}
        for _, c in ipairs({ "MAGE", "PRIEST", "PALADIN", "SHAMAN", "DRUID", "WARLOCK", "HUNTER" }) do
            parts[#parts + 1] = string.lower(c) .. " " .. onoff(NS.IsRequesterClass(c))
        end
        NS.Print("who may call: " .. table.concat(parts, ", "))

    elseif cmd == "set" then
        local key, val = string.match(rest, "^(%S+)%s+(%S+)$")
        val = tonumber(val or "")
        key = key and string.lower(key)
        local bounds = NS.LIMITS[key or ""]
        if key and val and bounds then
            NS.SetNumber(key, val)
            NS.Print(KEY_ALIAS[key] .. " = " .. NS.db[KEY_ALIAS[key]])
        else
            NS.Print("usage: /inn set claimHold|expire|cancelMana|urgentAt|drinkAt|scale <number>")
        end

    elseif cmd == "reset" then
        if NS.InCombat() then
            -- un-hiding is alpha, but the mouse behind it is protected: a window
            -- that looks open and ignores every click is worse than waiting
            NS.Window.resetPending = true
            NS.Print("window resets when this fight ends.")
            return
        end
        NS.db.hidden, NS.db.scale, NS.db.pos = false, 1, nil
        NS.db.minimap, NS.db.minimapAngle, NS.db.locked = true, 205, false
        NS.Window:Build(); NS.Window:ResetPosition(); NS.Window:ApplyScale(true)
        NS.Window:SetClickable(true)
        NS.Minimap:Build(); if NS.Minimap.button then NS.Minimap.button:Show(); NS.Minimap:Place() end
        NS.Window:Refresh()
        NS.Print("window reset.")

    elseif cmd == "status" then
        NS.Tracker:UpdateRoster()
        NS.Print("|cffb980ffBiS Innervate|r v" .. NS.VERSION .. "  (protocol " .. NS.PROTOCOL .. ")")
        for _, kind in ipairs(NS.KINDS) do
            local list = NS.Tracker:Available(kind)
            local names = {}
            for _, d in ipairs(list) do
                names[#names + 1] = d.name .. (d.cd > 0 and (" (" .. NS.TimeStr(d.cd) .. ")") or " (ready)")
            end
            NS.Print(NS.Provider(kind).name .. ": " .. (#names > 0 and table.concat(names, ", ") or "nobody with the addon"))
        end
        local calls = NS.Calls:Active()
        NS.Print(#calls .. " open call" .. (#calls == 1 and "" or "s"))
        for _, c in ipairs(calls) do
            NS.Print("  " .. NS.ClassColored(c.target, c.class) .. " " .. NS.Provider(c.kind).short ..
                     (c.claimedBy and (" - " .. c.claimedBy .. " on it") or " - waiting"))
        end
        local n = 0
        for name in pairs(NS.Comm.users) do n = n + 1 end
        NS.Print(n .. " other" .. (n == 1 and "" or "s") .. " with the addon.")

    elseif cmd == "demo" then
        NS.Demo:Toggle()
    elseif cmd == "version" then
        NS.Print("|cffb980ffBiS Innervate|r v" .. NS.VERSION .. "  (protocol " .. NS.PROTOCOL .. ")")
    elseif cmd == "debug" then
        NS.SetDebug(not NS.db.debug)
        NS.Print("debug " .. onoff(NS.db.debug))

    else
        NS.Print("rez: /inn rez (rez me first, or what the button does) | rezzers | rezlist | rezheals | rezsizes | rezscore | rezreset | bind <KEY> | unbind")
        NS.Print("commands: /inn (ask innervate) | tide | lust | drums | rez | cancel | show | hide | lock | scale <n> | " ..
                 "config | minimap | sound | voice [list|<pack>|off|auto|test] | faces | mages | healer | callers [class] | " ..
                 "set <key> <n> | reset | status | version | demo | debug")
    end
    -- the window and the commands go through the same setters; an open window
    -- repaints so it agrees with what a slash just did
    if NS.Config then NS.Config:Refresh() end
end
