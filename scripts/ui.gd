class_name Ui
## Kleine Helfer für die Anzeige, die mehrere Zeilen-Szenen gemeinsam nutzen.

const MISSING_COLOR := "ff8f8f"  # Rot für das, was noch fehlt
const ICON_SIZE := 34


## Ein Betrag mit Icon für RichTextLabel, z. B. "250 🍎". Ist "enough" falsch,
## wird genau dieser Teil rot – der Rest der Zeile bleibt weiß.
static func amount(id: String, value: float, enough: bool, prefix: String = "", suffix: String = "") -> String:
	var icon: String = Game.resource_def(id)["icon"]
	var text: String = "%s%s [img=%dx%d]%s[/img]%s" % [prefix, Game.fmt(value), ICON_SIZE, ICON_SIZE, icon, suffix]
	if not enough:
		text = "[color=#%s]%s[/color]" % [MISSING_COLOR, text]
	return text


## Kaufpreis als Zeile; jeder Posten wird einzeln geprüft.
static func cost_line(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id: String in cost:
		parts.append(amount(id, cost[id], Game.amounts[id] >= float(cost[id])))
	return "   ".join(parts)


## Lässt eine Fläche kurz hell aufblitzen und wieder abklingen – die Bestätigung,
## dass ein Kauf geklappt hat. self_modulate färbt nur die Fläche selbst, nicht
## den Inhalt darauf.
static func flash(panel: CanvasItem) -> void:
	panel.self_modulate = Color(5.0, 5.0, 5.0)
	panel.create_tween().tween_property(panel, "self_modulate", Color.WHITE, 0.35).set_ease(Tween.EASE_OUT)


## Lässt ein Element kurz größer werden und zurückfedern.
static func pop(node: Control, strength: float = 1.25) -> void:
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ONE * strength
	node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Aufdecken eines Rätsels: Das Icon geht vom schwarzen Umriss in seine Farben
## über und hüpft dabei, die Fläche blitzt auf.
static func reveal(panel: CanvasItem, icon: Control, use_self_modulate: bool = false) -> void:
	flash(panel)
	pop(icon, 1.5)
	var property: String = "self_modulate" if use_self_modulate else "modulate"
	icon.set(property, Color(0, 0, 0, 0.75))
	icon.create_tween().tween_property(icon, property, Color.WHITE, 0.5)


## Sanftes Einblenden, wenn eine Zeile neu auftaucht.
static func fade_in(node: CanvasItem) -> void:
	node.modulate.a = 0.0
	node.create_tween().tween_property(node, "modulate:a", 1.0, 0.4)
