extends Node
## Short interface sounds, synthesised once at start so they need no assets:
## a wooden thunk for a new site, a tock as materials arrive, a two-note chime
## when a building opens, a coin clink at payday and a dull knock for an error.
## play() is safe to call often: each sound has a few voices, and repeats
## within MIN_GAP seconds are dropped so a busy village does not clatter.
const RATE := 22050
const VOICES := 3
const MIN_GAP := 0.06
## Volume of each sound, in dB.
const LEVELS := {"place": -6.0, "deliver": -17.0, "complete": -8.0, "coin": -11.0, "error": -12.0}
var streams: Dictionary = {}
var players: Dictionary = {}
var last_played: Dictionary = {}
## Off in headless runs and tests that do not want sound.
var enabled := true

func _ready() -> void:
	streams = {
		"place": _render(0.22, _thunk),
		"deliver": _render(0.09, _tock),
		"complete": _render(0.75, _chime),
		"coin": _render(0.4, _coin),
		"error": _render(0.16, _knock),
	}
	for id in streams:
		var voices: Array = []
		for index in VOICES:
			var player := AudioStreamPlayer.new()
			player.stream = streams[id]
			player.volume_db = LEVELS[id]
			add_child(player)
			voices.append(player)
		players[id] = voices

func play(id: String, pitch: float = 1.0) -> void:
	if not enabled or not players.has(id):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last_played.get(id, -1.0)) < MIN_GAP:
		return
	last_played[id] = now
	for player in players[id]:
		if not player.playing:
			player.pitch_scale = pitch
			player.play()
			return

## Samples `seconds` of sound from `voice(t)`, a value in -1..1 at time t.
func _render(seconds: float, voice: Callable) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in count:
		var sample := clampf(float(voice.call(float(index) / RATE)), -1.0, 1.0)
		data.encode_s16(index * 2, int(sample * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream

## Deterministic noise, so every run sounds the same.
static func _noise(t: float) -> float:
	return fposmod(sin(t * 91234.567) * 43758.5453, 2.0) - 1.0

## A beam set down on packed earth: a falling low tone and a short scuff.
static func _thunk(t: float) -> float:
	var pitch := 70.0 + 70.0 * exp(-t * 30.0)
	var body := sin(TAU * pitch * t) * exp(-t * 18.0)
	var scuff := _noise(t) * exp(-t * 90.0) * 0.35
	return (body + scuff) * minf(1.0, t * 400.0)

## A log laid on the pile: a small, dry knock.
static func _tock(t: float) -> float:
	var pitch := 240.0 + 120.0 * exp(-t * 60.0)
	return (sin(TAU * pitch * t) + _noise(t) * 0.2) * exp(-t * 55.0) * minf(1.0, t * 600.0)

## Two bright bell notes, a fifth apart, the second a beat later.
static func _chime(t: float) -> float:
	var value := _bell(t, 659.25) * 0.55
	if t > 0.13:
		value += _bell(t - 0.13, 987.77) * 0.5
	return value

static func _bell(t: float, pitch: float) -> float:
	var tone := sin(TAU * pitch * t) + 0.35 * sin(TAU * pitch * 2.0 * t) + 0.12 * sin(TAU * pitch * 3.01 * t)
	return tone * exp(-t * 5.5) * minf(1.0, t * 300.0) * 0.6

## Two coins meeting: high partials, struck twice.
static func _coin(t: float) -> float:
	var value := _clink(t, 1.0)
	if t > 0.07:
		value += _clink(t - 0.07, 1.12) * 0.7
	return value

static func _clink(t: float, shift: float) -> float:
	var tone := sin(TAU * 2093.0 * shift * t) * 0.6 + sin(TAU * 3136.0 * shift * t) * 0.3 + sin(TAU * 4186.0 * shift * t) * 0.15
	return tone * exp(-t * 16.0) * minf(1.0, t * 900.0)

## Not allowed: a low, muffled double knock.
static func _knock(t: float) -> float:
	var local := t if t < 0.08 else t - 0.08
	var pitch := 150.0 if t < 0.08 else 120.0
	return sin(TAU * pitch * local) * exp(-local * 40.0) * minf(1.0, local * 500.0) * 0.8
