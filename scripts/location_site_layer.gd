class_name LocationSiteLayer
extends Node3D

## Geographic placeholders and metre-scale props. Buildings retain source
## records; the future editor can replace each without changing geography.
var terrain: HeightmapTerrainProvider
var profile: FoliageProfile
## Location Studio edits applied over the baked site, or null. S2 building
## overrides apply here; S3 instances go through OutdoorBuildingLayer.
var edits: LocationEdits
var focus: Node3D
var quality_level: FoliageQuality.Level = FoliageQuality.Level.HIGH:
	set(value):
		quality_level=value
		if crops!=null: crops.set_quality(value)
		for building in _authored_buildings: BuildingLocalLights.set_quality(building,value)
		if street_lights!=null: street_lights.quality_level=value
var building_count := 0
var road_count := 0
var prop_count := 0
var _props: Array[SiteProp] = []
var _trees: Array[MeshInstance3D] = []
var crops: SiteCropLayer
## Inferred lamps along urban roads; lit by AtmosphereSystem.night_lights.
var street_lights: SiteStreetLights
## Kerbs, pavements and street furniture by road context (rural/village/town).
var roadside: SiteRoadside
## Season for field crops; see LocationDefinition.day_of_year.
var day_of_year: float = 196.0
var building_zones: Array[AtmosphereZone] = []
var _authored_buildings: Array[Node3D] = []
var _building_nodes: Dictionary = {}
var _building_zone_map: Dictionary = {}
## Observed records by source_id, and the overrides they are drawn with.
var _records: Dictionary = {}
var _overrides: Dictionary = {}
var _replaced: Dictionary = {}
## Roof for records baked before building_materials.py gave each building
## its materials; their walls keep the shared PlaceholderWindows default.
var _legacy_roof: Material
## Road index -> its route mesh (or null when it has none), for area rebuilds.
var _road_nodes: Dictionary = {}
static var _override_materials: Dictionary = {}
## Game visits: placeholders, roads, pavements, furniture and lamps beyond
## NEAR_RADIUS of the arrival point are built after arrival through a
## SiteBuildQueue, nearest first, instead of blocking entry. Location Studio
## and tests keep the synchronous build: they count and edit site nodes
## straight after entry.
var progressive := false
## Built before the first frame even when progressive: what the arrival
## view and the first steps stand on.
const NEAR_RADIUS := 150.0
var _queue: SiteBuildQueue

## Move the crop season; pair with FoliageLocation.set_day_of_year().
## House chimneys smoke only in the heating season.
func set_day_of_year(day: float) -> void:
	day_of_year=day
	if crops!=null: crops.set_day_of_year(day)
	_smoke_emitters = _smoke_emitters.filter(func(emitter: GPUParticles3D) -> bool: return is_instance_valid(emitter))
	for emitter in _smoke_emitters: emitter.emitting = _smoking(emitter)

## Heating season for house chimneys (northern-hemisphere day of year).
const HEATING_SEASON := Vector2(285.0, 105.0)
var _smoke_emitters: Array[GPUParticles3D] = []
var _smoke_materials: Dictionary = {}

## Regional building sources by source-id prefix.
const BUILDING_ATTRIBUTION := {"lgb/": "© GeoBasis-DE/LGB (dl-de/by-2-0)"}

## Attribution for the sources this site actually uses: OSM always, WorldCover
## when the bake used it, and regional building or terrain refinements only
## when present (building source ids; the manifest's DEM refinement, copied
## into the site provenance by import_site.py).
static func credits_text(data: Dictionary) -> String:
	var provenance: Dictionary = data.get("provenance", {})
	var site := PackedStringArray(["© OpenStreetMap contributors (ODbL)"])
	if provenance.get("worldcover") != null: site.append("ESA WorldCover 2021 (CC BY 4.0)")
	# Overture building gap-fill (import_site.py --overture): credited when it
	# added footprints or heights, naming the footprint datasets it used.
	var overture: Variant = provenance.get("overture")
	if overture is Dictionary and (int(overture.get("added", 0)) > 0 or int(overture.get("osm_heights", 0)) > 0):
		var datasets := PackedStringArray((overture.get("datasets", {}) as Dictionary).keys())
		site.append("Overture Maps Foundation buildings (ODbL" + ("; " + ", ".join(datasets) if not datasets.is_empty() else "") + ")")
	var refined := PackedStringArray()
	for building in data.get("buildings", []):
		var source := str(building.get("source_id", ""))
		for prefix in BUILDING_ATTRIBUTION:
			if source.begins_with(prefix) and not refined.has(BUILDING_ATTRIBUTION[prefix]):
				refined.append(BUILDING_ATTRIBUTION[prefix])
	var terrain_credit: Variant = provenance.get("terrain_refinement")
	if terrain_credit is String and not (terrain_credit as String).is_empty():
		# Manifest form "© X, licence" -> "© X (licence)", matching the rest.
		var parts := (terrain_credit as String).split(", ", true, 1)
		var credit := parts[0] + (" (" + parts[1] + ")" if parts.size() > 1 else "")
		if not refined.has(credit): refined.append(credit)
	var text := "Site data: " + " · ".join(site)
	if not refined.is_empty(): text += "\nRegional refinement: " + " · ".join(refined)
	return text

func _ready() -> void:
	var data := terrain.imported_site.data
	_legacy_roof = _material(Color("#8c7161"))
	if edits != null: _overrides = edits.data.building_overrides.duplicate(true)
	if progressive:
		_queue = SiteBuildQueue.new()
		_queue.origin = _focus_xz()
	for record in data.buildings:
		_records[record.source_id] = record
		_building(record)
	for index in data.roads.size():
		var road: Dictionary = data.roads[index]
		_road_nodes[index] = null
		if _queue != null and not _near(road.points):
			_queue.add_along(road.points, Callable(SiteRouteMesh, "arrays").bind(road, terrain.get_height),
				func(surface: Array) -> void: _road_nodes[index] = _road_instance(surface, road))
		else:
			_road_nodes[index] = _road(road)
	_build_roadside()
	_build_street_lights()
	if terrain.imported_site.has_fields():
		crops=SiteCropLayer.new()
		crops.name="FieldCrops"
		crops.terrain=terrain
		crops.focus=focus
		crops.quality_level=quality_level
		crops.day_of_year=day_of_year
		add_child(crops)
	for record in data.props:
		var prop := SitePropCatalogue.create(record.asset)
		if prop == null: continue
		prop.name = record.id
		prop.set_meta("placement_basis", record.basis)
		add_child(prop)
		prop.position = _ground(record.xz)
		prop.rotation.y = deg_to_rad(float(record.get("yaw",0)))
		_props.append(prop)
		prop_count += 1
	for record in data.trees:
		var tree := MeshInstance3D.new()
		tree.name = record.id
		tree.mesh = NatureMeshBuilder.build(record.asset, float(record.get("height",12)), profile, false, true, false, 0.25)
		add_child(tree)
		tree.position = _ground(record.xz)
		tree.set_meta("placement_basis",record.basis)
		_trees.append(tree)
		var body := StaticBody3D.new()
		tree.add_child(body)
		var collision := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.3
		cylinder.height = 3.0
		collision.shape = cylinder
		collision.position.y = 1.5
		body.add_child(collision)
	var credits := CanvasLayer.new()
	credits.name = "SiteCredits"
	add_child(credits)
	var label := Label.new()
	label.text = credits_text(data)
	label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	label.add_theme_constant_override("outline_size",3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	label.position = Vector2(18,-64)
	credits.add_child(label)

func _process(_delta: float) -> void:
	if _queue != null:
		_queue.update()
		if _queue.pending() == 0: _queue = null
	if focus == null: return
	for prop in _props:
		var distance := prop.global_position.distance_squared_to(focus.global_position)
		prop.visible = distance < 650.0 * 650.0
		prop.use_far_mesh = distance > 55.0 * 55.0
	for tree in _trees:
		tree.visible = not tree.get_meta("building_excluded",false) and tree.global_position.distance_squared_to(focus.global_position) < 850.0 * 850.0

func _ground(point: Array, offset := 0.0) -> Vector3:
	return Vector3(float(point[0]), terrain.get_height(float(point[0]),float(point[1])) + offset, float(point[1]))

func _material(colour: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = colour
	result.roughness = 0.95
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result

## Site pieces not yet built (progressive game visits); 0 once complete.
func pending_pieces() -> int:
	return _queue.pending() if _queue != null else 0

## Builds whatever the progressive queue still holds, blocking. Later
## rebuilds (edits) are then synchronous.
func flush() -> void:
	if _queue != null: _queue.flush()
	_queue = null

func _exit_tree() -> void:
	# Drops unbuilt pieces; waits only for those already on a worker.
	if _queue != null: _queue.cancel()

func _focus_xz() -> Vector2:
	return Vector2(focus.global_position.x, focus.global_position.z) if focus != null and focus.is_inside_tree() else Vector2.ZERO

## True when any vertex of a footprint or polyline is within NEAR_RADIUS.
func _near(points: Array) -> bool:
	for p in points:
		if Vector2(p[0], p[1]).distance_squared_to(_queue.origin) < NEAR_RADIUS * NEAR_RADIUS: return true
	return false

func _building(record: Dictionary) -> void:
	if record.has("building_document"):
		var loaded := BuildingStore.load_id(String(record.building_document).get_file().get_basename())
		if loaded.ok:
			var definition: BuildingDefinition = loaded.definition
			var placement: Dictionary = definition.data.geographic_placement
			var building := BuildingSceneBuilder.build(definition)
			building.name = String(record.source_id).replace("/", "_")
			building.set_meta("geographic_record",record)
			building.set_meta("building_definition",definition)
			building.set_meta("placeholder",false)
			_building_nodes[record.source_id] = building
			add_child(building)
			building.position = _ground(placement.xz,float(placement.foundation_above_front_ground))
			building.rotation.y = deg_to_rad(float(placement.yaw_degrees))
			BuildingLocalLights.set_quality(building,quality_level)
			_authored_buildings.append(building)
			var zones := BuildingLightingZones.create(definition,building.global_transform)
			_building_zone_map[record.source_id] = zones
			building_zones.append_array(zones)
			building_count += 1
			return
		push_error("Location building document failed: " + loaded.error)
	var override: Dictionary = _overrides.get(record.source_id, {})
	var effective := LocationBuildingOverrides.effective_record(record, override)
	var build := Callable(LocationSiteLayer, "placeholder_geometry").bind(effective, terrain)
	if _queue != null and not _near(record.outline):
		_queue.add_along(record.outline, build, func(geometry: Dictionary) -> void:
			var node := _placeholder(geometry, record, override, effective)
			if _replaced.has(record.source_id):
				_set_excluded(node, true)
				building_count -= 1)
	else:
		_placeholder(build.call(), record, override, effective)

## Thread-safe placeholder geometry for an (override-effective) record:
## walls with window UVs (PlaceholderWindows) up to the eaves, the roof (a
## pitched PlaceholderRoofs roof, or the flat cap), gables and chimneys. The
## same triangles are the collision, so each surface is built once.
static func placeholder_geometry(record: Dictionary, ground: HeightmapTerrainProvider) -> Dictionary:
	var low := INF
	var high := -INF
	for p in record.outline:
		var y := ground.get_height(float(p[0]),float(p[1]))
		low = minf(low,y)
		high = maxf(high,y)
	var top := high + float(record.height)
	var eaves := top - PlaceholderRoofs.rise(record)
	var result := {"walls": PlaceholderWindows.wall_arrays(record, low, eaves, ground.north_axis), "roof": [], "gables": [],
		"chimneys": PlaceholderRoofs.chimneys(record, ground, eaves, top)}
	if eaves < top:
		var shell := PlaceholderRoofs.pitched(record, eaves, top)
		result.roof = shell.roof
		result.gables = shell.gables
	elif not record.roof_triangles.is_empty():
		var cap := SurfaceTool.new()
		cap.begin(Mesh.PRIMITIVE_TRIANGLES)
		for t in record.roof_triangles:
			# Plan-metre UVs, so a tiled roof keeps a constant course size.
			for p in [t[0], t[2], t[1]]:
				cap.set_uv(Vector2(p[0], p[1]))
				cap.add_vertex(Vector3(p[0], top, p[1]))
		cap.generate_normals()
		result.roof = cap.commit_to_arrays()
	return result

## MAIN THREAD. The placeholder node for placeholder_geometry().
func _placeholder(geometry: Dictionary, observed: Dictionary, override: Dictionary, record: Dictionary) -> StaticBody3D:
	# Imported materials (building_materials.py) with Studio overrides on top.
	var materials := LocationBuildingOverrides.drawn_materials(observed, override)
	var node := StaticBody3D.new()
	node.name = String(observed.source_id).replace("/", "_")
	# The observed record stays the node's geographic record; overrides are authored.
	node.set_meta("geographic_record", observed)
	node.set_meta("building_override", override)
	node.set_meta("drawn_height", float(record.height))
	node.set_meta("placeholder",true)
	_building_nodes[record.source_id] = node
	add_child(node)
	# Generic lit-at-night windows (PlaceholderWindows shader) in the wall colour.
	var walls: Material = _wall_override(materials.exterior_wall) if materials.has("exterior_wall") else PlaceholderWindows.material()
	var wall_mesh := _surface_instance(geometry.walls, walls, node)
	wall_mesh.name = "Walls"
	if not geometry.roof.is_empty():
		var roof: Material = _roof_override(materials.roof) if materials.has("roof") else _legacy_roof
		var cap_mesh := _surface_instance(geometry.roof, roof, node)
		cap_mesh.name = "Roof"
	if not geometry.gables.is_empty():
		_surface_instance(geometry.gables, walls, node).name = "Gables"
	for chimney in geometry.chimneys:
		_surface_instance(chimney.arrays, _flat_override(chimney.material), node).name = "Stack" if chimney.stack else "Chimney"
		_add_smoke(node, chimney)
	building_count += 1
	return node

## A mesh child from surface arrays, with matching two-sided trimesh collision.
func _surface_instance(surface: Array, material: Material, parent: Node3D) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(surface[Mesh.ARRAY_VERTEX])
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	parent.add_child(collision)
	return instance

## Redraws the placeholders whose override changed (Studio commands, undo).
## Observed records are untouched; a replaced placeholder stays hidden.
func apply_building_overrides(overrides: Dictionary) -> PackedStringArray:
	flush()
	var changed := PackedStringArray()
	for id in _overrides.keys() + overrides.keys():
		if changed.has(id) or not _records.has(id): continue
		if JSON.stringify(_overrides.get(id, {})) != JSON.stringify(overrides.get(id, {})): changed.append(id)
	_overrides = overrides.duplicate(true)
	for id in changed: _rebuild_building(id)
	return changed

func _rebuild_building(id: String) -> void:
	var old: Node3D = _building_nodes.get(id)
	if old == null or not old.get_meta("placeholder", false): return
	remove_child(old)
	old.free()
	building_count -= 1
	_building(_records[id])
	if _replaced.has(id): _set_excluded(_building_nodes[id], true)

## Sculpted heights changed inside `area` (Location Studio S5): placeholders,
## roads, pavements, street lamps, props, site trees and crops there follow
## the new ground. Returns what was rebuilt, by kind.
func terrain_changed(area: Rect2) -> Dictionary:
	flush()
	var rebuilt := {"buildings": 0, "roads": 0, "props": 0, "trees": 0}
	for id in _records:
		if _outline_rect(_records[id].outline).intersects(area):
			_rebuild_building(id)
			rebuilt.buildings += 1
	var roads: Array = terrain.imported_site.data.roads
	for index in roads.size():
		var record: Dictionary = roads[index]
		if not _outline_rect(record.points).grow(float(record.get("width", 4.0))).intersects(area): continue
		var old: Node3D = _road_nodes.get(index)
		if old != null:
			remove_child(old)
			old.free()
			road_count -= 1
		_road_nodes[index] = _road(record)
		rebuilt.roads += 1
	if rebuilt.roads > 0:
		# Pavements and lamps are planned along whole roads at once.
		for node in [roadside, street_lights]:
			if node != null:
				remove_child(node)
				node.free()
		_build_roadside()
		_build_street_lights()
	for prop in _props:
		if area.has_point(Vector2(prop.position.x, prop.position.z)):
			prop.position.y = terrain.get_height(prop.position.x, prop.position.z)
			rebuilt.props += 1
	for tree in _trees:
		if area.has_point(Vector2(tree.position.x, tree.position.z)):
			tree.position.y = terrain.get_height(tree.position.x, tree.position.z)
			rebuilt.trees += 1
	if crops != null: crops.terrain_changed()
	return rebuilt

static func _outline_rect(points: Array) -> Rect2:
	var rect := Rect2(Vector2(points[0][0], points[0][1]), Vector2.ZERO)
	for p in points: rect = rect.expand(Vector2(p[0], p[1]))
	return rect

func _build_roadside() -> void:
	roadside=SiteRoadside.new()
	roadside.name="Roadside"
	roadside.terrain=terrain
	roadside.queue=_queue
	add_child(roadside)

func _build_street_lights() -> void:
	street_lights=SiteStreetLights.new()
	street_lights.name="StreetLights"
	street_lights.terrain=terrain
	street_lights.focus=focus
	street_lights.quality_level=quality_level
	street_lights.queue=_queue
	add_child(street_lights)

func _wall_override(value: String) -> Material:
	var key := "wall:" + value
	if not _override_materials.has(key):
		var material := PlaceholderWindows.material().duplicate() as ShaderMaterial
		var colour := LocationBuildingOverrides.colour_of(value)
		material.set_shader_parameter("wall_colour", colour)
		_override_materials[key] = material
	return _override_materials[key]

func _roof_override(value: String) -> Material:
	var key := "roof:" + value
	if not _override_materials.has(key):
		var colour := LocationBuildingOverrides.colour_of(value)
		if LocationBuildingOverrides.is_tiled(value):
			var tiles := ShaderMaterial.new()
			tiles.shader = load("res://buildings/shaders/roof_tiles.gdshader")
			tiles.set_shader_parameter("tile_colour", colour)
			_override_materials[key] = tiles
		else:
			_override_materials[key] = _flat_override(value)
	return _override_materials[key]

## A plain lit material for a material value (non-tiled roofs, chimneys).
func _flat_override(value: String) -> Material:
	var key := "flat:" + value
	if not _override_materials.has(key):
		var material := _material(LocationBuildingOverrides.colour_of(value))
		material.roughness = LocationBuildingOverrides.roughness_of(value)
		if LocationBuildingOverrides.parse(value).family == "metal": material.metallic = 0.6
		_override_materials[key] = material
	return _override_materials[key]

## Smoke from a chimney outlet: stacks always, house chimneys in the heating
## season. Drifts downwind (FoliageProfile.wind_direction).
func _add_smoke(parent: Node3D, chimney: Dictionary) -> void:
	if chimney.season.is_empty() or (not chimney.stack and quality_level == FoliageQuality.Level.LOW): return
	var emitter := GPUParticles3D.new()
	emitter.name = "Smoke"
	emitter.amount = 32 if chimney.stack else 10
	emitter.lifetime = 10.0 if chimney.stack else 5.0
	emitter.preprocess = emitter.lifetime
	emitter.process_material = _smoke_process(chimney.stack)
	emitter.draw_pass_1 = _smoke_quad()
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 60, 80))
	emitter.position = chimney.smoke
	emitter.set_meta("heating_season", chimney.season == "heating_season")
	parent.add_child(emitter)
	emitter.emitting = _smoking(emitter)
	_smoke_emitters.append(emitter)

func _smoking(emitter: GPUParticles3D) -> bool:
	if not emitter.get_meta("heating_season", false): return true
	return day_of_year >= HEATING_SEASON.x or day_of_year <= HEATING_SEASON.y

func _smoke_process(stack: bool) -> ParticleProcessMaterial:
	if _smoke_materials.has(stack): return _smoke_materials[stack]
	var wind := profile.wind_direction if profile != null else Vector2(1.0, 0.35)
	wind = wind.normalized() if wind.length() > 0.0 else Vector2.RIGHT
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 6.0
	process.initial_velocity_min = 1.8 if stack else 0.5
	process.initial_velocity_max = 2.6 if stack else 0.9
	process.gravity = Vector3(wind.x, 0.12, wind.y) * (0.9 if stack else 0.6)
	process.damping_min = 0.15
	process.damping_max = 0.3
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.6 if stack else 0.15
	process.scale_min = 2.0 if stack else 0.5
	process.scale_max = 3.0 if stack else 0.8
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.35))
	growth.add_point(Vector2(1.0, 1.0))
	var growth_texture := CurveTexture.new()
	growth_texture.curve = growth
	process.scale_curve = growth_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(0.82, 0.82, 0.8, 0.0))
	fade.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	fade.add_point(0.12, Color(0.8, 0.8, 0.78, 0.5 if stack else 0.35))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	_smoke_materials[stack] = process
	return process

func _smoke_quad() -> QuadMesh:
	if _smoke_materials.has("quad"): return _smoke_materials["quad"]
	var puff := Gradient.new()
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = puff
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.roughness = 1.0
	material.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	quad.material = material
	_smoke_materials["quad"] = quad
	return quad

func _road(record: Dictionary) -> Node3D:
	return _road_instance(SiteRouteMesh.arrays(record,terrain.get_height),record)

func _road_instance(surface: Array, record: Dictionary) -> Node3D:
	var instance := SiteRouteMesh.instance(record,surface)
	if instance == null: return null
	add_child(instance)
	instance.name = String(record.source_id).replace("/","_")
	instance.set_meta("geographic_record",record)
	road_count += 1
	return instance

## Keep observations intact; a pinned instance only hides its named placeholders.
## Collision is toggled together with visibility and restored on instance removal.
func apply_building_exclusions(replaced: Dictionary, exclusions: FoliageExclusions) -> void:
	_replaced = replaced.duplicate()
	building_count = 0
	building_zones.clear()
	for id in _building_nodes:
		var node: Node3D = _building_nodes[id]
		_set_excluded(node,replaced.has(id))
		if not replaced.has(id):
			building_count += 1
			building_zones.append_array(_building_zone_map.get(id,[]))
	for tree in _trees:
		_set_excluded(tree,exclusions != null and exclusions.contains(tree.global_position.x,tree.global_position.z))

static func _set_excluded(node: Node3D, excluded: bool) -> void:
	if node.get_meta("building_excluded",false) == excluded: return
	node.set_meta("building_excluded",excluded)
	node.visible = not excluded
	_set_collision_excluded(node,excluded)

static func _set_collision_excluded(node: Node, excluded: bool) -> void:
	if node is CollisionObject3D:
		if not node.has_meta("original_collision_layer"):
			node.set_meta("original_collision_layer",node.collision_layer)
			node.set_meta("original_collision_mask",node.collision_mask)
		node.collision_layer = 0 if excluded else node.get_meta("original_collision_layer")
		node.collision_mask = 0 if excluded else node.get_meta("original_collision_mask")
	for child in node.get_children(): _set_collision_excluded(child,excluded)
