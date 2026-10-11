class_name GroundCoverScatter
extends RefCounted

## Forest-floor cover (environment zones Z3): moss, fallen branches and sticks,
## stumps and mushroom clusters, placed by zone recipe density
## (ZoneRecipe.moss_density etc.) and drawn by DebrisLayer.
##
## Same contract as every other placer: a pure function of (world seed, chunk)
## plus terrain and zones, worker-safe. Each category has its own salt and its
## own jittered grid, and every cell takes all of its draws before any test,
## so tuning one category's density -- or the woodland around it -- only adds
## or removes instances, never reshuffles the rest.

## Species indices appended after DebrisPlacer's 0 = rock, 1 = deadwood.
const MOSS := 2
const LITTER := 3
const STUMP := 4
const MUSHROOM := 5
const REED := 6
const BUSH := 7
## Coastal dune and heath (DUNE, HEATH zones). Appended, so the categories
## above keep their salts and grids.
const MARRAM := 8
const HEATHER := 9
const BUCKTHORN := 10
const CATEGORIES := ["moss", "litter", "stump", "mushroom", "reed", "bush", "marram", "heather", "buckthorn"]
## Grid spacing per category, metres.
const SPACING := {"moss": 2.5, "litter": 3.5, "stump": 14.0, "mushroom": 4.0, "reed": 1.8, "bush": 3.5, "marram": 1.6, "heather": 1.4, "buckthorn": 4.0}
const SALTS := {"moss": 0x6C0A51, "litter": 0x6C0A52, "stump": 0x6C0A53, "mushroom": 0x6C0A54, "reed": 0x6C0A55, "bush": 0x6C0A56,
	"marram": 0x6C0A57, "heather": 0x6C0A58, "buckthorn": 0x6C0A59}
## Mushrooms come in clusters of up to this many, within CLUSTER_RADIUS.
const CLUSTER := 5
const CLUSTER_RADIUS := 0.7
## Below this growth mask nothing lands (paths, water, steep rock).
const MIN_MASK := 0.4


## `variants`: assets per category, in CATEGORIES order (DebrisLayer builds
## one variant per asset NatureAssetCatalogue.floor_assets() returns).
static func scatter(
	out: GroveScatter.Placement, chunk: Vector2i, world_seed: int, chunk_size: float,
	terrain: TerrainProvider, zones: EnvironmentZones, variants: PackedInt32Array,
) -> void:
	if zones == null or zones.floor_neutral():
		return
	var origin := Vector2(chunk) * chunk_size
	for c in CATEGORIES.size():
		if zones.floor_peak(c) <= 0.0 or variants[c] <= 0:
			continue
		var category: String = CATEGORIES[c]
		var species := MOSS + c
		var rng := RandomNumberGenerator.new()
		rng.seed = GrassPlacer.hash_chunk(world_seed ^ SALTS[category], chunk.x, chunk.y)
		var cells := maxi(1, int(round(chunk_size / SPACING[category])))
		var cell := chunk_size / float(cells)
		for cz in cells:
			for cx in cells:
				# All draws up front: see the class comment.
				var jx := rng.randf()
				var jz := rng.randf()
				var accept := rng.randf()
				var variant := rng.randi() % variants[c]
				var yaw := rng.randf() * TAU
				var scale := rng.randf_range(0.75, 1.3)
				var colour := rng.randf()
				var offsets := PackedVector3Array()
				if species == MUSHROOM:
					for k in CLUSTER:
						offsets.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf()))

				var wx := origin.x + (float(cx) + jx) * cell
				var wz := origin.y + (float(cz) + jz) * cell
				var density := zones.floor_density(c, wx, wz)
				if accept >= density:
					continue
				var normal := terrain.get_normal(wx, wz)
				var mask := terrain.growth_mask_for(wx, wz, normal)
				if mask < MIN_MASK:
					continue
				if species == MOSS:
					# Moss keeps to flatter ground and favours north-facing,
					# shadier slopes: a second roll against the aspect weight,
					# reusing `accept` so no draw is added.
					var flat := smoothstep(0.7, 0.92, normal.y)
					var north := clampf(normal.z * terrain.north_z() * 4.0, -1.0, 1.0)
					if accept >= density * flat * (0.75 + 0.25 * north):
						continue
				if offsets.is_empty():
					# Moss and fallen wood lie along the slope; stumps, reeds and
					# bushes stand upright.
					_add(out, terrain, Vector3(wx, 0.0, wz), normal, yaw, scale, colour, species, variant, species == MOSS or species == LITTER)
				else:
					# A cluster of 2..CLUSTER of the same mushroom, upright.
					var count := 2 + int(offsets[0].z * float(CLUSTER - 1))
					for k in count:
						var o := offsets[k]
						var at := Vector3(wx + o.x * CLUSTER_RADIUS, 0.0, wz + o.y * CLUSTER_RADIUS)
						_add(out, terrain, at, Vector3.UP, yaw + o.z * TAU, scale * (0.7 + 0.6 * o.z), colour, species, variant, false)


static func _add(out: GroveScatter.Placement, terrain: TerrainProvider, at: Vector3, normal: Vector3,
		yaw: float, scale: float, colour: float, species: int, variant: int, settle: bool) -> void:
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	if settle:
		# Moss and fallen wood lie along the slope, like DebrisPlacer's logs.
		basis = Basis(Quaternion(Vector3.UP, normal)) * basis
	var y := terrain.get_height(at.x, at.z)
	if species == STUMP:
		# Stumps stand upright, a little sunk so their roots meet the ground.
		y -= 0.06 * scale
	out.transforms.push_back(Transform3D(basis, Vector3(at.x, y, at.z)))
	out.custom.push_back(Color(colour, 0.0, 0.0, 0.0))
	out.species.push_back(species)
	out.variant.push_back(variant)
