# Spindle — mod plan, density-first

*Draft 2, 2026-09-06. Supersedes draft 1's engine section; the world design in
draft 1 stands and is condensed in Part C.*

The approach here is the one the game designer asked for: **build on the
density API as it exists today, measure, and let the result decide what the
engine needs next** — the full map pre-pass, or something much smaller.

---

## Part A — Engine readiness

Audited from the `Tiamot-Voxel-Game-main` tree (read, not built). The build
plan runs through Task 16 and the tree carries work from every task,
including 15a domains and 15b LOD, so the engine is at or past its release
milestone.

### A.1 What the mod API offers for worldgen today

| Mechanism | Where | Notes |
|---|---|---|
| `game.density{...}` | `api/stubs/game.lua`, `detgen/density.rs` | Compiles a nested table to a native postfix program over whole arrays, f32, block resolution. Ops: `const`, `x`, `y`, `z` (world coords), `noise` (3D fBm only; `stream` name → seed), `abs`, `clamp{low,high}`, `add sub mul div min max`. Limits: 256 ops, 8 live buffers, 64 nesting. |
| `buf:fill_density(field, material)` | same | Fills every block where the field is **> 0**. Fill `game.AIR` to carve. Fills run in order; later ones overwrite. Measured: 358 µs for one noise node per 16³ chunk, 719 µs for terrain-with-caves. |
| `buf:fill_below_heightmap`, `game.noise_heightmap`, `game.flat_heightmap` | same | 2D fBm heightmap; `base` is an integer per call. 52 µs per chunk. |
| `buf:fill_all`, `buf:set_block` | same | Block-resolution writes. `set_subnode` expands to 48³ and costs 27× — not used by Spindle. |
| `game.rng_stream(pos, name)` → `:below(n)`, `:next_bool()` | same | Named, per-chunk, uncorrelated streams. Integer draws only — deterministic by construction. |
| `game.register_on_generate(fn)` | `mlua_vm.rs` ~L904 | The overworld runs **every** registered generator, in mod load order. A Spindle world either omits `core_worldgen` from `mods_path`, or Spindle runs after it and starts with `fill_all(AIR)`. |
| `game.register_domain{ generator = ... }` | same | Separate voxel spaces with their own generator. Not needed for Spindle's main world; noted for pockets (C.7). |
| `game.register_block{ light_emit, hardness, dominance, absorbs, sounds, tags }` | same | Everything a layer needs to look and feel different. |
| Fluids | `register_fluid`, `set_fluid` | Conserved, block-resolution, no sources. `set_fluid` is a **world** operation and is not available in `on_generate`; there is no `fill_fluid` on the buffer. |
| Trig tables | `detgen/trig.rs` | Committed sin/cos/atan2 exist in core, exposed only as `game.heading`. Not a density node. |
| World extents | `coords.rs` | `[−60,000, 59,999]` on every axis, 3,750 chunks per half-axis. As assumed. |

### A.2 What is missing, ranked by how small the fix is

1. **`sqrt` node.** The stub's comment says it is excluded because it differs
   between platforms. Charter rule 4 and `docs/float-determinism.md` say
   `sqrt` is IEEE-exact and allowed. One enum variant and one match arm.
   Not needed for the spike — squared distances work — but it is what a
   true cone-blend dome and an exact ellipsoidal *distance* (as opposed to
   an inside/outside test) want.
2. **2D noise node** (`noise2`: sample at `(x, z)`, ignore `y`). `fractal_2d`
   already exists in `noise.rs`. This is the single most consequential small
   ask: it is the difference between heightmap-style relief and 3D-noise
   relief, and A.3 explains why that matters at Spindle's scale.
3. **`ridged` / `billow` on the noise node.** Both variants exist in core
   (`Fractal` enum) and are not reachable from Lua. `abs` emulates ridged at
   one extra op; not urgent.
4. **`ramp` / `spline` node** (piecewise-linear over an input). Emulated today
   as a sum of clamped ramps at ~6 ops per knot; the `W(Y)` table costs ~60
   of the 256-op budget. A node makes that 1.
5. **`step` node** (sign → 0/1). Emulated as `clamp(mul(a, 1e6), 0, 1)`.
6. **`fill_fluid(field, fluid, volume)` on the buffer.** The first item that
   is not a one-liner: it needs the solver to accept generated fluid without
   waking it, i.e. draft 1's *dormant fluid*. Until it lands, every body of
   liquid in Spindle is a look-alike solid block.
7. **Biome registry / ore placer / pre-pass maps.** The large items from
   draft 1 §10. Whether any of them is needed is what the spike decides.

### A.3 The one structural limit: relief from 3D noise

The density example in the stubs — `noise − 0.06·y` — is the standard trick:
a 3D field with a vertical gradient. The surface is where `A·n(x,y,z) = k·(y − H)`.
It only stays a *surface* (no overhangs, no floating land) while the
gradient `k` exceeds the noise's own vertical derivative, roughly `A / λ` for
an octave of wavelength `λ`. Under that condition the relief is bounded:

```
relief  ≈  0.42 · A / k   <   0.42 · λ
```

So a 3D-noise surface cannot have more than about 40% of its largest
wavelength in overhang-free relief. For 15,000 blocks of mountains that means
a base wavelength of ~36,000 — ranges 36,000 blocks wide, which is not a
range, it is a continent tilting. Everything sharper than that either has
less relief or has overhangs at the scale of the feature.

This is not a bug; it is what 3D noise is. The heightmap path
(`noise_heightmap`) has no such limit but cannot be combined with the dome or
the caves. The spike (Part B) uses 3D noise anyway, with `λ = 12,000` and
5,000 of relief, because that is enough to answer "does noise relief look
like country at this scale?" — and if the answer is no, the fix is either
item 2 above (2D noise node: small) or the erosion pre-pass (large). That
is exactly the decision the designer wants the spike to make.

---

## Part B — Phase 1: the density spike

**Goal.** The whole world's silhouette and layer stack, generated entirely
through today's API, with no engine changes. Bare materials, placeholder
textures, a first cut at cave families and surface rings. Enough to fly
through every layer, dig from the Crown into the Char, drop down a Well,
walk to the rim, and — the point — see what 3D-noise relief gives us.

**Not in scope.** Erosion, rivers, rain shadow, ore realism, pockets, the
Winding Stair, sounds, anything perceptual beyond "is it the shape".

### B.1 Frame and scale

All fields work in **kilo-blocks**: `xs = x / 1000`, `zs = z / 1000`,
`Ys = (y − 11,000) / 1000`. Squares of world coordinates reach 3.5 × 10⁹,
where f32 has a resolution of ~256; squares of scaled coordinates stay under
4,000, where the resolution is ~0.0002 — two thousandths of a block. The
scaling costs 3 ops per axis and buys the whole design.

```lua
local S   = 0.001
local Y0  = 11000           -- world y at Spindle Y = 0
local xs  = { op="mul", a={op="x"}, b={op="const", value=S} }
local zs  = { op="mul", a={op="z"}, b={op="const", value=S} }
local Ys  = { op="mul", a={op="sub", a={op="y"}, b={op="const", value=Y0}},
              b={op="const", value=S} }
local r2  = { op="add", a={op="mul", a=xs, b=xs}, b={op="mul", a=zs, b=zs} }
```

Every program below starts from these; subexpressions are Lua tables and can
be shared, but each *program* is compiled once at load and captured.

### B.2 The dome without `sqrt`

`H` must be a function of `r²`, so the profile is a polynomial in `u = r²/R²`:

```
u     = r2 / 59²                       (R = 59,000 → 3.481 in km²)
f(u)  = 2u − u²                        flat top, flat rim, f(0)=0, f(1)=1
H(u)  = 19 − 2.5 · f(u)                in km; +19,000 at centre, +16,500 at rim
```

Grade is `2,500 · (4t − 4t³) / 59,000`: zero at the centre, a maximum of
**6.5% (3.7°) at 34,000 out**, zero again at the rim. Draft 1's parabola-to-
cone profile (max 4.8%) needs `sqrt`; this is the best sqrt-free shape and
the difference is not something the spike can perceive.

Terrain field, in km, positive below ground:

```
T = H(u) − Ys + A·n₁(x,y,z) + a·n₂(x,y,z)
    n₁: stream "relief",  5 octaves, frequency 1/12,000 (in blocks), A = 12 (km)  → ~5,000 relief
    n₂: stream "detail",  3 octaves, frequency 1/600,               a = 0.25      → ~100 of texture
```

with the gradient `k = 1` implicit (one km of density per km of depth). This
puts `n₁` right at the overhang limit of A.3 on purpose: the spike should show
what the limit looks like.

**Ring-dependent relief.** Multiply `n₁` by a radial mask so the Crown is a
massif and the Greensward is rolling: `m(u) = clamp(1.6 − 2u, 0.3, 1.0)`
(strong at the centre, 30% by the hot ring). One `clamp`, two ops.

### B.3 The body and the needle, as clamped ramps

`W(Y)` from draft 1 §2.2 is piecewise linear in `Y`. Any such function is a
sum of clamped ramps; from the top down:

```lua
-- knots (Y km, W km), top to bottom
local KNOTS = {
  { 16.5, 59.0 }, {  3.1, 58.5 }, { -8.0, 46.0 }, {-12.0, 30.0 }, {-16.0, 16.0 },
  {-25.0,  6.0 }, {-37.0,  2.0 }, {-50.0,  1.3 }, {-63.0,  0.9 }, {-70.0,  0.0 },
}
-- W(Y) = W_top + Σ slope_i · clamp(Y − Y_i, ΔY_i, 0)   for each downward segment
```

Ten knots, nine segments, ~55 ops, and the running sum never holds more than
three live buffers. Inside-the-body test, in km²:

```
B = W(Ys)² − r2          (positive inside; the apex is where W reaches 0)
```

Below `Y = −70` (`W` would go negative) `B` is negative everywhere, which is
correct. Add the surface warp — `0.4·n₃(x,y,z)`, stream `"flank"`, 2 octaves,
frequency 1/4,000 — to `W` before squaring, scaled by `W` itself so the
needle is not warped wider than it is: `W' = W · (1 + 0.15·n₃)`.

**Solid = below the dome AND inside the body:** `solid = min(T, B)`. Units
differ (km vs km²) but only the sign matters to a fill, and `min` preserves
the sign of whichever is negative.

### B.4 The core stack on squared ellipsoidal distance

With `k = 3.7` and the stack centre at `Ys = 3.1`:

```
E2 = r2 + (3.7 · (Ys − 3.1))²                            -- 6 ops, shared
inside(R) = R² − E2                                      -- 2 ops per shell
```

| Shell | `R` (km) | Fill | Material |
|---|---|---|---|
| Cinder margin | 57.5 | `min(solid, inside(57.5), −inside(55.0))` | `spindle:cinder` |
| Magma shell | 55.0 | `min(solid, inside(55.0), −inside(54.2))` | `spindle:magma_still` (solid look-alike; see A.2 item 6) |
| Outer magical | 54.2 | `min(solid, inside(54.2), −inside(50.3))` | `spindle:lantern_stone` |
| Slime border | 50.3 | `min(solid, inside(50.3), −inside(49.7))` | `spindle:caul` |
| Inner magical | 49.7 | `min(solid, inside(49.7), −inside(46.0))` | `spindle:dream_stone` |
| Hollow rind | 46.0 | `min(solid, inside(46.0), −inside(37.0))` | `spindle:scorch` |
| The Hollow | 37.0 | `inside(37.0)` | `game.AIR` |

Each fill is under 20 ops and has no noise in it, so the whole stack costs
tens of microseconds per chunk. The magma's 500-block "fade" and the Caul's
Throats are noise terms added to the relevant `R` — `R + 0.5·n₄` — and are
the only noise the stack needs; they can wait for phase 2.

**The core clamp** (draft 1 §6.0: the core is never within 500 of the
surface) is `min(inside(R), T − 0.5)` on the cinder margin only. Two ops.

### B.5 Depth bands without a depth field

There is no way to ask "how far below the *actual* surface am I" from a
density program, because the surface is itself the zero set of `T`. The
spike uses `T` as a proxy: at the surface `T = 0` and it grows by ~1 km per
km of depth plus the noise's vertical variation, which at `λ = 12,000` is
about 5% of `A` per 1,600 blocks of depth — a ~600-block error at the bottom
of the normal band. For the underside, the same trick on `B` divided by
`2W` (the gradient of `W²` is `2W·W'`; in the near-vertical stretches this
is close enough).

```
D ≈ min(T, B / (2·W))                  -- km below the nearer surface
band(lo, hi) = min(D − lo, hi − D)     -- positive inside the band
```

Cave fills, each `fill_density(min(band, caves), AIR)`:

| Band | `D` (km) | Cave field | Cost |
|---|---|---|---|
| Surface | −0.05 … 0.10 | `0.12 − |n₅|`, stream `"karst"`, freq 1/40 | 1 noise node |
| Normal | 0.10 … 1.6 | spaghetti `0.08 − max(|n₆|, |n₇|)` freq 1/90, cheese `n₈ − 0.55` freq 1/200 | 3 nodes |
| Gloam | 1.6 … 4.0 | spaghetti freq 1/300, cheese freq 1/600, threshold 0.5 | 3 nodes |
| Abyss | > 4.0 | cheese only, freq 1/1,500, threshold 0.45 | 1 node |

The depth proxy is the first thing the spike is expected to show is not good
enough — it is fine for "are the families in the right places" and wrong
under any mountain taller than the band. An exact `D` needs either the map
layer or a 2D-noise surface the field can subtract.

### B.6 Surface rings and materials

No biome registry, so a biome is a material fill masked by its ring. With
`t² = u` the ring boundaries from draft 1 become thresholds on `u`
(`0.08 → 0.0064`, `0.18 → 0.032`, `0.35 → 0.12`, `0.42 → 0.18`, `0.48 → 0.23`,
`0.6 → 0.36`, `0.85 → 0.72`, `0.9 → 0.81`). Ring mask:
`min(u − u_lo, u_hi − u)`. The spike fills **one surface material per ring**
into the top layer only: `min(ring, T, 0.003 − T)` — a 3-block skin — over
the base stone fill. Eight rings, no noise, cheap. A wet/dry split within a
ring is one more mask from a slow noise `n₉` (stream `"humidity"`, freq
1/9,000), which is what makes the rings not look like a target.

### B.7 Chunk gating in integer Lua

Every field above is cheap except its noise nodes, and most of the world's
chunks are solid rock or air in which no noise can matter. `on_generate`
receives integer chunk coordinates; integer arithmetic in Lua 5.4 is exact
and deterministic, so a **conservative** classification per chunk is allowed
and is what keeps generation under budget:

```lua
-- world-block bounds of the chunk, integers
local x0, x1 = pos.x * 16, pos.x * 16 + 15
local z0, z1 = pos.z * 16, pos.z * 16 + 15
local Y0, Y1 = pos.y * 16 - 11000, pos.y * 16 + 15 - 11000
-- min and max r² over the footprint, integers (64-bit)
local r2min, r2max = ...   -- 0 if the chunk straddles an axis
```

Then, with margins that exceed every noise amplitude in play (relief 5,000,
flank warp 400, caves 200):

| Test (all integer) | Action | Cost |
|---|---|---|
| `Y0 > 19,000 + 5,200` | air; return | ~0 |
| chunk entirely outside `W_max(Y)+600` for its `Y` range | air; return | ~0 |
| entirely inside the Hollow's ellipsoid with 600 margin | air; return | ~0 |
| entirely below the dome − 5,200 **and** deeper than 4,600 from the flank **and** outside every shell by 600 | one `fill_all(stone)` + the abyss cheese fill | 1 node |
| within 600 of any shell boundary | shell fills, no relief noise | ~0 |
| otherwise (near a surface) | the full pipeline | 8–10 nodes |

Only the last row runs relief and surface caves. The classification is
conservative in every direction, so a chunk near a boundary can only pay
more than it needed, never generate differently. `W_max(Y)` for the test is
the same knot table evaluated in integer Lua — it is the *bound*, not the
field; the field is the density program.

### B.8 Cost budget

From the engine's numbers (358 µs per noise node per chunk, 53 µs for a
heightmap chunk; `docs/performance-targets.md` records the opt-in 3D path as
"costing milliseconds"):

| Chunk class | Noise nodes | Estimate |
|---|---|---|
| Air, interior, far shell | 0 | < 50 µs |
| Deep solid | 1 | ~0.4 ms |
| Near a surface | 9–10 | **3.2–3.6 ms** |
| Near a surface, with 3 ore masks | 12–13 | ~4.5 ms |

A player's initial view at 16 chunks radius on a mostly-surface region is
~2,000 surface chunks — about 7 s of one core, spread over the worker pool.
Acceptable for the spike; the number to report is the near-surface figure as
a multiple of the engine's 53 µs heightmap baseline (≈ 65×) so the decision
in B.10 is made on the real cost.

### B.9 Ores in the spike

Two ways, both deterministic; the spike does both and compares:

- **Density masks.** `min(band, n_ore − θ)` at a high frequency gives blobs
  at a controlled density; exact band placement, 1 noise node per ore, gated
  so only 2–4 ores run per chunk class.
- **Stream scatter.** `game.rng_stream(pos, "ore:iron"):below(n)` for count
  and position, `set_block` for a small vein; ~0 cost, but band placement is
  by chunk class rather than by `D`, so a vein can land in the wrong band
  near the surface.

Diamonds are `min(inside(58.3), −inside(57.5), n − θ)` — a band of `E`, and
the one ore whose placement the density path gets exactly right today.

### B.10 Gates, and what they decide

Agent-verifiable:

- [A] The mod loads with `server --check-mods`; every density program
  compiles under 200 ops and 6 live buffers (`Density:len()` logged).
- [A] A column at the axis from `y = +30,000` to `−59,000` generates with the
  bot in under 3 minutes, and its layer sequence, sampled every 100 blocks,
  matches the table in C.1.
- [A] The same for a column at `r = 40,000` and one at `r = 58,000`.
- [A] Chunk classes: ≥ 95% of chunks in a 200-chunk cube centred on
  `(30,000, 0, 0)` take the cheap rows of B.7.
- [A] Determinism: a fixed set of 40 chunks — summit, rim, flank at
  `Y = −8,000`, needle at `−50,000`, the Eye, each shell — hashes
  identically on Linux, Windows, macOS.
- [A] Per-class cost measured with `criterion`, reported as multiples of the
  53 µs baseline.

Human gates — these are the decision:

- [H1] **Relief.** Fly the Crown and a spoke at 5,000 of relief. Does 3D-noise
  relief at `λ = 12,000` read as mountains, or as lumps and shelves? Are the
  overhangs at the limit acceptable, ugly, or the best part?
- [H2] **Drainage.** Standing in the Greensward, is the absence of rivers and
  valleys the thing you notice first?
- [H3] **Depth bands.** Dig from a mountain top. Do the cave families change
  where they should, or where the proxy says?
- [H4] **Silhouette.** Fly the rim, the underside, the needle. Is it the sketch?
- [H5] **Cost.** With 4 players spread across the surface, does the server
  keep up with generation?

**Decision rule.**

| Outcome | Next engine work |
|---|---|
| H1 no, H2 yes | **The map layer** (draft 1 §10.1): tectonics + erosion + flow. Relief and rivers are global facts; no local fix produces them. |
| H1 yes-ish, H2 tolerable | **Small asks 1–5** in A.2: `sqrt`, `noise2`, `ridged`, `ramp`, `step`. Heightmap-style relief inside density, exact `D`, and a 4× smaller op budget. Rivers stay absent. |
| H3 fails, everything else passes | `noise2` alone, for an exact `D`. |
| H5 fails | Explicit SIMD in `fill_3d` (engine, with its own determinism argument) before anything else; nothing in the design changes. |
| Any outcome | `fill_fluid` (A.2 item 6) — the Hollow needs its sea and the world needs its lakes regardless of which branch is taken. |

---

## Part C — The world (condensed from draft 1)

Everything here is design and is unchanged by the engine audit except where
marked. Each feature is tagged **[now]** — expressible on today's API, in the
spike or phase 2 — or **[needs …]** with the smallest engine item from A.2
that unlocks it.

### C.1 Geometry

Spindle frame `Y = y − 11,000`. Disc radius `R = 59,000`. Horizontal
distance `r = √(x² + z²)`, used squared throughout.

| Landmark | Y | Horizontal semi-axis |
|---|---|---|
| Summit (dome, before mountains) | +19,000 | — |
| Rim | +16,500 | 59,000 |
| Stack centre | +3,100 | — |
| Cinder margin | ±15,800 about the centre | 57,500 |
| Magma shell | ±15,000, 800 thick, 500 fade | 55,000 |
| Outer magical caves | ±14,200 | 54,000 |
| Slime border (the Caul) | ±12,600, 600 thick | 50,000 |
| Inner magical caves | ±11,600 | 48,000 |
| Hollow rind | ±11,000 | 46,000 |
| The Hollow (void) | ±9,300 | 37,000 |
| Body narrows to 8,000 wide | −25,000 | — |
| Needle begins (~2,000 wide) | −37,000 | — |
| Apex | −70,000 | — |

Squish factor `k = 3.7`. The dome profile is the sqrt-free quartic in B.2
**[now]**; the parabola-to-cone profile is **[needs sqrt]**. The body is the
knot table in B.3 **[now]**.

Above the summit: 30,000 of air. Below the apex: 1,000 of void, then the edge
of the volume.

### C.2 Depth bands — the cave families

Measured from the nearer surface, top or underside.

| Band | Depth | Name | Contents |
|---|---|---|---|
| Mountain caves | above −50 | — | caves in peaks take the peak's biome |
| Surface band | −50 … 100 | — | karst, sinkholes, springs; ice caves in the Crown, lava tubes on the Ember Ridge, root-hollows under Oakhold |
| Normal caves | 100 … 1,600 | — | spaghetti, cheese, noodle, ravines, aquifers, geodes, glowcap groves |
| Dark caves | 1,600 … 4,000 | the Gloam | Nightglass chambers, the Lichen Veins, the Drip |
| The Abyss | > 4,000 | the Still, the Petrified Wood, the Drowned Vaults, the Bone Fields | chambers a kilometre across |

Families by band: **[now]** with the proxy depth of B.5; exact placement under
tall terrain is **[needs noise2]** or the map layer. Aquifers (flooded below a
water table) are **[needs fill_fluid]**; until then, "flooded" is a solid
water-look block.

### C.3 The surface

**Climate.** Temperature is radial, `T = 4t(1−t)` in `t = r/R` — cold at
the centre, hot at `t = 0.5`, cold at the rim — minus one band per 3,000 of
altitude above the base dome. Rain is moisture advected *outward* from the
axis and dropped on windward (axis-facing) slopes, so every range's rim-ward
side is dry. Biome is a (temperature, rain) lookup.

Rings by `t` **[now]**, humidity from slow noise **[now]**, humidity from rain
shadow **[needs map layer]**.

**Relief.** A ring range over the hot belt (the Ember Ridge) and 5–9 spoke
ranges from the Crown; between spokes, basins draining rim-ward; erosion
giving the ranges drainage and the valleys their shape. Spoke placement is
**[now]** as a noise term multiplied by an angular mask — angle needs the trig
table, so in the spike the spokes are placed by a second low-frequency noise
rather than by angle; that is acceptable for [H1]. Erosion is
**[needs map layer]**; nothing smaller produces it.

**The rings**, centre outward: the Crown (ice cap, glacier valleys, steam
from the fire 500 below); Frostmoor and Firwold; the Greensward, Oakhold,
the Fen, the Downs; the Ember Ridge (volcanic, the only surface sign of the
magma shell); the Glass Waste, the Verdant Belt, Goldwater; the Long Shore;
the Hem (rim tundra, then the ice desert the Rimfall's spray makes, ending in
a cliff of frozen falls). Mountain forms for every biome above 6,000 of local
altitude. All **[now]** as material fills; their *content* (trees, grass,
snow layers) is phase 3 and mostly `set_block` scatter.

**Rivers and the Rimfall.** Every river runs outward and goes over the rim;
the Rimfall sheets down the flank; all of it ends at the Wellspring near the
apex. Rivers **[need map layer + fill_fluid]**. The Rimfall as a visual is
**[needs fill_fluid]**; as a generated look-alike it is **[now]** and ugly.

**The underside.** The Keel (flank, `Y > −25,000`): spray-fed hanging moss,
dripstone, the cave mouths that are the only entrances from outside. The
Spire (the needle's exterior): dry, cold, a 33,000-block climb, banded by the
tail biomes beneath. Both **[now]** as bands of `Y` on the outside of `B`.

### C.4 The core stack

| Layer | Character | Status |
|---|---|---|
| **The Char** (cinder margin) | cooked dark caves: basalt columns, obsidian, ash; diamonds on both sides of the magma | [now] |
| **The Girdle** (magma shell) | 800 of lava with crust; cooled plugs one per 5,000 as crossings | shape [now]; lava as fluid [needs fill_fluid]; plugs [now] via noise on `R` |
| **The Lantern Halls** (outer magical) | light-emitting crystal, floating stone, grown-looking geometry; Crown Vault / Flanks / Underhalls by position on the ellipsoid `(Ys − 3.1)·k / E` | [now]; the position scalar [needs sqrt] — use `E2` thresholds instead |
| **The Caul** (slime border) | a luminous solid membrane, bouncy, slow to dig, reflows over minutes via `on_tick`; Throats one per 4,000 | block fields [now]; reflow [now]; Throats [now] via noise on `R` |
| **The Dreaming Deep** (inner magical) | shaped chambers — spheres, thousand-block straight corridors, stairs; holds the pockets | [now] |
| **The Scorch** (rind) | dense, hot, dry; no caves; the Wells, one per 3,000, sheer 3,200-block shafts to the Hollow's ceiling | [now]; Wells are a scatter from a stream keyed on a coarse grid so both ends agree |
| **The Hollow** | 74,000 × 18,600 void: the Ceiling (Dripstone Forest, the Hanging Wastes), the Middle Air (hanging islands 20–2,000 across), the Floor (Furnace Sea, Basalt Deltas, Ash Flats, Bone Fields), and the Axle — a solid pillar 1,200 wide from floor to ceiling on the world's axis | void and Axle [now]; islands [now] as a sparse noise threshold; the Furnace Sea [needs fill_fluid] |

### C.5 Pocket worlds

Sealed oblate voids 200–800 across in the Dreaming Deep, one per 6,000 of
shell, with no natural entrance; the shell's tunnels bend around them. Kinds:
a Garden, a Drowned Pocket, a Mirror, a Frozen Pocket, an Echo (a 100-block
model of the world), an Empty Pocket. `spindle.on_pocket(fn)` lets other mods
claim pockets by kind.

**[now]**: scatter from a coarse-grid stream, each pocket a small ellipsoid
subtracted from the shell's solid and filled by kind. An alternative the
audit turned up: a pocket as an **instanced domain** reached through a
one-block portal — sealed by construction, its own generator, and other mods
could register kinds as templates. That is a design choice, not an engine
gap; both are open.

### C.6 The tail

| Band | Y | Name | Contents | Status |
|---|---|---|---|---|
| Upper tail | −37,000 … −50,000 | the Marrow | vertical shafts hundreds wide, water falling their length, white porous stone | shafts [now]; water [needs fill_fluid] |
| Mid tail | −50,000 … −63,000 | the Long Quiet | one cave: the Winding Stair, a 60-wide helical gallery, one turn per 1,500 | **[needs trig node]** — the helix is an angle test; the committed tables exist in core, not in the DSL. Placeholder in the spike: a straight shaft |
| Lower tail | −63,000 … −70,000 | the Stinger | the Wellspring at −68,000, 400 across; the Eye of the Needle, a 40-wide shaft to the apex, open below | [now] |

### C.7 Ores

Triangular density curves over a scalar — proxy `D` for the ordinary ores,
`E` for the core's, `Y` for the tail's — placed by density mask or stream
scatter (B.9). The table from draft 1 §8 stands: coal, copper, tin, iron,
silver, gold (plus river-gravel placer **[needs map layer]**), lead, emerald
(spokes only), diamond at `E ≈ 57,900` and `54,600`, Glimmer, Brimstone,
Ashen iron, Starmetal at the apex, Nightglass as a material. Ore *identity*
is a block registration; *placement* is the table; a mod wanting a different
economy overrides the table.

---

## Part D — Task files

In the charter's format. **S** for Spindle; engine asks are named as they
arise and go into the engine's own prompt sequence, not here.

**S01 — The spike (Part B).** One session, maybe two.
- [A] All of B.10's agent gates.
- [H] All of B.10's human gates, with the decision rule applied and the
  outcome written into `docs/spindle-spike-verdict.md` before S02 starts.

**S02 — Engine asks, whichever branch.** Not a Spindle task; the verdict
names the engine prompt(s). Two possible shapes:
- *Small:* one engine session adding `sqrt`, `noise2`, `ridged`/`billow`,
  `ramp`, `step` to the density DSL, each with a determinism test and a
  stub entry (`scripts/check-stubs.sh` will insist).
- *Large:* draft 1's W01 (pre-pass and map store) and a `map` density node.
- *Either:* `fill_fluid` with dormant fluid (draft 1's W04).

**S03 — The shape, finished.** `shape.lua` on the new nodes: exact dome,
exact `D`, Throats, plugs, Wells, the Eye. Placeholder blocks with real
textures.
- [A] Layer sequence at 12 columns matches C.1 to the block.
- [A] Every Throat connects the two magical layers; every Well lands on the
  Ceiling (flood-fill tests through the bot).
- [H] The underside and the needle, on foot.

**S04 — Surface.** `surface.lua`: rings, humidity, mountain forms, the Ember
Ridge, the Hem. Trees and cover as scatter.
- [A] Biome coverage: no ring under 0.5% or over 25% of the disc.
- [H] Walk 5,000 blocks rim-ward. Does it feel tilted? (It should not.)
- [H] Stand on a spoke. Is it a range?
- If the large branch: rivers, rain shadow, the Rimfall, and the [H] "does it
  look like the country the fellowship walked through".

**S05 — Caves.** `caves.lua`: the four bands and their sub-biomes.
- [A] Families only in their band, sampled.
- [H] Dig from the Greensward to the Gloam; note where it changes.

**S06 — The core.** `core.lua`: Char, Girdle, Lantern Halls, Caul, Dreaming
Deep, Scorch. The Caul's reflow.
- [A] Reflow closes a 3-block tunnel within 5 minutes of game time.
- [H] Break into the Char from the Crown. Is 500 the right distance for that
  to be a shock?

**S07 — The Hollow.** `hollow.lua`: ceiling, middle air, floor, the Axle.
- [A] Axle solid floor to ceiling; islands hang; the Furnace Sea is fluid
  (if `fill_fluid` has landed) or a placeholder (if not, and say so).
- [H] Drop down a Well. Report.

**S08 — Pockets.** `pockets.lua`, and the domain-vs-in-world decision.
- [A] Every pocket sealed (flood-fill). `on_pocket` called once per pocket
  per world, in a fixed order.

**S09 — The tail.** `tail.lua`: Marrow, the Stair (needs the trig node or a
straight placeholder), Stinger, Wellspring, the Eye.
- [A] The Stair is one connected gallery; the Eye is open below.
- [H] Walk the Stair.

**S10 — Ores, sounds, and the evening.** `ores.lua`, `sounds.lua`, a tuning
pass over every constant.
- [A] Ore density per band within 10% of the table.
- [H] Play for an evening. Write down everything that felt wrong.

---

## Part E — Mod layout

```toml
id = "tiamot_default_world"
name = "Spindle"
version = "0.1.0"
depends = ["core >=0.1", "core_sky >=0.1"]
description = "A spindle-shaped flat earth with a fire-cored hollow. A world, not a fixture."
```

A Spindle server's `mods_path` points at a directory without
`core_worldgen`; if both are present Spindle's generator runs after it and
begins with `fill_all(game.AIR)`, which costs nothing and makes the mod
order irrelevant.

| File | Owns |
|---|---|
| `init.lua` | loads the rest in order; `register_on_generate` with the B.7 gate at the top |
| `shape.lua` | the shared subexpressions (B.1), `H`, `W`, `E2`, `solid`, the proxy `D` |
| `surface.lua` | rings, humidity, mountain forms, cover |
| `caves.lua` | the four bands |
| `core.lua` | the shells and the Caul's reflow |
| `hollow.lua` | the Hollow's interior and the Axle |
| `pockets.lua` | scatter, kinds, `spindle.on_pocket` |
| `tail.lua` | Marrow, Stair, Stinger, Wellspring, the Eye |
| `ores.lua` | the table |
| `blocks.lua` | every block, with textures and `light_emit` |
| `sounds.lua` | ambience per band via the sky mod's loop mechanism |

Every constant is a named local at the top of its file. Every density program
is compiled once at load and captured; `Density:len()` is logged for each so
the op budget is visible in `server --check-mods` output.

---

## Part F — Corrections to draft 1

- The dome profile is a polynomial in `r²` (B.2) until `sqrt` exists;
  maximum grade 6.5% at 34,000 out rather than 4.8% at the rim.
- Ellipsoidal *distance* `E` is replaced by squared distance `E2`
  everywhere; the "position on the shell" scalar for the Lantern Halls'
  sub-regions becomes thresholds on `E2` instead of a normalised height.
- `D` is a proxy (B.5), not a field, in the spike.
- Draft 1's engine tasks W01–W04 are no longer a precondition; they are
  possible outcomes of S01.
- No liquid is generated anywhere until `fill_fluid` exists; every sea, lake,
  river and aquifer is a look-alike solid block in the meantime, and the plan
  says so wherever one appears.
