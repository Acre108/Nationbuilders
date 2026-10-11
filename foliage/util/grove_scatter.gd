class_name GroveScatter
extends RefCounted

## The jittered-grid scatter loop shared by every grove-correlated placer --
## TreePlacer's trees and shrubs, DebrisPlacer's rocks and deadwood. A broad
## noise field decides where growth (or its debris) clusters; within that, a
## jittered grid at `spacing` places individual instances. Extracted out of
## TreePlacer once a second placer needed the exact same loop, rather than
## copied a third time.
##
## Every cell makes the same random draws whether or not it accepts an
## instance, so changing cover or the terrain mask never reshuffles what
## remains -- the same lesson as grass carving, and why this is one function
## every caller goes through rather than each hand-rolling its own loop.

class Placement extends RefCounted:
	var transforms: Array[Transform3D] = []
	## r = palette/tint variation, g = wind phase (unused by debris). Matches
	## INSTANCE_CUSTOM in the consuming shader.
	var custom := PackedColorArray()
	var species := PackedInt32Array()
	var variant := PackedInt32Array()


## 0..1 "how much growth is here". Remapped so a caller's `cover` is roughly
## the share of land above its threshold: FBM value noise sits in about +-0.5.
static func grove_value(groves: FastNoiseLite, x: float, z: float) -> float:
	return clampf(0.5 + groves.get_noise_2d(x, z) * 1.1, 0.0, 1.0)


## One family's jittered grid over one chunk, appended into `out`.
## `species_offset` lets several families share one Placement without their
## species indices colliding (TreePlacer's trees use 0, its shrubs 2, its
## conifers 4). `weights` picks among `species_offset + 0 .. species_offset +
## weights.size() - 1` -- two entries covers a binary split (trees, shrubs,
## debris), three a three-way one (conifers: spruce/fir/pine).
##
## `grove_at`, when given, replaces the noise grove per point --
## EnvironmentZones.forest_grove() makes trees follow mapped forest.
##
## `density_at`, when given, multiplies the acceptance chance per point --
## EnvironmentZones.shrub_density() for zone recipes' shrub multipliers.
##
## `mask_at`, when given, replaces `terrain.get_growth_mask` as the mask
## query -- TreePlacer passes `terrain.get_tree_mask` for its tree-canopy
## families (trees, conifers), so they alone thin out above a treeline (see
## TerrainProvider.get_tree_mask()'s class doc). Left empty, behaviour is
## unchanged: every other caller (shrubs, ferns, cushion plants, DebrisPlacer)
## keeps reading the ordinary growth mask.
static func scatter_family(
	out: Placement, rng: RandomNumberGenerator, groves: FastNoiseLite, terrain: TerrainProvider,
	chunk_size: float, origin: Vector2, spacing: float, cover: float, min_mask: float,
	scale_min: float, scale_max: float, variants_per_species: int,
	species_offset: int, weights: PackedFloat32Array,
	mask_at: Callable = Callable(),
	density: float = 1.0,
	density_at: Callable = Callable(),
	grove_at: Callable = Callable(),
	jitter: float = 0.7,
) -> void:
	var cells := maxi(1, int(round(chunk_size / spacing)))
	# 0.7 is the original 0.15..0.85 offset; keep its exact arithmetic so
	# existing placements stay bit-identical.
	var classic := is_equal_approx(jitter, 0.7)
	var cell := chunk_size / float(cells)
	var threshold := 1.0 - cover

	for cz in cells:
		for cx in cells:
			# All draws up front: see the class comment.
			var jx := rng.randf_range(0.15, 0.85) if classic else 0.5 + (rng.randf() - 0.5) * jitter
			var jz := rng.randf_range(0.15, 0.85) if classic else 0.5 + (rng.randf() - 0.5) * jitter
			var accept := rng.randf()
			var species_roll := rng.randf()
			var variant := rng.randi() % maxi(variants_per_species, 1)
			var yaw := rng.randf() * TAU
			var scale := rng.randf_range(scale_min, scale_max)
			var colour := rng.randf()
			var phase := rng.randf()

			var wx := origin.x + (float(cx) + jx) * cell
			var wz := origin.y + (float(cz) + jz) * cell
			# The grove is at most 1: a roll already above the density cannot
			# pass. Skips costly grove_at queries without changing the result.
			if grove_at.is_valid() and not density_at.is_valid() and accept >= clampf(density, 0.0, 1.0):
				continue
			# `grove_at` (observed zones: mapped forest) replaces the noise
			# grove; draws above are unchanged either way.
			var grove: float = float(grove_at.call(wx, wz)) if grove_at.is_valid() \
				else smoothstep(threshold - 0.1, threshold + 0.1, grove_value(groves, wx, wz))
			var chance := grove * clampf(density, 0.0, 1.0)
			# Per-point density (zone recipe multipliers): only when given, so
			# the default path's arithmetic is exactly what it always was.
			if density_at.is_valid():
				chance = minf(chance * float(density_at.call(wx, wz)), 1.0)
			if accept >= chance:
				continue
			var mask: float = mask_at.call(wx, wz) if mask_at.is_valid() else terrain.get_growth_mask(wx, wz)
			if mask < min_mask:
				continue

			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
			out.transforms.push_back(Transform3D(basis, Vector3(wx, terrain.get_height(wx, wz), wz)))
			out.custom.push_back(Color(colour, phase, 0.0, 0.0))
			out.species.push_back(species_offset + _pick_species(species_roll, weights))
			out.variant.push_back(variant)


## Picks an index into `weights` from a single `[0, 1)` roll. Bit-identical to
## the old binary `species_roll < share_of_first` test when `weights` is
## exactly `[share_of_first, 1.0 - share_of_first]` -- the two-entry case
## sums to 1.0, so the running total lands on precisely the same threshold.
static func _pick_species(species_roll: float, weights: PackedFloat32Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return 0
	var target := species_roll * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(weights[i], 0.0)
		if target < acc:
			return i
	return weights.size() - 1
