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
| `--phys-demo` | 36 checks across mass conservation, tools, carrying, throwing and shatter |
| `--carve-quality` | Terrain quality after carving and mesh performance |
| `--ball-shape` | Balls stay spherical, density scaling, no phantom furrows |
| `--save-roundtrip` | Save slot API against the real filesystem, corrupt-file handling |

`--phys-demo` and `--carve-quality` need a real GPU. They report false failures
under `--headless` because the snow simulation cannot run there, so run them
windowed. `--ball-shape` and `--save-roundtrip` are safe headless.

`--menu-shot` renders the main menu, saves `main_menu.png` at the project root
and exits; it is the UI smoke test.

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

## Publishing

The repository has no remote configured yet. When it does, a plain `git push`
uploads the whole history; nothing is squashed. The commit author is currently
`MrSeb <mseb@users.noreply.github.com>`, set locally in this checkout; it can be
rewritten for every commit with a single rebase before the first push.
