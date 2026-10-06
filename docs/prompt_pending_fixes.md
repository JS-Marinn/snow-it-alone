# Prompt: fix the five open items in one pass

Hand this whole file to whoever picks up the work. It is self-contained.

---

You are working on **Snow It Alone** (working title "Snow It Together"), a co-op
snow-shovelling game in **Godot 4.7.2**, built by one programmer. Everything in the game —
code, comments, UI text and documentation — is in **English**. Your own replies may be in
whatever language you are asked in.

- **Repository:** `C:\Users\MrSeb\.gemini\antigravity\scratch\snow_it_alone`
- **Godot console executable:**
  `C:\Users\MrSeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- **Run pattern:** `& $godot --path $repo --quit-after 2400 -- --<flag>`

## Read these before touching anything

| File | Why |
|---|---|
| `docs/pending_work.md` | The running record of what is open. **Section 12 is task 1 below** and has the evidence. |
| `docs/spec_i18n.md` | The i18n architecture, decisions already made. Task 2 finishes it. |
| `docs/handoff_impact_flakiness.md` | A solved bug whose *history* still matters: disproved theories, and the environment traps. |
| `docs/roadmap.md` | The 17 ordered milestones. Task 5 corrects its markings. |
| `CONTRIBUTING.md` | Battery table and conventions. |

## Current state

- HEAD `9a1ae13`, working tree clean, local and remote in sync.
- `tools/run_batteries.ps1` runs the gate: `--save-roundtrip` (21), `--ball-shape` (8),
  `--movement-lab` (11), `--impact-lab` (18), `--impact-matrix` (28), `--phys-demo` (34),
  `--playground-check` (11), `--carve-quality` (diagnostic, FPS smoke check), plus
  `--i18n-check` headless.
- The terrain battery's FPS varies between 53 and 102 with machine load. **It is a smoke
  check, not a performance measurement.** Do not chase it.

## Five tasks, in this order. One commit each, pushed after each.

### Task 1 — diagnostics must not touch the player's real files

**This bug already bit the owner**: inverted mouse, jump moved from Space to J, volume at
0.33, and the menu in the pseudo-locale. All four values were written by the diagnostics
into the real preference files. They were deleted to fix the player; **the cause is still in
the code.** Evidence and analysis: `docs/pending_work.md` §12.

1. `scripts/settings_system.gd`: add `static var path: String = PATH`. Have `save()` and
   `load_from_disk()` use `path` instead of the constant.
2. `scripts/input_bindings.gd`: the same.
3. In `scripts/hud.gd`, every `--*-shot` diagnostic (`_run_pause_shot`,
   `_run_settings_shot`, `_run_rebind_shot`) must set both `path`s to scratch files
   (`user://scratch_settings.json`, `user://scratch_bindings.json`) **before it writes
   anything**, and delete both scratch files before quitting.
4. The pseudo-locale must never persist. `en_XA` must not be written to the settings file,
   and `available_languages()` must only offer it when `OS.is_debug_build()` is true — the
   same rule the Playground menu entry already follows.
5. **Acceptance test, mandatory.** Snapshot the bytes of the real `settings.json` and
   `bindings.json` before, run every `--*-shot` diagnostic, compare after: both must be
   **absent or byte-identical**. Implement it as a new battery `--diagnostics-harmless`
   (`Gpu = $false`) and register it in `tools/run_batteries.ps1`, so this can never come
   back silently.

Commit: `fix: diagnostics write to scratch files instead of the player's preferences`

### Task 2 — finish the i18n extraction

Already done: 96 keys in `locale/strings.csv` (`keys,en,en_XA`), `localization_manager.gd`,
`tools/make_pseudo_locale.ps1`, and `tr()` at 59 sites in `hud.gd` and 27 in `main_menu.gd`.

Remaining:

1. Add a development-only flag `--pseudo-locale` that switches to `en_XA` **without
   persisting it**, so the state can be checked on demand.
2. With that flag, screenshot **every** screen and inspect each with `read_image`: main menu,
   in-game HUD, pause menu, settings, controls. **Any text still in plain English is a
   string that was not extracted.** Extract it.
3. **Text authored in the scene files** (`scenes/main.tscn`, `scenes/main_menu.tscn`, such as
   the HUD title and the victory panel labels) is not in the CSV. Set it from keys in
   `_ready()` and either blank the scene text or leave it as the English fallback.
4. **Fonts.** The default font has no CJK coverage. Add a Noto Sans family (OFL licence) with
   the Latin, Cyrillic, Greek and CJK subsets the target languages need, set as the project
   theme's default font, and verify by rendering a Japanese and a Korean test string: no
   blank boxes, no clipped layout.
5. `refresh_text()` must exist on every screen and be called when the language changes.

Commit: `feat: finish the i18n extraction and add the font`

### Task 3 — account for every check the physics battery declares

`scripts/physics_demo.gd` declares more checks than it runs (34 report). Some of that is
legitimate: failure-only guards such as `the snowball is created`, and either/or pairs where
only one branch can run. Determine which are **real losses**, at least these four:

- `holding [E] pushes the ball along the ground`
- `holding [E] does NOT lift the ball`
- `the carried ball follows the player`
- `the throw releases the ball with impulse`

Method: find each phase, read its precondition, and decide whether the phase runs at all.
**A phase that cannot set itself up must report a failure**, using the pattern already in the
file (`_check("...", false)` on the early return). Restore any coverage that was genuinely
lost; document the rest as intentional in a comment beside the phase.

Commit: `test: account for every check the physics battery declares`

### Task 4 — face-snow presentation

The last piece of the shared-state milestone. `scripts/hud.gd` already has the overlay
(`_face_overlay`, driven by the player's `face_snow_amount`).

1. Add a blur or a darkening that scales with the amount. A `ColorRect` with a shader, or a
   `BackBufferCopy`, is enough; it does not need to be pretty, it needs to read as
   "I cannot see".
2. Muffle the audio while blinded: an `AudioServer` bus effect (a low-pass filter, or a
   volume reduction) created in code if the bus does not exist, restored **exactly** when the
   snow clears.
3. Wire the two settings that are stored but unread: `SettingsSystem.screen_shake` must scale
   the hit camera shake in `player_controller.gd`, and `face_snow_auto_clear` must be
   respected by the player (it already reads it at start-up — confirm it takes effect when
   changed at runtime).
4. Verify with a `--face-snow-shot` diagnostic: apply face snow, wait, screenshot, print the
   bus effect state and the overlay alpha, quit.

Commit: `feat: face snow blurs the view and muffles the audio`

### Task 5 — make the documentation tell the truth

1. `docs/roadmap.md`: mark as done the items that are finished (1, 2, 3, 4, 7, 8, 9), each
   with its commit reference. Leave the unstarted ones alone. **Do not mark item 9 as done
   without checking `_set_paused`, `_build_settings_panel` and `_build_controls_panel` still
   exist in `scripts/hud.gd`.**
2. `docs/pending_work.md`: move the solved sections into a "done" section, keeping the
   environment traps and the method notes. A stale pending file is worse than none.
3. Correct anything else the work above has made untrue.

Commit: `docs: mark the finished milestones and fold the solved sections`

## Rules — each one paid for in lost time

1. **Read a file before editing it.** The file editor requires a prior read. Bulk-replacing
   text while the editor is blocked invalidates that and causes cascading failures. Four
   files were invalidated this way in one session and one mistake left the game unable to
   start.
2. **Never use `class_name` for a new script.** It registers a global through the editor's
   class cache; a command-line run before the cache knows the name fails to parse with
   "Identifier not declared" and the game will not start. Use
   `const X = preload("res://scripts/x.gd")`, as `session_mode.gd`, `settings_system.gd` and
   `input_bindings.gd` do.
3. **Measure first, change one thing, then measure three times.** Four theories about the
   impact bug were acted on before being measured, and two were wrong. One run of a battery
   has twice been shown to be worthless.
4. **A battery that crashes or aborts without printing a verdict counts as a FAILURE**, not
   as a skip. A phase that cannot run must say so.
5. **PowerShell here is 5.1**: no `pwsh` on PATH, no `&` background operator, no inline `if`
   as an expression, no ternary, and piping a `foreach` *statement* is a parse error.
6. **Non-ASCII characters are mangled when the console reads your command.** An anchor
   containing an arrow or a multiplication sign silently never matches. Match on ASCII-only
   patterns and build symbols from their code points (`[char]0x2192`).
7. **Never kill the user's Godot editor.** Match processes by command line and kill only the
   ones you started.
8. **If you have MCP tools for Godot, use them.** The bundled `addons/godot_ai` addon exists to serve a client like yours, and asking the running editor what is actually in the scene beats reading a log. **If you do not have them, the fallback is the log plus `read_image`** on the PNGs the diagnostics save. Do not assume either way: say which one you used.
   equivalent is the log plus `read_image` on the PNGs the diagnostics save.
9. **Diagnostic output stays English** and is never translated. These are developer strings.
10. **No emojis in code or documentation.** The docs use status marks and those stay.

## Verification, before every commit

```powershell
$godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$repo  = "C:\Users\MrSeb\.gemini\antigravity\scratch\snow_it_alone"

& $godot --headless --path $repo -- --i18n-check
& "$repo\tools\run_batteries.ps1"     # must print ALL GREEN. Never commit on red.
```

- The GPU batteries fail spuriously under `--headless`; run them windowed.
- `--quit-after <frames>` guards against a hang. **A hang is a symptom**: the one time this
  happened, it was a parse error that had left the player script dead.
- Before the gate, check `git status` for stray files: diagnostics drop logs and PNGs into
  the repository root, and those are git-ignored by design.

## Definition of done

Every registered battery green, the gate run immediately before the final commit, five
commits pushed, and `docs/pending_work.md` updated so that nothing open is left implied. If a
task cannot be finished, say so in the commit message and in that file rather than leaving it
half-applied.
