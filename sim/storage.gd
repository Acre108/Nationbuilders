extends RefCounted
var capacity: int
var items: Dictionary = {}

func _init(size: int = 6) -> void:
	capacity = size

## Storage quantities are validated before a restored run can consume them.
static func from_snapshot(state: Dictionary, size: int = 6):
	var result = load("res://sim/storage.gd").new(size)
	for good in state:
		var amount = state[good]
		if not good is String or not (amount is int or amount is float) or amount < 0 or amount != int(amount):
			return null
		result.items[good] = int(amount)
	return result if result.total() <= size else null

func count(good: String) -> int:
	return int(items.get(good, 0))

func total() -> int:
	var result := 0
	for amount in items.values():
		result += int(amount)
	return result

func has_all(recipe: Dictionary) -> bool:
	for good in recipe:
		if count(good) < int(recipe[good]):
			return false
	return true

func fits(recipe: Dictionary) -> bool:
	var amount := 0
	for quantity in recipe.values():
		amount += int(quantity)
	return total() + amount <= capacity

func add(good: String, amount: int = 1) -> bool:
	if amount < 0 or total() + amount > capacity:
		return false
	items[good] = count(good) + amount
	return true

func take(good: String, amount: int = 1) -> bool:
	if amount < 0 or count(good) < amount:
		return false
	items[good] = count(good) - amount
	if items[good] == 0:
		items.erase(good)
	return true
