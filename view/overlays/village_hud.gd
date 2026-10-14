extends CanvasLayer
const ContentDB = preload("res://sim/content_db.gd")
const Building = preload("res://sim/building.gd")
const Economy = preload("res://sim/economy.gd")
const Needs = preload("res://sim/needs.gd")
signal tool_selected(id: String)
signal rotation_requested
signal deposits_toggled
signal inspection_closed
signal workers_toggled
signal speed_selected(speed: int)
signal restart_requested
signal weather_selected(kind: AtmosphereProfile.Weather, intensity: float)
signal time_of_day_selected(hour: float)
signal clock_toggled(running: bool)
signal fade_selected(seconds: float)
signal wind_selected(from_degrees: float, breeze: float, gust_speed: float)
signal weather_action(id: String)
signal world_map_requested
signal campaign_save_requested
signal campaign_menu_requested
signal campaign_abandon_requested
signal campaign_charter_requested
signal site_overview_requested
signal run_choice_selected(choice: String)
signal tax_selected(percent: int)
signal reserve_transfer_requested(pot: String, amount: int)
## Gold counter (top left), the one global counter on the play screen. It
## opens the Treasury panel: reserves, tax and the payday ledger.
var treasury_button: Button
## Always-visible storehouse fill and key stocks, beside the gold counter.
var stock_bar: PanelContainer
var stock_label: Label
var stock_bar_gold := ""
var treasury_menu: PanelContainer
var close_treasury_button: Button
var treasury_total: Label
var treasury_values: Dictionary = {}
var reserve_buttons: Dictionary = {}
var tax_value: Label
var tax_buttons: Dictionary = {}
var markup_value: Label
var treasury_ledger: RichTextLabel
var shown_tax := Economy.DEFAULT_TAX_PERCENT
## The village last refreshed, so the Treasury panel fills as soon as it opens.
var shown_sim
var campaign_save_button: Button
var campaign_menu_button: Button
var campaign_map_button: Button
var campaign_abandon_button: Button
var campaign_charter_button: Button
var site_overview_button: Button
var run_card: Control
var run_card_title: Label
var run_card_text: Label
var run_primary_button: Button
var run_secondary_button: Button
var run_card_kind := ""
const VillageAtmosphere = preload("res://view/village_atmosphere.gd")
var inspector: RichTextLabel
var inspector_title: Label
var close_inspector: Button
var inspection_progress: ProgressBar
var workers_button: Button
var build_buttons: Dictionary = {}
var demolish_button: Button
var deposits_button: Button
var build_button: Button
var cog_button: Button
var map_button: Button
var options_menu: PanelContainer
var close_options_button: Button
var speed_buttons: Dictionary = {}
var restart_button: Button
var sun_button: Button
var weather_menu: PanelContainer
var close_weather_button: Button
var weather_buttons: Dictionary = {}
var intensity_slider: HSlider
var time_slider: HSlider
var clock_button: CheckButton
var fade_slider: HSlider
var wind_from_slider: HSlider
var breeze_slider: HSlider
var gust_speed_slider: HSlider
var weather_action_buttons: Dictionary = {}
var weather_stats: Array[RichTextLabel] = []
var slider_values: Dictionary = {}
var weather_kind := AtmosphereProfile.Weather.CLEAR
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
var rotate_button: Button
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
	theme.set_color("font_color","Label",Color("e4dfd2"))
	for state in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("2d3328") if state == "normal" else Color("485439")
		if state == "disabled": style.bg_color = Color("222820")
		style.set_corner_radius_all(5)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		theme.set_stylebox(state,"Button",style)
	theme.set_color("font_color","Button",Color("e4dfd2"))
	theme.set_color("font_disabled_color","Button",Color("868f7a"))
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
	placement_info.add_theme_color_override("default_color",Color("e4dfd2"))
	placement_column.add_child(placement_info)
	rotate_button = _button("Rotate 90° (R)")
	rotate_button.tooltip_text = "Turn the building before placing it"
	rotate_button.pressed.connect(func(): rotation_requested.emit())
	placement_column.add_child(rotate_button)
	side = _panel()
	side.visible = false
	root.add_child(side)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation",10)
	side.add_child(info)
	var inspection_header := HBoxContainer.new()
	info.add_child(inspection_header)
	inspector_title = _label("",20)
	inspector_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspection_header.add_child(inspector_title)
	close_inspector = _button("×")
	close_inspector.tooltip_text = "Close inspection"
	close_inspector.pressed.connect(func(): inspection_closed.emit())
	inspection_header.add_child(close_inspector)
	inspector = RichTextLabel.new()
	inspector.bbcode_enabled = true
	inspector.fit_content = false
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.custom_minimum_size = Vector2(290,310)
	inspector.add_theme_color_override("default_color",Color("e4dfd2"))
	info.add_child(inspector)
	inspection_progress = ProgressBar.new()
	inspection_progress.custom_minimum_size = Vector2(0,12)
	inspection_progress.show_percentage = false
	var progress_background := StyleBoxFlat.new()
	progress_background.bg_color = Color("2d3328")
	progress_background.set_corner_radius_all(4)
	inspection_progress.add_theme_stylebox_override("background",progress_background)
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color("d6c288")
	progress_fill.set_corner_radius_all(4)
	inspection_progress.add_theme_stylebox_override("fill",progress_fill)
	info.add_child(inspection_progress)
	workers_button = _button("Stop workers")
	workers_button.tooltip_text = "Release this building's workers to other jobs"
	workers_button.pressed.connect(func(): workers_toggled.emit())
	info.add_child(workers_button)
	cog_button =_icon_button("res://view/overlays/cog.svg","Options")
	cog_button.pressed.connect(_toggle_options_menu)
	root.add_child(cog_button)
	sun_button = _icon_button("res://view/overlays/sun.svg","Weather")
	sun_button.pressed.connect(_toggle_weather_menu)
	root.add_child(sun_button)
	map_button = _icon_button("res://view/overlays/map.svg","World map")
	map_button.toggle_mode = false
	map_button.pressed.connect(func(): world_map_requested.emit())
	root.add_child(map_button)
	_build_treasury_menu()
	stock_bar = _panel()
	stock_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock_bar.tooltip_text = "Storehouse fill and key stocks"
	stock_label = _label("", 15)
	stock_bar.add_child(stock_label)
	root.add_child(stock_bar)
	_build_weather_menu()
	options_menu = _panel()
	options_menu.visible = false
	root.add_child(options_menu)
	var options_column := VBoxContainer.new()
	options_column.add_theme_constant_override("separation",4)
	options_menu.add_child(options_column)
	var options_header := HBoxContainer.new()
	options_column.add_child(options_header)
	var options_title := _label("Options",20)
	options_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_header.add_child(options_title)
	close_options_button = _button("×")
	close_options_button.tooltip_text = "Close options"
	close_options_button.pressed.connect(close_options_menu)
	options_header.add_child(close_options_button)
	options_column.add_child(_label("Simulation",14))
	var speed_row := HBoxContainer.new()
	options_column.add_child(speed_row)
	for entry in [["Pause",0],["1×",1],["3×",3]]:
		var button := _button(entry[0])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): speed_selected.emit(entry[1]))
		speed_buttons[entry[1]] = button
		speed_row.add_child(button)
	options_column.add_child(HSeparator.new())
	site_overview_button = _button("Site overview (Home)")
	site_overview_button.tooltip_text = "Frame the whole village site"
	site_overview_button.pressed.connect(func():
		close_options_menu()
		site_overview_requested.emit()
	)
	options_column.add_child(site_overview_button)
	options_column.add_child(HSeparator.new())
	restart_button = _button("Restart village")
	restart_button.pressed.connect(func(): restart_requested.emit())
	options_column.add_child(restart_button)
	campaign_save_button = _button("Save campaign")
	campaign_save_button.pressed.connect(func(): campaign_save_requested.emit())
	options_column.add_child(campaign_save_button)
	campaign_menu_button = _button("Save & main menu")
	campaign_menu_button.pressed.connect(func(): campaign_menu_requested.emit())
	options_column.add_child(campaign_menu_button)
	campaign_map_button = _button("World map")
	campaign_map_button.pressed.connect(func(): world_map_requested.emit())
	options_column.add_child(campaign_map_button)
	campaign_charter_button = _button("Charter village")
	campaign_charter_button.pressed.connect(func(): campaign_charter_requested.emit())
	options_column.add_child(campaign_charter_button)
	campaign_abandon_button = _button("Abandon village…")
	campaign_abandon_button.pressed.connect(func(): campaign_abandon_requested.emit())
	options_column.add_child(campaign_abandon_button)
	set_campaign_controls(false)
	_build_run_card()
	toast = _panel()
	toast.visible = false
	root.add_child(toast)
	toast_label = _label("",14)
	toast_label.add_theme_color_override("font_color",Color("d6c288"))
	toast.add_child(toast_label)
	root.resized.connect(_layout)
	_layout()

func set_campaign_controls(enabled: bool) -> void:
	campaign_save_button.visible = enabled
	campaign_menu_button.visible = enabled
	campaign_map_button.visible = enabled
	campaign_abandon_button.visible = enabled
	campaign_charter_button.visible = enabled
	campaign_charter_button.disabled = true
	restart_button.visible = not enabled

func _build_run_card() -> void:
	run_card = Control.new()
	run_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	run_card.hide()
	root.add_child(run_card)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.06, 0.045, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	run_card.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	run_card.add_child(centre)
	var card := _panel()
	card.custom_minimum_size = Vector2(440, 0)
	centre.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	run_card_title = _label("", 24)
	column.add_child(run_card_title)
	run_card_text = _label("", 16)
	run_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(run_card_text)
	run_primary_button = _button("")
	run_primary_button.focus_mode = Control.FOCUS_ALL
	run_primary_button.pressed.connect(func(): run_choice_selected.emit(run_card_kind))
	column.add_child(run_primary_button)
	run_secondary_button = _button("")
	run_secondary_button.focus_mode = Control.FOCUS_ALL
	run_secondary_button.pressed.connect(func(): run_choice_selected.emit("keep"))
	column.add_child(run_secondary_button)

func show_run_card(kind: String, village_name: String, best_tier: int, population: int, ticks: int) -> void:
	close_options_menu()
	close_build_menu()
	close_weather_menu()
	close_treasury_menu()
	run_card_kind = kind
	run_card_title.text = "Ready for a charter" if kind == "charter" else "Abandon this village?" if kind == "abandoned" else "The village has fallen"
	run_card_text.text = "%s\nTier %d · %d people · %d ticks\n\n%s" % [village_name, best_tier, population, ticks,
		"The highest current tier is reached. Charter this village and choose a new site, or keep building." if kind == "charter" else "This ends the run and leaves a ruin on the map. You can resettle its site later." if kind == "abandoned" else "Return to the world map to choose a new site. The ruin remains part of your nation."]
	run_primary_button.text = "Charter village" if kind == "charter" else "Confirm abandon" if kind == "abandoned" else "Return to world map"
	run_secondary_button.text = "Keep building" if kind == "charter" else "Cancel"
	run_secondary_button.visible = kind != "ruin"
	run_card.show()
	# Destructive confirmation starts on Cancel; Enter cannot accidentally abandon.
	if kind == "abandoned": run_secondary_button.grab_focus()
	else: run_primary_button.grab_focus()

func close_run_card() -> void:
	run_card.hide()
	run_card_kind = ""

func _build_treasury_menu() -> void:
	treasury_button = _button("")
	treasury_button.toggle_mode = true
	treasury_button.custom_minimum_size = Vector2(0,48)
	treasury_button.tooltip_text = "Village treasury: open the Treasury panel"
	var image := Image.new()
	image.load_svg_from_string(FileAccess.get_file_as_string("res://view/overlays/coin.svg"),1.0)
	treasury_button.icon = ImageTexture.create_from_image(image)
	treasury_button.add_theme_font_size_override("font_size",17)
	treasury_button.add_theme_color_override("font_color",Color("d6c288"))
	treasury_button.add_theme_color_override("font_pressed_color",Color("d6c288"))
	treasury_button.add_theme_color_override("font_hover_color",Color("f0e2bc"))
	treasury_button.pressed.connect(_toggle_treasury_menu)
	root.add_child(treasury_button)
	treasury_menu = _panel()
	treasury_menu.visible = false
	root.add_child(treasury_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	column.custom_minimum_size = Vector2(330,0)
	treasury_menu.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("Treasury",20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	close_treasury_button = _button("×")
	close_treasury_button.tooltip_text = "Close treasury"
	close_treasury_button.pressed.connect(close_treasury_menu)
	header.add_child(close_treasury_button)
	treasury_total = _label("",22)
	treasury_total.add_theme_color_override("font_color",Color("d6c288"))
	column.add_child(treasury_total)
	# Reserves are moved by hand: construction cannot spend public pay, and
	# public pay cannot spend the capital reserve.
	for entry in [["free","Free gold","Spent by construction and public pay alike"],
			["public","Public pay reserve","Pays public workers first; construction never touches it"],
			["capital","Capital reserve","Pays for construction first; public pay never touches it"]]:
		var buttons: Array = [] if entry[0] == "free" else [["−1 g",-Economy.SILVER_PER_GOLD],["+1 g",Economy.SILVER_PER_GOLD]]
		var row := _treasury_row(column,entry[1],entry[2],buttons,func(amount): reserve_transfer_requested.emit(entry[0],amount))
		treasury_values[entry[0]] = row[0]
		if not row[1].is_empty(): reserve_buttons[entry[0]] = row[1]
	column.add_child(HSeparator.new())
	var tax_row := _treasury_row(column,"Tax on wages","Withheld from household wages at payday",[["−%d%%" % Economy.TAX_STEP,-Economy.TAX_STEP],["+%d%%" % Economy.TAX_STEP,Economy.TAX_STEP]],
		func(step): tax_selected.emit(clampi(shown_tax + step,0,Economy.MAX_TAX_PERCENT)))
	tax_value = tax_row[0]
	tax_buttons = tax_row[1]
	markup_value = _treasury_row(column,"Storehouse markup","Households pay this above the chain price when they buy from a storehouse; producers sell direct at the chain price",[],Callable())[0]
	column.add_child(HSeparator.new())
	treasury_ledger = RichTextLabel.new()
	treasury_ledger.bbcode_enabled = true
	treasury_ledger.fit_content = true
	treasury_ledger.scroll_active = false
	treasury_ledger.custom_minimum_size = Vector2(330,0)
	treasury_ledger.add_theme_font_size_override("normal_font_size",14)
	treasury_ledger.add_theme_font_size_override("bold_font_size",14)
	treasury_ledger.add_theme_color_override("default_color",Color("e4dfd2"))
	treasury_ledger.tooltip_text = "Frustration counts unpaid worker-paydays. Unpaid public workers keep working;\nthe count will feed the trade union's contentedness once factions exist."
	column.add_child(treasury_ledger)

## One labelled value with optional step buttons: [[text, amount], ...].
## Returns [value label, {amount: button}].
func _treasury_row(parent: Control, title: String, tooltip: String, steps: Array, action: Callable) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	row.tooltip_text = tooltip
	parent.add_child(row)
	var name_label := _label(title,15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.tooltip_text = tooltip
	row.add_child(name_label)
	var value := _label("",15)
	value.custom_minimum_size = Vector2(70,0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	var buttons := {}
	for step in steps:
		var button := _button(step[0])
		button.add_theme_font_size_override("font_size",13)
		button.custom_minimum_size = Vector2(52,0)
		button.pressed.connect(func(): action.call(step[1]))
		buttons[step[1]] = button
		row.add_child(button)
	if steps.is_empty():
		# Keep values in one column with the rows that have two step buttons.
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(52*2+6,0)
		row.add_child(spacer)
	return [value,buttons]

func _toggle_treasury_menu() -> void:
	treasury_menu.visible = not treasury_menu.visible
	treasury_button.button_pressed = treasury_menu.visible
	if treasury_menu.visible:
		close_options_menu()
		close_build_menu()
		close_weather_menu()
		if shown_sim != null: _refresh_treasury(shown_sim)
	_layout()

func close_treasury_menu() -> void:
	treasury_menu.visible = false
	treasury_button.button_pressed = false

func _refresh_treasury(sim) -> void:
	shown_sim = sim
	treasury_button.text = Economy.format(sim.treasury)
	if not treasury_menu.visible:
		return
	shown_tax = sim.tax_percent
	var free: int = Economy.free_gold(sim)
	treasury_total.text = Economy.format(sim.treasury)
	treasury_values.free.text = Economy.format(free)
	treasury_values.public.text = Economy.format(sim.public_reserve)
	treasury_values.capital.text = Economy.format(sim.capital_reserve)
	for pot in reserve_buttons:
		reserve_buttons[pot][-Economy.SILVER_PER_GOLD].disabled = int(sim.get(pot + "_reserve")) == 0
		reserve_buttons[pot][Economy.SILVER_PER_GOLD].disabled = free == 0
	tax_value.text = "%d%%" % sim.tax_percent
	tax_buttons[-Economy.TAX_STEP].disabled = sim.tax_percent <= 0
	tax_buttons[Economy.TAX_STEP].disabled = sim.tax_percent >= Economy.MAX_TAX_PERCENT
	markup_value.text = "%d%%" % sim.markup_percent
	var text := _treasury_ledger_text(sim)
	if treasury_ledger.text != text:
		treasury_ledger.text = text
		_layout()

func _treasury_ledger_text(sim) -> String:
	var text := _services_text(sim)
	if sim.ledger.is_empty():
		text += "[color=#868f7a]Payday every %.0f s: tax and storehouse surpluses come in, public workers are paid.[/color]\n" % (float(sim.PAYDAY_TICKS)/10.0)
	else:
		# Tax is always listed; other lines only when they moved gold.
		var last: Dictionary = sim.ledger[-1]
		text += "[b]Last payday[/b]\n[table=2]"
		for entry in [["Tax on wages","tax",1],["Storehouse surplus","trade",1],["Demolition refunds","refunds",1],["Public workers","public_pay",-1],["Construction","construction",-1]]:
			if entry[1] == "tax" or int(last[entry[1]]) != 0:
				text += "[cell][color=#a9b39a]%s[/color]  [/cell][cell]%s[/cell]" % [entry[0],_signed_silver(int(last[entry[1]])*entry[2])]
		text += "[/table]\n"
		if int(last.unpaid) > 0:
			text += "[color=#d98c6f]Public workers went unpaid %s[/color]\n" % Economy.format(int(last.unpaid))
		var nets: Array[String] = []
		for index in range(sim.ledger.size()-1,-1,-1):
			var entry: Dictionary = sim.ledger[index]
			nets.append(_signed_silver(int(entry.tax) + int(entry.trade) + int(entry.refunds) - int(entry.public_pay) - int(entry.construction)))
		text += "\n[b]Net per payday[/b]  [color=#868f7a]newest first[/color]\n%s\n" % "  ·  ".join(nets)
	if int(sim.period.construction) > 0:
		text += "[b]Since last payday[/b]  construction %s\n" % _signed_silver(-int(sim.period.construction))
	text += "[b]Public workers' frustration[/b]  " + ("%d" % sim.public_frustration if sim.public_frustration == 0 else "[color=#d98c6f]%d[/color]" % sim.public_frustration)
	return text

## Public services the treasury runs, grouped by building type: how many, what
## they cost per payday, and what went unpaid at the last payday.
func _services_text(sim) -> String:
	var groups: Dictionary = {}
	var total := 0
	for building in sim.buildings.values():
		var row: Dictionary = building.definition
		if not Economy.is_public(row):
			continue
		var group: Dictionary = groups.get(row.id,{"name":row.name,"count":0,"idle":0,"due":0,"unpaid":0})
		group.count += 1
		if building.staffed:
			group.due += Economy.upkeep(row)
			if sim.tick >= sim.PAYDAY_TICKS:
				group.unpaid += maxi(0,Economy.upkeep(row) - building.last_wage)
		else:
			group.idle += 1
		groups[row.id] = group
		total += Economy.upkeep(row) if building.staffed else 0
	if groups.is_empty():
		return "[b]Services[/b]  [color=#868f7a]none yet; a forester is the first[/color]\n\n"
	var text := "[b]Services[/b]  %s per payday\n" % Economy.format(total)
	for id in groups:
		var group: Dictionary = groups[id]
		text += "[color=#a9b39a]%s ×%d[/color]  %s" % [group.name,group.count,Economy.format(group.due)]
		if group.idle > 0:
			text += "  ·  %d without workers" % group.idle
		if group.unpaid > 0:
			text += "  ·  [color=#d98c6f]%s unpaid[/color]" % Economy.format(group.unpaid)
		text += "\n"
	return text + "\n"

func _signed_silver(amount: int) -> String:
	if amount == 0:
		return "[color=#868f7a]0 s[/color]"
	return "[color=#%s]%s%s[/color]" % ["a8c38a" if amount > 0 else "d98c6f","+" if amount > 0 else "",Economy.format(amount)]

func _build_weather_menu() -> void:
	weather_menu = _panel()
	weather_menu.visible = false
	root.add_child(weather_menu)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation",8)
	weather_menu.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := _label("Weather",20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	close_weather_button = _button("×")
	close_weather_button.tooltip_text = "Close weather"
	close_weather_button.pressed.connect(close_weather_menu)
	header.add_child(close_weather_button)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",14)
	outer.add_child(columns)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	column.custom_minimum_size = Vector2(300,0)
	columns.add_child(column)
	columns.add_child(VSeparator.new())
	# Live readout of what the atmosphere is actually doing, mid-fade included.
	# Two sub-columns keep the panel short enough to clear the bottom bar.
	for i in 2:
		var stats := RichTextLabel.new()
		stats.bbcode_enabled = true
		stats.fit_content = true
		stats.scroll_active = false
		stats.custom_minimum_size = Vector2(200,0)
		stats.add_theme_font_size_override("normal_font_size",13)
		stats.add_theme_font_size_override("bold_font_size",13)
		stats.add_theme_color_override("default_color",Color("e4dfd2"))
		weather_stats.append(stats)
		columns.add_child(stats)
	var kinds := GridContainer.new()
	kinds.columns = 3
	kinds.add_theme_constant_override("h_separation",8)
	kinds.add_theme_constant_override("v_separation",8)
	column.add_child(kinds)
	for kind in AtmosphereProfile.Weather.values():
		var button := _button(AtmosphereSystem.weather_name(kind).capitalize())
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): _choose_weather(kind))
		weather_buttons[kind] = button
		kinds.add_child(button)
	intensity_slider = _slider_row(column,"Intensity",0.0,1.0,0.05)
	intensity_slider.value = 0.8
	intensity_slider.value_changed.connect(func(_value): _emit_weather())
	fade_slider = _slider_row(column,"Fade",0.0,30.0,0.5)
	fade_slider.tooltip_text = "Seconds to fade from one weather to the next"
	fade_slider.value_changed.connect(func(value): fade_selected.emit(value))
	column.add_child(HSeparator.new())
	# Stops short of 24: the atmosphere wraps 24 to 0, which would snap the slider back mid-drag.
	time_slider = _slider_row(column,"Time",0.0,23.75,0.25)
	time_slider.value_changed.connect(func(value): time_of_day_selected.emit(value))
	clock_button = CheckButton.new()
	clock_button.text = "Run clock"
	clock_button.focus_mode = Control.FOCUS_NONE
	clock_button.tooltip_text = "Let the day pass (two-minute days)"
	clock_button.toggled.connect(func(running): clock_toggled.emit(running))
	column.add_child(clock_button)
	column.add_child(HSeparator.new())
	wind_from_slider = _slider_row(column,"Wind from",0.0,355.0,5.0)
	wind_from_slider.tooltip_text = "Compass bearing the wind blows from"
	breeze_slider = _slider_row(column,"Breeze",0.0,3.0,0.1)
	breeze_slider.tooltip_text = "How far gusts bend foliage, against the authored breeze"
	gust_speed_slider = _slider_row(column,"Gust speed",0.0,3.0,0.1)
	gust_speed_slider.tooltip_text = "How fast gust fronts travel, against the authored breeze"
	for slider in [wind_from_slider,breeze_slider,gust_speed_slider]:
		slider.value_changed.connect(func(_value): wind_selected.emit(wind_from_slider.value,breeze_slider.value,gust_speed_slider.value))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",8)
	column.add_child(actions)
	for entry in [["strike","Lightning","A bolt now, whatever the weather"],["soak","Soak","Ground fully wet"],["dry","Dry","Ground bone dry"]]:
		var button := _button(entry[1])
		button.tooltip_text = entry[2]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): weather_action.emit(entry[0]))
		weather_action_buttons[entry[0]] = button
		actions.add_child(button)
	_show_weather_kind(weather_kind)
	_refresh_slider_values()

## One compact row: title, slider, live value. The value text comes from
## _refresh_slider_values(), so every way a slider moves updates it.
func _slider_row(parent: Control, title: String, min_value: float, max_value: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	var name_label := _label(title,14)
	name_label.custom_minimum_size = Vector2(84,0)
	row.add_child(name_label)
	var slider := _slider(min_value,max_value,step)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := _label("",14)
	value_label.custom_minimum_size = Vector2(70,0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider_values[slider] = value_label
	slider.value_changed.connect(func(_value): _refresh_slider_values())
	return slider

func _refresh_slider_values() -> void:
	if gust_speed_slider == null:
		return # Still building the panel.
	slider_values[intensity_slider].text = "%d%%" % roundi(intensity_slider.value*100.0)
	slider_values[fade_slider].text = "%.1f s" % fade_slider.value
	slider_values[time_slider].text = _clock_text(time_slider.value)
	slider_values[wind_from_slider].text = "%s %d°" % [VillageAtmosphere.compass_name(wind_from_slider.value),roundi(wind_from_slider.value)]
	slider_values[breeze_slider].text = "%.1f×" % breeze_slider.value
	slider_values[gust_speed_slider].text = "%.1f×" % gust_speed_slider.value

## Mirrors the wind controls without emitting (restart, debug keys).
func set_wind(from_degrees: float, breeze: float, gust_speed: float, fade_seconds: float) -> void:
	wind_from_slider.set_value_no_signal(from_degrees)
	breeze_slider.set_value_no_signal(breeze)
	gust_speed_slider.set_value_no_signal(gust_speed)
	fade_slider.set_value_no_signal(fade_seconds)
	_refresh_slider_values()

## `sections`: [[title, [[label, value], ...]], ...] from VillageAtmosphere.weather_report().
## The first half of the sections fills the left sub-column. Each sub-column
## is one table, so its values line up across sections.
func set_weather_stats(sections: Array) -> void:
	var split := ceili(sections.size()/2.0)
	for i in weather_stats.size():
		var text := "[table=2]"
		for section in sections.slice(i*split,(i+1)*split):
			text += "[cell][color=#d6c288][b]%s[/b][/color][/cell][cell][/cell]" % section[0]
			for row in section[1]:
				text += "[cell][color=#a9b39a]%s[/color]  [/cell][cell]%s[/cell]" % [row[0],row[1]]
		weather_stats[i].text = text + "[/table]"

func weather_stats_text() -> String:
	return "\n".join(weather_stats.map(func(stats): return stats.get_parsed_text()))

func _choose_weather(kind: AtmosphereProfile.Weather) -> void:
	_show_weather_kind(kind)
	_emit_weather()

func _emit_weather() -> void:
	weather_selected.emit(weather_kind,intensity_slider.value)

func _show_weather_kind(kind: AtmosphereProfile.Weather) -> void:
	weather_kind = kind
	for value in weather_buttons:
		weather_buttons[value].set_pressed_no_signal(value == kind)
	intensity_slider.editable = kind != AtmosphereProfile.Weather.CLEAR
	intensity_slider.modulate.a = 1.0 if intensity_slider.editable else 0.4

## Mirrors the atmosphere into the panel without emitting, so debug keys and a
## running clock keep the controls honest.
func set_weather(kind: AtmosphereProfile.Weather, intensity: float) -> void:
	_show_weather_kind(kind)
	if kind != AtmosphereProfile.Weather.CLEAR:
		intensity_slider.set_value_no_signal(intensity)
	_refresh_slider_values()

func set_time_of_day(hour: float, running: bool) -> void:
	time_slider.set_value_no_signal(hour)
	clock_button.set_pressed_no_signal(running)
	_refresh_slider_values()

func _clock_text(hour: float) -> String:
	var minutes := int(round(hour*60.0)) % (24*60)
	return "%02d:%02d" % [minutes/60,minutes%60]

func _toggle_weather_menu() -> void:
	weather_menu.visible = not weather_menu.visible
	sun_button.button_pressed = weather_menu.visible
	if weather_menu.visible:
		close_options_menu()
		close_build_menu()
		close_treasury_menu()
	_layout()

func close_weather_menu() -> void:
	weather_menu.visible = false
	sun_button.button_pressed = false

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
	close_options_menu()
	close_weather_menu()
	close_treasury_menu()
	build_menu.visible = not build_menu.visible
	build_button.button_pressed = build_menu.visible
	if build_menu.visible:
		show_build_categories()
		tool_selected.emit("inspect")
	_layout()

func close_build_menu() -> void:
	build_menu.visible = false
	build_button.button_pressed = false

func _toggle_options_menu() -> void:
	options_menu.visible = not options_menu.visible
	cog_button.button_pressed = options_menu.visible
	if options_menu.visible:
		close_build_menu()
		close_weather_menu()
		close_treasury_menu()
		inspection_closed.emit()
		tool_selected.emit("inspect")
	_layout()

func close_options_menu() -> void:
	options_menu.visible = false
	cog_button.button_pressed = false

func set_speed(value: int) -> void:
	for speed_value in speed_buttons:
		speed_buttons[speed_value].set_pressed_no_signal(speed_value == value)

func reset() -> void:
	close_build_menu()
	close_options_menu()
	close_weather_menu()
	close_treasury_menu()
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
	style.bg_color = Color(0.105,0.14,0.11,0.96)
	style.border_color = Color("5d7946")
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
	side.size = Vector2(330,420).max(side.get_combined_minimum_size())
	side.position = Vector2(screen.x-side.size.x-18,78)
	cog_button.size = Vector2(48,48)
	cog_button.position = Vector2(screen.x-66,18)
	sun_button.size = Vector2(48,48)
	sun_button.position = Vector2(screen.x-122,18)
	map_button.size = Vector2(48,48)
	map_button.position = Vector2(screen.x-178,18)
	weather_menu.size = Vector2(300,0).max(weather_menu.get_combined_minimum_size())
	weather_menu.position = Vector2(screen.x-weather_menu.size.x-18,78)
	options_menu.size = Vector2(300,0).max(options_menu.get_combined_minimum_size())
	options_menu.position = Vector2(screen.x-options_menu.size.x-18,78)
	treasury_button.reset_size()
	treasury_button.position = Vector2(18,18)
	# The gold counter's width follows the amount, so the bar follows its edge.
	stock_bar.reset_size()
	stock_bar.size.y = treasury_button.size.y
	stock_bar.position = Vector2(treasury_button.get_rect().end.x + 10, 18)
	treasury_menu.reset_size()
	treasury_menu.position = Vector2(18,78)
	toast.reset_size()
	toast.position = Vector2((screen.x-toast.size.x)/2.0,20).floor()

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	return label

func _icon_button(svg_path: String, tooltip: String) -> Button:
	var button := _button("")
	button.custom_minimum_size = Vector2(48,48)
	button.toggle_mode = true
	button.tooltip_text = tooltip
	var image := Image.new()
	image.load_svg_from_string(FileAccess.get_file_as_string(svg_path))
	button.icon = ImageTexture.create_from_image(image)
	button.expand_icon = true
	return button

func _slider(min_value: float, max_value: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0,24)
	return slider

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

func _refresh_stock_bar(sim) -> void:
	var held := 0
	var capacity := 0
	for building in sim.buildings.values():
		if building.definition.kind == "storehouse":
			held += building.inventory.total()
			capacity += building.inventory.capacity
	var fill := "Storehouse %d / %d" % [held, capacity] if capacity > 0 else "No storehouse"
	var text := "%s    Bread %d    Water %d    Logs %d" % [fill, sim.stock("bread"), sim.stock("water"), sim.stock("logs")]
	# Re-lay out when either the bar or the gold counter beside it changes width.
	if stock_label.text != text or stock_bar_gold != treasury_button.text:
		stock_label.text = text
		stock_bar_gold = treasury_button.text
		_layout()

func blocks_mouse(point: Vector2) -> bool:
	if run_card.visible: return true
	if options_menu.visible:
		return true
	for button in [cog_button,sun_button,map_button,treasury_button]:
		if button.get_global_rect().has_point(point):
			return true
	for panel in [bottom,build_menu,placement_card,side,toast,weather_menu,treasury_menu,stock_bar]:
		if panel.visible and panel.get_global_rect().has_point(point):
			return true
	return false

func refresh(sim, selected_id: int, tool: String, rotation_quarters: int = 0) -> void:
	_refresh_treasury(sim)
	_refresh_stock_bar(sim)
	demolish_button.button_pressed = tool == "demolish"
	demolish_button.modulate = Color("d6c288") if tool == "demolish" else Color.WHITE
	for id in build_buttons:
		var button: Button = build_buttons[id]
		var row: Dictionary = sim.db.buildings[id]
		var detail: Label = build_details[id]
		button.modulate = Color("d6c288") if tool == id else Color.WHITE
		button.disabled = int(row.unlock_tier) > sim.unlocked_tier
		if button.disabled:
			detail.text = "Needs " + sim.db.tiers[int(row.unlock_tier)].name
			detail.add_theme_color_override("font_color",Color("868f7a"))
		else:
			detail.text = _cost_text(row.cost,sim.db)
			detail.add_theme_color_override("font_color",Color("d6c288") if _affordable(sim,row.cost) else Color("d98c6f"))
		button.tooltip_text = _requirements_summary(row,sim.db)
	for good in supply_labels:
		supply_labels[good].text = str(sim.stock(good))
	placement_card.visible = sim.db.buildings.has(tool) and not build_menu.visible
	if placement_card.visible:
		_refresh_placement(sim,sim.db.buildings[tool],rotation_quarters)
	var selected = sim.buildings.get(selected_id)
	side.visible = selected != null and tool == "inspect"
	if side.visible:
		_refresh_inspection(sim,selected)

func _refresh_inspection(sim, building) -> void:
	var row: Dictionary = building.definition
	inspector_title.text = row.name
	var text := "[color=#d6c288]%s[/color]\n\n" % building.status.capitalize()
	var footprint: Vector2i = building.footprint()
	text += "[b]Footprint[/b]  %d × %d  ·  (%d, %d)\n" % [footprint.x,footprint.y,building.cell.x,building.cell.y]
	text += "[b]Facing[/b]  %d°\n" % (building.rotation_quarters * 90)
	var store = sim.nearest_store(building)
	text += "[b]Roads[/b]  " + ("Connected" if store != null else "No reachable storehouse") + "\n"
	inspection_progress.visible = false
	workers_button.visible = int(row.workers) > 0
	workers_button.text = "Stop workers" if building.workers_enabled else "Resume workers"
	match row.kind:
		"producer":
			var assigned := int(row.workers) if building.staffed else 0
			text += "[b]Workers[/b]  %d / %d%s  ·  %d idle in village\n" % [assigned,int(row.workers),"" if building.workers_enabled else " (stopped)",sim.idle_workers]
			var morale: int = Needs.morale(sim)
			if Needs.work_speed(morale) < 100:
				text += "[b]Speed[/b]  [color=#d98c6f]%d%%[/color]  ·  village morale %d%%\n" % [Needs.work_speed(morale),morale]
			if row.has("forest_action"):
				text += "[b]Work area[/b]  Up to %d tiles over reachable land\n" % int(row.work_radius)
				text += "Mature tree → 1 log; leaves a stump\n" if row.forest_action == "cut" else "Plants saplings; trees mature in 60 s\nKeeps the village clearing open\n"
				if building.work_cell.x >= 0:
					text += "[b]Working at[/b]  (%d, %d)\n" % [building.work_cell.x,building.work_cell.y]
			else:
				text += "[b]Recipe[/b]\n%s → %s\n" % [_goods(row.inputs,sim.db),_goods(row.outputs,sim.db)]
				text += "[b]Input[/b]  %d / %d\n%s\n" % [building.input.total(),building.input.capacity,_slot_goods(building.input,row.inputs,sim.db)]
			if not row.outputs.is_empty():
				text += "[b]Output[/b]  %d / %d\n%s\n" % [building.output.total(),building.output.capacity,_slot_goods(building.output,row.outputs,sim.db)]
				for good in row.outputs:
					text += "[b]Sells[/b]  %s for %s  ·  %s of it wages\n" % [sim.db.goods[good].name,Economy.format(sim.price(good)),Economy.format(int(sim.economy.labour[good]))]
				if not row.inputs.is_empty():
					text += "[b]Purse[/b]  %s for buying inputs\n" % Economy.format(building.silver)
			elif Economy.is_public(row):
				var due := Economy.upkeep(row)
				text += "[b]Public service[/b]  the treasury pays %s per payday\n" % Economy.format(due)
				if building.staffed and sim.tick >= sim.PAYDAY_TICKS:
					text += "[b]Last payday[/b]  %s\n" % (Economy.format(building.last_wage) if building.last_wage >= due else "[color=#d98c6f]%s of %s: working unpaid[/color]" % [Economy.format(building.last_wage),Economy.format(due)])
				if building.frustration > 0:
					text += "[b]Frustration[/b]  [color=#d98c6f]%d unpaid worker-paydays[/color]\n" % building.frustration
			text += "[b]Cycle[/b]  %.1f / %.1f s" % [building.progress/10.0,float(row.cycle_ticks)/10.0]
			inspection_progress.visible = true
			inspection_progress.max_value = float(row.cycle_ticks)
			inspection_progress.value = building.progress
		"house":
			var tier: Dictionary = sim.db.tiers[building.tier]
			text += "[b]Tier %d[/b]  %s\n[b]Workers provided[/b]  %d\n\n" % [building.tier,tier.name,int(tier.workers_per_house)]
			text += "[b]Happiness[/b]  %d%%  ·  %d of %d needs met this cycle\n" % [building.happiness,building.needs_met.size(),tier.consumption.size()]
			var settled: int = Needs.settled(building)
			text += "[b]Settled[/b]  %s\n\n" % ("after the first full cycle" if settled < 0 else "%d%%  ·  last %d cycles" % [settled,building.happiness_history.size()])
			text += "[b]Needs[/b]  every %.0f s\n%s\n" % [float(tier.consume_every_ticks)/10.0,_needs_text(building,tier.consumption,sim)]
			text += "[b]Pantry[/b]  %d / %d\n%s\n" % [building.input.total(),building.input.capacity,_goods(building.input.items,sim.db)]
			text += "[b]Savings[/b]  %s\n[b]Wages[/b]  %s last payday, %s of it taxed  ·  paid every %.0f s\n\n" % [Economy.format(building.silver),Economy.format(building.last_wage),Economy.format(building.last_tax),float(sim.PAYDAY_TICKS)/10.0]
			if building.needs_ok:
				text += "[b]Next consumption[/b]  %.1f s\n" % [maxi(0,building.needs_next_tick-sim.tick)/10.0]
			if sim.db.tiers.has(building.tier+1):
				text += "[b]Upgrade[/b]  %.1f / %.0f s satisfied" % [building.satisfied_ticks/10.0,float(tier.upgrade_after_ticks)/10.0]
				inspection_progress.visible = true
				inspection_progress.max_value = float(tier.upgrade_after_ticks)
				inspection_progress.value = building.satisfied_ticks
			elif building.tier > 1 and Needs.unhappy(sim,building):
				text += "[b]Downgrade in[/b]  [color=#d98c6f]%.1f s[/color]  ·  settled below %d%%" % [maxi(0,int(tier.downgrade_after_ticks)-building.unsatisfied_ticks)/10.0,int(tier.downgrade_below_happiness)]
			elif not building.needs_ok:
				text += "[b]Demotes[/b]  if settled happiness stays below %d%%" % int(tier.downgrade_below_happiness)
			else:
				text += "[b]Needs satisfied[/b]  %.1f s" % [building.satisfied_ticks/10.0]
		"storehouse":
			var total := 0
			var active := 0
			var carrying := 0
			for carrier in sim.carriers:
				if carrier.owner == building.uid:
					total += 1
					if carrier.stage != "idle": active += 1
					if not carrier.cargo.is_empty(): carrying += 1
			# Carriers are jobs, staffed from the village's idle workers.
			text += "\n[b]Carriers[/b]  %d active  ·  %d of %d on shift%s\n[b]Carrying goods[/b]  %d\n" % [active,building.crew,total,"" if building.crew >= total else " [color=#d98c6f](short of workers)[/color]",carrying]
			text += "[b]Carriers' wages[/b]  %s so far, from the markup\n\n" % Economy.format(building.wages_paid)
			text += "[b]Storage[/b]  %d / %d\n%s\n\n" % [building.inventory.total(),building.inventory.capacity,_goods(building.inventory.items,sim.db)]
			text += "[b]Trading purse[/b]  %s  ·  keeps up to %s\n" % [Economy.format(building.silver),Economy.format(sim.economy.purse_cap(sim,building))]
			text += "[b]Sells to households[/b]  at +%d%%; buys at the chain price\n" % sim.markup_percent
			text += "[b]Village treasury[/b]  %s  ·  tax %d%% of wages" % [Economy.format(sim.treasury),sim.tax_percent]
	inspector.text = text

func _goods(items: Dictionary, db) -> String:
	if items.is_empty():
		return "None"
	var parts: Array[String] = []
	for good in items:
		parts.append("%d %s" % [int(items[good]),db.goods[good].name])
	return ", ".join(parts)

func _needs_text(house, consumption: Dictionary, sim) -> String:
	var parts: Array[String] = []
	for good in consumption:
		var colour := "a8c38a" if house.needs_met.has(good) else "d98c6f"
		# Direct from the producer at the chain price, or from a storehouse with its markup.
		var retail: int = sim.economy.retail_price(sim,good)
		var price_text := Economy.format(sim.price(good)) if retail == sim.price(good) else "%s, %s stored" % [Economy.format(sim.price(good)),Economy.format(retail)]
		parts.append("[color=#%s]%d %s (%s)[/color]" % [colour,int(consumption[good]),sim.db.goods[good].name,price_text])
	return ", ".join(parts)

func _slot_goods(storage, recipe: Dictionary, db) -> String:
	var amounts: Dictionary = {}
	for good in recipe:
		amounts[good] = storage.count(good)
	return _goods(amounts,db)

func _refresh_placement(sim, row: Dictionary, rotation_quarters: int = 0) -> void:
	placement_title.text = row.name
	var cost_parts: Array[String] = []
	for good in row.cost:
		var need := int(row.cost[good])
		var have: int = sim.stock(good)
		cost_parts.append("[color=#%s]%d %s[/color] [color=#868f7a](have %d)[/color]" % ["e4dfd2" if have >= need else "d98c6f",need,sim.db.goods[good].name,have])
	var lines: Array[String] = ["[b]Cost[/b]  " + ("Free" if cost_parts.is_empty() else ", ".join(cost_parts))]
	var gold_cost: int = sim.economy.construction_price(sim,row)
	if gold_cost > 0:
		# Construction draws on the capital reserve, then free gold; never on public pay.
		var funds: int = Economy.construction_funds(sim)
		lines.append("[b]Treasury pays[/b]  [color=#%s]%s[/color] [color=#868f7a](have %s%s)[/color]" % ["e4dfd2" if funds >= gold_cost else "d98c6f",Economy.format(gold_cost),Economy.format(funds),
			"" if sim.public_reserve == 0 else " outside public pay"])
	if int(row.workers) > 0:
		lines.append("[b]Workers[/b]  %d" % int(row.workers))
	if Economy.is_public(row):
		lines.append("[b]Public service[/b]  upkeep %s per payday from the treasury" % Economy.format(Economy.upkeep(row)))
	match row.kind:
		"producer":
			if row.has("forest_action"):
				lines.append("[b]Work area[/b]  %d tiles over reachable land" % int(row.work_radius))
			if not row.inputs.is_empty():
				lines.append("[b]Uses[/b]  " + _goods(row.inputs,sim.db))
			if row.get("forest_action","") == "plant":
				lines.append("[b]Plants[/b]  A sapling every %.1f s\nMatures in 60 s; preserves the central clearing" % (float(row.cycle_ticks)/10.0))
			else:
				lines.append("[b]Makes[/b]  %s every %.1f s" % [_goods(row.outputs,sim.db),float(row.cycle_ticks)/10.0])
				if row.get("forest_action","") == "cut": lines.append("Harvests nearby mature trees")
		"storehouse":
			lines.append("[b]Storage[/b]  %d  ·  %d carriers" % [int(row.storage_capacity),int(row.carriers)])
		"house":
			var tier: Dictionary = sim.db.tiers[1]
			lines.append("[b]Houses[/b]  %s  ·  %d workers" % [tier.name,int(tier.workers_per_house)])
	if row.kind != "road":
		var footprint := Building.rotated_footprint(row, rotation_quarters)
		lines.append("[b]Size[/b]  %d × %d  ·  [b]Facing[/b]  %d°" % [footprint.x,footprint.y,rotation_quarters*90])
	rotate_button.visible = row.kind != "road"
	lines.append("[color=#868f7a]%s\nRight-click to cancel[/color]" %("Click two tiles to lay a road" if row.kind == "road" else "Place beside a road"))
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
		if row.get("forest_action","") == "plant":
			parts.append("Plants trees in a %d tile work area" % int(row.work_radius))
		else:
			parts.append(("Makes " if row.inputs.is_empty() else _goods(row.inputs,db) + " → ") + _goods(row.outputs,db))
	return "\n".join(parts)

func _cost_text(cost: Dictionary, db) -> String:
	return "Free" if cost.is_empty() else _goods(cost,db)

func _affordable(sim, cost: Dictionary) -> bool:
	for good in cost:
		if sim.stock(good) < int(cost[good]):
			return false
	return true
