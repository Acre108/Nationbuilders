extends RefCounted
## Hand-made site packages. Generated sites come from the world later; these
## provide the default coastal village and a fixed site with real relief.
const SitePackage = preload("res://sim/world/site_package.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const NAMES: Array[String] = ["first_bread", "terraces"]

static func named(site_name: String, rng):
	return terraces() if site_name == "terraces" else first_bread(rng)

## Woodland around a central settlement, with a western approach and coast.
## The explicit 40x40 reference retains the archived layout.
static func first_bread(rng, size: Vector2i = SitePackage.DEFAULT_SIZE):
	var site = SitePackage.new(size.x, size.y)
	site.name = "first_bread"
	var coast_x := int(site.width * 0.8)
	var reference := size == Vector2i(40,40)
	var woodland_seed: int = rng.state
	if not reference:
		site.founding_spot = Vector2i(site.width / 2 - 3, site.height / 2 + 1)
		var shift: Vector2i = site.founding_spot - Vector2i(17,21)
		site.settlement_clearance = Rect2i(Vector2i(10,15)+shift,Vector2i(20,12))
		for x in range(site.founding_spot.x+4):
			site.entrance_road.append(Vector2i(x,site.founding_spot.y-1))
	for y in site.height:
		for x in site.width:
			var roll: int = rng.next_int(100)
			var tile := "grass"
			if x >= coast_x + (y / 9) % 2:
				tile = "water"
			elif not reference:
				# Coarse groves and broad clearings, with individual gaps between crowns.
				var grove := _hash(x / 8,y / 7,woodland_seed)
				var clearing: bool = site.settlement_clearance.has_point(Vector2i(x,y))
				var approach: bool = x <= site.founding_spot.x+3 and absi(y-(site.founding_spot.y-1)) <= 1
				if not clearing and not approach and grove < 80 and roll < 88 and (x+y)%3 == 0:
					tile = "forest"
				elif not clearing and not approach and grove >= 96 and roll > 96:
					tile = "rock"
			elif (x < 9 or y < 12 or y > site.height - 13) and roll < 55:
				tile = "forest"
			elif (x < 7 or y < 9 or y > site.height - 10) and roll > 90:
				tile = "rock"
			var index := site.index(Vector2i(x, y))
			site.terrain[index] = tile
			var fertile: bool = x > 10 and x < 20 and y > 13 and y < 24 if reference else site.settlement_clearance.has_point(Vector2i(x,y))
			site.deposits[index] = "timber" if tile == "forest" else ("fertile_soil" if tile == "grass" and fertile else "")
	return site

## A 60x60 reach in hill country: a plateau with a cliff and one ramp, a
## hilltop, a river into a lake, and a stream that falls off the plateau.
static func terraces():
	var site = SitePackage.new(60, 60)
	site.name = "terraces"
	site.biome = "highland_hills"
	site.founding_spot = Vector2i(24, 35)
	var centre := Vector2(30, 30)
	var stream: Array[Vector2] = [Vector2(47,-1), Vector2(46,8), Vector2(42,15), Vector2(38,20), Vector2(31,22), Vector2(23,22), Vector2(15,23), Vector2(10,23)]
	for y in 60:
		for x in 60:
			var index := y * 60 + x
			var p := Vector2(x + 0.5, y + 0.5)
			site.reach[index] = 1 if HexMath.distance(HexMath.from_point(p - centre), Vector2i.ZERO) <= 1 else 0
			var level := 1 if p.x >= 37.0 + 2.0 * sin(y * 0.3) else 0
			if p.distance_to(Vector2(45, 44)) < 5.5:
				level = 2
			site.levels[index] = level
			var tile := "grass"
			var river_x := 11.0 + 3.0 * sin(y * 0.13)
			if absf(p.x - river_x) < 1.0 + y / 60.0:
				tile = "river"
			elif p.distance_to(Vector2(10, 49)) < 5.0:
				tile = "lake"
			elif _near_polyline(p, stream, 0.6):
				tile = "stream"
			elif (x < 22 and y < 18) or (x >= 28 and x < 35 and y > 40 and y < 51):
				tile = "forest" if _hash(x, y, 1) < 55 else "grass"
			elif level == 1 and p.distance_to(Vector2(46, 28)) < 7.0:
				tile = "forest" if _hash(x, y, 2) < 60 else "grass"
			elif level == 2 and _hash(x, y, 3) < 15:
				tile = "rock"
			site.terrain[index] = tile
	for y in 60:
		for x in 60:
			var cell := Vector2i(x, y)
			var index := y * 60 + x
			var level: int = site.levels[index]
			var lower := false
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbour: Vector2i = cell + direction
				if site.inside(neighbour) and site.levels[site.index(neighbour)] == level - 1:
					lower = true
			var water: bool = site.terrain[index] in ["river", "lake", "stream"]
			# One ramp up the plateau, south of the village, and one up the hill.
			if lower and not water and ((level == 1 and y >= 26 and y <= 31) or (level == 2 and x < 42 and absi(y - 44) <= 1)):
				site.ramps[index] = 1
			# Scree at the foot of cliffs, clear of the starter layout.
			var below_cliff := false
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbour: Vector2i = cell + direction
				if site.inside(neighbour) and site.levels[site.index(neighbour)] == level + 1 and y not in range(25, 33):
					below_cliff = true
			var starter_area := x >= 18 and x <= 35 and y >= 29 and y <= 39
			if below_cliff and not starter_area and site.terrain[index] == "grass" and _hash(x, y, 4) < 35:
				site.terrain[index] = "rock"
	for y in 60:
		for x in 60:
			var index := y * 60 + x
			var tile: String = site.terrain[index]
			var flat_grass: bool = tile == "grass" and site.ramps[index] == 0
			if tile == "forest":
				site.deposits[index] = "timber"
			elif flat_grass and ((x >= 18 and x <= 27 and y >= 28 and y <= 37) or (site.levels[index] == 1 and x >= 40 and x <= 48 and y >= 33 and y <= 40)):
				site.deposits[index] = "fertile_soil"
	return site

static func _near_polyline(p: Vector2, points: Array[Vector2], radius: float) -> bool:
	for index in range(1, points.size()):
		if Geometry2D.get_closest_point_to_segment(p, points[index - 1], points[index]).distance_to(p) < radius:
			return true
	return false

## Order-free integer hash in [0, 100), so tiles never depend on draw order.
static func _hash(x: int, y: int, salt: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return posmod(h ^ (h >> 16), 100)
