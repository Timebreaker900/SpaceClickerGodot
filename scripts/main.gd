extends Control
## Der Hauptbildschirm: zeigt den Zustand aus "Game" an und reicht Eingaben weiter.
## Hier steht keine Spielregel – nur Anzeige.

const BuildingRow := preload("res://scenes/building_row.tscn")
const RecipeRow := preload("res://scenes/recipe_row.tscn")

@onready var resource_bar: HFlowContainer = %ResourceBar
@onready var planet: TextureButton = %Planet
@onready var click_coins: Button = %ClickCoins
@onready var click_wood: Button = %ClickWood
@onready var buy_amount_button: Button = %BuyAmountButton
@onready var building_list: VBoxContainer = %BuildingList
@onready var recipe_list: VBoxContainer = %RecipeList
@onready var resource_list: VBoxContainer = %ResourceList

var _bar_labels: Dictionary = {}   # Ressourcen-ID -> Label in der Leiste oben
var _list_labels: Dictionary = {}  # Ressourcen-ID -> Label im Reiter "Ressourcen"


func _ready() -> void:
	var current_group: String = ""
	for res: Dictionary in Game.resources:
		if res.get("bar", false):
			_bar_labels[res["id"]] = _add_resource_entry(resource_bar, res, 56, false)
		if res.get("group", "") != current_group:
			current_group = res.get("group", "")
			_add_group_heading(current_group)
		_list_labels[res["id"]] = _add_resource_entry(resource_list, res, 64, true)

	for building: Dictionary in Game.buildings:
		var row: Node = BuildingRow.instantiate()
		building_list.add_child(row)
		row.setup(building)
	for recipe: Dictionary in Game.recipes:
		var row: Node = RecipeRow.instantiate()
		recipe_list.add_child(row)
		row.setup(recipe)

	planet.pivot_offset = planet.custom_minimum_size / 2.0
	planet.button_down.connect(_on_planet_pressed)
	click_coins.pressed.connect(_set_click_target.bind("coins"))
	click_wood.pressed.connect(_set_click_target.bind("wood"))
	buy_amount_button.pressed.connect(_on_buy_amount_pressed)
	_set_click_target(Game.click_target)


func _process(_delta: float) -> void:
	var rates: Dictionary = Game.get_rates()
	for id: String in _bar_labels:
		_bar_labels[id].text = _resource_text(id, rates)
	for id: String in _list_labels:
		_list_labels[id].text = _resource_text(id, rates)


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
	heading.add_theme_font_size_override("font_size", 40)
	heading.add_theme_color_override("font_color", Color(0.72, 0.85, 1.0))
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
	_spawn_click_text("+" + Game.fmt(gain))


func _spawn_click_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 48)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.global_position = get_global_mouse_position() + Vector2(randf_range(-40, 40), -60)
	var tween: Tween = label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 140, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)
