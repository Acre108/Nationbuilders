extends RefCounted
## Simple vertex-coloured meshes using the imported environment's lighting.
const WORLD_MATERIAL = preload("res://render/world.gdshader")
const MedievalBuildings = preload("res://view/medieval_buildings.gd")
const GridChanges = preload("res://view/grid_changes.gd")
const CONTEXT_NEIGHBOURS := [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
var medieval: MedievalBuildings
var material := ShaderMaterial.new()
var mesh_cache: Dictionary = {}
var art = preload("res://view/village_art.tres")
var ground_material := ShaderMaterial.new()
var crop_material: ShaderMaterial
var roof_material: ShaderMaterial
var wall_material: ShaderMaterial
var door_material: ShaderMaterial
var window_material: ShaderMaterial
var terrain_node: MeshInstance3D
var patch_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var forest_cover_cache: Dictionary = {}
var context_grid
var context_revision := -1
var context_forest_revision := -1
var context_image: Image
var context_texture: ImageTexture
var context_changes := GridChanges.new()
## Recolouring the ground after a felling or planting only revisits nearby
## vertices: each top-face vertex is listed under the cell its colour samples.
var forest_ground_changes := GridChanges.new()
var ground_mesh: Mesh
var ground_arrays: Array = []
var ground_vertex_cells: Array[Dictionary] = []
var district_ground := {"tundra":Color("a0b2a8"), "marsh":Color("557e68"), "coast":Color("b9af77"), "mountain_pass":Color("818b76"), "highland_hills":Color("82965e")}

func _init(art_settings: Resource = null) -> void:
	if art_settings != null: art = art_settings
	material.shader = WORLD_MATERIAL
	art.apply_material(material)
	ground_material.shader = preload("res://render/village_ground.gdshader")
	art.apply_material(ground_material)
	ground_material.set_shader_parameter("ao_strength", art.ao_strength)
	ground_material.set_shader_parameter("water_glints", art.water_glints)
	crop_material = material.duplicate()
	crop_material.set_shader_parameter("village_crop", true)
	roof_material = material.duplicate()
	roof_material.set_shader_parameter("village_surface_kind",1)
	wall_material = material.duplicate()
	wall_material.set_shader_parameter("village_surface_kind",2)
	door_material = material.duplicate()
	door_material.set_shader_parameter("village_surface_kind",3)
	window_material = material.duplicate()
	window_material.set_shader_parameter("village_surface_kind",4)
	medieval = MedievalBuildings.new(self)
	patch_noise.seed = 7319
	patch_noise.frequency = 0.105
	patch_noise.fractal_octaves = 2
	detail_noise.seed = 719
	detail_noise.frequency = 0.24
	detail_noise.fractal_octaves = 1

func primitive(parent: Node3D, shape: PrimitiveMesh, color: Color, at: Vector3) -> MeshInstance3D:
	var arrays: Array = shape.get_mesh_arrays()
	var colors := PackedColorArray()
	colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
	colors.fill(color.srgb_to_linear())
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance

func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return primitive(parent,shape,color,at)

func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, top: float = -1.0) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = radius if top < 0.0 else top
	shape.height = height
	shape.radial_segments = 6
	shape.rings = 1
	return primitive(parent,shape,color,at)

func roof(parent: Node3D, center: Vector3, width: float, depth: float, height: float, color: Color) -> MeshInstance3D:
	var a := Vector3(-width/2,0,-depth/2)
	var b := Vector3(width/2,0,-depth/2)
	var c := Vector3(0,height,-depth/2)
	var d := Vector3(-width/2,0,depth/2)
	var e := Vector3(width/2,0,depth/2)
	var f := Vector3(0,height,depth/2)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in [[a,c,b],[d,e,f],[a,d,f],[a,f,c],[b,c,f],[b,f,e]]:
		var normal: Vector3 = (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
		# Godot's front faces use clockwise winding; retain outward normals.
		for vertex in [triangle[2],triangle[1],triangle[0]]:
			surface.set_color(color.srgb_to_linear())
			surface.set_normal(normal)
			surface.add_vertex(vertex)
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = roof_material
	instance.position = center
	parent.add_child(instance)
	return instance

func building(row: Dictionary, tier: int) -> Node3D:
	var detailed := medieval.building(row, tier)
	if detailed != null: return detailed
	var root := Node3D.new()
	var width := float(row.footprint[0])
	var depth := float(row.footprint[1])
	var color := Color.html(row.get("color","d8cdb4"))
	if row.id in ["house", "mill", "bakery"]: color = art.plaster_cream
	var dark := Color("513a2b")
	var roof_color: Color = art.roof_terracotta
	var contact := box(root,Vector3(0,0.015,0),Vector3(width+0.12,0.025,depth+0.12),Color("26392f").lerp(Color("65715a"), 1.0-art.ao_strength))
	contact.visible = art.ao_strength > 0.001
	box(root,Vector3(0,0.06,0),Vector3(width-0.08,0.12,depth-0.08),Color("756b54"))
	match row.id:
		"farm":
			box(root,Vector3(0,0.14,0),Vector3(width-0.25,0.12,depth-0.25),Color("4b4930"))
			for x in 7:
				for z in 4:
					var stalk := box(root,Vector3(-1.1+x*0.36,0.38,-0.62+z*0.4),Vector3(0.12,0.43,0.12),art.crop_gold.darkened(0.13 if z%2 else 0.0).lightened(float(x%3)*0.035))
					stalk.material_override = crop_material
			for z in [-0.9,0.9]:
				box(root,Vector3(0,0.3,z),Vector3(3,0.07,0.06),dark)
		"well":
			cylinder(root,Vector3(0,0.35,0),0.4,0.55,color)
			cylinder(root,Vector3(0,0.635,0),0.28,0.02,Color("3a93a1"))
			for x in [-0.34,0.34]:
				box(root,Vector3(x,0.9,0),Vector3(0.08,0.95,0.08),dark)
			roof(root,Vector3(0,1.36,0),1.0,0.85,0.3,roof_color)
			box(root,Vector3(0,1.345,0),Vector3(1.0,0.055,0.85),dark)
		"mill":
			cylinder(root,Vector3(0,1.15,0),0.64,2.2,color,0.42).material_override = wall_material
			cylinder(root,Vector3(0,2.43,0),0.67,0.65,roof_color,0.0)
			var sails := Node3D.new()
			sails.name = "Sails"
			sails.position = Vector3(0,1.95,0.66)
			root.add_child(sails)
			box(sails,Vector3.ZERO,Vector3(0.16,2.65,0.10),Color("e4dfd2"))
			box(sails,Vector3.ZERO,Vector3(2.65,0.16,0.10),Color("e4dfd2"))
			cylinder(root,Vector3(0.65,0.27,0.6),0.2,0.4,Color("b78a59"))
		_:
			var height := 1.25 if row.id == "storehouse" else (1.35 if tier > 1 else 0.95)
			box(root,Vector3(0,height/2+0.13,0),Vector3(width-0.38,height,depth-0.35),color).material_override = wall_material
			roof(root,Vector3(0,height+0.13,0),width-0.1,depth-0.08,0.72,roof_color if tier == 1 else Color("4b5057"))
			# Narrow eave shade and sunward roof rim follow existing roof edges.
			box(root,Vector3(0,height+0.11,0),Vector3(width-0.12,0.06,depth-0.09),Color("493b36"))
			box(root,Vector3(-(width-0.1)/2,height+0.15,0),Vector3(0.035,0.045,depth-0.08),roof_color.lightened(0.22) if tier == 1 else Color("79858a"))
			box(root,Vector3(0,0.50,depth/2-0.15),Vector3(0.40,0.72,0.08),dark).material_override = door_material
			for x in [-0.53,0.53]:
				box(root,Vector3(x,0.80,depth/2-0.13),Vector3(0.26,0.29,0.08),Color("9e7651")).material_override = window_material
			if row.id == "bakery":
				box(root,Vector3(0.55,1.85,-0.40),Vector3(0.32,1.2,0.32),Color("a39d90"))
				box(root,Vector3(0,0.48,1.02),Vector3(1.05,0.1,0.30),dark)
			if tier > 1 and row.kind == "house":
				box(root,Vector3(-0.78,0.3,1.03),Vector3(0.35,0.20,0.3),Color("5d7946"))
	medieval.add_stock_root(root, row)
	return root

func terrain(parent: Node3D, grid) -> void:
	forest_cover_cache.clear()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in grid.height:
		for x in grid.width:
			if not grid.inside(Vector2i(x,y)): continue
			var tile: String = grid.terrain_at(Vector2i(x,y))
			var color: Color = ground_colour(grid, Vector2(x+0.5,y+0.5))
			match tile:
				"water", "stream", "river", "lake", "ocean": color = art.water_turquoise
				"rock": color = Color("788573")
			var height := -0.08 if tile == "water" else 0.0
			for point in [Vector3(x,height,y),Vector3(x+1,height,y),Vector3(x,height,y+1),Vector3(x+1,height,y),Vector3(x+1,height,y+1),Vector3(x,height,y+1)]:
				surface.set_normal(Vector3.UP)
				surface.set_color((ground_colour(grid,Vector2(point.x,point.z)) if tile in ["grass","forest"] else color).srgb_to_linear())
				surface.add_vertex(point)
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = ground_material
	parent.add_child(mesh)
	terrain_node = mesh
	# Later forest changes recolour only around themselves, relative to this grid.
	forest_ground_changes = GridChanges.new()
	forest_ground_changes.update(grid)
	ground_mesh = null
	sync_ground_context(grid)
	# The relief mesh supplies masked outer walls. Legacy square fixtures retain
	# their historical soil base; generated hexes never show a rectangular slab.
	if not "footprint" in grid or not 0 in grid.footprint:
		box(parent,Vector3(grid.width/2.0,-0.65,grid.height/2.0),Vector3(grid.width,1.1,grid.height),Color("6b6152"))

func forest_cover(grid, point: Vector2) -> float:
	var cell := Vector2i(point.floor())
	if forest_cover_cache.has(cell): return forest_cover_cache[cell]
	var density := 0.0
	for z in range(-2,3):
		for x in range(-2,3):
			if grid.terrain_at(cell+Vector2i(x,z)) == "forest": density += 1.0
	var cover := smoothstep(0.08,0.48,density/25.0)
	forest_cover_cache[cell] = cover
	return cover

func ground_colour(grid, point: Vector2) -> Color:
	var patch := clampf(patch_noise.get_noise_2dv(point)*1.6+0.5,0.0,1.0)
	var base: Color = art.grass_shade.lerp(art.grass_sun, lerpf(0.5,patch,art.terrain_variation))
	var cell := Vector2i(point.floor())
	if grid.hex_width > 0.0 and grid.inside(cell):
		var owner: Vector2i = grid.owner_coords[cell.y * grid.width + cell.x]
		var district: Dictionary = grid.districts.get("%d,%d" % [owner.x,owner.y], {})
		if district_ground.has(district.get("biome", "")): base = base.lerp(district_ground[district.biome],0.24)
	return base.lerp(art.forest_floor, forest_cover(grid,point)*art.forest_darkness)

func detail_cell(grid, cell: Vector2i) -> bool:
	if art.meadow_detail_cover <= 0.0: return false
	var edge := false
	for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var neighbor: Vector2i = cell+direction
		if grid.occupied.has(neighbor) or grid.roads.has(neighbor) or grid.terrain_at(neighbor) in ["forest","rock"]: edge = true
	var patch := detail_noise.get_noise_2dv(Vector2(cell))*0.5+0.5
	var edge_spacing := maxi(2,roundi(1.0/maxf(art.meadow_detail_cover,0.001)))
	return patch > 1.0-art.meadow_detail_cover*1.4 or (edge and (cell.x*13+cell.y*7)%edge_spacing == 0)

func sync_ground_context(grid) -> void:
	if context_grid == grid and context_revision == grid.revision and context_forest_revision == grid.forest_revision: return
	forest_cover_cache.clear()
	var changed := context_changes.update(grid)
	var rebuild: bool = context_changes.reset or context_grid != grid or context_image == null
	context_grid = grid
	context_revision = grid.revision
	context_forest_revision = grid.forest_revision
	# Quarter-tile contact masks embed roads/buildings into the original ground.
	# A change reaches two cells away: forest cover samples a 5x5 neighbourhood.
	if not rebuild:
		for cell in GridChanges.around(changed,2,grid):
			_paint_context(grid,cell)
		if not changed.is_empty(): context_texture.update(context_image)
		return
	context_image = Image.create(grid.width*4,grid.height*4,false,Image.FORMAT_RGBA8)
	for y in grid.height:
		for x in grid.width:
			_paint_context(grid,Vector2i(x,y))
	context_texture = ImageTexture.create_from_image(context_image)
	ground_material.set_shader_parameter("ground_world_size",Vector2(grid.width,grid.height))
	ground_material.set_shader_parameter("ground_context",context_texture)

## The 4x4 context texels of one cell.
func _paint_context(grid, cell: Vector2i) -> void:
	var corner := cell*4
	if not grid.inside(cell):
		context_image.fill_rect(Rect2i(corner,Vector2i(4,4)),Color(0,0,0,0))
		return
	var water: bool = grid.is_water(cell)
	var near_works := false
	var shore := false
	for direction in CONTEXT_NEIGHBOURS:
		var nearby: Vector2i = cell+direction
		if grid.occupied.has(nearby) or grid.roads.has(nearby): near_works = true
		if water and not grid.is_water(nearby) and grid.inside(nearby): shore = true
	var detail := 1.0 if detail_cell(grid,cell) and not grid.occupied.has(cell) and not grid.roads.has(cell) else 0.0
	if not near_works and not shore:
		# Nothing nearby varies across the tile, so its texels share one value.
		context_image.fill_rect(Rect2i(corner,Vector2i(4,4)),Color(0,0,0.0 if water else forest_cover(grid,Vector2(cell)),detail))
		return
	for y in 4:
		for x in 4:
			var point := Vector2((corner.x+x+0.5)/4.0,(corner.y+y+0.5)/4.0)
			var edge := 0.0
			var contact := 0.0
			var shoreline := 0.0
			for direction in CONTEXT_NEIGHBOURS:
				var nearby: Vector2i = cell+direction
				if water and not grid.is_water(nearby) and grid.inside(nearby):
					var shore_distance := (point-point.clamp(Vector2(nearby),Vector2(nearby)+Vector2.ONE)).length()
					shoreline = maxf(shoreline,1.0-smoothstep(0.0,0.30,shore_distance))
				if not grid.occupied.has(nearby) and not grid.roads.has(nearby): continue
				var distance_to_rect := (point-point.clamp(Vector2(nearby),Vector2(nearby)+Vector2.ONE)).length()
				edge = maxf(edge,1.0-smoothstep(0.0,0.65,distance_to_rect))
				if grid.occupied.has(nearby): contact = maxf(contact,1.0-smoothstep(0.0,0.24,distance_to_rect))
			context_image.set_pixel(corner.x+x,corner.y+y,Color(contact,edge,shoreline if water else forest_cover(grid,point),detail))

func sync_forest_ground(grid) -> void:
	forest_cover_cache.clear()
	if not is_instance_valid(terrain_node): return
	var changed := forest_ground_changes.update(grid)
	# Recolour the existing relief geometry; retain heights, faces and water flags.
	# terrain() coloured it for the grid it recorded, so only tiles whose corner
	# colours read changed forest cover need repainting: cover samples 5x5 cells
	# around a corner, and a tile's corners reach one cell further.
	if ground_mesh != terrain_node.mesh: _index_ground_vertices()
	var cells: Array = []
	if forest_ground_changes.reset:
		for by_cell in ground_vertex_cells: cells.append_array(by_cell.keys())
	else:
		cells = GridChanges.around(changed,3,grid)
	var colour_at := {}
	var mesh := ArrayMesh.new()
	for surface in ground_arrays.size():
		var arrays: Array = ground_arrays[surface]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var by_cell: Dictionary = ground_vertex_cells[surface]
		for cell in cells:
			if not by_cell.has(cell) or grid.terrain_at(cell) not in ["grass","forest"]: continue
			for index in by_cell[cell]:
				var point := Vector2(vertices[index].x,vertices[index].z)
				if not colour_at.has(point): colour_at[point] = ground_colour(grid,point).srgb_to_linear()
				colours[index] = colour_at[point]
		arrays[Mesh.ARRAY_COLOR] = colours
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	terrain_node.mesh = mesh
	ground_mesh = mesh
	sync_ground_context(grid)

## Lists the land top-face vertices of the terrain mesh under the tile their
## triangle belongs to, which is the tile terrain() coloured them for.
func _index_ground_vertices() -> void:
	ground_arrays.clear()
	ground_vertex_cells.clear()
	for surface in terrain_node.mesh.get_surface_count():
		var arrays: Array = terrain_node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var flags: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var by_cell := {}
		for first in range(0,vertices.size()-2,3):
			var centroid := (vertices[first]+vertices[first+1]+vertices[first+2])/3.0
			var cell := Vector2i(floori(centroid.x),floori(centroid.z))
			for index in range(first,first+3):
				if normals[index].y <= 0.5 or (not flags.is_empty() and flags[index].x >= 0.5): continue
				if not by_cell.has(cell): by_cell[cell] = []
				by_cell[cell].append(index)
		ground_arrays.append(arrays)
		ground_vertex_cells.append(by_cell)

func road(parent: Node3D, cell: Vector2i, grid) -> void:
	var at := Vector3(cell.x+0.5,0.018,cell.y+0.5)
	box(parent,at,Vector3(0.995,0.035,0.995),art.path_ochre.darkened(0.22))
	box(parent,at+Vector3.UP*0.022,Vector3(0.88,0.018,0.88),art.path_ochre)
	# Wear is a quiet, slightly warmer centre. No new route geometry.
	box(parent,at+Vector3.UP*0.032,Vector3(0.48,0.009,0.72),art.path_ochre.lightened(0.055))
	if (cell.x*7+cell.y*13)%7 == 0:
		box(parent,at+Vector3(-0.27,0.045,0.24),Vector3(0.09,0.025,0.07),Color("8d825f"))
	for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if grid.roads.has(cell+direction): continue
		if (cell.x*3+cell.y*7+direction.x)%4 == 0:
			box(parent,at+Vector3(direction.x*0.44,0.044,direction.y*0.44),Vector3(0.10,0.03,0.13),art.grass_shade)
