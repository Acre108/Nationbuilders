extends CanvasLayer
const ContentDB = preload("res://sim/content_db.gd")
const Building = preload("res://sim/building.gd")
const Economy = preload("res://sim/economy.gd")
const Needs = preload("res://sim/needs.gd")
const Forestry = preload("res://sim/forestry.gd")
const FoodReport = preload("res://sim/food_report.gd")
## The food overlay's key (view/food_overlay.gd, docs/WILDLIFE.md).
const FOOD_LEGEND := "[b]Food[/b]  [color=#868f7a]F7[/color]
[color=#f2c75a]■[/color] Fertile soil
[color=#dc3a55]■[/color] Wild berries
[color=#56a3e0]■[/color] Fishing shore
[color=#f3e6c4]■[/color] Deer and boar"
const FOOD_LEGEND_TIP := "Fields work at full speed on fertile soil, half speed elsewhere.\nLarger berry marks hold more ripe fruit.\nA fisher's hut stands beside the fishing shore.\nLabels count the deer and boar in each range.\nFelling woods loses their game and berries."
const OPERATIONS_LEGEND := "[b]Operations[/b]  [color=#868f7a]F6[/color]
[color=#d9534f]■[/color] Not working
[color=#e8c547]■[/color] Below full capacity
[color=#6fbf5a]■[/color] Could run at full capacity
[color=#4f8fd6]■[/color] At full capacity"
const OPERATIONS_LEGEND_TIP := "Red: no workers, stopped, no road, or blocked (missing inputs, storage full, nothing nearby to work).
Yellow: slowed by low morale or poor soil, or a storehouse short of carriers.
Green: able to run at full capacity, but a workshop lacks its next inputs or a storehouse has idle carriers.
Blue: working at full capacity.
Houses: red below the happiness that demotes them, yellow with a need unmet, green with every need met.
Roads and halls are not shown."
## Operations overlay colours by sim.operation() state.
const OPERATION_COLOURS := {"down": "d9534f", "limited": "e8c547", "ready": "6fbf5a", "full": "4f8fd6"}
const CLASS_LEGEND_TIP := "Houses are coloured by the faction they joined.\nTinted roads are within a hall's or alehouse's reach.\nSettlers have no class."
signal tool_selected(id: String)
signal rotation_requested
signal deposits_toggled
signal inspection_closed
signal workers_toggled
## Clear the selected construction site (VillageSim.demolish).
signal site_cancel_requested
## Pay for the selected workplace (Building.LOW, NORMAL or HIGH; economy.gd).
signal pay_selected(level: int)
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
signal reserve_target_toggled(enabled: bool)
signal reserve_transfer_requested(pot: String, amount: int)
signal offer_accepted(faction: String)
signal offer_declined(faction: String)
signal pledge_broken(pledge: String)
signal sale_requested(faction: String)
signal class_overlay_toggled
signal food_overlay_toggled
signal operations_overlay_toggled
## The food balance button opened its breakdown; the view shows the overlay.
signal food_menu_opened
## Gold counter (top left), the one global counter on the play screen. It
## opens the Treasury panel: reserves, tax and the payday ledger.
var treasury_button: Button
## Beside the gold counter: stocks by kind (food, water, fuel, materials,
## ingredients) and storehouse fill, each broken down by good on hover. The
## food chip is the food balance button.
var stock_bar: PanelContainer
var resource_chips: Dictionary = {}
## [[id, name, icon path, goods], ...] from content, built on first refresh.
var resource_groups: Array = []
var resource_db
const RESOURCE_GROUPS := [["food","Food","res://view/overlays/food.svg"],["water","Water","res://view/overlays/water.svg"],
	["fuel","Fuel","res://view/overlays/fuel.svg"],["materials","Materials","res://view/overlays/goods/logs.svg"],
	["ingredients","Ingredients","res://view/overlays/ingredients.svg"]]
var treasury_menu: PanelContainer
var close_treasury_button: Button
var treasury_values: Dictionary = {}
var reserve_buttons: Dictionary = {}
var keep_reserve_button: CheckButton
## The reserves are folded away under this toggle; "keep services reserved"
## tends them by default.
var reserves_button: Button
var reserves_box: VBoxContainer
var tax_value: Label
var tax_buttons: Dictionary = {}
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
## The inspector leads with what the player acts on: whether the building
## works, and why not. The rest waits under Details.
var inspector_scroll: ScrollContainer
var inspector: RichTextLabel
var inspector_title: Label
var close_inspector: Button
var inspection_progress: ProgressBar
var workers_button: Button
var details_button: Button
var cancel_site_button: Button
## Interface sounds (ui_sounds.gd), set by the view; null in bare HUD tests.
var sounds
## The gold counter counts up to a payday's takings rather than jumping.
const GOLD_COUNT_SECONDS := 0.8
var shown_gold := -1.0
var gold_from := 0.0
var gold_target := 0
var gold_count_left := 0.0
## The payday last seen, and the treasury at the last refresh, to measure
## what a payday brought in.
var shown_payday := -1
var seen_treasury := 0
var details_text: RichTextLabel
## Pay for the selected workplace (or a storehouse's carriers): 0 low, 1
## normal, 2 high; the hint says what the level costs.
var pay_row: HBoxContainer
var pay_buttons: Dictionary = {}
var pay_hint: Label
var build_buttons: Dictionary = {}
var demolish_button: Button
var build_button: Button
## The Overlays button and its menu: deposits, food and class.
var overlays_button: Button
var overlays_menu: PanelContainer
var deposits_button: CheckButton
## The weather panel is a developer tool: its sun button shows only with
## --dev or after F12.
var dev_tools := false
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
const Factions = preload("res://sim/factions.gd")
const Labour = preload("res://sim/labour.gd")
## The Factions button (top right, once a faction is present) and its panel.
var factions_button: Button
var factions_menu: PanelContainer
var factions_scroll: ScrollContainer
var close_factions_button: Button
var power_bar: HBoxContainer
var power_segments: Dictionary = {}
var faction_text: RichTextLabel
## Factions whose row is open in the Factions panel, by id.
var expanded_factions: Dictionary = {}
## Open offers: an alert per faction id on the left edge, and the card of the
## one opened (open_offer), whose Accept and Decline are offer_buttons[id].
var offer_alerts: VBoxContainer
var offer_alerts_by_id: Dictionary = {}
var offer_card: PanelContainer
var offer_title: Label
var offer_text: RichTextLabel
var offer_accept: Button
var offer_decline: Button
var open_offer := ""
var offer_buttons: Dictionary = {}
## Running pledges' Break buttons by pledge id; rebuilt when the pledges change.
var pledge_list: VBoxContainer
var pledge_buttons: Dictionary = {}
var deals_signature := ""
var lock_texture: Texture2D
var tax_lock: Label
var class_overlay_button: CheckButton
var operations_overlay_button: CheckButton
var operations_legend: PanelContainer
var class_legend: PanelContainer
var class_legend_text: RichTextLabel
var food_overlay_button: CheckButton
var food_legend: PanelContainer
## Food balance (sim/food_report.gd): the top-bar button, its breakdown
## panel, and the meter that samples what the village makes and eats.
var food_button: Button
var food_menu: PanelContainer
var food_text: RichTextLabel
var food_verdict: RichTextLabel
var food_bar: ProgressBar
var food_bar_fill: StyleBoxFlat
## Food in storehouses, shown on the food chip.
var food_total := 0
## Buildings placed this session: after a few, the placement card drops its hints.
var placements := 0
const HINT_PLACEMENTS := 3
var food_meter = FoodReport.new()
## The inspector's "Offer for sale" toggle and its bids, by faction id.
var sale_button: Button
var sale_list: VBoxContainer
var sale_buttons: Dictionary = {}
var sale_signature := ""
var sale_uid := -1
var shown_building
const BAND_NAMES := ["weak", "organised", "strong", "dominant"]
const TERM_NAMES := {"tax":"Tax", "markup":"Markup", "idle_workers":"Idle workers", "unpaid_public_workers":"Unpaid public workers", "rent":"Rent", "houses_sold":"Houses sold", "buildings_owned":"Property", "happiness":"Happiness", "woodland_lost":"Woodland lost", "strikes_riots":"Strikes and riots", "union_power":"Union power", "populist_power":"Populist power"}
const FLOW_NAMES := {"rent":"rent", "dues":"dues", "owner_share":"owner's share", "relief":"relief paid", "purchases":"goods bought"}
const CROWN_COLOUR := "d6c288"
const UNALIGNED_COLOUR := "8d957f"

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
	# Game speed is used constantly, so it lives here rather than in Options.
	for entry in [["pause",0,"Pause (Space)"],["1×",1,"Normal speed"],["3×",3,"Fast"]]:
		var button := _button("" if entry[0] == "pause" else entry[0])
		if entry[0] == "pause":
			button.icon = _svg_texture("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"16\"><rect x=\"1\" y=\"1\" width=\"4\" height=\"14\" rx=\"1\" fill=\"#e4dfd2\"/><rect x=\"9\" y=\"1\" width=\"4\" height=\"14\" rx=\"1\" fill=\"#e4dfd2\"/></svg>")
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(46,0)
		button.tooltip_text = entry[2]
		button.pressed.connect(func(): speed_selected.emit(entry[1]))
		speed_buttons[entry[1]] = button
		actions.add_child(button)
	actions.add_child(VSeparator.new())
	build_button = _button("Build")
	build_button.toggle_mode = true
	build_button.pressed.connect(_toggle_build_menu)
	actions.add_child(build_button)
	overlays_button = _button("Overlays")
	overlays_button.toggle_mode = true
	overlays_button.tooltip_text = "Deposits, food and classes on the map"
	overlays_button.pressed.connect(_toggle_overlays_menu)
	actions.add_child(overlays_button)
	demolish_button = _button("Demolish")
	demolish_button.toggle_mode = true
	demolish_button.tooltip_text = "Remove a building or road"
	demolish_button.pressed.connect(func(): tool_selected.emit("demolish" if demolish_button.button_pressed else "inspect"))
	actions.add_child(demolish_button)
	for button in [build_button,overlays_button,demolish_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_overlays_menu()
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
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation",8)
	side.add_child(outer)
	var inspection_header := HBoxContainer.new()
	outer.add_child(inspection_header)
	inspector_title = _label("",20)
	inspector_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspection_header.add_child(inspector_title)
	close_inspector = _button("×")
	close_inspector.tooltip_text = "Close inspection"
	close_inspector.pressed.connect(func(): inspection_closed.emit())
	inspection_header.add_child(close_inspector)
	# The panel grows with its text and scrolls only past the screen's height.
	inspector_scroll = ScrollContainer.new()
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(inspector_scroll)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation",10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(info)
	inspector = _rich_label(15)
	inspector.custom_minimum_size = Vector2(306,0)
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
	pay_row = HBoxContainer.new()
	pay_row.add_theme_constant_override("separation",6)
	info.add_child(pay_row)
	var pay_label := _label("Pay",15)
	pay_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pay_label.tooltip_text = "Workers take the best-paid jobs first"
	pay_label.mouse_filter = Control.MOUSE_FILTER_PASS
	pay_row.add_child(pay_label)
	for entry in [["Low",Building.LOW],["Normal",Building.NORMAL],["High",Building.HIGH]]:
		var button := _button(entry[0])
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",13)
		button.pressed.connect(func(): pay_selected.emit(entry[1]))
		pay_buttons[entry[1]] = button
		pay_row.add_child(button)
	pay_hint = _label("",13)
	pay_hint.add_theme_color_override("font_color",Color("868f7a"))
	pay_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pay_hint.custom_minimum_size = Vector2(306,0)
	info.add_child(pay_hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation",6)
	info.add_child(buttons)
	workers_button = _button("Stop workers")
	workers_button.tooltip_text = "Release this building's workers to other jobs"
	workers_button.add_theme_font_size_override("font_size",13)
	workers_button.pressed.connect(func(): workers_toggled.emit())
	buttons.add_child(workers_button)
	cancel_site_button = _button("Cancel")
	cancel_site_button.tooltip_text = "Clear the site: delivered materials go back to the storehouse and the unspent purse to the treasury"
	cancel_site_button.add_theme_font_size_override("font_size",13)
	cancel_site_button.pressed.connect(func(): site_cancel_requested.emit())
	buttons.add_child(cancel_site_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	details_button = _button("Details ▸")
	details_button.toggle_mode = true
	details_button.add_theme_font_size_override("font_size",13)
	details_button.tooltip_text = "Prices, wages, owner, families and position"
	details_button.toggled.connect(func(on):
		details_button.text = "Details ▾" if on else "Details ▸"
		details_text.visible = on
		if shown_sim != null and shown_building != null: _refresh_inspection(shown_sim, shown_building)
		_layout()
	)
	buttons.add_child(details_button)
	details_text = _rich_label(14)
	details_text.custom_minimum_size = Vector2(306,0)
	details_text.visible = false
	info.add_child(details_text)
	sale_button = _button("Offer for sale")
	sale_button.toggle_mode = true
	sale_button.tooltip_text = "See what the factions that buy this building would pay"
	sale_button.toggled.connect(func(_on):
		sale_signature = ""
		if shown_sim != null and shown_building != null: _refresh_sale(shown_sim, shown_building)
	)
	info.add_child(sale_button)
	sale_list = VBoxContainer.new()
	sale_list.add_theme_constant_override("separation",6)
	sale_list.visible = false
	info.add_child(sale_list)
	cog_button =_icon_button("res://view/overlays/cog.svg","Options")
	cog_button.pressed.connect(_toggle_options_menu)
	root.add_child(cog_button)
	sun_button = _icon_button("res://view/overlays/sun.svg","Weather (developer tool)")
	sun_button.pressed.connect(_toggle_weather_menu)
	sun_button.visible = dev_tools
	root.add_child(sun_button)
	map_button = _icon_button("res://view/overlays/map.svg","World map")
	map_button.toggle_mode = false
	map_button.pressed.connect(func(): world_map_requested.emit())
	root.add_child(map_button)
	_build_treasury_menu()
	_build_food_menu()
	_build_factions_menu()
	_build_resource_bar()
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

## Every map overlay in one menu above the bottom bar, each with its key.
func _build_overlays_menu() -> void:
	overlays_menu = _panel()
	overlays_menu.visible = false
	root.add_child(overlays_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",2)
	overlays_menu.add_child(column)
	deposits_button = _overlay_toggle(column,"Deposits  F3","Resource deposits on the site")
	deposits_button.toggled.connect(func(_on): deposits_toggled.emit())
	food_overlay_button = _overlay_toggle(column,"Food  F7","Fertile soil, wild berries, the fishing shore and game")
	food_overlay_button.toggled.connect(func(_on): food_overlay_toggled.emit())
	operations_overlay_button = _overlay_toggle(column,"Operations  F6","Which workplaces are working, and how fully")
	operations_overlay_button.toggled.connect(func(_on): operations_overlay_toggled.emit())
	class_overlay_button = _overlay_toggle(column,"Classes  F5","Houses by faction, and where halls and alehouses reach")
	class_overlay_button.toggled.connect(func(_on): class_overlay_toggled.emit())

func _overlay_toggle(parent: Control, text: String, tooltip: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.tooltip_text = tooltip
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.custom_minimum_size = Vector2(220,0)
	parent.add_child(toggle)
	return toggle

func _toggle_overlays_menu() -> void:
	var opening := not overlays_menu.visible
	close_build_menu()
	close_options_menu()
	close_weather_menu()
	overlays_menu.visible = opening
	overlays_button.button_pressed = opening
	_layout()

func close_overlays_menu() -> void:
	overlays_menu.visible = false
	overlays_button.button_pressed = false

## Shows or hides the developer tools: the weather panel's sun button.
func set_dev_tools(enabled: bool) -> void:
	dev_tools = enabled
	sun_button.visible = enabled
	if not enabled:
		close_weather_menu()
	_layout()

func _svg_texture(svg: String) -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string(svg,1.0)
	return ImageTexture.create_from_image(image)

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
	# The lever first; storehouse markups are each storehouse's pay.
	var tax_row := _treasury_row(column,"Tax on wages","Withheld from household wages at payday",[["−%d%%" % Economy.TAX_STEP,-Economy.TAX_STEP],["+%d%%" % Economy.TAX_STEP,Economy.TAX_STEP]],
		func(step): tax_selected.emit(clampi(shown_tax + step,0,Economy.MAX_TAX_PERCENT)))
	tax_value = tax_row[0]
	tax_buttons = tax_row[1]
	tax_lock = _lock_row(column)
	column.add_child(HSeparator.new())
	treasury_ledger = _rich_label(14)
	treasury_ledger.custom_minimum_size = Vector2(330,0)
	treasury_ledger.tooltip_text = "Unpaid public workers keep working, but the unions' favour falls\nwith the unpaid workers of the last 6 paydays."
	column.add_child(treasury_ledger)
	column.add_child(HSeparator.new())
	# Reserves are moved by hand: construction cannot spend public pay, and
	# public pay cannot spend the capital reserve. Most players never need to.
	reserves_button = _button("Reserves ▸")
	reserves_button.toggle_mode = true
	reserves_button.flat = true
	reserves_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	reserves_button.add_theme_font_size_override("font_size",14)
	reserves_button.tooltip_text = "Set gold aside for public pay or for construction"
	reserves_button.toggled.connect(func(on):
		reserves_button.text = "Reserves ▾" if on else "Reserves ▸"
		reserves_box.visible = on
		if shown_sim != null: _refresh_treasury(shown_sim)
		_layout()
	)
	column.add_child(reserves_button)
	reserves_box = VBoxContainer.new()
	reserves_box.add_theme_constant_override("separation",6)
	reserves_box.visible = false
	column.add_child(reserves_box)
	keep_reserve_button = CheckButton.new()
	keep_reserve_button.text = "Keep %d paydays of services reserved" % Economy.SERVICE_RESERVE_PAYDAYS
	keep_reserve_button.focus_mode = Control.FOCUS_NONE
	keep_reserve_button.add_theme_font_size_override("font_size",14)
	keep_reserve_button.tooltip_text = "At each payday, top the public pay reserve up from free gold"
	keep_reserve_button.toggled.connect(func(enabled): reserve_target_toggled.emit(enabled))
	reserves_box.add_child(keep_reserve_button)
	for entry in [["free","Free gold","Spent by construction and public pay alike"],
			["public","Public pay reserve","Pays public workers first; construction never touches it"],
			["capital","Capital reserve","Pays for construction first; public pay never touches it"]]:
		var buttons: Array = [] if entry[0] == "free" else [["−1 g",-Economy.SILVER_PER_GOLD],["+1 g",Economy.SILVER_PER_GOLD]]
		var row := _treasury_row(reserves_box,entry[1],entry[2],buttons,func(amount): reserve_transfer_requested.emit(entry[0],amount))
		treasury_values[entry[0]] = row[0]
		if not row[1].is_empty(): reserve_buttons[entry[0]] = row[1]

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
		close_factions_menu()
		close_options_menu()
		close_build_menu()
		close_weather_menu()
		if food_menu.visible: close_food_menu()
		if shown_sim != null: _refresh_treasury(shown_sim)
	_layout()

func close_treasury_menu() -> void:
	treasury_menu.visible = false
	treasury_button.button_pressed = false

func _refresh_treasury(sim) -> void:
	shown_sim = sim
	_refresh_gold(sim)
	if not treasury_menu.visible:
		return
	shown_tax = sim.tax_percent
	var free: int = Economy.free_gold(sim)
	treasury_values.free.text = Economy.format(free)
	treasury_values.public.text = Economy.format(sim.public_reserve)
	treasury_values.capital.text = Economy.format(sim.capital_reserve)
	keep_reserve_button.set_pressed_no_signal(sim.keep_service_reserve)
	for pot in reserve_buttons:
		reserve_buttons[pot][-Economy.SILVER_PER_GOLD].disabled = int(sim.get(pot + "_reserve")) == 0
		reserve_buttons[pot][Economy.SILVER_PER_GOLD].disabled = free == 0
	tax_value.text = "%d%%" % sim.tax_percent
	tax_buttons[-Economy.TAX_STEP].disabled = sim.tax_percent <= 0
	tax_buttons[Economy.TAX_STEP].disabled = sim.tax_percent >= Economy.MAX_TAX_PERCENT
	# A pledged lever shows a padlock, and the steps it forbids are disabled.
	_lock_lever(sim,"tax",sim.tax_percent,tax_buttons,tax_lock)
	var text := _treasury_ledger_text(sim)
	if treasury_ledger.text != text:
		treasury_ledger.text = text
		_layout()

## The last payday's net and its trend, what moved gold, then the services.
func _treasury_ledger_text(sim) -> String:
	var text := ""
	if sim.ledger.is_empty():
		text += "[color=#868f7a]Payday every %.0f s: tax comes in and public workers are paid.[/color]\n" % (float(sim.PAYDAY_TICKS)/sim.TICKS_PER_SECOND)
	else:
		var last: Dictionary = sim.ledger[-1]
		var net := _ledger_net(last)
		var trend := ""
		if sim.ledger.size() > 1:
			var before := _ledger_net(sim.ledger[-2])
			trend = "  [color=#868f7a]%s from %s[/color]" % ["↑" if net > before else ("↓" if net < before else "="),Economy.format(before)]
		text += "[b]Last payday[/b]  %s%s\n[table=2]" % [_signed_silver(net),trend]
		# Tax is always listed; other lines only when they moved gold.
		for entry in [["Tax on wages","tax",1],["Storehouse surplus","trade",1],["Pay cuts","pay_cuts",1],["Demolition refunds","refunds",1],["Faction deals","deals",1],["Public pay","public_pay",-1],["Construction","construction",-1]]:
			if entry[1] == "tax" or int(last[entry[1]]) != 0:
				text += "[cell][color=#a9b39a]%s[/color]  [/cell][cell]%s[/cell]" % [entry[0],_signed_silver(int(last[entry[1]])*entry[2])]
		text += "[/table]\n"
		if int(last.unpaid) > 0:
			text += "[color=#d98c6f]Public workers went unpaid %s[/color]\n" % Economy.format(int(last.unpaid))
	if int(sim.period.construction) > 0:
		text += "[color=#868f7a]Building since then %s[/color]\n" % Economy.format(-int(sim.period.construction))
	if sim.public_frustration > 0:
		text += "[color=#d98c6f]Public workers' frustration %d[/color]\n" % sim.public_frustration
	return text + "\n" + _services_text(sim)

static func _ledger_net(entry: Dictionary) -> int:
	return int(entry.tax) + int(entry.trade) + int(entry.pay_cuts) + int(entry.refunds) + int(entry.deals) - int(entry.public_pay) - int(entry.construction)

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
		var upkeep := Economy.upkeep(row,building.pay)
		group.count += 1
		if building.staffed:
			group.due += upkeep
			if sim.tick >= sim.PAYDAY_TICKS:
				group.unpaid += maxi(0,upkeep - building.last_wage)
		else:
			group.idle += 1
		groups[row.id] = group
		total += upkeep if building.staffed else 0
	if groups.is_empty():
		return "[b]Services[/b]  [color=#868f7a]none yet; a forester is the first[/color]"
	var text := "[b]Services[/b]  %s per payday\n" % Economy.format(total)
	for id in groups:
		var group: Dictionary = groups[id]
		text += "[color=#a9b39a]%s ×%d[/color]  %s" % [group.name,group.count,Economy.format(group.due)]
		if group.idle > 0:
			text += "  ·  %d without workers" % group.idle
		if group.unpaid > 0:
			text += "  ·  [color=#d98c6f]%s unpaid[/color]" % Economy.format(group.unpaid)
		text += "\n"
	return text.strip_edges()

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
	clock_button.tooltip_text = "Let the day pass (eight-minute days, four-minute nights)"
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
		close_factions_menu()
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
		# Reserved rows (the manor) exist in data but are not built yet.
		var members: Array = db.buildings.keys().filter(func(id): return db.buildings[id].category == category and not db.buildings[id].get("reserved", false))
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
	close_factions_menu()
	close_overlays_menu()
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
		close_factions_menu()
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
	close_overlays_menu()
	close_options_menu()
	close_weather_menu()
	close_treasury_menu()
	close_factions_menu()
	close_offer_card()
	for id in offer_alerts_by_id:
		offer_alerts_by_id[id].queue_free()
	offer_alerts_by_id.clear()
	set_class_overlay_visible(false)
	set_food_overlay_visible(false)
	set_operations_overlay_visible(false)
	close_food_menu()
	food_meter.samples.clear()
	sale_button.set_pressed_no_signal(false)
	placement_card.visible = false
	side.visible = false
	toast.visible = false
	toast_seconds = 0
	shown_payday = -1
	shown_gold = -1.0
	gold_count_left = 0.0
	set_deposits_visible(false)

func set_deposits_visible(value: bool) -> void:
	deposits_button.set_pressed_no_signal(value)

func show_error(text: String) -> void:
	if sounds != null:
		sounds.play("error")
	toast_label.text = text
	toast.visible = true
	toast_seconds = 3.0
	_layout()

func _process(delta: float) -> void:
	if gold_count_left > 0.0:
		gold_count_left = maxf(0.0, gold_count_left - delta)
		var t := 1.0 - gold_count_left / GOLD_COUNT_SECONDS
		shown_gold = lerpf(gold_from, float(gold_target), 1.0 - pow(1.0 - t, 3.0))
		_set_gold_text(int(round(shown_gold)) if gold_count_left > 0.0 else gold_target)
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
	overlays_menu.reset_size()
	overlays_menu.position = Vector2(clampf(overlays_button.get_global_rect().get_center().x - overlays_menu.size.x/2.0, 18, screen.x - overlays_menu.size.x - 18), bottom.position.y-overlays_menu.size.y-10).floor()
	placement_card.size = Vector2(320,0).max(placement_card.get_combined_minimum_size())
	placement_card.position = Vector2(18,screen.y-placement_card.size.y-18).floor()
	# The inspector fits its text, scrolling only when it would reach the bottom bar.
	var inspector_content: float = inspector_scroll.get_child(0).get_combined_minimum_size().y
	inspector_scroll.custom_minimum_size = Vector2(0,minf(inspector_content,maxf(160.0,bottom.position.y-78-70)))
	side.reset_size()
	side.size = Vector2(330,0).max(side.get_combined_minimum_size())
	side.position = Vector2(screen.x-side.size.x-18,78)
	cog_button.size = Vector2(48,48)
	cog_button.position = Vector2(screen.x-66,18)
	# The sun button shows only with the developer tools.
	var next_x: float = cog_button.position.x
	sun_button.size = Vector2(48,48)
	if sun_button.visible:
		next_x -= 56
	sun_button.position = Vector2(next_x,18)
	map_button.size = Vector2(48,48)
	map_button.position = Vector2(next_x-56,18)
	factions_button.size = Vector2(48,48)
	factions_button.position = Vector2(map_button.position.x-56,18)
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
	var below: float = treasury_button.get_rect().end.y + 12
	# The Factions panel opens under its button, where the inspector stands.
	var content: float = factions_scroll.get_child(0).get_combined_minimum_size().y
	factions_scroll.custom_minimum_size = Vector2(384,minf(content,maxf(120.0,bottom.position.y-78-70)))
	factions_menu.reset_size()
	factions_menu.position = Vector2(screen.x-factions_menu.size.x-18,78)
	# Offer alerts run down the left edge; the open one's card stands beside it.
	# The Treasury panel opens over the same edge, so they wait while it is open.
	offer_alerts.visible = not offer_alerts_by_id.is_empty() and not treasury_menu.visible
	offer_alerts.reset_size()
	offer_alerts.position = Vector2(18,below)
	offer_card.visible = offer_card.visible and offer_alerts.visible
	offer_card.reset_size()
	offer_card.size = Vector2(320,0).max(offer_card.get_combined_minimum_size())
	var open_alert: Control = offer_alerts_by_id.get(open_offer)
	offer_card.position = Vector2(offer_alerts.position.x + 62, offer_alerts.position.y + (open_alert.position.y if open_alert != null else 0.0)).floor()
	# Map keys stack up the left edge above the placement card.
	var key_top: float = placement_card.position.y if placement_card.visible else screen.y
	for legend in [class_legend,food_legend,operations_legend]:
		legend.reset_size()
		legend.position = Vector2(18,key_top-legend.size.y-18).floor()
		if legend.visible:
			key_top = legend.position.y
	treasury_menu.reset_size()
	treasury_menu.position = Vector2(18,below)
	food_menu.reset_size()
	# Under the food chip, which sits in the resource bar.
	food_menu.position = Vector2(clampf(food_button.get_global_rect().position.x, 18, maxf(18, screen.x - food_menu.size.x - 18)),below).floor()
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

func _build_resource_bar() -> void:
	stock_bar = _panel()
	stock_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(stock_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	stock_bar.add_child(row)
	# The food chip is the food balance button, so it opens the breakdown.
	root.remove_child(food_button)
	row.add_child(food_button)
	for entry in RESOURCE_GROUPS.slice(1) + [["storage","Storage","res://view/overlays/storage.svg"],["workers","Workers","res://view/overlays/workers.svg"]]:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation",5)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var icon := TextureRect.new()
		icon.texture = _svg_texture(FileAccess.get_file_as_string(entry[2]))
		icon.custom_minimum_size = Vector2(20,20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
		var label := _label("0",15)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(label)
		row.add_child(chip)
		resource_chips[entry[0]] = [chip,label]

## Each good in its first group: food (basic and staple), goods a tier needs
## by name (water), fuel, construction materials, then everything else.
func _group_goods(db) -> Array:
	var direct := {}
	var materials := {}
	for tier in db.tiers.values():
		for need in tier.consumption:
			direct[need] = true
	for row in db.buildings.values():
		for good in row.cost:
			materials[good] = true
	var groups := {}
	for entry in RESOURCE_GROUPS:
		groups[entry[0]] = []
	for good in db.goods:
		var categories: Array = db.goods[good].get("categories",[])
		var group := "ingredients"
		if "basic" in categories or "staple" in categories: group = "food"
		elif "fuel" in categories: group = "fuel"
		elif direct.has(good): group = "water"
		elif materials.has(good): group = "materials"
		groups[group].append(good)
	var result: Array = []
	for entry in RESOURCE_GROUPS:
		result.append([entry[0],entry[1],entry[2],groups[entry[0]]])
	return result

## Totals per group, with each good's count in the tooltip.
func _refresh_stock_bar(sim) -> void:
	if resource_db != sim.db:
		resource_db = sim.db
		resource_groups = _group_goods(sim.db)
	var changed := false
	for group in resource_groups:
		var total := 0
		var lines: Array[String] = ["%s in storehouses" % group[1]]
		var goods: Array = group[3].duplicate()
		goods.sort_custom(func(a, b): return sim.stock(a) > sim.stock(b))
		for good in goods:
			total += sim.stock(good)
			lines.append("%s  %d" % [sim.db.goods[good].name,sim.stock(good)])
		if group[0] == "food":
			food_button.tooltip_text = "\n".join(lines) + "\n\nThe rate is food made less what the houses need. Click for the food balance."
			food_total = total
			continue
		var chip: Array = resource_chips[group[0]]
		chip[0].visible = not goods.is_empty()
		chip[0].tooltip_text = "\n".join(lines)
		if chip[1].text != str(total):
			chip[1].text = str(total)
			changed = true
	var held := 0
	var capacity := 0
	for building in sim.buildings.values():
		if building.definition.kind == "storehouse":
			held += building.inventory.total()
			capacity += building.inventory.capacity
	var storage: Array = resource_chips.storage
	var fill := "%d/%d" % [held,capacity] if capacity > 0 else "none"
	storage[0].tooltip_text = "Storehouse space used\nProducers wait when their storehouse is full" if capacity > 0 else "No storehouse yet"
	storage[1].add_theme_color_override("font_color",Color("f0b43c") if capacity > 0 and held * 10 >= capacity * 9 else Color("e4dfd2"))
	if storage[1].text != fill:
		storage[1].text = fill
		changed = true
	# Working adults in a job of all of them; dependents are in the tooltip.
	var workforce: int = sim.workforce()
	var employed: int = workforce - sim.idle_workers
	var children := 0
	var families := 0
	for building in sim.buildings.values():
		if building.definition.kind == "house":
			families += 1
			children += sim.family_children(building)
	var workers: Array = resource_chips.workers
	var count := "%d/%d" % [employed,workforce]
	workers[0].tooltip_text = "%d of %d working adults in a job\n%d idle\nDependents: %d %s\nFamilies: %d" % [employed,workforce,sim.idle_workers,children,"child" if children == 1 else "children",families]
	workers[1].add_theme_color_override("font_color",Color("f0b43c") if sim.idle_workers > 0 else Color("e4dfd2"))
	if workers[1].text != count:
		workers[1].text = count
		changed = true
	if changed:
		_layout()

func blocks_mouse(point: Vector2) -> bool:
	if run_card.visible: return true
	if options_menu.visible:
		return true
	if factions_menu.visible and factions_menu.get_global_rect().has_point(point):
		return true
	for button in [cog_button,sun_button,map_button,factions_button,treasury_button]:
		if not button.visible: continue
		if button.get_global_rect().has_point(point):
			return true
	for panel in [bottom,build_menu,overlays_menu,placement_card,side,toast,weather_menu,treasury_menu,stock_bar,offer_alerts,offer_card,class_legend,food_legend,operations_legend,food_menu]:
		if panel.visible and panel.get_global_rect().has_point(point):
			return true
	return false

func refresh(sim, selected_id: int, tool: String, rotation_quarters: int = 0) -> void:
	_refresh_treasury(sim)
	_refresh_factions(sim)
	_refresh_stock_bar(sim)
	_refresh_food(sim)
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
	var selected = sim.structure(selected_id)
	side.visible = selected != null and tool == "inspect"
	# The inspector and the Factions panel share the right side.
	if side.visible and factions_menu.visible: close_factions_menu()
	if side.visible:
		_refresh_inspection(sim,selected)

func _refresh_inspection(sim, building) -> void:
	var row: Dictionary = building.definition
	inspector_title.text = row.name
	shown_building = building
	inspection_progress.visible = false
	cancel_site_button.visible = sim.sites.has(building.uid)
	if cancel_site_button.visible:
		_refresh_site(sim, building)
		return
	workers_button.visible = int(row.workers) > 0
	workers_button.text = "Stop workers" if building.workers_enabled else "Resume workers"
	# Storehouses pay their carriers through the markup; other workplaces pay their crews.
	var paid: bool = int(row.workers) > 0 or row.kind == "storehouse"
	pay_row.visible = paid
	pay_hint.visible = paid
	if paid:
		for level in pay_buttons:
			pay_buttons[level].set_pressed_no_signal(building.pay == level)
		pay_hint.text = _pay_hint(sim,building)
	var text := ""
	var details := ""
	match row.kind:
		"producer":
			text = _producer_summary(sim,building)
			details = _producer_details(sim,building)
		"house":
			text = _house_summary(sim,building)
			details = _house_details(sim,building)
		"storehouse":
			text = _store_summary(sim,building)
			details = _store_details(sim,building)
		"hall":
			text = _hall_text(sim,building)
		_:
			text = "[color=#d6c288]%s[/color]" % _sentence(building.status)
	if row.kind in ["producer","house"] and sim.nearest_store(building) == null:
		text += "\n[color=#d98c6f]No road to a storehouse[/color]"
	var footprint: Vector2i = building.footprint()
	details += _owner_text(sim,building)
	details += "[color=#868f7a]%d × %d at (%d, %d), facing %d°[/color]" % [footprint.x,footprint.y,building.cell.x,building.cell.y,building.rotation_quarters * 90]
	text = text.strip_edges()
	details = details.strip_edges()
	if inspector.text != text or details_text.text != details:
		inspector.text = text
		details_text.text = details
		_layout()
		# Rich text settles its height a frame late.
		call_deferred("_layout")
	_refresh_sale(sim,building)

## A construction site: what it waits for, then how far the building is.
func _refresh_site(sim, site) -> void:
	var row: Dictionary = site.definition
	workers_button.visible = false
	pay_row.visible = false
	pay_hint.visible = false
	sale_button.visible = false
	sale_list.visible = false
	var text := ""
	var build: int = sim.build_ticks(row)
	match site.status:
		"no road":
			text = "[color=#d98c6f]No road to a storehouse[/color]
"
		"building":
			text = "[color=#d6c288]Building[/color]  [color=#868f7a]%.0f s left[/color]
" % _seconds(sim,build - site.progress)
		_:
			text = "[color=#d6c288]Waiting for materials[/color]
"
	for good in row.cost:
		var have: int = site.materials.count(good)
		var need := int(row.cost[good])
		var colour := "a8c38a" if have >= need else "e4dfd2"
		text += "[b]%s[/b]  [color=#%s]%d / %d[/color]
" % [sim.db.goods[good].name,colour,have,need]
	if site.status != "building":
		var short: Array = []
		for good in row.cost:
			if sim.stock(good) < sim.site_owes(site,good):
				short.append(str(sim.db.goods[good].name).to_lower())
		if not short.is_empty():
			text += "[color=#d98c6f]Not enough %s in store[/color]
" % " or ".join(short)
	inspection_progress.visible = true
	if site.status == "building":
		inspection_progress.max_value = float(build)
		inspection_progress.value = site.progress
	else:
		inspection_progress.max_value = float(Building.material_count(row))
		inspection_progress.value = site.materials.total()
	var footprint: Vector2i = site.footprint()
	var details := "Purse for materials %s
Builds in %.0f s once supplied
[color=#868f7a]%d × %d at (%d, %d), facing %d°[/color]" % [Economy.format(site.silver),_seconds(sim,build),footprint.x,footprint.y,site.cell.x,site.cell.y,site.rotation_quarters * 90]
	text = text.strip_edges()
	if inspector.text != text or details_text.text != details:
		inspector.text = text
		details_text.text = details
		_layout()
		call_deferred("_layout")

## Sets the gold counter. A payday's change counts up (or down) over
## GOLD_COUNT_SECONDS with a coin clink and a "+12 s" rising from the counter;
## any other change, such as building, shows at once.
func _refresh_gold(sim) -> void:
	var payday: int = sim.tick / sim.PAYDAY_TICKS
	if shown_payday >= 0 and payday > shown_payday:
		var change: int = sim.treasury - seen_treasury
		gold_from = shown_gold if shown_gold >= 0.0 else float(seen_treasury)
		gold_count_left = GOLD_COUNT_SECONDS
		if change != 0:
			_float_payday(change)
		if sounds != null:
			sounds.play("coin")
	elif gold_count_left <= 0.0:
		shown_gold = float(sim.treasury)
		_set_gold_text(sim.treasury)
	shown_payday = payday
	gold_target = sim.treasury
	seen_treasury = sim.treasury

func _set_gold_text(silver: int) -> void:
	var text := Economy.format(silver)
	if treasury_button.text == text:
		return
	var resized := text.length() != treasury_button.text.length()
	treasury_button.text = text
	if resized:
		_layout()

## "+12 s" or "−4 s" in green or red, rising from under the gold counter and fading.
func _float_payday(change: int) -> void:
	var label := _label(("+" if change > 0 else "") + Economy.format(change), 16)
	label.add_theme_color_override("font_color", Color("a8c38a") if change > 0 else Color("d98c6f"))
	label.add_theme_color_override("font_outline_color", Color("1d2119"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.tooltip_text = ""
	root.add_child(label)
	var start := Vector2(treasury_button.get_rect().end.x - 64, treasury_button.get_rect().end.y + 2)
	label.position = start
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start.y + 26.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.9)
	tween.chain().tween_callback(label.queue_free)

## What the selected pay level costs, and who pays it.
func _pay_hint(sim, building) -> String:
	var row: Dictionary = building.definition
	if row.kind == "storehouse":
		return "Markup %d%%: households pay it, the storekeeper and carriers earn it. Better-paid carriers are found first." % Economy.markup(building)
	var bonus: int = Economy.PAY_BONUS[building.pay]
	if Economy.is_public(row):
		return "The treasury pays %s per payday.%s" % [Economy.format(Economy.upkeep(row,building.pay)),"" if bonus == 0 else (" Workers come here first." if bonus > 0 else " Workers come here last.")]
	if bonus > 0:
		return "+%s per worker each payday, from the treasury. Workers come here first." % Economy.format(bonus)
	if bonus < 0:
		return "−%s per worker each payday, kept by the treasury. Workers come here last." % Economy.format(-bonus)
	return "Workers take the best-paid jobs first."

## Seconds for a tick count at the sim's speed.
static func _seconds(sim, ticks: float) -> float:
	return ticks / float(sim.TICKS_PER_SECOND)

## Goods are counted per minute and money per payday (docs/UI.md): `amount`
## every `cycle_ticks` as a rate per minute at 1×.
static func _per_minute(sim, amount: float, cycle_ticks: int) -> float:
	return amount * 60.0 * float(sim.TICKS_PER_SECOND) / float(maxi(1,cycle_ticks))

static func _amount(value: float) -> String:
	return "%.0f" % value if value >= 10.0 or is_equal_approx(value,roundf(value)) else "%.1f" % value

## "24 Water/min" for each good a cycle makes.
func _rate(sim, items: Dictionary, cycle_ticks: int) -> String:
	var parts: Array[String] = []
	for good in items:
		parts.append("%s %s/min" % [_amount(_per_minute(sim,float(items[good]),cycle_ticks)),sim.db.goods[good].name])
	return ", ".join(parts)

## Whether it works and why not, its workers, what it makes and holds.
func _producer_summary(sim, building) -> String:
	var row: Dictionary = building.definition
	var text := "[color=#d6c288]%s[/color]" % _sentence(building.status)
	var morale: int = Needs.morale(sim)
	if building.staffed and Needs.work_speed(morale) < 100:
		text += "  [color=#d98c6f]%d%% speed: low morale[/color]" % Needs.work_speed(morale)
	text += "\n"
	var assigned := int(row.workers) if building.staffed else 0
	text += "[b]Workers[/b]  %d / %d%s\n" % [assigned,int(row.workers)," (stopped)" if not building.workers_enabled else ""]
	text += _crew_warnings(building)
	if row.has("forest_action"):
		if row.forest_action == "cut":
			text += "[b]Fells[/b]  mature trees up to %d tiles away, 1 log each\n" % int(row.work_radius)
		else:
			text += "[b]Plants[/b]  saplings up to %d tiles away; they grow in %.0f s\n" % [int(row.work_radius),_seconds(sim,Forestry.MATURITY_TICKS)]
	elif not row.inputs.is_empty():
		text += "[b]Makes[/b]  %s from %s\n" % [_goods(row.outputs,sim.db),_goods(row.inputs,sim.db)]
		text += "[b]Has[/b]  %s → %s\n" % [_slot_goods(building.input,row.inputs,sim.db),_slot_goods(building.output,row.outputs,sim.db)]
	elif not row.outputs.is_empty():
		text += "[b]Makes[/b]  %s\n" % _rate(sim,row.outputs,int(row.cycle_ticks))
		text += "[b]Has[/b]  %s  [color=#868f7a]of %d[/color]\n" % [_slot_goods(building.output,row.outputs,sim.db),building.output.capacity]
	if Economy.is_public(row):
		var due := Economy.upkeep(row,building.pay)
		if building.staffed and sim.tick >= sim.PAYDAY_TICKS and building.last_wage < due:
			text += "[color=#d98c6f]Last payday %s of %s: working unpaid[/color]\n" % [Economy.format(building.last_wage),Economy.format(due)]
		if building.frustration > 0:
			text += "[color=#d98c6f]Frustration: %d unpaid worker-paydays[/color]\n" % building.frustration
		if row.has("provides"):
			text += "[b]Serves[/b]  %d houses within %d road tiles\n" % [sim.served_houses(building),int(row.service_radius)]
	inspection_progress.visible = true
	inspection_progress.max_value = float(row.cycle_ticks)
	inspection_progress.value = building.progress
	return text

func _producer_details(sim, building) -> String:
	var row: Dictionary = building.definition
	var text := _families_line(sim,building)
	if not Economy.is_public(row):
		for good in row.outputs:
			text += "Sells %s for %s, %s of it wages\n" % [str(sim.db.goods[good].name).to_lower(),Economy.format(sim.price(good)),Economy.format(int(sim.economy.labour[good]))]
		if not row.inputs.is_empty():
			text += "Purse for inputs %s\n" % Economy.format(building.silver)
	text += "Cycle %.1f of %.1f s\n" % [_seconds(sim,building.progress),_seconds(sim,float(row.cycle_ticks))]
	if building.work_cell.x >= 0:
		text += "Working at (%d, %d)\n" % [building.work_cell.x,building.work_cell.y]
	text += "%d workers idle in the village\n" % sim.idle_workers
	return text

## Tier, happiness and where it is heading, needs met, family and savings.
func _house_summary(sim, house) -> String:
	var tier: Dictionary = sim.db.tiers[house.tier]
	var text := "[color=#d6c288]%s[/color]  [color=#868f7a]tier %d[/color]\n" % [tier.name,house.tier]
	if not house.needs_ok and house.status != "needs satisfied":
		text += "[color=#d98c6f]%s[/color]\n" % _sentence(house.status)
	text += "[b]Happiness[/b]  %d%%\n" % house.happiness
	if sim.db.tiers.has(house.tier+1) and not house.definition.has("fixed_tier"):
		var left: float = _seconds(sim,maxf(0.0,float(tier.upgrade_after_ticks) - house.satisfied_ticks))
		text += ("[b]Upgrades[/b]  in %.0f s\n" % left) if house.needs_ok else "[color=#868f7a]Upgrades once every need is met[/color]\n"
		inspection_progress.visible = true
		inspection_progress.max_value = float(tier.upgrade_after_ticks)
		inspection_progress.value = house.satisfied_ticks
	if house.tier > 1 and Needs.unhappy(sim,house):
		text += "[color=#d98c6f]Moves down a tier in %.0f s[/color]\n" % _seconds(sim,maxi(0,int(tier.downgrade_after_ticks)-house.unsatisfied_ticks))
	text += "[b]Needs[/b]  %s\n" % _need_marks(house,tier,sim)
	text += _family_line(sim,house)
	text += "[b]Savings[/b]  %s\n" % Economy.format(house.silver)
	return text

func _house_details(sim, house) -> String:
	var tier: Dictionary = sim.db.tiers[house.tier]
	var text := ""
	var settled: int = Needs.settled(house)
	text += "Settled happiness %s; below %d%% it moves down\n" % ["after a full cycle" if settled < 0 else "%d%%" % settled,int(tier.downgrade_below_happiness)]
	text += "Eats every %.0f s: %s\n" % [_seconds(sim,float(tier.consume_every_ticks)),_needs_text(house,tier.consumption,sim)]
	if house.needs_ok:
		text += "Next meal in %.0f s\n" % _seconds(sim,maxi(0,house.needs_next_tick-sim.tick))
	text += "Pantry %s\n" % _goods(house.input.items,sim.db)
	text += "Last wage %s, %s of it taxed\n" % [Economy.format(house.last_wage),Economy.format(house.last_tax)]
	text += _class_text(sim,house)
	return text

## Each need, ticked when met this cycle.
func _need_marks(house, tier: Dictionary, sim) -> String:
	var parts: Array[String] = []
	for need in tier.consumption:
		parts.append(_mark(house.needs_met.has(need),str(sim.db.need_name(need))))
	for service in Needs.counted_services(tier):
		parts.append(_mark(house.needs_met.has(service),str(service).capitalize()))
	return "  ".join(parts)

## A tick or cross and the need's name, kept on one line.
func _mark(met: bool, label: String) -> String:
	var space := String.chr(0xA0)
	var unbroken := ("✓" if met else "✗") + space + _sentence(label).replace(" ", space)
	return "[color=#%s]%s[/color]" % ["a8c38a" if met else "d98c6f",unbroken]

## "missing staple food" → "Missing staple food".
static func _sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1) if not text.is_empty() else text

## Carriers on shift, stock, and the storekeeper.
func _store_summary(sim, store) -> String:
	var total := 0
	for carrier in sim.carriers:
		if carrier.owner == store.uid:
			total += 1
	var text := ""
	if not store.workers_enabled:
		text += "[color=#d98c6f]Workers stopped[/color]\n"
	elif store.crew < total:
		text += "[color=#d98c6f]Short of carriers: %d of %d on shift[/color]\n" % [store.crew,total]
	else:
		text += "[color=#d6c288]%d carriers on shift[/color]\n" % total
	text += "[b]Stored[/b]  %d / %d\n" % [store.inventory.total(),store.inventory.capacity]
	if not Labour.jobs(store.definition).is_empty():
		if store._keeper >= 0:
			text += "[b]Storekeeper[/b]  %s\n" % _house_label(sim,store._keeper)
		else:
			text += "[color=#d98c6f]No storekeeper: needs a middle-class family[/color]\n"
	return text

func _store_details(sim, store) -> String:
	var active := 0
	var carrying := 0
	for carrier in sim.carriers:
		if carrier.owner == store.uid:
			if carrier.stage != "idle": active += 1
			if not carrier.cargo.is_empty(): carrying += 1
	var text := "%d carriers busy, %d carrying goods\n" % [active,carrying]
	text += "Wages paid from the markup %s so far%s\n" % [Economy.format(store.wages_paid),"; the storekeeper takes %d%%" % Labour.KEEPER_PERCENT if store._keeper >= 0 else ""]
	text += "Holds %s\n" % _goods(store.inventory.items,sim.db)
	text += "Trading purse %s, keeps up to %s\n" % [Economy.format(store.silver),Economy.format(sim.economy.purse_cap(sim,store))]
	return text

func _goods(items: Dictionary, db) -> String:
	if items.is_empty():
		return "None"
	var parts: Array[String] = []
	for good in items:
		parts.append("%d %s" % [int(items[good]),db.goods[good].name])
	return ", ".join(parts)

## Tier names whose houses need this service, e.g. "Villagers".
func _tiers_needing(sim, service: String) -> String:
	var names: Array = []
	for id in sim.db.tiers:
		if service in sim.db.tiers[id].get("services", []):
			names.append(sim.db.tiers[id].name)
	return " and ".join(names) if not names.is_empty() else "no"

func _needs_text(house, consumption: Dictionary, sim) -> String:
	var parts: Array[String] = []
	for need in consumption:
		var colour := "a8c38a" if house.needs_met.has(need) else "d98c6f"
		# Direct from the producer at the chain price, or from a storehouse with its
		# markup. A category (staple, fuel) is priced at its cheapest good.
		var chain: int = sim.economy.need_price(sim,need)
		var retail: int = sim.economy.retail_price(sim,need)
		var price_text := Economy.format(chain) if retail == chain else "%s, %s stored" % [Economy.format(chain),Economy.format(retail)]
		var label: String = sim.db.need_name(need)
		if not sim.db.goods.has(need):
			var goods: Array = sim.db.need_goods(need).map(func(good): return str(sim.db.goods[good].name))
			label += ": " + (", ".join(goods.slice(0,-1)) + " or " + goods[-1] if goods.size() > 1 else goods[0])
			price_text = "from " + price_text
		parts.append("[color=#%s]%d %s (%s)[/color]" % [colour,int(consumption[need]),label,price_text])
	# Service needs, such as a chapel, are met by a staffed provider in range.
	for service in Needs.counted_services(sim.db.tiers[house.tier]):
		var colour := "a8c38a" if house.needs_met.has(service) else "d98c6f"
		parts.append("[color=#%s]%s nearby[/color]" % [colour,str(service).capitalize()])
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
		var have: int = sim.available(good)
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
		lines.append("[b]Public service[/b]  upkeep %s per payday from the treasury" % Economy.format(Economy.upkeep(row,Building.NORMAL)))
	if row.has("provides"):
		lines.append("[b]Serves[/b]  houses within %d road tiles: a %s need" % [int(row.service_radius),_tiers_needing(sim,str(row.provides))])
	match row.kind:
		"producer":
			if row.has("forest_action"):
				lines.append("[b]Work area[/b]  %d tiles over reachable land" % int(row.work_radius))
			if not row.inputs.is_empty():
				lines.append("[b]Uses[/b]  " + _goods(row.inputs,sim.db))
			if row.get("forest_action","") == "plant":
				lines.append("[b]Plants[/b]  %s saplings/min; they grow in %.0f s" % [_amount(_per_minute(sim,1.0,int(row.cycle_ticks))),_seconds(sim,Forestry.MATURITY_TICKS)])
			else:
				lines.append("[b]Makes[/b]  " + _rate(sim,row.outputs,int(row.cycle_ticks)))
				if row.get("forest_action","") == "cut": lines.append("Harvests nearby mature trees")
		"storehouse":
			lines.append("[b]Storage[/b]  %d  ·  %d carriers" % [int(row.storage_capacity),int(row.carriers)])
		"house":
			var tier: Dictionary = sim.db.tiers[1]
			lines.append("[b]Houses[/b]  %s  ·  %d workers" % [tier.name,int(tier.workers_per_house)])
	# The first few placements explain themselves; after that the card is the facts.
	var learning: bool = placements < HINT_PLACEMENTS
	if row.kind != "road" and (learning or rotation_quarters != 0):
		var footprint := Building.rotated_footprint(row, rotation_quarters)
		lines.append("[b]Size[/b]  %d × %d  ·  [b]Facing[/b]  %d°" % [footprint.x,footprint.y,rotation_quarters*90])
	rotate_button.visible = row.kind != "road"
	if learning or row.kind == "road":
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
		if sim.available(good) < int(cost[good]):
			return false
	return true

## Faction chips under the gold counter, the Factions panel and the class
## overlay's key (docs/FACTIONS.md §3–5, PLAN-factions.md item 7).
func _build_factions_menu() -> void:
	factions_button = _icon_button("res://view/overlays/factions.svg","Factions")
	factions_button.visible = false
	factions_button.pressed.connect(_toggle_factions_menu)
	root.add_child(factions_button)
	# Open offers wait on the left edge, one alert each, until chosen or lapsed.
	offer_alerts = VBoxContainer.new()
	offer_alerts.add_theme_constant_override("separation",10)
	root.add_child(offer_alerts)
	offer_card = _panel()
	offer_card.visible = false
	root.add_child(offer_card)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation",8)
	offer_card.add_child(card)
	var card_header := HBoxContainer.new()
	card.add_child(card_header)
	offer_title = _label("",18)
	offer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_header.add_child(offer_title)
	var close_card := _button("×")
	close_card.tooltip_text = "Decide later"
	close_card.pressed.connect(close_offer_card)
	card_header.add_child(close_card)
	offer_text = _rich_label(14)
	offer_text.custom_minimum_size = Vector2(300,0)
	card.add_child(offer_text)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation",6)
	card.add_child(choices)
	offer_accept = _button("Accept")
	offer_accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offer_accept.pressed.connect(func(): offer_accepted.emit(open_offer))
	choices.add_child(offer_accept)
	offer_decline = _button("Decline")
	offer_decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offer_decline.pressed.connect(func(): offer_declined.emit(open_offer))
	choices.add_child(offer_decline)
	factions_menu = _panel()
	factions_menu.visible = false
	root.add_child(factions_menu)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation",6)
	factions_menu.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := _label("Factions",20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	close_factions_button = _button("×")
	close_factions_button.tooltip_text = "Close factions"
	close_factions_button.pressed.connect(close_factions_menu)
	header.add_child(close_factions_button)
	factions_scroll = ScrollContainer.new()
	factions_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(factions_scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	factions_scroll.add_child(column)
	# What the player can act on comes first; the reasons behind it follow.
	# Open offers are the alerts on the left edge.
	column.add_child(_label("Pledges",16))
	pledge_list = VBoxContainer.new()
	pledge_list.add_theme_constant_override("separation",8)
	column.add_child(pledge_list)
	column.add_child(HSeparator.new())
	column.add_child(_label("Power",15))
	power_bar = HBoxContainer.new()
	power_bar.add_theme_constant_override("separation",0)
	power_bar.custom_minimum_size = Vector2(360,14)
	column.add_child(power_bar)
	# One row per faction; a click opens what moves its favour.
	faction_text = _rich_label(14)
	faction_text.meta_underlined = false
	faction_text.meta_clicked.connect(func(meta):
		var id := str(meta)
		if expanded_factions.has(id): expanded_factions.erase(id)
		else: expanded_factions[id] = true
		if shown_sim != null: _refresh_factions(shown_sim)
	)
	column.add_child(faction_text)
	# Map keys: a swatch and a name per colour; the explanations are tooltips.
	class_legend = _panel()
	class_legend.visible = false
	class_legend.tooltip_text = CLASS_LEGEND_TIP
	root.add_child(class_legend)
	class_legend_text = _rich_label(13)
	class_legend_text.custom_minimum_size = Vector2(150,0)
	class_legend_text.tooltip_text = CLASS_LEGEND_TIP
	class_legend.add_child(class_legend_text)
	food_legend = _panel()
	food_legend.visible = false
	food_legend.tooltip_text = FOOD_LEGEND_TIP
	root.add_child(food_legend)
	var legend_text := _rich_label(13)
	legend_text.custom_minimum_size = Vector2(150,0)
	legend_text.text = FOOD_LEGEND
	legend_text.tooltip_text = FOOD_LEGEND_TIP
	food_legend.add_child(legend_text)
	operations_legend = _panel()
	operations_legend.visible = false
	operations_legend.tooltip_text = OPERATIONS_LEGEND_TIP
	root.add_child(operations_legend)
	var operations_text := _rich_label(13)
	operations_text.custom_minimum_size = Vector2(190,0)
	operations_text.text = OPERATIONS_LEGEND
	operations_text.tooltip_text = OPERATIONS_LEGEND_TIP
	operations_legend.add_child(operations_text)

func _rich_label(font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(360,0)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("normal_font_size",font_size)
	label.add_theme_font_size_override("bold_font_size",font_size)
	label.add_theme_color_override("default_color",Color("e4dfd2"))
	return label

func _toggle_factions_menu() -> void:
	factions_menu.visible = not factions_menu.visible
	factions_button.button_pressed = factions_menu.visible
	if factions_menu.visible:
		close_treasury_menu()
		close_options_menu()
		close_build_menu()
		close_weather_menu()
		if food_menu.visible: close_food_menu()
		# It opens where the inspector stands.
		inspection_closed.emit()
		deals_signature = ""
		if shown_sim != null: _refresh_factions(shown_sim)
	_layout()

func close_factions_menu() -> void:
	if factions_menu != null:
		factions_menu.visible = false
		factions_button.button_pressed = false

## Opens an alert's card: who offers what, when it lapses, Accept and Decline.
func open_offer_card(id: String) -> void:
	open_offer = id
	offer_card.visible = true
	if shown_sim != null: _refresh_offer_alerts(shown_sim)
	_layout()

func close_offer_card() -> void:
	open_offer = ""
	offer_card.visible = false
	offer_buttons.clear()
	_layout()

func set_class_overlay_visible(value: bool) -> void:
	class_overlay_button.set_pressed_no_signal(value)
	class_legend.visible = value
	if value and shown_sim != null:
		_refresh_class_legend(shown_sim)
	_layout()
	call_deferred("_layout")

func _lock_icon() -> Texture2D:
	if lock_texture == null:
		var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"18\" viewBox=\"0 0 16 18\"><path d=\"M4 8 V5.5 a4 4 0 0 1 8 0 V8\" stroke=\"#d6c288\" stroke-width=\"2\" fill=\"none\"/><rect x=\"2\" y=\"8\" width=\"12\" height=\"9\" rx=\"2\" fill=\"#d6c288\"/></svg>"
		var image := Image.new()
		image.load_svg_from_string(svg,1.0)
		lock_texture = ImageTexture.create_from_image(image)
	return lock_texture

## A padlock row under a Treasury lever, hidden until a pledge covers it.
## Returns its label; the row is the label's parent.
func _lock_row(parent: Control) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	row.visible = false
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.texture = _lock_icon()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(icon)
	var label := _label("",13)
	label.add_theme_color_override("font_color",Color("d6c288"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300,0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return label

## Disables the lever's steps a running pledge forbids and shows the padlock
## with the pledges' names.
func _lock_lever(sim, lever: String, value: int, buttons: Dictionary, label: Label) -> void:
	var reasons: Array[String] = []
	for step in buttons:
		var reason: String = sim.factions.forbids(sim,lever,value + int(step))
		buttons[step].tooltip_text = reason
		if not reason.is_empty():
			buttons[step].disabled = true
			if reason not in reasons:
				reasons.append(reason)
	var text := "\n".join(reasons)
	var row: Control = label.get_parent()
	if label.text != text or row.visible != not reasons.is_empty():
		label.text = text
		row.visible = not reasons.is_empty()
		_layout()

func _signed(value: int) -> String:
	return "+%d" % value if value > 0 else ("−%d" % -value if value < 0 else "0")

## The Factions button appears with the first faction; offers show as alerts;
## the panel refreshes while it is open.
func _refresh_factions(sim) -> void:
	var f = sim.factions
	var shares: Dictionary = f.shares(sim)
	var tips: Array[String] = ["Factions"]
	for id in f.coffers:
		tips.append("%s  %d%%  ·  favour %s" % [sim.db.factions[id].name,int(shares.get(id,0)),_signed(int(f.favour[id]))])
	factions_button.tooltip_text = "\n".join(tips)
	var changed: bool = factions_button.visible == f.coffers.is_empty()
	factions_button.visible = not f.coffers.is_empty()
	if class_legend.visible:
		_refresh_class_legend(sim)
	changed = _refresh_offer_alerts(sim) or changed
	if factions_menu.visible:
		_refresh_power(sim,shares)
		var text := _faction_text(sim,shares)
		if faction_text.text != text:
			faction_text.text = text
			changed = true
		changed = _refresh_deals(sim) or changed
	if changed:
		_layout()
		# New cards report their size only once their containers have sorted.
		call_deferred("_layout")

func _refresh_power(sim, shares: Dictionary) -> void:
	var silver: Dictionary = sim.factions.power(sim)
	var keys: Array = ["crown"]
	keys.append_array(sim.factions.coffers.keys())
	keys.append("unaligned")
	if power_segments.keys() != keys:
		for child in power_bar.get_children():
			power_bar.remove_child(child)
			child.queue_free()
		power_segments.clear()
		for key in keys:
			var segment := ColorRect.new()
			segment.color = Color.html(_holder_colour(sim,key))
			segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			segment.mouse_filter = Control.MOUSE_FILTER_PASS
			power_bar.add_child(segment)
			power_segments[key] = segment
	for key in keys:
		var segment: ColorRect = power_segments[key]
		var value: int = maxi(0,int(silver.get(key,0)))
		segment.visible = value > 0
		segment.size_flags_stretch_ratio = maxf(float(value),0.001)
		segment.tooltip_text = "%s: %s (%d%%)%s" % [_holder_name(sim,key),Economy.format(value),int(shares.get(key,0)),
			"\nHousehold savings no faction has won" if key == "unaligned" else ""]

func _holder_colour(sim, key: String) -> String:
	if key == "crown":
		return CROWN_COLOUR
	if key == "unaligned":
		return UNALIGNED_COLOUR
	return str(sim.db.factions[key].colour)

func _holder_name(sim, key: String) -> String:
	if key == "crown":
		return "Crown"
	if key == "unaligned":
		return "Unaligned"
	return str(sim.db.factions[key].name)

## One row per faction: power, and favour heading for its target. An open row
## adds its band and coffers, the stance terms behind the target, and its
## silver in and out last payday.
func _faction_text(sim, shares: Dictionary) -> String:
	var f = sim.factions
	var lines: Array[String] = []
	for id in f.coffers:
		var row: Dictionary = sim.db.factions[id]
		var share: int = int(shares.get(id,0))
		var favour: int = int(f.favour[id])
		var target: int = f.target(sim,id)
		var open: bool = expanded_factions.has(id)
		lines.append("[url=%s][color=#868f7a]%s[/color] [color=#%s][b]%s[/b][/color][/url]  %d%%  ·  favour %s %s" % [id,"▾" if open else "▸",row.colour,row.name,share,_signed(favour),
			"" if target == favour else "[color=#868f7a]%s %s[/color]" % ["↑" if target > favour else "↓",_signed(target)]])
		if not open:
			continue
		lines.append("[color=#a9b39a]    %s power  ·  coffers %s[/color]" % [BAND_NAMES[Factions.band(share)].capitalize(),Economy.format(int(f.coffers[id]))])
		var terms: Array[String] = []
		var stance: Dictionary = f.stance_terms(sim,id)
		for term in stance:
			if int(stance[term]) != 0:
				terms.append("%s %s" % [TERM_NAMES.get(term,term),_signed(int(stance[term]))])
		lines.append("[color=#a9b39a]    %s[/color]" % (", ".join(terms) if not terms.is_empty() else "Nothing moves its favour yet"))
		var flows: Array[String] = []
		var last: Dictionary = f.last_payday[id]
		for key in Factions.FLOW_KEYS:
			if int(last[key]) > 0:
				flows.append("%s %s" % [FLOW_NAMES[key],Economy.format(int(last[key]))])
		if not flows.is_empty():
			lines.append("[color=#868f7a]    Last payday: %s[/color]" % ", ".join(flows))
	return "\n".join(lines)

## One alert per open offer on the left edge, its clock showing the time left,
## and the open alert's card. Returns whether an alert came or went.
func _refresh_offer_alerts(sim) -> bool:
	var f = sim.factions
	var lifetime := float(Factions.OFFER_EXPIRY * sim.PAYDAY_TICKS)
	var changed := false
	for id in offer_alerts_by_id.keys():
		if f.offers.get(id,{}).is_empty():
			var alert: Control = offer_alerts_by_id[id]
			alert.visible = false
			alert.queue_free()
			offer_alerts_by_id.erase(id)
			changed = true
	for id in f.offers:
		var offer: Dictionary = f.offers[id]
		if offer.is_empty():
			continue
		var row: Dictionary = sim.db.factions[id]
		if not offer_alerts_by_id.has(id):
			var alert := OfferAlert.new()
			alert.colour = Color.html(row.colour)
			alert.tooltip_text = "The %s make an offer" % row.name
			alert.opened.connect(func(): close_offer_card() if open_offer == id else open_offer_card(id))
			offer_alerts.add_child(alert)
			offer_alerts_by_id[id] = alert
			changed = true
		offer_alerts_by_id[id].set_left(float(int(offer.expires) - sim.tick) / lifetime)
	if not open_offer.is_empty() and not offer_alerts_by_id.has(open_offer):
		close_offer_card()
		changed = true
	if not open_offer.is_empty():
		var id := open_offer
		var offer: Dictionary = f.offers[id]
		var row: Dictionary = sim.db.factions[id]
		var paydays: int = ceili(float(maxi(0,int(offer.expires) - sim.tick)) / sim.PAYDAY_TICKS)
		offer_title.text = row.name
		offer_title.add_theme_color_override("font_color",Color.html(row.colour))
		var text := "They offer %s.\n[color=#868f7a]Lapses in %d payday%s if you do not choose.[/color]" % [f.describe(sim,id,offer),paydays,"" if paydays == 1 else "s"]
		if offer_text.text != text:
			offer_text.text = text
			changed = true
		# Placing the hall near the house is what accepts an organising offer.
		var organise: bool = offer.type == "organise"
		offer_accept.disabled = organise
		offer_accept.text = "Place the hall to accept" if organise else "Accept"
		offer_accept.tooltip_text = ("Build a %s within %d tiles of the house" % [sim.db.buildings[Factions.hall_for(sim,id)].name.to_lower(),Factions.ORGANISE_TILES]) if organise else "+%d favour with the %s" % [Factions.OFFER_ACCEPTED,row.name]
		offer_decline.tooltip_text = "%s favour with the %s" % [_signed(Factions.OFFER_DECLINED),row.name]
		offer_buttons = {id: {"accept":offer_accept,"decline":offer_decline}}
	return changed

## Running pledges with "Break pledge". Rebuilt only when the pledges or the
## payday change. Returns whether it rebuilt.
func _refresh_deals(sim) -> bool:
	var f = sim.factions
	var signature := JSON.stringify([f.pledges,f.coffers.keys(),sim.tick / sim.PAYDAY_TICKS])
	if signature == deals_signature:
		return false
	deals_signature = signature
	for child in pledge_list.get_children():
		# Hidden at once, freed after the click that may have caused this.
		child.visible = false
		child.queue_free()
	pledge_buttons.clear()
	for id in f.pledges:
		for pledge in f.pledges[id]:
			var row: Dictionary = sim.db.factions[id]
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation",6)
			pledge_list.add_child(line)
			var paydays: int = ceili(float(maxi(0,int(pledge.until) - sim.tick)) / sim.PAYDAY_TICKS)
			var text := _rich_label(14)
			text.custom_minimum_size = Vector2(230,0)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.text = "[color=#%s]%s[/color]: %s  [color=#868f7a]· %d payday%s left[/color]" % [row.colour,row.name,Factions.pledge_text(pledge),paydays,"" if paydays == 1 else "s"]
			line.add_child(text)
			var pledge_id: String = Factions.pledge_id(id,pledge)
			var button := _button("Break pledge")
			button.add_theme_font_size_override("font_size",13)
			button.tooltip_text = "%s favour, and no offers from the %s for %d paydays" % [_signed(Factions.PLEDGE_BROKEN),row.name,Factions.BLOCK_PAYDAYS]
			button.pressed.connect(func(): pledge_broken.emit(pledge_id))
			line.add_child(button)
			pledge_buttons[pledge_id] = button
	if pledge_buttons.is_empty():
		var none := _label("None running",13)
		none.add_theme_color_override("font_color",Color("868f7a"))
		pledge_list.add_child(none)
	return true

## Who owns a building that factions can own: the Crown or a faction.
func _owner_text(sim, building) -> String:
	if not Building.ownable(building.definition,sim.db):
		return ""
	if building.owner.is_empty():
		return "[b]Owner[/b]  The Crown\n"
	var row: Dictionary = sim.db.factions[building.owner]
	var text := "[b]Owner[/b]  [color=#%s]%s[/color]" % [row.colour,row.name]
	if building.definition.kind == "house":
		text += "  ·  rent %s per payday" % Economy.format(Factions.rent(sim,building.owner,building.tier))
	return text + "\n"

## A house's class, alignment and the pulls on it (FACTIONS.md §3.1).
func _class_text(sim, house) -> String:
	var house_class: String = sim.db.tiers[house.tier].get("class","")
	if house_class.is_empty():
		return "[b]Class[/b]  none  ·  [color=#868f7a]%s are too poor to organise[/color]\n" % sim.db.tiers[house.tier].name
	var text := "[b]Class[/b]  %s class  ·  " % house_class.capitalize()
	if house.aligned.is_empty():
		text += "[color=#%s]Unaligned[/color]" % UNALIGNED_COLOUR
	else:
		var aligned: Dictionary = sim.db.factions[house.aligned]
		text += "[color=#%s]%s[/color]" % [aligned.colour,aligned.name]
	var pulls: Dictionary = sim.factions.last_pulls(house)
	if pulls.is_empty():
		return text + "\n[color=#868f7a]Pulls are counted at the next payday[/color]\n"
	var parts: Array[String] = []
	for id in pulls:
		parts.append("%s %d" % [str(sim.db.factions[id].name).to_lower(),int(pulls[id])])
	text += "\n[b]Pull[/b]  " + ", ".join(parts)
	var paydays: int = Factions.paydays_to_change(house)
	if paydays >= 0:
		text += "  ·  %s the %s in %d payday%s" % ["joins" if house.aligned.is_empty() else "goes over to",str(sim.db.factions[house.pull_leader].name).to_lower(),paydays,"" if paydays == 1 else "s"]
	return text + "\n"

func _hall_text(sim, hall) -> String:
	var id: String = hall.definition.recruits_for
	var faction: Dictionary = sim.db.factions[id]
	var reached := 0
	for house in sim.buildings.values():
		if house.definition.kind == "house" and Factions.hall_in_reach(sim,house,id):
			reached += 1
	var text := "\n[b]Recruits for[/b]  [color=#%s]%s[/color]\n" % [faction.colour,faction.name]
	text += "[b]Reach[/b]  %d road tiles  ·  %d house%s within it\n" % [int(hall.definition.radius),reached,"" if reached == 1 else "s"]
	text += "[color=#868f7a]Working-class houses in reach lean toward the %s. The Classes overlay shows who has joined.[/color]" % str(faction.name).to_lower()
	return text

## "Offer for sale" lists a bid from each present buyer for a Crown building:
## its price at the buyer's favour, or why it cannot be sold.
func _refresh_sale(sim, building) -> void:
	var row: Dictionary = building.definition
	if building.uid != sale_uid:
		sale_uid = building.uid
		sale_button.set_pressed_no_signal(false)
	var buyers: Array = []
	for id in row.get("buyers",[]):
		if sim.factions.present(id):
			buyers.append(id)
	sale_button.visible = building.owner.is_empty() and Building.ownable(row,sim.db) and not buyers.is_empty()
	sale_list.visible = sale_button.visible and sale_button.button_pressed
	if not sale_list.visible:
		return
	var lock: String = sim.factions.forbids(sim,"house_sale") if row.kind == "house" else ""
	var prices: Array = []
	for id in buyers:
		prices.append([id,sim.factions.sale_price(sim,building,id),int(sim.factions.coffers[id])])
	var signature := JSON.stringify([building.uid,lock,prices])
	if signature == sale_signature:
		return
	sale_signature = signature
	for child in sale_list.get_children():
		child.visible = false
		child.queue_free()
	sale_buttons.clear()
	for entry in prices:
		var faction: Dictionary = sim.db.factions[entry[0]]
		var button := _button("Sell to the %s for %s" % [faction.name,Economy.format(int(entry[1]))])
		button.add_theme_font_size_override("font_size",13)
		button.disabled = not lock.is_empty() or int(entry[2]) < int(entry[1])
		if not lock.is_empty():
			button.tooltip_text = lock
		elif button.disabled:
			button.tooltip_text = "The %s hold only %s" % [faction.name,Economy.format(int(entry[2]))]
		else:
			button.tooltip_text = "The treasury gains %s; the %s gain +%d favour%s" % [Economy.format(int(entry[1])),faction.name,Factions.BUYER_PLEASED,"; the unions resent it" if row.kind == "house" else ""]
		var id: String = entry[0]
		button.pressed.connect(func(): sale_requested.emit(id))
		sale_list.add_child(button)
		sale_buttons[id] = button
	_layout()

## Swatch and name per colour; what the marks mean is in the key's tooltip.
func _refresh_class_legend(sim) -> void:
	var lines: Array[String] = ["[b]Classes[/b]  [color=#868f7a]F5[/color]",_swatch(UNALIGNED_COLOUR,"Unaligned")]
	for id in sim.db.factions:
		if sim.db.factions[id].recruits and sim.factions.present(id):
			lines.append(_swatch(sim.db.factions[id].colour,sim.db.factions[id].name))
	var text := "\n".join(lines)
	if class_legend_text.text != text:
		class_legend_text.text = text
		_layout()

func _swatch(colour: String, label: String) -> String:
	return "[color=#%s]■[/color] %s" % [colour,label]

func set_operations_overlay_visible(value: bool) -> void:
	operations_overlay_button.set_pressed_no_signal(value)
	operations_legend.visible = value
	_layout()
	call_deferred("_layout")

func set_food_overlay_visible(value: bool) -> void:
	food_overlay_button.set_pressed_no_signal(value)
	food_legend.visible = value
	_layout()
	call_deferred("_layout")

## Food balance colours: enough, living off stores, short, and still measuring.
const FOOD_COLOURS := {"surplus": "93d46b", "stores": "f0b43c", "deficit": "f2694f", "measuring": "b9b3a1"}

## The food chip and its breakdown panel (sim/food_report.gd).
func _build_food_menu() -> void:
	food_button = _button("")
	food_button.toggle_mode = true
	# Slim, so the chip sits in the resource bar at the gold counter's height.
	for state in ["normal","hover","pressed","hover_pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0,0,0,0) if state in ["normal","focus"] else Color(0.28,0.33,0.22,0.9)
		style.set_corner_radius_all(4)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		food_button.add_theme_stylebox_override(state,style)
	food_button.add_theme_constant_override("h_separation",5)
	food_button.icon = _svg_texture(FileAccess.get_file_as_string("res://view/overlays/food.svg"))
	food_button.add_theme_font_size_override("font_size",15)
	food_button.pressed.connect(_toggle_food_menu)
	root.add_child(food_button)
	food_menu = _panel()
	food_menu.visible = false
	root.add_child(food_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	column.custom_minimum_size = Vector2(380,0)
	food_menu.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("Food",20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := _button("×")
	close.tooltip_text = "Close the food breakdown"
	close.pressed.connect(close_food_menu)
	header.add_child(close)
	food_verdict = _rich_label(15)
	food_verdict.custom_minimum_size = Vector2(380,0)
	column.add_child(food_verdict)
	# Food made against what the houses need: full when made covers needed.
	food_bar = ProgressBar.new()
	food_bar.custom_minimum_size = Vector2(0,10)
	food_bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color("2d3328")
	background.set_corner_radius_all(4)
	food_bar.add_theme_stylebox_override("background",background)
	food_bar_fill = StyleBoxFlat.new()
	food_bar_fill.set_corner_radius_all(4)
	food_bar.add_theme_stylebox_override("fill",food_bar_fill)
	column.add_child(food_bar)
	food_text = _rich_label(14)
	food_text.custom_minimum_size = Vector2(380,0)
	column.add_child(food_text)

func _toggle_food_menu() -> void:
	food_menu.visible = not food_menu.visible
	food_button.button_pressed = food_menu.visible
	if food_menu.visible:
		close_options_menu()
		close_build_menu()
		close_weather_menu()
		close_treasury_menu()
		close_factions_menu()
		if shown_sim != null: _refresh_food(shown_sim)
		food_menu_opened.emit()
	_layout()

func close_food_menu() -> void:
	food_menu.visible = false
	food_button.button_pressed = false
	_layout()

## Samples the meter, then shows food stored and the balance on the chip: food
## made (plus spare capacity waiting on storage) less what the houses need, per
## minute.
func _refresh_food(sim) -> void:
	food_meter.sample(sim)
	var report: Dictionary = food_meter.report(sim)
	# A short need shows its shortfall even if another need has food to spare.
	var net: float = -float(report.short) if report.state in ["stores","deficit"] else float(report.usable) - float(report.required)
	var text := "%d  %s" % [food_total,"—" if report.state == "measuring" else "%s%.1f/min" % ["+" if net >= 0.0 else "−", absf(net)]]
	var colour := Color(FOOD_COLOURS[report.state])
	if food_button.text != text or food_button.get_theme_color("font_color") != colour:
		food_button.text = text
		for key in ["font_color","font_pressed_color","font_hover_color","font_focus_color","font_hover_pressed_color"]:
			food_button.add_theme_color_override(key, colour)
		_layout()
	if food_menu.visible:
		var verdict := _food_verdict(report)
		var body := _food_breakdown(report)
		food_bar.visible = report.state != "measuring" and float(report.required) > 0.0
		food_bar.max_value = maxf(0.1,float(report.required))
		food_bar.value = minf(float(report.made),food_bar.max_value)
		food_bar_fill.bg_color = colour
		if food_text.text != body or food_verdict.text != verdict:
			food_verdict.text = verdict
			food_text.text = body
			_layout()

## The verdict, and while measuring nothing else: the numbers would be zeros.
func _food_verdict(report: Dictionary) -> String:
	var colour: String = FOOD_COLOURS[report.state]
	if report.state == "measuring":
		return "[color=#%s]Measuring food over the last two minutes…[/color]" % colour
	var verdict: String = {"surplus": "Enough food for every house", "stores": "Short %.1f/min: living off stored food", "deficit": "Short %.1f/min: houses will go hungry"}[report.state]
	return "[color=#%s][b]%s[/b][/color]\nMade %.1f of %.1f needed per minute" % [colour, (verdict % report.short) if "%" in verdict else verdict, report.made, report.required]

## Stores, needs, and one table of each food with who makes it.
func _food_breakdown(report: Dictionary) -> String:
	var lines: Array[String] = []
	if float(report.required) > 0.0 and report.state != "measuring":
		lines.append("Stored %d food: about %d min" % [report.stored, int(report.minutes_stored)])
	else:
		lines.append("Stored %d food" % report.stored)
	if float(report.usable_spare) > 0.05:
		lines.append("[color=#868f7a]Producers waiting for storehouse room could add %.1f/min[/color]" % report.usable_spare)
	if report.state == "measuring":
		return "\n".join(lines)
	lines.append("")
	lines.append("[b]Needs[/b]  [color=#868f7a]per minute[/color]")
	if report.needs.is_empty():
		lines.append("[color=#868f7a]No houses yet[/color]")
	for need in report.needs:
		var met: bool = float(need.supplied) + 0.05 >= float(need.required) * 0.95
		lines.append("[color=#%s]%s ×%d: %.1f %s, %.1f supplied[/color]" % ["a8c38a" if met else "d98c6f", " and ".join(need.tiers), need.houses, need.required, str(need.name).to_lower(), need.supplied])
	lines.append("")
	var table := "[table=5][cell][color=#868f7a]Food   [/color][/cell][cell][color=#868f7a]Made   [/color][/cell][cell][color=#868f7a]Eaten   [/color][/cell][cell][color=#868f7a]Stored   [/color][/cell][cell][color=#868f7a]Made by[/color][/cell]"
	var any_source := false
	for row in report.goods:
		if float(row.made) <= 0.0 and float(row.eaten) <= 0.0 and int(row.stored) == 0 and row.sources.is_empty():
			continue
		var makers: Array[String] = []
		for source in row.sources:
			any_source = true
			var idle := 0
			for status in source.idle:
				idle += int(source.idle[status])
			makers.append("%s ×%d%s" % [source.name, source.count, "" if idle == 0 else " [color=#d98c6f]%d idle[/color]" % idle])
		table += "[cell]%s   [/cell][cell]%.1f[/cell][cell]%.1f[/cell][cell]%d[/cell][cell]%s[/cell]" % [row.name, row.made, row.eaten, row.stored, ", ".join(makers) if not makers.is_empty() else "[color=#868f7a]—[/color]"]
	lines.append(table + "[/table]")
	if not any_source:
		lines.append("[color=#868f7a]No food producers yet: build a forager, hunter, fisher or berry bushes[/color]")
	return "\n".join(lines)

## Jobs by class and the families who fill them (docs/PLAN-job-classes.md).
func _class_label(job_class: String) -> String:
	return {"middle":"middle-class", "elite":"wealthy"}.get(job_class, "working-class")

func _house_label(sim, uid: int) -> String:
	var house = sim.buildings.get(uid)
	if house == null:
		return "the founders"
	return "%s at (%d, %d)" % [house.definition.name, house.cell.x, house.cell.y]

## Which families a workplace's workers come from.
func _families_line(sim, building) -> String:
	var counts := {}
	for uid in building._crew:
		counts[uid] = int(counts.get(uid, 0)) + 1
	var parts: Array[String] = []
	for uid in counts:
		parts.append(_house_label(sim, uid) + (" ×%d" % counts[uid] if counts[uid] > 1 else ""))
	return "Families: %s\n" % ", ".join(parts) if not parts.is_empty() else ""

## Any job no free family of its class can fill.
func _crew_warnings(building) -> String:
	var text := ""
	if building.workers_enabled and not building.staffed:
		for job_class in Labour.jobs(building.definition):
			if Labour.rank(job_class) > 1:
				text += "[color=#d98c6f]Needs a %s family for its %s job[/color]\n" % [_class_label(job_class), _class_label(job_class)]
	return text

## A house's family on one line: working adults, children and their jobs.
## Wages follow the jobs, so a family with none earns nothing.
func _family_line(sim, house) -> String:
	var adults: int = Labour.adults(sim, house)
	# The founding adults live in the first house.
	var first := true
	for other in sim.buildings.values():
		if other.definition.kind == "house" and other.uid < house.uid:
			first = false
	if first:
		adults += Labour.FOUNDERS
	var children: int = sim.family_children(house) if sim.has_method("family_children") else 0
	var held: Array[String] = []
	for building in sim.buildings.values():
		if building.definition.kind == "storehouse" and building._keeper == house.uid:
			held.append("Storekeeper")
		for uid in building._crew:
			if uid == house.uid:
				held.append("Carrier" if building.definition.kind == "storehouse" else str(building.definition.name))
	var family := "%d adult%s%s" % [adults, "" if adults == 1 else "s", (", %d child%s" % [children, "" if children == 1 else "ren"]) if children > 0 else ""]
	if held.is_empty():
		return "[b]Family[/b]  %s  [color=#d98c6f]no one in work, so no wages[/color]\n" % family
	var tally := {}
	for name in held:
		tally[name] = int(tally.get(name, 0)) + 1
	var parts: Array[String] = []
	for name in tally:
		parts.append(name + (" ×%d" % tally[name] if tally[name] > 1 else ""))
	return "[b]Family[/b]  %s\n[b]Jobs[/b]  %s\n" % [family, ", ".join(parts)]

## An open offer's alert on the left edge: a "!" over a faint clock face whose
## wedge is the time left before the offer lapses unanswered.
class OfferAlert extends Control:
	signal opened
	var colour := Color.WHITE
	## Share of the offer's life still to run, 1 when made, 0 when it lapses.
	var left := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(52,52)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_left(value: float) -> void:
		value = clampf(value,0.0,1.0)
		if absf(value - left) > 0.002:
			left = value
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			opened.emit()
			accept_event()

	func _draw() -> void:
		var centre := size / 2.0
		var radius := minf(size.x,size.y) / 2.0 - 2.0
		draw_circle(centre,radius,Color(0.105,0.14,0.11,0.96))
		# The time left, sweeping clockwise from twelve and shrinking back to it.
		if left > 0.0:
			var points := PackedVector2Array([centre])
			var steps := maxi(2,int(ceil(48.0 * left)))
			for step in steps + 1:
				var angle := -PI / 2.0 + TAU * left * float(step) / float(steps)
				points.append(centre + Vector2(cos(angle),sin(angle)) * (radius - 3.0))
			draw_colored_polygon(points,Color(colour,0.3))
		for hour in 12:
			var direction := Vector2.from_angle(TAU * hour / 12.0)
			draw_line(centre + direction * (radius - 7.0),centre + direction * (radius - 3.0),Color(1,1,1,0.16),1.0,true)
		draw_arc(centre,radius,0.0,TAU,48,colour,2.0,true)
		var font := get_theme_default_font()
		var font_size := 26
		var width := font.get_string_size("!",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var baseline := centre.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
		draw_string(font,Vector2(centre.x - width / 2.0,baseline),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("f0e2bc"))
