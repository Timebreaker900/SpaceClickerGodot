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
## einem Gebäude; dessen Level bestimmt, wie viel pro Durchgang verarbeitet wird.

const SAVE_VERSION := 1

## Wird ausgelöst, wenn Abwesenheit nachgerechnet wurde (Start oder Rückkehr in die App).
signal offline_applied(report: Dictionary)

var save_path: String = "user://save.json"  # Tests biegen das auf eine eigene Datei um.

var resources: Array = []
var buildings: Array = []
var recipes: Array = []
var upgrades: Array = []
var settings: Dictionary = {}

var amounts: Dictionary = {}       # Ressourcen-ID -> Vorrat
var levels: Dictionary = {}        # Gebäude-ID -> Level
var recipe_state: Dictionary = {}  # Rezept-ID -> { auto, running, progress, batch }
var bought: Dictionary = {}        # Upgrade-ID -> gekauft?
var click_counts: Dictionary = {}  # Ressourcen-ID -> wie oft dafür geklickt wurde
var seen: Dictionary = {}          # Ressourcen-ID -> schon einmal besessen? Bleibt für immer wahr.
var bar_selection: Array = []      # Vorräte, die der Spieler in der Leiste oben sehen will
var click_target: String = "coins"
var buy_amount: int = 1

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
	for upgrade: Dictionary in upgrades:
		bought[upgrade["id"]] = false
	for id: String in settings["click"]:
		click_counts[id] = 0
	_reset_discovery()
	load_game()
	_rebuild_bonuses()
	_catch_up()


func _process(delta: float) -> void:
	var rates: Dictionary = get_rates()
	for id: String in rates:
		amounts[id] = maxf(0.0, amounts[id] + rates[id] * delta)
	for recipe: Dictionary in recipes:
		_advance_recipe(recipe, delta)
	_update_seen()

	_save_timer += delta
	if _save_timer >= float(settings.get("autosave_seconds", 10)):
		save_game()


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
	return result


func can_buy(building: Dictionary, count: int) -> bool:
	if building_visibility(building) != "known":
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


## Wie viele Einheiten ein Rezept pro Durchgang verarbeitet (= Level des Gebäudes).
func recipe_batch(recipe: Dictionary) -> int:
	return levels[recipe["building"]]


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
	if not can_buy(building, buy_amount):
		return false
	var cost: Dictionary = cost_for(building, buy_amount)
	for id: String in cost:
		amounts[id] -= cost[id]
	levels[building["id"]] += buy_amount
	return true


## Legt fest, welche Vorräte die Leiste oben zeigt (höchstens bar_max).
func set_bar_selected(id: String, selected: bool) -> void:
	if not selected:
		bar_selection.erase(id)
	elif not bar_selection.has(id) and bar_selection.size() < int(settings.get("bar_max", 8)):
		bar_selection.append(id)


func cycle_buy_amount() -> void:
	var options: Array = settings["buy_amounts"]
	var index: int = options.find(float(buy_amount))
	buy_amount = int(options[(index + 1) % options.size()])


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
	recipe_state[recipe["id"]]["auto"] = enabled


func _advance_recipe(recipe: Dictionary, delta: float) -> void:
	var state: Dictionary = recipe_state[recipe["id"]]
	if state["running"]:
		state["progress"] += delta
		if state["progress"] >= float(recipe["seconds"]):
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
	var duration: float = float(recipe["seconds"])
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
			"auto": bool(saved.get("auto", false)),
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

## Zahl für die Anzeige: bis 1 Million ausgeschrieben, darüber als 1.23e9.
func fmt(value: float) -> String:
	if value >= 1_000_000.0:
		var exponent: int = int(floor(log(value) / log(10.0)))
		return "%.2fe%d" % [value / pow(10.0, exponent), exponent]
	return str(int(floor(value)))


## Wie fmt, aber mit Vorzeichen und einer Nachkommastelle bei krummen kleinen
## Werten – für Angaben wie "+0.8/s".
func fmt_signed(value: float) -> String:
	var sign_text: String = "-" if value < 0.0 else "+"
	var magnitude: float = absf(value)
	if magnitude < 100.0 and not is_equal_approx(magnitude, roundf(magnitude)):
		return sign_text + "%.1f" % magnitude
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
	return { "auto": false, "running": false, "progress": 0.0, "batch": 0 }


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
