class_name Menus
extends CanvasLayer
## All menus, built in code: home, garage, pause, game-over, settings,
## leaderboard (local runs) and quests (real, tracked, claimable).
## Fonts load from res://assets/fonts/ with default-font fallback.
## Settings + garage + quests persist in user://troadster_save.cfg.

signal drive_pressed
signal resume_pressed
signal restart_pressed
signal back_to_menu
signal skin_changed

const SAVE_PATH := "user://troadster_save.cfg"
const FONT_RUSSO := "res://assets/fonts/RussoOne-Regular.ttf"
const FONT_ARCHIVO := "res://assets/fonts/ArchivoBlack-Regular.ttf"
const FONT_NUNITO := "res://assets/fonts/Nunito-Regular.ttf"

const SKINS := [
	{"id": "white", "name": "WHITE PICKUP", "price": 0, "paint": Color(0.96, 0.96, 0.97), "desc": "The reel hero. Clean, angular, stock."},
	{"id": "sunset", "name": "SUNSET SPORTS", "price": 5000, "paint": Color(0.95, 0.45, 0.15), "desc": "Sunset-orange paint, dark trim."},
	{"id": "neon", "name": "NIGHT NEON", "price": 15000, "paint": Color(0.12, 0.10, 0.22), "desc": "Midnight body, neon underglow look."},
]
const PAINTS := [
	Color(0.96, 0.96, 0.97), Color(0.85, 0.10, 0.10), Color(0.10, 0.30, 0.85),
	Color(0.95, 0.65, 0.05), Color(0.10, 0.65, 0.30), Color(0.55, 0.20, 0.65),
]
const QUEST_DEFS := [
	{"id": "drive_1000", "name": "Coast Runner", "desc": "Drive 1,000 m in one run", "target": 1000, "reward": 200, "stat": "distance"},
	{"id": "score_10000", "name": "Ten Grand", "desc": "Score 10,000 points in one run", "target": 10000, "reward": 300, "stat": "score"},
	{"id": "coins_20", "name": "Coin Hound", "desc": "Collect 20 coins in one run", "target": 20, "reward": 150, "stat": "coins"},
]

var scoring: Scoring = null
var audio: AudioManager = null

# Settings (persisted, defaults per spec: controls Both).
var control_mode: String = "Both"
var tilt_sensitivity: float = 1.0
var reduce_shake: bool = false
var reduce_flash: bool = false

var _panels: Dictionary = {}
var _home_best: Label
var _home_coins: Label
var _garage_list: VBoxContainer
var _paint_row: HBoxContainer
var _go_title: Label
var _go_stats: Label
var _go_record: Label
var _leader_list: VBoxContainer
var _quest_list: VBoxContainer
var _settings_from: String = "home"

func _ready() -> void:
	layer = 20
	_load_settings()
	_build()

static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _russo() -> Font:
	return _load_font(FONT_RUSSO)

func _archivo() -> Font:
	return _load_font(FONT_ARCHIVO)

func _nunito() -> Font:
	return _load_font(FONT_NUNITO)

func _label(text: String, font: Font, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", maxi(3, size / 9))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _style_button(b: Button, bg: Color, font_size: int = 32) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.corner_radius_top_left = 16
	normal.corner_radius_top_right = 16
	normal.corner_radius_bottom_left = 16
	normal.corner_radius_bottom_right = 16
	normal.border_color = Color(1, 1, 1, 0.4)
	normal.set_border_width_all(2)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(minf(bg.r + 0.12, 1.0), minf(bg.g + 0.12, 1.0), minf(bg.b + 0.12, 1.0), bg.a)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(bg.r * 0.8, bg.g * 0.8, bg.b * 0.8, bg.a)
	b.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.25, 0.25, 0.28, 0.85)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
	var russo: Font = _russo()
	if russo != null:
		b.add_theme_font_override("font", russo)
	b.add_theme_font_size_override("font_size", font_size)

func _button(text: String, bg: Color, font_size: int = 32) -> Button:
	var b := Button.new()
	b.text = text
	_style_button(b, bg, font_size)
	return b

func _panel(name: String, dim: Color = Color(0.04, 0.03, 0.09, 0.88)) -> Control:
	var p := Control.new()
	p.name = name
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.visible = false
	var bg := ColorRect.new()
	bg.color = dim
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.add_child(bg)
	add_child(p)
	_panels[name] = p
	return p

func _center_vbox(parent: Control, width: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-width * 0.5, -700)
	v.size = Vector2(width, 1400)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	parent.add_child(v)
	return v

func _build() -> void:
	_build_home()
	_build_garage()
	_build_pause()
	_build_game_over()
	_build_settings()
	_build_leaderboard()
	_build_quests()
	show_home()

# ------------------------------------------------------------------- home

func _build_home() -> void:
	var p: Control = _panel("home", Color(0.05, 0.03, 0.12, 0.72))
	var v: VBoxContainer = _center_vbox(p, 760)
	var logo: Label = _label("T ROADSTER", _archivo(), 108, Color(1.0, 0.78, 0.2))
	v.add_child(logo)
	var sub: Label = _label("COASTAL SUNSET • STUNT DRIVER", _russo(), 28, Color(0.65, 0.85, 1.0))
	v.add_child(sub)
	var callsign: Label = _label("MUHAMMAD AHMED", _nunito(), 30, Color(1, 1, 1, 0.9))
	v.add_child(callsign)
	_home_best = _label("BEST  0  •  0 m", _russo(), 30, Color.WHITE)
	v.add_child(_home_best)
	_home_coins = _label("COINS  0", _russo(), 30, Color(1.0, 0.78, 0.2))
	v.add_child(_home_coins)
	var drive: Button = _button("DRIVE", Color(1.0, 0.55, 0.05), 54)
	drive.custom_minimum_size = Vector2(560, 120)
	drive.pressed.connect(func() -> void: drive_pressed.emit())
	v.add_child(drive)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	var garage_btn: Button = _button("GARAGE", Color(0.12, 0.35, 0.75), 28)
	garage_btn.custom_minimum_size = Vector2(230, 84)
	garage_btn.pressed.connect(show_garage)
	row.add_child(garage_btn)
	var lb_btn: Button = _button("LEADERBOARD", Color(0.12, 0.35, 0.75), 28)
	lb_btn.custom_minimum_size = Vector2(230, 84)
	lb_btn.pressed.connect(show_leaderboard)
	row.add_child(lb_btn)
	var q_btn: Button = _button("QUESTS", Color(0.12, 0.35, 0.75), 28)
	q_btn.custom_minimum_size = Vector2(230, 84)
	q_btn.pressed.connect(show_quests)
	row.add_child(q_btn)
	var settings_btn: Button = _button("SETTINGS", Color(0.25, 0.25, 0.3), 28)
	settings_btn.custom_minimum_size = Vector2(360, 72)
	settings_btn.pressed.connect(func() -> void: show_settings("home"))
	v.add_child(settings_btn)
	var hint: Label = _label("Swipe or tilt to steer • Hold HOP to fly • R to roll • W to flip", _nunito(), 24, Color(1, 1, 1, 0.6))
	v.add_child(hint)

# ------------------------------------------------------------------- garage

func _build_garage() -> void:
	var p: Control = _panel("garage")
	var v: VBoxContainer = _center_vbox(p, 820)
	v.add_child(_label("GARAGE", _archivo(), 72, Color(1.0, 0.78, 0.2)))
	v.add_child(_label("Skins and paints are cosmetic only — no speed, no AIR, no advantage.", _nunito(), 24, Color(1, 1, 1, 0.7)))
	_garage_list = VBoxContainer.new()
	_garage_list.add_theme_constant_override("separation", 14)
	v.add_child(_garage_list)
	v.add_child(_label("PAINT", _russo(), 28, Color.WHITE))
	_paint_row = HBoxContainer.new()
	_paint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_paint_row.add_theme_constant_override("separation", 16)
	v.add_child(_paint_row)
	var back: Button = _button("BACK", Color(0.25, 0.25, 0.3), 30)
	back.custom_minimum_size = Vector2(300, 80)
	back.pressed.connect(show_home)
	v.add_child(back)
	_refresh_garage()

func _refresh_garage() -> void:
	if _garage_list == null:
		return
	for child in _garage_list.get_children():
		child.queue_free()
	for child in _paint_row.get_children():
		child.queue_free()
	if scoring == null:
		return
	for skin in SKINS:
		var owned: bool = scoring.owned_skins.has(skin["id"])
		var selected: bool = scoring.selected_skin == skin["id"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var swatch := ColorRect.new()
		swatch.color = skin["paint"]
		swatch.custom_minimum_size = Vector2(64, 64)
		row.add_child(swatch)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title: Label = _label(skin["name"], _russo(), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		info.add_child(title)
		var desc: Label = _label(skin["desc"], _nunito(), 22, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
		info.add_child(desc)
		row.add_child(info)
		var btn: Button
		if selected:
			btn = _button("SELECTED", Color(0.15, 0.55, 0.25), 24)
			btn.disabled = true
		elif owned:
			btn = _button("SELECT", Color(0.12, 0.35, 0.75), 24)
			btn.pressed.connect(_select_skin.bind(skin["id"]))
		else:
			btn = _button("BUY  %d" % int(skin["price"]), Color(1.0, 0.55, 0.05), 24)
			btn.disabled = scoring.total_coins < int(skin["price"])
			btn.pressed.connect(_buy_skin.bind(skin["id"], int(skin["price"])))
		btn.custom_minimum_size = Vector2(210, 64)
		row.add_child(btn)
		_garage_list.add_child(row)
	for paint in PAINTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(72, 72)
		var sb := StyleBoxFlat.new()
		sb.bg_color = paint
		sb.corner_radius_top_left = 12
		sb.corner_radius_top_right = 12
		sb.corner_radius_bottom_left = 12
		sb.corner_radius_bottom_right = 12
		sb.border_color = Color(1, 1, 1, 0.9) if scoring.selected_paint == paint else Color(1, 1, 1, 0.25)
		sb.set_border_width_all(3 if scoring.selected_paint == paint else 1)
		b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(_select_paint.bind(paint))
		_paint_row.add_child(b)

func _select_skin(id: String) -> void:
	if scoring == null:
		return
	scoring.selected_skin = id
	for skin in SKINS:
		if skin["id"] == id:
			scoring.selected_paint = skin["paint"]
	scoring.save_bests()
	_refresh_garage()
	skin_changed.emit()
	if audio != null:
		audio.play_click()

func _buy_skin(id: String, price: int) -> void:
	if scoring == null or scoring.total_coins < price:
		return
	scoring.total_coins -= price
	scoring.owned_skins.append(id)
	scoring.selected_skin = id
	for skin in SKINS:
		if skin["id"] == id:
			scoring.selected_paint = skin["paint"]
	scoring.save_bests()
	_refresh_garage()
	skin_changed.emit()
	if audio != null:
		audio.play_fanfare()

func _select_paint(paint: Color) -> void:
	if scoring == null:
		return
	scoring.selected_paint = paint
	scoring.save_bests()
	_refresh_garage()
	skin_changed.emit()
	if audio != null:
		audio.play_click()

# ------------------------------------------------------------------- pause

func _build_pause() -> void:
	var p: Control = _panel("pause")
	var v: VBoxContainer = _center_vbox(p, 560)
	v.add_child(_label("PAUSED", _archivo(), 84, Color.WHITE))
	var resume: Button = _button("RESUME", Color(0.15, 0.55, 0.25), 40)
	resume.custom_minimum_size = Vector2(460, 100)
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	v.add_child(resume)
	var restart: Button = _button("RESTART", Color(0.12, 0.35, 0.75), 40)
	restart.custom_minimum_size = Vector2(460, 100)
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	v.add_child(restart)
	var settings_btn: Button = _button("SETTINGS", Color(0.25, 0.25, 0.3), 36)
	settings_btn.custom_minimum_size = Vector2(460, 88)
	settings_btn.pressed.connect(func() -> void: show_settings("pause"))
	v.add_child(settings_btn)
	var menu_btn: Button = _button("MENU", Color(0.25, 0.25, 0.3), 36)
	menu_btn.custom_minimum_size = Vector2(460, 88)
	menu_btn.pressed.connect(func() -> void: back_to_menu.emit())
	v.add_child(menu_btn)

# ------------------------------------------------------------------- game over

func _build_game_over() -> void:
	var p: Control = _panel("game_over")
	var v: VBoxContainer = _center_vbox(p, 760)
	_go_record = _label("", _russo(), 32, Color(1.0, 0.78, 0.2))
	v.add_child(_go_record)
	_go_title = _label("CRASHED", _archivo(), 96, Color(1.0, 0.25, 0.2))
	v.add_child(_go_title)
	_go_stats = _label("", _nunito(), 34, Color.WHITE)
	v.add_child(_go_stats)
	var again: Button = _button("DRIVE AGAIN", Color(1.0, 0.55, 0.05), 44)
	again.custom_minimum_size = Vector2(560, 110)
	again.pressed.connect(func() -> void: restart_pressed.emit())
	v.add_child(again)
	var menu_btn: Button = _button("MENU", Color(0.25, 0.25, 0.3), 36)
	menu_btn.custom_minimum_size = Vector2(460, 88)
	menu_btn.pressed.connect(func() -> void: back_to_menu.emit())
	v.add_child(menu_btn)

func show_game_over(stats: Dictionary) -> void:
	hide_all()
	_go_title.text = "CRASHED"
	_go_title.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	if bool(stats.get("is_record", false)):
		_go_record.text = "★  NEW RECORD  ★"
		_go_record.add_theme_color_override("font_color", Color(1.0, 0.78, 0.2))
		_go_title.text = "NEW RECORD"
		_go_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.2))
	else:
		_go_record.text = ""
	var lines: Array = [
		"SCORE   %s" % _format_int(int(stats.get("score", 0))),
		"DISTANCE   %d m" % int(stats.get("distance", 0)),
		"TIME   %d:%02d" % [int(stats.get("time", 0)) / 60, int(stats.get("time", 0)) % 60],
		"MAX COMBO   %d" % int(stats.get("max_combo", 0)),
		"RANK   #%d" % int(stats.get("rank", 99)),
		"COINS   +%d" % int(stats.get("coins", 0)),
	]
	_go_stats.text = "\n".join(lines)
	_panels["game_over"].visible = true

# ------------------------------------------------------------------- settings

func _build_settings() -> void:
	var p: Control = _panel("settings")
	var v: VBoxContainer = _center_vbox(p, 820)
	v.add_child(_label("SETTINGS", _archivo(), 72, Color.WHITE))
	v.add_child(_label("CONTROLS", _russo(), 30, Color(1.0, 0.78, 0.2)))
	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 14)
	v.add_child(mode_row)
	for mode in ["Swipe", "Tilt", "Both"]:
		var b: Button = _button(mode, Color(0.12, 0.35, 0.75) if control_mode == mode else Color(0.25, 0.25, 0.3), 26)
		b.custom_minimum_size = Vector2(200, 72)
		b.pressed.connect(_set_control_mode.bind(mode))
		mode_row.add_child(b)
	v.add_child(_label("TILT SENSITIVITY", _russo(), 26, Color.WHITE))
	var sens := HSlider.new()
	sens.min_value = 0.5
	sens.max_value = 2.0
	sens.step = 0.1
	sens.value = tilt_sensitivity
	sens.custom_minimum_size = Vector2(560, 40)
	sens.value_changed.connect(func(val: float) -> void: tilt_sensitivity = val; _save_settings())
	v.add_child(sens)
	var shake_btn: Button = _button(("REDUCE SHAKE: ON" if reduce_shake else "REDUCE SHAKE: OFF"), Color(0.25, 0.25, 0.3), 26)
	shake_btn.pressed.connect(func() -> void: reduce_shake = not reduce_shake; shake_btn.text = ("REDUCE SHAKE: ON" if reduce_shake else "REDUCE SHAKE: OFF"); _save_settings())
	v.add_child(shake_btn)
	var flash_btn: Button = _button(("REDUCE FLASH: ON" if reduce_flash else "REDUCE FLASH: OFF"), Color(0.25, 0.25, 0.3), 26)
	flash_btn.pressed.connect(func() -> void: reduce_flash = not reduce_flash; flash_btn.text = ("REDUCE FLASH: ON" if reduce_flash else "REDUCE FLASH: OFF"); _save_settings())
	v.add_child(flash_btn)
	v.add_child(_label("SOUND", _russo(), 26, Color.WHITE))
	var sfx := HSlider.new()
	sfx.min_value = 0.0
	sfx.max_value = 1.0
	sfx.step = 0.05
	sfx.value = 0.9 if audio == null else audio.sfx_volume
	sfx.custom_minimum_size = Vector2(560, 40)
	sfx.value_changed.connect(func(val: float) -> void: if audio != null: audio.set_sfx_volume(val))
	v.add_child(sfx)
	v.add_child(_label("MUSIC", _russo(), 26, Color.WHITE))
	var mus := HSlider.new()
	mus.min_value = 0.0
	mus.max_value = 1.0
	mus.step = 0.05
	mus.value = 0.7 if audio == null else audio.music_volume
	mus.custom_minimum_size = Vector2(560, 40)
	mus.value_changed.connect(func(val: float) -> void: if audio != null: audio.set_music_volume(val))
	v.add_child(mus)
	var back: Button = _button("BACK", Color(0.15, 0.55, 0.25), 30)
	back.custom_minimum_size = Vector2(360, 84)
	back.pressed.connect(func() -> void: show_home() if _settings_from == "home" else show_pause())
	v.add_child(back)

func _set_control_mode(mode: String) -> void:
	control_mode = mode
	_save_settings()
	# Rebuild the settings panel so the active mode button highlights.
	_panels["settings"].queue_free()
	_panels.erase("settings")
	_build_settings()
	_panels["settings"].visible = true
	if audio != null:
		audio.play_click()

# ------------------------------------------------------------------- leaderboard

func _build_leaderboard() -> void:
	var p: Control = _panel("leaderboard")
	var v: VBoxContainer = _center_vbox(p, 820)
	v.add_child(_label("LEADERBOARD", _archivo(), 64, Color(1.0, 0.78, 0.2)))
	v.add_child(_label("Local runs on this phone — no server, no account.", _nunito(), 24, Color(1, 1, 1, 0.7)))
	_leader_list = VBoxContainer.new()
	_leader_list.add_theme_constant_override("separation", 10)
	v.add_child(_leader_list)
	var back: Button = _button("BACK", Color(0.25, 0.25, 0.3), 30)
	back.custom_minimum_size = Vector2(300, 80)
	back.pressed.connect(show_home)
	v.add_child(back)

func _refresh_leaderboard() -> void:
	if _leader_list == null:
		return
	for child in _leader_list.get_children():
		child.queue_free()
	var runs: Array = _load_runs()
	if runs.is_empty():
		_leader_list.add_child(_label("No runs yet — hit DRIVE and set the first record.", _nunito(), 26, Color(1, 1, 1, 0.7)))
		return
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("score", 0)) > int(b.get("score", 0)))
	for i in range(mini(runs.size(), 5)):
		var r: Dictionary = runs[i]
		var line: String = "#%d    %s pts    %d m    %d:%02d" % [i + 1, _format_int(int(r.get("score", 0))), int(r.get("distance", 0)), int(r.get("time", 0)) / 60, int(r.get("time", 0)) % 60]
		_leader_list.add_child(_label(line, _russo(), 28, Color(1.0, 0.78, 0.2) if i == 0 else Color.WHITE))

func _load_runs() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return []
	var runs: Variant = cfg.get_value("runs", "top", [])
	return runs if runs is Array else []

func record_run(stats: Dictionary) -> void:
	var runs: Array = _load_runs()
	runs.append({"score": int(stats.get("score", 0)), "distance": int(stats.get("distance", 0)), "time": int(stats.get("time", 0))})
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("score", 0)) > int(b.get("score", 0)))
	while runs.size() > 10:
		runs.pop_back()
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("runs", "top", runs)
	cfg.save(SAVE_PATH)

# ------------------------------------------------------------------- quests

func _build_quests() -> void:
	var p: Control = _panel("quests")
	var v: VBoxContainer = _center_vbox(p, 820)
	v.add_child(_label("QUESTS", _archivo(), 72, Color(1.0, 0.78, 0.2)))
	_quest_list = VBoxContainer.new()
	_quest_list.add_theme_constant_override("separation", 14)
	v.add_child(_quest_list)
	var back: Button = _button("BACK", Color(0.25, 0.25, 0.3), 30)
	back.custom_minimum_size = Vector2(300, 80)
	back.pressed.connect(show_home)
	v.add_child(back)

func _refresh_quests() -> void:
	if _quest_list == null:
		return
	for child in _quest_list.get_children():
		child.queue_free()
	var progress: Dictionary = _load_quest_progress()
	for q in QUEST_DEFS:
		var done: int = int(progress.get(q["id"] + "_best", 0))
		var claimed: bool = bool(progress.get(q["id"] + "_claimed", false))
		var row := VBoxContainer.new()
		var title: Label = _label("%s — %s" % [q["name"], q["desc"]], _russo(), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		row.add_child(title)
		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 12)
		var bar_wrap := Control.new()
		bar_wrap.custom_minimum_size = Vector2(420, 18)
		var bar_bg := ColorRect.new()
		bar_bg.color = Color(1, 1, 1, 0.18)
		bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar_wrap.add_child(bar_bg)
		var bar := ColorRect.new()
		bar.color = Color(1.0, 0.78, 0.2)
		bar.position = Vector2(0, 0)
		bar.size = Vector2(420.0 * clampf(float(done) / float(q["target"]), 0.0, 1.0), 18)
		bar_wrap.add_child(bar)
		bar_row.add_child(bar_wrap)
		var pct: Label = _label("%d / %d" % [done, int(q["target"])], _nunito(), 24, Color.WHITE)
		bar_row.add_child(pct)
		row.add_child(bar_row)
		if done >= int(q["target"]) and not claimed:
			var claim: Button = _button("CLAIM  +%d COINS" % int(q["reward"]), Color(1.0, 0.55, 0.05), 24)
			claim.custom_minimum_size = Vector2(360, 64)
			claim.pressed.connect(_claim_quest.bind(q["id"], int(q["reward"])))
			row.add_child(claim)
		elif claimed:
			row.add_child(_label("CLAIMED  +%d COINS" % int(q["reward"]), _nunito(), 24, Color(0.4, 0.9, 0.4), HORIZONTAL_ALIGNMENT_LEFT))
		else:
			row.add_child(_label("REWARD  +%d COINS" % int(q["reward"]), _nunito(), 24, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT))
		_quest_list.add_child(row)

func _load_quest_progress() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}
	var d: Dictionary = {}
	for q in QUEST_DEFS:
		d[q["id"] + "_best"] = int(cfg.get_value("quests", q["id"] + "_best", 0))
		d[q["id"] + "_claimed"] = bool(cfg.get_value("quests", q["id"] + "_claimed", false))
	return d

func update_quests(stats: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	for q in QUEST_DEFS:
		var key: String = q["id"] + "_best"
		var prev: int = int(cfg.get_value("quests", key, 0))
		var cur: int = int(stats.get(q["stat"], 0))
		if cur > prev:
			cfg.set_value("quests", key, cur)
	cfg.save(SAVE_PATH)

func _claim_quest(id: String, reward: int) -> void:
	if scoring == null:
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	if bool(cfg.get_value("quests", id + "_claimed", false)):
		return
	cfg.set_value("quests", id + "_claimed", true)
	cfg.save(SAVE_PATH)
	scoring.total_coins += reward
	scoring.save_bests()
	_refresh_quests()
	_refresh_home()
	if audio != null:
		audio.play_fanfare()

# ------------------------------------------------------------------- show / hide

func hide_all() -> void:
	for p in _panels.values():
		p.visible = false

func _refresh_home() -> void:
	if scoring != null:
		_home_best.text = "BEST  %s  •  %d m" % [_format_int(scoring.best_score), scoring.best_distance]
		_home_coins.text = "COINS  %s" % _format_int(scoring.total_coins)

func show_home() -> void:
	hide_all()
	_refresh_home()
	_panels["home"].visible = true

func show_garage() -> void:
	hide_all()
	_refresh_garage()
	_panels["garage"].visible = true

func show_pause() -> void:
	hide_all()
	_panels["pause"].visible = true

func show_settings(from: String) -> void:
	_settings_from = from
	hide_all()
	_panels["settings"].visible = true

func show_leaderboard() -> void:
	hide_all()
	_refresh_leaderboard()
	_panels["leaderboard"].visible = true

func show_quests() -> void:
	hide_all()
	_refresh_quests()
	_panels["quests"].visible = true

# ------------------------------------------------------------------- settings IO

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	control_mode = String(cfg.get_value("settings", "control_mode", "Both"))
	tilt_sensitivity = float(cfg.get_value("settings", "tilt_sensitivity", 1.0))
	reduce_shake = bool(cfg.get_value("settings", "reduce_shake", false))
	reduce_flash = bool(cfg.get_value("settings", "reduce_flash", false))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("settings", "control_mode", control_mode)
	cfg.set_value("settings", "tilt_sensitivity", tilt_sensitivity)
	cfg.set_value("settings", "reduce_shake", reduce_shake)
	cfg.set_value("settings", "reduce_flash", reduce_flash)
	cfg.save(SAVE_PATH)

func _format_int(v: int) -> String:
	var s: String = str(v)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3, 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
