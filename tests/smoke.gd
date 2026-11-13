extends Node
## Schnelltest der Spielregeln und des Hauptbildschirms.
##
##   godot --headless --path . res://tests/smoke.tscn
##
## Mit Fenster und "-- --shot=pfad.png" wird zusätzlich ein Bildschirmfoto gespeichert.
## Der Test verwendet eine eigene Speicherdatei und rührt den echten Spielstand nicht an.

var _failed: int = 0


func _ready() -> void:
	Game.save_path = "user://test_save.json"
	Game.set_process(false)  # Zeit steht, damit die Zahlen exakt bleiben.
	_reset()

	var farm: Dictionary = _building("farm")
	var housing: Dictionary = _building("housing")
	var lumberjack: Dictionary = _building("lumberjack")
	var mine: Dictionary = _building("mine")

	# Klicken
	Game.click_target = "coins"
	for i: int in 25:
		Game.click()
	Game.click_target = "wood"
	for i: int in 25:
		Game.click()
	_check("25 Klicks geben 25 Coins", Game.amounts["coins"], 25.0)
	_check("25 Klicks geben 25 Holz", Game.amounts["wood"], 25.0)

	# Gebäude kaufen
	_check("Farm ist leistbar", Game.can_buy(farm, 1), true)
	Game.buy(farm)
	_check("Farm Level 1", Game.levels["farm"], 1)
	_check("Coins abgezogen", Game.amounts["coins"], 0.0)
	_check("Nahrung +1/s", Game.get_rates()["food"], 1.0)
	_check("Zweite Farm kostet 29", Game.cost_for(farm, 1)["coins"], 29.0)
	_check("Ohne Coins nicht leistbar", Game.can_buy(farm, 1), false)

	# Mengenkauf: Summe von 10 Leveln = Summe der Einzelpreise (bis auf Rundung)
	var single_sum: float = 0.0
	for i: int in 10:
		single_sum += 25.0 * pow(1.15, 1 + i)
	_check("10er-Kauf entspricht Einzelpreisen", absf(Game.cost_for(farm, 10)["coins"] - single_sum) < 1.0, true)

	# Bevölkerung: kostet Nahrung und laufenden Verbrauch
	Game.amounts["food"] = 250.0
	_check("Bevölkerung nicht leistbar bei +1/s", Game.can_buy(housing, 1), false)
	Game.levels["farm"] = 2
	_check("Bevölkerung leistbar bei +2/s", Game.can_buy(housing, 1), true)
	Game.buy(housing)
	_check("Nahrung netto 0/s", Game.get_rates()["food"], 0.0)
	_check("1 Bevölkerung frei", Game.capacity_free("population"), 1.0)

	# Kapazität belegen
	Game.amounts["coins"] = 1000.0
	Game.amounts["wood"] = 1000.0
	Game.buy(lumberjack)
	_check("Holzfäller belegt Bevölkerung", Game.capacity_free("population"), 0.0)
	_check("Mine ohne Bevölkerung gesperrt", Game.can_buy(mine, 1), false)

	# Speichern und Laden
	Game.save_game()
	var coins_before: float = Game.amounts["coins"]
	_reset()
	Game.load_game()
	_check("Coins nach Laden", Game.amounts["coins"], coins_before)
	_check("Level nach Laden", Game.levels["lumberjack"], 1)

	# Zahlenformat
	_check("Format klein", Game.fmt(1234.9), "1234")
	_check("Format groß", Game.fmt(2_500_000.0), "2.50e6")

	# Hauptbildschirm laden und ein paar Bilder laufen lassen
	Game.set_process(true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i: int in 10:
		await get_tree().process_frame
	_check("Gebäudezeilen angelegt", main.get_node("%BuildingList").get_child_count(), Game.buildings.size())

	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shot="))

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.json"))
	print("FEHLER: %d" % _failed if _failed > 0 else "ALLE TESTS OK")
	get_tree().quit(1 if _failed > 0 else 0)


func _building(id: String) -> Dictionary:
	for building: Dictionary in Game.buildings:
		if building["id"] == id:
			return building
	return {}


func _reset() -> void:
	for id: String in Game.amounts:
		Game.amounts[id] = 0.0
	for id: String in Game.levels:
		Game.levels[id] = 0


func _check(what: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("ok    ", what)
	else:
		_failed += 1
		print("FEHL  %s: erwartet %s, bekommen %s" % [what, expected, actual])
