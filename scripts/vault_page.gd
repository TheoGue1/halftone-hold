extends HBoxContainer
## The Counting Table: slide coins with arrows/WASD or a mouse swipe; equal coins merge into the next tier.

const CELL := 104.0
const GAP := 10.0
const SLIDE_TIME := 0.12
const POP_TIME := 0.18
const SWIPE_MIN := 30.0
const INK := Color(0.14, 0.09, 0.06)
const BOARD := Color(0.42, 0.3, 0.2)
const SLOT := Color(0.55, 0.42, 0.3)
const NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
const COIN_COLORS := [Color(0.72, 0.42, 0.2), Color(0.8, 0.8, 0.84), Color(0.62, 0.62, 0.68), Color(0.88, 0.88, 0.92),
	Color(1.0, 0.82, 0.3), Color(0.95, 0.7, 0.15), Color(1.0, 0.9, 0.45), Color(0.98, 0.95, 0.75),
	Color(0.85, 0.2, 0.15), Color(0.6, 0.25, 0.75), Color(0.75, 0.1, 0.08), Color(0.35, 0.55, 1.0)]

var caps_font: Font
var view: Control
var info: Label
var ladder: RichTextLabel
var clear_btn: Button
var _anim := {}  # {slides, merged, spawned, t}
var _swipe_from := Vector2.ZERO


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	left.add_child(v)
	v.add_child(_title("The Counting Table"))
	info = _text("", 17)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(center)
	view = Control.new()
	view.custom_minimum_size = Vector2.ONE * (CELL * CountingTable.SIZE + GAP * (CountingTable.SIZE + 1))
	view.draw.connect(_draw_board)
	view.gui_input.connect(_on_board_input)
	center.add_child(view)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	clear_btn = Button.new()
	clear_btn.text = "Sweep the table (keeps your best coin)"
	clear_btn.pressed.connect(func() -> void:
		Game.table.clear(Game.rng)
		_anim = {})
	row.add_child(clear_btn)

	var right := PanelContainer.new()
	right.custom_minimum_size.x = 360
	add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	rv.add_child(_title("The Coin Ladder"))
	ladder = RichTextLabel.new()
	ladder.bbcode_enabled = true
	ladder.fit_content = true
	ladder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ladder.add_theme_color_override("default_color", INK)
	rv.add_child(ladder)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not _anim.is_empty():
		_anim.t += delta
	if Game.table.is_empty():
		Game.table.clear(Game.rng)
	var t := Game.table
	info.text = "Arrow keys, WASD or swipe to slide. Each slide costs a tally stick (%d / %d, +1 every %ds). " % [
		int(t.tally), int(CountingTable.TALLY_CAP), int(CountingTable.TALLY_EVERY)] \
		+ "Merges pay gold. Best coin: %s, gold ×%s." % [CountingTable.COINS[maxi(t.best - 1, 0)],
		Game.fmt(t.gold_mult())]
	clear_btn.text = "The table is jammed: sweep it" if not t.can_move() else "Sweep the table (keeps your best coin)"
	var s := ""
	for i in CountingTable.COINS.size():
		var reached := t.best > i
		s += "[color=%s]%s  %s[/color]  ×%s\n" % ["#8f1209" if reached else "#8a8072", NUMERALS[i],
			CountingTable.COINS[i] if reached or i == t.best else "???", Game.fmt(pow(CountingTable.BEST_MULT, i))]
	ladder.text = s
	view.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var dir := Vector2i.ZERO
	match (event as InputEventKey).keycode:
		KEY_LEFT, KEY_A: dir = Vector2i.LEFT
		KEY_RIGHT, KEY_D: dir = Vector2i.RIGHT
		KEY_UP, KEY_W: dir = Vector2i.UP
		KEY_DOWN, KEY_S: dir = Vector2i.DOWN
	if dir != Vector2i.ZERO:
		_slide(dir)
		get_viewport().set_input_as_handled()


func _on_board_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if not mb or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_swipe_from = mb.position
		return
	var d := mb.position - _swipe_from
	if d.length() < SWIPE_MIN:
		return
	if absf(d.x) > absf(d.y):
		_slide(Vector2i.RIGHT if d.x > 0 else Vector2i.LEFT)
	else:
		_slide(Vector2i.DOWN if d.y > 0 else Vector2i.UP)


func _slide(dir: Vector2i) -> void:
	var res := Game.table_slide(dir)
	if res.get("moved", false):
		_anim = {"slides": res.slides, "merged": res.merged, "spawned": res.spawned, "t": 0.0}


func _cell_pos(i: int) -> Vector2:
	return Vector2(GAP, GAP) + Vector2(i % CountingTable.SIZE, int(i / float(CountingTable.SIZE))) * (CELL + GAP)


func _draw_board() -> void:
	view.draw_rect(Rect2(Vector2.ZERO, view.size), BOARD)
	for i in CountingTable.SIZE * CountingTable.SIZE:
		view.draw_rect(Rect2(_cell_pos(i), Vector2.ONE * CELL), SLOT)
	var sliding: bool = not _anim.is_empty() and _anim.t < SLIDE_TIME
	if sliding:
		var k: float = ease(_anim.t / SLIDE_TIME, 0.5)
		for sl in _anim.slides:
			_draw_coin(_cell_pos(sl[0]).lerp(_cell_pos(sl[1]), k), sl[2], 1.0)
		return
	var after: float = 0.0 if _anim.is_empty() else (_anim.t - SLIDE_TIME) / POP_TIME
	for i in Game.table.board.size():
		var tier: int = Game.table.board[i]
		if tier == 0:
			continue
		var s := 1.0
		if after < 1.0 and not _anim.is_empty():
			if i in _anim.merged:
				s = 1.0 + 0.25 * sin(after * PI)
			elif i == _anim.spawned:
				s = after
		_draw_coin(_cell_pos(i), tier, s)


func _draw_coin(at: Vector2, tier: int, s: float) -> void:
	var c := at + Vector2.ONE * CELL / 2.0
	var r := CELL * 0.42 * s
	var col: Color = COIN_COLORS[mini(tier - 1, COIN_COLORS.size() - 1)]
	view.draw_circle(c, r, col.darkened(0.35))
	view.draw_circle(c, r * 0.86, col)
	view.draw_arc(c, r * 0.7, 0, TAU, 32, col.darkened(0.25), 2.0)
	view.draw_arc(c, r, 0, TAU, 32, INK, 3.0)
	var label: String = NUMERALS[mini(tier - 1, NUMERALS.size() - 1)]
	var size := int(34 * s)
	if size > 4:
		view.draw_string(caps_font, c + Vector2(-r, size * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, size, INK)


func _title(text: String) -> Label:
	var l := _text(text, 26)
	l.add_theme_font_override("font", caps_font)
	return l


func _text(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l
