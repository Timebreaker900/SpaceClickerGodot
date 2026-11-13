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
