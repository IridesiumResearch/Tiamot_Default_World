<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Changelog

What changed, when, and why — one entry per working day, newest first.
The commit messages carry the same account; this file is the one you can
read without git. Engine changes made for the mod are listed too, with the
engine commit they landed in, because the mod is written against them.

## 2026-09-11

### Ground cover: grass as cards that stand still

- **Grass, brambles, lady's mantle and its bloom, rose bushes and their
  blooms are drawn as crossed cards** (`billboard = "cross"` in
  `blocks.lua`): two fixed cards on the diagonals of a run's column, the X
  Minecraft and Minetest draw. A card that turned to face the camera read
  as a sticker following the player. Engine: the sprite path gained a fixed
  heading per instance and emits two per crossed run; the block parser now
  refuses a `billboard` that is not `true`, `false` or `"cross"` instead of
  reading it as `false` silently. Protocol 50. Engine 79fd6e5, which also
  raises the density ceiling to 512 ops (see below).
- **Grass tufts are one or two cells tall and never cross into the block
  above** — the designer's "no stacking". They are stood on the surface by
  the engine's new cover fill (`buf:fill_cover`, `generate.lua` runs every
  biome's covers after every biome's fills), which reads the surface from
  the cells the fills wrote rather than from a field. A density field
  cannot say which block a sample is in, and the engine samples a block at
  its bottom corner, so a two-cell run confined to a block was invisible to
  the sampled fill's surface test in two thirds of columns.
- **Grass density** is about one card per three blocks (`TUFT_MIN` 0.20 in
  both temperate biomes), cut twice today at the designer's word: to a
  third of the first cut, then to 30 % of that.
- **The blade tile** is five one-pixel blades per card (`tools/make_textures.py`).
- **Two engine bugs found and fixed on the way** (engine-asks 13 and 14):
  a billboard that also declared `cutout` was drawn as cutout cubes with
  the sprite lost inside; and the incremental mesh job the game runs never
  attached sprites at all, so sprites had never been drawn in play — the
  screenshot test passed because it meshes through the one-shot path.
  `cutout` is off every billboard material now.

### Rolling Grasslands

- Sentinel trees at two thirds the size, leafier: four or five branches,
  a pad halfway and at the tip, thicker pads.
- The swells' low side deepened by 35 % (`shape.HOLLOW_DEEPEN`), so the
  hollows read more than the rises.
- **Rose bushes**: a rough ball of `rose_bush` cells on the turf with a few
  `rose_blooms` cells over its crown, planted by the grass tick in loose
  groups seven blocks apart. Two materials in one block, because every
  texture is one colour. **Picking is a dig on a bush that has blooms**:
  the dig is cancelled, every bloom on the bush turns to leaves, the player
  is given one or two `rose` items, and the blooms come back after four
  minutes or on the bush's random tick. A bare bush digs like anything else
  after a five-second grace, so a button held through the pick does not
  take the bush. A right-click pick waits on the engine (ask 16), as does
  reading the block inside the dig hook (ask 17): the world lease is not
  held there, so the hook decides on the event's material and the bush is
  read a tick later. Say `roses` in chat to be put beside the first bush of
  the session.
- The mod's tick dispatcher logs a tick error's text before the engine
  disables the mod for it; the engine says only that one happened.

### 1.3 Alpine Highlands, and programs per ring

- **The biome**: the frost ring's dry half. Fake erosion in the field
  (`shape.alpine_terms`): a staircase of hard-clamped ramps on one slow
  noise for stepped plateaus with twenty-block sheer risers; a tent along
  a noise's zero contour for thirty-block razor ridgeways; a clamped bowl
  for forty-block cirques with steep headwalls; a fine ridged noise for
  crags. Materials read the same ramps back (`shape.alpine_steep`): granite
  skin with `slate` seams, gravel drifts (the creek-bed block) down risers
  and cirque walls, `permafrost` in patches off the steep faces, thin dirt
  on the flats, and `snow` as a one-cell windswept crust by the cover fill.
  Three new materials, all named in the brief. Nothing grows by tick yet.
- **Programs per ring**: a density program cannot ask where it is, so the
  terrain and every biome's fills are compiled once per terrain mode
  (`shape.lua`, "terrain MODES") and the generator picks by the chunk's
  radius. Only the band a few hundred metres wide where the frost and
  temperate rings meet carries both rings' noise; those programs reach 382
  ops, so the engine's ceiling is 512 (was 256). Alpine chunks are the
  heaviest to generate so far: one tick over budget in forty seconds of a
  headless run, at 43 ms of generation.
- The spawn drop height gains an alpine allowance in the dev world: thirty
  blocks over the base dome sat inside the terraces, and a player put down
  in rock cannot climb out through chunks the vertical view does not reach.
- The dev switch (`tdw.config.everywhere` in `init.lua`) is on
  `alpine_highlands`.

### 1.3 Alpine Highlands, second cut: the Alps as a map

- The first cut's hard-clamped terraces on 3D noise gave overhanging
  drop-offs everywhere, because a field's noises vary in y as much as in
  x. The range is now a MAP built once per world in the pre-pass
  (`game.register_on_world_init`): a ridged multifractal (arêtes and horns)
  pulled down to flat floors along the zero contour of a slow valley noise —
  a meandering ribbon, so the valleys connect into a glacier network
  between the massifs rather than sitting as bowls (the U profile) — then
  two erosion passes over the whole map — needle peaks capped at 25 blocks
  over their 24-block neighbourhood mean, and valley floors replaced by
  their own 40-block blur so they lie flat while ridges keep their edges.
  The terrain reads it through a map node; small 3D crags stay in the field.
- `ice` is a new block (asked for by name). Above the snowline (50 blocks
  over the base dome) everything but the crests is packed snow two blocks
  deep and every valley floor and cirque is ice three blocks deep — the
  glaciers — so almost no stone shows up high; the lower slopes keep the
  scree, permafrost and thin dirt. The one-cell snow cover is gone.
- Programs that read the maps (the alpine and cross-faded terrain sets and
  the alpine biome's fills) are compiled at the first chunk that needs
  them, after the pre-pass; the rest still compile at load where the mod
  check sees them. The spawn drop height follows the range's peak.
- One map, 8 km square at 8 blocks a sample, centred on the spawn; outside
  it the map holds its edge value. Tiling the frost ring comes after the
  shape is right. A world made before this keeps generating without the
  maps (the pre-pass runs once per world), so look at it in a new world.

### Alpine lakes

- Medium to large frozen lakes on the valley floors, where a lake noise is
  high: a fourth map. The floor under a lake is smoothed with a 96-block
  blur so the lake lies level, and the fills make its top block ice and
  the eight blocks under that water. The lake is not carved: its surface
  is the floor, which keeps every lake chunk a surface chunk the generator
  paints. The water is the `water` block rather than the fluid, because
  the fluid fill takes one world level and a lake's level cannot reach
  Lua — engine ask 18 is a fluid fill by heightmap.

### Alpine, third cut: bigger, deeper snow, snow by aspect, stronger erosion

- The range two and a half times the second cut in height and breadth:
  ridge octaves from 1/3000, peaks near 0.9 km, valleys 500 blocks across,
  the map 16 km square at 16 blocks a sample. Snow four blocks deep.
- Snow lies by aspect: the snowline comes down 80 blocks in the valleys
  (the floor mask), goes up 100 blocks on the crests (the crest mask), and
  the walls — the valley mask's transition band, f(1-f) — carry none. The
  masks the map already holds stand in for the dot product with up, since
  a map has no gradient op.
- Erosion 1.75 times as strong: the peak cap's neighbourhood 48 blocks and
  the floor blur 64, and the cap 36 blocks over the mean against a range
  two and a half times taller.

### Housekeeping

- `stubs/game.lua` and `AGENTS.md` re-vendored from the engine's `api/`.
- `docs/engine-asks.md`: landed today in the engine — 9 (crossed cards),
  10 (a per-biome hue, as `game.register_chunk_tint`, engine 33dd9df, not
  yet used here), 12 (noise bounds over a box) and 15 (the cover fill),
  both in engine ffac6e0, which also carries the fix for 14. Items 13 and
  14 record the two sprite bugs; 16 and 17 are open.
- Everything in this entry was verified headless: engine unit tests, the
  mod check in both the dev and real-world modes, and a scratch server with
  scripted bots generating chunks, picking a rose bush, and landing on the
  alpine plateaus. Nothing was looked at in a window after the first grass
  screenshot of the morning.
