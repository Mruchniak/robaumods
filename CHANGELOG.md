# Changelog

## 1.5.4

- **Shaman Toolkit**: totem timers rewritten. In combat the game hides all totem data ("secret values"), so the addon now starts its own timer when you cast a totem and learns each totem's duration whenever the game shows it out of combat. A recast restarts the timer, and a totem update long after the cast ends it.
- **Shaman Toolkit**: a duration bar under each active totem replaces the cooldown-style sweep (the sweep is optional and now fills like a buff timer). Totems whose duration is not known yet show a dim full bar until learned.
- **Shaman Toolkit**: a debug recorder stores the raw totem data in `RobauShamanToolkitDB.debugLog` (last 80 events) to help diagnose client changes.

## 1.5.3

- **Shaman Toolkit**: totem timers keep working when the game hides totem names or times. The totem is matched by the button you clicked last in that element row and the game's own countdown numbers are used.
- **Shaman Toolkit**: new `/rst totems` command prints what the game returns for the four totem slots (for debugging).

## 1.5.2

- **LazyFisher**: if applying a lure is cancelled (for example by moving), the next key press tries to apply it again instead of casting the line. The "applying" lock now ends when the cast ends.

## 1.5.1

- **LazyFisher**: switching the mode on (minimap button, settings or command) always opens the toolbox again, also after it was closed with the x button.
- **LazyFisher**: the minimap button hides the toolbox when it switches the mode off.

## 1.5.0

- **LazyFisher**: closing the toolbox now also switches fishing mode off.
- **LazyFisher**: separate minimap ON/OFF button, green when on and red when off.
- **LazyFisher**: pulsing reminder when fishing mode is on but you walk, mount up, enter combat or stand idle. Click to switch off, right click to snooze.
- **LazyFisher**: if fishing mode is switched off during combat, the key is released right after combat.

## 1.4.0

First public release of the combined addon.

- **Suite**: one settings window with a module list, one minimap icon, shared teal look.
- **Ksenofob**: German, French and Russian chat filter, Cyrillic and non-Latin nickname filter, counters.
- **LFG Message**: saved message box under the LFG window, per-group Send PM, "Sent" state with a configurable time, Shift-click to resend.
- **Shaman Toolkit**: draggable totem toolbox with spacing and size options, seconds-left numbers and swipe on active totems, weapon imbue alert with a default imbue, hidden while a fishing pole is equipped.
- **LazyFisher**: one-key cast and pull, toolbox with ON/OFF, lure button with a safe apply (never over an active lure), lure picker, auto-apply on expiry with strong or weak choice, lure time bar, line progress bar, warning and auto-equip when no pole is in hand.
- **Fishing Stats**: session and all-time catches, success rate, fish per hour, catch list.
