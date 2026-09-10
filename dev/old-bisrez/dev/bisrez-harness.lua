-- BiSRez harness: mocks a TBC-Anniversary-ish client on real Lua 5.1
-- Goals: run the file, fire every event + slash command, detect global leaks.

local out = {}
local realprint = print
function print(...)
  local t = {}
  for i=1,select('#',...) do t[#t+1] = tostring((select(i,...))) end
  out[#out+1] = table.concat(t, " ")
end

-- ============ time ============
NOW = 1000
function GetTime() return NOW end

-- ============ frame mock ============
local frames = {}
local FrameMT = {}
FrameMT.__index = FrameMT
local function noop() end
local passthru = {
  "SetPoint","ClearAllPoints","SetMovable","RegisterForDrag",
  "SetAllPoints","SetTexture","SetDesaturated",
  "SetText","SetTextColor","SetJustifyH","SetFrameStrata","Show","Hide",
  "SetOwner","AddLine","NumLines","SetChecked","GetChecked","SetSpellBookItem","SetScale",
  "SetBackdrop","SetID","GetID","SetHitRectInsets","SetNormalTexture",
  "SetHighlightTexture","SetPushedTexture","SetDisabledTexture","SetVertexColor",
}
for _,m in ipairs(passthru) do FrameMT[m] = noop end
function FrameMT:EnableMouse(v) self.__mouse = v and true or false end
function FrameMT:IsMouseEnabled() return self.__mouse and true or false end
function FrameMT:RegisterForClicks(a, b) self.__clicks = b and (a.."+"..b) or a end
function FrameMT:SetAlpha(a) self.__alpha = a end
function FrameMT:GetAlpha() return self.__alpha or 1 end
function FrameMT:SetParent(p) self.__parent = p end
function FrameMT:GetParent() return self.__parent end
-- record who is being dragged, so a test can prove the button moves the WINDOW
function FrameMT:StartMoving() DRAGGING = self end
function FrameMT:StopMovingOrSizing() end
function FrameMT:GetSize() return self.__w or 0, self.__h or 0 end
function FrameMT:GetWidth() return self.__w or 0 end
function FrameMT:GetHeight() return self.__h or 0 end
function FrameMT:SetSize(w, h) self.__w, self.__h = w, h end
function FrameMT:SetWidth(w) self.__w = w end
function FrameMT:SetHeight(h) self.__h = h end
function FrameMT:GetName() return self.__name end
function FrameMT:IsShown() return self.__shown end
function FrameMT:Show() self.__shown = true end
function FrameMT:Hide() self.__shown = false end
function FrameMT:GetPoint() return "CENTER", nil, "CENTER", 0, -120 end
function FrameMT:SetScript(k, fn) self.__scripts[k] = fn end
function FrameMT:GetScript(k) return self.__scripts[k] end
function FrameMT:HookScript(k, fn) self.__scripts[k] = fn end
function FrameMT:RegisterEvent(ev)
  if not KNOWN_EVENTS[ev] then error("unknown event: "..tostring(ev)) end
  self.__events[ev] = true
end
function FrameMT:UnregisterEvent(ev) self.__events[ev] = nil end
function FrameMT:SetAttribute(k,v)
  if INCOMBAT then error("SetAttribute in combat (protected)") end
  self.__attr[k]=v
end
function FrameMT:GetAttribute(k) return self.__attr[k] end
function FrameMT:CreateTexture() return CreateFrame("Texture") end
function FrameMT:CreateFontString() return CreateFrame("FontString") end
function FrameMT:GetChecked() return self.__checked end
function FrameMT:SetChecked(v) self.__checked = v end
function FrameMT:GetText() return self.__text end
function FrameMT:NumLines() return 0 end

-- STRICT ON PURPOSE. SetColorTexture takes r,g,b[,a] and the client throws if
-- it gets fewer -- which is what `on and T.rgba(x) or shade(y)` does, since
-- `and`/`or` truncate a multi-return to one value. A stub that accepts anything
-- turns a window-killing live crash into a silent pass. This one records the
-- colour so a test can assert on the PAINT, not on the call.
function FrameMT:SetColorTexture(r, g, b, a)
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
    error("SetColorTexture needs colorR, colorG, colorB [, colorA] -- got "
          .. type(r) .. "," .. type(g) .. "," .. type(b), 2)
  end
  self.__color = { r, g, b, a }
end
function FrameMT:GetColor() return self.__color end
function FrameMT:SetShown(v) self.__shown = v and true or false end
function FrameMT:SetFont(f, size, flags) self.__font = { f, size, flags } end
function FrameMT:SetClampedToScreen() end
function FrameMT:SetFrameLevel(l) self.__level = l end
function FrameMT:GetFrameLevel() return self.__level or 1 end
function FrameMT:SetTexCoord() end
function FrameMT:SetMinMaxValues(lo, hi) self.__lo, self.__hi = lo, hi end
function FrameMT:SetValueStep(v) self.__step = v end
function FrameMT:SetObeyStepOnDrag() end
function FrameMT:SetOrientation() end
function FrameMT:SetThumbTexture() end
function FrameMT:SetValue(v) self.__value = v end
function FrameMT:GetValue() return self.__value or 0 end
function FrameMT:SetText(t) self.__text = t end
function FrameMT:SetClampedToScreen() end
function FrameMT:CreateAnimationGroup() return CreateFrame("AnimGroup") end
function FrameMT:CreateAnimation() return CreateFrame("Anim") end
function FrameMT:SetLooping() end
function FrameMT:SetDuration() end
function FrameMT:SetFromAlpha() end
function FrameMT:SetToAlpha() end
function FrameMT:Play() end
function FrameMT:Stop() end
function FrameMT:GetFont() return self.__font and self.__font[1] end
function FrameMT:SetFontObject(o) self.__fontobj = o end

KNOWN_EVENTS = {}
for _,e in ipairs({
  "ADDON_LOADED","PLAYER_LOGIN","PLAYER_ENTERING_WORLD","SPELLS_CHANGED",
  "PLAYER_EQUIPMENT_CHANGED","COMBAT_LOG_EVENT_UNFILTERED","UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_START","UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_STOP","CHAT_MSG_ADDON","GROUP_ROSTER_UPDATE","RAID_ROSTER_UPDATE",
  "PARTY_MEMBERS_CHANGED","UI_ERROR_MESSAGE","PLAYER_REGEN_ENABLED",
}) do KNOWN_EVENTS[e]=true end
-- deliberately NOT known (matches the client that threw): LEARNED_SPELL_IN_TAB

function CreateFrame(ftype, name, parent, template)
  local f = setmetatable({__name=name, __scripts={}, __events={}, __attr={}, __shown=true, __type=ftype}, FrameMT)
  if name then _G[name] = f end
  frames[#frames+1] = f
  return f
end

UIParent = CreateFrame("Frame","UIParent")
GameTooltip = CreateFrame("GameTooltip","GameTooltip")
UISpecialFrames = {}
-- secure visibility drivers: record the condition so a test can assert on it
STATE_DRIVERS = {}
function RegisterStateDriver(f, state, cond) STATE_DRIVERS[f] = cond end
function UnregisterStateDriver(f, state) STATE_DRIVERS[f] = nil end
SOUNDS = {}
function PlaySound(id, chan) SOUNDS[#SOUNDS+1] = id end
function IsShiftKeyDown() return false end
MINIMAP_SCALE = 1
Minimap = CreateFrame("Frame", "Minimap")
function Minimap:GetCenter() return 100, 100 end
function Minimap:GetEffectiveScale() return MINIMAP_SCALE end
function GetCursorPosition() return 150, 150 end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
CLASS_ICON_TCOORDS = {
  SHAMAN={0,0.25,0.25,0.5}, MAGE={0.25,0.5,0,0.25}, PRIEST={0.5,0.75,0.25,0.5},
  WARRIOR={0,0.25,0,0.25}, PALADIN={0,0.25,0.5,0.75}, DRUID={0.75,1,0,0.25},
  HUNTER={0,0.25,0.25,0.5}, WARLOCK={0.75,1,0.25,0.5}, ROGUE={0.5,0.75,0,0.25},
}
-- click registration follows this cvar; the window reads it rather than
-- hardcoding a side (BiS Innervate's ApplyClicks)
CVARS = { ActionButtonUseKeyDown = "1" }
function GetCVar(k) return CVARS[k] end
function GetCVarBool(k) return CVARS[k] == "1" end
function GetUnitName(unit, showRealm)
  local d = UNITS[unit]
  if not d then return nil end
  if showRealm and d.realm then return d.name .. "-" .. d.realm end
  return d.name
end
-- rez cooldowns: Rebirth has one, the rest do not
SPELL_CD = {}          -- [spellName] = { start, duration }
function GetSpellCooldown(name)
  local c = SPELL_CD[name]
  if not c then return 0, 0 end
  return c[1], c[2]
end
function GetAddOnMetadata(a, k) return "test" end
function tinsert(t,v) table.insert(t,v) end
INCOMBAT = false
function InCombatLockdown() return INCOMBAT end

-- ============ roster ============
-- player = Shaman. party1 Priest (dead), party2 Mage (dead), party3 Warrior (alive, hurt)
-- The addon captures the player's class ONCE, at file load. A test that wants
-- a druid has to say so before the harness loads BiSRez.lua -- setting
-- UNITS.player.class afterwards is too late and silently tests a shaman.
-- Survives a harness reload on purpose, like HEALCOMM.
if PLAYER_CLASS == nil then PLAYER_CLASS = "SHAMAN" end
UNITS = {
  player = {name="Kumlust", class=PLAYER_CLASS, guid="P-player", dead=false, hp=5000, hpmax=10000, connected=true, visible=true, player=true},
  party1 = {name="Holypal", class="PRIEST", guid="P-1", dead=true,  hp=0, hpmax=9000, connected=true, visible=true, player=true},
  party2 = {name="Frostay", class="MAGE",   guid="P-2", dead=true,  hp=0, hpmax=7000, connected=true, visible=true, player=true},
  party3 = {name="Tankee",  class="WARRIOR",guid="P-3", dead=false, hp=3000, hpmax=12000, connected=true, visible=true, player=true},
  target = nil,
}
PARTY_N = 3
RAID_N = 0
-- IDENTITY RULE, straight from the BiS Healing testing notes: in a RAID the
-- player is also raid<N>. A mock that keeps them separate lets "that\'s you"
-- bugs pass. RaidMode() rebuilds UNITS so raid1 IS the player, same GUID.
function RaidMode(n)
  RAID_N = n or 4
  PARTY_N = 0
  UNITS.raid1 = UNITS.player                       -- SAME TABLE: same guid, same name
  UNITS.raid2 = UNITS.party1
  UNITS.raid3 = UNITS.party2
  UNITS.raid4 = UNITS.party3
end
local function U(u) return UNITS[u] end
function UnitExists(u)
  if U(u) ~= nil then return true end
  -- the client resolves a group member's NAME as a unit token; a mock that
  -- does not lets "bound by name" bugs through (BiS Innervate testing note)
  for _, d in pairs(UNITS) do if d.name == u then return true end end
  return false
end
function UnitName(u) return U(u) and U(u).name end
function UnitGUID(u) return U(u) and U(u).guid end
function UnitClass(u) local d=U(u) if not d then return nil end return d.class, d.class end
function UnitIsDead(u) return U(u) and U(u).dead or false end
function UnitIsGhost(u) return false end
function UnitIsDeadOrGhost(u) return U(u) and U(u).dead or false end
function UnitIsConnected(u) return U(u) and U(u).connected or false end
function UnitIsVisible(u) return U(u) and U(u).visible or false end
function UnitIsPlayer(u) return U(u) and U(u).player or false end
function UnitCanAttack(a,b) return false end
function UnitIsUnit(a,b) local x,y=U(a),U(b) return x~=nil and y~=nil and x.guid==y.guid end
function UnitHealth(u) return U(u) and U(u).hp or 0 end
function UnitHealthMax(u) return U(u) and U(u).hpmax or 0 end
function UnitIsInMyGuild(u) return true end
PLAYER_MANA = 5000
-- per-unit mana; falls back to PLAYER_MANA so existing tests are unaffected
UNIT_MANA = {}       -- [unit] = current
UNIT_MANA_MAX = {}   -- [unit] = max
function UnitPower(u, t) return UNIT_MANA[u] or PLAYER_MANA end
function UnitPowerMax(u, t) return UNIT_MANA_MAX[u] or 10000 end
function GetNumRaidMembers() return RAID_N end
function GetNumPartyMembers() return PARTY_N end
function GetNumGroupMembers() return RAID_N > 0 and RAID_N or (PARTY_N+1) end
function GetNumSubgroupMembers() return PARTY_N end
function IsInRaid() return RAID_N > 0 end
RAID_CLASS_COLORS = setmetatable({}, {__index=function() return {r=0.41,g=0.8,b=0.94} end})

-- ============ spells ============
SPELLS = {
  [2006]={name="Resurrection", icon=1}, [7328]={name="Redemption",icon=2},
  [2008]={name="Ancestral Spirit",icon=3}, [20484]={name="Rebirth",icon=4},
}
C_Spell = {}
CAST_MS = { ["Ancestral Spirit"]=10000, ["Rebirth"]=2000, ["Lesser Healing Wave"]=1500,
            ["Regrowth"]=2000, ["Healing Touch"]=3500,
            ["Healing Wave"]=3000, ["Chain Heal"]=2500 }
function C_Spell.GetSpellInfo(id)
  if type(id)=="number" then
    local s=SPELLS[id]
    if s then return {name=s.name, iconID=s.icon, castTime=CAST_MS[s.name] or 0} end
    return nil
  end
  for _,s in pairs(SPELLS) do
    if s.name==id then return {name=s.name, iconID=s.icon, castTime=CAST_MS[s.name] or 0} end
  end
  if CAST_MS[id] then return {name=id, iconID=99, castTime=CAST_MS[id]} end
  return nil
end
SPELL_COSTS = { ["Regrowth"]=675, ["Healing Touch"]=800, [26980]=675, [26979]=800,
  ["Ancestral Spirit"]=1200, ["Lesser Healing Wave"]=265, ["Healing Wave"]=620, ["Chain Heal"]=540,
  [2008]=1200, [8004]=265, [25357]=620, [25423]=540 }
function C_Spell.GetSpellPowerCost(s)
  local c = SPELL_COSTS[s]
  if not c then return nil end
  return { {type=0, cost=c} }
end
function C_Spell.GetSpellTexture(s) return 99 end
function C_Spell.GetSpellCooldown(name)
  local c = SPELL_CD[name]
  if not c then return { startTime = 0, duration = 0 } end
  return { startTime = c[1], duration = c[2] }
end
IN_RANGE = 1
function C_Spell.IsSpellInRange(s, u) return IN_RANGE == 1 end

-- spellbook: max-rank only, as on his client
BOOK_ITEMS = {
  {name="Ancestral Spirit", rank="Rank 5", id=2008},
  {name="Rebirth", rank="Rank 6", id=20484},
  {name="Reincarnation", rank="", id=20608},
  {name="Regrowth", rank="Rank 10", id=26980},
  {name="Healing Touch", rank="Rank 13", id=26979},
  {name="Lesser Healing Wave", rank="Rank 6", id=8004},
  {name="Healing Wave", rank="Rank 11", id=25357},
  {name="Chain Heal", rank="Rank 5", id=25423},
  {name="Lightning Bolt", rank="Rank 12", id=25449},
}
Enum = { SpellBookSpellBank = { Player = 0 } }
C_SpellBook = {}
function C_SpellBook.GetSpellBookItemName(i, bank)
  local e = BOOK_ITEMS[i]; if not e then return nil end; return e.name, e.rank
end
function C_SpellBook.GetNumSpellBookSkillLines() return 1 end
function C_SpellBook.GetSpellBookSkillLineInfo(l) return {itemIndexOffset=0, numSpellBookItems=#BOOK_ITEMS} end
function C_SpellBook.GetSpellBookItemInfo(i, bank)
  local e = BOOK_ITEMS[i]; if not e then return nil end; return {spellID=e.id}
end
HEAL_TIP = { ["Regrowth"]="Heals a friendly target for 1215 to 1350.",
             ["Healing Touch"]="Heals a friendly target for 2267 to 2678.",
             ["Lesser Healing Wave"]="Heals a friendly target for 892 to 1010.",
             ["Healing Wave"]="Heals a friendly target for 1919 to 2190.",
             ["Chain Heal"]="Heals a friendly target for 1055 to 1205." }
C_TooltipInfo = {}
function C_TooltipInfo.GetSpellBookItem(i, bank)
  local e = BOOK_ITEMS[i]; if not e then return nil end
  local t = HEAL_TIP[e.name]
  if not t then return {lines={{leftText=e.name}}} end
  return {lines={{leftText=e.name},{leftText=t}}}
end
TooltipUtil = { SurfaceArgs = function() end }

-- ============ auras / bags ============
DRINKING = false
DRAGGING = nil
SOULSTONE = false        -- is a Soulstone Resurrection buff on the player?
BAG_ITEMS = {}           -- [itemID] = true, for the Ankh check
C_UnitAuras = {}
function C_UnitAuras.GetAuraDataByIndex(u,i,filter)
  local n = 0
  if DRINKING then n = n + 1 if i == n then return {spellId=27089, name="Drink"} end end
  if SOULSTONE then n = n + 1 if i == n then return {spellId=27239, name="Soulstone Resurrection"} end end
  return nil
end
BAGS = { [0] = { [1]={itemID=34062} }, [1]={}, [2]={}, [3]={}, [4]={} }
C_Container = {}
function C_Container.GetContainerNumSlots(b) return b==0 and 16 or 0 end
function C_Container.GetContainerItemInfo(b,s)
  local i=BAGS[b] and BAGS[b][s]
  if i then return {itemID=i.itemID} end
  -- extra bag contents declared by a test (an Ankh, say) sit after the drinks
  if b == 0 then
    local k = 2
    for id in pairs(BAG_ITEMS) do
      if s == k then return {itemID=id} end
      k = k + 1
    end
  end
end
C_Item = { GetItemIconByID = function(id) return 55 end }

-- ============ misc ============
-- 5th return is when the cast LANDS, in ms (BiS Healing's timing trick)
CASTING = {}
CAST_END_MS = {}      -- [unit] = endTime in ms
function UnitCastingInfo(u)
  local sp = CASTING and CASTING[u]
  if not sp then return nil end
  return sp, sp, nil, (NOW*1000), (CAST_END_MS[u] or ((NOW + 3) * 1000))
end

-- ============ native heal prediction ============
-- The client's own numbers -- sees EVERY healer, unlike LibHealComm.
NATIVE_INC = {}       -- [unit] = total inbound from everyone
NATIVE_MINE = {}      -- [unit] = inbound from the player
NATIVE_API = true
function UnitGetIncomingHeals(unit, healer)
  if not NATIVE_API then return nil end
  if healer == "player" then return NATIVE_MINE[unit] or 0 end
  return NATIVE_INC[unit] or 0
end

-- ============ gear + talents ============
SPELL_BONUS_HEALING = 0
function GetSpellBonusHealing() return SPELL_BONUS_HEALING end
TALENTS = {}          -- { {name=, rank=}, ... } in tab 1
function GetNumTalentTabs() return 1 end
function GetNumTalents(tab) return #TALENTS end
function GetTalentInfo(tab, i)
  local t = TALENTS[i]
  if not t then return nil end
  return t.name, nil, nil, nil, t.rank, t.maxRank or 5
end

-- ============ bindings ============
OVERRIDE_BINDS = {}
SAVED_BINDS = {}      -- writing here is the BUG: it is the user's keybind file
function SetOverrideBindingClick(owner, prio, key, button, mouseButton)
  OVERRIDE_BINDS[key] = button .. ":" .. tostring(mouseButton)
end
function ClearOverrideBindings(owner) OVERRIDE_BINDS = {} end
function SetBindingClick(k, b) SAVED_BINDS[k] = b end
function SaveBindings(s) SAVED_BINDS.__saved = true end
C_ChatInfo = {}
SENT = {}
function C_ChatInfo.SendAddonMessage(p,m,c)
  SENT[#SENT+1] = p.."|"..m.."|"..c
  SENT_LAST = { prefix = p, msg = m, chan = c }
end
function C_ChatInfo.RegisterAddonMessagePrefix(p) return true end
TIMERS = {}
C_Timer = { After = function(d, fn) TIMERS[#TIMERS+1] = fn end }
function CombatLogGetCurrentEventInfo() return unpack(CLEU_ARGS or {}) end
function GetBindingAction(k) return "" end
function GetCurrentBindingSet() return 1 end
SlashCmdList = {}
function GetSpellInfo() return nil end   -- modern client: gone
GetSpellBookItemName = nil
GetSpellName = nil
GetContainerNumSlots = nil
GetContainerItemInfo = nil
GetItemIcon = nil
UnitBuff = nil
GetSpellPowerCost = nil
GetSpellTexture = nil
IsSpellInRange = nil
SendAddonMessage = nil
RegisterAddonMessagePrefix = nil
BOOKTYPE_SPELL = nil

-- localized error strings the addon whitelists against
SPELL_FAILED_OUT_OF_RANGE = "Out of range."
SPELL_FAILED_NO_MANA = "Not enough mana"
ERR_OUT_OF_MANA = "Not enough mana"
SPELL_FAILED_LINE_OF_SIGHT = "Target not in line of sight"
SPELL_FAILED_BAD_TARGETS = "Invalid target"
SPELL_FAILED_TARGET_DEAD = "Your target is dead"
SPELL_FAILED_SPELL_IN_PROGRESS = "Another action is in progress"
SPELL_FAILED_INTERRUPTED = "Interrupted"
SPELL_FAILED_CASTER_DEAD = "You are dead"
SPELL_FAILED_MOVING = "Can't do that while moving"
SPELL_FAILED_REAGENTS = "Reagents"

-- ============ LibStub / LibHealComm-4.0 mock ============
-- HEALCOMM = false makes LibStub return nil, i.e. the Libs folder is missing.
-- Survives a harness reload on purpose, so a test can set it BEFORE the addon
-- loads -- healCommOn is captured once, at load.
if HEALCOMM == nil then HEALCOMM = true end
INCOMING = {}          -- [guid] = amount other players have in the air
OWN_INCOMING = {}      -- [guid] = amount YOU have in the air
local healCommLib = {
  CASTED_HEALS = 1,
  GetOthersHealAmount = function(self, guid, kind, when) return INCOMING[guid] or 0 end,
  GetHealAmount = function(self, guid, kind, when)
    return (INCOMING[guid] or 0) + (OWN_INCOMING[guid] or 0)
  end,
  RegisterCallback = function() end,
}
function LibStub(name, silent)
  if not HEALCOMM then return nil end
  if name == "LibHealComm-4.0" then return healCommLib end
  return nil
end

-- ============ global leak detector ============
local baseline = {}
for k in pairs(_G) do baseline[k]=true end

local LEAKS = {}
setmetatable(_G, {__newindex=function(t,k,v)
  if not baseline[k] then LEAKS[#LEAKS+1] = k end
  rawset(t,k,v)
end})

-- ============ run ============
local chunk, err = loadfile("BiSRez.lua")
if not chunk then realprint("LOAD ERROR: "..tostring(err)) os.exit(1) end
local ok, e = pcall(chunk)
if not ok then realprint("RUNTIME ERROR ON LOAD: "..tostring(e)) end

_G.__H = { out=out, frames=frames, leaks=LEAKS, realprint=realprint }
function FIRE(ev, ...)
  local fr
  for _,f in ipairs(frames) do if f.__events[ev] then fr=f end end
  if not fr then realprint("!! no frame registered for "..ev) return end
  local ok, e = pcall(fr.__scripts.OnEvent, fr, ev, ...)
  if not ok then realprint("!! ERROR in "..ev..": "..tostring(e)) end
end
function TICK(dt)
  local b = _G.BiSRezButton
  local ok,e = pcall(b.__scripts.OnUpdate, b, dt or 0.3)
  if not ok then realprint("!! ERROR in OnUpdate: "..tostring(e)) end
end
function CLICK()
  local b = _G.BiSRezButton
  local ok,e = pcall(b.__scripts.PostClick, b)
  if not ok then realprint("!! ERROR in PostClick: "..tostring(e)) end
end
function SLASH(cmd)
  local ok,e = pcall(SlashCmdList["BISREZ"], cmd)
  if not ok then realprint("!! ERROR in /bisrez "..cmd..": "..tostring(e)) end
end
function DUMP(label)
  realprint("---- "..label.." ----")
  for _,l in ipairs(out) do realprint("   "..l) end
  out = {}
  _G.__H.out = out
end
function FLUSHTIMERS()
  local t = TIMERS; TIMERS = {}
  for _,fn in ipairs(t) do pcall(fn) end
end
