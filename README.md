# Robau Mod Suite

A small collection of quality-of-life addons for **World of Warcraft: Forever**, bundled as one addon with one settings window and one minimap icon.

| Module | What it does |
|---|---|
| **Ksenofob** | Hides chat written in German, French or Russian, and messages from players with Cyrillic (or other non-Latin) nicknames. |
| **LFG Message** | A saved message under the Looking For Group window and a **Send PM** button on every group. |
| **Shaman Toolkit** | A draggable totem toolbox (click to drop a totem, no action bar space needed) and a pulsing weapon imbue alert. |
| **LazyFisher** | One-key fishing, a toolbox with lure handling, a line progress bar and a safety warning. Includes **Fishing Stats**. |

All modules share one look (dark teal panels, thin aqua border) and one settings window, so you do not need to remember chat commands.

> Built for the Forever client (`## Interface: 16001`) while it is still changing, so some features rely on assumptions about the client. See [Known limitations](#known-limitations).

---

## Install

1. Download this repository (Code > Download ZIP) or clone it.
2. Copy the **`RobauModSuite`** folder into your Forever AddOns folder:

   ```
   World of Warcraft\_forever_\Interface\AddOns\RobauModSuite
   ```

   You should end up with `AddOns\RobauModSuite\RobauModSuite.toc`, not a nested `RobauModSuite\RobauModSuite\...` folder.
3. Restart the game completely (`/reload` is not enough for a new addon).
4. On the character select screen open **Addons** and make sure *Robau Mod Suite* is enabled. If it shows as out of date, tick **Load out of date AddOns**.

The folder name for Forever may change after launch. Check your own install if the path above does not exist.

---

## Using it

- **Minimap icon**: left click opens the settings window, drag to move it. The icon can be hidden in the Overview tab or with `/robau minimap`.
- **Settings window**: `/robau`. Pick a module in the list on the left. Every setting is in the window.
- The old per-module commands still work (see each module below).

The window has six tabs: *Overview*, *Ksenofob*, *LFG Message*, *Shaman Toolkit*, *LazyFisher* and *Fishing Stats*.

---

## Ksenofob

Hides chat messages written in a language you do not want to read.

- Pick any of **German, French, Russian**. Language is guessed from common words that are not English, plus characters such as `ä ö ü ß é è`. Transliterated Russian words (`privet`, `spasibo`, ...) are caught too.
- **Any Cyrillic text counts as Russian** (optional).
- **Hide players with Cyrillic nicknames**, and optionally other non-Latin names (Chinese, Japanese, Korean, Arabic, Hebrew, Greek).
- Choose where it filters: say/yell/emotes/channels, whispers, party/raid/instance, guild/officer.
- **Sensitivity** 1 to 4: how many word matches a message needs before it is hidden. 1 is aggressive (more false hits), 4 is careful.
- A **counter** shows messages blocked this session and in total.
- Your own messages are never blocked. Messages the game hides from addons ("secret values") are passed through.

Commands: `/xeno` (opens the tab), `/xeno toggle`, `/xeno stats`, `/xeno de|fr|ru`, `/xeno test <text>` (tells you how a text is classified).

The word lists are in `RobauModSuite/Ksenofob/Words.lua` and are easy to edit.

---

## LFG Message

Adds two things to the **Looking For Group** window:

- A **message box** under the window. The text is saved between sessions (255 characters, the game limit).
- A **Send PM** button on every group that whispers your message to the group leader.

After you send a message, that leader's button changes to **Sent 23s** (then `Sent 2m`) for a time you choose in the settings (1 to 60 minutes, default 1). Clicking it again does nothing unless you hold **Shift**, so you cannot spam the same person by accident.

Whispers are only sent when you click. Both the box and the buttons can be switched off in the settings.

Command: `/lfgmsg status` (debug), `/lfgmsg frame` (prints the frame under the mouse, useful if the Forever UI changes).

---

## Shaman Toolkit

For shamans only (it does nothing on other classes).

**Totem toolbox**
- A small draggable window with one row per element (earth, fire, water, air) plus Totemic Call/Recall. Click a button to drop that totem.
- Only totems you know are shown. The button casts by spell name, so it uses the highest rank you know.
- Active totems show a **number** (seconds left, or minutes for long totems) and an optional clock swipe. The number turns gold under 15 s and red under 5 s.
- Settings: show/hide, lock position, number on/off, swipe on/off, size, spacing, reset positions.

**Weapon imbue alert**
- A pulsing alert when your weapon has no imbue (Rockbiter, Flametongue, ...).
- Click the alert to cast your **default imbue**, chosen in the settings (or "Auto", the best you know).
- The alert is hidden while a **fishing pole** is in your hand, and while dead or mounted. Optionally it also warns about a missing off-hand imbue.

Commands: `/rst` (opens the tab), `/rst dump` (lists the totems and imbues found in your spellbook), `/rst add <spell name> <earth|fire|water|air|imbue>` (add a spell the built-in list does not know).

---

## LazyFisher

Fishing with less clicking. **Every cast and every pull still needs your key press or click.** It does not automate fishing, and it never will.

**One key for everything**
- Set a key in the settings (click the button, press a key). While fishing mode is **on**, that key casts your line, and once the line is in the water the same key pulls in the bobber (the game's "interact with target").
- The key is only taken over **while fishing mode is on**. It is a temporary override binding and does not touch your saved key bindings. Switch the mode off and the key goes back to normal. A crash or restart also clears it.
- While fishing: auto loot, louder effects and quiet music (your own settings are restored when you switch off).

**Toolbox**
- ON/OFF switch, the key shown on a chip, a **lure** button, and a close button.
- **Lure button**: click to apply a lure to your pole. It never applies a new lure while one is still active, and it needs a fishing pole in your main hand.
- **Arrow above the lure**: a list of the lures you carry. Click one to use it.
- **Mode chip** (right side): shows which lure is chosen and whether auto-apply is on. Click it to turn on **apply when it expires** (your key applies a new lure first, then casts) and to pick **strong** or **weak** automatic lure.
- **Lure bar**: time left on the active lure.
- **Progress bar** (bottom): drains while the line is in the water. You can also click it to cast.

**Safety**
- If fishing mode is on and you have **no fishing pole in your hand**, a warning appears with a **Switch LazyFisher off** button.
- If a pole is in your bags, pressing the key (or clicking the bar) **equips it** first.
- If you have no pole at all, the key is released so it works normally again.

**Fishing Stats** tab: casts, catches, success rate, fish per hour and time with the line out, for this session and all time, plus a list of what you caught with item quality colours.

Commands: `/lazyfish` (opens the tab), `/lazyfish on`, `/lazyfish off`, `/lazyfish toggle`, `/lazyfish show`.

---

## Known limitations

This is a hobby project written for a client that is still changing. Some things are assumptions:

- **Spell and item names** (totems, imbues, lures, "Fishing") are taken from classic WoW. If Forever uses other names, a totem or lure will not show up. Use `/rst dump` to see what was found, `/rst add` to add a spell, or type a lure name in the LazyFisher settings.
- **Pulling in the bobber** with the key relies on the game's "interact with target" (`INTERACTTARGET`) working on fishing bobbers.
- **Bite detection** is not possible for addons, so LazyFisher cannot tell you when a fish bites. Louder effects help you hear it.
- **Fishing Stats** counts catches from the loot window (`IsFishingLoot`).
- The game hides some values from addons ("secret values", for example some names). Where that happens the addon skips the action instead of guessing.
- Addons cannot send messages to other players **inside instances**, so Send PM will not work there.
- Forever builds change often, so any of the above may need a small fix after a client update.

---

## Saved variables

`RobauModSuiteDB`, `KsenofobDB`, `LFGMsgDB`, `RobauShamanToolkitDB`, `LazyFisherDB` (in `WTF\Account\<account>\SavedVariables\RobauModSuite.lua`).

## Project layout

```
RobauModSuite/
  RobauModSuite.toc        addon manifest (Interface 16001)
  Suite.lua                shared UI kit, settings window, minimap icon, /robau
  Ksenofob/                chat language and nickname filter
  LFGMsg/                  LFG message box and Send PM
  ShamanToolkit/           totem toolbox and imbue alert
  LazyFisher/              one-key fishing, toolbox, stats
```

Each module registers its own tab with `ns.Hub.Register(...)` and builds its settings from the helpers in `ns.UI` (`Check`, `Button`, `Stepper`, `EditBox`, ...), which keeps the look consistent.

## Contributing

Issues and pull requests are welcome, especially reports of spell, item or frame names that differ on Forever.
