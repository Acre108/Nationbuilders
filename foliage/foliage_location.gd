class_name FoliageLocation
extends Node3D

## Everything outdoor about one place, from one resource.
##
## Give it a FoliageProfile (a .tres in content/locations/) and it builds the
## ground mesh, the GrassLayer, the TreeLayer and the DebrisLayer, wires the
## growth mask into the terrain, and applies the location's atmosphere and the
## quality preset to the scene's sun and environment. Swapping `profile`
## restyles the whole place.
##
## INDOOR SKIP: a profile with `enabled = false` builds nothing at all -- no
## nodes, no materials, no textures, no terrain sampling. An indoor location
## pays exactly zero for the foliage system, and nothing else in the scene has
## to know or check. `--indoor` in the test scene proves it.
##
## QUALITY: set_quality() is the one entry point a graphics menu calls. It
## rebuilds grass and trees at the new preset and applies the preset's shadow
## settings to the sun, because tree shadow quality is the first thing to cut
## and it lives on the light, not on the trees.
##
## STREAMING: with `streaming` on (the default) everything follows `focus`
## (normally the camera): grass out to quality.streaming_radius, ground and
## trees out to quality.view_distance, built on WorkerThreadPool and committed
## a few chunks a frame. With it off, a fixed square of `ground_extent` round
## the origin -- deterministic, camera-independent, what the self-tests use.
## build() (called by set_profile()) blocks on each old layer's in-flight
## workers before freeing it -- see _clear() -- so it is not itself part of
## the "settings changes do not block" guarantee set_quality() makes.

signal built(summary: Dictionary)

@export var profile: FoliageProfile
@export var quality_level: FoliageQuality.Level = FoliageQuality.Level.HIGH
## The scene's sun, for shadow settings. Optional.
@export var sun: DirectionalLight3D
## The scene's environment, for fog. Optional.
@export var world_environment: WorldEnvironment
## Follow `focus` instead of building a fixed square.
@export var streaming: bool = true
## First entry builds only the visible and physics chunks under the spawn;
## foliage, the rest of the ground, and the horizon continue via streaming.
@export var staged_streaming_startup: bool = false
## What streaming follows. Usually the camera.
@export var focus: Node3D
## Streaming off: half-width of the square of ground to build, metres. Grass
## covers half of it and trees most of it, so the edge of the built area reads
## as terrain rather than as grass cut off by a knife.
@export_range(16.0, 1024.0, 1.0) var ground_extent: float = 144.0
@export_range(0.0, 1.0) var grass_extent_fraction: float = 0.5
## Physics ground round the focus (TerrainCollision). Its radius is fixed,
## not part of the quality preset: what can be walked on must not depend on
## graphics settings.
@export var collision_enabled: bool = true
@export_range(16.0, 1024.0, 1.0) var collision_radius: float = 128.0
## Season for managed field crops (CropCatalogue): 1 = 1 January. Southern
## hemisphere sites shift it themselves. Change at runtime with
## set_day_of_year().
@export_range(1.0, 365.0, 1.0) var day_of_year: float = 196.0
## Calendar year for the tide (SeaState); 0 = the current year.
@export var year: int = 0
## Local mean solar time (hours) the tide follows; the atmosphere moves it
## each frame through set_clock_hour(). Set before build().
var clock_hour: float = 13.0

## Assign before adding to the tree (or before build()). Defaults to the
## profile's TerrainProfile, seeded from its world_seed.
var terrain: TerrainProvider
## Shared for the full location lifetime, including quality/profile rebuilds.
var placement_events := FoliagePlacementEvents.new()
var exclusions := FoliageExclusions.new()
var _ground_footprints: Dictionary = {}

func _init() -> void:
	placement_events.placed.connect(func(id: StringName, footprints: Array[GrassCarver]) -> void: _ground_footprints[id] = footprints.duplicate())
	placement_events.removed.connect(func(id: StringName) -> void: _ground_footprints.erase(id))

var quality: FoliageQuality
var grass: GrassLayer
var trees: TreeLayer
var debris: DebrisLayer
var shoreline: ShorelineLayer
var ground: TerrainLayer
## Coarse ground from view_distance out to quality.horizon_distance, so
## distant hills stand on the skyline. Streaming only; null otherwise.
var horizon: TerrainLayer
## Null when collision_enabled is off or the location is indoor.
var collision: TerrainCollision
## The sea (WaterLayer). Null when the location has no WaterProfile, or its
## sea is switched off.
var water: WaterLayer
## The sea's live level (docs/SEA_PLAN.md, SEA1): the sea plane, the water
## shader's depth and the terrain's shore band follow it; nothing baked does.
## Null without a sea.
var sea_state: SeaState
## What kind of ground each point is (meadow, woodland, rock...), for layers
## that vary by habitat. Rebuilt with the profile in build(); null indoors.
var zones: EnvironmentZones
var _river_credits: CanvasLayer

## True when `terrain` is the default provider this node made for the current
## profile, so a profile swap can replace it. A provider the caller assigned
## is never replaced.
var _owns_terrain := false
## ZoneMap for the current profile; baked once per build(), reused across
## quality changes.
var _zone_map: ImageTexture
## The near-range ZoneMap over the playable world, for the woodland floor.
var _zone_near_map: ImageTexture


func _ready() -> void:
	build()


func _process(_delta: float) -> void:
	if not streaming or focus == null or grass == null:
		return
	var point := focus.global_position
	# Ground first: grass and trees stand on it, and a missing ground chunk
	# under them shows sky.
	ground.update_streaming(point)
	if horizon != null:
		horizon.update_streaming(point)
	if collision != null:
		collision.update_streaming(point)
	grass.update_streaming(point)
	if trees != null:
		trees.update_streaming(point)
	if debris != null:
		debris.update_streaming(point)
	if shoreline != null:
		shoreline.update_streaming(point)
	if water != null:
		water.follow(point)


## Blocks until every chunk wanted at the current focus is built. For a first
## frame that must be complete (screenshots, benchmarks) -- normal play just
## lets streaming catch up.
func flush_streaming() -> void:
	if grass == null:
		return
	var point := focus.global_position if focus != null else Vector3.ZERO
	for layer in [ground, horizon, collision, grass, trees, debris, shoreline]:
		if layer != null:
			layer.focus_point = point
			layer.flush()


## The minimum safe arrival: rendered terrain and physics beneath the focus.
## All other chunks stay queued for the ordinary per-frame streamer.
func prepare_spawn() -> bool:
	if focus == null or ground == null or collision == null:
		return false
	var point := focus.global_position
	# Want the chunks around the point first: flush_at() only builds chunks
	# already in the streaming set, and the focus may have jumped (a Studio
	# walk kilometres from the map view).
	ground.update_streaming(point)
	collision.update_streaming(point)
	ground.flush_at(point)
	collision.flush_at(point)
	return collision.has_collision_at(point)


## Chunks wanted but not yet built, across all layers.
func pending_chunks() -> int:
	var n := 0
	for layer in [ground, horizon, collision, grass, trees, debris, shoreline]:
		if layer != null:
			n += layer.pending_chunks()
	return n


## (Re)builds everything from `profile`. Anything previously built is freed.
func build() -> void:
	_clear()
	quality = FoliageQuality.create(quality_level)
	if profile == null or not profile.enabled:
		# Indoor, or no foliage here: build nothing and touch nothing. The sun
		# and environment belong to the scene; an indoor room's lighting is
		# none of this system's business.
		built.emit({"indoor": true})
		return

	if terrain == null:
		var shape := profile.terrain if profile.terrain != null else TerrainProfile.new()
		terrain = shape.make_provider(profile.world_seed, profile.water)
		_owns_terrain = true
	elif terrain is HeightmapTerrainProvider and profile.terrain != null:
		# A real-world (heightmap) location has no TerrainProfile of its own
		# to build ground FROM (`terrain` above is already the caller's
		# HeightmapTerrainProvider, loaded from real elevation data) -- but
		# it can still point FoliageProfile.terrain at one purely for its
		# Altitude group, so a real peak gets the same rock/snow bands a
		# procedural mountain would. See HeightmapTerrainProvider.altitude
		# and docs/GEO_IMPORT.md, "Asset wishlist".
		(terrain as HeightmapTerrainProvider).altitude = profile.terrain
	var mask_image: Image = profile.growth_mask.get_image() if profile.growth_mask != null else null
	terrain.set_painted_mask(mask_image, profile.mask_bounds)
	if terrain is HeightmapTerrainProvider:
		terrain.imported_water_enabled = profile.water == null or profile.water.river_enabled
		terrain.sea_water = profile.water if profile.water != null and profile.water.sea_enabled else null
		# Estuaries (SEA8): rivers the tide comes up, before any chunk builds.
		terrain.set_estuary_reach(profile.water.estuary_reach if terrain.sea_water != null else 0.0)
	sea_state = null
	if profile.water != null and profile.water.sea_enabled:
		var sea: ImportedSea = terrain.imported_sea if terrain is HeightmapTerrainProvider else null
		sea_state = SeaState.new(profile.water, sea.tide if sea != null else null)
		sea_state.set_date(resolved_year(year), int(day_of_year))
		sea_state.set_clock(clock_hour)
		# Storm surge's wind set-up: the location's wind against the way surf
		# travels at its centre (onshore = +1).
		if sea != null and sea.has_coast() and profile.wind_direction.length_squared() > 0.0:
			sea_state.onshore = clampf(profile.wind_direction.normalized().dot(sea.coast_direction(0.0, 0.0)), -1.0, 1.0)
		sea_state.update(true)
	zones = EnvironmentZones.for_profile(profile, terrain)

	var start := focus.global_position if focus != null and focus.is_inside_tree() else Vector3.ZERO

	grass = GrassLayer.new()
	grass.name = "GrassLayer"
	grass.placement_events = placement_events
	grass.profile = profile
	grass.terrain = terrain
	grass.quality = quality
	grass.streaming = streaming
	grass.defer_first_streaming_build = staged_streaming_startup
	grass.focus_point = start
	grass.chunk_radius = maxi(1, int(ground_extent * grass_extent_fraction / grass.chunk_size))
	add_child(grass)
	for id in _ground_footprints: grass.carve(id,_ground_footprints[id])

	# Paintable ground (Location Studio S4) can grow painted woods anywhere.
	if profile.tree_cover > 0.0 or profile.shrub_cover > 0.0 or profile.conifer_cover > 0.0 or profile.fir_cover > 0.0 or profile.fern_cover > 0.0 or profile.cushion_cover > 0.0 or terrain.paintable():
		trees = TreeLayer.new()
		trees.name = "TreeLayer"
		trees.exclusions = exclusions
		trees.profile = profile
		trees.terrain = terrain
		trees.quality = quality
		trees.streaming = streaming
		trees.defer_first_streaming_build = staged_streaming_startup
		trees.focus_point = start
		trees.chunk_radius = maxi(0, int(floor(ground_extent / trees.chunk_size)))
		add_child(trees)

	if profile.debris_cover > 0.0 or profile.woodland_cover() > 0.0 or profile.floor_cover_wanted(terrain.has_observed_zones()) or terrain.paintable():
		debris = DebrisLayer.new()
		debris.name = "DebrisLayer"
		debris.exclusions = exclusions
		debris.profile = profile
		debris.terrain = terrain
		debris.quality = quality
		debris.streaming = streaming
		debris.defer_first_streaming_build = staged_streaming_startup
		debris.focus_point = start
		debris.chunk_radius = maxi(0, int(floor(ground_extent / debris.chunk_size)))
		add_child(debris)

	if profile.use_nature_pack and ShorelinePlacer.wanted(profile, terrain):
		shoreline = ShorelineLayer.new()
		shoreline.name = "ShorelineFoliage"
		shoreline.exclusions = exclusions
		shoreline.profile = profile
		shoreline.terrain = terrain
		shoreline.quality = quality
		shoreline.streaming = streaming
		shoreline.defer_first_streaming_build = staged_streaming_startup
		shoreline.focus_point = start
		shoreline.chunk_radius = maxi(0, int(floor(ground_extent / shoreline.chunk_size)))
		add_child(shoreline)

	# The ground takes the terrain material FROM the grass layer -- that shared
	# material is the horizon handover (see docs/FOLIAGE.md).
	ground = TerrainLayer.new()
	ground.name = "Ground"
	ground.terrain = terrain
	ground.material = grass.get_terrain_material()
	ground.streaming = streaming
	ground.defer_first_streaming_build = staged_streaming_startup
	ground.focus_point = start
	ground.extent = ground_extent
	_apply_ground_ranges()
	_zone_map = null
	_zone_near_map = null
	_apply_terrain_shading()
	add_child(ground)
	# Water first: the ground meshes the imported water field with it.
	_build_water()
	ground.rebuild()
	_build_horizon()
	_build_collision()
	_apply_atmosphere()
	_apply_shadows()
	built.emit(summary())


## Painted zone overrides changed inside `area` (Location Studio S4). The
## caller has already assigned the new ZoneOverrides to the terrain
## (copy-on-write). Re-places every placing layer's chunks there and updates
## the terrain shader's paint texture. Returns chunks marked per layer.
func zones_changed(area: Rect2) -> Dictionary:
	var marked := {}
	for entry in [["grass", grass], ["trees", trees], ["debris", debris]]:
		if entry[1] != null: marked[entry[0]] = entry[1].rebuild_zone_area(area)
	if ground != null: _apply_zone_paint(ground.material)
	return marked


## Sculpted heights changed inside `area` (Location Studio S5); the caller
## has already swapped the terrain's HeightDeltas. Re-meshes ground, horizon
## and collision there and re-places every vegetation layer. When the water
## was refitted (`water_refit`), lakes, shores and the zone field changed
## beyond the area, so the whole location rebuilds instead.
func terrain_changed(area: Rect2, water_refit: bool = false) -> void:
	if water_refit:
		build()
		return
	for layer in [ground, horizon, collision]:
		if layer != null: layer.rebuild_area(area)
	zones_changed(area)
	if shoreline != null: shoreline.rebuild_zone_area(area)


## The terrain shader's view of painted zones: an RG8 texture of the painted
## tiles' bounding box (ZoneOverrides.shader_image()) and each zone's ground
## tint.
func _apply_zone_paint(material: ShaderMaterial) -> void:
	var overrides: ZoneOverrides = terrain.zone_overrides if terrain is HeightmapTerrainProvider else null
	var painted := overrides != null and not overrides.is_empty()
	material.set_shader_parameter("terrain_has_zone_paint", painted)
	if not painted: return
	var baked := overrides.shader_image()
	var rect: Rect2 = baked.rect
	material.set_shader_parameter("terrain_zone_paint", ImageTexture.create_from_image(baked.image))
	material.set_shader_parameter("terrain_zone_paint_bounds", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	var tints := PackedVector4Array()
	for recipe in profile.zone_recipes():
		var c := recipe.ground_tint.srgb_to_linear()
		tints.append(Vector4(c.r, c.g, c.b, recipe.ground_tint_strength))
	material.set_shader_parameter("terrain_zone_tints", tints)


## The graphics-menu entry point.
func set_quality(level: FoliageQuality.Level) -> void:
	quality_level = level
	quality = FoliageQuality.create(level)
	if grass == null:
		return
	grass.quality = quality
	grass.rebuild()
	# grass.rebuild() just built a NEW terrain material (_build_materials()
	# always does); ground was still pointing at the old one. Without this the
	# two silently stop sharing a material -- the whole mechanism the horizon
	# handover depends on (see docs/FOLIAGE.md) -- from here until the next
	# full build().
	ground.material = grass.get_terrain_material()
	if trees != null:
		trees.quality = quality
		trees.rebuild()
	if debris != null:
		debris.quality = quality
		debris.rebuild()
	if shoreline != null:
		shoreline.quality = quality
		shoreline.rebuild()
	_apply_ground_ranges()
	_apply_terrain_shading()
	_build_water()
	ground.rebuild()
	_build_horizon()
	_apply_atmosphere()
	_apply_shadows()


func set_profile(new_profile: FoliageProfile) -> void:
	profile = new_profile
	# A new location may bring a different seed and mask; let the default
	# provider be rebuilt from it. A caller-supplied provider is kept.
	if _owns_terrain:
		terrain = null
	build()


func is_indoor() -> bool:
	return profile == null or not profile.enabled


func summary() -> Dictionary:
	if is_indoor():
		return {"indoor": true}
	return {
		"indoor": false,
		"location": profile.location_name,
		"grass_chunks": grass.debug_counts()["chunks"] if grass != null else 0,
		"trees": trees.tree_count if trees != null else 0,
		"debris": debris.count if debris != null else 0,
		"shore_reeds": shoreline.reed_count if shoreline != null else 0,
		"shore_rocks": shoreline.rock_count if shoreline != null else 0,
		"ground_chunks": ground.chunk_count() if ground != null else 0,
		"horizon_chunks": horizon.chunk_count() if horizon != null else 0,
		"collision_chunks": collision.chunk_count() if collision != null else 0,
		"sea": water != null and water.profile.sea_enabled,
		"lakes": water.lake_basins.size() + water.imported_lake_count() if water != null else 0,
		"rivers": water.river_paths.size() if water != null else 0,
		"streaming": streaming,
		"masked": terrain.has_painted_mask(),
	}


## Ground detail rings follow the quality preset: full detail wherever grass
## can be standing on it, then coarser.
func _apply_ground_ranges() -> void:
	ground.view_distance = quality.view_distance
	ground.near_ring = maxf(quality.streaming_radius, quality.lod_far_end) + 32.0
	ground.middle_ring = maxf(ground.near_ring * 2.5, 300.0)


## The horizon ring (see TerrainLayer.configure_as_horizon), sharing the
## ground's material so the handover to it is the same shader. Bounded to the
## world plus a margin of scenery beyond its edge. On a quality change the
## existing layer is reconfigured and rebuilt in place, so, like the others,
## it swaps chunks over without blocking.
func _build_horizon() -> void:
	if not streaming or quality.horizon_distance <= 0.0:
		if horizon != null:
			horizon.stop_streaming()
			horizon.queue_free()
			horizon = null
		return
	var shape := profile.terrain if profile.terrain != null else TerrainProfile.new()
	if horizon == null:
		horizon = TerrainLayer.new()
		horizon.name = "Horizon"
		horizon.terrain = terrain
		horizon.focus_point = ground.focus_point
		horizon.defer_first_streaming_build = staged_streaming_startup
		add_child(horizon)
	horizon.material = ground.material
	horizon.configure_as_horizon(ground, quality.horizon_distance, shape.bounds().grow(HORIZON_MARGIN))
	horizon.rebuild()


## The sea (WaterLayer), reusing the horizon's reach so it never visibly ends
## before the sky does. Off (no WaterProfile, or its sea switched off) frees
## whatever was built and touches nothing else, the same "off costs nothing"
## rule the rest of this class follows.
func _build_water() -> void:
	var active_profile := profile.water
	var imported: ImportedRivers = terrain.imported_rivers if terrain is HeightmapTerrainProvider else null
	if imported != null and (not imported.paths.is_empty() or imported.lakes.size() > 0) and active_profile == null:
		active_profile = WaterProfile.new()
		active_profile.river_enabled = true
	var wants_water := active_profile != null and (
		active_profile.sea_enabled or active_profile.lakes_enabled or active_profile.river_enabled)
	_update_river_credits(imported if active_profile != null and active_profile.river_enabled else null)
	ground.water_material = null
	ground.water_reach = 0.0
	if not wants_water:
		if water != null:
			water.queue_free()
			water = null
		return
	if water == null:
		water = WaterLayer.new()
		water.name = "Water"
		add_child(water)
	water.profile = active_profile
	water.reach = maxf(quality.horizon_distance, 2000.0) + HORIZON_MARGIN
	# Lakes and rivers are LandformTerrainProvider's own bake/trace; a
	# caller-supplied terrain that is not one just has neither to show.
	water.lake_basins = []
	water.river_paths = []
	if terrain is LandformTerrainProvider:
		water.lake_basins = terrain.lake_basins()
		water.river_paths = terrain.river_paths()
	water.river_widths = PackedFloat32Array()
	water.imported_rivers = null
	if imported != null and active_profile.river_enabled:
		water.river_paths = imported.paths
		water.river_widths = imported.widths
		# Fitted imports carry their own level water surface and flow; the
		# draped ribbon below is only the unfitted fallback.
		if imported.is_fitted():
			water.imported_rivers = imported
	water.field_reach = 0.0
	if water.imported_rivers != null:
		# The ground meshes rivers and lakes as one field, out to where its
		# streaming is sure to have built every chunk; lakes' own meshes
		# carry on beyond that.
		water.field_reach = ground.view_distance - ground.chunk_size * 1.5 if streaming else ground.extent
	water.terrain = terrain
	var coast_sea: ImportedSea = terrain.imported_sea if terrain is HeightmapTerrainProvider else null
	water.surf_patch = active_profile.sea_enabled and coast_sea != null and coast_sea.has_coast()
	water.rebuild()
	if water.field_reach > 0.0:
		ground.water_material = water.material
		ground.water_reach = water.field_reach
	active_profile.apply_to_material(water.material, profile.world_seed)
	profile.apply_to_water_material(water.material)
	_apply_water_depth_map()
	water.focus_point = ground.focus_point
	if sea_state != null:
		sea_state.apply(water, null)
	else:
		water.follow(ground.focus_point)


## Shifts the sea's live level by `metres` from sea_level: uniforms and the
## sea plane's height only, no rebuilds. The tide clock (SEA3) will drive
## this; for now it is for tests and debugging.
func set_sea_offset(metres: float) -> void:
	if sea_state == null:
		return
	sea_state.offset = metres
	if sea_state.update():
		sea_state.apply(water, ground.material if ground != null else null)


func _update_river_credits(imported: ImportedRivers) -> void:
	if _river_credits != null:
		_river_credits.free()
		_river_credits = null
	if imported == null or imported.paths.is_empty():
		return
	# Independent of the optional HUD, including screenshot/test harnesses.
	_river_credits = CanvasLayer.new()
	_river_credits.name = "RiverAttribution"
	_river_credits.layer = 90
	add_child(_river_credits)
	var label := Label.new()
	label.text = "River data: " + imported.attribution + " · ODbL · openstreetmap.org/copyright"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_river_credits.add_child(label)
	label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	label.offset_left = 16
	label.offset_top = -28
	label.offset_right = 760
	label.offset_bottom = -8


## Terrain-aware water (WaterDepthMap): the same sea/lake depth the growth
## mask already reads, baked into a texture so the water shader can damp its
## wave swell in shallow water instead of applying it blind -- see
## docs/WATER.md, *Terrain-aware water*. Set directly on the material rather
## than through WaterProfile.apply_to_material(), the same way ZoneMap is
## set directly on the ground material: this is data derived from the
## terrain provider, not an authored per-location value.
func _apply_water_depth_map() -> void:
	# A real coastline: the sea draws only within its reach (polders behind
	# the shore stay dry), and the depth over its bed at the live level fades
	# the swell.
	var sea: ImportedSea = terrain.imported_sea if terrain is HeightmapTerrainProvider else null
	var masked := sea != null and water.profile.sea_enabled
	water.material.set_shader_parameter("water_sea_masked", masked)
	water.material.set_shader_parameter("water_sea_reach", sea.reach_texture if masked else null)
	water.material.set_shader_parameter("water_sea_spill_on", masked and sea.spill_texture != null)
	water.material.set_shader_parameter("water_sea_spill", sea.spill_texture if masked else null)
	var near := masked and sea.has_near()
	water.material.set_shader_parameter("water_sea_near", near)
	water.material.set_shader_parameter("water_sea_near_reach", sea.near_reach_texture if near else null)
	water.material.set_shader_parameter("water_sea_near_spill_on", near and sea.near_spill_texture != null)
	water.material.set_shader_parameter("water_sea_near_spill", sea.near_spill_texture if near else null)
	if near:
		water.material.set_shader_parameter("water_sea_near_bounds", sea.near_bounds())
		water.material.set_shader_parameter("water_sea_near_fade", ImportedSea.NEAR_FADE)
	water.material.set_shader_parameter("water_sea_level_now", sea_state.level_now if sea_state != null else 0.0)
	water.profile.apply_surf(water.material, sea if masked else null)
	if masked:
		water.material.set_shader_parameter("water_sea_bounds", sea.bounds())
		water.material.set_shader_parameter("water_depth_map", sea.bed_texture())
		water.material.set_shader_parameter("water_has_depth_map", true)
		water.material.set_shader_parameter("water_depth_bounds", sea.bounds())
		return
	# Empty whenever neither sea nor lakes are on (rivers do not feed this
	# map -- see docs/WATER.md, *Terrain-aware water* -- so a rivers-only
	# location has nothing to bake here). WaterDepthMap.build() would try to
	# create a texture from a zero-length array otherwise.
	if not terrain is LandformTerrainProvider or (terrain as LandformTerrainProvider).water_depth_grid().is_empty():
		water.material.set_shader_parameter("water_depth_map", null)
		water.material.set_shader_parameter("water_has_depth_map", false)
		return
	var provider := terrain as LandformTerrainProvider
	var bounds := provider.profile.bounds() if provider.profile != null else TerrainProfile.new().bounds()
	water.material.set_shader_parameter("water_depth_map", WaterDepthMap.build(provider))
	water.material.set_shader_parameter("water_has_depth_map", true)
	water.material.set_shader_parameter("water_depth_bounds", Vector4(
		bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))


## Narrow imported streams painted into the ground beyond the near ring,
## where it is too coarse to mesh their water (ImportedRivers.stream_field()).
func _apply_stream_paint(material: ShaderMaterial) -> void:
	var field := {}
	if terrain is HeightmapTerrainProvider and terrain.has_water_marks():
		field = (terrain as HeightmapTerrainProvider).imported_rivers.stream_field()
	material.set_shader_parameter("terrain_streams", not field.is_empty())
	if field.is_empty():
		material.set_shader_parameter("terrain_stream_field", null)
		return
	var bounds: Rect2 = field.bounds
	material.set_shader_parameter("terrain_stream_field", ImageTexture.create_from_image(field.image))
	material.set_shader_parameter("terrain_stream_bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	material.set_shader_parameter("terrain_stream_start", ground.near_ring)


## Move the crop season: field surfaces here; the site's crop plants follow
## through LocationSiteLayer.set_day_of_year().
## `y`, or the current year for 0.
static func resolved_year(y: int) -> int:
	return y if y > 0 else int(Time.get_date_dict_from_system().year)


## The atmosphere's clock moved (hours, wrapping at 24): the tide follows.
## Cheap when nothing moves; pushes only when the level changes by a
## centimetre (SeaState.PUSH_STEP).
func set_clock_hour(hour: float) -> void:
	clock_hour = hour
	if sea_state != null and sea_state.has_tide() and sea_state.set_clock(hour) and sea_state.update():
		sea_state.apply(water, ground.material if ground != null else null)


## The weather's storm (AtmosphereModel.Frame.storm, 0..1), every frame:
## the storm surge follows it (SeaState.advance_surge(); SEA8).
func set_sea_storm(storm: float, delta: float) -> void:
	if sea_state != null and sea_state.advance_surge(storm, delta) and sea_state.update():
		sea_state.apply(water, ground.material if ground != null else null)


## The tide readout for the commands panel; empty without a tide.
func tide_status_line() -> String:
	return sea_state.status_line() if sea_state != null else ""


func set_day_of_year(day: float) -> void:
	day_of_year = day
	if sea_state != null and sea_state.has_tide():
		sea_state.set_date(resolved_year(year), int(day))
		if sea_state.update():
			sea_state.apply(water, ground.material if ground != null else null)
	if ground != null and ground.material != null:
		_apply_crop_season(ground.material, terrain.imported_site if terrain is HeightmapTerrainProvider else null)


func _apply_crop_season(material: ShaderMaterial, site: ImportedSite) -> void:
	var has_fields := site != null and site.has_fields()
	material.set_shader_parameter("terrain_has_fields", has_fields)
	material.set_shader_parameter("terrain_field_soil", CropCatalogue.soil())
	if not has_fields:
		return
	var arrays := CropCatalogue.shader_arrays(site.crop_day(day_of_year))
	material.set_shader_parameter("terrain_fields_mask", site.fields_texture)
	material.set_shader_parameter("terrain_crop_field", arrays.fields)
	material.set_shader_parameter("terrain_crop_rows", arrays.rows)


## TerrainProfile's altitude bands, and the far-woodland tint (ZoneMap), into
## the ground material. Called whenever that material is (re)built, since
## FoliageProfile.apply_to_materials() knows nothing of either.
func _apply_terrain_shading() -> void:
	var material := ground.material
	_apply_zone_paint(material)
	var site: ImportedSite = terrain.imported_site if terrain is HeightmapTerrainProvider else null
	material.set_shader_parameter("terrain_has_site_mask", site != null)
	if site != null:
		material.set_shader_parameter("terrain_site_mask", site.mask)
	var habitats := site != null and site.has_habitats()
	material.set_shader_parameter("terrain_has_habitats", habitats)
	if habitats:
		var recipes := profile.zone_recipes()
		material.set_shader_parameter("terrain_habitat_mask", site.habitat_texture)
		for pair in [["terrain_dune_ground", EnvironmentZones.Zone.DUNE], ["terrain_heath_ground", EnvironmentZones.Zone.HEATH]]:
			var recipe: ZoneRecipe = recipes[pair[1]]
			# sRGB authored, mixed in linear (as the woodland floors).
			var c := recipe.ground_tint.srgb_to_linear()
			material.set_shader_parameter(pair[0], Vector4(c.r, c.g, c.b, recipe.ground_tint_strength))
	material.set_shader_parameter("terrain_site_fade", site.fade_distance() if site != null else 0.0)
	material.set_shader_parameter("terrain_site_half", site.bounds().size.x * 0.5 if site != null else 1.0e9)
	_apply_crop_season(material, site)
	var shape := profile.terrain if profile.terrain != null else TerrainProfile.new()
	shape.apply_to_terrain_material(material)
	if sea_state != null:
		sea_state.apply(null, material)
	elif profile.water != null:
		profile.water.apply_to_terrain_material(material)
	# A real coastline limits the shore band to the sea's reach.
	var sea: ImportedSea = terrain.imported_sea if terrain is HeightmapTerrainProvider else null
	material.set_shader_parameter("terrain_sea_masked", sea != null)
	material.set_shader_parameter("terrain_sea_reach", sea.reach_texture if sea != null else null)
	material.set_shader_parameter("terrain_sea_spill_on", sea != null and sea.spill_texture != null)
	material.set_shader_parameter("terrain_sea_spill", sea.spill_texture if sea != null else null)
	if sea != null:
		material.set_shader_parameter("terrain_sea_bounds", sea.bounds())
	var sea_near := sea != null and sea.has_near()
	material.set_shader_parameter("terrain_sea_near", sea_near)
	material.set_shader_parameter("terrain_sea_near_reach", sea.near_reach_texture if sea_near else null)
	material.set_shader_parameter("terrain_sea_near_spill_on", sea_near and sea.near_spill_texture != null)
	material.set_shader_parameter("terrain_sea_near_spill", sea.near_spill_texture if sea_near else null)
	if sea_near:
		material.set_shader_parameter("terrain_sea_near_bounds", sea.near_bounds())
		material.set_shader_parameter("terrain_sea_near_fade", ImportedSea.NEAR_FADE)
	# Swash on the beach, from the sea's surf.
	if profile.water != null:
		profile.water.apply_surf(material, sea)
	else:
		material.set_shader_parameter("surf_enabled", false)
	# Imported river channels carve the ground and mark bed/bank in its vertex
	# colour; only then may the shader read that colour.
	material.set_shader_parameter("terrain_water_marks", terrain.has_water_marks())
	_apply_stream_paint(material)
	# maxf, not tree_cover alone: a conifer-only location (no broadleaf trees
	# at all, e.g. a real-world alpine/forest import) still wants its distant
	# woodland to read as woodland on the horizon. fir_cover folds into the
	# conifer side of this, not a third term of its own: fir shares
	# conifer_palette and the same needle read from a distance, and a
	# fir-only location (conifer_cover = 0) needs exactly the same fallback
	# conifer-only locations already needed.
	var conifer_side_cover := maxf(profile.conifer_cover, profile.fir_cover)
	var recipes := profile.zone_recipes()
	var conifer_floor := recipes[EnvironmentZones.Zone.WOODLAND_CONIFER]
	var broadleaf_floor := recipes[EnvironmentZones.Zone.WOODLAND_BROADLEAF]
	var floors := conifer_floor.ground_tint_strength > 0.0 or broadleaf_floor.ground_tint_strength > 0.0
	# Fixed (non-streaming) scenes have no horizon ring, so only the floor
	# tint can apply there.
	if maxf(profile.tree_cover, conifer_side_cover) <= 0.0 or not (streaming or floors):
		material.set_shader_parameter("terrain_broadleaf_cover", 0.0)
		material.set_shader_parameter("terrain_conifer_cover", 0.0)
		material.set_shader_parameter("terrain_fir_cover", 0.0)
		return
	var bounds := shape.bounds().grow(HORIZON_MARGIN)
	if _zone_map == null:
		_zone_map = ZoneMap.build(profile.world_seed, bounds)
	material.set_shader_parameter("terrain_zone_map", _zone_map)
	material.set_shader_parameter("terrain_zone_bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	material.set_shader_parameter("terrain_zone_near", floors)
	if floors:
		var near := shape.bounds()
		if _zone_near_map == null:
			_zone_near_map = ZoneMap.build(profile.world_seed, near, ZoneMap.NEAR_SIZE)
		material.set_shader_parameter("terrain_zone_near_map", _zone_near_map)
		material.set_shader_parameter("terrain_zone_near_bounds", Vector4(near.position.x, near.position.y, near.size.x, near.size.y))
	# Authored in sRGB like every other colour; the shader mixes in linear
	# (its source_color uniforms convert on their own, a vec4 does not).
	var c := conifer_floor.ground_tint.srgb_to_linear()
	var b := broadleaf_floor.ground_tint.srgb_to_linear()
	material.set_shader_parameter("terrain_conifer_floor", Vector4(c.r, c.g, c.b, conifer_floor.ground_tint_strength))
	material.set_shader_parameter("terrain_broadleaf_floor", Vector4(b.r, b.g, b.b, broadleaf_floor.ground_tint_strength))
	# Same covers EnvironmentZones.for_profile() reads.
	material.set_shader_parameter("terrain_broadleaf_cover", profile.tree_cover)
	material.set_shader_parameter("terrain_conifer_cover", profile.conifer_cover)
	material.set_shader_parameter("terrain_fir_cover", profile.fir_cover)
	material.set_shader_parameter("terrain_family_stems", EnvironmentZones.family_stems(profile))
	# Observed zones: woodland follows the mapped forest (EnvironmentZones.observed).
	var observed := terrain.has_observed_zones()
	material.set_shader_parameter("terrain_observed", observed)
	if observed:
		var observed_site: ImportedSite = (terrain as HeightmapTerrainProvider).imported_site
		var area := observed_site.bounds()
		var top := maxf(profile.tree_cover, conifer_side_cover)
		material.set_shader_parameter("terrain_observed_map", observed_site.zone_texture)
		material.set_shader_parameter("terrain_observed_bounds", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))
		material.set_shader_parameter("terrain_relative_covers", Vector3(profile.tree_cover, profile.conifer_cover, profile.fir_cover) / maxf(top, 0.000001))
	var tint_palette := profile.tree_palette if profile.tree_cover >= conifer_side_cover else profile.conifer_palette
	if tint_palette.size() > 1:
		material.set_shader_parameter("terrain_woodland_colour", tint_palette[1])
	# Real trees stand out to view_distance; the tint takes over as they end.
	# Without a horizon ring (fixed scenes) the far tint never applies.
	var far_start := quality.view_distance * 0.75 if streaming else 1.0e9
	material.set_shader_parameter("terrain_woodland_start", far_start)
	material.set_shader_parameter("terrain_woodland_end", quality.view_distance if streaming else 2.0e9)


## Physics ground (TerrainCollision). Built once per build(); a quality
## change leaves it alone, since nothing about it depends on quality.
func _build_collision() -> void:
	if not collision_enabled:
		return
	collision = TerrainCollision.new()
	collision.name = "Collision"
	collision.terrain = terrain
	collision.streaming = streaming
	collision.defer_first_streaming_build = staged_streaming_startup
	collision.radius = collision_radius
	collision.extent = ground_extent
	collision.focus_point = ground.focus_point
	add_child(collision)
	collision.rebuild()


## Scenery beyond the world's edge that the horizon still draws, metres.
const HORIZON_MARGIN := 2000.0


func _apply_atmosphere() -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var env := world_environment.environment
	var point := focus.global_position if focus != null and focus.is_inside_tree() else Vector3.ZERO
	AtmosphereHaze.apply(env, profile.fog_colour, profile.haze_amount, AtmosphereHaze.reach(self, point))


## How far ground is drawn from `point`, metres: the horizon ring's reach (the
## ground's own without one), cut short by the world's edge plus its margin of
## scenery. Distance haze completes here (AtmosphereHaze), so the end of the
## world dissolves wherever the camera stands -- nearer the edge, the air
## closes in.
func drawn_ground_distance(point: Vector3) -> float:
	if quality == null or profile == null:
		return AtmosphereHaze.FALLBACK_DISTANCE
	var reach := quality.view_distance
	if streaming and quality.horizon_distance > 0.0:
		reach = maxf(quality.horizon_distance, reach)
	var shape := profile.terrain if profile.terrain != null else TerrainProfile.new()
	var bounds := shape.bounds().grow(HORIZON_MARGIN)
	var p := Vector2(point.x, point.z)
	var edge := minf(minf(p.x - bounds.position.x, bounds.end.x - p.x), minf(p.y - bounds.position.y, bounds.end.y - p.y))
	return minf(reach, maxf(edge, 0.0))


## The quality preset's shadow settings, applied to the sun.
##
## Sun cascades now also cover buildings; tree proxy range remains separate.
## Apply occlusion quality alongside shadows, without changing exposure.
func _apply_shadows() -> void:
	if world_environment != null and world_environment.environment != null:
		LightingSettings.apply_environment_quality(world_environment.environment, quality.level)
	if sun != null:
		LightingSettings.apply_shadows(sun, quality)


func _clear() -> void:
	if _river_credits != null:
		_river_credits.free()
		_river_credits = null
	for node in [grass, trees, debris, shoreline, ground, horizon, collision]:
		if node == null:
			continue
		# Blocks until that layer's in-flight worker builds finish.
		# queue_free() alone is not enough: it only defers freeing to the end
		# of the frame, so build() could reach terrain.set_painted_mask()
		# below while a worker from the OLD layer is still mid-read of it.
		# With an owned terrain that is harmless -- build() always swaps in a
		# fresh provider instance for it -- but a caller-supplied one is the
		# same object across the swap, and mutating it while a stale worker
		# still reads it is a real data race.
		node.stop_streaming()
		node.queue_free()
	# The sea has no worker thread to wait on -- it is one plane, rebuilt
	# synchronously -- so it is not part of the stop_streaming() loop above.
	if water != null:
		water.queue_free()
		water = null
	sea_state = null
	grass = null
	trees = null
	debris = null
	shoreline = null
	ground = null
	horizon = null
	collision = null


func teardown() -> void:
	_clear()
