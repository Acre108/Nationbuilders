class_name GridBuildingCompiler
extends RefCounted

## Compiler 1 retains shells; 2 adds rooms; 3 adds openings; 4 connects storeys.
## Invoked only by document commands; readers render the saved records.
const VERSION := 5
const SUPPORTED_VERSIONS := [1,2,3,4,5]
const WALL_THICKNESS := 0.2
const PARTITION_THICKNESS := 0.12
const SLAB_THICKNESS := {"floor":0.2, "ceiling":0.12, "roof":0.16}

static func compile(source: BuildingDefinition) -> BuildingDefinition:
	if not source.is_grid_layout() or not source.data.get("compiler_version") in SUPPORTED_VERSIONS: return null
	if source.data.compiler_version in [4,5]: return BuildingStoreys.compile(source)
	var next := source.copy()
	var level: Dictionary = next.data.storeys[0]
	if not BuildingGridLayout.validate(level.layout).is_empty(): return null
	for field in ["rooms", "walls", "openings", "slabs"]: level[field] = []
	level.erase("resolved_digest")
	if level.layout.cells.is_empty():
		if next.data.compiler_version >= 3: GridBuildingOpenings.apply(next.data)
		next.data.build_state = "layout_draft"
		return next
	var cells := BuildingGridLayout.cell_set(level.layout.cells)
	var edges := boundary_edges(cells)
	var points: Array[Vector2i] = []
	for point in edges: points.append(point)
	points.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var start := points[0]
	var cursor := start
	var direction: Vector2i = edges[start] - start
	var run_start := start
	# Topology validation guarantees a single closed, non-touching loop.
	for index in edges.size():
		var end: Vector2i = edges[cursor]
		var following: Vector2i = edges[end] - end
		if following != direction or end == start:
			level.walls.append(wall_record(level, run_start, end))
			run_start = end
			direction = following
		cursor = end
	if next.data.compiler_version >= 2:
		level.walls = room_walls(level)
		if next.data.compiler_version >= 3: GridBuildingOpenings.apply(next.data)
		level.rooms = room_records(level)
	for rect in slab_rectangles(cells):
		for slot in ["floor", "ceiling", "roof"]:
			level.slabs.append(slab_record(level, rect, slot))
	next.data.build_state = "shell"
	level.resolved_digest = resolved_digest(next.data)
	return next

static func _spaces(cells: Dictionary,ownership: Dictionary,start: Vector2i,direction: Vector2i) -> Array:
	var left := start
	var right := start + Vector2i.UP
	if direction == Vector2i.DOWN:
		left = start + Vector2i.LEFT
		right = start
	elif direction == Vector2i.LEFT:
		left = start - Vector2i.ONE
		right = start + Vector2i.LEFT
	elif direction == Vector2i.UP:
		left = start + Vector2i.UP
		right = start - Vector2i.ONE
	return [ownership.get(left,"") if cells.has(left) else "outside",ownership.get(right,"") if cells.has(right) else "outside"]

static func room_walls(level: Dictionary) -> Array:
	var layout: Dictionary = level.layout
	var cells := BuildingGridLayout.cell_set(layout.cells)
	var ownership := BuildingGridLayout.owners(layout)
	var groups := {}
	var boundary := boundary_edges(cells)
	# Unit edges are canonical; only equivalent spaces and directions may merge.
	for start: Vector2i in boundary:
		var direction: Vector2i = boundary[start]-start
		_add_edge(groups,start,direction,_spaces(cells,ownership,start,direction),"exterior")
	for cell: Vector2i in cells:
		var owner: String = ownership.get(cell,"")
		for step: Vector2i in [Vector2i.RIGHT,Vector2i.DOWN]:
			var neighbour := cell + step
			if not cells.has(neighbour) or owner == ownership.get(neighbour,""): continue
			var start := cell + step
			var direction := Vector2i.DOWN if step == Vector2i.RIGHT else Vector2i.RIGHT
			var spaces: Array = [owner,ownership.get(neighbour,"")] if step == Vector2i.RIGHT else [ownership.get(neighbour,""),owner]
			_add_edge(groups,start,direction,spaces,"partition")
	var result: Array = []
	var keys: Array = groups.keys()
	keys.sort()
	for key in keys:
		var group: Dictionary = groups[key]
		var direction: Vector2i = group.direction
		var starts: Array = group.starts
		starts.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.x*direction.x+a.y*direction.y < b.x*direction.x+b.y*direction.y)
		var run: Vector2i = starts[0]
		var end := run + direction
		for index in range(1,starts.size()):
			if starts[index] != end:
				result.append(room_wall_record(level,run,end,group.spaces,group.kind))
				run = starts[index]
			end = starts[index] + direction
		result.append(room_wall_record(level,run,end,group.spaces,group.kind))
	return result

static func _add_edge(groups: Dictionary,start: Vector2i,direction: Vector2i,spaces: Array,kind: String) -> void:
	var key := JSON.stringify([direction.x,direction.y,start.y if direction.x != 0 else start.x,spaces,kind])
	if not groups.has(key): groups[key] = {"direction":direction,"spaces":spaces,"kind":kind,"starts":[]}
	groups[key].starts.append(start)

static func room_wall_record(level: Dictionary,start: Vector2i,end: Vector2i,spaces: Array,kind: String) -> Dictionary:
	var wall := wall_record(level,start,end)
	wall.kind = kind
	wall.spaces = spaces.duplicate()
	wall.face_colours = []
	for id in spaces:
		var room := BuildingGridLayout.room_by_id(level.layout,id)
		wall.face_colours.append(room.get("colour", ""))
	if kind == "partition":
		wall.id = _id(level,"partition",[start.x,start.y,end.x,end.y])
		wall.thickness = PARTITION_THICKNESS
		wall.exterior_side = 0
		var from := _world(level,start)
		var to := _world(level,end)
		var extension := (to-from).normalized()*PARTITION_THICKNESS/2
		from -= extension
		to += extension
		wall.from = [from.x,0.0,from.z]
		wall.to = [to.x,0.0,to.z]
	return wall

static func room_records(level: Dictionary) -> Array:
	var result: Array = []
	var blocked := wall_cell_coverage(level)
	var unit := float(level.layout.cell_size)
	for room in level.layout.rooms:
		var occupied := BuildingGridLayout.cell_set(room.cells)
		var box := BuildingGridLayout.bounds(occupied)
		var corner := _world(level,box.position)
		var regions: Array = []
		for rect in slab_rectangles(occupied):
			var at := _world(level,rect.position)
			regions.append([float(at.x),float(at.z),rect.size.x*unit,rect.size.y*unit])
		var loop: Array = []
		var boundary := boundary_edges(occupied)
		if not boundary.is_empty():
			var point: Vector2i = boundary.keys()[0]
			var start := point
			for index in boundary.size():
				var at := _world(level,point)
				loop.append([float(at.x),float(at.z)])
				point = boundary[point]
				if point == start: break
		var net := 0.0
		for cell: Vector2i in occupied: net += (1.0 - union_area(blocked.get(cell,[]))) * unit * unit
		# Area accumulation can land on a JSON rounding boundary. Persist stable
		# square-metre summaries while retaining the original geometry precision.
		net = snappedf(net,0.000001)
		var loops: Array = [] if loop.is_empty() else [loop]
		if level.layout.get("courtyards",false): loops = boundary_loops(level,occupied)
		result.append({"id":room.id,"name":room.name,"role":room.role,"colour":room.colour,"bounds":[float(corner.x),float(corner.z),box.size.x*unit,box.size.y*unit],"regions":regions,"boundary_loops":loops,"gross_area":occupied.size()*unit*unit,"net_area":net})
	return result

static func boundary_loops(level: Dictionary,cells: Dictionary) -> Array:
	var remaining := boundary_edges(cells)
	var result: Array = []
	while not remaining.is_empty():
		var points: Array = remaining.keys()
		points.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		var start: Vector2i = points[0]
		var cursor := start
		var loop: Array = []
		while remaining.has(cursor):
			var point := _world(level,cursor)
			loop.append([float(point.x),float(point.z)])
			var next: Vector2i = remaining[cursor]
			remaining.erase(cursor)
			cursor = next
			if cursor == start: break
		result.append(loop)
	return result

static func wall_cell_coverage(level: Dictionary) -> Dictionary:
	var result := {}
	var unit := float(level.layout.cell_size)
	# Work in grid units so translated/fractional origins do not affect area.
	for wall in level.walls:
		var start := Vector2(float(wall.grid_from[0]),float(wall.grid_from[1]))
		var end := Vector2(float(wall.grid_to[0]),float(wall.grid_to[1]))
		var half := float(wall.thickness)/(2*unit)
		var direction := (end-start).normalized()
		var cuts: Array = level.openings.filter(func(record: Dictionary) -> bool: return record.wall_id == wall.id and record.bottom == 0 and record.kind != "window")
		cuts.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.offset < b.offset)
		var at := -half
		for opening in cuts:
			var center := (GridBuildingOpenings.anchor_vector(opening)-start).dot(direction)
			_coverage_piece(result,start+direction*at,start+direction*(center-float(opening.width)/(2*unit)),half)
			at = center+float(opening.width)/(2*unit)
		_coverage_piece(result,start+direction*at,end+direction*half,half)
	return result

static func _coverage_piece(result: Dictionary,start: Vector2,end: Vector2,half: float) -> void:
	var normal := Vector2(0,half) if start.y == end.y else Vector2(half,0)
	var low := start.min(end)-normal
	var high := start.max(end)+normal
	var rect := Rect2(low,high-low)
	for y in range(floori(low.y),ceili(high.y)):
		for x in range(floori(low.x),ceili(high.x)):
			var cell := Vector2i(x,y)
			var clipped := rect.intersection(Rect2(Vector2(cell),Vector2.ONE))
			if clipped.has_area():
				if not result.has(cell): result[cell] = []
				result[cell].append(clipped)

static func union_area(rectangles: Array) -> float:
	if rectangles.is_empty(): return 0.0
	var cuts: Array = []
	for rect: Rect2 in rectangles:
		if not rect.position.x in cuts: cuts.append(rect.position.x)
		if not rect.end.x in cuts: cuts.append(rect.end.x)
	cuts.sort()
	var area := 0.0
	for index in range(cuts.size()-1):
		var intervals: Array[Vector2] = []
		for rect: Rect2 in rectangles:
			if rect.position.x < cuts[index+1] and rect.end.x > cuts[index]: intervals.append(Vector2(rect.position.y,rect.end.y))
		if intervals.is_empty(): continue
		intervals.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x < b.x)
		var total := 0.0
		var low := intervals[0].x
		var high := intervals[0].y
		for interval in intervals.slice(1):
			if interval.x > high:
				total += high-low
				low = interval.x
				high = interval.y
			else: high = maxf(high,interval.y)
		total += high-low
		area += (cuts[index+1]-cuts[index])*total
	return clampf(area,0,1)

static func boundary_edges(cells: Dictionary) -> Dictionary:
	var edges := {}
	for cell: Vector2i in cells:
		if not cells.has(cell + Vector2i.UP): edges[cell] = cell + Vector2i.RIGHT
		if not cells.has(cell + Vector2i.RIGHT): edges[cell + Vector2i.RIGHT] = cell + Vector2i.ONE
		if not cells.has(cell + Vector2i.DOWN): edges[cell + Vector2i.ONE] = cell + Vector2i.DOWN
		if not cells.has(cell + Vector2i.LEFT): edges[cell + Vector2i.DOWN] = cell
	return edges

static func slab_rectangles(cells: Dictionary) -> Array[Rect2i]:
	# Merge equal horizontal spans in neighbouring rows. No bounding-box fill.
	var box := BuildingGridLayout.bounds(cells)
	var active := {}
	var rectangles: Array[Rect2i] = []
	for y in range(box.position.y, box.end.y):
		var spans := {}
		var x := box.position.x
		while x < box.end.x:
			if not cells.has(Vector2i(x,y)):
				x += 1
				continue
			var left := x
			while x < box.end.x and cells.has(Vector2i(x,y)): x += 1
			var key := Vector2i(left,x-left)
			var rect: Rect2i = active.get(key, Rect2i(left,y,x-left,0))
			rect.size.y += 1
			spans[key] = rect
		for key in active:
			if not spans.has(key): rectangles.append(active[key])
		active = spans
	for key in active: rectangles.append(active[key])
	rectangles.sort_custom(func(a: Rect2i,b: Rect2i) -> bool: return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	return rectangles

static func _id(level: Dictionary, kind: String, anchor: Array) -> String:
	return "grid-" + kind + "-" + JSON.stringify([level.id,anchor]).sha256_text().substr(0,24)

static func _world(level: Dictionary, point: Vector2i) -> Vector3:
	return Vector3(float(level.layout.origin[0]) + point.x * float(level.layout.cell_size),0,float(level.layout.origin[1]) + point.y * float(level.layout.cell_size))

static func wall_record(level: Dictionary, start: Vector2i, end: Vector2i) -> Dictionary:
	var from := _world(level,start)
	var to := _world(level,end)
	var extension := (to-from).normalized() * WALL_THICKNESS/2
	# Extend both ends into the corner joint, including reflex corners.
	from -= extension
	to += extension
	return {"id":_id(level,"wall",[start.x,start.y,end.x,end.y]),"grid_from":[start.x,start.y],"grid_to":[end.x,end.y],"from":[from.x,0.0,from.z],"to":[to.x,0.0,to.z],"height":float(level.height),"thickness":WALL_THICKNESS,"exterior_side":-1,"openings":[]}

static func slab_record(level: Dictionary, rect: Rect2i, slot: String) -> Dictionary:
	var unit := float(level.layout.cell_size)
	var center := _world(level,rect.position) + Vector3(rect.size.x*unit/2,0,rect.size.y*unit/2)
	var thickness: float = SLAB_THICKNESS[slot]
	center.y = -thickness/2 if slot == "floor" else float(level.height) + thickness/2
	if slot == "roof": center.y += float(SLAB_THICKNESS.ceiling)
	var anchor := [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
	return {"id":_id(level,slot,anchor),"grid_rect":anchor,"slot":slot,"center":[center.x,center.y,center.z],"size":[rect.size.x*unit,thickness,rect.size.y*unit]}

static func resolved_digest(data: Dictionary) -> String:
	var level: Dictionary = data.storeys[0]
	# Canonical JSON tolerates the reader's double-precision ULP differences.
	var records := [data.compiler_version,level.layout_digest,level.height,level.rooms,level.walls,level.openings,level.slabs]
	if data.compiler_version >= 3: records.append(level.get("unresolved_openings",[]))
	return JSON.stringify(records,"",true).sha256_text()

static func _same_numbers(a: Variant,b: Array) -> bool:
	if not BuildingDefinition.numbers(a,b.size()): return false
	for index in b.size():
		if absf(float(a[index])-float(b[index])) > 0.000001: return false
	return true

static func _integer_anchor(value: Variant,count: int) -> bool:
	if not BuildingDefinition.numbers(value,count): return false
	for number in value:
		if float(number) != floor(float(number)) or absf(float(number)) > BuildingGridLayout.MAX_COORDINATE + 121: return false
	return true

static func validate_shell(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var level: Dictionary = data.storeys[0]
	if level.layout.cells.is_empty(): return PackedStringArray(["An empty footprint cannot have a shell."])
	if level.get("resolved_digest") != resolved_digest(data): errors.append("Saved shell disagrees with its layout or resolved digest. Source file is preserved; explicit repair is required.")
	var occupied := BuildingGridLayout.cell_set(level.layout.cells)
	var edges := boundary_edges(occupied)
	var covered_edges := {}
	var ids := {str(data.id):true,str(level.id):true}
	if data.compiler_version >= 2:
		errors.append_array(_validate_room_structure(level,ids,data.compiler_version))
	if data.compiler_version >= 3 and errors.is_empty():
		errors.append_array(GridBuildingOpenings.validate_resolved(data))
		if errors.is_empty():
			for opening in level.openings+level.unresolved_openings: BuildingDefinition._register_id(opening,ids,errors)
	for wall in level.walls if data.compiler_version == 1 else []:
		if not wall is Dictionary or not _integer_anchor(wall.get("grid_from"),2) or not _integer_anchor(wall.get("grid_to"),2):
			errors.append("Invalid grid wall anchor.")
			continue
		BuildingDefinition._register_id(wall,ids,errors)
		var start := Vector2i(int(wall.grid_from[0]),int(wall.grid_from[1]))
		var end := Vector2i(int(wall.grid_to[0]),int(wall.grid_to[1]))
		if start == end or (start.x != end.x and start.y != end.y) or start.distance_to(end) > 121:
			errors.append("Invalid orthogonal wall run.")
			continue
		var expected := wall_record(level,start,end)
		if wall.get("id") != expected.id or not _same_numbers(wall.get("from"),expected.from) or not _same_numbers(wall.get("to"),expected.to) or not _same_numbers([wall.get("height"),wall.get("thickness")],[expected.height,expected.thickness]) or wall.get("exterior_side") != -1 or wall.get("openings") != []:
			errors.append("Wall geometry disagrees with its painted boundary.")
		var direction := (end-start).sign()
		var cursor := start
		while cursor != end:
			if edges.get(cursor) != cursor+direction or covered_edges.has(cursor): errors.append("Wall is duplicated or not on the exterior boundary.")
			covered_edges[cursor] = true
			cursor += direction
	if data.compiler_version == 1 and covered_edges.size() != edges.size(): errors.append("Saved exterior walls do not cover the painted perimeter.")
	var coverage := {"floor":{},"ceiling":{},"roof":{}}
	for slab in level.slabs:
		if not slab is Dictionary or not _integer_anchor(slab.get("grid_rect"),4) or not slab.get("slot") in SLAB_THICKNESS:
			errors.append("Invalid grid slab anchor or surface.")
			continue
		BuildingDefinition._register_id(slab,ids,errors)
		var rect := Rect2i(int(slab.grid_rect[0]),int(slab.grid_rect[1]),int(slab.grid_rect[2]),int(slab.grid_rect[3]))
		if rect.size.x <= 0 or rect.size.y <= 0 or rect.size.x > (160 if level.layout.get("courtyards",false) else 120) or rect.size.y > (160 if level.layout.get("courtyards",false) else 120):
			errors.append("Invalid slab extent.")
			continue
		var expected := slab_record(level,rect,slab.slot)
		if slab.get("id") != expected.id or not _same_numbers(slab.get("center"),expected.center) or not _same_numbers(slab.get("size"),expected.size): errors.append("Slab geometry disagrees with its painted region.")
		var covered: Dictionary = coverage[slab.slot]
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var cell := Vector2i(x,y)
				if not occupied.has(cell) or covered.has(cell): errors.append("Slabs overlap or cover outside the footprint.")
				covered[cell] = true
	for slot in coverage:
		if coverage[slot].size() != occupied.size(): errors.append("Saved " + slot + " does not cover the footprint.")
	return errors

static func _validate_room_structure(level: Dictionary,ids: Dictionary,version: int) -> PackedStringArray:
	var errors := PackedStringArray()
	var expected := {}
	for wall in room_walls(level): expected[wall.id] = wall
	for wall in level.walls:
		if not wall is Dictionary:
			errors.append("Invalid resolved room boundary.")
			continue
		BuildingDefinition._register_id(wall,ids,errors)
		if version >= 3 and not wall.get("openings") is Array:
			errors.append("Missing wall opening references.")
			continue
		if not expected.has(wall.get("id")):
			errors.append("Unexpected or stale room boundary.")
			continue
		for field in expected[wall.id]:
			if field == "openings" and version >= 3: continue
			if JSON.stringify(wall.get(field),"",true) != JSON.stringify(expected[wall.id][field],"",true): errors.append("Room boundary geometry or face ownership disagrees with layout.")
		expected.erase(wall.id)
	if not expected.is_empty(): errors.append("Room partitions or exterior boundaries are missing.")
	if not errors.is_empty(): return errors
	for room in room_records(level): expected[room.id] = room
	for room in level.rooms:
		if not room is Dictionary:
			errors.append("Invalid resolved room.")
			continue
		BuildingDefinition._register_id(room,ids,errors)
		if not expected.has(room.get("id")):
			errors.append("Unexpected or stale resolved room ID.")
			continue
		for field in expected[room.id]:
			if field == "net_area":
				# Accept earlier compiler-2 summaries before the precision fix.
				if not BuildingDefinition.numbers([room.get(field)],1) or absf(float(room[field])-float(expected[room.id][field])) > 0.00001: errors.append("Resolved usable area disagrees with painted cells.")
				continue
			if JSON.stringify(room.get(field),"",true) != JSON.stringify(expected[room.id][field],"",true): errors.append("Resolved room regions, metadata or areas disagree with painted cells.")
		expected.erase(room.id)
	if not expected.is_empty(): errors.append("Resolved rooms are missing.")
	return errors
