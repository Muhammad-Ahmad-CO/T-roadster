class_name Scoring
extends RefCounted
## Scoring per SPEC §8 — calibrated to the reel run (1,420 m / 39 s / 25,681 pts).
## score = distance x 10 (FLAT, never multiplied) + (stunts + bonuses) x multiplier.
## multiplier = 1 + floor(combo / 3), capped x10. Combo timer 4 s.
## Starman doubles ALL points while active (pickup effect, not the multiplier).
## Bests / coins / skins persist in user://troadster_save.cfg, saved on crash.

signal score_changed(v: int)
signal multiplier_changed(m: int)
signal combo_lost
signal coins_changed(v: int)

const SAVE_PATH := "user://troadster_save.cfg"
const COMBO_WINDOW := 4.0
const DISTANCE_RATE := 10.0

## Base values (SPEC §8.2). Distance and police-survival points are NOT in here.
const BASE_VALUES := {
	"coin": 50,
	"air_coin": 50,
	"near_miss": 100,
	"hop_over": 150,
	"front_flip": 400,
	"barrel_roll": 500,
	"double_stunt": 1200,
	"perfect_landing": 150,
	"smash": 300,
	"ramp": 200,
}

var score: int = 0
var distance: float = 0.0
var time_s: float = 0.0
var combo: int = 0
var max_combo: int = 0
var coins_earned: int = 0
var coins_picked: int = 0
var starman_active: bool = false

var best_score: int = 0
var best_distance: int = 0
var total_coins: int = 0
var owned_skins: Array = ["white"]
var selected_skin: String = "white"
var selected_paint: Color = Color(0.96, 0.96, 0.97)
## TEST SITE first-run ramp intro (SPEC §2.5 + §3.4): true once the intro
## launch has played. False when the save is missing or corrupt, so a
## first-time player always gets the intro and a bad save never crashes.
var test_site_intro_played: bool = false

var _score_acc: float = 0.0
var _combo_timer: float = 0.0
var _last_score: int = -1
var _last_multiplier: int = -1

func _init() -> void:
	load_bests()

func get_multiplier() -> int:
	return mini(1 + combo / 3, 10)

func get_combo_frac() -> float:
	if _combo_timer <= 0.0:
		return 0.0
	return clampf(_combo_timer / COMBO_WINDOW, 0.0, 1.0)

func reset_run() -> void:
	score = 0
	distance = 0.0
	time_s = 0.0
	combo = 0
	max_combo = 0
	coins_earned = 0
	coins_picked = 0
	starman_active = false
	_score_acc = 0.0
	_combo_timer = 0.0
	_last_score = -1
	_last_multiplier = -1
	_emit_all()

func update(delta: float) -> void:
	time_s += delta
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_timer = 0.0
			combo = 0
			combo_lost.emit()
			_emit_all()

## Distance points: 10 per metre, FLAT. Starman still doubles (pickup effect).
func add_distance(metres: float) -> void:
	if metres <= 0.0:
		return
	distance += metres
	var gain: float = metres * DISTANCE_RATE
	if starman_active:
		gain *= 2.0
	_score_acc += gain
	_sync_score()

## A scoring action: bumps combo, refreshes the 4 s timer, applies the
## multiplier, returns the points actually gained. `kind` must be a key of
## BASE_VALUES, or pass an explicit base via add_bonus().
func add_stunt(kind: String) -> int:
	if not BASE_VALUES.has(kind):
		push_warning("Scoring.add_stunt: unknown kind '%s'" % kind)
		return 0
	return add_bonus(kind, int(BASE_VALUES[kind]))

func add_bonus(kind: String, base: int) -> int:
	combo += 1
	max_combo = maxi(max_combo, combo)
	_combo_timer = COMBO_WINDOW
	var m: int = get_multiplier()
	var gained: int = int(round(base * m * (2.0 if starman_active else 1.0)))
	_score_acc += gained
	_sync_score()
	multiplier_changed.emit(m)
	return gained

## Flat points: NO combo multiplier, NO combo bump, NO popup.
## (Police survival +25/s, escape +500.) Starman still doubles.
func add_flat(points: int) -> void:
	_score_acc += points * (2.0 if starman_active else 1.0)
	_sync_score()

func add_coins(n: int) -> void:
	coins_earned += n
	coins_changed.emit(coins_earned)

func on_coin_collected(is_air: bool) -> int:
	coins_picked += 1
	add_coins(25)
	return add_stunt("air_coin" if is_air else "coin")

func is_new_best() -> bool:
	return score > best_score

func end_run() -> Dictionary:
	var is_record: bool = score > best_score
	if score > best_score:
		best_score = score
	if int(distance) > best_distance:
		best_distance = int(distance)
	total_coins += coins_earned
	save_bests()
	# Local rank estimate: the reel run (25,681 pts) sat at #32.
	var rank: int = clampi(100 - int(score / 400.0), 1, 99)
	if is_record and score > 0:
		rank = 1
	return {
		"score": score,
		"distance": int(distance),
		"time": int(time_s),
		"max_combo": max_combo,
		"coins": coins_earned,
		"rank": rank,
		"is_record": is_record,
		"best_score": best_score,
		"best_distance": best_distance,
		"total_coins": total_coins,
	}

func _sync_score() -> void:
	score = int(_score_acc)
	if score != _last_score:
		_last_score = score
		score_changed.emit(score)
	var m: int = get_multiplier()
	if m != _last_multiplier:
		_last_multiplier = m
		multiplier_changed.emit(m)

func _emit_all() -> void:
	_sync_score()
	coins_changed.emit(coins_earned)

# ---------------------------------------------------------------- persistence

func load_bests() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_score = int(cfg.get_value("bests", "score", 0))
	best_distance = int(cfg.get_value("bests", "distance", 0))
	total_coins = int(cfg.get_value("bests", "coins", 0))
	owned_skins = cfg.get_value("garage", "owned_skins", ["white"])
	if not (owned_skins is Array) or owned_skins.is_empty():
		owned_skins = ["white"]
	selected_skin = String(cfg.get_value("garage", "skin", "white"))
	var paint_html: String = String(cfg.get_value("garage", "paint", "#F5F5F7"))
	selected_paint = Color.html(paint_html) if Color.html_is_valid(paint_html) else Color(0.96, 0.96, 0.97)
	# Only a real stored `true` counts — a corrupt or mistyped value
	# must never silently swallow the first-run intro.
	test_site_intro_played = cfg.get_value("progress", "test_site_intro_played", false) == true

## TEST SITE intro: mark the intro as played and persist immediately
## (same file, same load-first pattern as save_bests — the runs, quests
## and settings sections are preserved). Safe to call repeatedly.
func mark_test_site_intro_played() -> void:
	test_site_intro_played = true
	save_bests()

## Saved immediately on crash (called from end_run and from the garage).
func save_bests() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("bests", "score", best_score)
	cfg.set_value("bests", "distance", best_distance)
	cfg.set_value("bests", "coins", total_coins)
	cfg.set_value("garage", "owned_skins", owned_skins)
	cfg.set_value("garage", "skin", selected_skin)
	cfg.set_value("garage", "paint", "#" + selected_paint.to_html(false))
	cfg.set_value("progress", "test_site_intro_played", test_site_intro_played)
	cfg.save(SAVE_PATH)
