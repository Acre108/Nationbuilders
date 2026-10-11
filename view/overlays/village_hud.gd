extends CanvasLayer
const ContentDB = preload("res://sim/content_db.gd")
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
var build_title: Label
var build_back_button: Button
var category_list: VBoxContainer
var building_list: VBoxContainer
var build_category_buttons: Dictionary = {}
var build_details: Dictionary = {}
var build_category := ""
var supply_bar: HBoxContainer
var supply_items: Dictionary = {}
var supply_labels: Dictionary = {}
var category_goods: Dictionary = {}
var placement_card: PanelContainer
var placement_title: Label
var placement_info: RichTextLabel
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
	menu_header.add_theme_constant_override("separation",8)
	menu_column.add_child(menu_header)
	build_back_button = _button("‹")
	build_back_button.tooltip_text = "Back to categories"
	build_back_button.pressed.connect(show_build_categories)
	menu_header.add_child(build_back_button)
	build_title = _label("Build",18)
	build_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_header.add_child(build_title)
	var close_menu := _button("×")
	close_menu.pressed.connect(close_build_menu)
	menu_header.add_child(close_menu)
	supply_bar = HBoxContainer.new()
	supply_bar.add_theme_constant_override("separation",16)
	menu_column.add_child(supply_bar)
	category_list = VBoxContainer.new()
	category_list.add_theme_constant_override("separation",6)
	menu_column.add_child(category_list)
	building_list = VBoxContainer.new()
	building_list.add_theme_constant_override("separation",6)
	menu_column.add_child(building_list)
	placement_card = _panel()
	placement_card.visible = false
	root.add_child(placement_card)
	var placement_column := VBoxContainer.new()
	placement_column.add_theme_constant_override("separation",6)
	placement_card.add_child(placement_column)
	placement_title = _label("",18)
	placement_column.add_child(placement_title)
	placement_info = RichTextLabel.new()
	placement_info.bbcode_enabled = true
	placement_info.fit_content = true
	placement_info.scroll_active = false
	placement_info.custom_minimum_size = Vector2(290,0)
	placement_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placement_info.add_theme_color_override("default_color",Color("e1cea1"))
	placement_column.add_child(placement_info)
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
	for list in [category_list,building_list,supply_bar]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	build_buttons.clear()
	build_category_buttons.clear()
	build_details.clear()
	supply_items.clear()
	supply_labels.clear()
	# Goods any building costs, per category; "" is the category overview.
	category_goods = {"": []}
	for category in ContentDB.CATEGORIES:
		category_goods[category] = []
	for row in db.buildings.values():
		for good in row.cost:
			for key in ["",row.category]:
				if good not in category_goods[key]: category_goods[key].append(good)
			if not supply_items.has(good):
				var item := HBoxContainer.new()
				item.add_theme_constant_override("separation",6)
				item.tooltip_text = "%s in storehouses" % db.goods[good].name
				var icon := TextureRect.new()
				icon.texture = _good_icon(good,db.goods[good].color)
				icon.custom_minimum_size = Vector2(20,20)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				item.add_child(icon)
				var label := _label("0",15)
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				item.add_child(label)
				supply_items[good] = item
				supply_labels[good] = label
				supply_bar.add_child(item)
	for category in ContentDB.CATEGORIES:
		var members: Array = db.buildings.keys().filter(func(id): return db.buildings[id].category == category)
		if members.is_empty(): continue
		var category_button := _menu_row(ContentDB.CATEGORIES[category],"%d  ›" % members.size())
		category_button.tooltip_text = ", ".join(members.map(func(id): return db.buildings[id].name))
		category_button.pressed.connect(show_build_category.bind(category))
		build_category_buttons[category] = category_button
		category_list.add_child(category_button)
		for id in members:
			var button := _menu_row(db.buildings[id].name,"")
			button.set_meta("category",category)
			button.pressed.connect(func():
				close_build_menu()
				tool_selected.emit(id)
			)
			build_buttons[id] = button
			build_details[id] = button.get_node("Detail")
			building_list.add_child(button)
	show_build_categories()

func show_build_categories() -> void:
	build_category = ""
	build_title.text = "Build"
	build_back_button.visible = false
	category_list.visible = true
	building_list.visible = false
	_show_supply("")
	_layout()

func show_build_category(category: String) -> void:
	build_category = category
	build_title.text = ContentDB.CATEGORIES[category]
	build_back_button.visible = true
	category_list.visible = false
	building_list.visible = true
	for button in building_list.get_children():
		button.visible = button.get_meta("category") == category
	_show_supply(category)
	_layout()

## Show only the goods some building on this page costs.
func _show_supply(category: String) -> void:
	for good in supply_items:
		supply_items[good].visible = good in category_goods[category]
	supply_bar.visible = not category_goods[category].is_empty()

## Hand-drawn SVG from view/overlays/goods/, else a token in the good's colour.
func _good_icon(good: String, color: String) -> Texture2D:
	var path := "res://view/overlays/goods/%s.svg" % good
	var svg := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else \
		'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="12" r="9" fill="#%s" stroke="#1b241c" stroke-width="2"/></svg>' % color
	var image := Image.new()
	image.load_svg_from_string(svg,2.0)
	return ImageTexture.create_from_image(image)

func _toggle_build_menu() -> void:
	build_menu.visible = not build_menu.visible
	build_button.button_pressed = build_menu.visible
	if build_menu.visible:
		show_build_categories()
		tool_selected.emit("inspect")
	_layout()

func close_build_menu() -> void:
	build_menu.visible = false
	build_button.button_pressed = false

func reset() -> void:
	close_build_menu()
	placement_card.visible = false
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
	placement_card.size = Vector2(320,0).max(placement_card.get_combined_minimum_size())
	placement_card.position = Vector2(18,screen.y-placement_card.size.y-18).floor()
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

## Full-width menu button with a right-aligned detail label (count, cost).
func _menu_row(text: String, detail: String) -> Button:
	var button := _button(text)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := _label(detail,13)
	label.name = "Detail"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_right = -14
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	return button

func blocks_mouse(point: Vector2) -> bool:
	for panel in [bottom,build_menu,placement_card,side,toast]:
		if panel.visible and panel.get_global_rect().has_point(point):
			return true
	return false

func refresh(sim, selected_id: int, tool: String) -> void:
	demolish_button.button_pressed = tool == "demolish"
	demolish_button.modulate = Color("dfa66b") if tool == "demolish" else Color.WHITE
	for id in build_buttons:
		var button: Button = build_buttons[id]
		var row: Dictionary = sim.db.buildings[id]
		var detail: Label = build_details[id]
		button.modulate = Color("dfa66b") if tool == id else Color.WHITE
		button.disabled = int(row.unlock_tier) > sim.unlocked_tier
		if button.disabled:
			detail.text = "Needs " + sim.db.tiers[int(row.unlock_tier)].name
			detail.add_theme_color_override("font_color",Color("73847b"))
		else:
			detail.text = _cost_text(row.cost,sim.db)
			detail.add_theme_color_override("font_color",Color("dfa66b") if _affordable(sim,row.cost) else Color("d98c6f"))
		button.tooltip_text = _requirements_summary(row,sim.db)
	for good in supply_labels:
		supply_labels[good].text = str(sim.stock(good))
	placement_card.visible = sim.db.buildings.has(tool) and not build_menu.visible
	if placement_card.visible:
		_refresh_placement(sim,sim.db.buildings[tool])
	var selected = sim.buildings.get(selected_id)
	side.visible = selected != null and tool == "inspect"
	if side.visible:
		var text := "[font_size=18]%s[/font_size]\n" % selected.definition.name
		if selected.definition.kind == "house":
			text += "%s\n" % sim.db.tiers[selected.tier].name
		text += "[color=#dfa66b]%s[/color]" % selected.status.capitalize()
		inspector.text = text

func _refresh_placement(sim, row: Dictionary) -> void:
	placement_title.text = row.name
	var cost_parts: Array[String] = []
	for good in row.cost:
		var need := int(row.cost[good])
		var have: int = sim.stock(good)
		cost_parts.append("[color=#%s]%d %s[/color] [color=#73847b](have %d)[/color]" % ["e1cea1" if have >= need else "d98c6f",need,sim.db.goods[good].name,have])
	var lines: Array[String] = ["[b]Cost[/b]  " + ("Free" if cost_parts.is_empty() else ", ".join(cost_parts))]
	if int(row.workers) > 0:
		lines.append("[b]Workers[/b]  %d" % int(row.workers))
	match row.kind:
		"producer":
			if not row.inputs.is_empty():
				lines.append("[b]Uses[/b]  " + _goods(row.inputs,sim.db))
			lines.append("[b]Makes[/b]  %s every %.1f s" % [_goods(row.outputs,sim.db),float(row.cycle_ticks)/10.0])
		"storehouse":
			lines.append("[b]Storage[/b]  %d  ·  %d carriers" % [int(row.storage_capacity),int(row.carriers)])
		"house":
			var tier: Dictionary = sim.db.tiers[1]
			lines.append("[b]Houses[/b]  %s  ·  %d workers" % [tier.name,int(tier.workers_per_house)])
	if row.kind != "road":
		lines.append("[b]Size[/b]  %d × %d" % [int(row.footprint[0]),int(row.footprint[1])])
	lines.append("[color=#73847b]%s\nRight-click to cancel[/color]" % ("Click two tiles to lay a road" if row.kind == "road" else "Place beside a road"))
	var text := "\n".join(lines)
	if placement_info.text != text:
		placement_info.text = text
	# Re-anchor every refresh: the rich text settles its height a frame late.
	_layout()

func _requirements_summary(row: Dictionary, db) -> String:
	var parts: Array[String] = ["Cost: " + _cost_text(row.cost,db)]
	if int(row.workers) > 0:
		parts.append("Workers: %d" % int(row.workers))
	if row.kind == "producer":
		parts.append(("Makes " if row.inputs.is_empty() else _goods(row.inputs,db) + " → ") + _goods(row.outputs,db))
	return "\n".join(parts)

func _cost_text(cost: Dictionary, db) -> String:
	return "Free" if cost.is_empty() else _goods(cost,db)

func _affordable(sim, cost: Dictionary) -> bool:
	for good in cost:
		if sim.stock(good) < int(cost[good]):
			return false
	return true

func _goods(items: Dictionary, db) -> String:
	if items.is_empty():
		return "None"
	var parts: Array[String] = []
	for good in items:
		parts.append("%d %s" % [int(items[good]),db.goods[good].name])
	return ", ".join(parts)
