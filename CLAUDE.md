Read ../_bisdev/CLAUDE.md first.

## Layout (BiSInnervate only)

- `BiSInnervate.toc`: the load order, and the only place the version lives (`## Version`, currently 3.3.12). `## Interface: 20506`, `## SavedVariables: BiSInnervateDB`, `## OptionalDeps: BiSTheme, FojjiCore`. The libs load first, then `Core/Util`, `Comm`, `Shared`, `Tracker`, `Sound`, `Calls`, `Rez`, then `UI/Window`, `UI/Minimap`, `UI/Options`, then `Core/Demo`, `Core/Options` and last `Core/Init`. `dev/harness.lua` and `dev/release.ps1` both read the TOC.
- Every file shares the `local ADDON, NS = ...` namespace, and each module hangs off it (`NS.Calls`, `NS.Comm`, `NS.Rez`, `NS.Tracker`, ...). Big files are split into sections by `----` banners.
- `Core/Util.lua` (682 lines): constants, palette, small helpers, print, API shims, group helpers and timers. No frames, no events.
  - `NS.VERSION` comes from the TOC metadata. The literal `"3.3.12"` is only a fallback, and `dev/tests.lua` checks that it matches the TOC.
  - `NS.PROTOCOL = 4`, `NS.PREFIX = "BiSInn"`. Never bump the protocol: BiSGamba's RezComm sends `RCLAIM/RDONE/RFREE` on protocol 4.
  - `NS.T` is the palette: BiSTheme when it is installed, the same values inline when it is not.
- `Core/Comm.lua` (224 lines): the addon's own pipe-separated channel (`HELLO`, `STATE`, `REQ`, `ASSIGN`, `CLAIM`, `DONE`, `CANCEL`, plus the rez commands `RCLAIM/RDONE/RFREE`). Unknown commands are ignored, so new commands can be added without breaking older clients.
- `Core/Shared.lua` (30 lines): boots the embedded LibBiSComm (prefix `"BiS"`) next to the addon's own channel. No setting may turn it off. Only `/bis off` mutes it, and that choice is saved in `BiSInnervateDB.comm`.
- `Core/Tracker.lua` (297 lines): who can give mana (druids with Innervate, resto shamans with Mana Tide), their cooldowns and groups, and casts seen in the combat log. Lives in `Tracker.providers[kind][name]`. Only players running the addon count.
- `Core/Sound.lua` (179 lines): sound cues, plus FojjiCore voice lines played from FojjiCore's own folder. FojjiCore loads after this addon, so it is looked up when a sound plays, never at load time.
- `Core/Calls.lua` (375 lines): the call model. Someone calls, the faces pulse, the first druid to click claims the call (the claim lasts `claimHold` seconds) and the combat log confirms the cast. Sections: reading, may I ask, writing, combat log resolves, ticker, incoming.
- `Core/Rez.lua` (1503 lines): the rez module, folded in from BiS Rez 3.0. One secure button per healer that picks rez, heal or drink. It never uses a druid's Rebirth, and a claim only starts on `UNIT_SPELLCAST_START`. Sections:
  - constants, state, API shims, who am I
  - claims, peers (`Tracker.providers.REZ`), wipe protection
  - target selection, heals, drink, the decision
  - the button (attributes only; `UI/Window.lua` owns the frame), events, scoreboard, keybinding, tooltip, incoming
- `UI/Window.lua` (1557 lines): the one window everyone sees (ask buttons plus a grid of faces; for a druid each face is a secure Innervate button). Sections: paint helpers, build, drum flyout, drummer's kit (secure item buttons), bind (out of combat only), refresh (safe in combat), show/hide/scale (protected, waits until combat ends).
- `UI/Minimap.lua` (148 lines): the minimap button. Left-click shows or hides the window, right-click opens options, shift-left prints status, shift-right starts the demo.
- `UI/Options.lua` (225 lines): the option list for the shared options window in `Libs/BiSTheme/Options.lua`. Every `set` calls the function the slash command already uses (`NS.Set*`, `W:SetMagesOnly`, `Minimap:Set`) and never writes to the DB itself. It holds no secure frames.
- `Core/Demo.lua` (99 lines): `/inn demo`, fake raiders in `Demo.FAKES`. While it is on, the client sends nothing to the raid.
- `Core/Options.lua` (405 lines): `NS.DEFAULTS` and migrations (`dbVersion`, currently 4; anything older is 2.x data and gets pruned), the setters (one owner per key), and the slash command handler (`inn`, `tide`, `lust`, `drums`, `rez*`, `bind`, `callers`, `mages`, `healer`, `config`, `status`, `demo`, `reset`, ...).
- `Core/Init.lua` (237 lines): event wiring on `BiSInnervateEventFrame` (`NS.eventFrame`). Every `RegisterEvent` goes through `pcall`. Registers `/inn`, `/innervate` and `/bisinn`.
- `Libs/`: embedded LibStub, CallbackHandler-1.0, LibHealComm-4.0 (with ChatThrottleLib), BiSTheme `Console.lua`/`Options.lua` and LibBiSComm-1.0. `release.ps1` refuses to build if LibBiSComm differs from `../_bisdev`.
- `dev/harness.lua` (1205 lines): runs a simulated raid. Each client gets its own copy of the addon, and messages and combat log events are routed between them.
  - Reads the load order from the TOC. LibStub, CallbackHandler and LibHealComm are stubbed and skipped; the other libs load for real.
  - Fails on combat lockdown breaks. Any call to `SpellStopCasting` from addon code is counted as forbidden.
  - `world.rootFor` loads an older build for one client. The suite points it at `dev/old-3.2`, which has no TOC, so the fixed `OLD_FILES` list is used.
- `dev/tests.lua` (2272 lines): the regression suite, run with `lua5.1 dev/tests.lua` from the addon folder.
- `dev/theme.lua` (16 lines): runs `tests.lua` again with a BiSTheme whose accent is deliberately wrong (`ff0000`), to prove the addon reads the theme on each call.
- `dev/options.lua` (210 lines) with `dev/kit.lua` (478 lines): tests the shared `Libs/BiSTheme/Options.lua` on its own. `kit.lua` is Nebbinator's harness copied verbatim. There is no `stress` suite.
- `dev/old-2.x/`, `dev/old-3.2/`, `dev/old-bisrez/`, `dev/*.zip`: old builds kept for reference. Only `old-3.2` is loaded by the tests.
- `dev/release.ps1` (146 lines): builds the zip into Downloads (leaving out `dev`, `.pkgmeta` and dot-files) and uploads it to CurseForge project 1674333. The changelog it sends is the top entry of `CHANGELOG.md`. `-ZipOnly` skips the upload.
- `.pkgmeta`: `package-as: BiSInnervate`, ignores `dev` and `.pkgmeta`.
- `.github/workflows/check.yml`: calls the reusable workflow in `bisdev` with `addon: BiSInnervate`.
