extends RefCounted
## The generated world: a rectangle of pointy-top hexes in offset rows, stored by
## axial coordinate. Generation lives in WorldGen; this holds the result and the
## rules that read it (docs/PLAN-world-map.md §4).
const HexMath = preload("res://sim/world/hex_math.gd")
var seed_value := 0
var generator_version := 0
var columns := 0
var rows := 0
var data
## Axial coordinate -> HexInfo, inserted in row-major order.
var hexes: Dictionary = {}
var start := Vector2i.ZERO
## Site checks run when requested, never while regenerating the whole world.
## This cache is derived from the world seed and generator, not campaign state.
var site_errors: Dictionary = {}

## Axial coordinate of the hex in a given column and row ("odd-r" offset rows).
static func coord_at(column: int, row: int) -> Vector2i:
	return Vector2i(column - (row - (row & 1)) / 2, row)

static func column_of(coord: Vector2i) -> int:
	return coord.x + (coord.y - (coord.y & 1)) / 2

static func opposite(edge: int) -> int:
	return (edge + 3) % 6

func has(coord: Vector2i) -> bool:
	return hexes.has(coord)

func hex(coord: Vector2i):
	return hexes.get(coord)

func neighbour(coord: Vector2i, edge: int) -> Vector2i:
	return coord + HexMath.NEIGHBOURS[edge]

## In-map neighbours, in edge order.
func neighbours(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for edge in 6:
		var other := neighbour(coord, edge)
		if hexes.has(other):
			result.append(other)
	return result

## The hexes a village founded here may build in: its own and its neighbours.
func reach(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [coord]
	result.append_array(neighbours(coord))
	return result

## Deposits the player knows about: map-visible ones always, the rest once scouted.
func visible_deposits(coord: Vector2i) -> Array[String]:
	var result: Array[String] = []
	var info = hexes.get(coord)
	if info == null:
		return result
	for deposit in info.deposits:
		if info.scouted or data.deposits[deposit].visibility == "map":
			result.append(deposit)
	return result

## Whether the hex has deposits the player cannot see yet.
func has_hidden_deposits(coord: Vector2i) -> bool:
	return visible_deposits(coord).size() < hex(coord).deposits.size()

## Empty when a village may be founded here; otherwise why not. `settlements`
## lists the hexes of existing villages and ruins.
func found_blocked(coord: Vector2i, settlements: Array[Vector2i] = [], ignored_settlement: String = "") -> String:
	var info = hexes.get(coord)
	if info == null:
		return "Off the map"
	if not data.biomes[info.biome].settleable:
		return "Cannot settle " + data.biomes[info.biome].name.to_lower()
	var spacing := int(data.world.min_village_distance)
	for other in hexes:
		var village_id: String = hexes[other].settlement
		if not village_id.is_empty() and village_id != ignored_settlement and HexMath.distance(coord, other) < spacing:
			return "Too close to another village or ruin"
	for other in settlements:
		if HexMath.distance(coord, other) < spacing:
			return "Too close to another village"
	if site_errors.has(coord): return site_errors[coord]
	return ""

func check_site(coord: Vector2i) -> String:
	if site_errors.has(coord): return site_errors[coord]
	var reason := found_blocked(coord)
	if not reason.is_empty(): return reason
	var site = load("res://sim/world/site_gen.gd").generate(self,coord)
	site_errors[coord] = site.error()
	return site_errors[coord]

## A stable text form of every hex, for determinism checks.
func fingerprint() -> String:
	var rows_out: Array = []
	for coord in hexes:
		rows_out.append(hexes[coord].to_dict())
	return JSON.stringify({"seed":seed_value, "version":generator_version, "start":[start.x, start.y], "hexes":rows_out})
