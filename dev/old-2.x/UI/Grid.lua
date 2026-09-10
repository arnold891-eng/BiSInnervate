-- BiS Innervate :: Grid.lua
-- The Decursive answer to combat lockdown.
--
-- One small square per mage / healer in the raid. Each square is a secure
-- button bound to that player ONCE, out of combat, and from then on nothing
-- protected is ever touched again: in combat we only change colour, alpha and
-- a mana bar, all of which are textures and legal at any time.
--
-- That means it does not matter whether this client allows insecure attribute
-- writes mid-fight. There are no attribute writes. The square that lights up is
-- the square you click, and it was already pointing at that player before the
-- pull.

local ADDON, NS = ...
local T = NS.T

local Grid = {}
NS.Grid = Grid

Grid.MAX      = 40
Grid.SIZE     = 42          -- big enough for a face
Grid.PAD      = 3
Grid.PER_ROW  = 5
Grid.squares  = {}
Grid.byName   = {}

--------------------------------------------------------------------
-- build (login only)
--------------------------------------------------------------------

function Grid:Build()
    if self.frame then return self.frame end
    if NS.InCombat() then return nil end
    if NS.MyKind() ~= "INNERVATE" then return nil end   -- druids only; tide is self-cast

    -- The container holds secure children, so it is protected: it is created
    -- and positioned once, shown once, and never hidden or moved in combat.
    -- Visibility in combat is alpha only.
    local f = CreateFrame("Frame", "BiSInnervateGrid", UIParent)
    f:SetSize(self.PER_ROW * (self.SIZE + self.PAD) + self.PAD, 60)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(s) if not NS.InCombat() then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        if NS.InCombat() then return end
        s:StopMovingOrSizing()
        local point, _, rel, x, y = s:GetPoint()
        NS.db.gridPos = { point = point, rel = rel, x = x, y = y }
    end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.rgba("bg", 0.85))

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    title:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 2)
    title:SetText("Innervate")
    f.title = title

    local pos = NS.db.gridPos
    if pos then
        f:SetPoint(pos.point or "CENTER", UIParent, pos.rel or "CENTER", pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 300, -120)
    end

    local spell = NS.SpellNameFor("INNERVATE")

    for i = 1, self.MAX do
        local b = CreateFrame("Button", "BiSInnervateSquare" .. i, f, "SecureActionButtonTemplate")
        b:SetSize(self.SIZE, self.SIZE)
        b:SetAttribute("*type1", "spell")
        b:SetAttribute("*spell1", spell)
        b:SetAttribute("*type2", "spell")
        b:SetAttribute("*spell2", spell)
        b:SetAttribute("unit", "none")
        NS.Secure:ApplyClicks(b)

        local back = b:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(T.rgba("bg", 0.9))
        b.back = back

        -- 2D portrait: works at any range and costs nothing
        local face = b:CreateTexture(nil, "ARTWORK")
        face:SetPoint("TOPLEFT", 2, -2)
        face:SetPoint("BOTTOMRIGHT", -2, 2)
        b.face = face

        -- animated 3D portrait on top of it, when the client will give us one
        local model = CreateFrame("PlayerModel", nil, b)
        model:SetPoint("TOPLEFT", 2, -2)
        model:SetPoint("BOTTOMRIGHT", -2, 2)
        local lvl = (b.GetFrameLevel and b:GetFrameLevel()) or 0
        pcall(model.SetFrameLevel, model, lvl + 1)
        model:Hide()
        b.model = model

        -- everything that has to stay readable over a face lives in its own
        -- frame above the model: a colour wash for state, and the mana bar
        local ov = CreateFrame("Frame", nil, b)
        ov:SetAllPoints()
        pcall(ov.SetFrameLevel, ov, lvl + 4)
        b.ov = ov

        local body = ov:CreateTexture(nil, "ARTWORK")
        body:SetPoint("TOPLEFT", 2, -2)
        body:SetPoint("BOTTOMRIGHT", -2, 2)
        body:SetColorTexture(0.4, 0.4, 0.4, 1)
        b.body = body

        -- mana fills from the bottom: a texture height, legal to change in combat
        local mana = ov:CreateTexture(nil, "OVERLAY")
        mana:SetPoint("BOTTOMLEFT", 2, 2)
        mana:SetPoint("BOTTOMRIGHT", -2, 2)
        mana:SetHeight(1)
        mana:SetColorTexture(T.rgba("slate", 0.85))
        b.mana = mana

        NS.Secure:AttachProcGlow(b)
        if b.procGlow then pcall(b.procGlow.SetFrameLevel, b.procGlow, lvl + 6) end

        b:SetScript("OnEnter", function(s)
            if not GameTooltip then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(s.pname or "empty")
            if s.pmana then GameTooltip:AddLine(s.pmana .. "% mana", 1, 1, 1) end
            GameTooltip:AddLine("Click to Innervate them.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        b:SetAlpha(0)
        b:Show()          -- shown once, out of combat, and left that way forever
        self.squares[i] = b
    end

    f:Show()
    self.frame = f
    table.insert(NS.UI.refreshHooks, function() Grid:Update() end)
    return f
end

--------------------------------------------------------------------
-- bind (out of combat only)
--------------------------------------------------------------------

-- Every mage / healer gets a square, in a stable order. Only ever called
-- outside combat: this is the one moment anything protected is written.
function Grid:Bind()
    if not self.frame or NS.InCombat() then return end
    if NS.MyKind() ~= "INNERVATE" and not NS.demoMode then return end
    -- during a zone-in the roster reads empty for a moment; binding then would
    -- blank the grid until the next roster event, which may not come
    if NS.InGroup() and (GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0) <= 1 then
        return
    end

    local list = {}
    NS.ForEachMember(function(unit, name, class)
        if NS.IsRequesterClass(class) and name ~= NS.PlayerName() then
            list[#list + 1] = { unit = unit, name = name, class = class, group = NS.Subgroup(name) or 9 }
        end
    end)
    -- confirmed healers and mages first, then unknowns, then anyone the combat
    -- log says is dps. Order only ever changes between fights.
    local function rank(e)
        local guess = NS.Roles and NS.Roles:Guess(e.name) or "unknown"
        if e.class == "MAGE" or guess == "healer" then return 1 end
        if guess == "dps" then return 3 end
        return 2
    end
    table.sort(list, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)

    self.byName = {}
    for i = 1, self.MAX do
        local e, b = list[i], self.squares[i]
        if not b then break end
        if e then
            -- Raid slots RENUMBER the moment anyone leaves the raid, and the
            -- binding can only be rewritten out of combat. Bind to the player's
            -- NAME instead: a name is a valid unit id for anyone in your group
            -- and it never moves. Checked at bind time so that if this client
            -- ever disagreed we fall back to the slot rather than bind nothing.
            local byName = UnitExists and UnitExists(e.name)
                           and NS.Short(UnitName(e.name) or "") == e.name
            b:SetAttribute("unit", byName and e.name or e.unit)
            b.boundByName = byName and true or false
            b.pname, b.pclass, b.punit = e.name, e.class, e.unit
            self.byName[e.name] = b
            local col = NS.CLASS_COLOR[e.class or ""] or "888888"
            b.classR = tonumber(string.sub(col, 1, 2), 16) / 255
            b.classG = tonumber(string.sub(col, 3, 4), 16) / 255
            b.classB = tonumber(string.sub(col, 5, 6), 16) / 255
            self:SetPortrait(b, e.unit)

            local row = math.floor((i - 1) / self.PER_ROW)
            local col2 = (i - 1) % self.PER_ROW
            b:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                       self.PAD + col2 * (self.SIZE + self.PAD),
                       -(self.PAD + row * (self.SIZE + self.PAD)))
            b:SetAlpha(1)
        else
            b:SetAttribute("unit", "none")
            b.pname, b.pclass, b.punit, b.boundByName = nil, nil, nil, nil
            b.modelOk = false
            self:SetPortrait(b, nil)
            b:SetAlpha(0)
            -- park it off the grid: an empty square left in the layout is an
            -- invisible click-eater sitting right beside a real face
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", -5000, 0)
        end
    end

    -- A closed grid is alpha 0, and an invisible button still takes clicks -
    -- exactly the wasted innervate this addon exists to prevent. EnableMouse on
    -- a secure button is protected, so it is set here, out of combat, and a
    -- grid closed mid-fight goes properly deaf when the fight ends.
    self:SetClickable(not NS.db.gridHidden)

    local n = math.min(#list, self.MAX)
    local rows = math.max(1, math.ceil(n / self.PER_ROW))
    self.frame:SetSize(self.PER_ROW * (self.SIZE + self.PAD) + self.PAD,
                       rows * (self.SIZE + self.PAD) + self.PAD)
    self.count = n
end

-- the _ and x tabs live on the grid, so a hidden grid must hide them too or
-- they sit there invisible and clickable
-- 3D portraits do not inherit alpha, so they are shown and hidden explicitly
function Grid:ShowFaces(on)
    for i = 1, self.MAX do
        local b = self.squares[i]
        if not b then break end
        if b.model then
            if on then
                -- only the squares that actually had a face get it back
                if b.pname and b.modelOk then b.model:Show() else b.model:Hide() end
            else
                b.model:Hide()
            end
        end
    end
end

function Grid:SyncTabs()
    local f = self.frame
    if not f then return end
    local hidden = NS.db.gridHidden and true or false
    if f._scaleTab then if hidden then f._scaleTab:Hide() else f._scaleTab:Show() end end
    if f._closeTab then if hidden then f._closeTab:Hide() else f._closeTab:Show() end end
    if f._cfgTab   then if hidden then f._cfgTab:Hide()   else f._cfgTab:Show()   end end
end

function Grid:SetClickable(on)
    if not self.frame or NS.InCombat() then return false end
    for i = 1, self.MAX do
        local b = self.squares[i]
        if not b then break end
        pcall(b.EnableMouse, b, (on and b.pname) and true or false)
    end
    self.clickable = on and true or false
    return true
end

-- Raid slots renumber mid-fight. The cast is bound by name so it stays right,
-- but the mana bar and the death check read a unit id, so re-resolve those.
-- Plain table writes: legal at any time, including in combat.
function Grid:Reunit()
    if not self.frame then return end
    local byName = {}
    NS.ForEachMember(function(unit, name) byName[name] = unit end)
    for i = 1, self.MAX do
        local b = self.squares[i]
        if not b then break end
        -- keep the old token if the roster is mid-blip and gives us nothing,
        -- or a zone-in would dim the whole grid for a second
        if b.pname and not b.demoName and byName[b.pname] then b.punit = byName[b.pname] end
    end
end

--------------------------------------------------------------------
-- update (safe in combat: colours, alpha and a texture height only)
--------------------------------------------------------------------

function Grid:Update()
    if not self.frame then return end
    if NS.MyKind() ~= "INNERVATE" then return end

    local me       = NS.PlayerName()
    local ready    = NS.SpellCooldownFor("INNERVATE") <= 0
    local inGroup  = NS.InGroup()

    -- who is asking, and who is on the hook for them
    local wanted, taken = {}, {}
    for _, r in ipairs(NS.Queue:ActiveList()) do
        if (r.kind or "INNERVATE") == "INNERVATE" then
            if r.assigned == me and not r.releasing then
                wanted[r.target] = true
            else
                taken[r.target] = r.assigned or true
            end
        end
    end

    -- closed by the X (or /inn grid) stays closed: Update runs constantly and
    -- used to paint the alpha back on every pass
    -- a solo demo has no group; without this /inn demo shows nothing at all,
    -- which is the one situation it exists for
    local visible = (inGroup or NS.demoMode) and (self.count or 0) > 0 and not NS.db.gridHidden
    self.frame:SetAlpha(visible and 1 or 0)

    -- A 3D model frame ignores its parent's alpha - that is a WoW quirk, not a
    -- bug here - so fading the grid out left every portrait floating on screen
    -- with nothing behind it. Models have to be hidden by hand.
    if not visible then
        self:ShowFaces(false)
        return
    end
    self:ShowFaces(true)

    for i = 1, self.MAX do
        local b = self.squares[i]
        if not b then break end
        if b.pname then
            local unit = b.punit
            local mana = unit and NS.ManaPct(unit)
            if b.demoName and NS.Demo then mana = NS.Demo:ManaFor(b.demoName) end
            b.pmana = mana

            -- mana bar
            if b.mana then
                local h = math.max(1, math.floor((mana or 0) / 100 * (self.SIZE - 4)))
                b.mana:SetHeight(h)
            end

            local mine = wanted[b.pname]
            local hasFace = (b.model and b.model:IsShown()) or b.faceOk

            -- The state is the OUTLINE. Over a portrait nothing is washed on
            -- top of the face; without one the square falls back to a flat
            -- colour so it still reads.
            -- SetBorder(b, r, g, b, a, pulse): a call that is not the LAST
            -- argument is truncated to one value, so the colour is unpacked
            -- into locals first. That mistake reads fine and paints garbage.
            local br, bg2, bb, ba, pulse
            if mine and ready then
                br, bg2, bb, ba, pulse = T.rgba("accent", 1)           -- yours: violet, pulsing
                pulse = true
            elseif mine then
                br, bg2, bb, ba = T.rgba("gold", 1)                    -- yours, on cooldown
            elseif taken[b.pname] then
                br, bg2, bb, ba = T.rgba("good", 0.9)                  -- another druid has it
            else
                br, bg2, bb, ba = T.rgba("line", 0.8)                  -- idle: a plain dark edge
            end
            NS.Secure:SetBorder(b, br, bg2, bb, ba, pulse)

            if b.body then
                if hasFace then
                    b.body:SetColorTexture(0, 0, 0, 0)                -- let the face show
                elseif mine and ready then
                    b.body:SetColorTexture(T.rgba("accent", 1))
                elseif mine then
                    b.body:SetColorTexture(T.rgba("gold", 0.75))
                elseif taken[b.pname] then
                    b.body:SetColorTexture(T.rgba("good", 0.5))
                else
                    b.body:SetColorTexture((b.classR or 0.4) * 0.45,
                                           (b.classG or 0.4) * 0.45,
                                           (b.classB or 0.4) * 0.45, 1)
                end
            end

            local gone = (not b.demoName) and (not unit)
            local dead = (not b.demoName) and unit and
                ((UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
                 or (UnitIsConnected and not UnitIsConnected(unit)))
            dead = dead or gone
            -- someone the combat log has pegged as dps fades into the background
            -- until they ask for something; the square stays bound and clickable
            local quiet = (not mine) and (not taken[b.pname]) and b.pclass ~= "MAGE"
                          and NS.Roles and NS.Roles:Guess(b.pname) == "dps"
            local a = dead and 0.25 or (ready and 1 or 0.55)
            if quiet then a = math.min(a, 0.45) end
            b:SetAlpha(a)
        end
    end
end

-- Point a square's portrait at a player. Only ever called out of combat, with
-- the binding, so nothing here has to be combat safe.
function Grid:SetPortrait(b, unit)
    if not b then return end
    b.faceOk = false

    if not unit then
        b.modelOk = false
        if b.model then b.model:Hide() end
        if b.face then b.face:SetTexture(nil) end
        return
    end

    -- 2D first: it always works, even for someone across the zone
    if b.face and SetPortraitTexture then
        local ok = pcall(SetPortraitTexture, b.face, unit)
        b.faceOk = ok and true or false
        if not ok then b.face:SetTexture(nil) end
    end

    -- then the animated one on top, if it is wanted and the client plays along
    if b.model then
        if NS.db and NS.db.portraits == false then
            b.modelOk = false
            b.model:Hide()
            return
        end
        local ok = pcall(function()
            b.model:SetUnit(unit)
            if b.model.SetPortraitZoom then b.model:SetPortraitZoom(1) end
            if b.model.SetCamDistanceScale then b.model:SetCamDistanceScale(1.1) end
            if b.model.SetRotation then b.model:SetRotation(0) end
        end)
        if ok then
            b.modelOk = true
            b.model:Show()
            b.faceOk = true
        else
            b.modelOk = false
            b.model:Hide()
        end
    end
end

-- models occasionally come back blank after a zone change
function Grid:RefreshPortraits()
    if not self.frame or NS.InCombat() then return end
    for _, b in ipairs(self.squares) do
        if b.pname and b.punit then self:SetPortrait(b, b.punit) end
    end
end

function Grid:TogglePortraits()
    NS.db.portraits = (NS.db.portraits == false)
    NS.Print("3D portraits " .. (NS.db.portraits and "|cff40ff40on|r" or "|cffff6060off|r - flat squares"))
    if NS.InCombat() then
        NS.Print("takes effect when you leave combat.")
        return
    end
    self:Bind()
    self:Update()
end

function Grid:Toggle()
    self:Build()
    if not self.frame then
        NS.Print("the grid is for druids - your innervate squares.")
        return
    end
    if NS.InCombat() then
        -- a square's mouse can only be switched out of combat, so a mid-fight
        -- toggle would leave squares that look live and click dead, or the
        -- reverse. Refuse instead of half-doing it.
        NS.Print("the squares can't open or close mid-fight - try again when it ends.")
        return
    end
    NS.db.gridHidden = not NS.db.gridHidden
    self.frame:SetAlpha(NS.db.gridHidden and 0 or 1)
    self:SetClickable(not NS.db.gridHidden)
    -- the _ and x tabs go with it, or they sit there invisible and clickable
    self:SyncTabs()
    self:Update()          -- portraits do not follow the frame's alpha by themselves
    NS.Print("innervate grid " .. (NS.db.gridHidden and "hidden." or "shown."))
end
