extends SceneTree
## Headless checks + pacing simulation.
## godot --headless --path . --script tests/self_check.gd [-- sim]

const GameScript := preload("res://scripts/game.gd")
const SIM_HOURS := 30.0
const DT := 2.0

var failures := 0


func _init() -> void:
	check_tree()
	check_economy()
	check_save_roundtrip()
	check_format()
	check_systems()
	check_sliding()
	check_fast_allocation()
	if "sim" in OS.get_cmdline_user_args():
		simulate()
	print("FAILURES: %d" % failures)
	quit(1 if failures else 0)


func expect(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + what)


func check_tree() -> void:
	var t := PassiveTree.new()
	print("tree nodes: %d" % t.nodes.size())
	expect(t.nodes.size() > 700, "tree is big")
	var all := {}
	for n in t.nodes:
		all[n.id] = true
		expect(n.id == t.nodes.find(n), "ids are indexes")
		for nb in n.links:
			expect(n.id in t.nodes[nb].links, "links symmetric")
	expect(t.connected_without(all, -1), "whole tree reachable from throne")
	var kinds := [0, 0, 0, 0]
	for n in t.nodes:
		kinds[n.kind] += 1
	print("small/notable/keystone/root: %s" % [kinds])
	expect(kinds[PassiveTree.Kind.KEYSTONE] == 18, "18 keystones")
	var min_d := INF
	for a in t.nodes:
		for b in t.nodes:
			if a.id < b.id:
				min_d = minf(min_d, a.pos.distance_to(b.pos))
	print("min node spacing: %.1f" % min_d)
	expect(min_d > 60.0, "nodes do not overlap")


func check_economy() -> void:
	var g: Node = GameScript.new()
	expect(g.cost_of(0) == 15.0, "first peasant costs 15")
	expect(is_equal_approx(g.cost_of(0, 2), 15.0 + 15.0 * 1.15), "geometric cost")
	g.gold = 1000.0
	var k: int = g.max_affordable(0)
	expect(g.cost_of(0, k) <= 1000.0 and g.cost_of(0, k + 1) > 1000.0, "max_affordable exact")
	expect(g.buy(0, -1) == k and g.owned[0] == k, "buy max")
	expect(g.gold >= 0.0, "gold not negative")
	expect(g.renown_gain() == 0.0 and not g.crusade(), "no early crusade")
	g.run_gold = g.CRUSADE_BASE * 100.0
	expect(g.renown_gain() == 10.0, "100x base gold -> 10 renown")
	expect(not g.can_crusade(), "crusade needs muster time")
	g.run_time = g.CRUSADE_MIN_TIME
	expect(g.crusade() and g.renown == 10.0 and g.owned[0] == 0, "crusade resets run")
	expect(g.points_total() == 8, "10 renown -> 8 points")
	var first: int = g.tree.nodes[0].links[0]
	var far: int = g.tree.nodes.size() - 1
	expect(not g.can_allocate(far), "cannot allocate disconnected node")
	expect(g.allocate(first), "allocate next to throne")
	var second: int = -1
	for nb in g.tree.nodes[first].links:
		if nb != 0:
			second = nb
	expect(g.allocate(second), "allocate chain")
	expect(not g.can_refund(first), "cannot orphan a chain")
	expect(g.refund(second) and g.refund(first), "refund leaf first")
	g.renown = 1e9 * pow(10.0, g.BLOOD_STEP)
	expect(g.blood_gain() == 2.0, "one blood step -> 2 blood")
	expect(g.dynasty() and g.renown == 0.0 and g.allocated.size() == 1, "dynasty resets renown + tree")
	g.free()


func check_save_roundtrip() -> void:
	var a: Node = GameScript.new()
	a.gold = 123.0
	a.owned[3] = 7
	a.renown = 1e5
	a.allocated[a.tree.nodes[0].links[0]] = true
	var b: Node = GameScript.new()
	b.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	expect(b.gold == 123.0 and b.owned[3] == 7 and b.renown == 1e5, "save roundtrip values")
	expect(b.allocated.size() == 2, "save roundtrip tree")
	a.free()
	b.free()


func check_format() -> void:
	var g: Node = GameScript.new()
	for c in [[0.1, "0.1"], [5.0, "5"], [999.0, "999"], [1500.0, "1.50K"], [2.5e9, "2.50B"],
			[1e70, "1.00e70"], [INF, "∞"]]:
		expect(g.fmt(c[0]) == c[1], "fmt %s -> %s (got %s)" % [c[0], c[1], g.fmt(c[0])])
	g.free()


func check_systems() -> void:
	var g: Node = GameScript.new()
	g.rng.seed = 1
	for u in Content.UNLOCKS:
		g.unlocked[u.id] = true
	var grail := 14
	g.relics[grail] = 3
	expect(is_equal_approx(g.relic_mods(grail).xrenown, pow(1.4, 2.0)), "relic level scales x-mods")
	expect(g.toggle_equip(grail) and is_equal_approx(g.stat_mul("xrenown"), pow(1.4, 2.0)), "equipped relic applies")
	g.gold = 1e6
	expect(g.buy_card() and not g.buy_card(), "one card at a time")
	var resolved := [false]
	g.card_resolved.connect(func(_s: Array, _w: Array, _t: String) -> void: resolved[0] = true)
	for c in 9:
		g.scratch(c, 1.0)
	expect(resolved[0] and g.card.is_empty() and g.cards_opened == 1, "scratching every cell resolves the card")
	var early: Node = GameScript.new()
	var seen := {}
	early.omen_spawned.connect(func(k: String) -> void: seen[k] = true)
	for _i in 300:
		early.spawn_omen()
	expect(not seen.has("pilgrim") and seen.has("cart"), "no pilgrims before the Reliquary")
	early.free()
	g.claim_omen("star")
	expect(g.buffs.has("star"), "falling star buff starts")
	g.tick(31.0)
	expect(not g.buffs.has("star"), "falling star buff expires")
	g.claim_omen("dragon")
	expect(g.crit_chance() == 1.0, "dragon raid forces crits")

	g.play_time = 0.0
	g.tick(0.0)
	g.renown = 1e3
	var node := -1
	for nb in g.tree.nodes[0].links:
		if g.tree.nodes[nb].sector == 0 and g.tree.nodes[nb].kind == PassiveTree.Kind.SMALL:
			node = nb
	var stat: String = g.tree.nodes[node].mods.keys()[0]
	var v: float = g.tree.nodes[node].mods[stat]
	g.allocate(node)
	expect(is_equal_approx(g.stat_add(stat), v * Content.SEASON_ADD_MULT), "spring empowers Harvest nodes")
	g.play_time = Content.SEASON_LENGTH * 2.0
	g.tick(0.0)
	expect(is_equal_approx(g.stat_add(stat), v), "autumn does not")

	g.renown = 0.0
	expect(not g.destination_unlocked(g.destination("north")), "wilds locked early")
	g.run_oath = "silence"
	g._recompute()
	expect(g.click_value() == 0.0, "oath of silence mutes levies")
	var pts: int = g.points_total()
	g.run_gold = 1e20
	g.run_time = g.CRUSADE_MIN_TIME
	expect(g.crusade("holy", "haste"), "crusade with oath")
	expect(g.oaths.get("silence", 0) == 1 and g.run_oath == "haste", "oath kept, next oath sworn")
	expect(g.points_total() >= pts + Content.OATH_POINTS, "oath grants web points")
	var b: Node = GameScript.new()
	b.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	expect(b.relics.get(grail, 0) == 3 and b.oaths.get("silence", 0) == 1 and b.run_oath == "haste", "systems saved")
	g.free()
	b.free()


func check_sliding() -> void:
	var t := CountingTable.new()
	t.board = [1, 1, 2, 2, 0, 0, 0, 0, 2, 2, 2, 2, 3, 0, 3, 3]
	var res := t.slide(Vector2i.LEFT)
	expect(t.board.slice(0, 4) == [2, 3, 0, 0], "pairs merge once each")
	expect(t.board.slice(8, 12) == [3, 3, 0, 0], "four equal make two")
	expect(t.board.slice(12, 16) == [4, 3, 0, 0], "merge nearest the wall first")
	expect(res.created.size() == 5 and t.best == 4, "merges counted, best tracked")
	t.board = [1, 2, 3, 4, 2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3]
	expect(not t.slide(Vector2i.RIGHT).moved and not t.can_move(), "jammed board cannot move")
	t.board = [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	t.slide(Vector2i.DOWN)
	expect(t.board[15] == 1, "slide down to bottom row")

	var c := Chapel.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	c.start(0, rng)
	expect(not c.is_solved() and c.tiles.size() == 9, "window starts shuffled")
	var row_cell := (c.gap() / 3) * 3 + (2 if c.gap() % 3 == 0 else 0)
	var gap_before := c.gap()
	var anim := c.slide(row_cell)
	expect(c.gap() == row_cell and anim.size() == absi(row_cell - gap_before), "row slide moves every tile between")
	expect(c.slide(c.gap()).is_empty(), "clicking the gap does nothing")
	c.tiles = [0, 1, 2, 3, 4, 5, 6, 8, 7]
	c.slide(8)
	expect(c.solved[0], "last slide restores the window")

	var g: Node = GameScript.new()
	g.unlocked["table"] = true
	g.unlocked["chapel"] = true
	g.dynasties = 20
	g.table.board = [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var tally: float = g.table.tally
	var r: Dictionary = g.table_slide(Vector2i.LEFT)
	expect(r.moved and g.table.tally == tally - 1.0 and r.spawned >= 0, "table slide spends tally and spawns")
	expect(is_equal_approx(g.table.gold_mult(), CountingTable.BEST_MULT), "silver penny gives ×1.3")
	var pts: int = g.points_total()
	g.chapel_start(0)
	g.chapel.tiles = [0, 1, 2, 3, 4, 5, 6, 8, 7]
	g.chapel_slide(8)
	expect(g.chapel.solved[0] and g.chapel.current == -1 and g.points_total() == pts + Chapel.POINTS, "window reward")
	var b: Node = GameScript.new()
	b.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	expect(b.chapel.solved[0] and b.table.best == g.table.best, "sliding state saved")
	g.free()
	b.free()


func check_fast_allocation() -> void:
	var g: Node = GameScript.new()
	g.renown = 1e30
	var far: int = g.tree.nodes.size() - 1
	var path: Array = g.path_to(far)
	expect(path.size() == PassiveTree.RINGS and path.back() == far, "path reaches outer ring node")
	expect(g.allocate_path(far) == path.size() and g.allocated.has(far), "click allocates whole path")
	g.reset_tree()
	var t0 := Time.get_ticks_msec()
	var n: int = g.auto_spend()
	print("auto_spend %d nodes in %d ms" % [n, Time.get_ticks_msec() - t0])
	expect(g.points_free() == 0 and n == g.points_total(), "auto-spend uses every point")
	var no_keystones := true
	for id in g.allocated:
		no_keystones = no_keystones and g.tree.nodes[id].kind != PassiveTree.Kind.KEYSTONE
	expect(no_keystones, "auto-spend skips keystones")
	g.reset_tree()
	t0 = Time.get_ticks_msec()
	var targets: Array = [far, far - 200, far - 400]
	g.auto_spend(targets)
	print("auto_spend toward targets in %d ms" % [Time.get_ticks_msec() - t0])
	expect(g.allocated.has(far) and g.allocated.has(far - 200), "auto-spend walks to search targets")
	var before: Array = g.allocated.keys()
	g.renown = 1e12
	g.dynasty()
	g.renown = 1e30
	g.rebuild_layout(g.last_layout)
	expect(g.allocated.size() == before.size(), "rebuild restores last web")
	g.free()


## Greedy player: buys best gold-per-cost, clicks steadily, crusades on renown doubling.
func simulate() -> void:
	var g: Node = GameScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	g.rng.seed = 7
	# The court automates cards and omens, so the sim also feels relics and buffs.
	g.advisors = {"falconer": true, "abbot": true}
	var cps := 2.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("cps="):
			cps = float(a.substr(4))
	print("sim: %.1f clicks/s" % cps)
	var marks := {}
	var t := 0.0
	var now := [0.0]
	g.prestiged.connect(func(kind: String, _gain: float) -> void:
		if kind == "dynasty":
			print("  dynasty %d at %s, deeds %d, crusades %d" % [g.dynasties, g.fmt_time(now[0]), g.achieved.size(), g.crusades]))
	g.feature_unlocked.connect(func(id: String) -> void:
		print("  unlock %-9s at %s (%d clicks)" % [id, g.fmt_time(now[0]), int(now[0] * cps)]))
	var next_report := 0.0
	while t < SIM_HOURS * 3600.0 and not g.won:
		g.tick(DT)
		g.add_gold(g.click_value() * g.expected_crit() * cps * DT)
		t += DT
		now[0] = t
		g.clicks = int(t * cps)
		_sim_buy(g)
		while g.points_free() > 0 and _sim_allocate(g, rng):
			pass
		var gain: float = g.renown_gain()
		if g.can_crusade() and (gain >= maxf(3.0, g.renown) or gain >= 0.9 * g.softcap() or (g.run_time > 1800.0 and gain >= 0.25 * g.renown)):
			g.crusade()
		if g.blood_gain() >= maxf(1.0, g.blood):
			g.dynasty()
		for m in [["first crusade", g.crusades >= 1], ["renown 1e3", g.renown >= 1e3],
				["renown 1e6", g.renown >= 1e6], ["first dynasty", g.dynasties >= 1],
				["gold 1e30", g.total_gold >= 1e30], ["gold 1e60", g.total_gold >= 1e60],
				["gold 1e100", g.total_gold >= 1e100], ["gold 1e200", g.total_gold >= 1e200],
				["100 nodes", g.allocated.size() > 100], ["400 nodes", g.allocated.size() > 400],
				["victory", g.won]]:
			if m[1] and not marks.has(m[0]):
				marks[m[0]] = t
				print("  %-14s at %s (%d clicks)" % [m[0], g.fmt_time(t), int(t * cps)])
		if t >= next_report:
			next_report += 1800.0
			print("[%s] gold %s gps %s renown %s blood %s nodes %d/%d crus %d dyn %d" % [g.fmt_time(t),
				g.fmt(g.gold), g.fmt(g.gps()), g.fmt(g.renown), g.fmt(g.blood), g.allocated.size() - 1,
				g.points_total(), g.crusades, g.dynasties])
		expect(not is_nan(g.gold) and not is_inf(g.gps()) or g.won, "finite economy")
	print("sim end %s, won=%s" % [g.fmt_time(t), g.won])
	g.free()


func _sim_buy(g: Node) -> void:
	for _n in 400:
		var best: int = g.best_building()
		if best < 0:
			return
		g.buy(best, 1 if g.owned[best] < 100 else maxi(1, int(g.owned[best] / 20.0)))


func _sim_allocate(g: Node, rng: RandomNumberGenerator) -> bool:
	var best := -1
	var best_score := -1.0
	for id in g.allocated:
		for nb in g.tree.nodes[id].links:
			if g.allocated.has(nb):
				continue
			var n: Dictionary = g.tree.nodes[nb]
			var score := rng.randf() + (2.0 if n.kind == PassiveTree.Kind.NOTABLE else 0.0)
			if n.kind == PassiveTree.Kind.KEYSTONE and n.mods.get("xclick", 1.0) < 1.0:
				score -= 5.0
			if score > best_score:
				best_score = score
				best = nb
	return best >= 0 and g.allocate(best)
