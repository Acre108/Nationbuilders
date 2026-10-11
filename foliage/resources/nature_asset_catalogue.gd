class_name NatureAssetCatalogue
extends RefCounted

## Available regional approximations, not a botanical occurrence database.
## The pack has no tropical canopy, true fir or alpine cushion species.
const REGIONS := ["temperate", "mediterranean", "boreal", "alpine", "polar", "warm_dry", "cold_dry", "tropical"]
const LAKE_BRIENZ_ASSETS := ["birch_2", "birch_3", "lake_reeds", "lake_rushes", "reed_seedheads", "lake_pebble_1", "lake_pebble_2", "lake_pebble_3", "lake_boulder_1", "lake_boulder_2", "lake_boulder_3"]
## Authored additions are available for explicit placement, outside pack imports.
const CUSTOM_ASSETS := ["willow_weeping"]
## Woodland structure: young trees (regrowth slot 9), deadwood (debris) and
## bramble edges. See docs/NATURE_PACK.md.
const WOODLAND_ASSETS := ["young_tree_1", "young_tree_2", "young_tree_3", "young_tree_4", "young_tree_5",
	"fallen_tree", "broken_tree", "dried_wood", "trunk_1", "trunk_2", "half_trunk", "blackberry", "raspberry"]
## Deadwood debris heights in metres (the logs' and trunks' lying thickness;
## stumps and snags standing). Unlisted deadwood stays at 0.5 m.
const DEADWOOD_HEIGHTS := {"fallen_tree": 1.6, "broken_tree": 1.6, "half_trunk": 2.2, "trunk_1": 0.55, "trunk_2": 0.45}
## Coastal dune and heath floor cover (FLOOR_ASSETS marram, heather, buckthorn).
const DUNE_HEATH_ASSETS := ["marram_1", "marram_2", "sea_buckthorn", "heather_1", "heather_2", "heather_3"]
## Managed field plants for SiteCropLayer, never wild scatter.
const CROP_ASSETS := ["wheat", "sunflower"]
## Forest-floor cover (environment zones Z3), by GroundCoverScatter category.
## Stand-ins: the pack has no needle or leaf litter mesh (needle_litter is a
## mat of dry twigs, SM_Muss_011) and no conifer stumps (the broadleaf stumps
## stand in). Dune and heath (DUNE, HEATH zones): sea reeds stand in for
## marram grass, wolfberry for sea buckthorn, and lavender with the red moss
## mats (SM_Moss_03, SM_Muss_012) for heather and crowberry.
const FLOOR_ASSETS := {
	"moss": ["moss_1", "moss_tuft", "needle_litter"],
	"litter": ["branch_1", "branch_3", "stick_1", "stick_4", "stick_5"],
	"stump": ["stump_oak", "stump_maple", "stump_poplar"],
	"mushroom": ["mushroom_boletus", "mushroom_chanterelle", "mushroom_agaric", "mushroom_russula", "mushroom_toadstool"],
	# Wetland and scrub (Z6) reuse the shoreline reeds and the shrubs.
	"reed": ["lake_reeds", "lake_rushes", "reed_seedheads"],
	"bush": ["bush_1", "bush_2", "bush_3", "juniper"],
	"marram": ["marram_1", "marram_2"],
	"heather": ["heather_1", "heather_2", "heather_3"],
	"buckthorn": ["sea_buckthorn"],
}
## Colour adjustments applied when an asset's mesh is built
## (NatureMeshBuilder), without editing the converted assets. The pack's floor
## textures are autumnal and very saturated: its mosses turn yellow in full
## sun (a multiply pulls them back to green), and its dry-twig mat mixes
## orange and red strands that no multiply turns brown, so it gets a hue
## replacement instead (rgb = sRGB target, a = amount; see nature_pack.gdshader).
const ASSET_TINTS := {
	"moss_1": Color(0.72, 0.95, 0.58),
	"moss_tuft": Color(0.7, 0.92, 0.6),
}
const ASSET_RECOLOURS := {
	"needle_litter": Color(0.3, 0.21, 0.13, 0.9),
	# The sea reeds' seed heads are pink; marram's are pale straw.
	"marram_1": Color(0.74, 0.70, 0.52, 0.7), "marram_2": Color(0.74, 0.70, 0.52, 0.7),
	# The red moss mats read as paint-red; ling and crowberry mats are russet.
	"heather_2": Color(0.36, 0.21, 0.17, 0.6), "heather_3": Color(0.36, 0.21, 0.17, 0.6),
}
## Target heights in metres. The source stumps are 1.4-1.6 m tall, far above a
## real cut or snapped stump, so they are scaled down to about half a metre.
const FLOOR_HEIGHTS := {
	"moss_1": 0.22, "moss_tuft": 0.18, "needle_litter": 0.07,
	"branch_1": 0.3, "branch_3": 0.35, "stick_1": 0.06, "stick_4": 0.06, "stick_5": 0.09,
	"stump_oak": 0.55, "stump_maple": 0.5, "stump_poplar": 0.6,
	"mushroom_boletus": 0.12, "mushroom_chanterelle": 0.08, "mushroom_agaric": 0.16,
	"mushroom_russula": 0.09, "mushroom_toadstool": 0.1,
	"lake_reeds": 1.6, "lake_rushes": 1.3, "reed_seedheads": 1.8,
	"bush_1": 1.4, "bush_2": 1.1, "bush_3": 1.6, "juniper": 1.5,
	"marram_1": 0.8, "marram_2": 0.7, "heather_1": 0.4, "heather_2": 0.25, "heather_3": 0.2,
	"sea_buckthorn": 2.2,
}
const ASSETS := ["oak", "birch", "maple", "aspen", "poplar", "spruce", "tall_spruce", "small_spruce", "pine", "bush_1", "bush_2", "bush_3", "juniper", "fern_1", "fern_2", "fern_3", "moss_1", "moss_2", "agave", "aloe", "grass", "grass_short", "grass_simple", "flowers", "rock_1", "rock_2", "rock_3", "log_1", "log_2", "log_3", "moss_tuft", "needle_litter", "branch_1", "branch_3", "stick_1", "stick_4", "stick_5", "stump_oak", "stump_maple", "stump_poplar", "mushroom_boletus", "mushroom_chanterelle", "mushroom_agaric", "mushroom_russula", "mushroom_toadstool", "grass_tall", "daisies", "wildflower_blue", "wildflower_purple", "wildflower_pink", "wildflower_red", "wildflower_orange"] + LAKE_BRIENZ_ASSETS + CUSTOM_ASSETS + CROP_ASSETS + WOODLAND_ASSETS + DUNE_HEATH_ASSETS
const SHORE_ASSETS := ["lake_reeds", "lake_rushes", "reed_seedheads", "lake_pebble_1", "lake_pebble_2", "lake_pebble_3", "lake_boulder_1", "lake_boulder_2", "lake_boulder_3"]
const SHORE_HEIGHTS := [1.9, 1.6, 2.1, 0.22, 0.30, 0.42, 0.9, 1.2, 1.8]

static func asset_path(asset: String) -> String:
	return "res://assets/foliage/%s/%s.glb" % ["custom" if asset in CUSTOM_ASSETS else "poly_nature", asset]

static func region_for(climate: String, latitude: float = 50.0, alpine: bool = false) -> String:
	if alpine:
		return "alpine"
	if climate.begins_with("Cs"):
		return "mediterranean"
	match climate.left(1):
		"A": return "tropical"
		"B": return "warm_dry" if climate.ends_with("h") and absf(latitude) < 40.0 else "cold_dry"
		# Hot- and warm-summer continental climates (Dfa/Dfb, Dsa/Dsb, Dwa/Dwb)
		# carry mixed and broadleaf forest, as in Brandenburg or the Black
		# Forest; only the cold-summer classes (c, d) are taiga.
		"D": return "temperate" if climate.substr(2, 1) in ["a", "b"] else "boreal"
		"E": return "polar"
		_: return "temperate"

static func region(profile: FoliageProfile) -> String:
	if profile.nature_region in REGIONS:
		return profile.nature_region
	return region_for(profile.climate_zone, 50.0, profile.terrain != null and profile.terrain.treeline < 9000.0 and profile.climate_zone.begins_with("E"))

## Each position is the existing TreePlacer species slot. Keeping those slots
## preserves scatter seeds and compatibility with authored family controls.
static func choices(profile: FoliageProfile, species: int) -> Array:
	if species == 0 and not profile.broadleaf_assets.is_empty():
		return Array(profile.broadleaf_assets)
	if species == 1 and not profile.light_tree_assets.is_empty():
		return Array(profile.light_tree_assets)
	if species == 3 and not profile.low_shrub_assets.is_empty():
		return Array(profile.low_shrub_assets)
	if species == 9:
		if not profile.regrowth_assets.is_empty():
			return Array(profile.regrowth_assets)
		if maxf(profile.conifer_cover, profile.fir_cover) > profile.tree_cover:
			return ["small_spruce", "small_spruce", "young_tree_3"]
		return ["young_tree_1", "young_tree_4", "young_tree_5"]
	if profile.nature_asset_set == "lake_brienz":
		match species:
			0: return ["maple", "maple", "aspen"]
			1: return ["birch", "birch_2", "birch_3"]
			2, 3: return ["bush_1", "bush_2", "juniper"]
	var biome := region(profile)
	var broadleaf := ["oak", "maple", "poplar"]
	var light_tree := ["birch", "aspen", "birch"]
	var shrubs := ["bush_1", "bush_2", "bush_3"]
	if biome in ["boreal", "alpine", "cold_dry", "polar"]:
		broadleaf = ["aspen", "birch", "aspen"]
		shrubs = ["juniper", "bush_2", "juniper"]
	elif biome == "warm_dry":
		shrubs = ["agave", "aloe", "agave"]
	match species:
		0: return broadleaf
		1: return light_tree
		2, 3: return shrubs
		4: return ["spruce", "tall_spruce", "small_spruce"]
		5: return ["pine", "pine", "pine"]
		6: return ["spruce", "tall_spruce", "spruce"] # closest available fir stand-in
		7: return ["fern_1", "fern_2", "fern_3"]
		8: return ["moss_1", "moss_2", "moss_1"] # low alpine ground-cover stand-in
	return []

static func debris_assets(profile: FoliageProfile, rocks: bool) -> Array:
	if not rocks:
		# A cut log, a fallen tree with its crown of dead branches, and a
		# broken standing stump: the deadwood of an unmanaged wood.
		return ["log_1", "fallen_tree", "half_trunk"] if profile.woodland_deadwood else ["log_1", "log_2", "log_3"]
	return ["lake_boulder_1", "lake_boulder_2", "lake_boulder_3"] if profile.nature_asset_set == "lake_brienz" else ["rock_1", "rock_2", "rock_3"]

## Forest-floor assets for one GroundCoverScatter category in this profile's
## region. Dry regions get no moss: their open woods have a bare, dry floor.
static func floor_assets(profile: FoliageProfile, category: String) -> Array:
	if category == "moss" and region(profile) in ["mediterranean", "warm_dry", "cold_dry"]:
		return ["needle_litter"]
	return FLOOR_ASSETS[category]


## The tall grass drawn in lush meadow patches (MeadowPatches), or "" for none.
## A light card clump (26 triangles): it is instanced at grass density.
static func tall_grass_asset(_profile: FoliageProfile) -> String:
	return "grass_tall"


## Flower sets for this region's meadows, one draw set each, at most four:
## each set is another MultiMesh per grass chunk. Daisies everywhere; the
## coloured wild flowers vary by region. The pack's dense flower clump
## ("flowers", 832 triangles) is replaced here by these 20-26 triangle cards.
static func meadow_flowers(profile: FoliageProfile) -> Array:
	match region(profile):
		"alpine", "polar":
			return ["daisies", "wildflower_blue", "wildflower_purple"]
		"mediterranean", "warm_dry", "cold_dry":
			return ["daisies", "wildflower_orange", "wildflower_red", "wildflower_purple"]
		_:
			return ["daisies", "wildflower_blue", "wildflower_pink", "wildflower_red"]


static func grass_asset(profile: FoliageProfile, far: bool = false) -> String:
	if far:
		return "grass_simple"
	return "grass_short" if region(profile) in ["alpine", "polar", "warm_dry", "cold_dry"] else "grass"

## Applied only during import; hand-authored profiles remain editable.
static func apply_import_defaults(profile: FoliageProfile, latitude: float) -> void:
	profile.nature_region = region_for(profile.climate_zone, latitude, profile.terrain != null and profile.terrain.treeline < 9000.0 and profile.climate_zone.begins_with("E"))
	match profile.nature_region:
		"tropical":
			# No oak/birch forest as a surrogate for rainforest.
			profile.tree_cover = 0.0
			profile.conifer_cover = 0.0
			profile.fir_cover = 0.0
			profile.fern_cover = 0.2
		"mediterranean":
			profile.conifer_cover = 0.25
			profile.conifer_spruce_share = 0.0
			profile.fir_cover = 0.0
			profile.fern_cover = 0.0
		"warm_dry", "cold_dry":
			profile.tree_cover = 0.0
			profile.flower_chance = 0.0
		"polar":
			profile.flower_chance = 0.0
