class_name CountingTable
extends RefCounted
## 2048-style coin board. Slides cost tally sticks, which regrow; the best coin ever minted is a permanent multiplier.

const SIZE := 4
const COINS := ["Penny", "Silver Penny", "Groat", "Shilling", "Florin", "Ducat", "Noble", "Angel", "Crown",
	"Sovereign", "Dragon Coin", "Star of Gold"]
const TALLY_CAP := 60.0
const TALLY_EVERY := 4.0  # seconds per stick
const START_TALLY := 20.0
const BEST_MULT := 1.3  # gold ×1.3 per coin tier above the Penny
const SECONDS_PER_TIER := 3.0  # a merge into tier t pays t × this many seconds of income
const SPAWN_SILVER_CHANCE := 0.1
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var board: Array = []  # SIZE*SIZE tiers, 0 = empty
var best := 0
var tally := START_TALLY
var merges := 0


func _init() -> void:
	board.resize(SIZE * SIZE)
	board.fill(0)


func gold_mult() -> float:
	return pow(BEST_MULT, maxi(best - 1, 0))


func tick(dt: float) -> void:
	tally = minf(tally + dt / TALLY_EVERY, TALLY_CAP)


func is_empty() -> bool:
	return board.max() == 0


func clear(rng: RandomNumberGenerator) -> void:
	board.fill(0)
	spawn(rng)
	spawn(rng)


func spawn(rng: RandomNumberGenerator) -> int:
	var free: Array = []
	for i in board.size():
		if board[i] == 0:
			free.append(i)
	if free.is_empty():
		return -1
	var at: int = free[rng.randi_range(0, free.size() - 1)]
	board[at] = 2 if rng.randf() < SPAWN_SILVER_CHANCE else 1
	best = maxi(best, board[at])
	return at


func can_move() -> bool:
	for i in board.size():
		if board[i] == 0:
			return true
		var x := i % SIZE
		if x + 1 < SIZE and board[i] == board[i + 1]:
			return true
		if i + SIZE < board.size() and board[i] == board[i + SIZE]:
			return true
	return false


## Cell indices of each line, ordered from the edge tiles slide toward.
static func lines(dir: Vector2i) -> Array:
	var out: Array = []
	for a in SIZE:
		var line: Array = []
		for b in SIZE:
			var k := SIZE - 1 - b if dir == Vector2i.RIGHT or dir == Vector2i.DOWN else b
			line.append(a * SIZE + k if dir.y == 0 else k * SIZE + a)
		out.append(line)
	return out


## Slides every coin toward `dir`. Returns {moved, slides: [[from, to, tier]], merged: [cell], created: [tier]}.
## Does not spend tally or spawn; Game does that so it can pay out.
func slide(dir: Vector2i) -> Dictionary:
	var next: Array = []
	next.resize(board.size())
	next.fill(0)
	var slides: Array = []
	var merged: Array = []
	var created: Array = []
	var moved := false
	for line in lines(dir):
		var target := 0
		var last := 0  # tier at line[target - 1] that may still merge
		for k in SIZE:
			var from: int = line[k]
			var tier: int = board[from]
			if tier == 0:
				continue
			var to: int
			if tier == last:
				to = line[target - 1]
				next[to] = tier + 1
				merged.append(to)
				created.append(tier + 1)
				last = 0
			else:
				to = line[target]
				next[to] = tier
				last = tier
				target += 1
			slides.append([from, to, tier])
			moved = moved or from != to or tier == next[to] - 1
	if moved:
		board = next
		merges += created.size()
		for t in created:
			best = maxi(best, t)
	return {"moved": moved, "slides": slides, "merged": merged, "created": created}


func to_dict() -> Dictionary:
	return {"board": board, "best": best, "tally": tally, "merges": merges}


func from_dict(d: Dictionary) -> void:
	var saved: Array = d.get("board", [])
	board.fill(0)
	for i in mini(saved.size(), board.size()):
		board[i] = int(saved[i])
	best = int(d.get("best", 0))
	tally = float(d.get("tally", START_TALLY))
	merges = int(d.get("merges", 0))
