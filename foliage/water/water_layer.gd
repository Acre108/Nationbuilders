class_name WaterLayer
extends Node3D

## Still water: the sea (one plane that follows `focus`) and any lakes (one
## static flat quad per retained basin from LandformTerrainProvider's
## priority-flood bake -- see LakeBasins and docs/WATER.md, W3). Plus rivers
## (W4): unlike the sea and lakes, a river cannot be a flat plane -- it must
## follow its valley's slope -- so it is a real terrain-following ribbon mesh
## traced by RiverTracer. All three share the same material, so the same
## look, wind and horizon handover apply everywhere.
##
## The sea and lakes need no chunking or clipping. Every quad is a flat plane
## at a fixed height, sized (for a lake, to its basin's bounding box) so
## ordinary depth testing against the opaque ground does the "clipping":
## wherever the ground rises above the water's height it simply occludes the
## plane. That is what already made the sea (W1) cheap, and it is exactly as
## true for a lake with a finite footprint as it is for an unbounded sea. A
## river cannot use this trick (it is not flat), so its mesh is built by
## sampling the rendered terrain under every ribbon vertex and through each
## triangle's interior instead -- more work per metre, but rivers are narrow,
## so the vertex count stays small.
##
## This node itself stays at identity -- only the sea's own child moves each
## frame (follow()). Lake and river meshes are positioned/built in world
## space once, at rebuild(), and never move: an early version moved this
## whole node instead and dragged every lake along with the camera, which is
## wrong for anything that is not the sea.

@export var profile: WaterProfile
## Half-width of the sea's plane, world units. Sized from the quality
## preset's horizon_distance so it never visibly ends before the sky does.
var reach: float = 6500.0
## One entry per retained lake basin (LandformTerrainProvider.lake_basins()):
## world XZ bounds and fill height. Set by FoliageLocation before rebuild();
## empty = no lakes.
var lake_basins: Array[Dictionary] = []
## One entry per traced river (LandformTerrainProvider.river_paths()): a
## world-XZ polyline. Set by FoliageLocation before rebuild(); empty = no
## rivers. Needs `terrain` set too, to sample height along each ribbon.
var river_paths: Array[PackedVector2Array] = []
## Optional per-reach widths from imported vector data; procedural paths use
## WaterProfile.river_width when this array is empty.
var river_widths := PackedFloat32Array()
## Sampled on the rendered-ground lattice while building river meshes. Not
## needed for the sea or lakes, which never ask the ground anything.
var terrain: TerrainProvider
## Fitted OSM rivers and lakes (ImportedRivers.fit_to_terrain()). When set,
## their water is not drawn here: the ground meshes it chunk by chunk as one
## field (TerrainLayer.water_material, TerrainProvider.build_water_arrays()),
## out to `field_reach`. This layer adds each lake's whole surface beyond
## that, and the waterfalls. See docs/WATER.md, W5.
var imported_rivers: ImportedRivers
## Distance from the camera out to which the ground draws the water field;
## imported lakes' own meshes take over beyond it. 0 = no field: the lakes'
## meshes draw everywhere.
var field_reach: float = 0.0

var focus_point := Vector3.ZERO
var material: ShaderMaterial
## The sea's live level (SeaState), where follow() puts the plane. NAN until
## a SeaState sets it: the profile's sea_level.
var sea_level_now: float = NAN
## A real coastline with a coast field (ImportedSea.has_coast()): the sea
## gets the surf patch, a fine grid round the camera that carries the surf
## waves as geometry (docs/SEA_PLAN.md, SEA5). Set before rebuild().
var surf_patch: bool = false

const SEA_SUBDIVISIONS := 96
## The surf patch: drawn out to this many metres from the camera (the coarse
## sea plane takes over beyond), on a grid this fine, overlapping the
## handover by SURF_PATCH_MARGIN. The waves flatten out before the
## handover (water.gdshader, water_surf_patch), so it does not show.
const SURF_PATCH_RADIUS := 380.0
const SURF_PATCH_CELL := 4.0
const SURF_PATCH_MARGIN := 40.0
## Per lake quad. Lower than the sea's -- a basin is typically a fraction of
## the sea plane's reach, and this only needs enough resolution for the
## swell/ripple to read, not to resolve the shore precisely (that is what the
## depth-texture blend and the growth-mask cutoff are for).
const LAKE_SUBDIVISIONS := 24
## The nearby terrain mesh is the surface a river has to clear. It samples the
## provider on this world-aligned lattice (TerrainProvider.build_chunk_arrays),
## then interpolates within each of its triangles. Sampling the provider
## directly here would compare the river to a different, analytic surface and
## can still leave the actually rendered ground poking through it.
const RIVER_GROUND_SPACING := TerrainProvider.TILE_SPACING
## Long RiverTracer segments make long ribbon triangles. Checking only their
## corners is insufficient on rolling ground, so sample their interiors at no
## coarser a spacing than the rendered ground's own vertices.
const RIVER_INTERIOR_SAMPLE_SPACING := TerrainProvider.TILE_SPACING
## RiverTracer only needs a point every 24 m to follow a valley contour, but
## that is too long for one planar water triangle on undulating ground. Split
## its edge lines without changing the traced shape, keeping any subsequent
## interior correction local enough that it cannot lift a long reach of water
## above its banks.
const RIVER_MESH_STEP := TerrainProvider.TILE_SPACING * 3.0
## A waterfall curtain is this much wider than its river, metres either side,
## so its edges sink into the gorge walls.
const CURTAIN_OVERLAP := 0.4
## Waterfall curtains: rows down the arc, how far water at the river's flow
## speed is thrown before it lands (capped to the plunge pool), and how much
## the sheet spreads by the bottom.
const FALL_ROWS := 12
const FALL_SPREAD := 0.3
## Each fall's roar (assets/audio/waterfall_loop.wav, tools/audio): this loud
## for a REFERENCE_DROP fall, +/- per doubling of height, audible out to
## ROAR_RANGE plus ROAR_RANGE_PER_METRE of drop.
const ROAR_PATH := "res://assets/audio/waterfall_loop.wav"
const ROAR_VOLUME_DB := -4.0
const ROAR_REFERENCE_DROP := 20.0
const ROAR_RANGE := 60.0
const ROAR_RANGE_PER_METRE := 5.0

var _sea_instance: MeshInstance3D
var _surf_instance: MeshInstance3D
## The surf heard on the breaking line (SEA7), with the surf patch.
var surf_audio: SurfAudio
var _lake_instances: Array[MeshInstance3D] = []
var _river_instances: Array[MeshInstance3D] = []
var _imported_lake_instances: Array[MeshInstance3D] = []
## One node per waterfall, holding its curtain, spray and roar.
var _fall_nodes: Array[Node3D] = []


func rebuild() -> void:
	if material == null:
		material = ShaderMaterial.new()
		material.shader = load("res://foliage/shaders/water.gdshader")

	if profile != null and profile.sea_enabled:
		if _sea_instance == null:
			_sea_instance = MeshInstance3D.new()
			_sea_instance.name = "Sea"
			# The sea neither receives a useful shadow (it is flat and far
			# below most terrain) nor should cast one onto the ground under it.
			_sea_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Only the sea is clipped to a real coastline's reach (water.gdshader).
			_sea_instance.set_instance_shader_parameter("water_is_sea", 1.0)
			add_child(_sea_instance)
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * reach * 2.0
		plane.subdivide_width = SEA_SUBDIVISIONS
		plane.subdivide_depth = SEA_SUBDIVISIONS
		plane.material = material
		_sea_instance.mesh = plane
		_sea_instance.set_instance_shader_parameter("water_cut", Vector2(SURF_PATCH_RADIUS if surf_patch else 0.0, 0.0))
	elif _sea_instance != null:
		_sea_instance.queue_free()
		_sea_instance = null
	if profile != null and profile.sea_enabled and surf_patch:
		if _surf_instance == null:
			_surf_instance = MeshInstance3D.new()
			_surf_instance.name = "Surf"
			_surf_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_surf_instance.set_instance_shader_parameter("water_is_sea", 1.0)
			_surf_instance.set_instance_shader_parameter("water_cut", Vector2(0.0, SURF_PATCH_RADIUS))
			_surf_instance.set_instance_shader_parameter("water_surf_patch", SURF_PATCH_RADIUS)
			add_child(_surf_instance)
		var cells := int(ceil((SURF_PATCH_RADIUS + SURF_PATCH_MARGIN) * 2.0 / SURF_PATCH_CELL))
		var patch := PlaneMesh.new()
		patch.size = Vector2.ONE * cells * SURF_PATCH_CELL
		patch.subdivide_width = cells - 1
		patch.subdivide_depth = cells - 1
		patch.material = material
		_surf_instance.mesh = patch
		# Displaced up to a few metres: never culled by its flat bounds.
		_surf_instance.extra_cull_margin = 8.0
	elif _surf_instance != null:
		_surf_instance.queue_free()
		_surf_instance = null
	var coast_sea: ImportedSea = terrain.imported_sea if terrain is HeightmapTerrainProvider else null
	if _surf_instance != null and coast_sea != null and coast_sea.has_coast():
		if surf_audio == null:
			surf_audio = SurfAudio.new()
			surf_audio.name = "SurfAudio"
			add_child(surf_audio)
		surf_audio.sea = coast_sea
		surf_audio.terrain = terrain
		surf_audio.water = profile
	elif surf_audio != null:
		surf_audio.queue_free()
		surf_audio = null

	for instance in _lake_instances:
		instance.queue_free()
	_lake_instances.clear()
	for i in lake_basins.size():
		var basin: Dictionary = lake_basins[i]
		var bounds: Rect2 = basin["bounds"]
		var instance := MeshInstance3D.new()
		instance.name = "Lake_%d" % i
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var plane := PlaneMesh.new()
		plane.size = bounds.size
		plane.subdivide_width = LAKE_SUBDIVISIONS
		plane.subdivide_depth = LAKE_SUBDIVISIONS
		plane.material = material
		instance.mesh = plane
		instance.position = Vector3(
			bounds.position.x + bounds.size.x * 0.5, basin["level"], bounds.position.y + bounds.size.y * 0.5)
		add_child(instance)
		_lake_instances.append(instance)

	for instance in _river_instances:
		instance.queue_free()
	_river_instances.clear()
	# Fitted rivers are part of the ground's water field.
	if terrain != null and profile != null and imported_rivers == null:
		for i in river_paths.size():
			var path: PackedVector2Array = river_paths[i]
			if path.size() < 2:
				continue
			var instance := MeshInstance3D.new()
			instance.name = "River_%d" % i
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.material_override = material
			var width := river_widths[i] if i < river_widths.size() else profile.river_width
			instance.mesh = _build_river_mesh(path, width, profile.river_water_depth)
			add_child(instance)
			_river_instances.append(instance)

	# OSM lakes and reservoirs: one flat mesh each at its fitted level, in a
	# basin ImportedLakes has already carved, drawn only beyond field_reach
	# (nearer, the ground's water field holds them), in the field's shading
	# at rest (water_flow.z = 4) so the handover cannot be seen.
	for instance in _imported_lake_instances:
		instance.queue_free()
	_imported_lake_instances.clear()
	if imported_rivers != null:
		for i in imported_rivers.lakes.size():
			var instance := MeshInstance3D.new()
			instance.name = "ImportedLake_%d" % i
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.mesh = imported_rivers.lakes.build_mesh(i)
			instance.material_override = material
			instance.set_instance_shader_parameter("water_flow", Vector3(0.0, 0.0, 4.0))
			instance.set_instance_shader_parameter("water_cut", Vector2(field_reach, 0.0))
			add_child(instance)
			_imported_lake_instances.append(instance)

	# Waterfalls (W4.3): the water field leaves out each drop; a curtain
	# carries the water over it to the plunge pool, and spray rises where it
	# lands.
	for node in _fall_nodes:
		node.queue_free()
	_fall_nodes.clear()
	if imported_rivers != null and terrain != null and profile != null:
		for n in imported_rivers.falls.size():
			_build_fall(n)

	follow(focus_point)


func fall_count() -> int:
	return _fall_nodes.size()


func _build_fall(n: int) -> void:
	var fall: Dictionary = imported_rivers.falls[n]
	var path: PackedVector2Array = imported_rivers.paths[fall.path]
	var lip_index: int = fall.index
	var lip := path[lip_index]
	var direction := (path[lip_index + 1] - path[maxi(lip_index - 1, 0)]).normalized()
	var drop: float = fall.top - fall.bottom
	var half := imported_rivers.half_widths[fall.path] + CURTAIN_OVERLAP
	# Water leaving the lip at the river's speed, falling freely: it lands
	# speed * sqrt(2 h / g) out, but never beyond the pool carved for it.
	var throw := clampf(imported_rivers.flow_speed(fall.path) * sqrt(2.0 * drop / 9.81), 0.5, maxf(0.5, fall.pool * 0.6))
	var group := Node3D.new()
	group.name = "Waterfall_%d" % n
	add_child(group)
	_fall_nodes.append(group)
	var curtain := MeshInstance3D.new()
	curtain.name = "Curtain"
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curtain.mesh = _build_fall_mesh(Vector3(lip.x, fall.top, lip.y), direction, half, drop, throw)
	curtain.material_override = material
	# z = 2: falling water (water.gdshader). Streaks race down at about half
	# the speed water reaches by the bottom, so tall falls read as faster.
	curtain.set_instance_shader_parameter("water_flow",
		Vector3(clampf(sqrt(2.0 * 9.81 * drop) * 0.5, 3.0, 12.0), half * 2.0, 2.0))
	group.add_child(curtain)
	var landing := lip + direction * throw
	var spray := _build_spray(half, drop)
	spray.name = "Spray"
	spray.position = Vector3(landing.x, fall.bottom, landing.y)
	group.add_child(spray)
	var roar := _build_roar(drop, n)
	if roar != null:
		# From the middle of the curtain: the sound is the whole falling sheet
		# and its plunge, not the lip alone.
		var middle := lip.lerp(landing, 0.5)
		roar.position = Vector3(middle.x, (fall.top + fall.bottom) * 0.5, middle.y)
		group.add_child(roar)


## The fall's roar: louder, further-reaching and a touch deeper the taller the
## fall. Each starts at its own point in the loop with its own pitch, so a
## cascade's tiers (Giessbach has eleven within 500 m) do not play one loop in
## lockstep and comb-filter into a hum. Through the Weather bus, so it is
## muffled indoors like every other outdoor sound (WeatherAudio); without an
## atmosphere that bus does not exist and Godot plays it on Master.
static func _build_roar(drop: float, n: int) -> AudioStreamPlayer3D:
	if not ResourceLoader.exists(ROAR_PATH):
		push_error("Waterfall sound missing at %s -- run tools/audio/make_weather_audio.py" % ROAR_PATH)
		return null
	var roar := AudioStreamPlayer3D.new()
	roar.name = "Roar"
	roar.stream = load(ROAR_PATH)
	roar.bus = WeatherAudio.BUS
	var doublings := log(maxf(drop, 1.0) / ROAR_REFERENCE_DROP) / log(2.0)
	roar.volume_db = ROAR_VOLUME_DB + 3.0 * doublings
	roar.max_distance = ROAR_RANGE + drop * ROAR_RANGE_PER_METRE
	roar.unit_size = 4.0 + drop * 0.3
	roar.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	roar.pitch_scale = clampf(1.0 - 0.06 * doublings, 0.85, 1.15) * (0.96 + 0.08 * fposmod(n * 0.618, 1.0))
	# Started on entering the scene, each fall at its own point in the loop.
	roar.ready.connect(func() -> void: roar.play(fposmod(n * 3.7, 11.0)))
	return roar


## The falling sheet: a parabola from the lip (`lip`, at the water above)
## down `drop` metres, `throw` metres out along `direction`, spreading as it
## falls. Two-sided, since a fall is seen from below and beside. UV and
## vertex colour follow the river ribbon's contract (0..1 across, metres
## along the arc; rg = downstream, b = 1: all of it is white water).
func _build_fall_mesh(lip: Vector3, direction: Vector2, half: float, drop: float, throw: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var side_axis := Vector3(-direction.y, 0.0, direction.x)
	var outward := Vector3(direction.x, 0.0, direction.y)
	var colour := Color(direction.x * 0.5 + 0.5, direction.y * 0.5 + 0.5, 1.0, 1.0)
	var along := 0.0
	var previous := lip
	for row in FALL_ROWS + 1:
		var t := float(row) / float(FALL_ROWS)
		# Sink the foot a little into the pool so no seam shows where it lands.
		var centre := lip + outward * throw * t + Vector3.DOWN * (drop + 0.3) * t * t
		along += previous.distance_to(centre)
		previous = centre
		var tangent := (outward * throw + Vector3.DOWN * 2.0 * (drop + 0.3) * t).normalized()
		var normal := tangent.cross(side_axis).normalized()
		if normal.dot(outward + Vector3.UP) < 0.0:
			normal = -normal
		var spread := half * (1.0 + FALL_SPREAD * t)
		for side in 2:
			verts.push_back(centre + side_axis * spread * (1.0 - 2.0 * side))
			normals.push_back(normal)
			uvs.push_back(Vector2(float(side), along))
			colours.push_back(colour)
	for row in FALL_ROWS:
		var a := row * 2
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
		indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Spray where a fall lands: soft, unlit white puffs rising and drifting
## out of the pool, more of them (and bigger) the taller the fall.
static func _build_spray(half: float, drop: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = clampi(int(drop * 2.5), 16, 96)
	particles.lifetime = 3.0
	particles.preprocess = 3.0
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-half - 8.0, -1.0, -half - 8.0), Vector3(half * 2.0 + 16.0, drop * 0.5 + 10.0, half * 2.0 + 16.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = maxf(half, 1.0)
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.5 + clampf(drop * 0.08, 0.0, 3.0)
	process.gravity = Vector3(0.0, -0.3, 0.0)
	process.damping_min = 0.4
	process.damping_max = 0.8
	process.scale_min = 2.5
	process.scale_max = 4.0 + clampf(drop * 0.08, 0.0, 4.0)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.2, Color(1.0, 1.0, 1.0, 0.22))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	particles.process_material = process
	var puff := Gradient.new()
	# Soft all the way out: a hard rim reads as a ball, not as spray.
	puff.set_color(0, Color(1.0, 1.0, 1.0, 0.8))
	puff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	puff.add_point(0.45, Color(1.0, 1.0, 1.0, 0.3))
	var puff_texture := GradientTexture2D.new()
	puff_texture.gradient = puff
	puff_texture.fill = GradientTexture2D.FILL_RADIAL
	puff_texture.fill_from = Vector2(0.5, 0.5)
	puff_texture.fill_to = Vector2(0.5, 0.0)
	puff_texture.width = 64
	puff_texture.height = 64
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = puff_texture
	look.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.material = look
	particles.draw_pass_1 = quad
	return particles


func imported_lake_count() -> int:
	return _imported_lake_instances.size()


## A terrain-following ribbon along `path` (world XZ, subdivided more finely
## than RiverTracer's contour step), `width` wide, with `depth` metres of water
## above the carved bed.
## Built in world space directly (the mesh's own vertices ARE world
## positions, no node offset). Heights come from the nearby ground mesh's
## piecewise-planar surface, not the provider's unsampled analytic surface, so
## depth testing compares two geometries built from the same bed.
func _build_river_mesh(path: PackedVector2Array, width: float, depth: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var ground_cache := {}
	var half := width * 0.5
	var cross_subdivisions := maxi(1, ceili(width / RIVER_MESH_STEP))
	var row_size := cross_subdivisions + 1
	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()

	for i in path.size():
		# Tangent from both neighbours where they exist, so the ribbon does
		# not kink at interior vertices -- only the endpoints use a single
		# neighbour.
		var prev: Vector2 = path[i - 1] if i > 0 else path[i]
		var next: Vector2 = path[i + 1] if i < path.size() - 1 else path[i]
		var tangent := (next - prev)
		if tangent.length() < 0.0001:
			tangent = Vector2.RIGHT
		tangent = tangent.normalized()
		var perpendicular := Vector2(-tangent.y, tangent.x) * half
		var here: Vector2 = path[i]
		var left := here + perpendicular
		var right := here - perpendicular
		left_edge.push_back(left)
		right_edge.push_back(right)

	var distance_along := 0.0
	for i in path.size() - 1:
		var segment_length := maxf(
			left_edge[i].distance_to(left_edge[i + 1]),
			right_edge[i].distance_to(right_edge[i + 1]))
		var subdivisions := maxi(1, ceili(segment_length / RIVER_MESH_STEP))
		for part in subdivisions + 1:
			# The preceding segment already emitted this section, except at the
			# very start of the ribbon.
			if i > 0 and part == 0:
				continue
			var q := float(part) / float(subdivisions)
			var left := left_edge[i].lerp(left_edge[i + 1], q)
			var right := right_edge[i].lerp(right_edge[i + 1], q)
			if not verts.is_empty():
				var previous_centre := Vector2(
					(verts[verts.size() - row_size].x + verts[verts.size() - 1].x) * 0.5,
					(verts[verts.size() - row_size].z + verts[verts.size() - 1].z) * 0.5)
				distance_along += previous_centre.distance_to((left + right) * 0.5)
			for across in cross_subdivisions + 1:
				var u := float(across) / float(cross_subdivisions)
				var point := left.lerp(right, u)
				verts.push_back(Vector3(point.x,
					_rendered_ground_height(point.x, point.y, ground_cache) + depth, point.y))
				normals.push_back(Vector3.UP)
				uvs.push_back(Vector2(u, distance_along))

	var row_count := verts.size() / row_size
	for i in row_count - 1:
		for across in cross_subdivisions:
			var a := i * row_size + across
			var b := a + 1
			var c := a + row_size
			var d := c + 1
			# Winding matches TerrainProvider.build_chunk_arrays(): Godot culls
			# back faces, and this must face up (+Y), not down.
			indices.append_array([a, b, c, b, d, c])

	# A triangle can clear the bed at all three corners and still cut through a
	# rise between them. Lift each plane by its worst sampled shortfall. Shared
	# vertices only ever move upward, so correcting a later triangle cannot
	# invalidate one already checked.
	_raise_river_triangles_above_bed(verts, indices, depth, ground_cache)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Height of the actual nearby terrain mesh at a world XZ point. The ground's
## 64 m chunks and 48-quad near mesh share this global lattice exactly; this is
## TerrainTile.get_height() without allocating a tile spanning a whole river.
func _rendered_ground_height(x: float, z: float, cache: Dictionary) -> float:
	var fx := x / RIVER_GROUND_SPACING
	var fz := z / RIVER_GROUND_SPACING
	# The bias mirrors TerrainTile.covering(): decimal roundoff at an exact
	# lattice line must not select the cell on the other side.
	var ix := floori(fx + 0.0001)
	var iz := floori(fz + 0.0001)
	var tx := clampf(fx - float(ix), 0.0, 1.0)
	var tz := clampf(fz - float(iz), 0.0, 1.0)
	var h00 := _river_ground_lattice_height(ix, iz, cache)
	# Same diagonal as TerrainProvider.build_chunk_arrays()/TerrainTile.
	if tx + tz <= 1.0:
		return h00 \
			+ (_river_ground_lattice_height(ix + 1, iz, cache) - h00) * tx \
			+ (_river_ground_lattice_height(ix, iz + 1, cache) - h00) * tz
	var h11 := _river_ground_lattice_height(ix + 1, iz + 1, cache)
	return h11 \
		+ (_river_ground_lattice_height(ix, iz + 1, cache) - h11) * (1.0 - tx) \
		+ (_river_ground_lattice_height(ix + 1, iz, cache) - h11) * (1.0 - tz)


func _river_ground_lattice_height(ix: int, iz: int, cache: Dictionary) -> float:
	var key := Vector2i(ix, iz)
	if not cache.has(key):
		cache[key] = terrain.get_height(
			float(ix) * RIVER_GROUND_SPACING, float(iz) * RIVER_GROUND_SPACING)
	return cache[key]


func _raise_river_triangles_above_bed(
		verts: PackedVector3Array, indices: PackedInt32Array, depth: float, ground_cache: Dictionary) -> void:
	for offset in range(0, indices.size(), 3):
		var ia := indices[offset]
		var ib := indices[offset + 1]
		var ic := indices[offset + 2]
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		var longest := maxf(
			Vector2(a.x - b.x, a.z - b.z).length(),
			maxf(Vector2(b.x - c.x, b.z - c.z).length(), Vector2(c.x - a.x, c.z - a.z).length()))
		var steps := maxi(2, ceili(longest / RIVER_INTERIOR_SAMPLE_SPACING))
		var worst_shortfall := 0.0
		for ai in steps + 1:
			for bi in steps + 1 - ai:
				var wa := float(ai) / float(steps)
				var wb := float(bi) / float(steps)
				var wc := 1.0 - wa - wb
				var sample := a * wa + b * wb + c * wc
				var bed := _rendered_ground_height(sample.x, sample.z, ground_cache)
				worst_shortfall = maxf(worst_shortfall, bed + depth - sample.y)
		if worst_shortfall > 0.0:
			a.y += worst_shortfall
			b.y += worst_shortfall
			c.y += worst_shortfall
			verts[ia] = a
			verts[ib] = b
			verts[ic] = c


## Repositions the sea's plane under `focus`, at the live level
## (sea_level_now, else sea_level). Lake quads are not
## touched -- they are fixed in world space. The wave/ripple fields are
## computed from world position in the shader (world_vertex_coords), so
## moving the sea plane never shifts or seams its wave pattern: the same
## world point always gets the same wave phase regardless of where the
## mesh's own edges currently sit.
func follow(focus: Vector3) -> void:
	focus_point = focus
	if _sea_instance != null and profile != null:
		_sea_instance.position = Vector3(focus.x, profile.sea_level if is_nan(sea_level_now) else sea_level_now, focus.z)
	# Snapped to its own grid, so its vertices sit still in the world and
	# the waves do not swim as the camera moves.
	if _surf_instance != null and profile != null:
		_surf_instance.position = Vector3(snappedf(focus.x, SURF_PATCH_CELL), profile.sea_level if is_nan(sea_level_now) else sea_level_now,
			snappedf(focus.z, SURF_PATCH_CELL))
	if surf_audio != null and profile != null:
		surf_audio.listener = focus
		surf_audio.level = profile.sea_level if is_nan(sea_level_now) else sea_level_now
