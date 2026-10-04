class_name Chapel
extends RefCounted
## Stained-glass windows as sliding-tile puzzles, one per passive-web sector. Restored windows stay restored.

const SIZES := [3, 3, 4, 4, 5, 5]
const SHUFFLE_MOVES := [40, 60, 120, 160, 260, 320]
const FIRST_DYNASTY := 6
const DYNASTIES_PER_WINDOW := 2
const ADD_MULT := 1.3  # restored sector: additive node values ×1.3
const MUL_POW := 1.1  # restored sector: multiplicative node values ^1.1
const POINTS := 5

var solved: Array = [false, false, false, false, false, false]
var current := -1  # window being restored, -1 when none
var tiles: Array = []  # tiles[cell] = tile id; the highest id is the gap
var moves := 0


static func window_dynasty(i: int) -> int:
	return FIRST_DYNASTY + DYNASTIES_PER_WINDOW * i


func size() -> int:
	return SIZES[current] if current >= 0 else 0


func solved_count() -> int:
	return solved.count(true)


func gap() -> int:
	return tiles.find(tiles.size() - 1)


## Shuffles by random legal moves from the solved picture, so every puzzle is solvable.
func start(i: int, rng: RandomNumberGenerator) -> void:
	current = i
	moves = 0
	var n: int = SIZES[i]
	tiles = range(n * n)
	var prev := -1
	var done := 0
	while done < SHUFFLE_MOVES[i] or is_solved():
		var g := gap()
		var options: Array = []
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var x: int = g % n + d.x
			var y: int = g / n + d.y
			if x >= 0 and x < n and y >= 0 and y < n and y * n + x != prev:
				options.append(y * n + x)
		var pick: int = options[rng.randi_range(0, options.size() - 1)]
		prev = g
		tiles[g] = tiles[pick]
		tiles[pick] = tiles.size() - 1
		done += 1


func is_solved() -> bool:
	for k in tiles.size():
		if tiles[k] != k:
			return false
	return true


## Slides the tiles between `cell` and the gap (same row or column) one step toward the gap.
## Returns [[from_cell, to_cell, tile]] for animation, empty if the move is illegal.
func slide(cell: int) -> Array:
	if current < 0:
		return []
	var n := size()
	var g := gap()
	if cell == g or (cell % n != g % n and cell / n != g / n):
		return []
	var step := (1 if cell > g else -1) * (1 if cell / n == g / n else n)
	var out: Array = []
	var at := g
	while at != cell:
		var src := at + step
		out.append([src, at, tiles[src]])
		tiles[at] = tiles[src]
		at = src
	tiles[cell] = tiles.size() - 1
	moves += 1
	if is_solved():
		solved[current] = true
	return out


func to_dict() -> Dictionary:
	return {"solved": solved, "current": current, "tiles": tiles, "moves": moves}


func from_dict(d: Dictionary) -> void:
	var s: Array = d.get("solved", [])
	for i in mini(s.size(), solved.size()):
		solved[i] = bool(s[i])
	current = int(d.get("current", -1))
	tiles = []
	for t in d.get("tiles", []):
		tiles.append(int(t))
	moves = int(d.get("moves", 0))
	if current >= 0 and tiles.size() != SIZES[current] * SIZES[current]:
		current = -1
