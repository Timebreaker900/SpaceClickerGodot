extends SceneTree
## Erzeugt ui/theme.tres – das Aussehen aller Knöpfe, Flächen, Reiter usw.
##
##   godot --headless --path . -s tools/build_theme.gd
##
## Farben und Formen stehen hier an einer Stelle. Nach einer Änderung das Skript
## laufen lassen; die Szenen selbst müssen nicht angefasst werden.

const TEXT := Color("e8f4ff")
const TEXT_MUTED := Color("8fb2d6")
const TEXT_DARK := Color("04121f")
const ACCENT := Color("3fd0ff")
const PANEL := Color(0.04, 0.07, 0.15, 0.84)
const PANEL_BORDER := Color(0.25, 0.82, 1.0, 0.30)
const BUTTON := Color(0.08, 0.19, 0.34, 0.95)
const BUTTON_HOVER := Color(0.11, 0.27, 0.46, 0.98)
const PRIMARY := Color(0.10, 0.52, 0.78)
const PRIMARY_HOVER := Color(0.16, 0.62, 0.90)
const DISABLED := Color(0.07, 0.10, 0.17, 0.70)
const DISABLED_BORDER := Color(0.45, 0.55, 0.70, 0.25)


func _init() -> void:
	var theme := Theme.new()
	theme.default_font_size = 34

	theme.set_color("font_color", "Label", TEXT)

	# Flächen (Gebäudezeilen, Ressourcenleiste)
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, PANEL_BORDER, 2, 20))

	# Normale Knöpfe. "pressed" gilt auch für eingerastete Umschalter (Coins/Holz).
	theme.set_stylebox("normal", "Button", _box(BUTTON, Color(ACCENT, 0.55), 2, 16, 24, 10))
	theme.set_stylebox("hover", "Button", _box(BUTTON_HOVER, ACCENT, 2, 16, 24, 10))
	theme.set_stylebox("pressed", "Button", _box(ACCENT, ACCENT, 2, 16, 24, 10))
	theme.set_stylebox("disabled", "Button", _box(DISABLED, DISABLED_BORDER, 2, 16, 24, 10))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", TEXT_DARK)
	theme.set_color("font_hover_pressed_color", "Button", TEXT_DARK)
	theme.set_color("font_disabled_color", "Button", Color(TEXT_MUTED, 0.45))

	# Hauptknöpfe (Kaufen, Start): gefüllt, damit das Auge sie zuerst findet.
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _box(PRIMARY, ACCENT, 2, 16, 24, 10))
	theme.set_stylebox("hover", "PrimaryButton", _box(PRIMARY_HOVER, Color.WHITE, 2, 16, 24, 10))
	theme.set_stylebox("pressed", "PrimaryButton", _box(ACCENT, Color.WHITE, 2, 16, 24, 10))
	theme.set_color("font_color", "PrimaryButton", Color.WHITE)

	# Reiter: der gewählte bekommt eine leuchtende Unterkante.
	var tab_selected := _box(Color(ACCENT, 0.14), ACCENT, 0, 12, 30, 14)
	tab_selected.border_width_bottom = 5
	tab_selected.corner_radius_bottom_left = 0
	tab_selected.corner_radius_bottom_right = 0
	var tab_idle := _box(Color(0, 0, 0, 0), Color(ACCENT, 0.2), 0, 12, 30, 14)
	tab_idle.border_width_bottom = 2
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_idle)
	theme.set_stylebox("tab_hovered", "TabContainer", tab_idle)
	theme.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	var tab_panel := StyleBoxEmpty.new()
	tab_panel.content_margin_top = 16
	theme.set_stylebox("panel", "TabContainer", tab_panel)
	theme.set_color("font_selected_color", "TabContainer", Color.WHITE)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_MUTED)
	theme.set_color("font_hovered_color", "TabContainer", TEXT)

	# Fortschrittsbalken der Rezepte
	theme.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.45), Color(ACCENT, 0.25), 1, 9))
	theme.set_stylebox("fill", "ProgressBar", _box(ACCENT, ACCENT, 0, 9))

	# Schmale Bildlaufleiste
	var track := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4)
	track.content_margin_left = 4
	track.content_margin_right = 4
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("grabber", "VScrollBar", _box(Color(ACCENT, 0.35), ACCENT, 0, 4))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(ACCENT, 0.6), ACCENT, 0, 4))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _box(ACCENT, ACCENT, 0, 4))

	# Auto-Schalter
	theme.set_color("font_color", "CheckButton", TEXT_MUTED)
	theme.set_color("font_pressed_color", "CheckButton", ACCENT)
	theme.set_color("font_hover_color", "CheckButton", TEXT)
	theme.set_color("font_hover_pressed_color", "CheckButton", ACCENT)
	theme.set_color("font_disabled_color", "CheckButton", Color(TEXT_MUTED, 0.4))

	var error: int = ResourceSaver.save(theme, "res://ui/theme.tres")
	print("Theme gespeichert" if error == OK else "Fehler beim Speichern: %d" % error)
	quit(0 if error == OK else 1)


func _box(background: Color, border: Color, border_width: int, radius: int,
		margin_h: int = 0, margin_v: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box
