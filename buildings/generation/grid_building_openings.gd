class_name GridBuildingOpenings
extends RefCounted

const KINDS := ["door","window","entrance","passage"]
const MAX_OPENINGS := 128
const MARGIN := 0.15

static func validate(layout: Dictionary,height: float) -> PackedStringArray:
	var errors := PackedStringArray()
	var records: Variant = layout.get("openings",[])
	if not records is Array or records.size() > MAX_OPENINGS: return PackedStringArray(["A plan supports up to 128 openings."])
	var ids := {}
	var entrances := 0
	for room in layout.rooms: ids[room.id] = true
	for record in records:
		if not record is Dictionary or not BuildingDefinition.valid_id(record.get("id")) or ids.has(record.get("id")):
			errors.append("Invalid or duplicate opening ID.")
			continue
		ids[record.id] = true
		if record.get("kind") == "entrance": entrances += 1
		if not record.get("kind") in KINDS or not record.get("axis") in ["x","y"] or not BuildingDefinition.numbers(record.get("anchor"),2):
			errors.append("Invalid opening kind or boundary anchor.")
			continue
		for value in record.anchor:
			if absf(float(value)) > BuildingGridLayout.MAX_COORDINATE+1 or not is_equal_approx(float(value)*2,roundf(float(value)*2)): errors.append("Opening centres must snap to grid edges or half-cell positions.")
		var line := float(record.anchor[1 if record.axis == "x" else 0])
		if line != roundf(line): errors.append("Opening anchor must lie on a grid boundary.")
		if not BuildingDefinition.numbers([record.get("width"),record.get("height"),record.get("bottom")],3):
			errors.append("Invalid opening dimensions.")
			continue
		if record.width < 0.6 or record.width > 6 or record.height < 0.4 or record.bottom < 0 or record.bottom+record.height > height: errors.append("Opening dimensions must fit the wall height; width is 0.6–6 m.")
		if record.kind != "window" and (record.bottom != 0 or record.width < 0.9 or record.height < 2.1): errors.append("Doors and passages need a level threshold, at least 0.9 m width and 2.1 m height.")
		if record.kind == "entrance" and record.width < 1.2: errors.append("The entrance needs at least 1.2 m clear width.")
	if entrances > 1: errors.append("One arrival entrance is supported. Use Door for additional exterior doorways.")
	return errors

static func wall_axis(wall: Dictionary) -> String:
	return "x" if wall.grid_from[1] == wall.grid_to[1] else "y"

static func anchor_vector(record: Dictionary) -> Vector2:
	return Vector2(float(record.anchor[0]),float(record.anchor[1]))

static func wall_center(level: Dictionary,record: Dictionary) -> Vector3:
	return Vector3(float(level.layout.origin[0])+float(record.anchor[0])*float(level.layout.cell_size),0,float(level.layout.origin[1])+float(record.anchor[1])*float(level.layout.cell_size))

static func resolve(level: Dictionary) -> Dictionary:
	var openings: Array = []
	var conflicts: Array = []
	var references := {}
	for wall in level.walls: references[wall.id] = []
	for record in level.layout.get("openings",[]):
		var matched := {}
		var reason := "The original boundary no longer exists. Move or delete this opening."
		var point := anchor_vector(record)
		for wall in level.walls:
			if wall_axis(wall) != record.axis: continue
			var a := Vector2(float(wall.grid_from[0]),float(wall.grid_from[1]))
			var b := Vector2(float(wall.grid_to[0]),float(wall.grid_to[1]))
			var direction := (b-a).normalized()
			var along := (point-a).dot(direction)
			if absf((point-a).cross(direction)) > 0.00001 or along < 0 or along > a.distance_to(b): continue
			if record.kind in ["window","entrance"] and wall.kind != "exterior":
				reason = "Windows and entrances need an exterior wall."
				continue
			var unit := float(level.layout.cell_size)
			if along*unit-float(record.width)/2 < MARGIN or (a.distance_to(b)-along)*unit-float(record.width)/2 < MARGIN:
				reason = "Too close to a corner or wall junction; leave 0.15 m at each end."
				continue
			var center := wall_center(level,record)
			var offset := center.distance_to(BuildingDefinition.vector(wall.from))
			matched = record.duplicate(true)
			matched.wall_id = wall.id
			matched.offset = offset
			matched.spaces = wall.spaces.duplicate()
			for previous in openings:
				if previous.wall_id == wall.id and absf(float(previous.offset)-offset) < (float(previous.width)+float(record.width))/2+0.1:
					matched = {}
					reason = "Openings overlap or leave less than 0.1 m between them."
					break
			break
		if matched.is_empty():
			var conflict: Dictionary = record.duplicate(true)
			conflict.reason = reason
			conflicts.append(conflict)
		else:
			openings.append(matched)
			references[matched.wall_id].append(matched.id)
	return {"openings":openings,"conflicts":conflicts,"references":references}

static func apply(data: Dictionary) -> void:
	var level: Dictionary = data.storeys[0]
	var resolved := resolve(level)
	level.openings = resolved.openings
	level.unresolved_openings = resolved.conflicts
	for wall in level.walls: wall.openings = resolved.references[wall.id]
	data.entrance_id = ""
	data.visit_spawn = [0.0,0.0,0.0]
	for record in level.openings:
		if record.kind != "entrance": continue
		data.entrance_id = record.id
		var wall: Dictionary = level.walls.filter(func(item: Dictionary) -> bool: return item.id == record.wall_id)[0]
		var direction := (BuildingDefinition.vector(wall.to)-BuildingDefinition.vector(wall.from)).normalized()
		var outside := Vector3(-direction.z,0,direction.x)*(1 if wall.spaces[0] == "outside" else -1)
		var spawn := wall_center(level,record)+outside
		data.visit_spawn = [spawn.x,0.0,spawn.z]
		break

static func validate_resolved(data: Dictionary) -> PackedStringArray:
	var level: Dictionary = data.storeys[0]
	var expected := data.duplicate(true)
	apply(expected)
	var errors := PackedStringArray()
	for field in ["openings","unresolved_openings"]:
		if JSON.stringify(level.get(field),"",true) != JSON.stringify(expected.storeys[0][field],"",true): errors.append("Saved openings or conflicts disagree with their anchors.")
	for index in level.walls.size():
		if level.walls[index].openings != expected.storeys[0].walls[index].openings: errors.append("Wall opening references disagree with their anchors.")
	if data.get("entrance_id") != expected.entrance_id or not GridBuildingCompiler._same_numbers(data.get("visit_spawn"),expected.visit_spawn): errors.append("Entrance spawn disagrees with its exterior boundary.")
	return errors

static func snap(level: Dictionary,point: Vector2,kind: String,width: float,height: float,bottom: float,max_distance: float) -> Dictionary:
	var best := {}
	var distance := max_distance
	for wall in level.walls:
		if kind in ["window","entrance"] and wall.get("kind","exterior") != "exterior": continue
		var a := Vector2(float(wall.grid_from[0]),float(wall.grid_from[1]))
		var b := Vector2(float(wall.grid_to[0]),float(wall.grid_to[1]))
		var axis := wall_axis(wall)
		var at := Vector2(clampf(snappedf(point.x,0.5),minf(a.x,b.x),maxf(a.x,b.x)),a.y) if axis == "x" else Vector2(a.x,clampf(snappedf(point.y,0.5),minf(a.y,b.y),maxf(a.y,b.y)))
		var nearest := Vector2(clampf(point.x,minf(a.x,b.x),maxf(a.x,b.x)),a.y) if axis == "x" else Vector2(a.x,clampf(point.y,minf(a.y,b.y),maxf(a.y,b.y)))
		var away := point.distance_to(nearest)
		if away > distance: continue
		distance = away
		best = {"kind":kind,"axis":axis,"anchor":[float(at.x),float(at.y)],"width":width,"height":height,"bottom":bottom}
	return best

## Clearance map uses the standing visitor's circular horizontal cross section.
## Wall pieces and glass match the runtime cuts; reachability includes unassigned
## circulation cells. Quarter-metre samples conservatively connect clear paths.
static func access_report(definition: BuildingDefinition, start_points: Array = [], allow_outside: bool = true, barriers: Array[Rect2] = []) -> Dictionary:
	if definition.data.get("compiler_version") in [4,5]: return BuildingStoreys.access_report(definition)
	var issues: Array[String] = []
	var inaccessible: Array[String] = []
	if not definition.has_grid_shell() or definition.data.compiler_version < 3: return {"ok":false,"issues":["Place an exterior entrance and connecting doors before visiting."],"inaccessible":[],"reached":{}}
	var data: Dictionary = definition.data
	var level: Dictionary = data.storeys[0]
	if not level.get("unresolved_openings",[]).is_empty(): issues.append("Repair or delete %d displaced opening(s)." % level.unresolved_openings.size())
	var has_start: bool = not data.entrance_id.is_empty() or not start_points.is_empty()
	if not has_start: issues.append("Place an exterior entrance." if allow_outside else "No reachable stair landing.")
	var blocked: Array[Rect2] = barriers.duplicate()
	blocked.append_array(BuildingFurniture.barriers(data,level.id))
	issues.append_array(BuildingFurniture.conflicts(data))
	for wall in level.walls:
		var a3 := BuildingDefinition.vector(wall.from)
		var b3 := BuildingDefinition.vector(wall.to)
		var a := Vector2(a3.x,a3.z)
		var b := Vector2(b3.x,b3.z)
		var direction := (b-a).normalized()
		var holes: Array = level.openings.filter(func(item: Dictionary) -> bool: return item.wall_id == wall.id and item.kind != "window")
		holes.sort_custom(func(x: Dictionary,y: Dictionary) -> bool: return x.offset < y.offset)
		var cursor := 0.0
		for hole in holes:
			_add_block(blocked,a+direction*cursor,a+direction*(float(hole.offset)-float(hole.width)/2),float(wall.thickness))
			cursor = float(hole.offset)+float(hole.width)/2
		_add_block(blocked,a+direction*cursor,b,float(wall.thickness))
	var unit := float(level.layout.cell_size)
	var step := minf(unit/2,0.25)
	var origin := Vector2(float(level.layout.origin[0]),float(level.layout.origin[1]))
	var cells := BuildingGridLayout.cell_set(level.layout.cells)
	var box := BuildingGridLayout.bounds(cells)
	var scale := roundi(unit/step)
	var sample_bounds := Rect2i(box.position*scale,box.size*scale).grow(roundi(1.5/step))
	# Bin expanded rectangles once instead of checking every wall at every sample.
	var bins := {}
	for rect in blocked:
		var low := Vector2i(((rect.position-Vector2.ONE*VisitorController.RADIUS-origin)/step).floor())
		var high := Vector2i(((rect.end+Vector2.ONE*VisitorController.RADIUS-origin)/step).ceil())
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var key := Vector2i(x,y)
				if not bins.has(key): bins[key] = []
				bins[key].append(rect)
	var clear := {}
	for y in range(sample_bounds.position.y,sample_bounds.end.y):
		for x in range(sample_bounds.position.x,sample_bounds.end.x):
			var key := Vector2i(x,y)
			var point := origin+Vector2(key)*step
			var safe := true
			if not allow_outside:
				for offset in [Vector2.ZERO,Vector2.LEFT*0.34,Vector2.RIGHT*0.34,Vector2.UP*0.34,Vector2.DOWN*0.34]:
					if not cells.has(Vector2i(((point+offset-origin)/unit).floor())): safe = false
			for rect: Rect2 in bins.get(key,[]):
				var nearest := point.clamp(rect.position,rect.end)
				if point.distance_to(nearest) < VisitorController.RADIUS+0.04:
					safe = false
					break
			if safe: clear[key] = true
	var reached := {}
	if has_start:
		var spawn := BuildingDefinition.vector(data.visit_spawn)
		var starts: Array = start_points.duplicate()
		if not data.entrance_id.is_empty(): starts.append(Vector2(spawn.x,spawn.z))
		var queue: Array[Vector2i] = []
		for point: Vector2 in starts:
			var start := Vector2i(((point-origin)/step).round())
			if not clear.has(start): issues.append("Entrance or landing has insufficient capsule clearance.")
			elif not reached.has(start): queue.append(start); reached[start] = true
		if not queue.is_empty():
			var index := 0
			while index < queue.size():
				var at := queue[index]
				index += 1
				for direction: Vector2i in BuildingGridLayout.NEIGHBOURS:
					var next := at+direction
					if clear.has(next) and not reached.has(next):
						reached[next] = true
						queue.append(next)
	var reached_cells := {}
	for key: Vector2i in reached:
		var cell := Vector2i((Vector2(key)/scale).floor())
		if cells.has(cell): reached_cells[cell] = true
	if has_start and reached_cells.is_empty(): issues.append("The entrance or landing does not lead to clear interior floor space.")
	for room in level.layout.rooms:
		if room.cells.is_empty(): continue
		var reachable := false
		for cell: Vector2i in BuildingGridLayout.cell_set(room.cells):
			if reached_cells.has(cell): reachable = true; break
		if not reachable:
			inaccessible.append(room.id)
			issues.append("%s needs a clear route from the entrance." % room.name)
	# Wall-adjacent fine-grid cells may not hold a capsule centre themselves.
	# Check connected circulation areas, rather than rejecting their thin fringes.
	var owners := BuildingGridLayout.owners(level.layout)
	var unassigned := {}
	for cell: Vector2i in cells:
		if not owners.has(cell): unassigned[cell] = true
	var sealed := 0
	while not unassigned.is_empty():
		var start: Vector2i = unassigned.keys()[0]
		var queue: Array[Vector2i] = [start]
		unassigned.erase(start)
		var index := 0
		var accessible := false
		while index < queue.size():
			var at := queue[index]
			index += 1
			if reached_cells.has(at): accessible = true
			for direction: Vector2i in BuildingGridLayout.NEIGHBOURS:
				var next := at+direction
				if unassigned.has(next):
					unassigned.erase(next)
					queue.append(next)
		if not accessible: sealed += 1
	if sealed > 0: issues.append("%d unassigned circulation areas have no accessible standing space." % sealed)
	return {"ok":issues.is_empty(),"issues":issues,"inaccessible":inaccessible,"reached":reached_cells,"samples":reached,"origin":origin,"step":step}

static func _add_block(blocked: Array[Rect2],a: Vector2,b: Vector2,thickness: float) -> void:
	if a.distance_to(b) < 0.001: return
	var normal := Vector2(0,thickness/2) if absf(a.x-b.x) > absf(a.y-b.y) else Vector2(thickness/2,0)
	blocked.append(Rect2(a.min(b)-normal,a.max(b)-a.min(b)+normal*2))
