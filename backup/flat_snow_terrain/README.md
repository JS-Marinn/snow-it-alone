# Backup: the flat-terrain snow system

Kept on purpose. The snow field is the heart of this game: everything depends on it, from the
player to the balls to the shovel. This is a complete copy of the system as it worked, so that
a change to irregular terrain can be abandoned without archaeology.

**Last known good commit:** 2769fbc

**Gate at that commit:** 14 batteries, 250 checks, ALL GREEN. The per-battery numbers are in
the root README and in CONTRIBUTING.md.

## What is here

| Path | Why |
|---|---|
| scripts/snow_field.gd | The field itself: simulation, queries, mesh, collider |
| scripts/player_controller.gd | Every place the game asks the field for a height |
| scripts/snowball.gd | The support and friction of the balls |
| materials/snow_deform.gdshader and its .uid | The visual displacement. The .uid matters: without it references break |
| materials/snow_sim.glsl | The compute simulation |
| scenes/main.tscn, scenes/playground.tscn | Where the field is configured |
| project.godot | For reference only. The restore script does not overwrite it unless asked |

## How to restore

    powershell -File tools\restore_flat_snow.ps1

Then restart the editor. The script copies every path back over the project. project.godot is
left alone by default, because it may have gained unrelated settings since; pass
-IncludeProject if you really want it reverted too.

## Verifying the copy

The copy was verified by restoring it over the unchanged project and confirming that git
status reported **not one byte different**. That is the only honest way to know a backup is
faithful: restore it and watch for changes.