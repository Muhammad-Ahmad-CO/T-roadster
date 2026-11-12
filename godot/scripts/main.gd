extends Node3D
## T Roadster — root orchestrator.
## Owns the state machine (MENU -> COUNTDOWN -> PLAYING -> PAUSED -> CRASHED),
## the camera, the environment (sky / fog / sun from the biome palette),
## speed + distance, input (keyboard / swipe / tilt / touch buttons),
## pickup timers, police survival, and the crash sequence.
##
## WorldBuilder / Vehicles come from the world+vehicles agent. They are
## loaded dynamically (ResourceLoader.exists + load) so this project still
## parses and runs if those files land a minute later; a clearly-marked
## minimal fallback road is built only when WorldBuilder is absent.

enum State { MENU, COUNTDOWN, PLAYING, PAUSED, CRASHED }

const BASE_SPEED := 26.0
const SPEED_PER_100M := 1.0
const MAX_SPEED := 52.0
const NITRO_MULT := 1.35
const AIR_MAX := 600.0
const COUNTDOWN_STEP := 0.6
# TEST SITE first-run ramp intro (SPEC §2.5 + §3.4). The intro ramp sits
# 20 m ahead in the hero's starting lane — visible through the whole
# countdown, reached ~0.8 s after GO. No director spawns until 150 m, so
# nothing can reach the player during the flight. If the player steers
# around the ramp, the intro ends quietly at 50 m (the ramp despawns
# after 34 m of travel, so 50 m leaves a wide margin).
const INTRO_RAMP_Z := -20.0
const INTRO_SPAWN_HOLD_M := 150.0
const INTRO_MISS_DISTANCE_M := 50.0
const INTRO_AUTO_FLIP_DELAY := 0.15

var state: int = State.MENU

var world: Node3D = null
var player: Player = null
var traffic: TrafficManager = null
var hud: HUD = null
var menus: Menus = null
var audio: AudioManager = null
var scoring: Scoring = null

var _env: WorldEnvironment = null
var _environment: Environment = null
var _sky_material: ProceduralSkyMaterial = null
var _sun: DirectionalLight3D = null
var _camera: Camera3D = null
var _particles_root: Node3D = null
var _exhaust: GPUParticles3D = null

var _biome: String = "coastal"
var _distance: float = 0.0
var _speed: float = 0.0
var _trauma: float = 0.0
var _cam_base_pos := Vector3(0, 3.2, 7.5)
var _cam_x: float = 0.0 # damped camera x-follow; snapped to the hero in start_run/_to_menu
var _shake_time: float = 0.0
var _countdown_start_msec: int = 0
var _countdown_step: int = -1
var _crash_start_msec: int = 0
var _crash_panel_shown: bool = false
var _crash_stats: Dictionary = {}
var _rocket_timer: float = 0.0
var _starman_timer: float = 0.0
var _police_active: bool = false
var _police_survival_acc: float = 0.0
var _fly_hold_time: float = 0.0
var _hop_button_held: bool = false
var _swipe_steer: float = 0.0
var _touch_start: Vector2 = Vector2.ZERO
var _touch_start_msec: int = 0
var _touch_active: bool = false
var _tilt_calib: float = 0.0
var _muted: bool = false
var _base_saturation: float = 1.0
var _intro_active: bool = false
var _intro_launched: bool = false
var _intro_auto_flip_timer: float = -1.0

func _ready() -> void:
	scoring = Scoring.new()
	_build_world()
	_setup_environment_and_light()
	_build_camera()
	_build_gameplay()
	_build_ui()
	_wire_signals()
	# Menu backdrop is always coastal (the hero biome); each run picks
	# its own biome in start_run. _to_menu() re-forces coastal on entry.
	_biome = "coastal"
	_apply_biome()
	_to_menu()

# ------------------------------------------------------------------- build

func _setup_environment_and_light() -> void:
	# WorldBuilder owns the real sky / fog / sun (it builds its own
	# WorldEnvironment + DirectionalLight3D). This main must NOT add a
	# second pair — two WorldEnvironments fight over the renderer and two
	# suns double the light. So: when the real world exists, adopt ITS
	# environment (for the crash desaturation) and ITS sun; only when the
	# world is still missing do we build our own fallback pair.
	if world != null and not bool(world.get_meta("fallback", false)):
		_env = _find_world_environment(world)
		if _env != null:
			_environment = _env.environment
			_base_saturation = _environment.adjustment_saturation
		_sun = _find_sun(world)
		if _environment != null:
			return
		push_warning("WorldBuilder has no WorldEnvironment — building fallback environment.")
	_build_fallback_environment()

func _find_world_environment(parent: Node) -> WorldEnvironment:
	for child in parent.get_children():
		if child is WorldEnvironment:
			return child
		var found: WorldEnvironment = _find_world_environment(child)
		if found != null:
			return found
	return null

func _find_sun(parent: Node) -> DirectionalLight3D:
	for child in parent.get_children():
		if child is DirectionalLight3D:
			return child
		var found: DirectionalLight3D = _find_sun(child)
		if found != null:
			return found
	return null

func _build_fallback_environment() -> void:
	# Only used while scripts/world_builder.gd is absent.
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_top_color = Color(0.16, 0.05, 0.35)
	_sky_material.sky_horizon_color = Color(0.95, 0.45, 0.25)
	_sky_material.ground_bottom_color = Color(0.05, 0.02, 0.08)
	_sky_material.ground_horizon_color = Color(0.55, 0.2, 0.35)
	_sky_material.sun_angle_max = 30.0
	_sky_material.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_energy = 0.7
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.9, 0.55, 0.45)
	_environment.fog_density = 0.008
	_environment.fog_sky_affect = 0.5
	_environment.glow_enabled = false
	_environment.glow_intensity = 0.5
	_environment.glow_bloom = 0.08
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 1.0
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = 1.0
	_env = WorldEnvironment.new()
	_env.environment = _environment
	add_child(_env)
	# Fallback sun: warm, low, from the LEFT (-X) over the ocean, shadows on.
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-32, -48, 0)
	_sun.light_color = Color(1.0, 0.75, 0.5)
	_sun.light_energy = 1.25
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 120.0
	add_child(_sun)
	_base_saturation = 1.0

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.position = _cam_base_pos
	_camera.fov = 62.0
	_camera.near = 0.1
	_camera.far = 600.0
	_camera.current = true
	add_child(_camera)
	_camera.look_at(Vector3(0, 1, -12), Vector3.UP)
	_particles_root = Node3D.new()
	_particles_root.name = "Particles"
	add_child(_particles_root)

func _build_world() -> void:
	if ResourceLoader.exists("res://scripts/world_builder.gd"):
		var wb_script: GDScript = load("res://scripts/world_builder.gd")
		world = wb_script.new()
		world.name = "WorldBuilder"
		add_child(world)
	else:
		push_warning("WorldBuilder not present yet — minimal fallback road in use.")
		world = _build_fallback_world()
		add_child(world)

func _build_fallback_world() -> Node3D:
	# TEMPORARY fallback only — a flat road plane so gameplay is testable
	# before scripts/world_builder.gd lands. Delete once it exists.
	var root := Node3D.new()
	root.name = "FallbackWorld"
	var road := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 500)
	road.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.09, 0.11)
	road.material_override = mat
	road.position = Vector3(0, 0, -200)
	root.add_child(road)
	for i in range(4):
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.15, 0.02, 500)
		line.mesh = lm
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.9, 0.85, 0.4)
		lmat.emission_enabled = true
		lmat.emission = Color(0.5, 0.45, 0.1)
		line.material_override = lmat
		line.position = Vector3(-6.0 + float(i) * 3.0, 0.02, -200)
		root.add_child(line)
	root.set_meta("fallback", true)
	return root

func _build_gameplay() -> void:
	player = Player.new()
	player.name = "Player"
	player.position = Vector3(-1.5, 0, 0)
	add_child(player)
	traffic = TrafficManager.new()
	traffic.name = "TrafficManager"
	traffic.hero_node = player
	traffic.player_ref = player
	add_child(traffic)
	audio = AudioManager.new()
	audio.name = "AudioManager"
	add_child(audio)

func _build_ui() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	menus = Menus.new()
	menus.name = "Menus"
	menus.process_mode = Node.PROCESS_MODE_ALWAYS
	menus.scoring = scoring
	menus.audio = audio
	add_child(menus)

func _wire_signals() -> void:
	# Player (single scoring path for hero events).
	player.stunt_completed.connect(_on_stunt_completed)
	player.landed.connect(_on_landed)
	player.crashed.connect(_on_collision)
	player.coin_collected.connect(_on_coin_collected)
	player.near_miss.connect(_on_near_miss)
	player.air_changed.connect(_on_air_changed)
	# Traffic.
	traffic.smashed.connect(_on_smashed)
	traffic.collision.connect(_on_collision)
	traffic.hop_over_car.connect(_on_hop_over)
	traffic.coin_collected.connect(func(_is_air: bool) -> void: pass) # scoring via Player
	traffic.pickup_collected.connect(_on_pickup_collected)
	traffic.ramp_hit.connect(_on_ramp_hit)
	traffic.police_spawned.connect(_on_police_spawned)
	traffic.police_escaped.connect(_on_police_escaped)
	# Scoring -> HUD.
	scoring.score_changed.connect(hud.set_score)
	scoring.multiplier_changed.connect(hud.set_multiplier)
	scoring.coins_changed.connect(hud.set_coins)
	scoring.combo_lost.connect(func() -> void: audio.reset_coin_pitch())
	# HUD buttons.
	hud.pause_pressed.connect(_on_pause_pressed)
	hud.hop_pressed.connect(func() -> void: _hop_button_held = true; _on_hop_button_down())
	hud.hop_released.connect(func() -> void: _hop_button_held = false; player.stop_fly())
	hud.flip_pressed.connect(func() -> void: player.front_flip())
	hud.roll_pressed.connect(func() -> void: player.barrel_roll())
	hud.boost_pressed.connect(func() -> void: player.boost())
	# Menus.
	menus.drive_pressed.connect(start_run)
	menus.resume_pressed.connect(_on_resume_pressed)
	menus.restart_pressed.connect(start_run)
	menus.back_to_menu.connect(_to_menu)
	menus.skin_changed.connect(func() -> void: player.set_paint(scoring.selected_paint))

# ------------------------------------------------------------------- biome

func _pick_biome() -> void:
	# Weighted: coastal is the default/hero biome (50%), neon 20%,
	# canyon 15%, desert 10%, snow + rain 2.5% each.
	var r: float = randf()
	if r < 0.50:
		_biome = "coastal"
	elif r < 0.70:
		_biome = "neon"
	elif r < 0.85:
		_biome = "canyon"
	elif r < 0.95:
		_biome = "desert"
	elif r < 0.975:
		_biome = "snow"
	else:
		_biome = "rain"

func _apply_biome() -> void:
	# The real WorldBuilder applies the palette to its own sky / sun /
	# fog / road itself — main only tells it which biome. The palette
	# writes below run ONLY for the fallback environment.
	if world != null and not bool(world.get_meta("fallback", false)):
		if world.has_method("set_biome"):
			world.set_biome(_biome)
		return
	var palette: Dictionary = {}
	if ResourceLoader.exists("res://scripts/world_builder.gd"):
		var wb_script: GDScript = load("res://scripts/world_builder.gd")
		palette = wb_script.get_biome_palette(_biome)
	if palette.is_empty():
		palette = {
			"sky_top": Color(0.16, 0.05, 0.35), "sky_horizon": Color(0.95, 0.45, 0.25),
			"ground_bottom": Color(0.05, 0.02, 0.08), "ground_horizon": Color(0.55, 0.2, 0.35),
			"sun_color": Color(1.0, 0.75, 0.5), "sun_energy": 1.25,
			"fog_color": Color(0.9, 0.55, 0.45), "fog_density": 0.008,
			"ambient_color": Color(0.9, 0.6, 0.55), "ocean_color": Color(0.1, 0.3, 0.55),
			"road_color": Color(0.09, 0.09, 0.11), "haze_color": Color(0.95, 0.6, 0.4),
		}
	_sky_material.sky_top_color = palette.get("sky_top", Color(0.16, 0.05, 0.35))
	_sky_material.sky_horizon_color = palette.get("sky_horizon", Color(0.95, 0.45, 0.25))
	_sky_material.ground_bottom_color = palette.get("ground_bottom", Color(0.05, 0.02, 0.08))
	_sky_material.ground_horizon_color = palette.get("ground_horizon", Color(0.55, 0.2, 0.35))
	_environment.fog_light_color = palette.get("fog_color", Color(0.9, 0.55, 0.45))
	_environment.fog_density = float(palette.get("fog_density", 0.008))
	_environment.ambient_light_color = palette.get("ambient_color", Color(0.9, 0.6, 0.55))
	_sun.light_color = palette.get("sun_color", Color(1.0, 0.75, 0.5))
	_sun.light_energy = float(palette.get("sun_energy", 1.25))

# ------------------------------------------------------------------- flow

func start_run() -> void:
	# TEST SITE intro (SPEC §2.5 + §3.4): the first run opens on the ramp
	# in the coastal sunset biome — the intro is decoupled from the biome,
	# so the TEST SITE moment plays in daylight. The ramp, banner,
	# auto-flip, spawn hold and once-ever flag are unchanged; only the
	# biome assignment differs. Later runs pick biomes randomly.
	_intro_active = not scoring.test_site_intro_played
	_intro_launched = false
	_intro_auto_flip_timer = -1.0
	if _intro_active:
		_biome = "coastal"
	else:
		_pick_biome()
	_apply_biome()
	scoring.reset_run()
	player.set_paint(scoring.selected_paint)
	player.reset_run()
	player.active = false
	# Snap the damped camera follow to the hero and frame the countdown:
	# camera updates only run in PLAYING, so without this the countdown
	# would freeze at the previous run's camera x.
	_cam_x = player.position.x
	_camera.position = Vector3(_cam_x, _cam_base_pos.y + player.position.y * 0.3, _cam_base_pos.z)
	_camera.look_at(Vector3(_cam_x, 1.0 + player.position.y * 0.3, -12.0), Vector3.UP)
	traffic.start_run()
	if _intro_active:
		# Same ramp construction as the in-run ramp, placed 20 m ahead
		# in the hero's starting lane; no director spawns until 150 m.
		traffic.spawn_intro_ramp(player.lane, INTRO_RAMP_Z)
		traffic.hold_spawns_until_distance(INTRO_SPAWN_HOLD_M)
	_distance = 0.0
	_speed = BASE_SPEED
	_rocket_timer = 0.0
	_starman_timer = 0.0
	_police_active = false
	_police_survival_acc = 0.0
	_trauma = 0.0
	_fly_hold_time = 0.0
	_tilt_calib = Input.get_accelerometer().x
	Engine.time_scale = 1.0
	_environment.adjustment_saturation = _base_saturation
	menus.hide_all()
	hud.set_in_game(true)
	hud.set_score(0)
	hud.set_distance(0)
	hud.set_time(0)
	hud.set_multiplier(1)
	hud.set_combo_frac(0.0)
	hud.set_air(AIR_MAX, AIR_MAX)
	hud.set_coins(0)
	hud.set_speed(0)
	hud.set_boost_ready(true)
	hud.set_airborne(false)
	hud.clear_status()
	hud.hide_test_site_banner()
	if _intro_active:
		hud.show_test_site_banner()
	if _exhaust == null:
		_exhaust = Particles.attach_exhaust(player)
	audio.start_engine()
	audio.start_music()
	audio.set_music_mood(false)
	state = State.COUNTDOWN
	_countdown_start_msec = Time.get_ticks_msec()
	_countdown_step = -1

func _to_menu() -> void:
	state = State.MENU
	Engine.time_scale = 1.0
	_environment.adjustment_saturation = _base_saturation
	player.active = false
	player.reset_run()
	_cam_x = player.position.x
	traffic.clear_all()
	_intro_active = false
	_intro_launched = false
	_intro_auto_flip_timer = -1.0
	audio.stop_engine()
	audio.stop_music()
	audio.stop_siren()
	audio.set_music_mood(false)
	if _exhaust != null:
		Particles.stop_exhaust(_exhaust)
		_exhaust = null
	hud.set_in_game(false)
	hud.hide_countdown()
	hud.hide_test_site_banner()
	# Menu backdrop is always coastal, on every menu entry.
	if world != null:
		_biome = "coastal"
		_apply_biome()
	menus.show_home()

func _on_pause_pressed() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		player.active = false
		audio.stop_engine()
		menus.show_pause()
	elif state == State.PAUSED:
		_on_resume_pressed()

func _on_resume_pressed() -> void:
	if state != State.PAUSED:
		return
	menus.hide_all()
	hud.set_in_game(true)
	player.active = true
	audio.start_engine()
	state = State.PLAYING

# ------------------------------------------------------------------- input

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_SPACE:
					_on_hop_button_down()
				KEY_W:
					if state == State.PLAYING:
						player.front_flip()
				KEY_R:
					if state == State.PLAYING:
						player.barrel_roll()
				KEY_S:
					if state == State.PLAYING:
						player.slam()
				KEY_SHIFT:
					if state == State.PLAYING:
						player.boost()
				KEY_P, KEY_ESCAPE:
					_on_pause_pressed()
				KEY_M:
					_set_muted(not _muted)

func _on_hop_button_down() -> void:
	if state != State.PLAYING:
		return
	if player.is_airborne():
		player.barrel_roll()
	else:
		player.hop()
		audio.play_hop()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_touch_active = true
			_touch_start = t.position
			_touch_start_msec = Time.get_ticks_msec()
			_swipe_steer = 0.0
		else:
			if not _touch_active:
				return
			_touch_active = false
			var dt: float = float(Time.get_ticks_msec() - _touch_start_msec) / 1000.0
			var d: Vector2 = t.position - _touch_start
			if state == State.PLAYING and dt < 0.45:
				if d.y < -90.0:
					_on_hop_button_down()
				elif d.y > 90.0:
					player.slam()
			_swipe_steer = 0.0
	elif event is InputEventScreenDrag:
		var dr: InputEventScreenDrag = event
		if state == State.PLAYING:
			# Drag steers: horizontal offset from the touch start point.
			_swipe_steer = clampf((dr.position.x - _touch_start.x) / 220.0, -1.0, 1.0)

func _set_muted(m: bool) -> void:
	_muted = m
	audio.set_muted(m)
	hud.show_callout("MUTED" if m else "SOUND ON", Color.WHITE)

# ------------------------------------------------------------------- per-frame

func _process(_delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_update_countdown()
		State.CRASHED:
			_update_crash_sequence()

func _update_countdown() -> void:
	var elapsed: float = float(Time.get_ticks_msec() - _countdown_start_msec) / 1000.0
	var step: int = int(elapsed / COUNTDOWN_STEP)
	if step != _countdown_step:
		_countdown_step = step
		match step:
			0:
				hud.show_countdown("3")
				audio.play_tick()
			1:
				hud.show_countdown("2")
				audio.play_tick()
			2:
				hud.show_countdown("1")
				audio.play_tick()
			3:
				hud.show_countdown("GO!")
				audio.play_go()
	if elapsed >= COUNTDOWN_STEP * 4.0:
		hud.hide_countdown()
		player.active = true
		state = State.PLAYING

func _physics_process(delta: float) -> void:
	if state != State.PLAYING:
		return
	# --- speed: 26 m/s + 1 per 100 m, cap 52; nitro +35% for 3 s ---
	var base: float = minf(BASE_SPEED + _distance * SPEED_PER_100M / 100.0, MAX_SPEED)
	_speed = base * (NITRO_MULT if player.nitro_active else 1.0)
	player.speed_mps = _speed
	_distance += _speed * delta
	scoring.add_distance(_speed * delta)
	scoring.update(delta)
	# --- steering: keys, then tilt, then swipe (per Settings mode) ---
	var steer: float = 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		steer = -1.0
	elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		steer = 1.0
	elif menus.control_mode == "Tilt" or menus.control_mode == "Both":
		var acc_x: float = Input.get_accelerometer().x - _tilt_calib
		steer = clampf(acc_x * menus.tilt_sensitivity * 1.4, -1.0, 1.0)
		if absf(steer) < 0.12:
			steer = 0.0
	if menus.control_mode != "Tilt" and absf(_swipe_steer) > 0.05:
		steer = _swipe_steer
	player.set_steer_input(steer)
	# --- hold-to-fly (Space or HOP button held) ---
	var fly_held: bool = Input.is_key_pressed(KEY_SPACE) or _hop_button_held
	if fly_held and player.is_airborne():
		_fly_hold_time += delta
		if _fly_hold_time > 0.12 and player.air > 0.0:
			player.start_fly()
	else:
		_fly_hold_time = 0.0
		if not _hop_button_held and not Input.is_key_pressed(KEY_SPACE):
			player.stop_fly()
	# --- world + traffic ---
	if world != null and world.has_method("scroll"):
		world.scroll(delta, _speed)
	traffic.update_run(delta, _speed, _distance, player.lane, player.position.y)
	# --- TEST SITE intro: auto front-flip shortly after the launch, and
	# the missed-ramp fallback if the player steered around the ramp ---
	if _intro_active and _intro_auto_flip_timer >= 0.0:
		_intro_auto_flip_timer -= delta
		if _intro_auto_flip_timer < 0.0:
			_intro_auto_flip_timer = -1.0
			if player.is_airborne():
				player.front_flip()
	if _intro_active and not _intro_launched and _distance > INTRO_MISS_DISTANCE_M:
		_end_intro_missed()
	# --- pickup timers ---
	if _rocket_timer > 0.0:
		_rocket_timer -= delta
		hud.set_status("ROCKET  %ds" % int(ceil(_rocket_timer)), Color(1.0, 0.55, 0.15))
		if _rocket_timer <= 0.0:
			traffic.set_rocket(false)
			hud.clear_status()
	if _starman_timer > 0.0:
		_starman_timer -= delta
		hud.set_status("STARMAN x2  %ds" % int(ceil(_starman_timer)), Color(1.0, 0.9, 0.2))
		if _starman_timer <= 0.0:
			scoring.starman_active = false
			hud.clear_status()
	# --- police survival: +25 flat per second while chased ---
	if _police_active:
		_police_survival_acc += delta
		if _police_survival_acc >= 1.0:
			_police_survival_acc -= 1.0
			scoring.add_flat(25)
	# --- HUD ---
	hud.set_distance(int(_distance))
	hud.set_time(int(scoring.time_s))
	hud.set_combo_frac(scoring.get_combo_frac())
	hud.set_speed(int(_speed * 3.6))
	hud.set_boost_ready(player.boost_ready)
	hud.set_airborne(player.is_airborne())
	audio.set_engine(clampf((_speed - BASE_SPEED) / (MAX_SPEED - BASE_SPEED), 0.0, 1.0), player.nitro_active)
	audio.set_music_mood(player.nitro_active or _police_active)
	# --- camera: chase framing, FOV kick on nitro, trauma shake, never roll ---
	_shake_time += delta
	var target_fov: float = 70.0 if player.nitro_active else 62.0
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-6.0 * delta))
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	var shake_scale: float = 0.25 if menus.reduce_shake else 1.0
	var sh: float = _trauma * _trauma * 0.4 * shake_scale
	var off := Vector3(
		sin(_shake_time * 61.0) * sh,
		sin(_shake_time * 47.0 + 1.3) * sh,
		0.0)
	# Damped 1.0 follow: the camera tracks the hero's lane fully, so the
	# hero never slides past the frame edge at lanes ±4.5.
	_cam_x = lerpf(_cam_x, player.position.x, 1.0 - exp(-5.5 * delta))
	_camera.position = Vector3(_cam_x, _cam_base_pos.y + player.position.y * 0.3, _cam_base_pos.z) + off
	_camera.look_at(Vector3(_cam_x, 1.0 + player.position.y * 0.3, -12.0), Vector3.UP)

# ------------------------------------------------------------------- scoring events

func _on_stunt_completed(kind: String) -> void:
	if state != State.PLAYING:
		return
	var gained: int = scoring.add_stunt(kind)
	match kind:
		"front_flip":
			hud.show_callout("FRONT FLIP  +%d" % gained)
			audio.play_flip()
		"barrel_roll":
			hud.show_callout("BARREL ROLL  +%d" % gained)
			audio.play_roll()
		"double_stunt":
			hud.show_callout("DOUBLE STUNT  +%d" % gained, Color(1.0, 0.55, 0.15))
			audio.play_chime()
	Particles.spark_burst(_particles_root, player.position + Vector3(0, 1.2, 0))

func _on_landed(quality: String) -> void:
	if state != State.PLAYING:
		return
	if traffic.car_under(player.position.x):
		# Landing on a car roof is a crash — unless Rocket is smashing it.
		if not traffic.rocket_active:
			_on_collision()
			return
	if quality == "perfect":
		var gained: int = scoring.add_stunt("perfect_landing")
		hud.show_callout("PERFECT LANDING  +%d" % gained)
		audio.play_chime()
		Particles.spark_burst(_particles_root, player.position + Vector3(0, 0.5, 0))
	else:
		Particles.tyre_smoke(_particles_root, player.position + Vector3(0, 0.3, 1.6))
	if _intro_active and _intro_launched:
		# Intro flight complete: the landing already scored through the
		# normal path above (perfect landing, since the auto-flip
		# finished). Normal play was never interrupted — just drop the
		# intro flag and keep driving.
		_intro_active = false
		_intro_auto_flip_timer = -1.0

func _on_coin_collected(is_air: bool) -> void:
	if state != State.PLAYING:
		return
	var gained: int = scoring.on_coin_collected(is_air)
	hud.show_callout(("AIR COIN  +%d" % gained) if is_air else ("COIN  +%d" % gained), Color(0.4, 0.8, 1.0) if is_air else Color(1.0, 0.85, 0.3))
	audio.play_coin(scoring.combo)
	if is_air:
		Particles.spark_burst(_particles_root, player.position + Vector3(0, 1.0, 0), Color(0.4, 0.8, 1.0))

func _on_near_miss() -> void:
	if state != State.PLAYING:
		return
	var gained: int = scoring.add_stunt("near_miss")
	hud.show_callout("NEAR MISS  +%d" % gained)
	audio.play_near_miss()
	_trauma = minf(_trauma + 0.25, 1.0)
	Particles.spark_burst(_particles_root, player.position + Vector3(0, 1.0, 0))

func _on_hop_over() -> void:
	if state != State.PLAYING:
		return
	var gained: int = scoring.add_stunt("hop_over")
	hud.show_callout("HOP OVER  +%d" % gained)
	audio.play_whoosh()

func _on_smashed(count: int) -> void:
	if state != State.PLAYING:
		return
	var gained: int = 0
	for i in range(count):
		gained += scoring.add_stunt("smash")
	hud.show_callout("SMASH x%d  +%d" % [count, gained], Color(1.0, 0.45, 0.1))
	audio.play_smash()
	_trauma = minf(_trauma + 0.45, 1.0)

func _on_pickup_collected(kind: String) -> void:
	if state != State.PLAYING:
		return
	audio.play_pickup()
	if kind == "rocket":
		_rocket_timer = 6.0
		traffic.set_rocket(true)
		hud.show_callout("ROCKET MODE!", Color(1.0, 0.55, 0.15))
	elif kind == "starman":
		_starman_timer = 8.0
		scoring.starman_active = true
		hud.show_callout("STARMAN x2!", Color(1.0, 0.9, 0.2))

func _on_ramp_hit() -> void:
	if state != State.PLAYING:
		return
	player.launch_ramp()
	var gained: int = scoring.add_stunt("ramp")
	hud.show_callout("RAMP  +%d  —  FLIP!" % gained, Color(1.0, 0.55, 0.15))
	audio.play_whoosh()
	Particles.tyre_smoke(_particles_root, player.position + Vector3(0, 0.3, 1.6))
	if _intro_active and not _intro_launched:
		# This MUST be the intro ramp: in-run ramps cannot spawn before
		# 650 m, and the intro ends on landing (~50 m) or on the
		# missed-ramp fallback (50 m). The launch + scoring above are
		# identical to an in-run ramp; the intro only adds the auto
		# front-flip (SPEC §3.4), the teaching text, and the persisted
		# flag — saved now, at the launch, so a crash during the flight
		# still counts the intro as played.
		_intro_launched = true
		_intro_auto_flip_timer = INTRO_AUTO_FLIP_DELAY
		hud.hide_test_site_banner()
		hud.show_callout("HOLD HOP TO FLY", Color(0.55, 0.85, 1.0))
		scoring.mark_test_site_intro_played()

## The player steered around the intro ramp: the TEST SITE moment was
## offered and declined. End the intro quietly, persist the flag so the
## intro never loops on a player who dodges it, and let normal play —
## already running — continue untouched.
func _end_intro_missed() -> void:
	_intro_active = false
	_intro_launched = true
	_intro_auto_flip_timer = -1.0
	hud.hide_test_site_banner()
	scoring.mark_test_site_intro_played()

func _on_police_spawned() -> void:
	_police_active = true
	_police_survival_acc = 0.0
	audio.start_siren()
	hud.show_callout("POLICE!  DON'T GET BUSTED", Color(0.5, 0.6, 1.0))

func _on_police_escaped() -> void:
	_police_active = false
	audio.stop_siren()
	scoring.add_flat(500)
	hud.show_callout("ESCAPED!  +500", Color(0.4, 0.9, 0.4))
	audio.play_chime()
	Particles.confetti(_particles_root, player.position + Vector3(0, 2.0, -2.0))

func _on_air_changed(v: float) -> void:
	hud.set_air(v, AIR_MAX)

## Called by TrafficManager when a Rocket smash frees a car.
func spawn_smash_debris(pos: Vector3) -> void:
	Particles.smash_debris(_particles_root, pos)

# ------------------------------------------------------------------- crash

func _on_collision() -> void:
	if state != State.PLAYING:
		return
	state = State.CRASHED
	player.active = false
	_trauma = 1.0
	_intro_active = false
	_intro_launched = false
	_intro_auto_flip_timer = -1.0
	hud.hide_test_site_banner()
	audio.play_crash()
	audio.stop_engine()
	audio.stop_siren()
	audio.set_music_mood(false)
	if _exhaust != null:
		Particles.stop_exhaust(_exhaust)
		_exhaust = null
	Particles.smash_debris(_particles_root, player.position + Vector3(0, 1.0, 0))
	# Save immediately on crash (SPEC §9): bests, coins, runs, quests.
	_crash_stats = scoring.end_run()
	menus.record_run(_crash_stats)
	menus.update_quests(_crash_stats)
	_crash_start_msec = Time.get_ticks_msec()
	_crash_panel_shown = false
	Engine.time_scale = 0.05 # hit-stop, 90 ms

func _update_crash_sequence() -> void:
	var elapsed: float = float(Time.get_ticks_msec() - _crash_start_msec) / 1000.0
	if elapsed < 0.09:
		Engine.time_scale = 0.05
	elif elapsed < 1.2:
		# Slow-mo + desaturate (capped when Reduce Flash is on).
		Engine.time_scale = 0.35
		var target_sat: float = 0.6 if menus.reduce_flash else 0.15
		_environment.adjustment_saturation = lerpf(_base_saturation, target_sat, clampf((elapsed - 0.09) / 0.5, 0.0, 1.0))
	else:
		Engine.time_scale = 1.0
		if not _crash_panel_shown:
			_crash_panel_shown = true
			_show_game_over()

func _show_game_over() -> void:
	hud.set_in_game(false)
	hud.hide_countdown()
	if bool(_crash_stats.get("is_record", false)):
		audio.play_fanfare()
		Particles.confetti(_particles_root, Vector3(0, 3.0, -4.0))
	menus.show_game_over(_crash_stats)
