extends SceneTree
## Writes artifacts/world-<seed>.png for quick review of generated worlds, with
## no rendering: hexes by biome (lighter with height), rivers, lakes, the start
## hex (white ring) and unscouted land slightly darkened.
##   godot --headless --path . --script tools/dump_world.gd -- --seeds=1,2,3
const WorldGen = preload("res://sim/world/world_gen.gd")
const WorldMap = preload("res://sim/world/world_map.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const PIXELS_PER_UNIT := 1.4
const RIVER_COLOUR := Color("2f6f8f")

func _init() -> void:
	var seeds: Array[int] = [73]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seeds.clear()
			for part in argument.trim_prefix("--seeds=").split(","):
				seeds.append(int(part))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	for seed_value in seeds:
		var started := Time.get_ticks_msec()
		var world = WorldGen.generate(seed_value)
		if world == null:
			quit(1)
			return
		var elapsed := Time.get_ticks_msec() - started
		var path := "res://artifacts/world-%d.png" % seed_value
		draw(world).save_png(path)
		print("WORLD %d: %d ms, %s -> %s" % [seed_value, elapsed, summary(world), path])
	quit(0)

static func summary(world) -> String:
	var biomes := {}
	var lakes := 0
	var mouths := 0
	for coord in world.hexes:
		var info = world.hexes[coord]
		biomes[info.biome] = int(biomes.get(info.biome, 0)) + 1
		if info.lake: lakes += 1
		if not info.is_land() and not info.river_edges.is_empty(): mouths += 1
	return "biomes %s; %d lakes; %d river mouths; start %s" % [JSON.stringify(biomes), lakes, mouths, world.start]

static func draw(world) -> Image:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for coord in world.hexes:
		var centre := HexMath.centre(coord)
		low = low.min(centre)
		high = high.max(centre)
	low -= Vector2(HexMath.WIDTH * 0.5, HexMath.RADIUS)
	high += Vector2(HexMath.WIDTH * 0.5, HexMath.RADIUS)
	var size := Vector2i(((high - low) * PIXELS_PER_UNIT).ceil())
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	image.fill(Color("1d2b30"))
	for y in size.y:
		for x in size.x:
			var point := low + Vector2(x + 0.5, y + 0.5) / PIXELS_PER_UNIT
			var coord := HexMath.from_point(point)
			var info = world.hex(coord)
			if info == null:
				continue
			var colour := Color.html(world.data.biomes[info.biome].colour)
			if info.is_land():
				colour = colour.lightened(info.elevation * 0.06)
				if not info.scouted: colour = colour.darkened(0.12)
			# Darken near the hex outline so the grid reads.
			var rim := (point - HexMath.centre(coord)).length() / HexMath.RADIUS
			if rim > 0.86 and _near_edge(point, coord): colour = colour.darkened(0.18)
			image.set_pixel(x, y, colour)
	for coord in world.hexes:
		var info = world.hexes[coord]
		var centre := HexMath.centre(coord)
		if info.lake:
			_disc(image, (centre - low) * PIXELS_PER_UNIT, HexMath.WIDTH * 0.28 * PIXELS_PER_UNIT, RIVER_COLOUR)
		for edge in info.river_edges:
			var middle: Vector2 = (centre + HexMath.centre(world.neighbour(coord, edge))) * 0.5
			var from: Vector2 = centre if info.is_land() else middle
			_line(image, (from - low) * PIXELS_PER_UNIT, (middle - low) * PIXELS_PER_UNIT, 0.6 + int(info.river_edges[edge]) * 0.9, RIVER_COLOUR)
	var start := (HexMath.centre(world.start) - low) * PIXELS_PER_UNIT
	for angle in 64:
		var at := start + Vector2.from_angle(angle * TAU / 64.0) * HexMath.WIDTH * 0.32 * PIXELS_PER_UNIT
		_disc(image, at, 1.2, Color.WHITE)
	return image

## True when the point is closer to a neighbouring hex centre's boundary than the
## hex's own inner area, i.e. within the outline band.
static func _near_edge(point: Vector2, coord: Vector2i) -> bool:
	var local := point - HexMath.centre(coord)
	for edge in 6:
		var normal: Vector2 = HexMath.centre(HexMath.NEIGHBOURS[edge]).normalized()
		if local.dot(normal) > HexMath.WIDTH * 0.5 * 0.9:
			return true
	return false

static func _line(image: Image, a: Vector2, b: Vector2, radius: float, colour: Color) -> void:
	var steps := maxi(1, ceili(a.distance_to(b)))
	for step in steps + 1:
		_disc(image, a.lerp(b, float(step) / steps), radius, colour)

static func _disc(image: Image, centre: Vector2, radius: float, colour: Color) -> void:
	for y in range(floori(centre.y - radius), ceili(centre.y + radius) + 1):
		for x in range(floori(centre.x - radius), ceili(centre.x + radius) + 1):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() and Vector2(x + 0.5, y + 0.5).distance_to(centre) <= radius:
				image.set_pixel(x, y, colour)
