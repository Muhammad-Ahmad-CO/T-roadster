class_name AudioManager
extends Node
## Audio: buses + SFX pool + engine loop + music, all built in code.
## Sounds are the ORIGINAL generated WAVs from the Flutter project
## (res://assets/sounds/*.wav) — reuse is allowed, nothing licensed.
## Music uses those same original loops (music_cruise / music_redline);
## there is no licensed track anywhere in this project.

const SOUND_PATH := "res://assets/sounds/"
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_ENGINE := "Engine"

var muted: bool = false
var music_volume: float = 0.7
var sfx_volume: float = 0.9

var _streams: Dictionary = {}
var _sfx_pool: Array = []
var _engine_player: AudioStreamPlayer = null
var _music_cruise: AudioStreamPlayer = null
var _music_redline: AudioStreamPlayer = null
var _siren_player: AudioStreamPlayer = null
var _combo_pitch_step: int = 0

func _ready() -> void:
	_setup_buses()
	_load_streams()
	_build_players()

func _setup_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_ENGINE]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus(AudioServer.get_bus_count())
			var idx: int = AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)
	_apply_volumes()

func _apply_volumes() -> void:
	_set_bus_volume(BUS_MUSIC, music_volume)
	_set_bus_volume(BUS_SFX, sfx_volume)
	_set_bus_volume(BUS_ENGINE, 0.8)

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))

func _load_streams() -> void:
	for fname in ["chime", "click", "coin", "crash", "engine", "fanfare", "flip",
			"go", "hop", "music_cruise", "music_redline", "pickup", "roll",
			"siren", "smash", "tick", "whoosh"]:
		var path: String = SOUND_PATH + fname + ".wav"
		if ResourceLoader.exists(path):
			_streams[fname] = load(path)

func _build_players() -> void:
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_sfx_pool.append(p)
	_engine_player = AudioStreamPlayer.new()
	_engine_player.bus = BUS_ENGINE
	if _streams.has("engine"):
		_engine_player.stream = _streams["engine"]
	add_child(_engine_player)
	_music_cruise = AudioStreamPlayer.new()
	_music_cruise.bus = BUS_MUSIC
	if _streams.has("music_cruise"):
		_music_cruise.stream = _streams["music_cruise"]
	add_child(_music_cruise)
	_music_redline = AudioStreamPlayer.new()
	_music_redline.bus = BUS_MUSIC
	if _streams.has("music_redline"):
		_music_redline.stream = _streams["music_redline"]
	add_child(_music_redline)
	_siren_player = AudioStreamPlayer.new()
	_siren_player.bus = BUS_SFX
	if _streams.has("siren"):
		_siren_player.stream = _streams["siren"]
	add_child(_siren_player)

func _play_on_pool(stream_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if muted or not _streams.has(stream_name):
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = _streams[stream_name]
			p.pitch_scale = pitch
			p.volume_db = volume_db
			p.play()
			return
	# Pool busy: steal the first player rather than dropping the sound.
	var p0: AudioStreamPlayer = _sfx_pool[0]
	p0.stream = _streams[stream_name]
	p0.pitch_scale = pitch
	p0.volume_db = volume_db
	p0.play()

# ------------------------------------------------------------------- SFX API

func play_click() -> void:
	_play_on_pool("click")

func play_hop() -> void:
	_play_on_pool("hop")
	_play_on_pool("whoosh", 1.0, -6.0)

func play_coin(combo: int) -> void:
	# Coin ding rises +1 semitone per combo step, resets on combo loss.
	_combo_pitch_step = combo
	var pitch: float = pow(2.0, float(combo % 12) / 12.0)
	_play_on_pool("coin", pitch)

func reset_coin_pitch() -> void:
	_combo_pitch_step = 0

func play_near_miss() -> void:
	_play_on_pool("whoosh", 1.25)

func play_whoosh() -> void:
	_play_on_pool("whoosh")

func play_smash() -> void:
	_play_on_pool("smash")
	_play_on_pool("crash", 1.0, -8.0)

func play_flip() -> void:
	_play_on_pool("flip")

func play_roll() -> void:
	_play_on_pool("roll")

func play_pickup() -> void:
	_play_on_pool("pickup")

func play_chime() -> void:
	_play_on_pool("chime")

func play_tick() -> void:
	_play_on_pool("tick")

func play_go() -> void:
	_play_on_pool("go")

func play_crash() -> void:
	_play_on_pool("crash")

func play_fanfare() -> void:
	_play_on_pool("fanfare")

# ------------------------------------------------------------------- loops

func start_engine() -> void:
	if _engine_player != null and _engine_player.stream != null and not _engine_player.playing:
		_engine_player.play()

func stop_engine() -> void:
	if _engine_player != null:
		_engine_player.stop()

## speed_frac 0..1 across 26..52 m/s; nitro pushes pitch + volume.
func set_engine(speed_frac: float, nitro: bool) -> void:
	if _engine_player == null or _engine_player.stream == null:
		return
	var target: float = 0.75 + speed_frac * 0.9 + (0.25 if nitro else 0.0)
	_engine_player.pitch_scale = lerpf(_engine_player.pitch_scale, target, 0.08)
	_engine_player.volume_db = -14.0 + speed_frac * 6.0 + (3.0 if nitro else 0.0)

func start_music() -> void:
	if _music_cruise != null and _music_cruise.stream != null and not _music_cruise.playing:
		_music_cruise.play()
	if _music_redline != null and _music_redline.stream != null and not _music_redline.playing:
		_music_redline.volume_db = -80.0
		_music_redline.play()

## Cruise loop normally; redline loop fades in on nitro / police chase.
func set_music_mood(intense: bool) -> void:
	if _music_cruise == null or _music_redline == null:
		return
	_music_cruise.volume_db = -6.0 if not intense else -14.0
	_music_redline.volume_db = -80.0 if not intense else -8.0

func stop_music() -> void:
	if _music_cruise != null:
		_music_cruise.stop()
	if _music_redline != null:
		_music_redline.stop()

func start_siren() -> void:
	if _siren_player != null and _siren_player.stream != null and not _siren_player.playing:
		_siren_player.volume_db = -10.0
		_siren_player.play()

func stop_siren() -> void:
	if _siren_player != null:
		_siren_player.stop()

# ------------------------------------------------------------------- settings

func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), m)

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_set_bus_volume(BUS_MUSIC, music_volume)

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_set_bus_volume(BUS_SFX, sfx_volume)
