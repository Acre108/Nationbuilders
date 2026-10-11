class_name FoliageProfile
extends Resource

## Everything that makes one real location look like itself.
##
## Part 3 of the brief: each outdoor location gets its own palette, density,
## mask and atmosphere, authored as a Resource so a place can be restyled
## without touching code. Indoor locations simply have no GrassLayer, or set
## `enabled = false`.
##
## The critical job of this resource is apply_to_materials(): it pushes ONE set
## of values into both the grass material and the terrain material. That shared
## push is what makes the horizon handover invisible -- if grass and terrain
## ever get their palette or wind settings from different places, the streaming
## boundary becomes a visible ring on the ground.
##
## Saved per location as a .tres (content/locations/). FoliageLocation reads
## it and builds everything; nothing else should construct one in code except
## tests.

## Reference palettes, darkest/shadowed at 0 to lightest/sun-bleached at 1.
## A new location starts by copying one of these and shifting it.
##
## These are static functions, not constants, for two stacked GDScript reasons:
## Color("#hex") is not a constant expression so it cannot initialise a `const`
## at all, and an external class's constant cannot be resolved as an @export
## default even when it is one. The defaults below are therefore written inline.
static func palette_meadow() -> PackedColorArray:
	return PackedColorArray([
		Color("#2f4423"), Color("#446329"), Color("#5d8236"), Color("#7ba24a"), Color("#a8c46b"),
	])

static func palette_dry_field() -> PackedColorArray:
	return PackedColorArray([
		Color("#4a4526"), Color("#6b6231"), Color("#8f8244"), Color("#b5a360"), Color("#d6c288"),
	])

## Tree canopies sit darker and cooler than the grass under them; a canopy on
## the grass palette reads as a lawn floating in the air.
static func palette_canopy() -> PackedColorArray:
	return PackedColorArray([
		Color("#1f3319"), Color("#2d4a22"), Color("#3f6330"), Color("#587e3c"), Color("#7d9f52"),
	])

static func palette_flowers_warm() -> PackedColorArray:
	return PackedColorArray([
		Color("#8a4a5e"), Color("#c76a7a"), Color("#e8a0a0"), Color("#f4d4a8"), Color("#fdf2d0"),
	])

## Rainforest: none of the four palettes above fit -- meadow and dry_field
## are both too muted, canopy is too dark to use as ground cover on its own.
static func palette_tropical() -> PackedColorArray:
	return PackedColorArray([
		Color("#0f3d1a"), Color("#155c24"), Color("#1f8033"), Color("#3aa84a"), Color("#7ed957"),
	])

## Polar/tundra: pale and desaturated, nothing existing is close.
static func palette_tundra() -> PackedColorArray:
	return PackedColorArray([
		Color("#5a5f52"), Color("#767c68"), Color("#93987f"), Color("#b3b79c"), Color("#d4d6bd"),
	])

## Picks a reference palette from a Koppen climate class code (e.g. "Cfb"),
## by its leading letter group -- see tools/geo/import_koppen.py for how a
## real-world location's code is derived. Approximate, not authoritative: a
## location built this way is meant to be a starting point to shift from
## (palette_offset/palette_contrast), the same as copying any other
## palette_*() by hand.
static func palette_for_koppen(code: String) -> PackedColorArray:
	match code.substr(0, 1):
		"A":
			return palette_tropical()
		"B":
			return palette_dry_field()
		"C":
			return palette_meadow()
		"D":
			# Continental climates correlate with conifer forest more than
			# with open meadow; the closest existing fit, not an exact one.
			return palette_canopy()
		"E":
			return palette_tundra()
		_:
			return palette_meadow()


@export_group("Identity")
@export var location_name: String = "Untitled meadow"
## Fixes the scatter for this location. Every client derives the same grass from
## it, which is why grass never needs to be networked.
@export var world_seed: int = 20260918
@export var enabled: bool = true
## Koppen climate class from geographic import. Also resolves the nature
## asset region at runtime when nature_region is left at auto.
@export var climate_zone: String = ""

@export_group("Nature pack")
@export var use_nature_pack: bool = true
## Auto resolves climate for authored profiles; the importer persists its
## selection using climate, latitude and the location's alpine altitude rules.
@export_enum("auto", "temperate", "mediterranean", "boreal", "alpine", "polar", "warm_dry", "cold_dry", "tropical") var nature_region: String = "auto"
## A curated place-specific selection layered over the climate region.
@export_enum("regional", "lake_brienz") var nature_asset_set: String = "regional"

@export_group("Shoreline foliage")
## Opt-in: requires fitted lake outlines from the water importer. This layer
## reads shoreline/level data; it never creates or modifies water geometry.
@export_range(0.0, 1.0) var shoreline_reed_cover: float = 0.0
@export_range(0.0, 1.0) var shoreline_rock_cover: float = 0.0
@export_range(0.8, 5.0, 0.1) var shoreline_reed_spacing: float = 1.6
@export_range(2.0, 12.0, 0.5) var shoreline_rock_spacing: float = 4.0
## Empty accepts all fitted lakes; Brienz is restricted to Brienzersee,
## excluding the high mountain tarns present in the same terrain crop.
@export var shoreline_lake_name: String = ""
## Streams and rivers (fitted imports): pebbles across their beds and along
## their banks, a few boulders in wider ones, and reeds on calm reaches. On by
## default, unlike the lake shore: every imported stream wants a bed.
@export_range(0.0, 1.0) var stream_rock_cover: float = 0.5
@export_range(0.0, 1.0) var stream_reed_cover: float = 0.25

@export_group("Palette")
@export var grass_palette: PackedColorArray = PackedColorArray([
	Color("#2f4423"), Color("#446329"), Color("#5d8236"), Color("#7ba24a"), Color("#a8c46b"),
])
@export var flower_palette: PackedColorArray = PackedColorArray([
	Color("#8a4a5e"), Color("#c76a7a"), Color("#e8a0a0"), Color("#f4d4a8"), Color("#fdf2d0"),
])
@export_range(-1.0, 1.0) var palette_offset: float = 0.0
@export_range(0.1, 3.0) var palette_contrast: float = 1.0
## World units per tile of colour noise. Larger values = broader colour patches.
@export_range(0.001, 1.0, 0.001) var colour_noise_scale: float = 0.035
@export_range(0.0, 1.0) var colour_octave_mix: float = 0.35

@export_group("Wind")
@export var wind_direction: Vector2 = Vector2(1.0, 0.35)
@export_range(0.0, 2.0) var wind_speed: float = 0.12
@export_range(0.0, 2.0) var wind_strength: float = 0.28
## Grass samples wind at this scale. Terrain multiplies it by
## `terrain_wind_scale_multiplier` so distant fields show broad rolling waves
## instead of per-blade noise, which would alias into shimmer at range.
@export_range(0.0005, 0.5, 0.0005) var wind_noise_scale: float = 0.02
@export_range(0.02, 1.0) var terrain_wind_scale_multiplier: float = 0.18
@export_range(0.0, 1.0) var wind_colour_shift: float = 0.18

## How a clump is drawn.
##
## SPRITE_CARDS is the default: crossed quads textured from the clump sprite
## atlas. The two BLADE_ styles build the clump from individual tapered blade
## geometry instead -- fully opaque, no alpha scissor, but several times the
## triangles. BLADE_DOME is the rounded tussock shape, kept for scrubbier or
## alpine biomes where clumps should stay individually legible.
enum ClumpStyle { SPRITE_CARDS, BLADE_FLAT, BLADE_DOME }

@export_group("Grass")
@export var clump_style: ClumpStyle = ClumpStyle.SPRITE_CARDS
## Tufts per square metre at Ultra quality. FoliageQuality scales this down.
@export_range(0.1, 20.0, 0.1) var base_density: float = 3.0
@export_range(0.05, 3.0, 0.01) var tuft_height: float = 0.45
@export_range(0.0, 1.0) var flower_chance: float = 0.0
@export_range(0.0, 1.0) var root_darkening: float = 0.5
## Backlight. Low for sprite cards and high for blade geometry, because the
## forced +Y normal means a card never faces away from the sun -- backlight
## stops being rim transmission and becomes a flat brightness boost that washes
## the whole field out.
@export_range(0.0, 1.0) var translucency: float = 0.22
@export_range(0.0, 1.0) var slope_align: float = 0.35

@export_group("Woodland floor")
## Extra bushes, rocks and logs in the same groves as broadleaf/conifer/fir
## trees. Independent of authored shrub/debris cover. Off costs no scatter.
@export var woodland_floor_enabled: bool = true
@export_range(0.0, 1.0) var woodland_floor_density: float = 0.55
@export_range(2.0, 20.0, 0.5) var woodland_bush_spacing: float = 5.0
@export_range(4.0, 40.0, 1.0) var woodland_debris_spacing: float = 12.0


func woodland_cover() -> float:
	if not enabled or not woodland_floor_enabled or woodland_floor_density <= 0.0:
		return 0.0
	return maxf(tree_cover, maxf(conifer_cover, fir_cover))


@export_group("Zones")
## What each environment zone (EnvironmentZones.Zone) does to the layers over
## it. Empty slots use ZoneRecipe.region_default() for this profile's nature
## region; set one to override it. See docs/ENVIRONMENT_ZONES.md.
@export var meadow_recipe: ZoneRecipe
@export var woodland_conifer_recipe: ZoneRecipe
@export var woodland_broadleaf_recipe: ZoneRecipe
@export var rock_recipe: ZoneRecipe
@export var snow_recipe: ZoneRecipe
@export var bare_recipe: ZoneRecipe
@export var shore_recipe: ZoneRecipe
@export var wetland_recipe: ZoneRecipe
@export var farmland_recipe: ZoneRecipe
@export var garden_recipe: ZoneRecipe
@export var scrub_recipe: ZoneRecipe
@export var village_recipe: ZoneRecipe
@export var town_recipe: ZoneRecipe
@export var road_recipe: ZoneRecipe
@export var dune_recipe: ZoneRecipe
@export var heath_recipe: ZoneRecipe


## Off keeps every unset slot neutral instead of using region defaults --
## for fixtures that must not change when zone defaults are tuned.
@export var zone_defaults_enabled: bool = true


## One recipe per EnvironmentZones.Zone, in enum order. Unset slots use the
## region default, or a neutral recipe when zone_defaults_enabled is off.
func zone_recipes() -> Array[ZoneRecipe]:
	var set: Array[ZoneRecipe] = [meadow_recipe, woodland_conifer_recipe, woodland_broadleaf_recipe, rock_recipe, snow_recipe, bare_recipe, shore_recipe, wetland_recipe, farmland_recipe, garden_recipe, scrub_recipe, village_recipe, town_recipe, road_recipe, dune_recipe, heath_recipe]
	assert(set.size() == EnvironmentZones.COUNT, "FoliageProfile.zone_recipes() is missing a zone")
	var region := NatureAssetCatalogue.region(self)
	for i in set.size():
		if set[i] == null:
			set[i] = ZoneRecipe.region_default(region, i) if zone_defaults_enabled else ZoneRecipe.new()
	return set


## True when some zone that can occur here places forest-floor cover
## (GroundCoverScatter, drawn by DebrisLayer). Nature-pack locations only.
## `observed`: the terrain carries observed zones, so wetland, farmland,
## garden, scrub, settlement, dune and heath recipes can apply too.
func floor_cover_wanted(observed: bool = false) -> bool:
	if not enabled or not use_nature_pack:
		return false
	var recipes := zone_recipes()
	if not recipes[EnvironmentZones.Zone.MEADOW].floor_neutral():
		return true
	if observed:
		for zone in [EnvironmentZones.Zone.WETLAND, EnvironmentZones.Zone.FARMLAND, EnvironmentZones.Zone.GARDEN, EnvironmentZones.Zone.SCRUB,
				EnvironmentZones.Zone.VILLAGE, EnvironmentZones.Zone.TOWN, EnvironmentZones.Zone.ROAD,
				EnvironmentZones.Zone.DUNE, EnvironmentZones.Zone.HEATH]:
			if not recipes[zone].floor_neutral():
				return true
	if maxf(tree_cover, maxf(conifer_cover, fir_cover)) <= 0.0:
		return false
	return not (recipes[EnvironmentZones.Zone.WOODLAND_CONIFER].floor_neutral() and recipes[EnvironmentZones.Zone.WOODLAND_BROADLEAF].floor_neutral())


## True when some zone recipe places GroundCoverScatter category `category`.
func floor_category_used(category: String) -> bool:
	var property := category + "_density"
	for recipe in zone_recipes():
		if float(recipe.get(property)) > 0.0:
			return true
	return false


## True when no zone recipe changes anything, so layers can skip sampling.
func zones_neutral() -> bool:
	for recipe in zone_recipes():
		if not recipe.is_neutral():
			return false
	return true


@export_group("Terrain")
## The shape of the ground (world size, rolling ground, hills, valleys), in
## its own resource under content/terrain/. FoliageLocation builds its default
## provider from it, seeded with world_seed. Null means TerrainProfile's
## defaults: gentle rolling ground. A scene that supplies its own provider
## ignores this.
@export var terrain: TerrainProfile

@export_group("Water")
## Sea, lakes and rivers (content/water/). Null, or a profile with its sea
## switched off, means no water at all -- FoliageLocation builds no
## WaterLayer. See WaterProfile for what exists so far.
@export var water: WaterProfile

@export_group("Trees")
@export var tree_palette: PackedColorArray = PackedColorArray([
	Color("#1f3319"), Color("#2d4a22"), Color("#3f6330"), Color("#587e3c"), Color("#7d9f52"),
])
## Fraction of the land that is grove rather than open meadow, 0..1. Groves
## come from a broad noise field, so trees clump into woods with clearings
## rather than dotting the field evenly.
@export_range(0.0, 1.0) var tree_cover: float = 0.3
## Typical spacing between trees inside a grove, metres.
@export_range(3.0, 40.0, 0.5) var tree_spacing: float = 8.0
## Share of oak among placed trees; the rest are birch.
@export_range(0.0, 1.0) var tree_oak_share: float = 0.65
@export_range(0.0, 0.2) var tree_sway: float = 0.035
@export_range(0.0, 0.3) var tree_flutter: float = 0.05
@export_range(0.0, 1.0) var tree_translucency: float = 0.3
@export var bark_tint: Color = Color(1, 1, 1)

@export_group("Shrubs")
## 0 = no shrubs (the default). Independent of `tree_cover` -- a location can
## have shrubs without trees (heathland, a hedged garden) or trees without
## shrubs. Rendered by the same TreeLayer, at rounded-shrub/low-hedge sizes;
## see TreePlacer's class comment for why shrubs correlate with tree groves
## even though the two covers are set separately.
@export_range(0.0, 1.0) var shrub_cover: float = 0.0
## Typical spacing between shrubs, metres. Deliberately tighter than
## tree_spacing -- shrubs are meant to read as undergrowth, not as sparse as
## trees.
@export_range(0.5, 15.0, 0.25) var shrub_spacing: float = 2.5
## Share of rounded-shrub among placed shrubs; the rest are low-hedge.
@export_range(0.0, 1.0) var shrub_share: float = 0.55

@export_group("Conifers")
## 0 = no conifers (the default). Independent of `tree_cover`/`shrub_cover`/
## `fir_cover` -- a real location typically sets this instead of `tree_cover`,
## not alongside it, but nothing stops both (a treeline mixed forest).
## Rendered by the same TreeLayer at spruce/pine sizes; see TreePlacer's
## class comment for why conifers correlate with the same grove field the
## broadleaf trees use. Fir used to be a third share of this same family;
## it is now independent -- see `fir_cover` below -- so a location can run a
## pure fir stand without dragging spruce/pine along.
@export_range(0.0, 1.0) var conifer_cover: float = 0.0
## Typical spacing between conifers, metres. Tighter than tree_spacing --
## conifer stands read as dense, not as an orchard.
@export_range(3.0, 40.0, 0.5) var conifer_spacing: float = 6.0
## Share of spruce among placed conifers; the rest are pine.
@export_range(0.0, 1.0) var conifer_spruce_share: float = 0.7
## Needle colour, separate from tree_palette (broadleaf canopies): conifers
## stay cool, dark blue-green year round rather than a broadleaf's seasonal
## warmer greens. Shared with fir below -- both are needled evergreens in the
## same colour family, just covered and placed independently.
@export var conifer_palette: PackedColorArray = PackedColorArray([
	Color("#101f16"), Color("#16301f"), Color("#1f4429"), Color("#2c5c37"), Color("#457048"),
])

@export_group("Fir")
## 0 = no fir (the default). Independent of every other cover, including
## `conifer_cover` -- fir was originally a share of the conifer family
## (`conifer_fir_share`); it is now its own family placed over the same
## grove field, so a location can mix fir with spruce/pine, run a pure fir
## stand, or skip it entirely. Rendered by the same TreeLayer, drawing the
## same needle atlas and `conifer_palette` as spruce/pine -- visually
## unchanged, only its placement became independent.
@export_range(0.0, 1.0) var fir_cover: float = 0.0
## Typical spacing between fir, metres. Matches conifer_spacing's default --
## fir reads the same density as spruce/pine unless tuned otherwise.
@export_range(3.0, 40.0, 0.5) var fir_spacing: float = 6.0

@export_group("Woodland structure")
## Saplings and young trees (species slot 9) inside woods: the chance per
## regrowth cell, over the woodland field of the canopy families. 0 = none.
@export_range(0.0, 1.0) var regrowth_cover: float = 0.0
## Typical spacing between young trees, metres.
@export_range(1.5, 20.0, 0.5) var regrowth_spacing: float = 4.0
## Nature-pack assets for the young trees; empty = by the dominant canopy
## (young broadleaves, or small spruce in conifer woods).
@export var regrowth_assets: PackedStringArray = PackedStringArray()
## Override the region's broadleaf (slot 0) and light-tree (slot 1) assets,
## e.g. maple-led woods as a beech stand-in. Empty = region default.
@export var broadleaf_assets: PackedStringArray = PackedStringArray()
@export var light_tree_assets: PackedStringArray = PackedStringArray()
## Size spread of canopy trees and conifers (scale on the species height).
## A wider spread reads as an uneven-aged stand rather than one cohort.
## Woodland mantle (Waldmantel): a belt of bushes, brambles and young trees
## on the open side of wood edges, `mantle_width` metres deep. 0 = none, the
## hard line where forest meets meadow.
@export_range(0.0, 1.0) var mantle_cover: float = 0.0
@export_range(2.0, 20.0, 0.5) var mantle_width: float = 6.0
@export_range(1.0, 10.0, 0.25) var mantle_spacing: float = 2.0
## Override the low-shrub slot (slot 3: low hedges, the mantle's brambles).
@export var low_shrub_assets: PackedStringArray = PackedStringArray()
## Deadwood debris: fallen trees and broken stumps instead of cut logs.
@export var woodland_deadwood: bool = false
@export_range(0.3, 2.0, 0.05) var tree_scale_min: float = 0.85
@export_range(0.3, 2.0, 0.05) var tree_scale_max: float = 1.2
@export_range(0.3, 2.0, 0.05) var conifer_scale_min: float = 0.8
@export_range(0.3, 2.0, 0.05) var conifer_scale_max: float = 1.25
## How far a canopy tree may sit from its grid cell's centre, as a share of
## the cell (GroveScatter). 0.7 keeps trees evenly apart; 1.0 lets them pair
## up and leave gaps, as real stands do. Placement, not acceptance: zones and
## the terrain tint are unaffected.
@export_range(0.0, 1.0, 0.05) var tree_jitter: float = 0.7

@export_group("Ferns")
## 0 = no ferns (the default). Independent of the other three tree/shrub/
## conifer covers -- ferns are forest-floor undergrowth, placed over the
## same grove field as the rest (see TreePlacer's class comment).
@export_range(0.0, 1.0) var fern_cover: float = 0.0
## Typical spacing between fern clumps, metres. Tighter than shrub_spacing --
## ferns read as a dense floor carpet under trees, not scattered accents.
@export_range(0.3, 10.0, 0.1) var fern_spacing: float = 1.5
## Frond colour, separate from tree_palette/conifer_palette: a fresh,
## brighter green than either canopy above it.
@export var fern_palette: PackedColorArray = PackedColorArray([
	Color("#1c2f12"), Color("#2c4a1c"), Color("#3f6b28"), Color("#5c8f39"), Color("#84b355"),
])

@export_group("Cushion plants")
## 0 = no cushion plants (the default). Independent of the other covers --
## alpine cushion plants (moss campion, saxifrage) hug rock and scree across
## a wide elevation band, so unlike conifer_cover this needs no altitude
## gating to place honestly (see docs/GEO_IMPORT.md's asset wishlist).
@export_range(0.0, 1.0) var cushion_cover: float = 0.0
## Typical spacing between cushion-plant clumps, metres. Tight -- real ones
## grow as dense speckled hummocks across open ground, not scattered accents.
@export_range(0.1, 5.0, 0.05) var cushion_spacing: float = 0.6
## Cool grey-green through to a pale bloom colour -- the atlas's brighter
## "in bloom" leaflets read as whichever end of this gradient the palette
## lookup lands on, so a warm/pale top stop is what makes them read as
## flecks of flower colour rather than just a lit highlight.
@export var cushion_palette: PackedColorArray = PackedColorArray([
	Color("#3a4a3f"), Color("#5c7060"), Color("#8aa085"), Color("#c9a8a0"), Color("#f0d8d0"),
])

@export_group("Debris")
## 0 = no rocks or deadwood (the default). Rendered by DebrisLayer, placed
## over the same grove field as trees and shrubs -- see DebrisPlacer's class
## comment for why deadwood clusters where the trees are.
@export_range(0.0, 1.0) var debris_cover: float = 0.0
## Typical spacing between debris instances, metres. Wider than tree_spacing
## -- rocks and fallen trees are meant to read as occasional accents, not a
## carpet.
@export_range(3.0, 60.0, 1.0) var debris_spacing: float = 18.0
## Share of rock among placed debris; the rest are logs/fallen trees.
@export_range(0.0, 1.0) var debris_rock_share: float = 0.6

@export_group("Terrain")
## Close-range ground detail under the grass (terrain.gdshader). 0 turns it off.
@export_range(0.0, 1.0) var terrain_detail_strength: float = 0.6
@export_range(0.1, 8.0) var terrain_detail_scale: float = 3.0
## Ground colour where the growth mask is bare: paths, clearings, yards.
@export var bare_colour: Color = Color("#6b6152")
@export var slope_colour: Color = Color("#6b5c47")
@export_range(0.0, 1.0) var slope_begin: float = 0.55
@export_range(0.0, 1.0) var slope_end: float = 0.8

@export_group("Mask")
## Where things grow, painted: red channel, 1 = grass, 0 = bare, stretched
## across `mask_bounds` in world XZ. Drives the grass placer, the tree placer
## (via the terrain provider) and the bare-ground colour in the terrain shader.
## Import it Lossless with detect_3d off -- VRAM compression would make the
## CPU-side copy the placers read unreadable.
@export var growth_mask: Texture2D = null
@export var mask_bounds: Rect2 = Rect2(-1000, -1000, 2000, 2000)

@export_group("Atmosphere")
## Daytime haze colour. Only the remainder after aerial perspective shows (see
## AtmosphereHaze.AERIAL_PERSPECTIVE): most of the haze takes the sky's colour.
## A soft blue, so far ridges read as distance, not dust.
@export var fog_colour: Color = Color("#b9c9d6")
## Distance haze at the edge of the drawn ground, 0..1: 0 is none, 1 hides it
## completely. Depth haze, ramping from the camera out to the quality level's
## horizon (AtmosphereHaze). Lower for clear mountain air, higher for dusty
## lowland. Weather and mist work on top of this.
@export_range(0.0, 1.0, 0.01) var haze_amount: float = 0.85
## Every foliage surface eases towards this with distance (see
## foliage_distance.gdshaderinc): the painterly half of the horizon handover.
@export var distance_tint: Color = Color("#aebfc9")
@export_range(0.0, 1.0) var distance_tint_strength: float = 0.35
@export_range(0.0, 2000.0, 1.0) var distance_tint_start: float = 80.0
@export_range(10.0, 5000.0, 1.0) var distance_tint_end: float = 700.0


## Pushes this profile into both foliage materials.
##
## Deliberately one function taking both materials rather than two functions:
## it is then structurally impossible to update grass and forget terrain, which
## is the failure mode that produces a visible grass edge on the horizon.
func apply_to_materials(grass_material: ShaderMaterial, terrain_material: ShaderMaterial, flower_material: ShaderMaterial = null) -> void:
	var grass_palette_tex := FoliageTextures.palette_texture(grass_palette, location_name + ":grass")
	for material in [grass_material, terrain_material, flower_material]:
		if material == null:
			continue
		_apply_shared(material)
		material.set_shader_parameter("foliage_palette", grass_palette_tex)

	# Flowers keep the shared grass palette on `foliage_palette` (their stems are
	# ordinary grass and must match their neighbours) and take the bloom colour
	# on a second sampler, selected per-vertex by the mesh's colour channel.
	# Overwriting foliage_palette here instead would turn the stems pink.
	if flower_material != null:
		flower_material.set_shader_parameter(
			"foliage_petal_palette",
			FoliageTextures.palette_texture(flower_palette, location_name + ":flower"),
		)
		# Blooms want per-instance colour, not per-patch: without this a whole
		# corner of the field comes out the same shade of pink.
		flower_material.set_shader_parameter("foliage_variation_weight", 0.85)

	# Sprite atlas and mode. Flowers never use the atlas -- their bloom is real
	# geometry -- so they are explicitly switched out of sprite mode rather than
	# left to inherit the uniform default.
	var sprite_mode := clump_style == ClumpStyle.SPRITE_CARDS
	grass_material.set_shader_parameter("grass_sprite_mode", sprite_mode)
	if sprite_mode:
		grass_material.set_shader_parameter("grass_sprite_atlas", FoliageTextures.sprite_atlas())
	if flower_material != null:
		flower_material.set_shader_parameter("grass_sprite_mode", false)

	grass_material.set_shader_parameter("grass_root_darkening", root_darkening)
	grass_material.set_shader_parameter("grass_translucency", translucency)
	if flower_material != null:
		flower_material.set_shader_parameter("grass_root_darkening", root_darkening)
		flower_material.set_shader_parameter("grass_translucency", translucency)

	# Terrain wind is the same field at a much larger scale. Derived from the
	# grass value rather than authored separately, so the two cannot drift.
	terrain_material.set_shader_parameter("foliage_wind_noise_scale", wind_noise_scale * terrain_wind_scale_multiplier)
	terrain_material.set_shader_parameter("terrain_slope_colour", slope_colour)
	terrain_material.set_shader_parameter("terrain_slope_begin", slope_begin)
	terrain_material.set_shader_parameter("terrain_slope_end", slope_end)
	terrain_material.set_shader_parameter("terrain_bare_colour", bare_colour)
	terrain_material.set_shader_parameter("terrain_detail_strength", terrain_detail_strength)
	terrain_material.set_shader_parameter("terrain_detail_scale", terrain_detail_scale)
	terrain_material.set_shader_parameter("terrain_growth_mask", growth_mask)
	terrain_material.set_shader_parameter("terrain_mask_bounds", Vector4(
		mask_bounds.position.x, mask_bounds.position.y, mask_bounds.size.x, mask_bounds.size.y,
	))


## Pushes this profile into the tree materials. Same shared colour and wind
## values as the grass (via _apply_shared), so a gust crosses meadow and grove
## as one field; only the palette differs. `needle_material`/`fern_material`/
## `cushion_material`, when given, take the SAME wind/sway as the broadleaf
## leaves but their own palette -- a needle mass wants a colder colour and
## far less light transmission than a thin broad leaf (translucency scaled
## down, not shared); a fern frond is thin and papery, so it keeps
## translucency close to a broadleaf's; a cushion plant's leaves are tiny
## and leathery, closer to a needle's than a fern's.
func apply_to_tree_materials(
	leaf_material: ShaderMaterial, bark_material: ShaderMaterial,
	needle_material: ShaderMaterial = null, fern_material: ShaderMaterial = null,
	cushion_material: ShaderMaterial = null,
) -> void:
	var shared := [leaf_material, bark_material]
	for extra in [needle_material, fern_material, cushion_material]:
		if extra != null:
			shared.append(extra)
	for material in shared:
		_apply_shared(material)
		material.set_shader_parameter("tree_sway_strength", tree_sway)
		material.set_shader_parameter("tree_flutter_strength", tree_flutter)
	leaf_material.set_shader_parameter("foliage_palette", FoliageTextures.palette_texture(tree_palette, location_name + ":tree"))
	# Trees want far more per-instance colour difference than grass: a grove of
	# identical-green crowns reads as one blob.
	leaf_material.set_shader_parameter("foliage_variation_weight", 0.45)
	leaf_material.set_shader_parameter("leaf_translucency", tree_translucency)
	bark_material.set_shader_parameter("bark_tint", bark_tint)
	if needle_material != null:
		needle_material.set_shader_parameter("foliage_palette", FoliageTextures.palette_texture(conifer_palette, location_name + ":conifer"))
		needle_material.set_shader_parameter("foliage_variation_weight", 0.4)
		needle_material.set_shader_parameter("leaf_translucency", tree_translucency * 0.4)
	if fern_material != null:
		fern_material.set_shader_parameter("foliage_palette", FoliageTextures.palette_texture(fern_palette, location_name + ":fern"))
		fern_material.set_shader_parameter("foliage_variation_weight", 0.5)
		fern_material.set_shader_parameter("leaf_translucency", tree_translucency)
	if cushion_material != null:
		cushion_material.set_shader_parameter("foliage_palette", FoliageTextures.palette_texture(cushion_palette, location_name + ":cushion"))
		cushion_material.set_shader_parameter("foliage_variation_weight", 0.55)
		cushion_material.set_shader_parameter("leaf_translucency", tree_translucency * 0.4)


## Pushes the distance-tint values into a debris material (rocks, logs,
## fallen trees) -- the only foliage_distance.gdshaderinc include debris uses.
## Unlike grass and trees it has no wind or palette to share, so this does not
## go through _apply_shared(): most of what that pushes is for a uniform
## debris.gdshader does not declare, and set_shader_parameter() on a uniform a
## shader does not have is a silent no-op, not an error, so it would look
## harmless while quietly doing nothing.
func apply_to_debris_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("foliage_distance_tint", distance_tint)
	material.set_shader_parameter("foliage_distance_tint_strength", distance_tint_strength)
	material.set_shader_parameter("foliage_distance_tint_start", distance_tint_start)
	material.set_shader_parameter("foliage_distance_tint_end", distance_tint_end)


## Pushes the one thing water shares with the rest of the location -- its
## wind (so the sea's ripples travel the same way the grass bends) and the
## distance tint (so the horizon handover applies to it too). Not through
## _apply_shared(): that pushes the grass colour/palette uniforms
## water.gdshader does not declare, the same reasoning
## apply_to_debris_material() documents for debris.
func apply_to_water_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("water_wind_direction", wind_direction)
	material.set_shader_parameter("water_wind_speed", wind_speed)
	material.set_shader_parameter("foliage_distance_tint", distance_tint)
	material.set_shader_parameter("foliage_distance_tint_strength", distance_tint_strength)
	material.set_shader_parameter("foliage_distance_tint_start", distance_tint_start)
	material.set_shader_parameter("foliage_distance_tint_end", distance_tint_end)


## Everything in foliage_common.gdshaderinc except the palette. Every foliage
## material goes through this one function, so a uniform added to the include
## has exactly one place to be set -- and grass, terrain and trees cannot drift.
func _apply_shared(material: ShaderMaterial) -> void:
	material.set_shader_parameter("foliage_colour_noise", FoliageTextures.noise_texture(world_seed, 0.01, 512, 4))
	material.set_shader_parameter("foliage_wind_noise", FoliageTextures.noise_texture(world_seed + 5501, 0.012, 512, 3))
	material.set_shader_parameter("foliage_colour_noise_scale", colour_noise_scale)
	material.set_shader_parameter("foliage_colour_octave_mix", colour_octave_mix)
	material.set_shader_parameter("foliage_palette_offset", palette_offset)
	material.set_shader_parameter("foliage_palette_contrast", palette_contrast)
	material.set_shader_parameter("foliage_wind_direction", wind_direction)
	material.set_shader_parameter("foliage_wind_speed", wind_speed)
	material.set_shader_parameter("foliage_wind_strength", wind_strength)
	material.set_shader_parameter("foliage_wind_noise_scale", wind_noise_scale)
	material.set_shader_parameter("foliage_wind_colour_shift", wind_colour_shift)
	material.set_shader_parameter("foliage_distance_tint", distance_tint)
	material.set_shader_parameter("foliage_distance_tint_strength", distance_tint_strength)
	material.set_shader_parameter("foliage_distance_tint_start", distance_tint_start)
	material.set_shader_parameter("foliage_distance_tint_end", distance_tint_end)
