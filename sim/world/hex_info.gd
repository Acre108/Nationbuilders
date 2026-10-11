extends RefCounted
## One world-map hex (docs/PLAN-world-map.md §4.1). Edges are indexed like
## HexMath.NEIGHBOURS; the opposite of edge e is (e + 3) % 6.
var coord := Vector2i.ZERO
var biome := ""
## Elevation band: 0 lowland, 1 rolling, 2 hills, 3 highland, 4 peaks.
var elevation := 0
## Raw generated height and the drainage surface rivers descend (generation detail).
var height := 0.0
var filled := 0.0
var moisture := 0.0
var temperature := 0.0
## Edge index -> width (1 stream, 2 river, 3 great river).
var river_edges: Dictionary = {}
## Edge water leaves by, toward the sea; -1 for ocean hexes.
var flows_to := -1
## Number of hexes draining through this one, itself included.
var flow := 0
var coast_edges: Array[int] = []
var lake := false
var cliffs := 0.0
var forest := 0.0
var deposits: Array[String] = []
var wildness := 0
var scouted := false
## Village id, or empty.
var settlement := ""

func is_land() -> bool:
	return biome != "ocean"

func river_width() -> int:
	var widest := 0
	for edge in river_edges:
		widest = maxi(widest, int(river_edges[edge]))
	return widest

func to_dict() -> Dictionary:
	var rivers := {}
	for edge in river_edges:
		rivers[str(edge)] = river_edges[edge]
	return {"coord":[coord.x, coord.y], "biome":biome, "elevation":elevation, "height":snappedf(height, 0.000001), "moisture":snappedf(moisture, 0.000001), "temperature":snappedf(temperature, 0.000001), "river_edges":rivers, "flows_to":flows_to, "flow":flow, "coast_edges":coast_edges.duplicate(), "lake":lake, "cliffs":snappedf(cliffs, 0.000001), "forest":snappedf(forest, 0.000001), "deposits":deposits.duplicate(), "wildness":wildness, "scouted":scouted, "settlement":settlement}
