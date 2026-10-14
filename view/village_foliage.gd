extends Node3D
const IntNoise = preload("res://sim/world/int_noise.gd")
const GridChanges = preload("res://view/grid_changes.gd")
## SpacesOS meshes/materials placed against the authoritative village grid.
## All randomness is local to presentation; it never advances the sim RNG.
var profile := FoliageProfile.new()
## Camera zoom (orthographic size) from which trees draw their far LOD.
const FAR_TREE_ZOOM := 32.0
var far_meshes: Dictionary = {}
var far_trees := false
## Ground cover is kept as packed MultiMesh rows per cell, so a road or felled
## tree repacks only its neighbourhood. The joined buffers match a full rebuild.
var changes := GridChanges.new()
## Seeded draws for each cell's three tufts: x, z, angle, r, g, b.
var tuft_draws := PackedFloat64Array()
var grass_rows: Array[PackedFloat32Array] = []
var shadow_rows: Array[PackedFloat32Array] = []
var accent_rows: Array = []
## Per cell: 1 = open meadow, 2 = detailed meadow.
var meadow_flags := PackedByteArray()
var grass: MultiMeshInstance3D
var grass_mesh: ArrayMesh
var meshes: Dictionary = {}
var plants: Dictionary = {}
var stump_nodes: Dictionary = {}
var art = preload("res://view/village_art.tres")
var contact: MultiMeshInstance3D
var contacts_mesh := PlaneMesh.new()
var motes: Array[MeshInstance3D] = []
var mote_lives: Array[float] = []
var ambience_time := 0.0
var mote_accumulator := 0.0
var next_mote := 3.0
var ambience_rng := RandomNumberGenerator.new()
var ambience_bounds := Rect2(11,13,19,14)
var wind_source: AtmosphereSystem
var ground_factory
## Ground heights for the current grid; set by build().
var relief
var accents: Array[MultiMeshInstance3D] = []
var accent_meshes: Array[ArrayMesh] = []
var detailed_meadow_cells := 0
var meadow_cells := 0
var patch_tuft_count: int:
	get: return 3*art.grass_patch_density

func _init(art_settings: Resource = null) -> void:
	if art_settings != null: art = art_settings
	ground_factory = preload("res://view/mesh_factory.gd").new(art)
	profile.location_name = "Hearthlands"
	profile.world_seed = 73
	profile.haze_amount = 0.0
	profile.distance_tint_strength = 0.0
	profile.wind_strength = art.wind_strength
	profile.wind_speed = art.wind_speed
	profile.wind_direction = art.wind_direction
	profile.grass_palette = PackedColorArray([Color("3b5b4b"),Color("687d52"),Color("8c9d54"),Color("a8b265"),Color("bdc279")])
	profile.translucency = 0.08
	profile.tree_translucency = 0.025
	profile.tree_flutter = 0.0
	profile.wind_colour_shift = 0.025
	ambience_rng.seed = 7341
	contacts_mesh.size = Vector2.ONE
	var shadow := ShaderMaterial.new()
	shadow.shader = preload("res://render/contact_shadow.gdshader")
	shadow.set_shader_parameter("ao_strength", art.ao_strength)
	contacts_mesh.material = shadow
	profile.clump_style = FoliageProfile.ClumpStyle.BLADE_FLAT
	# Use the source profile's meadow palette on both terrain and blade materials.
	var config := GrassTuftBuilder.TuftConfig.flat_meadow()
	config.height = 0.30
	config.width = 0.065
	config.blade_count = 5
	config.segments = 2
	grass_mesh = GrassTuftBuilder.build_tuft(config,73)
	var material := ShaderMaterial.new()
	material.shader = preload("res://foliage/shaders/grass.gdshader")
	var terrain_material := ShaderMaterial.new()
	terrain_material.shader = preload("res://foliage/shaders/terrain.gdshader")
	profile.apply_to_materials(material,terrain_material)
	art.apply_material(material)
	material.set_shader_parameter("grass_sprite_mode",false)
	material.set_shader_parameter("grass_lod_band",0)
	grass_mesh.surface_set_material(0,material)

func build(grid) -> void:
	relief = preload("res://view/terrain_relief.gd").new(grid)
	if grid.settlement_clearance.has_area():
		ambience_bounds = Rect2(grid.settlement_clearance)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	plants.clear()
	stump_nodes.clear()
	accents.clear()
	accent_meshes.clear()
	motes.clear()
	mote_lives.clear()
	ambience_time = 0.0
	mote_accumulator = 0.0
	next_mote = 3.0
	ambience_rng.seed = 7341
	for y in grid.height:
		for x in grid.width:
			var cell := Vector2i(x,y)
			var tile: String = grid.terrain_at(cell)
			var asset := ""
			var height := 1.0
			if grid.trees.has(cell) or grid.saplings.has(cell):
				asset = _tree_asset(grid, cell)
				height = _tree_height(grid, cell)
			elif tile == "rock":
				asset = "lake_boulder_1"
				height = 0.65
			if asset.is_empty(): continue
			var key := "%s:%.2f" % [asset,height]
			if not meshes.has(key):
				_build_meshes(key,asset,height,tile == "rock",height*NatureMeshBuilder.root_sink(asset) if tile == "forest" else 0.0)
			_add_plant(grid,cell,key)
	grass = MultiMeshInstance3D.new()
	grass.name = "Grass"
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)
	contact = MultiMeshInstance3D.new()
	contact.name = "RootContactShadows"
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(contact)
	var accent_sizes := [Vector3(0.08,0.065,0.08),Vector3(0.14,0.012,0.09),Vector3(0.11,0.065,0.08)]
	var accent_colours := [Color("e5c787"),Color("736744"),Color("858876")]
	for i in 3:
		var temporary := Node3D.new()
		var mesh: ArrayMesh = ground_factory.box(temporary,Vector3.ZERO,accent_sizes[i],accent_colours[i]).mesh
		mesh.surface_set_material(0,ground_factory.material)
		temporary.free()
		accent_meshes.append(mesh)
		var accent := MultiMeshInstance3D.new()
		accent.name = ["TinyFlowers","EarthFlecks","Pebbles"][i]
		accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(accent)
		accents.append(accent)
	_build_motes()
	changes = GridChanges.new()
	sync_grid(grid)

func sync_grid(grid) -> void:
	ground_factory.forest_cover_cache.clear()
	sync_trees(grid)
	for cell in plants:
		plants[cell].visible = not grid.occupied.has(cell) and not grid.roads.has(cell)
	var changed := changes.update(grid)
	var cells: Array[Vector2i] = []
	if changes.reset:
		_reset_rows(grid)
		for y in grid.height:
			for x in grid.width:
				cells.append(Vector2i(x,y))
	else:
		# Tufts read forest cover two cells away and meadow detail one away.
		cells = GridChanges.around(changed,2,grid)
	if cells.is_empty() and grass.multimesh != null: return
	for cell in cells: _sync_cell(grid,cell)
	grass.multimesh = _rows_multimesh(grass_mesh,grass_rows)
	contact.multimesh = _rows_multimesh(contacts_mesh,shadow_rows)
	for i in accents.size():
		accents[i].multimesh = _rows_multimesh(accent_meshes[i],accent_rows[i])

func _reset_rows(grid) -> void:
	var count: int = grid.width*grid.height
	for rows in [grass_rows,shadow_rows]:
		rows.clear()
		rows.resize(count)
	accent_rows.clear()
	for i in 3:
		var rows: Array[PackedFloat32Array] = []
		rows.resize(count)
		accent_rows.append(rows)
	meadow_flags = PackedByteArray()
	meadow_flags.resize(count)
	meadow_cells = 0
	detailed_meadow_cells = 0
	# Draws are consumed for every cell so construction doesn't reshuffle grass.
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.world_seed
	tuft_draws.resize(count*18)
	for index in range(0,count*18,6):
		tuft_draws[index] = rng.randf_range(0.12,0.88)
		tuft_draws[index+1] = rng.randf_range(0.12,0.88)
		tuft_draws[index+2] = rng.randf()*TAU
		tuft_draws[index+3] = rng.randf()
		tuft_draws[index+4] = rng.randf()
		tuft_draws[index+5] = rng.randf()

func _sync_cell(grid, cell: Vector2i) -> void:
	var x := cell.x
	var y := cell.y
	var index: int = y*grid.width+x
	var lift: float = relief.cell_height(cell)
	var shadows: Array[Transform3D] = []
	if plants.has(cell) and plants[cell].visible:
		var span := 0.9 if grid.terrain_at(cell) == "forest" else 0.75
		var root: Vector3 = plants[cell].position
		shadows.append(Transform3D(Basis.IDENTITY.scaled(Vector3(span,1,span)),root - Vector3.UP * 0.008))
	shadow_rows[index] = _pack(shadows)
	# About 80% of meadow cells are quiet; detail lives in irregular patches.
	var keep: bool = ground_factory.detail_cell(grid,cell)
	var accent_transforms: Array = [[],[],[]]
	var flags := 0
	if grid.terrain_at(cell) == "grass" and not grid.occupied.has(cell) and not grid.roads.has(cell):
		flags = 1
		if keep:
			flags = 3
			if float((x*71+y*19)%100)/100.0 < art.flower_patch_density:
				for offset in [Vector2.ZERO,Vector2(0.13,0.02),Vector2(-0.08,0.11)]:
					accent_transforms[0].append(Transform3D(Basis.IDENTITY,Vector3(x+0.36+offset.x,0.18+lift,y+0.62+offset.y)))
			if (x*71+y*19)%11 == 0:
				var kind: int = 1+(x*17+y*7)%2
				accent_transforms[kind].append(Transform3D(Basis.IDENTITY,Vector3(x+0.52,0.04+lift,y+0.42)))
	meadow_cells += (flags & 1) - (meadow_flags[index] & 1)
	detailed_meadow_cells += (flags >> 1) - (meadow_flags[index] >> 1)
	meadow_flags[index] = flags
	for i in 3:
		var transforms_for_kind: Array[Transform3D] = []
		if not accent_transforms[i].is_empty(): transforms_for_kind.assign(accent_transforms[i])
		accent_rows[i][index] = _pack(transforms_for_kind)
	var transforms: Array[Transform3D] = []
	var custom := PackedColorArray()
	if keep and grid.terrain_at(cell) in ["grass","forest"] and not grid.occupied.has(cell) and not grid.roads.has(cell):
		var cover: float = ground_factory.forest_cover(grid,Vector2(x+0.5,y+0.5))
		for tuft in 3:
			var draw := (index*3+tuft)*6
			var at := Vector3(x+tuft_draws[draw],0.025,y+tuft_draws[draw+1])
			var basis := Basis(Vector3.UP,tuft_draws[draw+2])
			var data := Color(tuft_draws[draw+3],tuft_draws[draw+4],tuft_draws[draw+5],1.0)
			data.g = cover
			for density in art.grass_patch_density:
				# Additional shoots stay clustered around the original seeded root.
				var offset := Vector3(0.09*density,0.0,-0.065*density)
				var clustered_at := at+offset
				clustered_at.x = clampf(clustered_at.x,x+0.06,x+0.94)
				clustered_at.z = clampf(clustered_at.z,y+0.06,y+0.94)
				clustered_at.y += relief.surface_height(Vector2(clustered_at.x,clustered_at.z))
				transforms.append(Transform3D(basis,clustered_at))
				custom.append(data)
	grass_rows[index] = FoliageMultiMesh.pack(transforms,custom,Vector3.ZERO) if not transforms.is_empty() else PackedFloat32Array()

## Contact shadows and accents use white custom data.
func _pack(transforms: Array[Transform3D]) -> PackedFloat32Array:
	if transforms.is_empty(): return PackedFloat32Array()
	var custom := PackedColorArray()
	custom.resize(transforms.size())
	custom.fill(Color.WHITE)
	return FoliageMultiMesh.pack(transforms,custom,Vector3.ZERO)

func _rows_multimesh(mesh: Mesh, rows: Array) -> MultiMesh:
	var buffer := PackedFloat32Array()
	for row in rows:
		if not row.is_empty(): buffer.append_array(row)
	return FoliageMultiMesh.from_buffer(mesh,buffer.size()/16,buffer)

## Reuse shared mature meshes; a small scale makes young trees readable saplings.
func sync_trees(grid) -> void:
	for cell in plants.keys():
		if grid.terrain_at(cell) == "rock": continue
		if not grid.trees.has(cell) and not grid.saplings.has(cell):
			var removed: Node3D = plants[cell]
			remove_child(removed)
			removed.queue_free()
			plants.erase(cell)
	for collection in [grid.trees,grid.saplings]:
		for cell in collection:
			if not plants.has(cell):
				var asset := _tree_asset(grid, cell)
				var height := _tree_height(grid, cell)
				var key := "%s:%.2f" % [asset,height]
				if not meshes.has(key):
					_build_meshes(key,asset,height,false,height*NatureMeshBuilder.root_sink(asset))
				_add_plant(grid,cell,key)
			plants[cell].scale = Vector3.ONE * (0.28 if grid.saplings.has(cell) else 1.0)
	for cell in stump_nodes.keys():
		if not grid.stumps.has(cell):
			var removed: Node3D = stump_nodes[cell]
			remove_child(removed)
			removed.queue_free()
			stump_nodes.erase(cell)
	for cell in grid.stumps:
		if stump_nodes.has(cell): continue
		var stump: MeshInstance3D = ground_factory.cylinder(self,_plant_position(grid,cell) + Vector3.UP * 0.10,0.16,0.22,Color("98724d"))
		stump_nodes[cell] = stump

## Each tree also gets the pack's authored far LOD: about half the triangles,
## with a slightly thinner crown. It always casts the tree's shadow, which
## looks the same, and is drawn instead of the full tree when zoomed out.
func _build_meshes(key: String, asset: String, height: float, rock: bool, sink: float) -> void:
	meshes[key] = NatureMeshBuilder.build(asset,height,profile,false,rock,false,sink)
	for surface in meshes[key].get_surface_count(): art.apply_material(meshes[key].surface_get_material(surface))
	if rock: return
	far_meshes[key] = NatureMeshBuilder.build(asset,height,profile,true,false,true,sink)
	for surface in far_meshes[key].get_surface_count(): art.apply_material(far_meshes[key].surface_get_material(surface))

func _add_plant(grid, cell: Vector2i, key: String) -> void:
	var plant := MeshInstance3D.new()
	plant.mesh = far_meshes[key] if far_trees and far_meshes.has(key) else meshes[key]
	plant.position = _plant_position(grid, cell)
	plant.rotation.y = float((cell.x*31+cell.y*17)%360)*PI/180.0
	plant.set_meta("mesh_key",key)
	if far_meshes.has(key):
		plant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shadow := MeshInstance3D.new()
		shadow.name = "ShadowProxy"
		shadow.mesh = far_meshes[key]
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		plant.add_child(shadow)
	add_child(plant)
	plants[cell] = plant

## Draws the far LOD for every tree while the camera is zoomed out.
func set_far_trees(enabled: bool) -> void:
	if enabled == far_trees: return
	far_trees = enabled
	for plant in plants.values():
		var key: String = plant.get_meta("mesh_key","")
		if far_meshes.has(key): plant.mesh = far_meshes[key] if enabled else meshes[key]
	# Materials only receive wind changes while they are in the scene.
	if is_instance_valid(wind_source): wind_source._push_wind()

func _district(grid, cell: Vector2i) -> Dictionary:
	if grid.hex_width <= 0.0 or not grid.inside(cell): return {}
	var owner: Vector2i = grid.owner_coords[cell.y * grid.width + cell.x]
	return grid.districts.get("%d,%d" % [owner.x,owner.y], {})

func _tree_asset(grid, cell: Vector2i) -> String:
	var district := _district(grid,cell)
	if district.is_empty(): return "spruce" if (cell.x*7+cell.y*2)%5 < 2 else "oak"
	var roll := IntNoise.unit(7341,cell.x,cell.y,341)
	if district.biome in ["tundra","mountain_pass","highland_hills"] or district.temperature < 0.35:
		return "spruce" if roll < 0.7 else "pine"
	if district.biome == "marsh": return "birch_2"
	return "oak" if roll < 0.8 else "birch_2"

func _tree_height(grid, cell: Vector2i) -> float:
	if grid.hex_width <= 0.0: return 2.0 + float((cell.x*13+cell.y*7)%5)*0.18
	return 2.0 + float(IntNoise.mix(7341,cell.x,cell.y,343) % 5) * 0.18

func _plant_position(grid, cell: Vector2i) -> Vector3:
	var point := Vector2(cell) + Vector2(0.5,0.5)
	if grid.hex_width > 0.0:
		# Keep each root in its authoritative command cell while breaking rows.
		point += Vector2(IntNoise.unit(7341,cell.x,cell.y,347)-0.5,IntNoise.unit(7341,cell.x,cell.y,349)-0.5) * 0.55
	return Vector3(point.x,0.02 + relief.surface_height(point),point.y)

func _build_motes() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color("d9c98b")
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.065,0.065)
	mesh.material = material
	for i in 8:
		var mote := MeshInstance3D.new()
		mote.name = "Seed%d" % i
		mote.mesh = mesh
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mote.visible = false
		add_child(mote)
		motes.append(mote)
		mote_lives.append(0.0)

func sync_growth(grid, tick: int) -> void:
	for cell in grid.saplings:
		if plants.has(cell):
			var growth := clampf(1.0-float(int(grid.saplings[cell])-tick)/600.0,0.0,1.0)
			plants[cell].scale = Vector3.ONE * lerpf(0.28,1.0,growth)

func _process(delta: float) -> void:
	ambience_time += minf(delta,0.1)
	mote_accumulator += minf(delta,0.1)
	var daylight := wind_source.frame.daylight if is_instance_valid(wind_source) and wind_source.frame != null else 1.0
	if daylight <= 0.2 or art.particle_density <= 0.0:
		for mote in motes: mote.visible = false
	if mote_accumulator < 0.125: return
	var step := mote_accumulator
	mote_accumulator = 0.0
	var wind: Vector2 = art.wind_direction.normalized()
	for i in motes.size():
		if mote_lives[i] <= 0.0: continue
		var strength: float = wind_source.wind_at(motes[i].position) if is_instance_valid(wind_source) else 1.0
		mote_lives[i] -= step
		motes[i].position += Vector3(wind.x,-0.04,wind.y)*step*art.wind_strength*4.0*strength
		motes[i].visible = mote_lives[i] > 0.0 and art.particle_density > 0.0 and daylight > 0.2
	if ambience_time >= next_mote and art.particle_density > 0.0 and daylight > 0.2:
		next_mote = ambience_time+ambience_rng.randf_range(0.8,1.8)/art.particle_density
		for i in motes.size():
			if mote_lives[i] > 0.0: continue
			motes[i].position = Vector3(ambience_rng.randf_range(ambience_bounds.position.x,ambience_bounds.end.x),ambience_rng.randf_range(0.5,2.2),ambience_rng.randf_range(ambience_bounds.position.y,ambience_bounds.end.y))
			mote_lives[i] = ambience_rng.randf_range(3.0,6.0)
			motes[i].visible = true
			break
