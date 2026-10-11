class_name GrassPlacer
extends RefCounted

## Deterministic grass scatter for a single chunk.
##
## Determinism requirement (brief, Part 1): placement is a pure function of
## (world seed, chunk coordinate), so every client generates identical grass
## locally and no grass data is ever sent over the network. That also makes
## carving reproducible -- a chunk rebuilt after furniture is placed is the same
## scatter minus the carved tufts, not a fresh random field, so grass does not
## visibly reshuffle when someone puts a picnic blanket down.
##
## The hash below is hand-rolled rather than using Godot's hash(). Godot makes
## no promise that hash() is stable across engine versions, and a change there
## would silently reshuffle every field in the game on an engine upgrade.
##
## Carving is deliberately NOT part of placement. place_chunk() always produces
## the full uncarved scatter, and filter_carved() removes tufts afterwards. An
## earlier version tested carvers inside the placement loop, which skipped the
## RNG draws for a carved tuft and so shifted every draw after it: putting a
## blanket down reshuffled the rest of the chunk. Splitting the two makes "same
## scatter minus the carved tufts" structural rather than something the draw
## order has to be kept honest about. It is also much faster -- a carve re-runs
## a point-in-footprint test over a cached result instead of re-sampling the
## terrain for every candidate.
##
## This class is intentionally free of node and RenderingServer access so Phase
## 5 can call it from WorkerThreadPool. Its only external dependency is reading
## from a TerrainProvider.

## Tunables for one scatter pass. Filled from FoliageProfile + FoliageQuality.
class PlacementParams extends RefCounted:
	var world_seed: int = 20260918
	var chunk_size: float = 16.0
	## Tufts per square metre before masking.
	var density: float = 3.0
	var scale_min: float = 0.8
	var scale_max: float = 1.35
	## 0 = every tuft stands straight up, 1 = fully aligned to the ground normal.
	## Grass does not actually grow perpendicular to a slope, so partial reads
	## far better than full alignment.
	var slope_align: float = 0.35
	## Fraction of accepted placements that become flowers instead of grass.
	var flower_chance: float = 0.0
	## Placements below this mask value are dropped outright, before the
	## probabilistic thinning, so near-zero mask areas do not keep stray tufts.
	var mask_cutoff: float = 0.05
	## Random downward sink, hiding the seam where a tuft meets the ground.
	var sink: float = 0.03
	## Zone recipes to apply (woodland floors). Null = none, and no zone
	## sampling cost. Worker-safe: EnvironmentZones only reads.
	var zones: EnvironmentZones
	## Meadow variety: patch height/colour and flower drifts. Null = none.
	## Nature-pack grass only: it overwrites the sprite-atlas variant
	## (custom.g), which pack meshes do not use. Worker-safe: only reads.
	var meadow: MeadowPatches


## One chunk of scatter, ready to be pushed into MultiMeshes on the main thread.
class PlacementResult extends RefCounted:
	var grass_transforms: Array[Transform3D] = []
	var grass_custom: PackedColorArray = PackedColorArray()
	var flower_transforms: Array[Transform3D] = []
	var flower_custom: PackedColorArray = PackedColorArray()
	## World-space height range of every tuft root in the chunk. Chunks need it
	## for their culling box: terrain height varies, and a box sized only for
	## the tuft culls hillside grass that is on screen.
	var min_y: float = INF
	var max_y: float = -INF

	func total() -> int:
		return grass_transforms.size() + flower_transforms.size()


## Mask keeping the hash inside unsigned 32-bit range.
##
## Deliberately 32-bit rather than the more usual 64-bit splitmix: GDScript ints
## are SIGNED 64-bit, so the standard 64-bit constants cannot even be written as
## literals (0x9E3779B97F4A7C15 overflows), and `>>` on a negative int is an
## arithmetic shift, which silently breaks any mix that assumes a logical one.
## Masking to 32 bits keeps every intermediate non-negative, so the shifts
## behave, and the products stay well inside int64 with no overflow.
const HASH_MASK := 0xFFFFFFFF


## Integer mix over (seed, chunk x, chunk z), verified to give 6,561 distinct
## values over an 81x81 chunk grid with no correlation between neighbours --
## adjacent chunks must not get similar seeds or their scatter visibly rhymes
## across the chunk boundary.
##
## Hand-rolled rather than using Godot's hash(): the engine makes no stability
## promise there, and a change would silently reshuffle every field in the game
## on an engine upgrade.
static func hash_chunk(world_seed: int, chunk_x: int, chunk_z: int) -> int:
	var h := world_seed & HASH_MASK
	h = (h ^ (chunk_x * 0x27D4EB2D)) & HASH_MASK
	h = (h ^ (h >> 15)) & HASH_MASK
	h = (h * 0x85EBCA6B) & HASH_MASK
	h = (h ^ (h >> 13)) & HASH_MASK
	h = (h ^ (chunk_z * 0x165667B1)) & HASH_MASK
	h = (h * 0xC2B2AE35) & HASH_MASK
	return (h ^ (h >> 16)) & HASH_MASK


## Scatters one chunk, uncarved. `chunk` is the chunk's integer grid coordinate;
## world position is derived from it and params.chunk_size.
static func place_chunk(
	chunk: Vector2i,
	params: PlacementParams,
	terrain: TerrainProvider,
) -> PlacementResult:
	var result := PlacementResult.new()

	var rng := RandomNumberGenerator.new()
	rng.seed = hash_chunk(params.world_seed, chunk.x, chunk.y)

	var origin := Vector2(float(chunk.x), float(chunk.y)) * params.chunk_size
	# Every question below is answered from one grid sampled up front, laid on
	# the ground mesh's lattice so tufts stand on the drawn surface. See
	# TerrainTile.
	var ground := terrain.tile(chunk_bounds(chunk, params.chunk_size))

	# Jittered grid rather than uniform random placement. Uniform random over an
	# area clumps and leaves bald patches at any density a human would call
	# "lush"; a jittered grid gives even coverage that still looks unplanned.
	var cell := 1.0 / sqrt(maxf(params.density, 0.0001))
	var cells := maxi(1, int(ceil(params.chunk_size / cell)))
	cell = params.chunk_size / float(cells)

	for cz in cells:
		for cx in cells:
			var wx := origin.x + (float(cx) + rng.randf()) * cell
			var wz := origin.y + (float(cz) + rng.randf()) * cell

			var normal := ground.get_normal(wx, wz)
			var mask := ground.growth_mask_for(wx, wz, normal)
			if mask <= params.mask_cutoff:
				continue
			# Mask doubles as an acceptance probability, so a mask edge thins out
			# rather than cutting a hard line.
			if rng.randf() > mask:
				continue

			var position := Vector3(wx, ground.get_height(wx, wz) - rng.randf() * params.sink, wz)

			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			if params.slope_align > 0.0:
				# Rotate partially from vertical towards the ground normal.
				var axis := Vector3.UP.cross(normal)
				if axis.length_squared() > 0.000001:
					var angle := Vector3.UP.angle_to(normal) * params.slope_align
					basis = Basis(axis.normalized(), angle) * basis
			var scale := rng.randf_range(params.scale_min, params.scale_max)

			# r = palette jitter, g = sprite atlas variant, b = wind phase,
			# a = LOD rank. Matches INSTANCE_CUSTOM.x / .y / .z / .w in
			# grass.gdshader. The rank decides which tufts survive into the far
			# band and at what distance each one thins out; it is uniform so
			# any cutoff keeps an even, unclumped fraction of the field.
			var custom := Color(
				rng.randf(),
				GrassCardBuilder.encode_variant(rng.randi()),
				rng.randf(),
				rng.randf(),
			)
			# Flower drifts change which roll counts as a flower, never whether
			# the roll is drawn, so the scatter keeps its draw sequence.
			var flower_chance := params.flower_chance
			if params.meadow != null and flower_chance > 0.0:
				flower_chance = minf(flower_chance * params.meadow.bloom_factor(wx, wz), 1.0)
			var flower := params.flower_chance > 0.0 and rng.randf() < flower_chance
			if params.meadow != null:
				scale *= params.meadow.height_scale(wx, wz)
				# Pack meshes ignore the atlas variant, so .y carries the patch's
				# lushness to grass.gdshader (grass_patch_contrast) instead.
				custom.g = params.meadow.lush(wx, wz)

			# Zone recipes (woodland floors) thin, shorten and darken tufts. Every
			# draw above is taken first and the keep test reuses the wind phase
			# as its roll, so no draw is skipped or added: ground whose recipe
			# keeps everything (meadow) gets exactly the scatter it had before
			# zones, and tuning a recipe only removes tufts, never reshuffles.
			var tuft_basis := basis.scaled(Vector3.ONE * scale)
			if params.zones != null:
				var effect := params.zones.grass_effect(wx, wz)
				if custom.b >= effect.x:
					continue
				if effect.y != 1.0 or effect.z != 1.0:
					# Scaled in the tuft's own axes, so a narrowed tuft stays
					# narrow across the ground even when tilted to the slope.
					# Untouched tufts keep the original maths above, so
					# meadow transforms stay bit-identical.
					tuft_basis = basis * Basis.from_scale(Vector3(effect.z, effect.y, effect.z) * scale)
				custom.r *= 1.0 - effect.w

			var transform := Transform3D(tuft_basis, position)
			result.min_y = minf(result.min_y, position.y)
			result.max_y = maxf(result.max_y, position.y)

			if flower:
				result.flower_transforms.push_back(transform)
				result.flower_custom.push_back(custom)
			else:
				result.grass_transforms.push_back(transform)
				result.grass_custom.push_back(custom)

	return result


## `result` minus every tuft inside any carver. Order is preserved, so the
## survivors are exactly the uncarved scatter's tufts with the same transforms
## and custom data -- which is what keeps grass from reshuffling on a carve.
##
## The height range is carried over unchanged. It only sizes a culling box, and
## a slightly generous box is harmless.
static func filter_carved(result: PlacementResult, carvers: Array[GrassCarver]) -> PlacementResult:
	if carvers.is_empty():
		return result
	var out := PlacementResult.new()
	out.min_y = result.min_y
	out.max_y = result.max_y

	# A carve removes tens of tufts from thousands. So find just the carved
	# indices -- with an inline bounds test that rejects almost every tuft
	# without a method call -- and copy the runs between them with native
	# slices, rather than pushing survivors back one by one from GDScript.
	var area := carvers[0].bounds()
	for carver in carvers:
		area = area.merge(carver.bounds())
	var grass_cut := _carved_indices(result.grass_transforms, carvers, area)
	var flower_cut := _carved_indices(result.flower_transforms, carvers, area)
	out.grass_transforms = _without(result.grass_transforms, grass_cut)
	out.grass_custom = _without_packed(result.grass_custom, grass_cut)
	out.flower_transforms = _without(result.flower_transforms, flower_cut)
	out.flower_custom = _without_packed(result.flower_custom, flower_cut)
	return out


static func _carved_indices(transforms: Array[Transform3D], carvers: Array[GrassCarver], area: Rect2) -> PackedInt32Array:
	var cut := PackedInt32Array()
	var min_x := area.position.x
	var min_z := area.position.y
	var max_x := area.end.x
	var max_z := area.end.y
	for i in transforms.size():
		var origin := transforms[i].origin
		if origin.x < min_x or origin.x > max_x or origin.z < min_z or origin.z > max_z:
			continue
		for carver in carvers:
			if carver.contains(origin.x, origin.z):
				cut.push_back(i)
				break
	return cut


static func _without(items: Array[Transform3D], cut: PackedInt32Array) -> Array[Transform3D]:
	if cut.is_empty():
		return items
	var out: Array[Transform3D] = []
	var start := 0
	for index in cut:
		out.append_array(items.slice(start, index))
		start = index + 1
	out.append_array(items.slice(start))
	return out


static func _without_packed(items: PackedColorArray, cut: PackedInt32Array) -> PackedColorArray:
	if cut.is_empty():
		return items
	var out := PackedColorArray()
	var start := 0
	for index in cut:
		out.append_array(items.slice(start, index))
		start = index + 1
	out.append_array(items.slice(start))
	return out


## World-space bounds of a chunk, used for culling and for deciding which chunks
## a carve event touches.
static func chunk_bounds(chunk: Vector2i, chunk_size: float) -> Rect2:
	return Rect2(Vector2(float(chunk.x), float(chunk.y)) * chunk_size, Vector2(chunk_size, chunk_size))
