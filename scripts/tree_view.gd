extends Node2D
## Pan/zoom view of the passive web. Drawn under the halftone pass, so it prints as ink.

signal hovered(id: int)  # -1 when nothing is under the cursor

const RADIUS := [18.0, 30.0, 42.0, 50.0]  # indexed by PassiveTree.Kind
const LINE_ON := Color(0.55, 0.06, 0.04)
const LINE_HALF := Color(0.42, 0.36, 0.3)
const LINE_OFF := Color(0.8, 0.75, 0.65)
const NODE_OFF := Color(0.88, 0.83, 0.72)
const INK := Color(0.12, 0.08, 0.06)
const GOLD := Color(1.0, 0.78, 0.2)
const MIN_ZOOM := 0.12
const MAX_ZOOM := 1.8
const CLICK_SLOP := 6.0

var font: Font
var search := ""
var hover := -1
var t := 0.0
var _search_hits := {}
var _preview := {}  # node ids on the hovered allocation route
var _texts: PackedStringArray = []
var _dragging := false
var _drag_moved := 0.0


func _ready() -> void:
	for n in Game.tree.nodes:
		_texts.append((n.name + " " + Game.describe_mods(n.mods)).to_lower())
	recenter()


func recenter() -> void:
	scale = Vector2.ONE * 0.5
	position = get_viewport_rect().size * Vector2(0.5, 0.55)


func set_search(text: String) -> void:
	search = text.strip_edges().to_lower()
	_search_hits.clear()
	if search.length() >= 2:
		for i in _texts.size():
			if search in _texts[i]:
				_search_hits[i] = true


func _process(delta: float) -> void:
	if visible:
		t += delta
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed: _zoom_at(mb.position, 1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed: _zoom_at(mb.position, 1.0 / 1.12)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_drag_moved = 0.0
				else:
					_dragging = false
					var id := _node_at(mb.position)
					if _drag_moved < CLICK_SLOP and id >= 0:
						Game.allocate_path(id)
						_update_preview()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					var id := _node_at(mb.position)
					if id >= 0:
						Game.refund(id)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			position += mm.relative
			_drag_moved += mm.relative.length()
		var id := _node_at(mm.position)
		if id != hover:
			hover = id
			_update_preview()
			hovered.emit(id)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
	elif event is InputEventPanGesture:
		position -= (event as InputEventPanGesture).delta * 12.0


func search_hits() -> Array:
	return _search_hits.keys()


func _update_preview() -> void:
	_preview = {}
	if hover >= 0:
		for id in Game.path_to(hover):
			_preview[id] = true


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _to_local(screen_pos)
	scale = Vector2.ONE * clampf(scale.x * factor, MIN_ZOOM, MAX_ZOOM)
	position += screen_pos - (position + before * scale.x)


func _to_local(screen_pos: Vector2) -> Vector2:
	return (screen_pos - position) / scale.x


func _node_at(screen_pos: Vector2) -> int:
	var p := _to_local(screen_pos)
	for n in Game.tree.nodes:
		var r: float = RADIUS[n.kind] + 6.0
		if p.distance_squared_to(n.pos) <= r * r:
			return n.id
	return -1


func _draw() -> void:
	var nodes := Game.tree.nodes
	var alloc := Game.allocated
	for n in nodes:
		for nb in n.links:
			if nb < n.id:
				continue
			var a: bool = alloc.has(n.id)
			var b: bool = alloc.has(nb)
			var col := LINE_ON if a and b else (LINE_HALF if a or b else LINE_OFF)
			draw_line(n.pos, nodes[nb].pos, col, 12.0 if a and b else (7.0 if a or b else 4.0))
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	var empowered := [Game.season().sector, Game.weather().sector] if Game.has("seasons") else []
	for n in nodes:
		var r: float = RADIUS[n.kind]
		if n.sector in empowered and n.kind != PassiveTree.Kind.KEYSTONE:
			draw_arc(n.pos, r + 7.0, 0, TAU, 32, GOLD, 5.0)
		var sector_col: Color = GOLD if n.sector < 0 else PassiveTree.SECTORS[n.sector].color
		var fill := NODE_OFF
		if alloc.has(n.id):
			fill = sector_col.lerp(INK, 0.15)
		elif Game.can_allocate(n.id):
			fill = NODE_OFF.lerp(sector_col, 0.35 + 0.4 * pulse)
		draw_circle(n.pos, r, fill)
		var w: float = [4.0, 6.0, 8.0, 9.0][n.kind]
		draw_arc(n.pos, r, 0, TAU, 32 + n.kind * 16, INK, w)
		if n.kind == PassiveTree.Kind.KEYSTONE:
			draw_arc(n.pos, r + 10.0, 0, TAU, 64, INK, 4.0)
		if _search_hits.has(n.id):
			draw_arc(n.pos, r + 16.0 + 4.0 * pulse, 0, TAU, 48, LINE_ON, 6.0)
		if _preview.has(n.id):
			draw_arc(n.pos, r + 5.0, 0, TAU, 32, LINE_ON, 4.0)
		if n.id == hover:
			draw_arc(n.pos, r + 8.0, 0, TAU, 48, INK, 3.0)
	if font:
		var outer := PassiveTree.RING0_RADIUS + PassiveTree.RINGS * PassiveTree.RING_STEP + 140.0
		for s in PassiveTree.SECTORS.size():
			var ang := -PI / 2.0 + (s + 0.5) * TAU / PassiveTree.SECTORS.size()
			var label: String = PassiveTree.SECTORS[s].name.to_upper()
			var size := 120
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			draw_string(font, Vector2.from_angle(ang) * outer - Vector2(w / 2.0, -size * 0.3), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, PassiveTree.SECTORS[s].color.lerp(INK, 0.3))
