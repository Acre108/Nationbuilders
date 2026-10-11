class_name TreePlacer
extends RefCounted

## Deterministic tree AND shrub scatter for one chunk. Same contract as
## GrassPlacer: a pure function of (world seed, chunk coordinate) plus the
## terrain, so every client grows the same vegetation locally and none of it
## is networked. No node or RenderingServer access, so streaming runs it on
## WorkerThreadPool.
##
## Six independent FAMILIES share one Placement: trees (species 0-1, oak
## and birch), shrubs (species 2-3, rounded-shrub and low-hedge), conifers
## (species 4-5, spruce/pine), fir (species 6), ferns (species 7) and alpine
## cushion plants (species 8) -- the last three single-species families (see
## GroveScatter.scatter_family()'s `weights`, which a one-element array
## still goes through cleanly). Fir used to be a third share of the conifer
## family (`conifer_fir_share`); it is now independent, placed and covered
## on its own, so a location can mix or separate it from spruce/pine freely
## -- see FoliageFamily's class comment for why that split happened. These
## index ranges are this file's own hardcoded assumption (the base offset
## passed to each scatter_family() call below) and must stay in step with
## FoliageFamily.all_species()'s order, which is what TreeLayer actually
## builds species from. Each family has its own spacing, cover and RNG
## stream -- shrubs, ferns and cushion plants are meant to read as dense
## undergrowth, several times closer together than trees, not as sparse as
## them -- but all six are decided over the SAME grove noise field
## (`grove_value()`), so the undergrowth families correlate with where the
## (broadleaf) trees are: denser inside a grove, fringing its edge, thinning
## out with it into the open. Most of these families do not read this as
## "growing among the oaks" -- a location typically sets only one or two of
## `tree_cover`/`conifer_cover`/`fir_cover`/`cushion_cover` -- so in practice
## the shared field just means every family gets the same clearings-and-
## clusters shape. A location can have any family without the others
## (`cover`, `shrub_cover`, `conifer_cover`, `fir_cover`, `fern_cover` or
## `cushion_cover` at 0 skips that family's loop entirely).
##
## Trees gather into GROVES: a broad noise field decides where woodland is,
## and within it a jittered grid at `spacing` places individual trees. Even
## scatter across a whole meadow reads as an orchard; groves with clearings
## read as landscape.
##
## Every cell makes the same number of random draws whether or not it gets a
## plant, so changing cover or the terrain mask never reshuffles what remains
## -- the same lesson as grass carving. This holds per family: a shrub-cover
## change cannot reshuffle the trees, and vice versa, because each family
## draws from its own RNG stream (see SEED_SALT / SHRUB_SEED_SALT).
##
## The jittered-grid loop itself lives in GroveScatter, once DebrisPlacer
## (rocks and fallen trees) needed the exact same thing -- see it for the loop
## and for `Placement`, which this file's `Placement` is just a named alias of.

## Keeps tree and shrub randomness each a separate stream from grass and from
## each other, all of which share `world_seed`.
const SEED_SALT := 0x7EE5EED
const SHRUB_SEED_SALT := 0x58B0B58
const CONIFER_SEED_SALT := 0x60A71F5
const FIR_SEED_SALT := 0x3A9C1E7
const FERN_SEED_SALT := 0xFE2110C
const CUSHION_SEED_SALT := 0xC0541DE
const REGROWTH_SEED_SALT := 0x9E6C0A7
const MANTLE_SEED_SALT := 0x3A27E11
const MANTLE_TREE_SEED_SALT := 0x3A27E12
const REGROWTH_MIN_MASK := 0.6

## Below this growth-mask value, nothing of that family is placed. Shrubs
## tolerate rougher ground than trees -- real underbrush grows on slopes and
## marginal land a trunk would not stand well on. Conifers (and fir, the same
## ecological tolerance, just independently covered) sit between the two:
## real ones hold mountain slopes broadleaf trees would not. Ferns and
## cushion plants are the most tolerant of all -- shade-loving forest-floor
## growth and rock-hugging alpine growth respectively, both thriving on
## marginal ground nothing else here bothers with.
const TREE_MIN_MASK := 0.6
const SHRUB_MIN_MASK := 0.35
const CONIFER_MIN_MASK := 0.5
const FIR_MIN_MASK := 0.5
const FERN_MIN_MASK := 0.25
const CUSHION_MIN_MASK := 0.15

class Params extends RefCounted:
	var woodland_cover: float = 0.0
	var woodland_density: float = 0.55
	var woodland_spacing: float = 5.0
	var world_seed: int = 20260918
	var chunk_size: float = 32.0
	var spacing: float = 8.0
	var cover: float = 0.3
	var oak_share: float = 0.65
	## 0 = no shrubs. Independent of `cover` -- see the class comment.
	var shrub_cover: float = 0.0
	var shrub_spacing: float = 2.5
	var shrub_share: float = 0.55
	## 0 = no conifers. Independent of `cover` and `shrub_cover`.
	var conifer_cover: float = 0.0
	var conifer_spacing: float = 6.0
	## Share of spruce among placed conifers; the rest are pine. Fir used to
	## be a third share of this same family (`conifer_fir_share`) -- it is
	## now placed independently below.
	var conifer_spruce_share: float = 0.45
	## 0 = no fir. Independent of `conifer_cover` and every other cover --
	## see FoliageFamily's class comment for why fir was pulled out of the
	## conifer family.
	var fir_cover: float = 0.0
	var fir_spacing: float = 6.0
	var fir_scale_min: float = 0.8
	var fir_scale_max: float = 1.25
	## 0 = no ferns. Independent of the other covers.
	var fern_cover: float = 0.0
	var fern_spacing: float = 1.5
	## 0 = no cushion plants. Independent of the other covers.
	var cushion_cover: float = 0.0
	var cushion_spacing: float = 0.6
	## Young trees inside woods: chance per cell over the woodland field.
	var regrowth_cover: float = 0.0
	var regrowth_spacing: float = 4.0
	## Woodland mantle: shrubs, brambles and young trees along wood edges.
	var mantle_cover: float = 0.0
	var mantle_width: float = 6.0
	var mantle_spacing: float = 2.0
	## Canopy families' offset within their cell (GroveScatter `jitter`).
	var jitter: float = 0.7
	var variants_per_species: int = 3
	var scale_min: float = 0.85
	var scale_max: float = 1.2
	var shrub_scale_min: float = 0.7
	var shrub_scale_max: float = 1.15
	var conifer_scale_min: float = 0.8
	var conifer_scale_max: float = 1.25
	var fern_scale_min: float = 0.75
	var fern_scale_max: float = 1.3
	var cushion_scale_min: float = 0.7
	var cushion_scale_max: float = 1.4
	## Shrub and fern habitat (EnvironmentZones.understorey_mask()) and the
	## zone recipes' shrub multipliers. Null = the terrain alone, as before.
	var zones: EnvironmentZones
	## Built by grove_noise(); shared across chunks (read-only use is safe).
	var groves: FastNoiseLite


## Same fields as GroveScatter.Placement (0 = oak, 1 = birch, 2 = rounded-
## shrub, 3 = low-hedge, 4 = spruce, 5 = pine, 6 = fir, 7 = fern,
## 8 = alpine-cushion); kept as a named subclass so existing call sites
## reading `TreePlacer.Placement` need not change.
class Placement extends GroveScatter.Placement:
	pass


static func grove_noise(world_seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.seed = world_seed ^ SEED_SALT
	# ~70 m groves: a few woods and clearings within a player's view.
	noise.frequency = 1.0 / 70.0
	noise.fractal_octaves = 3
	return noise


## 0..1 "how much woodland is here". Remapped so `cover` is roughly the share
## of land above the grove threshold: FBM value noise sits in about +-0.5.
static func grove_value(params: Params, x: float, z: float) -> float:
	return GroveScatter.grove_value(params.groves, x, z)


static func place_chunk(chunk: Vector2i, params: Params, terrain: TerrainProvider) -> Placement:
	var out := Placement.new()
	if (params.cover <= 0.0 and params.shrub_cover <= 0.0 and params.conifer_cover <= 0.0
			and params.fir_cover <= 0.0 and params.fern_cover <= 0.0 and params.cushion_cover <= 0.0 and params.woodland_cover <= 0.0
			and params.regrowth_cover <= 0.0 and params.mantle_cover <= 0.0):
		return out
	var origin := Vector2(float(chunk.x), float(chunk.y)) * params.chunk_size
	var zones := params.zones if params.zones != null else EnvironmentZones.for_terrain(terrain)
	var understorey := Callable(zones, "understorey_mask")
	var shrub_density := Callable() if zones.shrub_neutral() else Callable(zones, "shrub_density")
	# Observed zones: tree families follow mapped forest, each at its cover
	# relative to the dominant family. Without them, the noise as always.
	var forest := func(cover: float) -> Callable:
		return Callable(zones, "forest_grove").bind(cover) if zones.observed else Callable()
	# Painted zones (Location Studio S4): only chunks overlapping painted
	# tiles take the per-point override path; elsewhere every family places
	# exactly as before.
	var painted := terrain.painted_zones_in(Rect2(origin, Vector2.ONE * params.chunk_size))
	var broadleaf_paint := painted.has(EnvironmentZones.Zone.WOODLAND_BROADLEAF)
	var conifer_paint := painted.has(EnvironmentZones.Zone.WOODLAND_CONIFER)
	var woody := func(cover: float, kind: int) -> Callable:
		return Callable(zones, "woody_grove").bind(cover, kind) if not painted.is_empty() else forest.call(cover)

	if params.cover > 0.0 or broadleaf_paint:
		var rng := RandomNumberGenerator.new()
		rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ SEED_SALT, chunk.x, chunk.y)
		GroveScatter.scatter_family(
			out, rng, params.groves, terrain, params.chunk_size, origin,
			params.spacing, params.cover, TREE_MIN_MASK,
			params.scale_min, params.scale_max, params.variants_per_species, 0,
			PackedFloat32Array([params.oak_share, 1.0 - params.oak_share]),
			terrain.get_tree_mask, 1.0, Callable(), woody.call(params.cover, 0), params.jitter,
		)

	if params.shrub_cover > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ SHRUB_SEED_SALT, chunk.x, chunk.y)
		GroveScatter.scatter_family(
			out, rng, params.groves, terrain, params.chunk_size, origin,
			params.shrub_spacing, params.shrub_cover, SHRUB_MIN_MASK,
			params.shrub_scale_min, params.shrub_scale_max, params.variants_per_species, 2,
			PackedFloat32Array([params.shrub_share, 1.0 - params.shrub_share]),
			understorey, 1.0, shrub_density,
		)

	if params.conifer_cover > 0.0 or conifer_paint:
		var rng := RandomNumberGenerator.new()
		rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ CONIFER_SEED_SALT, chunk.x, chunk.y)
		GroveScatter.scatter_family(
			out, rng, params.groves, terrain, params.chunk_size, origin,
			params.conifer_spacing, params.conifer_cover, CONIFER_MIN_MASK,
			params.conifer_scale_min, params.conifer_scale_max, params.variants_per_species, 4,
			PackedFloat32Array([params.conifer_spruce_share, 1.0 - params.conifer_spruce_share]),
			terrain.get_tree_mask, 1.0, Callable(), woody.call(params.conifer_cover, 1), params.jitter,
		)

	if params.fir_cover > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ FIR_SEED_SALT, chunk.x, chunk.y)
		GroveScatter.scatter_family(
			out, rng, params.groves, terrain, params.chunk_size, origin,
			params.fir_spacing, params.fir_cover, FIR_MIN_MASK,
			params.fir_scale_min, params.fir_scale_max, params.variants_per_species, 6,
			PackedFloat32Array([1.0]),
			terrain.get_tree_mask, 1.0, Callable(), woody.call(params.fir_cover, 1), params.jitter,
		)

	if params.fern_cover > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ FERN_SEED_SALT, chunk.x, chunk.y)
		GroveScatter.scatter_family(
			out, rng, params.groves, terrain, params.chunk_size, origin,
			params.fern_spacing, params.fern_cover, FERN_MIN_MASK,
			params.fern_scale_min, params.fern_scale_max, params.variants_per_species, 7,
			PackedFloat32Array([1.0]),
			understorey, 1.0, shrub_density,
		)

	if params.cushion_cover > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ CUSHION_SEED_SALT, chunk.x, chunk.y)
		GroveScatter.scatter_family(
			out, rng, params.groves, terrain, params.chunk_size, origin,
			params.cushion_spacing, params.cushion_cover, CUSHION_MIN_MASK,
			params.cushion_scale_min, params.cushion_scale_max, params.variants_per_species, 8,
			PackedFloat32Array([1.0]),
		)

	# Regrowth: young trees wherever the canopy families make woodland, at
	# their own spacing; `regrowth_cover` thins them. Own salt and RNG, so the
	# canopy and every other family are untouched by it.
	var woods := maxf(params.cover, maxf(params.conifer_cover, params.fir_cover))
	var young_paint := broadleaf_paint or conifer_paint or painted.has(EnvironmentZones.Zone.SCRUB)
	if (params.regrowth_cover > 0.0 and woods > 0.0) or young_paint:
		var rng := RandomNumberGenerator.new()
		rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ REGROWTH_SEED_SALT, chunk.x, chunk.y)
		# Painted chunks fold the regrowth density into the grove, so painted
		# scrub can grow young trees where the location has no regrowth.
		var young_density := 1.0 if not painted.is_empty() else params.regrowth_cover
		var young_grove: Callable = Callable(zones, "young_grove").bind(woods, params.regrowth_cover) if not painted.is_empty() else forest.call(woods)
		GroveScatter.scatter_family(
			out, rng, params.groves, terrain, params.chunk_size, origin,
			params.regrowth_spacing, woods, REGROWTH_MIN_MASK,
			0.45, 1.3, params.variants_per_species, 9,
			PackedFloat32Array([1.0]),
			terrain.get_tree_mask, young_density, Callable(), young_grove, 1.0,
		)

	# Mantle: a shrub belt on the open side of wood edges -- bushes (slot 2)
	# and low brambles (slot 3), with young trees among them (slot 9).
	if params.mantle_cover > 0.0 and woods > 0.0:
		var edge := Callable(zones, "mantle").bind(params.mantle_width)
		# The ground mask alone: an imported site's tree channel ends where
		# the mapped wood does, and the mantle lies just beyond it. Mown,
		# settled, wet and arable ground is excluded by mantle() itself.
		var ground := Callable(terrain, "get_growth_mask")
		var start := out.transforms.size()
		var rng := RandomNumberGenerator.new()
		rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ MANTLE_SEED_SALT, chunk.x, chunk.y)
		GroveScatter.scatter_family(
			out, rng, params.groves, terrain, params.chunk_size, origin,
			params.mantle_spacing, 1.0, SHRUB_MIN_MASK,
			1.1, 2.0, params.variants_per_species, 2,
			PackedFloat32Array([0.55, 0.45]),
			ground, params.mantle_cover, Callable(), edge, 1.0,
		)
		var young := RandomNumberGenerator.new()
		young.seed = GrassPlacer.hash_chunk(params.world_seed ^ MANTLE_TREE_SEED_SALT, chunk.x, chunk.y)
		GroveScatter.scatter_family(
			out, young, params.groves, terrain, params.chunk_size, origin,
			params.mantle_spacing * 2.0, 1.0, REGROWTH_MIN_MASK,
			0.6, 1.3, params.variants_per_species, 9,
			PackedFloat32Array([1.0]),
			ground, params.mantle_cover * 0.9, Callable(), edge, 1.0,
		)
		# Step down from the wood: tallest at its edge, low at the outer rim.
		for i in range(start, out.transforms.size()):
			var t := out.transforms[i]
			var step := lerpf(0.55, 1.0, float(edge.call(t.origin.x, t.origin.z)))
			t.basis = t.basis.scaled(Vector3.ONE * step)
			out.transforms[i] = t

	# Woodland-floor bushes are shrubs too: the same recipe multiplier applies.
	WoodlandScatter.scatter(out, chunk, params.world_seed, params.chunk_size, params.groves, terrain,
		params.woodland_cover, params.woodland_density, params.woodland_spacing, params.variants_per_species, true,
		0.6, shrub_density, woody.call(params.woodland_cover, 2))
	return out
