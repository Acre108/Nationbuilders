extends Node3D
## The food overlay (F7): what the land can feed.
## - Gold tiles: fertile soil, where fields work at full speed.
## - Red marks: wild berry bushes, larger the more ripe fruit they hold.
## - Blue tiles: the fishing shore, water a fisher's hut can stand beside.
## - Labels: the deer and boar living in each range (sim/wildlife.gd).
## Each layer is one mesh, rebuilt only when what it shows changes.
const FERTILE := Color(0.96, 0.62, 0.06, 0.5)
const SHORE := Color(0.32, 0.64, 0.88, 0.55)
const BERRY := Color(0.86, 0.16, 0.32, 0.95)
const FISHING := ["water", "river", "lake", "ocean"]
var grid
var relief
var material := StandardMaterial3D.new()
var land := MeshInstance3D.new()
var berries := MeshInstance3D.new()
var game := Node3D.new()
var land_signature := ""
var berry_signature := ""
var game_signature := ""

func _init() -> void:
	name = "FoodOverlay"
	visible = false
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for node in [land, berries]:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = material
		add_child(node)
	game.name = "Game"
	add_child(game)

## A new site: everything is rebuilt on the next sync.
func build(site_grid, terrain_relief) -> void:
	grid = site_grid
	relief = terrain_relief
	land_signature = ""
	berry_signature = ""
	game_signature = ""

func sync(sim) -> void:
	if not visible or grid == null:
		return
	var next := "%d|%d" % [grid.revision, grid.forest_revision]
	if next != land_signature:
		land_signature = next
		_build_land()
	next = _berry_key(sim.forage)
	if next != berry_signature:
		berry_signature = next
		_build_berries(sim.forage)
	next = "%s|%s" % [str(sim.wildlife.herds.deer), str(sim.wildlife.herds.boar)]
	if next != game_signature:
		game_signature = next
		_build_game(sim.wildlife)

func _berry_key(forage) -> String:
	var sum := 0
	for cell in forage.bushes:
		sum += (int(forage.bushes[cell]) + 1) * (cell.x * 92821 + cell.y * 68917 + 1)
	return "%d|%d" % [forage.bushes.size(), sum]

## Fertile soil and the fishing shore.
func _build_land() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for y in grid.height:
		for x in grid.width:
			var cell := Vector2i(x, y)
			if not grid.in_reach(cell):
				continue
			if grid.deposits[y * grid.width + x] == "fertile_soil" and grid.terrain_at(cell) == "grass" and not grid.occupied.has(cell) and not grid.roads.has(cell):
				_square(tool, Vector2(cell) + Vector2(0.5, 0.5), 0.92, FERTILE)
				count += 1
			elif grid.terrain_at(cell) in FISHING and _beside_land(cell):
				_square(tool, Vector2(cell) + Vector2(0.5, 0.5), 0.92, SHORE)
				count += 1
	land.mesh = tool.commit() if count > 0 else null

func _beside_land(cell: Vector2i) -> bool:
	for direction in grid.DIRECTIONS:
		var other: Vector2i = cell + direction
		if grid.in_reach(other) and not grid.is_water(other):
			return true
	return false

func _build_berries(forage) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in forage.bushes:
		var fruit: int = forage.bushes[cell]
		var colour := BERRY if fruit > 0 else Color(0.45, 0.32, 0.30, 0.8)
		_square(tool, Vector2(cell) + Vector2(0.5, 0.5), 0.3 + 0.15 * fruit, colour, 0.5)
	berries.mesh = tool.commit() if not forage.bushes.is_empty() else null

## A count above each range that has game: "3 deer · 2 boar".
func _build_game(wildlife) -> void:
	for child in game.get_children():
		child.queue_free()
	for index in wildlife.range_count():
		var deer: int = wildlife.herds.deer[index]
		var boar: int = wildlife.herds.boar[index]
		if deer + boar == 0:
			continue
		var parts: Array[String] = []
		if deer > 0: parts.append("%d deer" % deer)
		if boar > 0: parts.append("%d boar" % boar)
		var label := Label3D.new()
		label.text = " · ".join(parts)
		var centre: Vector2 = wildlife.centre(index)
		label.position = Vector3(centre.x, relief.surface_height(centre) + 1.6, centre.y)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0015
		label.font_size = 30
		label.outline_size = 8
		label.modulate = Color("f3e6c4")
		label.outline_modulate = Color("3a2a1c")
		game.add_child(label)

## A flat square marker on the ground at a tile point.
func _square(tool: SurfaceTool, point: Vector2, size: float, colour: Color, lift: float = 0.06) -> void:
	var half := size * 0.5
	var y: float = relief.surface_height(point) + lift
	var a := Vector3(point.x - half, y, point.y - half)
	var b := Vector3(point.x + half, y, point.y - half)
	var c := Vector3(point.x + half, y, point.y + half)
	var d := Vector3(point.x - half, y, point.y + half)
	tool.set_color(colour)
	for vertex in [a, b, c, a, c, d]:
		tool.add_vertex(vertex)
