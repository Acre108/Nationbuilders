extends Node3D
## SpacesOS meshes/materials placed against the authoritative village grid.
## All randomness is local to presentation; it never advances the sim RNG.
var profile := FoliageProfile.new()
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
				asset = "spruce" if (x*7+y*2)%5 < 2 else "oak"
				height = 2.0 + float((x*13+y*7)%5)*0.18
			elif tile == "rock":
				asset = "lake_boulder_1"
				height = 0.65
			if asset.is_empty(): continue
			var key := "%s:%.2f" % [asset,height]
			if not meshes.has(key):
				meshes[key] = NatureMeshBuilder.build(asset,height,profile,false,tile == "rock",false,height*NatureMeshBuilder.root_sink(asset) if tile == "forest" else 0.0)
				for surface in meshes[key].get_surface_count():
					var material: ShaderMaterial = meshes[key].surface_get_material(surface)
					art.apply_material(material)
			var plant := MeshInstance3D.new()
			plant.mesh = meshes[key]
			plant.position = Vector3(x+0.5,0.02+relief.cell_height(Vector2i(x,y)),y+0.5)
			plant.rotation.y = float((x*31+y*17)%360)*PI/180.0
			add_child(plant)
			plants[cell] = plant
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
	sync_grid(grid)

func sync_grid(grid) -> void:
	ground_factory.forest_cover_cache.clear()
	sync_trees(grid)
	for cell in plants:
		plants[cell].visible = not grid.occupied.has(cell) and not grid.roads.has(cell)
	var transforms: Array[Transform3D] = []
	var custom := PackedColorArray()
	var shadows: Array[Transform3D] = []
	var accent_transforms: Array = [[],[],[]]
	detailed_meadow_cells = 0
	meadow_cells = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.world_seed
	for y in grid.height:
		for x in grid.width:
			var cell := Vector2i(x,y)
			var lift: float = relief.cell_height(cell)
			if plants.has(cell) and plants[cell].visible:
				var span := 0.9 if grid.terrain_at(cell) == "forest" else 0.75
				shadows.append(Transform3D(Basis.IDENTITY.scaled(Vector3(span,1,span)),Vector3(x+0.5,0.012+lift,y+0.5)))
			# About 80% of meadow cells are quiet; detail lives in irregular patches.
			var keep: bool = ground_factory.detail_cell(grid,cell)
			if grid.terrain_at(cell) == "grass" and not grid.occupied.has(cell) and not grid.roads.has(cell):
				meadow_cells += 1
				if keep:
					detailed_meadow_cells += 1
					if float((x*71+y*19)%100)/100.0 < art.flower_patch_density:
						for offset in [Vector2.ZERO,Vector2(0.13,0.02),Vector2(-0.08,0.11)]:
							accent_transforms[0].append(Transform3D(Basis.IDENTITY,Vector3(x+0.36+offset.x,0.18+lift,y+0.62+offset.y)))
					if (x*71+y*19)%11 == 0:
						var kind: int = 1+(x*17+y*7)%2
						accent_transforms[kind].append(Transform3D(Basis.IDENTITY,Vector3(x+0.52,0.04+lift,y+0.42)))
			# Draws are consumed for every cell so construction doesn't reshuffle grass.
			for tuft in 3:
				var at := Vector3(x+rng.randf_range(0.12,0.88),0.025,y+rng.randf_range(0.12,0.88))
				var basis := Basis(Vector3.UP,rng.randf()*TAU)
				var data := Color(rng.randf(),rng.randf(),rng.randf(),1.0)
				data.g = ground_factory.forest_cover(grid,Vector2(x+0.5,y+0.5))
				if grid.terrain_at(cell) not in ["grass","forest"] or grid.occupied.has(cell) or grid.roads.has(cell): continue
				if not keep: continue
				for density in art.grass_patch_density:
					# Additional shoots stay clustered around the original seeded root.
					var offset := Vector3(0.09*density,0.0,-0.065*density)
					var clustered_at := at+offset
					clustered_at.x = clampf(clustered_at.x,x+0.06,x+0.94)
					clustered_at.z = clampf(clustered_at.z,y+0.06,y+0.94)
					clustered_at.y += relief.surface_height(Vector2(clustered_at.x,clustered_at.z))
					transforms.append(Transform3D(basis,clustered_at))
					custom.append(data)
	grass.multimesh = FoliageMultiMesh.build(grass_mesh,transforms,custom,Vector3.ZERO)
	var shadow_custom := PackedColorArray()
	shadow_custom.resize(shadows.size())
	shadow_custom.fill(Color.WHITE)
	contact.multimesh = FoliageMultiMesh.build(contacts_mesh,shadows,shadow_custom,Vector3.ZERO)
	for i in accents.size():
		var transforms_for_kind: Array[Transform3D] = []
		transforms_for_kind.assign(accent_transforms[i])
		var data := PackedColorArray()
		data.resize(transforms_for_kind.size())
		data.fill(Color.WHITE)
		accents[i].multimesh = FoliageMultiMesh.build(accent_meshes[i],transforms_for_kind,data,Vector3.ZERO)

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
				var asset := "spruce" if (cell.x*7+cell.y*2)%5 < 2 else "oak"
				var height := 2.0 + float((cell.x*13+cell.y*7)%5)*0.18
				var key := "%s:%.2f" % [asset,height]
				if not meshes.has(key):
					meshes[key] = NatureMeshBuilder.build(asset,height,profile,false,false,false,height*NatureMeshBuilder.root_sink(asset))
					for surface in meshes[key].get_surface_count(): art.apply_material(meshes[key].surface_get_material(surface))
				var plant := MeshInstance3D.new()
				plant.mesh = meshes[key]
				plant.position = Vector3(cell.x+0.5,0.02+relief.cell_height(cell),cell.y+0.5)
				plant.rotation.y = float((cell.x*31+cell.y*17)%360)*PI/180.0
				add_child(plant)
				plants[cell] = plant
			plants[cell].scale = Vector3.ONE * (0.28 if grid.saplings.has(cell) else 1.0)
	for cell in stump_nodes.keys():
		if not grid.stumps.has(cell):
			var removed: Node3D = stump_nodes[cell]
			remove_child(removed)
			removed.queue_free()
			stump_nodes.erase(cell)
	for cell in grid.stumps:
		if stump_nodes.has(cell): continue
		var stump: MeshInstance3D = ground_factory.cylinder(self,Vector3(cell.x+0.5,0.12+relief.cell_height(cell),cell.y+0.5),0.16,0.22,Color("98724d"))
		stump_nodes[cell] = stump

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
