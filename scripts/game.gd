extends Node
## Der gesamte Spielzustand und alle Regeln. Als Autoload "Game" überall erreichbar.
##
## Die Inhalte (welche Ressourcen, Gebäude und Rezepte es gibt, was sie kosten)
## stehen in data/*.json. Dieses Skript kennt kein einzelnes Gebäude beim Namen.
##
## Zwei Arten von Ressourcen:
##   stock    - ein Vorrat, der wächst und ausgegeben wird (Coins, Holz, ...)
##   capacity - eine Obergrenze, die belegt wird (Bevölkerung, Strom)
##
## Ein Gebäude kann pro Level:
##   cost     - einmalig Vorrat kosten (steigt mit jedem Level um "growth")
##   cost_per_level - zusätzlich Vorrat kosten, der gleichmäßig steigt: das erste
##                    Level kostet 1x, das zweite 2x, das dritte 3x ...
##   produces - Vorrat pro Sekunde liefern (negativ = laufender Verbrauch)
##   provides - Kapazität schaffen
##   reserves - Kapazität dauerhaft belegen
##   requires - erst kaufbar, wenn andere Gebäude ein Level erreicht haben
##
## Ein Upgrade wird einmal gekauft und verbessert dauerhaft etwas:
##   add_produces / add_provides - Gebäude liefern pro Level mehr
##   add_click                   - ein Klick bringt mehr
##   add_offline_hours / _percent - Abwesenheit zählt länger bzw. mit mehr Ertrag
## Ohne Abwesenheits-Upgrade passiert nichts, solange das Spiel zu ist.
## Freigeschaltet wird es über Gebäude-Level (requires), Klicks (requires_clicks)
## oder andere Upgrades (requires_upgrades).
##
## Ein Rezept wandelt in "seconds" Sekunden "input" in "output" um. Es gehört zu
## einem Gebäude und wird ab dessen Level "requires_level" freigeschaltet
## (ohne Angabe ab Level 1). Jedes Gebäude-Level darüber und jedes Mengen-Upgrade
## vergrößert den Durchgang um 1: mehr Zutaten hinein, mehr Ergebnis heraus, bei
## gleicher Dauer.
## Jedes Rezept hat drei eigene Upgrades, bezahlt mit dem, was es herstellt:
##   auto   - einmalig: das Rezept startet von selbst
##   speed  - je Stufe 1 Sekunde schneller, bis zur Mindestdauer
##   amount - je Stufe 1 Menge mehr (also Zutaten und Ergebnis um den Grundwert)

const SAVE_VERSION := 1

## Wird ausgelöst, wenn Abwesenheit nachgerechnet wurde (Start oder Rückkehr in die App).
signal offline_applied(report: Dictionary)

## Etwas Neues ist aufgetaucht (Gebäude aufgedeckt, Ressource entdeckt). Der
## Hauptbildschirm zeigt dazu eine kurze Einblendung.
signal announcement(icon_path: String, text: String)

var save_path: String = "user://save.json"  # Tests biegen das auf eine eigene Datei um.

var resources: Array = []
var buildings: Array = []
var recipes: Array = []
var upgrades: Array = []
var settings: Dictionary = {}

var amounts: Dictionary = {}       # Ressourcen-ID -> Vorrat
var levels: Dictionary = {}        # Gebäude-ID -> Level
var recipe_state: Dictionary = {}  # Rezept-ID -> Zustand, siehe _new_recipe_state()
var bought: Dictionary = {}        # Upgrade-ID -> gekauft?
var click_counts: Dictionary = {}  # Ressourcen-ID -> wie oft dafür geklickt wurde
var seen: Dictionary = {}          # Ressourcen-ID -> schon einmal besessen? Bleibt für immer wahr.
var bar_selection: Array = []      # Vorräte, die der Spieler in der Leiste oben sehen will
var click_target: String = "coins"
var buy_amount: int = 1      # feste Kaufmenge (1, 10, 100)
var buy_max: bool = false    # stattdessen: so viele wie leistbar

var _resource_by_id: Dictionary = {}
var _building_by_id: Dictionary = {}
var _bonus: Dictionary = {}  # Summe der gekauften Upgrades, siehe _rebuild_bonuses()
var _save_timer: float = 0.0
var _last_save_time: float = 0.0  # Zeitstempel des letzten Speicherns, 0 = noch nie

## Ergebnis der letzten Nachrechnung: { seconds, counted, gains }. Leer, wenn es
## nichts zu melden gab.
var offline_report: Dictionary = {}


func _ready() -> void:
	# Testszenen bekommen von Anfang an eine eigene Speicherdatei, damit sie den
	# echten Spielstand weder lesen noch überschreiben.
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("res://tests/"):
			save_path = "user://test_save.json"
	resources = _load_json("res://data/resources.json")
	buildings = _load_json("res://data/buildings.json")
	recipes = _load_json("res://data/recipes.json")
	upgrades = _load_json("res://data/upgrades.json")
	settings = _load_json("res://data/settings.json")
	for res: Dictionary in resources:
		_resource_by_id[res["id"]] = res
		if res["type"] == "stock":
			amounts[res["id"]] = 0.0
	for building: Dictionary in buildings:
		_building_by_id[building["id"]] = building
		levels[building["id"]] = 0
	for recipe: Dictionary in recipes:
		recipe_state[recipe["id"]] = _new_recipe_state()
	_set_recipe_building_caps()
	_expand_upgrade_series(_load_json("res://data/upgrade_series.json"))  # braucht die Gebäude von oben
	for upgrade: Dictionary in upgrades:
		bought[upgrade["id"]] = false
	for id: String in settings["click"]:
		click_counts[id] = 0
	_reset_discovery()
	load_game()
	_rebuild_bonuses()
	_catch_up()


func _process(delta: float) -> void:
	advance(delta)
	_save_timer += delta
	if _save_timer >= float(settings.get("autosave_seconds", 10)):
		save_game()


## Lässt die Spielwelt um "delta" Sekunden weiterlaufen: Gebäude produzieren,
## Rezepte laufen. Getrennt vom Speichern, damit die Balancing-Simulation
## (tests/sim.gd) Stunden in Sekunden durchspielen kann.
func advance(delta: float) -> void:
	var rates: Dictionary = get_rates()
	for id: String in rates:
		amounts[id] = maxf(0.0, amounts[id] + rates[id] * delta)
	for recipe: Dictionary in recipes:
		_advance_recipe(recipe, delta)
	_update_seen()


func _notification(what: int) -> void:
	# Fenster wird geschlossen bzw. App geht am Handy in den Hintergrund.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()
	# Am Handy läuft das Spiel im Hintergrund nicht weiter. Bei der Rückkehr wird
	# die Zeit seit dem Speichern nachgerechnet.
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_catch_up()


# --- Abfragen ---------------------------------------------------------------

func resource_def(id: String) -> Dictionary:
	return _resource_by_id[id]


func building_def(id: String) -> Dictionary:
	return _building_by_id[id]


## Netto-Produktion aller Vorräte pro Sekunde (ohne Rezepte).
func get_rates() -> Dictionary:
	var rates: Dictionary = {}
	for building: Dictionary in buildings:
		var level: int = levels[building["id"]]
		if level == 0:
			continue
		var produces: Dictionary = building_output(building, "produces")
		for id: String in produces:
			rates[id] = rates.get(id, 0.0) + float(produces[id]) * level
	return rates


## Was ein Gebäude pro Level liefert: Grundwert aus den Daten plus gekaufte
## Upgrades. "key" ist "produces" oder "provides".
func building_output(building: Dictionary, key: String) -> Dictionary:
	var result: Dictionary = building.get(key, {}).duplicate()
	var bonus: Dictionary = _bonus.get(key, {}).get(building["id"], {})
	for id: String in bonus:
		result[id] = float(result.get(id, 0.0)) + bonus[id]
	return result


## Wie viele Stunden Abwesenheit höchstens angerechnet werden (0 = gar keine).
func offline_hours() -> float:
	return _bonus.get("offline_hours", 0.0)


## Wie viel Prozent der normalen Produktion bei Abwesenheit zählen.
func offline_percent() -> float:
	return _bonus.get("offline_percent", 0.0)


## Wie viel ein Klick für eine Ressource bringt.
func click_gain(id: String) -> float:
	return float(settings["click"][id]) + _bonus.get("click", {}).get(id, 0.0)


func capacity_total(id: String) -> float:
	return _sum_over_buildings("provides", id)


func capacity_used(id: String) -> float:
	return _sum_over_buildings("reserves", id)


func capacity_free(id: String) -> float:
	return capacity_total(id) - capacity_used(id)


## Wie ein Gebäude in der Liste erscheint – die Überraschung wie bei Cookie Clicker:
##   "known"   - normal sichtbar und kaufbar
##   "mystery" - als schwarzer Umriss mit "???": das nächste, das kommt
##   "hidden"  - noch gar nicht da
## Bekannt ist ein Gebäude, wenn sein Vorgänger in derselben Liste gekauft wurde
## und seine Voraussetzungen erfüllt sind. Genau eines danach ist das Rätsel.
func building_visibility(building: Dictionary) -> String:
	if building.get("placement", "list") != "list":
		return "known"
	var previous_known: bool = true
	var previous_owned: bool = true
	for sibling: Dictionary in buildings:
		if sibling.get("placement", "list") != "list" or sibling.get("parent", "") != building.get("parent", ""):
			continue
		# Was man schon besitzt, bleibt immer sichtbar (auch bei älteren Spielständen).
		var known: bool = levels[sibling["id"]] > 0 or (previous_known and previous_owned and is_unlocked(sibling))
		if sibling["id"] == building["id"]:
			if known:
				return "known"
			return "mystery" if previous_known else "hidden"
		previous_known = known
		previous_owned = levels[sibling["id"]] > 0
	return "hidden"


## Das Gebäude, das in derselben Liste direkt davor steht (leer, wenn keines).
func previous_building(building: Dictionary) -> Dictionary:
	var previous: Dictionary = {}
	for sibling: Dictionary in buildings:
		if sibling.get("placement", "list") != "list" or sibling.get("parent", "") != building.get("parent", ""):
			continue
		if sibling["id"] == building["id"]:
			return previous
		previous = sibling
	return {}


## Dasselbe für Upgrades: gekaufte und Kettenglieder ohne Vorgänger sind weg,
## freigeschaltete sichtbar, und ein Rätsel ist ein Upgrade nur für Gebäude,
## die man schon besitzt.
func upgrade_visibility(upgrade: Dictionary) -> String:
	if bought[upgrade["id"]] or not upgrade_visible(upgrade):
		return "hidden"
	if upgrade_unlocked(upgrade):
		return "known"
	var requires: Dictionary = upgrade.get("requires", {})
	for id: String in requires:
		if levels[id] == 0:
			return "hidden"
	return "mystery"


## Gebäude mit Rezepten lassen sich noch ein Stück über ihre letzte Freischaltung
## hinaus ausbauen, damit auch das letzte Rezept größere Durchgänge bekommt:
## Höchstlevel = höchstes "requires_level" + "levels_after_last_recipe".
## Kommt später ein Rezept dazu, wandert die Grenze von selbst mit.
func _set_recipe_building_caps() -> void:
	for building: Dictionary in buildings:
		if not building.has("levels_after_last_recipe"):
			continue
		var last_unlock: int = 0
		for recipe: Dictionary in recipes:
			if recipe["building"] == building["id"]:
				last_unlock = maxi(last_unlock, int(recipe.get("requires_level", 1)))
		building["max_level"] = last_unlock + int(building["levels_after_last_recipe"])


## Hat das Gebäude sein Höchstlevel erreicht? Dann gibt es nichts mehr zu kaufen.
func is_maxed(building: Dictionary) -> bool:
	return building.has("max_level") and levels[building["id"]] >= int(building["max_level"])


## Sind alle Voraussetzungen ("requires") eines Gebäudes erfüllt?
func is_unlocked(building: Dictionary) -> bool:
	var requires: Dictionary = building.get("requires", {})
	for id: String in requires:
		if levels[id] < int(requires[id]):
			return false
	return true


## Kosten für die nächsten "count" Level eines Gebäudes.
## Ein Level kostet Basis * growth^Level, mehrere Level sind die Summe davon.
func cost_for(building: Dictionary, count: int) -> Dictionary:
	var level: int = levels[building["id"]]
	var growth: float = float(building.get("growth", 1.0))
	var factor: float
	if is_equal_approx(growth, 1.0):
		factor = float(count)
	else:
		factor = pow(growth, level) * (pow(growth, count) - 1.0) / (growth - 1.0)
	var result: Dictionary = {}
	var cost: Dictionary = building.get("cost", {})
	for id: String in cost:
		result[id] = roundf(float(cost[id]) * factor)
	# Gleichmäßig steigender Anteil: Level n kostet n mal den Grundwert. Für mehrere
	# Level auf einmal ist das die Summe (level+1) + (level+2) + ... + (level+count).
	var per_level: Dictionary = building.get("cost_per_level", {})
	for id: String in per_level:
		var steps: float = count * level + count * (count + 1) / 2.0
		result[id] = float(result.get(id, 0.0)) + float(per_level[id]) * steps
	return result


func can_buy(building: Dictionary, count: int) -> bool:
	if building_visibility(building) != "known":
		return false
	# Manche Gebäude gibt es nur begrenzt oft (Schmelze, Fabrik: einmal).
	if building.has("max_level") and levels[building["id"]] + count > int(building["max_level"]):
		return false
	# Manche Gebäude dürfen ein anderes nicht überholen (Erzabbau <= Mine).
	if building.has("level_cap") and levels[building["id"]] + count > levels[building["level_cap"]]:
		return false
	var cost: Dictionary = cost_for(building, count)
	for id: String in cost:
		if amounts[id] < cost[id]:
			return false
	var reserves: Dictionary = building.get("reserves", {})
	for id: String in reserves:
		if capacity_free(id) < float(reserves[id]) * count:
			return false
	# Laufender Verbrauch darf die Produktion nicht ins Minus drücken.
	var rates: Dictionary = get_rates()
	var produces: Dictionary = building_output(building, "produces")
	for id: String in produces:
		var change: float = float(produces[id]) * count
		if change < 0.0 and rates.get(id, 0.0) + change < 0.0:
			return false
	return true


## Wie viele Einheiten ein Rezept pro Durchgang verarbeitet: 1 beim Freischalten,
## dazu +1 je weiterem Gebäude-Level und +1 je Mengen-Upgrade. Unter dem
## Freischalt-Level 0, das Rezept ist dann nicht verfügbar.
func recipe_batch(recipe: Dictionary) -> int:
	var unlock_level: int = int(recipe.get("requires_level", 1))
	var building_level: int = levels[recipe["building"]]
	if building_level < unlock_level:
		return 0
	return 1 + (building_level - unlock_level) + int(recipe_state[recipe["id"]]["amount"])


## Ab welchem Level das Gebäude sein nächstes Rezept freischaltet (0 = keines mehr).
func next_recipe_level(building: Dictionary) -> int:
	var next: int = 0
	for recipe: Dictionary in recipes:
		var needed: int = int(recipe.get("requires_level", 1))
		if recipe["building"] == building["id"] and needed > levels[building["id"]] and (next == 0 or needed < next):
			next = needed
	return next


## Ein Rezept taucht erst auf, wenn sein Gebäude steht und der Spieler alle
## Zutaten schon einmal hatte – sonst verriete es, was noch kommt.
func recipe_visible(recipe: Dictionary) -> bool:
	if recipe_batch(recipe) == 0:
		return false
	for id: String in recipe["input"]:
		if not seen[id]:
			return false
	return true


## Dauer eines Durchgangs nach Tempo-Upgrades, nie unter der Mindestdauer.
func recipe_seconds(recipe: Dictionary) -> float:
	var rules: Dictionary = settings["recipe_upgrades"]
	var faster: float = float(rules["seconds_per_level"]) * int(recipe_state[recipe["id"]]["speed"])
	return maxf(float(rules["min_seconds"]), float(recipe["seconds"]) - faster)


## Gibt es dieses Upgrade ("auto", "speed", "amount") für das Rezept noch?
func recipe_upgrade_available(recipe: Dictionary, kind: String) -> bool:
	var state: Dictionary = recipe_state[recipe["id"]]
	match kind:
		"auto":
			return not state["auto_unlocked"]
		"speed":
			return recipe_seconds(recipe) > float(settings["recipe_upgrades"]["min_seconds"])
	return true


## Wie viele Stufen es von diesem Upgrade höchstens gibt (0 = unbegrenzt).
## Tempo endet, wenn die Mindestdauer erreicht ist: 4 s Grunddauer -> 3 Stufen.
func recipe_upgrade_max(recipe: Dictionary, kind: String) -> int:
	var rules: Dictionary = settings["recipe_upgrades"]
	match kind:
		"auto":
			return 1
		"speed":
			return int(ceil((float(recipe["seconds"]) - float(rules["min_seconds"])) / float(rules["seconds_per_level"])))
	return 0


## Preis des nächsten Upgrades, bezahlt mit dem Erzeugnis des Rezepts.
## Auto kostet einen festen Betrag; Tempo und Menge kosten 25, 50, 75 ...
func recipe_upgrade_cost(recipe: Dictionary, kind: String) -> Dictionary:
	var rules: Dictionary = settings["recipe_upgrades"]
	var product: String = recipe["output"].keys()[0]
	if kind == "auto":
		return { product: float(rules["auto_cost"]) }
	var level: int = int(recipe_state[recipe["id"]][kind])
	return { product: float(rules["cost_step"]) * (level + 1) }


func can_buy_recipe_upgrade(recipe: Dictionary, kind: String) -> bool:
	if recipe_batch(recipe) == 0 or not recipe_upgrade_available(recipe, kind):
		return false
	var cost: Dictionary = recipe_upgrade_cost(recipe, kind)
	for id: String in cost:
		if amounts[id] < cost[id]:
			return false
	return true


func can_start_recipe(recipe: Dictionary) -> bool:
	var batch: int = recipe_batch(recipe)
	if batch == 0 or recipe_state[recipe["id"]]["running"]:
		return false
	var input: Dictionary = recipe["input"]
	for id: String in input:
		if amounts[id] < float(input[id]) * batch:
			return false
	return true


# --- Aktionen ---------------------------------------------------------------

func click() -> float:
	var gain: float = click_gain(click_target)
	amounts[click_target] += gain
	click_counts[click_target] += 1
	return gain


func buy(building: Dictionary) -> bool:
	var count: int = buy_count(building)
	if not can_buy(building, count):
		return false
	var cost: Dictionary = cost_for(building, count)
	for id: String in cost:
		amounts[id] -= cost[id]
	levels[building["id"]] += count
	return true


## Wie viele Level ein Druck auf "Kaufen" gerade kauft: die feste Menge oder,
## bei "Max", so viele wie leistbar (mindestens 1, damit ein Preis dasteht).
func buy_count(building: Dictionary) -> int:
	if not buy_max:
		return buy_amount
	return maxi(1, max_affordable(building))


## Größte Menge, die sich gerade ausgeht. Weil "n leistbar" auch "weniger als n
## leistbar" bedeutet, lässt sich die Grenze einkreisen: erst verdoppeln, bis es
## nicht mehr reicht, dann die Mitte suchen.
func max_affordable(building: Dictionary) -> int:
	if not can_buy(building, 1):
		return 0
	var low: int = 1      # geht sicher
	var high: int = 2     # wird gesucht: geht sicher nicht
	while high <= 100000 and can_buy(building, high):
		low = high
		high *= 2
	while high - low > 1:
		var middle: int = (low + high) / 2
		if can_buy(building, middle):
			low = middle
		else:
			high = middle
	return low


## Legt fest, welche Vorräte die Leiste oben zeigt (höchstens bar_max).
func set_bar_selected(id: String, selected: bool) -> void:
	if not selected:
		bar_selection.erase(id)
	elif not bar_selection.has(id) and bar_selection.size() < int(settings.get("bar_max", 8)):
		bar_selection.append(id)


## Schaltet zur nächsten Kaufmenge aus data/settings.json: 1 -> 10 -> 100 -> Max -> 1
func cycle_buy_amount() -> void:
	var options: Array = settings["buy_amounts"]
	var current: Variant = "max" if buy_max else float(buy_amount)
	var next: Variant = options[(options.find(current) + 1) % options.size()]
	buy_max = typeof(next) == TYPE_STRING
	if not buy_max:
		buy_amount = int(next)


## Upgrades einer Kette tauchen erst auf, wenn ihr Vorgänger gekauft ist.
func upgrade_visible(upgrade: Dictionary) -> bool:
	for id: String in upgrade.get("requires_upgrades", []):
		if not bought[id]:
			return false
	return true


func upgrade_unlocked(upgrade: Dictionary) -> bool:
	if not is_unlocked(upgrade) or not upgrade_visible(upgrade):
		return false
	var clicks: Dictionary = upgrade.get("requires_clicks", {})
	for id: String in clicks:
		if click_counts[id] < int(clicks[id]):
			return false
	return true


func can_buy_upgrade(upgrade: Dictionary) -> bool:
	if bought[upgrade["id"]] or not upgrade_unlocked(upgrade):
		return false
	var cost: Dictionary = upgrade.get("cost", {})
	for id: String in cost:
		if amounts[id] < float(cost[id]):
			return false
	return true


func buy_upgrade(upgrade: Dictionary) -> bool:
	if not can_buy_upgrade(upgrade):
		return false
	var cost: Dictionary = upgrade.get("cost", {})
	for id: String in cost:
		amounts[id] -= float(cost[id])
	bought[upgrade["id"]] = true
	_rebuild_bonuses()
	return true


## Startet einen Durchgang: Die Zutaten werden sofort abgezogen, das Ergebnis
## kommt nach Ablauf der Zeit.
func start_recipe(recipe: Dictionary) -> bool:
	if not can_start_recipe(recipe):
		return false
	var state: Dictionary = recipe_state[recipe["id"]]
	var batch: int = recipe_batch(recipe)
	var input: Dictionary = recipe["input"]
	for id: String in input:
		amounts[id] -= float(input[id]) * batch
	state["running"] = true
	state["progress"] = 0.0
	state["batch"] = batch
	return true


func set_recipe_auto(recipe: Dictionary, enabled: bool) -> void:
	var state: Dictionary = recipe_state[recipe["id"]]
	state["auto"] = enabled and state["auto_unlocked"]


func buy_recipe_upgrade(recipe: Dictionary, kind: String) -> bool:
	if not can_buy_recipe_upgrade(recipe, kind):
		return false
	var cost: Dictionary = recipe_upgrade_cost(recipe, kind)
	for id: String in cost:
		amounts[id] -= cost[id]
	var state: Dictionary = recipe_state[recipe["id"]]
	if kind == "auto":
		state["auto_unlocked"] = true
		state["auto"] = true  # gleich einschalten, dafür wurde es gekauft
	else:
		state[kind] = int(state[kind]) + 1
	return true


func _advance_recipe(recipe: Dictionary, delta: float) -> void:
	var state: Dictionary = recipe_state[recipe["id"]]
	if state["running"]:
		state["progress"] += delta
		if state["progress"] >= recipe_seconds(recipe):
			_advance_recipe_to_end(recipe)
	if state["auto"] and not state["running"]:
		start_recipe(recipe)


# --- Abwesenheit -------------------------------------------------------------

## Rechnet nach, was in "seconds" Sekunden Abwesenheit passiert wäre, und gibt
## einen Bericht zurück. Dauer und Ertrag hängen von den gekauften Upgrades ab:
## höchstens offline_hours() Stunden, davon zählen offline_percent() Prozent.
##   - Gebäude liefern ihre normale Produktion.
##   - Ein laufender Rezept-Durchgang wird fertig.
##   - Rezepte auf "Auto" laufen weiter, solange Zeit und Zutaten reichen.
func apply_offline(seconds: float) -> Dictionary:
	var counted: float = clampf(seconds, 0.0, offline_hours() * 3600.0)
	var effective: float = counted * offline_percent() / 100.0  # so viel Zeit zählt wirklich
	var before: Dictionary = amounts.duplicate()
	var rates: Dictionary = get_rates()
	for id: String in rates:
		amounts[id] = maxf(0.0, amounts[id] + rates[id] * effective)
	for recipe: Dictionary in recipes:
		_offline_recipe(recipe, effective)
	var gains: Dictionary = {}
	for id: String in amounts:
		if amounts[id] - before[id] >= 1.0:
			gains[id] = amounts[id] - before[id]
	return { "seconds": seconds, "counted": counted, "percent": offline_percent(), "gains": gains }


func _offline_recipe(recipe: Dictionary, seconds: float) -> void:
	var state: Dictionary = recipe_state[recipe["id"]]
	var duration: float = recipe_seconds(recipe)
	var time_left: float = seconds
	if state["running"]:
		var remaining: float = duration - float(state["progress"])
		if time_left < remaining:
			state["progress"] += time_left
			return
		_advance_recipe_to_end(recipe)
		time_left -= remaining
	var batch: int = recipe_batch(recipe)
	if not state["auto"] or batch == 0:
		return
	# Wie viele ganze Durchgänge gehen sich aus? Begrenzt durch Zeit und Zutaten.
	var cycles: float = floorf(time_left / duration)
	var input: Dictionary = recipe["input"]
	for id: String in input:
		cycles = minf(cycles, floorf(amounts[id] / (float(input[id]) * batch)))
	for id: String in input:
		amounts[id] -= float(input[id]) * batch * cycles
	var output: Dictionary = recipe["output"]
	for id: String in output:
		amounts[id] += float(output[id]) * batch * cycles


func _advance_recipe_to_end(recipe: Dictionary) -> void:
	var state: Dictionary = recipe_state[recipe["id"]]
	var output: Dictionary = recipe["output"]
	for id: String in output:
		amounts[id] += float(output[id]) * int(state["batch"])
	state["running"] = false
	state["progress"] = 0.0


## Zeit seit dem letzten Speichern nachrechnen und melden, wenn es sich lohnt.
func _catch_up() -> void:
	if _last_save_time <= 0.0 or offline_hours() <= 0.0 or offline_percent() <= 0.0:
		return
	var away: float = Time.get_unix_time_from_system() - _last_save_time
	if away < float(settings.get("offline_min_seconds", 60)):
		return  # Kurze Pausen laufen stillschweigend weiter, ohne Fenster.
	var report: Dictionary = apply_offline(away)
	save_game()
	if not report["gains"].is_empty():
		offline_report = report
		offline_applied.emit(report)


# --- Speichern --------------------------------------------------------------

func save_game() -> void:
	_save_timer = 0.0
	_last_save_time = Time.get_unix_time_from_system()
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"time": _last_save_time,
		"amounts": amounts,
		"levels": levels,
		"recipes": recipe_state,
		"bought": bought,
		"click_counts": click_counts,
		"seen": seen,
		"bar": bar_selection,
		"click_target": click_target,
	}
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Speichern fehlgeschlagen: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Spielstand unlesbar, starte neu.")
		return
	# Nur übernehmen, was es in den Daten noch gibt. So überlebt ein Spielstand,
	# wenn später Ressourcen, Gebäude oder Rezepte dazukommen oder wegfallen.
	_last_save_time = float(data.get("time", 0.0))
	var saved_amounts: Dictionary = data.get("amounts", {})
	for id: String in amounts:
		amounts[id] = float(saved_amounts.get(id, 0.0))
	var saved_levels: Dictionary = data.get("levels", {})
	for id: String in levels:
		levels[id] = int(saved_levels.get(id, 0))
	var saved_recipes: Dictionary = data.get("recipes", {})
	for id: String in recipe_state:
		var saved: Dictionary = saved_recipes.get(id, {})
		recipe_state[id] = {
			"auto_unlocked": bool(saved.get("auto_unlocked", false)),
			"auto": bool(saved.get("auto", false)) and bool(saved.get("auto_unlocked", false)),
			"speed": int(saved.get("speed", 0)),
			"amount": int(saved.get("amount", 0)),
			"running": bool(saved.get("running", false)),
			"progress": float(saved.get("progress", 0.0)),
			"batch": int(saved.get("batch", 0)),
		}
	var saved_bought: Dictionary = data.get("bought", {})
	for id: String in bought:
		bought[id] = bool(saved_bought.get(id, false))
	var saved_clicks: Dictionary = data.get("click_counts", {})
	for id: String in click_counts:
		click_counts[id] = int(saved_clicks.get(id, 0))
	var saved_seen: Dictionary = data.get("seen", {})
	for id: String in seen:
		seen[id] = seen[id] or bool(saved_seen.get(id, false))
	if data.has("bar"):
		bar_selection = []
		for id: Variant in data["bar"]:
			if amounts.has(id):
				bar_selection.append(id)
	_update_seen()  # Spielstände von früher: alles, was man hat, gilt als entdeckt
	var target: String = data.get("click_target", "coins")
	if settings["click"].has(target):
		click_target = target


func reset_game() -> void:
	for id: String in amounts:
		amounts[id] = 0.0
	for id: String in levels:
		levels[id] = 0
	for id: String in recipe_state:
		recipe_state[id] = _new_recipe_state()
	for id: String in bought:
		bought[id] = false
	for id: String in click_counts:
		click_counts[id] = 0
	_reset_discovery()
	_rebuild_bonuses()
	save_game()


# --- Hilfen -----------------------------------------------------------------

## Namen für je drei Stellen mehr, beginnend bei der Million.
const NUMBER_NAMES: Array = ["Mio", "Mrd", "Bio", "Brd", "Trio", "Trd", "Quad", "Qrd"]


## Zahl für die Anzeige, je nach Einstellung:
##   kurz:             12.345   1,23 Mio   4,50 Mrd
##   wissenschaftlich: 12345    1.23e6     4.50e9
## Gehen die Namen aus, wird auch im kurzen Format wissenschaftlich geschrieben.
func fmt(value: float) -> String:
	var short: bool = Options.number_format == "short"
	if value < 1_000_000.0:
		var digits: String = str(int(floor(value)))
		return _group_thousands(digits) if short else digits
	var exponent: int = int(floor(log(value) / log(10.0)))
	var name_index: int = exponent / 3 - 2
	if short and name_index < NUMBER_NAMES.size():
		var mantissa: float = value / pow(10.0, (name_index + 2) * 3)
		return ("%.2f" % mantissa).replace(".", ",") + " " + NUMBER_NAMES[name_index]
	return "%.2fe%d" % [value / pow(10.0, exponent), exponent]


## Wie fmt, aber ab einer Million mit drei Stellen statt mit festen zwei
## Nachkommastellen: 1,23 Mio / 12,3 Mio / 123 Mio. Für Stellen mit wenig Platz.
func fmt_compact(value: float) -> String:
	if value < 1_000_000.0 or Options.number_format != "short":
		return fmt(value)
	var name_index: int = int(floor(log(value) / log(10.0))) / 3 - 2
	if name_index >= NUMBER_NAMES.size():
		return fmt(value)
	var mantissa: float = value / pow(10.0, (name_index + 2) * 3)
	var decimals: int = 2 if mantissa < 10.0 else (1 if mantissa < 100.0 else 0)
	return ("%.*f" % [decimals, mantissa]).replace(".", ",") + " " + NUMBER_NAMES[name_index]


## 1234567 -> 1.234.567
func _group_thousands(digits: String) -> String:
	var result: String = ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += "."
		result += digits[i]
	return result


## Wie fmt, aber mit Vorzeichen und einer Nachkommastelle bei krummen kleinen
## Werten – für Angaben wie "+0.8/s".
func fmt_signed(value: float) -> String:
	var sign_text: String = "-" if value < 0.0 else "+"
	var magnitude: float = absf(value)
	if magnitude < 100.0 and not is_equal_approx(magnitude, roundf(magnitude)):
		var text: String = "%.1f" % magnitude
		return sign_text + (text.replace(".", ",") if Options.number_format == "short" else text)
	return sign_text + fmt(magnitude)


## Rechnet aus allen gekauften Upgrades zusammen, was sie bewirken. Das Ergebnis
## wird gemerkt, damit nicht jedes Bild alle Upgrades durchgegangen werden müssen.
##   _bonus["produces"][Gebäude-ID][Ressourcen-ID] = Zuschlag pro Level
##   _bonus["click"][Ressourcen-ID] = Zuschlag pro Klick
func _rebuild_bonuses() -> void:
	_bonus = { "produces": {}, "provides": {}, "click": {}, "offline_hours": 0.0, "offline_percent": 0.0 }
	for upgrade: Dictionary in upgrades:
		if not bought[upgrade["id"]]:
			continue
		for key: String in ["produces", "provides"]:
			var per_building: Dictionary = upgrade.get("add_" + key, {})
			for building_id: String in per_building:
				if not _bonus[key].has(building_id):
					_bonus[key][building_id] = {}
				var target: Dictionary = _bonus[key][building_id]
				for id: String in per_building[building_id]:
					target[id] = target.get(id, 0.0) + float(per_building[building_id][id])
		_bonus["offline_hours"] += float(upgrade.get("add_offline_hours", 0.0))
		_bonus["offline_percent"] += float(upgrade.get("add_offline_percent", 0.0))
		var click_bonus: Dictionary = upgrade.get("add_click", {})
		for id: String in click_bonus:
			_bonus["click"][id] = _bonus["click"].get(id, 0.0) + float(click_bonus[id])


## Erzeugt die Gebäude-Upgrades aus einer Regel statt aus einzelnen Einträgen:
## Alle "every_levels" Level gibt es eine Stufe. Stufe n bringt n * step mal die
## Grundproduktion dazu – bei step 0,5 und Grundwert 1 also +0,5, dann +1, dann
## +1,5 usw. Jede Stufe erscheint erst, wenn die vorige gekauft ist.
## Der Preis ist das cost_factor-Fache dessen, was das Gebäude auf dem
## Freischalt-Level kostet, und wächst damit von selbst mit.
func _expand_upgrade_series(series: Dictionary) -> void:
	var building_upgrades: Array = []
	var click_upgrades: Array = []
	var every: int = int(series["every_levels"])
	var step: float = float(series["step"])
	for entry: Dictionary in series["buildings"]:
		var building: Dictionary = _building_by_id[entry["building"]]
		var growth: float = float(building.get("growth", 1.0))
		# Wie viele Stufen es gibt, kann je Gebäude abweichen (späte Gebäude mehr).
		for tier: int in range(1, int(entry.get("tiers", series["tiers"])) + 1):
			var upgrade: Dictionary = {
				"id": "%s_%d" % [building["id"], tier],
				"name": "%s %s" % [entry["name"], _roman(tier)],
				"icon": building["icon"],
				"requires": { building["id"]: every * tier },
				"cost": {},
			}
			if tier > 1:
				upgrade["requires_upgrades"] = ["%s_%d" % [building["id"], tier - 1]]
			var cost: Dictionary = building.get("cost", {})
			for id: String in cost:
				upgrade["cost"][id] = roundf(float(cost[id]) * pow(growth, every * tier) * float(series["cost_factor"]))
			var produces: Dictionary = building.get("produces", {})
			for id: String in produces:
				if float(produces[id]) > 0.0:
					upgrade["add_produces"] = { building["id"]: { id: step * tier * float(produces[id]) } }
			# Versorgung (Strom) gibt es nur in ganzen Einheiten, daher aufgerundet.
			var provides: Dictionary = building.get("provides", {})
			for id: String in provides:
				upgrade["add_provides"] = { building["id"]: { id: ceilf(step * tier * float(provides[id])) } }
			building_upgrades.append(upgrade)

	# Klick-Upgrades nach demselben Muster: alle "every_clicks" Klicks eine Stufe,
	# jede bringt "amount" mehr pro Klick. Der Preis wächst mit der Klickzahl.
	var clicks: Dictionary = series["clicks"]
	var every_clicks: int = int(clicks["every_clicks"])
	for entry: Dictionary in clicks["resources"]:
		var id: String = entry["resource"]
		for tier: int in range(1, int(clicks["tiers"]) + 1):
			var needed: int = every_clicks * tier
			var upgrade: Dictionary = {
				"id": "click_%s_%d" % [id, tier],
				"name": "%s %s" % [entry["name"], _roman(tier)],
				"icon": _resource_by_id[id]["icon"],
				"requires_clicks": { id: needed },
				"cost": {
					id: roundf(needed * float(clicks["cost_per_click"])),
					entry["other"]: roundf(needed * float(clicks["other_cost_per_click"])),
				},
				"add_click": { id: float(clicks["amount"]) },
			}
			if tier > 1:
				upgrade["requires_upgrades"] = ["click_%s_%d" % [id, tier - 1]]
			click_upgrades.append(upgrade)

	# Reihenfolge im Reiter: Klick-Upgrades, dann die aus data/upgrades.json
	# (Abwesenheit), dann die Gebäude-Upgrades.
	upgrades = click_upgrades + upgrades + building_upgrades


## 1 -> I, 4 -> IV, 14 -> XIV
func _roman(number: int) -> String:
	var values: Array = [50, 40, 10, 9, 5, 4, 1]
	var symbols: Array = ["L", "XL", "X", "IX", "V", "IV", "I"]
	var result: String = ""
	for i: int in values.size():
		while number >= values[i]:
			result += symbols[i]
			number -= values[i]
	return result


## Ausgangszustand: Entdeckt ist nur, was man anklicken kann. Die Leiste zeigt
## die Vorräte, die in den Daten mit "bar" markiert sind.
func _reset_discovery() -> void:
	bar_selection = []
	for res: Dictionary in resources:
		seen[res["id"]] = settings["click"].has(res["id"])
		if res["type"] == "stock" and res.get("bar", false):
			bar_selection.append(res["id"])


## Merkt sich, welche Ressourcen der Spieler schon einmal hatte.
func _update_seen() -> void:
	for res: Dictionary in resources:
		var id: String = res["id"]
		if seen[id]:
			continue
		if res["type"] == "stock":
			seen[id] = amounts[id] > 0.0
		else:
			seen[id] = capacity_total(id) > 0.0


func _new_recipe_state() -> Dictionary:
	return {
		"auto_unlocked": false,  # Auto-Upgrade gekauft?
		"auto": false,           # Auto gerade eingeschaltet?
		"speed": 0,              # gekaufte Tempo-Stufen
		"amount": 0,             # gekaufte Mengen-Stufen
		"running": false,
		"progress": 0.0,         # Sekunden im laufenden Durchgang
		"batch": 0,              # Menge des laufenden Durchgangs
	}


func _sum_over_buildings(key: String, id: String) -> float:
	var total: float = 0.0
	for building: Dictionary in buildings:
		var entry: Dictionary = building_output(building, key) if key == "provides" else building.get(key, {})
		total += float(entry.get(id, 0.0)) * levels[building["id"]]
	return total


func _load_json(path: String) -> Variant:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data != null, "Datei fehlt oder ist kein gültiges JSON: %s" % path)
	return data
