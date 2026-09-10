-- Regression tests for the v2.4 fixes. Each one FAILED on v2.3.
dofile("bisrez-harness.lua")
local P = _G.__H.realprint
local pass, fail = 0, 0
local function T(name, cond, extra)
  if cond then pass = pass + 1 P("  ok   "..name)
  else fail = fail + 1 P("  FAIL "..name..(extra and ("  -> "..tostring(extra)) or "")) end
end
local function reset()
  dofile("bisrez-harness.lua")
  FIRE("ADDON_LOADED","BiSRez") FIRE("PLAYER_LOGIN")
  return _G.BiSRezButton
end

P("#1 interrupt / stop cross-talk")
local b = reset()
TICK() CLICK()
FIRE("UNIT_SPELLCAST_START","player",nil,2008)
local held = 0 for _ in pairs(_G.BiSRezDB and {} or {}) do end
SENT = {}
FIRE("UNIT_SPELLCAST_INTERRUPTED","player",nil,25449)   -- Lightning Bolt, not the rez
local broadcastX = false
for _,m in ipairs(SENT) do if m:find("|FREE|") then broadcastX = true end end
T("unrelated interrupt does NOT broadcast a claim release", not broadcastX)
T("unrelated interrupt does NOT clear pendingGUID", b.pendingGUID ~= nil, b.pendingGUID)
FIRE("UNIT_SPELLCAST_STOP","player",nil,25449)
T("unrelated STOP does NOT clear pendingGUID", b.pendingGUID ~= nil, b.pendingGUID)
SENT = {}
FIRE("UNIT_SPELLCAST_INTERRUPTED","player",nil,2008)    -- the actual rez
local realX = false
for _,m in ipairs(SENT) do if m:find("|FREE|") then realX = true end end
T("interrupting the REZ does release the claim", realX and b.pendingGUID == nil)

P("#2 heal targets are range-checked")
b = reset()
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=7000
UNITS.player.hp=10000 UNITS.party3.hp=1000
IN_RANGE = 0
TICK()
T("out-of-range hurt player is not chosen", b.action ~= "heal", b.action)
IN_RANGE = 1
TICK()
T("in-range hurt player IS chosen", b.action == "heal" and b.healUnit == "party3", b.healUnit)

P("#3 combat: a heal stays armed behind click-time conditionals")
b = reset()
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=7000
UNITS.party3.hp=12000 UNITS.player.hp=10000
TICK()  -- nobody hurt -> v2.3 armed an EMPTY macro here
T("idle button is greyed", b.action == nil)
local m = b:GetAttribute("*macrotext1")
T("idle button still arms a heal", m and m:find("/cast") ~= nil, m)
T("armed macro has a mouseover fallback", m and m:find("@mouseover") ~= nil, m)
T("armed macro has a self fallback", m and m:find("@player") ~= nil, m)
INCOMBAT = true
UNITS.party3.hp = 2000
TICK()
T("macro survives combat lockdown unchanged", b:GetAttribute("*macrotext1") == m)
T("combatLocked flag set", b.combatLocked == true)
INCOMBAT = false

P("#4 the roster handler can actually reach the options window")
b = reset()
SLASH("")                                   -- build + show the window
T("window built", _G.BiSRezConfig ~= nil)
T("no global named 'opts' leaked", rawget(_G, "opts") == nil)
-- v2.3 read `opts` before its `local` declaration, so the roster handler was
-- refreshing a nil global and an open panel kept showing a cleared scoreboard.
-- It now hangs off G, which a late local cannot shadow.
local refreshed = 0
local realRefresh = _G.BiSRezConfig.Refresh
_G.BiSRezConfig.Refresh = function(self) refreshed = refreshed + 1 return realRefresh(self) end
_G.BiSRezConfig.__shown = true
_G.BiSRezDB.scores = { Kumlust = 3 }
_G.BiSRezDB.keepScores = false
FIRE("GROUP_ROSTER_UPDATE")                 -- seed lastGroupGUIDs
UNITS.party1.guid="Q-1" UNITS.party2.guid="Q-2" UNITS.party3.guid="Q-3"
refreshed = 0
FIRE("GROUP_ROSTER_UPDATE")                 -- new group -> scores cleared
T("scoreboard cleared on a group change", next(_G.BiSRezDB.scores) == nil)
T("open window is refreshed when that happens", refreshed > 0, refreshed)

P("#5 a stale click no longer hijacks an unrelated error")
b = reset()
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=7000
UNITS.party3.hp=1000
TICK() CLICK()
T("reportPending armed by the click", b.reportPending == true)
NOW = NOW + 1.0                       -- INSIDE the 1.5s window v2.3 trusted
local before = #_G.__H.out
FIRE("UI_ERROR_MESSAGE", 1, "You are already in a party")
T("unrelated red error is not blamed on the heal target", #_G.__H.out == before,
  _G.__H.out[#_G.__H.out])
before = #_G.__H.out
FIRE("UI_ERROR_MESSAGE", 1, "Out of range.")
T("a real cast error IS still reported", #_G.__H.out > before)
b = reset()
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=7000
UNITS.party3.hp=1000
TICK() CLICK()
NOW = NOW + 10                        -- nothing ever answered this click
before = #_G.__H.out
FIRE("UI_ERROR_MESSAGE", 1, "Out of range.")
T("a click older than the window is forgotten", #_G.__H.out == before)

P("#6 one click edge by default")
b = reset()
T("clickMode defaults to down", _G.BiSRezDB.clickMode == "down", _G.BiSRezDB.clickMode)

P("#7 heals cast without a rank suffix")
b = reset()
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=3000
UNITS.party3.hp=1000 UNITS.player.hp=10000
TICK()
m = b:GetAttribute("*macrotext1")
T("heal goes out as macro text", b.action == "heal" and m and m:find("/cast") ~= nil, m)
T("no (Rank N) suffix in the cast", m and m:find("%(Rank") == nil, m)
T("spell attribute not left dangling", b:GetAttribute("*spell1") == nil)

P("borrowed: why-here tooltip data")
b = reset()
IN_RANGE = 0
TICK()
T("rejected corpses recorded with reasons", (function()
    local ok = false
    local tip = _G.GameTooltip
    -- lastReject is a file local; prove it through the tooltip instead
    local lines = {}
    tip.AddLine = function(self, txt) lines[#lines+1] = tostring(txt) end
    b.__scripts.OnEnter(b)
    for _,l in ipairs(lines) do if l:find("Skipped") then ok = true end end
    for _,l in ipairs(lines) do if l:find("out of range") then ok = ok and true end end
    return ok
  end)())
IN_RANGE = 1

P("borrowed: LibHealComm anti-snipe")
b = reset()
T("HealComm detected", (function()
    local lines = {}
    local rp = _G.print
    _G.print = function(t) lines[#lines+1] = tostring(t) end
    SLASH("heals")
    _G.print = rp
    for _,l in ipairs(lines) do if l:find("loaded") and not l:find("not loaded") then return true end end
    return false
  end)())

-- tank is the worst off on raw health, but two instant-casters already have him
b = reset()
UNITS.party1.dead=false UNITS.party1.hp=9000     -- priest, full
UNITS.party2.dead=false UNITS.party2.hp=5000     -- mage 5000/7000, -2000
UNITS.party3.hp=6000                             -- warrior 6000/12000, -6000
UNITS.player.hp=10000
INCOMING = {}
TICK()
T("without inbound, the tank is the target", b.healUnit == "party3", b.healUnit)

INCOMING = { ["P-3"] = 6000 }                    -- tank already covered
TICK()
T("with inbound covering the tank, it moves to the mage", b.healUnit == "party2", b.healUnit)

INCOMING = { ["P-3"] = 6000, ["P-2"] = 2000 }    -- everyone covered
TICK()
T("with everyone covered it stands down", b.action == nil, b.action)
T("...but still arms the combat fallback", b.armedFallback ~= nil)

-- your OWN pending heal must not cancel the reason you are casting it
INCOMING = {}
OWN_INCOMING = { ["P-3"] = 6000 }
TICK()
T("your own inbound heal is not subtracted", b.healUnit == "party3", b.healUnit)
OWN_INCOMING = {}

-- and it all degrades to v2.4 behaviour when the Libs folder is missing
HEALCOMM = false
b = reset()
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=5000
UNITS.party3.hp=6000 UNITS.player.hp=10000
INCOMING = { ["P-3"] = 6000 }
TICK()
T("no HealComm: falls back to raw health, no crash", b.healUnit == "party3", b.healUnit)
INCOMING = {}
HEALCOMM = true

P("v2.6 borrowed: native heal prediction sees non-HealComm healers")
b = reset()
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=5000    -- mage -2000
UNITS.party3.hp=6000                            -- warrior -6000
UNITS.player.hp=10000
INCOMING = {}                                   -- HealComm sees NOTHING
NATIVE_INC = {}
TICK()
T("no inbound at all: tank is the target", b.healUnit == "party3", b.healUnit)

-- a healer with no HealComm addon is casting on the tank. v2.5 was blind here.
NATIVE_INC = { party3 = 6000 }
TICK()
T("native prediction alone re-routes off the covered tank", b.healUnit == "party2", b.healUnit)

-- our own inbound must NOT count as someone else covering them
NATIVE_INC = { party3 = 6000 }
NATIVE_MINE = { party3 = 6000 }
TICK()
T("our own inbound is excluded from the native total", b.healUnit == "party3", b.healUnit)
NATIVE_MINE = {}

-- larger, not sum: both sources describing the same 6000 heal must not read 12000
INCOMING = { ["P-2"] = 2000 }
NATIVE_INC = { party2 = 2000, party3 = 6000 }
TICK()
T("both sources on one target take the larger, not the sum", b.action == nil, b.action)

NATIVE_API = false
INCOMING = {} NATIVE_INC = {}
b = reset()
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=5000
UNITS.party3.hp=6000 UNITS.player.hp=10000
TICK()
T("no native API: still works off HealComm alone", b.healUnit == "party3", b.healUnit)
NATIVE_API = true

P("v2.6 borrowed: heal sizes include gear")
b = reset()
SPELL_BONUS_HEALING = 0
TALENTS = {}
FIRE("SPELLS_CHANGED")
local baseLHW = (function()
  local lines = {} local rp=_G.print
  _G.print = function(t) lines[#lines+1]=tostring(t) end
  SLASH("heals") _G.print = rp
  for _,l in ipairs(lines) do local n=l:match("Lesser Healing Wave%b()%s+~(%d+)") if n then return tonumber(n) end end
end)()
T("no gear: heal size is the raw tooltip number", baseLHW == 951, baseLHW)

SPELL_BONUS_HEALING = 1500
TALENTS = { { name="Purification", rank=5, maxRank=5 } }
FIRE("SPELLS_CHANGED")
local gearedLHW = (function()
  local lines = {} local rp=_G.print
  _G.print = function(t) lines[#lines+1]=tostring(t) end
  SLASH("heals") _G.print = rp
  for _,l in ipairs(lines) do local n=l:match("Lesser Healing Wave%b()%s+~(%d+)") if n then return tonumber(n) end end
end)()
-- LHW casts in 1.5s -> coefficient 1.5/3.5, +1500 healing, x1.10 Purification
local want = math.floor((951 + 1500 * (1.5/3.5)) * 1.10)
T("gear + talents fold into the heal size", gearedLHW and math.abs(gearedLHW - want) <= 1,
  tostring(gearedLHW) .. " vs " .. want)
T("geared estimate is far above the tooltip", gearedLHW > baseLHW * 1.7, gearedLHW)

-- and the point of all of it: a modest hole now picks the SMALL heal
b = reset()
SPELL_BONUS_HEALING = 1500
TALENTS = { { name="Purification", rank=5, maxRank=5 } }
FIRE("SPELLS_CHANGED")
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=7000
UNITS.party3.hp=10500 UNITS.player.hp=10000     -- 1500 hole
INCOMING = {} NATIVE_INC = {}
TICK()
T("a 1500 hole picks the small heal, not the big one",
  b.healSpell and b.healSpell:find("Lesser"), b.healSpell)
SPELL_BONUS_HEALING = 0 TALENTS = {}

P("v2.6 borrowed: cast-bar claims last as long as the cast does")
b = reset()
UNITS.party1.dead=true UNITS.party1.hp=0
UNITS.party2.dead=true UNITS.party2.hp=0
CASTING = { party3 = "Ancestral Spirit" }
CAST_END_MS = { party3 = (NOW + 9) * 1000 }     -- a 10s rez, 9s left
UNITS.party3target = UNITS.party1               -- he is casting it on the priest
TICK()
local claimLine = (function()
  local lines = {} local rp=_G.print
  _G.print = function(t) lines[#lines+1]=tostring(t) end
  SLASH("claims") _G.print = rp
  return table.concat(lines, " ")
end)()
T("claim outlives the old flat 3s window", claimLine:find("1[01]s left") ~= nil, claimLine)
CASTING = {} CAST_END_MS = {}

P("v2.6 borrowed: binding does not touch saved keybinds")
b = reset()
SAVED_BINDS = {} OVERRIDE_BINDS = {}
SLASH("bind ALT-R")
T("an override binding is created", OVERRIDE_BINDS["ALT-R"] ~= nil, OVERRIDE_BINDS["ALT-R"])
T("the user\'s saved keybinds are untouched", next(SAVED_BINDS) == nil)
T("the key is remembered for the next login", _G.BiSRezDB.bindKey == "ALT-R", _G.BiSRezDB.bindKey)
OVERRIDE_BINDS = {}
FIRE("PLAYER_ENTERING_WORLD")                    -- /reload wipes override binds
T("re-applied after a reload", OVERRIDE_BINDS["ALT-R"] ~= nil)
SLASH("unbind")
T("unbind clears it", next(OVERRIDE_BINDS) == nil and _G.BiSRezDB.bindKey == nil)

P("identity rule: in a raid, raid1 IS the player")
b = reset()
RaidMode(4)
UNITS.raid2.dead = true UNITS.raid2.hp = 0
TICK()
T("the player is never his own rez target", b.currentUnit ~= "raid1", b.currentUnit)
T("a real corpse in the raid is still found", b.action == "rez", b.action)

P("v2.7 options window: it builds, and every surface paints")
b = reset()
local C = _G.BiSRez
local okOpen, errOpen = pcall(C.OpenConfig)
T("window opens without error", okOpen, errOpen)
T("named BiSRezConfig", _G.BiSRezConfig ~= nil)
T("registered as a special frame (Esc closes it)", (function()
    for _, n in ipairs(UISpecialFrames) do if n == "BiSRezConfig" then return true end end
  end)())
T("all four tabs switch", (function()
    for _, t in ipairs({ "Rez", "Support", "Leaderboard", "Button" }) do
      local ok = pcall(C.ShowConfigTab, t)
      if not ok then return false end
    end
    return true
  end)())
T("toggling closes it", (function() C.ToggleConfig() return not _G.BiSRezConfig:IsShown() end)())
T("toggling again reopens it", (function() C.ToggleConfig() return _G.BiSRezConfig:IsShown() end)())

-- every control the pages are supposed to expose
local WANT = { "mode","at","rank","autoheal","autodrink","rescan","healsdump",
               "champ","keep","guild","score","sync","resetscore",
               "shown","locked","resetpos","hidecombat","minimapbtn","rezzerlist",
               "clicks","verbose","list","claims","diag" }
local GONE = { "window", "windowlock", "windowreset" }
local have = {}
for _, id in ipairs(C.ConfigIds()) do have[id] = true end
local missing = {}
for _, id in ipairs(WANT) do if not have[id] then missing[#missing+1] = id end end
T("every expected control id exists", #missing == 0, table.concat(missing, ","))
local stale = {}
for _, id in ipairs(GONE) do if have[id] then stale[#stale+1] = id end end
T("the folded-away duplicates are gone", #stale == 0, table.concat(stale, ","))

P("v2.7 options window: every control writes the SAME saved variable")
-- checkboxes: db key, and whether the control reads inverted
local CHECKS = {
  { id="rank",      key="useRank",   invert=false },
  { id="autoheal",  key="autoHeal",  invert=false },
  { id="autodrink", key="autoDrink", invert=false },
  { id="keep",      key="keepScores",invert=false },
  { id="guild",     key="guildOnly", invert=false },
  { id="verbose",   key="verbose",   invert=false },
  { id="champ",     key="hideChamp", invert=true  },
  { id="shown",     key="hidden",    invert=true  },
  { id="hidecombat",key="hideInCombat", invert=false },
  { id="locked",    key="locked",    invert=false },
}
local bad = {}
for _, c in ipairs(CHECKS) do
  -- explicit if/else, NOT `c.invert and false or true` -- that idiom always
  -- yields true, which is the same and/or trap the window itself has to dodge
  -- when passing colours. It made this test lie about two controls.
  local wantOn, wantOff
  if c.invert then wantOn, wantOff = false, true else wantOn, wantOff = true, false end
  local was = C.ConfigGet(c.id)
  C.ConfigSet(c.id, true)
  if _G.BiSRezDB[c.key] ~= wantOn then bad[#bad+1] = c.id .. "=on->" .. tostring(_G.BiSRezDB[c.key]) end
  if C.ConfigGet(c.id) ~= true then bad[#bad+1] = c.id .. " get(on)" end
  C.ConfigSet(c.id, false)
  if _G.BiSRezDB[c.key] ~= wantOff then bad[#bad+1] = c.id .. "=off->" .. tostring(_G.BiSRezDB[c.key]) end
  if C.ConfigGet(c.id) ~= false then bad[#bad+1] = c.id .. " get(off)" end
  -- put it back. Several of these have real side effects now (the `shown` one
  -- actually hides the button), and a flipped leftover poisons later sections.
  C.ConfigSet(c.id, was)
end
T("all 9 checkboxes round-trip through the real saved variable", #bad == 0, table.concat(bad, " "))

-- segmented controls
C.ConfigSet("mode", "spell")
T("mode seg writes db.mode", _G.BiSRezDB.mode == "spell" and C.ConfigGet("mode") == "spell", _G.BiSRezDB.mode)
C.ConfigSet("mode", "macro")
T("mode seg writes it back", _G.BiSRezDB.mode == "macro" and C.ConfigGet("mode") == "macro", _G.BiSRezDB.mode)

C.ConfigSet("at", true)
T("macro-syntax seg writes db.useAtShorthand", _G.BiSRezDB.useAtShorthand == true and C.ConfigGet("at") == true)
C.ConfigSet("at", false)
T("...and back", _G.BiSRezDB.useAtShorthand == false and C.ConfigGet("at") == false)

C.ConfigSet("clicks", "both")
T("click-edge seg writes db.clickMode", _G.BiSRezDB.clickMode == "both", _G.BiSRezDB.clickMode)
C.ConfigSet("clicks", "down")
T("...and back", _G.BiSRezDB.clickMode == "down", _G.BiSRezDB.clickMode)

INCOMBAT = true
C.ConfigSet("clicks", "up")
T("click edge refuses to change in combat", _G.BiSRezDB.clickMode == "down", _G.BiSRezDB.clickMode)
INCOMBAT = false

-- the toggles must agree with what the slash commands already do
b = reset()
SLASH("rank")
local viaSlash = _G.BiSRezDB.useRank
T("slash and window read the same variable", C.ConfigGet("rank") == viaSlash, tostring(viaSlash))
SLASH("at")
T("...for the other one too", C.ConfigGet("at") == (_G.BiSRezDB.useAtShorthand and true or false))

-- action buttons must not throw
b = reset()
local threw = {}
for _, id in ipairs({ "rescan", "healsdump", "score", "sync", "resetscore",
                      "resetpos", "list", "claims", "diag" }) do
  local ok = pcall(C.ConfigSet, id, nil)
  if not ok then threw[#threw+1] = id end
end
T("all 9 action buttons run without error", #threw == 0, table.concat(threw, ","))

-- Refresh must survive being called with an empty roster, no heals, no board
b = reset()
PARTY_N = 0
healRanksProbe = nil
C.OpenConfig()
T("Refresh survives a solo, empty-board state", pcall(_G.BiSRezConfig.Refresh, _G.BiSRezConfig))
PARTY_N = 3

P("v2.7 the SetColorTexture trap")
T("strict stub rejects a truncated colour", (function()
    local t = CreateFrame("Texture")
    return not pcall(function() t:SetColorTexture(true and 0.5 or 0.1) end)
  end)())
T("...and accepts a full argument list", (function()
    local t = CreateFrame("Texture")
    local ok = pcall(function() t:SetColorTexture(0.7, 0.5, 1, 0.18) end)
    local c = t:GetColor()
    return ok and c and c[1] == 0.7 and c[4] == 0.18
  end)())

P("v2.8 stolen from Innervate: the roster blip")
b = reset()
_G.BiSRezDB.scores = { Kumlust = 5, Dps12 = 2 }
_G.BiSRezDB.keepScores = false
FIRE("GROUP_ROSTER_UPDATE")                     -- we are in a party of 3
T("board is populated", next(_G.BiSRezDB.scores) ~= nil)
PARTY_N = 0                                     -- ZONE IN: the roster reads empty
FIRE("GROUP_ROSTER_UPDATE")
T("an empty roster right after a real one does NOT clear the board",
  _G.BiSRezDB.scores.Kumlust == 5, tostring(_G.BiSRezDB.scores.Kumlust))
PARTY_N = 3                                     -- ...and it comes back
FIRE("GROUP_ROSTER_UPDATE")
T("the board survived the zone-in", _G.BiSRezDB.scores.Kumlust == 5)

-- but a real departure, once the blip window has passed, still clears it
b = reset()
_G.BiSRezDB.scores = { Kumlust = 5 }
_G.BiSRezDB.keepScores = false
FIRE("GROUP_ROSTER_UPDATE")
PARTY_N = 0
FIRE("GROUP_ROSTER_UPDATE")
NOW = NOW + 11                                  -- past the 10s grace
FIRE("GROUP_ROSTER_UPDATE")
T("a real departure still clears the board", next(_G.BiSRezDB.scores) == nil)
PARTY_N = 3

P("v2.8 stolen from Innervate: the typed protocol")
b = reset()
SENT = {}
TICK() CLICK()
FIRE("UNIT_SPELLCAST_START","player",nil,2008)
T("a claim goes out as PROTO|CLAIM|guid",
  SENT_LAST and SENT_LAST.msg:match("^1|CLAIM|") ~= nil, SENT_LAST and SENT_LAST.msg)
T("...on a group channel", SENT_LAST and (SENT_LAST.chan == "PARTY" or SENT_LAST.chan == "RAID"),
  SENT_LAST and SENT_LAST.chan)

-- a whispered claim from outside the group must not touch a corpse
b = reset()
FIRE("CHAT_MSG_ADDON", "BiSRez", "1|CLAIM|P-1", "WHISPER", "Dps7")
local claimsAfter = (function()
  local lines = {} local rp=_G.print
  _G.print = function(t) lines[#lines+1]=tostring(t) end
  SLASH("claims") _G.print = rp
  return table.concat(lines," ")
end)()
T("a WHISPERed claim is ignored", claimsAfter:find("none") ~= nil, claimsAfter)

-- and one from a stranger on the party channel, who is not in our group
FIRE("CHAT_MSG_ADDON", "BiSRez", "1|CLAIM|P-1", "PARTY", "Nobody")
claimsAfter = (function()
  local lines = {} local rp=_G.print
  _G.print = function(t) lines[#lines+1]=tostring(t) end
  SLASH("claims") _G.print = rp
  return table.concat(lines," ")
end)()
T("a claim from a non-member is ignored", claimsAfter:find("none") ~= nil, claimsAfter)

-- a real group member's claim lands
FIRE("CHAT_MSG_ADDON", "BiSRez", "1|CLAIM|P-1", "PARTY", "Tank2")
claimsAfter = (function()
  local lines = {} local rp=_G.print
  _G.print = function(t) lines[#lines+1]=tostring(t) end
  SLASH("claims") _G.print = rp
  return table.concat(lines," ")
end)()
T("a group member's claim IS honoured", claimsAfter:find("Tank2") ~= nil, claimsAfter)

-- an oversized message is refused rather than silently dropped by the client
b = reset()
_G.BiSRezDB.verbose = true
SENT = {}
local before = #_G.__H.out
_G.BiSRez.Send("SCORE", string.rep("x", 300))
T("an over-long message is not sent", #SENT == 0)
T("...and says so instead of vanishing", #_G.__H.out > before)
_G.BiSRezDB.verbose = false

P("v2.8 stolen from Innervate: other people's rez cooldowns")
b = reset()
T("nobody known at first", #_G.BiSRez.RezzerList() == 0)
FIRE("CHAT_MSG_ADDON", "BiSRez", "1|HELLO|2.8|DRUID|900|0", "PARTY", "Tank2")
local list = _G.BiSRez.RezzerList()
T("a HELLO puts them on the rezzer list", #list == 1 and list[1].name == "Tank2", #list)
T("their class came across", list[1].class == "DRUID", list[1].class)
T("their cooldown came across", list[1].cd > 890 and list[1].cd <= 900, list[1].cd)
T("a druid on a 15-minute Rebirth is not counted ready", _G.BiSRez.RezzersReady() == 0)

FIRE("CHAT_MSG_ADDON", "BiSRez", "1|STATE|PRIEST|0|0", "PARTY", "Healer6")
T("a second rezzer, ready", _G.BiSRez.RezzersReady() == 1, _G.BiSRez.RezzersReady())
FIRE("CHAT_MSG_ADDON", "BiSRez", "1|STATE|PRIEST|0|1", "PARTY", "Healer6")
T("a rezzer mid-cast is not counted ready", _G.BiSRez.RezzersReady() == 0)

NOW = NOW + 400                                  -- the druid's Rebirth comes back
T("a cooldown ticks down on its own", _G.BiSRez.RezzerCooldown("Tank2") < 520,
  _G.BiSRez.RezzerCooldown("Tank2"))

-- our OWN cooldown is read live from the client, not assumed
b = reset()
SPELL_CD["Ancestral Spirit"] = { NOW, 600 }
T("our own rez cooldown is read from the client", _G.BiSRez.MyRezCooldown() > 590,
  _G.BiSRez.MyRezCooldown())
SPELL_CD["Ancestral Spirit"] = { NOW, 1.5 }
T("the global cooldown is not mistaken for it", _G.BiSRez.MyRezCooldown() == 0)
SPELL_CD = {}

P("v2.8 stolen from Innervate: the corpse window")
b = reset()
T("the window is built at login", _G.BiSRezWindow ~= nil)
local W = _G.BiSRez.Window
_G.BiSRezDB.useRank = false
T("both corpses have a face", (function()
    W:Bind()
    local n = 0
    for i = 1, W.MAX do if W.squares[i].pname then n = n + 1 end end
    return n
  end)() == 2)
T("the priest sorts above the mage", W.squares[1].pname == "Healer6", W.squares[1].pname)
T("a face is bound by NAME, never a raid slot",
  W.squares[1]:GetAttribute("unit") == "Healer6", W.squares[1]:GetAttribute("unit"))
T("...and casts the rez", W.squares[1]:GetAttribute("*spell1") == "Ancestral Spirit",
  W.squares[1]:GetAttribute("*spell1"))
T("an empty slot is bound to nothing", W.squares[10]:GetAttribute("unit") == "none")

-- a name the client cannot resolve leaves the face UNBOUND rather than wrong
UNITS.party1.name = "Dps8"
UNITS.party1.__hidden = true
local realExists = _G.UnitExists
_G.UnitExists = function(u) if u == "Dps8" then return false end return realExists(u) end
W:Bind()
local ghost
for i = 1, W.MAX do if W.squares[i].pname == "Dps8" then ghost = W.squares[i] end end
T("an unresolvable name leaves the face unbound", ghost and ghost.unbound == true)
T("...and it targets nothing", ghost and ghost:GetAttribute("unit") == "none",
  ghost and ghost:GetAttribute("unit"))
_G.UnitExists = realExists
UNITS.party1.name = "Healer6"

-- combat: repaint yes, rebind never
b = reset()
W = _G.BiSRez.Window
W:Bind()
local boundBefore = W.squares[1]:GetAttribute("unit")
INCOMBAT = true
UNITS.party3.dead = true                        -- a third person dies mid-fight
local okTick = pcall(TICK)
T("a death in combat does not throw", okTick)
T("...and does not rebind a secure button", W.squares[1]:GetAttribute("unit") == boundBefore,
  W.squares[1]:GetAttribute("unit"))
T("repainting in combat is still fine", pcall(function() W:Refresh() end))
INCOMBAT = false
FIRE("PLAYER_REGEN_ENABLED")                    -- the pull ends: now it rebinds
T("the deferred rebind happens when combat ends", (function()
    local n = 0
    for i = 1, W.MAX do if W.squares[i].pname then n = n + 1 end end
    return n
  end)() == 3)

-- closed means deaf, not just invisible
b = reset()
W = _G.BiSRez.Window
W:Bind()
W:SetShown(false)
T("closing drops the window to alpha 0", W.frame:GetAlpha() == 0)
T("...the header stops taking the mouse", W.head.__mouse == false)
T("...and so do the faces", W.squares[1].__mouse == false)
W:SetShown(true)
T("reopening makes it live again", W.frame:GetAlpha() == 1 and W.head.__mouse == true)

T("click registration follows the client cvar", (function()
    CVARS.ActionButtonUseKeyDown = "0"
    local bb = CreateFrame("Button", nil, nil, "SecureActionButtonTemplate")
    _G.BiSRez.ApplyClicks(bb)
    local up = bb.__clicks
    CVARS.ActionButtonUseKeyDown = "1"
    _G.BiSRez.ApplyClicks(bb)
    return up == "AnyUp" and bb.__clicks == "AnyDown"
  end)())

P("v2.9 a druid's Rebirth is never spent on recovery")
PLAYER_CLASS = "DRUID"
dofile("bisrez-harness.lua")
FIRE("ADDON_LOADED","BiSRez") FIRE("PLAYER_LOGIN")
b = _G.BiSRezButton
UNITS.party1.dead = true UNITS.party1.hp = 0
UNITS.party2.dead = true UNITS.party2.hp = 0
TICK()
T("a druid is never offered a rez", b.action ~= "rez", b.action)
T("...even with corpses on the floor", b.currentUnit == nil, b.currentUnit)
T("the button is NOT hidden -- heals and drinks still work", b:IsShown())
UNITS.party1.dead=false UNITS.party1.hp=9000
UNITS.party2.dead=false UNITS.party2.hp=7000
UNITS.party3.hp = 1000
TICK()
T("a druid still heals", b.action == "heal", b.action)
PLAYER_MANA = 10
TICK()
T("a druid still drinks", b.action == "drink", b.action)
PLAYER_MANA = 5000
T("a druid broadcasts no rez cooldown", _G.BiSRez.MyRezCooldown() == 0)
PLAYER_CLASS = "SHAMAN"

P("v2.9 rez order is a throughput order")
b = reset()
UNITS.party1.class = "MAGE"    UNITS.party1.dead = true
UNITS.party2.class = "PRIEST"  UNITS.party2.dead = true
UNITS.party3.class = "ROGUE"   UNITS.party3.dead = true
UNIT_MANA_MAX = { party1 = 10000, party2 = 10000, party3 = 10000, player = 10000 }
UNIT_MANA = { player = 9000 }                  -- we are a shaman with mana
TICK()
T("with the rezzers wet, the priest goes first",
  select(2, UnitClass(b.currentUnit)) == "PRIEST", b.currentUnit)

-- dry, but still able to afford the cast: 2000 of 10000 is under the 30% line
-- and over the 1200 the rez costs. (Dropping to 100 would make the button
-- drink instead, which tests nothing about ordering.)
UNIT_MANA = { player = 2000 }
TICK()
T("with every rezzer dry, the mage goes first (water beats another body)",
  select(2, UnitClass(b.currentUnit)) == "MAGE", b.currentUnit)
UNIT_MANA = {} UNIT_MANA_MAX = {}
TICK()
T("with no mana readable at all it does NOT assume dry",
  select(2, UnitClass(b.currentUnit)) == "PRIEST", b.currentUnit)

-- a released player is running back anyway; they sort behind every body
b = reset()
UNITS.party1.class = "ROGUE"  UNITS.party1.dead = true
UNITS.party2.class = "PRIEST" UNITS.party2.dead = false
local realGhost = _G.UnitIsGhost
_G.UnitIsGhost = function(u) return u == "party2" end
_G.UnitIsDead = function(u) return UNITS[u] and UNITS[u].dead or false end
TICK()
T("a released priest sorts behind a rogue's body",
  select(2, UnitClass(b.currentUnit)) == "ROGUE", b.currentUnit)
_G.UnitIsGhost = realGhost

P("v3.0 hidden in combat rather than engineered around")
b = reset()
T("one state driver, on the window",
  STATE_DRIVERS[_G.BiSRezWindow] == "[combat] hide; show", STATE_DRIVERS[_G.BiSRezWindow])
T("...and none on the button, which is now a child of it",
  STATE_DRIVERS[_G.BiSRezButton] == nil, STATE_DRIVERS[_G.BiSRezButton])
_G.BiSRezDB.hideInCombat = false
_G.BiSRez.ApplyVisibility()
T("turning it off removes the driver", STATE_DRIVERS[_G.BiSRezWindow] == nil)
_G.BiSRezDB.hideInCombat = true
_G.BiSRezDB.hidden = true
_G.BiSRez.ApplyVisibility()
T("something you hid stays hidden, driver or not",
  STATE_DRIVERS[_G.BiSRezWindow] == nil and _G.BiSRezWindow:IsShown() == false)
_G.BiSRezDB.hidden = false
_G.BiSRez.ApplyVisibility()

P("v2.9 wipe protection")
b = reset()
T("nothing up to start with", _G.BiSRez.WipeProtection() == 0)

-- a shaman with Reincarnation and an Ankh
BAG_ITEMS = { [17030] = true }
FIRE("SPELLS_CHANGED")
T("Reincarnation with an Ankh counts", _G.BiSRez.WipeProtection() == 1,
  _G.BiSRez.WipeProtection())
BAG_ITEMS = {}
T("Reincarnation with no Ankh does NOT count", _G.BiSRez.WipeProtection() == 0)
BAG_ITEMS = { [17030] = true }
SPELL_CD["Reincarnation"] = { NOW, 1800 }
T("Reincarnation on cooldown does not count", _G.BiSRez.WipeProtection() == 0)
SPELL_CD = {}

-- a soulstone only counts on somebody who can actually rez
SOULSTONE = true
BAG_ITEMS = {}
T("a soulstone on a rezzer counts", _G.BiSRez.WipeProtection() == 1)
PLAYER_CLASS = "ROGUE"
dofile("bisrez-harness.lua")
FIRE("ADDON_LOADED","BiSRez") FIRE("PLAYER_LOGIN")
SOULSTONE = true
T("a soulstone on a rogue does NOT count", _G.BiSRez.WipeProtection() == 0)
SOULSTONE = false
PLAYER_CLASS = "SHAMAN"

-- peers contribute theirs, over the wire
b = reset()
FIRE("CHAT_MSG_ADDON","BiSRez","1|HELLO|2.9|PALADIN|0|0|D","PARTY","Healer6")
local wn, wd = _G.BiSRez.WipeProtection()
T("a paladin's Divine Intervention arrives over the wire", wn == 1, wn)
T("...and is named", wd[1] and wd[1].what == "Divine Intervention", wd[1] and wd[1].what)
FIRE("CHAT_MSG_ADDON","BiSRez","1|STATE|PRIEST|0|0|S","PARTY","Tank2")
T("a second peer's soulstone adds to it", _G.BiSRez.WipeProtection() == 2)
FIRE("CHAT_MSG_ADDON","BiSRez","1|STATE|PRIEST|0|0|","PARTY","Tank2")
T("and drops off when they lose it", _G.BiSRez.WipeProtection() == 1)

-- a v2.8 client sends no wipe field at all: it must not break or invent one
b = reset()
FIRE("CHAT_MSG_ADDON","BiSRez","1|HELLO|2.8|PRIEST|0|0","PARTY","Healer6")
T("an older client with no wipe field still lands as a rezzer",
  #_G.BiSRez.RezzerList() == 1)
T("...and contributes no phantom protection", _G.BiSRez.WipeProtection() == 0)

P("v2.9 the one sound cue")
b = reset()
UNITS.player.dead = true
SOUNDS = {}
FIRE("CHAT_MSG_ADDON","BiSRez","1|CLAIM|P-player","PARTY","Healer6")
T("a rez claimed on YOUR corpse makes a noise", #SOUNDS == 1, #SOUNDS)
FIRE("CHAT_MSG_ADDON","BiSRez","1|CLAIM|P-player","PARTY","Tank2")
T("...but only once per corpse, not once per message", #SOUNDS == 1, #SOUNDS)
NOW = NOW + 20
SOUNDS = {}
UNITS.player.dead = false
FIRE("CHAT_MSG_ADDON","BiSRez","1|CLAIM|P-player","PARTY","Healer6")
T("no noise when you are alive", #SOUNDS == 0)
UNITS.player.dead = true
SOUNDS = {}
_G.BiSRezDB.sound = false
FIRE("CHAT_MSG_ADDON","BiSRez","1|CLAIM|P-player","PARTY","Healer6")
T("and none at all with sound off", #SOUNDS == 0)
_G.BiSRezDB.sound = nil
UNITS.player.dead = false

P("v2.9 minimap button")
b = reset()
T("a coin is on the ring", _G.BiSRezMinimapButton ~= nil)
_G.BiSRez.Minimap:Set(false)
T("it can be turned off", _G.BiSRezMinimapButton:IsShown() == false)
_G.BiSRez.Minimap:Set(true)
T("...and back on", _G.BiSRezMinimapButton:IsShown() == true)
T("dragging never writes nan into the db", (function()
    MINIMAP_SCALE = 0            -- a zero scale used to produce nan
    _G.BiSRez.Minimap.drag()
    local a = _G.BiSRezDB.minimapAngle
    MINIMAP_SCALE = 1
    return a == nil or a == a
  end)())

P("v3.0 one window, not three pieces of furniture")
b = reset()
local W = _G.BiSRez.Window
T("the button is a child of the window", _G.BiSRezButton.__parent == _G.BiSRezWindow,
  tostring(_G.BiSRezButton.__parent))
T("the window is tall enough for the action row",
  select(2, _G.BiSRezWindow:GetSize()) >= W.HEADER + W.BTN, select(2, _G.BiSRezWindow:GetSize()))
T("it is wide enough for the button plus a name beside it",
  select(1, _G.BiSRezWindow:GetSize()) >= W.PAD * 2 + W.BTN + 8, select(1, _G.BiSRezWindow:GetSize()))

-- one switch, not two
_G.BiSRez.Window:SetShown(false)
T("hiding writes the single flag", _G.BiSRezDB.hidden == true)
T("...and there is no second flag any more", _G.BiSRezDB.windowHidden == nil)
T("the window really is hidden", _G.BiSRezWindow:GetAlpha() == 0)
_G.BiSRez.Window:SetShown(true)
T("showing it again brings the whole thing back",
  _G.BiSRezDB.hidden == false and _G.BiSRezWindow:GetAlpha() == 1)

-- /bisrez show, /bisrez hide and /bisrez window are the same switch now
SLASH("hide")
T("/bisrez hide hides everything", _G.BiSRez.Window:IsHidden())
SLASH("show")
T("/bisrez show brings it back", not _G.BiSRez.Window:IsHidden())
SLASH("window")
T("/bisrez window is the same switch", _G.BiSRez.Window:IsHidden())
SLASH("window")

-- dragging the button moves the window, it does not tear the button off
b = reset()
DRAGGING = nil
_G.BiSRezButton.__scripts.OnDragStart(_G.BiSRezButton)
T("dragging the button starts the WINDOW moving", DRAGGING == _G.BiSRezWindow,
  tostring(DRAGGING))
_G.BiSRezButton.__scripts.OnDragStop(_G.BiSRezButton)
T("...and dropping it saves the window position", _G.BiSRezDB.windowPos ~= nil)
_G.BiSRezDB.locked = true
DRAGGING = nil
_G.BiSRezButton.__scripts.OnDragStart(_G.BiSRezButton)
T("locked means locked", DRAGGING == nil)
_G.BiSRezDB.locked = false

P("v3.0 the old split settings are folded in, not lost")
dofile("bisrez-harness.lua")
_G.BiSRezDB = { windowHidden = true, windowLocked = true, pos = { "CENTER", "CENTER", 10, 20 } }
FIRE("ADDON_LOADED","BiSRez") FIRE("PLAYER_LOGIN")
T("a window you had hidden stays hidden", _G.BiSRezDB.hidden == true)
T("a window you had locked stays locked", _G.BiSRezDB.locked == true)
T("the old keys are cleared", _G.BiSRezDB.windowHidden == nil and _G.BiSRezDB.windowLocked == nil)
T("the old button position becomes the window position",
  _G.BiSRezDB.windowPos ~= nil and _G.BiSRezDB.pos == nil)

dofile("bisrez-harness.lua")
_G.BiSRezDB = { hidden = true }
FIRE("ADDON_LOADED","BiSRez") FIRE("PLAYER_LOGIN")
T("a button you had hidden keeps the whole thing hidden", _G.BiSRezDB.hidden == true)

P("")
P(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
