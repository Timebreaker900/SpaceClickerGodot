extends PanelContainer
## Eine Zeile im Reiter "Produktion". Dieselbe Szene für jedes Rezept aus
## data/recipes.json.

@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %Name
@onready var info_label: Label = %Info
@onready var progress: ProgressBar = %Progress
@onready var start_button: Button = %StartButton
@onready var auto_button: CheckButton = %AutoButton

var recipe: Dictionary


func setup(definition: Dictionary) -> void:
	recipe = definition
	icon.texture = load(recipe["icon"])
	name_label.text = recipe["name"]
	auto_button.button_pressed = Game.recipe_state[recipe["id"]]["auto"]
	start_button.pressed.connect(func() -> void:
		if Game.start_recipe(recipe):
			Ui.pop(icon))
	auto_button.toggled.connect(func(on: bool) -> void: Game.set_recipe_auto(recipe, on))


func _process(_delta: float) -> void:
	if recipe.is_empty():
		return
	var state: Dictionary = Game.recipe_state[recipe["id"]]
	var batch: int = Game.recipe_batch(recipe)
	var unlocked: bool = batch > 0
	visible = unlocked  # Rezepte tauchen erst auf, wenn ihr Gebäude steht
	if not visible:
		return
	icon.modulate.a = 1.0 if unlocked else 0.4
	start_button.disabled = not Game.can_start_recipe(recipe)
	auto_button.disabled = not unlocked
	progress.value = state["progress"] / float(recipe["seconds"]) if state["running"] else 0.0
	if unlocked:
		info_label.text = "%s → %s  (%d s)" % [
			_describe(recipe["input"], batch), _describe(recipe["output"], batch), int(recipe["seconds"])]
	else:
		info_label.text = "Benötigt %s" % Game.building_def(recipe["building"])["name"]


## "4 Kupfererz, 2 Sand" – Mengen mal Durchgangsgröße.
func _describe(items: Dictionary, batch: int) -> String:
	var parts: PackedStringArray = []
	for id: String in items:
		parts.append("%s %s" % [Game.fmt(float(items[id]) * batch), Game.resource_def(id)["name"]])
	return ", ".join(parts)
