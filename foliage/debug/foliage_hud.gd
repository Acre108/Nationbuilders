class_name FoliageHUD
extends CanvasLayer

## On-screen readout for the foliage system.
##
## This is a deliverable, not a convenience: the brief asks for instance counts
## per LOD band, and the perf numbers have to come from a real windowed run.
## Godot's headless mode uses a dummy renderer where the draw-call and primitive
## monitors always read 0 -- the PlacesOS spike hit that repeatedly -- so
## anything measured without a window on screen is not a measurement.

var _label: Label
var _layer: GrassLayer
var _trees: TreeLayer
var _debris: DebrisLayer
var _location: FoliageLocation
var _atmosphere: AtmosphereSystem
var _frame_samples: PackedFloat32Array = PackedFloat32Array()
var _sample_index: int = 0
var destination_help := "N next location"

const SAMPLE_COUNT := 120


func _init() -> void:
	layer = 100


func _ready() -> void:
	_frame_samples.resize(SAMPLE_COUNT)
	_frame_samples.fill(0.0)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.modulate = Color(1, 1, 1, 0.92)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	margin.add_child(_label)


func track(layer_node: GrassLayer) -> void:
	_layer = layer_node


func track_trees(layer_node: TreeLayer) -> void:
	_trees = layer_node


func track_debris(layer_node: DebrisLayer) -> void:
	_debris = layer_node


func track_location(location: FoliageLocation) -> void:
	_location = location


## Optional. With one tracked, the HUD shows time and weather, and the sun keys
## are listed as clock keys -- the atmosphere owns the sun.
func track_atmosphere(atmosphere: AtmosphereSystem) -> void:
	_atmosphere = atmosphere


func _process(delta: float) -> void:
	_frame_samples[_sample_index] = delta * 1000.0
	_sample_index = (_sample_index + 1) % SAMPLE_COUNT

	var total := 0.0
	var worst := 0.0
	var counted := 0
	for sample in _frame_samples:
		if sample <= 0.0:
			continue
		total += sample
		worst = maxf(worst, sample)
		counted += 1
	var mean := total / float(maxi(counted, 1))

	var lines := PackedStringArray()
	lines.append("COMMANDS / F to hide or show")
	lines.append("fps %d    frame %.2f ms (worst %.2f over %ds)" % [
		Engine.get_frames_per_second(), mean, worst, SAMPLE_COUNT / 60,
	])
	lines.append("draw calls %d    primitives %s" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		_thousands(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))),
	])
	lines.append("video mem %.1f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))

	if _layer != null:
		var camera := get_viewport().get_camera_3d()
		var counts := _layer.debug_counts(camera.global_position if camera != null else null)
		lines.append("")
		lines.append("quality: %s    LOD %s" % [
			FoliageQuality.level_name(_layer.quality.level), "on" if _layer.lod_enabled else "off",
		])
		lines.append("chunks %d    grass %s    flowers %s    carved objects %d" % [
			counts["chunks"], _thousands(counts["grass"]), _thousands(counts["flowers"]), counts["carvers"],
		])
		if counts.has("near_in_range"):
			# Per LOD band, before frustum culling: what each band hands the
			# renderer from where the camera stands.
			lines.append("in range: near %s    far %s    tris %s" % [
				_thousands(counts["near_in_range"]), _thousands(counts["far_in_range"]),
				_thousands(counts["triangles_in_range"]),
			])

	if _location != null and _location.profile != null:
		lines.append("location: %s    %s    %d chunks pending" % [
			_location.profile.location_name,
			"streaming" if _location.streaming else "fixed",
			_location.pending_chunks(),
		])
	if _trees != null and _trees.visible:
		# TreeLayer folds shrubs and conifers into the same total as trees,
		# since they share every mechanism downstream of placement (see
		# TreeLayer's class comment).
		var tree_counts := _trees.debug_counts()
		lines.append("trees + shrubs: " + (
			"%d plants / %s tris" % [tree_counts["trees"], _thousands(tree_counts["triangles"])]
			if tree_counts["trees"] > 0 else "none"
		))

	if _debris != null and _debris.visible:
		var debris_counts := _debris.debug_counts()
		lines.append("debris: %d rocks/logs / %s tris" % [debris_counts["count"], _thousands(debris_counts["triangles"])])

	if _atmosphere != null:
		lines.append(_atmosphere.status_line())
	if _location != null:
		var tide := _location.tide_status_line()
		if not tide.is_empty():
			lines.append(tide)

	lines.append("")
	lines.append("RMB look · WASD/QE move · Shift sprint")
	if _atmosphere != null:
		lines.append(AtmosphereSystem.DEBUG_KEYS_HELP.replace(" · 5", "\n5").replace(" · -", "\n-"))
		lines.append("1-4 quality · F hide")
	else:
		lines.append("[ ] sun · 1-4 quality · F hide")
	lines.append("P place · R rotate · Bksp remove · L LOD tint · K LOD on/off")
	lines.append(destination_help)
	_label.text = "\n".join(lines)


func _thousands(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
