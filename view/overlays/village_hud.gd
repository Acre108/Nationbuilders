extends CanvasLayer
signal tool_selected(id: String)
signal deposits_toggled
signal inspection_closed
var inspector: RichTextLabel
var build_buttons: Dictionary = {}
var demolish_button: Button
var deposits_button: Button
var build_button: Button
var root: Control
var bottom: PanelContainer
var side: PanelContainer
var build_menu: PanelContainer
var build_grid: GridContainer
var toast: PanelContainer
var toast_label: Label
var toast_seconds := 0.0

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 15
	theme.set_color("font_color","Label",Color("e1cea1"))
	for state in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("284146") if state == "normal" else Color("416358")
		if state == "disabled": style.bg_color = Color("222f32")
		style.set_corner_radius_all(5)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		theme.set_stylebox(state,"Button",style)
	theme.set_color("font_color","Button",Color("f0e2bc"))
	theme.set_color("font_disabled_color","Button",Color("73847b"))
	root.theme = theme
	bottom = _panel()
	root.add_child(bottom)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",8)
	bottom.add_child(actions)
	demolish_button = _button("Demolish")
	demolish_button.toggle_mode = true
	demolish_button.tooltip_text = "Remove a building or road"
	demolish_button.pressed.connect(func(): tool_selected.emit("demolish" if demolish_button.button_pressed else "inspect"))
	actions.add_child(demolish_button)
	deposits_button = _button("Deposits")
	deposits_button.toggle_mode = true
	deposits_button.tooltip_text = "Show deposits (F3)"
	deposits_button.pressed.connect(func(): deposits_toggled.emit())
	actions.add_child(deposits_button)
	build_button = _button("Build")
	build_button.toggle_mode = true
	build_button.pressed.connect(_toggle_build_menu)
	actions.add_child(build_button)
	for button in [demolish_button,deposits_button,build_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_menu = _panel()
	build_menu.visible = false
	root.add_child(build_menu)
	var menu_column := VBoxContainer.new()
	menu_column.add_theme_constant_override("separation",10)
	build_menu.add_child(menu_column)
	var menu_header := HBoxContainer.new()
	menu_column.add_child(menu_header)
	var title := _label("Build",18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_header.add_child(title)
	var close_menu := _button("×")
	close_menu.pressed.connect(close_build_menu)
	menu_header.add_child(close_menu)
	build_grid = GridContainer.new()
	build_grid.columns = 2
	build_grid.add_theme_constant_override("h_separation",8)
	build_grid.add_theme_constant_override("v_separation",8)
	menu_column.add_child(build_grid)
	side = _panel()
	side.visible = false
	root.add_child(side)
	var info := HBoxContainer.new()
	side.add_child(info)
	inspector = RichTextLabel.new()
	inspector.bbcode_enabled = true
	inspector.fit_content = true
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.custom_minimum_size = Vector2(180,70)
	inspector.add_theme_color_override("default_color",Color("e1cea1"))
	info.add_child(inspector)
	var close_inspector := _button("×")
	close_inspector.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_inspector.pressed.connect(func(): inspection_closed.emit())
	info.add_child(close_inspector)
	toast = _panel()
	toast.visible = false
	root.add_child(toast)
	toast_label = _label("",14)
	toast_label.add_theme_color_override("font_color",Color("dfa66b"))
	toast.add_child(toast_label)
	root.resized.connect(_layout)
	_layout()

func configure_build_menu(db) -> void:
	for child in build_grid.get_children():
		build_grid.remove_child(child)
		child.queue_free()
	build_buttons.clear()
	for id in db.buildings:
		var row: Dictionary = db.buildings[id]
		var button := _button(row.name)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "Click two tiles" if row.kind == "road" else "Place beside a road"
		button.pressed.connect(func():
			close_build_menu()
			tool_selected.emit(id)
		)
		build_buttons[id] = button
		build_grid.add_child(button)
	_layout()

func _toggle_build_menu() -> void:
	build_menu.visible = not build_menu.visible
	build_button.button_pressed = build_menu.visible
	if build_menu.visible:
		tool_selected.emit("inspect")
	_layout()

func close_build_menu() -> void:
	build_menu.visible = false
	build_button.button_pressed = false

func reset() -> void:
	close_build_menu()
	side.visible = false
	toast.visible = false
	toast_seconds = 0
	set_deposits_visible(false)

func set_deposits_visible(value: bool) -> void:
	deposits_button.button_pressed = value

func show_error(text: String) -> void:
	toast_label.text = text
	toast.visible = true
	toast_seconds = 3.0
	_layout()

func _process(delta: float) -> void:
	if toast_seconds > 0:
		toast_seconds -= delta
		if toast_seconds <= 0:
			toast.visible = false

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065,0.12,0.13,0.96)
	style.border_color = Color("416358")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel",style)
	return panel

func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	bottom.size = Vector2(360,62).max(bottom.get_combined_minimum_size())
	bottom.position = Vector2((screen.x-bottom.size.x)/2.0,screen.y-bottom.size.y-18).floor()
	build_menu.size = Vector2(360,0).max(build_menu.get_combined_minimum_size())
	build_menu.position = Vector2(bottom.position.x, bottom.position.y-build_menu.size.y-10).floor()
	side.size = Vector2(260,100).max(side.get_combined_minimum_size())
	side.position = Vector2(screen.x-side.size.x-18,18)
	toast.reset_size()
	toast.position = Vector2((screen.x-toast.size.x)/2.0,20).floor()

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	return label

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	return button

func blocks_mouse(point: Vector2) -> bool:
	for panel in [bottom,build_menu,side,toast]:
		if panel.visible and panel.get_global_rect().has_point(point):
			return true
	return false

func refresh(sim, selected_id: int, tool: String) -> void:
	demolish_button.button_pressed = tool == "demolish"
	demolish_button.modulate = Color("dfa66b") if tool == "demolish" else Color.WHITE
	for id in build_buttons:
		var button: Button = build_buttons[id]
		var row: Dictionary = sim.db.buildings[id]
		button.modulate = Color("dfa66b") if tool == id else Color.WHITE
		button.disabled = int(row.unlock_tier) > sim.unlocked_tier
		button.tooltip_text = "Requires Villagers" if button.disabled else ("Click two tiles" if row.kind == "road" else "Place beside a road")
	var selected = sim.buildings.get(selected_id)
	side.visible = selected != null and tool == "inspect"
	if side.visible:
		var text := "[font_size=18]%s[/font_size]\n" % selected.definition.name
		if selected.definition.kind == "house":
			text += "%s\n" % sim.db.tiers[selected.tier].name
		text += "[color=#dfa66b]%s[/color]" % selected.status.capitalize()
		inspector.text = text
