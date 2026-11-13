extends PanelContainer
## Eine Zeile im Reiter "Produktion". Dieselbe Szene für jedes Rezept aus
## data/recipes.json.
##
## Unter dem Rezept stehen seine Upgrades (Schneller, Mehr, Sparsam, Auto). Sie
## werden mit dem bezahlt, was das Rezept herstellt; die Regeln stehen in
## Game.recipe_upgrade_cost().

@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %Name
@onready var info_label: RichTextLabel = %Info
@onready var progress: ProgressBar = %Progress
@onready var start_button: Button = %StartButton
@onready var auto_button: CheckButton = %AutoButton
@onready var upgrade_buttons: Dictionary = {
	"speed": %SpeedButton, "amount": %AmountButton, "saver": %SaverButton, "auto": %AutoUpgradeButton }

const UPGRADE_LABELS: Dictionary = { "speed": "Schneller", "amount": "Mehr", "saver": "Sparsam", "auto": "Auto" }

var recipe: Dictionary
var in_shown_group: bool = true  # vom Hauptbildschirm gesetzt: gehört zur gewählten Gruppe


func setup(definition: Dictionary) -> void:
	recipe = definition
	icon.texture = load(recipe["icon"])
	name_label.text = recipe["name"]
	start_button.pressed.connect(func() -> void:
		if Ui.tap_allowed() and Game.start_recipe(recipe):
			Sfx.play("tap")
			Ui.pop(icon))
	auto_button.toggled.connect(func(on: bool) -> void:
		if Ui.tap_allowed():
			Game.set_recipe_auto(recipe, on))  # sonst stellt _process den Schalter zurück
	# Die Upgrade-Knöpfe zeigen das Icon dessen, womit bezahlt wird.
	var product_icon: Texture2D = load(Game.resource_def(recipe["output"].keys()[0])["icon"])
	for kind: String in upgrade_buttons:
		upgrade_buttons[kind].icon = product_icon
		upgrade_buttons[kind].pressed.connect(_on_upgrade_pressed.bind(kind))


func _process(_delta: float) -> void:
	if recipe.is_empty():
		return
	var state: Dictionary = Game.recipe_state[recipe["id"]]
	var batch: int = Game.recipe_batch(recipe)
	visible = in_shown_group and Game.recipe_visible(recipe)  # erst mit Gebäude und bekannten Zutaten
	if not visible:
		return
	var seconds: float = Game.recipe_seconds(recipe)
	start_button.disabled = not Game.can_start_recipe(recipe)
	progress.value = state["progress"] / seconds if state["running"] else 0.0

	# Der Auto-Schalter erscheint erst, wenn das Auto-Upgrade gekauft ist.
	auto_button.visible = state["auto_unlocked"]
	auto_button.set_pressed_no_signal(state["auto"])

	var info: String = "%s  →  %s    %d s" % [
		_describe(Game.recipe_input(recipe, Game.recipe_input_batch(recipe)), 1, true), _describe(recipe["output"], batch, false), int(seconds)]
	if info_label.text != info:
		info_label.text = info

	for kind: String in upgrade_buttons:
		var button: Button = upgrade_buttons[kind]
		button.visible = Game.recipe_upgrade_available(recipe, kind)
		if button.visible:
			var cost: Dictionary = Game.recipe_upgrade_cost(recipe, kind)
			button.text = "%s%s · %s" % [tr(UPGRADE_LABELS[kind]), _level_text(kind), Game.fmt(cost.values()[0])]
			button.disabled = not Game.can_buy_recipe_upgrade(recipe, kind)


## Stand eines Upgrades für die Beschriftung: " 1/3" bei begrenzten Stufen,
## " 4" bei unbegrenzten, nichts beim einmaligen Auto.
func _level_text(kind: String) -> String:
	if kind == "auto":
		return ""
	var level: int = int(Game.recipe_state[recipe["id"]][kind])
	var maximum: int = Game.recipe_upgrade_max(recipe, kind)
	return " %d/%d" % [level, maximum] if maximum > 0 else " Lv %d" % level


func _on_upgrade_pressed(kind: String) -> void:
	if Ui.tap_allowed() and Game.buy_recipe_upgrade(recipe, kind):
		Sfx.play("upgrade")
		Ui.flash(self)
		Ui.pop(icon)


## Mengen mal Durchgangsgröße, als Zahl mit Icon. Bei den Zutaten wird rot, was fehlt.
func _describe(items: Dictionary, batch: int, check_stock: bool) -> String:
	var parts: PackedStringArray = []
	for id: String in items:
		var needed: float = float(items[id]) * batch
		parts.append(Ui.amount(id, needed, not check_stock or Game.amounts[id] >= needed))
	return "  ".join(parts)
