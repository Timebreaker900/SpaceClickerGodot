extends PanelContainer
## Eine Zeile im Reiter "Upgrades". Dieselbe Szene für jedes Upgrade aus
## data/upgrades.json. Nach dem Kauf verschwindet die Zeile.
##
## Ob die Zeile normal, als Rätsel ("???") oder gar nicht erscheint, bestimmt
## Game.upgrade_visibility().

@onready var icon: TextureRect = %Icon
@onready var badge: TextureRect = %Badge
@onready var name_label: Label = %Name
@onready var info_label: Label = %Info
@onready var cost_label: RichTextLabel = %Cost
@onready var buy_button: Button = %BuyButton

var upgrade: Dictionary
var _leaving: bool = false  # gekauft, die Zeile blendet gerade aus
var _last_state: String = ""
var _reveal_until: float = 0.0


func setup(definition: Dictionary) -> void:
	upgrade = definition
	icon.texture = load(upgrade["icon"])
	info_label.text = _describe_effects()
	buy_button.pressed.connect(_on_buy_pressed)


func _process(_delta: float) -> void:
	if upgrade.is_empty() or _leaving:
		return
	var state: String = Game.upgrade_visibility(upgrade)
	visible = state != "hidden"
	var previous_state: String = _last_state
	_last_state = state
	if not visible:
		return
	var known: bool = state == "known"
	var now: float = Time.get_ticks_msec() / 1000.0
	if previous_state == "mystery" and known:
		_reveal_until = now + 0.6
		Sfx.play("discover")
		Ui.reveal(self, icon, true)
	elif previous_state == "hidden":
		Ui.fade_in(self)
	if now >= _reveal_until:
		icon.self_modulate = Color.WHITE if known else Color(0, 0, 0, 0.75)  # nur das Icon, nicht das Abzeichen
	badge.visible = known
	info_label.visible = known
	name_label.text = upgrade["name"] if known else "???"
	buy_button.text = "Kaufen" if known else "?"
	buy_button.disabled = not Game.can_buy_upgrade(upgrade)
	var cost_text: String = Ui.cost_line(upgrade.get("cost", {})) if known else _describe_requirements()
	if cost_label.text != cost_text:
		cost_label.text = cost_text


func _on_buy_pressed() -> void:
	if not Game.buy_upgrade(upgrade):
		return
	# Aufblitzen, kurz stehen lassen, dann ausblenden und entfernen.
	_leaving = true
	Sfx.play("upgrade")
	buy_button.disabled = true
	Ui.flash(self)
	Ui.pop(icon)
	var tween: Tween = create_tween()
	tween.tween_interval(0.25)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)


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
	if upgrade.has("add_offline_hours"):
		parts.append("Abwesenheit: +%d Std anrechenbar" % int(upgrade["add_offline_hours"]))
	if upgrade.has("add_offline_percent"):
		parts.append("Abwesenheit: +%d %% Ertrag" % int(upgrade["add_offline_percent"]))
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
