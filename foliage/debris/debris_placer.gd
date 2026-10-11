class_name DebrisPlacer
extends RefCounted

## Deterministic rock and deadwood scatter for one chunk. Same contract as
## TreePlacer/GrassPlacer: a pure function of (world seed, chunk coordinate)
## plus the terrain, safe on WorkerThreadPool, nothing sent over the network.
##
## One family, not two: rocks and fallen trees do not need as sharp a
## density split as trees-vs-undergrowth do, so both share one spacing/cover
## pass through GroveScatter (species 0 = rock, 1 = deadwood, split by
## `rock_share`). Placed over the SAME grove noise field TreePlacer uses
## (`TreePlacer.grove_noise()` is a pure function of `world_seed`, so calling
## it again here reconstructs an identical field without either placer
## holding a reference to the other) -- deadwood comes from trees, so it
## should cluster where the trees are, and rock outcrops clustering near
## higher ground/woodland edges is a reasonable simplification of where real
## ones turn up.

## A different salt from TreePlacer's own SEED_SALT/SHRUB_SEED_SALT, so
## a debris-cover change cannot reshuffle the trees or shrubs, or vice versa.
const SEED_SALT := 0x0DEB215

const MIN_MASK := 0.4

class Params extends RefCounted:
	var woodland_cover: float = 0.0
	var woodland_density: float = 0.55
	var woodland_spacing: float = 12.0
	var world_seed: int = 20260918
	var chunk_size: float = 64.0
	var spacing: float = 18.0
	var cover: float = 0.0
	var rock_share: float = 0.6
	var variants_per_species: int = 3
	var scale_min: float = 0.8
	var scale_max: float = 1.3
	## Built by TreePlacer.grove_noise(); shared across chunks.
	var groves: FastNoiseLite
	## Forest-floor cover (GroundCoverScatter). Null = none.
	var zones: EnvironmentZones
	## Assets per GroundCoverScatter category, in its CATEGORIES order.
	var floor_variants := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])


## 0 = rock, 1 = deadwood, then GroundCoverScatter's 2 = moss, 3 = litter,
## 4 = stump, 5 = mushroom, 6 = reed, 7 = bush.
class Placement extends GroveScatter.Placement:
	pass


static func place_chunk(chunk: Vector2i, params: Params, terrain: TerrainProvider) -> Placement:
	var out := Placement.new()
	# Painted zones (S4): only chunks overlapping painted tiles change.
	var area := Rect2(Vector2(chunk) * params.chunk_size, Vector2.ONE * params.chunk_size)
	var painted := params.zones != null and not terrain.painted_zones_in(area).is_empty()
	var deadwood := Callable(params.zones, "woody_grove").bind(params.woodland_cover, 2) if painted else _forest(params)
	if params.cover <= 0.0:
		WoodlandScatter.scatter(out, chunk, params.world_seed, params.chunk_size, params.groves, terrain,
			params.woodland_cover, params.woodland_density, params.woodland_spacing, params.variants_per_species, false, params.rock_share,
			Callable(), deadwood)
		GroundCoverScatter.scatter(out, chunk, params.world_seed, params.chunk_size, terrain, params.zones, params.floor_variants)
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ SEED_SALT, chunk.x, chunk.y)
	var origin := Vector2(float(chunk.x), float(chunk.y)) * params.chunk_size
	GroveScatter.scatter_family(
		out, rng, params.groves, terrain, params.chunk_size, origin,
		params.spacing, params.cover, MIN_MASK,
		params.scale_min, params.scale_max, params.variants_per_species, 0,
		PackedFloat32Array([params.rock_share, 1.0 - params.rock_share]),
		Callable(), 1.0, Callable(params.zones, "debris_density") if painted else Callable(),
	)
	WoodlandScatter.scatter(out, chunk, params.world_seed, params.chunk_size, params.groves, terrain,
		params.woodland_cover, params.woodland_density, params.woodland_spacing, params.variants_per_species, false, params.rock_share,
		Callable(), deadwood)
	GroundCoverScatter.scatter(out, chunk, params.world_seed, params.chunk_size, terrain, params.zones, params.floor_variants)
	return out


## Woodland-floor deadwood follows mapped forest when the zones are observed.
static func _forest(params: Params) -> Callable:
	if params.zones == null or not params.zones.observed:
		return Callable()
	return Callable(params.zones, "forest_grove").bind(params.woodland_cover)
