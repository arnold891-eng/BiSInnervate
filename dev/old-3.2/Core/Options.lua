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
    flyoutDir   = "up",   -- the drum types unfold up or down from the button
    sound       = true,
    voice       = "auto", -- FojjiCore voice pack: auto | <name> | off
    chatAlert   = true,
    minimap     = true,
    minimapAngle = 205,
    debug       = false,
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
    scale      = { 0.5, 2 },
}
local KEY_ALIAS = { claimhold = "claimHold", expire = "expire", cancelmana = "cancelMana",
                    urgentat = "urgentAt", scale = "scale" }

local function onoff(v) return v and "|cff4fd0cfon|r" or "|cfff08cb0off|r" end

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

    elseif cmd == "cancel" or cmd == "stop" then
        local n = NS.Calls:CancelMine("manual")
        NS.Print(n > 0 and "call cancelled." or "nothing to cancel.")

    elseif cmd == "show" or cmd == "open" then
        NS.Window:Show()
    elseif cmd == "hide" or cmd == "close" or cmd == "toggle" then
        NS.Window:ToggleShown()

    elseif cmd == "lock" then
        NS.db.locked = not NS.db.locked
        NS.Print("window " .. (NS.db.locked and "locked." or "unlocked - drag the title bar."))

    elseif cmd == "scale" or cmd == "size" then
        local v = tonumber(rest)
        if v then
            NS.db.scale = NS.Clamp(v, 0.5, 2)
            NS.Window:ApplyScale()
            NS.Print("scale " .. NS.db.scale .. (NS.InCombat() and " (applies when the fight ends)" or ""))
        else
            NS.Print("usage: /inn scale 0.5 - 2  (now " .. tostring(NS.db.scale) .. ")")
        end

    elseif cmd == "config" or cmd == "options" or cmd == "settings" then
        NS.Config:Toggle()

    elseif cmd == "minimap" or cmd == "button" then
        NS.Minimap:Toggle()

    elseif cmd == "sound" then
        NS.db.sound = not NS.db.sound
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
            NS.db.voice = rest
            NS.Print("voice: " .. rest .. " -> " .. tostring(NS.Sound:ActivePack() or "none"))
        end
    elseif cmd == "mages" or cmd == "odiss" then
        NS.Window:SetMagesOnly(not NS.db.magesOnly)

    elseif cmd == "faces" or cmd == "3d" then
        NS.db.portraits3d = not NS.db.portraits3d
        NS.Window:RefreshPortraits(); NS.Window:Refresh()
        NS.Print("3D faces " .. onoff(NS.db.portraits3d))

    elseif cmd == "set" then
        local key, val = string.match(rest, "^(%S+)%s+(%S+)$")
        val = tonumber(val or "")
        key = key and string.lower(key)
        local bounds = NS.LIMITS[key or ""]
        if key and val and bounds then
            NS.db[KEY_ALIAS[key]] = NS.Clamp(val, bounds[1], bounds[2])
            NS.Print(KEY_ALIAS[key] .. " = " .. NS.db[KEY_ALIAS[key]])
            if key == "scale" then NS.Window:ApplyScale() end
        else
            NS.Print("usage: /inn set claimHold|expire|cancelMana|urgentAt|scale <number>")
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
    elseif cmd == "debug" then
        NS.db.debug = not NS.db.debug
        NS.Print("debug " .. onoff(NS.db.debug))

    else
        NS.Print("commands: /inn (ask innervate) | tide | lust | drums | cancel | show | hide | lock | scale <n> | " ..
                 "config | minimap | sound | voice [list|<pack>|off|auto|test] | faces | mages | " ..
                 "set <key> <n> | reset | status | demo | debug")
    end
    -- the window and the commands write the same keys; keep an open window honest
    if NS.Config and NS.Config.frame and NS.Config.frame:IsShown() then NS.Config:Refresh() end
end
