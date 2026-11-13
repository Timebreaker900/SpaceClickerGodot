extends PanelContainer
## Eine Zeile im Reiter "Upgrades". Dieselbe Szene für jedes Upgrade aus
## data/upgrades.json. Nach dem Kauf verschwindet die Zeile.

@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %Name
@onready var info_label: Label = %Info
@onready var cost_label: RichTextLabel = %Cost
@onready var buy_button: Button = %BuyButton

var upgrade: Dictionary


func setup(definition: Dictionary) -> void:
	upgrade = definition
	icon.texture = load(upgrade["icon"])
	name_label.text = upgrade["name"]
	info_label.text = _describe_effects()
	buy_button.pressed.connect(_on_buy_pressed)


func _process(_delta: float) -> void:
	if upgrade.is_empty():
		return
	var unlocked: bool = Game.upgrade_unlocked(upgrade)
	var affordable: bool = Game.can_buy_upgrade(upgrade)
	buy_button.disabled = not affordable
	var cost_text: String = Ui.cost_line(upgrade.get("cost", {})) if unlocked else _describe_requirements()
	if cost_label.text != cost_text:
		cost_label.text = cost_text
	icon.modulate.a = 1.0 if unlocked else 0.4


func _on_buy_pressed() -> void:
	if Game.buy_upgrade(upgrade):
		queue_free()


## Z. B. "Farm: +1 Nahrung/s je Level" oder "+1 Coins pro Klick".
func _describe_effects() -> String:
	var parts: PackedStringArray = []
	var produces: Dictionary = upgrade.get("add_produces", {})
	for building_id: String in produces:
		for id: String in produces[building_id]:
			parts.append("%s: %s %s/s je Level" % [Game.building_def(building_id)["name"],
				Game.fmt_signed(produces[building_id][id]), Game.resource_def(id)["name"]])
	var provides: Dictionary = upgrade.get("add_provides", {})
	for building_id: String in provides:
		for id: String in provides[building_id]:
			parts.append("%s: %s %s je Level" % [Game.building_def(building_id)["name"],
				Game.fmt_signed(provides[building_id][id]), Game.resource_def(id)["name"]])
	var click: Dictionary = upgrade.get("add_click", {})
	for id: String in click:
		parts.append("%s %s pro Klick" % [Game.fmt_signed(click[id]), Game.resource_def(id)["name"]])
	return ", ".join(parts)


## Z. B. "Ab Farm Lv 10" oder "Ab 100 Klicks für Coins (37)".
func _describe_requirements() -> String:
	var parts: PackedStringArray = []
	var requires: Dictionary = upgrade.get("requires", {})
	for id: String in requires:
		parts.append("%s Lv %d" % [Game.building_def(id)["name"], int(requires[id])])
	var clicks: Dictionary = upgrade.get("requires_clicks", {})
	for id: String in clicks:
		parts.append("%d Klicks für %s (%d)" % [int(clicks[id]), Game.resource_def(id)["name"], Game.click_counts[id]])
	return "Ab " + ", ".join(parts)
