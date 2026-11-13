extends VBoxContainer
## Eine Zeile in der Gebäudeliste. Dieselbe Szene wird für jedes Gebäude
## verwendet; welches sie zeigt, bestimmt der Eintrag aus data/buildings.json.
##
## Eine Zeile kann Unterzeilen haben (z. B. der Erzabbau unter der Mine). Die
## hängen eingerückt darunter und lassen sich auf- und zuklappen.
##
## Ob die Zeile normal, als Rätsel ("???") oder gar nicht erscheint, bestimmt
## Game.building_visibility().

@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %Name
@onready var info_label: Label = %Info
@onready var cost_label: RichTextLabel = %Cost
@onready var buy_button: Button = %BuyButton
@onready var expand_button: Button = %ExpandButton
@onready var sub_margin: MarginContainer = %SubMargin
@onready var sub_list: VBoxContainer = %SubList

var building: Dictionary
var _last_state: String = ""   # Zustand im vorigen Bild, um Wechsel zu bemerken
var _reveal_until: float = 0.0  # solange läuft die Aufdeck-Animation des Icons


func setup(definition: Dictionary) -> void:
	building = definition
	icon.texture = load(building["icon"])
	buy_button.pressed.connect(_on_buy_pressed)
	expand_button.toggled.connect(_on_expand_toggled)


func _on_buy_pressed() -> void:
	if Game.buy(building):
		Sfx.play("buy")
		Ui.flash($Panel)
		Ui.pop(icon)
		Ui.pop(name_label, 1.08)


## Hängt die Zeile eines untergeordneten Gebäudes ein.
func add_sub_row(row: Node) -> void:
	sub_list.add_child(row)
	_on_expand_toggled(expand_button.button_pressed)


func _process(_delta: float) -> void:
	if building.is_empty():
		return
	var state: String = Game.building_visibility(building)
	visible = state != "hidden"
	var previous_state: String = _last_state
	_last_state = state
	if not visible:
		return
	var known: bool = state == "known"
	var now: float = Time.get_ticks_msec() / 1000.0
	# Wechsel bemerken. Beim allerersten Bild (previous_state leer) passiert nichts,
	# damit beim Spielstart nicht alles auf einmal aufblitzt.
	if previous_state == "mystery" and known:
		_reveal_until = now + 0.6
		Sfx.play("reveal")
		Ui.reveal($Panel, icon)
		Game.announcement.emit(building["icon"], "Neu: %s" % building["name"])
	elif previous_state == "hidden":
		Ui.fade_in(self)
	# Als Rätsel bleibt vom Icon nur der schwarze Umriss.
	if now >= _reveal_until:
		icon.modulate = Color.WHITE if known else Color(0, 0, 0, 0.75)
	info_label.visible = known
	expand_button.visible = known and sub_list.get_child_count() > 0
	sub_margin.visible = expand_button.visible and expand_button.button_pressed
	var count: int = Game.buy_count(building)
	buy_button.disabled = not Game.can_buy(building, count)
	buy_button.text = "+%d" % count if known else "?"

	var cost_text: String
	if known:
		name_label.text = "%s  Lv %d" % [building["name"], Game.levels[building["id"]]]
		info_label.text = _describe_effects()  # jedes Bild neu, weil Upgrades die Werte ändern
		cost_text = _describe_cost()
	else:
		name_label.text = "???"
		cost_text = _describe_hint()
	if cost_label.text != cost_text:  # nur bei Änderung setzen, das Einlesen der Icons kostet Zeit
		cost_label.text = cost_text


func _on_expand_toggled(open: bool) -> void:
	sub_margin.visible = open
	expand_button.text = "%s %s" % [building.get("children_label", "Mehr"), "▲" if open else "▼"]


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
	var count: int = Game.buy_count(building)
	var text: String = Ui.cost_line(Game.cost_for(building, count))
	var reserves: Dictionary = building.get("reserves", {})
	for id: String in reserves:
		var needed: float = float(reserves[id]) * count
		text += "   " + Ui.amount(id, needed, Game.capacity_free(id) >= needed, "belegt ")
	# Darf dieses Gebäude ein anderes nicht überholen, steht die Grenze dabei –
	# rot, sobald sie erreicht ist.
	if building.has("level_cap"):
		var cap: Dictionary = Game.building_def(building["level_cap"])
		var limit: int = Game.levels[cap["id"]]
		var note: String = "höchstens %s-Level (%d)" % [cap["name"], limit]
		if Game.levels[building["id"]] + count > limit:
			note = "[color=#%s]%s[/color]" % [Ui.MISSING_COLOR, note]
		text += "   " + note
	return text


## Was fehlt, damit das Rätsel gelüftet wird: zuerst der Vorgänger, dann die
## eigenen Voraussetzungen.
func _describe_hint() -> String:
	var previous: Dictionary = Game.previous_building(building)
	if not previous.is_empty() and Game.levels[previous["id"]] == 0:
		return "Kaufe zuerst: %s" % previous["name"]
	var parts: PackedStringArray = []
	var requires: Dictionary = building.get("requires", {})
	for id: String in requires:
		parts.append("%s Lv %d" % [Game.building_def(id)["name"], int(requires[id])])
	return "Ab " + ", ".join(parts)
