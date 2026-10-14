extends SceneTree
## Writes artifacts/world-<seed>.png and paired site-<seed>-<q>-<r>.png for review,
## no rendering: hexes by biome (lighter with height), rivers, lakes, the start
## hex (white ring) and unscouted land slightly darkened.
##   godot --headless --path . --script tools/dump_world.gd -- --seeds=1,2,3
##   Add --site=q,r for a selected tile, or --lake for a lake layout fixture.
const WorldGen = preload("res://sim/world/world_gen.gd")
const WorldMap = preload("res://sim/world/world_map.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const Layout = preload("res://sim/world/terrain_layout.gd")
const SiteGen = preload("res://sim/world/site_gen.gd")
const PIXELS_PER_UNIT := 1.4
const RIVER_COLOUR := Color("2f6f8f")

func _init() -> void:
	var seeds: Array[int] = [73]
	var selected := Vector2i.ZERO
	var has_selected := false
	var lake_fixture := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seeds.clear()
			for part in argument.trim_prefix("--seeds=").split(","):
				seeds.append(int(part))
		elif argument.begins_with("--site="):
			var parts := argument.trim_prefix("--site=").split(",")
			if parts.size() == 2:
				selected = Vector2i(int(parts[0]),int(parts[1]))
				has_selected = true
		elif argument == "--lake": lake_fixture = true
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
		var coord: Vector2i = selected if has_selected else world.start
		if lake_fixture:
			for candidate in world.hexes:
				if world.hex(candidate).lake and world.data.biomes[world.hex(candidate).biome].settleable:
					coord = candidate
					break
		var site = SiteGen.generate(world,coord)
		var site_path := "res://artifacts/site-%d-%d-%d.png" % [seed_value,coord.x,coord.y]
		draw_pair(world,site).save_png(site_path)
		print("SITE %s: %s -> %s" % [coord, "Playable" if site.error().is_empty() else site.error(),site_path])
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
			var water: String = Layout.water_at(world,coord,point * Layout.SCALE)
			if not water.is_empty(): colour = RIVER_COLOUR
			image.set_pixel(x, y, colour)
	var start := (HexMath.centre(world.start) - low) * PIXELS_PER_UNIT
	for angle in 64:
		var at := start + Vector2.from_angle(angle * TAU / 64.0) * HexMath.WIDTH * 0.32 * PIXELS_PER_UNIT
		_disc(image, at, 1.2, Color.WHITE)
	return image

## Left: the source tile and neighbour descriptors at the same orientation.
## Right: the exact playable mask, square-cell relief and deposits. The pale
## cross is the storehouse founding cell; subtle lines retain district edges.
static func draw_pair(world, site) -> Image:
	var scale := 3
	var gap := 18
	var panel_size := Vector2i(site.width * scale,site.height * scale)
	var image := Image.create(panel_size.x * 2 + gap,panel_size.y,false,Image.FORMAT_RGB8)
	image.fill(Color("223b37"))
	for y in site.height:
		for x in site.width:
			var cell := Vector2i(x,y)
			var point: Vector2 = site.world_point(cell)
			var owner := HexMath.from_point(point / Layout.SCALE)
			var info = world.hex(owner)
			var source := Color("223b37")
			if info != null:
				source = _district_colour(info.biome,info.elevation)
				if info.forest > 0.0 and Layout.grove_at(world,owner,point) > 0.68 - info.forest * 0.42: source = source.lerp(Color("38675e"),0.52)
				source = source.lightened(Layout.relief_at(world,owner,point) * 0.15)
				if not Layout.water_at(world,owner,point).is_empty(): source = Color("4c9999")
				if _near_edge(point / Layout.SCALE,owner): source = source.darkened(0.12)
			var generated := Color("223b37")
			if site.inside(cell):
				var index: int = site.index(cell)
				var descriptor = world.hex(site.owner_coords[index])
				generated = _district_colour(descriptor.biome,site.levels[index])
				if site.terrain[index] == "forest": generated = Color("38675e")
				elif site.terrain[index] == "rock": generated = Color("87917d")
				elif site.terrain[index] in ["ocean","lake","river","stream"]: generated = Color("4c9999")
				if site.ramps[index] == 1: generated = generated.lightened(0.12)
				if site.deposits[index] not in ["","timber","fertile_soil"]: generated = generated.lerp(Color("d7b366"),0.38)
				if cell == site.founding_spot: generated = Color("f5eac7")
			for dy in scale:
				for dx in scale:
					image.set_pixel(x * scale + dx,y * scale + dy,source)
					image.set_pixel(panel_size.x + gap + x * scale + dx,y * scale + dy,generated)
	return image

static func _district_colour(biome: String, elevation: int) -> Color:
	var palette := {"ocean":"4c9999","peaks":"a2aca5","mountain_pass":"8b9478","tundra":"9baa9d","marsh":"537968","highland_hills":"7b9157","coast":"99a36c","riverland":"709452","heartland":"94aa60"}
	return Color(palette.get(biome,"94aa60")).lightened(elevation * 0.025)

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
