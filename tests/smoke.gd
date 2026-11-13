extends Node
## Schnelltest der Spielregeln und des Hauptbildschirms.
##
##   godot --headless --path . res://tests/smoke.tscn
##
## Mit Fenster und "-- --shot=pfad.png" wird zusätzlich ein Bildschirmfoto gespeichert.
## Der Test verwendet eine eigene Speicherdatei und rührt den echten Spielstand nicht an.

var _failed: int = 0


func _ready() -> void:
	_check("Test nutzt eigene Speicherdatei", Game.save_path, "user://test_save.json")
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

	# Freischaltung über Gebäude-Level
	var copper_mining: Dictionary = _building("copper_mining")
	_check("Kupferabbau anfangs gesperrt", Game.is_unlocked(copper_mining), false)
	Game.levels["mine"] = 5
	_check("Kupferabbau ab Mine Lv 5 frei", Game.is_unlocked(copper_mining), true)

	# Rezepte: Zutaten sofort weg, Ergebnis nach Ablauf, Menge = Gebäude-Level
	var copper_bar: Dictionary = _recipe("copper_bar")
	Game.amounts["copper_ore"] = 4.0
	_check("Ohne Schmelze kein Schmelzen", Game.can_start_recipe(copper_bar), false)
	Game.levels["smeltery"] = 2
	_check("Mit Schmelze startbar", Game.start_recipe(copper_bar), true)
	_check("Erz sofort abgezogen", Game.amounts["copper_ore"], 0.0)
	Game._advance_recipe(copper_bar, 3.9)
	_check("Vor Ablauf noch kein Barren", Game.amounts["copper_bar"], 0.0)
	Game._advance_recipe(copper_bar, 0.2)
	_check("Nach Ablauf 2 Barren", Game.amounts["copper_bar"], 2.0)
	Game.amounts["copper_ore"] = 4.0
	Game.set_recipe_auto(copper_bar, true)
	Game._advance_recipe(copper_bar, 0.0)
	_check("Auto startet von selbst", Game.recipe_state["copper_bar"]["running"], true)
	Game.set_recipe_auto(copper_bar, false)

	# Upgrades: erst ab Bedingung, einmalig, wirken auf die Produktion
	var farm_upgrade: Dictionary = _upgrade("farm_1")
	Game.amounts["food"] = 1000.0
	Game.amounts["coins"] = 1000.0
	Game.amounts["wood"] = 1000.0
	Game.levels["farm"] = 9
	_check("Farm-Upgrade unter Lv 10 gesperrt", Game.can_buy_upgrade(farm_upgrade), false)
	Game.levels["farm"] = 10
	var food_before: float = Game.get_rates()["food"]
	_check("Farm-Upgrade kaufbar", Game.buy_upgrade(farm_upgrade), true)
	_check("Farm liefert doppelt", Game.get_rates()["food"] - food_before, 10.0)
	_check("Upgrade nur einmal kaufbar", Game.can_buy_upgrade(farm_upgrade), false)
	var click_upgrade: Dictionary = _upgrade("click_coins_1")
	Game.click_counts["coins"] = 99
	_check("Klick-Upgrade unter 100 Klicks gesperrt", Game.upgrade_unlocked(click_upgrade), false)
	Game.click_target = "coins"
	Game.click()
	_check("Klick-Upgrade ab 100 Klicks frei", Game.buy_upgrade(click_upgrade), true)
	_check("Klick bringt 2 Coins", Game.click(), 2.0)
	Game.save_game()
	_reset()
	Game.load_game()
	Game._rebuild_bonuses()
	_check("Upgrade nach Laden noch gekauft", Game.click_gain("coins"), 2.0)

	# Abwesenheit: Gebäude liefern weiter, Auto-Rezepte laufen, Obergrenze greift
	_reset()
	Game.levels["farm"] = 3
	var report: Dictionary = Game.apply_offline(1000.0)
	_check("Ohne Upgrade keine Abwesenheit", Game.amounts["food"], 0.0)
	Game.bought["offline_1"] = true
	Game._rebuild_bonuses()
	report = Game.apply_offline(100.0)
	_check("Erstes Upgrade: 20 Prozent", Game.amounts["food"], 60.0)
	_check("Bericht nennt Nahrung", report["gains"].get("food", 0.0), 60.0)
	Game.amounts["food"] = 0.0
	Game.apply_offline(100.0 * 3600.0)
	_check("Erstes Upgrade: höchstens 1 Stunde", Game.amounts["food"], 3.0 * 3600.0 * 0.2)
	_check("Kette: Stufe 3 erst nach Stufe 2 sichtbar", Game.upgrade_visible(_upgrade("offline_time_3")), false)
	for upgrade: Dictionary in Game.upgrades:
		if upgrade["id"].begins_with("offline_"):
			Game.bought[upgrade["id"]] = true
	Game._rebuild_bonuses()
	_check("Alle Upgrades: 8 Stunden", Game.offline_hours(), 8.0)
	_check("Alle Upgrades: 80 Prozent", Game.offline_percent(), 80.0)
	_reset()
	for upgrade: Dictionary in Game.upgrades:
		if upgrade["id"].begins_with("offline_"):
			Game.bought[upgrade["id"]] = true
	Game._rebuild_bonuses()
	Game.levels["farm"] = 1
	Game.apply_offline(100.0 * 3600.0)
	_check("Obergrenze 8 Stunden zu 80 Prozent", is_equal_approx(Game.amounts["food"], 8.0 * 3600.0 * 0.8), true)
	Game.amounts["food"] = 0.0
	Game.levels["farm"] = 0
	Game.levels["smeltery"] = 1
	Game.amounts["copper_ore"] = 10.0
	Game.apply_offline(1000.0)
	_check("Ohne Auto wird nichts geschmolzen", Game.amounts["copper_bar"], 0.0)
	Game.set_recipe_auto(_recipe("copper_bar"), true)
	Game.apply_offline(15.0)
	_check("Auto: 15 s zu 80 Prozent reichen für 3 Durchgänge", Game.amounts["copper_bar"], 3.0)
	Game.apply_offline(1000.0)
	_check("Auto: Zutaten begrenzen", Game.amounts["copper_bar"], 5.0)
	_check("Erz aufgebraucht", Game.amounts["copper_ore"], 0.0)
	Game.set_recipe_auto(_recipe("copper_bar"), false)

	# Zahlenformat
	_check("Format klein", Game.fmt(1234.9), "1234")
	_check("Format groß", Game.fmt(2_500_000.0), "2.50e6")
	_check("Format krumme Rate", Game.fmt_signed(0.8), "+0.8")
	_check("Format negative Rate", Game.fmt_signed(-2.0), "-2")

	# Hauptbildschirm laden und ein paar Bilder laufen lassen
	Game.set_process(true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i: int in 10:
		await get_tree().process_frame
	var top_level: int = 0
	for building: Dictionary in Game.buildings:
		if not building.has("parent") and building.get("placement", "list") == "list":
			top_level += 1
	_check("Gebäudezeilen angelegt", main.get_node("%BuildingList").get_child_count(), top_level)

	# Klick auf den Planeten samt Flug-Animation darf keinen Fehler werfen
	var coins_before_click: float = Game.amounts["coins"]
	main._on_planet_pressed()
	await get_tree().create_timer(0.2).timeout
	_check("Klick über die Oberfläche zählt", Game.amounts["coins"] > coins_before_click, true)
	_check("Rezeptzeilen angelegt", main.get_node("%RecipeList").get_child_count(), Game.recipes.size())

	for arg: String in OS.get_cmdline_user_args():
		if arg == "--offline":
			main._show_offline_report({ "seconds": 30000.0, "counted": 28800.0, "percent": 80.0,
				"gains": { "coins": 57600.0, "wood": 28800.0, "food": 1234567.0, "copper_bar": 420.0 } })
			await get_tree().process_frame
		if arg == "--expand":
			for row: Node in main.get_node("%BuildingList").get_children():
				row.expand_button.button_pressed = true
			await get_tree().process_frame
			main.get_node("%BuildingList").get_parent().scroll_vertical = 330
			await get_tree().process_frame
		if arg.begins_with("--tab="):
			main.get_node("%Tabs").current_tab = int(arg.trim_prefix("--tab="))
			await get_tree().process_frame
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


func _upgrade(id: String) -> Dictionary:
	for upgrade: Dictionary in Game.upgrades:
		if upgrade["id"] == id:
			return upgrade
	return {}


func _recipe(id: String) -> Dictionary:
	for recipe: Dictionary in Game.recipes:
		if recipe["id"] == id:
			return recipe
	return {}


func _reset() -> void:
	for id: String in Game.amounts:
		Game.amounts[id] = 0.0
	for id: String in Game.levels:
		Game.levels[id] = 0
	for id: String in Game.recipe_state:
		Game.recipe_state[id] = Game._new_recipe_state()
	for id: String in Game.bought:
		Game.bought[id] = false
	for id: String in Game.click_counts:
		Game.click_counts[id] = 0
	Game._rebuild_bonuses()


func _check(what: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("ok    ", what)
	else:
		_failed += 1
		print("FEHL  %s: erwartet %s, bekommen %s" % [what, expected, actual])
