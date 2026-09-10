-- BiS Innervate :: Demo.lua
-- /inn demo: see the druid's side without a druid. Three pretend raiders sit in
-- the grid - two of them calling for innervate, one claimed by another druid -
-- and the faces are wired to a do-nothing macro, so a click prints a line and
-- casts nothing at anyone.
--
-- While the demo is on this client says nothing to the raid and takes no real
-- calls, so it is for standing around, not for the pull.

local ADDON, NS = ...
local T = NS.T

local Demo = {}
NS.Demo = Demo

Demo.FAKES = {
    { name = "Dps4", class = "MAGE",   mana = 14, call = true },
    { name = "Dps9",      class = "MAGE",   mana = 31, call = true, claimedBy = "Dps11" },
    { name = "Lightwell",    class = "PRIEST", mana = 22, call = true },
    { name = "Sparkle",      class = "MAGE",   mana = 88 },
    { name = "Healer7",    class = "PALADIN", mana = 64 },
}

function Demo:IsOn() return NS.demoMode and true or false end

function Demo:People()
    local out = {}
    for _, p in ipairs(self.FAKES) do
        out[#out + 1] = { unit = "player", name = p.name, class = p.class, demo = true }
    end
    return out
end

function Demo:ManaFor(name)
    for _, p in ipairs(self.FAKES) do if p.name == name then return p.mana end end
end

function Demo:Start()
    if self:IsOn() then return end
    if NS.InCombat() then
        NS.Print("come out of combat first - the demo has to wire up the faces.")
        return
    end
    NS.demoMode = true
    NS.demoKind = "INNERVATE"          -- pretend to be a druid
    NS.ForgetSpellCache()

    NS.Window:Build()
    NS.Window:Bind()
    NS.Window:SetClickable(true)

    for _, p in ipairs(self.FAKES) do
        if p.call then
            local id = "demo-" .. p.name
            NS.Calls.list[id] = {
                id = id, kind = "INNERVATE", target = p.name, owner = p.name, class = p.class,
                mana = p.mana, startMana = p.mana, created = NS.Now() - 5, state = "open",
                group = 1, demo = true, claimedBy = p.claimedBy,
                claimedAt = p.claimedBy and (NS.Now() + 3600) or nil,   -- never expires
            }
        end
    end
    NS.Window:Refresh()

    if NS.InGroup() then
        NS.Print(T.text("gold", "note:") .. " while the demo is on this client says nothing to the raid " ..
                 "and takes no real calls. Turn it off before the pull.")
    end
    NS.Print(T.text("good", "demo on") .. " - this is what a druid sees. Faces are harmless: " ..
             "clicking one prints a line instead of casting.")
    NS.Print("pulsing violet = calling, solid violet = yours, greyed = another druid took it. " ..
             T.text("gold", "/inn demo") .. " again to stop.")
end

function Demo:Stop()
    if not NS.demoMode then return end
    if NS.InCombat() then
        -- faces can only be rewired out of combat; stopping now would leave
        -- three that look normal and cast nothing for the rest of the fight
        NS.demoStopPending = true
        NS.Print("demo ends when this fight does.")
        return
    end
    NS.demoStopPending = nil
    NS.demoMode, NS.demoKind = nil, nil
    NS.ForgetSpellCache()
    for id, c in pairs(NS.Calls.list) do
        if c.demo then NS.Calls.list[id] = nil end
    end
    NS.Tracker:UpdateRoster()
    NS.Window:Bind()
    NS.Window:SetClickable(not NS.Window:IsHidden())
    NS.Window:Refresh()
    NS.Print("demo off.")
end

function Demo:Toggle()
    if self:IsOn() then self:Stop() else self:Start() end
end
