extends VBoxContainer
## Eine Zeile in der Gebäudeliste. Dieselbe Szene wird für jedes Gebäude
## verwendet; welches sie zeigt, bestimmt der Eintrag aus data/buildings.json.
##
## Eine Zeile kann Unterzeilen haben (z. B. der Erzabbau unter der Mine). Die
## hängen eingerückt darunter und lassen sich auf- und zuklappen.

@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %Name
@onready var info_label: Label = %Info
@onready var cost_label: RichTextLabel = %Cost
@onready var buy_button: Button = %BuyButton
@onready var expand_button: Button = %ExpandButton
@onready var sub_margin: MarginContainer = %SubMargin
@onready var sub_list: VBoxContainer = %SubList

var building: Dictionary


func setup(definition: Dictionary) -> void:
	building = definition
	icon.texture = load(building["icon"])
	buy_button.pressed.connect(func() -> void: Game.buy(building))
	expand_button.toggled.connect(_on_expand_toggled)


## Hängt die Zeile eines untergeordneten Gebäudes ein.
func add_sub_row(row: Node) -> void:
	sub_list.add_child(row)
	expand_button.visible = true
	_on_expand_toggled(expand_button.button_pressed)


func _process(_delta: float) -> void:
	if building.is_empty():
		return
	name_label.text = "%s  Lv %d" % [building["name"], Game.levels[building["id"]]]
	info_label.text = _describe_effects()  # jedes Bild neu, weil Upgrades die Werte ändern
	buy_button.text = "+%d" % Game.buy_amount
	buy_button.disabled = not Game.can_buy(building, Game.buy_amount)
	var unlocked: bool = Game.is_unlocked(building)
	var cost_text: String = _describe_cost() if unlocked else _describe_requirements()
	if cost_label.text != cost_text:  # nur bei Änderung setzen, das Einlesen der Icons kostet Zeit
		cost_label.text = cost_text
	icon.modulate.a = 1.0 if unlocked else 0.4


func _on_expand_toggled(open: bool) -> void:
	sub_margin.visible = open
	expand_button.text = "%s (%d) %s" % [
		building.get("children_label", "Mehr"), sub_list.get_child_count(), "▲" if open else "▼"]


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
## Rot wird nur der Posten, an dem es gerade scheitert.
func _describe_cost() -> String:
	var text: String = Ui.cost_line(Game.cost_for(building, Game.buy_amount))
	var reserves: Dictionary = building.get("reserves", {})
	for id: String in reserves:
		var needed: float = float(reserves[id]) * Game.buy_amount
		text += "   " + Ui.amount(id, needed, Game.capacity_free(id) >= needed, "belegt ")
	return text


## Text für gesperrte Gebäude, z. B. "Ab Mine Lv 5".
func _describe_requirements() -> String:
	var parts: PackedStringArray = []
	var requires: Dictionary = building.get("requires", {})
	for id: String in requires:
		parts.append("%s Lv %d" % [Game.building_def(id)["name"], int(requires[id])])
	return "Ab " + ", ".join(parts)
