class_name ZoneRecipe
extends Resource

## What one environment zone does to the layers drawn over it. Layers blend
## recipes by EnvironmentZones weights at each point, e.g. grass keep is
## sum(weight[z] * recipe[z].grass_keep).
##
## A freshly made recipe is neutral: it changes nothing. A profile slot left
## empty uses region_default() instead, which is where the built-in look of
## each zone lives (woodland floors, phase Z2). See
## docs/ENVIRONMENT_ZONES.md.

@export_group("Grass")
## Share of the grass scatter kept in this zone. 1 = unchanged.
@export_range(0.0, 1.0) var grass_keep: float = 1.0
## Multiplier on surviving tuft height.
@export_range(0.25, 2.0) var grass_height_scale: float = 1.0
## Multiplier on surviving tuft width, separate from height. The pack's
## grass tufts are wide, low mats (about 7x wider than tall), so thinning
## alone still carpets the ground; narrowing them turns a sparse floor into
## scattered sprigs. Visible ground cover scales with keep x footprint^2.
@export_range(0.1, 2.0) var grass_footprint: float = 1.0
## Pushes surviving tufts towards the dark end of the grass palette.
@export_range(0.0, 1.0) var grass_shade: float = 0.0

@export_group("Meadow variety")
## Meadow variety (MeadowPatches, Z4); read from the MEADOW recipe only.
## Up to this share of tufts in lush patches draw as tall grass.
@export_range(0.0, 1.0) var tall_grass_share: float = 0.0
## How strongly lush/thin patches vary tuft height and colour. 0 = uniform.
@export_range(0.0, 1.0) var grass_patchiness: float = 0.0
## 0 = flowers sprinkled evenly (flower_chance alone); 1 = gathered in drifts
## of one kind.
@export_range(0.0, 1.0) var bloom_clustering: float = 0.0

@export_group("Ground")
## Near-range terrain tint. Strength 0 = off. Only the woodland, dune and
## heath zones' tints reach terrain.gdshader so far; other zones' are ignored.
@export var ground_tint: Color = Color(0.3, 0.25, 0.17)
@export_range(0.0, 1.0) var ground_tint_strength: float = 0.0

@export_group("Floor cover")
## Forest-floor cover (GroundCoverScatter), each 0..1 as the share of its
## scatter grid that gets an instance at full zone weight. 0 = none.
@export_range(0.0, 1.0) var moss_density: float = 0.0
## Fallen branches and sticks.
@export_range(0.0, 1.0) var litter_density: float = 0.0
@export_range(0.0, 1.0) var stump_density: float = 0.0
## Mushroom clusters.
@export_range(0.0, 1.0) var mushroom_density: float = 0.0
## Reeds and rushes away from open water (wetland).
@export_range(0.0, 1.0) var reed_density: float = 0.0
## Free-standing bushes (scrub), independent of the tree layer's shrubs.
@export_range(0.0, 1.0) var bush_density: float = 0.0
## Marram grass clumps (dune).
@export_range(0.0, 1.0) var marram_density: float = 0.0
## Heather and crowberry (heath).
@export_range(0.0, 1.0) var heather_density: float = 0.0
## Sea buckthorn bushes (dune scrub).
@export_range(0.0, 1.0) var buckthorn_density: float = 0.0

@export_group("Undergrowth")
## Multipliers on shrub and debris density in this zone. 1 = unchanged.
@export_range(0.0, 4.0) var shrub_multiplier: float = 1.0
@export_range(0.0, 4.0) var debris_multiplier: float = 1.0
## Young trees (the regrowth species) where this zone is painted in Location
## Studio, 0..1 acceptance; read for painted SCRUB (S4).
@export_range(0.0, 1.0) var young_tree_density: float = 0.0


## True when this recipe changes nothing, so a layer can skip zone sampling.
func is_neutral() -> bool:
	return is_equal_approx(grass_keep, 1.0) and is_equal_approx(grass_height_scale, 1.0) \
		and is_equal_approx(grass_footprint, 1.0) \
		and grass_shade <= 0.0 and ground_tint_strength <= 0.0 \
		and floor_neutral() \
		and tall_grass_share <= 0.0 and grass_patchiness <= 0.0 and bloom_clustering <= 0.0 \
		and is_equal_approx(shrub_multiplier, 1.0) and is_equal_approx(debris_multiplier, 1.0)


## True when this recipe places no forest-floor cover.
func floor_neutral() -> bool:
	return moss_density <= 0.0 and litter_density <= 0.0 and stump_density <= 0.0 and mushroom_density <= 0.0 \
		and reed_density <= 0.0 and bush_density <= 0.0 		and marram_density <= 0.0 and heather_density <= 0.0 and buckthorn_density <= 0.0


## The built-in recipe for `zone` (EnvironmentZones.Zone) in a nature region
## (NatureAssetCatalogue.REGIONS). Neutral for zones without one yet.
##
## Woodland floors: real forest floors carry little grass. Shade and needle
## litter leave conifer interiors close to bare; broadleaf woods keep more,
## patchier grass in their light gaps. Drier regions' open woods keep more
## grass and a drier ground colour.
static func region_default(region: String, zone: int) -> ZoneRecipe:
	var recipe := ZoneRecipe.new()
	var dry := region in ["mediterranean", "warm_dry", "cold_dry"]
	match zone:
		EnvironmentZones.Zone.MEADOW:
			# Lush lowland meadows grow tall in damp patches; alpine and polar
			# turf stays short, dry grassland pale and patchy.
			var short_turf := region in ["alpine", "polar"]
			recipe.tall_grass_share = 0.15 if short_turf else (0.25 if dry else 0.45)
			recipe.grass_patchiness = 0.5 if short_turf else (0.8 if dry else 0.7)
			recipe.bloom_clustering = 0.8
		EnvironmentZones.Zone.WOODLAND_CONIFER:
			recipe.grass_keep = 0.25 if dry else (0.12 if region == "boreal" else 0.08)
			recipe.grass_height_scale = 0.8
			recipe.grass_footprint = 0.45
			recipe.grass_shade = 0.5
			# Needle litter over dark soil; boreal floors run mossier.
			if dry:
				recipe.ground_tint = Color(0.36, 0.30, 0.20)
			elif region == "boreal":
				recipe.ground_tint = Color(0.24, 0.24, 0.13)
			else:
				recipe.ground_tint = Color(0.27, 0.21, 0.14)
			recipe.ground_tint_strength = 0.7
			# Spruce floors: moss carpets, needles, fallen twigs, ceps and fly
			# agaric. Dry pine woods keep the litter but little moss.
			recipe.moss_density = 0.12 if dry else 0.4
			recipe.litter_density = 0.35
			recipe.stump_density = 0.2
			recipe.mushroom_density = 0.04 if dry else 0.1
		EnvironmentZones.Zone.WOODLAND_BROADLEAF:
			recipe.grass_keep = 0.5 if dry else 0.35
			recipe.grass_height_scale = 0.9
			recipe.grass_footprint = 0.6
			recipe.grass_shade = 0.35
			# Leaf litter and moss: darker and browner than the meadow.
			recipe.ground_tint = Color(0.36, 0.30, 0.20) if dry else Color(0.21, 0.23, 0.12)
			recipe.ground_tint_strength = 0.5
			# Broadleaf floors: more fallen wood, less moss than under spruce.
			recipe.moss_density = 0.06 if dry else 0.2
			recipe.litter_density = 0.45
			recipe.stump_density = 0.2
			recipe.mushroom_density = 0.03 if dry else 0.07
		EnvironmentZones.Zone.WETLAND:
			# Reed fen and wet meadow: tall, lush, dark sedge and grass with
			# reeds and rushes, a little moss, few shrubs.
			recipe.grass_height_scale = 1.35
			recipe.grass_shade = 0.35
			recipe.reed_density = 0.12 if dry else 0.3
			recipe.moss_density = 0.1
			recipe.shrub_multiplier = 0.4
		EnvironmentZones.Zone.FARMLAND:
			# Arable fields: the site mask already keeps grass off tilled
			# ground; what grows is short stubble and margins, no shrubs.
			recipe.grass_keep = 0.6
			recipe.grass_height_scale = 0.75
			recipe.shrub_multiplier = 0.0
		EnvironmentZones.Zone.GARDEN:
			# Mown lawns and yards: short, even grass, no litter or drifts
			# (MeadowPatches stands down via EnvironmentZones.variety_at()).
			recipe.grass_height_scale = 0.35
			recipe.grass_footprint = 0.9
			recipe.shrub_multiplier = 0.25
		EnvironmentZones.Zone.SCRUB:
			# Shrubland: dense bushes in rough, slightly taller grass.
			recipe.grass_keep = 0.8
			recipe.grass_height_scale = 1.15
			recipe.grass_shade = 0.15
			recipe.bush_density = 0.3 if dry else 0.55
			recipe.litter_density = 0.1
			recipe.shrub_multiplier = 2.0
			# Scattered birch, willow and thorn saplings among the bushes.
			recipe.young_tree_density = 0.15 if dry else 0.3
		EnvironmentZones.Zone.VILLAGE:
			# Village greens, yards and corners: mostly mown, some rough
			# edges and hedging, little woody debris.
			recipe.grass_height_scale = 0.6
			recipe.grass_footprint = 0.95
			recipe.tall_grass_share = 0.1
			recipe.grass_patchiness = 0.4
			recipe.shrub_multiplier = 0.6
			recipe.debris_multiplier = 0.3
		EnvironmentZones.Zone.TOWN:
			# Town ground: short, patchy turf between paving; few shrubs.
			recipe.grass_keep = 0.55
			recipe.grass_height_scale = 0.4
			recipe.grass_footprint = 0.85
			recipe.shrub_multiplier = 0.2
			recipe.debris_multiplier = 0.1
		EnvironmentZones.Zone.ROAD:
			# Verges: cut short and even next to the carriageway, no shrubs,
			# no litter or stumps.
			recipe.grass_height_scale = 0.5 if dry else 0.55
			recipe.grass_footprint = 0.9
			recipe.grass_keep = 0.75 if dry else 0.95
			recipe.shrub_multiplier = 0.0
			recipe.debris_multiplier = 0.0
		EnvironmentZones.Zone.DUNE:
			# Grey dune: short, sparse grass and sedge in thin tufts over pale
			# sand, carpets of moss and lichen between them, marram clumps,
			# scattered sea buckthorn and the odd juniper; no woody litter. The tint
			# is the sandy ground between tufts; open sand and beach use it
			# at full strength (terrain.gdshader).
			recipe.grass_keep = 0.3
			recipe.grass_height_scale = 0.5
			recipe.grass_footprint = 0.4
			recipe.grass_shade = 0.15
			recipe.ground_tint = Color(0.66, 0.61, 0.48)
			recipe.ground_tint_strength = 0.55
			recipe.moss_density = 0.25
			recipe.marram_density = 0.12
			recipe.buckthorn_density = 0.05
			recipe.bush_density = 0.02
			recipe.shrub_multiplier = 0.3
			recipe.debris_multiplier = 0.2
		EnvironmentZones.Zone.HEATH:
			# Dwarf-shrub heath: a near-continuous carpet of low heather and
			# crowberry, sparse dark grass on peaty sand, a little moss, scattered
			# juniper. Tuned on the Totengrund (Lueneburger Heide), the first real
			# heath: more grass than this read as a green meadow.
			recipe.grass_keep = 0.15
			recipe.grass_height_scale = 0.6
			recipe.grass_footprint = 0.5
			recipe.grass_shade = 0.35
			recipe.ground_tint = Color(0.30, 0.24, 0.20)
			recipe.ground_tint_strength = 0.65
			recipe.moss_density = 0.1
			recipe.heather_density = 0.85
			recipe.bush_density = 0.08
			recipe.shrub_multiplier = 0.6
			recipe.debris_multiplier = 0.3
	return recipe
