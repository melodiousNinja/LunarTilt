extends Node
## Zero-asset sound effects: tiny PCM synths baked once at runtime into
## AudioStreamWav clips and played through one polyphonic stream. Keeps the
## APK small (no audio files) while giving every action a tactile voice.

const RATE := 22050

var _player: AudioStreamPlayer
var _cache := {}


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 8
	_player.stream = poly
	add_child(_player)
	_player.play()


func play(name: String, pitch := 1.0, vol_db := 0.0) -> void:
	if _player == null:
		return
	if not _player.playing:
		_player.play()
	var stream: AudioStreamWAV = _cache.get(name)
	if stream == null:
		stream = _synth(name)
		_cache[name] = stream
	if stream == null:
		return
	var pb := _player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if pb != null:
		pb.play_stream(stream, 0.0, vol_db, pitch)


func _synth(name: String) -> AudioStreamWAV:
	var n := 0
	match name:
		"whoosh": n = int(RATE * 0.28)
		"score": n = int(RATE * 0.40)
		"pop": n = int(RATE * 0.09)
		"block": n = int(RATE * 0.22)
		"thud": n = int(RATE * 0.13)
		"gutter": n = int(RATE * 0.35)
		_: return null
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		var u := float(i) / float(n)
		var v := 0.0
		match name:
			"whoosh":
				v = (randf() * 2.0 - 1.0) * 0.55 * sin(PI * u) * (0.4 + 0.6 * u)
			"score":
				var env := exp(-3.2 * t)
				v = (sin(TAU * 880.0 * t) + 0.7 * sin(TAU * 1320.0 * t)) * 0.42 * env
			"pop":
				# Solid wood/resin ball knock (2026-09-08: the previous version
				# read as "plastic" - too much thin high-frequency noise, not
				# enough body). Modeled like a billiard-ball clack (8 Ball
				# Pool reference): a low-mid resonant BODY carries the
				# "solid" weight, a brief noise transient gives the attack,
				# and a touch of higher ring gives the knock its edge -
				# body dominates so it never reads as a hollow click.
				var body := (sin(TAU * 480.0 * t) * 0.5 + sin(TAU * 720.0 * t) * 0.35) * exp(-60.0 * t)
				var click := (randf() * 2.0 - 1.0) * 0.30 * exp(-450.0 * t)
				var ring := sin(TAU * 1400.0 * t) * 0.22 * exp(-80.0 * t)
				v = body + click + ring
			"block":
				v = signf(sin(TAU * 140.0 * t)) * 0.30 * exp(-9.0 * t)
			"thud":
				v = sin(TAU * 110.0 * t) * 0.9 * exp(-26.0 * t)
			"gutter":
				v = sin(TAU * (520.0 - 380.0 * u) * t) * 0.5 * exp(-5.0 * t)
		samples[i] = clampf(v, -1.0, 1.0)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(samples[i] * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav