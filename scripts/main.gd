extends Control
## Der Hauptbildschirm: zeigt den Zustand aus "Game" an und reicht Eingaben weiter.
## Hier steht keine Spielregel – nur Anzeige.

const BuildingRow := preload("res://scenes/building_row.tscn")
const RecipeRow := preload("res://scenes/recipe_row.tscn")
const UpgradeRow := preload("res://scenes/upgrade_row.tscn")

@onready var resource_bar: HFlowContainer = %ResourceBar
@onready var planet: TextureButton = %Planet
@onready var click_coins: Button = %ClickCoins
@onready var click_wood: Button = %ClickWood
@onready var pop_cost: RichTextLabel = %PopCost
@onready var pop_button: Button = %PopButton
@onready var buy_amount_button: Button = %BuyAmountButton
@onready var building_list: VBoxContainer = %BuildingList
@onready var recipe_list: VBoxContainer = %RecipeList
@onready var upgrade_list: VBoxContainer = %UpgradeList
@onready var resource_list: VBoxContainer = %ResourceList
@onready var tabs: TabContainer = %Tabs
@onready var offline_popup: Control = %OfflinePopup
@onready var offline_time: Label = %OfflineTime
@onready var offline_gains: RichTextLabel = %OfflineGains
@onready var offline_close: Button = %OfflineClose

var _bar_labels: Dictionary = {}   # Ressourcen-ID -> Label in der Leiste oben
var _list_labels: Dictionary = {}  # Ressourcen-ID -> Label im Reiter "Ressourcen"
var _planet_building: Dictionary   # Gebäude mit eigenem Knopf beim Planeten (Bevölkerung)


func _ready() -> void:
	var current_group: String = ""
	for res: Dictionary in Game.resources:
		if res.get("bar", false):
			_bar_labels[res["id"]] = _add_resource_entry(resource_bar, res, 56, false)
		if res.get("group", "") != current_group:
			current_group = res.get("group", "")
			_add_group_heading(current_group)
		_list_labels[res["id"]] = _add_resource_entry(resource_list, res, 64, true)

	_build_building_rows()
	for recipe: Dictionary in Game.recipes:
		var row: Node = RecipeRow.instantiate()
		recipe_list.add_child(row)
		row.setup(recipe)
	for upgrade: Dictionary in Game.upgrades:
		if Game.bought[upgrade["id"]]:
			continue  # Gekaufte Upgrades tauchen nicht mehr auf.
		var row: Node = UpgradeRow.instantiate()
		upgrade_list.add_child(row)
		row.setup(upgrade)

	planet.pivot_offset = planet.custom_minimum_size / 2.0
	planet.button_down.connect(_on_planet_pressed)
	click_coins.pressed.connect(_set_click_target.bind("coins"))
	click_wood.pressed.connect(_set_click_target.bind("wood"))
	pop_button.pressed.connect(func() -> void: Game.buy(_planet_building))
	buy_amount_button.pressed.connect(_on_buy_amount_pressed)
	_set_click_target(Game.click_target)

	# Abwesenheit: beim Start steht der Bericht schon bereit, bei der Rückkehr in
	# die App (Handy) kommt er über das Signal.
	offline_close.pressed.connect(func() -> void: offline_popup.visible = false)
	Game.offline_applied.connect(_show_offline_report)
	if not Game.offline_report.is_empty():
		_show_offline_report(Game.offline_report)


## Legt die Gebäudezeilen an. Drei Fälle, gesteuert über data/buildings.json:
##   "placement": "planet" -> keine Zeile, sondern der Knopf beim Planeten
##   "parent": "mine"      -> Unterzeile im aufklappbaren Menü der Mine
##   sonst                 -> normale Zeile in der Liste
func _build_building_rows() -> void:
	var rows: Dictionary = {}  # Gebäude-ID -> Zeile
	for building: Dictionary in Game.buildings:
		if building.get("placement", "list") == "planet":
			_planet_building = building
			continue
		var row: Node = BuildingRow.instantiate()
		if building.has("parent"):
			rows[building["parent"]].add_sub_row(row)
		else:
			building_list.add_child(row)
		row.setup(building)
		rows[building["id"]] = row


func _process(_delta: float) -> void:
	var rates: Dictionary = Game.get_rates()
	for id: String in _bar_labels:
		_bar_labels[id].text = _resource_text(id, rates)
	for id: String in _list_labels:
		_list_labels[id].text = _resource_text(id, rates)
	_update_population_button(rates)

	# Der Reiter zeigt, wie viele Upgrades gerade kaufbar sind.
	var buyable: int = 0
	for upgrade: Dictionary in Game.upgrades:
		if Game.can_buy_upgrade(upgrade):
			buyable += 1
	tabs.set_tab_title(upgrade_list.get_parent().get_index(), "Upgrades (%d)" % buyable if buyable > 0 else "Upgrades")


## Der Bevölkerungs-Knopf: einmaliger Preis plus laufender Verbrauch, jeder
## Posten einzeln rot, wenn es daran scheitert.
func _update_population_button(rates: Dictionary) -> void:
	if _planet_building.is_empty():
		return
	var count: int = Game.buy_amount
	var text: String = Ui.cost_line(Game.cost_for(_planet_building, count))
	var upkeep: Dictionary = Game.building_output(_planet_building, "produces")
	for id: String in upkeep:
		var per_second: float = -float(upkeep[id]) * count
		if per_second > 0.0:
			text += "   " + Ui.amount(id, per_second, rates.get(id, 0.0) >= per_second, "", "/s")
	if pop_cost.text != text:
		pop_cost.text = text
	pop_button.text = "+%d" % count
	pop_button.disabled = not Game.can_buy(_planet_building, count)


func _show_offline_report(report: Dictionary) -> void:
	offline_time.text = "Du warst %s weg." % _duration_text(report["seconds"])
	if report["counted"] < report["seconds"]:
		offline_time.text += " Angerechnet werden höchstens %s." % _duration_text(report["counted"])
	var lines: PackedStringArray = []
	var gains: Dictionary = report["gains"]
	for res: Dictionary in Game.resources:  # Reihenfolge wie in der Ressourcenliste
		if gains.has(res["id"]):
			lines.append("[img=48x48]%s[/img]  +%s %s" % [res["icon"], Game.fmt(gains[res["id"]]), res["name"]])
	offline_gains.text = "\n".join(lines)
	offline_popup.visible = true


## "45 Sek", "12 Min", "3 Std 20 Min"
func _duration_text(seconds: float) -> String:
	var total: int = int(seconds)
	if total < 60:
		return "%d Sek" % total
	if total < 3600:
		return "%d Min" % (total / 60)
	var minutes: int = (total % 3600) / 60
	return "%d Std" % (total / 3600) if minutes == 0 else "%d Std %d Min" % [total / 3600, minutes]


## "1234  +2/s" für Vorräte, "frei/gesamt" für Bevölkerung und Strom.
func _resource_text(id: String, rates: Dictionary) -> String:
	if Game.resource_def(id)["type"] == "capacity":
		return "%s/%s" % [Game.fmt(Game.capacity_free(id)), Game.fmt(Game.capacity_total(id))]
	var text: String = Game.fmt(Game.amounts[id])
	var rate: float = rates.get(id, 0.0)
	if rate != 0.0:
		text += "  %s/s" % Game.fmt_signed(rate)
	return text


## Legt Icon + Zahl an und gibt das Label mit der Zahl zurück.
func _add_resource_entry(parent: Container, res: Dictionary, icon_size: int, with_name: bool) -> Label:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.texture = load(res["icon"])
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	entry.add_child(icon)
	if with_name:
		var name_label := Label.new()
		name_label.text = res["name"]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_child(name_label)
	var value_label := Label.new()
	entry.add_child(value_label)
	parent.add_child(entry)
	return value_label


func _add_group_heading(title: String) -> void:
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"HeadingLabel"
	heading.add_theme_font_size_override("font_size", 38)
	heading.add_theme_color_override("font_color", Color(0.25, 0.82, 1.0))
	resource_list.add_child(heading)


func _set_click_target(id: String) -> void:
	Game.click_target = id
	click_coins.button_pressed = id == "coins"
	click_wood.button_pressed = id == "wood"


func _on_buy_amount_pressed() -> void:
	Game.cycle_buy_amount()
	buy_amount_button.text = "Kaufen: %d" % Game.buy_amount


func _on_planet_pressed() -> void:
	var gain: float = Game.click()
	# Kurzes "Eindrücken" des Planeten.
	var tween: Tween = create_tween()
	tween.tween_property(planet, "scale", Vector2(0.94, 0.94), 0.05)
	tween.tween_property(planet, "scale", Vector2.ONE, 0.08)
	_spawn_click_effect(Game.click_target, gain)


## Das geklickte Icon springt kurz hoch und fliegt dann im Bogen zur Seite weg,
## wie im alten Spiel. Die Bahn ist eine Wurfparabel: seitlich gleichmäßig,
## nach unten immer schneller.
func _spawn_click_effect(resource_id: String, gain: float) -> void:
	var effect := TextureRect.new()
	effect.texture = load(Game.resource_def(resource_id)["icon"])
	effect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	effect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	effect.size = Vector2(84, 84)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effect)
	if gain > 1.0:
		var label := Label.new()
		label.text = "+" + Game.fmt(gain)
		label.position = Vector2(88, 16)
		effect.add_child(label)

	var start: Vector2 = get_local_mouse_position() - effect.size / 2.0
	var direction: float = -1.0 if randf() < 0.5 else 1.0
	var distance: float = randf_range(200.0, 300.0)
	var fly := func(t: float) -> void:
		effect.position = start + Vector2(direction * distance * t, 422.0 * t * t - 169.0 * t)
		effect.modulate.a = clampf(2.0 - 2.0 * t, 0.0, 1.0)  # zweite Hälfte ausblenden
	var tween: Tween = effect.create_tween()
	tween.tween_method(fly, 0.0, 1.0, 0.45)
	tween.tween_callback(effect.queue_free)
