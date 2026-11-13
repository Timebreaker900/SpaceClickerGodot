extends Node
## Einstellungen des Spielers. Als Autoload "Options" überall erreichbar.
##
## Sie liegen in einer eigenen Datei, getrennt vom Spielstand: "Spielstand
## zurücksetzen" lässt Lautstärke und Zahlenformat in Ruhe.

var volume: float = 0.7              # 0 = stumm, 1 = voll
var number_format: String = "short"  # "short" = 1,23 Mio / "scientific" = 1.23e6

var _path: String = "user://options.json"


func _ready() -> void:
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("res://tests/"):
			_path = "user://test_options.json"
	if not FileAccess.file_exists(_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if typeof(data) != TYPE_DICTIONARY:
		return
	volume = clampf(float(data.get("volume", volume)), 0.0, 1.0)
	if data.get("number_format", "") in ["short", "scientific"]:
		number_format = data["number_format"]


func save() -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({ "volume": volume, "number_format": number_format }))
