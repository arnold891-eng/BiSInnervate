# BiS Innervate 3.3

One window for the whole raid. Call for **Innervate** or **Mana Tide**; the druids see your face
pulse and the first one to click it locks the rest out. No voice chat, no triple innervates.

Only people running the addon take part. No whispers, no assignments, no separate windows.

## The window

Five icons: **Mana Tide**, **Innervate**, **Bloodlust**, **Drums**, **Rez**. Tide and Drums come from
somebody in *your* group; Bloodlust from any shaman with the addon in the raid (first to click
answers); Innervate from any druid with the addon. Hover Drums for the five types. Bloodlust greys while you are Exhausted, Drums while
you have Tinnitus.

**Rez** (folded in from BiS Rez) is a healer's one button: click to rez the best corpse, else heal
whoever is worst off, else drink. Rezzers first, then mana, then everyone else. The moment one
rezzer starts a cast, every other rezzer's button moves to the next corpse. A druid's Rebirth is
never spent by it. It is only on screen out of combat with something to do. For everyone else
the button appears only while they are dead: click it to go to the front of the rez line - the
next rezzer to click gets you. Option: any mana user can have it turn into a blinking drink
button under 75% mana (biscuit, then glacier water, then draenic water).

Everybody sees the same thing:

```
 BiS Innervate                cfg  _  x
 [~]  Mana Tide     Healer2 ready          <- ask (or drop it, if you are the shaman)
 [~]  Innervate     2 druids up           <- ask
 [face][face][face][face][face][face]     <- everyone with the addon who uses mana
 [face][face]
```

- **Mana Tide** is lit when a shaman with the talent is in *your* group. Click to ask. If you are
  that shaman, this is your totem: it lights up when your group asks and clicking it drops it.
- **Innervate** is lit when a druid with the addon is in the raid or party. Click to ask.
  Right-click either button to withdraw.
- **The faces** are everyone with the addon who uses mana, in class order. A caller's face pulses
  violet on every screen. A druid clicks a pulsing face to innervate that player - the click *is*
  the cast. That face greys out for every other druid on the spot; the rest keep pulsing.
- A face that was clicked but not innervated within 8 seconds pulses again for everyone.
- The combat log closes the call when the innervate lands. The caller hears it.

Warriors and rogues see the window too, with both buttons greyed - so they can see who is asking.

## Combat

The faces are secure buttons bound to each player **by name** before the pull and never touched
during a fight. That is what lets a click cast in combat, and it has two consequences you will
notice: somebody who joins the raid mid-fight gets a face when the fight ends, and the window
cannot be opened, closed, moved or rescaled until then either (the addon says so if you try).

## Commands

```
/inn               ask for an innervate        /inn tide        ask your group's shaman
/inn lust          ask for bloodlust           /inn drums [type]  ask for drums (battle, war, restoration, speed, panic)
/inn cancel        withdraw                    /inn show|hide   the window
/inn scale <n>     0.5 - 2                     /inn lock        no dragging
/inn config        the options window          /inn minimap     the minimap button
/inn sound         on / off                    /inn voice       list | <pack> | off | auto | test
/inn faces         flat or 3D portraits        /inn reset       put the window back
/inn status        who has the addon, cooldowns, open calls
/inn mages         mages only (Odiss mode): just the mage faces, no buttons, the window fits them
/inn healer        healer mode: just the rez / heal / drink button, nothing else
/inn rez           dead: rez me first. A healer: what the button would do right now
/inn rezzers       who can rez, ready or casting, and the wipe protection up
/inn rezlist       the corpses in the order the button takes them
/inn rezheals      the heals it knows and their sizes, and the drink it found
/inn rezscore      the rez scoreboard        /inn rezreset    clear it
/inn bind ALT-R    bind the rez button (override binding)   /inn unbind
/inn demo          see the druid's side without a druid (fake callers, harmless clicks)
```

`cfg` in the window's corner, or right-click the minimap button, opens the options: scale,
sound, FojjiCore voice packs, how long a call lives, which classes may call, the rez button.

## Voice packs

If [FojjiCore](https://www.curseforge.com/wow/addons/fojjicore) and its voice packs are installed,
the alerts are spoken. `Auto` picks the first installed pack that has the lines; `/inn voice list` shows what you have. Nothing is
copied - lines play from FojjiCore's own folder.

## Install

Copy `BiSInnervate` to `World of Warcraft/_anniversary_/Interface/AddOns/` and `/reload`.
Optional: `BiSTheme` for the shared palette, `FojjiCore` for voices.

## Development

`lua5.1 dev/tests.lua` from the addon folder runs the offline suite: several independent clients
in their own Lua environments with addon messages and combat-log events routed between them, a
combat-lockdown model that includes protection propagation, and strict texture stubs that turn
the classic `SetColorTexture` truncation crash into a test failure. `H.CheckLayout(page, frame)` estimates every rectangle on an options page (anchors, sizes, text width from the font size) and reports overlaps and overflow - section 51 runs it on every page, so a merged-in options page cannot ship cut off.
