extends Node
## Renders main.tscn with seeded state and saves a PNG, then quits.
## godot --path . tests/shot.tscn -- --out=/abs/file.png [--page=web] [--late]

func _ready() -> void:
	var out := "user://shot.png"
	var page := "kingdom"
	var late := false
	var season := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--page="): page = a.substr(7)
		elif a == "--late": late = true
		elif a.begins_with("--season="): season = int(a.substr(9))
	Game.set_process(false)
	Game.from_dict({})
	if late:
		Game.renown = 1e25
		Game.blood = 40.0
		Game.crusades = 30
		Game.clicks = 500
		for i in Game.owned.size():
			Game.owned[i] = 120 - i * 8
		var frontier := [0]
		while Game.points_free() > 0 and Game.allocated.size() < 260:
			var id: int = frontier.pop_front()
			for nb in Game.tree.nodes[id].links:
				if Game.allocate(nb):
					frontier.append(nb)
		Game.gold = 3.3e40
	else:
		Game.owned[0] = 12
		Game.owned[1] = 4
		Game.gold = 842.0
	Game.play_time = Content.SEASON_LENGTH * season + 5.0
	Game.relics = {0: 2, 7: 1, 14: 1}
	Game.equipped = [0, 14]
	Game.oaths = {"silence": 2}
	Game.renown = maxf(Game.renown, 2e4)
	Game.check_achievements()
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._show_page(page)
	if page == "web":
		main._on_web_hover(Game.tree.nodes[0].links[2])
	if "--omens" in OS.get_cmdline_user_args():
		for k in ["cart", "star", "dragon", "pilgrim"]:
			main.world.spawn_omen(k)
		for o in main.world.omens:
			o.age = 4.0
			o.pos += o.vel * 4.0
	if page == "relics":
		Game.gold = 1e9
		main.pages.relics._buy()
		for c in [0, 1, 3, 4]:
			Game.scratch(c, 1.0)
		Game.scratch(2, 0.5)
	if page in ["vault", "chapel"] or "--all" in OS.get_cmdline_user_args():
		for u in Content.UNLOCKS:
			Game.unlocked[u.id] = true
		Game.dynasties = 12
	if page == "vault":
		Game.table.board = [1, 2, 0, 0, 3, 3, 1, 0, 5, 6, 2, 1, 7, 9, 4, 2]
		Game.table.best = 9
	if page == "chapel":
		Game.chapel.solved[0] = true
		Game.chapel_start(2)
		main.pages.chapel.rebuild()
	if page in ["vault", "chapel"]:
		main._show_page(page)
	if "--map" in OS.get_cmdline_user_args():
		main._open_map()
	if page == "kingdom":
		for i in 4:
			Game.levy()
			await get_tree().create_timer(0.05).timeout
	for i in 20:
		await get_tree().process_frame
	if page == "web":
		main._on_web_hover(Game.tree.nodes[0].links[2])
		await get_tree().process_frame
	if "--ui-check" in OS.get_cmdline_user_args():
		await _ui_check(main)
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()


## Drives real mouse events through the viewport and checks the game reacts.
func _ui_check(main: Node) -> void:
	Game.from_dict({})
	Game.renown = 100.0
	main._show_page("kingdom")
	await get_tree().process_frame
	var before: int = Game.clicks
	await _click(main.world.seal_center(), MOUSE_BUTTON_LEFT)
	print("UI seal click: ", "OK" if Game.clicks == before + 1 else "FAIL")
	main.world.spawn_omen("star")
	await get_tree().process_frame
	await _click(main.world.omens[0].pos, MOUSE_BUTTON_LEFT)
	print("UI omen click: ", "OK" if Game.buffs.has("star") and main.world.omens.is_empty() else "FAIL")
	main._show_page("web")
	await get_tree().process_frame
	var id: int = Game.tree.nodes[0].links[0]
	var screen: Vector2 = main.web.position + Game.tree.nodes[id].pos * main.web.scale.x
	await _click(screen, MOUSE_BUTTON_LEFT)
	print("UI web allocate: ", "OK" if Game.allocated.has(id) else "FAIL")
	await _click(screen, MOUSE_BUTTON_RIGHT)
	print("UI web refund: ", "OK" if not Game.allocated.has(id) else "FAIL")
	Game.unlocked["table"] = true
	Game.unlocked["chapel"] = true
	Game.dynasties = 20
	main._show_page("vault")
	Game.table.board = [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	await get_tree().process_frame
	var key := InputEventKey.new()
	key.keycode = KEY_LEFT
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	print("UI vault key slide: ", "OK" if Game.table.board[0] == 2 else "FAIL")
	main._show_page("chapel")
	Game.chapel_start(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var gap: int = Game.chapel.gap()
	var cell: int = gap + 1 if gap % 3 < 2 else gap - 1
	var view: Control = main.pages.chapel.view
	var px: float = main.pages.chapel.VIEW / 3.0
	await _click(view.global_position + Vector2(cell % 3 + 0.5, cell / 3 + 0.5) * px, MOUSE_BUTTON_LEFT)
	print("UI chapel slide: ", "OK" if Game.chapel.moves == 1 and Game.chapel.gap() == cell else "FAIL")


func _click(pos: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = pos
		e.global_position = pos
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame
