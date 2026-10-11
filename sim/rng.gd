extends RefCounted
## One portable Park-Miller stream; state is included in snapshots.
var state: int

func _init(seed_value: int = 73) -> void:
	state = posmod(seed_value, 2147483646) + 1

func next_int(limit: int) -> int:
	state = (state * 48271) % 2147483647
	return state % maxi(1, limit)
