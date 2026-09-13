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

### Alpine, fourth cut: detail

- Two finer ridged octaves in the range (ribs 47 and 23 blocks apart,
  weighted by the coarser as before) and ribs down the walls — the
  couloirs — from a ridged octave that shows only in the valley mask's
  transition band. Both in the map.
- Under the map's resolution the field adds a mid ridged 3D noise, ledges
  a few blocks high, three times stronger on the walls and crests than on
  the flats and quiet under the snowfields, beside the fine crags.

### Alpine, fifth cut: lower snow, mottled edges, boulders and hollows, sharper erosion

- The snowline down to 90 blocks over the base dome, and no longer a line:
  it wanders by a slow noise and is flecked by a fine one, so its edge is
  a mottled zone some fifty blocks tall.
- The material patches (slate, scree, permafrost, dirt) get two octaves
  and a fine dither at their thresholds, so they have irregular outlines
  and speckled edges instead of blobs.
- Erosion: an unsharp pass before the others — the height plus six tenths
  of its difference from a 32-block blur — which stands the arêtes and
  spurs up and cuts the gullies down, the sharper shapes from the erosion
  that were asked for; the peak cap and floor smoothing a little stronger.
- Small clamped steps in the field: a noise clamped hard, ledges about a
  block high wherever it crosses zero.
- Grown by random tick: boulders (granite, slate one in four; alone or in
  clusters) on flat snow, permafrost, dirt and scree; and hollows carved
  into granite wall faces, a chain of two to four rough spheres going in.
  Counts logged every ten seconds under "alpine:".

### Alpine, sixth cut: more rocks, lower snow, a tree line and firs

- Boulders twice as often, and small lone rocks everywhere flat besides.
- The snowline down to 65 blocks over the base dome.
- A rough tree line at 90 blocks over the dome, jittered fifteen either
  way per 24-block square, decided at runtime: a tick knows its surface
  height, and the base dome's height at that radius is a formula. Below
  it, firs grow by random tick on snow, permafrost, dirt and scree, never
  within three blocks of another's trunk: tall and thin, a cell-thin
  trunk bare for its lowest sixth and a cone of needle pads shrinking to a
  point, every block on a small tree (six to ten blocks), every other
  block on a big one (fourteen to twenty-two), so the big ones read as
  tiered. Two new blocks, `fir_log` and `fir_needles`, asked for.

### Alpine, seventh cut: bigger firs on a plus trunk, more of them, more and bigger boulders, snow patches

- Firs a quarter taller and wider, twice as dense (one surface block in
  nine below the line). The trunk is a plus of five cells in every layer,
  written as one mask per block, so it is the same all the way up — the
  thin ellipsoid it was rounded to one cell in some blocks and a plus in
  others.
- Boulders twice as often and a little bigger.
- Below the snowline, patches of snow that thin out with depth: a patch
  noise against a threshold that rises 120 blocks below the line, so the
  snow peters out instead of stopping. In the snow fill itself (a `max`
  node, new in `shape.node`), not a second program.
- Hollows start from a SURFACE tick now: it looks three blocks out each
  way with a probe that sees twelve blocks up, and where the ground stands
  five or more higher there is a wall to carve into at its foot. A tick
  on rock itself found faces almost never — the random tick picks through
  the whole loaded volume and a face is a vanishing share of the stone —
  and the rocks module's own probe scans only two blocks up, so a wall
  read as unloaded. Each growth draws its chance from its own salt of the
  hash: a rock chance of one in 45 drawn from the same number as a tree
  chance of one in 9 was never a rock. The shared edit queue lands five
  batches a second and holds twenty (from three and twelve), and each kind
  asks it for its own reserve, so a queue full of firs never starves the
  rare things.

### Alpine, eighth cut: the tick budget, dead firs, grass

- The tick budget: an alpine chunk ran nine surface fills, each
  re-evaluating the whole terrain. Now seven: the granite skin fill runs
  only where another biome shares the chunk (the generator lays the
  biome's soil under the surface already), and the lake ice is folded
  into the glacier ice fill by a `max` (the lake water written after
  takes back all but the top block). The terrain itself is cheaper: the
  fine crags are gone and the ledge detail is one octave, since an octave
  in the terrain is paid once per fill.
- Dead firs, one in twenty-one — twice the woodlands' rate: half snags
  (the plus trunk in dead wood, shorter, a broken top and a stub or two),
  half fallen trunks lying along x or z, merged into the surface.
- Grass: sparse tufts of `alpine_grass` stood by the cover fill below the
  snowline where the ground faces up, off the crests and lakes — the
  temperate blades in a darker, desaturated blue-green with its own cold
  tint, shorter, wind-flattened.

### Alpine, ninth cut: a third the grass, three times the trees, boulders twice the size, dirt and turf, bigger lakes

- Grass a third as common; firs one surface block in three below the
  line (a forest, held apart by the spacing); boulders twice the size;
  lakes larger and more of them.
- Granite about a third as common on the surface: dirt three blocks deep
  over most ground below the snowline that faces up, and turf (the
  `grass` block) over most of that below the tree line, so the granite
  shows on the walls, the crests, and the patches these leave. The
  surface tick grows on turf too.
- Engine: the client stops drawing sprites (grass, bushes) beyond seven
  chunks and cutout foliage (leaves, needles) beyond eleven, measured to
  the chunk's centre. This is the frame's cost, not the server's tick.
- The tick: a single alpine chunk took over fifty milliseconds to
  generate. The world's own two detail octaves are left out of the alpine
  terrain (the map and the ledges carry that scale), a third of the noise
  in every alpine fill; tree tries check the block above first and size
  their loaded box to the tree, and are one in five rather than three.
  The remaining cost is structural — every fill re-evaluates the terrain
  — and is engine ask 19, a palette fill: one evaluation, many materials.

### Alpine, tenth cut: more and bigger boulders, cold turf

- Boulders twice as often again and three tenths bigger.
- The turf is `alpine_turf`, a new block in the same cold blue-green tint
  as the alpine grass that stands on it; the shared `grass` block carries
  the temperate tint and a tint is per material.

### Alpine, eleventh cut: crevasses, more needles

- Crevasses, now and then, on the glaciers and the high snow: a crack
  fourteen to thirty-four blocks long along x or z, eight to twenty-two
  deep in the middle and shallowing to its ends, one to three wide, its
  walls coated with ice — one tall ellipsoid of ice written first and a
  slightly smaller one carved out of it as air, merged so the ground
  round it stays. Grown by the surface tick on ice and high snow; say
  `crevasse` in chat and one is carved where you stand, to look at.
- Firs carry a quarter more needles: pads an eighth wider and thicker.

### Alpine, twelfth cut: one fill for the whole surface; the tree line up

- The alpine surface — slate, scree, permafrost, dirt, turf, snow, the
  glaciers and the lakes — is ONE fill: `buf:fill_layers`, new in the
  engine beside its palette fill. The terrain is evaluated once, smooth at
  the cells; a code field evaluated once at block resolution names which
  set of depth bands each block gets (the greatest of k times a stepped
  condition, later layers larger); a table maps code and band to
  material. The engine's palette is a single value against thresholds,
  right for depth bands and wrong for a category, which the smooth detail
  would interpolate at every patch edge and at the surface itself. Eight
  evaluations of the terrain a chunk are one.
- The tree line up to 200 blocks over the base dome, jittered forty
  either way, and tries one surface block in two: at 90 most of the range
  stood above the line, and growth by tick took minutes to fill a chunk.

### Alpine, thirteenth cut: snow as a deposit, the forest fills in, cold ice, boulders halved

- The snowfields are a deposit: where snow lies above the line the
  terrain itself stands four blocks higher (`snow_lift`, a term of the
  alpine terrain, tapered in over four blocks of height above the
  wandering, flecked line, and off the lakes, walls and crests over their
  masks), and the snow layer there is eight blocks deep — double — so it
  is those four blocks and four under them, and a snowfield's edge is a
  bank, mottled by the fleck. The glaciers stand up with it; their ice is
  six deep so it reaches under the lift. The patches below the line stay
  flat and four deep: a mound at every patch would be a field of lumps,
  and the patch noise in every terrain evaluation cost a fifth of a
  chunk. The patches' fade reads the line from the maps alone, three
  octaves fewer. The snow's masks moved to file level, written
  left-leaning, because the lift is evaluated inside the terrain with
  buffers already held. Chunk generation with the lift: about five
  milliseconds a chunk, from four.
- The forest fills in. Two ceilings on it, both raised. The edit queue
  landed five batches a second across every loaded chunk (a thousand
  three hundred fir tries in ten seconds, thirty-seven landed, seven
  hundred refused for room): it lands a batch every tick now and two a
  tick when it is filling, twenty to forty a second (four a tick built
  firs faster than the tick could relight them). And a
  random tick on buried snow — seven in eight of them, now the snow is
  eight deep — was a try refused for headroom: a buried tick is taken up
  to the surface of its column, so the whole depth of the snow ticks its
  surface. And a block of two materials names none (`material` nil,
  `cells` listed) — which is the surface block of most columns, the
  grass cover standing its cells in the top block's air — so every read
  of a surface material is now by cell (`holds`, `is_surface_block`), and
  the grass cover is open to a trunk, as in the woodlands. The firs stood
  in patches where the player had waited and nowhere else; growth by tick
  is still growth by tick, and a chunk's forest is there within a minute
  of its loading rather than at generation (engine-asks 3).
- Ice is cold blue: a blue texture and a blue-shifting tint.
- Boulders halved: they stood twice the size they read on paper.

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
