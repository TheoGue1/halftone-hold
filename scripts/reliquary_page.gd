extends HBoxContainer
## Scratch-card reliquary (drag to scratch the foil) and the relic collection with equip slots.

const CELL := 118.0
const GAP := 10.0
const TILES := 6  # foil tiles per cell side; tiles flake off as the cell is scratched
const SCRATCH_PER_PX := 0.012
const SCRATCH_PER_CLICK := 0.25
const INK := Color(0.14, 0.09, 0.06)
const GOLD := Color(1.0, 0.8, 0.22)
const FOIL := Color(0.72, 0.68, 0.6)
const FOIL_DARK := Color(0.55, 0.5, 0.43)
const PAPER := Color(0.99, 0.95, 0.86)

var caps_font: Font
var card_view: Control
var buy_btn: Button
var reveal_btn: Button
var result_label: Label
var cost_label: Label
var slots_label: Label
var relic_list: VBoxContainer
var _shown := {}  # resolved card kept on display: {symbols, winners}
var _flakes: Array[Dictionary] = []
var _t := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	left.add_child(v)
	v.add_child(_title("The Reliquary"))
	cost_label = _text("", 17)
	cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cost_label)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(center)
	card_view = Control.new()
	card_view.custom_minimum_size = Vector2.ONE * (CELL * 3 + GAP * 2)
	card_view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card_view.draw.connect(_draw_card)
	card_view.gui_input.connect(_on_card_input)
	center.add_child(card_view)
	result_label = _text("", 20)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(result_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	buy_btn = Button.new()
	buy_btn.pressed.connect(_buy)
	row.add_child(buy_btn)
	reveal_btn = Button.new()
	reveal_btn.text = "Reveal all"
	reveal_btn.pressed.connect(Game.reveal_card)
	row.add_child(reveal_btn)

	var right := PanelContainer.new()
	right.custom_minimum_size.x = 430
	add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	rv.add_child(_title("Relics"))
	slots_label = _text("", 16)
	slots_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(slots_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	relic_list = VBoxContainer.new()
	relic_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(relic_list)

	Game.card_resolved.connect(_on_resolved)
	Game.relic_found.connect(func(_id: int, _lv: int) -> void: rebuild_relics())
	rebuild_relics()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	for f in _flakes:
		f.vel.y += 600.0 * delta
		f.pos += f.vel * delta
		f.life -= delta
	_flakes = _flakes.filter(func(f: Dictionary) -> bool: return f.life > 0.0)
	var live := not Game.card.is_empty()
	var cost := Game.card_cost()
	if Game.free_cards > 0:
		buy_btn.text = "Open a free card (%d)" % Game.free_cards
	else:
		buy_btn.text = "Buy a card — %s gold" % Game.fmt(cost)
	buy_btn.disabled = live or (Game.free_cards == 0 and Game.gold < cost)
	reveal_btn.disabled = not live
	cost_label.text = "Scratch the foil. 3 coins or 3 crowns pay gold. 3 chalices summon an omen. " \
		+ "2+ relic marks find a relic (more marks, rarer relic). Cards opened: %d" % Game.cards_opened
	card_view.queue_redraw()


func rebuild_relics() -> void:
	for c in relic_list.get_children():
		c.queue_free()
	slots_label.text = "Equipped %d / %d slots. Extra slots at dynasties %s. Duplicates level a relic up to %d." % [
		Game.equipped.size(), Game.relic_slots(), str(Content.SLOT_DYNASTIES).trim_prefix("[").trim_suffix("]"), Content.RELIC_MAX_LEVEL]
	for i in Content.RELICS.size():
		var r: Dictionary = Content.RELICS[i]
		var rarity: Dictionary = Content.RARITIES[r.rarity]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		if Game.relics.has(i):
			b.text = "%s  · Lv %d  · %s\n%s" % [r.name, Game.relics[i], rarity.name,
				Game.describe_mods(Game.relic_mods(i)).replace("\n", ", ")]
			b.button_pressed = i in Game.equipped
			b.add_theme_color_override("font_color", rarity.color)
			b.pressed.connect(func() -> void:
				Game.toggle_equip(i)
				rebuild_relics())
		else:
			b.text = "???  · %s" % rarity.name
			b.disabled = true
		relic_list.add_child(b)


func _buy() -> void:
	if Game.buy_card():
		_shown = {}
		result_label.text = ""


func _on_resolved(symbols: Array, winners: Array, text: String) -> void:
	_shown = {"symbols": symbols, "winners": winners}
	result_label.text = text
	card_view.pivot_offset = card_view.size / 2.0
	card_view.scale = Vector2.ONE * (1.08 if winners.is_empty() else 1.18)
	card_view.create_tween().tween_property(card_view, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _on_card_input(event: InputEvent) -> void:
	if Game.card.is_empty():
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_scratch_at(mb.position, SCRATCH_PER_CLICK)
	var mm := event as InputEventMouseMotion
	if mm and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_scratch_at(mm.position, mm.relative.length() * SCRATCH_PER_PX)


func _scratch_at(p: Vector2, amount: float) -> void:
	var col := int(p.x / (CELL + GAP))
	var row := int(p.y / (CELL + GAP))
	if col < 0 or col > 2 or row < 0 or row > 2:
		return
	var cell := row * 3 + col
	if Game.card.scratched[cell] >= 1.0:
		return
	for k in 3:
		_flakes.append({"pos": p, "vel": Vector2(randf_range(-160, 160), randf_range(-220, -40)), "life": 0.6})
	Game.scratch(cell, amount)


func _cell_rect(i: int) -> Rect2:
	return Rect2(Vector2(i % 3, int(i / 3.0)) * (CELL + GAP), Vector2.ONE * CELL)


func _draw_card() -> void:
	var live := not Game.card.is_empty()
	if not live and _shown.is_empty():
		for i in 9:
			var r := _cell_rect(i)
			card_view.draw_rect(r, FOIL_DARK.lerp(PAPER, 0.5))
			card_view.draw_rect(r, INK, false, 2.0)
		card_view.draw_string(caps_font, Vector2(0, card_view.size.y / 2.0 + 10), "Buy a card to scratch",
			HORIZONTAL_ALIGNMENT_CENTER, card_view.size.x, 30, INK)
		return
	var symbols: Array = Game.card.symbols if live else _shown.symbols
	var winners: Array = [] if live else _shown.winners
	for i in 9:
		var r := _cell_rect(i)
		card_view.draw_rect(r, PAPER)
		if symbols[i] in winners:
			var pulse := 0.5 + 0.5 * sin(_t * 8.0)
			card_view.draw_rect(r.grow(-4), Color(1.0, 0.85, 0.35, 0.35 + 0.35 * pulse))
		_draw_symbol(symbols[i], r.get_center(), CELL * 0.32)
		if live:
			_draw_foil(r, Game.card.scratched[i], i)
		card_view.draw_rect(r, INK, false, 2.0)
	for f in _flakes:
		card_view.draw_rect(Rect2(f.pos - Vector2(3, 3), Vector2(6, 6)), FOIL)


## Foil tiles drop out in a fixed pseudo-random order as `amount` rises, so scratching looks patchy.
func _draw_foil(r: Rect2, amount: float, cell: int) -> void:
	if amount >= 1.0:
		return
	var tile := r.size / TILES
	for y in TILES:
		for x in TILES:
			if fposmod(sin((cell * 97 + y * TILES + x) * 12.9898) * 43758.5453, 1.0) < amount:
				continue
			var col := FOIL if (x + y) % 2 == 0 else FOIL.lerp(FOIL_DARK, 0.4)
			card_view.draw_rect(Rect2(r.position + Vector2(x, y) * tile, tile + Vector2.ONE), col)
	if amount == 0.0:
		card_view.draw_string(caps_font, r.position + Vector2(0, r.size.y / 2.0 + 12), "?",
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 40, FOIL_DARK)


func _draw_symbol(kind: String, c: Vector2, s: float) -> void:
	match kind:
		"coin":
			card_view.draw_circle(c, s, GOLD)
			card_view.draw_arc(c, s, 0, TAU, 32, INK, 3.0)
			card_view.draw_arc(c, s * 0.7, 0, TAU, 32, INK, 2.0)
		"crown":
			var pts := PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(-s, -s * 0.4), c + Vector2(-s * 0.5, s * 0.1),
				c + Vector2(0, -s * 0.8), c + Vector2(s * 0.5, s * 0.1), c + Vector2(s, -s * 0.4), c + Vector2(s, s * 0.6)])
			card_view.draw_colored_polygon(pts, GOLD)
			pts.append(pts[0])
			card_view.draw_polyline(pts, INK, 3.0)
		"chalice":
			var cup := PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.8), c + Vector2(s * 0.8, -s * 0.8),
				c + Vector2(s * 0.4, 0), c + Vector2(-s * 0.4, 0)])
			card_view.draw_colored_polygon(cup, Color(0.8, 0.8, 0.85))
			card_view.draw_rect(Rect2(c + Vector2(-s * 0.1, 0), Vector2(s * 0.2, s * 0.6)), Color(0.7, 0.7, 0.75))
			card_view.draw_rect(Rect2(c + Vector2(-s * 0.5, s * 0.6), Vector2(s, s * 0.2)), Color(0.7, 0.7, 0.75))
			cup.append(cup[0])
			card_view.draw_polyline(cup, INK, 3.0)
		"relic":
			card_view.draw_circle(c, s * 1.1, Color(0.75, 0.6, 1.0, 0.35))
			card_view.draw_rect(Rect2(c + Vector2(-s * 0.15, -s * 0.9), Vector2(s * 0.3, s * 1.8)), Color(0.45, 0.2, 0.6))
			card_view.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.45), Vector2(s * 1.2, s * 0.3)), Color(0.45, 0.2, 0.6))
		_:
			card_view.draw_circle(c + Vector2(0, -s * 0.15), s * 0.7, Color(0.95, 0.93, 0.88))
			card_view.draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.3), Vector2(s * 0.8, s * 0.4)), Color(0.95, 0.93, 0.88))
			card_view.draw_circle(c + Vector2(-s * 0.25, -s * 0.2), s * 0.16, INK)
			card_view.draw_circle(c + Vector2(s * 0.25, -s * 0.2), s * 0.16, INK)


func _title(text: String) -> Label:
	var l := _text(text, 26)
	l.add_theme_font_override("font", caps_font)
	return l


func _text(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l
