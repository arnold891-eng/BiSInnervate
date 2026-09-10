-- BiS Innervate :: Shared.lua
-- The shared BiS channel (Libs\LibBiSComm-1.0, embedded byte-identical from
-- _bisdev). It is NOT an Innervate feature and no setting here may gate it:
-- just carrying this addon makes the client answer WHERE and SUM for any BiS
-- summoner in the raid - "one addon gets you half way". Only /bis off mutes it.
--
-- Innervate's own pipe (Core/Comm.lua: prefix BiSInn, protocol 4) is a
-- separate channel and is not touched: the lib rides alongside, prefix "BiS",
-- and each OnMessage ignores the other's prefix.
--
-- The lib keeps no SavedVariables, so its off switch is remembered in
-- BiSInnervateDB.comm and restored next login.

local ADDON, NS = ...

local Shared = {}
NS.Shared = Shared

function Shared.Boot()
    local lib = _G.LibBiSComm
    if not lib then return end
    lib:RegisterAddon(ADDON, NS.VERSION)
    if NS.db and NS.db.comm == false then lib:SetEnabled(false) end   -- restore the off switch
    lib:Boot()
end

function Shared.Save()
    local lib = _G.LibBiSComm
    if lib and NS.db then NS.db.comm = lib:Enabled() and true or false end
end
