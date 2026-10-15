extends RefCounted
## Site packages, relief and reach (docs/WORLD_MAP.md phase 1).
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Sites = preload("res://sim/world/sites.gd")
const SitePackage = preload("res://sim/world/site_package.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const SeededRNG = preload("res://sim/rng.gd")

func run(t) -> void:
	_legacy(t)
	_hex_math(t)
	_package_validation(t)
	_footprint_boundary(t)
	_terraces_shape(t)
	_relief_rules(t)
	_terraces_chain(t)

func _legacy(t) -> void:
	var sim = Sim.new(73)
	t.check(Sites.first_bread(SeededRNG.new(73)).terrain == sim.grid.terrain, "Default coastal site generation is deterministic")
	t.check(sim.grid.width == 100 and sim.grid.height == 100 and Scenario.offset(sim) == Vector2i(30,30), "Default site is 100x100 with the starter in the centre")
	t.check(not 1 in sim.grid.levels and not 1 in sim.grid.ramps and not 0 in sim.grid.reach, "Default site is flat and fully within village reach")
	var blank = SitePackage.new()
	t.check(blank.width == 100 and blank.height == 100 and blank.error().is_empty(), "New site packages also default to 100x100")
	var snapshot: Dictionary = sim.snapshot()
	t.check(snapshot.width == 100 and snapshot.height == 100 and snapshot.terrain.size() == 10000 and snapshot.deposits.size() == 10000 and snapshot.levels.size() == 10000 and snapshot.ramps.size() == 10000 and snapshot.reach.size() == 10000, "All authoritative map layers cover 10000 tiles")
	t.check(sim.grid.terrain_at(Vector2i(70,70)) in ["grass","forest"] and sim.grid.terrain_at(Vector2i(95,70)) == "water", "Expanded map has usable inland terrain and an eastern coast")
	t.check(sim.place("house",sim.site.founding_spot+Vector2i(0,-4)), "Build in the central clearing beyond the old 40x40 boundary")
	var edge := Vector2i(-1, sim.grid.height-1)
	for x in range(9,79):
		if sim.grid.terrain_at(Vector2i(x,edge.y)) == "grass" and sim.grid.terrain_at(Vector2i(x+1,edge.y)) == "grass":
			edge.x = x
			break
	t.check(edge.x >= 0, "Final map row has a buildable edge fixture")
	if edge.x >= 0:
		# A 2×2 woodcutter on the last row reaches past the map; a cottage (2×1) fits.
		t.check(not sim.place("woodcutter", edge) and sim.last_error == "Outside the map", "Footprints cannot extend past the new map edge")
		t.check(sim.place("well", edge), "Build on the final map row")
	# Retain an explicit reference-size option for archived captures and fixtures.
	var legacy = Sites.first_bread(SeededRNG.new(73), Vector2i(40,40))
	t.check(legacy.width == 40 and legacy.height == 40 and legacy.terrain.size() == 1600 and legacy.terrain[legacy.index(Vector2i(35,20))] == "water", "Explicit 40x40 reference site remains available")

func _hex_math(t) -> void:
	var round_trip := true
	for q in range(-3, 4):
		for r in range(-3, 4):
			if HexMath.from_point(HexMath.centre(Vector2i(q, r))) != Vector2i(q, r):
				round_trip = false
	t.check(round_trip, "Hex centres map back to their own hex")
	t.check(HexMath.from_point(Vector2(9.9, 0)) == Vector2i.ZERO and HexMath.from_point(Vector2(10.1, 0)) == Vector2i(1, 0), "Hex boundary falls halfway to the east neighbour")
	var neighbours_adjacent := true
	for neighbour in HexMath.NEIGHBOURS:
		neighbours_adjacent = neighbours_adjacent and HexMath.distance(Vector2i.ZERO, neighbour) == 1
	t.check(neighbours_adjacent and HexMath.distance(Vector2i(0, 0), Vector2i(2, -1)) == 2 and HexMath.distance(Vector2i(-2, 0), Vector2i(2, 0)) == 4, "Hex distance counts steps between hexes")

func _package_validation(t) -> void:
	var broken = SitePackage.new(10, 10)
	broken.levels.resize(5)
	t.check(not broken.error().is_empty(), "Reject site arrays of the wrong size")
	var sim = Sim.new(73, null, broken)
	t.check(not sim.valid and not sim.place("well", Vector2i(1, 1)), "An invalid site stops the run instead of crashing")
	var bad_mask = SitePackage.new(40,40)
	bad_mask.footprint.resize(3)
	t.check(not bad_mask.error().is_empty(), "Reject physical boundary masks of the wrong size")

func _footprint_boundary(t) -> void:
	var site = SitePackage.new(40,40)
	var outside := Vector2i(1,1)
	site.footprint[site.index(outside)] = 0
	var sim = Sim.new(73,null,site)
	var grid = sim.grid
	t.check(not grid.inside(outside) and grid.terrain_at(outside) == "void" and not grid.is_ramp(outside) and not grid.in_reach(outside), "Physical mask applies to all terrain and reach queries")
	t.check(not sim.place("well",outside) and not sim.place_road([outside]), "Buildings and roads cannot enter backing-storage holes")
	grid.roads[outside] = true
	grid.roads[outside + Vector2i.RIGHT] = true
	t.check(grid.astar(outside,outside + Vector2i.RIGHT).is_empty() and not grid.passable(outside,outside + Vector2i.RIGHT), "Injected exterior roads cannot bypass the physical boundary")
	grid.plant_tree(outside,1)
	t.check(not grid.saplings.has(outside), "Planting cannot enter backing-storage holes")
	grid.saplings[outside] = 1
	grid.grow_trees(2)
	t.check(not grid.trees.has(outside), "Injected exterior saplings never mature into resources")

func _terraces_shape(t) -> void:
	var a = Sites.terraces()
	var b = Sites.terraces()
	t.check(a.error().is_empty() and a.width == 60 and a.height == 60, "Terraces is a valid 60x60 site")
	t.check(a.terrain == b.terrain and a.levels == b.levels and a.ramps == b.ramps and a.reach == b.reach, "Hand-made site is deterministic")
	var inside_reach := 0
	var waterfall := false
	for y in a.height:
		for x in a.width:
			var cell := Vector2i(x, y)
			inside_reach += a.reach[a.index(cell)]
			var right := cell + Vector2i.RIGHT
			if a.inside(right) and a.terrain[a.index(cell)] == "stream" and a.terrain[a.index(right)] == "stream" and a.levels[a.index(cell)] != a.levels[a.index(right)]:
				waterfall = true
	# Seven 20-tile hexes hold about 2,425 tile centres.
	t.check(inside_reach > 2300 and inside_reach < 2550, "Reach covers the founding hex and its six neighbours (%d tiles)" % inside_reach)
	t.check(a.reach[a.index(Vector2i(1, 1))] == 0 and a.reach[a.index(Vector2i(30, 30))] == 1, "Site corners lie beyond the village lands")
	t.check(waterfall, "The stream falls off the plateau")

func _relief_rules(t) -> void:
	var sim = Sim.new(73, null, Sites.terraces())
	var grid = sim.grid
	t.check(grid.level_at(Vector2i(35, 34)) == 0 and grid.level_at(Vector2i(36, 34)) == 1 and not grid.passable(Vector2i(35, 34), Vector2i(36, 34)), "A level change without a ramp is a cliff")
	t.check(grid.is_ramp(Vector2i(39, 28)) and grid.passable(Vector2i(38, 28), Vector2i(39, 28)), "A ramp connects the plain to the plateau")
	t.check(not sim.place("house", Vector2i(35, 33)) and sim.last_error == "Ground is not level", "Buildings cannot straddle a cliff")
	t.check(not sim.place("house", Vector2i(39, 27)) and sim.last_error == "Cannot build on a slope", "Buildings cannot stand on a ramp")
	t.check(not sim.place("well", Vector2i(3, 1)) and sim.last_error == "Beyond the village lands", "Buildings stay inside the reach")
	t.check(not sim.place_road([Vector2i(3, 1)]) and sim.last_error == "Beyond the village lands", "Roads stay inside the reach")
	t.check(sim.place("well", Vector2i(44, 36)), "Buildings fit on flat plateau ground")
	var before: Dictionary = sim.snapshot()
	t.check(not sim.place_road([Vector2i(34, 34), Vector2i(35, 34), Vector2i(36, 34), Vector2i(37, 34)]) and sim.last_error == "Cliff in the way", "A road stroke cannot climb a cliff")
	t.check(JSON.stringify(before) == JSON.stringify(sim.snapshot()), "Rejected cliff road is atomic")
	t.check(sim.place_road([Vector2i(37, 28), Vector2i(38, 28), Vector2i(39, 28), Vector2i(40, 28)]), "A road climbs the ramp")
	t.check(grid.astar(Vector2i(37, 28), Vector2i(40, 28)).size() == 4, "Carriers route up the ramp")
	t.check(sim.place_road([Vector2i(35, 34)]) and sim.place_road([Vector2i(36, 34)]), "Separate roads may end at either side of a cliff")
	t.check(grid.astar(Vector2i(35, 34), Vector2i(36, 34)).is_empty(), "Carriers never step over a cliff")
	t.check(sim.place("well", Vector2i(35, 35)) and sim.place_road([Vector2i(34, 35)]), "Place a plateau well beside a road below the cliff")
	t.check(grid.access(sim.buildings[grid.occupied[Vector2i(35, 35)]]).is_empty(), "A road below a cliff gives no access")
	t.check(grid.terrain_at(Vector2i(25, 22)) == "stream" and sim.place_road([Vector2i(25, 22)]), "Roads ford streams")
	t.check(not sim.place_road([Vector2i(8, 30)]) and sim.last_error == "Cannot build on river", "Rivers block roads")
	var state: Dictionary = sim.snapshot()
	t.check(state.width == 60 and state.levels.size() == 3600 and state.ramps.size() == 3600 and state.reach.size() == 3600, "Snapshots carry the site's relief and reach")

func _terraces_chain(t) -> void:
	var sim = Sim.new(73, null, Sites.terraces())
	t.check(Scenario.starter(sim), "Starter layout fits at the Terraces founding spot")
	sim.step(1000)
	t.check(sim.unlocked_tier == 2 and Scenario.complete_chain(sim), "Terraces village reaches Villagers")
	sim.step(1800)
	t.check(int(sim.produced.get("bread", 0)) > 0, "Terraces village bakes bread")
