class_name BuildingGridLayout
extends RefCounted

## Sparse footprint and named room ownership, independent of canvas pixels.
const CELL_SIZES := [0.25, 0.5, 1.0]
const MAX_METRES := 30.0
const COURTYARD_MAX_METRES := 40.0
const MAX_COORDINATE := 2048
const MAX_CELLS := 14400
const NEIGHBOURS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const ROOM_ROLES := ["", "bedroom", "kitchen", "bathroom", "living", "corridor", "utility"]

static func cell_set(cells: Array) -> Dictionary:
	var result := {}
	for cell in cells: result[Vector2i(int(cell[0]), int(cell[1]))] = true
	return result

static func sorted_cells(occupied: Dictionary) -> Array:
	var points: Array = occupied.keys()
	points.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var result: Array = []
	for cell: Vector2i in points: result.append([cell.x, cell.y])
	return result

static func bounds(occupied: Dictionary) -> Rect2i:
	if occupied.is_empty(): return Rect2i()
	var minimum: Vector2i = occupied.keys()[0]
	var maximum := minimum
	for cell: Vector2i in occupied:
		minimum = minimum.min(cell)
		maximum = maximum.max(cell)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

static func digest(layout: Dictionary) -> String:
	var records := {"cell_size": float(layout.cell_size), "origin": [float(layout.origin[0]), float(layout.origin[1])], "cells": sorted_cells(cell_set(layout.cells)), "rooms": layout.rooms}
	if layout.has("openings"): records.openings = layout.openings
	if layout.has("courtyards"): records.courtyards = layout.courtyards
	return JSON.stringify(records, "", true).sha256_text()

static func validate(layout: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not layout is Dictionary: return PackedStringArray(["Missing grid layout."])
	if layout.has("courtyards") and not layout.courtyards is bool: return PackedStringArray(["Invalid courtyard authoring mode."])
	if not (layout.get("cell_size") is float or layout.get("cell_size") is int) or not layout.cell_size in CELL_SIZES:
		errors.append("Grid size must be 0.25, 0.5 or 1 metre.")
	if not layout.get("origin") is Array or layout.origin.size() != 2:
		errors.append("Invalid grid origin.")
	else:
		for value in layout.origin:
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 2048: errors.append("Invalid grid origin.")
	if not layout.get("rooms") is Array or layout.rooms.size() > 64: errors.append("A layout supports up to 64 named rooms.")
	if not layout.get("cells") is Array or layout.cells.size() > (25600 if layout.get("courtyards",false) else MAX_CELLS):
		errors.append("Invalid or oversized cell collection.")
		return errors
	var occupied := {}
	for point in layout.cells:
		if not point is Array or point.size() != 2:
			errors.append("Cells must be pairs of integer coordinates.")
			continue
		var valid := true
		for coordinate in point:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate)) > MAX_COORDINATE or float(coordinate) != floor(float(coordinate)):
				valid = false
		if not valid:
			errors.append("Cell coordinates must be finite integers within the canvas limit.")
			continue
		var cell := Vector2i(int(point[0]), int(point[1]))
		if occupied.has(cell): errors.append("Duplicate painted cell.")
		occupied[cell] = true
	if not errors.is_empty(): return errors
	for room_errors in validate_rooms(layout,occupied): errors.append(room_errors)
	if not errors.is_empty() or occupied.is_empty(): return errors
	var box := bounds(occupied)
	var limit := COURTYARD_MAX_METRES if layout.get("courtyards",false) else MAX_METRES
	if box.size.x * float(layout.cell_size) > limit or box.size.y * float(layout.cell_size) > limit:
		return PackedStringArray(["The footprint must fit within %d × %d metres." % [limit,limit]])
	var visited := _flood(occupied.keys()[0], occupied, box, true)
	if visited.size() != occupied.size(): return PackedStringArray(["The footprint must be connected by shared edges; separate or diagonal-only pieces are unsupported."])
	var outside := _flood(box.position - Vector2i.ONE, occupied, box.grow(1), false)
	if outside.size() + occupied.size() != box.grow(1).get_area() and not layout.get("courtyards",false):
		return PackedStringArray(["Enclosed courtyard holes are not supported yet."])
	for cell: Vector2i in occupied:
		for corner in [cell, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.ONE]:
			var a := occupied.has(corner)
			var b := occupied.has(corner + Vector2i.LEFT)
			var c := occupied.has(corner + Vector2i.UP)
			var d := occupied.has(corner - Vector2i.ONE)
			if a == d and b == c and a != b:
				return PackedStringArray(["The boundary touches itself at a corner. Join or separate those edges."])
	return errors

static func owners(layout: Dictionary) -> Dictionary:
	var result := {}
	for room in layout.rooms:
		for cell in room.cells: result[Vector2i(int(cell[0]),int(cell[1]))] = room.id
	return result

static func room_by_id(layout: Dictionary,id: String) -> Dictionary:
	for room in layout.rooms:
		if room.id == id: return room
	return {}

static func validate_rooms(layout: Dictionary,occupied: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	var assigned := {}
	for room in layout.rooms:
		if not room is Dictionary or not BuildingDefinition.valid_id(room.get("id")) or room.get("id") == "outside" or ids.has(room.get("id")):
			errors.append("Invalid or duplicate room ID.")
			continue
		ids[room.id] = true
		if not room.get("name") is String or room.name.strip_edges().is_empty() or room.name.length() > 80: errors.append("Room names must contain 1–80 characters.")
		if not room.get("role") in ROOM_ROLES: errors.append("Unsupported room role.")
		if not room.get("colour") is String or not Color.html_is_valid(str(room.get("colour",""))): errors.append("Invalid room colour.")
		if not room.get("cells") is Array:
			errors.append("Missing room cells.")
			continue
		# The same topology rules apply to a nonempty room, without recursion.
		var shape := {"cell_size":layout.cell_size,"origin":layout.origin,"cells":room.cells,"rooms":[]}
		if layout.has("courtyards"): shape.courtyards = layout.courtyards
		var shape_errors := validate(shape)
		if not shape_errors.is_empty():
			for error in shape_errors: errors.append("Room %s: %s" % [str(room.get("name",room.id)),error])
			continue
		for cell: Vector2i in cell_set(room.cells):
			if not occupied.has(cell): errors.append("Room cells must stay inside the footprint.")
			if assigned.has(cell): errors.append("Room assignments cannot overlap.")
			assigned[cell] = room.id
	return errors

static func _flood(start: Vector2i, occupied: Dictionary, area: Rect2i, filled: bool) -> Dictionary:
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for step: Vector2i in NEIGHBOURS:
			var next := cell + step
			if area.has_point(next) and occupied.has(next) == filled and not visited.has(next):
				visited[next] = true
				queue.append(next)
	return visited

static func outline_cells(vertices: Array[Vector2i], cell_size: float, limit: float = MAX_METRES) -> Dictionary:
	if not cell_size in CELL_SIZES: return {"ok":false,"error":"Unsupported grid size."}
	if vertices.size() < 4 or vertices.size() > 512: return {"ok": false, "error": "An outline needs at least four corners."}
	var polygon := PackedVector2Array()
	var unique := {}
	for index in vertices.size():
		var a := vertices[index]
		var b := vertices[(index + 1) % vertices.size()]
		if unique.has(a) or a == b or (a.x != b.x and a.y != b.y): return {"ok": false, "error": "Outline edges must be horizontal or vertical, without repeated corners."}
		if absi(a.x) > MAX_COORDINATE or absi(a.y) > MAX_COORDINATE: return {"ok": false, "error": "Outline is outside the canvas limit."}
		unique[a] = true
		polygon.append(Vector2(a))
		for previous in index:
			var c := vertices[previous]
			var d := vertices[(previous + 1) % vertices.size()]
			if _intersects(a, b, c, d):
				var adjacent := previous == index - 1 or (previous == 0 and index == vertices.size() - 1)
				if not adjacent or _overlaps(a, b, c, d): return {"ok": false, "error": "Outline edges cross or overlap."}
	var box := bounds(unique)
	if (box.size.x - 1) * cell_size > limit or (box.size.y - 1) * cell_size > limit: return {"ok": false, "error": "The footprint must fit within %d × %d metres." % [limit,limit]}
	var result := {}
	for y in range(box.position.y, box.end.y - 1):
		for x in range(box.position.x, box.end.x - 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), polygon): result[Vector2i(x, y)] = true
	if result.is_empty(): return {"ok": false, "error": "The outline has no interior area."}
	return {"ok": true, "cells": sorted_cells(result)}

static func _intersects(a: Vector2i, b: Vector2i, c: Vector2i, d: Vector2i) -> bool:
	return maxi(mini(a.x,b.x), mini(c.x,d.x)) <= mini(maxi(a.x,b.x), maxi(c.x,d.x)) and maxi(mini(a.y,b.y), mini(c.y,d.y)) <= mini(maxi(a.y,b.y), maxi(c.y,d.y))

static func _overlaps(a: Vector2i, b: Vector2i, c: Vector2i, d: Vector2i) -> bool:
	if a.x == b.x and c.x == d.x:
		return a.x == c.x and maxi(mini(a.y,b.y), mini(c.y,d.y)) < mini(maxi(a.y,b.y), maxi(c.y,d.y))
	if a.y == b.y and c.y == d.y:
		return a.y == c.y and maxi(mini(a.x,b.x), mini(c.x,d.x)) < mini(maxi(a.x,b.x), maxi(c.x,d.x))
	return false
