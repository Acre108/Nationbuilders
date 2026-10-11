class_name BuildingStoreys
extends RefCounted

## Compiler 4 composes the pinned room/opening compiler, then cuts shared slabs.
## Old documents retain their compiler. Readers validate saved geometry only.
const MAX_STOREYS := 4
const WIDTH := 1.4
const LANDING := 1.3
const SLOPE := 0.6

static func single(data: Dictionary, index: int, uncut: bool = true) -> BuildingDefinition:
	var copy := data.duplicate(true)
	var level: Dictionary = copy.storeys[index]
	level.elevation = 0.0
	if uncut and level.has("uncut_slabs"): level.slabs = level.uncut_slabs.duplicate(true)
	copy.storeys = [level]
	copy.compiler_version = 3
	copy.parameters = {"width":level.bounds[2],"depth":level.bounds[3],"storey_height":level.height,"storeys":1}
	copy.furniture = []
	copy.stairs = []
	copy.exterior_components = []
	copy.material_overrides = {}
	copy.storey_materials = {}
	copy.erase("storeys_digest")
	if index > 0:
		copy.entrance_id = ""
		copy.visit_spawn = [0.0,0.0,0.0]
	return BuildingDefinition.new(copy)

static func compile(source: BuildingDefinition) -> BuildingDefinition:
	var next := source.copy()
	var elevation := 0.0
	for index in next.data.storeys.size():
		var input := single(next.data,index,false)
		if not input.data.storeys[0].layout.has("openings"): input.data.storeys[0].layout.openings = []
		input.data.storeys[0].layout_digest = BuildingGridLayout.digest(input.data.storeys[0].layout)
		var base := GridBuildingCompiler.compile(input)
		if base == null or base.is_grid_draft(): return null
		var level: Dictionary = base.data.storeys[0]
		level.elevation = elevation
		level.uncut_slabs = level.slabs.duplicate(true)
		next.data.storeys[index] = level
		elevation += float(level.height)
		if index == 0:
			next.data.entrance_id = base.data.entrance_id
			next.data.visit_spawn = base.data.visit_spawn
	next.data.parameters.storeys = next.data.storeys.size()
	var ground: Dictionary = next.data.storeys[0]
	next.data.parameters.width = ground.bounds[2]
	next.data.parameters.depth = ground.bounds[3]
	next.data.parameters.storey_height = ground.height
	next.data.build_state = "shell"
	for stair in next.data.stairs:
		var lower := level_index(next.data,stair.from_storey)
		if lower >= 0:
			stair.height = float(next.data.storeys[lower].height)
			stair.run = path_run(stair.path) if stair.has("path") else stair.height/SLOPE
	next.data.stair_conflicts = conflicts(next.data)
	for index in next.data.storeys.size(): next.data.storeys[index].slabs = cut_slabs(next.data,index)
	next.data.storeys_digest = digest(next.data)
	return next

static func level_index(data: Dictionary, id: String) -> int:
	for index in data.storeys.size():
		if data.storeys[index].id == id: return index
	return -1

static func direction(stair: Dictionary) -> Vector2:
	return [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT][int(stair.orientation)]

static func start(stair: Dictionary) -> Vector2:
	return Vector2(float(stair.position[0]),float(stair.position[1]))

static func end(stair: Dictionary) -> Vector2:
	if stair.has("path"): return Vector2(float(stair.path[-1][0]),float(stair.path[-1][1]))
	return start(stair)+direction(stair)*float(stair.run)

static func hole(stair: Dictionary) -> Rect2:
	if stair.has("path"):
		var box := Rect2(start(stair),Vector2.ZERO)
		for point in stair.path: box = box.expand(Vector2(float(point[0]),float(point[1])))
		return box.grow(float(stair.width)/2)
	var normal := Vector2(-direction(stair).y,direction(stair).x)*float(stair.width)/2
	return Rect2(start(stair).min(end(stair))-normal.abs(),(end(stair)-start(stair)).abs()+normal.abs()*2)

static func reservation(stair: Dictionary) -> Rect2:
	var box := hole(stair)
	if stair.has("path"):
		for point in landings(stair): box = box.merge(Rect2(point-Vector2.ONE*WIDTH/2,Vector2.ONE*WIDTH))
		return box
	return box.grow_individual(LANDING if direction(stair).x != 0 else 0,LANDING if direction(stair).y != 0 else 0,LANDING if direction(stair).x != 0 else 0,LANDING if direction(stair).y != 0 else 0)

static func landings(stair: Dictionary) -> Array[Vector2]:
	if stair.has("path"):
		var before := Vector2(float(stair.path[-2][0]),float(stair.path[-2][1]))
		return [start(stair)-direction(stair)*(WIDTH/2+LANDING/2),end(stair)+(end(stair)-before).normalized()*(WIDTH/2+LANDING/2)]
	return [start(stair)-direction(stair)*LANDING/2,end(stair)+direction(stair)*LANDING/2]

static func path_run(path: Array) -> float:
	var total := 0.0
	for index in path.size()-1:
		total += Vector2(float(path[index][0]),float(path[index][1])).distance_to(Vector2(float(path[index+1][0]),float(path[index+1][1])))
	return total-WIDTH*maxi(0,path.size()-2)

static func path_errors(stair: Dictionary) -> PackedStringArray:
	var path: Variant = stair.get("path")
	if not path is Array or path.size() < 3 or path.size() > 8: return PackedStringArray(["A turned stair needs three to eight orthogonal path points."])
	for point in path:
		if not BuildingDefinition.numbers(point,2) or absf(float(point[0])) > 4096 or absf(float(point[1])) > 4096: return PackedStringArray(["Invalid stair path point."])
	var previous := Vector2.ZERO
	for index in path.size()-1:
		var delta := Vector2(float(path[index+1][0])-float(path[index][0]),float(path[index+1][1])-float(path[index][1]))
		if (delta.x != 0 and delta.y != 0) or delta.length() < WIDTH+0.2: return PackedStringArray(["Stair path legs must be orthogonal and leave room for a landing."])
		if index > 0 and absf(previous.normalized().dot(delta.normalized())) > 0.001: return PackedStringArray(["Stair paths must turn by 90 degrees."])
		previous = delta
	if stair.position != path[0] or (Vector2(float(path[1][0]),float(path[1][1]))-start(stair)).normalized() != direction(stair): return PackedStringArray(["Stair path start disagrees with its transform."])
	if absf(float(stair.run)-path_run(path)) > 0.00001 or float(stair.height)/float(stair.run) > SLOPE+0.00001: return PackedStringArray(["The stair path is too steep for its storey height."])
	# Non-neighbouring legs must not cross or share headroom.
	for index in path.size()-1:
		var a := Vector2(float(path[index][0]),float(path[index][1]))
		var b := Vector2(float(path[index+1][0]),float(path[index+1][1]))
		var box := Rect2(a.min(b),(b-a).abs()).grow(WIDTH/2)
		for other in range(index+2,path.size()-1):
			var c := Vector2(float(path[other][0]),float(path[other][1]))
			var d := Vector2(float(path[other+1][0]),float(path[other+1][1]))
			if box.intersects(Rect2(c.min(d),(d-c).abs()).grow(WIDTH/2)): return PackedStringArray(["Stair path legs overlap."])
	return PackedStringArray()

static func conflicts(data: Dictionary) -> Array:
	var result: Array = []
	for stair in data.stairs:
		var reasons: Array[String] = []
		var lower := level_index(data,stair.from_storey)
		var upper := level_index(data,stair.to_storey)
		if lower < 0 or upper != lower+1:
			reasons.append("Connect adjacent storeys.")
		else:
			for index in [lower,upper]:
				var level: Dictionary = data.storeys[index]
				var cells := BuildingGridLayout.cell_set(level.layout.cells)
				var unit := float(level.layout.cell_size)
				var origin := Vector2(float(level.layout.origin[0]),float(level.layout.origin[1]))
				var box := reservation(stair).grow(0.12)
				var low := Vector2i(((box.position-origin)/unit).floor())
				var high := Vector2i(((box.end-origin)/unit).ceil())
				var supported := true
				for y in range(low.y,high.y):
					for x in range(low.x,high.x):
						if not cells.has(Vector2i(x,y)): supported = false
				if not supported: reasons.append("Storey %d: stair and landings must fit inside the footprint." % (index+1))
				for wall in level.walls:
					var a := BuildingDefinition.vector(wall.from)
					var b := BuildingDefinition.vector(wall.to)
					var wall_box := Rect2(Vector2(a.x,a.z).min(Vector2(b.x,b.z)),Vector2(absf(a.x-b.x),absf(a.z-b.z))).grow(float(wall.thickness)/2)
					if box.intersects(wall_box): reasons.append("Storey %d: keep walls out of the stair and landing reservation." % (index+1)); break
			for other in data.stairs:
				if other.id == stair.id: continue
				if other.from_storey == stair.from_storey and reservation(stair).intersects(reservation(other)):
					reasons.append("Stair reservations overlap.")
				# Repeated aligned flights have a full storey of headroom. Other
				# overlapping flights cannot share a landing safely in this grammar.
				elif (other.to_storey == stair.from_storey or other.from_storey == stair.to_storey) and hole(stair).intersects(hole(other)) and (stair.position != other.position or stair.orientation != other.orientation or stair.run != other.run or stair.get("path",[]) != other.get("path",[])):
					reasons.append("Stack overlapping flights at the same position and direction.")
		if not reasons.is_empty(): result.append({"id":stair.id,"reason":"\n".join(reasons)})
	return result

static func cut_slabs(data: Dictionary, index: int) -> Array:
	var level: Dictionary = data.storeys[index]
	var result: Array = []
	var invalid := {}
	for conflict in data.get("stair_conflicts",[]): invalid[conflict.id] = true
	for slab in level.uncut_slabs:
		# Shared upper floor is the single solid slab at each storey boundary.
		var cuts: Array[Rect2] = []
		if slab.slot in ["ceiling","roof"] and index < data.storeys.size()-1:
			for upper_slab in data.storeys[index+1].uncut_slabs:
				if upper_slab.slot != "floor": continue
				var upper_center := BuildingDefinition.vector(upper_slab.center)
				var upper_size := BuildingDefinition.vector(upper_slab.size)
				cuts.append(Rect2(Vector2(upper_center.x-upper_size.x/2,upper_center.z-upper_size.z/2),Vector2(upper_size.x,upper_size.z)))
		for stair in data.stairs:
			if invalid.has(stair.id): continue
			if slab.slot == "floor" and stair.to_storey == level.id: cuts.append(hole(stair))
		var center := BuildingDefinition.vector(slab.center)
		var size := BuildingDefinition.vector(slab.size)
		var pieces: Array[Rect2] = [Rect2(Vector2(center.x-size.x/2,center.z-size.z/2),Vector2(size.x,size.z))]
		for cut in cuts:
			var kept: Array[Rect2] = []
			for piece in pieces: kept.append_array(subtract(piece,cut))
			pieces = kept
		for part in pieces:
			var record: Dictionary = slab.duplicate(true)
			if part != Rect2(Vector2(center.x-size.x/2,center.z-size.z/2),Vector2(size.x,size.z)):
				record.id = slab.id+"-cut-"+JSON.stringify([part.position.x,part.position.y,part.size.x,part.size.y]).sha256_text().substr(0,12)
				record.source_id = slab.id
				record.center = [part.get_center().x,center.y,part.get_center().y]
				record.size = [part.size.x,size.y,part.size.y]
			result.append(record)
	return result

static func subtract(piece: Rect2, cut: Rect2) -> Array[Rect2]:
	var overlap := piece.intersection(cut)
	if overlap.size.x <= 0 or overlap.size.y <= 0: return [piece]
	var result: Array[Rect2] = []
	for part in [Rect2(piece.position,Vector2(piece.size.x,overlap.position.y-piece.position.y)),Rect2(Vector2(piece.position.x,overlap.end.y),Vector2(piece.size.x,piece.end.y-overlap.end.y)),Rect2(Vector2(piece.position.x,overlap.position.y),Vector2(overlap.position.x-piece.position.x,overlap.size.y)),Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(piece.end.x-overlap.end.x,overlap.size.y))]:
		if part.size.x > 0.00001 and part.size.y > 0.00001: result.append(part)
	return result

static func floor_regions(level: Dictionary, region: Array) -> Array[Rect2]:
	var rectangle := Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]))
	var result: Array[Rect2] = []
	for slab in level.slabs:
		if slab.slot != "floor": continue
		var center := BuildingDefinition.vector(slab.center)
		var size := BuildingDefinition.vector(slab.size)
		var overlap := rectangle.intersection(Rect2(center.x-size.x/2,center.z-size.z/2,size.x,size.z))
		if overlap.size.x > 0.00001 and overlap.size.y > 0.00001: result.append(overlap)
	return result

static func room_net_area(level: Dictionary, room: Dictionary) -> float:
	var removed := 0.0
	for region in room.regions:
		removed += float(region[2])*float(region[3])
		for piece in floor_regions(level,region): removed -= piece.get_area()
	return maxf(0,float(room.net_area)-removed)

static func digest(data: Dictionary) -> String:
	return JSON.stringify([data.storeys,data.stairs,data.get("stair_conflicts",[])],"",true).sha256_text()

static func validate(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.get("structure_mode") != "grid": return PackedStringArray(["Compiler 4 requires a grid-authored building."])
	if not data.get("storeys") is Array or data.storeys.is_empty() or data.storeys.size() > MAX_STOREYS or data.parameters.get("storeys") != data.storeys.size(): return PackedStringArray(["Buildings support one to four storeys."])
	if data.get("build_state") != "shell" or not data.get("stairs") is Array or data.stairs.size() > 64 or not data.get("furniture") is Array or not data.get("stair_conflicts") is Array: return PackedStringArray(["Invalid multi-storey structure."])
	var ids := {str(data.id):true}
	var elevation := 0.0
	for index in data.storeys.size():
		var level: Variant = data.storeys[index]
		if not level is Dictionary or not BuildingDefinition.numbers([level.get("elevation"),level.get("height")],2) or not level.get("uncut_slabs") is Array: return PackedStringArray(["Invalid saved storey."])
		if not BuildingDefinition.valid_id(level.get("id")) or not BuildingDefinition.numbers(level.get("bounds"),4) or not level.get("slabs") is Array or not level.get("layout") is Dictionary or not level.layout.get("openings") is Array: return PackedStringArray(["Invalid saved storey geometry or layout."])
		BuildingDefinition._register_id(level,ids,errors)
		if absf(float(level.elevation)-elevation) > 0.000001: errors.append("Storey elevations must be contiguous.")
		elevation += float(level.height)
		var base := single(data,index)
		# Compiler 5 uses the pinned single-floor algorithms internally, with
		# explicit courtyard topology. Public legacy readers keep rejecting it.
		errors.append_array(base._validate_grid_layout(PackedStringArray()) if data.compiler_version == 5 else base.validate())
		if not errors.is_empty(): return errors
		for field in ["walls","slabs"]:
			for record in level[field]: BuildingDefinition._register_id(record,ids,errors)
		for room in level.layout.rooms: BuildingDefinition._register_id(room,ids,errors)
		for opening in level.layout.openings: BuildingDefinition._register_id(opening,ids,errors)
		if index > 0:
			for opening in level.layout.openings:
				if opening.kind == "entrance": errors.append("The arrival entrance belongs on the ground floor.")
	for stair in data.stairs:
		if not stair is Dictionary: return PackedStringArray(["Invalid stair record."])
		BuildingDefinition._register_id(stair,ids,errors)
		if not BuildingDefinition.valid_id(stair.get("from_storey")) or not BuildingDefinition.valid_id(stair.get("to_storey")) or not BuildingDefinition.numbers(stair.get("position"),2) or not BuildingDefinition.numbers([stair.get("width"),stair.get("height"),stair.get("run"),stair.get("orientation")],4): return PackedStringArray(["Invalid stair dimensions or attachment."])
		if stair.orientation != floor(float(stair.orientation)) or not int(stair.orientation) in [0,1,2,3] or stair.width != WIDTH or stair.height < 2.7 or stair.height > 5 or absf(stair.position[0]) > 4096 or absf(stair.position[1]) > 4096: return PackedStringArray(["Unsupported stair geometry."])
		if stair.has("path"):
			if data.compiler_version != 5: return PackedStringArray(["Turned stairs require compiler 5."])
			errors.append_array(path_errors(stair))
			if not errors.is_empty(): return errors
		elif absf(stair.run-stair.height/SLOPE) > 0.000001: return PackedStringArray(["Unsupported stair slope."])
		var lower := level_index(data,stair.from_storey)
		if lower < 0 or level_index(data,stair.to_storey) != lower+1 or stair.height != data.storeys[lower].height: return PackedStringArray(["Stairs must join adjacent existing storeys at their saved heights."])
	for instance in data.furniture:
		if not instance is Dictionary: return PackedStringArray(["Invalid furniture reference."])
		BuildingDefinition._register_id(instance,ids,errors)
		if not instance.get("catalogue_id") is String or level_index(data,str(instance.get("storey_id",""))) < 0 or not BuildingDefinition.numbers(instance.get("position"),3) or not BuildingDefinition.numbers([instance.get("yaw_degrees")],1): errors.append("Invalid furniture attachment or transform.")
	if not errors.is_empty(): return errors
	if data.compiler_version == 5: BuildingDefinition.new(data)._validate_exterior(ids,errors)
	if JSON.stringify(data.get("stair_conflicts"),"",true) != JSON.stringify(conflicts(data),"",true): return PackedStringArray(["Saved stair conflicts disagree with the layout."])
	for index in data.storeys.size():
		if JSON.stringify(data.storeys[index].slabs,"",true) != JSON.stringify(cut_slabs(data,index),"",true): errors.append("Saved stair slab openings disagree with their connections.")
	if data.get("storeys_digest") != digest(data): errors.append("Saved multi-storey geometry digest mismatch; source preserved.")
	if data.parameters.width != data.storeys[0].bounds[2] or data.parameters.depth != data.storeys[0].bounds[3] or data.parameters.storey_height != data.storeys[0].height: errors.append("Ground floor summary mismatch.")
	return errors

static func access_report(definition: BuildingDefinition) -> Dictionary:
	var data: Dictionary = definition.data
	var envelope := BuildingRoofEnvelope.new(data)
	var seeds: Array = []
	var reports: Array = []
	var previous_seeds: Array = []
	for index in data.storeys.size(): seeds.append([]); reports.append({}); previous_seeds.append(null)
	var invalid := {}
	for conflict in data.stair_conflicts: invalid[conflict.id] = true
	for iteration in data.storeys.size()*2+1:
		for index in data.storeys.size():
			if seeds[index] == previous_seeds[index]: continue
			previous_seeds[index] = seeds[index].duplicate()
			if index > 0 and seeds[index].is_empty():
				reports[index] = {"issues":[],"inaccessible":data.storeys[index].layout.rooms.filter(func(item: Dictionary) -> bool: return not item.cells.is_empty()).map(func(item: Dictionary) -> String: return item.id),"reached":{}}
				continue
			var barriers: Array[Rect2] = BuildingFurniture.barriers(data,data.storeys[index].id)
			barriers.append_array(envelope.standing_barriers(data.storeys[index]))
			for stair in data.stairs:
				if not invalid.has(stair.id) and data.storeys[index].id in [stair.from_storey,stair.to_storey]: barriers.append(hole(stair).grow(0.07))
			reports[index] = GridBuildingOpenings.access_report(single(data,index),seeds[index],index == 0,barriers)
		var changed := false
		for stair in data.stairs:
			if invalid.has(stair.id): continue
			var lower := level_index(data,stair.from_storey)
			var upper := level_index(data,stair.to_storey)
			var points := landings(stair)
			if reached_point(reports[lower],points[0]) and not points[1] in seeds[upper]: seeds[upper].append(points[1]); changed = true
			if reached_point(reports[upper],points[1]) and not points[0] in seeds[lower]: seeds[lower].append(points[0]); changed = true
		if not changed: break
	var issues: Array = []
	var inaccessible: Array = []
	var reached := {}
	for index in reports.size():
		for issue in reports[index].issues: issues.append("Storey %d: %s" % [index+1,issue])
		inaccessible.append_array(reports[index].inaccessible)
		reached[data.storeys[index].id] = reports[index].reached
		if index > 0 and seeds[index].is_empty(): issues.append("Storey %d needs a reachable stair connection." % (index+1))
	issues.append_array(BuildingFurniture.conflicts(data))
	for conflict in data.stair_conflicts: issues.append("Stair: "+conflict.reason)
	var storey_reports := {}
	for index in reports.size(): storey_reports[data.storeys[index].id] = reports[index]
	return {"ok":issues.is_empty(),"issues":issues,"inaccessible":inaccessible,"reached":reached,"storey_reports":storey_reports}

static func reached_point(report: Dictionary, point: Vector2) -> bool:
	if not report.has("samples"): return false
	var key := Vector2i(((point-report.origin)/float(report.step)).round())
	return report.samples.has(key)
