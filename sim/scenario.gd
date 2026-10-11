extends RefCounted
## Same public commands used by the playable start and headless fixture.
## Coordinates are the milestone 1 layout, shifted so its storehouse sits on the
## site's founding spot; on the milestone 1 map the shift is zero.
const LAYOUT_STOREHOUSE := Vector2i(17, 21)

static func offset(sim) -> Vector2i:
	return sim.site.founding_spot - LAYOUT_STOREHOUSE

static func starter(sim) -> bool:
	var shift := offset(sim)
	var roads: Array[Vector2i] = []
	roads.append_array(sim.site.entrance_road)
	for x in range(12, 28):
		roads.append(Vector2i(x, 20) + shift)
	for y in range(16, 25):
		roads.append(Vector2i(20, y) + shift)
	if not sim.place_road(roads):
		return false
	for entry in [["storehouse",Vector2i(17,21)],["house",Vector2i(21,21)],["well",Vector2i(21,19)],["farm",Vector2i(12,18)],["woodcutter",Vector2i(24,21)]]:
		if not sim.place(entry[0],entry[1] + shift):
			return false
	return true

static func complete_chain(sim) -> bool:
	var shift := offset(sim)
	return sim.place("mill",Vector2i(16,18) + shift) and sim.place("bakery",Vector2i(23,18) + shift)
