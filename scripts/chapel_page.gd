extends HBoxContainer
## The Chapel: pick a shattered stained-glass window and slide its shards back. Click a shard in the gap's row or column.

const ART := 384  # generated window texture size, px
const VIEW := 450.0
const SLIDE_TIME := 0.1
const LEAD := Color(0.08, 0.06, 0.05)
const STONE := Color(0.5, 0.47, 0.42)
const WALL := Color(0.36, 0.33, 0.3)
const INK := Color(0.14, 0.09, 0.06)

var caps_font: Font
var view: Control
var info: Label
var list: VBoxContainer
var _art := {}  # window index -> ImageTexture
var _shown := -1  # window drawn when none is in progress (last restored)
var _anim := {}  # tile id -> [from_cell, to_cell]
var _anim_t := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 400
	add_child(left)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	left.add_child(v)
	v.add_child(_title("The Chapel"))
	info = _text("", 16)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	list = VBoxContainer.new()
	v.add_child(list)
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var center := CenterContainer.new()
	right.add_child(center)
	view = Control.new()
	view.custom_minimum_size = Vector2.ONE * VIEW
	view.draw.connect(_draw_window)
	view.gui_input.connect(_on_view_input)
	center.add_child(view)
	Game.window_restored.connect(func(i: int) -> void:
		_shown = i
		view.pivot_offset = view.size / 2.0
		view.scale = Vector2.ONE * 1.12
		view.create_tween().tween_property(view, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC) \
			.set_ease(Tween.EASE_OUT)
		rebuild())
	rebuild()


func rebuild() -> void:
	for c in list.get_children():
		c.queue_free()
	for i in Chapel.SIZES.size():
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var n: int = Chapel.SIZES[i]
		var title := "Window of %s  (%d×%d)" % [PassiveTree.SECTORS[i].name, n, n]
		if Game.chapel.solved[i]:
			b.text = title + "\nRestored: %s nodes empowered" % PassiveTree.SECTORS[i].name
			b.pressed.connect(func() -> void:
				_shown = i)
		elif not Game.window_available(i):
			b.text = title + "\nShattered beyond reach until dynasty %d" % Chapel.window_dynasty(i)
			b.disabled = true
		elif Game.chapel.current == i:
			b.text = title + "\nBeing restored (%d moves)" % Game.chapel.moves
		else:
			b.text = title + "\nShattered: click to begin"
			b.pressed.connect(func() -> void:
				Game.chapel_start(i)
				_anim = {}
				rebuild())
		list.add_child(b)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_anim_t += delta
	info.text = "Each restored window empowers its Web sector forever (+%d%% to its nodes) and grants %d web points. " % [
		int((Chapel.ADD_MULT - 1.0) * 100), Chapel.POINTS] \
		+ "Click a shard in line with the gap to slide it. Restored: %d / %d." % [Game.chapel.solved_count(),
		Chapel.SIZES.size()]
	view.queue_redraw()


func _on_view_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if not mb or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or Game.chapel.current < 0:
		return
	var n := Game.chapel.size()
	var cell_px := VIEW / n
	var x := int(mb.position.x / cell_px)
	var y := int(mb.position.y / cell_px)
	if x < 0 or x >= n or y < 0 or y >= n:
		return
	var moved := Game.chapel_slide(y * n + x)
	if moved.is_empty():
		return
	_anim = {}
	for m in moved:
		_anim[m[2]] = [m[0], m[1]]
	_anim_t = 0.0
	if Game.chapel.current >= 0:
		(list.get_child(Game.chapel.current) as Button).text = "Window of %s  (%d×%d)\nBeing restored (%d moves)" % [
			PassiveTree.SECTORS[Game.chapel.current].name, n, n, Game.chapel.moves]


func _draw_window() -> void:
	var i := Game.chapel.current
	if i < 0:
		if _shown >= 0:
			view.draw_texture_rect(_texture(_shown), Rect2(Vector2.ZERO, Vector2.ONE * VIEW), false)
		else:
			view.draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * VIEW), WALL)
			view.draw_string(caps_font, Vector2(0, VIEW / 2.0), "Choose a window", HORIZONTAL_ALIGNMENT_CENTER,
				VIEW, 32, Color(0.9, 0.86, 0.78))
		return
	var tex := _texture(i)
	var n := Game.chapel.size()
	var cell_px := VIEW / n
	var src_px := float(ART) / n
	view.draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * VIEW), WALL)
	var k := clampf(_anim_t / SLIDE_TIME, 0.0, 1.0)
	var gap_id: int = Game.chapel.tiles.size() - 1
	for cell in Game.chapel.tiles.size():
		var id: int = Game.chapel.tiles[cell]
		if id == gap_id:
			continue
		var at := Vector2(cell % n, int(cell / float(n))) * cell_px
		if _anim.has(id) and k < 1.0:
			var from: int = _anim[id][0]
			at = (Vector2(from % n, int(from / float(n))) * cell_px).lerp(at, ease(k, 0.5))
		var src := Rect2(Vector2(id % n, int(id / float(n))) * src_px, Vector2.ONE * src_px)
		view.draw_texture_rect_region(tex, Rect2(at, Vector2.ONE * cell_px).grow(-1.5), src)
		view.draw_rect(Rect2(at, Vector2.ONE * cell_px).grow(-1.5), INK, false, 2.0)


func _texture(i: int) -> ImageTexture:
	if not _art.has(i):
		_art[i] = ImageTexture.create_from_image(_paint_window(i))
	return _art[i]


## Procedural rose window: rings of glass segments split by lead lines, stone tracery outside.
func _paint_window(i: int) -> Image:
	var base: Color = PassiveTree.SECTORS[i].color
	var palette := [base.lightened(0.2), Color(0.98, 0.78, 0.2), Color(0.2, 0.36, 0.8), Color(0.82, 0.16, 0.12),
		Color(0.3, 0.65, 0.32), Color(0.6, 0.3, 0.78), base.lightened(0.5)]
	var spokes := 8 + i * 2
	var rings := [0.2, 0.46, 0.72, 0.94]
	var data := PackedByteArray()
	data.resize(ART * ART * 3)
	var half := ART / 2.0
	for y in ART:
		for x in ART:
			var p := (Vector2(x, y) - Vector2(half, half)) / half
			var r := p.length()
			var col := WALL
			if r <= 1.0:
				col = STONE
				var ring := rings.size()
				for k in rings.size():
					if r < rings[k]:
						ring = k
						break
				var lead := false
				for edge in rings:
					if absf(r - edge) * half < 2.0:
						lead = true
				if ring < rings.size():
					var count: int = [1, spokes, spokes, spokes * 2][ring]
					var f := (atan2(p.y, p.x) + PI) / TAU * count + (0.5 if ring == 2 else 0.0)
					var seg := int(floor(f)) % count
					var arc := TAU * r * half / count
					if ring > 0 and minf(fposmod(f, 1.0), 1.0 - fposmod(f, 1.0)) * arc < 1.6:
						lead = true
					col = palette[(seg + ring * 3 + i) % palette.size()]
					col = col * (0.82 + 0.18 * sin(x * 0.21 + y * 0.13) * sin(y * 0.17 - x * 0.07))
				if lead:
					col = LEAD
			var o := (y * ART + x) * 3
			data[o] = int(clampf(col.r, 0.0, 1.0) * 255)
			data[o + 1] = int(clampf(col.g, 0.0, 1.0) * 255)
			data[o + 2] = int(clampf(col.b, 0.0, 1.0) * 255)
	return Image.create_from_data(ART, ART, false, Image.FORMAT_RGB8, data)


func _title(text: String) -> Label:
	var l := _text(text, 26)
	l.add_theme_font_override("font", caps_font)
	return l


func _text(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l
