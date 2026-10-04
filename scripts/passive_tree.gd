class_name PassiveTree
extends RefCounted
## Deterministic passive web: 6 sectors x 14 rings around the Throne (~720 nodes).

enum Kind { SMALL, NOTABLE, KEYSTONE, ROOT }

const RINGS := 14
const RING0_RADIUS := 170.0
const RING_STEP := 115.0
const KEYSTONE_RINGS := [6, 10, 13]
const BRIDGE_RINGS := [2, 5, 8, 11, 13]
const NOTABLE_CHANCE := 0.17
const SEED := 1337

const SECTORS := [
	{"name": "Harvest", "color": Color(0.33, 0.55, 0.18), "stats": ["b0", "b1", "b2", "gold", "offline"],
		"nouns": ["Furrow", "Sheaf", "Orchard", "Meadow", "Granary", "Plough"]},
	{"name": "Forge", "color": Color(0.5, 0.27, 0.12), "stats": ["click", "click_gps", "crit", "critx", "b3", "b6"],
		"nouns": ["Anvil", "Hammer", "Bellows", "Ingot", "Rampart", "Gauntlet"]},
	{"name": "Coin", "color": Color(0.85, 0.62, 0.08), "stats": ["cost", "gold", "b4", "b7"],
		"nouns": ["Ledger", "Ducat", "Scale", "Charter", "Guild", "Strongbox"]},
	{"name": "Faith", "color": Color(0.2, 0.38, 0.72), "stats": ["renown", "b5", "b10", "milestone"],
		"nouns": ["Chalice", "Psalm", "Reliquary", "Vigil", "Bell", "Censer"]},
	{"name": "Arcana", "color": Color(0.45, 0.2, 0.6), "stats": ["auto", "offline", "b8", "b11", "gold"],
		"nouns": ["Grimoire", "Astrolabe", "Sigil", "Athanor", "Orrery", "Rune"]},
	{"name": "War", "color": Color(0.72, 0.1, 0.08), "stats": ["renown", "crit", "critx", "b9", "click"],
		"nouns": ["Banner", "Lance", "Warhorn", "Siege", "Oath", "Pennant"]},
]

const ADJECTIVES := ["Gilded", "Hallowed", "Iron", "Silver", "Ashen", "Crimson", "Sable", "Verdant",
	"Ancient", "Blessed", "Burning", "Royal", "Wandering", "Stalwart", "Gloaming", "Thorned", "Gleaming", "Sworn"]

const SMALL_TITLES := {
	"gold": "Tithe", "click": "Firm Hand", "click_gps": "Tax Roll", "cost": "Haggling", "renown": "Glory",
	"offline": "Stewardship", "crit": "Keen Eye", "critx": "Heavy Blow", "auto": "Reeve", "milestone": "Heraldry",
	"b0": "Peasantry", "b1": "Husbandry", "b2": "Millwright", "b3": "Smithing", "b4": "Trade", "b5": "Devotion",
	"b6": "Masonry", "b7": "Minting", "b8": "Sorcery", "b9": "Wyrmlore", "b10": "Liturgy", "b11": "Starcraft",
}

# One keystone per sector per KEYSTONE_RINGS tier: big power, real drawback.
const KEYSTONES := [
	[{"name": "Bountiful Earth", "mods": {"xb0": 25.0, "xb1": 10.0, "xb2": 5.0, "xclick": 0.5}},
		{"name": "Serf's Covenant", "mods": {"xgold": 4.0, "xcost": 1.5}},
		{"name": "Eternal Harvest", "mods": {"xgold": 12.0, "xrenown": 0.8}}],
	[{"name": "Iron Fist", "mods": {"xclick": 8.0, "xgold": 0.8}},
		{"name": "Hammer of Dawn", "mods": {"xb3": 30.0, "xb6": 30.0}},
		{"name": "Anvil of Ages", "mods": {"click_gps": 0.25, "xclick": 20.0, "xgold": 0.7}}],
	[{"name": "Usury", "mods": {"xcost": 0.6, "xrenown": 0.85}},
		{"name": "Gilded Ledger", "mods": {"xgold": 3.0, "xb4": 10.0, "xb7": 10.0}},
		{"name": "Midas Touch", "mods": {"xcost": 0.25, "xclick": 0.0}}],
	[{"name": "Pilgrimage", "mods": {"xrenown": 1.6, "xgold": 0.75}},
		{"name": "Holy Relics", "mods": {"milestone": 0.5, "xclick": 0.5}},
		{"name": "Divine Right", "mods": {"xrenown": 3.0, "xcost": 1.3}}],
	[{"name": "Familiar", "mods": {"auto": 5.0, "xclick": 0.6}},
		{"name": "Hourglass", "mods": {"offline": 1.0, "xgold": 2.0}},
		{"name": "Philosopher's Stone", "mods": {"xgold": 25.0, "xrenown": 0.6}}],
	[{"name": "Blood Oath", "mods": {"crit": 0.15, "critx": 10.0}},
		{"name": "Wyrmslayer", "mods": {"xb9": 50.0, "xgold": 1.5}},
		{"name": "Holy Crusade", "mods": {"xrenown": 2.5, "xgold": 2.0}}],
]

## Each node: {id, pos, kind, sector, ring, name, mods, links}
var nodes: Array[Dictionary] = []


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	nodes.append(_node(Vector2.ZERO, Kind.ROOT, -1, -1, "The Throne", {}))
	var span := TAU / SECTORS.size()
	var grid: Array = []  # grid[sector][ring] -> Array of node ids
	for s in SECTORS.size():
		var rings: Array = []
		for r in RINGS:
			var n := 2 + r
			var ids: Array[int] = []
			for k in n:
				var ang := -PI / 2.0 + s * span + span * (0.06 + 0.88 * (k + 0.5) / n)
				var pos := Vector2.from_angle(ang) * (RING0_RADIUS + r * RING_STEP)
				ids.append(nodes.size())
				nodes.append(_roll(rng, pos, s, r, k == int(n / 2.0)))
			rings.append(ids)
		grid.append(rings)

	for s in grid.size():
		for r in RINGS:
			var ids: Array = grid[s][r]
			for k in ids.size():
				if r == 0:
					_link(0, ids[k])
				else:
					var prev: Array = grid[s][r - 1]
					_link(ids[k], prev[mini(int((k + 0.5) / ids.size() * prev.size()), prev.size() - 1)])
				if k + 1 < ids.size() and (r % 2 == 0 or k % 3 == 0):
					_link(ids[k], ids[k + 1])
	for r in BRIDGE_RINGS:
		for s in grid.size():
			_link(grid[s][r].back(), grid[(s + 1) % grid.size()][r][0])


func _roll(rng: RandomNumberGenerator, pos: Vector2, s: int, r: int, middle: bool) -> Dictionary:
	var sector: Dictionary = SECTORS[s]
	var stats: Array = sector.stats
	if middle and r in KEYSTONE_RINGS:
		var ks: Dictionary = KEYSTONES[s][KEYSTONE_RINGS.find(r)]
		return _node(pos, Kind.KEYSTONE, s, r, ks.name, ks.mods)
	var stat: String = stats[rng.randi_range(0, stats.size() - 1)]
	if r >= 1 and rng.randf() < NOTABLE_CHANCE:
		var title := "%s %s" % [ADJECTIVES[rng.randi_range(0, ADJECTIVES.size() - 1)],
			sector.nouns[rng.randi_range(0, sector.nouns.size() - 1)]]
		return _node(pos, Kind.NOTABLE, s, r, title, notable_mods(stat, r))
	return _node(pos, Kind.SMALL, s, r, SMALL_TITLES[stat], small_mods(stat, r))


static func small_mods(stat: String, r: int) -> Dictionary:
	match stat:
		"click_gps": return {stat: 0.002 + 0.0005 * r}
		"cost": return {stat: 0.04 + 0.01 * r}
		"renown": return {stat: 0.06 + 0.02 * r}
		"offline": return {stat: 0.05}
		"crit": return {stat: 0.01}
		"critx": return {stat: 0.25 + 0.05 * r}
		"auto": return {stat: 0.2 + 0.05 * r}
		"milestone": return {stat: 0.03 + 0.005 * r}
	return {stat: 0.10 + 0.05 * r}  # gold, click, per-building


static func notable_mods(stat: String, r: int) -> Dictionary:
	match stat:
		"gold": return {"xgold": 1.1 + 0.02 * r}
		"click": return {"xclick": 1.3 + 0.05 * r}
		"click_gps": return {"click_gps": 0.01, "xclick": 1.2}
		"cost": return {"xcost": 1.0 / (1.05 + 0.01 * r)}
		"renown": return {"xrenown": 1.05 + 0.01 * r}
		"offline": return {"offline": 0.2, "gold": 0.5}
		"crit": return {"crit": 0.03, "critx": 1.0}
		"critx": return {"critx": 2.0 + 0.3 * r}
		"auto": return {"auto": 1.0 + 0.25 * r}
		"milestone": return {"milestone": 0.12}
	return {"x" + stat: 1.5 + 0.1 * r}  # per-building


func _node(pos: Vector2, kind: Kind, s: int, r: int, title: String, mods: Dictionary) -> Dictionary:
	return {"id": nodes.size(), "pos": pos, "kind": kind, "sector": s, "ring": r,
		"name": title, "mods": mods, "links": []}


func _link(a: int, b: int) -> void:
	if b in nodes[a].links:
		return
	nodes[a].links.append(b)
	nodes[b].links.append(a)


## True if every id in `allocated` stays reachable from the root without `removed`.
func connected_without(allocated: Dictionary, removed: int) -> bool:
	var seen := {0: true}
	var stack: Array[int] = [0]
	while not stack.is_empty():
		for nb in nodes[stack.pop_back()].links:
			if nb != removed and allocated.has(nb) and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return seen.size() == allocated.size() - (1 if allocated.has(removed) else 0)
