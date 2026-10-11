extends RefCounted
## Same public commands used by the playable start and headless fixture.
static func starter(sim) -> bool:
	var roads: Array[Vector2i] = []
	for x in range(12, 28):
		roads.append(Vector2i(x, 20))
	for y in range(16, 25):
		roads.append(Vector2i(20, y))
	if not sim.place_road(roads):
		return false
	for entry in [["storehouse",Vector2i(17,21)],["house",Vector2i(21,21)],["well",Vector2i(21,19)],["farm",Vector2i(12,18)],["woodcutter",Vector2i(24,21)]]:
		if not sim.place(entry[0],entry[1]):
			return false
	return true

static func complete_chain(sim) -> bool:
	return sim.place("mill",Vector2i(16,18)) and sim.place("bakery",Vector2i(23,18))
