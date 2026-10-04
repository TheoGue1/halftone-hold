extends Node
## Economy, prestige layers, achievements and persistence. Autoloaded as `Game`.

signal changed
signal tree_changed
signal levied(amount: float, crit: bool)
signal achievement_unlocked(title: String)
signal prestiged(kind: String, gain: float)
signal victory
signal offline_report(seconds: float, gold: float)
signal omen_spawned(kind: String)
signal omen_claimed(kind: String, text: String)
signal season_changed
signal relic_found(id: int, level: int)
signal card_resolved(symbols: Array, winners: Array, text: String)
signal oath_kept(title: String, completions: int)
signal feature_unlocked(id: String)
signal window_restored(index: int)

const SAVE_PATH := "user://halftone_hold.json"
const SAVE_VERSION := 1
const COST_GROWTH := 1.15
const HOARD_LIMIT := 1.79e308
const OFFLINE_CAP := 86400.0
const LEDGER_CAP_MULT := 3.0
const LEDGER_OFFLINE := 0.25
const AUTOSAVE_EVERY := 15.0
const CRUSADE_BASE := 3e5
const CRUSADE_EXP := 0.5
const DYNASTY_MIN := 1e9
const POINTS_PER_DOUBLING := 2.5
const BLOOD_POINTS_PER_DOUBLING := 4.0
const BASE_CLICK_GPS := 0.01
const BASE_CRIT_MULT := 5.0
const MAX_CRIT := 0.75
const BASE_OFFLINE := 0.25
const ACH_BONUS := 0.05
const RENOWN_POWER := 0.8
const BLOOD_POWER := 0.03
const CRUSADE_MIN_TIME := 60.0
const SOFTCAP_FACTOR := 10.0
const SOFTCAP_EXP := 0.2
const BLOOD_STEP := 2.5  # decades of renown per doubling of blood
const GPS_SCALE := 3.0
const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "UDc", "DDc", "TDc",
	"QaDc", "QiDc", "SxDc", "SpDc", "OcDc", "NoDc", "Vg"]

const BUILDINGS := [
	{"name": "Peasant", "cost": 15.0, "gps": 0.1, "desc": "Tills the royal soil for a crust of bread."},
	{"name": "Farmstead", "cost": 100.0, "gps": 1.0, "desc": "Barley, beans and the odd goose."},
	{"name": "Watermill", "cost": 1.1e3, "gps": 8.0, "desc": "Grinds grain and, somehow, coin."},
	{"name": "Smithy", "cost": 1.2e4, "gps": 47.0, "desc": "Horseshoes by day, swords by night."},
	{"name": "Market Town", "cost": 1.3e5, "gps": 260.0, "desc": "Tolls on every cart and cabbage."},
	{"name": "Abbey", "cost": 1.4e6, "gps": 1400.0, "desc": "Monks illuminate the ledgers in gold leaf."},
	{"name": "Castle", "cost": 2e7, "gps": 7800.0, "desc": "Stone walls, steep taxes."},
	{"name": "Royal Mint", "cost": 3.3e8, "gps": 4.4e4, "desc": "Stamps the king's face on everything."},
	{"name": "Wizard's Tower", "cost": 5.1e9, "gps": 2.6e5, "desc": "Transmutes lead, and patience."},
	{"name": "Dragon's Hoard", "cost": 7.5e10, "gps": 1.6e6, "desc": "Rent is negotiable. The dragon is not."},
	{"name": "Cathedral", "cost": 1e12, "gps": 1e7, "desc": "Indulgences, sold by the cartload."},
	{"name": "Celestial Citadel", "cost": 1.4e13, "gps": 6.5e7, "desc": "A fortress on the clouds, taxing the rain."},
]

const GOLD_ACH := [[1e3, "A Full Purse"], [1e6, "Coffers Creak"], [1e9, "Counting House"], [1e12, "Treasury"],
	[1e15, "Crown Jewels"], [1e20, "Rich as Croesus"], [1e30, "Gold Beyond Ledgers"], [1e50, "Dragon Envy"],
	[1e75, "Sea of Ducats"], [1e100, "A Googol of Gold"], [1e150, "Gilded Heavens"], [1e200, "Coin Eclipse"],
	[1e250, "The Sky Is Gold"], [1e300, "Edge of the Hoard"]]
const COUNT_ACH := [
	["clicks", 100, "Tax Collector"], ["clicks", 1000, "Sheriff of Nottingham"], ["clicks", 10000, "Writ of Iron"],
	["crusades", 1, "Take the Cross"], ["crusades", 5, "Veteran Crusader"], ["crusades", 25, "Holy Warlord"],
	["crusades", 100, "Endless Crusade"], ["dynasties", 1, "A New Bloodline"], ["dynasties", 3, "House of Ages"],
	["dynasties", 10, "Eternal Dynasty"], ["nodes", 10, "Apprentice"], ["nodes", 50, "Journeyman"],
	["nodes", 150, "Master of the Web"], ["nodes", 300, "Grand Vizier"], ["nodes", 500, "Arch-Sage"],
	["nodes", 700, "All-Knowing"], ["owned_total", 100, "Hamlet"], ["owned_total", 500, "Township"],
	["owned_total", 2000, "Kingdom"], ["owned_total", 10000, "Empire"]]
# Appended after the victory deed so saved achievement ids stay stable.
const EXTRA_ACH := [
	["omens", 10, "Augur"], ["omens", 100, "Seer of Signs"], ["cards", 10, "Gambler's Luck"],
	["cards", 100, "Reliquarian"], ["relics", 5, "Collector"], ["relics", 17, "Keeper of Relics"],
	["oaths", 1, "Sworn"], ["oaths", 12, "Oathbound"]]
const OMEN_WEIGHTS := {"cart": 40.0, "star": 30.0, "dragon": 15.0, "pilgrim": 15.0}
const FIRST_OMEN_DELAY := 45.0

var tree := PassiveTree.new()
var achievements: Array[Dictionary] = []

var gold := 0.0
var run_gold := 0.0
var total_gold := 0.0
var owned: Array[int] = []
var renown := 0.0
var blood := 0.0
var allocated := {0: true}
var achieved := {}
var clicks := 0
var crusades := 0
var dynasties := 0
var play_time := 0.0
var run_time := 0.0
var won := false
var won_time := -1.0
var buy_amount := 1  # 1, 10, 100 or -1 for max
var settings := {"notation": 0}
var relics := {}  # relic index -> level
var equipped: Array[int] = []
var card := {}  # {symbols, scratched, cost}; empty when no card is out
var free_cards := 0
var cards_opened := 0
var omens_claimed := 0
var buffs := {}  # omen id -> seconds left
var run_spoils := {}
var run_oath := ""
var oaths := {}  # oath id -> completions
var advisors := {}  # advisor id -> enabled
var rng := RandomNumberGenerator.new()
var unlocked := {}  # feature id -> true, see Content.UNLOCKS
var presets: Array = [[], []]  # saved web layouts, node ids in allocation order
var last_layout: Array = []  # web layout from before the latest dynasty
var last_dest := "holy"
var last_oath := ""
var table := CountingTable.new()
var chapel := Chapel.new()

var _add := {}
var _mul := {}
var _gps := -1.0  # cached; negative means dirty
var _save_timer := 0.0
var _ach_timer := 0.0
var _court_timer := 0.0
var _omen_timer := FIRST_OMEN_DELAY
var _season_idx := -1


func _init() -> void:
	owned.resize(BUILDINGS.size())
	owned.fill(0)
	for a in GOLD_ACH:
		achievements.append({"title": a[1], "kind": "gold", "value": a[0]})
	for i in BUILDINGS.size():
		achievements.append({"title": "First " + BUILDINGS[i].name, "kind": "own", "value": i})
	for a in COUNT_ACH:
		achievements.append({"title": a[2], "kind": a[0], "value": a[1]})
	achievements.append({"title": "The Infinite Hoard", "kind": "won", "value": 1})
	for a in EXTRA_ACH:
		achievements.append({"title": a[2], "kind": a[0], "value": a[1]})
	for i in achievements.size():
		achievements[i]["id"] = i


func _ready() -> void:
	load_game()


func _process(delta: float) -> void:
	tick(delta)
	_save_timer += delta
	if _save_timer >= AUTOSAVE_EVERY:
		_save_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


# --- Economy ------------------------------------------------------------------

func tick(dt: float) -> void:
	play_time += dt
	run_time += dt
	add_gold(gps() * dt + stat_add("auto") * click_value() * expected_crit() * dt)
	for k in buffs.keys():
		buffs[k] -= dt
		if buffs[k] <= 0.0:
			buffs.erase(k)
			_gps = -1.0
	if season_index() != _season_idx:
		_season_idx = season_index()
		_recompute()
		season_changed.emit()
	_omen_timer -= dt
	if _omen_timer <= 0.0 and has("omens"):
		_omen_timer = rng.randf_range(Content.OMEN_MIN_DELAY, Content.OMEN_MAX_DELAY)
		spawn_omen()
	if has("table"):
		table.tick(dt)
	_ach_timer += dt
	if _ach_timer >= 1.0:
		_ach_timer = 0.0
		check_achievements()
	_court_timer += dt
	if _court_timer >= 1.0:
		_court_timer = 0.0
		_run_court()


func add_gold(x: float) -> void:
	if x <= 0.0 or is_nan(x):
		return
	gold = minf(gold + x, HOARD_LIMIT)
	run_gold = minf(run_gold + x, HOARD_LIMIT)
	total_gold = minf(total_gold + x, HOARD_LIMIT)
	if gold >= HOARD_LIMIT and not won:
		won = true
		won_time = play_time
		check_achievements()
		victory.emit()


func stat_add(k: String) -> float:
	return _add.get(k, 0.0)


func stat_mul(k: String) -> float:
	return _mul.get(k, 1.0)


static func milestones(n: int) -> int:
	if n < 10: return 0
	if n < 25: return 1
	if n < 50: return 2
	if n < 100: return 3
	return 4 + int((n - 100) / 50.0)


func building_mult(i: int) -> float:
	return (1.0 + stat_add("b%d" % i)) * stat_mul("xb%d" % i) \
		* pow(2.0 + stat_add("milestone"), milestones(owned[i]))


func renown_power() -> float:
	return RENOWN_POWER + BLOOD_POWER * log(1.0 + blood) / log(2.0)


func global_mult() -> float:
	return (1.0 + stat_add("gold")) * stat_mul("xgold") * pow(1.0 + renown, renown_power()) \
		* (1.0 + blood) * (1.0 + ACH_BONUS * achieved.size()) \
		* (Content.STAR_MULT if buffs.has("star") else 1.0) * table.gold_mult()


func building_gps(i: int) -> float:
	return owned[i] * BUILDINGS[i].gps * GPS_SCALE * building_mult(i) * global_mult()


func gps() -> float:
	if _gps < 0.0:
		var total := 0.0
		for i in BUILDINGS.size():
			if owned[i] > 0:
				total += owned[i] * BUILDINGS[i].gps * GPS_SCALE * building_mult(i)
		_gps = minf(total * global_mult(), HOARD_LIMIT)
	return _gps


func cost_mult() -> float:
	return stat_mul("xcost") / (1.0 + stat_add("cost"))


## Cost of the next `k` buildings of type `i` (geometric series, log-space to dodge overflow).
func cost_of(i: int, k: int = 1) -> float:
	var g := COST_GROWTH
	var first := exp(log(BUILDINGS[i].cost * cost_mult()) + owned[i] * log(g))
	return first * (pow(g, k) - 1.0) / (g - 1.0)


func max_affordable(i: int) -> int:
	var first := cost_of(i, 1)
	if first > gold or is_inf(first):
		return 0
	var g := COST_GROWTH
	return int(minf(floor(log(gold * (g - 1.0) / first + 1.0) / log(g)), 1e6))


## amount: 0 uses the player's buy setting, -1 buys as many as affordable.
func buy(i: int, amount: int = 0) -> int:
	if amount == 0:
		amount = buy_amount
	var k := max_affordable(i)
	if amount > 0:
		k = mini(k, amount)
	if k <= 0:
		return 0
	gold = maxf(gold - cost_of(i, k), 0.0)
	owned[i] += k
	_gps = -1.0
	changed.emit()
	return k


func is_revealed(i: int) -> bool:
	return i == 0 or owned[i] > 0 or owned[i - 1] > 0 or total_gold >= BUILDINGS[i].cost


func click_value() -> float:
	return (1.0 + gps() * (BASE_CLICK_GPS + stat_add("click_gps"))) * (1.0 + stat_add("click")) * stat_mul("xclick")


func crit_chance() -> float:
	return 1.0 if buffs.has("dragon") else minf(stat_add("crit"), MAX_CRIT)


func crit_mult() -> float:
	return (BASE_CRIT_MULT + stat_add("critx")) * (Content.DRAGON_CRIT_MULT if buffs.has("dragon") else 1.0)


func expected_crit() -> float:
	return 1.0 + crit_chance() * (crit_mult() - 1.0)


func levy() -> float:
	clicks += 1
	var crit := randf() < crit_chance()
	var amount := click_value() * (crit_mult() if crit else 1.0)
	add_gold(amount)
	levied.emit(amount, crit)
	return amount


func offline_efficiency() -> float:
	return BASE_OFFLINE + stat_add("offline") + (LEDGER_OFFLINE if has("ledger") else 0.0)


# --- Prestige -----------------------------------------------------------------

func renown_mult() -> float:
	return (1.0 + stat_add("renown")) * stat_mul("xrenown") * (1.0 + blood)


func renown_gain() -> float:
	var raw := pow(run_gold / CRUSADE_BASE, CRUSADE_EXP) * renown_mult()
	var cap := softcap()
	return floor(raw if raw <= cap else cap * pow(raw / cap, SOFTCAP_EXP))


## Gains past this are heavily dampened so the late game cannot skip the tree.
func softcap() -> float:
	return SOFTCAP_FACTOR * (renown + 100.0)


func can_crusade() -> bool:
	return run_time >= CRUSADE_MIN_TIME and renown_gain() >= 1.0


func destination(id: String) -> Dictionary:
	for d in Content.DESTINATIONS:
		if d.id == id:
			return d
	return {}


func destination_unlocked(d: Dictionary) -> bool:
	return renown >= d.need_renown and dynasties >= d.need_dyn


func destination_gain(d: Dictionary) -> float:
	return maxf(1.0, floor(renown_gain() * d.renown))


func oath(id: String) -> Dictionary:
	for o in Content.OATHS:
		if o.id == id:
			return o
	return {}


## Renown a single crusade must yield, while sworn, to keep this oath once more.
func oath_goal(id: String) -> float:
	return pow(10.0, 2.0 + 3.0 * oaths.get(id, 0))


func can_swear(id: String) -> bool:
	return has("oaths") and not oath(id).is_empty() and oaths.get(id, 0) < Content.OATH_MAX


func oaths_completed() -> int:
	var n := 0
	for k in oaths:
		n += oaths[k]
	return n


## Returns home with Renown, then sets the next run's spoils and (optional) oath.
func crusade(dest_id: String = "holy", oath_id: String = "") -> bool:
	var d := destination(dest_id)
	if not can_crusade() or d.is_empty() or not destination_unlocked(d):
		return false
	var gain := destination_gain(d)
	if run_oath != "" and gain >= oath_goal(run_oath) and can_swear(run_oath):
		oaths[run_oath] = oaths.get(run_oath, 0) + 1
		oath_kept.emit(oath(run_oath).name, oaths[run_oath])
	renown = minf(renown + gain, HOARD_LIMIT)
	crusades += 1
	run_spoils = d.spoils.duplicate()
	run_oath = oath_id if can_swear(oath_id) else ""
	last_dest = dest_id
	last_oath = run_oath
	_reset_run()
	_recompute()
	if dest_id == "peaks":
		roll_relic(1)
	prestiged.emit("crusade", gain)
	return true


func blood_gain() -> float:
	if renown < DYNASTY_MIN:
		return 0.0
	return floor(pow(2.0, (log(renown) / log(10.0) - 9.0) / BLOOD_STEP) + 1e-9)


func dynasty() -> bool:
	var gain := blood_gain()
	if gain < 1.0:
		return false
	blood += gain
	renown = 0.0
	dynasties += 1
	last_layout = allocated.keys()
	allocated = {0: true}
	run_spoils = {}
	run_oath = ""
	_recompute()
	_reset_run()
	prestiged.emit("dynasty", gain)
	return true


func _reset_run() -> void:
	gold = 0.0
	run_gold = 0.0
	run_time = 0.0
	owned.fill(0)
	_gps = -1.0
	check_achievements()
	changed.emit()


# --- Passive tree -------------------------------------------------------------

func points_total() -> int:
	return int(floor(POINTS_PER_DOUBLING * log(1.0 + renown) / log(2.0))) \
		+ int(floor(BLOOD_POINTS_PER_DOUBLING * log(1.0 + blood) / log(2.0))) \
		+ Content.OATH_POINTS * oaths_completed() + Chapel.POINTS * chapel.solved_count()


func points_free() -> int:
	return points_total() - (allocated.size() - 1)


func can_allocate(id: int) -> bool:
	if allocated.has(id) or points_free() <= 0:
		return false
	for nb in tree.nodes[id].links:
		if allocated.has(nb):
			return true
	return false


func allocate(id: int) -> bool:
	if not can_allocate(id):
		return false
	allocated[id] = true
	_recompute()
	return true


## Unallocated nodes on the shortest route from the allocated web to `target`, nearest first.
func path_to(target: int) -> Array:
	if allocated.has(target):
		return []
	var prev := {}
	var queue: Array = allocated.keys()
	for id in queue:
		prev[id] = -1
	var head := 0
	while head < queue.size():
		var id: int = queue[head]
		head += 1
		if id == target:
			break
		for nb in tree.nodes[id].links:
			if not prev.has(nb):
				prev[nb] = id
				queue.append(nb)
	var path: Array = []
	var at := target
	while at >= 0 and not allocated.has(at):
		path.push_front(at)
		at = prev.get(at, -1)
	return path


## Closest node of `goals` (by web distance) reachable from the allocated web, or -1.
func _nearest(goals: Dictionary) -> int:
	if goals.is_empty():
		return -1
	var seen := allocated.duplicate()
	var queue: Array = allocated.keys()
	var head := 0
	while head < queue.size():
		var id: int = queue[head]
		head += 1
		for nb in tree.nodes[id].links:
			if seen.has(nb):
				continue
			if goals.has(nb):
				return nb
			seen[nb] = true
			queue.append(nb)
	return -1


## Allocates as much of the route to `target` as free points allow. Returns nodes allocated.
func allocate_path(target: int) -> int:
	var n := 0
	for id in path_to(target):
		if points_free() <= 0:
			break
		allocated[id] = true
		n += 1
	if n > 0:
		_recompute()
	return n


## Spends every free point. With `targets`, walks to the nearest target each time;
## otherwise takes the best neighbour: notables first, then empowered sectors. Never takes keystones.
func auto_spend(targets: Array = []) -> int:
	var spent := 0
	var empowered := [season().sector, weather().sector] if has("seasons") else []
	var goals := {}
	for t in targets:
		if not allocated.has(t):
			goals[t] = true
	while points_free() > 0:
		var pick := -1
		var goal := _nearest(goals)
		if goal >= 0:
			for id in path_to(goal):
				if points_free() <= 0:
					break
				allocated[id] = true
				goals.erase(id)
				spent += 1
			continue
		if pick < 0:
			var best := -INF
			for id in allocated:
				for nb in tree.nodes[id].links:
					var nd: Dictionary = tree.nodes[nb]
					if allocated.has(nb) or nd.kind == PassiveTree.Kind.KEYSTONE:
						continue
					var score: float = (10.0 if nd.kind == PassiveTree.Kind.NOTABLE else 0.0) \
						+ (5.0 if nd.sector in empowered or chapel.solved[nd.sector] else 0.0) - nd.ring * 0.1
					if score > best:
						best = score
						pick = nb
		if pick < 0:
			break
		allocated[pick] = true
		spent += 1
	if spent > 0:
		_recompute()
	return spent


func can_refund(id: int) -> bool:
	return id != 0 and allocated.has(id) and tree.connected_without(allocated, id)


func refund(id: int) -> bool:
	if not can_refund(id):
		return false
	allocated.erase(id)
	_recompute()
	return true


func reset_tree() -> void:
	allocated = {0: true}
	_recompute()


func _recompute() -> void:
	_add = {}
	_mul = {}
	var empowered := [season().sector, weather().sector] if has("seasons") else []
	if run_oath != "humility":
		for id in allocated:
			var n: Dictionary = tree.nodes[id]
			var add_mult := 1.0
			var mul_pow := 1.0
			if n.kind != PassiveTree.Kind.KEYSTONE and n.sector >= 0:
				if n.sector in empowered:
					add_mult *= Content.SEASON_ADD_MULT
					mul_pow *= Content.SEASON_MUL_POW
				if chapel.solved[n.sector]:
					add_mult *= Chapel.ADD_MULT
					mul_pow *= Chapel.MUL_POW
			_merge(n.mods, add_mult, mul_pow)
	for r in equipped:
		_merge(relic_mods(r))
	_merge(run_spoils)
	if run_oath != "":
		_merge(oath(run_oath).mods)
	if oaths_completed() > 0:
		_mul["xgold"] = stat_mul("xgold") * pow(Content.OATH_GOLD, oaths_completed())
	_gps = -1.0
	tree_changed.emit()
	changed.emit()


func _merge(mods: Dictionary, add_mult: float = 1.0, mul_pow: float = 1.0) -> void:
	for k: String in mods:
		var v: float = mods[k]
		if k.begins_with("x"):
			_mul[k] = stat_mul(k) * pow(v, mul_pow)
		else:
			_add[k] = stat_add(k) + v * add_mult


# --- Counting table & chapel (sliding) ----------------------------------------

## One slide on the counting table. Returns the board result plus "spawned", or {} if not allowed.
func table_slide(dir: Vector2i) -> Dictionary:
	if not has("table") or table.tally < 1.0:
		return {}
	if table.is_empty():
		table.clear(rng)
	var best_before := table.best
	var res := table.slide(dir)
	if not res.moved:
		return res
	table.tally -= 1.0
	for t: int in res.created:
		add_gold(gps() * CountingTable.SECONDS_PER_TIER * t + click_value())
	res["spawned"] = table.spawn(rng)
	if table.best != best_before:
		_gps = -1.0
	return res


func window_available(i: int) -> bool:
	return has("chapel") and dynasties >= Chapel.window_dynasty(i)


func chapel_start(i: int) -> bool:
	if not window_available(i) or chapel.solved[i]:
		return false
	chapel.start(i, rng)
	return true


func chapel_slide(cell: int) -> Array:
	var i := chapel.current
	var res := chapel.slide(cell)
	if i >= 0 and chapel.solved[i] and chapel.current == i:
		chapel.current = -1
		_recompute()
		window_restored.emit(i)
	return res


# --- Seasons ------------------------------------------------------------------

func season_index() -> int:
	return int(play_time / Content.SEASON_LENGTH)


func season() -> Dictionary:
	return Content.SEASONS[season_index() % Content.SEASONS.size()]


## Deterministic per season so it survives save/load; Clear 3 times in 5.
func weather() -> Dictionary:
	return Content.WEATHER[[0, 0, 0, 1, 2][posmod(hash(season_index() * 7919), 5)]]


func season_time_left() -> float:
	return Content.SEASON_LENGTH - fmod(play_time, Content.SEASON_LENGTH)


# --- Omens --------------------------------------------------------------------

func spawn_omen(kind: String = "") -> void:
	if kind == "":
		var kinds := OMEN_WEIGHTS.keys()
		if not has("relics"):
			kinds.erase("pilgrim")  # pilgrims bring reliquary cards, meaningless before the Reliquary opens
		kind = _weighted(kinds, kinds.map(func(k: String) -> float: return OMEN_WEIGHTS[k]))
	if advisor_on("falconer"):
		claim_omen(kind)
	else:
		omen_spawned.emit(kind)


func claim_omen(kind: String) -> String:
	var text := ""
	match kind:
		"cart":
			var amount := minf(gold * 0.25, gps() * 900.0) + gps() * 60.0 + click_value() * 20.0
			add_gold(amount)
			text = "+%s gold" % fmt(amount)
		"star", "dragon":
			buffs[kind] = Content.OMENS[kind].buff
			_gps = -1.0
			text = Content.OMENS[kind].desc
		"pilgrim":
			free_cards += 1
			text = "A free scratch-card, waiting in the Relics tab"
	omens_claimed += 1
	omen_claimed.emit(kind, text)
	return text


func _weighted(items: Array, weights: Array) -> Variant:
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for i in items.size():
		roll -= weights[i]
		if roll <= 0.0:
			return items[i]
	return items.back()


# --- Relics & reliquary cards -------------------------------------------------

func relic_mods(i: int) -> Dictionary:
	var level: int = relics.get(i, 0)
	var out := {}
	for k: String in Content.RELICS[i].mods:
		var v: float = Content.RELICS[i].mods[k]
		out[k] = pow(v, 1.0 + 0.5 * (level - 1)) if k.begins_with("x") else v * level
	return out


func relic_slots() -> int:
	var n := Content.BASE_RELIC_SLOTS
	for d in Content.SLOT_DYNASTIES:
		if dynasties >= d:
			n += 1
	return n


func roll_relic(min_rarity: int = 0) -> int:
	var tiers: Array = []
	var weights: Array = []
	for r in range(min_rarity, Content.RARITIES.size()):
		tiers.append(r)
		weights.append(Content.RARITIES[r].weight)
	var rarity: int = _weighted(tiers, weights)
	var pool: Array = []
	for i in Content.RELICS.size():
		if Content.RELICS[i].rarity == rarity:
			pool.append(i)
	var id: int = pool[rng.randi_range(0, pool.size() - 1)]
	relics[id] = mini(relics.get(id, 0) + 1, Content.RELIC_MAX_LEVEL)
	if id not in equipped and equipped.size() < relic_slots():
		equipped.append(id)
	_recompute()
	relic_found.emit(id, relics[id])
	return id


func toggle_equip(i: int) -> bool:
	if i in equipped:
		equipped.erase(i)
	elif relics.has(i) and equipped.size() < relic_slots():
		equipped.append(i)
	else:
		return false
	_recompute()
	return true


func card_cost() -> float:
	return maxf(Content.CARD_MIN_COST, gps() * Content.CARD_SECONDS)


func buy_card() -> bool:
	if not card.is_empty():
		return false
	var cost := card_cost()
	if free_cards > 0:
		free_cards -= 1
	elif gold >= cost:
		gold -= cost
	else:
		return false
	var symbols: Array = []
	for i in Content.CARD_CELLS:
		symbols.append(_weighted(Content.SYMBOLS, Content.SYMBOL_WEIGHTS))
	var scratched: Array = []
	scratched.resize(Content.CARD_CELLS)
	scratched.fill(0.0)
	card = {"symbols": symbols, "scratched": scratched, "cost": cost}
	changed.emit()
	return true


## Scratches `amount` (0..1) off a cell; the card pays out once every cell is uncovered.
func scratch(cell: int, amount: float) -> void:
	if card.is_empty():
		return
	card.scratched[cell] = minf(card.scratched[cell] + amount, 1.0)
	for v in card.scratched:
		if v < 1.0:
			return
	_resolve_card()


func reveal_card() -> void:
	if card.is_empty():
		return
	card.scratched.fill(1.0)
	_resolve_card()


func _resolve_card() -> void:
	var symbols: Array = card.symbols
	var cost: float = card.cost
	card = {}
	cards_opened += 1
	var count := {}
	for sym in symbols:
		count[sym] = count.get(sym, 0) + 1
	var lines: PackedStringArray = []
	var winners: Array = []
	if count.get("coin", 0) >= 3:
		var g: float = cost * (count.coin - 1)
		add_gold(g)
		lines.append("Coins! +%s gold" % fmt(g))
		winners.append("coin")
	if count.get("crown", 0) >= 3:
		var g: float = cost * 6.0 * (count.crown - 2)
		add_gold(g)
		lines.append("Crowns! +%s gold" % fmt(g))
		winners.append("crown")
	if count.get("chalice", 0) >= 3:
		lines.append("Chalices! An omen appears")
		winners.append("chalice")
	if count.get("relic", 0) >= 2:
		var relic_count: int = count.relic
		var id := roll_relic(0 if relic_count < 3 else (1 if relic_count < 5 else 2))
		lines.append("Relic: %s" % Content.RELICS[id].name)
		winners.append("relic")
	if lines.is_empty():
		lines.append("Only bones. Better luck next time.")
	card_resolved.emit(symbols, winners, "\n".join(lines))
	if "chalice" in winners:
		spawn_omen()
	changed.emit()


# --- Royal court --------------------------------------------------------------

func advisor_unlocked(a: Dictionary) -> bool:
	return achieved.size() >= a.deeds


func advisor_on(id: String) -> bool:
	if not advisors.get(id, false):
		return false
	for a in Content.ADVISORS:
		if a.id == id:
			return advisor_unlocked(a)
	return false


## Affordable holding with the best gold/s per gold spent, or -1.
func best_building() -> int:
	var best := -1
	var best_ratio := 0.0
	for i in BUILDINGS.size():
		var c := cost_of(i)
		if c > gold:
			continue
		var ratio: float = BUILDINGS[i].gps * building_mult(i) / c
		if ratio > best_ratio:
			best_ratio = ratio
			best = i
	return best


func _run_court() -> void:
	if advisor_on("steward"):
		for _n in 50:
			var b := best_building()
			if b < 0:
				break
			buy(b, 1)
	if advisor_on("marshal") and can_crusade() and renown_gain() >= maxf(10.0, renown):
		crusade("holy", "")
	if advisor_on("regent") and blood_gain() >= maxf(1.0, blood):
		dynasty()
	if advisor_on("abbot") and card.is_empty() and gold >= 20.0 * card_cost() and buy_card():
		reveal_card()


func describe_mods(mods: Dictionary) -> String:
	var lines: PackedStringArray = []
	for k: String in mods:
		var v: float = mods[k]
		var base := k.substr(1) if k.begins_with("x") else k
		var what := _stat_label(base)
		if k.begins_with("x"):
			lines.append("×%s %s" % [_short(v), what])
			continue
		match base:
			"click_gps": lines.append("Levies also take +%s%% of gold/s" % _short(v * 100.0))
			"cost": lines.append("+%s%% haggling (holdings cheaper)" % _short(v * 100.0))
			"crit": lines.append("+%s%% critical levy chance" % _short(v * 100.0))
			"critx": lines.append("+%s× critical levy power" % _short(v))
			"auto": lines.append("+%s automatic levies per second" % _short(v))
			"milestone": lines.append("Milestones +%s stronger" % _short(v))
			_: lines.append("+%s%% %s" % [_short(v * 100.0), what])
	return "\n".join(lines)


func _stat_label(base: String) -> String:
	if base.begins_with("b") and base.substr(1).is_valid_int():
		return BUILDINGS[int(base.substr(1))].name + " output"
	match base:
		"gold": return "all gold"
		"click": return "levy gold"
		"cost": return "holding costs"
		"renown": return "Renown gained"
		"offline": return "offline earnings"
	return base


func _short(v: float) -> String:
	return String.num(snappedf(v, 0.01)) if v < 100.0 else fmt(v)


# --- Achievements -------------------------------------------------------------

func check_achievements() -> void:
	var before := achieved.size()
	var total_owned := 0
	for n in owned:
		total_owned += n
	for a in achievements:
		if achieved.has(a.id):
			continue
		var ok := false
		match a.kind:
			"gold": ok = total_gold >= a.value
			"own": ok = owned[a.value] > 0
			"clicks": ok = clicks >= a.value
			"crusades": ok = crusades >= a.value
			"dynasties": ok = dynasties >= a.value
			"nodes": ok = allocated.size() - 1 >= a.value
			"owned_total": ok = total_owned >= a.value
			"omens": ok = omens_claimed >= a.value
			"cards": ok = cards_opened >= a.value
			"relics": ok = relics.size() >= a.value
			"oaths": ok = oaths_completed() >= a.value
			"won": ok = won
		if ok:
			achieved[a.id] = true
			achievement_unlocked.emit(a.title)
	if achieved.size() != before:
		_gps = -1.0
	check_unlocks()


func has(feature: String) -> bool:
	return unlocked.has(feature)


func unlock_ready(id: String) -> bool:
	var total_owned := 0
	for n in owned:
		total_owned += n
	match id:
		"buy10": return total_owned >= 25
		"omens": return total_gold >= 2000.0
		"crusade": return crusades > 0 or total_gold >= CRUSADE_BASE * 0.3
		"web", "buymax": return crusades >= 1
		"hold": return clicks >= 1000
		"relics": return crusades >= 3
		"map": return renown >= 1e3 or dynasties > 0
		"court": return achieved.size() >= Content.ADVISORS[0].deeds
		"repeat": return crusades >= 15
		"dynasty": return dynasties > 0 or renown >= DYNASTY_MIN * 0.001
		"reveal": return cards_opened >= 10
		"seasons": return dynasties >= 1
		"slot1": return dynasties >= Content.SLOT_DYNASTIES[0]
		"presets": return dynasties >= 3
		"peaks": return dynasties >= destination("peaks").need_dyn
		"oaths": return dynasties >= 5
		"silk": return dynasties >= destination("silk").need_dyn
		"slot2": return dynasties >= Content.SLOT_DYNASTIES[1]
		"ledger": return dynasties >= 10
		"slot3": return dynasties >= Content.SLOT_DYNASTIES[2]
		"table": return dynasties >= 2
		"chapel": return dynasties >= Chapel.window_dynasty(0)
		"window2", "window3", "window4", "window5", "window6":
			return dynasties >= Chapel.window_dynasty(int(id.substr(6)) - 1)
	return false


## Unlocks every feature whose condition holds, in order; `silent` skips the announcement (save load).
func check_unlocks(silent: bool = false) -> void:
	for u in Content.UNLOCKS:
		if not unlocked.has(u.id) and unlock_ready(u.id):
			unlocked[u.id] = true
			if u.id == "seasons":
				_recompute()
			if not silent:
				feature_unlocked.emit(u.id)


func save_preset(i: int) -> void:
	presets[i] = allocated.keys()


## Re-allocates a saved layout as far as points allow. Multiple passes cover ids saved out of path order.
func load_preset(i: int) -> void:
	rebuild_layout(presets[i])


## Clears the web and re-allocates `ids` as far as points allow. Multiple passes cover out-of-order ids.
func rebuild_layout(ids: Array) -> void:
	allocated = {0: true}
	var pending: Array = ids.duplicate()
	var progress := true
	while progress and points_free() > 0:
		progress = false
		for id in pending.duplicate():
			if can_allocate(int(id)):
				allocated[int(id)] = true
				pending.erase(id)
				progress = true
	_recompute()


# --- Formatting ---------------------------------------------------------------

func fmt(x: float) -> String:
	if is_nan(x):
		return "?"
	if x < 0.0:
		return "-" + fmt(-x)
	if is_inf(x) or x >= HOARD_LIMIT:
		return "∞"
	if x < 10.0:
		return "%d" % int(x) if x == floor(x) else "%.1f" % x
	if x < 1000.0:
		return "%d" % int(x)
	var e := int(floor(log(x) / log(10.0) + 1e-9))
	var t := int(e / 3.0)
	if settings.notation == 1 or t >= SUFFIXES.size():
		return "%.2fe%d" % [x / pow(10.0, e), e]
	return "%.2f%s" % [x / pow(10.0, t * 3), SUFFIXES[t]]


static func fmt_time(s: float) -> String:
	var t := int(s)
	if t >= 3600:
		return "%dh %02dm" % [int(t / 3600.0), int((t % 3600) / 60.0)]
	return "%dm %02ds" % [int(t / 60.0), t % 60]


# --- Persistence --------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"v": SAVE_VERSION, "gold": gold, "run_gold": run_gold, "total_gold": total_gold, "owned": owned,
		"renown": renown, "blood": blood, "allocated": allocated.keys(), "achieved": achieved.keys(),
		"clicks": clicks, "crusades": crusades, "dynasties": dynasties, "play_time": play_time,
		"run_time": run_time, "won": won, "won_time": won_time, "buy_amount": buy_amount,
		"settings": settings, "relics": relics, "equipped": equipped, "card": card, "free_cards": free_cards,
		"cards_opened": cards_opened, "omens_claimed": omens_claimed, "run_spoils": run_spoils,
		"run_oath": run_oath, "oaths": oaths, "advisors": advisors, "unlocked": unlocked, "presets": presets,
		"last_dest": last_dest, "last_oath": last_oath, "table": table.to_dict(), "chapel": chapel.to_dict(),
		"last_layout": last_layout,
		"saved_at": Time.get_unix_time_from_system()}


func from_dict(d: Dictionary) -> void:
	gold = d.get("gold", 0.0)
	run_gold = d.get("run_gold", 0.0)
	total_gold = d.get("total_gold", 0.0)
	var saved_owned: Array = d.get("owned", [])
	for i in mini(saved_owned.size(), owned.size()):
		owned[i] = int(saved_owned[i])
	renown = d.get("renown", 0.0)
	blood = d.get("blood", 0.0)
	allocated = {0: true}
	for id in d.get("allocated", []):
		if int(id) < tree.nodes.size():
			allocated[int(id)] = true
	achieved = {}
	for id in d.get("achieved", []):
		achieved[int(id)] = true
	clicks = int(d.get("clicks", 0))
	crusades = int(d.get("crusades", 0))
	dynasties = int(d.get("dynasties", 0))
	play_time = d.get("play_time", 0.0)
	run_time = d.get("run_time", 0.0)
	won = d.get("won", false)
	won_time = d.get("won_time", -1.0)
	buy_amount = int(d.get("buy_amount", 1))
	settings.merge(d.get("settings", {}), true)
	relics = {}
	for k in d.get("relics", {}):
		if int(k) < Content.RELICS.size():
			relics[int(k)] = int(d.relics[k])
	equipped.clear()
	for id in d.get("equipped", []):
		if relics.has(int(id)):
			equipped.append(int(id))
	card = d.get("card", {})
	free_cards = int(d.get("free_cards", 0))
	cards_opened = int(d.get("cards_opened", 0))
	omens_claimed = int(d.get("omens_claimed", 0))
	run_spoils = d.get("run_spoils", {})
	run_oath = d.get("run_oath", "")
	oaths = {}
	for k in d.get("oaths", {}):
		oaths[k] = int(d.oaths[k])
	advisors = d.get("advisors", {})
	unlocked = d.get("unlocked", {})
	presets = d.get("presets", [[], []])
	last_layout = d.get("last_layout", [])
	last_dest = d.get("last_dest", "holy")
	last_oath = d.get("last_oath", "")
	table = CountingTable.new()
	table.from_dict(d.get("table", {}))
	chapel = Chapel.new()
	chapel.from_dict(d.get("chapel", {}))
	buffs = {}
	check_unlocks(true)
	_recompute()


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(to_dict()))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_recompute()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_warning("Save file unreadable, starting fresh")
		_recompute()
		return
	from_dict(parsed)
	var cap := OFFLINE_CAP * (LEDGER_CAP_MULT if has("ledger") else 1.0)
	var away := clampf(Time.get_unix_time_from_system() - parsed.get("saved_at", 0.0), 0.0, cap)
	if away > 60.0:
		var earned := gps() * away * offline_efficiency()
		add_gold(earned)
		offline_report.emit.call_deferred(away, earned)


func wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	from_dict({})
	_reset_run()
	tree_changed.emit()
