dofile("bisrez-harness.lua")
local P = _G.__H.realprint
DUMP("file load")

-- login
FIRE("ADDON_LOADED", "BiSRez")
FIRE("PLAYER_LOGIN")
DUMP("login")

P("healRanks/groupHeal via slash:")
SLASH("heals")
DUMP("/bisrez heals")

TICK()
local b = _G.BiSRezButton
P(("action=%s currentUnit=%s currentName=%s failReason=%s")
  :format(tostring(b.action), tostring(b.currentUnit), tostring(b.currentName), tostring(b.failReason)))
P(("attrs: *type1=%s *macrotext1=%s *spell1=%s unit=%s")
  :format(tostring(b:GetAttribute("*type1")), tostring(b:GetAttribute("*macrotext1")),
          tostring(b:GetAttribute("*spell1")), tostring(b:GetAttribute("unit"))))
DUMP("tick 1 (2 dead, full mana -> expect rez priest)")

-- click + cast lifecycle
CLICK() ; CLICK()  -- both click edges
DUMP("click (double edge)")
FIRE("UNIT_SPELLCAST_START", "player", nil, 2008)
DUMP("cast start")
FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 2008)
DUMP("cast succeeded")
CLEU_ARGS = {0,"SPELL_RESURRECT",false,"P-player","Kumlust",0,0,"P-1","Holypal",0,0,2008,"Ancestral Spirit",0}
FIRE("COMBAT_LOG_EVENT_UNFILTERED")
DUMP("combat log SPELL_RESURRECT")
SLASH("score")
DUMP("/bisrez score")

-- now low mana with a dead target -> drink
UNITS.party1.dead = false ; UNITS.party1.hp = 9000
PLAYER_MANA = 100
NOW = NOW + 40
TICK()
P(("action=%s macrotext=%s"):format(tostring(b.action), tostring(b:GetAttribute("*macrotext1"))))
DUMP("tick: low mana, mage still dead -> expect drink")

-- nobody dead, someone hurt -> heal
UNITS.party2.dead = false ; UNITS.party2.hp = 3000
PLAYER_MANA = 5000
TICK()
P(("action=%s healSpell=%s healUnit=%s *spell1=%s unit=%s"):format(
  tostring(b.action), tostring(b.healSpell), tostring(b.healUnit),
  tostring(b:GetAttribute("*spell1")), tostring(b:GetAttribute("unit"))))
DUMP("tick: nobody dead, 2 hurt -> expect group heal")

-- one hurt only
UNITS.party3.hp = 11800 ; UNITS.player.hp = 10000
TICK()
P(("action=%s healSpell=%s healUnit=%s"):format(tostring(b.action), tostring(b.healSpell), tostring(b.healUnit)))
DUMP("tick: only party2 hurt -> expect single heal")

CLICK()
FIRE("UNIT_SPELLCAST_SUCCEEDED","player",nil,8004)
DUMP("heal click + success (should print NOTHING)")

-- everyone topped
UNITS.party2.hp = 7000
TICK()
P("action="..tostring(b.action))
DUMP("tick: nobody hurt -> expect nil")

-- combat
INCOMBAT = true
UNITS.party3.hp = 2000
TICK()
P("in combat action="..tostring(b.action).." healUnit="..tostring(b.healUnit))
INCOMBAT = false
DUMP("tick in combat")

-- roster change
FIRE("GROUP_ROSTER_UPDATE")
DUMP("roster update (same group)")
UNITS.party1.guid="Q-1" UNITS.party2.guid="Q-2" UNITS.party3.guid="Q-3"
FIRE("GROUP_ROSTER_UPDATE")
DUMP("roster update (new group -> expect scoreboard cleared)")

-- addon comms
FIRE("CHAT_MSG_ADDON","BiSRez","H:","PARTY","Someone")
FLUSHTIMERS()
FIRE("CHAT_MSG_ADDON","BiSRez","S:Zug=7;Kumlust=2;","PARTY","Someone")
DUMP("addon comms")

-- errors / interrupts
CLICK()
FIRE("UI_ERROR_MESSAGE", 1, "Not enough mana")
FIRE("UNIT_SPELLCAST_INTERRUPTED","player",nil,2008)
FIRE("UNIT_SPELLCAST_FAILED","player",nil,2008)
FIRE("UNIT_SPELLCAST_STOP","player")
DUMP("errors")

-- every slash command
for _,c in ipairs({"","lock","unlock","show","hide","list","claims","score","sync","resetscore",
                   "diag","macro","verbose","mode","clicks","rank","at","heals","rescan","bind ALT-R","bogus"}) do
  SLASH(c)
end
DUMP("all slash commands")

-- options panel: toggle every checkbox
local opt = _G.BiSRezOptions
if opt then
  local n = 0
  for k,c in pairs(opt.checks or {}) do
    n = n + 1
    c.__checked = not c.__checked
    local ok,e = pcall(c.__scripts.OnClick, c)
    if not ok then P("!! checkbox "..k.." error: "..tostring(e)) end
  end
  P("toggled "..n.." checkboxes")
  pcall(opt.Refresh, opt)
else
  P("!! no options frame")
end
TICK()
DUMP("options panel")

-- PANEL GEOMETRY probe
P("panel size check: see analysis")

-- leaks
P("=== GLOBAL LEAKS ===")
if #_G.__H.leaks == 0 then P("  none") end
for _,k in ipairs(_G.__H.leaks) do P("  "..k) end
DUMP("leaks")
