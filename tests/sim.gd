extends Node
## Balancing-Simulation: ein einfacher Bot spielt das Spiel im Zeitraffer und
## schreibt auf, wann er was erreicht.
##
##   godot_console --headless --path . res://tests/sim.tscn -- --minutes=180 --clicks=3
##
##   --minutes  wie lange gespielt wird (Spielzeit)
##   --clicks   Klicks pro Sekunde (3 = aktiver Spieler, 0.5 = nebenbei)
##
## Der Bot spielt vernünftig, aber nicht perfekt. Die Zeiten sind Richtwerte:
## Sie zeigen, wo es zäh wird und was zu billig ist, nicht die Bestzeit.
## So entscheidet er jede Sekunde:
##   1. Upgrades kaufen, sobald leistbar.
##   2. Fehlt für ein Gebäude nur Bevölkerung oder Strom, das Passende kaufen.
##   3. Neue Gebäude (Level 0) zuerst, sonst das mit dem niedrigsten Level.
##   4. Ist ein neues Gebäude in unter zwei Minuten leistbar, dafür sparen.
##   5. Rezepte starten; Rezept-Upgrades kaufen, wenn danach noch genug für
##      Gebäude übrig bleibt.
## Er benutzt dieselben Regeln wie das Spiel (Autoload "Game") und eine eigene
## Speicherdatei.

var minutes: int = 180
var clicks_per_second: float = 3.0

var _time: float = 0.0
var _click_debt: float = 0.0
var _milestones: Array = []        # [Sekunde, Text]
var _done: Dictionary = {}         # schon gemeldete Meilensteine
var _snapshots: Array = []
var _click_total: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="):
			minutes = int(arg.trim_prefix("--minutes="))
		if arg.begins_with("--clicks="):
			clicks_per_second = float(arg.trim_prefix("--clicks="))
	Options.number_format = "short"
	Game.set_process(false)
	Game.reset_game()

	var snapshot_at: Array = [5, 15, 30, 60, 120, 180, 240, 360]
	for second: int in minutes * 60:
		_time = float(second)
		_click()
		_play()
		Game.advance(1.0)
		_record()
		if second % 60 == 59 and snapshot_at.has((second + 1) / 60):
			_snapshots.append(_snapshot((second + 1) / 60))

	_print_report()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.json"))
	get_tree().quit()


# --- Der Bot ------------------------------------------------------------------

func _click() -> void:
	_click_debt += clicks_per_second
	Game.click_target = _wanted_click_resource()
	while _click_debt >= 1.0:
		_click_debt -= 1.0
		_click_total += 1
		Game.click()


## Geklickt wird, wovon für das aktuelle Ziel am meisten fehlt.
func _wanted_click_resource() -> String:
	var target: Dictionary = _current_target()
	var best: String = "coins"
	var worst_gap: float = 0.0
	if target.is_empty():
		return best
	var cost: Dictionary = Game.cost_for(target, 1)
	for id: String in Game.settings["click"]:
		var gap: float = (float(cost.get(id, 0.0)) - Game.amounts[id]) / Game.click_gain(id)
		if gap > worst_gap:
			worst_gap = gap
			best = id
	return best


func _play() -> void:
	# Rakete: Teile bauen, sobald das Material da ist, und starten.
	for part: Dictionary in Game.rocket["parts"]:
		if Game.build_rocket_part(part):
			_once("Rakete: %s" % part["name"])
	if Game.launch_rocket():
		_once("RAKETE GESTARTET")
	for round_index: int in 40:  # mehrere Käufe pro Sekunde, aber nicht endlos
		if not _buy_something():
			break
	for recipe: Dictionary in Game.recipes:
		if Game.recipe_visible(recipe):
			Game.start_recipe(recipe)
			_buy_recipe_upgrades(recipe)


func _buy_something() -> bool:
	for upgrade: Dictionary in Game.upgrades:
		if Game.can_buy_upgrade(upgrade) and not _needed_for_saving(upgrade.get("cost", {})):
			return Game.buy_upgrade(upgrade)

	# Die Wunschliste von oben nach unten durchgehen: kaufen, was geht; sparen,
	# wenn etwas in unter zwei Minuten leistbar ist; sonst zum nächsten Wunsch.
	# Fehlt einem Wunsch eine Versorgung (etwa Forschung), wird sie für ihn
	# aufgespart: Spätere Wünsche, die dieselbe Versorgung belegen, warten.
	var saved_for_earlier: Dictionary = {}
	for building: Dictionary in _buildings_by_level():
		var reserves: Dictionary = building.get("reserves", {})
		var waits: bool = false
		for capacity_id: String in reserves:
			if saved_for_earlier.has(capacity_id):
				waits = true
			elif Game.capacity_free(capacity_id) < float(reserves[capacity_id]):
				saved_for_earlier[capacity_id] = true
		if waits:
			continue
		var target: Dictionary = _resolve(building)
		if Game.can_buy(target, 1):
			return _buy_building(target)
		if _wait_seconds(target) < 120.0:
			return false
	return false


## Das, worauf der Bot gerade hinarbeitet: der erste Wunsch, der überhaupt
## erreichbar ist (für den also alle Kosten irgendwann hereinkommen).
func _current_target() -> Dictionary:
	var first: Dictionary = {}
	for building: Dictionary in _buildings_by_level():
		var target: Dictionary = _resolve(building)
		if first.is_empty():
			first = target
		if _wait_seconds(target) < INF:
			return target
	return first


## Was für ein Wunschgebäude tatsächlich als Nächstes zu kaufen ist. Meist es
## selbst; fehlt dafür aber Bevölkerung oder Strom, dann das Gebäude, das sie
## liefert; und fehlt dem wiederum die laufende Nahrung, dann das Gebäude, das
## Nahrung herstellt.
func _resolve(goal: Dictionary, depth: int = 0) -> Dictionary:
	var reserves: Dictionary = goal.get("reserves", {})
	for capacity_id: String in reserves:
		if Game.capacity_free(capacity_id) >= float(reserves[capacity_id]):
			continue
		var provider: Dictionary = _best_provider(capacity_id)
		if provider.is_empty():
			continue
		var upkeep: Dictionary = provider.get("produces", {})
		for id: String in upkeep:
			if float(upkeep[id]) < 0.0 and Game.get_rates().get(id, 0.0) + float(upkeep[id]) < 0.0:
				for building: Dictionary in Game.buildings:
					if float(building.get("produces", {}).get(id, 0.0)) > 0.0 and Game.building_visibility(building) == "known":
						return building
		# Der Versorger kann selbst etwas belegen (das Labor braucht Strom und Bevölkerung).
		return _resolve(provider, depth + 1) if depth < 3 else provider
	return goal

## Das bekannte Gebäude, das diese Versorgung am schnellsten liefert.
func _best_provider(capacity_id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_wait: float = INF
	for building: Dictionary in Game.buildings:
		if not building.get("provides", {}).has(capacity_id) or Game.building_visibility(building) != "known":
			continue
		var wait: float = _wait_seconds(building)
		if best.is_empty() or wait < best_wait:
			best = building
			best_wait = wait
	return best

func _buy_building(building: Dictionary) -> bool:
	var before: int = Game.buy_amount
	Game.buy_max = false
	Game.buy_amount = 1
	var bought: bool = Game.buy(building)
	Game.buy_amount = before
	return bought


## Das Gebäude, das der Bot als Nächstes haben will: ein neues, sonst das mit
## dem niedrigsten Level. Fertige und gedeckelte Gebäude fallen heraus.
func _next_building() -> Dictionary:
	var list: Array = _buildings_by_level()
	return list[0] if not list.is_empty() else {}


func _buildings_by_level() -> Array:
	var list: Array = []
	for building: Dictionary in Game.buildings:
		if building.get("placement", "list") != "list" or Game.building_visibility(building) != "known":
			continue
		if Game.is_maxed(building):
			continue
		if building.has("level_cap") and Game.levels[building["id"]] >= Game.levels[building["level_cap"]]:
			continue
		# Reine Versorger (Wassermühle, Solarpanel) kauft der Bot nur bei Bedarf.
		if building.has("provides") and not building.has("produces") and Game.levels[building["id"]] > 0:
			continue
		list.append(building)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Game.levels[a["id"]] < Game.levels[b["id"]])
	return list


## Wie lange es bei der jetzigen Produktion dauert, bis das Gebäude leistbar ist.
func _wait_seconds(building: Dictionary) -> float:
	var rates: Dictionary = Game.get_rates()
	var longest: float = 0.0
	var cost: Dictionary = Game.cost_for(building, 1)
	for id: String in cost:
		var missing: float = float(cost[id]) - Game.amounts[id]
		if missing <= 0.0:
			continue
		var income: float = rates.get(id, 0.0)
		if Game.settings["click"].has(id):
			income += clicks_per_second * Game.click_gain(id) * 0.5
		if income <= 0.0:
			return INF
		longest = maxf(longest, missing / income)
	return longest


## Würde dieser Kauf dem Ziel, auf das gerade gespart wird, etwas wegnehmen?
func _needed_for_saving(cost: Dictionary) -> bool:
	var goal: Dictionary = _current_target()
	if goal.is_empty() or _wait_seconds(goal) > 120.0:
		return false
	var goal_cost: Dictionary = Game.cost_for(goal, 1)
	for id: String in cost:
		if goal_cost.has(id) and Game.amounts[id] - float(cost[id]) < float(goal_cost[id]):
			return true
	return false


## Rezept-Upgrades: erst Auto, dann Sparsam, dann Tempo, dann Menge – aber nur, wenn vom
## Erzeugnis genug übrig bleibt für das, was bekannte Gebäude davon brauchen.
func _buy_recipe_upgrades(recipe: Dictionary) -> void:
	var product: String = recipe["output"].keys()[0]
	var keep: float = 0.0
	for building: Dictionary in Game.buildings:
		if Game.building_visibility(building) == "known" and not Game.is_maxed(building):
			keep = maxf(keep, float(Game.cost_for(building, 1).get(product, 0.0)))
	# Auch für die Raketenteile wird Material zurückgehalten.
	if Game.rocket_available():
		for part: Dictionary in Game.rocket["parts"]:
			if not Game.rocket_built[part["id"]]:
				keep = maxf(keep, float(part["cost"].get(product, 0.0)))
	for kind: String in ["auto", "saver", "speed", "amount"]:
		if not Game.recipe_upgrade_available(recipe, kind):
			continue
		var price: float = Game.recipe_upgrade_cost(recipe, kind)[product]
		if Game.amounts[product] >= price + keep:
			Game.buy_recipe_upgrade(recipe, kind)
		return  # eines nach dem anderen, in dieser Reihenfolge


# --- Aufzeichnung -------------------------------------------------------------

func _record() -> void:
	for building: Dictionary in Game.buildings:
		var level: int = Game.levels[building["id"]]
		if level > 0:
			_once("Gebäude: %s" % building["name"])
		for mark: int in [5, 10, 15, 25, 50]:
			if level >= mark and (building.has("recipes_label") or mark >= 25):
				_once("%s Lv %d" % [building["name"], mark])
	for res: Dictionary in Game.resources:
		if Game.seen[res["id"]] and not Game.settings["click"].has(res["id"]):
			_once("Entdeckt: %s" % res["name"])
	for upgrade: Dictionary in Game.upgrades:
		if Game.bought[upgrade["id"]] and (upgrade["id"].ends_with("_1") or upgrade["id"].begins_with("offline_")):
			_once("Upgrade: %s" % upgrade["name"])
	for recipe: Dictionary in Game.recipes:
		if Game.recipe_state[recipe["id"]]["auto_unlocked"]:
			_once("Auto: %s" % recipe["name"])


func _once(text: String) -> void:
	if not _done.has(text):
		_done[text] = true
		_milestones.append([_time, text])


func _snapshot(minute: int) -> Dictionary:
	var rates: Dictionary = Game.get_rates()
	var total_levels: int = 0
	for building: Dictionary in Game.buildings:
		if building.get("placement", "list") == "list":
			total_levels += Game.levels[building["id"]]
	return {
		"minute": minute,
		"coins": rates.get("coins", 0.0), "wood": rates.get("wood", 0.0),
		"food": rates.get("food", 0.0), "stone": rates.get("stone", 0.0),
		"click": Game.click_gain("coins"),
		"population": Game.capacity_total("population"),
		"electricity": Game.capacity_total("electricity"),
		"levels": total_levels,
	}


func _print_report() -> void:
	print("\n=== Simulation: %d Minuten, %.1f Klicks pro Sekunde (%d Klicks) ===\n" % [minutes, clicks_per_second, _click_total])
	print("MEILENSTEINE")
	for entry: Array in _milestones:
		print("  %7s  %s" % [_clock(entry[0]), entry[1]])

	print("\nNIE ERREICHT")
	var missing: PackedStringArray = []
	for building: Dictionary in Game.buildings:
		if Game.levels[building["id"]] == 0:
			missing.append(building["name"])
	for recipe: Dictionary in Game.recipes:
		if Game.amounts[recipe["output"].keys()[0]] <= 0.0 and not _done.has("Entdeckt: %s" % Game.resource_def(recipe["output"].keys()[0])["name"]):
			missing.append("Rezept " + recipe["name"])
	if not Game.rocket_launched:
		missing.append("Raketenstart (%d von %d Teilen)" % [Game.rocket_parts_built(), Game.rocket_built.size()])
	print("  " + (", ".join(missing) if not missing.is_empty() else "nichts"))

	print("\nVERLAUF (Produktion pro Sekunde)")
	print("  Minute   Coins    Holz  Nahrung   Stein  Klick  Bevölk.  Strom  Gebäude-Level")
	for s: Dictionary in _snapshots:
		print("  %6d %7s %7s %8s %7s %6s %8s %6s %14d" % [s["minute"], Game.fmt(s["coins"]), Game.fmt(s["wood"]),
			Game.fmt(s["food"]), Game.fmt(s["stone"]), Game.fmt(s["click"]), Game.fmt(s["population"]),
			Game.fmt(s["electricity"]), s["levels"]])

	print("\nSTAND AM ENDE")
	for building: Dictionary in Game.buildings:
		if building.get("placement", "list") == "list":
			print("  %-14s Lv %d" % [building["name"], Game.levels[building["id"]]])


## 754 Sekunden -> "12:34"
func _clock(seconds: float) -> String:
	var total: int = int(seconds)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]
