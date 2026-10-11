extends SceneTree
var checks := 0
var failures: Array[String] = []
func _init() -> void:
	_run.call_deferred()
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)
func _run() -> void:
	var script = load("res://tests/test_site_gen.gd")
	if script == null or not script.can_instantiate():
		check(false,"Site generation suite compiles")
	else:
		script.new().run(self)
	check(checks > 0,"Site generation suite executed checks")
	print("SITE GENERATION: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
