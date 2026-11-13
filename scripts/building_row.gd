extends PanelContainer
## Eine Zeile in der Gebäudeliste. Dieselbe Szene wird für jedes Gebäude
## verwendet; welches sie zeigt, bestimmt der Eintrag aus data/buildings.json.

@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %Name
@onready var info_label: Label = %Info
@onready var cost_label: Label = %Cost
@onready var buy_button: Button = %BuyButton

var building: Dictionary


func setup(definition: Dictionary) -> void:
	building = definition
	icon.texture = load(building["icon"])
	buy_button.pressed.connect(func() -> void: Game.buy(building))


func _process(_delta: float) -> void:
	if building.is_empty():
		return
	name_label.text = "%s  Lv %d" % [building["name"], Game.levels[building["id"]]]
	info_label.text = _describe_effects()  # jedes Bild neu, weil Upgrades die Werte ändern
	buy_button.text = "+%d" % Game.buy_amount
	var affordable: bool = Game.can_buy(building, Game.buy_amount)
	buy_button.disabled = not affordable
	var unlocked: bool = Game.is_unlocked(building)
	cost_label.text = _describe_cost() if unlocked else _describe_requirements()
	# Kosten rötlich, solange es nicht reicht.
	cost_label.modulate = Color.WHITE if affordable else Color(1.0, 0.62, 0.62)
	icon.modulate.a = 1.0 if unlocked else 0.4


## Was ein Level bringt, z. B. "+1 Nahrung/s" oder "+1 Strom".
func _describe_effects() -> String:
	var parts: PackedStringArray = []
	var produces: Dictionary = Game.building_output(building, "produces")
	for id: String in produces:
		parts.append("%s %s/s" % [Game.fmt_signed(produces[id]), Game.resource_def(id)["name"]])
	var provides: Dictionary = Game.building_output(building, "provides")
	for id: String in provides:
		parts.append("%s %s" % [Game.fmt_signed(provides[id]), Game.resource_def(id)["name"]])
	if building.has("note"):
		parts.append(building["note"])
	return ", ".join(parts)


## Kaufpreis für die gewählte Menge plus das, was dauerhaft belegt wird.
func _describe_cost() -> String:
	var parts: PackedStringArray = []
	var cost: Dictionary = Game.cost_for(building, Game.buy_amount)
	for id: String in cost:
		parts.append("%s %s" % [Game.fmt(cost[id]), Game.resource_def(id)["name"]])
	var reserves: Dictionary = building.get("reserves", {})
	for id: String in reserves:
		var needed: float = float(reserves[id]) * Game.buy_amount
		parts.append("belegt %s %s" % [Game.fmt(needed), Game.resource_def(id)["name"]])
	return ", ".join(parts)


## Text für gesperrte Gebäude, z. B. "Ab Mine Lv 5".
func _describe_requirements() -> String:
	var parts: PackedStringArray = []
	var requires: Dictionary = building.get("requires", {})
	for id: String in requires:
		parts.append("%s Lv %d" % [Game.building_def(id)["name"], int(requires[id])])
	return "Ab " + ", ".join(parts)
