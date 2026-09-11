# BiS Innervate

## 3.3.10

- Shared console minor 4: the blinking cursor in the `BiS>` header is its own text now, so
  the words beside it no longer shift a hair every half second.

## 3.3.9

- Shared console minor 3: a header slot that toggles (`online`, `incoming`) no longer takes
  a second turn in the rotation every time it comes back.
- Offline proof that a Gamba-only or Tools-only rezzer's RezComm claim lands on this grid:
  claim same tick, his own FREE releases, a stranger's FREE is refused, wrong protocol is
  silence - and RezComm's PROTO is read off its file and held equal to NS.PROTOCOL.

## 3.3.8

- lib minor 5: phantom summon on bystanders fixed.
- The suite and `release.ps1` hold every embedded lib byte-identical to its canonical copy
  (`_bisdev`, `BiSTheme`), so a stale lib can no longer ship. 598 checks.

## 3.3.7

- **The options window is the house one** (`Libs\BiSTheme\Options.lua`): one narrow flat window,
  no tabs - the minimap button and the BiS channel switch, then window (scale, lock, Odiss and Neb
  mode, faces, drums), the rez button, alerts and the voice pack (a stepper that plays each pack as
  you land on it), and the call timings. Every change says itself in the window's `BiS>` prompt,
  not in chat. The old five-page panel is gone.
- What did not fit a box, a switch or a stepper is a slash command now: `/inn callers [class]` (who
  may ask), `/inn version`; the rezzer list, the heal list, the scoreboard and the keybind were
  already `/inn rezzers`, `rezheals`, `rezscore`, `bind`. The About page's version is on the
  minimap tooltip.
- Every option goes through the function its slash command uses (`NS.Set*`), so the two cannot
  drift; the suite clicks every control mid-fight and holds it to zero protected calls.
- The options window's test button and the voice stepper play a cue every class hears. They
  played `someoneAsked`, which is a druid's cue - silent on everyone else, the old panel too.
- Voice packs show as the voice - `Illidan`, `Fojji`, `Stacy` - not Fojji's `Flavour - ` /
  `Community - <Numen>` wrapping, which is all a 40 px stepper had room for. `auto` prefers
  Illidan when it is installed and carries our lines, then any pack that does, then the first.
- Escape closes the options window (the kit, minor 2 - every BiS addon gets it as they copy out).
- 595 checks, both ways; 61 for the kit itself.

## 3.3.6

- **The title is the `BiS>` prompt** (the house header, `Libs\BiSTheme\Console.lua`). It
  cycles the standing slots - `Innervate`, `N online` in green, what the window is doing
  (`heal Jeck` in gold, `rez Shammy` in teal, `drink`) - with a fade between, and events
  (`drums: War`, `Neb mode`) jump in over them for three seconds. The logo is gone: the prompt
  is the brand. Hover the prompt for who is online, shift-click prints them, drag moves the
  window - as before. Budget: 152 window - 64 (H and everything right of it) - 4 - 3 = 81
  clear, held at 76, so a long name trims with an ellipsis instead of running under H.
- **The shared BiS channel** (`Libs\LibBiSComm-1.0`, prefix `BiS`, minor 4) rides alongside.
  Innervate's own `BiSInn` protocol-4 pipe is untouched. Carrying this addon now makes you a
  peer for any BiS summoner in the raid: a `HI` at login, a `WHERE` on a zone change, an
  answer to a summon ASK. No heartbeat. `/biscomm` for status and the off switch (`/bis` is
  LoonBestInSlot's - lib minor 4 moved off it), remembered in
  `BiSInnervateDB.comm`. No Innervate setting can gate it (mutation-verified in the suite).
- `NS.VERSION` is the TOC's, not a literal; the suite holds every version literal equal to it.
- The harness loads the files the TOC lists, in the TOC's order, embedded libs included;
  `dev/theme.lua` runs the whole suite again under a wrong-on-purpose palette to prove the
  theme is read per call. 561 checks, both ways.

## 3.3.5

- **Druids are off the portrait grid.** Only mages and healers get a face: druids are the ones
  who click, not the ones who get clicked. A druid keeps their Innervate ask button.
- **The title bar cycles.** Every few seconds the title fades between a green-triangle
  `N online` count and what the window is doing (`heal Jeck`, or the name when idle). Hover the
  title for the list of who is online with the addon, click it to print them to chat. A new
  action shows at once, no fade. Text and alpha only, so it keeps ticking in a fight. The title
  is clipped at the H button, so a long name never runs under the buttons.
- Healer mode is labelled **Neb mode** in the options, the H tooltip and the chat line. Same
  `/inn healer`.
- **Spec on the grid.** A priest, paladin or shaman in a dps tree (shadow, ret, enhance,
  elemental) gets no face - only healing trees do. The biggest talent tree decides; it rides
  the REZ blob as `H` / `X`, a respec flips it live, and a client older than this keeps its
  face. Mages unchanged, druids stay off.
- **A starting mode.** Until you touch H, M, the tick or `/inn mages|healer`, the window picks
  a mode for you: a healing-tree priest / paladin / shaman starts in Neb mode, a druid in
  Odiss mode, everyone else in the full window. Anyone with a Mana Tide or drums in the bag
  keeps the full window - the faces are who they hand it to. Your first choice pins it for
  good (`modeSet`).
- The title bar drags the window again: the online strip only prints on **shift-click**.
- 529 checks.

## 3.3.4

- The logo leaves the title bar in healer mode and mages-only: the narrow bar is H, M, x and nothing else. It overlapped H.

## 3.3.3

- **Healer mode.** The `H` in the title bar, the tick on the Window page, or `/inn healer`: the
  rez / heal / drink button and nothing else - no faces, no ask buttons, the window one button
  wide. It still only appears with something to do. Turns mages-only off, and the other way
  round. Mid-fight it waits for the fight to end, like Odiss mode.
- The compact bar (mages-only, healer mode) is 64px minimum now that H sits beside M and x.
- 494 checks.

## 3.3.2

- **A druid in bear or cat form cannot innervate, and the raid knows.** The form flag rides the
  HELLO/STATE blob (`INNERVATE=F`), so a shapeshifted druid drops out of "druids up" and the ask
  button greys with "the druid is in bear or cat form" once every druid is in one. On the druid's
  own screen the faces grey while shifted (the tooltip says leave your form). Tree of Life is not
  a form for this purpose.
- Harness: `world.form` for shapeshifts. 477 checks.

## 3.3.1

- **Fixed: every heal was cast at max rank.** The rank was stripped off the cast name on the way
  into the macro (a caution copied from the rez path), so the picker's choice never reached the
  client: three "rank 8" heals landing for 3880 each. `Healing Wave(Rank 8)` is what the macro
  says now - the same form BiS Healing downranks with. Live check: estimates land within 1-3% of
  the measured casts (rank 9 est 3034 / measured 3062, rank 10 3374 / 3411).
- **Heal sizes are measured, not just estimated** (BiS Healing's method): every heal of your own
  in the combat log sizes that rank - crits thrown out, casts that were mostly overheal thrown
  out, only the first target of a chain. One calibration factor from the measured ranks corrects
  the unmeasured ones; a lower rank never reads above a higher one. Estimates carry the TBC
  downrank penalty (`(level + 11) / your level`, and under-20 ranks) when the client gives a
  rank's level. **The group heal downranks too**: two people 600 down get Chain Heal rank 1, not
  rank 5. `/inn rezheals` shows measured vs estimated; `/inn rezsizes` forgets the measurements.
- Every macro carries `nocombat`: the button is hidden in a fight, but a keybind still fires a
  hidden button with whatever was armed at the pull. The heal macro aims at one name only - the
  old `[@mouseover][@target][@player]` fallback put a heal meant for somebody else on the caster.
- Harness: `World:Heal2` feeds SPELL_HEAL lines, `world.spellLevel` for the rank levels. 467 checks.

## 3.3.0

- **BiS Rez is now a module of this addon.** Nobody had downloaded BiS Rez; everyone has
  downloaded Innervate, so every Innervate user becomes a rez peer the day they update. The
  rez, heal and drink logic moved over as `Core/Rez.lua`, rebuilt on Innervate's Comm, Tracker,
  Window and Config; BiS Rez's own copies of that plumbing are gone (its 161 checks are
  sections 36-50 of this suite). The folder stays `BiSInnervate`.
- **A fifth button in the row.** For a priest, paladin or shaman it is the rez button: one
  click rezzes the best corpse, else heals whoever is worst off, else drinks. Rezzers first
  (priest, paladin, shaman), then mana (druid, mage, warlock), then everyone else; the mage is
  promoted when every standing rezzer is dry, and a released player sorts behind every body
  still on the floor. The title bar names who it is about to rez; the tooltip says what it
  skipped and why. A druid gets heal and drink - **Rebirth is never spent here.**
- **The moment one rezzer starts a cast, every other rezzer's button moves to the next
  corpse.** A claim attaches on `UNIT_SPELLCAST_START` (never on click) and goes out as
  `RCLAIM`; a cast that dies frees it (`RFREE`); the landing takes it (`RDONE`). Other people's
  cast bars are read too, so rezzers *without* the addon still claim their target - and the
  corpse hears "X is rezzing you - don't release" once.
- **Never in a fight.** The button is not on screen in combat (a secure state driver hides it
  the moment a pull starts) and out of combat only while there is something to do - a corpse, a
  hurt player, a drink. The rest of the time it is not there to be misclicked.
- **Rez me first.** For everyone else the fifth button is on screen only while they are dead:
  click it and you go to the front of the rez line (several askers in the order they asked),
  and the next rezzer to click gets you - the innervate model. Same as `/inn rez`. It closes on
  its own when you stand up.
- **Wipe protection** in the tooltip and `/inn rezzers`: Reincarnation (only with an Ankh in
  the bag and off cooldown), Divine Intervention, a Soulstone on somebody who can rez. Carried
  in the HELLO as `REZ=RS`.
- Heals: sized from the spellbook tooltip plus healing power x cast time / 3.5 x the class
  talent; inbound heals from others (the larger of LibHealComm and `UnitGetIncomingHeals`, never
  the sum) are subtracted before anyone is picked; the group heal when the class has one and
  two or more are hurt; one hurt gets the smallest heal that covers them. `Libs/` (LibStub,
  CallbackHandler, LibHealComm-4.0) ship with the addon.
- Drink: Conjured Manna Biscuit first, then the 7200-mana tier, when the next cast is
  unaffordable. Rez scoreboard: `/inn rezscore`, the champion in the tooltip, cleared when you
  leave the group (option to keep). `/inn bind ALT-R` binds the button as an override binding
  (your saved keybinds are untouched); re-applied at login.
- **Protocol stays 4.** The rez traffic is new commands, which a 3.2.0 client silently ignores,
  and `REZ` in the kinds blob, which it skips. Section 50 runs a real 3.2.0 client
  (`dev/old-3.2/`) in the same raid and checks it sees everything but the rez.
- **A drummer's kit unrolls mid-fight.** The five drums beside the drum button are now secure
  item buttons of their own, bound out of combat to what you carry (`/use [combat] item:<id>`)
  and unrolled by secure enter/leave handlers, so they open in a fight. When the group asks for
  a drum the main button does not hold, that one pulses in the kit and clicking it drums it (the
  main button cannot be rebound until the fight ends). Out of a fight the same click sets it as
  the button's default and the kit rolls back in - it used to stay open. Askers keep the plain
  flyout.
- **Drink option, for anyone who uses mana** (off by default, Rez page): out of combat, with
  nothing to rez or heal, under 75% mana the button becomes a drink and blinks - Conjured Manna
  Biscuit, then Conjured Glacier Water, then Purified Draenic Water, whichever you carry. The
  threshold is a slider (`/inn set drinkAt 60`). A warrior never sees it; a corpse gets the
  "rez me first" button instead.
- Options: a **Rez** page. Window: the row is five buttons wide (152px). Mages-only mode hides
  the rez button with the others.
- Not carried over from BiS Rez: the scoreboard sync over the wire, the cast-mode / rank /
  `@` diagnostics knobs (macro text, bare name, `[target=]` - the ones that worked), and the
  combat-armed fallback heal (the button is simply not there in combat).
- Harness: `world.hp / hpmax / ghost / casting / bags / buffs / incoming / outOfRange /
  bonusHealing / talents / assist / book / binds`, `World:CastRez`, `World:StartCast`,
  `world.rootFor[name]` to load an older build for one client, secure state drivers that the
  world evaluates on a combat change, secure enter/leave snippets run as real Lua against a frame handle. A layout checker (`H.CheckLayout`) estimates every frame and text rectangle on an options page and fails the suite on any overlap or anything past its column - the guard for folding more addons into this one. 453 checks.

## 3.2.0

- **Mages only (Odiss mode).** The `M` in the title bar, the tick on the Window page, or
  `/inn mages`: the button row goes away, the grid is the mages and nothing else, and the window is
  exactly as wide as they are - one strip up to eight faces, then a second row. It grows and shrinks
  as mages join and leave. The title and `cfg` leave the bar too (options stay on the minimap
  button and `/inn config`). Calls, claims and a druid's face clicks work the same; a shaman or
  drummer in this mode is told the buttons are off when their group asks.
- Sizing is protected (the window holds the secure faces), so the shape follows in `Bind`: at once
  out of combat, at the end of the fight otherwise. Flipping M mid-fight saves and repaints the bar
  and the window waits. Whatever corner the window is anchored by stays put.
- **Fixed:** a closed window (alpha 0) left its title bar as an invisible drag strip with three
  invisible buttons on it. Closed means deaf now - at login too.
- Harness: frames remember their size, `ClearAllPoints` is guarded like `SetPoint`, font strings
  show and hide. 265 checks.

## 3.1.7

- **FojjiCore's pack shuffle.** Their update dropped the Brittney pack and prefixed the rest
  (`Community - ...`). Nothing here broke - the window, calls and combat never touch FojjiCore -
  but `Auto` used to reach for Brittney by name. Auto now takes the first installed pack that
  actually carries our lines, so it cannot rot when they rename again. A saved pack name still
  matches by substring (`ripley` finds `Community - Ripley`); a pack that is gone plays the
  built-in tones instead of nothing.

## 3.1.6

- **Drummers get the flyout too.** Hover your drum button and the five types unfold: the ones you
  carry are lit, the one your button uses has the violet edge, and the button itself wears that
  drum's letter (B/W/R/S/P). Click a carried one to make it the drum your button uses - now if out
  of combat, when the fight ends if not. A group's call for a specific drum still wins over your
  pick while it is open.
  (The flyout items stay plain buttons on purpose: a secure button in there would make the flyout
  protected and it could no longer open mid-fight.)

## 3.1.5

- One number, the small one. The cooldown swipe's own big countdown (Blizzard's and OmniCC's)
  is off on the four buttons; the corner tag is the timer.

## 3.1.4

- Exhaustion and Tinnitus show their time left on the greyed button - a rose corner timer and the
  swipe - on the asker's and on the provider's own button. The tooltip says "exhausted - 3:05 left".

## 3.1.3

- **The asker sees the cooldown too.** After a tide, a bloodlust or a drum, the button greyed
  only on the provider's screen; on everyone else's it still looked askable. Now when everyone
  in reach is on cooldown the button greys, shows the swipe and a corner timer, and an ask is
  refused with "Shammy back in 4:47" until somebody is up. Innervate the same: "next druid in".

## 3.1.2

- A shaman's or drummer's own button goes solid after they click it, like a claimed face - it
  pulsed until the cast landed, which read as "still waiting".
- Added the 25-man combat soak to the suite: five groups, three innervates to three druids, tide
  in one group and refused in another, raid-wide bloodlust seen by five shamans and locked by one,
  any-drum and a specific drum, the flyout, a debuff, a bag change and a respec - all in combat, on
  a client that drops secure writes. No protected call.

## 3.1.1

- **Bloodlust is raid-wide.** Every shaman with the addon sees the call and their button pulses;
  the first to click locks the others out. One bloodlust call for the whole raid at a time.
  (Mana Tide and Drums stay group-scoped - they only reach the caster's own group.)
- The drum flyout unfolds upward by default; Options > Window > Drums lets you pick up or down.

## 3.1.0

- **Bloodlust and Drums**, two more icons in the row. Same shape as Mana Tide: the button is lit
  when someone in *your* group has it (any shaman for Bloodlust; anyone carrying drums, found by
  name in their bags, Greater or normal), click to ask, their button pulses, their click uses it,
  the combat log closes it. Bloodlust and Drums can be asked for by any class.
- **Hover Drums for a specific one.** The five types unfold under the button (Battle, War,
  Restoration, Speed, Panic); the ones nobody in your group carries are greyed. A plain click asks
  for any drum. A specific call lights only drummers who have that type, and out of combat their
  button is bound to it; mid-fight it stays on their best drum and the tooltip says so.
- Bloodlust greys while you have **Exhaustion/Sated**; Drums grey while you have **Tinnitus** -
  asking would do nothing. A sated shaman's own button greys too.
- One player is several providers now (a talented shaman with drums is Tide + Bloodlust + Drums).
  Protocol 4: HELLO carries the list.
- `/inn lust`, `/inn drums`, `/inn drums restoration`.

## 3.0.2

- Options: the Calls and Window pages are two columns now, so nothing runs off the bottom of the
  window; pages clip to the window either way.

## 3.0.1

- **Half the screen space.** The window is compact by design now, not by scaling: the two spell
  buttons are 26px icons side by side (Mana Tide, then Innervate) with no text - the tooltip
  carries the words, a one-glyph corner tag carries the state (`?` asked, `*` on its way, `!` your
  group wants the totem, a timer on cooldown). Faces are 20px. About 150px wide for a raid.
- The body is 1% opaque - only the title bar (50%), the icons and the faces are drawn on your
  screen. `/inn scale` still works on top of that.

## 3.0.0

A rewrite. The 2.x design had five windows, an assignment board, a whisper bridge and a queue
that decided for the druids. Most of what went wrong lived in those. 3.0 is one window, the same
on every screen, and people decide.

- **One window, everyone sees it.** Mana Tide on top, Innervate under it, and a grid of faces:
  everyone with the addon who uses mana, in class order. Fojji-flat on the BiS violet palette.
- **Ask by clicking.** Innervate is lit when a druid with the addon is in the raid or party;
  Mana Tide when a shaman with the talent is in your group (that shaman's button is the totem
  itself and lights when the group asks). Greyed with the reason otherwise. Right-click withdraws.
- **The first click locks the rest out.** A caller's face pulses violet on every screen. A druid
  clicks it to cast; that face greys for every other druid immediately, the rest keep pulsing. A
  claim that has not landed in 8s pulses again for everyone. The combat log closes it.
- **Gone:** assignments and the assignment window, the whisper bridge (non-addon players are no
  longer part of it), the cooldown board, the separate druid panel and request button, role
  learning from the combat log, the `_`/`x` chrome floating over five windows.
- **Kept, because it worked:** faces bound before the pull by player *name* (raid slots renumber
  mid-fight), nothing protected touched during a fight, the window never shown/hidden/moved/
  rescaled in combat, the demo, the minimap button, the options window.
- **Options:** scale, lock, sound, FojjiCore voice packs (Auto = Brittney), how long a call lives,
  auto-cancel line, which classes may call, flat or 3D portraits.
- Protocol 3. A 2.x client is told, once, that it cannot see 3.0 calls.
- 2.x settings that still mean something carry over (sound, half size -> scale 0.5, classes).

Found by the pre-release audit and fixed before this shipped: a zone-in reads the roster as
empty for a moment and used to wipe the list of who has the addon - mages and priests fell off
every grid for the night, because only druids re-announce themselves; a cross-realm face fell
back to a raid slot binding; a throw inside the window build left a silent half-boot; a
closed window's tooltip catchers came back on the next roster change; the mana bar was a full
wash over healthy faces; `/inn reset` mid-fight un-hid a window that ignored every click.

147 offline checks.

## Earlier (2.x)


## 2.1.1

- **Fixed: the addon would not draw at all.** Five files had been converted to read colours from
  `NS.T` and nothing defined it, so the first frame that tried to paint threw on a nil. `NS.T`
  now lives in `Core/Util.lua`: it is `BiSTheme` when that addon is installed and the identical
  palette inline when it is not, resolved on first use so load order cannot matter.
- The squares now wear the BiS palette the demo text has been promising: **violet** is yours to
  cast, gold is yours but on cooldown, teal is another druid's, and idle is a plain dark edge.
- The options window reads the same `NS.T`, so there is one palette in the addon rather than two.

## 2.1.0

- **An options window** - `/inn config`, the `cfg` tab on any window, or ctrl-right-click the
  minimap button. Four tabs: Requests, Providers, Windows, Raid.
  - Flat FojjiCore-style panel on the BiS violet palette: no Blizzard templates and no backdrop
    art, every surface a plain colour a shade lighter as it comes forward, borders four 1px
    lines, hand-built checkboxes, sliders, segments and buttons. Reads `BiSTheme` when it is
    installed and falls back to the same values inline when it is not.
  - Every control writes the same saved variable the slash commands already write - and where a
    command owns the toggle (`/inn grid`, `/inn small`, `/inn minimap`, `/inn bar`) the control
    calls that command's own function rather than setting the key itself, so the two can never
    drift apart.
  - Sliders clamp to the same bounds `/inn set` uses.
- The harness now refuses a `SetColorTexture` call that is not given three numbers. The
  truncating `cond and rgba(...) or shade(...)` idiom is a live client crash that takes the whole
  window with it; it is now a headless test failure instead. Verified by reintroducing it.

## 2.0.4

- **Fixed: a request made above 70% mana was cancelled a fraction of a second after you clicked.**
  Auto-cancel compared your mana against a fixed number, so anyone who asked at, say, 85% had
  their request killed by the very next tick - it looked like the button did nothing. It now
  measures against what you had when you asked: you have to actually gain mana (15 points, and
  past the 70% line) before it gives up on your behalf. If you clicked, you meant it.
- The shaman's drag grip moved to the left edge of the button - above the icon is where the panel
  title and its `_` / `x` tabs live, and the grip was sitting on top of them.

## 2.0.3

- **Fixed: closing the squares left the portraits floating on screen.** A 3D model frame does not
  inherit its parent's alpha - a WoW quirk - and the grid is faded rather than hidden, because
  hiding it mid-fight is a protected call. The faces are now shown and hidden by hand, and come
  back exactly as they were when you reopen it. Same for a grid that starts closed after a reload.

## 2.0.2

- **A shaman can move their Mana Tide button.** It sits on its own most of the time - the panel
  around it is hidden whenever nobody is asking - so there was nothing to grab. It now has a small
  blue grip bar just above it: drag that to move it, out of combat. The button itself deliberately
  is not the handle, because a drag on a secure button eats the click that casts.
- The grip carries its own `_` and `x` tabs, since a shaman rarely sees the panel that used to
  hold them.

## 2.0.1

- **Fixed: a shaman's Mana Tide button disappeared.** A 2.0.0 change meant to stop the button
  floating in space when you close the panel with the `x` also fired in the ordinary "nobody is
  asking right now" case - which is exactly when the button is supposed to be sitting there
  waiting. Nothing ever put it back, so it was gone for the session, and `/inn reset` re-hid it
  on the next refresh. It is only hidden now when the panel was actually closed.

## 2.0.0

Five independent audits before the first live raid. Sixteen defects worth fixing, three of them
capable of costing a cooldown in the middle of a fight.

**The one that mattered most.** A square was bound to a raid slot (`raid7`), and raid slots
renumber the instant anybody leaves the raid - a death and release, a kick, a disconnect. The
binding can only be rewritten out of combat, so from that moment a square showed one player's
face, pulsed green for that player, and innervated whoever had inherited their slot. Squares are
now bound to the **player's name**, which never moves, with the raid slot kept only for the mana
bar and re-resolved on every roster change. Verified against a slot shift mid-fight.

**No secure attribute is written during a fight any more.** The druid panel's rows have been a
display since 1.8.0 - the squares do the casting - but they were still writing unit attributes to
a protected frame several times a second, all fight, on a client that refuses them. The rows now
blank themselves at the pull and repopulate when it ends.

**Half size no longer walks off the screen.** Saved window offsets are already in the scaled
frame's own units, so re-scaling them at login doubled them - and doubled them again on every
reload, permanently, until the window was jammed against the screen edge.

Also fixed:

- With only two non-addon druids, a request would bounce between them in total silence after the
  second hop and expire with nobody told anything. One whisper per person per escalation now,
  not one per person for all time.
- The requester is told once per change, capped - not once per escalation hop.
- `inn` and `oom` were matched anywhere in a whisper, so "beginning now" and "zoom in on the
  boss" were requests. Word boundaries, and long sentences are ignored.
- The assignment board is sent in numbered pieces and only applied whole. Past about eight
  assignments it overflowed the client's 255-byte message limit and was either dropped or applied
  truncated - silently deleting assignments on everyone else's client.
- `DONE` and `CANCEL` are accepted only from the people actually involved; a short `ASSIGN` can
  no longer unassign every mirror in the raid.
- A druid who dies or disconnects while on the hook hands the request on instead of holding it
  until it expires.
- A zone-in no longer wipes the list of who is running the addon (which whispered plain text at
  people who had the addon) or prunes half the assignment board.
- `/inn demo` no longer builds panel rows wired to the real spell - a shaman's demo could drop a
  real Mana Tide. Stopping a demo mid-fight is deferred instead of leaving three squares that
  look normal and cast nothing. A solo demo is visible now, which is the point of it.
- Role learning does the cheap test first: it was walking the whole roster for every combat log
  line, thousands a second on a big pull. Melee damage and absorbs are counted now, and it takes
  a lot more than one trash pull to be judged dps.
- Empty squares are parked off the grid and take no clicks; a hidden grid's squares go deaf.
- `/inn reset` - one command that reopens everything and puts every window back.
  `/inn show` and `/inn bar` also un-close what the `x` closed.
- `/inn grid` refuses mid-fight rather than leaving squares that look live and click dead.
- Cooldown broadcasts go out on the transition, not every two seconds for six minutes.
- A Mana Tide in your group no longer blocks you from asking for an innervate.
- Removed the dead pre-bound fallback and the chat line that claimed the addon had switched to it.
- Dropped the unused per-character SavedVariables file; added a LICENSE.

293 offline checks, up from 246.

## 1.9.3

- **A minimap button**, wearing the Innervate icon. Drag it anywhere around the ring.
  - left: the innervate squares (a druid) or the request button (everyone else)
  - right: the raid cooldown board
  - shift-left: the assignment window
  - shift-right: half size, and back
  - ctrl-left: the druid panel (who is asking)
  - middle: `/inn status` in chat
  - `/inn minimap` hides the button itself.
- **An `x` on every window**, beside the `_`. Closing sticks between sessions, and the minimap
  button is how anything comes back.
- Closing the squares now also stops them taking clicks. They were only ever faded to alpha 0
  (hiding them in combat is a protected call) and an invisible button still catches a click -
  which is a wasted innervate, the exact thing this addon exists to prevent. The mouse is turned
  off out of combat, so a grid closed mid-fight goes properly deaf the moment the fight ends.
- Fixed: `/inn grid` hiding the squares did not survive the next refresh - `Grid:Update` painted
  the alpha straight back on.

## 1.9.2

- **A `_` tab on every window.** Top-right corner of the druid panel, the innervate squares, the
  cooldown board, the assignment window and the mage's request button. Click it and the whole
  addon renders at half size; click the `+` it turns into to go back. `/inn small` does the same.
- The choice is remembered between sessions, and a window keeps the screen position it had - the
  offsets are rescaled with the frame so nothing drifts toward the middle.
- Clicking it mid-fight is safe: `SetScale` on the squares or the druid panel is a protected call,
  so those two are held until the fight ends (the addon says so) while the plain windows shrink
  immediately.

## 1.9.1

- **The state is the outline now.** Nothing is painted over the portrait: a green pulsing border
  means yours to cast, orange means yours but on cooldown, yellow means another druid has it, and
  a plain dark edge is idle. Squares without a portrait still fall back to a solid colour.
- **Healer detection from the combat log.** TBC has no spec API, so the addon watches who actually
  casts heals on other people and who only deals damage. Evidence accumulates across the whole
  session and persists between sessions, so one quiet fight - or being afk at the pull - proves
  nothing.
  - Nobody is ever unbound: a player with no evidence keeps a full square, and even a confirmed
    dps keeps a working one. What the guess changes is prominence - confirmed healers and mages
    sort first, confirmed dps fade to the back until they actually ask, at which point their
    square lights up like anyone else's.
  - The layout is only ever rebuilt **after** a fight ends, so learning can never cause a
    protected call mid-combat.
  - `/inn roles` prints what it thinks and why (heal and damage counts).
    `/inn roles <name> healer|dps|clear` overrides it by hand.

## 1.9.0

- **Faces on the squares.** Each grid square now shows that player's animated 3D portrait, with
  the flat 2D portrait underneath as a fallback for anyone the client will not model (out of
  range, not loaded). Squares grew to 42px to fit a face.
- The state colour is now a translucent wash over the portrait rather than a solid block: green
  wash = yours to cast, yellow = another druid has it, plain darkened = idle. The mana bar and the
  glow sit above the model.
- `/inn portraits` turns the 3D models off if you would rather have flat colour squares (or want
  the frames back).
- Portraits are re-seated a couple of seconds after a zone change, which is when models tend to
  come back blank.

## 1.8.1

- **`/inn demo`** - see the druid's side without needing a druid. It pretends you are a druid with
  two mages and a healer asking: two squares light green (yours to cast) and one turns yellow
  (another druid has it). Nothing leaves your client - no addon messages, no whispers - and the
  squares are wired to an empty macro, so clicking one prints a line instead of casting anything.
  It works in combat too, which makes it a way to check that clicks register mid-fight.
- Demo requests are exempt from the housekeeping tick, so they do not expire while you look at them.

## 1.8.0 - the grid

Druids now get a Decursive-style grid: **one small square per mage and healer in the raid**.

- Each square is bound to its player **once, out of combat**. In a fight the addon only changes
  colour, alpha and a mana bar - all textures, all legal at any time. There are no attribute
  writes and no show/hide, so it does not matter whether this client allows them.
- The square that lights up green is the one to click, and it was already pointing at that player
  before the pull. Two people asking at once means two lit squares, not a queue of one.
- Idle squares show class colour dimmed with a mana bar, so it doubles as an at-a-glance mana
  readout for the people you cover. You can innervate anyone by clicking their square at any time.
- A square turns dull yellow when another druid has that request, and everything greys out while
  your innervate is down.
- Roster changes mid-fight cannot mis-aim a square: bindings are only rewritten out of combat, and
  the grid re-aims itself the moment the fight ends.
- `/inn grid` shows or hides it. Drag to move (out of combat).

Mana Tide shamans keep their single self-cast button, which has the same property for the same
reason: the totem needs no target.

The old pre-bound fallback pool is gone - the grid replaces it, and it is not a fallback.

## 1.7.2

- **`BiSInnervateFrame:Hide()` blocked in combat, again.** Moving the cast buttons out of the panel
  was only half of it: they were still *anchored* to it, and the client protects a frame that a
  secure frame is anchored to just as it protects a parent — hiding an anchor moves what depends on
  it. The header now owns its own position and the panel anchors to the header, so the dependency
  points insecure → secure and never back. The offline harness models both rules now and reproduces
  the exact error.
- **Mana Tide shamans no longer touch the secure machinery at all.** The totem lands where the
  shaman stands, so the button never needs a target: it now exists from login, always points at the
  caster, and only its artwork changes when someone asks. Immune to the write-blocking this client
  does, which is why the shaman saw nothing during the fight.
- `/inn diag` prints everything worth knowing when something looks wrong in a raid.

## 1.7.1

- **The 90% button setting finally applies.** v1.6.0 stamped the database as migrated while
  leaving `showAt` at 35, so the migration could never run again — the buttons kept appearing at
  35% on characters that had logged in under that build. A v3 migration moves anyone still below
  90 up to it, and says so in chat once.
- **Clients that block secure writes in combat are remembered.** Instead of rediscovering it every
  fight, the addon notes it in its settings and goes straight to the pre-bound buttons — a primary
  row it cannot update in combat is a row that could cast on the wrong player.

## 1.7.0 — release candidate

First public release.

### Fixed (pre-release audit + live testing)

- **Blocked action in combat.** The cast buttons were children of the panel, which made the
  panel itself protected — hiding it mid-fight produced
  `ADDON_ACTION_BLOCKED: BiSInnervateFrame:Hide()`. The secure buttons now hang off UIParent
  and are only anchored to the panel, so the panel is an ordinary frame again.
- **Loading during combat killed the addon for the session.** Secure frames cannot be created
  in combat; the failure was swallowed and never retried. It now says so and finishes the
  moment the fight ends.
- **One provider could hold two requests.** A standing assignment (or a volunteer takeover)
  skipped the "already busy" check, so one druid could get two live buttons for one cooldown.
- **A claim during the handover blackout stranded the request** — no ASSIGN was broadcast, and
  every client sat with no live button until the request expired.
- **A disconnected requester left a button glowing all raid.** Only the owner expired requests,
  so mirrors kept them forever. Every client now drops a request whose owner is gone.
- **A provider on cooldown still got a castable row**, and clicking it pushed the escalation
  out by another 8 seconds. Cooldown rows are inert now, and a click no longer counts as a cast
  — the actual cast event does.
- **Fallback mode** (clients that block secure writes in combat): now verifies the unit that
  landed rather than just the row count, refuses to light a button whose binding went stale
  after a roster change, handles more than one request, blanks stale primary rows, and re-tests
  each fight instead of latching for the session.
- **Whisper spam.** Addon users are recognised from any addon-channel traffic, not just their
  login HELLO. One whisper per person per request. No escalation at all when nobody else could
  take it. Stand-downs are retried instead of being dropped by the send throttle.
- **Assignment board.** The dropdown could assign the provider a row *used* to hold, since rows
  re-sort by mana. Only the actual raid leader hands out editing rights or answers a board
  request, a new leader republishes, and rights and assignments are dropped when people leave.
- **Duplicate requests** for the same non-addon player now resolve the same way on every client.
- `/inn set` values are bounded (`escalate 0` turned the addon channel into a firehose).
- `/inn cancel` clears both an innervate and a mana tide request, and says so honestly.
- Mana tide no longer reports "innervate from X".
- Non-English clients: the spell name is no longer cached from a cold lookup at login, so the
  buttons cannot end up bound to an English spell name that does not exist.
- Warriors and rogues no longer build 45 secure buttons they can never use.
- Cooldown swipes are actually driven; leftover animations, unbounded tables and orphaned tide
  riders cleaned up.
