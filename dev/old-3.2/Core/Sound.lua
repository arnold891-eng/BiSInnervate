-- BiS Innervate :: Sound.lua
-- Cues, and a voice line in front of them when a FojjiCore voice pack is
-- installed. Lines are never copied: they are played from FojjiCore's own
-- folder by path, the same way BiS Gamba does it.
--
--   asked        I just called (a soft confirmation)
--   someoneAsked a druid hears this when anyone calls for innervate
--   tideAsked    a tide shaman hears this when their group calls
--   claimed      the caller hears that a druid took it
--   landed       the caller hears that it landed
--
-- FojjiCore loads AFTER us (alphabetical), so it is resolved at play time,
-- never at file scope.

local ADDON, NS = ...

local Sound = {}
NS.Sound = Sound

-- sound-kit ids that exist on this client; the fallback that always plays
Sound.KITS = {
    soft   = 1115,      -- gsTitleOptionExit-ish click
    ping   = 8959,      -- raid warning
    ready  = 8960,      -- ready check
    quest  = 618,       -- quest complete-ish
    level  = 888,       -- level up
}

Sound.CUES = {
    asked        = { kit = "soft",  phrase = "Ready Check" },
    someoneAsked = { kit = "ping",  phrase = "Fixate on You" },
    groupAsked   = { kit = "ping",  phrase = "Stack Up",
                     byKind = { LUST = "Bloodlust", DRUMS = "Go Forward", TIDE = "Stack Up" } },
    claimed      = { kit = "ready", phrase = "Safe" },
    landed       = { kit = "quest", phrase = "Clear" },
}

Sound.voiceCache = {}     -- "pack/phrase" -> path | false

-- which cues this client should hear at all
local function wanted(cue, call)
    if NS.db and NS.db.sound == false then return false end
    if cue == "someoneAsked" then
        return NS.Provides("INNERVATE")
    elseif cue == "groupAsked" then
        -- only the provider of that thing, in that group (or anywhere, raid-wide)
        return call and NS.Provides(call.kind)
               and (NS.Provider(call.kind).scope == "raid" or call.group == NS.Subgroup(NS.PlayerName()))
    end
    return true
end

local function slug(phrase)
    return (string.lower(phrase):gsub("[^%w]+", "_"))
end

function Sound:VoicePacks()
    local fc = _G.FojjiCore
    local out = {}
    if fc and fc.voicePackOrder then
        for _, name in ipairs(fc.voicePackOrder) do out[#out + 1] = name end
    elseif fc and fc.voicePacks then
        for name in pairs(fc.voicePacks) do out[#out + 1] = name end
        table.sort(out)
    end
    return out
end

function Sound:ActivePack()
    local v = NS.db and NS.db.voice or "auto"
    if v == "off" then return nil end
    local packs = self:VoicePacks()
    if #packs == 0 then return nil end
    if v == "auto" then
        -- FojjiCore renames and drops packs between releases (Brittney went
        -- away in one update), so auto never names a pack: it takes the first
        -- installed pack that carries our lines, else whatever is first.
        local fc = _G.FojjiCore
        for _, p in ipairs(packs) do
            local lines = fc and fc.voicePacks and fc.voicePacks[p]
            if type(lines) == "table" and lines["Fixate on You"] then return p end
        end
        return packs[1]
    end
    local lv = string.lower(v)
    for _, p in ipairs(packs) do
        if string.lower(p) == lv or string.find(string.lower(p), lv, 1, true) then return p end
    end
    return nil
end

function Sound:PlayVoice(phrase)
    local pack = self:ActivePack()
    if not pack or not phrase or not PlaySoundFile then return false end
    local key = pack .. "/" .. phrase
    local cached = self.voiceCache[key]
    if type(cached) == "number" then
        -- a miss is retried after 30s: FojjiCore may not have registered its
        -- packs yet when the first cue fired
        if (NS.Now() - cached) < 30 then return false end
        cached = nil
    end
    local fc = _G.FojjiCore
    local path = cached
    if not path then
        path = fc and fc.voicePacks and fc.voicePacks[pack] and fc.voicePacks[pack][phrase]
        if not path then
            path = "Interface\\AddOns\\FojjiCore\\voice\\" .. pack .. "\\" .. slug(phrase) .. ".ogg"
        end
    end
    local ok, played = pcall(PlaySoundFile, path, "Master")
    if ok and played then
        self.voiceCache[key] = path
        return true
    end
    self.voiceCache[key] = NS.Now()
    return false
end

function Sound:Play(cue, call)
    local spec = self.CUES[cue]
    if not spec or not wanted(cue, call) then return end
    -- the same cue twice in one frame is one cue
    local now = NS.Now()
    self._last = self._last or {}
    if self._last[cue] and (now - self._last[cue]) < 0.2 then return end
    self._last[cue] = now

    local phrase = (spec.byKind and call and spec.byKind[call.kind]) or spec.phrase
    if self:PlayVoice(phrase) then return end
    local id = self.KITS[spec.kit]
    if id and PlaySound then pcall(PlaySound, id, "Master") end
end

function Sound:Test()
    NS.Print("voice pack: " .. tostring(self:ActivePack() or "none") ..
             " (" .. #self:VoicePacks() .. " installed)")
    self:Play("someoneAsked")
end
