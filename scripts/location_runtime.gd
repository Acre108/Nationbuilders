class_name LocationRuntime
extends Node3D

## One construction path for playable locations in the landing screen and
## test scenes. Owns environment, sun, camera, foliage, atmosphere and quality.

signal stage_changed(message: String, progress: float, pending_chunks: int)
signal location_ready(location: FoliageLocation)
signal location_failed(message: String)
signal choose_destination_requested

const FAR_MARGIN := 1.15
const FAR_PADDING := 250.0

var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var camera: FlyCamera
var location: FoliageLocation
var atmosphere: AtmosphereSystem
var definition: LocationDefinition
var quality_level: FoliageQuality.Level = FoliageQuality.Level.HIGH
## Test harnesses with their own controls can opt out before entering.
var commands_enabled: bool = true
var commands: LocationCommands
var buildings: OutdoorBuildingLayer
## Location Studio opens a destination even when authored building instances
## no longer validate (a changed base): it places the valid ones and lists the
## rest in building_issues ({instance_id: reason}). The game fails visibly.
var tolerant_buildings := false
var building_issues: Dictionary = {}
## Location Studio paints zones: the terrain always carries a ZoneOverrides
## (possibly empty), so every placing layer exists and samples zones live.
## The game attaches overrides only when the edits contain painted tiles.
var zone_painting := false
var site_layer: LocationSiteLayer
## Game visits build the geographic site progressively after arrival
## (LocationSiteLayer.progressive); Location Studio and tests count and edit
## site nodes straight after entry, so they keep the synchronous build.
var progressive_site := false
## Location Studio edits for this destination, or null when it has none.
var edits: LocationEdits


func _ready() -> void:
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = make_daylight_environment()
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	configure_sun(sun)
	add_child(sun)

	camera = FlyCamera.new()
	camera.name = "FlyCamera"
	camera.current = true
	add_child(camera)


static func make_daylight_environment(level: FoliageQuality.Level = FoliageQuality.Level.HIGH) -> Environment:
	return LightingSettings.make_daylight_environment(level)


static func configure_sun(target: DirectionalLight3D) -> void:
	LightingSettings.configure_sun(target)


func set_space_mode() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#04050a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#2a3040")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_environment.environment = env
	camera.far = 100.0
	camera.movement_enabled = false


func enter_destination(
	new_definition: LocationDefinition,
	level: FoliageQuality.Level = FoliageQuality.Level.HIGH,
	with_atmosphere: bool = true,
	streaming: bool = true,
) -> bool:
	teardown_location()
	definition = new_definition
	quality_level = level
	stage_changed.emit("Loading terrain and foliage profile", 0.15, 0)

	var profile := load(definition.foliage_profile_path) as FoliageProfile
	var terrain: TerrainProvider = HeightmapLocationLoader.load(definition.manifest_path) if not definition.manifest_path.is_empty() else null
	if profile == null:
		return _fail("Could not load foliage profile: %s" % definition.foliage_profile_path)
	if not definition.manifest_path.is_empty() and terrain == null:
		return _fail("Could not load terrain: %s" % definition.manifest_path)
	if terrain is HeightmapTerrainProvider:
		var loaded_edits := LocationEdits.load_for(definition, (terrain as HeightmapTerrainProvider).north_axis)
		if not loaded_edits.ok:
			return _fail("Could not load location edits: %s" % loaded_edits.error)
		edits = loaded_edits.edits
		# Sculpted heights (S5) first: water refits onto the edited ground.
		var height_section: Dictionary = edits.data.heights if edits != null else {}
		if not height_section.get("tiles", {}).is_empty():
			var sculpted := HeightDeltas.load_section(height_section, LocationEdits.path_for(definition), (terrain as HeightmapTerrainProvider).world_size())
			if not sculpted.ok:
				return _fail("Could not load sculpted heights: %s" % sculpted.error)
			(terrain as HeightmapTerrainProvider).set_height_deltas(sculpted.deltas)
		# Painted zones (S4): sidecar tiles beside the edits file.
		var zone_section: Dictionary = edits.data.zones if edits != null else {}
		if zone_painting or not zone_section.get("tiles", {}).is_empty():
			var painted := ZoneOverrides.load_section(zone_section, LocationEdits.path_for(definition), (terrain as HeightmapTerrainProvider).world_size())
			if not painted.ok:
				return _fail("Could not load painted zones: %s" % painted.error)
			(terrain as HeightmapTerrainProvider).zone_overrides = painted.overrides

	world_environment.environment = make_daylight_environment(level)
	configure_sun(sun)
	var quality := FoliageQuality.create(level)
	LightingSettings.apply_shadows(sun, quality)
	camera.far = maxf(quality.horizon_distance * FAR_MARGIN + FAR_PADDING, quality.view_distance + FAR_PADDING)
	camera.speed = 12.0
	camera.movement_enabled = false
	var xz := definition.spawn_xz
	var ground_height: float = terrain.get_height(xz.x, xz.y) if terrain != null else 0.0
	camera.position = Vector3(xz.x, ground_height + definition.eye_height, xz.y)
	camera.rotation = Vector3(deg_to_rad(definition.pitch_degrees), deg_to_rad(definition.heading_degrees), 0.0)
	camera.release_pointer()

	stage_changed.emit("Building arrival ground and collision", 0.42, 0)
	location = FoliageLocation.new()
	location.name = "Location"
	location.sun = sun
	location.world_environment = world_environment
	location.quality_level = level
	location.streaming = streaming
	location.staged_streaming_startup = streaming
	location.focus = camera
	location.profile = profile.duplicate()
	location.terrain = terrain
	location.day_of_year = definition.day_of_year
	location.year = definition.year
	if definition.atmosphere_profile != null:
		location.clock_hour = definition.atmosphere_profile.time_of_day
	add_child(location)
	if streaming and not location.is_indoor() and not location.prepare_spawn():
		teardown_location()
		return _fail("Arrival collision was not ready at %s" % str(camera.position))
	if not streaming:
		location.flush_streaming()
	if terrain is HeightmapTerrainProvider and terrain.imported_site != null:
		site_layer = LocationSiteLayer.new()
		site_layer.name = "GeographicSite"
		site_layer.terrain = terrain
		site_layer.edits = edits
		site_layer.profile = location.profile
		site_layer.focus = camera
		site_layer.quality_level = level
		site_layer.day_of_year = definition.day_of_year
		site_layer.progressive = progressive_site and streaming
		add_child(site_layer)


	buildings = OutdoorBuildingLayer.new()
	buildings.name = "AuthoredBuildings"
	buildings.terrain = location.terrain
	buildings.placement_events = location.placement_events
	buildings.exclusions = location.exclusions
	buildings.quality_level = level
	buildings.changed.connect(_sync_buildings)
	add_child(buildings)
	var instances: Array = edits.data.building_instances if edits != null else []
	var placed := buildings.replace_valid(instances) if tolerant_buildings else buildings.replace_all(instances)
	building_issues = placed.get("skipped", {})
	if not placed.ok:
		var message: String = placed.error
		teardown_location()
		return _fail("Could not place destination buildings: " + message)

	stage_changed.emit("Placing camera", 0.68, location.pending_chunks())
	camera.position.y = (location.terrain.get_height(xz.x, xz.y) if location.terrain != null else 0.0) + definition.eye_height

	if with_atmosphere and not location.is_indoor():
		stage_changed.emit("Starting atmosphere", 0.82, location.pending_chunks())
		atmosphere = AtmosphereSystem.new()
		atmosphere.name = "Atmosphere"
		atmosphere.profile = definition.atmosphere_profile.duplicate() if definition.atmosphere_profile != null else AtmosphereProfile.new()
		# The real sun for a destination on the map.
		if not definition.manifest_path.is_empty():
			atmosphere.profile.latitude = definition.latitude
			atmosphere.profile.day_of_year = location.day_of_year
			atmosphere.profile.north_z = (location.terrain as HeightmapTerrainProvider).north_z() if location.terrain is HeightmapTerrainProvider else -1.0
		atmosphere.sun = sun
		atmosphere.world_environment = world_environment
		atmosphere.foliage_location = location
		atmosphere.building_zones = _building_zones()
		add_child(atmosphere)

	camera.movement_enabled = true
	if commands_enabled:
		commands = LocationCommands.new()
		commands.name = "Commands"
		commands.runtime = self
		add_child(commands)
	stage_changed.emit("Streaming scenery", 1.0, location.pending_chunks())
	location_ready.emit(location)
	return true


## Foliage chunks and progressive site pieces still to build.
func pending_chunks() -> int:
	var pending := location.pending_chunks() if location != null else 0
	return pending + (site_layer.pending_pieces() if site_layer != null else 0)

## One quality path for commands and callers; authored physics stays intact.
func set_quality(level: FoliageQuality.Level) -> void:
	quality_level = level
	if location != null: location.set_quality(level)
	if site_layer != null: site_layer.quality_level = level
	if buildings != null: buildings.quality_level = level
	if location != null:
		camera.far = maxf(location.quality.horizon_distance*FAR_MARGIN+FAR_PADDING,location.quality.view_distance+FAR_PADDING)


func teardown_location() -> void:
	camera.movement_enabled = false
	camera.release_pointer()
	if buildings != null:
		remove_child(buildings)
		buildings.free()
		buildings = null
	if site_layer != null:
		remove_child(site_layer)
		site_layer.free()
		site_layer = null
	if commands != null:
		remove_child(commands)
		commands.free()
		commands = null
	if atmosphere != null:
		remove_child(atmosphere)
		atmosphere.free()
		atmosphere = null
	if location != null:
		location.teardown()
		remove_child(location)
		location.free()
		location = null
	definition = null
	edits = null


func _fail(message: String) -> bool:
	push_error("LocationRuntime: " + message)
	location_failed.emit(message)
	return false

## Dynamic Studio/runtime operations update weather and placeholder collision
## immediately. The base bake and source building documents remain untouched.
func _sync_buildings() -> void:
	if site_layer != null: site_layer.apply_building_exclusions(buildings.replaced_ids,location.exclusions)
	if atmosphere != null:
		atmosphere.building_zones = _building_zones()

func _building_zones() -> Array[AtmosphereZone]:
	var result: Array[AtmosphereZone] = []
	if site_layer != null: result.append_array(site_layer.building_zones)
	if buildings != null: result.append_array(buildings.zones)
	return result
