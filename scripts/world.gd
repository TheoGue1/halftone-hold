extends Node2D
## Procedural kingdom backdrop. High tonal contrast on purpose: the halftone pass turns it into ink.

const SKY_TOP := Color(0.74, 0.85, 0.94)
const SKY_LOW := Color(1.0, 0.93, 0.78)
const SUN := Color(1.0, 0.78, 0.3)
const STONE := Color(0.62, 0.6, 0.56)
const STONE_DARK := Color(0.38, 0.36, 0.34)
const ROOF := Color(0.72, 0.14, 0.1)
const WAX := Color(0.62, 0.08, 0.06)
const WAX_LIGHT := Color(0.8, 0.18, 0.12)
const GOLD := Color(1.0, 0.8, 0.22)
const INK := Color(0.12, 0.08, 0.06)
const SEAL_POS := Vector2(0.28, 0.52)
const SEAL_RADIUS := 100.0
const OMEN_HIT_RADIUS := 55.0
const MAX_FLAKES := 160
const FLAKE_RATE := 30.0  # per second while a season/weather has particles

var t := 0.0
var area := Rect2(0, 0, 840, 720)  ## Uncovered play area, set by main.
var seal_scale := 1.0
var coins: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var dust: Array[Dictionary] = []
var omens: Array[Dictionary] = []
var flakes: Array[Dictionary] = []
var _flake_acc := 0.0
var _lightning := 0.0
var _rain := 0.0


func _process(delta: float) -> void:
	t += delta
	seal_scale = lerpf(seal_scale, 1.0, 1.0 - exp(-10.0 * delta))
	for c in coins:
		c.vel.y += 900.0 * delta
		c.pos += c.vel * delta
		c.life -= delta
	coins = coins.filter(func(c: Dictionary) -> bool: return c.life > 0.0)
	for r in rings:
		r.age += delta
	rings = rings.filter(func(r: Dictionary) -> bool: return r.age < 0.8)
	_process_omens(delta)
	_process_flakes(delta)
	for d in dust:
		d.age += delta
	dust = dust.filter(func(d: Dictionary) -> bool: return d.age < 0.7)
	# Ambient coin rain: one coin/s per ~8 orders of magnitude of income.
	_rain += delta * clampf(log(Game.gps() + 1.0) / log(10.0) / 8.0, 0.0, 4.0)
	while _rain >= 1.0:
		_rain -= 1.0
		coins.append({"pos": Vector2(area.position.x + randf() * area.size.x, area.position.y - 10.0),
			"vel": Vector2(randf_range(-30, 30), randf_range(0, 80)), "life": 2.0, "r": randf_range(4, 7)})
	queue_redraw()


func seal_center() -> Vector2:
	return area.position + area.size * SEAL_POS


func hits_seal(p: Vector2) -> bool:
	return p.distance_to(seal_center()) <= SEAL_RADIUS * 1.15


func stamp(p: Vector2, crit: bool) -> void:
	seal_scale = 0.86 if not crit else 0.75
	for i in (14 if crit else 6):
		coins.append({"pos": p, "vel": Vector2.from_angle(randf_range(-PI * 0.9, -PI * 0.1)) * randf_range(250, 520),
			"life": randf_range(0.6, 1.1), "r": randf_range(6, 11)})
	rings.append({"pos": p, "age": 0.0, "big": crit})


func raise_building(_i: int) -> void:
	var p := _castle_base()
	for k in 6:
		dust.append({"pos": p + Vector2(randf_range(-120, 120), randf_range(-10, 5)), "age": 0.0,
			"r": randf_range(10, 22)})


func _castle_base() -> Vector2:
	return Vector2(area.position.x + area.size.x * 0.68, get_viewport_rect().size.y * 0.63)


func fanfare() -> void:
	var c := seal_center()
	for i in 60:
		coins.append({"pos": c, "vel": Vector2.from_angle(randf() * TAU) * randf_range(200, 900),
			"life": randf_range(0.8, 1.6), "r": randf_range(6, 14)})
	rings.append({"pos": c, "age": 0.0, "big": true})


func _draw() -> void:
	var size := get_viewport_rect().size
	_draw_sky(size)
	_draw_sun(size)
	_draw_clouds(size)
	_draw_birds(size)
	_draw_hills(size, 0.62, 40.0, Color(0.66, 0.76, 0.82), 0.7)
	_draw_castle(size)
	_draw_sparkles()
	_draw_hills(size, 0.72, 30.0, Color(0.66, 0.78, 0.46), 1.3)
	_draw_fields(size)
	_draw_mill(size)
	_draw_smithy(size)
	_draw_hills(size, 0.86, 18.0, Color(0.5, 0.64, 0.32), 2.1)
	_draw_road(size)
	for d in dust:
		var k: float = d.age / 0.7
		draw_circle(d.pos - Vector2(0, 30 * k), d.r * (1.0 + k), Color(0.8, 0.75, 0.68, 1.0 - k))
	if Game.owned[9] > 0:
		_draw_dragon(size)
	_draw_seal()
	for o in omens:
		_draw_omen(o)
	for f in flakes:
		_draw_flake(f)
	if _lightning > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, _lightning * 2.0))
	for r in rings:
		var k: float = r.age / 0.8
		draw_arc(r.pos, lerpf(SEAL_RADIUS, SEAL_RADIUS * (2.6 if r.big else 1.7), k), 0, TAU, 64,
			Color(INK, 1.0 - k), 10.0 * (1.0 - k))
	for c in coins:
		draw_circle(c.pos, c.r, GOLD)
		draw_arc(c.pos, c.r, 0, TAU, 16, INK, 2.0)


func _draw_sky(size: Vector2) -> void:
	var tint: Color = Game.season().tint if Game.has("seasons") else Color.WHITE
	var storm: bool = _weather() == "Storm"
	var top := SKY_TOP * tint
	var low := SKY_LOW * tint
	if storm:
		top = top.lerp(Color(0.45, 0.47, 0.52), 0.55)
		low = low.lerp(Color(0.62, 0.62, 0.64), 0.5)
	var bands := 24
	for i in bands:
		var y0 := size.y * 0.75 * i / bands
		draw_rect(Rect2(0, y0, size.x, size.y * 0.75 / bands + 1), top.lerp(low, float(i) / bands))
	draw_rect(Rect2(0, size.y * 0.75, size.x, size.y * 0.25), low)


func _draw_sun(size: Vector2) -> void:
	if _weather() == "Storm":
		return
	var c := Vector2(area.position.x + area.size.x * 0.88, size.y * 0.17)
	var heat: float = 1.35 if _weather() == "Heatwave" else 1.0
	for i in 16:
		var a := t * 0.05 * heat + i * TAU / 16.0
		draw_colored_polygon(PackedVector2Array([c + Vector2.from_angle(a - 0.07) * 80 * heat,
			c + Vector2.from_angle(a) * (190 + 20 * sin(t * heat + i)) * heat, c + Vector2.from_angle(a + 0.07) * 80 * heat]),
			Color(1.0, 0.88, 0.5))
	draw_circle(c, 72 * heat, SUN)


func _draw_clouds(size: Vector2) -> void:
	for i in 5:
		var x := fposmod(i * 330.0 + t * (8.0 + i * 3.0), size.x + 400.0) - 200.0
		var y := size.y * (0.1 + 0.07 * (i % 3))
		for j in 4:
			var p := Vector2(x + j * 38.0, y + (12.0 if j % 2 == 0 else 0.0))
			draw_circle(p + Vector2(0, 8), 34.0 - abs(j - 1.5) * 5.0, Color(0.8, 0.8, 0.84))
			draw_circle(p, 34.0 - abs(j - 1.5) * 5.0, Color(0.99, 0.98, 0.96))


func _draw_hills(size: Vector2, base: float, amp: float, col: Color, freq: float) -> void:
	var pts := PackedVector2Array([Vector2(0, size.y)])
	for i in 65:
		var x := size.x * i / 64.0
		pts.append(Vector2(x, size.y * base - amp * (sin(x * 0.004 * freq + base * 10.0) + 0.5 * sin(x * 0.011 * freq))))
	pts.append(Vector2(size.x, size.y))
	var season: String = Game.season().name if Game.has("seasons") else ""
	if season == "Winter":
		col = col.lerp(Color(0.97, 0.97, 1.0), 0.6)
	elif season == "Autumn":
		col = col.lerp(Color(0.85, 0.55, 0.2), 0.35)
	draw_colored_polygon(pts, col)


func _draw_fields(size: Vector2) -> void:
	var rows := mini(Game.owned[1], 12)
	for i in rows:
		var y := size.y * 0.79 + i * 6.0
		draw_line(Vector2(area.position.x + area.size.x * 0.5, y), Vector2(size.x, y + 10.0), Color(0.68, 0.6, 0.2), 3.0)


func _draw_castle(size: Vector2) -> void:
	var kinds := 0
	for n in Game.owned:
		if n > 0:
			kinds += 1
	var s := 0.6 + 0.025 * kinds
	var base := _castle_base()
	# keep
	_tower(base, 70 * s, 150 * s, true)
	for i in kinds:
		var side := -1.0 if i % 2 == 0 else 1.0
		var off := (60.0 + 24.0 * int(i / 2.0)) * s * side
		var h := (110.0 - 8.0 * int(i / 2.0) + 20.0 * float(i % 3)) * s
		_tower(base + Vector2(off, 0), 30 * s, h, false)
	if kinds > 1:
		var w := (60.0 + 24.0 * int((kinds - 1) / 2.0)) * s
		draw_rect(Rect2(base.x - w, base.y - 50 * s, w * 2, 50 * s), STONE)
		for x in range(int(-w), int(w), int(maxf(12 * s, 6))):
			draw_rect(Rect2(base.x + x, base.y - 60 * s, 6 * s, 10 * s), STONE)
	# gate
	draw_rect(Rect2(base.x - 14 * s, base.y - 38 * s, 28 * s, 38 * s), INK)


func _tower(foot: Vector2, w: float, h: float, keep: bool) -> void:
	draw_rect(Rect2(foot.x - w / 2, foot.y - h, w, h), STONE)
	draw_rect(Rect2(foot.x + w / 6, foot.y - h, w / 3, h), STONE_DARK)
	var top := foot.y - h
	draw_colored_polygon(PackedVector2Array([Vector2(foot.x - w * 0.62, top), Vector2(foot.x + w * 0.62, top),
		Vector2(foot.x, top - w * (0.9 if keep else 1.4))]), ROOF)
	var tip := Vector2(foot.x, top - w * (0.9 if keep else 1.4))
	draw_line(tip, tip - Vector2(0, 22), INK, 2.0)
	var wave := sin(t * 4.0 + foot.x) * 4.0
	draw_colored_polygon(PackedVector2Array([tip - Vector2(0, 22), tip + Vector2(20, -17 + wave),
		tip - Vector2(0, 12)]), ROOF)
	for i in 3:
		draw_rect(Rect2(foot.x - w * 0.12, top + h * (0.25 + 0.22 * i), w * 0.24, h * 0.1), INK)


func _draw_dragon(size: Vector2) -> void:
	var c := Vector2(area.position.x + area.size.x * (0.6 + cos(t * 0.3) * 0.3), size.y * 0.25 + sin(t * 0.6) * 40.0)
	var dir := -1.0 if sin(t * 0.3) > 0.0 else 1.0
	var flap := sin(t * 6.0) * 26.0
	var col := Color(0.2, 0.1, 0.08)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-40 * dir, 0), c + Vector2(30 * dir, -6),
		c + Vector2(48 * dir, -2), c + Vector2(30 * dir, 6)]), col)
	for side in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([c + Vector2(-6 * dir, 0), c + Vector2(14 * dir, 0),
			c + Vector2(-10 * dir, side * (34 + flap * side))]), col)
	draw_line(c + Vector2(-40 * dir, 0), c + Vector2(-70 * dir, 10 + sin(t * 3.0) * 8.0), col, 4.0)


func _draw_seal() -> void:
	var c := seal_center()
	var r := SEAL_RADIUS * seal_scale * (1.0 + 0.025 * sin(t * 2.2))
	var blob := PackedVector2Array()
	for i in 48:
		var a := i * TAU / 48.0
		blob.append(c + Vector2.from_angle(a) * r * (1.08 + 0.05 * sin(a * 7.0 + 1.3) + 0.03 * sin(a * 13.0)))
	draw_colored_polygon(blob, WAX)
	draw_circle(c, r * 0.86, WAX_LIGHT)
	draw_arc(c, r * 0.78, 0, TAU, 64, WAX, 5.0)
	# crown
	var w := r * 0.5
	var y := c.y + r * 0.22
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w, r * 0.22), c + Vector2(-w, -r * 0.18),
		c + Vector2(-w * 0.5, r * 0.02), c + Vector2(0, -r * 0.34), c + Vector2(w * 0.5, r * 0.02),
		c + Vector2(w, -r * 0.18), c + Vector2(w, r * 0.22)]), GOLD)
	draw_rect(Rect2(c.x - w, y, w * 2, r * 0.1), GOLD)
	for x in [-w, 0.0, w]:
		draw_circle(c + Vector2(x, -r * (0.34 if x == 0.0 else 0.18) - 6), 7 * seal_scale, GOLD)


func _draw_birds(size: Vector2) -> void:
	for i in 4:
		var x := fposmod(i * 260.0 + t * (40.0 + i * 7.0), size.x + 200.0) - 100.0
		var y := size.y * (0.12 + 0.05 * i) + sin(t * 1.3 + i) * 10.0
		var f := sin(t * 9.0 + i) * 7.0
		draw_polyline(PackedVector2Array([Vector2(x - 12, y - f), Vector2(x, y), Vector2(x + 12, y - f)]), INK, 2.5)


func _draw_sparkles() -> void:
	if Game.owned[8] <= 0:
		return
	var base := _castle_base()
	for k in 7:
		var p := base + Vector2(cos(t * 0.7 + k) * 100.0, -180.0 + sin(t * 1.1 + k * 2.0) * 40.0)
		var s := 4.0 + 5.0 * absf(sin(t * 3.0 + k))
		var col := Color(0.55, 0.35, 1.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 2), p + Vector2(s * 0.4, 0),
			p + Vector2(0, s * 2), p + Vector2(-s * 0.4, 0)]), col)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 2, 0), p + Vector2(0, s * 0.4),
			p + Vector2(s * 2, 0), p + Vector2(0, -s * 0.4)]), col)


func _draw_mill(size: Vector2) -> void:
	if Game.owned[2] <= 0:
		return
	var c := Vector2(area.position.x + area.size.x * 0.93, size.y * 0.75)
	draw_rect(Rect2(c.x - 10, c.y - 44, 46, 44), STONE)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -44), c + Vector2(42, -44), c + Vector2(13, -70)]), ROOF)
	var hub := c + Vector2(-12, -20)
	draw_circle(hub, 27, Color(0.45, 0.3, 0.18))
	draw_circle(hub, 21, Color(0.78, 0.64, 0.44))
	for k in 8:
		draw_line(hub, hub + Vector2.from_angle(t * 1.6 + k * TAU / 8.0) * 28.0, Color(0.35, 0.22, 0.12), 4.0)


func _draw_smithy(size: Vector2) -> void:
	if Game.owned[3] <= 0:
		return
	var c := Vector2(area.position.x + area.size.x * 0.47, size.y * 0.76)
	draw_rect(Rect2(c.x - 24, c.y - 30, 48, 30), STONE_DARK)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-30, -30), c + Vector2(30, -30), c + Vector2(0, -52)]),
		Color(0.45, 0.3, 0.2))
	draw_rect(Rect2(c.x - 8, c.y - 16, 16, 16), Color(1.0, 0.55 + 0.2 * sin(t * 12.0), 0.1))
	var chimney := c + Vector2(14, -58)
	draw_rect(Rect2(chimney.x - 5, chimney.y, 10, 20), INK)
	for k in 6:
		var ph := fposmod(t * 0.35 + k / 6.0, 1.0)
		draw_circle(chimney + Vector2(sin(t + k) * 8.0 + ph * 40.0, -ph * 130.0), 6.0 + ph * 16.0,
			Color(0.55, 0.52, 0.5).lerp(Color(0.92, 0.9, 0.87), ph))


func _draw_road(size: Vector2) -> void:
	var y := size.y * 0.9
	draw_rect(Rect2(0, y - 10, size.x, 22), Color(0.88, 0.8, 0.62))
	for i in mini(Game.owned[0], 10):
		var dir := 1.0 if i % 2 == 0 else -1.0
		var speed := 18.0 + (i * 7) % 15
		var foot := Vector2(area.position.x + fposmod(i * 131.0 + dir * t * speed, area.size.x), y + 4.0)
		var step := sin(t * speed * 0.35 + i)
		draw_line(foot + Vector2(-5 * step, 0), foot + Vector2(0, -12), INK, 2.5)
		draw_line(foot + Vector2(5 * step, 0), foot + Vector2(0, -12), INK, 2.5)
		draw_rect(Rect2(foot.x - 5, foot.y - 26, 10, 15), Color(0.55, 0.35, 0.2))
		draw_circle(foot + Vector2(0, -31), 5, Color(0.95, 0.8, 0.65))
	for i in mini(Game.owned[4], 3):
		var c := Vector2(area.position.x + fposmod(i * 300.0 + t * 30.0, area.size.x + 120.0) - 60.0, y - 6.0)
		draw_rect(Rect2(c.x - 26, c.y - 20, 52, 18), Color(0.55, 0.36, 0.18))
		draw_circle(c + Vector2(-8, -24), 8, GOLD)
		draw_circle(c + Vector2(8, -25), 7, GOLD)
		for wx in [-16.0, 16.0]:
			var wc: Vector2 = c + Vector2(wx, 0)
			draw_arc(wc, 9, 0, TAU, 16, INK, 3.0)
			var spoke := Vector2.from_angle(t * 3.3) * 9.0
			draw_line(wc - spoke, wc + spoke, INK, 2.0)


# --- Omens ----------------------------------------------------------------------

func spawn_omen(kind: String) -> void:
	var size := get_viewport_rect().size
	var x0 := area.position.x
	var x1 := area.end.x
	var o := {"kind": kind, "age": 0.0}
	match kind:
		"cart":
			o.pos = Vector2(x0 - 40, size.y * 0.86)
			o.vel = Vector2(area.size.x / Content.OMEN_LIFETIME, 0)
		"star":
			o.pos = Vector2(randf_range(x0 + area.size.x * 0.4, x1), area.position.y + 20)
			o.vel = Vector2(-50, 38)
		"dragon":
			o.pos = Vector2(x1 + 60, size.y * 0.3)
			o.vel = Vector2(-area.size.x / Content.OMEN_LIFETIME, 0)
		_:
			o.pos = Vector2(x1 + 20, size.y * 0.88)
			o.vel = Vector2(-area.size.x / Content.OMEN_LIFETIME * 0.9, 0)
	omens.append(o)


## Index of the omen under `p`, or -1.
func omen_at(p: Vector2) -> int:
	for i in omens.size():
		if p.distance_to(omens[i].pos) <= OMEN_HIT_RADIUS:
			return i
	return -1


func take_omen(i: int) -> String:
	var o: Dictionary = omens[i]
	omens.remove_at(i)
	for k in 30:
		coins.append({"pos": o.pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(150, 600),
			"life": randf_range(0.6, 1.2), "r": randf_range(5, 10)})
	rings.append({"pos": o.pos, "age": 0.0, "big": true})
	return o.kind


func _process_omens(delta: float) -> void:
	for o in omens:
		o.age += delta
		o.pos += o.vel * delta
		if o.kind == "dragon":
			o.pos.y += cos(o.age * 2.5) * 60.0 * delta
	omens = omens.filter(func(o: Dictionary) -> bool: return o.age < Content.OMEN_LIFETIME)


func _draw_omen(o: Dictionary) -> void:
	var p: Vector2 = o.pos
	var glow := 0.5 + 0.5 * sin(o.age * 6.0)
	draw_circle(p, 48 + 8 * glow, Color(1.0, 0.92, 0.55, 0.55))
	draw_arc(p, 52 + 8 * glow, 0, TAU, 48, GOLD, 4.0)
	match o.kind:
		"cart":
			draw_rect(Rect2(p.x - 36, p.y - 28, 72, 26), Color(0.55, 0.36, 0.18))
			for k in 5:
				draw_circle(p + Vector2(-24 + k * 12, -32 - (k % 2) * 6), 9, GOLD)
			for wx in [-22.0, 22.0]:
				var wc: Vector2 = p + Vector2(wx, 0)
				draw_arc(wc, 12, 0, TAU, 16, INK, 4.0)
				var spoke := Vector2.from_angle(o.age * 5.0) * 12.0
				draw_line(wc - spoke, wc + spoke, INK, 2.5)
		"star":
			for k in 6:
				draw_circle(p - o.vel.normalized() * (14.0 + k * 12.0), 9.0 - k * 1.3, Color(1.0, 0.85, 0.4, 0.8 - k * 0.12))
			var pts := PackedVector2Array()
			for k in 10:
				pts.append(p + Vector2.from_angle(-PI / 2 + k * PI / 5 + o.age) * (28.0 if k % 2 == 0 else 12.0))
			draw_colored_polygon(pts, GOLD)
		"dragon":
			var flap := sin(o.age * 7.0) * 40.0
			var col := WAX
			draw_colored_polygon(PackedVector2Array([p + Vector2(-60, 0), p + Vector2(50, -10),
				p + Vector2(76, -4), p + Vector2(50, 10)]), col)
			for side in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([p + Vector2(-10, 0), p + Vector2(24, 0),
					p + Vector2(-16, side * (55 + flap * side))]), col)
			draw_circle(p + Vector2(-64, 0), 8, Color(1.0, 0.5, 0.1))
		_:
			draw_line(p + Vector2(14, 6), p + Vector2(14, -50), INK, 3.0)
			draw_circle(p + Vector2(14, -54), 7, Color(1.0, 0.85, 0.3))
			draw_colored_polygon(PackedVector2Array([p + Vector2(-12, 6), p + Vector2(10, 6), p + Vector2(0, -32)]),
				Color(0.45, 0.35, 0.28))
			draw_circle(p + Vector2(0, -38), 7, Color(0.95, 0.8, 0.65))


# --- Seasonal particles ---------------------------------------------------------

func _weather() -> String:
	return Game.weather().name if Game.has("seasons") else "Clear"


func _particle_kind() -> String:
	if not Game.has("seasons"):
		return ""
	var w: String = Game.weather().particles
	return w if w != "" else Game.season().particles


func _process_flakes(delta: float) -> void:
	var size := get_viewport_rect().size
	var kind := _particle_kind()
	if kind != "":
		_flake_acc += delta * FLAKE_RATE * (3.0 if kind == "rain" else 1.0)
		while _flake_acc >= 1.0 and flakes.size() < MAX_FLAKES:
			_flake_acc -= 1.0
			flakes.append({"kind": kind, "pos": Vector2(randf() * size.x, -10.0), "seed": randf() * TAU,
				"speed": randf_range(0.7, 1.3)})
		_flake_acc = minf(_flake_acc, 1.0)
	for f in flakes:
		match f.kind:
			"rain": f.pos += Vector2(-120, 700) * f.speed * delta
			"snow": f.pos += Vector2(sin(t + f.seed) * 20.0, 45.0 * f.speed) * delta
			_: f.pos += Vector2(sin(t * 1.5 + f.seed) * 50.0 + 15.0, 60.0 * f.speed) * delta
	flakes = flakes.filter(func(f: Dictionary) -> bool: return f.pos.y < size.y + 20.0)
	_lightning = maxf(_lightning - delta, 0.0)
	if _weather() == "Storm" and randf() < delta / 7.0:
		_lightning = 0.25


func _draw_flake(f: Dictionary) -> void:
	var p: Vector2 = f.pos
	match f.kind:
		"rain":
			draw_line(p, p + Vector2(-6, 30), Color(0.35, 0.45, 0.6), 2.0)
		"snow":
			draw_circle(p, 3.5 * f.speed, Color(1, 1, 1))
		"leaves":
			var a: float = t * 2.0 + f.seed
			draw_colored_polygon(PackedVector2Array([p + Vector2.from_angle(a) * 9, p + Vector2.from_angle(a + 2.2) * 4,
				p + Vector2.from_angle(a + PI) * 9, p + Vector2.from_angle(a - 2.2) * 4]), Color(0.85, 0.42, 0.12))
		_:
			draw_circle(p, 4.0 * f.speed, Color(1.0, 0.72, 0.8))
