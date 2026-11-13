extends Node
## Alle Töne des Spiels. Als Autoload "Sfx" überall erreichbar: Sfx.play("buy")
##
## Die Töne sind keine Dateien, sondern werden beim Start berechnet: Jeder Ton
## besteht aus einem oder mehreren kurzen Sinustönen, die schnell abklingen.
## Um einen Ton später gegen eine echte Sounddatei zu tauschen, genügt es,
## _streams["name"] mit load("res://...") zu füllen.
##
## Die Lautstärke liegt in einer eigenen Datei und überlebt damit das
## Zurücksetzen des Spielstands.

const RATE := 44100  # Messwerte pro Sekunde

var volume: float = 0.7  # 0 = stumm, 1 = voll

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _options_path: String = "user://options.json"


func _ready() -> void:
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("res://tests/"):
			_options_path = "user://test_options.json"
	_load_options()

	# Ein Ton ist eine Liste aus [Start in s, Tonhöhe von, Tonhöhe bis, Dauer in s, Stärke].
	# Tonhöhen in Hertz; 523 / 659 / 784 / 1047 sind die Noten C, E, G, C.
	_streams["click"] = _build([[0.0, 900, 520, 0.08, 0.55]])
	_streams["tap"] = _build([[0.0, 1400, 1100, 0.035, 0.30]])
	_streams["buy"] = _build([[0.0, 523, 523, 0.09, 0.45], [0.07, 784, 784, 0.16, 0.45]])
	_streams["upgrade"] = _build([
		[0.0, 523, 523, 0.2, 0.4], [0.07, 659, 659, 0.2, 0.4],
		[0.14, 784, 784, 0.2, 0.4], [0.21, 1047, 1047, 0.3, 0.4]])
	_streams["reveal"] = _build([
		[0.0, 400, 1300, 0.3, 0.40], [0.0, 404, 1313, 0.3, 0.30], [0.22, 1568, 1568, 0.3, 0.35]])
	_streams["discover"] = _build([[0.0, 988, 988, 0.12, 0.4], [0.09, 1319, 1319, 0.25, 0.4]])

	# Mehrere Abspieler, damit sich schnelle Klicks nicht gegenseitig abschneiden.
	for i: int in 8:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	set_volume(volume, false)


## Spielt einen Ton. "pitch_variation" verstimmt ihn zufällig ein wenig, damit
## viele gleiche Klicks hintereinander nicht eintönig klingen.
func play(sound: String, pitch_variation: float = 0.0) -> void:
	if volume <= 0.0 or not _streams.has(sound):
		return
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[sound]
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func set_volume(value: float, save: bool = true) -> void:
	volume = clampf(value, 0.0, 1.0)
	for player: AudioStreamPlayer in _players:
		player.volume_db = linear_to_db(maxf(volume, 0.0001))
	if save:
		var file: FileAccess = FileAccess.open(_options_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({ "volume": volume }))


func _load_options() -> void:
	if not FileAccess.file_exists(_options_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_options_path))
	if typeof(data) == TYPE_DICTIONARY:
		volume = clampf(float(data.get("volume", volume)), 0.0, 1.0)


# --- Tonerzeugung -------------------------------------------------------------

## Mischt alle Teiltöne zusammen und verpackt das Ergebnis als abspielbaren Ton.
func _build(notes: Array) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for note: Array in notes:
		samples = _add_note(samples, note[0], note[1], note[2], note[3], note[4])

	# Von Kommazahlen (-1 bis 1) in das Dateiformat: 16-Bit-Ganzzahlen.
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## Ein Teilton: eine Sinuswelle, deren Höhe von "from_hz" nach "to_hz" gleitet.
## Er setzt in 4 Millisekunden ein (sonst knackt es) und klingt dann rasch ab.
## Ein leiser Oberton (doppelte Frequenz) macht ihn etwas heller.
func _add_note(samples: PackedFloat32Array, start: float, from_hz: float, to_hz: float,
		seconds: float, level: float) -> PackedFloat32Array:
	var first: int = int(start * RATE)
	var count: int = int(seconds * RATE)
	if samples.size() < first + count:
		samples.resize(first + count)
	var phase: float = 0.0
	for i: int in count:
		var t: float = float(i) / count
		phase += TAU * lerpf(from_hz, to_hz, t) / RATE
		var envelope: float = minf(1.0, i / (0.004 * RATE)) * exp(-5.0 * t)
		samples[first + i] += (sin(phase) + 0.3 * sin(2.0 * phase)) * envelope * level
	return samples
