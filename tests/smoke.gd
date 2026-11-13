extends Node
## Schnelltest der Spielregeln und des Hauptbildschirms.
##
##   godot --headless --path . res://tests/smoke.tscn
##
## Mit Fenster und "-- --shot=pfad.png" wird zusätzlich ein Bildschirmfoto gespeichert.
## Der Test verwendet eine eigene Speicherdatei und rührt den echten Spielstand nicht an.

var _failed: int = 0


func _ready() -> void:
	Options.number_format = "scientific"  # die meisten Prüfungen unten erwarten diese Schreibweise
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

	# Überraschung: nur das nächste Gebäude ist als Rätsel zu sehen
	_check("Farm von Anfang an bekannt", Game.building_visibility(farm), "known")
	_check("Holzfäller anfangs Rätsel", Game.building_visibility(lumberjack), "mystery")
	_check("Mine anfangs unsichtbar", Game.building_visibility(mine), "hidden")
	_check("Rätsel ist nicht kaufbar", Game.can_buy(lumberjack, 1), false)
	_check("Coins entdeckt, Stein nicht", [Game.seen["coins"], Game.seen["stone"]], [true, false])

	# Gebäude kaufen
	_check("Farm ist leistbar", Game.can_buy(farm, 1), true)
	Game.buy(farm)
	_check("Farm Level 1", Game.levels["farm"], 1)
	_check("Nach Farm: Holzfäller bekannt", Game.building_visibility(lumberjack), "known")
	_check("Nach Farm: Markt wird Rätsel, Mine bleibt unsichtbar", [Game.building_visibility(_building("market")), Game.building_visibility(mine)], ["mystery", "hidden"])
	_check("Coins abgezogen", Game.amounts["coins"], 0.0)
	_check("Nahrung +1/s", Game.get_rates()["food"], 1.0)
	_check("Zweite Farm kostet 29", Game.cost_for(farm, 1)["coins"], 29.0)
	_check("Ohne Coins nicht leistbar", Game.can_buy(farm, 1), false)

	# Mengenkauf: Summe von 10 Leveln = Summe der Einzelpreise (bis auf Rundung)
	var single_sum: float = 0.0
	for i: int in 10:
		single_sum += 25.0 * pow(1.15, 1 + i)
	_check("10er-Kauf entspricht Einzelpreisen", absf(Game.cost_for(farm, 10)["coins"] - single_sum) < 1.0, true)

	# Kaufmenge Max: so viele wie leistbar, begrenzt durch Vorrat und Bevölkerung
	var saved_coins: float = Game.amounts["coins"]
	var saved_wood: float = Game.amounts["wood"]
	Game.amounts["coins"] = 100.0
	Game.amounts["wood"] = 100.0
	_check("Max: 3 Farmen um 100 (29+33+38)", Game.max_affordable(farm), 3)
	Game.amounts["coins"] = 0.0
	_check("Max ohne Coins: 0, angezeigt wird 1", [Game.max_affordable(farm), Game.buy_count(farm)], [0, 1])
	for i: int in 3:
		Game.cycle_buy_amount()
	_check("Durchschalten endet bei Max", Game.buy_max, true)
	_check("Max ohne Coins kauft nichts", Game.buy(farm), false)
	Game.cycle_buy_amount()
	_check("Danach wieder 1", [Game.buy_max, Game.buy_amount], [false, 1])
	Game.amounts["coins"] = saved_coins
	Game.amounts["wood"] = saved_wood

	# Reihenfolge der Gebäude in der Liste
	var order: Array = []
	for building: Dictionary in Game.buildings:
		if not building.has("parent") and building.get("placement", "list") == "list":
			order.append(building["id"])
	_check("Gebäude-Reihenfolge", order, ["farm", "lumberjack", "market", "mine", "smeltery", "watermill", "factory", "greenhouse", "solarpanel", "sawmill", "bank"])
	_check("Gewächshaus liefert mehr Nahrung als die Farm und kostet Glas", [_building("greenhouse")["produces"]["food"] > _building("farm")["produces"]["food"], _building("greenhouse")["cost"].has("glass")], [true, true])
	_check("Schmelze braucht keinen Strom mehr, Sand ab Mine Lv 2, Kohle ab Lv 4", [_building("smeltery")["reserves"].has("electricity"), _building("coal_mining")["requires"]["mine"], _building("sandmine")["requires"]["mine"], _building("sandmine").get("parent", "")], [false, 4.0, 2.0, "mine"])
	_check("Schmelze erscheint erst mit dem Kohleabbau", _building("smeltery")["requires"], { "coal_mining": 1.0 })
	_check("Erste Bank kostet 1 Goldbarren, die dritte 3", [Game.cost_for(_building("bank"), 1)["gold_bar"], Game.cost_for(_building("bank"), 3)["gold_bar"]], [1.0, 6.0])
	_check("Markt liefert 1 Coin, Sägewerk mehr Holz als der Holzfäller", [_building("market")["produces"]["coins"], _building("sawmill")["produces"]["wood"] > _building("lumberjack")["produces"]["wood"]], [1.0, true])

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
	Game.levels["mine"] = 6
	_check("Kupferabbau ab Mine Lv 6 frei", Game.is_unlocked(copper_mining), true)

	# Rezepte: Zutaten sofort weg, Ergebnis nach Ablauf, Menge = Gebäude-Level
	var copper_bar: Dictionary = _recipe("copper_bar")
	Game.amounts["copper_ore"] = 2.0
	Game.amounts["coal"] = 100.0
	_check("Ohne Schmelze kein Schmelzen", Game.can_start_recipe(copper_bar), false)
	Game.levels["smeltery"] = 1
	_check("Schmelze Lv 1: Glas ja, Kupferbarren nein", [Game.recipe_batch(_recipe("glass")), Game.recipe_batch(copper_bar)], [1, 0])
	_check("Glas steht in der Liste ganz oben", Game.recipes[0]["id"], "glass")
	var factory: Dictionary = _building("factory")
	_check("Erste Fabrik kostet 1 Glas", Game.cost_for(factory, 1)["glass"], 1.0)
	Game.levels["factory"] = 3
	_check("Vierte Fabrik kostet 4 Glas, zwei auf einmal 4 + 5", [Game.cost_for(factory, 1)["glass"], Game.cost_for(factory, 2)["glass"]], [4.0, 9.0])
	Game.levels["factory"] = 0
	Game.levels["smeltery"] = 4
	_check("Schmelze Lv 4: noch kein Kupferbarren", Game.can_start_recipe(copper_bar), false)
	Game.levels["smeltery"] = 5
	_check("Schmelze Lv 5: Glas mit Menge 5, Kupferbarren neu mit 1, Eisenbarren noch nicht", [Game.recipe_batch(_recipe("glass")), Game.recipe_batch(copper_bar), Game.recipe_batch(_recipe("iron_bar"))], [5, 1, 0])
	Game.levels["smeltery"] = 8
	_check("Schmelze Lv 8: Kupferbarren mit Menge 4", Game.recipe_batch(copper_bar), 4)
	Game.levels["smeltery"] = 5
	_check("Nächstes Rezept ab Lv 10", Game.next_recipe_level(_building("smeltery")), 10)
	_check("Mit Schmelze startbar", Game.start_recipe(copper_bar), true)
	_check("Erz sofort abgezogen, dazu 1 Kohle", [Game.amounts["copper_ore"], Game.amounts["coal"]], [0.0, 99.0])
	Game._advance_recipe(copper_bar, 3.9)
	_check("Vor Ablauf noch kein Barren", Game.amounts["copper_bar"], 0.0)
	Game._advance_recipe(copper_bar, 0.2)
	_check("Nach Ablauf 1 Barren", Game.amounts["copper_bar"], 1.0)
	_check("Höchstlevel = letzte Freischaltung + 5: Fabrik 15, Schmelze 20", [_building("factory")["max_level"], _building("smeltery")["max_level"]], [15, 20])
	Game.levels["factory"] = 5
	_check("Fabrik Lv 5: Kupferkabel ja, Eisenplatte nein", [Game.recipe_batch(_recipe("copper_cable")), Game.recipe_batch(_recipe("iron_plate"))], [1, 0])
	Game.levels["factory"] = 10
	_check("Fabrik Lv 10: Eisenplatte da, Fabrik noch nicht fertig", [Game.recipe_batch(_recipe("iron_plate")), Game.is_maxed(_building("factory"))], [1, false])
	Game.levels["factory"] = 15
	_check("Fabrik Lv 15: Eisenplatte mit Menge 6, Fabrik fertig", [Game.recipe_batch(_recipe("iron_plate")), Game.is_maxed(_building("factory")), Game.can_buy(_building("factory"), 1)], [6, true, false])
	Game.levels["smeltery"] = 20
	_check("Schmelze Lv 20: Goldbarren mit Menge 6", Game.recipe_batch(_recipe("gold_bar")), 6)
	Game.levels["smeltery"] = 5
	Game.levels["factory"] = 0
	Game.amounts["copper_ore"] = 4.0
	Game.set_recipe_auto(copper_bar, true)
	_check("Auto ohne Upgrade bleibt aus", Game.recipe_state["copper_bar"]["auto"], false)
	Game.recipe_state["copper_bar"]["auto_unlocked"] = true
	Game.set_recipe_auto(copper_bar, true)
	Game._advance_recipe(copper_bar, 0.0)
	_check("Auto startet von selbst", Game.recipe_state["copper_bar"]["running"], true)
	Game.set_recipe_auto(copper_bar, false)

	# Upgrades: erst ab Bedingung, einmalig, wirken auf die Produktion
	var farm_upgrade: Dictionary = _upgrade("farm_1")
	Game.amounts["food"] = 1000.0
	Game.amounts["coins"] = 1000.0
	Game.amounts["wood"] = 1000.0
	Game.levels["farm"] = 4
	_check("Farm-Upgrade I unter Lv 5 gesperrt", Game.can_buy_upgrade(farm_upgrade), false)
	Game.levels["farm"] = 5
	_check("Farm-Upgrade I kostet das 5-Fache des Farmpreises auf Lv 5", farm_upgrade["cost"]["coins"], roundf(25.0 * pow(1.15, 5) * 5.0))
	_check("Farm-Upgrade I kaufbar", Game.buy_upgrade(farm_upgrade), true)
	_check("Stufe I: +0,5 je Level", Game.building_output(_building("farm"), "produces")["food"], 1.5)
	var farm_upgrade_2: Dictionary = _upgrade("farm_2")
	_check("Stufe II heißt II und braucht Lv 10", [farm_upgrade_2["name"], Game.can_buy_upgrade(farm_upgrade_2)], ["Farm-Upgrade II", false])
	Game.levels["farm"] = 10
	Game.buy_upgrade(farm_upgrade_2)
	_check("Stufe II: +1 dazu, zusammen 2,5", Game.building_output(_building("farm"), "produces")["food"], 2.5)
	_check("Stufe III erst nach II sichtbar, dann Rätsel", Game.upgrade_visibility(_upgrade("farm_3")), "mystery")
	_check("Stufe IV noch unsichtbar", Game.upgrade_visibility(_upgrade("farm_4")), "hidden")
	_check("Frühe Gebäude haben 5 Stufen, späte 10", [_upgrade("farm_5").is_empty(), _upgrade("farm_6").is_empty(), _upgrade("bank_10").is_empty(), _upgrade("bank_11").is_empty()], [false, true, false, true])
	_check("Strom-Upgrade in ganzen Einheiten", _upgrade("watermill_1")["add_provides"]["watermill"]["electricity"], 1.0)
	_check("Bank-Upgrade I: halbe Grundproduktion", _upgrade("bank_1")["add_produces"]["bank"]["coins"], 25.0)
	_check("Upgrade nur einmal kaufbar", Game.can_buy_upgrade(farm_upgrade), false)
	var click_upgrade: Dictionary = _upgrade("click_coins_1")
	Game.amounts["coins"] = 5000.0
	Game.amounts["wood"] = 5000.0
	Game.click_counts["coins"] = 249
	_check("Klick-Upgrade I unter 250 Klicks gesperrt", Game.upgrade_unlocked(click_upgrade), false)
	Game.click_target = "coins"
	Game.click()
	_check("Klick-Upgrade I kostet 250 Coins und 125 Holz", [click_upgrade["cost"]["coins"], click_upgrade["cost"]["wood"]], [250.0, 125.0])
	_check("Klick-Upgrade I ab 250 Klicks frei", Game.buy_upgrade(click_upgrade), true)
	_check("Klick bringt 2 Coins", Game.click(), 2.0)
	var click_upgrade_2: Dictionary = _upgrade("click_coins_2")
	_check("Stufe II braucht 500 Klicks", [click_upgrade_2["requires_clicks"]["coins"], Game.can_buy_upgrade(click_upgrade_2)], [500, false])
	Game.click_counts["coins"] = 500
	Game.buy_upgrade(click_upgrade_2)
	_check("Nach Stufe II bringt ein Klick 3 Coins", Game.click_gain("coins"), 3.0)
	_check("Holz-Klick bleibt bei 1", Game.click_gain("wood"), 1.0)
	_check("Stufe XL heißt XL", _upgrade("click_wood_40")["name"], "Stärkerer Klick: Holz XL")
	Game.save_game()
	_reset()
	Game.load_game()
	Game._rebuild_bonuses()
	_check("Upgrades nach Laden noch gekauft", Game.click_gain("coins"), 3.0)

	# Abwesenheit: Gebäude liefern weiter, Auto-Rezepte laufen, Obergrenze greift
	_reset()
	Game.levels["farm"] = 3
	Game._process(3600.0)
	_check("Ein Riesen-Bild (App kommt aus dem Hintergrund) zählt höchstens 1 Sekunde", Game.amounts["food"], 3.0)
	Game.amounts["food"] = 0.0
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
	Game.levels["smeltery"] = 5
	Game.amounts["copper_ore"] = 10.0
	Game.amounts["coal"] = 1000.0
	Game.apply_offline(1000.0)
	_check("Ohne Auto wird nichts geschmolzen", Game.amounts["copper_bar"], 0.0)
	Game.recipe_state["copper_bar"]["auto_unlocked"] = true
	Game.set_recipe_auto(_recipe("copper_bar"), true)
	Game.apply_offline(15.0)
	_check("Auto: 15 s zu 80 Prozent reichen für 3 Durchgänge", Game.amounts["copper_bar"], 3.0)
	Game.apply_offline(1000.0)
	_check("Auto: Zutaten begrenzen", Game.amounts["copper_bar"], 5.0)
	_check("Erz aufgebraucht", Game.amounts["copper_ore"], 0.0)
	Game.set_recipe_auto(_recipe("copper_bar"), false)

	# Ton: alle Töne wurden erzeugt, Lautstärke lässt sich setzen
	_check("Acht Töne erzeugt", Sfx._streams.size(), 8)
	_check("Eigener Klick-Ton je Ressource", [Sfx._streams.has("click_coins"), Sfx._streams.has("click_wood")], [true, true])
	_check("Klick-Ton ist 0,08 s lang", is_equal_approx(Sfx._streams["click"].get_length(), 0.08), true)
	Sfx.set_volume(0.4)
	_check("Lautstärke gesetzt", Options.volume, 0.4)
	Sfx.play("upgrade")

	# Erzabbau darf die Mine nicht überholen
	_reset()
	Game.levels.merge({ "farm": 1, "lumberjack": 1, "mine": 6, "sandmine": 1 }, true)
	_check("Kupferabbau bleibt Rätsel, bis der Kohleabbau steht", Game.building_visibility(_building("copper_mining")), "mystery")
	Game.levels["coal_mining"] = 1
	for id: String in ["food", "wood", "stone"]:
		Game.amounts[id] = 1.0e9
	var copper: Dictionary = _building("copper_mining")
	_check("Erzabbau: höchstens so viele wie Mine (6)", Game.max_affordable(copper), 6)
	Game.levels["copper_mining"] = 6
	_check("Erzabbau auf Minen-Level: gesperrt", Game.can_buy(copper, 1), false)
	Game.levels["mine"] = 7
	_check("Mine +1: wieder eins möglich", Game.max_affordable(copper), 1)

	# Rezept-Upgrades: bezahlt mit dem eigenen Erzeugnis
	_reset()
	var bar: Dictionary = _recipe("copper_bar")  # 2 Erz -> 1 Barren in 4 s
	Game.levels["smeltery"] = 5
	Game.amounts["copper_bar"] = 24.0
	_check("Tempo I kostet 25, 24 reichen nicht", [Game.recipe_upgrade_cost(bar, "speed")["copper_bar"], Game.can_buy_recipe_upgrade(bar, "speed")], [25.0, false])
	Game.amounts["copper_bar"] = 1000.0
	Game.buy_recipe_upgrade(bar, "speed")
	_check("Tempo I: 3 s, Tempo II kostet 50", [Game.recipe_seconds(bar), Game.recipe_upgrade_cost(bar, "speed")["copper_bar"]], [3.0, 50.0])
	Game.buy_recipe_upgrade(bar, "speed")
	Game.buy_recipe_upgrade(bar, "speed")
	_check("Nach drei Stufen 1 s, mehr gibt es nicht", [Game.recipe_seconds(bar), Game.recipe_upgrade_available(bar, "speed")], [1.0, false])
	_check("Tempo hat 3 Stufen (4 s bis 1 s), Menge unbegrenzt", [Game.recipe_upgrade_max(bar, "speed"), Game.recipe_upgrade_max(bar, "amount"), Game.recipe_upgrade_max(_recipe("gold_bar"), "speed")], [3, 0, 7])
	_check("Vierte Stufe wird nicht verkauft", Game.buy_recipe_upgrade(bar, "speed"), false)
	Game.buy_recipe_upgrade(bar, "amount")
	_check("Menge I: 2 pro Durchgang (1 + 1 Upgrade)", Game.recipe_batch(bar), 2)
	Game.amounts["copper_ore"] = 4.0
	Game.amounts["coal"] = 1.0
	_check("Ohne genug Kohle kein Durchgang (braucht 2)", Game.can_start_recipe(bar), false)
	Game.amounts["coal"] = 100.0
	Game.start_recipe(bar)
	_check("Durchgang nimmt 4 Erz", Game.amounts["copper_ore"], 0.0)
	Game._advance_recipe(bar, 1.0)
	var bars_before: float = Game.amounts["copper_bar"]
	_check("Auto kostet 100", Game.recipe_upgrade_cost(bar, "auto")["copper_bar"], 100.0)
	Game.buy_recipe_upgrade(bar, "auto")
	_check("Auto gekauft: 100 weg, eingeschaltet, nicht nochmal kaufbar", [bars_before - Game.amounts["copper_bar"], Game.recipe_state["copper_bar"]["auto"], Game.recipe_upgrade_available(bar, "auto")], [100.0, true, false])
	Game.save_game()
	_reset()
	Game.load_game()
	_check("Rezept-Upgrades überleben Speichern", [Game.recipe_seconds(bar), Game.recipe_state["copper_bar"]["amount"], Game.recipe_state["copper_bar"]["auto_unlocked"]], [1.0, 1, true])
	_reset()

	# Rezepte verraten nichts: erst sichtbar, wenn die Zutat entdeckt ist
	Game.levels["smeltery"] = 15
	Game.seen["coal"] = true
	_check("Goldbarren-Rezept ohne Golderz unsichtbar", Game.recipe_visible(_recipe("gold_bar")), false)
	Game.amounts["gold_ore"] = 1.0
	Game._update_seen()
	_check("Mit Golderz sichtbar", Game.recipe_visible(_recipe("gold_bar")), true)
	_reset()
	Game._reset_discovery()

	# Kompakte Zahl für die Leiste
	Options.number_format = "short"
	_check("Leiste: drei Stellen", [Game.fmt_compact(1234567.0), Game.fmt_compact(12345678.0), Game.fmt_compact(123456789.0)], ["1,23 Mio", "12,3 Mio", "123 Mio"])
	Options.number_format = "scientific"

	# Zahlenformat
	_check("Format klein", Game.fmt(1234.9), "1234")
	_check("Format groß", Game.fmt(2_500_000.0), "2.50e6")
	_check("Format krumme Rate", Game.fmt_signed(0.8), "+0.8")
	_check("Format negative Rate", Game.fmt_signed(-2.0), "-2")
	Options.number_format = "short"
	_check("Kurz: Tausenderpunkt", Game.fmt(1234567.0 / 100.0), "12.345")
	_check("Kurz: Millionen", Game.fmt(2_500_000.0), "2,50 Mio")
	_check("Kurz: Milliarden", Game.fmt(4.5e9), "4,50 Mrd")
	_check("Kurz: Billionen", Game.fmt(123.4e12), "123,40 Bio")
	_check("Kurz: ohne Namen wissenschaftlich", Game.fmt(1.5e40), "1.50e40")
	_check("Kurz: Komma bei Raten", Game.fmt_signed(0.8), "+0,8")
	Options.number_format = "scientific"

	# Leisten-Auswahl: höchstens bar_max
	Game.bar_selection = []
	for res: Dictionary in Game.resources:
		if res["type"] == "stock":
			Game.set_bar_selected(res["id"], true)
	_check("Leiste nimmt höchstens 8", Game.bar_selection.size(), 8)
	_reset()
	Game._reset_discovery()

	# Für Bildschirmfotos: ein fortgeschrittener Spielstand
	if OS.get_cmdline_user_args().has("--demo"):
		Game.levels.merge({ "farm": 12, "housing": 14, "lumberjack": 4, "mine": 6, "market": 3, "watermill": 6, "sandmine": 2, "smeltery": 10, "factory": 5, "solarpanel": 1, "bank": 1, "coal_mining": 6, "copper_mining": 6, "iron_mining": 2 }, true)
		Game.amounts.merge({ "coins": 4820.0, "wood": 1310.0, "food": 960.0, "stone": 455.0, "sand": 88.0, "coal": 240.0, "copper_ore": 37.0, "iron_ore": 3.0, "copper_bar": 61.0, "iron_bar": 12.0 }, true)
		Game.recipe_state["copper_bar"].merge({ "auto_unlocked": true, "auto": true, "speed": 1 }, true)
		Game.click_counts["coins"] = 140
		Game._update_seen()

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
	# Aufdecken: Gebäude wird bekannt, Ressource wird entdeckt -> je eine Einblendung
	if not OS.get_cmdline_user_args().has("--demo"):
		Game.levels["farm"] = 1
		Game.amounts["stone"] = 5.0
		Game._update_seen()
		for i: int in 3:
			await get_tree().process_frame
		_check("Drei Einblendungen (Holzfäller, Stein, Nahrung)", main.get_node("%Toasts").get_child_count(), 3)

	# Kauf über die Zeile samt Aufblitzen darf keinen Fehler werfen
	Game.amounts["coins"] += 1000.0
	Game.amounts["wood"] += 1000.0
	var farm_level_before: int = Game.levels["farm"]
	main.get_node("%BuildingList").get_child(0)._on_buy_pressed()
	await get_tree().create_timer(0.1).timeout
	_check("Kauf über die Zeile zählt", Game.levels["farm"], farm_level_before + 1)
	_check("Rezeptzeilen angelegt, zwei Gruppen im Umschalter", [main.get_node("%RecipeList").get_child_count(), main.get_node("%RecipeGroups").get_child_count()], [Game.recipes.size(), 2])

	for arg: String in OS.get_cmdline_user_args():
		if arg == "--group2":
			main._recipe_group = "factory"
			await get_tree().process_frame
			await get_tree().process_frame
		if arg.begins_with("--scroll="):
			main.get_node("%BuildingList").get_parent().scroll_vertical = int(arg.trim_prefix("--scroll="))
			await get_tree().process_frame
		if arg == "--notch":
			main.set_insets(0.0, 130.0, 0.0, 70.0)  # wie ein Handy mit Notch und Wischleiste
			await get_tree().process_frame
			await get_tree().process_frame
		if arg == "--short":
			Options.number_format = "short"
			Game.amounts["coins"] = 48213456.0
			await get_tree().process_frame
		if arg == "--fresh":
			_reset()
			Game._reset_discovery()
			await get_tree().process_frame
			await get_tree().process_frame
		if arg == "--picker":
			main._open_bar_picker()
			await get_tree().process_frame
		if arg == "--settings":
			main._open_settings()
			await get_tree().process_frame
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

	# Wischen wie am Handy. Das lässt sich nur ohne Fenster verlässlich nachstellen;
	# bei Läufen mit Fenster (für Bildschirmfotos) wird es übersprungen.
	if DisplayServer.get_name() == "headless":
		await _test_swipe(main)

	# Reihenfolge im Upgrade-Reiter: Klick, Abwesenheit, Gebäude
	var kinds: Array = []
	for upgrade: Dictionary in Game.upgrades:
		var kind: String = "klick" if upgrade.has("add_click") else ("abwesenheit" if upgrade["id"].begins_with("offline_") else "gebäude")
		if kinds.is_empty() or kinds[-1] != kind:
			kinds.append(kind)
	_check("Upgrades: erst Klick, dann Abwesenheit, dann Gebäude", kinds, ["klick", "abwesenheit", "gebäude"])

	# Übersicht "Aktuell" im Upgrade-Reiter zeigt Klickstärke und Abwesenheit
	var bought_before: Dictionary = Game.bought.duplicate()
	for id: String in Game.bought:
		Game.bought[id] = false
	Game._rebuild_bonuses()
	main._update_stats()
	_check("Übersicht ohne Upgrades", [main._stat_labels["click_coins"].text, main._stat_labels["offline"].text], ["Coins pro Klick: 1", "Abwesenheit: noch nicht freigeschaltet"])
	Game.bought["offline_1"] = true
	Game.bought["click_coins_1"] = true
	Game._rebuild_bonuses()
	main._update_stats()
	_check("Übersicht mit Upgrades", [main._stat_labels["click_coins"].text, main._stat_labels["offline"].text], ["Coins pro Klick: 2", "Abwesenheit: bis 1 h, 20 % Ertrag"])
	Game.bought = bought_before
	Game._rebuild_bonuses()

	# Handy-Ränder: Zusatzrand kommt zum normalen Abstand dazu
	main.set_insets(0.0, 130.0, 0.0, 70.0)
	_check("Rand oben = 28 + 130", main.get_node("Margin").get_theme_constant("margin_top"), 158)
	_check("Rand unten = 28 + 70", main.get_node("Margin").get_theme_constant("margin_bottom"), 98)
	main.set_insets(0.0, 0.0, 0.0, 0.0)

	# Hinweis auf Kohle: Schmelze steht, Kohle nie gehabt
	_reset()
	Game.seen["coal"] = false
	Game.levels.merge({ "farm": 1, "housing": 5, "lumberjack": 1, "mine": 2, "market": 1, "sandmine": 1, "smeltery": 1 }, true)
	Game.amounts["sand"] = 5.0
	Game._update_seen()
	_check("Hinweis: Schmelze braucht Kohle", main._hint_text(), "Schmelze braucht Kohle: Bergbau unter Mine")

	# Einstiegshinweise: führen bis zur ersten Farm, danach Ruhe
	_reset()
	Game.levels["farm"] = 1
	_check("Nach der Farm: Hinweis auf Bevölkerung", main._hint_text(), "Holzfäller braucht Bevölkerung. Kaufe sie rechts mit Nahrung")
	Game.levels["housing"] = 1
	_check("Mit Bevölkerung kein Hinweis", main._hint_text(), "")
	_reset()
	_check("Am Anfang: tippen", main._hint_text(), "Tippe auf den Planeten")
	Game.click_counts["coins"] = 25
	Game.amounts["coins"] = 25.0
	Game.click_target = "coins"
	_check("Genug Coins: auf Holz umschalten", main._hint_text(), "Genug Coins. Schalte links um auf Holz")
	Game.click_target = "wood"
	_check("Beim Holzsammeln kein Hinweis", main._hint_text(), "")
	Game.amounts["wood"] = 25.0
	_check("Leistbar: Farm kaufen", main._hint_text(), "Kaufe unten: Farm")

	# Aufräumen: laufende Töne beenden, Testdateien löschen
	for player: AudioStreamPlayer in Sfx._players:
		player.stop()
		player.stream = null
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_options.json"))
	print("FEHLER: %d" % _failed if _failed > 0 else "ALLE TESTS OK")
	get_tree().quit(1 if _failed > 0 else 0)


func _building(id: String) -> Dictionary:
	for building: Dictionary in Game.buildings:
		if building["id"] == id:
			return building
	return {}


func _test_swipe(main: Node) -> void:
	# Wischen wie am Handy: Finger auf einen Kaufknopf setzen, nach oben ziehen,
	# loslassen. Die Liste muss scrollen, und es darf nichts gekauft werden.
	# Godot scrollt per Finger nur auf Geräten mit Touchscreen; am PC wird das
	# über "Maus als Finger" nachgestellt.
	_reset()
	Game.levels.merge({ "farm": 3, "housing": 30, "lumberjack": 2, "mine": 2, "market": 2, "sandmine": 2, "smeltery": 2, "watermill": 9, "factory": 1, "solarpanel": 1, "sawmill": 1 }, true)
	for id: String in Game.amounts:
		Game.amounts[id] = 1.0e9
	for i: int in 3:
		await get_tree().process_frame
	Input.emulate_touch_from_mouse = true
	var list_scroll: ScrollContainer = main.get_node("%BuildingList").get_parent()
	var row: Node = main.get_node("%BuildingList").get_child(2)
	var levels_before: Dictionary = Game.levels.duplicate()

	# Gegenprobe: Hält die Zeile die Berührung fest (der Fehler vom Handy),
	# bewegt sich nichts. So ist sicher, dass dieser Test den Fehler erkennt.
	row.get_node("Panel").mouse_filter = Control.MOUSE_FILTER_STOP
	await _swipe(row.get_node("%Name").get_global_rect().get_center())
	_check("Gegenprobe: festgehaltene Berührung scrollt nicht", list_scroll.scroll_vertical, 0)
	row.get_node("Panel").mouse_filter = Control.MOUSE_FILTER_PASS

	await _swipe(row.buy_button.get_global_rect().get_center())
	_check("Wischen scrollt die Gebäudeliste", list_scroll.scroll_vertical > 150, true)
	_check("Beim Wischen wird nichts gekauft", Game.levels, levels_before)
	await get_tree().create_timer(0.6).timeout
	var tap: Vector2 = row.buy_button.get_global_rect().get_center()
	if list_scroll.get_global_rect().has_point(tap):
		_touch(tap, true)
		await get_tree().process_frame
		_touch(tap, false)
		await get_tree().process_frame
		_check("Antippen kauft weiterhin", Game.levels["mine"], int(levels_before["mine"]) + 1)
	list_scroll.scroll_vertical = 0

	# Dasselbe im Fenster "Leiste anpassen": mit allen Ressourcen ist die Liste
	# länger als das Fenster und muss sich wischen lassen, auch auf einem Schalter.
	for id: String in Game.seen:
		Game.seen[id] = true
	main._open_bar_picker()
	for i: int in 3:
		await get_tree().process_frame
	var popup_scroll: ScrollContainer = main.get_node("%Popup").scroll
	var popup_rows: Array = main.get_node("%Popup").content.get_children()
	var selection_before: Array = Game.bar_selection.duplicate()
	_check("Auswahlliste ist länger als das Fenster", main.get_node("%Popup").content.size.y > popup_scroll.size.y, true)
	await _swipe(popup_rows[5].get_child(1).get_global_rect().get_center())
	_check("Wischen scrollt die Auswahlliste", popup_scroll.scroll_vertical > 150, true)
	_check("Beim Wischen wird kein Schalter umgelegt", Game.bar_selection, selection_before)
	main.get_node("%Popup").hide()
	Input.emulate_touch_from_mouse = false


## Ein Finger berührt den Bildschirm bzw. hebt ab. Android meldet das dem Spiel
## als Mausklick; genau das wird hier nachgestellt.
func _touch(at: Vector2, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	click.position = at
	click.global_position = at
	click.pressed = pressed
	get_viewport().push_input(click, true)


## Finger aufsetzen, 360 Pixel nach oben ziehen, loslassen.
func _swipe(from: Vector2) -> void:
	var finger: Vector2 = from
	_touch(finger, true)
	await get_tree().process_frame
	for i: int in 12:
		finger.y -= 30.0
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = finger
		motion.global_position = finger
		motion.relative = Vector2(0, -30)
		motion.velocity = Vector2(0, -900)
		get_viewport().push_input(motion, true)
		await get_tree().process_frame
	_touch(finger, false)
	for i: int in 3:
		await get_tree().process_frame

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
