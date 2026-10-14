extends RefCounted
const WorldGen = preload("res://sim/world/world_gen.gd")
const SiteGen = preload("res://sim/world/site_gen.gd")
const Layout = preload("res://sim/world/terrain_layout.gd")
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Grid = preload("res://sim/grid.gd")
const IntNoise = preload("res://sim/world/int_noise.gd")
## Random sites built and baked per seed, besides each seed's start and lake site.
const SITES_PER_SEED := 2
var completed := false

func run(t) -> void:
	_water_fixtures(t)
	var count := 0
	var rivers := 0
	var lakes := 0
	var coasts := 0
	for seed_value in [73,1,2]:
		var world = WorldGen.generate(seed_value)
		var start_site = SiteGen.generate(world,world.start)
		t.check(start_site.error().is_empty(),"Start region has a viable natural founding clearing for seed %d" % seed_value)
		for lake_coord in world.hexes:
			if not world.hex(lake_coord).lake or not world.data.biomes[world.hex(lake_coord).biome].settleable: continue
			var lake_site = SiteGen.generate(world,lake_coord)
			var lake_tiles := 0
			for index in lake_site.terrain.size():
				if lake_site.terrain[index] == "lake" and lake_site.owner_coords[index] == lake_coord: lake_tiles += 1
			t.check(lake_site.error().is_empty() and lake_tiles > 500,"Actual generated lake site keeps its basin and a natural clearing for seed %d" % seed_value)
			break
		var mouths_match := true
		for owner in world.hexes:
			for edge in world.hex(owner).river_edges:
				var other: Vector2i = world.neighbour(owner,int(edge))
				if not world.has(other) or not world.hex(other).river_edges.has(world.opposite(int(edge))): continue
				var first := Layout.river_path(world,owner,int(edge))
				var second := Layout.river_path(world,other,world.opposite(int(edge)))
				if first[-1].distance_to(second[-1]) > 0.00001: mouths_match = false
		t.check(mouths_match,"Shared river edge positions agree from both sides for seed %d" % seed_value)
		var checked := 0
		var candidates: Array[Vector2i] = [world.start]
		for coord in world.hexes:
			if coord != world.start and world.found_blocked(coord).is_empty(): candidates.append(coord)
		candidates.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return IntNoise.mix(seed_value,a.x,a.y,310) < IntNoise.mix(seed_value,b.x,b.y,310))
		for coord in candidates:
			var site = SiteGen.generate(world, coord)
			if not site.error().is_empty(): continue
			print("SITE GENERATED seed %d coord %s" % [seed_value,coord])
			var label := "seed %d hex %s" % [seed_value,coord]
			t.check(site.width == 144 and site.height == 168 and site.owner_coords.size() == site.width * site.height, "Hex site has full backing and ownership: " + label)
			t.check(site.playability_result.ok and site.playability_result.founding_cells >= 250 and site.playability_result.reach_cells >= 800, "Connected founding land and reach: " + label)
			var grid = Grid.new(site)
			t.check(not grid.inside(Vector2i.ZERO) and not grid.in_reach(Vector2i.ZERO) and grid.terrain_at(Vector2i.ZERO) == "void", "Physical hex masks rectangular corners: " + label)
			var sim = Sim.new(site.seed_value,null,site)
			t.check(not sim.place("well",Vector2i.ZERO) and not sim.place_road([Vector2i.ZERO]), "Commands reject exterior hex cells: " + label)
			grid.roads[Vector2i.ZERO] = true
			t.check(grid.astar(Vector2i.ZERO,Vector2i.ZERO).is_empty() and not grid.passable(Vector2i.ZERO,Vector2i.RIGHT), "Even injected exterior roads cannot route: " + label)
			var aligned := true
			var relief_aligned := true
			var boundary_aligned := true
			var deposit_owners := {}
			for y in site.height:
				for x in site.width:
					var cell := Vector2i(x,y)
					var local: Vector2 = site.world_point(cell) - Layout.centre(coord)
					if site.inside(cell) != SiteGen._outer_hex(local): boundary_aligned = false
					if not site.inside(cell): continue
					var owner: Vector2i = site.owner_coords[site.index(cell)]
					var water: String = Layout.water_at(world,owner,site.world_point(cell))
					if not water.is_empty() and site.terrain[site.index(cell)] != water: aligned = false
					var info = world.hex(owner)
					var expected_level: int = info.elevation * 2 + int(floor(Layout.relief_at(world,owner,site.world_point(cell)) * 8.0)) if info.is_land() else 0
					if site.levels[site.index(cell)] != expected_level: relief_aligned = false
					var deposit: String = site.deposits[site.index(cell)]
					if not deposit.is_empty(): deposit_owners["%s:%s" % [owner,deposit]] = true
			t.check(aligned,"Every village water cell matches shared river/lake/coast geometry: " + label)
			t.check(relief_aligned,"Relief bands and ridges retain their shared layout: " + label)
			t.check(boundary_aligned,"Visible and playable physical mask is one regular hex: " + label)
			var deposits_present := true
			for deposit in world.hex(coord).deposits:
				if not deposit_owners.has("%s:%s" % [coord,deposit]): deposits_present = false
			t.check(deposits_present,"Selected tile's promised deposits remain in their own district: " + label)
			t.check(not site.promised_water or site.playability_result.water_distance <= 8,"Promised water near the founding clearing: " + label)
			t.check(Scenario.starter(sim),"Real-command starter fits without terraforming: " + label)
			sim.step(600)
			t.check(sim.unlocked_tier == 2 and Scenario.complete_chain(sim),"Generated site reaches Villagers and completes chain: " + label)
			sim.step(900)
			t.check(int(sim.produced.get("bread",0)) > 0,"Generated-site village bakes bread: " + label)
			if count == 0:
				var again = SiteGen.generate(world,coord)
				t.check(site.terrain == again.terrain and site.levels == again.levels and site.ramps == again.ramps and site.deposits == again.deposits and site.footprint == again.footprint and site.founding_spot == again.founding_spot,"Identical seed and coord regenerate identical site")
			for owner in world.reach(coord):
				rivers += 1 if not world.hex(owner).river_edges.is_empty() else 0
				lakes += 1 if world.hex(owner).lake else 0
				coasts += 1 if not world.hex(owner).coast_edges.is_empty() else 0
			count += 1
			checked += 1
			if checked >= SITES_PER_SEED: break
		t.check(checked >= SITES_PER_SEED,"At least %d playable sites generated for seed %d" % [SITES_PER_SEED,seed_value])
	t.check(count >= SITES_PER_SEED * 3,"Random settleable sites across three seeds bake bread")
	t.check(rivers > 0 and coasts > 0,"Aligned sites include promised rivers and coasts")
	print("SITE COVERAGE: %d sites, %d river districts, %d lakes, %d coasts" % [count,rivers,lakes,coasts])
	completed = true

func _water_fixtures(t) -> void:
	var world = WorldGen.generate(73)
	var coord: Vector2i = world.start
	var descriptor = world.hex(coord)
	descriptor.lake = true
	descriptor.river_edges = {0:3,2:1,4:2}
	descriptor.coast_edges.clear()
	descriptor.coast_edges.append(1)
	descriptor.forest = 0.0
	descriptor.deposits.clear()
	var site = SiteGen.generate(world,coord)
	var lake_cells := 0
	var ocean_cells := 0
	var forest_cells := 0
	for y in site.height:
		for x in site.width:
			var cell := Vector2i(x,y)
			if not site.inside(cell) or site.owner_coords[site.index(cell)] != coord: continue
			if site.terrain[site.index(cell)] == "lake": lake_cells += 1
			if site.terrain[site.index(cell)] == "ocean": ocean_cells += 1
			if site.terrain[site.index(cell)] == "forest": forest_cells += 1
	t.check(lake_cells > 500 and ocean_cells > 0,"Lake basin and coastal inset survive even if the natural starter is unsuitable")
	t.check(forest_cells == 0,"A district with zero promised forest cover contains no woodland resources")
	for edge in descriptor.river_edges:
		var path := Layout.river_path(world,coord,int(edge))
		var point: Vector2 = path[-1] * 0.95 + path[0] * 0.05
		var local := Vector2i(((point-site.world_origin) * (site.hex_width / 2.0)).floor())
		var nearby_water := false
		for y in range(local.y-1,local.y+2):
			for x in range(local.x-1,local.x+2):
				var cell := Vector2i(x,y)
				if site.inside(cell) and site.terrain[site.index(cell)] in Grid.WATER: nearby_water = true
		t.check(nearby_water,"Confluence retains promised edge %d mouth and width class %d" % [edge,descriptor.river_edges[edge]])

