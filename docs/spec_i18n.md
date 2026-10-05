# Milestone 8 specification: the i18n architecture

A complete, prescriptive specification. Every decision is already made here; the job is to
implement it. If something below is wrong for a reason discovered during the work, change
this file rather than working around it silently.

Source of the product intent: `plan_juego.md` §11 (languages, fonts, pipeline,
accessibility). This file is the implementation of it.

**Goal:** move every string a player can read out of the code, so a translator can work
without touching a script, and so a missing translation falls back to English instead of
showing a blank.

**State:** **COMPLETE** (2026-10-05). All 5 criteria in DoD verified. 9th battery registered and passing (11 OK / 0 FAIL). Pseudo-locale `en_XA` active and live-switching operational.

**Out of scope:** the 13 translations themselves (that is milestone 11, and they must happen
after the text is final). This milestone delivers English plus a pseudo-locale, and the
machinery for the rest.

---

## 0. Definition of done

1. `--i18n-check` reports `[I18N] RESULT: N OK / 0 FAIL` and is registered in
   `tools/run_batteries.ps1` as the 9th battery with `Gpu = $false`.
2. The pseudo-locale is selectable in-game and, with it active, **no text anywhere appears
   in plain English**. Anything that does is a string that was not extracted.
3. Switching language in the settings screen re-labels every visible screen **immediately**,
   without restarting and without leaving the screen.
4. The full gate is green: the 8 existing batteries plus the new one.
5. The built-in controls help panel, the pause menu, the settings screen, the controls
   screen and the main menu all read from the translation files.

---

## 1. Technology decisions (already made — do not re-litigate)

- **Use Godot's built-in translation system.** `TranslationServer` plus `tr()` plus
  CSV files imported as translations. Do not hand-roll a lookup table: the engine already
  handles locale negotiation, fallback and live switching.
- **CSV, not gettext.** One file, `res://locale/strings.csv`, first column `keys`, then one
  column per language. Reason: a translator can be handed a spreadsheet, and Godot imports
  it directly. Configure the import in the project so `strings.csv` generates a
  `Translation` per column.
- **English is the base and the fallback.** Set the project's
  `internationalization/locale/fallback` to `en` and keep the English column complete.
  Reason: a missing key then shows English, which is a bug you can live with, rather than a
  key name or an empty box.
- **Diagnostic output stays English.** Every `print("[PHYS] ...")`, every battery verdict and
  every log line is for developers and must NOT be translated. Do not add them to the CSV.

## 2. Key naming convention

`SCREEN_THING`, all capitals, underscores, grouped by screen. Examples:

```
MENU_CONTINUE          MENU_NEW_GAME          MENU_DELETE_SLOT
MENU_SLOTS_TITLE       MENU_SLOT_UNREADABLE   MENU_OVERWRITE_SLOT
HUD_MONEY              HUD_CLEARED            HUD_SNOW_REMOVED
HUD_TOOL_SHOVEL        HUD_TOOL_BLOWER        HUD_TOOL_SALT
HUD_WIPE_FACE          HUD_TITLE              HUD_VICTORY_TITLE
PAUSE_TITLE            PAUSE_RESUME           PAUSE_RESTART          PAUSE_QUIT_MENU
SETTINGS_TITLE         SETTINGS_VOLUME        SETTINGS_SENSITIVITY
SETTINGS_SHAKE         SETTINGS_INVERT        SETTINGS_FACE_SNOW
SETTINGS_LANGUAGE      SETTINGS_BACK          SETTINGS_RESET         SETTINGS_CONTROLS
CONTROLS_TITLE         CONTROLS_BACK          CONTROLS_RESET         CONTROLS_LISTENING
ACTION_MOVE_FORWARD    ACTION_MOVE_BACKWARD   ACTION_MOVE_LEFT       ACTION_MOVE_RIGHT
ACTION_SPRINT          ACTION_JUMP            ACTION_INTERACT
ACTION_TOOL_1          ACTION_TOOL_2          ACTION_TOOL_3
HELP_CONTROLS          (the whole help panel, one key with newlines)
```

**Absolute rule: never build a sentence from fragments.** Placeholders go inside whole
sentences, because word order differs between languages. `"%s %s"` glued together in code is
wrong; `HUD_TOOL_NAME` with two placeholders is right.

## 3. The inventory: every string to extract

This is what exists today. Treat it as a starting list and add anything the
pseudo-locale exposes.

### `scripts/hud.gd`
- `"Money: $%d"`, `"Cleared: %d%%"`, `"Snow removed: %.1f kg"`
- `"Tool: [1] Snow Shovel"`, `"Tool: [2] Motorized Snow Blower"`, `"Tool: [3] Thermal Salt Spreader"`
- `"Snow on your face - hold [E] to wipe it off"`
- The whole `CONTROLS_TEXT` help panel (~15 lines) — keep its line breaks in the translation
- `"Paused"`, `"Resume"`, `"Restart level"`, `"Quit to menu"`, `"Settings"`, `"Controls"`,
  `"Back"`, `"Reset"`, `"Reset controls"`, `"press a key or button"`
- `"Settings"` panel: `"Master volume"`, `"Mouse sensitivity"`, `"Screen shake"`,
  `"Invert look"`, `"Face snow clears by itself"`
- `"Controls"` panel: title, `"Back"`, `"Reset controls"`, plus the per-action names from
  `input_bindings.gd` (see below)

### `scripts/main_menu.gd`
- `"Continue"`, `"New Game"`, `"Delete Slot"`, `"Quit"`, `"Save slots"`,
  `"That slot could not be read."`, `"Overwrite slot %d?"`, the subtitle, `"Playground (dev)"`
  and its tooltip

### `scenes/main.tscn` and `scenes/main_menu.tscn`
- Text authored in the scene files (the HUD title `"SNOW IT TOGETHER - Entrance Path"`, the
  victory panel labels, the menu titles). **Decide one way and be consistent:** either remove
  the text from the scenes and set it in `_ready()` from keys, or keep it in the scene and
  overwrite it in `_ready()`. The first is cleaner; the second is a smaller diff.

### `scripts/input_bindings.gd`
- `action_label()` currently builds a readable name by replacing underscores. Replace it with
  a lookup: `ACTION_MOVE_FORWARD` and so on. A missing key must fall back to the raw action
  name rather than crashing.

### Not to extract
- Battery and diagnostic output (see §1).
- The `Playground` ledger block and hint panel: this is a **development scene**, never
  shipped. Leave it English, or extract it only if that is cheaper than special-casing it.

## 4. New files

### `scripts/localization_manager.gd`
Follow the conventions the other systems use: `extends RefCounted`, **no `class_name`**
(see §8), statics only, preloaded by callers.

Required API:
- `static func ensure_loaded() -> void` — load once per run, like `SettingsSystem`.
- `static func available_languages() -> Array` — `[{"code": "en", "label": "English"}, ...]`.
- `static func set_language(code: String) -> void` — `TranslationServer.set_locale(code)`,
  persist it through `SettingsSystem`, and notify listeners.
- `static func current_language() -> String`
- `static func language_column_key(code: String) -> String` — map `es` to the CSV column.

Add `language` to `scripts/settings_system.gd` (`"language": "en"` in the dictionary, with a
default of the OS locale if it is one we ship, otherwise `en`).

### `res://locale/strings.csv`
Two columns to begin with: `keys,en`. The pseudo-locale column is generated (see §6), not
hand-written.

### The pseudo-locale
A language code `en_XA` whose column is machine-generated from the English one:
- replace vowels with accented look-alikes and wrap the string in brackets
  (for example `[Tööl: Snöw Shovêl]`), so a leftover in plain English is obvious;
- **pad it to about 140 % of the original length** so the layout is stressed as well as the
  extraction. German and Finnish will be long; the pseudo-locale finds the clipping before a
  translator does.

Generate it with a script committed to the repository (`tools/make_pseudo_locale.ps1`), and
document that it must be re-run whenever the English column changes.

## 5. Screens that must refresh live

Add `func refresh_text() -> void` to each of these and call it when the language changes:
the HUD (money, cleared, snow removed, tool name, help panel), the pause menu, the settings
panel, the controls panel, and the main menu.

The settings screen gains a **Language** row: an `OptionButton` listing every entry from
`available_languages()` with each language named in its own language ("Español", "Deutsch",
"日本語"), the current one selected, and applying it immediately.

Keep the existing settings pattern: **write through on change and persist**, no Apply button.

The per-action labels in the controls screen come from `InputBindings` keys, so changing
language must rebuild or refresh those buttons too.

## 6. `--i18n-check`

A new battery, headless-safe (`Gpu = $false`), printing `[I18N] RESULT: N OK / M FAIL`. The
checks:

1. **Every key used in code exists in the CSV.** Collect `tr("...")` and `TranslationServer`
   lookups from `scripts/`; fail on any key missing from the English column.
2. **No dead keys.** Every CSV key is referenced somewhere in `scripts/`. Report the count;
   fail if it grows beyond zero.
3. **The CSV is well formed.** Every row has the same number of columns as the header, no
   empty English cell, no duplicate key.
4. **Language columns match English.** For each language column, report how many English keys
   it is missing. Do not fail on this: the translations do not exist yet. Print the table.
5. **A heuristic scan for unextracted text.** Find `.text = "..."` assignments in `scripts/`
   whose literal is longer than, say, 12 characters and is not `tr(`. **Warn, do not fail** —
   this heuristic has false positives (the diagnostics), and a check that cries wolf gets
   ignored. The pseudo-locale is the real test for this one.
6. **The pseudo-locale is complete.** Every English key has an `en_XA` entry, and every
   pseudo entry is longer than its English one.

## 7. Order of work

1. Add `res://locale/strings.csv` with the `keys,en` columns and the full inventory from §3.
   Configure the CSV import. Set the project fallback locale to `en`.
2. Write `localization_manager.gd` and add `language` to `settings_system.gd`.
3. Extract `main_menu.gd`. Verify by hand: switch to the pseudo-locale and confirm the menu
   is entirely in fake text.
4. Extract `hud.gd` (including the help panel and the pause, settings and controls screens).
5. Add `refresh_text()` everywhere and the Language row in settings; verify live switching
   without a restart.
6. Write `tools/make_pseudo_locale.ps1` and generate the `en_XA` column.
7. Write `--i18n-check`, register it in `tools/run_batteries.ps1` with `Gpu = $false`.
8. Add the font, if the pseudo-locale or a manual check shows missing glyphs. The default
   font does not cover CJK; a Noto Sans family (OFL) with the needed subsets is the expected
   choice. Set it as the project theme's default font.
9. Update `docs/pending_work.md`, `docs/roadmap.md` (mark item 8 done) and this file.

## 8. Environment traps (learned the hard way)

- **Do not use `class_name` for the new scripts.** It registers a global through the editor's
  class cache, and a command-line run before the cache knows the name fails to parse with
  "Identifier not declared" — which leaves the game unable to start. Use
  `const X = preload("res://scripts/x.gd")`. `session_mode.gd`, `settings_system.gd` and
  `input_bindings.gd` are the working examples.
- **Read a file before editing it.** The editor tool requires it; bulk text replacement while
  the editor is blocked invalidates that state and causes cascading failures.
- **PowerShell here is 5.1**: no `pwsh`, no `&` background operator, no inline `if`
  expressions, no ternary, and piping a `foreach` statement is a parse error.
- **Never kill the user's Godot editor process.**
- The `godot_ai` MCP addon exists but no MCP client tools reach the agent. Use the logs and
  `read_image` on the screenshots the diagnostics save.

## 9. Verification commands

```powershell
$godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$repo  = "C:\Users\MrSeb\.gemini\antigravity\scratch\snow_it_alone"

& $godot --headless --path $repo -- --i18n-check      # the new battery
& $godot --path $repo --quit-after 1200 -- --menu-shot  # renders the menu, saves a PNG
& "$repo\tools\run_batteries.ps1"                      # the whole gate, 9 batteries
```

`--menu-shot` writes `main_menu.png`; add an equivalent for the pseudo-locale run so the
before/after can be compared visually. The GPS of this milestone is the pseudo-locale
screenshot: a menu with any English left in it is a failure.

## 10. What NOT to do

- Do not translate diagnostic output, log lines or battery verdicts.
- Do not assemble sentences from fragments (§2).
- Do not hand-write the pseudo-locale column; generate it, or it will drift.
- Do not pull the real 13 translations forward. They must follow the final text
  (milestone 11), or every level added afterwards invalidates them.
- Do not add an Apply button to settings. The existing screen writes through on change; keep
  that, because it is the pattern players already have here.
