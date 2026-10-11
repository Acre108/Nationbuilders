extends RefCounted
## World generation (docs/PLAN-world-map.md phase A).
const WorldGen = preload("res://sim/world/world_gen.gd")
const WorldMap = preload("res://sim/world/world_map.gd")
const WorldData = preload("res://sim/world/world_data.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const IntNoise = preload("res://sim/world/int_noise.gd")
const SEEDS: Array[int] = [73, 1, 2, 3, 4]

func run(t) -> void:
	var data = WorldData.new()
	t.check(data.load_directory(), "Shipped world data validates")
	_data_rejection(t)
	_noise(t)
	var biomes_seen := {}
	for seed_value in SEEDS:
		var world = WorldGen.generate(seed_value, data)
		_shape(t, world, data)
		_rivers(t, world)
		_biomes(t, world)
		_start(t, world)
		_deposits(t, world)
		for coord in world.hexes:
			biomes_seen[world.hexes[coord].biome] = true
	t.check(biomes_seen.size() == WorldData.RULE_BIOMES.size(), "Every biome appears across the test seeds (%d of %d)" % [biomes_seen.size(), WorldData.RULE_BIOMES.size()])
	var a = WorldGen.generate(73, data)
	t.check(a.fingerprint() == WorldGen.generate(73, data).fingerprint(), "Same seed gives the same world")
	t.check(a.fingerprint() != WorldGen.generate(74, data).fingerprint(), "Different seeds give different worlds")
	_founding(t, a)
	_visibility(t, a)

func _data_rejection(t) -> void:
	var data = WorldData.new()
	data.load_directory()
	var world_row: Dictionary = data.world.duplicate(true)
	var biomes: Array = data.biomes.values().duplicate(true)
	var deposits: Array = data.deposits.values().duplicate(true)
	var broken: Array = biomes.duplicate(true)
	broken[2].signature["unobtainium"] = 1
	t.check(not data.validate(world_row, broken, deposits) and "unknown deposit unobtainium" in "; ".join(data.errors), "Reject unknown deposit in a biome pool")
	var hidden: Array = deposits.duplicate(true)
	hidden[0].visibility = "sometimes"
	t.check(not data.validate(world_row, biomes, hidden), "Reject unknown deposit visibility")
	t.check(not data.validate(world_row, biomes.slice(1), deposits) and "missing biome ocean" in "; ".join(data.errors), "Reject data missing a biome the rules assign")
	var bands: Dictionary = world_row.duplicate(true)
	bands.band_fractions = [0.5, 0.4, 0.8, 0.9]
	t.check(not data.validate(bands, biomes, deposits), "Reject elevation bands that do not increase")
	t.check(not data.validate([], 3, null), "Malformed world data returns diagnostics without crashing")

func _noise(t) -> void:
	t.check(IntNoise.mix(73, 4, -9, 2) == IntNoise.mix(73, 4, -9, 2) and IntNoise.mix(73, 4, -9, 2) != IntNoise.mix(73, 4, -9, 3), "Hash noise is stable and separates channels")
	var in_range := true
	for i in 200:
		var v := IntNoise.fbm(5, 1, Vector2(i * 0.37, i * 0.11))
		in_range = in_range and v >= 0.0 and v <= 1.0
	t.check(in_range, "Fractal noise stays within 0..1")

func _shape(t, world, data) -> void:
	var label := "seed %d: " % world.seed_value
	t.check(world.hexes.size() == int(data.world.columns) * int(data.world.rows), label + "map has columns x rows hexes")
	var border_ocean := true
	var ocean := 0
	for coord in world.hexes:
		var column: int = WorldMap.column_of(coord)
		if column == 0 or coord.y == 0 or column == world.columns - 1 or coord.y == world.rows - 1:
			border_ocean = border_ocean and not world.hexes[coord].is_land()
		if not world.hexes[coord].is_land():
			ocean += 1
	t.check(border_ocean, label + "the map is ringed by ocean")
	var fraction: float = float(ocean) / world.hexes.size()
	t.check(absf(fraction - float(data.world.sea_fraction)) < 0.1, label + "sea covers about the configured share (%.2f)" % fraction)

func _rivers(t, world) -> void:
	var label := "seed %d: " % world.seed_value
	var mirrored := true
	var downhill := true
	var reaches_sea := true
	var rivers := 0
	for coord in world.hexes:
		var info = world.hexes[coord]
		for edge in info.river_edges:
			var other = world.hex(world.neighbour(coord, edge))
			mirrored = mirrored and other != null and other.river_edges.get(WorldMap.opposite(edge)) == info.river_edges[edge]
		if not info.is_land() or info.river_edges.is_empty():
			continue
		rivers += 1
		# Follow the water: it must fall every step and reach the sea.
		var current: Vector2i = coord
		var steps := 0
		while world.hex(current).is_land() and steps <= world.hexes.size():
			var here = world.hex(current)
			var next: Vector2i = world.neighbour(current, here.flows_to)
			downhill = downhill and world.hex(next).filled < here.filled
			current = next
			steps += 1
		reaches_sea = reaches_sea and not world.hex(current).is_land()
	t.check(rivers >= 6, label + "the world has rivers (%d river hexes)" % rivers)
	t.check(mirrored, label + "every river edge is marked on both of its hexes")
	t.check(downhill, label + "rivers only run downhill")
	t.check(reaches_sea, label + "every river reaches the sea")

func _biomes(t, world) -> void:
	var label := "seed %d: " % world.seed_value
	var consistent := true
	for coord in world.hexes:
		var info = world.hexes[coord]
		match info.biome:
			"peaks": consistent = consistent and info.elevation == 4
			"mountain_pass": consistent = consistent and info.elevation == 3
			"marsh": consistent = consistent and info.elevation == 0
			"highland_hills": consistent = consistent and info.elevation == 2
			"coast": consistent = consistent and not info.coast_edges.is_empty()
			"riverland": consistent = consistent and (info.river_width() >= 2 or info.lake)
		if info.is_land():
			consistent = consistent and info.forest >= 0.0 and info.forest <= 1.0 and info.cliffs >= 0.0 and info.cliffs <= 1.0
	t.check(consistent, label + "biomes follow their classification rules")

func _start(t, world) -> void:
	var label := "seed %d: " % world.seed_value
	var start = world.hex(world.start)
	t.check(start != null and world.found_blocked(world.start).is_empty() and not world.data.biomes[start.biome].harsh, label + "the start hex is settleable and not harsh")
	var scouted := true
	var wild_near := 0.0
	var wild_far := 0.0
	var near := 0
	var far := 0
	for coord in world.hexes:
		var distance := HexMath.distance(coord, world.start)
		var info = world.hexes[coord]
		if distance <= int(world.data.world.scout_radius):
			scouted = scouted and info.scouted and info.wildness == 0
		elif distance <= 4:
			wild_near += info.wildness
			near += 1
		elif distance >= 8:
			wild_far += info.wildness
			far += 1
	t.check(scouted, label + "the start region is scouted and tame")
	t.check(far == 0 or wild_far / far > wild_near / maxi(1, near), label + "wildness grows with distance from the start")

func _deposits(t, world) -> void:
	var label := "seed %d: " % world.seed_value
	var from_pools := true
	var harsh_rare := true
	var salt_on_coast := true
	var none_unsettled := true
	for coord in world.hexes:
		var info = world.hexes[coord]
		var biome: Dictionary = world.data.biomes[info.biome]
		if not biome.settleable:
			none_unsettled = none_unsettled and info.deposits.is_empty()
			continue
		var rare_found := 0
		for deposit in info.deposits:
			from_pools = from_pools and (biome.signature.has(deposit) or biome.rare.has(deposit) or biome.get("extra", {}).has(deposit))
			if biome.rare.has(deposit):
				rare_found += 1
			if deposit == "sea_salt_flats":
				salt_on_coast = salt_on_coast and not info.coast_edges.is_empty()
		if biome.harsh:
			harsh_rare = harsh_rare and rare_found >= 1
	t.check(from_pools, label + "deposits come from their biome's pools")
	t.check(harsh_rare, label + "every harsh hex has a rare deposit")
	t.check(salt_on_coast, label + "sea salt flats only appear on ocean edges")
	t.check(none_unsettled, label + "ocean and peaks hold no deposits")

func _founding(t, world) -> void:
	var ocean := Vector2i.ZERO
	for coord in world.hexes:
		if not world.hexes[coord].is_land():
			ocean = coord
			break
	t.check(world.found_blocked(ocean).begins_with("Cannot settle"), "Ocean hexes cannot be founded")
	var village: Vector2i = world.start
	var close := Vector2i(-99, -99)
	var spaced := Vector2i(-99, -99)
	for coord in world.hexes:
		if not world.data.biomes[world.hexes[coord].biome].settleable:
			continue
		var distance := HexMath.distance(coord, village)
		if distance == 3 and close.x == -99:
			close = coord
		if distance == 4 and spaced.x == -99:
			spaced = coord
	var settlements: Array[Vector2i] = [village]
	t.check(close.x == -99 or world.found_blocked(close, settlements) == "Too close to another village", "Villages 3 hexes apart are too close")
	t.check(spaced.x == -99 or world.found_blocked(spaced, settlements).is_empty(), "Villages 4 hexes apart leave a hex of wilderness and are allowed")
	t.check(world.reach(village).size() == 7 and world.found_blocked(village, settlements) == "Too close to another village", "Reach is a hex and its neighbours; an occupied hex cannot be refounded")

func _visibility(t, world) -> void:
	var checked := false
	for coord in world.hexes:
		var info = world.hexes[coord]
		var hidden := false
		for deposit in info.deposits:
			hidden = hidden or world.data.deposits[deposit].visibility == "scouted"
		if not hidden or info.scouted:
			continue
		var shown: Array[String] = world.visible_deposits(coord)
		var only_map := true
		for deposit in shown:
			only_map = only_map and world.data.deposits[deposit].visibility == "map"
		t.check(only_map and world.has_hidden_deposits(coord), "Unscouted hexes show only map-visible deposits")
		info.scouted = true
		t.check(world.visible_deposits(coord).size() == info.deposits.size(), "Scouting reveals every deposit")
		info.scouted = false
		checked = true
		break
	t.check(checked, "The test world has an unscouted hex with hidden deposits")
