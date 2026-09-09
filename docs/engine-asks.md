# Engine asks from the Spindle

What the world mod has needed from the engine, found by building it. Each
entry says what was seen, why the mod cannot fix it, and the smallest
engine change that would. Newest first. Items are removed when they land.

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
