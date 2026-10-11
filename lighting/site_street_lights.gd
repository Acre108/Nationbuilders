class_name SiteStreetLights
extends Node3D

## Street lamps along the village and town streets of an imported site.
## Positions are INFERRED from road records at load (no lamp survey exists),
## by each road's context (tools/geo/settlements.py `context_spans`): village
## streets one side, town streets both sides staggered, rural roads none;
## OSM lit=yes lights any way, lit=no is respected. Sites baked before road
## contexts fall back to street-class ways inside residential/commercial land
## use. Nothing is written back to the site bake.
##
## Every lamp shows its mesh and an emissive head; only the nearest few carry a
## real SpotLight3D, from a fixed pool sized by quality, so cost stays bounded
## however many lamps a village has. Lamps follow AtmosphereSystem.night_lights.

const LAMP_SCENE := "res://assets/town/poly_towncity/road_light.glb"
## Light origin under the lamp head, from the source prefab's spot light.
const HEAD := Vector3(0.0, 3.83, 1.9)
const STREET_CLASSES := ["residential", "living_street", "unclassified", "tertiary",
	"secondary", "primary", "pedestrian"]
const URBAN_LANDUSE := ["residential", "commercial", "retail", "village_green"]
const SPACING := 30.0
## Lamp spacing along a street-class span by road context, per side.
const CONTEXT_SPACING := {"village": 35.0, "town": 28.0}
## A lit=yes way outside a settlement.
const LIT_SPACING := 40.0
const MIN_GAP := 14.0
const EDGE_SETBACK := 0.6
const COLOUR := Color("#ffc27a")
const ENERGY := 8.0
const VISIBLE_RANGE := 600.0
const LIGHT_RANGE := 160.0
const POOL := {FoliageQuality.Level.LOW: 6, FoliageQuality.Level.MEDIUM: 12,
	FoliageQuality.Level.HIGH: 24, FoliageQuality.Level.ULTRA: 32}

var terrain: HeightmapTerrainProvider
var focus: Node3D
var quality_level: FoliageQuality.Level = FoliageQuality.Level.HIGH:
	set(value):
		quality_level = value
		if is_inside_tree(): _build_pool()
## Placements: {position, yaw, road} in world space.
var placements: Array[Dictionary] = []
var _lamps: Array[Node3D] = []
var _pool: Array[SpotLight3D] = []
var _head_material: StandardMaterial3D
var _head_mesh: BoxMesh
var _scene: PackedScene
var _refresh := 0.0
## Set before entering the tree to plan on a worker and add lamps through the
## queue a few at a time (LocationSiteLayer).
var queue: SiteBuildQueue

func _ready() -> void:
	_head_material = StandardMaterial3D.new()
	_head_material.albedo_color = Color("#3a3530")
	_head_material.emission_enabled = true
	_head_material.emission = COLOUR
	_head_material.emission_energy_multiplier = 0.0
	_head_mesh = BoxMesh.new()
	_head_mesh.size = Vector3(0.22, 0.03, 0.5)
	_scene = load(LAMP_SCENE) as PackedScene
	if queue != null:
		queue.add(queue.origin, Callable(SiteStreetLights, "plan").bind(terrain.imported_site.data, terrain.get_height), _planned)
	else:
		placements = plan(terrain.imported_site.data, terrain.get_height)
		for placement in placements: _add_lamp(placement)
	_build_pool()

func _planned(planned: Array) -> void:
	placements.assign(planned)
	for placement in placements: queue.then(_add_lamp.bind(placement))

func _add_lamp(placement: Dictionary) -> void:
	var lamp := Node3D.new()
	lamp.name = "StreetLamp%d" % _lamps.size()
	lamp.set_meta("placement_basis", "inferred")
	lamp.set_meta("road", placement.road)
	add_child(lamp)
	lamp.position = placement.position
	lamp.rotation.y = placement.yaw
	if _scene != null: lamp.add_child(_scene.instantiate())
	var glow := MeshInstance3D.new()
	glow.mesh = _head_mesh
	glow.material_override = _head_material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = HEAD + Vector3(0.0, 0.05, 0.0)
	lamp.add_child(glow)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.12
	cylinder.height = 4.0
	shape.shape = cylinder
	shape.position.y = 2.0
	body.add_child(shape)
	lamp.add_child(body)
	_lamps.append(lamp)

func _process(delta: float) -> void:
	var on := AtmosphereSystem.night_lights
	_head_material.emission_energy_multiplier = on * 6.0
	_refresh -= delta
	if _refresh > 0.0 or focus == null: return
	_refresh = 0.25
	var from := focus.global_position
	var near: Array = []
	for lamp in _lamps:
		var d := lamp.position.distance_squared_to(from)
		lamp.visible = d < VISIBLE_RANGE * VISIBLE_RANGE
		if on > 0.01 and d < LIGHT_RANGE * LIGHT_RANGE: near.append([d, lamp])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in _pool.size():
		var light := _pool[i]
		light.visible = i < near.size()
		if not light.visible: continue
		var lamp: Node3D = near[i][1]
		light.global_transform = lamp.global_transform.translated_local(HEAD)
		light.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		light.light_energy = ENERGY * on

func _build_pool() -> void:
	for light in _pool: light.queue_free()
	_pool.clear()
	for i in POOL.get(quality_level, 24):
		var light := SpotLight3D.new()
		light.light_color = COLOUR
		light.spot_range = 18.0
		light.spot_angle = 62.0
		light.spot_attenuation = 0.6
		light.shadow_enabled = false
		light.light_bake_mode = Light3D.BAKE_DYNAMIC
		light.visible = false
		add_child(light)
		_pool.append(light)
	_refresh = 0.0

## Pure placement from site data; `height` samples terrain at (x, z).
static func plan(data: Dictionary, height: Callable) -> Array[Dictionary]:
	var urban: Array[PackedVector2Array] = []
	for area in data.get("landuse", []):
		if str(area.get("kind", "")) in URBAN_LANDUSE: urban.append(_ring(area.outline))
	var footprints: Array[PackedVector2Array] = []
	for building in data.get("buildings", []): footprints.append(_ring(building.outline))
	var result: Array[Dictionary] = []
	var taken := {}
	for road in data.get("roads", []):
		var tags: Dictionary = road.get("tags", {})
		var lit := str(tags.get("lit", ""))
		if lit == "no": continue
		var forced := lit == "yes"
		var street := str(tags.get("highway", "")) in STREET_CLASSES
		if not forced and not street: continue
		# Runs of [start, end, side, spacing, phase] along the centre line.
		var runs: Array = []
		if road.has("context_spans"):
			for span in road.context_spans:
				var context := str(span[2])
				if street and CONTEXT_SPACING.has(context):
					var spacing: float = CONTEXT_SPACING[context]
					# Village lamps keep to the pavement side (left if neither).
					var side := 1.0 if float(span[3]) >= float(span[4]) else -1.0
					runs.append([float(span[0]), float(span[1]), side, spacing, 0.5])
					if context == "town": runs.append([float(span[0]), float(span[1]), -side, spacing, 0.0])
				elif forced:
					runs.append([float(span[0]), float(span[1]), 1.0, LIT_SPACING, 0.5])
		else:
			runs.append([0.0, INF, 1.0, SPACING, 0.5])
		var offset := float(road.get("width", 5.0)) * 0.5 + EDGE_SETBACK
		var legacy: bool = not road.has("context_spans")
		for run in runs:
			for spot in _run_spots(road.points, run):
				var centre: Vector2 = spot[0]
				if legacy and not forced and not _inside_any(centre, urban): continue
				var lamp: Vector2 = centre + spot[1] * offset
				if _inside_any(lamp, footprints) or _near_taken(lamp, taken): continue
				taken[_cell(lamp)] = taken.get(_cell(lamp), []) + [lamp]
				# The arm reaches along +Z: turn it towards the road centre.
				var to_road := (centre - lamp).normalized()
				result.append({"position": Vector3(lamp.x, height.call(lamp.x, lamp.y), lamp.y),
					"yaw": atan2(to_road.x, to_road.y), "road": str(road.get("source_id", ""))})
	return result

## [centre point, unit normal to the run's side] every run spacing between
## its start and end distances, starting `phase` of a spacing in.
static func _run_spots(points: Array, run: Array) -> Array:
	var start: float = run[0]
	var end: float = run[1]
	var side: float = run[2]
	var spacing: float = run[3]
	var result: Array = []
	var next := start + spacing * float(run[4])
	var travelled := 0.0
	for i in points.size() - 1:
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[i + 1][0], points[i + 1][1])
		var length := a.distance_to(b)
		if length < 0.01: continue
		var along := (b - a) / length
		while next <= travelled + length and next <= end:
			result.append([a + along * (next - travelled), Vector2(-along.y, along.x) * side])
			next += spacing
		travelled += length
		if travelled > end: break
	return result

static func _ring(outline: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for p in outline: ring.append(Vector2(p[0], p[1]))
	return ring

static func _inside_any(point: Vector2, rings: Array[PackedVector2Array]) -> bool:
	for ring in rings:
		# Cheap bounds reject first: villages have hundreds of footprints.
		if ring.size() < 3 or point.x < ring[0].x - 200.0 or point.x > ring[0].x + 200.0: continue
		var box := Rect2(ring[0], Vector2.ZERO)
		for q in ring: box = box.expand(q)
		if box.has_point(point) and Geometry2D.is_point_in_polygon(point, ring): return true
	return false

static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / MIN_GAP), floori(p.y / MIN_GAP))

static func _near_taken(p: Vector2, taken: Dictionary) -> bool:
	var c := _cell(p)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for q in taken.get(c + Vector2i(dx, dy), []):
				if p.distance_to(q) < MIN_GAP: return true
	return false
