# BiS Rez

One button. Rezzes the right person -- and keeps the raid moving between rezzes.

BiS Rez scans your party or raid for dead members in range, ranks them by class
priority, and casts your class's max-rank resurrection on the best target. No
clicking through corpses, no guessing who's already covered.

## What it does

- **Smart target picking** — dead, connected, in range, not already being rezzed.
  Priority order: Priest > Paladin > Shaman > Druid > Mage > Hunter > Warlock >
  Warrior > Rogue.
- **Works on ungrouped players** — your current target counts as a candidate too.
- **No double rezzes** — two layers:
  - *Passive*: watches everyone's cast bar for a rez spell and reads their target.
    Works whether or not they have this addon.
  - *Active*: BiS Rez users broadcast their claim the moment the cast starts, so
    the target drops off everyone else's button immediately.
  - Claims release instantly on interrupt, failure, or a refused cast.
- **Rez leaderboard** — tally of who has rezzed the most, shown above the button.
  Ties display as ties. Clears automatically when you leave or change groups.
- **Drinks when it can't cast** — a rez or heal you can't afford turns the button
  into a drink instead. Prefers Conjured Manna Biscuit, then any 7200-mana drink.
- **Heals between rezzes** — when nobody needs a rez, the button heals whoever is
  worst off, counting heals other players already have in the air (LibHealComm)
  so it doesn't race an instant-caster to a target that will be full before your
  cast lands. Two or more hurt and your class has a group heal (Chain Heal, Circle
  of Healing), it uses that instead. Heal sizes are read from your own spellbook
  tooltips, so they follow your +healing gear. Successful heals stay out of chat;
  only errors get a line.
- **The icon shows what the click will do** — green border for rez, yellow for
  heal, blue for drink, greyed out when there's nothing to do. The tooltip also
  lists any corpses it skipped and why.
- **Still works in combat** — secure attributes freeze the moment combat starts,
  so heals go out as macro text whose conditionals resolve at click time:
  the chosen unit, then mouseover, then target, then you. A greyed idle button
  keeps the biggest heal armed behind that chain rather than doing nothing.
- **One window** — the button, the target name, the champion tally, every corpse
  in reach and every other rezzer running BiS Rez, in a single frame you drag by
  any part of it. Click a face to rez that one; claimed corpses grey out. The
  rezzer strip shows whether each one's spell is up.
- **Options window** — `/bisrez` with no arguments, or `/bisrez config`. Five
  tabs; every control is the same saved variable the slash commands set.

## Supported classes

| Class | Spell |
|---|---|
| Priest | Resurrection |
| Paladin | Redemption |
| Shaman | Ancestral Spirit |

Druids are deliberately absent. Rebirth is an hour of cooldown and the only
combat rez the raid has, so BiS Rez will never spend it — a druid gets the heal,
the drink, the corpse window and the rezzer list instead.


Other classes: the button hides itself.

## Installation

Drop the `BiSRez` folder into `Interface\AddOns\`. The button appears in the
centre of the screen — drag it where you like, then tick **Lock button position**
in the options panel.

Bind a key with `/bisrez bind ALT-R` (add `force` to override an existing binding),
and `/bisrez unbind` to clear it. This is an *override* binding: it sits on top of
your keybinds without editing them, and is re-applied at every login.

## Commands

| Command | Effect |
|---|---|
| `/bisrez` | Toggle the options window |
| `/bisrez config` | Open it (also `options`, `settings`) |
| `/bisrez help` | List all commands |
| `/bisrez list` | Show every candidate and why each was accepted or rejected |
| `/bisrez claims` | Show active rez claims and who holds them |
| `/bisrez score` | Full leaderboard |
| `/bisrez resetscore` | Clear the leaderboard |
| `/bisrez bind <KEY>` | Bind a key to the button |
| `/bisrez lock` / `unlock` | Lock or unlock the button position |
| `/bisrez heals` | List the heals it can cast and the drink it found |
| `/bisrez rescan` | Rebuild the heal list now |
| `/bisrez diag` | Dump spell resolution and secure attribute state |

## Options

- Lock button position
- Show / hide the button
- Append rank suffix to the cast
- `[@unit]` vs `[target=unit]` macro syntax
- Cast via spell attribute instead of macro text
- Show rez champion above the button
- Keep scores after leaving the group
- Only count guildmates on the leaderboard
- Drink when out of mana
- Heal the worst hurt when nobody needs a rez

## Notes

The passive detection reads the caster's current target. Someone rezzing through
a mouseover macro without a target is invisible to it until the rez lands.

Claims are advisory — they hide a target from your button, but nothing stops
anyone from hard-casting over you.

`dev/` holds an offline test harness: it mocks the WoW API, runs the addon on
real Lua 5.1 (the client's interpreter), fires every event and slash command,
and flags any accidental global. `lua5.1 dev/bisrez-regress.lua` runs the
regression suite.

Rezzing always takes priority: the button only heals or drinks when there is no
rezzable target. Heals and drinks are deliberately kept out of the claim system
and the leaderboard — only real rezzes count.

This client's spellbook exposes only the highest rank of each spell, so heal
choice is effectively small-heal vs big-heal rather than full downranking.

Heal sizes are estimated as `(base + healing power x cast time / 3.5) x talents`,
because the spellbook tooltip on this client contains no gear at all. Cast time is
read live, so haste is included. Talents are matched by English name; a non-English
client gets the untalented estimate. BiS Healing goes further and measures real
casts -- BiSRez only needs to choose between a small heal and a big one.

Inbound heals come from two places and the larger wins: LibHealComm-4.0 (ships
under `Libs/`, optional, only sees other HealComm users but is filtered by when
the heal lands) and the client's own `UnitGetIncomingHeals` (sees every healer,
but is not time-filtered). Delete `Libs/` and the native source carries it alone.
