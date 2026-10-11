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
	preload("res://tests/test_campaign.gd").new().run(self)
	print("CAMPAIGNS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
