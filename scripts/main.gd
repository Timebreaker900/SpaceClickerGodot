extends Control
## Der Hauptbildschirm: zeigt den Zustand aus "Game" an und reicht Eingaben weiter.
## Hier steht keine Spielregel – nur Anzeige.

const BuildingRow := preload("res://scenes/building_row.tscn")
const RecipeRow := preload("res://scenes/recipe_row.tscn")
const UpgradeRow := preload("res://scenes/upgrade_row.tscn")
const GAME_VERSION := "0.3"
const BASE_MARGIN := 28       # normaler Abstand zum Bildschirmrand
const HINT_TOP := 700.0       # Lage des Hinweisfelds ohne Zusatzrand
const TOASTS_TOP := 250.0     # Lage der Einblendungen ohne Zusatzrand

@onready var resource_bar: GridContainer = %ResourceBar
@onready var bar_divider: ColorRect = %BarDivider
@onready var capacity_bar: HBoxContainer = %CapacityBar
@onready var settings_button: Button = %SettingsButton
@onready var resources_button: Button = %ResourcesButton
@onready var planet: TextureButton = %Planet
@onready var click_coins: Button = %ClickCoins
@onready var click_wood: Button = %ClickWood
@onready var pop_caption: Label = %PopCaption
@onready var pop_cost: RichTextLabel = %PopCost
@onready var pop_button: Button = %PopButton
@onready var buy_amount_button: Button = %BuyAmountButton
@onready var building_list: VBoxContainer = %BuildingList
@onready var production_tab: Control = %Produktion
@onready var recipe_groups: HBoxContainer = %RecipeGroups
@onready var recipe_list: VBoxContainer = %RecipeList
@onready var upgrade_list: VBoxContainer = %UpgradeList
var _stat_labels: Dictionary = {}  # Schlüssel -> Label in der Übersicht "Aktuell"
@onready var resource_list: VBoxContainer = %ResourceList
@onready var tabs: TabContainer = %Tabs
@onready var hint_area: CenterContainer = %HintArea
@onready var hint: PanelContainer = %Hint
@onready var hint_label: Label = %HintLabel
@onready var toasts: VBoxContainer = %Toasts
@onready var popup: Control = %Popup
@onready var offline_popup: Control = %OfflinePopup
@onready var offline_time: Label = %OfflineTime
@onready var offline_gains: RichTextLabel = %OfflineGains
@onready var offline_close: Button = %OfflineClose

# Je Ressource die Einträge in der Leiste oben und im Reiter "Ressourcen".
# Ein Eintrag ist { "node": die ganze Zeile, "label": das Label mit der Zahl }.
var _bar_entries: Dictionary = {}
var _list_entries: Dictionary = {}
var _group_headings: Dictionary = {}  # Gruppenname -> Überschrift im Reiter
var _group_buttons: Dictionary = {}   # Gebäude-ID -> Knopf im Umschalter des Reiters "Produktion"
var _recipe_rows: Array = []          # alle Rezeptzeilen
var _recipe_group: String = ""        # gerade gezeigte Gruppe (Gebäude-ID)
var _seen_before: Dictionary = {}     # Stand von Game.seen im vorigen Bild
var _planet_building: Dictionary      # Gebäude mit eigenem Knopf beim Planeten (Bevölkerung)
var _rocket_button: Button            # Knopf neben dem Planeten, öffnet die Raketen-Ansicht


func _ready() -> void:
	for res: Dictionary in Game.resources:
		# Leiste: Vorräte fließen oben, Versorgung (Bevölkerung, Strom) steht
		# in einer eigenen Zeile darunter.
		var bar_parent: Container = capacity_bar if res["type"] == "capacity" else resource_bar
		_bar_entries[res["id"]] = _add_resource_entry(bar_parent, res, 48, false, 136)
		var group: String = res.get("group", "")
		if not _group_headings.has(group):
			_group_headings[group] = _add_group_heading(group)
		_list_entries[res["id"]] = _add_resource_entry(resource_list, res, 64, true)

	_build_building_rows()
	pop_caption.text = _planet_building.get("caption", "")
	for recipe: Dictionary in Game.recipes:
		# Je Gebäude mit Rezepten ein Knopf im Umschalter: "Schmelzen", "Herstellen".
		var building_id: String = recipe["building"]
		if not _group_buttons.has(building_id):
			var button := Button.new()
			button.text = Game.building_def(building_id).get("recipes_label", "")
			button.toggle_mode = true
			button.custom_minimum_size.y = 84
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(func() -> void:
				Sfx.play("tap")
				_recipe_group = building_id)
			recipe_groups.add_child(button)
			_group_buttons[building_id] = button
		var row: Node = RecipeRow.instantiate()
		recipe_list.add_child(row)
		row.setup(recipe)
		_recipe_rows.append(row)
	_build_stats()
	_build_rocket_button()
	for upgrade: Dictionary in Game.upgrades:
		if Game.bought[upgrade["id"]]:
			continue  # Gekaufte Upgrades tauchen nicht mehr auf.
		var row: Node = UpgradeRow.instantiate()
		upgrade_list.add_child(row)
		row.setup(upgrade)

	# Wischen am Handy: Alle Listen reichen Berührungen weiter und melden, wenn
	# gewischt wird (siehe Ui.pass_touches und Ui.tap_allowed).
	for list: Control in [building_list, recipe_list, upgrade_list, resource_list]:
		Ui.pass_touches(list)
		var scroll: ScrollContainer = list.get_parent()
		scroll.scroll_started.connect(Ui.set_scrolling.bind(true))
		scroll.scroll_ended.connect(Ui.set_scrolling.bind(false))

	planet.pivot_offset = planet.custom_minimum_size / 2.0
	planet.button_down.connect(_on_planet_pressed)
	click_coins.pressed.connect(_set_click_target.bind("coins"))
	click_wood.pressed.connect(_set_click_target.bind("wood"))
	pop_button.pressed.connect(func() -> void:
		if Game.buy(_planet_building):
			Sfx.play("buy")
			Ui.pop(pop_button, 1.12))
	buy_amount_button.pressed.connect(_on_buy_amount_pressed)
	buy_amount_button.text = tr("Kaufen: Max") if Game.buy_max else tr("Kaufen: %d") % Game.buy_amount
	settings_button.pressed.connect(_open_settings)
	resources_button.pressed.connect(_open_bar_picker)
	_set_click_target(Game.click_target)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_seen_before = Game.seen.duplicate()
	# Leiser Tipp-Ton für alles, was nur umschaltet oder ein Fenster öffnet.
	for button: Button in [click_coins, click_wood, buy_amount_button, settings_button, resources_button, offline_close]:
		button.pressed.connect(Sfx.play.bind("tap"))
	tabs.tab_changed.connect(func(_index: int) -> void: Sfx.play("tap"))
	Game.announcement.connect(_show_toast)

	# Abwesenheit: beim Start steht der Bericht schon bereit, bei der Rückkehr in
	# die App (Handy) kommt er über das Signal.
	offline_close.pressed.connect(func() -> void: offline_popup.visible = false)
	Ui.close_on_outside_tap(offline_popup, offline_popup.get_node("Center"), offline_popup.get_node("Center/Panel"))
	Game.offline_applied.connect(_show_offline_report)
	if not Game.offline_report.is_empty():
		_show_offline_report(Game.offline_report)


## Übersicht ganz oben im Reiter "Upgrades": was die gekauften Upgrades gerade
## bewirken (Stärke pro Klick, Abwesenheit). Die Zahlen füllt _update_stats().
func _build_stats() -> void:
	upgrade_list.add_child(_heading(tr("Aktuell")))
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 12)
	for id: String in Game.settings["click"]:
		_stat_labels["click_" + id] = _add_stat_line(lines, Game.resource_def(id)["icon"])
	_stat_labels["offline"] = _add_stat_line(lines, "res://assets/icons/offline_rate.svg")
	margin.add_child(lines)
	panel.add_child(margin)
	upgrade_list.add_child(panel)


func _add_stat_line(parent: Container, icon_path: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_icon(icon_path, 52))
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	parent.add_child(row)
	return label


func _update_stats() -> void:
	for id: String in Game.settings["click"]:
		_stat_labels["click_" + id].text = tr("%s pro Klick: %s") % [Game.resource_def(id)["name"], Game.fmt(Game.click_gain(id))]
	if Game.offline_hours() <= 0.0 or Game.offline_percent() <= 0.0:
		_stat_labels["offline"].text = tr("Abwesenheit: noch nicht freigeschaltet")
	else:
		_stat_labels["offline"].text = tr("Abwesenheit: bis %s h, %s %% Ertrag") % [Game.fmt(Game.offline_hours()), Game.fmt(Game.offline_percent())]


## Legt die Gebäudezeilen an. Drei Fälle, gesteuert über data/buildings.json:
##   "placement": "planet" -> keine Zeile, sondern der Knopf beim Planeten
##   "parent": "mine"      -> Unterzeile im aufklappbaren Menü der Mine
##   sonst                 -> normale Zeile in der Liste
func _build_building_rows() -> void:
	var rows: Dictionary = {}  # Gebäude-ID -> Zeile
	for building: Dictionary in Game.buildings:
		if building.get("placement", "list") == "planet":
			_planet_building = building
			continue
		var row: Node = BuildingRow.instantiate()
		if building.has("parent"):
			rows[building["parent"]].add_sub_row(row)
		else:
			building_list.add_child(row)
		row.setup(building)
		rows[building["id"]] = row


func _process(_delta: float) -> void:
	# Der Planet schwebt: langsam auf und ab und wiegt sich dabei ein wenig.
	# Zwei verschieden schnelle Sinuswellen, damit es nicht mechanisch wirkt.
	var time: float = Time.get_ticks_msec() / 1000.0
	planet.position.y = sin(time * 0.9) * 10.0
	planet.rotation = sin(time * 0.5) * 0.045

	# Einstiegshinweis: sichtbar, solange es einen gibt, und leicht wippend.
	var hint_text: String = _hint_text()
	hint.visible = hint_text != ""
	hint_label.text = hint_text
	hint.position.y = sin(time * 3.0) * 6.0

	var rates: Dictionary = Game.get_rates()
	_update_resource_views(rates)
	_update_population_button(rates)

	# Der Reiter "Produktion" erscheint erst, wenn es ein Rezept gibt.
	var any_recipe: bool = false
	var buildings_with_recipes: Dictionary = {}
	for recipe: Dictionary in Game.recipes:
		if Game.recipe_visible(recipe):
			any_recipe = true
			buildings_with_recipes[recipe["building"]] = true
	tabs.set_tab_hidden(production_tab.get_index(), not any_recipe)
	# Umschalter: Es gibt nur Knöpfe für Gruppen, in denen schon etwas zu sehen ist.
	# Ist die gewählte Gruppe leer, springt die Anzeige zur ersten mit Inhalt.
	if not buildings_with_recipes.has(_recipe_group) and not buildings_with_recipes.is_empty():
		_recipe_group = buildings_with_recipes.keys()[0]
	recipe_groups.visible = buildings_with_recipes.size() > 1
	for building_id: String in _group_buttons:
		_group_buttons[building_id].visible = buildings_with_recipes.has(building_id)
		_group_buttons[building_id].set_pressed_no_signal(building_id == _recipe_group)
	for row: Node in _recipe_rows:
		row.in_shown_group = row.recipe["building"] == _recipe_group

	_update_stats()
	_rocket_button.visible = Game.rocket_available()

	# Der Reiter zeigt, wie viele Upgrades gerade kaufbar sind.
	var buyable: int = 0
	for upgrade: Dictionary in Game.upgrades:
		if Game.can_buy_upgrade(upgrade):
			buyable += 1
	tabs.set_tab_title(upgrade_list.get_parent().get_index(), "Upgrades (%d)" % buyable if buyable > 0 else "Upgrades")


## Handys haben oben oft eine Kamera-Aussparung (Notch), unten eine Wischleiste
## und runde Ecken. Das System nennt den "sicheren Bereich"; alles außerhalb
## wird hier als zusätzlicher Rand freigehalten. Der Hintergrund füllt weiter
## den ganzen Bildschirm.
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return  # Am PC meldet das System hier die Arbeitsfläche des Monitors, nicht des Fensters.
	var window: Vector2i = DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	# Das System rechnet in Bildschirmpixeln, das Spiel in seiner eigenen Breite von 1080.
	var factor: float = get_viewport_rect().size.x / float(window.x)
	set_insets(
		maxf(0.0, safe.position.x * factor),
		maxf(0.0, safe.position.y * factor),
		maxf(0.0, (window.x - safe.end.x) * factor),
		maxf(0.0, (window.y - safe.end.y) * factor))


## Setzt die Zusatzränder (in Spiel-Einheiten). Eigene Funktion, damit sich das
## auch am PC ausprobieren lässt.
func set_insets(left: float, top: float, right: float, bottom: float) -> void:
	var margin: MarginContainer = $Margin
	margin.add_theme_constant_override("margin_left", BASE_MARGIN + int(left))
	margin.add_theme_constant_override("margin_top", BASE_MARGIN + int(top))
	margin.add_theme_constant_override("margin_right", BASE_MARGIN + int(right))
	margin.add_theme_constant_override("margin_bottom", BASE_MARGIN + int(bottom))
	# Hinweisfeld und Einblendungen hängen nicht im Layout und wandern mit.
	hint_area.offset_top = HINT_TOP + top
	hint_area.offset_bottom = HINT_TOP + 90.0 + top
	toasts.offset_top = TOASTS_TOP + top
	toasts.offset_bottom = TOASTS_TOP + top


## Führt neue Spieler bis zum ersten Gebäude: klicken, beide Ressourcen sammeln,
## kaufen. Sobald das erste Gebäude steht, kommt kein Hinweis mehr.
func _hint_text() -> String:
	var first: Dictionary = Game.buildings[0]
	if Game.levels[first["id"]] > 0:
		var capacity_hint: String = _capacity_hint()
		return capacity_hint if capacity_hint != "" else _fuel_hint()
	if Game.can_buy(first, 1):
		return tr("Kaufe unten: %s") % first["name"]
	var total_clicks: int = 0
	for id: String in Game.click_counts:
		total_clicks += Game.click_counts[id]
	if total_clicks == 0:
		return tr("Tippe auf den Planeten")
	# Wovon ist schon genug da, wovon fehlt noch? Der Hinweis kommt nur, wenn
	# gerade das Falsche geklickt wird.
	var cost: Dictionary = Game.cost_for(first, 1)
	var target: String = Game.click_target
	if cost.has(target) and Game.amounts[target] >= float(cost[target]):
		for id: String in cost:
			if id != target and Game.amounts[id] < float(cost[id]):
				return tr("Genug %s. Schalte links um auf %s") % [Game.resource_def(target)["name"], Game.resource_def(id)["name"]]
	return ""


## Zweiter Schritt der Einführung: Sobald ein Gebäude zu sehen ist, das Bevölkerung
## braucht, und es noch keine gibt, zeigt der Hinweis auf den Knopf rechts.
func _capacity_hint() -> String:
	if _planet_building.is_empty():
		return ""
	for capacity_id: String in _planet_building.get("provides", {}):
		if Game.capacity_total(capacity_id) > 0.0:
			continue
		for building: Dictionary in Game.buildings:
			if building.get("reserves", {}).has(capacity_id) and Game.building_visibility(building) == "known":
				var cost: Dictionary = _planet_building.get("cost", {})
				var paid_with: String = Game.resource_def(cost.keys()[0])["name"] if not cost.is_empty() else ""
				return tr("%s braucht %s. Kaufe sie rechts mit %s") % [
					building["name"], Game.resource_def(capacity_id)["name"], paid_with]
	return ""


## Dritter Schritt: Steht ein Gebäude mit Rezepten, aber es fehlt noch eine Zutat,
## die der Spieler nie hatte (Kohle für die Schmelze), sagt der Hinweis, woher
## sie kommt. Sonst stünde man vor einem leeren Produktions-Reiter.
func _fuel_hint() -> String:
	for recipe: Dictionary in Game.recipes:
		if Game.recipe_batch(recipe) == 0 or Game.recipe_visible(recipe):
			continue
		for id: String in recipe["input"]:
			if Game.seen[id]:
				continue
			for building: Dictionary in Game.buildings:
				if building.get("produces", {}).has(id) and Game.building_visibility(building) != "hidden":
					var where: String = building["name"]
					if building.has("parent"):
						var parent: Dictionary = Game.building_def(building["parent"])
						where = tr("%s unter %s") % [parent.get("children_label", ""), parent["name"]]
					return tr("%s braucht %s: %s") % [Game.building_def(recipe["building"])["name"], Game.resource_def(id)["name"], where]
	return ""


## Leiste und Ressourcen-Reiter zeigen nur, was der Spieler schon einmal hatte.
## Die Leiste zeigt bloß den Stand; die Rate pro Sekunde steht im Reiter.
func _update_resource_views(rates: Dictionary) -> void:
	var groups_seen: Dictionary = {}
	var any_capacity: bool = false
	for res: Dictionary in Game.resources:
		var id: String = res["id"]
		var seen: bool = Game.seen[id]
		var is_capacity: bool = res["type"] == "capacity"
		var bar_entry: Dictionary = _bar_entries[id]
		bar_entry["node"].visible = seen and (is_capacity or Game.bar_selection.has(id))
		bar_entry["label"].text = _resource_text(id, rates, false)
		var list_entry: Dictionary = _list_entries[id]
		list_entry["node"].visible = seen
		list_entry["label"].text = _resource_text(id, rates, true)
		if seen and not _seen_before.get(id, false):
			# Gerade entdeckt: Einblendung, und der Eintrag in der Leiste hüpft.
			_seen_before[id] = true
			_show_toast(res["icon"], tr("Entdeckt: %s") % res["name"])
			Sfx.play("discover")
			if bar_entry["node"].visible:
				Ui.pop.call_deferred(bar_entry["node"], 1.4)
		if seen:
			groups_seen[res.get("group", "")] = true
			any_capacity = any_capacity or is_capacity
	for group: String in _group_headings:
		_group_headings[group].visible = groups_seen.has(group)
	bar_divider.visible = any_capacity
	capacity_bar.visible = any_capacity


## Der Bevölkerungs-Knopf: einmaliger Preis plus laufender Verbrauch, jeder
## Posten einzeln rot, wenn es daran scheitert.
func _update_population_button(rates: Dictionary) -> void:
	if _planet_building.is_empty():
		return
	var count: int = Game.buy_count(_planet_building)
	var text: String = Ui.cost_line(Game.cost_for(_planet_building, count))
	var upkeep: Dictionary = Game.building_output(_planet_building, "produces")
	for id: String in upkeep:
		var per_second: float = -float(upkeep[id]) * count
		if per_second > 0.0:
			text += "   " + Ui.amount(id, per_second, rates.get(id, 0.0) >= per_second, "", "/s")
	if pop_cost.text != text:
		pop_cost.text = text
	pop_button.text = "+%d" % count
	pop_button.disabled = not Game.can_buy(_planet_building, count)


## Vorräte: der Stand, auf Wunsch mit Rate ("1234  +2/s").
## Versorgung: in der Leiste knapp "3 / 9", im Reiter ausgeschrieben "3 frei von 9".
func _resource_text(id: String, rates: Dictionary, with_rate: bool) -> String:
	if Game.resource_def(id)["type"] == "capacity":
		var pattern: String = tr("%s frei von %s") if with_rate else "%s / %s"
		return pattern % [Game.fmt(Game.capacity_free(id)), Game.fmt(Game.capacity_total(id))]
	# In der Leiste ist wenig Platz, dort steht die Zahl mit drei Stellen (12,3 Mio).
	var text: String = Game.fmt(Game.amounts[id]) if with_rate else Game.fmt_compact(Game.amounts[id])
	var rate: float = rates.get(id, 0.0)
	if with_rate and rate != 0.0:
		text += "  %s/s" % Game.fmt_signed(rate)
	return text


## Legt Icon + Zahl an und gibt die Zeile samt Zahlen-Label zurück.
## Mit "fixed_width" bekommt die Zahl eine feste Breite. Dann verschiebt sich
## nichts, wenn eine Zahl eine Stelle länger wird (wichtig für die Leiste).
func _add_resource_entry(parent: Container, res: Dictionary, icon_size: int, with_name: bool,
		fixed_width: int = 0) -> Dictionary:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 12)
	entry.add_child(_icon(res["icon"], icon_size))
	if with_name:
		var name_label := Label.new()
		name_label.text = res["name"]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_child(name_label)
	var value_label := Label.new()
	if fixed_width > 0:
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.custom_minimum_size.x = fixed_width
		value_label.clip_text = true
		value_label.add_theme_font_size_override("font_size", 30)
	entry.add_child(value_label)
	parent.add_child(entry)
	return { "node": entry, "label": value_label }


func _icon(path: String, icon_size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(path)
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _add_group_heading(title: String) -> Label:
	var heading: Label = _heading(title)
	resource_list.add_child(heading)
	return heading


## Türkise Zwischenüberschrift für Listen.
func _heading(title: String) -> Label:
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"HeadingLabel"
	heading.add_theme_font_size_override("font_size", 38)
	heading.add_theme_color_override("font_color", Color(0.25, 0.82, 1.0))
	return heading


## Kurze Einblendung unter der Leiste: erscheint, bleibt gut zwei Sekunden und
## blendet wieder aus. Mehrere stapeln sich untereinander.
func _show_toast(icon_path: String, text: String) -> void:
	var toast := PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_icon(icon_path, 60))
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeadingLabel"
	row.add_child(label)
	margin.add_child(row)
	toast.add_child(margin)
	toasts.add_child(toast)
	toast.modulate.a = 0.0
	var tween: Tween = toast.create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	tween.tween_interval(2.2)
	tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	tween.tween_callback(toast.queue_free)


# --- Fenster ------------------------------------------------------------------

## Auswahl, welche Vorräte die Leiste oben zeigt. Zur Wahl steht nur, was der
## Spieler schon entdeckt hat; die Obergrenze kommt aus data/settings.json.
func _open_bar_picker() -> void:
	popup.open(tr("Leiste anpassen"), 760)
	var limit: int = int(Game.settings.get("bar_max", 8))
	var counter := Label.new()
	counter.add_theme_color_override("font_color", Color(0.25, 0.82, 1.0))
	popup.content.add_child(counter)
	var boxes: Dictionary = {}  # Ressourcen-ID -> Schalter
	var refresh := func() -> void:
		counter.text = tr("%d von höchstens %d Vorräten gewählt. Bevölkerung und Strom sind immer zu sehen.") % [
			Game.bar_selection.size(), limit]
		for id: String in boxes:
			# Ist die Grenze erreicht, lassen sich nur noch gewählte abwählen.
			boxes[id].disabled = Game.bar_selection.size() >= limit and not boxes[id].button_pressed
	counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for res: Dictionary in Game.resources:
		if res["type"] != "stock" or not Game.seen[res["id"]]:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.add_child(_icon(res["icon"], 64))
		var box := CheckButton.new()
		box.text = res["name"]
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.button_pressed = Game.bar_selection.has(res["id"])
		box.toggled.connect(func(on: bool) -> void:
			Game.set_bar_selected(res["id"], on)
			refresh.call())
		row.add_child(box)
		popup.content.add_child(row)
		boxes[res["id"]] = box
	refresh.call()
	Ui.pass_touches(popup.content)


func _open_settings() -> void:
	popup.open(tr("Einstellungen"), 900)
	var version := Label.new()
	version.text = "Space Clicker – Version %s" % GAME_VERSION
	version.add_theme_color_override("font_color", Color(0.56, 0.70, 0.84))
	popup.content.add_child(version)

	var hint := Label.new()
	hint.text = tr("Der Spielstand wird alle 10 Sekunden und beim Schließen gespeichert.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup.content.add_child(hint)

	var volume_label := Label.new()
	popup.content.add_child(volume_label)
	var slider := HSlider.new()
	slider.max_value = 100
	slider.step = 5
	slider.value = Options.volume * 100.0
	slider.custom_minimum_size.y = 64
	var show_volume := func() -> void:
		volume_label.text = tr("Ton: aus") if slider.value == 0 else tr("Ton: %d %%") % int(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		Sfx.set_volume(value / 100.0)
		Sfx.play("buy")  # gleich hören, wie laut es ist
		show_volume.call())
	show_volume.call()
	popup.content.add_child(slider)

	# Zahlenformat: ein Knopf, der zwischen den beiden Schreibweisen wechselt.
	var format_button := Button.new()
	format_button.custom_minimum_size.y = 96
	var show_format := func() -> void:
		format_button.text = tr("Zahlen: %s") % Game.fmt(1234567.0)
	format_button.pressed.connect(func() -> void:
		Options.number_format = "scientific" if Options.number_format == "short" else "short"
		Options.save()
		Sfx.play("tap")
		show_format.call())
	show_format.call()
	popup.content.add_child(format_button)

	# Sprache: wechselt zwischen den vorhandenen Sprachen. Danach wird der
	# Bildschirm neu aufgebaut, damit jede Zeile ihren Text neu holt.
	var language_button := Button.new()
	language_button.custom_minimum_size.y = 96
	language_button.text = tr("Sprache: Deutsch")
	language_button.pressed.connect(func() -> void:
		var codes: Array = Options.LANGUAGES.keys()
		Options.set_language(codes[(codes.find(Options.language) + 1) % codes.size()])
		Game.localize()
		Sfx.play("tap")
		get_tree().reload_current_scene())
	popup.content.add_child(language_button)

	# Zurücksetzen steht abgesetzt ganz unten, ist rot und braucht zwei Tipps,
	# damit es nicht aus Versehen passiert.
	var gap := Control.new()
	gap.custom_minimum_size.y = 90
	popup.content.add_child(gap)
	popup.content.add_child(HSeparator.new())
	var reset := Button.new()
	reset.text = tr("Spielstand zurücksetzen")
	reset.custom_minimum_size.y = 96
	reset.theme_type_variation = &"DangerButton"
	var armed := [false]
	reset.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			reset.text = tr("Wirklich alles löschen? Nochmal tippen")
			return
		Game.reset_game()
		get_tree().reload_current_scene())
	popup.content.add_child(reset)


func _show_offline_report(report: Dictionary) -> void:
	offline_time.text = tr("Du warst %s weg.") % _duration_text(report["seconds"])
	offline_time.text += tr(" Angerechnet: %s zu %d %%.") % [_duration_text(report["counted"]), int(report["percent"])]
	var lines: PackedStringArray = []
	var gains: Dictionary = report["gains"]
	for res: Dictionary in Game.resources:  # Reihenfolge wie in der Ressourcenliste
		if gains.has(res["id"]):
			lines.append("[img=48x48]%s[/img]  +%s %s" % [res["icon"], Game.fmt(gains[res["id"]]), res["name"]])
	offline_gains.text = "\n".join(lines)
	offline_popup.visible = true
	Sfx.play("discover")


## "45 Sek", "12 Min", "3 Std 20 Min"
func _duration_text(seconds: float) -> String:
	var total: int = int(seconds)
	if total < 60:
		return tr("%d Sek") % total
	if total < 3600:
		return tr("%d Min") % (total / 60)
	var minutes: int = (total % 3600) / 60
	return tr("%d Std") % (total / 3600) if minutes == 0 else tr("%d Std %d Min") % [total / 3600, minutes]


# --- Rakete -------------------------------------------------------------------

## Knopf neben dem Planeten; erscheint, sobald die Startrampe steht.
func _build_rocket_button() -> void:
	_rocket_button = Button.new()
	_rocket_button.icon = load(Game.rocket["icon"])
	_rocket_button.expand_icon = true
	_rocket_button.custom_minimum_size = Vector2(130, 130)
	_rocket_button.size = Vector2(130, 130)
	_rocket_button.position = Vector2(planet.custom_minimum_size.x - 110, -10)
	_rocket_button.tooltip_text = tr("Rakete")
	_rocket_button.visible = false
	_rocket_button.pressed.connect(func() -> void:
		Sfx.play("tap")
		_open_rocket())
	planet.get_parent().add_child(_rocket_button)


## Die Raketen-Ansicht: oben das Bild (fehlende Teile als dunkler Umriss),
## darunter die Teile mit Kosten und Bauknopf, ganz unten der Start.
func _open_rocket() -> void:
	popup.open(tr("Rakete"), 1000)
	var picture := Control.new()
	picture.custom_minimum_size = Vector2(380, 380)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.content.add_child(picture)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup.content.add_child(status)

	var layers: Dictionary = {}   # Teil-ID -> Bild in der Rakete
	var costs: Dictionary = {}    # Teil-ID -> Kostenzeile
	var buttons: Dictionary = {}  # Teil-ID -> Bauknopf
	var launch := Button.new()
	var refresh := func() -> void:
		for part: Dictionary in Game.rocket["parts"]:
			var id: String = part["id"]
			var built: bool = Game.rocket_built[id]
			layers[id].modulate = Color.WHITE if built else Color(0.1, 0.14, 0.2)
			costs[id].visible = not built
			var line: String = Ui.cost_line(part["cost"])
			if costs[id].text != line:
				costs[id].text = line
			buttons[id].text = tr("Gebaut") if built else tr("Bauen")
			buttons[id].disabled = not Game.can_build_rocket_part(part)
		var total: int = Game.rocket_built.size()
		if Game.rocket_launched:
			status.text = tr("Die Rakete ist gestartet. Der Mond ist freigeschaltet; sein Inhalt folgt in einer späteren Version.")
			launch.text = tr("Gestartet")
		else:
			status.text = tr("%d von %d Teilen gebaut") % [Game.rocket_parts_built(), total]
			launch.text = tr("Rakete starten")
		launch.disabled = Game.rocket_launched or not Game.rocket_complete()

	# Die Teile liegen deckungsgleich übereinander; die Reihenfolge der Datei
	# bestimmt nur die Liste, gezeichnet wird von hinten nach vorn.
	var parts: Array = Game.rocket["parts"].duplicate()
	parts.reverse()
	for part: Dictionary in parts:
		var layer: TextureRect = _icon(part["icon"], 380)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.add_child(layer)
		layers[part["id"]] = layer

	for part: Dictionary in Game.rocket["parts"]:
		var panel := PanelContainer.new()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		row.add_child(_icon(part["icon"], 96))
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		var title := Label.new()
		title.text = part["name"]
		title.theme_type_variation = &"HeadingLabel"
		text.add_child(title)
		var cost := RichTextLabel.new()
		cost.bbcode_enabled = true
		cost.fit_content = true
		cost.scroll_active = false
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(cost)
		row.add_child(text)
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 96)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(func() -> void:
			if Ui.tap_allowed() and Game.build_rocket_part(part):
				Sfx.play("upgrade")
				Ui.flash(panel)
				Ui.pop(layers[part["id"]])
				refresh.call())
		row.add_child(button)
		panel.add_child(row)
		popup.content.add_child(panel)
		costs[part["id"]] = cost
		buttons[part["id"]] = button

	launch.custom_minimum_size.y = 110
	launch.theme_type_variation = &"PrimaryButton"
	launch.pressed.connect(func() -> void:
		if Ui.tap_allowed() and Game.launch_rocket():
			Sfx.play("discover")
			_show_toast(Game.rocket["icon"], tr("Rakete gestartet – der Mond ist frei"))
			get_tree().create_timer(1.8).timeout.connect(_show_victory)
			# Die Rakete hebt ab: nach oben aus dem Bild und dabei ausblenden.
			var tween: Tween = picture.create_tween().set_parallel(true)
			tween.tween_property(picture, "position:y", picture.position.y - 900.0, 1.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(picture, "modulate:a", 0.0, 1.6)
			refresh.call())
	popup.content.add_child(launch)

	# Kosten färben sich um, während Material hereinkommt: zweimal pro Sekunde auffrischen.
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(refresh)
	popup.content.add_child(timer)
	refresh.call()
	Ui.pass_touches(popup.content)


## Siegbildschirm: Mit dem Start der Rakete ist die Erde abgeschlossen.
func _show_victory() -> void:
	popup.open(tr("Geschafft!"), 760)
	popup.close_button.text = tr("Weiterspielen")
	var picture: TextureRect = _icon(Game.rocket["icon"], 300)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	popup.content.add_child(picture)
	var total_clicks: int = 0
	for id: String in Game.click_counts:
		total_clicks += Game.click_counts[id]
	var total_levels: int = 0
	for id: String in Game.levels:
		total_levels += Game.levels[id]
	var lines: Array = [
		[tr("Du hast den Mond erreicht."), true],
		[tr("Damit ist die Erde abgeschlossen. Der Mond folgt in einer späteren Version."), false],
		[tr("Klicks insgesamt: %s") % Game.fmt(total_clicks), false],
		[tr("Gebäude-Level insgesamt: %s") % Game.fmt(total_levels), false],
	]
	for line: Array in lines:
		var label := Label.new()
		label.text = line[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if line[1]:
			label.theme_type_variation = &"HeadingLabel"
			label.add_theme_font_size_override("font_size", 44)
			label.add_theme_color_override("font_color", Color(0.25, 0.82, 1.0))
		popup.content.add_child(label)
	Sfx.play("discover")


# --- Eingaben -----------------------------------------------------------------

func _set_click_target(id: String) -> void:
	Game.click_target = id
	click_coins.button_pressed = id == "coins"
	click_wood.button_pressed = id == "wood"


func _on_buy_amount_pressed() -> void:
	Game.cycle_buy_amount()
	buy_amount_button.text = tr("Kaufen: Max") if Game.buy_max else tr("Kaufen: %d") % Game.buy_amount


func _on_planet_pressed() -> void:
	var gain: float = Game.click()
	Sfx.play("click_" + Game.click_target, 0.05)  # Münze klimpert, Holz klopft
	# Kurzes "Eindrücken" des Planeten.
	var tween: Tween = create_tween()
	tween.tween_property(planet, "scale", Vector2(0.94, 0.94), 0.05)
	tween.tween_property(planet, "scale", Vector2.ONE, 0.08)
	_spawn_click_effect(Game.click_target, gain)


## Das geklickte Icon springt kurz hoch und fliegt dann im Bogen zur Seite weg,
## wie im alten Spiel. Die Bahn ist eine Wurfparabel: seitlich gleichmäßig,
## nach unten immer schneller.
func _spawn_click_effect(resource_id: String, gain: float) -> void:
	var effect: TextureRect = _icon(Game.resource_def(resource_id)["icon"], 84)
	effect.size = Vector2(84, 84)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effect)
	move_child(effect, popup.get_index())  # unter den Fenstern bleiben
	if gain > 1.0:
		var label := Label.new()
		label.text = "+" + Game.fmt(gain)
		label.position = Vector2(88, 16)
		effect.add_child(label)

	var start: Vector2 = get_local_mouse_position() - effect.size / 2.0
	var direction: float = -1.0 if randf() < 0.5 else 1.0
	var distance: float = randf_range(200.0, 300.0)
	var fly := func(t: float) -> void:
		effect.position = start + Vector2(direction * distance * t, 422.0 * t * t - 169.0 * t)
		effect.modulate.a = clampf(2.0 - 2.0 * t, 0.0, 1.0)  # zweite Hälfte ausblenden
	var tween: Tween = effect.create_tween()
	tween.tween_method(fly, 0.0, 1.0, 0.45)
	tween.tween_callback(effect.queue_free)
