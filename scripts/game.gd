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
## Ein Rezept wandelt in "seconds" Sekunden "input" in "output" um. Es gehört zu
## einem Gebäude; dessen Level bestimmt, wie viel pro Durchgang verarbeitet wird.

const SAVE_VERSION := 1

var save_path: String = "user://save.json"  # Tests biegen das auf eine eigene Datei um.

var resources: Array = []
var buildings: Array = []
var recipes: Array = []
var settings: Dictionary = {}

var amounts: Dictionary = {}       # Ressourcen-ID -> Vorrat
var levels: Dictionary = {}        # Gebäude-ID -> Level
var recipe_state: Dictionary = {}  # Rezept-ID -> { auto, running, progress, batch }
var click_target: String = "coins"
var buy_amount: int = 1

var _resource_by_id: Dictionary = {}
var _building_by_id: Dictionary = {}
var _save_timer: float = 0.0


func _ready() -> void:
	resources = _load_json("res://data/resources.json")
	buildings = _load_json("res://data/buildings.json")
	recipes = _load_json("res://data/recipes.json")
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
	load_game()


func _process(delta: float) -> void:
	var rates: Dictionary = get_rates()
	for id: String in rates:
		amounts[id] = maxf(0.0, amounts[id] + rates[id] * delta)
	for recipe: Dictionary in recipes:
		_advance_recipe(recipe, delta)

	_save_timer += delta
	if _save_timer >= float(settings.get("autosave_seconds", 10)):
		save_game()


func _notification(what: int) -> void:
	# Fenster wird geschlossen bzw. App geht am Handy in den Hintergrund.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


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
		var produces: Dictionary = building.get("produces", {})
		for id: String in produces:
			rates[id] = rates.get(id, 0.0) + float(produces[id]) * level
	return rates


func capacity_total(id: String) -> float:
	return _sum_over_buildings("provides", id)


func capacity_used(id: String) -> float:
	return _sum_over_buildings("reserves", id)


func capacity_free(id: String) -> float:
	return capacity_total(id) - capacity_used(id)


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
	if not is_unlocked(building):
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
	var produces: Dictionary = building.get("produces", {})
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
	var gain: float = float(settings["click"][click_target])
	amounts[click_target] += gain
	return gain


func buy(building: Dictionary) -> bool:
	if not can_buy(building, buy_amount):
		return false
	var cost: Dictionary = cost_for(building, buy_amount)
	for id: String in cost:
		amounts[id] -= cost[id]
	levels[building["id"]] += buy_amount
	return true


func cycle_buy_amount() -> void:
	var options: Array = settings["buy_amounts"]
	var index: int = options.find(float(buy_amount))
	buy_amount = int(options[(index + 1) % options.size()])


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
			var output: Dictionary = recipe["output"]
			for id: String in output:
				amounts[id] += float(output[id]) * int(state["batch"])
			state["running"] = false
			state["progress"] = 0.0
	if state["auto"] and not state["running"]:
		start_recipe(recipe)


# --- Speichern --------------------------------------------------------------

func save_game() -> void:
	_save_timer = 0.0
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"time": Time.get_unix_time_from_system(),
		"amounts": amounts,
		"levels": levels,
		"recipes": recipe_state,
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


func _new_recipe_state() -> Dictionary:
	return { "auto": false, "running": false, "progress": 0.0, "batch": 0 }


func _sum_over_buildings(key: String, id: String) -> float:
	var total: float = 0.0
	for building: Dictionary in buildings:
		var entry: Dictionary = building.get(key, {})
		total += float(entry.get(id, 0.0)) * levels[building["id"]]
	return total


func _load_json(path: String) -> Variant:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data != null, "Datei fehlt oder ist kein gültiges JSON: %s" % path)
	return data
