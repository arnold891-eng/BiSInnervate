# Changelog

## 3.0
**It is one window now.**

Through 2.9 there were three unrelated pieces of furniture on screen: a title
bar with the counts, a 64px button somewhere else, and a line of champion text
floating between them. Each had its own position, its own drag, its own hide
flag. They are one frame:

    +--------------------------------------+
    | [icon] BiS Rez  2/3  +1     cfg   x  |
    |  [ button ]   Holypal                |
    |               Kumlust 3              |
    |  [f][f][f][f][f][f][f]               |
    |  ------------------------------------|
    |  [r][r][r]                           |
    +--------------------------------------+

- The button is a child of the window, with the target name beside it and the
  champion tally under that. Drag it by the title bar **or by the button** --
  it is the biggest target, so it moves the window rather than tearing off it.
- One `hidden` flag and one `locked` flag for the whole thing. `/bisrez show`,
  `/bisrez hide` and `/bisrez window` are the same switch. **Your existing
  settings are folded in, not lost**: if either half was hidden or locked
  before, it stays that way, and the button's old position becomes the window's.
- One visibility driver, on the window -- the button follows its parent rather
  than fighting a second driver of its own.
- The options lose three duplicated controls. The **Window** tab now owns show,
  lock, hide-in-combat, reset position and the minimap coin; **Button** keeps
  the click edge, the binding and the diagnostics.
- The window sizes itself to what is actually there: 174x94 with nothing to do,
  taller as corpses appear, taller again when a peer answers. Seven corpses per
  row now rather than six, to match the width the button needs.
- New: `/bisrez hidecombat`.

Suite is at 161 tests.

## 2.9
This is an out-of-combat addon, so it now behaves like one.

- **A druid's Rebirth is never spent on a recovery.** It is an hour of cooldown
  and the raid's only combat rez; burning it on a corpse after the fight is over
  is the most expensive thing this addon could have done. Rebirth is gone from
  the rez path entirely. A druid keeps the heal, the drink, the window and the
  rezzer list -- their rez stays theirs, to spend by hand, in a fight, on purpose.
- **Wipe protection counter.** How many ways the raid has of getting somebody up
  without a corpse run: a Shaman's Reincarnation (only with an Ankh actually in
  the bag), a Paladin's Divine Intervention, and a Soulstone -- but only on
  somebody who can resurrect. A stone on a rogue saves one corpse run; a stone on
  a priest saves the raid's. Shown on the window when there is any, in the header
  tooltip with names, and in `/bisrez rezzers`. It stays blank when the number is
  zero, because a permanent "0" is noise and its absence is the thing to notice.
- **The rez order is a throughput order.** Rezzers first, because each one
  multiplies the rate everyone else comes up; then mana (a druid's Innervate, a
  mage's water, a warlock's stone for next time); then everyone who can only be
  rezzed. When every standing rezzer is actually dry, the mage is promoted --
  at that point water outranks another body. `/bisrez list` shows the real score.
- **A released player sorts behind every body still on the floor.** They are
  running back under their own steam; standing here does not help them.
- **Hidden in combat instead of engineered around.** A stray mid-fight click just
  threw a red error, so the button and window now disappear for the fight via a
  secure visibility driver. A bound key still fires -- a deliberate keypress is
  not a misclick. Optional, on by default.
- **Minimap coin.** Left toggles the corpse window, right opens the options,
  shift-left prints who can rez. Drag it round the ring. `/bisrez minimap`.
- **One sound.** Exactly one, for the only moment where a noise changes what
  somebody does: a rez is being cast on YOU while you are deciding whether to
  release. Fires for non-addon rezzers too, off the cast bar.

Fixed on the way: with mana unreadable, every mage permanently outranked every
priest -- absence of a reading is not evidence that a rezzer is dry. The harness
caught it on the first run.

Suite is at 142 tests.

## 2.8
Everything worth taking from **BiS Innervate**, which has been through a real
raid and paid for these lessons already.

- **The corpse window.** A compact list of every corpse in reach -- click a face
  to rez that one. Claimed corpses grey out with a `*`, the one your button is
  aimed at gets an accent border and a `!`. Below a hairline, every other rezzer
  running BiS Rez, greyed with a countdown when their spell is down. `/bisrez
  window`, or the new Window tab in the options.
- **You can see other people's rez cooldowns.** Peers broadcast their class and
  their real cooldown, read live from the client -- which matters entirely for
  Druids, whose Rebirth is twenty minutes while every other rez has none.
  `/bisrez rezzers` lists them. Only people running the addon count: a druid
  without it cannot see a claim, so counting them would make a corpse look
  covered when nobody is coming.
- **The addon channel is a real protocol now.** `PROTO|CMD|args` instead of
  `C:<guid>`. Four things the old format did not do, all of which Innervate hit
  live: no version field (a format change silently corrupts a claim); no channel
  check (a whispered addon message from outside the group could plant or release
  a claim on a corpse); no sender check (same); and no length guard -- the client
  drops anything past 255 bytes and never tells the sender, so a long scoreboard
  simply evaporated. An older client in the group now gets one explanatory line
  instead of being half-understood.
- **Fixed: a zone-in wiped the scoreboard.** The roster reads EMPTY for a moment
  when you zone, and the handler read that as "left the group". A zone into the
  raid instance threw away the night's tally. It now waits ten seconds before
  believing an empty roster -- a real departure still clears it.

Secure discipline, carried over intact: faces are bound **out of combat, by
NAME** (raid slots renumber mid-fight and cannot be rewritten); a name the
client cannot resolve leaves the face **unbound** rather than pointed at
whoever inherited the slot; in combat only colour and text change; and a closed
window is **deaf**, not merely invisible -- alpha 0 alone left an invisible drag
strip and invisible tooltip catchers across the screen. Class icons rather than
3D portraits, because PlayerModel ignores parent alpha.

Suite is at 108 tests.

## 2.7
**New options window.** Flat and layered in the spirit of FojjiCore -- a left rail
of tabs, surfaces that step a shade lighter as they come forward, 1px texture
borders -- but in BiS violet on violet-black, off the shared `BiSTheme` palette.
700x500, hand-built checkbox / segmented / button widgets, no Blizzard templates
and no backdrop art.

- Four tabs: **Rez** (cast method, macro syntax, priority order, and the exact
  macro body a click sends right now), **Support** (auto-heal, auto-drink, the
  heal list with its sizes and your healing power), **Leaderboard** (display,
  counting rules, the board itself), **Button** (placement, click edge, current
  binding, diagnostics).
- Every control writes the **same saved variable the slash commands already
  set**, so the two can never drift. There is a test that toggles a setting by
  slash and asserts the window reads the change back.
- `/bisrez` with no arguments toggles it; `/bisrez config` (or `options`,
  `settings`) opens it. Esc closes it.
- The old panel's eleven globally-named checkbuttons are gone.

Internals: the window reaches the rest of the addon through a shared `G` table
rather than by bare name -- a bare reference to a local declared further down
resolves to a nil global, which is the trap that has now bitten this family six
times. A table field cannot be shadowed that way.

Testing: `G.ConfigSet(id, v)` / `G.ConfigGet(id)` drive any control by id through
the same path a mouse click takes, so the harness proves the real widget writes
the real variable -- 9 checkboxes, 3 segmented controls and 9 action buttons,
round-tripped. The harness's `SetColorTexture` stub is now **strict**: it throws
unless it gets three numbers. `on and T.rgba(x) or shade(y)` truncates a
multi-return to one value and would take the whole window down on the live
client; a permissive stub would have let that through. Suite is at 70 tests.

## 2.6
Four things carried over from BiS Healing, which learned them the hard way.

- **Heal sizes now include your gear.** The spellbook tooltip on this client is
  BASE healing only -- Lesser Healing Wave reads ~950 and lands for well over
  double that. Every heal in the table was sized at a fraction of the truth, so
  "smallest heal that covers the deficit" concluded almost nothing ever covered
  it and reached for the biggest heal nearly every time -- the slowest, most
  expensive option, and the one that overheals. Sizes are now
  `(base + healing power x cast time / 3.5) x talents`, with the cast time read
  live so haste folds in for free. `/bisrez heals` shows both numbers.
- **Heal prediction sees healers who are not running a HealComm addon.** 2.5
  shipped with the caveat that LibHealComm only sees its own users -- which is
  exactly the healer who out-heals you to a target. The client's own
  `UnitGetIncomingHeals` sees everyone. Prediction takes the LARGER of the two,
  never the sum: for a HealComm user both numbers describe the same heal.
- **A cast-bar claim now lasts as long as the cast does.** It was a flat 3
  seconds, which expires under a 10-second rez and reopens the corpse on
  everyone's button while the caster is still casting on it. The cast bar says
  when it lands; the claim uses that.
- **Binding no longer edits your saved keybinds.** `/bisrez bind` used to write
  into your bindings file, so uninstalling the addon would leave a key pointing
  at a button that no longer exists. It now uses an override binding, which
  sits on top and touches nothing. Overrides clear on `/reload`, so the key is
  stored and re-applied at login. New: `/bisrez unbind`.

Also: passes `_bisdev/bislint.lua` clean, and the regression suite is up to 49
tests -- including the raid-identity case (in a raid, `raid1` IS you) that the
BiS Healing testing notes call out as a mock that hides live bugs.

## 2.5
- New: LibHealComm-4.0 (ships under `Libs/`, same copy BiS Healing uses). The
  heal picker was blind to other healers: it would see a tank at 40% and start
  a 3s Healing Wave on someone two instant-casters had already topped off before
  the cast landed. Heals other players have in the air are now subtracted from
  everyone's deficit BEFORE a target is picked, so the button moves on to whoever
  is genuinely uncovered -- and stands down entirely when the whole group is
  covered. Your own pending cast is never subtracted, or it would cancel the
  reason you started casting.
- Heal size and cast lead are read live, so both follow haste and +healing gear.
- `/bisrez heals` says whether the library loaded; `/bisrez diag` prints the cast
  lead and every unit with inbound heals plus its effective deficit.
- Without `Libs/` present the addon behaves exactly as v2.4 -- the library is
  entirely optional and every path degrades cleanly. Covered by a test.

## 2.4
Audit pass: the addon was run front-to-back on real Lua 5.1 against a mocked
client, with a global-leak detector. 25 regression tests ship in `dev/`.

- Fixed: ANY interrupted cast of yours released your rez claim and broadcast
  the release to the whole group, reopening the target on everyone's button
  mid-cast -- the exact double-rez this addon exists to prevent. Interrupt and
  stop handlers now check the spell, the way the failure handler already did.
- Fixed: heal targets were never range-checked. The rez path checked range; the
  heal path picked the worst-hurt player anywhere in the zone, so every click
  ate an "Out of range". Also skips anyone not visible.
- Fixed: the button went dead in combat. Attributes are locked once combat
  starts, so whatever was armed at the pull was frozen for the fight -- usually
  nothing, since nobody is hurt yet. Heals now go out as macro text with
  click-time conditionals ([@unit] -> mouseover -> target -> self), and an idle
  button keeps the biggest heal armed behind that same chain. Druid Rebirth,
  which is a combat rez, was hit hardest by this.
- Fixed: heals cast with a "(Rank N)" suffix through the spell attribute -- the
  one thing the rez path deliberately avoids as most likely to be silently
  rejected.
- Fixed: both click edges were registered by default, firing the secure action
  twice per click. The second cast landed on the first and the client's
  "another action is in progress" was reported as a failure for a heal that
  actually worked. Down edge only now; /bisrez clicks still cycles it.
- Fixed: a click's pending outcome line never expired, and any red error within
  1.5s was blamed on it -- "Holypal: You are already in a party". Errors are now
  matched against the client's own cast-failure strings, and a click older than
  3s is forgotten.
- Fixed: the roster handler read `opts` before its `local` declaration, so it
  was refreshing a nil global. An open options panel kept showing a scoreboard
  that had already been cleared.
- New (from BiS Healing): the button tooltip now lists the corpses it skipped
  and why, instead of making you type /bisrez list mid-wipe.
- New (from BiS Healing): options panel height is derived from its contents
  instead of a hardcoded 600px, and warns at login if the two drift apart.
- New: dev/ holds the offline harness and the regression suite -- real Lua 5.1,
  mocked WoW API, global-leak detector. `lua5.1 dev/bisrez-regress.lua`.

## 2.3
- One button now covers wipe recovery end to end: rez, drink, heal
- Drinks when a rez or heal is unaffordable -- picks Conjured Manna Biscuit first, then the 7200-mana drinks
- Heals whoever is worst off when nobody needs a rez; uses your class's group heal when 2+ are hurt
- Heal ranks are read from your own spellbook tooltips, so the numbers follow your +healing gear
- Icon and border now show what the click will do: green rez, yellow heal, blue drink, grey nothing
- Successful heals print nothing; only errors get a line
- Heals and drinks never touch the rez claim system or the leaderboard
- Two new options: Drink when out of mana, Heal the worst hurt when nobody needs a rez
- New: /bisrez heals, /bisrez rescan

## 2.2
- Fixed: chat line printed twice per click
- Scoreboard sync now names who it synced with

## 2.1
- Fixed: /bisrez had to be typed twice to open the options panel

## 2.0
- Fixed: error spam when any non-rez spell finished casting (spell-name lookup ran before its table existed)

## 1.9
- Registers all roster event variants so the scoreboard clears reliably on leaving a group

## 1.8
- Fixed: cast success/failure detection compared spell names against numeric spell IDs on modern clients — success report, self rez-count, and claim broadcast on cast start were all silently broken
- Fixed: failure/interrupt handlers now only react to the rez spell
- Fixed: saved click-edge setting is applied again at login
- Fixed: guildmate-only scoreboard filter crashed (function referenced before definition)

## 1.7
- One outcome line per click (rezzed / error / interrupted); full detail behind a verbose toggle

## 1.6
- Leaderboard syncs to newcomers who join with the addon
## 1.5
- Leaderboard clears when you change groups, not just when the roster empties

## 1.4
- Rez priority reordered: Priest > Paladin > Shaman > Druid > Mage > Hunter > Warlock > Warrior > Rogue

## 1.3
- Claims attach when the cast starts, not on click, so a no-mana click no longer locks a target
- Leaderboard ties display as ties

## 1.2
- Leaderboard clears on leaving the group; optional guildmate-only counting

## 1.1
- Rez leaderboard above the button

## 1.0
- Options panel

## 0.9
- Rez claim system: passive cast-bar detection plus addon-to-addon broadcast

## 0.1 - 0.7
- Initial release
