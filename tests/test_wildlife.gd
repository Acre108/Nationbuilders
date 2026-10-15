extends RefCounted
## Game in the land (docs/WILDLIFE.md): habitat from the grid, herds that breed,
## move and decline, and the hunter's lodge.
const Sim = preload("res://sim/village_sim.gd")
const SitePackage = preload("res://sim/world/site_package.gd")
const Wildlife = preload("res://sim/wildlife.gd")

func run(t) -> void:
	_habitat(t)
	_herds(t)
	_hunting(t)
	_snapshot(t)
	_default_map(t)

## A 40 × 30 site of three bands, each a column of 10 × 10 ranges: a wood
## (x 0–9), meadow beside it (x 10–19) and open land far from cover (x 20–39).
func _site():
	var site = SitePackage.new(40, 30)
	site.founding_spot = Vector2i(25, 15)
	for y in 30:
		for x in 10:
			if (x + y) % 3 == 0:
				site.terrain[site.index(Vector2i(x, y))] = "forest"
	return site

func _sim():
	return Sim.new(73, null, _site())

func _habitat(t) -> void:
	var sim = _sim()
	var w = sim.wildlife
	t.check(w.columns == 4 and w.rows == 3 and w.range_of(Vector2i(25, 15)) == 6, "Ranges are %d-tile squares" % Wildlife.RANGE)
	var land: Dictionary = w.habitat(sim.grid)
	t.check(int(land.trees[0]) >= 30 and int(land.meadow[0]) == 0, "A full wood is woodland, not meadow: %d trees, %d meadow" % [land.trees[0], land.meadow[0]])
	t.check(int(land.meadow[2]) == 100 and int(land.trees[2]) == 0, "Open grass with no tree beside it is meadow")
	var boar: Array = w.capacity(sim.grid, "boar")
	var deer: Array = w.capacity(sim.grid, "deer")
	t.check(int(boar[0]) >= 3 and int(boar[4]) >= 3 and int(boar[8]) >= 3 and int(boar[1]) + int(boar[2]) + int(boar[5]) == 0, "Boar live in the wood only: %s" % str(boar))
	t.check(int(deer[1]) >= 2 and int(deer[0]) == 0, "Deer graze the meadow beside the wood, not inside it: %s" % str(deer))
	t.check(int(deer[2]) == 0 and int(deer[3]) == 0, "Open land far from cover holds no deer")
	t.check(w.herds.boar == boar and w.herds.deer == deer, "Herds start at capacity: %d boar, %d deer" % [w.total("boar"), w.total("deer")])
	# Felling the wood takes the boar's home and the deer's cover.
	for y in 10:
		for x in 10:
			sim.grid.clear_tree(Vector2i(x, y), true)
	t.check(int(w.capacity(sim.grid, "boar")[0]) == 0 and int(w.capacity(sim.grid, "deer")[1]) < int(deer[1]), "Felling the wood removes boar habitat and deer cover")
	# Roads and buildings disturb a range; enough of them settle it.
	var road: Array[Vector2i] = []
	for x in range(10, 20):
		road.append(Vector2i(x, 14))
	t.check(sim.place_road(road), "Lay a road through the meadow")
	t.check(int(w.capacity(sim.grid, "deer")[5]) == int(deer[5]) - 1, "A road costs a range one animal of capacity")
	road.clear()
	for x in range(10, 20):
		road.append(Vector2i(x, 16))
	sim.place_road(road)
	t.check(int(w.capacity(sim.grid, "deer")[5]) == 0, "A settled range holds no game")

func _herds(t) -> void:
	var sim = _sim()
	var w = sim.wildlife
	var room: Array = w.capacity(sim.grid, "boar")
	# Breeding: each pair under capacity gains one per breeding interval, up to
	# its range's capacity, then stops.
	for index in [0, 4, 8]:
		w.herds.boar[index] = 2
	sim.step(Wildlife.BREED_TICKS - sim.tick % Wildlife.BREED_TICKS)
	t.check(w.herds.boar[0] == 3 and w.herds.boar[4] == 3 and w.herds.boar[8] == 3, "A pair under capacity breeds: %s" % str([w.herds.boar[0], w.herds.boar[4], w.herds.boar[8]]))
	for index in 3:
		sim.step(Wildlife.BREED_TICKS)
	t.check(w.herds.boar == room, "Herds grow to their range's capacity and stop: %s" % str(w.herds.boar))
	# Recolonisation: empty habitat gains a migrant from a neighbouring pair.
	# Each neighbour sends at most one, and a lone animal cannot breed.
	var full: int = room[4]
	w.herds.boar[0] = 0
	w.herds.boar[8] = 1
	w.herds.deer[1] = 0
	w.herds.deer[5] = 1
	w.herds.deer[9] = 0
	sim.step(Wildlife.BREED_TICKS)
	t.check(w.herds.boar[0] == 1 and w.herds.boar[4] == full - 1 and w.herds.boar[8] == 1, "A neighbouring herd sends one migrant to empty habitat: %s" % str([w.herds.boar[0], w.herds.boar[4], w.herds.boar[8]]))
	t.check(w.herds.deer[1] == 0 and w.herds.deer[5] == 1 and w.herds.deer[9] == 0, "Without a neighbouring pair, empty habitat stays empty and a lone deer does not breed")
	# Lost habitat: each range over capacity loses one animal per interval.
	var before: int = w.total("boar")
	for y in 30:
		for x in 10:
			sim.grid.clear_tree(Vector2i(x, y), true)
	sim.step(Wildlife.BREED_TICKS)
	t.check(w.total("boar") == before - 3, "Boar decline once the wood is felled: %d → %d" % [before, w.total("boar")])
	for index in full:
		sim.step(Wildlife.BREED_TICKS)
	t.check(w.total("boar") == 0, "In time no boar remain without woodland")

func _hunting(t) -> void:
	var sim = _sim()
	var w = sim.wildlife
	t.check(sim.place_road([Vector2i(12, 9), Vector2i(13, 9)]) and sim.place("hunter", Vector2i(12, 10)), "Place a hunter's lodge between wood and meadow: %s" % sim.last_error)
	var hunter = null
	for building in sim.buildings.values():
		hunter = building
	var animals: int = w.total("deer") + w.total("boar")
	sim.step(int(hunter.definition.cycle_ticks) * 2 + 2)
	t.check(hunter.status.begins_with("hunting ") and int(sim.produced.get("meat", 0)) == 4, "Two hunts make four meat: %s, %d" % [hunter.status, int(sim.produced.get("meat", 0))])
	t.check(w.total("deer") + w.total("boar") == animals - 2, "Each hunt takes one animal")
	# Nothing left in reach: the lodge waits and says why.
	for species in Wildlife.SPECIES:
		for index in w.range_count():
			w.herds[species][index] = 0
	hunter.output.take("meat", hunter.output.count("meat"))
	sim.step(1)
	t.check(hunter.status == "no game nearby" and hunter.progress == 0, "With no game in reach the hunter waits: %s" % hunter.status)
	w.herds.deer[11] = 4
	sim.step(1)
	t.check(hunter.status == "no game nearby", "Game beyond the work radius is out of reach")
	w.herds.boar[4] = 1
	sim.step(1)
	t.check(hunter.status == "hunting wild boar", "Game returning to reach is hunted again")
	# Content rejects a hunter that also cuts trees or takes inputs.
	var db = sim.db
	var rows: Array = db.buildings.values().duplicate(true)
	for row in rows:
		if row.id == "hunter": row.inputs = {"water":1}
	t.check(not db.validate(db.goods.values().duplicate(true), rows, db.tiers.values().duplicate(true)) and "hunting takes from the land" in "; ".join(db.errors), "Reject a hunter with recipe inputs")
	db.load_directory()

func _snapshot(t) -> void:
	var sim = _sim()
	sim.place_road([Vector2i(12, 9), Vector2i(13, 9)])
	sim.place("hunter", Vector2i(12, 10))
	sim.step(Wildlife.BREED_TICKS + 250)
	var state: Dictionary = sim.snapshot()
	t.check(state.wildlife.boar == sim.wildlife.herds.boar, "The snapshot holds the herds")
	var restored = Sim.from_snapshot(state, sim.db)
	t.check(restored != null and JSON.stringify(restored.snapshot()) == JSON.stringify(state), "Herds round-trip through a snapshot")
	if restored != null:
		sim.step(Wildlife.BREED_TICKS * 2)
		restored.step(Wildlife.BREED_TICKS * 2)
		t.check(JSON.stringify(restored.snapshot()) == JSON.stringify(sim.snapshot()), "A restored village's herds continue identically")
	var bad: Dictionary = state.duplicate(true)
	bad.wildlife.deer = bad.wildlife.deer.slice(1)
	t.check(Sim.from_snapshot(bad, sim.db) == null, "Reject herds sized for another map")
	bad = state.duplicate(true)
	bad.wildlife.boar[0] = -1
	t.check(Sim.from_snapshot(bad, sim.db) == null, "Reject a negative herd")

## The default village starts among both species.
func _default_map(t) -> void:
	var sim = Sim.new(73)
	t.check(sim.wildlife.total("deer") > 20 and sim.wildlife.total("boar") > 40, "The default site has deer and boar: %d deer, %d boar" % [sim.wildlife.total("deer"), sim.wildlife.total("boar")])
	t.check(preload("res://sim/scenario.gd").starter(sim), "Default site: starter layout")
	var settled: int = sim.wildlife.range_of(sim.site.founding_spot)
	t.check(int(sim.wildlife.capacity(sim.grid, "deer")[settled]) == 0 and int(sim.wildlife.capacity(sim.grid, "boar")[settled]) == 0, "The settled founding range holds no game")
