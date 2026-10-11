class_name EnvironmentZones
extends RefCounted

## The one answer to "what kind of ground is this?" at a world XZ, as weights
## over a small fixed set of zones that sum to 1. Every layer that varies by
## habitat (grass, ground colour, ground cover, debris) reads this instead of
## combining terrain masks its own way. See docs/ENVIRONMENT_ZONES.md.
##
## Worker-safe: no nodes, no RenderingServer, only reads from a TerrainProvider
## and a FastNoiseLite, like GrassPlacer, so streaming workers can call it.
##
## Woodland comes from the SAME grove noise and cover thresholds the tree
## placers scatter with (TreePlacer.grove_noise(), GroveScatter's smoothstep),
## so the woodland zones sit exactly where trees stand. Trees do not read zones;
## zones read the trees' inputs. Moving trees onto zones would reshuffle every
## forest and is a separate, later decision (plan phase Z6).
##
## Adding a zone: append to Zone (never reorder -- recipes and the baked map
## index by it), give it a recipe export in FoliageProfile, and decide which
## existing weight it takes its share from in weights_for(). A location whose
## habitats fit none of these should prompt that conversation, not be forced
## into the nearest zone -- see docs/GEO_IMPORT.md.

enum Zone {
	MEADOW,
	WOODLAND_CONIFER,
	WOODLAND_BROADLEAF,
	ROCK,
	SNOW,
	## Ground that grows nothing and is not rock or snow: open water away
	## from its margin, paths, painted-bare patches, outside the world.
	BARE,
	## Water margins of imported lakes and streams (ShoreHabitat): the
	## shallows and the bank. Taken from the water part of BARE first, then
	## from MEADOW -- never from woodland. growing_shares() still counts its
	## meadow part as meadow, so grass and floor cover are unchanged by it.
	SHORE,
	## Observed zones (Z6), from an imported site's zone mask and farmland
	## channel. Zero where a location has no such data.
	## Reed beds, sedge fen, wet meadow.
	WETLAND,
	## Arable fields (the site mask's farmland channel).
	FARMLAND,
	## Mown lawns, gardens, yards, settlements, cemeteries, allotments.
	GARDEN,
	## Shrubland: dense bushes and young trees in rough grass.
	SCRUB,
	## Settlement zones (settlements.py: footprint clusters, OSM place
	## nodes): the unmapped open ground of a village or a town. Taken from
	## MEADOW only, so mapped gardens, fields and woods keep their zones.
	VILLAGE,
	TOWN,
	## The verge beside drivable roads, outside carriageway and pavement. It
	## carries a road context (road_context(): rural, village, town); town
	## streets have pavement instead. Claims its share from every growing zone.
	ROAD,
	## Coastal and heath habitats (the site's habitat mask, import_site.py):
	## grey dune grassland -- short, sparse grass, moss and lichen on sand --
	## plus open sand and beach, which take their share from BARE. Dune
	## grassland is taken from MEADOW only, so mapped woods, scrub and
	## wetland in the dunes keep their zones.
	DUNE,
	## Dwarf-shrub heath (heather, crowberry) on poor sandy ground. Taken
	## from MEADOW only, like DUNE.
	HEATH,
}
const COUNT := 16
## The zones a growing point is shared between, in growing_weights() order.
const GROWING := [Zone.MEADOW, Zone.WOODLAND_CONIFER, Zone.WOODLAND_BROADLEAF, Zone.WETLAND, Zone.FARMLAND, Zone.GARDEN, Zone.SCRUB, Zone.VILLAGE, Zone.TOWN, Zone.ROAD, Zone.DUNE, Zone.HEATH]
enum RoadContext { RURAL, VILLAGE, TOWN }

## GroveScatter's acceptance ramp, either side of the cover threshold, in
## grove-value units. Must match GroveScatter.scatter_family() and the
## woodland formula in terrain.gdshader.
const GROVE_RAMP := 0.1

var terrain: TerrainProvider
var groves: FastNoiseLite
## FoliageProfile.tree_cover, conifer_cover, fir_cover. Fir counts as
## conifer woodland (it shares the needle read) but keeps its own threshold.
var broadleaf_cover: float = 0.0
var conifer_cover: float = 0.0
var fir_cover: float = 0.0
## Relative stems per square metre at full strength, 1 / spacing^2 per
## family (x = broadleaf, y = conifer, z = fir). The conifer/broadleaf split
## follows expected stem counts, not raw strength: where several families
## saturate, a dense spruce stand outnumbers sparse oaks.
var stems := Vector3.ONE

## The grass fields of the profile's recipes, one entry per Zone, copied out
## as plain floats so worker threads never touch the Resources.
var grass_keep := PackedFloat32Array()
var grass_height := PackedFloat32Array()
var grass_footprint := PackedFloat32Array()
var grass_shade := PackedFloat32Array()
## Forest-floor densities, GroundCoverScatter.CATEGORIES x Zone, row-major:
## floor_table[category * COUNT + zone].
var floor_table := PackedFloat32Array()
## ZoneRecipe.shrub_multiplier per Zone.
var shrub_multiplier := PackedFloat32Array()
## ZoneRecipe.young_tree_density and debris_multiplier per Zone (painted
## zones, S4).
var young_trees := PackedFloat32Array()
var debris_multiplier := PackedFloat32Array()
## Lake and stream margins (SHORE), or null: no SHORE zone.
var shore: ShoreHabitat
## True when the terrain carries observed zones (an imported site's zone
## mask): woodland then follows the mapped forest, and WETLAND, FARMLAND,
## GARDEN and SCRUB come from the masks. False keeps the inferred field.
var observed := false
## True when the observed site also carries a habitat mask (DUNE, HEATH).
var has_habitats := false
## The largest family cover: with observed zones, families are scaled
## relative to it, so the dominant family fills mapped forest and minor ones
## keep their noise patches inside it.
var _max_cover := 0.0


func _init() -> void:
	set_recipes(_neutral_recipes())


## Terrain only: no woods, neutral recipes, no shore. For placers called
## without a profile's zones (tests, tools), which then behave as before.
static func for_terrain(provider: TerrainProvider) -> EnvironmentZones:
	var zones := EnvironmentZones.new()
	zones.terrain = provider
	return zones


static func for_profile(profile: FoliageProfile, provider: TerrainProvider) -> EnvironmentZones:
	var zones := EnvironmentZones.new()
	zones.terrain = provider
	var habitat := ShoreHabitat.for_terrain(provider, profile.shoreline_lake_name)
	zones.shore = habitat if habitat.has_lakes() or habitat.streams != null else null
	zones.groves = TreePlacer.grove_noise(profile.world_seed)
	if profile.enabled:
		zones.broadleaf_cover = profile.tree_cover
		zones.conifer_cover = profile.conifer_cover
		zones.fir_cover = profile.fir_cover
	zones._max_cover = maxf(zones.broadleaf_cover, maxf(zones.conifer_cover, zones.fir_cover))
	zones.observed = provider != null and provider.has_observed_zones()
	zones.has_habitats = zones.observed and provider.has_observed_habitats()
	zones.stems = family_stems(profile)
	zones.set_recipes(profile.zone_recipes())
	return zones


## 1 / spacing^2 for broadleaf, conifer and fir, as the tree placer spaces
## them. Shared with FoliageLocation so the shader splits families the same way.
static func family_stems(profile: FoliageProfile) -> Vector3:
	return Vector3(
		1.0 / (profile.tree_spacing * profile.tree_spacing),
		1.0 / (profile.conifer_spacing * profile.conifer_spacing),
		1.0 / (profile.fir_spacing * profile.fir_spacing),
	)


func set_recipes(recipes: Array[ZoneRecipe]) -> void:
	grass_keep.resize(COUNT)
	grass_height.resize(COUNT)
	grass_footprint.resize(COUNT)
	grass_shade.resize(COUNT)
	for i in COUNT:
		grass_keep[i] = recipes[i].grass_keep
		grass_height[i] = recipes[i].grass_height_scale
		grass_footprint[i] = recipes[i].grass_footprint
		grass_shade[i] = recipes[i].grass_shade
	shrub_multiplier.resize(COUNT)
	young_trees.resize(COUNT)
	debris_multiplier.resize(COUNT)
	for i in COUNT:
		shrub_multiplier[i] = recipes[i].shrub_multiplier
		young_trees[i] = recipes[i].young_tree_density
		debris_multiplier[i] = recipes[i].debris_multiplier
	floor_table.resize(GroundCoverScatter.CATEGORIES.size() * COUNT)
	for i in COUNT:
		var r := recipes[i]
		var row := [r.moss_density, r.litter_density, r.stump_density, r.mushroom_density, r.reed_density, r.bush_density,
			r.marram_density, r.heather_density, r.buckthorn_density]
		for c in row.size():
			floor_table[c * COUNT + i] = row[c]


## True when the grass recipes of every growing zone are neutral, so the
## grass placer can skip zone sampling entirely.
func grass_neutral() -> bool:
	# Woodland recipes cannot apply where there is no woodland.
	for i in _possible_growing():
		if not (is_equal_approx(grass_keep[i], 1.0) and is_equal_approx(grass_height[i], 1.0) \
				and is_equal_approx(grass_footprint[i], 1.0) and grass_shade[i] <= 0.0):
			return false
	return true


## Where shrubs and ferns may grow: the growth mask and an imported site's
## woody-growth mask, but not the treeline -- understorey thrives above it.
## (Formerly TerrainProvider.get_understorey_mask().)
func understorey_mask(x: float, z: float) -> float:
	return terrain.get_growth_mask(x, z) * terrain.site_tree_mask(x, z)


## True when every growing zone's shrub multiplier is 1, so shrub and fern
## placement can skip the per-point density entirely.
func shrub_neutral() -> bool:
	for i in _possible_growing():
		if not is_equal_approx(shrub_multiplier[i], 1.0):
			return false
	return true


## The growing zones that can occur here: meadow always, woodland with tree
## cover, the observed zones with observed data.
func _possible_growing() -> Array:
	var out := [Zone.MEADOW]
	if broadleaf_cover > 0.0 or conifer_cover > 0.0 or fir_cover > 0.0:
		out += [Zone.WOODLAND_CONIFER, Zone.WOODLAND_BROADLEAF]
	if observed:
		out += [Zone.WETLAND, Zone.FARMLAND, Zone.GARDEN, Zone.SCRUB, Zone.VILLAGE, Zone.TOWN, Zone.ROAD]
		if has_habitats:
			out += [Zone.DUNE, Zone.HEATH]
	# Painted zones can occur anywhere a location has overrides (S4).
	if terrain != null and terrain.zone_overrides != null and not terrain.zone_overrides.is_empty():
		for zone in ZoneOverrides.PAINTABLE:
			if zone in GROWING and not zone in out: out.append(zone)
	return out


## True where a painted zone override applies (Location Studio S4). Painted
## points take the full growing_weights() path even without observed data.
func painted(x: float, z: float) -> bool:
	return terrain.zone_overrides != null and terrain.zone_overrides.sample(x, z).y > 0.0


## w = lerp(w, onehot(zone), strength) for a painted point. `growing_only`:
## growing_weights() takes only growing zones; painted rock and bare ground
## act through the growth mask there instead.
func _apply_override(w: PackedFloat32Array, x: float, z: float, growing_only: bool) -> void:
	var o := terrain.zone_overrides.sample(x, z)
	if o.y <= 0.0: return
	var zone := int(o.x)
	if zone < 0 or zone >= COUNT or (growing_only and not zone in GROWING): return
	for i in COUNT: w[i] *= 1.0 - o.y
	w[zone] += o.y


## Painted woody acceptance (S4) for a tree family: `kind` 0 broadleaf,
## 1 conifer, 2 any woodland (regrowth, woodland floor, deadwood), 3 young
## trees (painted scrub's young_tree_density). Painted woodland raises the
## acceptance to full cover; every other painted zone suppresses it.
## Unpainted points return `base` unchanged.
func painted_grove(x: float, z: float, base: float, kind: int) -> float:
	var o := terrain.zone_override(x, z)
	if o.y <= 0.0: return base
	var zone := int(o.x)
	var target := 0.0
	if zone == Zone.WOODLAND_BROADLEAF: target = 1.0 if kind in [0, 2, 3] else 0.0
	elif zone == Zone.WOODLAND_CONIFER: target = 1.0 if kind in [1, 2, 3] else 0.0
	elif zone == Zone.SCRUB and kind == 3: target = young_trees[Zone.SCRUB]
	return lerpf(base, target, o.y)


## Young trees (the regrowth species) where painted: woodland keeps the
## location's regrowth density, scrub uses its recipe's young_tree_density,
## other zones none. Unpainted points: the woods' acceptance times `density`.
func young_grove(x: float, z: float, cover: float, density: float) -> float:
	var base := (forest_grove(x, z, cover) if observed else woodland_from_value(GroveScatter.grove_value(groves, x, z), cover)) * density
	var o := terrain.zone_override(x, z)
	if o.y <= 0.0: return base
	var zone := int(o.x)
	var target := density if zone in [Zone.WOODLAND_BROADLEAF, Zone.WOODLAND_CONIFER] else (young_trees[Zone.SCRUB] if zone == Zone.SCRUB else 0.0)
	return lerpf(base, target, o.y)


## Generic debris (rocks and fallen wood) multiplier at a painted point,
## blended from the recipes' debris_multiplier; 1 where unpainted.
func debris_density(x: float, z: float) -> float:
	return _blend_growing(debris_multiplier, 0, x, z) if painted(x, z) else 1.0


## A grove_at callable for GroveScatter that adds painted zones to a family's
## usual acceptance: observed forest_grove() or the noise grove at `cover`.
func woody_grove(x: float, z: float, cover: float, kind: int) -> float:
	var base := forest_grove(x, z, cover) if observed else woodland_from_value(GroveScatter.grove_value(groves, x, z), cover)
	return painted_grove(x, z, base, kind)


## Generic blend of a per-zone table over growing_weights().
func _blend_growing(table: PackedFloat32Array, offset: int, x: float, z: float) -> float:
	var w := growing_weights(x, z)
	var total := 0.0
	for i in GROWING:
		if w[i] > 0.0:
			total += w[i] * table[offset + i]
	return total


## Shrub and fern density multiplier at a growing point, blended by
## growing_shares() from the recipes' shrub_multiplier.
func shrub_density(x: float, z: float) -> float:
	if observed or painted(x, z):
		return _blend_growing(shrub_multiplier, 0, x, z)
	var s := growing_shares(x, z)
	return s.x * shrub_multiplier[Zone.MEADOW] + s.y * shrub_multiplier[Zone.WOODLAND_CONIFER] + s.z * shrub_multiplier[Zone.WOODLAND_BROADLEAF]


## True when no growing zone places forest-floor cover (or there are no woods
## for the woodland recipes to apply in).
func floor_neutral() -> bool:
	for c in GroundCoverScatter.CATEGORIES.size():
		if floor_peak(c) > 0.0:
			return false
	return true


## The highest density category `c` reaches in any zone that can occur here.
func floor_peak(c: int) -> float:
	var peak := 0.0
	for i in _possible_growing():
		peak = maxf(peak, floor_table[c * COUNT + i])
	return peak


## Category `c`'s density at a growing point, blended by growing_shares().
## The caller still tests the growth mask itself.
func floor_density(c: int, x: float, z: float) -> float:
	if observed or painted(x, z):
		return _blend_growing(floor_table, c * COUNT, x, z)
	var s := growing_shares(x, z)
	var row := c * COUNT
	return s.x * floor_table[row + Zone.MEADOW] + s.y * floor_table[row + Zone.WOODLAND_CONIFER] + s.z * floor_table[row + Zone.WOODLAND_BROADLEAF]


static func _neutral_recipes() -> Array[ZoneRecipe]:
	var out: Array[ZoneRecipe] = []
	for i in COUNT:
		out.append(ZoneRecipe.new())
	return out


## 0..1 woodland strength for one family from a raw grove value. Identical to
## the per-instance acceptance GroveScatter applies before its density and
## mask tests.
static func woodland_from_value(value: float, cover: float) -> float:
	if cover <= 0.0:
		return 0.0
	var threshold := 1.0 - cover
	return smoothstep(threshold - GROVE_RAMP, threshold + GROVE_RAMP, value)


## Raw woodland strength per family, before terrain masks:
## x = broadleaf, y = conifer, z = fir.
func families(x: float, z: float) -> Vector3:
	if broadleaf_cover <= 0.0 and conifer_cover <= 0.0 and fir_cover <= 0.0:
		return Vector3.ZERO
	if observed:
		# Beyond a partial site (4 km inside an 8 km crop) the mapped forest
		# gives way to the inferred groves over the site's fade band.
		var value := GroveScatter.grove_value(groves, x, z)
		var forest := terrain.observed_zones(x, z).a
		var mapped := relative_families_from_value(value) * forest if forest > 0.0 else Vector3.ZERO
		var k := terrain.observed_coverage(x, z)
		return mapped if k >= 1.0 else families_from_value(value).lerp(mapped, k)
	return families_from_value(GroveScatter.grove_value(groves, x, z))


## With observed zones: each family's strength relative to the dominant one,
## so inside mapped forest the dominant family is everywhere and minor ones
## keep their noise patches. Mirrored by terrain.gdshader.
func relative_families_from_value(value: float) -> Vector3:
	var m := maxf(_max_cover, 0.000001)
	return Vector3(woodland_from_value(value, broadleaf_cover / m), woodland_from_value(value, conifer_cover / m), woodland_from_value(value, fir_cover / m))


## GroveScatter's grove for a tree family with observed zones: mapped forest
## times the family's relative strength. TreePlacer binds `cover`.
func forest_grove(x: float, z: float, cover: float) -> float:
	if cover <= 0.0:
		return 0.0
	var forest := terrain.observed_zones(x, z).a
	var k := terrain.observed_coverage(x, z)
	if forest <= 0.0 and k >= 1.0:
		return 0.0
	var value := GroveScatter.grove_value(groves, x, z)
	var mapped := forest * woodland_from_value(value, cover / maxf(_max_cover, 0.000001)) if forest > 0.0 else 0.0
	# Beyond a partial site: GroveScatter's own inferred acceptance.
	return mapped if k >= 1.0 else lerpf(woodland_from_value(value, cover), mapped, k)


func families_from_value(value: float) -> Vector3:
	return Vector3(woodland_from_value(value, broadleaf_cover), woodland_from_value(value, conifer_cover), woodland_from_value(value, fir_cover))


## Raw woodland strength before terrain masks: x = broadleaf, y = conifer
## side (conifer or fir, whichever is stronger).
func woodland(x: float, z: float) -> Vector2:
	var f := families(x, z)
	return Vector2(f.x, maxf(f.y, f.z))


## Woodland mantle (Waldmantel) strength at an open point: 1 just outside a
## wood's edge, fading to 0 by `width` metres out and inside the wood itself.
## Fields, roads and paths grow nothing (the placers' masks); mown, settled
## and wet ground keeps no mantle here. Placement only: not a zone weight.
func mantle(x: float, z: float, width: float) -> float:
	var own := woodland_extent(families(x, z))
	if own >= 0.35:
		return 0.0
	var near := 0.0
	for k in 8:
		var angle := TAU * float(k) / 8.0
		for reach in [width * 0.5, width]:
			near = maxf(near, woodland_extent(families(x + cos(angle) * reach, z + sin(angle) * reach)))
		if near >= 0.6:
			break
	var band := smoothstep(0.3, 0.6, near) * (1.0 - own / 0.35)
	if band <= 0.0 or not observed:
		return band
	var w := growing_weights(x, z)
	return band * clampf(1.0 - w[Zone.GARDEN] - w[Zone.VILLAGE] - w[Zone.TOWN] - w[Zone.ROAD] - w[Zone.FARMLAND] - w[Zone.WETLAND], 0.0, 1.0)


## The families share one noise and differ only by threshold, so the
## strongest is the woodland extent.
static func woodland_extent(f: Vector3) -> float:
	return maxf(f.x, maxf(f.y, f.z))


## Conifer share of woodland by expected stems. Mirrors terrain.gdshader's
## zone_conifer_share().
func conifer_share(f: Vector3) -> float:
	var broadleaf := f.x * stems.x
	var conifer := f.y * stems.y + f.z * stems.z
	return conifer / maxf(broadleaf + conifer, 0.000001)


func weights(x: float, z: float) -> PackedFloat32Array:
	return weights_for(x, z, terrain.get_normal(x, z))


## Zone weights given the ground normal already in hand (a TerrainTile's).
## Always COUNT entries summing to 1.
func weights_for(x: float, z: float, normal: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(COUNT)
	var growth := clampf(terrain.growth_mask_for(x, z, normal), 0.0, 1.0)

	# Non-growing ground: split into snow, then rock, from the altitude bands
	# the growth mask already applied; whatever is left is bare.
	var barren := 1.0 - growth
	if barren > 0.0:
		var altitude := terrain.altitude_cover(x, z, normal)
		var snow := minf(barren, altitude.y)
		var rock := minf(barren - snow, altitude.x * (1.0 - altitude.y))
		out[Zone.SNOW] = snow
		out[Zone.ROCK] = rock
		out[Zone.BARE] = barren - snow - rock

	if observed:
		_observed_weights(out, x, z, growth)
	# Growing ground: woodland where trees stand, meadow elsewhere, split
	# between conifer and broadleaf by expected stems.
	elif growth > 0.0:
		var f := families(x, z)
		var wood := woodland_extent(f)
		if wood > 0.0:
			# get_tree_mask() == growth * tree_mask_factor(): the treeline and
			# the imported site's tree mask on top of the growth mask.
			wood = minf(wood * growth * terrain.tree_mask_factor(x, z), growth)
			var share := conifer_share(f)
			out[Zone.WOODLAND_CONIFER] = wood * share
			out[Zone.WOODLAND_BROADLEAF] = wood * (1.0 - share)
		out[Zone.MEADOW] = growth - wood
	# Painted zones: lerp to the painted zone at the brush strength. Before
	# SHORE, which still follows the water.
	if terrain.zone_overrides != null: _apply_override(out, x, z, false)

	# Water margins: from the water part of BARE (not paths or painted bare
	# ground), then from meadow.
	if shore != null:
		var band := shore.shore_band(x, z)
		if band > 0.0:
			var water := minf(out[Zone.BARE], terrain.water_cover(x, z))
			var from_water := minf(water, band)
			var from_meadow := minf(out[Zone.MEADOW], band - from_water)
			out[Zone.BARE] -= from_water
			out[Zone.MEADOW] -= from_meadow
			out[Zone.SHORE] = from_water + from_meadow
	return out


## With observed zones: the growing part shared by growing_weights(), and
## farmland's remainder taken from bare ground (fields barely grow grass).
func _observed_weights(out: PackedFloat32Array, x: float, z: float, growth: float) -> void:
	if growth > 0.0:
		# Base weights: weights_for() applies a painted override once, at its end.
		var w := growing_weights(x, z, false)
		for i in GROWING:
			out[i] = growth * w[i]
	var fields := minf(maxf(terrain.farmland_cover(x, z) - out[Zone.FARMLAND], 0.0), out[Zone.BARE])
	out[Zone.BARE] -= fields
	out[Zone.FARMLAND] += fields
	# Open sand and beach: dune ground that grows nothing. Open water stays
	# BARE (SHORE takes its margin below).
	if has_habitats and out[Zone.BARE] > 0.0:
		var sand := terrain.observed_habitat(x, z).b
		if sand > 0.0:
			sand = minf(sand, maxf(out[Zone.BARE] - terrain.water_cover(x, z), 0.0))
			out[Zone.BARE] -= sand
			out[Zone.DUNE] += sand


## Every zone's share of a point that does grow (the GROWING zones sum to 1).
## Without observed zones this is growing_shares() spread over COUNT.
## `with_paint` false gives the unpainted weights (weights_for() applies a
## painted override once, at its end).
func growing_weights(x: float, z: float, with_paint: bool = true) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(COUNT)
	if not observed:
		var s := _growing_shares_base(x, z)
		w[Zone.MEADOW] = s.x
		w[Zone.WOODLAND_CONIFER] = s.y
		w[Zone.WOODLAND_BROADLEAF] = s.z
		if with_paint and terrain.zone_overrides != null: _apply_override(w, x, z, true)
		return w
	var f := families(x, z)
	var wood := minf(woodland_extent(f) * terrain.tree_mask_factor(x, z), 1.0)
	var c := terrain.observed_zones(x, z)
	var fields := terrain.farmland_cover(x, z)
	var claimed := wood + c.r + c.g + c.b + fields
	# Overlapping classes (a wooded fen) share the ground.
	var scale := 1.0 / claimed if claimed > 1.0 else 1.0
	var share := conifer_share(f) if wood > 0.0 else 0.0
	w[Zone.WOODLAND_CONIFER] = wood * share * scale
	w[Zone.WOODLAND_BROADLEAF] = wood * (1.0 - share) * scale
	w[Zone.WETLAND] = c.r * scale
	w[Zone.GARDEN] = c.g * scale
	w[Zone.SCRUB] = c.b * scale
	w[Zone.FARMLAND] = fields * scale
	w[Zone.MEADOW] = maxf(1.0 - claimed * scale, 0.0)
	# Dune grassland and heath: the open ground of the dunes and heaths.
	if has_habitats and w[Zone.MEADOW] > 0.0:
		var habitat := terrain.observed_habitat(x, z)
		var wild := habitat.r + habitat.g
		if wild > 0.0:
			var take := w[Zone.MEADOW] * minf(wild, 1.0)
			w[Zone.MEADOW] -= take
			w[Zone.DUNE] = take * habitat.r / wild
			w[Zone.HEATH] = take * habitat.g / wild
	var settled := terrain.observed_settlement(x, z)
	# The verge claims first, from every growing zone alike.
	if settled.b > 0.0:
		for i in GROWING:
			w[i] *= 1.0 - settled.b
		w[Zone.ROAD] = settled.b
	# Village and town ground is the unmapped open part of a settlement.
	var settlement := maxf(settled.r, settled.g)
	if settlement > 0.0 and w[Zone.MEADOW] > 0.0:
		var take := w[Zone.MEADOW] * settlement
		w[Zone.MEADOW] -= take
		w[Zone.TOWN if settled.g > settled.r else Zone.VILLAGE] += take
	if with_paint and terrain.zone_overrides != null: _apply_override(w, x, z, true)
	return w


## The road context at a world XZ: a verge's own context, otherwise the
## settlement it lies in. Rural without observed settlement data.
func road_context(x: float, z: float) -> RoadContext:
	var settled := terrain.observed_settlement(x, z)
	if settled.b > 0.0:
		return RoadContext.TOWN if settled.a > 0.75 else (RoadContext.VILLAGE if settled.a > 0.25 else RoadContext.RURAL)
	if settled.g > 0.5:
		return RoadContext.TOWN
	return RoadContext.VILLAGE if settled.r > 0.5 else RoadContext.RURAL


## How much meadow variety (MeadowPatches: patches, tall grass, flower drifts)
## applies at a growing point: everywhere without observed zones; not on
## mown gardens or fields with them.
func variety_at(x: float, z: float) -> float:
	if not observed and not painted(x, z):
		return 1.0
	var w := growing_weights(x, z)
	# Village meadows keep their variety; town ground and verges are kept short.
	# Dune grassland and heath are short and even: no lush patches or drifts.
	return 1.0 - w[Zone.GARDEN] - w[Zone.FARMLAND] - w[Zone.TOWN] - w[Zone.ROAD] - w[Zone.DUNE] - w[Zone.HEATH]


## The growing zones' share of a point that does grow (meadow + conifer +
## broadleaf = 1), i.e. weights_for() divided by the growth mask. This is all
## a grass tuft needs -- it only stands where something grows -- and skips the
## growth-mask and altitude work weights_for() repeats. x = meadow,
## y = conifer, z = broadleaf.
func growing_shares(x: float, z: float) -> Vector3:
	if observed or painted(x, z):
		var w := growing_weights(x, z)
		var woods := w[Zone.WOODLAND_CONIFER] + w[Zone.WOODLAND_BROADLEAF]
		return Vector3(1.0 - woods, w[Zone.WOODLAND_CONIFER], w[Zone.WOODLAND_BROADLEAF])
	var f := families(x, z)
	var wood := woodland_extent(f)
	if wood <= 0.0:
		return Vector3(1.0, 0.0, 0.0)
	wood = minf(wood * terrain.tree_mask_factor(x, z), 1.0)
	var share := conifer_share(f)
	return Vector3(1.0 - wood, wood * share, wood * (1.0 - share))


## growing_shares() without painted zones, for growing_weights().
func _growing_shares_base(x: float, z: float) -> Vector3:
	var f := families(x, z)
	var wood := woodland_extent(f)
	if wood <= 0.0:
		return Vector3(1.0, 0.0, 0.0)
	wood = minf(wood * terrain.tree_mask_factor(x, z), 1.0)
	var share := conifer_share(f)
	return Vector3(1.0 - wood, wood * share, wood * (1.0 - share))


## The blended grass recipe at a growing point: x = keep, y = height scale,
## z = footprint (width) scale, w = shade.
func grass_effect(x: float, z: float) -> Vector4:
	if observed or painted(x, z):
		return Vector4(_blend_growing(grass_keep, 0, x, z), _blend_growing(grass_height, 0, x, z),
			_blend_growing(grass_footprint, 0, x, z), _blend_growing(grass_shade, 0, x, z))
	var s := growing_shares(x, z)
	var m := Zone.MEADOW
	var c := Zone.WOODLAND_CONIFER
	var b := Zone.WOODLAND_BROADLEAF
	return Vector4(
		s.x * grass_keep[m] + s.y * grass_keep[c] + s.z * grass_keep[b],
		s.x * grass_height[m] + s.y * grass_height[c] + s.z * grass_height[b],
		s.x * grass_footprint[m] + s.y * grass_footprint[c] + s.z * grass_footprint[b],
		s.x * grass_shade[m] + s.y * grass_shade[c] + s.z * grass_shade[b],
	)


## The weight-blended value of one recipe property, e.g. "grass_keep".
static func blend(zone_weights: PackedFloat32Array, recipes: Array[ZoneRecipe], property: StringName) -> float:
	var total := 0.0
	for i in COUNT:
		if zone_weights[i] > 0.0:
			total += zone_weights[i] * float(recipes[i].get(property))
	return total
