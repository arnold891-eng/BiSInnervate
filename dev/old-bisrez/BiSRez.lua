--[[--------------------------------------------------------------------------
  BiS Rez
  One secure button. Scans party/raid for dead members in range, picks the
  best one by class priority, and casts your class's max-rank rez on it.

  Why this works: rez spells are out-of-combat only, so InCombatLockdown() is
  false when we need to update the secure button's attributes. No taint.
----------------------------------------------------------------------------]]

-- BiS Theme: use the shared palette when it's loaded, otherwise the same values inline.
local T = BiSTheme
if not T then
  local hex = { bg="121020", surface="1a1730", sunken="221d3c", line="2a2446", line2="3a3260",
    ink="ece8f6", ink2="c6bedd", muted="968ead", accent="b980ff", accentSoft="2c2148",
    good="4fd0cf", warn="f08cb0", gold="e5c04a", slate="8fb4d6", dim="8e86a6",
    epic="c08cff", rare="5fa8f0", uncommon="5fd06f", common="ece8f6", poor="8e86a6" }
  local cache = {}
  local function rgb(name)
    local h = hex[name] or hex.ink
    local c = cache[h]
    if not c then
      c = { tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255 }
      cache[h] = c
    end
    return c[1], c[2], c[3]
  end
  T = {
    hex = hex, rgb = rgb,
    rgba = function(n, a) local r, g, b = rgb(n); return r, g, b, (a or 1) end,
    text = function(n, s) return "|cff" .. (hex[n] or hex.ink) .. tostring(s) .. "|r" end,
    classRGB = function(tok)
      local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[tok]
      if c then return c.r, c.g, c.b end
      return rgb("ink")
    end,
    pctColor = function(p)
      if p == nil then return "muted" elseif p >= 80 then return "good" elseif p < 40 then return "warn" end
      return "ink2"
    end,
    skin = function(f, border)
      if not f.SetBackdrop then return end
      f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      f:SetBackdropColor(rgb("surface")); f:SetBackdropBorderColor(rgb(border or "line2"))
    end,
  }
end

local ADDON = "BiSRez"
local VERSION = "3.0"

-- Class rez spells (base rank spell IDs -- used only to fetch localized names)
-- Out-of-combat rezzes only. Rebirth is deliberately NOT here: it is an hour
-- of cooldown and the only combat rez the raid has, so spending it on a corpse
-- after the fight is over is the single most expensive mistake this addon
-- could make. A druid gets the heal, the drink and the window; their rez stays
-- theirs to spend by hand, in a fight, on purpose.
local REZ_SPELL_ID = {
    PRIEST  = 2006,   -- Resurrection
    PALADIN = 7328,   -- Redemption
    SHAMAN  = 2008,   -- Ancestral Spirit
}

-- Lower number = rezzed first.
--
-- This is not a class-favourites list, it is a throughput order: the job is to
-- get the raid pullable again, and the fastest route is to rez the people who
-- shorten the recovery for everybody else first.
--
--   1-3  the rezzers. Every one you stand up multiplies the rate at which the
--        rest come up. Nothing else comes close.
--   4-6  mana. A rezzer with an empty bar is not a rezzer -- a druid's
--        Innervate and a mage's water are what keep tier 1 casting, and a
--        warlock's soulstone is insurance against doing this again.
--   7-9  everyone else, who can only be rezzed, never rez.
--
-- MANA_TIER below promotes the mage when the standing rezzers are actually dry,
-- because at that point water outranks another body.
local PRIORITY = {
    PRIEST  = 1,
    PALADIN = 2,
    SHAMAN  = 3,
    DRUID   = 4,   -- Innervate: mana for tier 1 (their own rez is off-limits)
    MAGE    = 5,   -- water and food
    WARLOCK = 6,   -- soulstone for the next attempt
    HUNTER  = 7,
    WARRIOR = 8,
    ROGUE   = 9,
}

-- A released player is running back under their own steam and cannot be helped
-- by standing here; they sort behind every body still on the floor.
local GHOST_PENALTY = 100

local REZ_COOLDOWN_GUARD = 30 -- seconds to ignore a target after someone rezzes it

-- FORWARD DECLARATIONS. A `local` declared below its first use is a nil upvalue
-- and the reference silently resolves to a global instead. That is how the
-- roster handler's `opts:Refresh()` was a no-op through v2.3 -- the options
-- window now hangs off G instead, which cannot be shadowed that way at all.
local SpellInRange    -- defined once the API shims are up
local lastReject      -- {unit=, name=, why=} list from the last FindBestTarget pass
local CastSeconds     -- live cast time of a spell; assigned with the HealComm block
local ApplyBind       -- keybinder; defined with the button, called from login

-- The addon's shared surface. The options window reaches the rest of the file
-- through THIS, never by bare name: a bare reference to a local declared
-- further down resolves to a nil global and fails silently (landmines #1).
-- A table field cannot be shadowed by a late local, so G.x is always safe.
local G = {}
_G.BiSRez = G

--------------------------------------------------------------------------------
-- API shims (TBC Classic renamed a few things over its patch life)
--------------------------------------------------------------------------------

local BOOK           = BOOKTYPE_SPELL or "spell"
local CLEUInfo       = CombatLogGetCurrentEventInfo

-- Spell info: newer builds moved this to C_Spell.GetSpellInfo (returns a table)
local function SpellNameIcon(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if type(info) == "table" and info.name then
            return info.name, info.iconID or info.icon
        end
    end
    if GetSpellInfo then
        local n, _, icon = GetSpellInfo(id)
        if n then return n, icon end
    end
    return nil, nil
end

-- Spellbook walk: C_SpellBook on newer builds, GetSpellBookItemName / GetSpellName on old
local PLAYER_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0

local function BookName(i)
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        return C_SpellBook.GetSpellBookItemName(i, PLAYER_BANK)
    end
    if GetSpellBookItemName then return GetSpellBookItemName(i, BOOK) end
    if GetSpellName then return GetSpellName(i, BOOK) end
    return nil
end

local function NumSpells()
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local total = 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then total = math.max(total, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0)) end
        end
        return total
    end
    return 1000 -- old API: just walk until nil
end

-- SavedVariables may not exist yet (first run, or folder name mismatch).
-- Never touch BiSRezDB directly -- go through DB().
local function DB()
    if type(BiSRezDB) ~= "table" then BiSRezDB = {} end
    return BiSRezDB
end

-- SetTexture(r,g,b,a) is gone on this engine -- solid colors need SetColorTexture
local function SolidColor(tex, r, g, b, a)
    if tex.SetColorTexture then
        tex:SetColorTexture(r, g, b, a)
    else
        tex:SetTexture(r, g, b, a)
    end
end

local function GroupInfo()
    -- returns unit prefix, member count (excluding player for party)
    local nRaid = 0
    if GetNumRaidMembers then nRaid = GetNumRaidMembers() or 0 end
    if nRaid == 0 and IsInRaid and IsInRaid() and GetNumGroupMembers then
        nRaid = GetNumGroupMembers() or 0
    end
    if nRaid > 0 then return "raid", nRaid end

    local nParty = 0
    if GetNumPartyMembers then nParty = GetNumPartyMembers() or 0 end
    if nParty == 0 and GetNumSubgroupMembers then nParty = GetNumSubgroupMembers() or 0 end
    return "party", nParty
end

--------------------------------------------------------------------------------
-- Spell setup
--------------------------------------------------------------------------------

local _, playerClass = UnitClass("player")
local baseName, spellIcon, castName

-- English fallbacks, used if the spell-ID lookup comes back empty
local REZ_NAME_EN = {
    PRIEST  = "Resurrection",
    PALADIN = "Redemption",
    SHAMAN  = "Ancestral Spirit",
    DRUID   = "Rebirth",
}

local function ResolveSpell(verbose)
    local id = REZ_SPELL_ID[playerClass]
    if not id then
        if verbose then
            if playerClass == "DRUID" then
                print("|cff66ccffBiS Rez|r: " .. T.text("gold",
                    "Rebirth is an hour of cooldown and the raid's only combat rez -- BiS Rez will never spend it."))
                print("|cff66ccffBiS Rez|r: " .. T.text("muted",
                    "the button still heals and drinks, and the window still shows you the corpses and who can take them."))
            else
                print("|cff66ccffBiS Rez|r: " .. T.text("warn",
                    "class " .. tostring(playerClass) .. " has no out-of-combat rez."))
            end
        end
        return false
    end

    local name, icon = SpellNameIcon(id)
    if not name then
        name = REZ_NAME_EN[playerClass]
        if verbose then print("|cff66ccffBiS Rez|r: " .. T.text("muted", "spell-ID lookup failed, falling back to English name.")) end
    end
    if not name then return false end
    baseName, spellIcon = name, icon

    -- Walk the spellbook for the highest rank we actually know
    local bestRank, found
    local limit = NumSpells()
    for i = 1, limit do
        local n, rank = BookName(i)
        if not n then
            if limit >= 1000 then break end
        elseif n == baseName then
            found, bestRank = true, rank
        end
    end

    if not found and verbose then
        print("|cff66ccffBiS Rez|r: " .. T.text("muted", "'" .. baseName .. "' not found in spellbook -- casting by name, no rank."))
    end

    if bestRank and bestRank ~= "" then
        castName = baseName .. "(" .. bestRank .. ")"
    else
        castName = baseName -- ranks stripped on this build, or scan failed
    end
    return true
end

--------------------------------------------------------------------------------
-- Duplicate-rez guard (TBC has no UnitHasIncomingResurrection)
--------------------------------------------------------------------------------

local recentRez = {} -- [destGUID] = GetTime()

local function MarkRezzed(guid)
    if guid then recentRez[guid] = GetTime() end
end

local function RecentlyRezzed(unit)
    local guid = UnitGUID(unit)
    if not guid then return false end
    local t = recentRez[guid]
    if not t then return false end
    if GetTime() - t > REZ_COOLDOWN_GUARD then
        recentRez[guid] = nil
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- Target selection
--------------------------------------------------------------------------------

-- Group units plus your current target (rez works on ungrouped players too)
local function CandidateUnits()
    local prefix, count = GroupInfo()
    local list, seen = {}, {}
    for i = 1, count do
        local u = prefix .. i
        local guid = UnitGUID(u)
        if guid and not seen[guid] then
            seen[guid] = true
            list[#list + 1] = u
        end
    end
    local tguid = UnitGUID("target")
    if tguid and not seen[tguid] then
        list[#list + 1] = "target"
    end
    return list
end


--------------------------------------------------------------------------------
-- Rez claims: who is already rezzing whom
--   passive = read other people's cast bars + their target
--   active  = addon-to-addon broadcast over CHAT_MSG_ADDON
--------------------------------------------------------------------------------

local PREFIX = "BiSRez"
local CLAIM_LIFE   = 15  -- seconds a broadcast claim holds
local CASTBAR_LIFE = 3   -- fallback when the cast bar won't tell us when it ends
local CASTBAR_SLOP = 1.5 -- grace after their cast lands, before the corpse reopens

local claims = {}   -- [guid] = { expires = t, who = name, src = "cast"/"comm" }
local REZ_NAMES = {} -- every class's rez spell name, for cast-bar matching

local function BuildRezNameSet()
    for class, id in pairs(REZ_SPELL_ID) do
        local n = SpellNameIcon(id)
        if n then REZ_NAMES[n] = true end
    end
    for _, n in pairs(REZ_NAME_EN) do REZ_NAMES[n] = true end
end

-- UNIT_SPELLCAST_* pass a spell NAME on old clients and a numeric spell ID on
-- modern ones. Accept either. Must live below REZ_NAMES -- it reads it.
local function IsRezSpellArg(arg)
    if arg == nil then return true end -- can't tell; assume yes
    if type(arg) == "string" then
        return arg == baseName or (REZ_NAMES and REZ_NAMES[arg]) or false
    end
    if type(arg) == "number" then
        local n = SpellNameIcon(arg)
        if not n then return false end
        return n == baseName or (REZ_NAMES and REZ_NAMES[n]) or false
    end
    return false
end

local function Claim(guid, who, life, src)
    if not guid or not who then return end
    local existing = claims[guid]
    local expires = GetTime() + (life or CLAIM_LIFE)
    if existing and existing.expires > expires and existing.src == "comm" then return end
    claims[guid] = { expires = expires, who = who, src = src or "comm" }
end

local function ClearClaim(guid)
    if guid then claims[guid] = nil end
end

local function ClaimedBy(unit)
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local c = claims[guid]
    if not c then return nil end
    if GetTime() > c.expires then claims[guid] = nil return nil end
    if UnitIsUnit(unit, "player") then return nil end
    return c.who, c.src
end

-- Passive: anyone in the group with a rez on their cast bar claims their target
local function ScanCastBars()
    local prefix, count = GroupInfo()
    for i = 1, count do
        local u = prefix .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") then
            -- UnitCastingInfo's 5th return is when the cast LANDS, in ms. BiS
            -- Healing uses it to time other people's heals; here it means a
            -- claim can last exactly as long as their cast really has left,
            -- instead of a flat 3s that expires under a 10s rez and reopens
            -- the corpse while they are still casting on it.
            local spell, _, _, _, endMS = UnitCastingInfo(u)
            if spell and REZ_NAMES[spell] then
                local tgt = u .. "target"
                local guid = UnitGUID(tgt)
                -- the cast-bar scan sees rezzers who are NOT running the addon,
                -- which is most of them: that is where this cue earns its keep
                if guid == UnitGUID("player") then
                    G.RezIncomingOnMe(UnitName(u))
                end
                if guid then
                    local life = CASTBAR_LIFE
                    if type(endMS) == "number" and endMS > 0 then
                        local left = (endMS / 1000) - GetTime()
                        if left > 0 then life = left + CASTBAR_SLOP end
                    end
                    Claim(guid, UnitName(u) or "someone", life, "cast")
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Addon channel -- protocol 1
--
-- Rebuilt on BiS Innervate's Comm, which learned every one of these the hard
-- way. Pipe separated: PROTO|CMD|a1|a2|...
--
--   HELLO |ver|class|rezcd|known    I run BiS Rez, this is my class, my rez has
--                                   N seconds of cooldown left, and I currently
--                                   know about K other users
--   STATE |class|rezcd|casting      periodic; the same, plus am I mid-cast
--   CLAIM |guid                     I have started casting on this corpse
--   DONE  |guid                     my rez landed on it
--   FREE  |guid                     my cast died; the corpse is open again
--   WANT  |                         somebody wants the scoreboard
--   SCORE |name=n;name=n;...        here is my scoreboard (chunked)
--
-- The v2.7 format was a bare "C:<guid>". Four things it did not do, all of
-- which Innervate hit in a real raid:
--   * no protocol field, so a future format change silently corrupts a claim
--   * no channel check, so a whispered addon message from outside the group
--     could plant or release a claim
--   * no sender check, same
--   * no length guard: the client drops anything over 255 bytes and never
--     tells the sender, so a long scoreboard just evaporated
--------------------------------------------------------------------------------

local PROTOCOL = 1
local SEP = "|"

local warnedNewer, warnedOlder = false, false

local function Split(msg)
    local out, i = {}, 1
    for piece in string.gmatch(msg .. SEP, "([^" .. SEP .. "]*)%" .. SEP) do
        out[i] = piece
        i = i + 1
    end
    return out
end

local function GroupChannel()
    local prefix = GroupInfo()
    return (prefix == "raid") and "RAID" or "PARTY"
end

-- returns true if it actually went out
local function Send(cmd, ...)
    local parts = { PROTOCOL, cmd }
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v == nil then v = ""
        elseif type(v) == "boolean" then v = v and "1" or "0" end
        parts[#parts + 1] = tostring(v)
    end
    local msg = table.concat(parts, SEP)
    -- The client silently drops anything past 255 bytes and the sender never
    -- hears about it. Say so rather than losing it.
    if #msg > 250 then
        if DB().verbose then
            print("|cff66ccffBiS Rez|r: " .. T.text("warn",
                  ("message too long, not sent: %s (%d bytes)"):format(cmd, #msg)))
        end
        return false
    end
    local _, gcount = GroupInfo()
    if gcount == 0 then return false end
    local chan = GroupChannel()
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, chan)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, msg, chan)
    else
        return false
    end
    return true
end
G.Send = Send

--------------------------------------------------------------------------------
-- Rezzer roster: who else in this raid can rez, and is their spell up
--
-- Straight port of Innervate's Tracker. Only people RUNNING THE ADDON count:
-- a druid without it cannot see a claim, so counting them as a rezzer would be
-- a lie -- the button would think a corpse was covered when nobody was coming.
--
-- Cooldowns matter more here than the class list suggests. Priest, Paladin and
-- Shaman rezzes have no cooldown, but a Druid's Rebirth has twenty minutes,
-- and knowing that the only other rezzer standing is a druid who just used it
-- is the difference between waiting and casting.
--------------------------------------------------------------------------------

local rezzers = {}          -- [name] = { class, cd, cdStamp, casting, seen }
local REZZER_STALE = 120    -- forget a peer we have not heard from in 2 minutes

local function RezzerEntry(name)
    local d = rezzers[name]
    if not d then
        d = { name = name, cd = 0, cdStamp = GetTime() }
        rezzers[name] = d
    end
    return d
end

-- seconds of rez cooldown left for a peer (0 = ready)
local function RezzerCooldown(name)
    local d = rezzers[name]
    if not d then return 0 end
    local left = (d.cd or 0) - (GetTime() - (d.cdStamp or 0))
    return (left > 0) and left or 0
end
G.RezzerCooldown = RezzerCooldown

-- our own rez cooldown, read live so Rebirth is honest
local function MyRezCooldown()
    if not baseName then return 0 end
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, baseName)
        if ok and type(info) == "table" then start, dur = info.startTime, info.duration end
    end
    if not start and GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, baseName)
        if ok then start, dur = s, d end
    end
    if type(start) ~= "number" or type(dur) ~= "number" then return 0 end
    if dur <= 1.5 then return 0 end          -- that is the global cooldown, not ours
    local left = (start + dur) - GetTime()
    return (left > 0) and left or 0
end
G.MyRezCooldown = MyRezCooldown

-- every rezzer we know about, ready first
function G.RezzerList()
    local list = {}
    local now = GetTime()
    for name, d in pairs(rezzers) do
        if (now - (d.seen or 0)) <= REZZER_STALE then
            list[#list + 1] = { name = name, class = d.class, wipe = d.wipe,
                                cd = RezzerCooldown(name), casting = d.casting }
        end
    end
    table.sort(list, function(a, b)
        if a.cd ~= b.cd then return a.cd < b.cd end
        return a.name < b.name
    end)
    return list
end

-- how many rezzers (us included) could cast right now
function G.RezzersReady()
    local n = 0
    for _, r in ipairs(G.RezzerList()) do
        if r.cd <= 0 and not r.casting then n = n + 1 end
    end
    return n
end

local function CountUsers()
    local n = 0
    for _ in pairs(rezzers) do n = n + 1 end
    return n
end

function G.NoteRezzer(sender, class, cd, casting, wipe)
    local d = RezzerEntry(sender)
    d.seen = GetTime()
    if class and class ~= "" then d.class = class end
    if cd then d.cd, d.cdStamp = cd, GetTime() end
    d.casting = casting and true or false
    if wipe ~= nil then d.wipe = wipe end
end
local NoteRezzer = G.NoteRezzer

local function ForgetAbsent()
    for name in pairs(rezzers) do
        if name ~= UnitName("player") and G.UnitByName and not G.UnitByName(name) then
            rezzers[name] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Wipe protection
--
-- The number that actually decides whether a wipe costs thirty seconds or ten
-- minutes: how many ways the raid has of getting somebody back on their feet
-- WITHOUT a corpse run. Three of them, and only three:
--
--   * a Shaman's Reincarnation, with an Ankh in the bag to spend
--   * a Paladin's Divine Intervention -- they die, their target lives
--   * a Soulstone, but ONLY on somebody who can actually resurrect. A stone on
--     a rogue saves one corpse run; a stone on a priest saves the whole raid's.
--
-- Everything else is a corpse run. This is a raid-wide count, so it only works
-- as well as the addon is spread: people without it are invisible here, the
-- same as they are on the rezzer strip.
--------------------------------------------------------------------------------

-- One table, not eight locals. Lua 5.1 allows 200 per chunk and this file has
-- form: BiSHealing hit the ceiling twice and the fix both times was to group
-- new state rather than keep naming it. (bislint warns from 170.)
local WP = {
    SPELLS = {
        SHAMAN  = { name = "Reincarnation",       letter = "R",
                    reagent = 17030, reagentName = "Ankh" },
        PALADIN = { name = "Divine Intervention", letter = "D" },
    },
    SOULSTONE = "Soulstone Resurrection",
    LABEL = {
        R = "Reincarnation",
        D = "Divine Intervention",
        S = "Soulstone (on a rezzer)",
    },
    known = nil,   -- do we actually have ours? resolved against the spellbook
}

function WP.Resolve()
    WP.known = nil
    local cfg = WP.SPELLS[playerClass]
    if not cfg then return end
    local limit = NumSpells()
    for i = 1, limit do
        local n = BookName(i)
        if not n then
            if limit >= 1000 then break end
        elseif n == cfg.name then
            WP.known = cfg
            return
        end
    end
end
G.ResolveWipeSpell = WP.Resolve

function WP.HasItem(itemID)
    if not itemID then return false end
    for bag = 0, 4 do
        local n = (C_Container and C_Container.GetContainerNumSlots(bag))
                  or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            local id
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                id = info and info.itemID
            elseif GetContainerItemInfo then
                id = select(10, GetContainerItemInfo(bag, slot))
            end
            if id == itemID then return true end
        end
    end
    return false
end

function WP.OffCooldown(name)
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, name)
        if ok and type(info) == "table" then start, dur = info.startTime, info.duration end
    end
    if not start and GetSpellCooldown then
        local ok, st, du = pcall(GetSpellCooldown, name)
        if ok then start, dur = st, du end
    end
    if type(start) ~= "number" or type(dur) ~= "number" then return true end
    if dur <= 1.5 then return true end          -- the global cooldown, not this
    return ((start + dur) - GetTime()) <= 0
end

-- is a Soulstone sitting on us right now?
function WP.HasSoulstone()
    for i = 1, 40 do
        local name
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            name = a.name
        elseif UnitBuff then
            name = UnitBuff("player", i)
            if not name then break end
        else
            break
        end
        if name == WP.SOULSTONE then return true end
    end
    return false
end
G.HasSoulstone = WP.HasSoulstone

-- what THIS player brings, as letters: "R", "D", "S", or a combination
function G.MyWipeProtection()
    local out = {}
    if WP.known and WP.OffCooldown(WP.known.name) then
        -- Reincarnation without an Ankh is not protection, it is a dead button
        if (not WP.known.reagent) or WP.HasItem(WP.known.reagent) then
            out[#out + 1] = WP.known.letter
        end
    end
    -- a stone only counts on somebody who can pick the raid back up
    if REZ_SPELL_ID[playerClass] and WP.HasSoulstone() then out[#out + 1] = "S" end
    return table.concat(out)
end

-- everything the raid has, ours included: count plus who has what
function G.WipeProtection()
    local n, detail = 0, {}
    local mine = G.MyWipeProtection()
    for letter in string.gmatch(mine, "%a") do
        n = n + 1
        detail[#detail + 1] = { name = UnitName("player"), what = WP.LABEL[letter] or letter }
    end
    for _, r in ipairs(G.RezzerList()) do
        for letter in string.gmatch(r.wipe or "", "%a") do
            n = n + 1
            detail[#detail + 1] = { name = r.name, what = WP.LABEL[letter] or letter }
        end
    end
    table.sort(detail, function(a, b)
        if a.what ~= b.what then return a.what < b.what end
        return a.name < b.name
    end)
    return n, detail
end

-- Reincarnation and Divine Intervention belong to classes that are not
-- necessarily rezzers, so a paladin with DI has to reach the rezzer table even
-- though every other reason to be in it is about casting a rez.
function G.NoteWipeOnly(name, class, wipe)
    if not wipe or wipe == "" then return end
    G.NoteRezzer(name, class, nil, false, wipe)
end

local helloBack, lastHelloBack = false, 0

local function SendHello()
    Send("HELLO", VERSION, playerClass or "", math.floor(MyRezCooldown()), CountUsers(),
         G.MyWipeProtection())
end
G.SendHello = SendHello

function G.BroadcastState()
    local wipe = G.MyWipeProtection()
    -- a paladin holding Divine Intervention is worth announcing even if this
    -- client has no rez of its own to offer
    if not castName and wipe == "" then return end
    Send("STATE", playerClass or "", math.floor(MyRezCooldown()),
         (G.btn and G.btn.pendingGUID) and 1 or 0, wipe)
end

--------------------------------------------------------------------------------
-- Roster blip
--
-- Innervate lost a whole night's grid to this: a ZONE-IN reads the roster as
-- EMPTY for a moment -- zero members, IsInGroup false -- before it repopulates.
-- Acting on that blip wiped its user table, and only providers ever re-announce
-- themselves, so everyone else stayed off the grid until a reload.
--
-- BiS Rez has the identical shape: the roster handler reads count == 0 as
-- "left the group" and clears the scoreboard. A zone into the raid instance
-- therefore threw away the night's tally. If we had a group a moment ago and
-- now see nobody, wait ten seconds before believing it.
--------------------------------------------------------------------------------

local rosterLastN, rosterEmptySince = 0, nil

function G.RosterBlip()
    local _, n = GroupInfo()
    if n > 0 then
        rosterLastN, rosterEmptySince = n, nil
        return false
    end
    if rosterLastN == 0 then return false end
    rosterEmptySince = rosterEmptySince or GetTime()
    if (GetTime() - rosterEmptySince) < 10 then return true end
    rosterLastN, rosterEmptySince = 0, nil
    return false
end


--------------------------------------------------------------------------------
-- Rez scoreboard: who has rezzed the most, this raid
--------------------------------------------------------------------------------

local function Scores() 
    local db = DB()
    db.scores = db.scores or {}
    return db.scores
end

function G.UnitByName(name)
    if not name then return nil end
    local short = name:match("^[^-]+") or name
    for _, u in ipairs(CandidateUnits()) do
        local n = UnitName(u)
        if n == short then return u end
    end
    if UnitName("player") == short then return "player" end
    return nil
end

local function AddScore(name)
    if not name then return end
    local short = name:match("^[^-]+") or name
    if DB().guildOnly then
        local u = G.UnitByName(short)
        if not u or not (UnitIsInMyGuild and UnitIsInMyGuild(u)) then return end
    end
    local sc = Scores()
    sc[short] = (sc[short] or 0) + 1
end

-- returns { name, name, ... }, count -- every leader, so ties show as ties
local function Champions()
    local leaders, best = {}, nil
    for name, count in pairs(Scores()) do
        if not best or count > best then
            best, leaders = count, { name }
        elseif count == best then
            leaders[#leaders + 1] = name
        end
    end
    table.sort(leaders)
    return leaders, best
end

local function ChampionText(maxNames)
    local leaders, best = Champions()
    if #leaders == 0 then return nil end
    if #leaders == 1 then return leaders[1] .. " " .. best, leaders, best end
    if #leaders <= (maxNames or 2) then
        return table.concat(leaders, " & ") .. " " .. best, leaders, best
    end
    return #leaders .. "-way tie " .. best, leaders, best
end

--------------------------------------------------------------------------------
-- Leaderboard sync: newcomers ask, one person answers
--------------------------------------------------------------------------------

local MSG_MAX      = 230   -- addon messages cap around 255 bytes; leave headroom
local syncPending  = false -- we owe the group a scoreboard reply
local syncSeenAt   = 0     -- last time anyone answered, so we don't all answer
local lastSyncPrint = 0    -- throttles the "synced with" line across chunks

local function Later(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
end

-- "S:name=3;name=1;..." split across as many messages as it takes
local function BroadcastScores()
    local chunk, sent = "", 0
    local function flush()
        if chunk ~= "" then Send("SCORE", chunk) chunk = "" sent = sent + 1 end
    end
    for name, count in pairs(Scores()) do
        local piece = name .. "=" .. count .. ";"
        if #chunk + #piece > MSG_MAX then flush() end
        chunk = chunk .. piece
    end
    flush()
    return sent
end

local function MergeScores(payload)
    local sc, changed = Scores(), false
    for name, count in payload:gmatch("([^=;]+)=(%d+)") do
        count = tonumber(count)
        -- max, not sum: everyone counts the same combat log events
        if count and count > (sc[name] or 0) then
            sc[name] = count
            changed = true
        end
    end
    return changed
end

-- Someone asked. Answer after a random pause, and stay quiet if a peer beat us.
local function ScheduleReply()
    if syncPending then return end
    if not next(Scores()) then return end
    syncPending = true
    Later(0.5 + math.random() * 2.0, function()
        syncPending = false
        if GetTime() - syncSeenAt < 3 then return end -- someone already answered
        BroadcastScores()
    end)
end

local function RequestSync()
    Later(2.0, function()
        local _, count = GroupInfo()
        if count > 0 then Send("WANT") end
    end)
end

-- Range check that works on both API generations and tolerates a rank suffix.
-- Returns 1 / 0 / nil (nil = the client would not tell us).
function SpellInRange(spell, unit)
    if type(spell) == "string" then
        spell = (spell:gsub("%b()", ""):gsub("%s+$", ""))
    end
    if not spell or spell == "" then return nil end
    local r
    if C_Spell and C_Spell.IsSpellInRange then
        r = C_Spell.IsSpellInRange(spell, unit)
        if r == true then r = 1 elseif r == false then r = 0 end
    elseif IsSpellInRange then
        r = IsSpellInRange(spell, unit)
    end
    return r
end

local function IsRezzable(unit)
    if not UnitExists(unit) then return false, "doesn't exist" end
    if UnitIsUnit(unit, "player") then return false, "that's you" end
    if not UnitIsPlayer(unit) then return false, "not a player" end
    if not (UnitIsDead(unit) or UnitIsGhost(unit)) then return false, "alive" end
    if not UnitIsConnected(unit) then return false, "offline" end
    if not UnitIsVisible(unit) then return false, "not visible / different zone" end
    if UnitCanAttack("player", unit) then return false, "hostile" end
    if RecentlyRezzed(unit) then return false, "rez already incoming" end
    local who, src = ClaimedBy(unit)
    if who then
        return false, ((src == "cast") and "being rezzed by " or "claimed by ") .. who
    end

    if SpellInRange(baseName, unit) == 0 then return false, "out of range" end
    return true, "ok"
end

-- Keeps the reject reasons from the last pass so the tooltip can explain itself
-- the way BiS Healing's "why here" tooltip does, instead of making you type
-- /bisrez list to find out why a corpse is being skipped.
-- True when no rezzer still standing has the mana to actually cast. At that
-- point another body is worth less than the water to fuel the ones we have.
local function RezzersAreDry()
    local prefix, count = GroupInfo()
    local anyWet, sawAny = false, false

    local function look(u, class)
        if not REZ_SPELL_ID[class] then return end
        local mx = UnitPowerMax and UnitPowerMax(u, 0) or 0
        if mx <= 0 then return end          -- no reading: this one tells us nothing
        sawAny = true
        if (UnitPower(u, 0) / mx) > 0.3 then anyWet = true end
    end

    for i = 1, count do
        local u = prefix .. i
        if UnitExists(u) and not UnitIsDeadOrGhost(u) then
            local _, class = UnitClass(u)
            look(u, class)
        end
    end
    if not UnitIsDeadOrGhost("player") then look("player", playerClass) end

    -- Never conclude "dry" from an absence of readings. A client where
    -- UnitPowerMax is missing or returns 0 would otherwise report every rezzer
    -- as empty forever, and the mage would permanently outrank the priest --
    -- which is exactly what the harness caught the first time this ran.
    if not sawAny then return false end
    return not anyWet
end
G.RezzersAreDry = RezzersAreDry

-- What this corpse is worth to the recovery, lower first.
function G.RezScore(unit, class)
    local score = PRIORITY[class] or 99
    if class == "MAGE" and RezzersAreDry() then score = 0.5 end
    if UnitIsGhost and UnitIsGhost(unit) and not UnitIsDead(unit) then
        score = score + GHOST_PENALTY
    end
    return score
end

local function FindBestTarget()
    local bestUnit, bestScore, bestName
    local rejects = {}

    for _, unit in ipairs(CandidateUnits()) do
        local ok, why = IsRezzable(unit)
        if ok then
            local _, class = UnitClass(unit)
            local score = G.RezScore(unit, class)
            if not bestScore or score < bestScore then
                bestUnit, bestScore, bestName = unit, score, UnitName(unit)
            end
        elseif why ~= "alive" and why ~= "that's you" and why ~= "not a player"
               and why ~= "doesn't exist" and why ~= "hostile" then
            -- only the interesting rejections: a dead player we are NOT taking
            rejects[#rejects + 1] = { name = UnitName(unit) or unit, why = why }
        end
    end

    lastReject = rejects
    return bestUnit, bestName, bestScore
end

--------------------------------------------------------------------------------
-- Support actions: drink and heal
--
-- The button does one thing per click, decided in Refresh:
--   dead? -yes-> afford rez? -yes-> REZ
--        |               `--no--> DRINK
--        `-no-> hurt? -yes-> afford heal? -yes-> HEAL
--              |                    `--no--> DRINK
--              `-no-> nothing
--
-- Rez always wins. Drink and heal are opt-out in the options panel.
--------------------------------------------------------------------------------

-- Heal spells per class. Names only -- ranks and heal amounts are read from the
-- spellbook at runtime, so nothing here goes stale when gear changes.
-- "group" is a smart/multi-target heal used when 2+ people are hurt; classes
-- without one just heal whoever is worst off.
local CLASS_HEALS = {
    SHAMAN  = { single = { "Lesser Healing Wave", "Healing Wave" },
                group  = "Chain Heal" },
    PRIEST  = { single = { "Flash Heal", "Heal", "Greater Heal" },
                group  = "Circle of Healing" },   -- Holy talent; skipped if unknown
    PALADIN = { single = { "Flash of Light", "Holy Light" },
                group  = nil },
    DRUID   = { single = { "Regrowth", "Healing Touch" },
                group  = nil },
}

-- Mana consumables, best first. Verified against wowhead TBC pages: the biscuit
-- restores mana AND health, everything below it is the 7200-mana tier.
local CONSUMABLES = {
    { id = 34062, name = "Conjured Manna Biscuit" },
    { id = 22018, name = "Conjured Glacier Water" },
    { id = 27860, name = "Purified Draenic Water" },
    { id = 29395, name = "Ethermead" },
    { id = 29401, name = "Sparkling Southshore Cider" },
}
local CONSUMABLE_RANK = {}
for i, c in ipairs(CONSUMABLES) do CONSUMABLE_RANK[c.id] = i end

local DRINK_AURAS = { 27089, 24707, 430, 431, 432, 1133, 1135, 1137 }

-- A "(Rank N)" suffix makes cost and texture lookups return nil, which would
-- read as cost 0 and make every spell look affordable. Strip it for strings.
local function BareName(x)
    if type(x) ~= "string" then return x end
    return (x:gsub("%b()", ""):gsub("%s+$", ""))
end

local function SpellCost(spell)
    local costs
    spell = BareName(spell)
    if C_Spell and C_Spell.GetSpellPowerCost then
        costs = C_Spell.GetSpellPowerCost(spell)
    elseif GetSpellPowerCost then
        costs = GetSpellPowerCost(spell)
    end
    if costs then
        for _, c in ipairs(costs) do
            if c.type == 0 then return c.cost end   -- mana
        end
    end
    return 0
end

local function SpellIcon(spell)
    spell = BareName(spell)
    if not spell then return nil end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) end
    if GetSpellTexture then return GetSpellTexture(spell) end
end

local function ItemIcon(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    if GetItemIcon then return GetItemIcon(itemID) end
end

local function IsDrinking()
    for i = 1, 40 do
        local spellId
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            spellId = a.spellId
        elseif UnitBuff then
            local name; name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
            if not name then break end
        else
            break
        end
        for _, id in ipairs(DRINK_AURAS) do
            if spellId == id then return true end
        end
    end
    return false
end

-- Heal ranks, read off the spellbook tooltips at login. NOTE: this client's
-- spellbook only exposes the HIGHEST rank of each spell, so this yields one
-- entry per spell name, not per rank -- effectively a small-heal / big-heal
-- pair. True downranking would need hardcoded per-rank spell IDs; not worth it.
local healRanks, groupHeal = {}, nil
-- set by PLAYER_EQUIPMENT_CHANGED, consumed by the button's OnUpdate. Must be
-- declared above both, or they end up as two different variables.
local healRebuildAt = nil

local function BookSpellID(i)
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local info = C_SpellBook.GetSpellBookItemInfo(i, PLAYER_BANK)
        return info and (info.spellID or info.actionID)
    end
    if GetSpellBookItemInfo then
        local a, b = GetSpellBookItemInfo(i, "spell")
        if type(a) == "string" then return b end
        return a
    end
end

-- Pull a heal number out of a tooltip line: "1234 to 1456" or "heals ... 1234".
local function ParseHeal(text)
    if not text then return nil end
    local lo, hi = text:match("(%d+) to (%d+)")
    if lo then return (tonumber(lo) + tonumber(hi)) / 2 end
    local n = text:match("[Hh]eal[^%d]-(%d+)")
    if n then return tonumber(n) end
    return nil
end

local scanTip
local function TooltipHeal(index)
    if C_TooltipInfo and C_TooltipInfo.GetSpellBookItem then
        local data = C_TooltipInfo.GetSpellBookItem(index, PLAYER_BANK)
        if data then
            if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
            for _, line in ipairs(data.lines or {}) do
                if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
                local n = ParseHeal(line.leftText)
                if n then return n end
            end
        end
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "BiSRezScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    if scanTip.SetSpellBookItem then
        pcall(scanTip.SetSpellBookItem, scanTip, index, PLAYER_BANK)
        for i = 1, scanTip:NumLines() do
            local fs = _G["BiSRezScanTipTextLeft" .. i]
            local n = fs and ParseHeal(fs:GetText())
            if n then return n end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Heal sizes: the spellbook tooltip is BASE healing only
--
-- The single biggest correctness bug carried since v2.3, found in BiS Healing:
-- on this client a heal tooltip does not include your gear. Chain Heal reads
-- "681 to 775" and lands for 2800. Every heal in the table was therefore sized
-- at roughly a quarter of the truth, so PickHeal -- "smallest heal that covers
-- the deficit" -- concluded almost nothing ever covered it and reached for the
-- biggest heal nearly every time. That is backwards: it is the expensive,
-- slowest option, and it overheals.
--
--   effective = (base + healing power x coefficient) x talent multiplier
--
-- Coefficient is cast time / 3.5s, read from the LIVE cast time so haste and
-- Improved Healing Wave both fall out of it for free. Instants are clamped so
-- a 1.5s floor applies rather than a coefficient of zero.
--
-- Talents are the class-wide "+% healing done" ones, matched by English name
-- (a non-English client just gets the untalented estimate -- honest, and still
-- far closer than base). Per-spell talents are deliberately NOT modelled;
-- BiS Healing needed that precision for colour bands, BiSRez only needs to
-- pick between a small heal and a big one.
--------------------------------------------------------------------------------

local HEAL_TALENTS = {
    SHAMAN  = { ["Purification"]        = 0.02 },  -- 5/5 = +10%
    PRIEST  = { ["Spiritual Healing"]   = 0.02 },  -- 5/5 = +10%
    PALADIN = { ["Healing Light"]       = 0.04 },  -- 3/3 = +12%
    DRUID   = { ["Gift of Nature"]      = 0.02 },  -- 5/5 = +10%
}

local function HealingPower()
    if type(GetSpellBonusHealing) == "function" then
        return GetSpellBonusHealing() or 0
    end
    return 0
end

-- 1.0 when nothing matches, so this can only ever make the estimate better.
local function TalentMultiplier()
    local want = HEAL_TALENTS[playerClass]
    if not want then return 1 end
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentInfo) ~= "function" then
        return 1
    end
    local mult = 1
    local okAll = pcall(function()
        for tab = 1, (GetNumTalentTabs() or 0) do
            for i = 1, (GetNumTalents(tab) or 0) do
                local name, _, _, _, rank = GetTalentInfo(tab, i)
                local per = name and want[name]
                if per and rank and rank > 0 then mult = mult + per * rank end
            end
        end
    end)
    if not okAll then return 1 end
    return mult
end

-- Turn a base tooltip number into what the heal actually lands for.
local function EffectiveHeal(base, castSpell)
    if not base or base <= 0 then return base or 0 end
    local sp = HealingPower()
    if sp <= 0 then return base end          -- no gear data: keep the base
    local ct = CastSeconds(castSpell)
    if ct <= 0 then ct = 1.5 end             -- instants get the 1.5s floor
    if ct > 3.5 then ct = 3.5 end
    return (base + sp * (ct / 3.5)) * TalentMultiplier()
end

function G.BuildHealTable()
    healRanks, groupHeal = {}, nil
    local cfg = CLASS_HEALS[playerClass]
    if not cfg then return end

    local wanted = {}
    for _, n in ipairs(cfg.single) do wanted[n] = true end

    local limit = NumSpells()
    for i = 1, limit do
        local name, rank = BookName(i)
        if not name then
            if limit >= 1000 then break end
        else
            local cast = (rank and rank ~= "") and (name .. "(" .. rank .. ")") or name
            if wanted[name] then
                local base = TooltipHeal(i) or 0
                healRanks[#healRanks + 1] = { cast = cast, id = BookSpellID(i),
                                              base = base,
                                              heal = EffectiveHeal(base, cast) }
            elseif cfg.group and name == cfg.group then
                groupHeal = cast
            end
        end
    end
    table.sort(healRanks, function(a, b) return a.heal < b.heal end)
end

--------------------------------------------------------------------------------
-- LibHealComm-4.0 (optional, ships under Libs/)
--
-- Straight lift of what BiS Healing does with it. Without this the heal picker
-- is blind: it sees a tank at 40% and starts a 2.5s Healing Wave on someone
-- three instant-casters have already topped off before your cast lands. The
-- library reports heals other players have IN THE AIR, keyed by target, so the
-- deficit can be discounted by them BEFORE anyone is picked.
--
-- Others' heals only, never your own -- subtracting your own pending cast would
-- cancel the reason you started casting it.
--
-- Entirely optional. Absent, every path below still works, it just can't see
-- inbound and behaves exactly like v2.4.
--------------------------------------------------------------------------------

local HealComm   = LibStub and LibStub("LibHealComm-4.0", true)
local healCommOn = HealComm ~= nil
local HEAL_REACTION = 0.3   -- click-to-cast slop, same constant BiS Healing uses

-- The client's own heal prediction. This is the fix for the caveat v2.5 shipped
-- with: LibHealComm only ever sees healers who are ALSO running a HealComm
-- addon, so a healer running bare -- or with a UI that doesn't broadcast -- was
-- invisible, which is precisely who out-heals you to a target. UnitGetIncomingHeals
-- is the client's own number and sees everyone.
local nativeIncoming = (type(UnitGetIncomingHeals) == "function")

-- Cast time of a heal, in seconds. Read live so it follows haste -- BiS Healing
-- found the spellbook updates the moment a haste trinket fires.
function CastSeconds(spell)
    spell = BareName(spell)
    if not spell then return 0 end
    if C_Spell and C_Spell.GetSpellInfo then
        local i = C_Spell.GetSpellInfo(spell)
        if type(i) == "table" and i.castTime then return (i.castTime or 0) / 1000 end
    end
    if GetSpellInfo then
        local _, _, _, ct = GetSpellInfo(spell)
        if ct then return ct / 1000 end
    end
    return 0
end

-- What OTHER healers already have landing on this unit before our cast would.
--
-- Two sources, and we take the LARGER of the two -- larger, not the sum. For a
-- healer who runs a HealComm addon both numbers describe the same heal, so
-- adding them would double-count them out of existence and we would never heal
-- anyone. Larger means: whichever source can see more, wins.
--   * HealComm  -- time-filtered, only sees HealComm users, has per-caster data
--   * native    -- sees EVERY healer, but is not time-filtered, so it can
--                  include a heal landing after ours. Conservative in the safe
--                  direction: at worst we skip someone who is already covered.
-- Our own pending cast is subtracted out of the native total; subtracting it
-- would cancel the reason we started casting.
local function OthersIncoming(unit, lead)
    if not unit then return 0 end
    local best = 0

    if healCommOn then
        local guid = UnitGUID(unit)
        if guid then
            local when = GetTime() + (lead or 0) + HEAL_REACTION
            best = HealComm:GetOthersHealAmount(guid, HealComm.CASTED_HEALS, when) or 0
        end
    end

    if nativeIncoming then
        local all  = UnitGetIncomingHeals(unit) or 0
        local mine = UnitGetIncomingHeals(unit, "player") or 0
        local others = all - mine
        if others > best then best = others end
    end

    return best
end

-- How badly this unit needs healing once inbound heals are accounted for.
local function EffectiveDeficit(unit, lead)
    local d = UnitHealthMax(unit) - UnitHealth(unit) - OthersIncoming(unit, lead)
    if d < 0 then d = 0 end
    return d
end

-- Smallest heal that covers the deficit; biggest known if nothing covers it.
-- Returns nil when somebody else's inbound already has them covered.
local function PickHeal(unit, lead)
    if #healRanks == 0 then return nil end
    local deficit = EffectiveDeficit(unit, lead)
    if deficit <= 0 then return nil end
    for _, h in ipairs(healRanks) do
        if h.heal >= deficit then return h end
    end
    return healRanks[#healRanks]
end

-- Worst-off living group member, plus how many are hurt at all.
-- rangeSpell (optional): skip anyone that spell cannot reach. Without it the
-- button happily picked someone 100 yards away and every click ate an
-- "Out of range" -- the rez path had this check, the heal path did not.
-- lead (optional): seconds until our heal would land, so inbound heals from
-- other players can be discounted first. Ranking on raw health is what makes a
-- slow caster lose every race and overheal; see the HealComm block above.
local function FindMostHurt(rangeSpell, lead)
    local worst, worstPct, injured = nil, 1, 0
    local prefix, count = GroupInfo()
    local units = {}
    if count > 0 then
        for i = 1, count do units[#units + 1] = prefix .. i end
        if prefix == "party" then units[#units + 1] = "player" end
    else
        units[1] = "player"
    end
    for _, u in ipairs(units) do
        if UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitIsConnected(u)
           and UnitIsVisible(u)
           and not (rangeSpell and SpellInRange(rangeSpell, u) == 0) then
            local hpMax = UnitHealthMax(u)
            if hpMax > 0 then
                -- where they will be when our cast lands, not where they are
                local pct = (hpMax - EffectiveDeficit(u, lead)) / hpMax
                if pct < 0.95 then
                    injured = injured + 1
                    if pct < worstPct then worst, worstPct = u, pct end
                end
            end
        end
    end
    return worst, injured
end

-- Best mana consumable in bags: bag, slot, itemID.
local function FindDrink()
    local bBag, bSlot, bRank, bID
    for bag = 0, 4 do
        local n = (C_Container and C_Container.GetContainerNumSlots(bag))
                  or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            local itemID
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                itemID = info and info.itemID
            elseif GetContainerItemInfo then
                itemID = select(10, GetContainerItemInfo(bag, slot))
            end
            local r = itemID and CONSUMABLE_RANK[itemID]
            if r and (not bRank or r < bRank) then
                bBag, bSlot, bRank, bID = bag, slot, r, itemID
            end
        end
    end
    return bBag, bSlot, bID
end

--------------------------------------------------------------------------------
-- The button
--------------------------------------------------------------------------------

local btn = CreateFrame("Button", "BiSRezButton", UIParent, "SecureActionButtonTemplate")
G.btn = btn
btn:SetWidth(64)
btn:SetHeight(64)
-- Parked off-screen until the window adopts it in W:Build. Through 2.9 this was
-- a separate floating frame with its own position, its own drag and its own
-- hide flag, and the result on screen was three unrelated pieces of furniture:
-- a header bar, a button, and a line of text between them.
btn:SetPoint("CENTER", 0, -120)
btn:SetMovable(true)
btn:RegisterForDrag("LeftButton")
-- DOWN EDGE ONLY. Registering both edges fires the secure action TWICE per
-- click: the second cast lands on top of the first, the client answers
-- "another action is in progress", and that error got reported as a failure
-- for a heal that actually worked. AnyUp alone does not fire at all on this
-- build, so "down" is the only sane default. /bisrez clicks still cycles it.
btn:RegisterForClicks("AnyDown")
btn:SetAttribute("*type1", "macro")

local okVisuals, visualErr = pcall(function()
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture("Interface\\Icons\\Spell_Holy_Resurrection")

    btn.border = btn:CreateTexture(nil, "BACKGROUND")
    btn.border:SetPoint("TOPLEFT", -2, 2)
    btn.border:SetPoint("BOTTOMRIGHT", 2, -2)
    SolidColor(btn.border, T.rgba("dim", 0.35))

    -- Both of these are re-anchored inside the window by W:Build; the points
    -- here only matter for the moment before it exists.
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    btn.label:SetWidth(120)

    btn.champ = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.champ:SetPoint("BOTTOM", btn, "TOP", 0, 3)
    btn.champ:SetWidth(160)
end)

--------------------------------------------------------------------------------
-- Keybinding
--
-- Override bindings sit on top of the user's keybinds without editing them and
-- clear on /reload, so the chosen key is stored in SavedVariables and re-applied
-- every login. This is the whole reason it is safe to bind at all: uninstalling
-- BiSRez can no longer leave a dead "CLICK BiSRezButton" in his bindings file.
--------------------------------------------------------------------------------
function ApplyBind(key)
    if not key or key == "" then return false end
    if InCombatLockdown() then return false end
    if type(SetOverrideBindingClick) ~= "function" then
        -- ancient build with no override API: fall back to the old behaviour
        if type(SetBindingClick) == "function" then
            local ok = pcall(SetBindingClick, key, "BiSRezButton")
            if ok and SaveBindings and GetCurrentBindingSet then
                pcall(SaveBindings, GetCurrentBindingSet())
            end
            return ok
        end
        return false
    end
    local ok = pcall(SetOverrideBindingClick, btn, true, key, "BiSRezButton", "LeftButton")
    return ok and true or false
end

-- The button is the biggest target on the window, so dragging it drags the
-- window rather than tearing the button off it.
btn:SetScript("OnDragStart", function()
    local f = G.Window and G.Window.frame
    if f and not DB().locked and not InCombatLockdown() then f:StartMoving() end
end)
btn:SetScript("OnDragStop", function()
    local f = G.Window and G.Window.frame
    if not f then return end
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    DB().windowPos = { p, rp, x, y }
end)

btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("BiS Rez", T.rgb("accent"))
    GameTooltip:AddLine("Spell: " .. tostring(castName), T.rgb("ink2"))

    -- what this click will do right now
    local act = self.action
    if act == "rez" then
        GameTooltip:AddLine("Click: rez " .. tostring(self.currentName), T.rgb("good"))
    elseif act == "heal" then
        GameTooltip:AddLine(("Click: %s on %s"):format(BareName(self.healSpell or "heal"),
            (self.healUnit and UnitName(self.healUnit)) or "?"), T.rgb("gold"))
    elseif act == "drink" then
        local nm
        for _, c in ipairs(CONSUMABLES) do if c.id == self.drinkID then nm = c.name end end
        GameTooltip:AddLine("Click: drink " .. (nm or "mana consumable"), T.rgb("slate"))
    else
        GameTooltip:AddLine("Click: nothing to do", T.rgb("muted"))
    end

    if self.currentName then
        GameTooltip:AddLine("Rez target: " .. self.currentName, T.rgb("ink"))
    else
        GameTooltip:AddLine("No rez target" .. (self.failReason and (" -- " .. self.failReason) or ""), T.rgb("warn"))
    end

    -- Why the corpses you can see are being skipped. Straight lift of BiS
    -- Healing's "why here" tooltip: the reasons were already computed, they
    -- were just buried behind /bisrez list where nobody looks mid-wipe.
    if lastReject and #lastReject > 0 then
        GameTooltip:AddLine("Skipped:", T.rgb("muted"))
        for i = 1, math.min(#lastReject, 5) do
            local r = lastReject[i]
            GameTooltip:AddLine("  " .. r.name .. " -- " .. r.why, T.rgb("dim"))
        end
        if #lastReject > 5 then
            GameTooltip:AddLine("  ...and " .. (#lastReject - 5) .. " more", T.rgb("muted"))
        end
    end

    if self.combatLocked then
        GameTooltip:AddLine("Locked in combat -- showing what is armed", T.rgb("gold"))
    end
    if not act and self.armedFallback then
        GameTooltip:AddLine("Armed for combat: " .. BareName(self.armedFallback)
            .. " on mouseover / target / self", T.rgb("slate"))
    end
    if #healRanks > 0 then
        GameTooltip:AddLine(("Heals ready: %d%s"):format(#healRanks,
            groupHeal and (" + " .. BareName(groupHeal)) or ""), T.rgb("muted"))
    end
    local ctext, cleaders, ccount = ChampionText(4)
    if ctext then
        GameTooltip:AddLine((#cleaders > 1 and "Tied for lead: " or "Rez champion: ")
            .. table.concat(cleaders, ", ") .. " (" .. ccount .. ")", T.rgb("gold"))
    end
    GameTooltip:AddLine("Drag to move. /bisrez for options.", T.rgb("muted"))
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

--------------------------------------------------------------------------------
-- Refresh loop
--------------------------------------------------------------------------------

local elapsed = 0
local THROTTLE = 0.25
local lastState, STATE_EVERY = 0, 10

-- Cheap fingerprint of "which corpses are on screen". A rebind is protected
-- and touches forty secure buttons; this decides when it is worth doing.
function G.CorpseSignature()
    local parts = {}
    for _, unit in ipairs(CandidateUnits()) do
        if UnitExists(unit) and UnitIsPlayer(unit)
           and (UnitIsDead(unit) or UnitIsGhost(unit))
           and not UnitIsUnit(unit, "player") then
            parts[#parts + 1] = tostring(UnitGUID(unit))
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- Macro body. Defaults: long-form [target=], no rank suffix.
-- Bare spell name casts your highest known rank anyway; the "(Rank N)" suffix
-- and the "@" shorthand are the two things most likely to be silently rejected.
local function BuildMacro(unit)
    local db = DB()
    local spell = db.useRank and castName or baseName
    local cond  = db.useAtShorthand and ("[@" .. unit .. "]") or ("[target=" .. unit .. "]")
    return "/cast " .. cond .. " " .. spell
end

-- Heals go out as MACRO TEXT, not a spell attribute, for two reasons:
--   * the spell attribute was being handed "Chain Heal(Rank 5)"; the rez path
--     deliberately avoids that suffix as the thing most likely to be silently
--     rejected, and the heal path had no such care. BareName strips it.
--   * macro conditionals are resolved BY THE CLIENT AT CLICK TIME, which is the
--     trick BiS Healing uses to stay useful in combat. Secure attributes freeze
--     the moment combat starts, so whatever is armed at that instant is what
--     you get for the whole pull. A bare [@party3] would keep firing at a
--     stale unit; the fallback chain degrades to mouseover, then target, then
--     self, so the click still heals someone sensible.
local function BuildHealMacro(unit, spell)
    local s = BareName(spell)
    if not s then return "" end
    local head = unit and ("[@" .. unit .. ",help,nodead]") or ""
    return "/cast " .. head
           .. "[@mouseover,help,nodead][@target,help,nodead][@player] " .. s
end

function G.Refresh()
    -- Secure attributes are locked in combat, so we cannot re-aim the button.
    -- We do NOT fake it by updating the icon: whatever was armed when combat
    -- started is what the click will do, and the icon should keep saying so.
    -- What makes that survivable is BuildHealMacro's click-time fallback chain.
    if InCombatLockdown() then btn.combatLocked = true return end
    btn.combatLocked = false
    -- No out-of-combat rez (a druid, or a lookup that failed) is NOT the end of
    -- the button: heal and drink still work, and on a wipe those are most of
    -- what a druid is doing anyway. Only the rez branch is skipped.
    local canRez = castName ~= nil
    if not canRez then
        btn.currentName = nil
        btn.failReason = (playerClass == "DRUID")
            and "no out-of-combat rez -- Rebirth is yours to spend" or "rez spell not resolved"
    end

    if canRez then ScanCastBars() end

    local unit, name, score
    if canRez then unit, name, score = FindBestTarget() end

    -- macro body beats the spell+unit attribute pair: it parses "(Rank 5)"
    -- and @unit tokens the same way a normal rez macro does
    -- IMPORTANT: attributes must be button-suffixed. SecureButton_GetModifiedAttribute
    -- resolves "<mod>-type1" -> "*type1" -> "type1" -> "*type*" -> "type*".
    -- A bare "type" is NEVER consulted -- the click silently does nothing.
    -- "unit" is the exception: it has a bare fallback, so plain "unit" is fine.
    -- Decide what this click does. currentUnit stays REZ-ONLY: claims, scoring
    -- and the leaderboard all key off it, and a heal must never touch those.
    local mana = UnitPower("player", 0)
    local action, healUnit, healSpell, drinkBag, drinkSlot, drinkID
    local armedFallback

    if unit then
        if mana >= SpellCost(baseName) then
            action = "rez"
        elseif DB().autoDrink ~= false and not IsDrinking() then
            drinkBag, drinkSlot, drinkID = FindDrink()
            action = drinkBag and "drink" or nil
        end
    elseif DB().autoHeal ~= false and not UnitIsDeadOrGhost("player") then
        local biggest = healRanks[#healRanks]
        local probe = (biggest and biggest.cast) or groupHeal
        local lead = CastSeconds(probe)
        local hurt, injured = FindMostHurt(probe, lead)
        if hurt then
            local cost
            if injured > 1 and groupHeal and EffectiveDeficit(hurt, lead) > 0 then
                healSpell, cost = groupHeal, SpellCost(groupHeal)
            else
                local pick = PickHeal(hurt, lead)
                if pick then healSpell, cost = pick.cast, SpellCost(pick.id or pick.cast) end
            end
            if healSpell and mana >= cost then
                action, healUnit = "heal", hurt
            elseif healSpell and DB().autoDrink ~= false and not IsDrinking() then
                drinkBag, drinkSlot, drinkID = FindDrink()
                action = drinkBag and "drink" or nil
            end
        end
    end

    if action == "rez" then
        if DB().mode == "spell" then
            btn:SetAttribute("*type1", "spell")
            btn:SetAttribute("*spell1", DB().useRank and castName or baseName)
            btn:SetAttribute("unit", unit)
            btn:SetAttribute("*macrotext1", nil)
        else
            btn:SetAttribute("*type1", "macro")
            btn:SetAttribute("*macrotext1", BuildMacro(unit))
            btn:SetAttribute("*spell1", nil)
            btn:SetAttribute("unit", nil)
        end
        btn.currentUnit = unit
    elseif action == "heal" then
        btn:SetAttribute("*type1", "macro")
        btn:SetAttribute("*macrotext1", BuildHealMacro(healUnit, healSpell))
        btn:SetAttribute("*spell1", nil)
        btn:SetAttribute("unit", nil)
        btn.currentUnit = nil
    elseif action == "drink" then
        btn:SetAttribute("*type1", "macro")
        btn:SetAttribute("*macrotext1", ("/use %d %d"):format(drinkBag, drinkSlot))
        btn:SetAttribute("*spell1", nil)
        btn:SetAttribute("unit", nil)
        btn.currentUnit = nil
    else
        -- Nothing to do THIS instant -- which is exactly the state the button is
        -- usually in when a pull starts, and the state it would then be frozen
        -- in for the whole fight. Arm the biggest heal behind click-time
        -- conditionals so the button is a working heal button in combat instead
        -- of a dead one. Costs nothing out of combat: the icon stays greyed and
        -- the click just heals your target.
        local fb = healRanks[#healRanks]
        fb = (fb and fb.cast) or groupHeal
        armedFallback = (DB().autoHeal ~= false) and fb or nil
        btn:SetAttribute("*type1", "macro")
        btn:SetAttribute("*macrotext1", armedFallback and BuildHealMacro(nil, armedFallback) or "")
        btn:SetAttribute("*spell1", nil)
        btn:SetAttribute("unit", nil)
        btn.currentUnit = nil
    end

    btn.armedFallback = armedFallback
    btn.action    = action
    btn.healUnit  = healUnit
    btn.healSpell = healSpell
    btn.drinkID   = drinkID
    btn.currentName = name
    btn.failReason = nil

    -- rez target exists but we can't pay for it: say so in the tooltip
    if unit and action ~= "rez" then
        btn.failReason = (action == "drink") and "not enough mana -- drinking"
                         or "not enough mana"
    end

    -- Icon shows what the click will actually do, border colors the branch:
    -- good (teal) rez, gold heal, slate drink, dim nothing.
    if btn.icon then
        local tex = spellIcon
        if action == "heal" then tex = SpellIcon(healSpell) or spellIcon
        elseif action == "drink" then tex = ItemIcon(drinkID) or spellIcon end
        if tex then btn.icon:SetTexture(tex) end
        btn.icon:SetDesaturated(action == nil)
        btn.icon:SetAlpha(action and 1 or 0.4)
    end
    if btn.label then
        local who = (action == "rez" and name)
                    or (action == "heal" and healUnit and UnitName(healUnit))
        if action == "drink" then
            btn.label:SetText("drink")
            btn.label:SetTextColor(T.rgb("slate"))
        elseif who then
            local cunit = (action == "rez") and unit or healUnit
            local _, class = UnitClass(cunit)
            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            btn.label:SetText(who)
            if c then btn.label:SetTextColor(c.r, c.g, c.b) else btn.label:SetTextColor(T.rgb("ink")) end
        else
            btn.label:SetText("")
        end
    end
    if btn.border then
        if action == "rez" then SolidColor(btn.border, T.rgba("good", 0.6))
        elseif action == "heal" then SolidColor(btn.border, T.rgba("gold", 0.6))
        elseif action == "drink" then SolidColor(btn.border, T.rgba("slate", 0.6))
        else SolidColor(btn.border, T.rgba("dim", 0.2)) end
    end
end

-- Click reporting: tells you what was attempted and what the client said back
local lastClick = 0

-- One line per click, reporting the outcome. Set by PostClick, spent by whichever
-- of success / error / failure arrives first.
local REPORT_WINDOW = 3  -- a click's outcome line expires; see below

-- UI_ERROR_MESSAGE carries no spell attribution on this client, so v2.3 blamed
-- the pending target for ANY red error that happened to land within 1.5s of a
-- click -- "Healer6: You are already in a party". Filter to messages that are
-- actually cast failures, using the client's own localized strings so this
-- keeps working on a non-English client.
local CAST_ERRORS = {}
for _, g in ipairs({
    "SPELL_FAILED_OUT_OF_RANGE", "SPELL_FAILED_LINE_OF_SIGHT", "SPELL_FAILED_BAD_TARGETS",
    "SPELL_FAILED_TARGET_DEAD", "SPELL_FAILED_TARGET_NOT_DEAD", "SPELL_FAILED_NO_MANA",
    "SPELL_FAILED_SPELL_IN_PROGRESS", "SPELL_FAILED_NOT_READY", "SPELL_FAILED_MOVING",
    "SPELL_FAILED_INTERRUPTED", "SPELL_FAILED_TARGET_NOT_IN_PARTY",
    "SPELL_FAILED_TARGET_NOT_IN_RAID", "SPELL_FAILED_BAD_IMPLICIT_TARGETS",
    "SPELL_FAILED_NOTHING_TO_DISPEL", "SPELL_FAILED_REAGENTS", "SPELL_FAILED_TOTEMS",
    "SPELL_FAILED_CASTER_DEAD", "SPELL_FAILED_AFFECTING_COMBAT", "SPELL_FAILED_TRY_AGAIN",
    "SPELL_FAILED_ITEM_NOT_READY", "ERR_OUT_OF_MANA", "ERR_SPELL_COOLDOWN",
    "ERR_SPELL_OUT_OF_RANGE", "ERR_BADATTACKPOS", "ERR_GENERIC_NO_TARGET",
    "ERR_ITEM_COOLDOWN", "ERR_CLIENT_LOCKED_OUT",
}) do
    local v = _G[g]
    if type(v) == "string" and v ~= "" then CAST_ERRORS[v] = true end
end

local haveCastErrors = next(CAST_ERRORS) ~= nil

-- true if this red error plausibly came from the cast we just tried
local function IsCastError(msg)
    if type(msg) ~= "string" then return false end
    -- no localized strings on this build: fall back to v2.3 behaviour (report
    -- everything) rather than going silent, which would be the worse failure
    if not haveCastErrors then return true end
    if CAST_ERRORS[msg] then return true end
    -- some strings arrive with %s already substituted; match the stem too
    for pattern in pairs(CAST_ERRORS) do
        local stem = pattern:match("^([^%%]+)")
        if stem and #stem >= 8 and msg:sub(1, #stem) == stem then return true end
    end
    return false
end

-- reportPending used to be set on a click and cleared only when a matching
-- event arrived. If none ever did (an item use, a cast the client swallowed)
-- it stayed armed forever and the NEXT unrelated UI error in the game printed
-- with the old target's name glued to it. It now expires.
local function Report(text, color)
    if not btn.reportPending then return end
    if GetTime() - (btn.reportAt or 0) > REPORT_WINDOW then
        btn.reportPending = false
        return
    end
    btn.reportPending = false
    print("|cff66ccffBiS Rez|r: " .. T.text(color or "ink2", text))
end

btn:SetScript("PostClick", function(self)
    -- registered for both click edges, so this runs twice per click. The cast
    -- firing twice is harmless; the chat line twice is not.
    local dup = (GetTime() - lastClick) < 0.3
    lastClick = GetTime()

    -- Heal and drink clicks: no claim, no score, no success line. Only errors
    -- get reported, so topping people off doesn't spam chat.
    if self.action == "heal" or self.action == "drink" then
        if dup then return end
        self.pendingGUID = nil
        self.pendingName = (self.action == "heal" and self.healUnit
                            and UnitName(self.healUnit)) or nil
        self.reportPending = true
        self.reportAt = GetTime()
        self.reportSilentOK = true      -- consumed silently if the cast succeeds
        return
    end

    if not self.currentUnit then
        if dup then return end
        if self.armedFallback then
            -- greyed button, but a combat-safe heal is armed behind it
            self.pendingGUID = nil
            self.pendingName = UnitName("target") or UnitName("mouseover")
            self.reportPending = true
            self.reportAt = GetTime()
            self.reportSilentOK = true
        else
            print("|cff66ccffBiS Rez|r: " .. T.text("muted", "nothing to do"))
        end
        return
    end
    if dup then return end
    self.reportSilentOK = false

    -- claim is attached when the cast actually STARTS, not here: a click that
    -- dies on "not enough mana" never begins a cast and must not lock the target
    self.pendingGUID = UnitGUID(self.currentUnit)
    self.pendingName = self.currentName
    self.reportPending = true
    self.reportAt = GetTime()

    if DB().verbose then
        print("|cff66ccffBiS Rez v" .. VERSION .. "|r: "
              .. ((DB().mode == "spell")
                  and ("spell=" .. tostring(DB().useRank and castName or baseName)
                       .. " unit=" .. self.currentUnit)
                  or BuildMacro(self.currentUnit)))
    end

    if UnitIsDeadOrGhost("player") then
        Report("you're dead", "warn")
    elseif InCombatLockdown() then
        Report("in combat", "warn")
    end
end)

function btn:UpdateChamp()
    if not self.champ then return end
    if DB().hideChamp then self.champ:SetText("") return end
    local text, leaders = ChampionText(2)
    if not text then
        self.champ:SetText(T.text("muted", "no rezzes yet"))
        return
    end
    local col = "gold"
    local me = UnitName("player")
    for _, n in ipairs(leaders) do
        if n == me then col = "good" break end
    end
    self.champ:SetText(T.text(col, text))
end

btn:SetScript("OnUpdate", function(self, e)
    elapsed = elapsed + e
    if elapsed < THROTTLE then return end
    elapsed = 0
    if healRebuildAt and GetTime() >= healRebuildAt then
        healRebuildAt = nil
        G.BuildHealTable()
    end
    G.Refresh()
    self:UpdateChamp()

    -- The window repaints every tick (textures and text only, safe in combat)
    -- but REBINDS only when the corpse list actually changes, and only out of
    -- combat: rebinding a secure button mid-fight is the one thing that cannot
    -- be done at all.
    local W = G.Window
    if W and W.frame then
        local sig = G.CorpseSignature()
        if sig ~= W.lastSig and not InCombatLockdown() then
            W.lastSig = sig
            W:Bind()
        else
            W:Refresh()
        end
    end

    if GetTime() - lastState > STATE_EVERY then
        lastState = GetTime()
        G.BroadcastState()
    end
end)

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local registeredEvents = {}
local wasInGroup = false
local lastGroupGUIDs = {}
local f = CreateFrame("Frame")
-- Register defensively: an unknown event name throws and would kill the rest
-- of this file (that's what LEARNED_SPELL_IN_TAB did on this build).
for _, ev in ipairs({
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB",
    "PLAYER_EQUIPMENT_CHANGED",   -- tooltip heal numbers move with +healing
    "COMBAT_LOG_EVENT_UNFILTERED",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_STOP",
    "CHAT_MSG_ADDON",
    -- roster changes: different clients ship different subsets of these three,
    -- so register all and route them to the same branch
    "GROUP_ROSTER_UPDATE",
    "RAID_ROSTER_UPDATE",
    "PARTY_MEMBERS_CHANGED",
    "UI_ERROR_MESSAGE",
    "PLAYER_REGEN_ENABLED",   -- the pull is over: everything protected that waited
}) do
    registeredEvents[ev] = pcall(f.RegisterEvent, f, ev) or nil
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local who = ...
        if type(who) ~= "string" or who:lower() ~= ADDON:lower() then return end
        local db = DB()
        -- 3.0 folded the button and the window into one frame, so the two sets
        -- of flags become one. Done once, additively: if either half was hidden
        -- or locked before, it stays that way.
        if db.windowHidden ~= nil then
            db.hidden = (db.hidden or db.windowHidden) and true or nil
            db.windowHidden = nil
        end
        if db.windowLocked ~= nil then
            db.locked = (db.locked or db.windowLocked) and true or nil
            db.windowLocked = nil
        end
        if db.pos and not db.windowPos then db.windowPos = db.pos end
        db.pos = nil
        if db.pos then
            local p, rp, x, y = unpack(db.pos)
            btn:ClearAllPoints()
            btn:SetPoint(p, UIParent, rp, x, y)
        end
        if db.hidden then btn:Hide() end
        if db.clickMode == nil then db.clickMode = "down" end
        if db.clickMode == "down" then btn:RegisterForClicks("AnyDown")
        elseif db.clickMode == "up" then btn:RegisterForClicks("AnyUp")
        else btn:RegisterForClicks("AnyDown", "AnyUp") end

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
        or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        if ResolveSpell(event == "PLAYER_LOGIN") then
            if spellIcon and btn.icon then btn.icon:SetTexture(spellIcon) end
        elseif not CLASS_HEALS[playerClass] then
            -- nothing to rez with AND nothing to heal with: there is no button
            -- worth showing. A druid falls through here and keeps theirs.
            btn:Hide()
            if event == "PLAYER_LOGIN" then
                print("|cff66ccffBiS Rez|r: " .. T.text("warn",
                      "your class has no out-of-combat rez and no heals. Hiding the button."))
            end
        end
        BuildRezNameSet()
        G.ResolveWipeSpell()
        G.BuildHealTable()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(PREFIX)
        end
        local gprefix, gcount = GroupInfo()
        wasInGroup = gcount > 0
        local myGUID = UnitGUID("player")
        for i = 1, gcount do
            local g = UnitGUID(gprefix .. i)
            if g and g ~= myGUID then lastGroupGUIDs[g] = true end
        end
        if wasInGroup then RequestSync() end
        pcall(function() G.Minimap:Build() end)
        local okw, errw = pcall(function() G.Window:Build() end)
        if not okw then
            print("|cff66ccffBiS Rez|r: " .. T.text("warn", "corpse window failed -- " .. tostring(errw)))
        else
            G.Window:Bind()
        end
        G.ApplyVisibility()
        Later(3, function() SendHello() end)
        -- override bindings do not survive /reload, so re-apply the stored one
        if DB().bindKey then ApplyBind(DB().bindKey) end
        if event == "PLAYER_LOGIN" then
            print("|cff66ccffBiS Rez v" .. VERSION .. "|r loaded -- spell: " .. tostring(castName)
                  .. " -- type /bisrez")
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Secure attributes are writable again. Everything the fight deferred
        -- happens here, exactly as BiS Innervate's AfterCombat does it.
        if G.Window then G.Window:Bind() end
        G.ApplyVisibility()

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        healRebuildAt = GetTime() + 1

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local sub, srcName, dstGUID, spellName
        if CLEUInfo then
            local a = { CLEUInfo() }
            sub, srcName, dstGUID, spellName = a[2], a[5], a[8], a[13]
        else
            local a = { ... }
            sub, srcName, dstGUID, spellName = a[2], a[5], a[8], a[13]
        end
        if sub == "SPELL_RESURRECT" then
            MarkRezzed(dstGUID)
            -- only count real class rezzes, not soulstones or self-rez
            if (not spellName) or REZ_NAMES[spellName] then
                AddScore(srcName)
                if btn.UpdateChamp then btn:UpdateChamp() end
            end
        end

    elseif event == "UI_ERROR_MESSAGE" then
        local a, b = ...
        local msg = (type(a) == "string") and a or b
        if msg and GetTime() - lastClick < 1.5 and IsCastError(msg) then
            -- cast never began (no mana, out of range, etc): release immediately
            if btn.pendingGUID then
                ClearClaim(btn.pendingGUID)
                Send("FREE", btn.pendingGUID)
                btn.pendingGUID = nil
            end
            Report((btn.pendingName or "target") .. ": " .. tostring(msg), "warn")
        end

    elseif event == "CHAT_MSG_ADDON" then
        local pfx, msg, chan, sender = ...
        if pfx == PREFIX and msg then
            local sname = sender and sender:match("^[^-]+") or sender
            local p = Split(msg)
            local proto = tonumber(p[1] or "")
            local cmd = p[2]
            -- Only our protocol. A v2.7 "C:<guid>" parses as proto nil and is
            -- dropped rather than half-understood; say so once, per direction.
            if proto ~= PROTOCOL then
                if proto and proto > PROTOCOL and not warnedNewer then
                    warnedNewer = true
                    print("|cff66ccffBiS Rez|r: " .. T.text("gold",
                        "somebody in the group runs a newer BiS Rez -- update yours."))
                elseif not warnedOlder and tostring(msg):match("^[CDXHS]:") then
                    warnedOlder = true
                    print("|cff66ccffBiS Rez|r: " .. T.text("muted",
                        tostring(sname) .. " runs an older BiS Rez -- their claims are invisible to you."))
                end
            -- Only from the group, and only on a group channel: a whispered
            -- addon message from a stranger must not be able to plant or
            -- release a claim on a corpse.
            elseif cmd and (chan == "RAID" or chan == "PARTY" or chan == "INSTANCE_CHAT")
                   and sname and (sname == UnitName("player") or G.UnitByName(sname)) then
                local a1 = p[3]
                if sname ~= UnitName("player") then
                    if cmd == "HELLO" then
                        NoteRezzer(sname, p[4], tonumber(p[5] or ""), false, p[7] or "")
                        -- Answer EVERY hello, throttled -- not just a newcomer's.
                        -- A client that lost its table (a zone-in, a reload) says
                        -- hello again and needs answering INSIDE the throttle, or
                        -- the rezzer strip never comes back for them.
                        local theyKnow = tonumber(p[6] or "") or 0
                        local short = theyKnow < (CountUsers() - 1)
                        local throttled = (GetTime() - lastHelloBack) <= 5
                        if not helloBack and (short or not throttled) then
                            helloBack = true
                            Later(1 + math.random() * 2, function()
                                helloBack = false
                                lastHelloBack = GetTime()
                                SendHello()
                            end)
                        end
                        if G.Window then G.Window:Refresh() end
                    elseif cmd == "STATE" then
                        NoteRezzer(sname, a1, tonumber(p[4] or ""), p[5] == "1", p[6] or "")
                        if G.Window then G.Window:Refresh() end
                    elseif cmd == "WANT" then
                        ScheduleReply()
                    elseif cmd == "SCORE" then
                        syncSeenAt = GetTime()
                        if MergeScores(a1 or "") then
                            btn:UpdateChamp()
                            if BiSRezConfig and BiSRezConfig:IsShown() then BiSRezConfig:Refresh() end
                        end
                        if GetTime() - lastSyncPrint > 3 then
                            lastSyncPrint = GetTime()
                            local total = 0
                            for _ in pairs(Scores()) do total = total + 1 end
                            print("|cff66ccffBiS Rez|r: " .. T.text("good", "scoreboard synced with "
                                  .. sname) .. " (" .. total .. " on the board)")
                        end
                    elseif cmd == "CLAIM" then
                        Claim(a1, sname, CLAIM_LIFE, "comm")
                        if a1 == UnitGUID("player") then G.RezIncomingOnMe(sname) end
                        if G.Window then G.Window:Refresh() end
                    elseif cmd == "DONE" then
                        Claim(a1, sname, 30, "comm")
                        if G.Window then G.Window:Refresh() end
                    elseif cmd == "FREE" then
                        ClearClaim(a1)
                        if G.Window then G.Window:Refresh() end
                    end
                end
            end
        end

    elseif event == "UNIT_SPELLCAST_START" then
        local u, _, spell = ...
        if u == "player" and btn.pendingGUID then
            if IsRezSpellArg(spell) then
                Claim(btn.pendingGUID, UnitName("player"), CLAIM_LIFE, "comm")
                Send("CLAIM", btn.pendingGUID)
            end
        end

    elseif event == "UNIT_SPELLCAST_STOP" then
        -- Only OUR rez ending should retire the pending target. Without the
        -- spell guard any other cast of yours finishing wiped pendingGUID and
        -- broke the claim/report bookkeeping for the rez still in flight.
        local u, _, spell = ...
        if u == "player" and btn.pendingGUID and IsRezSpellArg(spell) then
            btn.pendingGUID = nil
        end

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- Same guard. v2.3 released the claim AND broadcast "X:" to the whole
        -- group whenever ANY spell of yours was interrupted -- the target
        -- reopened on everyone else's button mid-rez, which is the exact
        -- double-rez this addon exists to prevent.
        local u, _, spell = ...
        if u == "player" and IsRezSpellArg(spell) then
            local guid = btn.pendingGUID or (btn.currentUnit and UnitGUID(btn.currentUnit))
            if guid then ClearClaim(guid) Send("FREE", guid) end
            btn.pendingGUID = nil
        end

    elseif event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE"
        or event == "PARTY_MEMBERS_CHANGED" then
        -- Compare group membership by GUID, excluding yourself. Clearing only on
        -- an empty roster misses group->group hops, where the count never hits 0.
        -- A zone-in reads the roster as empty for a moment. Believing it
        -- cleared the scoreboard mid-raid; see G.RosterBlip.
        if G.RosterBlip() then return end
        local prefix, count = GroupInfo()
        local cur, curCount, overlap = {}, 0, 0
        local myGUID = UnitGUID("player")
        for i = 1, count do
            local g = UnitGUID(prefix .. i)
            if g and g ~= myGUID and not cur[g] then
                cur[g] = true
                curCount = curCount + 1
                if lastGroupGUIDs[g] then overlap = overlap + 1 end
            end
        end

        local hadGroup = next(lastGroupGUIDs) ~= nil
        local reason
        if hadGroup and curCount == 0 then
            reason = "left the group"
        elseif hadGroup and curCount > 0 and overlap == 0 then
            reason = "new group"
        end

        if reason and not DB().keepScores then
            local had = false
            for _ in pairs(Scores()) do had = true break end
            DB().scores = {}
            btn:UpdateChamp()
            if BiSRezConfig and BiSRezConfig:IsShown() then BiSRezConfig:Refresh() end
            if had then print("|cff66ccffBiS Rez|r: " .. reason .. " -- scoreboard cleared.") end
        end

        -- joined a group (or a different one): ask whoever is there for the board
        if curCount > 0 and (not hadGroup or reason == "new group") then
            RequestSync()
        end

        lastGroupGUIDs = cur
        wasInGroup = curCount > 0
        ForgetAbsent()
        if G.Window then G.Window:Bind() end

    elseif event == "UNIT_SPELLCAST_FAILED" then
        local u, _, fspell = ...
        if u == "player" and IsRezSpellArg(fspell) then
            if btn.currentUnit then
                local guid = UnitGUID(btn.currentUnit)
                if guid then ClearClaim(guid) Send("FREE", guid) end
            end
            if GetTime() - lastClick < 1.5 then
                Report((btn.pendingName or "target") .. ": cast failed", "warn")
            end
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spell = ...
        if unit == "player" and btn.reportSilentOK and not IsRezSpellArg(spell) then
            -- our heal landed: clear the pending line without printing it
            btn.reportPending = false
            btn.reportSilentOK = false
        end
        if unit == "player" and IsRezSpellArg(spell) then
            Report("rezzed " .. tostring(btn.pendingName or btn.currentName), "good")
        end
        if unit == "player" and IsRezSpellArg(spell) and btn.currentName then
            -- our own cast landed on whoever we had queued
            for _, u in ipairs(CandidateUnits()) do
                if UnitName(u) == btn.currentName then
                    local guid = UnitGUID(u)
                    MarkRezzed(guid)
                    if guid then Send("DONE", guid) end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Options window
--
-- Flat, layered config panel in the spirit of FojjiCore's -- a left rail of
-- tabs, surfaces that step a shade lighter as they come forward, 1px texture
-- borders, everything hand-built -- but in BiS violet on violet-black, and
-- wired straight to the same saved variables the slash commands already set,
-- so the two can never drift apart.
--------------------------------------------------------------------------------

local Cfg = { built = false, tab = "Rez", controls = {}, dyn = {} }
G.Cfg = Cfg

-- shades, darkest (furthest back) to lightest (most forward)
local function hx(h) return tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255 end
local SH = {
    frame   = { hx("0d0b18") },
    header  = { hx("141127") },
    sidebar = { hx("191531") },
    content = { hx("1f1a3a") },
    field   = { hx("17132e") },
    hair    = { hx("2a2446") },
    edge    = { hx("3a3260") },
}
local function shade(name, a) local c = SH[name] return c[1], c[2], c[3], a or 1 end

local function tex(parent, layer, name, a)
    local t = parent:CreateTexture(nil, layer)
    if SH[name] then t:SetColorTexture(shade(name, a)) else t:SetColorTexture(T.rgba(name, a)) end
    return t
end

local function border(f, name, a)
    local col = {}
    local function bar()
        local b = f:CreateTexture(nil, "BORDER")
        b:SetColorTexture(T.rgba(name, a or 1))
        return b
    end
    col.top = bar()     col.top:SetPoint("TOPLEFT")      col.top:SetPoint("TOPRIGHT")      col.top:SetHeight(1)
    col.bottom = bar()  col.bottom:SetPoint("BOTTOMLEFT") col.bottom:SetPoint("BOTTOMRIGHT") col.bottom:SetHeight(1)
    col.left = bar()    col.left:SetPoint("TOPLEFT")     col.left:SetPoint("BOTTOMLEFT")   col.left:SetWidth(1)
    col.right = bar()   col.right:SetPoint("TOPRIGHT")   col.right:SetPoint("BOTTOMRIGHT") col.right:SetWidth(1)
    -- NOTE the explicit four-argument call. `on and T.rgba(x) or shade(y)` would
    -- truncate to ONE value and SetColorTexture throws, taking the whole window
    -- with it. Every branch below passes a full argument list on purpose.
    function col:set(n, aa)
        for _, b in pairs(self) do
            if type(b) == "table" and b.SetColorTexture then b:SetColorTexture(T.rgba(n, aa or 1)) end
        end
    end
    return col
end

local function fs(parent, text, size, colorName)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "")
    f:SetText(text or "")
    f:SetTextColor(T.rgb(colorName or "ink"))
    return f
end

-- re-apply anything that has a live effect the moment a setting changes
local function Apply()
    local b = G.btn
    if not b then return end
    if DB().hidden then b:Hide() else b:Show() end
    if b.UpdateChamp then b:UpdateChamp() end
    if G.Refresh and not InCombatLockdown() then G.Refresh() end
    if Cfg.built and Cfg.frame and Cfg.frame:IsShown() then Cfg.frame:Refresh() end
end

--------------------------------------------------------------------------------
-- widgets -- each returns the next y and registers a setter in Cfg.controls[id]
--------------------------------------------------------------------------------

local ROW_H = 30

local function Check(page, y, id, label, tip, get, set)
    local row = CreateFrame("Button", nil, page)
    row:SetSize(page.w, ROW_H) row:SetPoint("TOPLEFT", 0, y)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(18, 18) box:SetPoint("LEFT", 0, 0)
    local bg = tex(box, "BACKGROUND", "field") bg:SetAllPoints()
    local bd = border(box, "edge")
    local fill = tex(box, "ARTWORK", "accent")
    fill:SetPoint("TOPLEFT", 4, -4) fill:SetPoint("BOTTOMRIGHT", -4, 4)
    local lbl = fs(row, label, 12, "ink") lbl:SetPoint("LEFT", box, "RIGHT", 10, 0)
    local function paint()
        if get() then fill:Show() bd:set("accent", 0.8) else fill:Hide() bd:set("edge") end
    end
    local ctrl = { paint = paint }
    function ctrl.set(v) set(v and true or false) paint() Apply() end
    function ctrl.get() return get() and true or false end
    row:SetScript("OnClick", function() ctrl.set(not get()) end)
    row:SetScript("OnEnter", function()
        bd:set("accent", 0.8)
        if tip then
            GameTooltip:SetOwner(row, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tip, 0.6, 0.63, 0.67, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() paint() GameTooltip:Hide() end)
    paint()
    Cfg.controls[id] = ctrl
    return y - ROW_H
end

local function Seg(page, y, id, label, options, get, set)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(page.w, ROW_H) row:SetPoint("TOPLEFT", 0, y)
    fs(row, label, 12, "ink"):SetPoint("LEFT", 0, 0)
    local pills = {}
    local function paint()
        for v, p in pairs(pills) do
            local on = (get() == v)
            if on then p.bg:SetColorTexture(T.rgba("accent", 0.18))
            else p.bg:SetColorTexture(shade("field")) end
            if on then p.bd:set("accent", 0.8) else p.bd:set("edge", 1) end
            if on then p.lbl:SetTextColor(T.rgb("accent")) else p.lbl:SetTextColor(T.rgb("muted")) end
        end
    end
    local ctrl = { paint = paint }
    function ctrl.set(v) set(v) paint() Apply() end
    function ctrl.get() return get() end
    local x = 0
    for i = #options, 1, -1 do
        local opt = options[i]
        local w = opt.w or 58
        local p = CreateFrame("Button", nil, row)
        p:SetSize(w, 20) p:SetPoint("RIGHT", -x, 0)
        p.bg = tex(p, "BACKGROUND", "field") p.bg:SetAllPoints()
        p.bd = border(p, "edge")
        p.lbl = fs(p, opt.label, 11, "muted") p.lbl:SetPoint("CENTER")
        p:SetScript("OnClick", function() ctrl.set(opt.v) end)
        p:SetScript("OnEnter", function() if get() ~= opt.v then p.bd:set("accent", 0.6) end end)
        p:SetScript("OnLeave", function() paint() end)
        pills[opt.v] = p
        x = x + w + 4
    end
    paint()
    Cfg.controls[id] = ctrl
    return y - ROW_H
end

local function Btn(page, y, id, label, tip, onclick, colorName)
    local b = CreateFrame("Button", nil, page)
    b:SetSize(170, 22) b:SetPoint("TOPLEFT", 0, y)
    local bg = tex(b, "BACKGROUND", "field") bg:SetAllPoints()
    local bd = border(b, "edge")
    local lbl = fs(b, label, 12, colorName or "ink2") lbl:SetPoint("CENTER")
    b:SetScript("OnClick", function() onclick() end)
    b:SetScript("OnEnter", function()
        if colorName == "warn" then bd:set("warn", 0.8) else bd:set("accent", 0.8) end
        if tip then
            GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(tip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() bd:set("edge") GameTooltip:Hide() end)
    if id then Cfg.controls[id] = { click = onclick } end
    return y - 30
end

local function Caption(page, y, text)
    local c = fs(page, string.upper(text), 10, "muted")
    c:SetPoint("TOPLEFT", 0, y)
    return y - 20
end

-- a line of text the Refresh pass rewrites
local function Live(page, y, key, size, colorName, lines)
    local t = fs(page, "", size or 11, colorName or "ink2")
    t:SetPoint("TOPLEFT", 0, y)
    t:SetWidth(page.w)
    t:SetJustifyH("LEFT")
    Cfg.dyn[key] = t
    return y - ((lines or 1) * 16 + 6)
end

--------------------------------------------------------------------------------
-- pages
--------------------------------------------------------------------------------

local function BuildRez(page)
    local y = 0
    y = Caption(page, y, "Casting")
    y = Seg(page, y, "mode", "Cast through",
        { { v = "macro", label = "macro text", w = 76 }, { v = "spell", label = "spell attr", w = 76 } },
        function() return (DB().mode == "spell") and "spell" or "macro" end,
        function(v) DB().mode = v end)
    y = Seg(page, y, "at", "Macro syntax",
        { { v = false, label = "[target=]", w = 70 }, { v = true, label = "[@unit]", w = 62 } },
        function() return DB().useAtShorthand and true or false end,
        function(v) DB().useAtShorthand = v end)
    y = Check(page, y, "rank", "Append the rank suffix, e.g. (Rank 5)",
        "Off is safer. A bare spell name already casts your highest rank, and the suffix is one of the two things this client silently rejects.",
        function() return DB().useRank end,
        function(v) DB().useRank = v end)
    y = y - 8

    y = Caption(page, y, "Priority")
    y = Live(page, y, "prio", 11, "ink2", 2)
    y = y - 4

    y = Caption(page, y, "What a click sends right now")
    y = Live(page, y, "macro", 11, "gold", 2)
end

local function BuildSupport(page)
    local y = 0
    y = Caption(page, y, "When nobody needs a rez")
    y = Check(page, y, "autoheal", "Heal whoever is worst off",
        "Rezzing always wins. This only fires when there is no rezzable target -- and it stands down when other healers already have everyone covered.",
        function() return DB().autoHeal ~= false end,
        function(v) DB().autoHeal = v end)
    y = Check(page, y, "autodrink", "Drink when the next cast is unaffordable",
        "A rez or heal you cannot pay for turns the button into a drink. Conjured Manna Biscuit first, then the 7200-mana drinks.",
        function() return DB().autoDrink ~= false end,
        function(v) DB().autoDrink = v end)
    y = y - 8

    y = Caption(page, y, "Heals")
    y = Live(page, y, "heals", 11, "ink2", 3)
    y = Btn(page, y, "rescan", "Rebuild the heal list",
        "Re-walk the spellbook and re-measure heal sizes against your current gear.",
        function()
            if G.BuildHealTable then G.BuildHealTable() end
            Apply()
        end)
    y = y - 4
    Btn(page, y, "healsdump", "List them in chat",
        "Print every heal, its size, its cost, and the drink it found.",
        function() SlashCmdList["BISREZ"]("heals") end)
end

local function BuildLeaderboard(page)
    local y = 0
    y = Caption(page, y, "Display")
    y = Check(page, y, "champ", "Show the rez champion above the button",
        "A running tally of who has rezzed the most. Ties are shown as ties.",
        function() return not DB().hideChamp end,
        function(v) DB().hideChamp = not v end)
    y = y - 8

    y = Caption(page, y, "Counting")
    y = Check(page, y, "keep", "Keep scores after leaving the group",
        "Off: the board clears when you leave or change groups, so each raid starts fresh.",
        function() return DB().keepScores end,
        function(v) DB().keepScores = v end)
    y = Check(page, y, "guild", "Only count guildmates",
        "Pugs stop appearing on the board.",
        function() return DB().guildOnly end,
        function(v) DB().guildOnly = v end)
    y = y - 8

    y = Caption(page, y, "The board")
    y = Live(page, y, "board", 11, "gold", 1)
    y = Btn(page, y, "score", "Print the scoreboard", "Dump the full standings to chat.",
        function() SlashCmdList["BISREZ"]("score") end)
    y = y - 4
    y = Btn(page, y, "sync", "Ask the group for the board",
        "Other BiS Rez users answer with their tallies; the higher count wins.",
        function() SlashCmdList["BISREZ"]("sync") end)
    y = y - 4
    Btn(page, y, "resetscore", "Clear the leaderboard", "Wipe every tally, including your own.",
        function() SlashCmdList["BISREZ"]("resetscore") Apply() end, "warn")
end

local function BuildButton(page)
    local y = 0
    y = Caption(page, y, "Input")
    y = Seg(page, y, "clicks", "Fires on",
        { { v = "down", label = "down", w = 52 }, { v = "up", label = "up", w = 44 },
          { v = "both", label = "both", w = 50 } },
        function() return DB().clickMode or "down" end,
        function(v)
            -- RegisterForClicks is protected once the pull starts
            if InCombatLockdown() then
                print("|cff66ccffBiS Rez|r: " .. T.text("warn", "can't change the click edge in combat."))
                return
            end
            DB().clickMode = v
            local b = G.btn
            if not b then return end
            if v == "down" then b:RegisterForClicks("AnyDown")
            elseif v == "up" then b:RegisterForClicks("AnyUp")
            else b:RegisterForClicks("AnyDown", "AnyUp") end
        end)
    y = Live(page, y, "bind", 11, "ink2", 1)
    y = y - 4

    y = Caption(page, y, "Diagnostics")
    y = Check(page, y, "verbose", "Print the full cast detail on every click",
        "Debugging only. Prints the exact macro body or spell/unit pair each click sends.",
        function() return DB().verbose end,
        function(v) DB().verbose = v end)
    y = Btn(page, y, "list", "List every candidate",
        "Each unit it considered, and why it was taken or skipped.",
        function() SlashCmdList["BISREZ"]("list") end)
    y = y - 4
    y = Btn(page, y, "claims", "Show active claims", "Who is currently rezzing whom.",
        function() SlashCmdList["BISREZ"]("claims") end)
    y = y - 4
    Btn(page, y, "diag", "Diagnostics", "Spell resolution, cast lead, inbound heals, attribute state.",
        function() SlashCmdList["BISREZ"]("diag") end)
end

local function BuildWindow(page)
    local y = 0
    y = Caption(page, y, "The window")
    y = Check(page, y, "shown", "Show BiS Rez",
        "The whole thing: the button, the corpse list and the rezzer strip are one window. Hiding it does not turn the addon off -- a bound key still casts.",
        function() return not DB().hidden end,
        function(v)
            if InCombatLockdown() then
                print("|cff66ccffBiS Rez|r: " .. T.text("warn", "it can't be toggled in combat."))
                return
            end
            G.Window:Build()
            G.Window:SetShown(v)
        end)
    y = Check(page, y, "locked", "Lock its position",
        "Stops it being dragged. Drag it by the title bar or by the button itself.",
        function() return DB().locked end,
        function(v) DB().locked = v end)
    y = Check(page, y, "hidecombat", "Hide it in combat",
        "This is an out-of-combat addon and a stray click mid-fight just throws a red error. A bound key still fires.",
        function() return DB().hideInCombat ~= false end,
        function(v) DB().hideInCombat = v G.ApplyVisibility() end)
    y = Btn(page, y, "resetpos", "Reset its position", "Put it back in the middle of the screen.",
        function()
            if InCombatLockdown() then
                print("|cff66ccffBiS Rez|r: " .. T.text("warn", "can't move it in combat."))
                return
            end
            local w = G.Window and G.Window.frame
            if w then
                w:ClearAllPoints()
                w:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
            end
            DB().windowPos = nil
        end)
    y = Check(page, y, "minimapbtn", "Minimap coin",
        "Left toggles the window, right opens these options, shift-left prints who can rez.",
        function() return DB().minimap ~= false end,
        function(v) G.Minimap:Set(v) end)
    y = y - 10

    y = Caption(page, y, "Other rezzers")
    y = Live(page, y, "rezzers", 11, "ink2", 4)
    Btn(page, y, "rezzerlist", "List them in chat",
        "Every rezzer running BiS Rez, their class, and whether their rez is up.",
        function() SlashCmdList["BISREZ"]("rezzers") end)
end

local PAGES = {
    { name = "Rez",         build = BuildRez },
    { name = "Support",     build = BuildSupport },
    { name = "Leaderboard", build = BuildLeaderboard },
    { name = "Window",      build = BuildWindow },
    { name = "Button",      build = BuildButton },
}

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------

function G.ShowConfigTab(name)
    if not Cfg.built then return end
    Cfg.tab = name
    for _, t in ipairs(Cfg.tabs) do
        local on = (t.name == name)
        t.indicator:SetShown(on)
        t.glow:SetShown(on)
        if on then t.label:SetTextColor(T.rgb("ink")) else t.label:SetTextColor(T.rgb("muted")) end
        Cfg.pages[t.name]:SetShown(on)
    end
end

local function PriorityText()
    local order = {}
    for class, rank in pairs(PRIORITY) do order[rank] = class end
    local parts = {}
    for i = 1, #order do
        local c = order[i]
        local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]
        local pretty = c:sub(1, 1) .. c:sub(2):lower()
        if col then
            parts[#parts + 1] = string.format("|cff%02x%02x%02x%s|r",
                math.floor(col.r * 255), math.floor(col.g * 255), math.floor(col.b * 255), pretty)
        else
            parts[#parts + 1] = pretty
        end
    end
    return table.concat(parts, "  >  ")
end

function G.BuildConfig()
    if Cfg.built then return Cfg.frame end
    Cfg.built = true
    Cfg.tabs, Cfg.pages = {}, {}

    local f = CreateFrame("Frame", "BiSRezConfig", UIParent)
    f:SetSize(700, 500) f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG") f:SetFrameLevel(120)
    f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()   -- CreateFrame returns a SHOWN frame; without this the first
               -- /bisrez toggles it straight back off again
    tex(f, "BACKGROUND", "frame", 0.98):SetAllPoints()
    border(f, "accent", 0.55)
    tinsert(UISpecialFrames, "BiSRezConfig")
    Cfg.frame = f

    -- header
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 1, -1) head:SetPoint("TOPRIGHT", -1, -1) head:SetHeight(64)
    tex(head, "BACKGROUND", "header"):SetAllPoints()

    local logo = head:CreateTexture(nil, "ARTWORK")
    logo:SetSize(30, 30) logo:SetPoint("LEFT", 18, 0)
    logo:SetTexture(spellIcon or "Interface\\Icons\\Spell_Holy_Resurrection")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Cfg.logo = logo

    local title = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 16, "")
    title:SetText("|cffb980ffBiS|r |cff4fd0cfRez|r")
    title:SetPoint("LEFT", logo, "RIGHT", 10, 6)

    local ver = fs(head, "Settings  -  v" .. VERSION, 10, "dim")
    ver:SetPoint("LEFT", logo, "RIGHT", 10, -9)

    local x = CreateFrame("Button", nil, head)
    x:SetSize(28, 28) x:SetPoint("RIGHT", -16, 0)
    tex(x, "BACKGROUND", "field"):SetAllPoints()
    local xbd = border(x, "edge")
    local xt = fs(x, "x", 15, "muted") xt:SetPoint("CENTER", 0, 1)
    x:SetScript("OnEnter", function() xbd:set("accent", 0.8) xt:SetTextColor(T.rgb("ink")) end)
    x:SetScript("OnLeave", function() xbd:set("edge") xt:SetTextColor(T.rgb("muted")) end)
    x:SetScript("OnClick", function() f:Hide() end)

    local hsep = tex(f, "ARTWORK", "hair")
    hsep:SetPoint("TOPLEFT", 1, -65) hsep:SetPoint("TOPRIGHT", -1, -65) hsep:SetHeight(1)

    -- body: sidebar + content
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 1, -66) body:SetPoint("BOTTOMRIGHT", -1, 1)
    local side = CreateFrame("Frame", nil, body)
    side:SetPoint("TOPLEFT") side:SetPoint("BOTTOMLEFT") side:SetWidth(168)
    tex(side, "BACKGROUND", "sidebar"):SetAllPoints()
    local cont = CreateFrame("Frame", nil, body)
    cont:SetPoint("TOPLEFT", side, "TOPRIGHT") cont:SetPoint("BOTTOMRIGHT")
    tex(cont, "BACKGROUND", "content"):SetAllPoints()
    local divide = tex(body, "ARTWORK", "edge")
    divide:SetPoint("TOPLEFT", side, "TOPRIGHT") divide:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT")
    divide:SetWidth(1)

    for i, spec in ipairs(PAGES) do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(168, 44) b:SetPoint("TOPLEFT", 0, -14 - (i - 1) * 44)
        b.name = spec.name
        b.glow = tex(b, "BACKGROUND", "accent", 0.10) b.glow:SetAllPoints() b.glow:Hide()
        b.indicator = tex(b, "ARTWORK", "accent", 1)
        b.indicator:SetPoint("TOPLEFT") b.indicator:SetPoint("BOTTOMLEFT")
        b.indicator:SetWidth(3) b.indicator:Hide()
        b.label = fs(b, spec.name, 13, "muted") b.label:SetPoint("LEFT", 24, 0)
        b:SetScript("OnEnter", function()
            if Cfg.tab ~= spec.name then
                b.glow:SetColorTexture(1, 1, 1, 0.03)
                b.glow:Show()
                b.label:SetTextColor(T.rgb("ink2"))
            end
        end)
        b:SetScript("OnLeave", function()
            if Cfg.tab ~= spec.name then b.glow:Hide() b.label:SetTextColor(T.rgb("muted")) end
        end)
        b:SetScript("OnClick", function() G.ShowConfigTab(spec.name) end)
        Cfg.tabs[i] = b

        local page = CreateFrame("Frame", nil, cont)
        page:SetPoint("TOPLEFT", 30, -26) page:SetPoint("BOTTOMRIGHT", -30, 24)
        page.w = 700 - 168 - 60
        page:Hide()
        spec.build(page)
        Cfg.pages[spec.name] = page
    end

    local tip = fs(cont, "Everything here is also a /bisrez command -- /bisrez help", 10, "dim")
    tip:SetPoint("BOTTOMLEFT", 30, 8)

    -- repaint every control from the saved variables, plus the live text
    function f:Refresh()
        for _, c in pairs(Cfg.controls) do
            if c.paint then c.paint() end
        end
        local d = Cfg.dyn
        if d.prio then d.prio:SetText(PriorityText()) end
        if d.macro then
            local u = (G.btn and G.btn.currentUnit) or "party1"
            d.macro:SetText(BuildMacro(u))
        end
        if d.heals then
            local names = {}
            for _, h in ipairs(healRanks) do
                names[#names + 1] = ("%s ~%d"):format(BareName(h.cast), h.heal or 0)
            end
            local line = (#names > 0) and table.concat(names, ",  ") or "none found"
            if groupHeal then line = line .. "\ngroup heal: " .. BareName(groupHeal) end
            line = line .. ("\nhealing power %d, talents x%.2f")
                   :format(HealingPower(), TalentMultiplier())
            d.heals:SetText(line)
        end
        if d.board then
            local ctext = ChampionText(3)
            d.board:SetText(ctext or "nobody yet")
        end
        if d.rezzers then
            local list = G.RezzerList()
            local lines = {}
            for _, r in ipairs(list) do
                local state
                if r.casting then state = "casting"
                elseif r.cd > 0 then state = "back in " .. G.TimeStr(r.cd)
                else state = "ready" end
                lines[#lines + 1] = ("%s (%s) -- %s"):format(r.name, tostring(r.class), state)
            end
            if #lines == 0 then
                lines[1] = "nobody else is running BiS Rez"
                lines[2] = "they have to have it for you to see their cooldown"
            end
            local mine = G.MyRezCooldown()
            lines[#lines + 1] = ("your rez: %s"):format(mine > 0 and ("back in " .. G.TimeStr(mine)) or "ready")
            local wn = G.WipeProtection()
            lines[#lines + 1] = (wn > 0) and ("wipe protection up: " .. wn)
                                          or "no wipe protection up"
            d.rezzers:SetText(table.concat(lines, "\n", 1, math.min(#lines, 4)))
        end
        if d.bind then
            local k = DB().bindKey
            if k then d.bind:SetText("Bound to " .. k .. "   (/bisrez unbind to clear)")
            else d.bind:SetText("No key bound   (/bisrez bind ALT-R)") end
        end
        if Cfg.logo and spellIcon then Cfg.logo:SetTexture(spellIcon) end
    end

    return f
end

function G.OpenConfig()
    local ok, err = pcall(G.BuildConfig)
    if not ok then
        print("|cff66ccffBiS Rez|r: " .. T.text("warn", "options window failed -- " .. tostring(err)))
        return
    end
    Cfg.frame:Refresh()
    Cfg.frame:Show()
    G.ShowConfigTab(Cfg.tab or "Rez")
end

function G.ToggleConfig()
    local ok, err = pcall(G.BuildConfig)
    if not ok then
        print("|cff66ccffBiS Rez|r: " .. T.text("warn", "options window failed -- " .. tostring(err)))
        return
    end
    if Cfg.frame:IsShown() then Cfg.frame:Hide() else G.OpenConfig() end
end

-- drive one control by id -- this is what the headless harness uses, and it is
-- the same path a mouse click takes, so a passing round-trip test means the
-- real widget writes the real saved variable.
function G.ConfigSet(id, v)
    G.BuildConfig()
    local c = Cfg.controls[id]
    if c and c.set then c.set(v) elseif c and c.click then c.click() end
end

function G.ConfigGet(id)
    G.BuildConfig()
    local c = Cfg.controls[id]
    return c and c.get and c.get()
end

function G.ConfigIds()
    G.BuildConfig()
    local ids = {}
    for id in pairs(Cfg.controls) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end


--------------------------------------------------------------------------------
-- The corpse window
--
--     +--------------------------------+
--     | [icon] BiS Rez        cfg   x  |   16px header, half opaque
--     |  [face][face][face][face]      |   every corpse in reach, 20px
--     |  [face]                        |   claimed ones grey, yours pulses
--     |  ------------------------------|
--     |  [r][r][r]   rezzers, cd tags  |   who else can rez, and is it up
--     +--------------------------------+
--
-- Lifted wholesale from BiS Innervate's Window, including the rules that are
-- the only reason that addon survives a raid:
--
--   * faces are SecureActionButtons bound OUT OF COMBAT, to the player's NAME.
--     Raid slots renumber the moment anybody leaves and cannot be rewritten
--     mid-fight; a face bound to "raid7" would rez whoever inherited the slot.
--   * if neither the plain name nor Name-Realm resolves, the face stays
--     UNBOUND. A face that does nothing is safe; one that casts at the wrong
--     person is not.
--   * during a fight only colour, alpha and text change. The window holds
--     secure children, so it is never shown, hidden, moved or scaled in
--     combat -- closing it is alpha, and everything else waits for the pull
--     to end.
--   * closed means DEAF. A window at alpha 0 left its header as an invisible
--     drag strip with live buttons, and its faces as invisible tooltip
--     catchers. EnableMouse goes off on everything when it closes.
--   * class icons, not 3D portraits: PlayerModel ignores parent alpha, which
--     is exactly the bug that made Innervate's faces show through a closed
--     window.
--------------------------------------------------------------------------------

local W = { squares = {}, rez = {}, byName = {} }
G.Window = W

W.SIZE, W.GAP, W.PER_ROW, W.MAX = 20, 3, 7, 40
W.RSIZE, W.RMAX = 16, 10
W.PAD, W.HEADER = 5, 16
W.BTN, W.CHAMP_H = 64, 13
W.BODY_A, W.HEAD_A = 0.01, 0.5
-- wide enough for the action row (button + the name beside it); the corpse grid
-- is sized to match rather than the other way round
W.WIDTH = math.max(W.PAD * 2 + W.PER_ROW * (W.SIZE + W.GAP) - W.GAP,
                   W.PAD * 2 + W.BTN + 8 + 92)

local CLASS_RING = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function wcol(name, a)
    if SH[name] then return shade(name, a) end
    return T.rgba(name, a)
end

local function wfill(parent, layer, name, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(wcol(name, a))
    return t
end

local function wborder(frame, name, a)
    local b = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(wcol(name, a))
        b[side] = t
    end
    b.top:SetPoint("TOPLEFT")       b.top:SetPoint("TOPRIGHT")       b.top:SetHeight(1)
    b.bottom:SetPoint("BOTTOMLEFT") b.bottom:SetPoint("BOTTOMRIGHT") b.bottom:SetHeight(1)
    b.left:SetPoint("TOPLEFT")      b.left:SetPoint("BOTTOMLEFT")    b.left:SetWidth(1)
    b.right:SetPoint("TOPRIGHT")    b.right:SetPoint("BOTTOMRIGHT")  b.right:SetWidth(1)
    -- explicit four-argument calls in every branch; `on and A or B` truncates
    function b:set(n, alpha)
        local r, g, bl, al = wcol(n, alpha)
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            self[side]:SetColorTexture(r, g, bl, al)
        end
    end
    return b
end

local function wtext(parent, str, size, name, justify)
    local f = parent:CreateFontString(nil, "OVERLAY")
    pcall(f.SetFont, f, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 11)
    if not f:GetFont() then f:SetFontObject("GameFontHighlightSmall") end
    local r, g, b = wcol(name or "ink")
    f:SetTextColor(r, g, b, 1)
    f:SetText(str or "")
    f:SetJustifyH(justify or "LEFT")
    return f
end

-- Click registration must match the client's cvar or a secure cast never
-- fires. Innervate reads it rather than hardcoding a side.
local function ApplyClicks(b)
    local down
    if GetCVarBool then down = GetCVarBool("ActionButtonUseKeyDown") end
    if down == nil and GetCVar then down = (GetCVar("ActionButtonUseKeyDown") == "1") end
    if down == nil then down = true end
    if down then b:RegisterForClicks("AnyDown") else b:RegisterForClicks("AnyUp") end
end
G.ApplyClicks = ApplyClicks

local function ClassIcon(tex, class)
    local c = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]
    if c then
        tex:SetTexture(CLASS_RING)
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        tex:SetTexture(spellIcon or "Interface\\Icons\\Spell_Holy_Resurrection")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- a name we can safely hand a secure unit attribute, or nil
local function NameToken(name, unit)
    if not name or name == "" then return nil end
    if UnitExists(name) then return name end
    if unit and GetUnitName then
        local full = GetUnitName(unit, true)
        if full and UnitExists(full) then return full end
    end
    return nil
end
G.NameToken = NameToken

-- ONE hidden flag for the whole thing. 2.9 had db.hidden for the button and
-- db.windowHidden for the window, which is two switches for one piece of
-- furniture; anything set on the old keys is folded in at load.
function W:IsHidden()
    return DB().hidden and true or false
end

--------------------------------------------------------------------------------
-- one corpse face
--------------------------------------------------------------------------------

function W:Square(i)
    local b = CreateFrame("Button", "BiSRezFace" .. i, self.grid, "SecureActionButtonTemplate")
    b:SetSize(self.SIZE, self.SIZE)
    b:SetAttribute("unit", "none")
    ApplyClicks(b)

    b.back = wfill(b, "BACKGROUND", "field", 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2) b.icon:SetPoint("BOTTOMRIGHT", -2, 2)

    local ov = CreateFrame("Frame", nil, b)
    ov:SetAllPoints()
    pcall(ov.SetFrameLevel, ov, ((b.GetFrameLevel and b:GetFrameLevel()) or 0) + 4)
    b.ov = ov
    b.lock = ov:CreateTexture(nil, "ARTWORK")
    b.lock:SetAllPoints()
    b.lock:SetColorTexture(wcol("frame", 0.72))
    b.lock:Hide()
    b.tag = wtext(ov, "", 9, "ink2", "RIGHT")
    b.tag:SetPoint("BOTTOMRIGHT", -1, 1)
    b.edge = wborder(ov, "hair", 1)

    b:HookScript("OnEnter", function(s) W:FaceTooltip(s) end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- insecure twin so hovering still works when the face itself takes no mouse
    local hover = CreateFrame("Frame", nil, ov)
    hover:SetAllPoints()
    hover:EnableMouse(false)
    hover:SetScript("OnEnter", function() W:FaceTooltip(b) end)
    hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b.hover = hover

    b:SetAlpha(0)
    b:Show()
    return b
end

function W:FaceTooltip(b)
    if not GameTooltip or not b.pname then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local col = RAID_CLASS_COLORS and b.pclass and RAID_CLASS_COLORS[b.pclass]
    if col then GameTooltip:AddLine(b.pname, col.r, col.g, col.b)
    else GameTooltip:AddLine(b.pname) end
    if b.pwhy and b.pwhy ~= "ok" then
        GameTooltip:AddLine(b.pwhy, 0.9, 0.5, 0.6, true)
    elseif b.unbound then
        GameTooltip:AddLine("this client cannot target them by name -- rez by hand", 0.9, 0.5, 0.6, true)
    else
        GameTooltip:AddLine("Click to rez them.", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- a rezzer chip -- never secure, you do not click another rezzer
--------------------------------------------------------------------------------

function W:Chip(i)
    local c = CreateFrame("Frame", nil, self.strip)
    c:SetSize(self.RSIZE, self.RSIZE)
    c.back = wfill(c, "BACKGROUND", "field", 1)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 1, -1) c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    c.tag = wtext(c, "", 8, "muted", "RIGHT")
    c.tag:SetPoint("BOTTOMRIGHT", 0, 0)
    c.edge = wborder(c, "hair", 1)
    c:EnableMouse(false)
    c:SetScript("OnEnter", function(s)
        if not GameTooltip or not s.pname then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        local col = RAID_CLASS_COLORS and s.pclass and RAID_CLASS_COLORS[s.pclass]
        if col then GameTooltip:AddLine(s.pname, col.r, col.g, col.b)
        else GameTooltip:AddLine(s.pname) end
        if s.pcast then
            GameTooltip:AddLine("casting a rez now", 1, 0.82, 0)
        elseif (s.pcd or 0) > 0 then
            GameTooltip:AddLine(("rez back in %s"):format(G.TimeStr(s.pcd)), 0.9, 0.5, 0.6)
        else
            GameTooltip:AddLine("rez is up", 0.3, 1, 0.3)
        end
        GameTooltip:AddLine("running BiS Rez", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    c:Hide()
    return c
end

function G.TimeStr(s)
    s = math.floor(s or 0)
    if s <= 0 then return "now" end
    if s < 60 then return s .. "s" end
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

--------------------------------------------------------------------------------
-- build
--------------------------------------------------------------------------------

function W:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "BiSRezWindow", UIParent)
    f:SetSize(self.WIDTH, self.HEADER + self.PAD * 2 + self.BTN)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true) f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not DB().locked and not InCombatLockdown() then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint()
        DB().windowPos = { p, rp, x, y }
    end)
    self.frame = f

    self.body = wfill(f, "BACKGROUND", "frame", self.BODY_A)

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT") head:SetPoint("TOPRIGHT") head:SetHeight(self.HEADER)
    head:EnableMouse(true)
    head:SetScript("OnMouseDown", function() if not DB().locked and not InCombatLockdown() then f:StartMoving() end end)
    head:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        DB().windowPos = { p, rp, x, y }
    end)
    self.head = head
    self.headBG = wfill(head, "BACKGROUND", "header", self.HEAD_A)
    head:SetScript("OnEnter", function(hs)
        if not GameTooltip then return end
        GameTooltip:SetOwner(hs, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("BiS |cffb980ffRez|r")
        local list = G.RezzerList()
        GameTooltip:AddLine(("%d rezzer(s) with the addon, %d ready"):format(#list, G.RezzersReady()), 1, 1, 1)
        local n, detail = G.WipeProtection()
        if n > 0 then
            GameTooltip:AddLine(("Wipe protection: %d"):format(n), 0.31, 0.82, 0.81)
            for i = 1, math.min(#detail, 6) do
                GameTooltip:AddLine("  " .. detail[i].name .. " -- " .. detail[i].what, 0.7, 0.7, 0.7)
            end
            if #detail > 6 then
                GameTooltip:AddLine("  ...and " .. (#detail - 6) .. " more", 0.6, 0.6, 0.6)
            end
        else
            GameTooltip:AddLine("No wipe protection up -- a wipe is a corpse run", 0.94, 0.55, 0.69)
        end
        GameTooltip:AddLine("Drag to move. Right-click the minimap coin for options.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local logo = head:CreateTexture(nil, "ARTWORK")
    logo:SetSize(12, 12) logo:SetPoint("LEFT", 3, 0)
    logo:SetTexture(spellIcon or "Interface\\Icons\\Spell_Holy_Resurrection")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.logo = logo

    self.title = wtext(head, "BiS Rez", 10, "accent")
    self.title:SetPoint("LEFT", logo, "RIGHT", 4, 0)

    local x = CreateFrame("Button", nil, head)
    x:SetSize(14, 14) x:SetPoint("RIGHT", -2, 0)
    local xt = wtext(x, "x", 11, "muted") xt:SetPoint("CENTER")
    x:SetScript("OnEnter", function() xt:SetTextColor(T.rgb("ink")) end)
    x:SetScript("OnLeave", function() xt:SetTextColor(T.rgb("muted")) end)
    x:SetScript("OnClick", function() W:SetShown(false) end)
    self.closeBtn = x

    local cfg = CreateFrame("Button", nil, head)
    cfg:SetSize(20, 14) cfg:SetPoint("RIGHT", x, "LEFT", -2, 0)
    local ct = wtext(cfg, "cfg", 9, "muted") ct:SetPoint("CENTER")
    cfg:SetScript("OnEnter", function() ct:SetTextColor(T.rgb("ink")) end)
    cfg:SetScript("OnLeave", function() ct:SetTextColor(T.rgb("muted")) end)
    cfg:SetScript("OnClick", function() G.ToggleConfig() end)
    self.cfgBtn = cfg

    -- ADOPT THE BUTTON. It becomes a child of the window and sits in the body,
    -- with the target name beside it and the champion tally under it, so the
    -- whole addon is one piece of furniture you drag by any part of it.
    btn:SetParent(f)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", self.PAD, -(self.HEADER + self.PAD))
    if btn.label then
        btn.label:ClearAllPoints()
        btn.label:SetPoint("TOPLEFT", btn, "TOPRIGHT", 8, -3)
        btn.label:SetWidth(self.WIDTH - self.PAD * 2 - self.BTN - 8)
        btn.label:SetJustifyH("LEFT")
    end
    if btn.champ then
        btn.champ:ClearAllPoints()
        btn.champ:SetPoint("TOPLEFT", btn, "TOPRIGHT", 8, -19)
        btn.champ:SetWidth(self.WIDTH - self.PAD * 2 - self.BTN - 8)
        btn.champ:SetJustifyH("LEFT")
    end

    self.grid = CreateFrame("Frame", nil, f)
    self.grid:SetPoint("TOPLEFT", self.PAD, -(self.HEADER + self.PAD + self.BTN + 4))
    self.grid:SetSize(1, 1)
    for i = 1, self.MAX do self.squares[i] = self:Square(i) end

    self.hair = f:CreateTexture(nil, "ARTWORK")
    self.hair:SetColorTexture(wcol("hair", 1))
    self.hair:SetHeight(1)
    self.hair:Hide()

    self.strip = CreateFrame("Frame", nil, f)
    self.strip:SetSize(1, 1)
    for i = 1, self.RMAX do self.rez[i] = self:Chip(i) end

    local db = DB()
    if db.windowPos then
        local p, rp, px, py = unpack(db.windowPos)
        f:ClearAllPoints()
        f:SetPoint(p, UIParent, rp, px, py)
    end
    self:ApplyShown()
    return f
end

--------------------------------------------------------------------------------
-- bind -- the ONE place anything protected is written, out of combat only
--------------------------------------------------------------------------------

function W:Bind()
    if not self.frame or InCombatLockdown() then return end
    if G.RosterBlip() then return end     -- a zone-in, not everyone leaving

    local corpses = {}
    for _, unit in ipairs(CandidateUnits()) do
        local ok, why = IsRezzable(unit)
        local isDead = UnitExists(unit) and UnitIsPlayer(unit)
                       and (UnitIsDead(unit) or UnitIsGhost(unit))
                       and not UnitIsUnit(unit, "player")
        if isDead then
            local _, class = UnitClass(unit)
            corpses[#corpses + 1] = {
                unit = unit, name = UnitName(unit), class = class,
                ok = ok, why = why, prio = G.RezScore(unit, class),
                ghost = (UnitIsGhost and UnitIsGhost(unit) and not UnitIsDead(unit)) or false,
            }
        end
    end
    table.sort(corpses, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        return (a.name or "") < (b.name or "")
    end)
    -- (prio is G.RezScore, so released players already sit at the back)

    local spell = DB().useRank and castName or baseName
    self.byName = {}
    local shown = not self:IsHidden()

    for i = 1, self.MAX do
        local e, b = corpses[i], self.squares[i]
        if e then
            local token = NameToken(e.name, e.unit)
            b.unbound = (not token) or nil
            if token then
                b:SetAttribute("*type1", "spell")
                b:SetAttribute("*spell1", spell)
                b:SetAttribute("unit", token)
            else
                b:SetAttribute("*type1", nil)
                b:SetAttribute("*spell1", nil)
                b:SetAttribute("unit", "none")
            end
            b.pname, b.pclass, b.punit, b.pwhy = e.name, e.class, e.unit, e.why
            self.byName[e.name or ""] = b
            local row = math.floor((i - 1) / self.PER_ROW)
            local col = (i - 1) % self.PER_ROW
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.grid, "TOPLEFT",
                       col * (self.SIZE + self.GAP), -(row * (self.SIZE + self.GAP)))
            ClassIcon(b.icon, e.class)
            local live = shown and not b.unbound
            pcall(b.EnableMouse, b, live and true or false)
            b.hover:EnableMouse((not live) and shown and true or false)
        else
            b:SetAttribute("*type1", nil)
            b:SetAttribute("*spell1", nil)
            b:SetAttribute("unit", "none")
            b.unbound = nil
            b.pname, b.pclass, b.punit, b.pwhy = nil, nil, nil, nil
            pcall(b.EnableMouse, b, false)
            b.hover:EnableMouse(false)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.grid, "TOPLEFT", -5000, 0)
        end
    end

    self.nCorpses = #corpses
    self:Layout()
    self:Refresh()
end

function W:Layout()
    if not self.frame then return end
    if InCombatLockdown() then return end   -- resizing a secure parent is protected
    local n = self.nCorpses or 0
    local rows = math.max(1, math.ceil(math.min(n, self.MAX) / self.PER_ROW))
    local list = G.RezzerList()
    local nrez = math.min(#list, self.RMAX)

    local w = self.WIDTH
    -- header, then the action row (button + name + champion), always present
    local h = self.HEADER + self.PAD + self.BTN + 4

    -- the corpse grid only takes room when there are corpses
    if n > 0 then
        self.grid:ClearAllPoints()
        self.grid:SetPoint("TOPLEFT", self.PAD, -h)
        h = h + rows * (self.SIZE + self.GAP) - self.GAP + 4
    end

    if nrez > 0 then
        self.hair:ClearAllPoints()
        self.hair:SetPoint("TOPLEFT", self.PAD, -h)
        self.hair:SetPoint("TOPRIGHT", -self.PAD, -h)
        self.hair:Show()
        self.strip:ClearAllPoints()
        self.strip:SetPoint("TOPLEFT", self.PAD, -(h + 3))
        h = h + self.RSIZE + 3
    else
        self.hair:Hide()
    end
    self.frame:SetSize(w, h + self.PAD)
end

--------------------------------------------------------------------------------
-- paint -- safe in combat, textures and text only
--------------------------------------------------------------------------------

function W:Refresh()
    if not self.frame then return end
    local shown = not self:IsHidden()
    local me = UnitName("player")

    for i = 1, self.MAX do
        local b = self.squares[i]
        if b.pname then
            b:SetAlpha(shown and 1 or 0)
            local who, src = nil, nil
            if b.punit then who, src = ClaimedBy(b.punit) end
            local mine = (btn and btn.currentName == b.pname)
            if who then
                b.lock:Show()
                b.tag:SetText("*")
                b.tag:SetTextColor(T.rgb("muted"))
                b.edge:set("hair", 1)
            elseif b.unbound then
                b.lock:Show()
                b.tag:SetText("?")
                b.tag:SetTextColor(T.rgb("warn"))
                b.edge:set("warn", 0.8)
            elseif not b.pwhy or b.pwhy == "ok" then
                b.lock:Hide()
                b.tag:SetText(mine and "!" or "")
                b.tag:SetTextColor(T.rgb("good"))
                if mine then b.edge:set("accent", 1) else b.edge:set("hair", 1) end
            else
                b.lock:Show()
                b.tag:SetText("")
                b.edge:set("hair", 1)
            end
        else
            b:SetAlpha(0)
        end
    end

    local list = G.RezzerList()
    local x = 0
    for i = 1, self.RMAX do
        local c, r = self.rez[i], list[i]
        if r and shown then
            c.pname, c.pclass, c.pcd, c.pcast = r.name, r.class, r.cd, r.casting
            ClassIcon(c.icon, r.class)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", self.strip, "TOPLEFT", x, 0)
            x = x + self.RSIZE + 2
            if r.casting then
                c.tag:SetText("~") c.tag:SetTextColor(T.rgb("gold"))
                c.edge:set("gold", 0.8)
                c.icon:SetDesaturated(false)
            elseif r.cd > 0 then
                c.tag:SetText(G.TimeStr(r.cd)) c.tag:SetTextColor(T.rgb("muted"))
                c.edge:set("hair", 1)
                c.icon:SetDesaturated(true)
            else
                c.tag:SetText("")
                c.edge:set("good", 0.6)
                c.icon:SetDesaturated(false)
            end
            c:EnableMouse(true)
            c:Show()
        else
            c.pname = nil
            c:EnableMouse(false)
            c:Hide()
        end
    end

    -- the strip appears the moment a peer answers, which is not a corpse change
    local nrezNow = math.min(#list, self.RMAX)
    if nrezNow ~= self.lastNRez and not InCombatLockdown() then
        self.lastNRez = nrezNow
        self:Layout()
    end

    if self.title then
        local ready = G.RezzersReady()
        local wipes = G.WipeProtection()
        local txt = ("BiS Rez  %d/%d"):format(ready, math.max(#list, ready))
        -- the wipe-protection count only appears when there IS some; a
        -- permanent "0" is noise, and its absence is the thing worth noticing
        if wipes > 0 then txt = txt .. "  |cff4fd0cf+" .. wipes .. "|r" end
        self.title:SetText(txt)
    end
    self:ApplyShown()
end

-- closed means DEAF: alpha alone leaves an invisible drag strip and invisible
-- tooltip catchers over the screen
function W:ApplyShown()
    if not self.frame then return end
    local shown = not self:IsHidden()
    self.frame:SetAlpha(shown and 1 or 0)
    if self.head then self.head:EnableMouse(shown) end
    if self.closeBtn then self.closeBtn:EnableMouse(shown) end
    if self.cfgBtn then self.cfgBtn:EnableMouse(shown) end
    if not shown then
        for i = 1, self.MAX do
            local b = self.squares[i]
            pcall(b.EnableMouse, b, false)
            b.hover:EnableMouse(false)
        end
        for i = 1, self.RMAX do self.rez[i]:EnableMouse(false) end
    end
end

function W:SetShown(on)
    DB().hidden = not on
    if not self.frame then if on then self:Build() end return end
    self:ApplyShown()
    if not InCombatLockdown() then self:Bind() end
end

function W:Toggle()
    self:Build()
    self:SetShown(self:IsHidden())
end


--------------------------------------------------------------------------------
-- Hiding in combat
--
-- The reason combat ever mattered here is small and practical: this is an
-- out-of-combat addon, and a stray click on it mid-fight just throws a red
-- error. The answer is not to engineer around the lockdown -- it is to not be
-- there. A hidden frame cannot be misclicked.
--
-- Hide() on a secure frame IS protected in combat, so we cannot simply do it
-- when the pull starts. RegisterStateDriver is the sanctioned way: the secure
-- environment evaluates "[combat] hide; show" itself, so the frame disappears
-- for the fight without this addon touching anything protected. The keybind
-- still fires, which is deliberate -- a deliberate keypress is not a misclick.
--------------------------------------------------------------------------------

function G.ApplyVisibility()
    -- registering a driver is itself protected; the pull's end re-runs this
    if InCombatLockdown() then return end
    local db = DB()
    local hasDriver = (type(RegisterStateDriver) == "function")
                      and (type(UnregisterStateDriver) == "function")

    local function drive(frame, hidden)
        if not frame then return end
        if hasDriver then UnregisterStateDriver(frame, "visibility") end
        if hidden then
            frame:Hide()
        elseif db.hideInCombat ~= false and hasDriver then
            RegisterStateDriver(frame, "visibility", "[combat] hide; show")
        else
            frame:Show()
        end
    end

    local W = G.Window
    if W and W.frame then
        -- one frame, one driver. The button is a child, so it follows its
        -- parent; driving it separately would just fight this.
        drive(W.frame, db.hidden)
        btn:Show()
        W:ApplyShown()
    else
        drive(btn, db.hidden)
    end
end

--------------------------------------------------------------------------------
-- One sound
--
-- Exactly one, for the only moment where a noise changes what somebody does:
-- a rez is being cast ON YOU while you are lying there deciding whether to
-- release. Releasing is the single biggest time sink in a recovery, and this
-- is the half-second where telling you not to actually helps.
--
-- Everything else this addon does is already visible on the button.
--------------------------------------------------------------------------------

G.CUE = { sound = 8959, last = 0 }   -- the raid-warning kit; short, unmistakable

function G.RezIncomingOnMe(who)
    if DB().sound == false then return end
    if not UnitIsDeadOrGhost("player") then return end
    if GetTime() - G.CUE.last < 10 then return end   -- once per corpse, not per message
    G.CUE.last = GetTime()
    if PlaySound then pcall(PlaySound, G.CUE.sound, "Master") end
    print("|cff66ccffBiS Rez|r: " .. T.text("good", (who or "somebody") .. " is rezzing you")
          .. T.text("gold", " -- don't release."))
end

--------------------------------------------------------------------------------
-- Minimap button
--
-- Lifted from BiS Innervate's Minimap. Insecure top to bottom: a plain button
-- on a Blizzard frame, and every action behind it is either legal in combat or
-- defers itself. It is how the window comes back after you close it.
--------------------------------------------------------------------------------

local Mini = {}
G.Minimap = Mini

Mini.RADIUS = 80

function Mini.angle()
    local a = tonumber(DB().minimapAngle)
    if not a or a ~= a then a = 205 end          -- a ~= a catches nan
    return math.rad(a)
end

function Mini:Place()
    local b = self.button
    if not b or not Minimap then return end
    local a = Mini.angle()
    pcall(b.ClearAllPoints, b)
    pcall(b.SetPoint, b, "CENTER", Minimap, "CENTER",
          Mini.RADIUS * math.cos(a), Mini.RADIUS * math.sin(a))
end

function Mini.drag()
    if not Minimap or not GetCursorPosition then return end
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    if not scale or scale <= 0 then return end   -- 0 would write nan into the db
    local cx, cy = GetCursorPosition()
    if not cx then return end
    cx, cy = cx / scale, cy / scale
    DB().minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
    Mini:Place()
end

function Mini:Tooltip(b)
    if not GameTooltip then return end
    GameTooltip:SetOwner(b, "ANCHOR_LEFT")
    GameTooltip:AddLine("BiS |cffb980ffRez|r")
    local list = G.RezzerList()
    GameTooltip:AddLine(("%d rezzer(s) up, %d ready"):format(#list, G.RezzersReady()), 1, 1, 1)
    GameTooltip:AddLine("Left: show / hide the corpse window", 1, 1, 1)
    GameTooltip:AddLine("Right: options", 1, 1, 1)
    GameTooltip:AddLine("Shift-left: who can rez, in chat", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag to move me around the ring.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function Mini:OnClick(button)
    local shift = IsShiftKeyDown and IsShiftKeyDown()
    if button == "LeftButton" then
        if shift then
            SlashCmdList["BISREZ"]("rezzers")
        elseif InCombatLockdown() then
            print("|cff66ccffBiS Rez|r: " .. T.text("warn", "the window can't be toggled in combat."))
        else
            G.Window:Toggle()
        end
    elseif button == "RightButton" then
        G.ToggleConfig()
    end
end

function Mini:Build()
    if self.button then return self.button end
    if not Minimap then return nil end
    if DB().minimap == false then return nil end

    local b = CreateFrame("Button", "BiSRezMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    pcall(b.SetFrameLevel, b, 8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(spellIcon or "Interface\\Icons\\Spell_Holy_Resurrection")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    pcall(icon.SetTexCoord, icon, 0.07, 0.93, 0.07, 0.93)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(_, button) Mini:OnClick(button) end)
    b:SetScript("OnEnter", function(s) Mini:Tooltip(s) end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnDragStart", function(s) s:SetScript("OnUpdate", Mini.drag) end)
    b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)

    self.button = b
    self:Place()
    b:Show()
    return b
end

-- the options window sets a value; it must not route through a toggle whose
-- first branch builds a missing button and returns
function Mini:Set(on)
    DB().minimap = on and true or false
    if on then
        if self.button then self.button:Show() else self:Build() end
    elseif self.button then
        self.button:Hide()
    end
end

function Mini:Toggle()
    if not self.button and DB().minimap ~= false then
        self:Build()
        return
    end
    Mini:Set(DB().minimap == false)
end


SLASH_BISREZ1 = "/bisrez"
SLASH_BISREZ2 = "/bis"
SlashCmdList["BISREZ"] = function(msg)
    msg = (msg or ""):lower()
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    local db = DB()

    if cmd == "lock" then
        db.locked = true
        print("|cff66ccffBiS Rez|r: locked.")
    elseif cmd == "unlock" then
        db.locked = false
        print("|cff66ccffBiS Rez|r: unlocked -- drag to move.")
    elseif cmd == "show" then
        db.hidden = false; G.ApplyVisibility()
    elseif cmd == "hide" then
        db.hidden = true; G.ApplyVisibility()
    elseif cmd == "hidecombat" then
        db.hideInCombat = (db.hideInCombat == false)
        G.ApplyVisibility()
        print("|cff66ccffBiS Rez|r: hide in combat "
              .. ((db.hideInCombat ~= false) and "ON" or "OFF"))
    elseif cmd == "minimap" then
        G.Minimap:Toggle()
        print("|cff66ccffBiS Rez|r: minimap button "
              .. ((DB().minimap == false) and "hidden" or "shown"))
    elseif cmd == "bind" then
        if InCombatLockdown() then
            print("|cff66ccffBiS Rez|r: " .. T.text("warn", "can't bind in combat."))
            return
        end
        if arg == "" then
            print("|cff66ccffBiS Rez|r: usage -- /bisrez bind SHIFT-R")
            return
        end
        local key, force = arg:match("^(%S+)%s*(.-)$")
        key = key:upper()

        local existing = GetBindingAction(key)
        if existing and existing ~= "" and existing ~= "CLICK BiSRezButton:LeftButton"
           and force:lower() ~= "force" then
            print("|cff66ccffBiS Rez|r: " .. key .. " already does " .. T.text("gold", existing) ..
                  ". Use: /bisrez bind " .. key .. " force")
            return
        end

        -- SetOverrideBindingClick, not SetBindingClick + SaveBindings. The old
        -- pair WROTE INTO HIS SAVED KEYBINDS -- a permanent edit to a file this
        -- addon has no business owning, and uninstalling BiSRez would leave the
        -- key bound to a button that no longer exists. Override bindings sit on
        -- top, touch nothing, and evaporate on /reload -- so the key is stored
        -- and re-applied at login (see ApplyBind).
        DB().bindKey = key
        if ApplyBind(key) then
            print("|cff66ccffBiS Rez|r: bound to " .. key
                  .. T.text("muted", "  (override binding -- your saved keybinds are untouched)"))
        else
            print("|cff66ccffBiS Rez|r: " .. T.text("warn", "could not bind " .. key))
        end
    elseif cmd == "unbind" then
        DB().bindKey = nil
        if type(ClearOverrideBindings) == "function" then
            pcall(ClearOverrideBindings, btn)
        end
        print("|cff66ccffBiS Rez|r: binding cleared.")
    elseif cmd == "heals" then
        print(("|cff66ccffBiS Rez|r: %s -- %d heal(s) known, group heal: %s")
              :format(tostring(playerClass), #healRanks, groupHeal or "none"))
        for _, h in ipairs(healRanks) do
            print(("  %s  ~%d heal  %d mana%s"):format(h.cast, h.heal or 0,
                  SpellCost(h.id or h.cast) or 0,
                  (h.base and h.base > 0 and h.heal > h.base + 1)
                    and (" " .. T.text("muted", ("(tooltip says %d)"):format(h.base))) or ""))
        end
        print(("  healing power %d, talent multiplier %.2f")
              :format(HealingPower(), TalentMultiplier()))
        if healCommOn then
            print("  LibHealComm-4.0: " .. T.text("good", "loaded") .. " -- inbound heals from other")
            print("    healers are subtracted before a target is picked.")
        else
            print("  LibHealComm-4.0: " .. T.text("warn", "not loaded") .. " -- put it under")
            print("    BiSRez\\Libs and the heal picker stops fighting other healers.")
        end
        local bag, slot, id = FindDrink()
        if bag then
            local nm
            for _, c in ipairs(CONSUMABLES) do if c.id == id then nm = c.name end end
            print("  drink: " .. (nm or ("item " .. tostring(id))))
        else
            print("  drink: " .. T.text("warn", "none in bags"))
        end

    elseif cmd == "rescan" then
        G.BuildHealTable()
        print(("|cff66ccffBiS Rez|r: rescanned -- %d heal(s), group heal: %s")
              :format(#healRanks, groupHeal or "none"))

    elseif cmd == "list" then
        print("|cff66ccffBiS Rez|r: spell = " .. tostring(castName))
        local prefix, count = GroupInfo()
        print(string.format("  group: %s x%d", prefix, count))
        local units = CandidateUnits()
        if #units == 0 then
            print("  no units to check -- not grouped and no target")
        end
        for _, u in ipairs(units) do
            local ok, why = IsRezzable(u)
            local _, class = UnitClass(u)
            print(string.format("  %s: %s (%s) prio %s -- %s",
                u, tostring(UnitName(u)), tostring(class),
                string.format("%.1f", G.RezScore(u, class)),
                T.text(ok and "good" or "warn", why)))
        end
    elseif cmd == "mode" then
        db.mode = (db.mode == "spell") and "macro" or "spell"
        print("|cff66ccffBiS Rez|r: cast mode = " .. db.mode)
    elseif cmd == "clicks" then
        if InCombatLockdown() then print("|cff66ccffBiS Rez|r: " .. T.text("warn", "not in combat, please.")) return end
        db.clickMode = (db.clickMode == "down") and "up" or ((db.clickMode == "up") and "both" or "down")
        if db.clickMode == "down" then btn:RegisterForClicks("AnyDown")
        elseif db.clickMode == "up" then btn:RegisterForClicks("AnyUp")
        else btn:RegisterForClicks("AnyDown", "AnyUp") end
        print("|cff66ccffBiS Rez|r: click edge = " .. db.clickMode)
    elseif cmd == "rank" then
        db.useRank = not db.useRank
        print("|cff66ccffBiS Rez|r: rank suffix " .. (db.useRank and "ON" or "OFF"))
    elseif cmd == "at" then
        db.useAtShorthand = not db.useAtShorthand
        print("|cff66ccffBiS Rez|r: @ shorthand " .. (db.useAtShorthand and "ON" or "OFF"))
    elseif cmd == "macro" then
        local u = btn.currentUnit or "raid1"
        print("|cff66ccffBiS Rez|r: current body -->")
        print("  " .. BuildMacro(u))
        print("  Paste that into a real macro and click it. If the real macro also")
        print("  does nothing, the syntax is the problem, not the addon.")
    elseif cmd == "score" then
        local sc, list = Scores(), {}
        for n, c in pairs(sc) do list[#list + 1] = { n = n, c = c } end
        table.sort(list, function(a, b) return a.c > b.c end)
        print("|cff66ccffBiS Rez|r: rez scoreboard --")
        if #list == 0 then print("  nobody yet") end
        for i, e in ipairs(list) do
            print(string.format("  %d. %s -- %d", i, e.n, e.c))
        end
    elseif cmd == "verbose" then
        db.verbose = not db.verbose
        print("|cff66ccffBiS Rez|r: verbose cast detail " .. (db.verbose and "ON" or "OFF"))
    elseif cmd == "sync" then
        local _, gcount = GroupInfo()
        if gcount == 0 then
            print("|cff66ccffBiS Rez|r: " .. T.text("warn", "not in a group."))
        else
            Send("WANT")
            print("|cff66ccffBiS Rez|r: asked the group for the scoreboard.")
        end
    elseif cmd == "resetscore" then
        db.scores = {}
        btn:UpdateChamp()
        print("|cff66ccffBiS Rez|r: scoreboard cleared.")
    elseif cmd == "claims" then
        print("|cff66ccffBiS Rez|r: active claims --")
        local n = 0
        for guid, c in pairs(claims) do
            if GetTime() <= c.expires then
                n = n + 1
                print(string.format("  %s by %s (%s) %.0fs left",
                    guid, tostring(c.who), c.src, c.expires - GetTime()))
            end
        end
        if n == 0 then print("  none") end
    elseif cmd == "diag" then
        print("|cff66ccffBiS Rez|r diagnostics:")
        print(("  action now: %s | heals known: %d | group heal: %s | autoDrink %s | autoHeal %s")
              :format(tostring(btn.action), #healRanks, tostring(groupHeal),
                      tostring(DB().autoDrink ~= false), tostring(DB().autoHeal ~= false)))
        print("  LibHealComm-4.0: " .. (healCommOn and "loaded" or "NOT loaded"))
        if healCommOn then
            local biggest = healRanks[#healRanks]
            local probe = (biggest and biggest.cast) or groupHeal
            local lead = CastSeconds(probe)
            print(("  cast lead: %.2fs (%s) + %.2fs reaction")
                  :format(lead, tostring(BareName(probe)), HEAL_REACTION))
            local prefix, count = GroupInfo()
            for i = 1, count do
                local u = prefix .. i
                if UnitExists(u) and not UnitIsDeadOrGhost(u) then
                    local inc = OthersIncoming(u, lead)
                    if inc > 0 then
                        print(("    %s: %d inbound from others -> effective deficit %d")
                              :format(tostring(UnitName(u)), inc, EffectiveDeficit(u, lead)))
                    end
                end
            end
        end
        print("  class: " .. tostring(playerClass) .. "  spellID: " .. tostring(REZ_SPELL_ID[playerClass]))
        print("  baseName: " .. tostring(baseName) .. "  castName: " .. tostring(castName))
        print("  C_Spell.GetSpellInfo: " .. tostring(C_Spell and C_Spell.GetSpellInfo ~= nil))
        print("  GetSpellInfo: " .. tostring(GetSpellInfo ~= nil))
        print("  C_SpellBook.GetSpellBookItemName: " .. tostring(C_SpellBook and C_SpellBook.GetSpellBookItemName ~= nil))
        print("  GetSpellBookItemName: " .. tostring(GetSpellBookItemName ~= nil) .. "  GetSpellName: " .. tostring(GetSpellName ~= nil))
        print("  IsSpellInRange: " .. tostring(IsSpellInRange ~= nil) .. "  C_Spell.IsSpellInRange: " .. tostring(C_Spell and C_Spell.IsSpellInRange ~= nil))
        ResolveSpell(true)
        print("  after rescan -> castName: " .. tostring(castName))
        local evs = {}
        for _, e in ipairs({"GROUP_ROSTER_UPDATE","RAID_ROSTER_UPDATE","PARTY_MEMBERS_CHANGED"}) do
            evs[#evs + 1] = e .. "=" .. tostring(registeredEvents[e] == true)
        end
        print("  roster events: " .. table.concat(evs, "  "))
        print("  *type1: " .. tostring(btn:GetAttribute("*type1"))
              .. "  *macrotext1: " .. tostring(btn:GetAttribute("*macrotext1"))
              .. "  *spell1: " .. tostring(btn:GetAttribute("*spell1"))
              .. "  unit: " .. tostring(btn:GetAttribute("unit")))
    elseif cmd == "" then
        G.ToggleConfig()
    elseif cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "opt" then
        G.OpenConfig()
    elseif cmd == "window" or cmd == "win" then
        -- the button and the window are one frame since 3.0, so this and
        -- show/hide are the same switch
        if InCombatLockdown() then
            print("|cff66ccffBiS Rez|r: " .. T.text("warn", "it can't be toggled in combat."))
        else
            G.Window:Toggle()
            print("|cff66ccffBiS Rez|r: " .. (G.Window:IsHidden() and "hidden" or "shown"))
        end
    elseif cmd == "rezzers" or cmd == "peers" then
        local list = G.RezzerList()
        print(("|cff66ccffBiS Rez|r: %d rezzer(s) running the addon, %d ready --")
              :format(#list, G.RezzersReady()))
        if #list == 0 then print("  " .. T.text("muted", "nobody else -- they need BiS Rez for you to see them")) end
        for _, r in ipairs(list) do
            local state
            if r.casting then state = T.text("gold", "casting")
            elseif r.cd > 0 then state = T.text("warn", "back in " .. G.TimeStr(r.cd))
            else state = T.text("good", "ready") end
            print(("  %s (%s) -- %s"):format(r.name, tostring(r.class), state))
        end
        print(("  your own rez: %s"):format(
              (G.MyRezCooldown() > 0) and ("back in " .. G.TimeStr(G.MyRezCooldown())) or "ready"))
        local wn, wdetail = G.WipeProtection()
        if wn > 0 then
            print("|cff66ccffBiS Rez|r: " .. T.text("good", ("wipe protection: %d"):format(wn)))
            for _, d in ipairs(wdetail) do print(("  %s -- %s"):format(d.name, d.what)) end
        else
            print("|cff66ccffBiS Rez|r: " .. T.text("warn",
                  "no wipe protection up -- a wipe here is a corpse run"))
        end
    else
        print("|cff66ccffBiS Rez|r: /bisrez (no args opens the options window) | config | lock | unlock | show | hide")
        print("  | bind <KEY> | unbind | list | claims | rezzers | window | minimap | hidecombat | score | sync | resetscore | diag | macro | verbose | mode | clicks | rank | at")
        print("  | heals (what it can cast and drink) | rescan (rebuild the heal list)")
    end
end

--------------------------------------------------------------------------------
-- Bootstrap: don't rely on PLAYER_LOGIN alone (addon may load after it)
--------------------------------------------------------------------------------

if not okVisuals then
    print("|cff66ccffBiS Rez|r: " .. T.text("warn", "visual setup failed -- " .. tostring(visualErr)))
end

if ResolveSpell(true) and spellIcon and btn.icon then
    btn.icon:SetTexture(spellIcon)
end

print("|cff66ccffBiS Rez v" .. VERSION .. "|r file loaded. Class: " .. tostring(playerClass)
      .. " | Spell: " .. tostring(castName) .. " | /bisrez diag")
