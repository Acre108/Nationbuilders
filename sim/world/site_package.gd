extends RefCounted
## The contract between the world and one village run (docs/WORLD_MAP.md §6.2).
## Per-tile arrays are row-major, x fastest, like Grid. Cliffs are derived, not
## stored: neighbours connect when their levels match, or differ by one and the
## upper tile is a ramp. Every other level change is a cliff.
const VERSION := 1
const DEFAULT_SIZE := Vector2i(100, 100)
var name := ""
var width := 0
var height := 0
var terrain: Array[String] = []
var deposits: Array[String] = []
var levels := PackedInt32Array()
var ramps := PackedByteArray()
## 1 = inside the village's reach (founding hex and its six neighbours).
var reach := PackedByteArray()
## Physical boundary, independent of buildable reach (authored fixtures may
## retain visible wilderness outside their reach). Generated sites are hexes.
var footprint := PackedByteArray()
var seed_value := 0
var world_coord := Vector2i.ZERO
var hex_width := 0.0
## Local cell-centre -> normalized world coordinates uses this origin.
var world_origin := Vector2.ZERO
var owner_coords: Array[Vector2i] = []
## Descriptor summaries indexed by "q,r"; available after campaign restore.
var districts: Dictionary = {}
var generation_error := ""
var promised_water := false
var playability_result: Dictionary = {}
## Storehouse cell of the starter layout.
var founding_spot := Vector2i(17, 21)
var biome := "heartland"
## Optional authored approach and space kept open by foresters.
var entrance_road: Array[Vector2i] = []
var settlement_clearance := Rect2i()

func _init(site_width: int = DEFAULT_SIZE.x, site_height: int = DEFAULT_SIZE.y, fill: String = "grass") -> void:
	width = site_width
	height = site_height
	for index in width * height:
		terrain.append(fill)
		deposits.append("")
	levels.resize(width * height)
	ramps.resize(width * height)
	reach.resize(width * height)
	reach.fill(1)
	footprint.resize(width * height)
	footprint.fill(1)

func index(cell: Vector2i) -> int:
	return cell.y * width + cell.x

func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height and footprint[index(cell)] == 1

func world_point(cell: Vector2i) -> Vector2:
	return world_origin + (Vector2(cell) + Vector2(0.5, 0.5)) * (2.0 / hex_width) if hex_width > 0.0 else Vector2(cell)

## Empty when the package is usable; otherwise the first problem found.
func error() -> String:
	if not generation_error.is_empty():
		return generation_error
	var count := width * height
	if width < 1 or height < 1:
		return "Site has no tiles"
	for field in [terrain, deposits, levels, ramps, reach, footprint]:
		if field.size() != count:
			return "Site arrays must hold %d tiles" % count
	if not inside(founding_spot):
		return "Founding spot is outside the site"
	return ""
