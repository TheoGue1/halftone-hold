extends Node
## Builds the scene: world + passive web (layer 0), halftone pass (layer 1), crisp UI (layer 2).

const WorldScript := preload("res://scripts/world.gd")
const TreeViewScript := preload("res://scripts/tree_view.gd")
const ReliquaryScript := preload("res://scripts/reliquary_page.gd")
const VaultScript := preload("res://scripts/vault_page.gd")
const ChapelScript := preload("res://scripts/chapel_page.gd")
const HALFTONE := preload("res://shaders/halftone.gdshader")
const HALFTONE_UI := preload("res://shaders/halftone_ui.gdshader")
const FONT_GARAMOND := preload("res://fonts/EBGaramond.ttf")
const FONT_CAPS := preload("res://fonts/IMFeENsc28P.ttf")

const INK := Color(0.14, 0.09, 0.06)
const PARCH := Color(0.96, 0.92, 0.82)
const WAX := Color(0.62, 0.08, 0.06)
const FADED := Color(0.45, 0.4, 0.34)
const UI_REFRESH := 0.1
const MAX_FLOATERS := 40
const DEV_SPEEDS := [1, 10, 25, 100]
const HALFTONE_CELL := 4.0  # finest screen the shader prints cleanly
const KIND_NAMES := ["Minor", "Notable", "Keystone", "Origin"]

var body_font: FontVariation
var world: WorldScript
var web: TreeViewScript
var halftone: ShaderMaterial
var root: Control
var pages := {}
var tax_area: Control
var levy_label: Label
var hint_label: Label
var gold_label: Label
var gps_label: Label
var renown_label: Label
var rows: Array[Button] = []
var crusade_btn: Button
var crusade_info: Label
var dynasty_btn: Button
var dynasty_info: Label
var points_label: Label
var tooltip: PanelContainer
var tooltip_label: RichTextLabel
var chronicle_label: RichTextLabel
var oath_label: RichTextLabel
var advisor_rows: Array = []  # [advisor dict, CheckButton, Label]
var buff_label: Label
var season_label: Label
var map_panel: PanelContainer
var map_canvas: Control
var dest_buttons := {}
var tab_buttons := {}
var buy_buttons := {}
var repeat_btn: Button
var oath_row: HBoxContainer
var preset_row: HBoxContainer
var rebuild_btn: Button
var _holding := false
var _hold_acc := 0.0
var oath_pick: OptionButton
var oath_info: Label
var toasts: VBoxContainer
var floaters: Control
var dynasty_confirm: ConfirmationDialog
var victory_panel: PanelContainer
var victory_label: Label
var _refresh := 0.0


func _ready() -> void:
	var ts := TextServerManager.get_primary_interface()
	body_font = FontVariation.new()
	body_font.base_font = FONT_GARAMOND
	# Lining, tabular figures: counters must not wobble or read as old-style digits.
	body_font.opentype_features = {ts.name_to_tag("lnum"): 1, ts.name_to_tag("tnum"): 1}
	body_font.variation_opentype = {ts.name_to_tag("wght"): 500}
	world = WorldScript.new()
	add_child(world)
	web = TreeViewScript.new()
	web.font = FONT_CAPS
	web.visible = false
	add_child(web)
	web.hovered.connect(_on_web_hover)

	var fx := CanvasLayer.new()
	fx.layer = 1
	add_child(fx)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halftone = ShaderMaterial.new()
	halftone.shader = HALFTONE
	rect.material = halftone
	fx.add_child(rect)

	var ui := CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	var ui_ink := ShaderMaterial.new()
	ui_ink.shader = HALFTONE_UI
	ui_ink.set_shader_parameter("cell", HALFTONE_CELL)
	root.material = ui_ink
	# Every menu node, including ones created later (rows, toasts, floaters), prints with the root's inks.
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is CanvasItem and root.is_ancestor_of(n):
			n.use_parent_material = true)
	ui.add_child(root)
	_build_ui()

	Game.levied.connect(_on_levied)
	Game.achievement_unlocked.connect(func(title: String) -> void:
		_toast("Achievement — %s  (+%d%% gold)" % [title, int(Game.ACH_BONUS * 100)])
		for adv in Content.ADVISORS:
			if Game.achieved.size() == adv.deeds:
				_toast("%s joins your court. Enable them in the Court tab." % adv.name))
	Game.offline_report.connect(func(sec: float, earned: float) -> void:
		_toast("While you were away (%s) your stewards gathered %s gold." % [Game.fmt_time(sec), Game.fmt(earned)]))
	Game.prestiged.connect(_on_prestiged)
	Game.victory.connect(_show_victory)
	Game.omen_spawned.connect(func(kind: String) -> void:
		world.spawn_omen(kind)
		_toast("An omen! %s — click it in the Kingdom." % Content.OMENS[kind].name))
	Game.omen_claimed.connect(func(kind: String, text: String) -> void:
		_toast("%s: %s" % [Content.OMENS[kind].name, text]))
	Game.relic_found.connect(func(id: int, level: int) -> void:
		var r: Dictionary = Content.RELICS[id]
		_toast("Relic found: %s (%s), level %d." % [r.name, Content.RARITIES[r.rarity].name, level])
		world.fanfare())
	Game.oath_kept.connect(func(title: String, n: int) -> void:
		_toast("Oath kept: %s (%d/%d). +%d web points." % [title, n, Content.OATH_MAX, Content.OATH_POINTS]))
	Game.feature_unlocked.connect(func(id: String) -> void:
		for u in Content.UNLOCKS:
			if u.id == id:
				_toast("New: %s. %s" % [u.name, u.desc])
		world.fanfare()
		_refresh_ui())
	Game.window_restored.connect(func(i: int) -> void:
		_toast("The Window of %s is restored! Its Web sector is empowered forever, +%d web points." % [
			PassiveTree.SECTORS[i].name, Chapel.POINTS])
		world.fanfare())
	Game.season_changed.connect(func() -> void:
		if not Game.has("seasons"):
			return
		_toast("%s%s has come. Check the Web for empowered nodes." % [Game.season().name,
			"" if Game.weather().name == "Clear" else " (" + Game.weather().name + ")"]))
	_apply_settings()
	_show_page("kingdom")
	_refresh_ui()


func _process(delta: float) -> void:
	world.area = Rect2(tax_area.global_position, tax_area.size)
	gold_label.text = "%s gold" % Game.fmt(Game.gold)
	_refresh += delta
	if _refresh >= UI_REFRESH:
		_refresh = 0.0
		_refresh_ui()
	if tooltip.visible:
		_place_tooltip()
	if map_panel.visible:
		map_canvas.queue_redraw()
	if _holding and Game.has("hold") and pages.kingdom.visible:
		_hold_acc += delta * Content.HOLD_LEVY_RATE
		while _hold_acc >= 1.0:
			_hold_acc -= 1.0
			Game.levy()


# --- Building ---------------------------------------------------------------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	col.add_child(_build_topbar())

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)
	pages.kingdom = _build_kingdom()
	pages.web = _build_web_page()
	var relics: Control = ReliquaryScript.new()
	relics.caps_font = FONT_CAPS
	relics.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pages.relics = relics
	for p in [["vault", VaultScript], ["chapel", ChapelScript]]:
		var page: Control = p[1].new()
		page.caps_font = FONT_CAPS
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pages[p[0]] = page
	pages.court = _build_court()
	pages.settings = _build_settings()
	for p: Control in pages.values():
		body.add_child(p)

	floaters = Control.new()
	floaters.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	floaters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(floaters)
	toasts = VBoxContainer.new()
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toasts.position += Vector2(20, -20)
	root.add_child(toasts)

	tooltip = PanelContainer.new()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	tooltip.custom_minimum_size.x = 340
	tooltip_label = _rich()
	tooltip.add_child(tooltip_label)
	root.add_child(tooltip)

	dynasty_confirm = ConfirmationDialog.new()
	dynasty_confirm.title = "Found a Dynasty?"
	dynasty_confirm.ok_button_text = "Found it"
	dynasty_confirm.confirmed.connect(func() -> void: Game.dynasty())
	root.add_child(dynasty_confirm)
	_build_victory()
	_build_map()


func _build_topbar() -> Control:
	var bar := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var title := _label("Halftone Hold", 26, WAX)
	title.add_theme_font_override("font", FONT_CAPS)
	row.add_child(title)
	gold_label = _label("", 30)
	gold_label.custom_minimum_size.x = 210
	row.add_child(gold_label)
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_constant_override("separation", -4)
	row.add_child(stats)
	gps_label = _label("", 18, FADED)
	gps_label.clip_text = true
	gps_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stats.add_child(gps_label)
	renown_label = _label("", 18, WAX)
	renown_label.clip_text = true
	renown_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stats.add_child(renown_label)
	var group := ButtonGroup.new()
	for p in [["kingdom", "Kingdom"], ["web", "Web"], ["relics", "Relics"], ["vault", "Vault"], ["chapel", "Chapel"],
			["court", "Court"], ["settings", "Options"]]:
		var b := Button.new()
		b.text = p[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = p[0] == "kingdom"
		b.pressed.connect(_show_page.bind(p[0]))
		b.add_theme_font_size_override("font_size", 18)
		for st in [["normal", Color(0.9, 0.84, 0.7)], ["hover", Color(0.97, 0.9, 0.74)], ["pressed", WAX],
				["hover_pressed", WAX.lightened(0.1)]]:
			var box := _box(st[1], 2)
			box.content_margin_left = 7
			box.content_margin_right = 7
			b.add_theme_stylebox_override(st[0], box)
		row.add_child(b)
		tab_buttons[p[0]] = b
	return bar


func _build_kingdom() -> Control:
	var page := HBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tax_area = Control.new()
	tax_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tax_area.mouse_filter = Control.MOUSE_FILTER_STOP
	tax_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tax_area.gui_input.connect(_on_tax_input)
	page.add_child(tax_area)
	levy_label = _outlined(_label("", 24))
	levy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tax_area.add_child(levy_label)
	buff_label = _outlined(_label("", 20, WAX))
	buff_label.position = Vector2(16, 10)
	tax_area.add_child(buff_label)
	hint_label = _outlined(_label("Press the Royal Seal to levy taxes", 26, WAX))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tax_area.add_child(hint_label)

	var side := PanelContainer.new()
	side.custom_minimum_size.x = 440
	page.add_child(side)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	side.add_child(v)
	var head := HBoxContainer.new()
	var h := _label("Holdings", 24)
	h.add_theme_font_override("font", FONT_CAPS)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	var group := ButtonGroup.new()
	for amt in [1, 10, 100, -1]:
		var b := Button.new()
		b.text = "Max" if amt < 0 else "×%d" % amt
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Game.buy_amount == amt
		b.pressed.connect(func() -> void: Game.buy_amount = amt)
		head.add_child(b)
		buy_buttons[amt] = b
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in Game.BUILDINGS.size():
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 58
		b.pressed.connect(_on_buy.bind(i))
		list.add_child(b)
		rows.append(b)
	v.add_child(HSeparator.new())
	crusade_btn = Button.new()
	crusade_btn.custom_minimum_size.y = 44
	crusade_btn.pressed.connect(func() -> void:
		if Game.has("map"):
			_open_map()
		else:
			Game.crusade("holy", ""))
	v.add_child(crusade_btn)
	crusade_info = _label("", 16, FADED)
	crusade_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(crusade_info)
	repeat_btn = Button.new()
	repeat_btn.pressed.connect(func() -> void: Game.crusade(Game.last_dest, Game.last_oath))
	v.add_child(repeat_btn)
	dynasty_btn = Button.new()
	dynasty_btn.custom_minimum_size.y = 44
	dynasty_btn.pressed.connect(_ask_dynasty)
	v.add_child(dynasty_btn)
	dynasty_info = _label("", 16, FADED)
	dynasty_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(dynasty_info)
	return page


func _build_web_page() -> Control:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 320
	page.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	points_label = _label("", 24, WAX)
	points_label.add_theme_font_override("font", FONT_CAPS)
	v.add_child(points_label)
	var search := LineEdit.new()
	search.placeholder_text = "Search the web (e.g. dragon, renown)"
	search.text_changed.connect(web.set_search)
	v.add_child(search)
	var buttons := HBoxContainer.new()
	var recenter := Button.new()
	recenter.text = "Recenter"
	recenter.pressed.connect(web.recenter)
	buttons.add_child(recenter)
	var reset := Button.new()
	reset.text = "Refund all"
	reset.pressed.connect(Game.reset_tree)
	buttons.add_child(reset)
	v.add_child(buttons)
	var quick := HBoxContainer.new()
	var auto := Button.new()
	auto.text = "Auto-spend"
	auto.tooltip_text = "Spend every free point: toward your search matches if you searched,\notherwise notables and empowered sectors first. Never takes keystones."
	auto.pressed.connect(func() -> void:
		var n := Game.auto_spend(web.search_hits())
		_toast("Allocated %d nodes." % n))
	quick.add_child(auto)
	rebuild_btn = Button.new()
	rebuild_btn.text = "Rebuild last web"
	rebuild_btn.tooltip_text = "Re-allocate the layout you had before your last dynasty."
	rebuild_btn.pressed.connect(func() -> void: Game.rebuild_layout(Game.last_layout))
	quick.add_child(rebuild_btn)
	v.add_child(quick)
	preset_row = HBoxContainer.new()
	for i in 2:
		for save in [true, false]:
			var pb := Button.new()
			pb.text = ("Save " if save else "Load ") + ["I", "II"][i]
			pb.tooltip_text = "Web layout %s" % ["I", "II"][i]
			pb.pressed.connect(func() -> void:
				if save:
					Game.save_preset(i)
					_toast("Web layout %s saved." % ["I", "II"][i])
				else:
					Game.load_preset(i))
			preset_row.add_child(pb)
	v.add_child(preset_row)
	season_label = _label("", 16, WAX)
	season_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(season_label)
	var hint := _label("Click: allocate the path to a node\nRight-click: refund   Drag: pan   Wheel: zoom", 16, FADED)
	v.add_child(hint)
	return page


func _build_court() -> Control:
	var page := HBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 10)
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 540
	page.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(_heading("The Royal Court"))
	for a in Content.ADVISORS:
		var cb := CheckButton.new()
		cb.text = a.name
		cb.button_pressed = Game.advisors.get(a.id, false)
		cb.toggled.connect(func(on: bool) -> void: Game.advisors[a.id] = on)
		v.add_child(cb)
		var d := _label("", 16, FADED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		advisor_rows.append([a, cb, d])
	v.add_child(HSeparator.new())
	v.add_child(_heading("Oaths"))
	oath_label = _rich()
	oath_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(oath_label)
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(right)
	var scroll2 := ScrollContainer.new()
	scroll2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll2)
	chronicle_label = _rich()
	chronicle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll2.add_child(chronicle_label)
	return page


func _refresh_court() -> void:
	for row in advisor_rows:
		var a: Dictionary = row[0]
		var unlocked := Game.advisor_unlocked(a)
		row[1].disabled = not unlocked
		row[2].text = a.desc if unlocked else "%s  Joins your court at %d deeds (you have %d)." % [
			a.desc, a.deeds, Game.achieved.size()]
	var s := "Swear an oath when you set out on a crusade. Keep it by coming home from the next crusade " \
		+ "with enough Renown. Each kept oath grants +%d web points and ×%s gold, forever.\n\n" % [
			Content.OATH_POINTS, str(Content.OATH_GOLD)]
	for o in Content.OATHS:
		var kept: int = Game.oaths.get(o.id, 0)
		s += "[color=#8f1209]%s[/color]  %d / %d\n%s\n" % [o.name, kept, Content.OATH_MAX, o.desc]
		if kept < Content.OATH_MAX:
			s += "[color=#6b6052]Next: a crusade worth %s Renown while sworn.[/color]\n" % Game.fmt(Game.oath_goal(o.id))
		s += "\n"
	if Game.run_oath != "":
		s += "[b]Sworn this run: %s[/b]" % Game.oath(Game.run_oath).name
	oath_label.text = s
	chronicle_label.text = _chronicle_text()


func _build_map() -> void:
	map_panel = PanelContainer.new()
	map_panel.visible = false
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	map_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(map_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	map_panel.add_child(v)
	v.add_child(_heading("Choose your Crusade"))
	map_canvas = Control.new()
	map_canvas.custom_minimum_size = Vector2(780, 380)
	map_canvas.draw.connect(_draw_map)
	v.add_child(map_canvas)
	for d in Content.DESTINATIONS:
		var b := Button.new()
		b.pressed.connect(_embark.bind(d.id))
		map_canvas.add_child(b)
		dest_buttons[d.id] = b
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	oath_row = HBoxContainer.new()
	oath_row.add_theme_constant_override("separation", 12)
	row.add_child(oath_row)
	oath_row.add_child(_label("Swear an oath for the next run:", 18))
	oath_pick = OptionButton.new()
	oath_pick.item_selected.connect(func(_i: int) -> void: _refresh_map())
	oath_row.add_child(oath_pick)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var cancel := Button.new()
	cancel.text = "Stay home"
	cancel.pressed.connect(map_panel.hide)
	row.add_child(cancel)
	oath_info = _label("", 16, FADED)
	oath_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	oath_info.custom_minimum_size.x = 780
	v.add_child(oath_info)


func _open_map() -> void:
	oath_pick.clear()
	oath_pick.add_item("No oath")
	for o in Content.OATHS:
		oath_pick.add_item("%s (%d/%d)" % [o.name, Game.oaths.get(o.id, 0), Content.OATH_MAX])
		oath_pick.set_item_disabled(oath_pick.item_count - 1, not Game.can_swear(o.id))
	oath_pick.select(0)
	_refresh_map()
	map_panel.show()


func _picked_oath() -> String:
	return "" if oath_pick.selected <= 0 else Content.OATHS[oath_pick.selected - 1].id


func _refresh_map() -> void:
	for d in Content.DESTINATIONS:
		var b: Button = dest_buttons[d.id]
		if Game.destination_unlocked(d):
			b.text = "%s\n+%s Renown" % [d.name, Game.fmt(Game.destination_gain(d))]
			b.disabled = false
		else:
			b.text = "%s\nLocked: %s" % [d.name, "found a dynasty" if Game.dynasties < d.need_dyn
				else "%s Renown" % Game.fmt(d.need_renown)]
			b.disabled = true
		b.tooltip_text = d.desc
		b.reset_size()
		b.position = d.pos * map_canvas.custom_minimum_size - b.size / 2.0
	var id := _picked_oath()
	oath_info.text = "Hover a destination for its spoils." if id == "" else "%s Keep it: a crusade worth %s Renown." % [
		Game.oath(id).desc, Game.fmt(Game.oath_goal(id))]


func _embark(dest_id: String) -> void:
	if Game.crusade(dest_id, _picked_oath()):
		map_panel.hide()


func _draw_map() -> void:
	var c := map_canvas
	var s := c.size
	var t := Time.get_ticks_msec() / 1000.0
	c.draw_rect(Rect2(Vector2.ZERO, s), Color(0.72, 0.84, 0.88))
	for k in 6:
		var y := s.y * (0.1 + k * 0.16) + sin(t + k) * 3.0
		c.draw_arc(Vector2(s.x * 0.08 + k * 40.0, y), 10, PI * 1.1, PI * 1.9, 8, Color(0.5, 0.65, 0.72), 2.0)
	var land := PackedVector2Array()
	for i in 72:
		var a := i * TAU / 72.0
		var r := 0.43 + 0.06 * sin(a * 3.0 + 1.0) + 0.04 * sin(a * 7.0 + 0.5)
		land.append(s * 0.5 + Vector2(cos(a) * s.x * r, sin(a) * s.y * r * 1.08))
	c.draw_colored_polygon(land, Color(0.93, 0.87, 0.72))
	land.append(land[0])
	c.draw_polyline(land, INK, 2.5)
	var peaks: Vector2 = Content.DESTINATIONS[2].pos * s
	for k in 5:
		var m := peaks + Vector2(-90 + k * 32, 30 + (k % 2) * 14)
		c.draw_colored_polygon(PackedVector2Array([m + Vector2(-18, 0), m + Vector2(0, -34), m + Vector2(18, 0)]),
			Color(0.6, 0.55, 0.5))
	var north: Vector2 = Content.DESTINATIONS[1].pos * s
	for k in 9:
		c.draw_circle(north + Vector2(-80 + k * 22, 40 + (k % 3) * 9), 9, Color(0.35, 0.5, 0.25))
	var silk: Vector2 = Content.DESTINATIONS[3].pos * s
	for k in 4:
		c.draw_arc(silk + Vector2(-120 + k * 36, -6), 16, PI, TAU, 10, Color(0.8, 0.62, 0.3), 3.0)
	var home := Vector2(0.18, 0.55) * s
	c.draw_rect(Rect2(home - Vector2(14, 22), Vector2(28, 22)), Color(0.6, 0.58, 0.55))
	c.draw_colored_polygon(PackedVector2Array([home + Vector2(-18, -22), home + Vector2(18, -22),
		home + Vector2(0, -42)]), WAX)
	for i in Content.DESTINATIONS.size():
		var d: Dictionary = Content.DESTINATIONS[i]
		var end: Vector2 = d.pos * s
		var open := Game.destination_unlocked(d)
		c.draw_dashed_line(home, end, INK if open else FADED, 2.5, 12.0)
		if open:
			var p := home.lerp(end, fposmod(t * 0.12 + i * 0.25, 1.0))
			c.draw_line(p, p + Vector2(0, -22), INK, 2.0)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -22), p + Vector2(16, -17), p + Vector2(0, -12)]), WAX)


func _build_settings() -> Control:
	var page := CenterContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 520
	page.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var h := _label("Settings", 28)
	h.add_theme_font_override("font", FONT_CAPS)
	v.add_child(h)
	var sci := CheckButton.new()
	sci.text = "Scientific notation"
	sci.button_pressed = Game.settings.notation == 1
	sci.toggled.connect(func(on: bool) -> void: Game.settings.notation = 1 if on else 0)
	v.add_child(sci)
	# ponytail: dev-only speed control, not saved; remove (or hide behind a debug build check) before release.
	var speed_row := HBoxContainer.new()
	speed_row.add_child(_label("Dev: game speed", 18, WAX))
	var speed := OptionButton.new()
	for x in DEV_SPEEDS:
		speed.add_item("×%d" % x)
	speed.item_selected.connect(func(i: int) -> void: Engine.time_scale = DEV_SPEEDS[i])
	speed_row.add_child(speed)
	v.add_child(speed_row)
	var save := Button.new()
	save.text = "Save now"
	save.pressed.connect(func() -> void:
		Game.save_game()
		_toast("Chronicle sealed."))
	v.add_child(save)
	var wipe := Button.new()
	wipe.text = "Burn the chronicle (wipe save)"
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Erase all progress forever?"
	confirm.confirmed.connect(Game.wipe)
	v.add_child(confirm)
	wipe.pressed.connect(confirm.popup_centered)
	v.add_child(wipe)
	v.add_child(_label("Fonts: EB Garamond (Georg Duffner, Octavio Pardo) and IM Fell English SC (Igino Marini), SIL OFL.", 14, FADED))
	return page


func _build_victory() -> void:
	victory_panel = PanelContainer.new()
	victory_panel.visible = false
	victory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	victory_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	victory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	victory_panel.custom_minimum_size = Vector2(560, 0)
	root.add_child(victory_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	victory_panel.add_child(v)
	var h := _label("The Infinite Hoard", 40, WAX)
	h.add_theme_font_override("font", FONT_CAPS)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	victory_label = _label("", 20)
	victory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(victory_label)
	var share := Button.new()
	share.text = "Copy my reign to clipboard"
	share.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_victory_brag())
		_toast("Copied. Go boast."))
	v.add_child(share)
	var cont := Button.new()
	cont.text = "Keep ruling"
	cont.pressed.connect(func() -> void: victory_panel.visible = false)
	v.add_child(cont)


# --- Refresh ----------------------------------------------------------------------

func _refresh_ui() -> void:
	_refresh_gates()
	var left := Game.season_time_left()
	var weather: String = Game.weather().name
	gps_label.text = "%s / sec" % Game.fmt(Game.gps())
	if Game.has("seasons"):
		gps_label.text += "   ·   %s%s %d:%02d" % [Game.season().name,
			"" if weather == "Clear" else ", " + weather, int(left / 60.0), int(left) % 60]
	var buffs: PackedStringArray = []
	for k in Game.buffs:
		buffs.append("%s: %s  %ds" % [Content.OMENS[k].name, Content.OMENS[k].desc, int(Game.buffs[k])])
	if Game.run_oath != "":
		buffs.append("Sworn: " + Game.oath(Game.run_oath).name)
	if not Game.run_spoils.is_empty():
		buffs.append("Spoils: " + Game.describe_mods(Game.run_spoils).replace("\n", ", "))
	buff_label.text = "\n".join(buffs)
	season_label.text = "%s empowers %s%s." % [Game.season().name,
		PassiveTree.SECTORS[Game.season().sector].name,
		"" if Game.weather().sector < 0 else "; the %s empowers %s" % [weather.to_lower(),
			PassiveTree.SECTORS[Game.weather().sector].name]]
	var parts: PackedStringArray = []
	if Game.renown > 0.0 or Game.crusades > 0:
		parts.append("Renown %s" % Game.fmt(Game.renown))
	if Game.blood > 0.0:
		parts.append("Royal Blood %s" % Game.fmt(Game.blood))
	renown_label.text = "   ".join(parts)

	var c := world.seal_center() - tax_area.global_position
	levy_label.text = "Levy: %s gold" % Game.fmt(Game.click_value())
	levy_label.size = Vector2(320, 30)
	levy_label.position = c + Vector2(-160, 125)
	hint_label.size = Vector2(420, 30)
	hint_label.position = c + Vector2(-210, -170)
	hint_label.visible = Game.clicks < 15 and Game.crusades == 0

	for i in rows.size():
		_refresh_row(i)
	_refresh_prestige()
	points_label.text = "Web points: %d free / %d" % [Game.points_free(), Game.points_total()]
	if pages.court.visible:
		_refresh_court()


func _refresh_gates() -> void:
	for k in ["web", "relics", "court", "chapel"]:
		tab_buttons[k].visible = Game.has(k)
	tab_buttons.vault.visible = Game.has("table")
	buy_buttons[10].visible = Game.has("buy10")
	buy_buttons[100].visible = Game.has("buymax")
	buy_buttons[-1].visible = Game.has("buymax")
	crusade_btn.visible = Game.has("crusade")
	crusade_info.visible = Game.has("crusade")
	repeat_btn.visible = Game.has("repeat")
	var dest: Dictionary = Game.destination(Game.last_dest)
	repeat_btn.disabled = not Game.can_crusade() or not Game.destination_unlocked(dest)
	repeat_btn.text = "Again: %s%s (+%s Renown)" % [dest.name,
		"" if Game.last_oath == "" else ", " + Game.oath(Game.last_oath).name, Game.fmt(Game.destination_gain(dest))]
	oath_row.visible = Game.has("oaths")
	preset_row.visible = Game.has("presets")
	rebuild_btn.visible = not Game.last_layout.is_empty()
	season_label.visible = Game.has("seasons")
	pages.relics.reveal_btn.visible = Game.has("reveal")


func _refresh_row(i: int) -> void:
	var b := rows[i]
	var data: Dictionary = Game.BUILDINGS[i]
	if not Game.is_revealed(i):
		b.text = "???\nA greater holding awaits more gold"
		b.disabled = true
		b.tooltip_text = ""
		return
	var amt := Game.buy_amount
	var n := Game.max_affordable(i) if amt < 0 else amt
	var cost := Game.cost_of(i, maxi(n, 1))
	var each: float = data.gps * Game.GPS_SCALE * Game.building_mult(i) * Game.global_mult()
	b.text = "%s  ×%d\n%s%s gold   ·   +%s/s each" % [data.name, Game.owned[i],
		("Max %d: " % n) if amt < 0 else ("×%d: " % amt if amt > 1 else ""), Game.fmt(cost), Game.fmt(each)]
	b.disabled = cost > Game.gold or n <= 0
	var next := _next_milestone(Game.owned[i])
	b.tooltip_text = "%s\nProduces %s/s in total.\nNext milestone at %d owned: output ×%s." % [data.desc,
		Game.fmt(Game.building_gps(i)), next, str(snappedf(2.0 + Game.stat_add("milestone"), 0.01))]


func _next_milestone(n: int) -> int:
	for m in [10, 25, 50, 100]:
		if n < m:
			return m
	return 100 + 50 * (int((n - 100) / 50.0) + 1)


func _refresh_prestige() -> void:
	var gain := Game.renown_gain()
	var ready := Game.can_crusade()
	crusade_btn.disabled = not ready
	crusade_btn.text = "Embark on Crusade  (+%s Renown)" % Game.fmt(gain)
	var lines: PackedStringArray = []
	if gain < 1.0:
		lines.append("Gather %s gold this run to earn Renown." % Game.fmt(Game.CRUSADE_BASE / pow(Game.renown_mult(), 1.0 / Game.CRUSADE_EXP)))
	elif Game.run_time < Game.CRUSADE_MIN_TIME:
		lines.append("The host musters… %ds." % int(Game.CRUSADE_MIN_TIME - Game.run_time))
	if gain > Game.softcap():
		lines.append("Gains past %s are softcapped." % Game.fmt(Game.softcap()))
	lines.append("Resets gold and holdings. Renown multiplies gold and grants Passive Web points.")
	crusade_info.text = " ".join(lines)

	var show_dyn := Game.has("dynasty")
	dynasty_btn.visible = show_dyn
	dynasty_info.visible = show_dyn
	var bg := Game.blood_gain()
	dynasty_btn.disabled = bg < 1.0
	dynasty_btn.text = "Found a Dynasty  (+%s Royal Blood)" % Game.fmt(bg)
	dynasty_info.text = ("Needs %s Renown. " % Game.fmt(Game.DYNASTY_MIN) if bg < 1.0 else "") \
		+ "Resets Renown and the Web. Royal Blood multiplies gold and Renown, raises Renown's power and grants permanent Web points."


func _chronicle_text() -> String:
	var s := "[font_size=28]Chronicle of the Realm[/font_size]\n\n"
	s += "Reign: %s    This crusade: %s\n" % [Game.fmt_time(Game.play_time), Game.fmt_time(Game.run_time)]
	s += "Gold ever levied: %s\nLevies by hand: %d\nCrusades: %d    Dynasties: %d\n" % [Game.fmt(Game.total_gold),
		Game.clicks, Game.crusades, Game.dynasties]
	s += "Gold multiplier: ×%s    Renown power: %s\n" % [Game.fmt(Game.global_mult()), str(snappedf(Game.renown_power(), 0.01))]
	s += "Web nodes: %d / %d\n" % [Game.allocated.size() - 1, Game.tree.nodes.size() - 1]
	s += "Omens caught: %d    Cards scratched: %d    Relics: %d / %d\n\n" % [Game.omens_claimed,
		Game.cards_opened, Game.relics.size(), Content.RELICS.size()]
	s += "[font_size=24]Deeds (%d / %d)[/font_size]\n" % [Game.achieved.size(), Game.achievements.size()]
	for a in Game.achievements:
		if Game.achieved.has(a.id):
			s += "[color=#8f1209]✦ %s[/color]  [color=#6b6052]%s[/color]\n" % [a.title, _goal(a)]
		else:
			s += "[color=#8a8072]· %s[/color]\n" % _goal(a)
	return s


func _goal(a: Dictionary) -> String:
	match a.kind:
		"gold": return "Levy %s gold in total" % Game.fmt(a.value)
		"own": return "Raise a %s" % Game.BUILDINGS[a.value].name
		"clicks": return "Press the seal %d times" % a.value
		"crusades": return "Return from %d crusades" % a.value
		"dynasties": return "Found %d dynasties" % a.value
		"nodes": return "Hold %d nodes of the web at once" % a.value
		"owned_total": return "Own %d holdings at once" % a.value
		"omens": return "Catch %d omens" % a.value
		"cards": return "Scratch %d reliquary cards" % a.value
		"relics": return "Find %d different relics" % a.value
		"oaths": return "Keep %d oaths" % a.value
	return "Fill the Infinite Hoard"


# --- Events -----------------------------------------------------------------------

func _on_buy(i: int) -> void:
	var before := Game.milestones(Game.owned[i])
	var n := Game.buy(i)
	if n <= 0:
		return
	var b := rows[i]
	b.modulate = Color(1.35, 1.15, 0.8)
	b.create_tween().tween_property(b, "modulate", Color.WHITE, 0.4)
	world.raise_building(i)
	if Game.milestones(Game.owned[i]) > before:
		_toast("%s milestone: %d owned, output doubled!" % [Game.BUILDINGS[i].name, Game.owned[i]])
		world.fanfare()


func _pulse_gold() -> void:
	gold_label.pivot_offset = gold_label.size / 2.0
	gold_label.scale = Vector2.ONE * 1.12
	gold_label.create_tween().tween_property(gold_label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_tax_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_holding = mb.pressed
		_hold_acc = 0.0
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var omen := world.omen_at(mb.global_position)
		if omen >= 0:
			Game.claim_omen(world.take_omen(omen))
		else:
			Game.levy()


func _on_levied(amount: float, crit: bool) -> void:
	var p := tax_area.get_global_mouse_position()
	world.stamp(p, crit)
	_pulse_gold()
	if floaters.get_child_count() >= MAX_FLOATERS:
		return
	var l := _outlined(_label(("CRITICAL! +" if crit else "+") + Game.fmt(amount), 34 if crit else 26, WAX if crit else INK))
	l.position = p + Vector2(randf_range(-30, 10), -40)
	floaters.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 80, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)


func _on_prestiged(kind: String, gain: float) -> void:
	world.fanfare()
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: halftone.set_shader_parameter("pulse", v), 2.5, 0.0, 1.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	if kind == "crusade":
		_toast("The host returns: +%s Renown." % Game.fmt(gain))
	else:
		_toast("A new dynasty rises: +%s Royal Blood." % Game.fmt(gain))


func _ask_dynasty() -> void:
	dynasty_confirm.dialog_text = "Gain %s Royal Blood.\nYour Renown and Passive Web will be reset." % Game.fmt(Game.blood_gain())
	dynasty_confirm.popup_centered()


func _show_victory() -> void:
	victory_label.text = "Your treasury has overflowed the very ledgers of creation.\n\n" + _victory_brag()
	victory_panel.visible = true
	world.fanfare()


func _victory_brag() -> String:
	return "I filled the Infinite Hoard in Halftone Hold — %s, %d crusades, %d dynasties, %d web nodes." % [
		Game.fmt_time(Game.won_time if Game.won_time >= 0.0 else Game.play_time), Game.crusades, Game.dynasties,
		Game.allocated.size() - 1]


func _on_web_hover(id: int) -> void:
	tooltip.visible = id >= 0
	if id < 0:
		return
	var n: Dictionary = Game.tree.nodes[id]
	var sector: String = "Throne" if n.sector < 0 else PassiveTree.SECTORS[n.sector].name
	var status: String
	if n.kind == PassiveTree.Kind.ROOT:
		status = "Every path begins here."
	elif Game.allocated.has(id):
		status = "Allocated — right-click to refund." if Game.can_refund(id) else "Allocated — holds other nodes up."
	elif not Game.path_to(id).is_empty() and Game.points_free() > 0:
		var cost := Game.path_to(id).size()
		status = "Click to allocate (%d point%s)." % [cost, "" if cost == 1 else "s"] if cost <= Game.points_free() \
			else "Path costs %d points; click to go %d of the way." % [cost, Game.points_free()]
	elif Game.points_free() <= 0:
		status = "No free points. Earn Renown."
	else:
		status = "Not connected yet."
	tooltip_label.text = "[font_size=24][color=#8f1209]%s[/color][/font_size]\n[color=#6b6052]%s · %s[/color]\n%s\n[i]%s[/i]" % [
		n.name, KIND_NAMES[n.kind], sector, Game.describe_mods(n.mods), status]
	tooltip.reset_size()
	_place_tooltip()


func _place_tooltip() -> void:
	var view := root.get_viewport_rect().size
	var p := root.get_global_mouse_position() + Vector2(20, 20)
	tooltip.position = Vector2(clampf(p.x, 8.0, view.x - tooltip.size.x - 8), clampf(p.y, 8.0, view.y - tooltip.size.y - 8))


func _show_page(name: String) -> void:
	for k in pages:
		pages[k].visible = k == name
	web.visible = name == "web"
	world.visible = name != "web"
	tooltip.visible = false
	if name == "court":
		_refresh_court()
	elif name == "relics":
		pages.relics.rebuild_relics()
	elif name == "chapel":
		pages.chapel.rebuild()


func _toast(text: String) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label(text, 18))
	toasts.add_child(panel)
	var tw := panel.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(panel.queue_free)


func _apply_settings() -> void:
	halftone.set_shader_parameter("strength", 1.0)
	halftone.set_shader_parameter("cell", HALFTONE_CELL)


# --- Helpers ----------------------------------------------------------------------

func _label(text: String, size: int = 20, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _heading(text: String) -> Label:
	var l := _label(text, 26)
	l.add_theme_font_override("font", FONT_CAPS)
	return l


func _outlined(l: Label) -> Label:
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", PARCH)
	return l


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_color_override("default_color", INK)
	r.add_theme_font_size_override("normal_font_size", 19)
	r.add_theme_font_override("normal_font", body_font)
	return r


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = body_font
	th.default_font_size = 20
	th.set_stylebox("panel", "PanelContainer", _box(Color(PARCH, 0.94), 3))
	th.set_stylebox("panel", "TooltipPanel", _box(PARCH, 2))
	th.set_color("font_color", "TooltipLabel", INK)
	th.set_stylebox("normal", "Button", _box(Color(0.9, 0.84, 0.7), 2))
	th.set_stylebox("hover", "Button", _box(Color(0.97, 0.9, 0.74), 2))
	th.set_stylebox("pressed", "Button", _box(WAX, 2))
	th.set_stylebox("hover_pressed", "Button", _box(WAX.lightened(0.1), 2))
	th.set_stylebox("disabled", "Button", _box(Color(0.86, 0.82, 0.74, 0.7), 1))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		th.set_color(c, "Button", INK)
	th.set_color("font_pressed_color", "Button", PARCH)
	th.set_color("font_hover_pressed_color", "Button", PARCH)
	th.set_color("font_disabled_color", "Button", FADED)
	th.set_color("font_color", "Label", INK)
	th.set_color("font_color", "CheckButton", INK)
	th.set_color("font_hover_color", "CheckButton", INK)
	th.set_color("font_pressed_color", "CheckButton", INK)
	th.set_stylebox("normal", "LineEdit", _box(Color(1, 0.97, 0.9), 2))
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", FADED)
	th.set_stylebox("panel", "AcceptDialog", _box(PARCH, 3))
	th.set_color("font_color", "AcceptDialog", INK)
	return th


func _box(bg: Color, border: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = INK
	b.set_border_width_all(border)
	b.set_corner_radius_all(3)
	b.set_content_margin_all(10)
	return b
