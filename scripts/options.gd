extends Node
## Einstellungen des Spielers. Als Autoload "Options" überall erreichbar.
##
## Sie liegen in einer eigenen Datei, getrennt vom Spielstand: "Spielstand
## zurücksetzen" lässt Lautstärke, Zahlenformat und Sprache in Ruhe.
##
## Sprache: Alle Texte stehen auf Deutsch im Code und in data/*.json. Für jede
## weitere Sprache gibt es eine Datei data/lang_<kürzel>.json, die den deutschen
## Text auf den übersetzten abbildet. Godot schlägt darin nach, wenn tr() einen
## Text übersetzt oder ein Knopf bzw. Label seinen Text anzeigt.

const LANGUAGES: Dictionary = { "de": "Deutsch", "en": "English" }

var volume: float = 0.7              # 0 = stumm, 1 = voll
var number_format: String = "short"  # "short" = 1,23 Mio / "scientific" = 1.23e6
var language: String = "de"

var _path: String = "user://options.json"


func _ready() -> void:
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("res://tests/"):
			_path = "user://test_options.json"
	_load_translations()
	if FileAccess.file_exists(_path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if typeof(data) == TYPE_DICTIONARY:
			volume = clampf(float(data.get("volume", volume)), 0.0, 1.0)
			if data.get("number_format", "") in ["short", "scientific"]:
				number_format = data["number_format"]
			if LANGUAGES.has(data.get("language", "")):
				language = data["language"]
	TranslationServer.set_locale(language)


func set_language(code: String) -> void:
	if not LANGUAGES.has(code):
		return
	language = code
	TranslationServer.set_locale(code)
	save()


func save() -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({ "volume": volume, "number_format": number_format, "language": language }))


func _load_translations() -> void:
	for code: String in LANGUAGES:
		var path: String = "res://data/lang_%s.json" % code
		if not FileAccess.file_exists(path):
			continue  # Deutsch braucht keine Datei: Es ist die Ausgangssprache.
		var entries: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(entries) != TYPE_DICTIONARY:
			push_warning("Sprachdatei unlesbar: %s" % path)
			continue
		var translation := Translation.new()
		translation.locale = code
		for source: String in entries:
			translation.add_message(source, entries[source])
		TranslationServer.add_translation(translation)
