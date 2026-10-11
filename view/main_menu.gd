extends Control
const Campaign = preload("res://sim/campaign.gd")
const MapScene = preload("res://view/world_map/world_map_view.tscn")
const VillageScene = preload("res://view/village_view.tscn")
var campaign
var menu: Control
var map_view
var village_view
var campaign_name: LineEdit
var seed_input: LineEdit
var saves: ItemList
var paths: Array[String] = []
var status: Label
var map_status: Label
var region_text: Label
var founding_name: LineEdit
var found_button: Button
var resume_button: Button
var village_list: ItemList
var village_detail: Label
var list_ids: Array[String] = []
var selected_hex := Vector2i.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().auto_accept_quit = false
	_build_theme()
	_build_menu()
	_refresh_saves()
	# Keep the documented render smoke and authored-site debug launches working.
	for argument in OS.get_cmdline_user_args():
		if argument == "--render-smoke" or argument.begins_with("--site="):
			menu.hide()
			village_view = VillageScene.instantiate()
			add_child(village_view)
			break

func _build_theme() -> void:
	var ui := Theme.new()
	ui.default_font_size = 17
	for type in ["Label", "Button", "LineEdit", "ItemList"]:
		ui.set_color("font_color", type, Color("ebe3ce"))
	for type in ["Button", "LineEdit", "ItemList", "PanelContainer"]:
		for state in (["normal", "hover", "pressed", "disabled", "focus"] if type == "Button" else ["normal", "panel"]):
			var style := StyleBoxFlat.new()
			style.bg_color = Color("344b3c") if state in ["hover", "pressed"] else Color("1b2b24")
			style.border_color = Color("526b52")
			style.set_border_width_all(1)
			style.set_corner_radius_all(6)
			style.content_margin_left = 18
			style.content_margin_right = 18
			style.content_margin_top = 12
			style.content_margin_bottom = 12
			ui.set_stylebox(state, type, style)
	ui.set_color("font_disabled_color", "Button", Color("7c887a"))
	theme = ui

func _label(text: String, font_size: int = 17) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var backdrop := ColorRect.new()
	backdrop.color = Color("101d19")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(backdrop)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(centre)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(820, 0)
	column.add_theme_constant_override("separation", 14)
	centre.add_child(column)
	var title := _label("HEARTHLANDS", 44)
	title.add_theme_color_override("font_color", Color("d9bd7d"))
	column.add_child(title)
	column.add_child(_label("A world to discover. A village to call home.", 20))
	column.add_child(_label("1  Create a campaign     /     2  Generate your world     /     3  Found your first village", 14))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 24)
	column.add_child(cards)
	var new_card := PanelContainer.new()
	new_card.custom_minimum_size = Vector2(380, 0)
	cards.add_child(new_card)
	var new_column := VBoxContainer.new()
	new_column.add_theme_constant_override("separation", 12)
	new_card.add_child(new_column)
	new_column.add_child(_label("New campaign", 24))
	new_column.add_child(_label("Campaign name", 14))
	campaign_name = LineEdit.new()
	campaign_name.placeholder_text = "My hearthlands"
	campaign_name.max_length = 64
	new_column.add_child(campaign_name)
	new_column.add_child(_label("World seed", 14))
	seed_input = LineEdit.new()
	seed_input.text = "73"
	seed_input.max_length = 11
	new_column.add_child(seed_input)
	_button(new_column, "Random seed", func(): seed_input.text = str(randi_range(1, 2147483646)))
	_button(new_column, "Generate world", _new_campaign)
	var load_card := PanelContainer.new()
	load_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_child(load_card)
	var load_column := VBoxContainer.new()
	load_column.add_theme_constant_override("separation", 12)
	load_card.add_child(load_column)
	load_column.add_child(_label("Saved campaigns", 24))
	saves = ItemList.new()
	saves.custom_minimum_size = Vector2(360, 210)
	saves.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saves.item_activated.connect(func(_index): _load_campaign())
	load_column.add_child(saves)
	_button(load_column, "Continue campaign", _load_campaign)
	status = _label("Campaigns save when founded, left, and every two minutes during a run.", 14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)

func _refresh_saves() -> void:
	paths = Campaign.save_paths()
	saves.clear()
	for path in paths:
		var saved = Campaign.new()
		if saved.load_save(path):
			saves.add_item("%s  ·  %s" % [saved.name, saved.village_name if saved.village != null else "World ready"])
		else:
			saves.add_item(path.get_file().get_basename() + "  ·  Unavailable")
			saves.set_item_tooltip(saves.item_count - 1, saved.last_error)
	if not paths.is_empty(): saves.select(0)

func _new_campaign() -> void:
	if not seed_input.text.is_valid_int() or absi(int(seed_input.text)) > 2147483646:
		status.text = "Enter a whole-number seed between -2147483646 and 2147483646."
		return
	var created = Campaign.new()
	if not created.generate(campaign_name.text, int(seed_input.text)) or not created.save():
		status.text = created.last_error
		return
	campaign = created
	_show_map()

func _load_campaign() -> void:
	if saves.get_selected_items().is_empty():
		status.text = "No campaign selected. Generate a world to begin."
		return
	var loaded = Campaign.new()
	if not loaded.load_save(paths[saves.get_selected_items()[0]]):
		status.text = loaded.last_error
		return
	campaign = loaded
	_show_map()

func _show_map() -> void:
	menu.hide()
	map_view = MapScene.instantiate()
	map_view.provided_world = campaign.world
	map_view.provided_campaign = campaign
	map_view.campaign_mode = true
	map_view.hex_selected.connect(_select_region)
	add_child(map_view)
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	card.offset_left = -318
	card.offset_right = -18
	card.offset_top = 18
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	var title := _label(campaign.name, 22)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	region_text = _label("", 14)
	region_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	region_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var summary_scroll := ScrollContainer.new()
	summary_scroll.custom_minimum_size = Vector2(0, 190)
	summary_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(summary_scroll)
	summary_scroll.add_child(region_text)
	founding_name = LineEdit.new()
	founding_name.max_length = 64
	founding_name.placeholder_text = "Village name"
	founding_name.text_submitted.connect(func(_text):
		if not found_button.disabled: _enter_village()
	)
	column.add_child(founding_name)
	found_button = _button(column, "Found village here", _enter_village)
	found_button.clip_text = true
	resume_button = _button(column, "Resume active village", _resume_active)
	resume_button.clip_text = true
	resume_button.visible = campaign.village != null
	if resume_button.visible:
		resume_button.text = "Resume " + campaign.village_name
		resume_button.tooltip_text = resume_button.text
	_button(column, "Save campaign", _save_campaign)
	_button(column, "Save & main menu", _return_menu)
	map_status = _label("", 14)
	map_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(map_status)
	map_view.add_child(card)
	_build_village_list()
	if not campaign.map_view_state.is_empty(): map_view.restore_view_state(campaign.map_view_state)
	_select_region(campaign.map_view_state.get("selected_hex", campaign.world.start if campaign.village == null else campaign.village_hex))

func _build_village_list() -> void:
	var card := PanelContainer.new()
	card.position = Vector2(18, 18)
	card.custom_minimum_size = Vector2(225, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	column.add_child(_label("Your villages", 22))
	village_list = ItemList.new()
	village_list.custom_minimum_size = Vector2(189, 215)
	village_list.add_theme_font_size_override("font_size", 14)
	village_list.item_selected.connect(_select_village_row)
	village_list.item_activated.connect(func(index):
		_select_village_row(index)
		if list_ids[index] == campaign.active_village: _resume_active()
	)
	column.add_child(village_list)
	list_ids.clear()
	for record in campaign.villages:
		list_ids.append(record.id)
		village_list.add_item("%s · %s" % [record.name, record.status.capitalize()])
		village_list.set_item_tooltip(village_list.item_count - 1, "%s\nTier %d · %d people · %d buildings\nFounded turn %d" % [record.name, record.best_tier, record.population, record.buildings, record.founded_turn])
	village_detail = _label("Select a village to centre the map." if not list_ids.is_empty() else "No villages yet.\nChoose a hex to found your first.", 14)
	village_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(village_detail)
	map_view.add_child(card)

func _select_village_row(index: int) -> void:
	var record: Dictionary = campaign.villages[index]
	map_view.center_on(record.hex)
	_select_region(record.hex)
	village_detail.text = "%s · %s\nTier %d · %d people\n%d buildings · founded turn %d" % [record.name, record.status.capitalize(), record.best_tier, record.population, record.buildings, record.founded_turn]

func _select_region(coord: Vector2i) -> void:
	selected_hex = coord
	map_view.select_hex(coord)
	var info = campaign.world.hex(coord)
	if info == null: return
	var record: Dictionary = campaign.village_at(coord)
	var active_here: bool = not record.is_empty() and record.id == campaign.active_village
	var blocked: String = campaign.found_blocked(coord)
	var biome: Dictionary = campaign.world.data.biomes[info.biome]
	var summary := "%s · %s\nRegion %d, %d · wildness %d" % [biome.name, "Harsh" if biome.get("harsh", false) else "Normal", coord.x, coord.y, info.wildness]
	if not record.is_empty():
		summary += "\n%s · %s\nTier %d · %d people · %d buildings" % [record.name, record.status.capitalize(), record.best_tier, record.population, record.buildings]
		if not record.result.is_empty(): summary += "\nRun: %s · %d ticks" % [record.result.outcome.capitalize(), record.result.duration_ticks]
	if active_here:
		summary += "\nYour active village is waiting."
	else:
		summary += "\n" + ("Confirm the name below to found here." if blocked.is_empty() else blocked)
		var deposits: Array[String] = []
		for reach_hex in campaign.world.reach(coord):
			var known: Array[String] = campaign.world.visible_deposits(reach_hex)
			if not known.is_empty():
				var names: Array[String] = []
				for deposit in known: names.append(String(campaign.world.data.deposits[deposit].name))
				deposits.append("%d,%d: %s" % [reach_hex.x, reach_hex.y, ", ".join(names)])
		summary += "\nKnown reach deposits:\n" + ("\n".join(deposits) if not deposits.is_empty() else "None known")
		if not info.scouted: summary += "\nUnscouted — hidden deposits unknown"
	region_text.text = summary
	founding_name.visible = not active_here and blocked.is_empty()
	if founding_name.visible: founding_name.text = "Hearth %d" % (campaign.villages.size() + 1)
	found_button.text = "Resume " + record.name if active_here else ("Resettle village here" if not record.is_empty() and record.status in ["ruin", "abandoned"] else "Found village here")
	found_button.tooltip_text = found_button.text
	found_button.disabled = not active_here and not blocked.is_empty()

func _enter_village() -> void:
	var record: Dictionary = campaign.village_at(selected_hex)
	if not record.is_empty() and record.id == campaign.active_village:
		_resume_active()
		return
	if not campaign.found(selected_hex, founding_name.text):
		map_status.text = campaign.last_error
		return
	if not _save_campaign():
		resume_button.show()
		resume_button.text = "Resume " + campaign.village_name
		_select_region(selected_hex)
		return
	_resume_active()

func _resume_active() -> void:
	if campaign.village == null: return
	if not _save_campaign(): return
	_retire_view(map_view)
	map_view = null
	village_view = VillageScene.instantiate()
	village_view.campaign = campaign
	village_view.campaign_map_requested.connect(_leave_village)
	village_view.campaign_menu_requested.connect(_leave_to_menu)
	village_view.campaign_result_requested.connect(_end_run)
	add_child(village_view)

func _capture_view_state() -> void:
	if map_view != null: campaign.map_view_state = map_view.capture_view_state()
	if village_view != null: village_view.capture_campaign_view_state()

func _end_run(outcome: String) -> void:
	_capture_view_state()
	if not campaign.end_and_save(outcome):
		village_view.hud.show_error(campaign.last_error)
		return
	_retire_view(village_view)
	village_view = null
	_show_map()
	map_status.text = "Village %s. Choose the next site, or review your villages." % ("chartered" if outcome == "charter" else "lost" if outcome == "ruin" else "abandoned")

func _save_campaign() -> bool:
	_capture_view_state()
	var success: bool = campaign.save()
	map_status.text = "Campaign saved." if success else campaign.last_error
	return success

func _leave_village() -> void:
	_capture_view_state()
	if not campaign.save():
		village_view.hud.show_error(campaign.last_error)
		return
	_retire_view(village_view)
	village_view = null
	_show_map()

func _leave_to_menu() -> void:
	_capture_view_state()
	if not campaign.save():
		village_view.hud.show_error(campaign.last_error)
		return
	_retire_view(village_view)
	village_view = null
	campaign = null
	menu.show()
	_refresh_saves()
	status.text = "Campaign saved."

func _return_menu() -> void:
	if not _save_campaign(): return
	_retire_view(map_view)
	map_view = null
	campaign = null
	menu.show()
	_refresh_saves()
	status.text = "Campaign saved."

func _retire_view(view: Node) -> void:
	# Exit the old atmosphere before the next scene creates its weather bus.
	# Free later so button signals can finish dispatching safely.
	remove_child(view)
	view.queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_capture_view_state()
		if campaign != null and not campaign.save():
			if village_view != null: village_view.hud.show_error(campaign.last_error)
			elif map_status != null: map_status.text = campaign.last_error
			return
		get_tree().quit()
