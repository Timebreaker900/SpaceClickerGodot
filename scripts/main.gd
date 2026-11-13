extends Control
## Der Hauptbildschirm: zeigt den Zustand aus "Game" an und reicht Eingaben weiter.
## Hier steht keine Spielregel – nur Anzeige.

const BuildingRow := preload("res://scenes/building_row.tscn")
const RecipeRow := preload("res://scenes/recipe_row.tscn")
const UpgradeRow := preload("res://scenes/upgrade_row.tscn")
const GAME_VERSION := "0.1"

@onready var resource_bar: HFlowContainer = %ResourceBar
@onready var bar_divider: ColorRect = %BarDivider
@onready var capacity_bar: HBoxContainer = %CapacityBar
@onready var settings_button: Button = %SettingsButton
@onready var resources_button: Button = %ResourcesButton
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
@onready var popup: Control = %Popup
@onready var offline_popup: Control = %OfflinePopup
@onready var offline_time: Label = %OfflineTime
@onready var offline_gains: RichTextLabel = %OfflineGains
@onready var offline_close: Button = %OfflineClose

# Je Ressource die Einträge in der Leiste oben und im Reiter "Ressourcen".
# Ein Eintrag ist { "node": die ganze Zeile, "label": das Label mit der Zahl }.
var _bar_entries: Dictionary = {}
var _list_entries: Dictionary = {}
var _group_headings: Dictionary = {}  # Gruppenname -> Überschrift im Reiter
var _planet_building: Dictionary      # Gebäude mit eigenem Knopf beim Planeten (Bevölkerung)


func _ready() -> void:
	for res: Dictionary in Game.resources:
		# Leiste: Vorräte fließen oben, Versorgung (Bevölkerung, Strom) steht
		# in einer eigenen Zeile darunter.
		var bar_parent: Container = capacity_bar if res["type"] == "capacity" else resource_bar
		_bar_entries[res["id"]] = _add_resource_entry(bar_parent, res, 52, false)
		var group: String = res.get("group", "")
		if not _group_headings.has(group):
			_group_headings[group] = _add_group_heading(group)
		_list_entries[res["id"]] = _add_resource_entry(resource_list, res, 64, true)

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
	settings_button.pressed.connect(_open_settings)
	resources_button.pressed.connect(_open_bar_picker)
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
	_update_resource_views(rates)
	_update_population_button(rates)

	# Der Reiter "Produktion" erscheint erst, wenn es ein Rezept gibt.
	var any_recipe: bool = false
	for recipe: Dictionary in Game.recipes:
		any_recipe = any_recipe or Game.recipe_batch(recipe) > 0
	tabs.set_tab_hidden(recipe_list.get_parent().get_index(), not any_recipe)

	# Der Reiter zeigt, wie viele Upgrades gerade kaufbar sind.
	var buyable: int = 0
	for upgrade: Dictionary in Game.upgrades:
		if Game.can_buy_upgrade(upgrade):
			buyable += 1
	tabs.set_tab_title(upgrade_list.get_parent().get_index(), "Upgrades (%d)" % buyable if buyable > 0 else "Upgrades")


## Leiste und Ressourcen-Reiter zeigen nur, was der Spieler schon einmal hatte.
## Die Leiste zeigt bloß den Stand; die Rate pro Sekunde steht im Reiter.
func _update_resource_views(rates: Dictionary) -> void:
	var groups_seen: Dictionary = {}
	var any_capacity: bool = false
	for res: Dictionary in Game.resources:
		var id: String = res["id"]
		var seen: bool = Game.seen[id]
		var is_capacity: bool = res["type"] == "capacity"
		var bar_entry: Dictionary = _bar_entries[id]
		bar_entry["node"].visible = seen and (is_capacity or Game.bar_selection.has(id))
		bar_entry["label"].text = _resource_text(id, rates, false)
		var list_entry: Dictionary = _list_entries[id]
		list_entry["node"].visible = seen
		list_entry["label"].text = _resource_text(id, rates, true)
		if seen:
			groups_seen[res.get("group", "")] = true
			any_capacity = any_capacity or is_capacity
	for group: String in _group_headings:
		_group_headings[group].visible = groups_seen.has(group)
	bar_divider.visible = any_capacity
	capacity_bar.visible = any_capacity


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


## Vorräte: der Stand, auf Wunsch mit Rate ("1234  +2/s").
## Versorgung: "frei / gesamt".
func _resource_text(id: String, rates: Dictionary, with_rate: bool) -> String:
	if Game.resource_def(id)["type"] == "capacity":
		return "%s / %s" % [Game.fmt(Game.capacity_free(id)), Game.fmt(Game.capacity_total(id))]
	var text: String = Game.fmt(Game.amounts[id])
	var rate: float = rates.get(id, 0.0)
	if with_rate and rate != 0.0:
		text += "  %s/s" % Game.fmt_signed(rate)
	return text


## Legt Icon + Zahl an und gibt die Zeile samt Zahlen-Label zurück.
func _add_resource_entry(parent: Container, res: Dictionary, icon_size: int, with_name: bool) -> Dictionary:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 12)
	entry.add_child(_icon(res["icon"], icon_size))
	if with_name:
		var name_label := Label.new()
		name_label.text = res["name"]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_child(name_label)
	var value_label := Label.new()
	entry.add_child(value_label)
	parent.add_child(entry)
	return { "node": entry, "label": value_label }


func _icon(path: String, icon_size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(path)
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _add_group_heading(title: String) -> Label:
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"HeadingLabel"
	heading.add_theme_font_size_override("font_size", 38)
	heading.add_theme_color_override("font_color", Color(0.25, 0.82, 1.0))
	resource_list.add_child(heading)
	return heading


# --- Fenster ------------------------------------------------------------------

## Auswahl, welche Vorräte die Leiste oben zeigt. Zur Wahl steht nur, was der
## Spieler schon entdeckt hat; die Obergrenze kommt aus data/settings.json.
func _open_bar_picker() -> void:
	popup.open("Leiste anpassen", 760)
	var limit: int = int(Game.settings.get("bar_max", 8))
	var counter := Label.new()
	counter.add_theme_color_override("font_color", Color(0.25, 0.82, 1.0))
	popup.content.add_child(counter)
	var boxes: Dictionary = {}  # Ressourcen-ID -> Schalter
	var refresh := func() -> void:
		counter.text = "%d von höchstens %d Vorräten gewählt. Bevölkerung und Strom sind immer zu sehen." % [
			Game.bar_selection.size(), limit]
		for id: String in boxes:
			# Ist die Grenze erreicht, lassen sich nur noch gewählte abwählen.
			boxes[id].disabled = Game.bar_selection.size() >= limit and not boxes[id].button_pressed
	counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for res: Dictionary in Game.resources:
		if res["type"] != "stock" or not Game.seen[res["id"]]:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.add_child(_icon(res["icon"], 64))
		var box := CheckButton.new()
		box.text = res["name"]
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.button_pressed = Game.bar_selection.has(res["id"])
		box.toggled.connect(func(on: bool) -> void:
			Game.set_bar_selected(res["id"], on)
			refresh.call())
		row.add_child(box)
		popup.content.add_child(row)
		boxes[res["id"]] = box
	refresh.call()


func _open_settings() -> void:
	popup.open("Einstellungen", 420)
	var version := Label.new()
	version.text = "Space Clicker – Version %s" % GAME_VERSION
	version.add_theme_color_override("font_color", Color(0.56, 0.70, 0.84))
	popup.content.add_child(version)

	var hint := Label.new()
	hint.text = "Der Spielstand wird alle 10 Sekunden und beim Schließen gespeichert."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup.content.add_child(hint)

	# Zurücksetzen braucht zwei Klicks, damit es nicht aus Versehen passiert.
	var reset := Button.new()
	reset.text = "Spielstand zurücksetzen"
	reset.custom_minimum_size.y = 96
	var armed := [false]
	reset.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			reset.text = "Wirklich alles löschen? Nochmal tippen"
			return
		Game.reset_game()
		get_tree().reload_current_scene())
	popup.content.add_child(reset)


func _show_offline_report(report: Dictionary) -> void:
	offline_time.text = "Du warst %s weg." % _duration_text(report["seconds"])
	offline_time.text += " Angerechnet: %s zu %d %%." % [_duration_text(report["counted"]), int(report["percent"])]
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


# --- Eingaben -----------------------------------------------------------------

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
	var effect: TextureRect = _icon(Game.resource_def(resource_id)["icon"], 84)
	effect.size = Vector2(84, 84)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effect)
	move_child(effect, popup.get_index())  # unter den Fenstern bleiben
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
