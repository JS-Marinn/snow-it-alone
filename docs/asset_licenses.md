# Third-party assets and licences

What this project uses that it did not make, what each is licensed under, and how
certain that is. The distinction matters: **verified** means the licence text is in
this repository or came with the download, **unverified** means it is inferred from
how the files are named and must be confirmed from the original source before release.

Anything marked unverified is a release blocker, not a detail.

Last reviewed: 2026-10-05.

---

## Verified

| Asset | Origin | Licence | Evidence |
|---|---|---|---|
| `assets/models/cabin_fence.glb`, `bench.glb`, `snow_pile.glb`, `snowman.glb`, `colormap.png`, `assets/models/Textures/colormap.png` | **Kenney — Holiday Kit 2.0** (kenney.nl, created 2024-12-11) | **CC0 1.0** (public domain dedication) | The pack's own `License.txt` is kept in the staging folder `scratch_assets/holiday_kit/`. CC0 allows personal, educational and commercial use; crediting Kenney is appreciated but not required. |
| `addons/godot_ai/` | Godot AI contributors, v4.1.0 | **MIT** | `addons/godot_ai/LICENSE`. This is an **editor-only** plugin (enabled in `project.godot` under `[editor_plugins]`), so it is not part of an exported build. |

## Unverified — confirm before release

| Asset | Probable origin | Probable licence | What to do |
|---|---|---|---|
| `assets/models/cozy_cottage.glb`, `cozy_cottage_colormap.png`, `tree_snow_a.glb`, `tree_snow_b.glb`, `tree_snow_c.glb`, `pine_tree.glb`, `snow_shovel.glb`, `first_person_shovel.glb` | Likely the same Kenney Holiday Kit or another Kenney kit, since they share the single-atlas `colormap.png` convention. The cottage may be assembled from kit parts. | CC0 if Kenney | Confirm which kits each model came from and keep their `License.txt` files in the repository. |
| `assets/models/lantern.glb`, `lantern_01.glb`, `lantern_01_Lantern_01_brass_*` textures (arm, diff, nor_gl, 1k) | The `_1k`, `_diff` and `_nor_gl` suffixes are the [Poly Haven](https://polyhaven.com) naming convention. | CC0 if Poly Haven | Confirm the model's source page and record the URL here. |
| `assets/textures/asphalt_*`, `snow_*` (ao, diffuse, normal, rough, disp), `wood_*` | ambientCG or Poly Haven: both use this four-map PBR naming and both are CC0. | CC0 | Confirm the source page for each set and record the URLs. |
| `audio/` — 32 files: `SnowWalk.ogg`, `SnowWalk2.ogg`, `concrete_step_1..5.ogg`, `snow_step_1..5.ogg`, `snow_thud_1..3.ogg`, `shovel_scrape_1..8.ogg`, `shovel_dig.ogg`, `salt_pour.ogg`, `snowblower_loop.mp3`, `swish_1..13.wav`, `wind_loop.ogg` | Unknown. The batch naming (`concrete_step_N`, `swish_N`) suggests a freely licensed sound pack. | Unknown | **Find the download page for each pack.** This is the largest single gap: 32 shipped files with no recorded licence. If the source cannot be established, replace them. |

## Not distributed

| Item | Note |
|---|---|
| `scratch_assets/` (the full Kenney Holiday Kit with previews, in FBX, GLB and OBJ) | Excluded by `.gitignore`. It is a staging area, not part of the game. Its `License.txt` is the evidence used above. |
| `addons/`, `extension_api.json`, `export_presets.cfg` | Development-only, excluded or editor-only. |

## Missing, and needed before release

- **A game icon.** `project.godot` sets no `config/icon`, so builds carry Godot's
  default icon. That is Godot's logo (CC BY 4.0, Godot Engine contributors) and must
  not ship as this game's identity.
- **A credits screen.** Not required by CC0, but it is the decent thing and it is
  what makes the unverified list above verifiable at a glance.

## Before every release

1. Every row in the first two tables has a licence and a source.
2. The licence files of every asset pack are committed alongside the assets.
3. Nothing marked unverified is still unverified.
4. `LICENSE` at the repository root covers the project's own work, and this file
   covers everything else.
