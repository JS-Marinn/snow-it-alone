# Development workflow

## Language

Everything that ships is English: identifiers, comments, UI strings, console
output and commit messages. The design documents under `docs/` are still Spanish
and are being migrated; new documents are written in English.

## Code style

- No emojis and no decorative banner comments anywhere. Comments explain *why*
  something is done, or the non-obvious constraint; they do not restate the code.
- No magic numbers: tuneable values are exported or live in data resources.
- Systems talk through signals or explicit APIs, never by reaching into each
  other.

## Commits: one per verified milestone

Work is committed per **milestone**, not per file and not per working session. A
milestone is a coherent step that leaves the project working: a system finished,
a class of bug fixed, a diagnostic added.

Before committing:

1. Every touched script parses:
   `godot --headless --path . --check-only --script res://scripts/<file>.gd`
2. The diagnostic batteries below are green.
3. The message states what changed and why.

Format (Conventional Commits):

```
<type>: <short summary in the imperative>

Optional body: what was verified, measured numbers, known limits.
```

Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `chore`.

Example:

```
feat: add save slots and main menu

Continue and New Game over three JSON slots in user://saves, with a versioned
schema and a two-step overwrite confirm. Verified with --save-roundtrip
(21 OK / 0 FAIL) and a rendered menu screenshot.
```

## Diagnostic batteries

Run these before every commit that touches physics, snow, balls or saves.

| Command | Checks |
|---|---|
| `--movement-lab` | 11: surface speeds, crisp stops, straight hops gain nothing, strafing does, the hop ceiling |
| `--impact-lab` | 18: the three ball tiers against body and face, state durations, immunity, the manual wipe, the dummy |
| `--phys-demo` | 36: mass conservation, tools, carrying, throwing, ground push and shatter |
| `--carve-quality` | Terrain quality after carving and mesh performance |
| `--ball-shape` | Balls stay spherical, density scaling, no phantom furrows |
| `--save-roundtrip` | Save slot API against the real filesystem, corrupt-file handling |

`--movement-lab`, `--impact-lab`, `--phys-demo` and `--carve-quality` need a real
GPU. They report false failures under `--headless` because the snow simulation
cannot run there, so run them windowed. `--ball-shape` and `--save-roundtrip` are
safe headless.

`--menu-shot` renders the main menu, saves `main_menu.png` at the project root
and exits; it is the UI smoke test.

### Running all of them with one command

`tools/run_batteries.ps1` runs every battery, reads each verdict and exits non-zero
unless all of them passed. A battery that crashes without printing a verdict counts as
a **failure**, not a skip: a crash must never look like a pass. Logs land next to the
project as `battery_<flag>.log` (git-ignored).

```powershell
pwsh -File tools/run_batteries.ps1                              # all six, windowed
pwsh -File tools/run_batteries.ps1 -Headless                    # only the two that need no GPU
pwsh -File tools/run_batteries.ps1 -Only movement-lab,impact-lab
```

The Godot executable is found automatically at its usual location on the development
machine; anywhere else pass `-Godot <path>` or set `GODOT_BIN`.

### What CI covers, and what it cannot

`.github/workflows/batteries.yml` runs the two batteries that need no graphics card on
every push and pull request. The four that need a GPU cannot run on a hosted runner, so
they are covered locally only. The workflow's final step prints that limitation into the
log on purpose, so a green run is never mistaken for full coverage.

## Repository layout

```
assets/      models, textures, materials sources
audio/       sound effects and music
docs/        design and implementation documents (Spanish, being migrated)
materials/   shaders used by the snow surface
scenes/      main_menu.tscn (entry point), main.tscn (the level)
scripts/     gameplay, simulation driver, diagnostics
shaders/     the snow simulation compute shader
addons/      third-party editor tooling (the Godot AI MCP plugin)
```

Generated content is not tracked: `.godot/`, root-level diagnostic screenshots,
logs, `extension_api.json` and `scratch_assets/`. See `.gitignore`.

## Repository and publishing

The remote is `https://github.com/JS-Marinn/snow-it-alone` (public) and the local
`main` branch tracks `origin/main`. Commits are authored as
`JS-Marinn <JS-Marinn@users.noreply.github.com>`, configured in this checkout.

Routine for every milestone: run the batteries, commit, push.

```
git add -A
git commit -m "feat: <milestone>"
git push
```

A push carries the whole history of the branch; nothing is squashed or lost.

Files that must never be published are covered by `.gitignore`: the editor cache,
export presets (they can hold keystore passwords), local addon state and staging
asset packs. Check `git status` before adding anything that was downloaded rather
than authored: third-party asset licences are the author's responsibility, and
this repository is public.
