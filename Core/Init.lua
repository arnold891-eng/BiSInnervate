-- BiS Innervate :: Init.lua
-- Event wiring. Every RegisterEvent is pcall'd: an unknown event on this client
-- throws and would abort the rest of the file.

local ADDON, NS = ...

local f = CreateFrame("Frame", "BiSInnervateEventFrame")
NS.eventFrame = f

local handlers = {}

local function reg(event, fn, unit1, unit2)
    handlers[event] = fn
    local ok
    if unit1 and f.RegisterUnitEvent then
        ok = pcall(f.RegisterUnitEvent, f, event, unit1, unit2)
    end
    if not ok then ok = pcall(f.RegisterEvent, f, event) end
    if not ok then NS.Debug("event not supported:", event) end
end

f:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then NS.Debug("event error", event, err) end
end)

--------------------------------------------------------------------

local function bootstrap()
    if NS._booted then return end
    NS.InitDB()

    -- Loading during combat cannot create the secure buttons. Say so and finish
    -- the moment the fight ends; do NOT mark booted or nothing would retry.
    if NS.InCombat() then
        if not NS._deferredBoot then
            NS._deferredBoot = true
            NS.Print("loaded in combat - the window appears when this fight ends.")
        end
        return
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, NS.PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, NS.PREFIX)
    end

    -- If building the window throws, say so out loud and stay un-booted so the
    -- next event retries; a silent half-boot left people with no window, no
    -- error and a slash command that still answered.
    local okBuild, err = pcall(function()
        NS.Rez:BuildHealTable()
        NS.Window:DefaultMode()
        NS.Window:Build()
        NS.Tracker:UpdateRoster()
        NS.Window:Bind()
        NS.Window:SetClickable(not NS.Window:IsHidden())
        NS.Minimap:Build()
    end)
    if not okBuild then
        NS.Print("|cfff08cb0failed to build the window:|r " .. tostring(err))
        return
    end
    NS._booted = true

    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.5, function() NS.Calls:Tick(); NS.Rez:Tick(); NS.Window:Refresh() end)
        C_Timer.NewTicker(0.2, function() NS.Window:TickTitle() end)
        C_Timer.NewTicker(5,   function() NS.Tracker:BroadcastState() end)
        C_Timer.NewTicker(10,  function() NS.Calls:Heartbeat() end)
    end

    NS.After(2, function() if NS.InGroup() then NS.Comm:Hello() end end)
    -- an override keybind does not survive /reload: re-apply the stored one
    if NS.db.rezBindKey then NS.After(1, function() NS.Rez:ApplyBind(NS.db.rezBindKey) end) end

    NS.Window:Refresh()
    NS.Print("v" .. NS.VERSION .. " loaded. /inn to ask for an innervate, /inn config for options." ..
             (NS.Rez:Enabled() and " Rez button: " .. tostring(NS.Rez:SpellName() or "heal and drink only") .. "." or ""))
end

reg("ADDON_LOADED", function(name) if name == ADDON then NS.InitDB() end end)
reg("PLAYER_LOGIN", bootstrap)

reg("PLAYER_ENTERING_WORLD", function()
    if not NS._booted then bootstrap() end
    NS.Tracker:UpdateRoster()
    NS.Window:Reunit()
    NS.Window:Bind()
    NS.After(2, function() NS.Window:RefreshPortraits() end)
    NS.Window:Refresh()
end)

reg("GROUP_ROSTER_UPDATE", function()
    NS.Tracker:UpdateRoster()
    NS.Window:Reunit()
    NS.Window:Bind()
    NS.Window:Refresh()
    if NS.InGroup() and (NS.Now() - (NS._lastHello or 0)) > 10 then
        NS._lastHello = NS.Now()
        NS.After(1 + math.random() * 2, function() NS.Comm:Hello() end)
    end
end)

reg("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
    NS.Comm:OnMessage(prefix, msg, channel, sender)
end)

reg("COMBAT_LOG_EVENT_UNFILTERED", function()
    if not CombatLogGetCurrentEventInfo then return end
    NS.Tracker:OnCombatLogEvent(CombatLogGetCurrentEventInfo())
end)

reg("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellId)
    NS.Tracker:OnUnitCast(unit, castGUID, spellId)
    NS.Rez:OnCastSucceeded(unit, spellId)
end)

-- the rez module: a claim attaches when OUR cast starts, and lets go when it
-- dies. Player-only where the client allows it.
reg("UNIT_SPELLCAST_START",       function(unit, _, spellId) NS.Rez:OnCastStart(unit, spellId) end, "player")
reg("UNIT_SPELLCAST_STOP",        function(unit, _, spellId) NS.Rez:OnCastStop(unit, spellId) end, "player")
reg("UNIT_SPELLCAST_INTERRUPTED", function(unit, _, spellId) NS.Rez:OnCastInterrupted(unit, spellId) end, "player")
reg("UNIT_SPELLCAST_FAILED",      function(unit, _, spellId) NS.Rez:OnCastFailed(unit, spellId) end, "player")
reg("UI_ERROR_MESSAGE", function(a, b)
    NS.Rez:OnUIError((type(a) == "string") and a or b)
end)
reg("SPELLS_CHANGED", function()
    if NS.InCombat() then return end
    NS.ForgetSpellCache()
    NS.Rez:OnSpellsChanged()
end)
reg("PLAYER_EQUIPMENT_CHANGED", function()
    -- heal sizes move with +healing; a second later, once the stats settle
    if NS._gearCheck then return end
    NS._gearCheck = true
    if not NS.After(1, function() NS._gearCheck = nil; NS.Rez:BuildHealTable(); NS.Rez.last = nil end) then
        NS._gearCheck = nil; NS.Rez:BuildHealTable()
    end
end)
-- dying and standing up change what the button (and the ask) can do
reg("PLAYER_DEAD",    function() NS.Rez.last = nil; NS.Window:Refresh() end)
reg("PLAYER_UNGHOST", function() NS.Rez.last = nil; NS.Window:Refresh() end)
reg("PLAYER_ALIVE",   function() NS.Rez.last = nil; NS.Window:Refresh() end)

reg("PLAYER_TALENT_UPDATE", function()
    if NS.InCombat() then return end
    NS.ForgetSpellCache()
    NS.Rez:OnSpellsChanged()
    -- a respec: the H / X in the REZ blob changes, the grid follows, and a
    -- mode nobody chose yet may change with it
    if NS.MyHealerSpec() ~= nil then NS.Tracker:BroadcastState(); NS.Window:DefaultMode() end
    NS.Tracker:UpdateRoster()
    NS.Window:Bind()
end)

reg("BAG_UPDATE", function()
    -- drums come and go with the bags: if what I can provide changed, say so
    -- and rewire the buttons (out of combat)
    if NS._bagCheck then return end
    NS._bagCheck = true
    if not NS.After(1, function() NS._bagCheck = nil; NS.Window:RecheckKinds() end) then
        NS._bagCheck = nil; NS.Window:RecheckKinds()
    end
end)

reg("UNIT_AURA", function(unit)
    if unit == "player" then NS.Window:Refresh() end     -- exhaustion / tinnitus grey the buttons
end, "player")

reg("SPELL_UPDATE_COOLDOWN", function()
    local kinds = NS.MyKinds()
    if #kinds == 0 then return end
    -- speak on a ready<->not-ready transition or a big jump only, for any of
    -- my kinds: a ticking cooldown "changes" every second for six minutes
    NS._lastCds = NS._lastCds or {}
    local speak = false
    for _, kind in ipairs(kinds) do
        local cd = NS.Round(NS.SpellCooldownFor(kind))
        local was = NS._lastCds[kind]
        local flipped = (was == nil) or ((was <= 0) ~= (cd <= 0))
        if flipped or math.abs((was or 0) - cd) >= 20 then
            speak = true
            NS._lastCds[kind] = cd
            NS.Tracker:SetState(NS.PlayerName(), kind, NS.SpellCooldownFor(kind), NS.ManaPct("player"),
                                NS.InCombat(), true, NS.Subgroup(NS.PlayerName()))
        end
    end
    if not speak then return end
    if (NS.Now() - (NS._lastCdCast or 0)) < 2 then return end
    NS._lastCdCast = NS.Now()
    NS.Tracker:BroadcastState()
end)

-- a druid shifting in or out of a form: the raid's innervate buttons follow
reg("UPDATE_SHAPESHIFT_FORM", function()
    if not NS.Provides("INNERVATE") then return end
    local now = NS.Shapeshifted()
    if now == (NS._wasShifted or false) then return end
    NS._wasShifted = now
    NS.Tracker:SetState(NS.PlayerName(), "INNERVATE", nil, nil, nil, true, nil, now and "F" or "")
    NS.Tracker:BroadcastState()
    NS.Window:Refresh()
end)

reg("PLAYER_REGEN_ENABLED", function()
    if not NS._booted then bootstrap() end
    if NS.demoStopPending then NS.Demo:Stop() end
    NS.Window:AfterCombat()
end)

reg("PLAYER_REGEN_DISABLED", function()
    if NS.demoMode and NS.InGroup() then
        NS.Print("|cfff08cb0demo is still on|r - your calls still go out, but you look like a druid to yourself. /inn demo after the fight.")
    end
    NS.Window:Refresh()
end)

reg("CVAR_UPDATE", function(name)
    if name == "ActionButtonUseKeyDown" or name == "ACTION_BUTTON_USE_KEY_DOWN" then
        NS.Window:ReapplyClicks()
    end
end)

--------------------------------------------------------------------

SLASH_BISINNERVATE1 = "/inn"
SLASH_BISINNERVATE2 = "/innervate"
SLASH_BISINNERVATE3 = "/bisinn"
SlashCmdList["BISINNERVATE"] = function(input) NS.HandleSlash(input) end

NS.Bootstrap = bootstrap
