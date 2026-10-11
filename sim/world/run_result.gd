extends RefCounted
## Stable result contract; later charter rules can fill the reserved fields.
static func create(outcome: String, best_tier: int, final_population: int, duration_ticks: int) -> Dictionary:
	return {"outcome":outcome,"best_tier":best_tier,"final_population":final_population,
		"duration_ticks":duration_ticks,"role":"","faction":"","export_bundle":{}}

static func valid(state) -> bool:
	if not state is Dictionary: return false
	if state.get("outcome") not in ["charter","ruin","abandoned"]: return false
	for key in ["best_tier","final_population","duration_ticks"]:
		if not state.get(key) is int or state[key] < 0: return false
	return state.get("role") is String and state.get("faction") is String and state.get("export_bundle") is Dictionary
