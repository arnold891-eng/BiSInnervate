-- BiS Innervate :: DruidPanel.lua
-- What a druid sees. One glowing row = "this one is yours, click it".
-- Grey rows = other people's requests, shown only so you know they are covered.

local ADDON, NS = ...
local T = NS.T

local UI = {}
NS.UI = UI
UI.refreshHooks = {}

local PANEL_W = 210
local INFO_H  = 20

function UI:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "BiSInnervateFrame", UIParent)
    f:SetSize(PANEL_W, 40)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(self_)
        if NS.InCombat() then return end
        local h = NS.Secure.header
        if h then h:SetMovable(true); h:StartMoving() else self_:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self_)
        if NS.InCombat() then return end
        local h = NS.Secure.header
        local moved = h or self_
        moved:StopMovingOrSizing()
        local point, _, rel, x, y = moved:GetPoint()
        NS.db.pos = { point = point, rel = rel, x = x, y = y }
    end)

    -- the frame keeps a fixed size (resizing it in combat would touch the anchor
    -- of a secure child); only the background texture grows and shrinks, which
    -- is legal at any time.
    f:SetSize(PANEL_W, 24 + NS.Secure.MAX_ROWS * NS.Secure.STEP)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT")
    bg:SetPoint("TOPRIGHT")
    bg:SetHeight(52)
    bg:SetColorTexture(T.rgba("bg", 0.9))
    f.bg = bg

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 6, -5)
    title:SetText("Innervate")
    title:SetTextColor(T.rgb("accent"))
    f.title = title

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("TOPRIGHT", -6, -6)
    f.status = status

    -- (the header is created first, in Init, so the panel can anchor to it)
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 0, -22)
    list:SetPoint("TOPRIGHT", 0, -22)
    list:SetHeight(NS.Secure.MAX_ROWS * NS.Secure.STEP)
    f.list = list

    NS.Secure:Build(UIParent)

    -- info rows: ordinary buttons, no spell attributes, safe to show/move in combat
    self.info = {}
    for i = 1, NS.Secure.MAX_ROWS do
        local row = CreateFrame("Button", "BiSInnervateInfo" .. i, f)
        row:SetSize(PANEL_W - 12, INFO_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -22 - ((i - 1) * INFO_H))
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(T.rgba("surface", 0.9))
        local t = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t:SetPoint("LEFT", 6, 0)
        t:SetJustifyH("LEFT")
        row.text = t
        local take = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        take:SetPoint("RIGHT", -6, 0)
        row.take = take
        row:SetScript("OnClick", function(s)
            local req = s.reqId and NS.Queue:Get(s.reqId)
            if req then NS.Queue:AskToTake(req) end
        end)
        row:SetScript("OnEnter", function(s)
            if not GameTooltip then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Another druid is on this one.")
            GameTooltip:AddLine("Click to take it over - they get dropped first.", T.rgb("ink"))
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide()
        self.info[i] = row
    end

    -- Anchor the panel TO the secure header. The header owns the position (it
    -- is the thing that must not move in combat); the panel just follows it.
    -- Anchoring the other way round is what re-protected the panel.
    local anchor = NS.Secure.header
    if anchor then
        f:SetPoint("TOPLEFT", anchor, "TOPLEFT", -4, 22)
    else
        local pos = NS.db.pos
        if pos then
            f:SetPoint(pos.point or "CENTER", UIParent, pos.rel or "CENTER", pos.x or 0, pos.y or 0)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
        end
    end
    f:Hide()

    self.frame = f
    return f
end

function UI:Alert(req)
    if not req or req.state ~= "pending" then return end
    if req.assigned ~= NS.PlayerName() then return end
    if self._lastAlert == req.id and (NS.Now() - (self._lastAlertAt or 0)) < 4 then return end
    self._lastAlert, self._lastAlertAt = req.id, NS.Now()
    if NS.db.sound ~= false and PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
    if NS.db.chatAlert ~= false then
        local kind = req.kind or "INNERVATE"
        local what = (NS.Provider(kind) or {}).short or "innervate"
        local how  = (kind == "INNERVATE") and " - click their purple square."
                                            or " - click your Mana Tide button."
        NS.Print(T.text("gold", req.target) .. " needs " .. what ..
            (req.mana and (" (" .. req.mana .. "%)") or "") .. how)
    end
end

-- A castable row is ONLY ever built for a request that is assigned to me and
-- not mid-handover. Other people's requests are drawn as plain text lines that
-- cannot cast anything, so two providers can never both have a live button.
local function entryFor(req, meReady)
    -- no unit while the spell is down: an inert row cannot be clicked into a
    -- wasted click, and cannot stall the escalation
    if not meReady then return nil end
    -- never "player" for a demo request: that builds a row wired to the REAL
    -- spell, labelled with a fake name, that casts Innervate (or drops a real
    -- Mana Tide) on you. The demo lives on the grid squares.
    if req.demo then return nil end
    local unit = NS.UnitOf(req.target)
    if not unit then return nil end
    -- the icon carries the spell; the text beside it says who and how bad
    local label = NS.ClassColored(req.target, req.class)
    local sub   = req.mana and (req.mana .. "% mana") or ""
    if req.kind == "TIDE" then
        local n = 1
        for _ in pairs(req.riders or {}) do n = n + 1 end
        label = "Group " .. tostring(req.group or "?")
        sub   = (n > 1) and (n .. " out of mana") or (req.target .. " oom")
    end
    return {
        unit = unit, name = req.target, label = label, id = req.id,
        sub  = sub, glow = meReady,
    }
end

function UI:Refresh()
    -- coalesce: many events fire at once
    if self._pending then return end
    self._pending = true
    if not NS.After(0.05, function() UI._pending = false; UI:DoRefresh() end) then
        self._pending = false
        self:DoRefresh()
    end
end

function UI:DoRefresh()
    for _, fn in ipairs(self.refreshHooks) do pcall(fn) end
    if not self.frame then return end

    local myKind  = NS.MyKind()
    local isDruid = myKind ~= nil
    local all = NS.Queue:ActiveList()
    local reqs = {}
    for _, r in ipairs(all) do
        if (r.kind or "INNERVATE") == myKind then reqs[#reqs + 1] = r end
    end
    if self.frame.title and myKind then
        self.frame.title:SetText((NS.Provider(myKind) or {}).name or "Innervate")
    end

    if NS.db.hidePanel or not isDruid or not NS.InGroup()
       or (#reqs == 0 and not NS.db.alwaysShow) then
        self.frame:Hide()
        -- the cast buttons hang off UIParent now, so hiding the panel does not
        -- hide them: clear them explicitly or one is left floating and castable
        NS.Secure:SetEntries({})
        -- The Mana Tide button lives on the header, not the panel, so closing the
        -- panel with the x would leave it hanging in space. But this branch is
        -- also the ordinary "nobody is asking right now" case, and a shaman's
        -- tide button is meant to sit there permanently - hiding it there took
        -- the button away for good, since nothing here ever put it back.
        if NS.Secure.selfCast and NS.Secure.rows[1] then
            NS.Secure.rows[1]:SetAlpha(NS.db.hidePanel and 0 or 0.35)
        end
        self:SetInfo({}, 0, false)
        return
    end

    local cd = NS.SpellCooldownFor(myKind)
    local meReady = (cd <= 0)
    NS.Secure:UpdateCooldowns()
    self.frame.status:SetText(meReady and T.text("good", "ready") or T.text("gold", NS.TimeStr(cd)))

    local mine, others = {}, {}
    for _, r in ipairs(reqs) do
        if r.assigned == NS.PlayerName() and not r.releasing and meReady then
            mine[#mine + 1] = r
        else
            others[#others + 1] = r
        end
    end

    local entries = {}
    for _, r in ipairs(mine) do
        local e = entryFor(r, meReady); if e then entries[#entries + 1] = e end
    end

    local n = NS.Secure:SetEntries(entries) or 0
    local infoN = self:SetInfo(others, n, meReady)
    if self.frame.bg then
        self.frame.bg:SetHeight(26 + (n * NS.Secure.STEP) + (infoN * INFO_H))
    end
    self.frame:Show()
end

-- plain, non-casting lines for requests that belong to another druid.
-- Clicking one asks the owner to hand it over (only allowed if my innervate is
-- up); the owner then runs the same release-then-assign handover, so there is
-- still never more than one live button in the raid.
function UI:SetInfo(list, offset, meReady)
    local shown = 0
    for i = 1, NS.Secure.MAX_ROWS do
        local row = self.info and self.info[i]
        local r = list[i]
        if row then
            if r and (offset + shown) < NS.Secure.MAX_ROWS then
                shown = shown + 1
                row.reqId = r.id
                row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4,
                    -22 - (offset * NS.Secure.STEP) - ((shown - 1) * INFO_H))
                local who = r.releasing and T.text("muted", "handing over")
                          or (r.assigned == NS.PlayerName() and T.text("gold", "yours - on cooldown"))
                          or (r.assigned and T.text("muted", r.assigned) or T.text("muted", "unassigned"))
                row.text:SetText(string.format("%s  %s", T.text("ink2", r.target ..
                    (r.mana and (" " .. r.mana .. "%") or "")), who))
                row.take:SetText(meReady and T.text("good", "take") or "")
                row:Show()
            else
                row.reqId = nil
                row:Hide()
            end
        end
    end
    return shown
end

function UI:ToggleHidden()
    NS.db.hidePanel = not NS.db.hidePanel
    NS.Print("request list " .. (NS.db.hidePanel and "closed." or "back."))
    self:DoRefresh()
end

function UI:Toggle()
    NS.db.alwaysShow = not NS.db.alwaysShow
    NS.Print("panel " .. (NS.db.alwaysShow and "pinned." or "auto-hide."))
    self:DoRefresh()
end
