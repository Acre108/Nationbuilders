extends SceneTree
const WorldGen = preload("res://sim/world/world_gen.gd")
const SiteGen = preload("res://sim/world/site_gen.gd")
func _init() -> void:
	var world = WorldGen.generate(73)
	print("PROBE start ",world.start)
	var begin := Time.get_ticks_msec()
	var site = SiteGen.generate(world,world.start)
	print("PROBE ",Time.get_ticks_msec()-begin,"ms ",site.error()," ",site.founding_spot," ",site.playability_result)
	quit()
