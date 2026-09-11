# Engine asks from the Spindle

What the world mod has needed from the engine, found by building it. Each
entry says what was seen, why the mod cannot fix it, and the smallest
engine change that would. Newest first. Items are removed when they land.

*Landed 2026-09-10: the merge write (`set_block(pos, block, mask, { merge
= true })`, contract §7.4 — no protocol change, it is the placement rule
made reachable), the serve budget (53296a0), `Density:bounds` (9f01f67),
and maps <-> density fields (86cd44e). The mod uses the merge write for
every runtime structure, the bound for its gate, and clamps its noise so
the bound is tight; the map node is the erosion work's. Items 0, 1, 2 and 4
below are closed and kept for the record. Item 3 — structures at
generation across chunk edges — is the one still open; note from the
engine that `buf:set_subnode` already preserves a uniform block's other
cells, so generation-time embedding needs nothing new, only the
cross-chunk pass.*

## 11. An item dropped at a position (2026-09-11)

**Wanted.** Water reaching a leaves block breaks it (`rules.lua`, on
`register_on_fluid_flow`), and the designer wants what it was to DROP. A
dig drops through the engine's own rule and a placement can be refused
with the player keeping the material, but a mod that removes a block in a
hook has no way to put its units into the world as a pickup.

**Ask.** `game.drop(position, { material = "mod:block", units = 27 })`: the
same pickup a dig makes, spawned at a position, owned by nobody.

## 10. A per-biome hue (2026-09-11)

**Wanted.** The designer wants each biome to carry its own cast: drier
biomes a little less saturated and browner, wetter ones bluer-green,
darker and richer. `tint` is per MATERIAL over one world field, so a grass
block is the same green in every biome, and per-biome block variants would
multiply the node list the designer keeps small.

**Ask.** One colour per chunk from the generator — `buf:set_tint{ r, g, b }`
(multipliers, default white) on the chunk buffer, carried in the chunk
message, and on the client interpolated between chunk centres and
multiplied into the albedo beside the material's own `tint`. A biome's hue
is then one line in its file, and the boundary between two biomes is a
smooth sixteen-block blend rather than a seam. Three bytes a chunk.

## 9. Crossed cards (2026-09-11)

**Wanted.** Grass, lady's mantle and brambles as the X of two crossed
quads Minecraft and Minetest draw, rather than a single card turning to
face the camera. From the window a turning card reads as a sprite; the X
reads as a plant, and it does not swivel as the player walks round it.

**Ask.** `billboard = "cross"` beside the present `true`: the same run of
cells drawn as two fixed quads on the diagonals of the run's column, the
whole tile across each, the top edge swaying as now. No new state — the
mesher already finds the run; only the vertex stage differs.

## 8. Sprite cards for grass, placed by the cell (2026-09-10) — LANDED as `billboard` and `sway`; grass, flowers and leaves use them

**Wanted.** Grass the way Minecraft and Minetest draw it — two crossed
alpha-tested quads — but standing on the sub-node surface rather than on
the block grid, so it never floats over a smooth slope, and with heights
that vary blade to blade.

**Why the mod cannot do it.** Every material is drawn as cells. The mod
already places grass as cells on the surface, one to three tall per
column and about half a block's columns taken; it needs the mesher to draw
those columns as cards instead of cubes.

**Ask.** `register_block{ draw = "card" }`. For every occupied cell column
of such a block — a run of the material's cells stacked in one (x, z)
cell position — the mesher emits two crossed quads, centred on that cell,
one block wide, as tall as the run (a third, two thirds or a whole
block), alpha-tested like `cutout`, unlit by face normal (both sides).
Nothing else changes: the cells still exist, collide (until item 6),
dig and drop. Nine columns a block is the most it can be asked to draw;
the mod uses four or five.

## 7. Summaries of partial blocks read as crosses (2026-09-10) — noted

**Seen.** Beyond the view distance the horizon is drawn from LOD summaries,
and a woodland's trunks — whole blocks minus their corner columns — come
out as "+" shapes floating at canopy height, with small leaf clumps as
lone crosses. Not a mod matter; recorded so it is not chased as one.

## 6. A passable block (2026-09-10) — LANDED (engine 0ab4113); ferns and tufts declare it, brambles do not

**Wanted.** Ground cover: ferns two cells tall, tufts of grass, in
carpets. A player should walk through them.

**Why the mod cannot do it.** Every block collides, whole or partial —
the contract's collision is the cell lattice, and `register_block` has no
way to say a material is not an obstacle. Knee-high fern cells are a
two-thirds lip the player steps up, so a fern carpet is a field of bumps.
The mod grows ferns in clumps with gaps for now and keeps tufts a cell
tall.

**Ask.** `register_block{ passable = true }`: the material's cells are
left out of the collision lattice (and of pathfinding's floor test) and
otherwise unchanged — drawn, lit, dug, dropped. A player walks through a
fern; a bramble stays a bramble.

## 5. Per-cell value jitter on a material (2026-09-10) — LANDED as a global one per cent (engine 9caa151), not per material; nothing for the mod to declare

**Follow-up (2026-09-10, later).** The engine agent raised it to 2.5 %
(`CELL_VARIATION` in `crates/client/src/render/world.wgsl`), and from the
window that is still too mild: the designer asks for **three times it,
0.075**. The screenshot test `one_material_is_not_one_flat_colour` bounds
the measured spread at 10 %, and 2.5 % measured as 2.6 %, so 7.5 % should
land near 7.8 % — under the bound, but the bound's comment ("catches an
order-of-magnitude mistake") wants restating alongside the constant.

**Wanted.** Every material is now a single flat colour by design (the
designer's rule: no picture ever carries variation). What breaks up a flat
surface should be the renderer's: a very slight, random VALUE offset per
sub-node cell — each cell a hair lighter or darker than its neighbour,
flat across the cell, world-anchored, the same on every machine.

**Why the mod cannot do it.** The unit is the cell, and only the mesher and
the world shader know where a cell is. `tint` is the other thing: one
smooth field per material at a scale of tens of blocks, sampled and
interpolated (`tint_noise`) — it cannot produce a flat step per cell, and
a material has one of it.

**Ask.** `register_block{ jitter = 0.04 }`: in the world shader, take the
cell of the fragment (`floor(world_position * 3)`), hash it with the
`tint_hash` that already exists, and scale the lit colour by
`1 + jitter * (hash - 0.5) * 2`. No interpolation — the whole cell gets
one value. World-anchored like the tint, under the lighting like the tint,
and `None` on the wire when a material declares none, like the tint. One
byte per material, no protocol shape change beyond the field.

## 0. A merge write: cells into a block that keeps its others (2026-09-09)

**Seen.** Surfaces are sub-node smooth, so the block a rock, a root or a
tree's root flare sits in is the block the grass cells are in. A mod can
write one material per block (`set_block` with a mask replaces the block),
so anything placed ON a smooth surface either hangs a cell above it or
turns the whole block into itself — a rock stands in a full-block footprint
of stone, a root flare makes a wood-topped block. The designer's rule is
that anything embedded in the ground embeds at sub-node resolution.

**Why the mod cannot fix it.** Two materials in one block is a mixed block,
and there is no runtime write that produces one. The engine already does
this per cell for plan stamps (`Edit::SubNode`, one per filled cell, when a
stamp layers onto a block it has replaced), so the mechanism exists; it is
not reachable from Lua.

**Ask.** `game.set_block(position, block, occupancy, { merge = true })` —
or a fourth positional — that writes `block` into the masked cells and
leaves every other cell as it was: one `Edit::SubNode` per masked cell, or
one mixed-block edit if the protocol grows one. With it a rock's cells go
into the grass block around them and nothing else changes.

## 1. Chunk serving is not paced against the tick (2026-09-09)

**Seen.** With `view_distance = 24` on a world of sub-node surfaces, every
tick logs `a tick ran over its budget — 50–80ms total: serving 44–80ms`,
with `mods` at 0.5–2 ms and `save chunks` at 4–12 ms. Serving alone is over
the whole 50 ms budget, every tick, for as long as the player moves. The
client is corrected by a late server and reads it as being pushed around.

**Why the mod cannot fix it.** Serving is the engine's; the mod does not
choose how many chunks go out a tick. A sub-node chunk is up to 27x the
cells of a block one and the serve cost (2.3 ms measured for a block chunk)
scales with it; a 24-chunk view is a 49x49x25 interest volume. The mod can
only make chunks smaller (block resolution) or the view smaller (the
player's setting), neither of which is the mod's to decide.

**Ask.** A per-tick serve budget: serve chunks in order of distance until
N ms have gone (say 15), and leave the rest for the next tick. A player
sees terrain arrive over a few ticks instead of the whole server stalling.
Second, serialising and compressing a chunk for the wire off the simulation
thread, so the tick only hands out finished bytes.

## 2. A cheap bounds probe on a density program (2026-09-08)

**Seen.** A chunk is classified from bounds the mod computes in Lua, and the
bound on the terrain field is the sum of every noise amplitude — so every
chunk within the full relief of the base dome (a band 400–2,000 blocks
thick) runs the whole surface pipeline, though the surface crosses only a
few of them.

**Ask.** `Density:bounds(pos)` — evaluate the program at a chunk's eight
corners and centre and return the min and max. Not a guarantee (noise
between samples), but with the finest octave's amplitude as a margin it
lets a mod skip nine chunks in ten. It is what the `smooth` fill already
does internally to find the crossing blocks.

## 3. Structures at generation, across chunk edges (2026-09-09)

**Seen.** Trees, rocks and pools are grown at runtime by random tick,
because a generator cannot read the surface it just wrote and a structure
crosses chunk edges in every direction. Runtime growth costs a relight and
a remesh per chunk per structure and fills a woodland in over minutes.

**Ask.** A decoration pass: after a chunk and its 26 neighbours have been
generated, a second callback with a buffer that can be READ (`buf:get_block`,
or a `buf:tops()` heightmap of the highest solid block per column) and
written across the 3x3x3 neighbourhood. Deterministic from the chunk's own
stream. This is how every voxel engine with trees does it.

## 4. Maps into density fields (2026-09-08)

See `erosion-options.md`: a `{ op = "map" }` density node, `Map:fill(density)`,
and a larger or tiled map are the gate for any erosion. Unchanged.
