-- BiS Innervate :: Roles.lua
-- Who is actually healing?
--
-- TBC has no role or spec API worth trusting, so a shadow priest, a ret paladin
-- and a resto shaman all look identical from the outside. Instead of guessing
-- from class alone, this watches the combat log and learns: heals cast on other
-- people say healer, damage with no healing says dps.
--
-- Two rules keep it safe:
--   * Nobody is ever unbound. A player with no evidence yet - the one who was
--     afk at the pull, or who just joined - keeps a live square. Evidence only
--     dims a square, it never removes the ability to innervate them.
--   * Evidence accumulates across the whole session (and persists between
--     sessions), so one quiet fight proves nothing either way.
--
-- The grid is only ever re-laid-out between fights, so nothing here can cause a
-- protected call mid-combat.

local ADDON, NS = ...

local Roles = {}
NS.Roles = Roles

local HEAL_EVENTS = {
    SPELL_HEAL = true,
    SPELL_PERIODIC_HEAL = true,
    SPELL_ABSORBED = true,      -- a disc priest's whole job logs as an absorb
}
local DAMAGE_EVENTS = {
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    RANGE_DAMAGE = true,
    SWING_DAMAGE = true,        -- without this, melee dps read as "unknown" forever
}

-- how sure we need to be before dimming somebody
local HEALER_MIN   = 5      -- heals on other people
local DPS_MIN      = 120    -- damage events (one trash pull must not be enough)
local DPS_RATIO    = 4      -- ...and this many times more damage than healing

function Roles:Data()
    NS.db.roles = NS.db.roles or {}
    return NS.db.roles
end

function Roles:Entry(name)
    local d = self:Data()
    local e = d[name]
    if not e then
        e = { h = 0, d = 0, t = 0 }
        d[name] = e
    end
    return e
end

--------------------------------------------------------------------
-- watching
--------------------------------------------------------------------

function Roles:OnCombatLog(subEvent, srcName, dstName)
    -- This runs on EVERY combat log line - thousands a second on a big pull -
    -- so the cheap test comes first. Looking the source up in the roster before
    -- checking the event type meant a full roster walk per line.
    local heal = HEAL_EVENTS[subEvent]
    if not heal and not DAMAGE_EVENTS[subEvent] then return end
    if not srcName then return end
    local src = NS.Short(srcName)
    if not src then return end
    -- self-heals prove little: a shadow priest heals themselves all fight
    if heal and src == NS.Short(dstName or "") then return end
    if not NS.UnitOf(src) then return end          -- only people in my group

    local e = self:Entry(src)
    if heal then
        e.h = (e.h or 0) + 1
    else
        e.d = (e.d or 0) + 1
    end
    e.t = (time and time()) or 0
    self.dirty = true
end

--------------------------------------------------------------------
-- reading
--------------------------------------------------------------------

-- "healer" | "dps" | "unknown"
function Roles:Guess(name)
    name = NS.Short(name or "")
    local manual = NS.db.roleOverride and NS.db.roleOverride[name]
    if manual then return manual end

    local e = (NS.db.roles or {})[name]
    if not e then return "unknown" end
    if (e.h or 0) >= HEALER_MIN then return "healer" end
    if (e.d or 0) >= DPS_MIN and (e.d or 0) > (e.h or 0) * DPS_RATIO then return "dps" end
    return "unknown"
end

-- should this player's square be prominent? A mage always. A healer-capable
-- class until it is clear they are not healing.
function Roles:IsLikely(name, class)
    if class == "MAGE" then return true end
    return self:Guess(name) ~= "dps"
end

function Roles:Set(name, role)
    name = NS.ResolveName(name)
    if not name then return end
    if not NS.UnitOf(name) then
        NS.Print("nobody called " .. tostring(name) .. " in the group.")
        return
    end
    NS.db.roleOverride = NS.db.roleOverride or {}
    if role == "clear" then
        NS.db.roleOverride[name] = nil
        NS.Print(name .. ": back to watching the combat log.")
    else
        NS.db.roleOverride[name] = role
        NS.Print(name .. " is now treated as " .. role .. ".")
    end
    if not NS.InCombat() then NS.Grid:Bind(); NS.Grid:Update() end
end

function Roles:Report()
    NS.Print("|cffffff00who the combat log says is healing|r")
    local any = false
    NS.ForEachMember(function(unit, name, class)
        if NS.IsRequesterClass(class) then
            any = true
            local e = (NS.db.roles or {})[name] or {}
            local guess = self:Guess(name)
            local colour = (guess == "healer") and "|cff40ff40"
                        or (guess == "dps") and "|cff888888" or "|cffffff00"
            NS.Print(string.format("  %s%s|r %s  (%d heals, %d damage)%s",
                colour, guess, NS.ClassColored(name, class), e.h or 0, e.d or 0,
                (NS.db.roleOverride and NS.db.roleOverride[name]) and " |cff40d0d0[set by hand]|r" or ""))
        end
    end)
    if not any then NS.Print("  nobody to judge yet.") end
    NS.Print("|cff888888unknown people keep a full square - afk at the pull is not evidence.|r")
end

-- called when a fight ends: only now may the grid be rebuilt
function Roles:AfterCombat()
    if not self.dirty then return end
    self.dirty = false
    NS.Grid:Bind()
    NS.Grid:Update()
end

-- housekeeping: forget people we have not seen in a fortnight
function Roles:Prune()
    local now = (time and time()) or 0
    if now == 0 then return end
    for name, e in pairs(self:Data()) do
        if e.t and e.t > 0 and (now - e.t) > (14 * 24 * 60 * 60) then
            self:Data()[name] = nil
        end
    end
end
