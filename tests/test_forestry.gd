extends RefCounted
const Sim = preload("res://sim/village_sim.gd")
const Site = preload("res://sim/world/site_package.gd")
const Scenario = preload("res://sim/scenario.gd")

func fixture(tree_cells: Array = []):
	var site = Site.new(24,24)
	site.founding_spot = Vector2i(3,3)
	for cell in tree_cells:
		site.terrain[site.index(cell)] = "forest"
		site.deposits[site.index(cell)] = "timber"
	return Sim.new(73,null,site)

func run(t) -> void:
	var sim = Sim.new()
	t.check(sim.grid.trees.size() > 1500,"Default map contains over 1500 actual trees")
	var groves := 0
	var clearings := 0
	for by in range(0,80,8):
		for bx in range(0,80,8):
			var count := 0
			for y in range(by,by+8):
				for x in range(bx,bx+8):
					if sim.grid.trees.has(Vector2i(x,y)): count += 1
			if count > 8: groves += 1
			if count < 3: clearings += 1
	t.check(groves > 50 and clearings > 5,"Woodland has broad groves and separate clearings")
	t.check(Scenario.starter(sim),"Starter fits in the central clearing")
	var entry: Vector2i = sim.site.entrance_road[0]
	t.check(entry.x == 0 and sim.grid.astar(entry,sim.site.founding_spot+Vector2i(0,-1)).size() > 40,"Incoming road connects the western boundary to the centre")
	var clear := true
	for cell in sim.grid.trees:
		if sim.site.settlement_clearance.has_point(cell): clear = false
	t.check(clear and sim.site.settlement_clearance.get_area() == 240,"Central clearing leaves open space around starting buildings")
	_cutting(t)
	_planting(t)
	_obstacles(t)
	var a = Sim.new(919)
	var b = Sim.new(919)
	for village in [a,b]:
		Scenario.starter(village)
		t.check(village.place("forester",Vector2i(26,18)+Scenario.offset(village)),"Forester fits beside the eastern road")
		# Spend founding logs below the storehouse limit, so harvested logs are hauled in.
		village._pay({"logs":50})
	a.step(1300)
	for batch in 130: b.step(10)
	t.check(a.snapshot() == b.snapshot(),"Forestry and regrowth are deterministic across tick batches")
	t.check(a.produced.get("logs",0) > 0 and a.stock("logs") > 19 and not a.grid.saplings.is_empty(),"Carriers collect actual harvested logs while foresters replace trees")
	var state: Dictionary = a.snapshot()
	state.trees.clear()
	state.saplings.clear()
	t.check(not a.grid.trees.is_empty() and not a.grid.saplings.is_empty(),"Snapshots do not expose mutable tree collections")
	var db = preload("res://sim/content_db.gd").new()
	db.load_directory()
	var rows: Array = db.buildings.values().duplicate(true)
	for row in rows:
		if row.id == "forester": row.work_radius = 0
	t.check(not db.validate(db.goods.values(),rows,db.tiers.values()),"Content rejects invalid forestry radius")

func _cutting(t) -> void:
	var tree := Vector2i(7,4)
	var sim = fixture([tree])
	t.check(sim.place("woodcutter",Vector2i(4,4)),"Place woodcutter near actual timber")
	var cutter = sim.buildings.values()[0]
	var revision: int = sim.grid.revision
	sim.step(64)
	t.check(sim.grid.trees.has(tree) and cutter.output.count("logs") == 0,"Tree remains until the cutting cycle completes")
	sim.step()
	t.check(not sim.grid.trees.has(tree) and sim.grid.stumps.has(tree) and cutter.output.count("logs") == 1,"Harvest removes one tree, leaves a stump and produces one log")
	t.check(sim.grid.terrain_at(tree) == "grass" and sim.grid.deposits[sim.site.index(tree)].is_empty(),"Harvest clears timber terrain for construction")
	t.check(sim.grid.revision == revision and sim.grid.forest_revision == 1,"Forestry leaves road route caches valid")
	sim.step(130)
	t.check(cutter.status == "no mature trees nearby" and sim.produced.logs == 1,"Woodcutter stops when local trees run out")
	t.check(sim.place("well",tree) and not sim.grid.stumps.has(tree),"Build on harvested ground and clear its stump")
	var full = fixture([tree])
	full.place("woodcutter",Vector2i(4,4))
	var blocked = full.buildings.values()[0]
	blocked.output.add("logs",6)
	full.step(65)
	t.check(full.grid.trees.has(tree) and blocked.status == "output full","Full stock prevents wasting a tree")
	full.set_workers_enabled(blocked.uid,false)
	blocked.output.take("logs",6)
	full.step(65)
	t.check(full.grid.trees.has(tree) and blocked.status == "workers stopped","Stopped workers do not fell trees")
	full.set_workers_enabled(blocked.uid,true)
	full.step(65)
	t.check(not full.grid.trees.has(tree),"Resumed workers harvest a real tree")

func _planting(t) -> void:
	var sim = fixture()
	sim.grid.settlement_clearance = Rect2i(3,3,5,5)
	sim.place("forester",Vector2i(4,4))
	sim.step(50)
	t.check(sim.grid.saplings.size() == 1 and sim.grid.trees.is_empty(),"Forester plants a young sapling after one cycle")
	var cell: Vector2i = sim.grid.saplings.keys()[0]
	t.check(not sim.grid.settlement_clearance.has_point(cell),"Forester preserves the designated settlement clearing")
	t.check(sim.produced.is_empty(),"Planting creates trees instead of phantom goods")
	sim.set_workers_enabled(1,false)
	sim.step(599)
	t.check(sim.grid.saplings.has(cell),"Sapling remains unharvestable until mature")
	sim.step()
	t.check(sim.grid.trees.has(cell) and not sim.grid.saplings.has(cell) and sim.grid.terrain_at(cell) == "forest","Sapling matures after 600 ticks even with forester stopped")
	t.check(sim.grid.deposits[sim.site.index(cell)] == "timber","Mature tree restores a timber deposit")
	var cleared = fixture()
	cleared.place("forester",Vector2i(4,4))
	cleared.step(50)
	var planting: Vector2i = cleared.grid.saplings.keys()[0]
	t.check(cleared.place_road([planting]),"Road construction clears a sapling")
	cleared.set_workers_enabled(1,false)
	cleared.step(650)
	t.check(not cleared.grid.saplings.has(planting) and not cleared.grid.trees.has(planting),"Cleared saplings never regrow through roads")
	var protected = fixture()
	protected.grid.settlement_clearance = Rect2i(0,0,24,24)
	protected.place("forester",Vector2i(4,4))
	protected.step()
	t.check(protected.buildings.values()[0].status == "no planting space nearby","Forester reports an unavailable work area")

func _obstacles(t) -> void:
	var tree := Vector2i(8,5)
	var sim = fixture([tree])
	sim.place("woodcutter",Vector2i(4,4))
	sim.place("woodcutter",Vector2i(10,4))
	sim.step(65)
	t.check(sim.produced.logs == 1,"Two cutters cannot harvest the same tree twice")
	var river = fixture([Vector2i(12,4),Vector2i(23,23)])
	for y in river.grid.height: river.grid.terrain[y*24+8] = "river"
	river.place("woodcutter",Vector2i(4,4))
	river.step(100)
	t.check(river.produced.is_empty(),"Water and work radius prevent unreachable harvests")
	var cliff = fixture([tree])
	for y in cliff.grid.height:
		for x in range(8,24): cliff.grid.levels[y*24+x] = 1
	cliff.place("woodcutter",Vector2i(4,4))
	cliff.step(65)
	t.check(cliff.grid.trees.has(tree),"Cliffs block forestry access")
	cliff.grid.ramps[cliff.site.index(Vector2i(8,5))] = 1
	cliff.grid.changed()
	cliff.step(65)
	t.check(not cliff.grid.trees.has(tree),"Ramps provide access to plateau timber")
	var invalid = fixture([tree])
	var snapshot: Dictionary = invalid.snapshot()
	t.check(not invalid.place_road([tree,Vector2i(24,0)]) and snapshot == invalid.snapshot(),"Rejected construction never clears trees")
