-- BiS Innervate :: dev/theme.lua
-- The whole suite again, with a BiSTheme whose accent is WRONG on purpose
-- (#ff0000) installed after the addon files loaded. Only a wrong palette can
-- tell "reads the theme per call" from "captured the fallback at load and
-- looks right by coincidence" - the two are pixel-identical otherwise.
--
--     lua5.1 dev/theme.lua
package.path = "./dev/?.lua;" .. package.path
local H = dofile("./dev/harness.lua")
_G.BIS_HARNESS = H
H.THEME_PASS = "ff0000"
H.afterLoad = function(env)
    local T = env.BiSTheme
    if T and T.hex then T.hex.accent = H.THEME_PASS end
end
dofile("dev/tests.lua")
