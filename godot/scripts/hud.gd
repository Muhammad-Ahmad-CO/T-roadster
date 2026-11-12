class_name HUD
extends CanvasLayer
## In-game HUD, built entirely in code (no .tscn widgets to drift).
## Layout (1080x1920 portrait): big score top-centre, DIST / TIME / STUNT xm
## under it, gold combo drain bar, AIR bar top-left, coins + pause top-right,
## speed bottom-left, touch buttons bottom-right, callouts centre.
## Fonts load from res://assets/fonts/ with a clean fallback to the default
## font if a file is ever missing — the HUD never breaks on a font.

signal pause_pressed
signal hop_pressed
signal hop_released
signal flip_pressed
signal roll_pressed
signal boost_pressed

const FONT_RUSSO := "res://assets/fonts/RussoOne-Regular.ttf"
const FONT_ARCHIVO := "res://assets/fonts/ArchivoBlack-Regular.ttf"
const FONT_NUNITO := "res://assets/fonts/Nunito-Regular.ttf"

var _score_label: Label
var _dist_label: Label
var _time_label: Label
var _mult_label: Label
var _combo_bar: ColorRect
var _combo_bar_bg: ColorRect
var _air_bar: ColorRect
var _air_bar_bg: ColorRect
var _air_label: Label
var _coins_label: Label
var _speed_label: Label
var _status_label: Label
var _countdown_label: Label
var _intro_title: Label
var _intro_subtitle: Label
var _callout_layer: Control
var _callouts: Dictionary = {} # id -> Label
var _callout_next_id: int = 1
var _hop_button: Button
var _flip_button: Button
var _roll_button: Button
var _boost_button: Button
var _root: Control
var _last_score: int = -1

static func load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f: Font = load(path)
		return f
	return null

func _ready() -> void:
	layer = 10
	_build()

func _font_russo() -> Font:
	return load_font(FONT_RUSSO)

func _font_archivo() -> Font:
	return load_font(FONT_ARCHIVO)

func _font_nunito() -> Font:
	return load_font(FONT_NUNITO)

func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	return l

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var russo: Font = _font_russo()
	var nunito: Font = _font_nunito()
	var archivo: Font = _font_archivo()
	# --- score, top-centre ---
	_score_label = _label("0", russo, 76, Color.WHITE)
	_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_label.position = Vector2(-300, 56)
	_score_label.size = Vector2(600, 100)
	_root.add_child(_score_label)
	# DIST / TIME / STUNT xm row under the score.
	var sub := HBoxContainer.new()
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-320, 158)
	sub.size = Vector2(640, 44)
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_theme_constant_override("separation", 28)
	_root.add_child(sub)
	_dist_label = _label("0 m", nunito, 30, Color(1, 1, 1, 0.92))
	sub.add_child(_dist_label)
	_time_label = _label("0:00", nunito, 30, Color(1, 1, 1, 0.92))
	sub.add_child(_time_label)
	_mult_label = _label("STUNT x1", russo, 30, Color(1.0, 0.78, 0.2))
	sub.add_child(_mult_label)
	# Combo drain bar (gold, drains over the 4 s window).
	_combo_bar_bg = ColorRect.new()
	_combo_bar_bg.color = Color(1, 1, 1, 0.18)
	_combo_bar_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_combo_bar_bg.position = Vector2(-210, 208)
	_combo_bar_bg.size = Vector2(420, 8)
	_root.add_child(_combo_bar_bg)
	_combo_bar = ColorRect.new()
	_combo_bar.color = Color(1.0, 0.78, 0.2)
	_combo_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_combo_bar.position = Vector2(-210, 208)
	_combo_bar.size = Vector2(420, 8)
	_root.add_child(_combo_bar)
	# Active pickup status (ROCKET / STARMAN) under the combo bar.
	_status_label = _label("", russo, 30, Color(1.0, 0.55, 0.15))
	_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_label.position = Vector2(-300, 226)
	_status_label.size = Vector2(600, 44)
	_root.add_child(_status_label)
	# --- AIR bar, top-left ---
	var air_title: Label = _label("AIR", russo, 26, Color(0.55, 0.85, 1.0))
	air_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	air_title.position = Vector2(36, 56)
	air_title.size = Vector2(200, 34)
	_root.add_child(air_title)
	_air_bar_bg = ColorRect.new()
	_air_bar_bg.color = Color(1, 1, 1, 0.18)
	_air_bar_bg.position = Vector2(36, 94)
	_air_bar_bg.size = Vector2(260, 22)
	_root.add_child(_air_bar_bg)
	_air_bar = ColorRect.new()
	_air_bar.color = Color(0.25, 0.75, 1.0)
	_air_bar.position = Vector2(36, 94)
	_air_bar.size = Vector2(260, 22)
	_root.add_child(_air_bar)
	_air_label = _label("600 L", nunito, 26, Color.WHITE)
	_air_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_air_label.position = Vector2(36, 122)
	_air_label.size = Vector2(200, 34)
	_root.add_child(_air_label)
	# --- coins + pause, top-right ---
	_coins_label = _label("COINS 0", russo, 28, Color(1.0, 0.78, 0.2))
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_coins_label.position = Vector2(-316, 56)
	_coins_label.size = Vector2(280, 40)
	_root.add_child(_coins_label)
	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(-116, 104)
	pause_btn.size = Vector2(80, 80)
	_style_button(pause_btn, Color(0, 0, 0, 0.35), 40)
	if russo != null:
		pause_btn.add_theme_font_override("font", russo)
	pause_btn.add_theme_font_size_override("font_size", 30)
	pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	_root.add_child(pause_btn)
	# --- speed, bottom-left ---
	_speed_label = _label("0 km/h", russo, 44, Color.WHITE)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_speed_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_speed_label.position = Vector2(36, -120)
	_speed_label.size = Vector2(320, 60)
	_root.add_child(_speed_label)
	var speed_hint: Label = _label("NITRO: SHIFT / BOOST", nunito, 22, Color(1, 1, 1, 0.6))
	speed_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	speed_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	speed_hint.position = Vector2(36, -64)
	speed_hint.size = Vector2(340, 30)
	_root.add_child(speed_hint)
	# --- callouts, centre ---
	_callout_layer = Control.new()
	_callout_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_callout_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_callout_layer)
	# --- countdown, centre ---
	_countdown_label = _label("", archivo, 190, Color.WHITE)
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.position = Vector2(-300, -160)
	_countdown_label.size = Vector2(600, 320)
	_countdown_label.visible = false
	_root.add_child(_countdown_label)
	# --- TEST SITE intro banner (SPEC §2.5: "TEST SITE / Rocket test
	# grounds"). First run only; hidden by default, shown by main during
	# the intro countdown + ramp approach, hidden at the launch.
	_intro_title = _label("TEST SITE", archivo, 72, Color(1.0, 0.78, 0.2))
	_intro_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_intro_title.position = Vector2(-300, 300)
	_intro_title.size = Vector2(600, 90)
	_intro_title.visible = false
	_root.add_child(_intro_title)
	_intro_subtitle = _label("ROCKET TEST GROUNDS", russo, 30, Color(0.65, 0.85, 1.0))
	_intro_subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_intro_subtitle.position = Vector2(-300, 392)
	_intro_subtitle.size = Vector2(600, 44)
	_intro_subtitle.visible = false
	_root.add_child(_intro_subtitle)
	# --- touch buttons, bottom-right ---
	_boost_button = _make_touch_button("BOOST", Vector2(-316, -420), Vector2(140, 84), Color(1.0, 0.55, 0.1, 0.75))
	_boost_button.pressed.connect(func() -> void: boost_pressed.emit())
	_flip_button = _make_touch_button("FLIP", Vector2(-316, -316), Vector2(140, 84), Color(1.0, 0.78, 0.2, 0.45))
	_flip_button.pressed.connect(func() -> void: flip_pressed.emit())
	_roll_button = _make_touch_button("ROLL", Vector2(-160, -316), Vector2(140, 84), Color(1.0, 0.78, 0.2, 0.45))
	_roll_button.pressed.connect(func() -> void: roll_pressed.emit())
	_hop_button = _make_touch_button("HOP", Vector2(-316, -196), Vector2(280, 140), Color(0.25, 0.75, 1.0, 0.75))
	_hop_button.button_down.connect(func() -> void: hop_pressed.emit())
	_hop_button.button_up.connect(func() -> void: hop_released.emit())

func _style_button(b: Button, bg: Color, radius: int) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.corner_radius_top_left = radius
	normal.corner_radius_top_right = radius
	normal.corner_radius_bottom_left = radius
	normal.corner_radius_bottom_right = radius
	normal.border_color = Color(1, 1, 1, 0.35)
	normal.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", normal)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(bg.r, bg.g, bg.b, minf(bg.a + 0.25, 1.0))
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color.WHITE)

func _make_touch_button(text: String, pos: Vector2, size: Vector2, bg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.position = pos
	b.size = size
	_style_button(b, bg, 18)
	var russo: Font = _font_russo()
	if russo != null:
		b.add_theme_font_override("font", russo)
	b.add_theme_font_size_override("font_size", 30)
	_root.add_child(b)
	return b

# ------------------------------------------------------------------ API

func set_score(v: int) -> void:
	_score_label.text = _format_int(v)
	if v != _last_score:
		_last_score = v
		_score_label.pivot_offset = _score_label.size * 0.5
		var tw: Tween = create_tween()
		_score_label.scale = Vector2(1.15, 1.15)
		tw.tween_property(_score_label, "scale", Vector2.ONE, 0.12)

func set_distance(v: int) -> void:
	_dist_label.text = "%d m" % v

func set_time(seconds: int) -> void:
	_time_label.text = "%d:%02d" % [seconds / 60, seconds % 60]

func set_multiplier(m: int) -> void:
	_mult_label.text = "STUNT x%d" % m
	_mult_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.2) if m <= 1 else Color(1.0, 0.62, 0.05))

func set_combo_frac(f: float) -> void:
	_combo_bar.size.x = 420.0 * clampf(f, 0.0, 1.0)
	_combo_bar.visible = f > 0.0
	_combo_bar_bg.visible = f > 0.0

func set_air(v: float, max_v: float) -> void:
	var frac: float = clampf(v / maxf(max_v, 1.0), 0.0, 1.0)
	_air_bar.size.x = 260.0 * frac
	_air_label.text = "%d L" % int(v)
	if v < 120.0:
		# Low AIR: red flash.
		var flash: bool = int(Time.get_ticks_msec() / 250) % 2 == 0
		_air_bar.color = Color(1.0, 0.15, 0.1) if flash else Color(1.0, 0.45, 0.2)
		_air_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	else:
		_air_bar.color = Color(0.25, 0.75, 1.0)
		_air_label.add_theme_color_override("font_color", Color.WHITE)

func set_coins(v: int) -> void:
	_coins_label.text = "COINS %s" % _format_int(v)

func set_speed(kmh: int) -> void:
	_speed_label.text = "%d km/h" % kmh

func set_status(text: String, color: Color = Color(1.0, 0.55, 0.15)) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)

func clear_status() -> void:
	_status_label.text = ""

func show_callout(text: String, color: Color = Color(1.0, 0.85, 0.3)) -> void:
	# Max 3 on screen: drop the oldest. The tween frees by numeric id —
	# never bind the Label itself (a freed bound Object breaks the tween).
	while _callouts.size() >= 3:
		var oldest_id: int = _callouts.keys()[0]
		_free_callout_id(oldest_id)
	var id: int = _callout_next_id
	_callout_next_id += 1
	var l: Label = _label(text, _font_archivo(), 54, color)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-400, -260 + _callouts.size() * 70)
	l.size = Vector2(800, 70)
	_callout_layer.add_child(l)
	_callouts[id] = l
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 130.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.25)
	tw.chain().tween_callback(_free_callout_id.bind(id))

func _free_callout_id(id: int) -> void:
	if not _callouts.has(id):
		return
	var l: Label = _callouts[id]
	_callouts.erase(id)
	if is_instance_valid(l):
		l.queue_free()

func _prune_callout(l: Label) -> void:
	for id in _callouts.keys():
		if _callouts[id] == l:
			_callouts.erase(id)
			return

func set_airborne(b: bool) -> void:
	# FLIP / ROLL go gold only while airborne; dimmed on the road.
	var gold := Color(1.0, 0.78, 0.2, 0.85 if b else 0.45)
	_style_button(_flip_button, gold, 18)
	_style_button(_roll_button, gold, 18)
	_flip_button.disabled = false
	_roll_button.disabled = false

func set_boost_ready(b: bool) -> void:
	var bg := Color(1.0, 0.55, 0.1, 0.85 if b else 0.35)
	_style_button(_boost_button, bg, 18)

func show_countdown(text: String) -> void:
	_countdown_label.text = text
	_countdown_label.visible = true
	_countdown_label.pivot_offset = _countdown_label.size * 0.5
	_countdown_label.scale = Vector2(1.6, 1.6)
	_countdown_label.modulate.a = 1.0
	var tw: Tween = create_tween()
	tw.tween_property(_countdown_label, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_countdown() -> void:
	_countdown_label.visible = false

func show_test_site_banner() -> void:
	_intro_title.visible = true
	_intro_subtitle.visible = true

func hide_test_site_banner() -> void:
	_intro_title.visible = false
	_intro_subtitle.visible = false

func set_touch_visible(v: bool) -> void:
	for b in [_hop_button, _flip_button, _roll_button, _boost_button]:
		b.visible = v

func set_in_game(v: bool) -> void:
	_root.visible = v

func _format_int(v: int) -> String:
	var s: String = str(v)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3, 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
