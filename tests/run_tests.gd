extends SceneTree
## Run directly on a fresh checkout; no editor import or rendering required.
var checks := 0
var failures: Array[String] = []
## With `-- --quick`, test files skip their slow sections: whole-campaign
## saves and the hour-long village run.
var quick := false

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	# Lets CI verify that a failing assertion reaches the process exit code.
	if "--verify-failure-exit" in OS.get_cmdline_user_args():
		check(false, "Intentional runner exit-code probe")
		quit(1)
		return
	quick = "--quick" in OS.get_cmdline_user_args()
	for path in ["res://tests/test_content.gd", "res://tests/test_sim.gd", "res://tests/test_site.gd", "res://tests/test_rotation.gd", "res://tests/test_world.gd", "res://tests/test_forestry.gd", "res://tests/test_campaign.gd", "res://tests/test_logistics.gd", "res://tests/test_factions.gd", "res://tests/test_chains.gd", "res://tests/test_wildlife.gd", "res://tests/test_forage.gd", "res://tests/test_food_report.gd", "res://tests/test_labour.gd", "res://tests/test_construction.gd"]:
		var script = load(path)
		if script == null or not script.can_instantiate():
			check(false, "Could not compile " + path)
			continue
		var started := Time.get_ticks_msec()
		var failed_before := failures.size()
		script.new().run(self)
		print("  %-28s %6.1f s%s" % [path.get_file(), (Time.get_ticks_msec() - started) / 1000.0, "" if failures.size() == failed_before else "  (%d failed)" % (failures.size() - failed_before)])
	print("HEARTHLANDS%s: %d checks, %d failures" % [" (quick)" if quick else "", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
