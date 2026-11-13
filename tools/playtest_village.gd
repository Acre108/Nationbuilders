extends SceneTree
## Scripted playtest of the village through real input only: the bottom
## toolbar, the build menu, map clicks, the inspector and the Treasury panel.
## Needs a window and GPU. Plays from the playable start to Villagers and
## bread, builds the services and a second house, then keeps playing at 3×.
##   Godot.exe --path . --script tools/playtest_village.gd [-- --minutes=15]
## Writes artifacts/playtest/*.png and prints a timeline and a findings list.
const Needs = preload("res://sim/needs.gd")
const Economy = preload("res://sim/economy.gd")
const OUT := "res://artifacts/playtest/"
var view
var log_lines: Array[String] = []
var findings: Array[String] = []
var toasts: Dictionary = {}

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var minutes := 15
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--minutes="): minutes = int(argument.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	view = load("res://view/village_view.tscn").instantiate()
	root.add_child(view)
	await process_frame
	await process_frame
	var sim = view.sim
	_note("Start: %d buildings, treasury %s, tax %d%%, average markup %d%%" % [sim.buildings.size(), Economy.format(sim.treasury), sim.tax_percent, sim.average_markup()])
	await _shot("00-start")
	# Speed 3× through the bottom bar.
	await _click(view.hud.speed_buttons[3].get_global_rect().get_center())
	if view.speed != 3: findings.append("Could not set 3× speed from the bottom bar")
	# Settlers eat berries; the founding stock runs out, so plant bushes early.
	await _build("berry_bushes")
	await _build("forester")
	await _until(func(): return sim.unlocked_tier >= 2, 2400, "promotion to Villagers")
	_note("Villagers at %s" % _clock(sim.tick))
	await _shot("01-villagers")
	for id in ["mill", "bakery", "chapel"]:
		await _build(id)
	await _until(func(): return int(sim.produced.get("bread", 0)) > 0, 3000, "first bread")
	_note("First bread at %s" % _clock(sim.tick))
	await _until(func(): return Economy.construction_funds(sim) >= sim.economy.construction_price(sim, sim.db.buildings.house), 3000, "gold for a second house")
	await _build("house")
	var start_tick: int = sim.tick
	var next_report: int = sim.tick
	var shot_mid := false
	while sim.tick < start_tick + minutes * 600:
		await process_frame
		_watch_toast()
		if sim.tick >= next_report:
			next_report += 600
			_report(sim)
		if not shot_mid and sim.tick >= start_tick + minutes * 300:
			shot_mid = true
			await _inspect_first("house", "02-house-inspector")
			await _inspect_first("chapel", "03-chapel-inspector")
			await _inspect_first("storehouse", "04-storehouse-inspector")
	_report(sim)
	await _click(view.hud.treasury_button.get_global_rect().get_center())
	await process_frame
	await _shot("05-treasury")
	await _click(view.hud.close_treasury_button.get_global_rect().get_center())
	await _shot("06-end")
	_review(sim)
	print("\n== PLAYTEST TIMELINE ==")
	for line in log_lines: print(line)
	print("\n== FINDINGS ==")
	for line in findings: print("- " + line)
	if findings.is_empty(): print("- none")
	quit(0)

## Opens the build menu, picks the building, and clicks a free spot that
## touches a road, as a player would after reading the placement ghost.
func _build(id: String) -> void:
	var sim = view.sim
	var cell := _spot(id)
	if cell.x < 0:
		findings.append("No free spot beside a road for %s near the village" % sim.db.buildings[id].name)
		return
	await _click(view.hud.build_button.get_global_rect().get_center())
	await _click(view.hud.build_category_buttons[sim.db.buildings[id].category].get_global_rect().get_center())
	var button: Button = view.hud.build_buttons[id]
	if button.disabled:
		findings.append("%s is locked in the build menu: %s" % [sim.db.buildings[id].name, button.get_node("Detail").text])
		await _key(KEY_ESCAPE)
		return
	await _click(button.get_global_rect().get_center())
	var before: int = sim.buildings.size()
	view.camera.focus = Vector3(cell.x + 0.5, 0, cell.y + 0.5)
	view.camera.refresh()
	await process_frame
	await _click(_screen(cell))
	await process_frame
	_watch_toast()
	if sim.buildings.size() > before:
		_note("Built %s at %s (%s)" % [sim.db.buildings[id].name, cell, _clock(sim.tick)])
	else:
		findings.append("Placing %s at %s failed: %s" % [sim.db.buildings[id].name, cell, view.hud.toast_label.text if view.hud.toast.visible else sim.last_error])
	await _key(KEY_ESCAPE)

func _spot(id: String) -> Vector2i:
	var sim = view.sim
	var row: Dictionary = sim.db.buildings[id]
	var centre: Vector2i = sim.site.founding_spot
	var best := Vector2i(-1, -1)
	var best_distance := 1 << 30
	for y in range(centre.y - 14, centre.y + 15):
		for x in range(centre.x - 14, centre.x + 15):
			var cell := Vector2i(x, y)
			if not sim.placement_error(id, cell).is_empty(): continue
			var size := Vector2i(int(row.footprint[0]), int(row.footprint[1]))
			var touches := false
			for dy in range(-1, size.y + 1):
				for dx in range(-1, size.x + 1):
					var inside := dx >= 0 and dy >= 0 and dx < size.x and dy < size.y
					var corner := (dx < 0 or dx >= size.x) and (dy < 0 or dy >= size.y)
					if not inside and not corner and sim.grid.roads.has(cell + Vector2i(dx, dy)): touches = true
			var distance: int = absi(x - centre.x) + absi(y - centre.y)
			if touches and distance < best_distance:
				best = cell
				best_distance = distance
	return best

func _inspect_first(id: String, shot: String) -> void:
	for building in view.sim.buildings.values():
		if building.definition.id == id:
			view.camera.focus = Vector3(building.cell.x + 0.5, 0, building.cell.y + 0.5)
			view.camera.refresh()
			await process_frame
			await _click(_screen(building.cell))
			await process_frame
			await process_frame
			if view.selected_uid != building.uid:
				findings.append("Clicking the %s did not select it" % building.definition.name)
			else:
				_note("%s inspector: %s" % [building.definition.name, view.hud.inspector.get_parsed_text().replace("\n", " | ").left(400)])
			await _shot(shot)
			await _key(KEY_ESCAPE)
			return

func _report(sim) -> void:
	var houses: Array[String] = []
	for building in sim.buildings.values():
		if building.definition.kind == "house":
			houses.append("T%d %d%% (settled %d%%) %s %s" % [building.tier, building.happiness, Needs.settled(building), Economy.format(building.silver), building.status])
	var store = null
	for building in sim.buildings.values():
		if building.definition.kind == "storehouse": store = building
	_note("%s | morale %d%% speed %d%% | treasury %s | carriers %d/6 | frustration %d | bread %d | %s" % [_clock(sim.tick), Needs.morale(sim), Needs.work_speed(Needs.morale(sim)), Economy.format(sim.treasury), store.crew if store != null else 0, sim.public_frustration, sim.stock("bread"), "; ".join(houses)])

## End-of-run checks a playtester would notice.
func _review(sim) -> void:
	var statuses: Array[String] = []
	for building in sim.buildings.values():
		if building.definition.kind == "producer":
			statuses.append("%s: %s" % [building.definition.name, building.status])
	_note("Workplaces at the end: " + "; ".join(statuses))
	for building in sim.buildings.values():
		if building.definition.kind == "house" and building.tier < 2:
			findings.append("A house is back at Settlers by the end (%s)" % building.status)
		if building.definition.kind == "producer" and not building.staffed:
			findings.append("%s has no workers at the end" % building.definition.name)
	if sim.public_frustration > 0:
		findings.append("Public workers went unpaid: frustration %d" % sim.public_frustration)
	if Needs.morale(sim) < 100:
		findings.append("Village morale ends at %d%% (workplaces at %d%% speed)" % [Needs.morale(sim), Needs.work_speed(Needs.morale(sim))])
	for text in toasts:
		findings.append("Error toast seen %d× : %s" % [toasts[text], text])

func _watch_toast() -> void:
	if view.hud.toast.visible and view.hud.toast_seconds > 2.9:
		toasts[view.hud.toast_label.text] = int(toasts.get(view.hud.toast_label.text, 0)) + 1

func _until(condition: Callable, max_ticks: int, label: String) -> void:
	var limit: int = view.sim.tick + max_ticks
	while not condition.call() and view.sim.tick < limit:
		await process_frame
		_watch_toast()
	if not condition.call() and not label.is_empty():
		findings.append("No %s within %s" % [label, _clock(max_ticks)])

func _screen(cell: Vector2i) -> Vector2:
	var height: float = view.relief.cell_height(cell)
	var local: Vector2 = view.camera.unproject_position(Vector3(cell.x + 0.5, height, cell.y + 0.5))
	return view.display.position + local * view.display.size / Vector2(view.pixel_viewport.size)

func _clock(ticks: int) -> String:
	return "%d:%02d" % [ticks / 600, (ticks / 10) % 60]

func _note(text: String) -> void:
	log_lines.append(text)
	print(text)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")

func _click(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move)
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame
