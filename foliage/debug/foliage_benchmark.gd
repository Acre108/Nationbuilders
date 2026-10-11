class_name FoliageBenchmark
extends Node

## Automated perf pass over the foliage quality levels.
##
## Run with:
##   Godot.exe --path . -- --bench
##
## This exists because the numbers in the brief's deliverables list cannot be
## produced any other way. Godot's --headless mode uses a dummy renderer whose
## RENDER_TOTAL_DRAW_CALLS_IN_FRAME and RENDER_TOTAL_PRIMITIVES_IN_FRAME
## monitors always read 0, so a headless "benchmark" measures nothing. This runs
## a real window against the real renderer and samples the same monitors the HUD
## shows, then writes both a readable table and a JSON file.
##
## Frame times are reported as mean and 95th percentile. The 95th matters more
## than the mean for this system: streaming and chunk rebuilds produce
## occasional long frames, and a mean happily hides a hitch that a player feels.

const SETTLE_SECONDS := 1.5
const SAMPLE_FRAMES := 240

signal finished(results: Array)

var _layer: GrassLayer
var _location: FoliageLocation
var _label: String = "scene"


## Given a FoliageLocation, each level is applied through its set_quality(), so
## trees and the sun's shadow settings change with the level as they would in
## game. Without one, only the grass layer is rebuilt.
func run_for(layer: GrassLayer, label: String, location: FoliageLocation = null) -> void:
	_layer = layer
	_location = location
	_label = label
	call_deferred("_run")


func _run() -> void:
	# Without this every level reports exactly the refresh interval (16.67 ms on
	# a 60 Hz panel) and the benchmark measures nothing but the monitor. The
	# whole point is headroom: how far under budget a level actually runs.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var results: Array = []
	for level in [
		FoliageQuality.Level.LOW,
		FoliageQuality.Level.MEDIUM,
		FoliageQuality.Level.HIGH,
		FoliageQuality.Level.ULTRA,
	]:
		results.append(await _measure(level))

	_report(results)
	finished.emit(results)


func _measure(level: FoliageQuality.Level) -> Dictionary:
	var build_started := Time.get_ticks_usec()
	# How long the quality change itself blocks the main thread -- what a
	# player feels. `rebuild` below is time to fully caught-up steady state.
	var switch_ms := -1.0
	if _location != null:
		# A quality change on a streaming location rebuilds progressively;
		# for a steady-state measurement, wait for all of it -- including the
		# impostor bake, which recommits every tree chunk when it lands.
		_location.set_quality(level)
		switch_ms = (Time.get_ticks_usec() - build_started) / 1000.0
		_location.flush_streaming()
		# Only wait for a bake if TreeLayer.rebuild() actually started one --
		# see its own impostors_enabled / --headless guard. Otherwise
		# impostors_ready never fires and this would hang forever; --bench
		# always needs a real window, but disabling impostors on the layer
		# (or running under --headless despite that) must not hang either.
		var awaiting_bake := (
			_location.trees != null and not _location.trees.has_impostors()
			and _location.trees.impostors_enabled and DisplayServer.get_name() != "headless"
		)
		if awaiting_bake:
			await _location.trees.impostors_ready
			_location.flush_streaming()
	else:
		_layer.quality = FoliageQuality.create(level)
		_layer.rebuild()
	var build_ms := (Time.get_ticks_usec() - build_started) / 1000.0

	# Let the renderer settle: the first frames after a rebuild include shader
	# pipeline work and buffer uploads that are not representative of steady
	# state, and averaging them in would flatter or punish a level arbitrarily.
	var settle_until := Time.get_ticks_msec() + int(SETTLE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < settle_until:
		await get_tree().process_frame

	var samples := PackedFloat32Array()
	var draw_calls := 0.0
	var primitives := 0.0
	for i in SAMPLE_FRAMES:
		await get_tree().process_frame
		samples.append(get_process_delta_time() * 1000.0)
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)

	var sorted := Array(samples)
	sorted.sort()
	var total := 0.0
	for s in samples:
		total += s

	var counts := _layer.debug_counts()
	return {
		"level": FoliageQuality.level_name(level),
		"mean_ms": total / float(samples.size()),
		"p95_ms": sorted[int(float(sorted.size()) * 0.95)],
		"worst_ms": sorted[sorted.size() - 1],
		"fps_mean": 1000.0 / (total / float(samples.size())),
		"rebuild_ms": build_ms,
		"switch_ms": switch_ms,
		"draw_calls": int(draw_calls / float(SAMPLE_FRAMES)),
		"primitives": int(primitives / float(SAMPLE_FRAMES)),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"chunks": counts["chunks"],
		"grass": counts["grass"],
		"flowers": counts["flowers"],
		"grass_triangles": counts["triangles_grass"] + counts["triangles_flowers"],
	}


func _report(results: Array) -> void:
	var adapter := RenderingServer.get_video_adapter_name()
	var size := DisplayServer.window_get_size()

	print("")
	print("=== foliage benchmark: %s ===" % _label)
	print("gpu: %s   resolution: %dx%d" % [adapter, size.x, size.y])
	print("%-8s %9s %9s %9s %9s %9s %10s %12s %10s %9s" % [
		"level", "mean ms", "p95 ms", "fps", "switch", "rebuild", "draws", "primitives", "grass", "vram MB",
	])
	for r in results:
		print("%-8s %9.2f %9.2f %9.1f %8.0fm %8.0fm %10d %12d %10d %9.1f" % [
			r["level"], r["mean_ms"], r["p95_ms"], r["fps_mean"], r["switch_ms"], r["rebuild_ms"],
			r["draw_calls"], r["primitives"], r["grass"], r["video_mem_mb"],
		])
	print("")

	var path := "user://foliage_benchmark_%s.json" % _label.to_snake_case()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"gpu": adapter,
			"resolution": [size.x, size.y],
			"scene": _label,
			"results": results,
		}, "  "))
		file.close()
		print("wrote %s" % ProjectSettings.globalize_path(path))


## True when the process was launched with `-- --bench`.
static func requested() -> bool:
	return OS.get_cmdline_user_args().has("--bench")
