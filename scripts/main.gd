extends Control
## Der Hauptbildschirm: zeigt den Zustand aus "Game" an und reicht Eingaben weiter.
## Hier steht keine Spielregel – nur Anzeige.

const BuildingRow := preload("res://scenes/building_row.tscn")

@onready var resource_bar: HFlowContainer = %ResourceBar
@onready var planet: TextureButton = %Planet
@onready var click_coins: Button = %ClickCoins
@onready var click_wood: Button = %ClickWood
@onready var buy_amount_button: Button = %BuyAmountButton
@onready var building_list: VBoxContainer = %BuildingList

var _resource_labels: Dictionary = {}  # Ressourcen-ID -> Label


func _ready() -> void:
	for res: Dictionary in Game.resources:
		_add_resource_chip(res)
	for building: Dictionary in Game.buildings:
		var row: Node = BuildingRow.instantiate()
		building_list.add_child(row)
		row.setup(building)

	planet.pivot_offset = planet.custom_minimum_size / 2.0
	planet.button_down.connect(_on_planet_pressed)
	click_coins.pressed.connect(_set_click_target.bind("coins"))
	click_wood.pressed.connect(_set_click_target.bind("wood"))
	buy_amount_button.pressed.connect(_on_buy_amount_pressed)
	_set_click_target(Game.click_target)


func _process(_delta: float) -> void:
	var rates: Dictionary = Game.get_rates()
	for id: String in _resource_labels:
		var label: Label = _resource_labels[id]
		if Game.resource_def(id)["type"] == "capacity":
			label.text = "%s/%s" % [Game.fmt(Game.capacity_free(id)), Game.fmt(Game.capacity_total(id))]
		else:
			var rate: float = rates.get(id, 0.0)
			label.text = Game.fmt(Game.amounts[id])
			if rate != 0.0:
				label.text += "  %+.0f/s" % rate


func _add_resource_chip(res: Dictionary) -> void:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.texture = load(res["icon"])
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var label := Label.new()
	chip.add_child(icon)
	chip.add_child(label)
	chip.tooltip_text = res["name"]
	resource_bar.add_child(chip)
	_resource_labels[res["id"]] = label


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
