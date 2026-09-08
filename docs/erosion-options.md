# Erosion for the Spindle — the options, costed

*2026-09-08. What "fake erosion" can mean here, what each method needs from
the engine, and what it would cost. Written against the engine at `4cea122`.*

## What the engine offers today

Two ways to shape terrain, and they do not mix:

| Path | Where it runs | What it can express |
|---|---|---|
| `game.density` + `fill_density` | per chunk, per sample | anything that is a function of ONE position: the dome, the body, the shells, caves, noise relief, terraces, boulders |
| `game.map` + `Map:heightmap` + `fill_below_heightmap` | once per world (`register_on_world_init`), stored | a 2D field that can see all of itself: `noise`, `offset`, `scale_by`, `clamp`, `blur(radius)`, `combine(other, add/mul/min/max)` |

Erosion is by definition the second kind — where water goes depends on the
land everywhere else — so it lives in a map. Three limits matter:

1. **A map cannot reach a density fill.** There is no `{ op = "map" }` node,
   so an eroded heightmap can only feed `fill_below_heightmap`, and the
   Spindle's surface is a density (the dome plus the relief, and the caves and
   shells under it). Today the two cannot be combined in one world.
2. **A map has no coordinate op**, so the dome cannot be written INTO a map
   either: `noise` is the only thing that puts a shape in one.
3. **1,024 samples a side.** The disc is 118,000 blocks across, so one map
   over it is 115 blocks per sample. `Map:heightmap` interpolates bilinearly
   (`detgen/map.rs`), so the ground is smooth between samples, but no eroded
   feature can be narrower than about a hundred blocks. Erosion at 16 blocks
   per sample over the disc would be a 7,400² map.

So **every method below needs the same two small engine additions before it
can touch the Spindle at all** — see the asks at the end — and the third is
what decides how fine the result can be.

## The methods

### 1. Laplacian curvature stencil ("local sediment deposition")

The discrete Laplacian of a heightmap, `∇²h ≈ mean(neighbours) − h`, is
positive in hollows and negative on ridges. Adding `k·∇²h` each step moves
material from convex to concave — a diffusion step, which is exactly what
soil creep and slope-wash look like at landscape scale. The one-sided variant
(`max(∇²h, 0)` only, i.e. deposit in hollows and never cut the ridges) is
what people mean by "local sediment deposition": valley floors fill and
flatten while peaks keep their edges.

**Expressible today**, entirely from the map ops:

```lua
-- one diffusion step on `h`, in place
local m = game.map{ name = "h_mean", side = S, scale = SC }   -- scratch
m:combine(h, "add")             -- copy (m starts empty)
m:blur(1)                       -- 3x3 box mean == neighbours + self
h:scale_by(1 - k); m:scale_by(k); h:combine(m, "add")
-- deposit-only: replace the last line with
--   m:combine(h_neg, "add"); m:clamp(0, 1e9); h:combine(m, "add")
-- where h_neg is h scaled by -1 (a second scratch map)
```

Cost: a 1,024² box blur is ~1M samples a pass; fifty passes is well under
a second, once per world. Deterministic: whole-array ops in fixed order.

What it gives: smoothed valley floors, softened saddles, rounded lower
slopes. What it does NOT give: drainage. There are no channels, no branching
valleys, no rivers — diffusion has no direction. On its own it makes the
relief read as old and worn rather than as a country with rivers. It is a
finishing pass, not the erosion.

### 2. Thermal (talus) erosion

Material above the angle of repose slides downhill until the slope is under
it. Needs, per sample, "how much higher am I than my lowest neighbour" —
directional, so `blur` cannot express it. **Needs a native op** (`Map:talus{
angle, passes }`), O(n) per pass, trivially deterministic. Gives scree
slopes and cliff bases; still no drainage.

### 3. Diffusion-limited aggregation (DLA)

Random walkers stick to a growing cluster; the cluster is a branching tree.
Draw it as ridges (or invert it as valleys), blur it in stages and add the
stages together, and you get a heightmap whose valleys BRANCH — the shape of
a drainage network, without simulating water. It is the cheapest thing that
produces the branching a Laplacian never will.

**Needs a native op** (`Map:dla{ seed, walkers, stickiness }`): walkers are a
loop with random steps, which is per-sample work no map op can express. Cost
on a 512² grid, ~20k walkers × a few thousand steps each ≈ 10⁷ integer steps
— tens of milliseconds native. Deterministic with a seeded stream and a
fixed walker order.

Limits: the network is a fractal tree with no respect for the existing
relief — it does not flow downhill, it just branches — so it has to be laid
OVER a relief field (as `combine("min")` of a blurred, inverted cluster) and
tuned so its trunks land in the basins. On the Spindle that is tractable
because the drainage is known in advance: every river runs outward from the
axis to the rim, so the DLA would be seeded at the rim and grown inward.

### 4. Hydraulic erosion, particle (droplet) method

Beyer's method: drop a particle, let it flow downhill carrying sediment,
erode where it speeds up, deposit where it slows. Tens of thousands of
droplets carve a heightmap into something that looks like real ground —
channels, alluvial fans, incised valleys. The standard choice for
"Minecraft-but-better" terrain.

**Needs a native op** (`Map:droplets{ seed, count, ... }`). Cost: 200k
droplets × ~30 steps ≈ 6·10⁶ steps of gradient-and-bilinear work — a few
hundred ms native on 1,024², once per world. Determinism: fine with a seeded
stream, fixed order, and the gradient normalised with `sqrt` (IEEE-exact,
allowed) — no trig anywhere. The catch is that droplets are sample-scale, so
at 115 blocks per sample the channels are 115 blocks wide; it wants the
finer map.

### 5. Stream-power erosion with flow routing (Fastscape)

Route flow downhill (D8), accumulate drainage area, then erode each sample by
`K · A^m · slope^n` using the implicit scheme of Braun & Willett (2013),
which is O(n) per iteration and unconditionally stable. This is what
geomorphologists use; it produces properly organised drainage with a river
network that is a consequence of the relief rather than laid over it.

**Needs a native op** (`Map:stream_power{ iterations, k, m, n }`). Cost:
O(n) per iteration with one sort of samples by height; 50 iterations on
1,024² is a second or so, once per world. Deterministic: the routing is
integer, the erosion is `+ - * /` and one `powf`-free formulation if `m = n
= 1` (or a committed table for other exponents). Gives, as a by-product, the
**drainage-area map** — which is where the rivers ARE, and what a river fill
would read.

### 6. Nothing but noise (the current approach)

Ridged/billow noise and domain warping fake the LOOK of erosion — sharp
ridges, warped valleys — with no simulation. Cheap, per-sample, works inside
a density field today. Neither `ridged` nor a domain-warp node exists yet in
the density DSL (`abs` fakes ridged at one extra op; warp needs a node that
feeds one noise's output into another's coordinates).

## Side by side

| Method | Drainage? | Engine work | Once-per-world cost (1,024²) | Fineness |
|---|---|---|---|---|
| Laplacian stencil | no | none | < 1 s | sample |
| Thermal | no | small op | < 1 s | sample |
| DLA | branching, imposed | medium op | ~0.1 s | sample |
| Droplet hydraulic | yes, local | medium op | ~0.5 s | sample |
| Stream power | yes, organised | medium op | ~1 s | sample |
| Noise only | no | small DSL nodes | per chunk | block |

## The engine asks, in order of size

1. **`{ op = "map", name = "..." }` density node** — samples a named map at
   the block's `(x, z)`, bilinearly, the value at `y` ignored. One enum
   variant and one match arm; the map read already exists. **This is the
   gate for everything above**: without it no map can shape the Spindle.
2. **`Map:fill(density)`** — evaluate a density program over the map's
   samples at `y = 0` and write the result in. Lets the dome, the rings and
   the humidity live in the map, so erosion runs on the real relief and not
   on a placeholder.
3. **Bigger or tiled maps** — either raise the 1,024 cap (a 4,096² f32 map
   is 64 MB, stored once) or let a mod own several maps by region. This
   decides whether valleys are a hundred blocks wide or sixteen.
4. **One erosion op.** If one, `stream_power` — it is the only one whose
   rivers are a consequence of the land, and its drainage-area output is the
   river map for free. `droplets` is the second choice and easier to tune by
   eye. `dla` is worth having as a cheap stylised alternative but should not
   be the only one. `talus` is small and pairs with any of them.

## What to do meanwhile

The Laplacian stencil can be prototyped **today** in a test domain using
`fill_below_heightmap` alone (no dome, flat world, one map), to see what the
deposit-only variant does to noise relief at 16 blocks per sample. That is
worth an hour and answers "does this finishing pass earn its place" before
any engine work — and it is a domain, so it composes with the Spindle rather
than replacing it.

In the density field, the things that read as erosion without being it —
terraces (`clamp` of a steep noise), boulders (a thresholded high-frequency
noise in the band just above the surface), a ridged term via `abs` — are in
`shape.lua` now and cost one noise node each.
