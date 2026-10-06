# Future: cel shading

Kept here on purpose. The cel shading was implemented, tried in game, and the owner did not
like the result, so the project was reverted to the shading it had before. These files are
what was removed.

## What is here

| File | What it is |
|---|---|
| `toon.gdshader` | The toon material for ordinary objects: light bands, rim, outline. |
| `snow_deform_with_toon.gdshader` | A copy of the snow field shader **with** the toon banding added inside it. The live `materials/snow_deform.gdshader` is the version without it. |

Nothing in the game references these files, so they are inert. They are here so a future
attempt starts from working code instead of from scratch.

## Why it was reverted

The banding fought the snow. The field is a displaced heightfield whose per-pixel normals come
from carved, noisy relief, so quantising the light into a few hard bands turned every
irregularity into a blotch. Two attempts to fix it failed, and the owner asked for the
project back.

## What to read before trying again

`docs/pending_work.md` and the advanced prompt that was written for this bug. The short
version, which is the part that mattered:

- **The invariant:** shading must not show relief the geometry does not have. If a bank's
  silhouette is a flat plane and its shading is a mosaic, the shading is lying.
- **On white-on-white, the rim and the outline are what separate shapes** — not the bands.
  Banding the snow is the cheapest way to make it look worse.
- **Bisect before changing anything:** five screenshots, each with one term disabled (snow
  toon off, object toon at one band, outline off, all off), from the same camera. The one
  that removes the artefact names the cause. Two attempts were made without doing this and
  both failed.