extends RefCounted
const Sim = preload("res://sim/village_sim.gd")
const Site = preload("res://sim/world/site_package.gd")
const Building = preload("res://sim/building.gd")

func new_sim():
	var site = Site.new(12, 12)
	site.founding_spot = Vector2i(1, 1)
	return Sim.new(73, null, site)

func run(t) -> void:
	var sim = new_sim()
	var row: Dictionary = sim.db.buildings.storehouse
	var original_row := row.duplicate(true)
	for turns in 4:
		sim = new_sim()
		var footprint := Building.rotated_footprint(row, turns)
		t.check(footprint == (Vector2i(3,2) if turns%2 == 0 else Vector2i(2,3)), "Rectangular footprint swaps on odd quarter turns")
		t.check(sim.place("storehouse", Vector2i(3,3), turns), "Place storehouse at each orientation")
		var building = sim.buildings[sim.grid.occupied[Vector2i(3,3)]]
		t.check(building.rotation_quarters == turns and building.snapshot().rotation_quarters == turns, "Placement facing is authoritative and snapshotted")
		t.check(building.cells().size() == 6 and sim.grid.occupied.size() == 6, "All rotated footprint cells reserved")
		var corner := Vector2i(3,3) + footprint - Vector2i.ONE
		t.check(sim.grid.occupied.has(corner), "Rotated opposite corner occupied")
		t.check(not sim.place("well", corner), "Reject overlap on rotated corner")
		t.check(sim.place("well", Vector2i(3,3) + Vector2i(footprint.x,0)), "Unoccupied neighbouring tile stays buildable")
		t.check(sim.demolish(Vector2i(3,3)+Vector2i(footprint.x,0)), "Remove neighbouring well")
		t.check(sim.demolish(corner) and sim.grid.occupied.is_empty(), "Demolish from rotated corner clears whole building")
	# A rotation can make the same anchor valid or invalid at the map edge.
	sim = new_sim()
	t.check(not sim.place("storehouse", Vector2i(10,1), 0), "Unrotated width rejected at map edge")
	t.check(sim.place("storehouse", Vector2i(10,1), 1), "Rotated width fits at same map edge")
	var state: Dictionary = sim.snapshot()
	t.check(not sim.place("farm", Vector2i(10,10), 1), "Rotated depth rejected at bottom edge")
	t.check(sim.snapshot() == state, "Rejected rotation placement does not spend goods or alter state")
	# Each tile check must use the swapped dimensions, including slopes and reach.
	sim = new_sim()
	var index: int = sim.site.index(Vector2i(4,5))
	sim.grid.levels[index] = 1
	t.check(sim.placement_error("storehouse", Vector2i(3,3), 0).is_empty(), "Original footprint misses raised tile")
	t.check(sim.placement_error("storehouse", Vector2i(3,3), 1) == "Ground is not level", "Rotated footprint checks its extra row's level")
	sim.grid.levels[index] = 0
	sim.grid.ramps[index] = 1
	t.check(sim.placement_error("storehouse", Vector2i(3,3), 1) == "Cannot build on a slope", "Rotated footprint checks ramps")
	sim.grid.ramps[index] = 0
	sim.grid.reach[index] = 0
	t.check(sim.placement_error("storehouse", Vector2i(3,3), 1) == "Beyond the village lands", "Rotated footprint checks village reach")
	sim.grid.reach[index] = 1
	sim.grid.terrain[index] = "water"
	t.check(sim.placement_error("storehouse", Vector2i(3,3), 1) == "Cannot build on water", "Rotated footprint checks terrain")
	# Delivery access is derived from actual occupied cells rather than the definition.
	sim = new_sim()
	t.check(sim.place_road([Vector2i(4,6),Vector2i(5,6),Vector2i(6,6),Vector2i(7,6)]), "Place delivery route beside rotated bottom edge")
	t.check(sim.place("storehouse", Vector2i(3,3), 1) and sim.place("well", Vector2i(7,5), 3), "Place rotated storehouse and water producer")
	var store = sim.buildings[1]
	t.check(sim.grid.access(store) == [Vector2i(4,6)], "Road access follows rotated depth")
	sim.step(120)
	t.check(store.inventory.count("water") > 0, "Carriers deliver to rotated storehouse")
	# Normalize supplied turns, without mutating shared content definitions.
	var other = Building.new(99,row,Vector2i.ZERO,-1)
	t.check(other.rotation_quarters == 3 and other.footprint() == Vector2i(2,3), "Negative rotation normalized to a quarter turn")
	t.check(row == original_row, "Rotation leaves content definition unchanged")
	var a = new_sim()
	var b = new_sim()
	a.place("storehouse",Vector2i(3,3),5)
	b.place("storehouse",Vector2i(3,3),1)
	a.step(10)
	for tick in 10: b.step(1)
	t.check(a.snapshot() == b.snapshot(), "Equivalent normalized orientations replay deterministically")
