class_name Player
extends Node3D
## The hero pickup: lane steering with magnet, hop / hold-to-fly / slam,
## barrel roll + front flip, nitro, squash-on-landing, brake lights.
## The car mesh comes from Vehicles.build_hero_pickup() (world/vehicles agent).
## If that script is not present yet, a clearly-marked primitive fallback car
## is built with the SAME node structure (Body / Wheels / WheelFL/FR/RL/RR)
## so every other line of gameplay code works unchanged.
##
## Wiring note: TrafficManager detects overlaps and calls notify_coin() /
## notify_near_miss() on this player; THIS player's coin_collected /
## near_miss signals are the single path main connects for scoring.
## TrafficManager also declares its own near_miss signal (API mirror) —
## do not connect both or points double-count.

signal stunt_completed(kind: String)
signal landed(quality: String)
signal crashed
signal coin_collected(is_air: bool)
signal near_miss
signal air_changed(v: float)

const LANE_X := [-4.5, -1.5, 1.5, 4.5]
const GRAVITY := 22.0
const HOP_VELOCITY := 10.5 # apex ~2.5 m: clears sedans/hatches/vans, not trucks — those need flight
const HOP_COST := 40.0
const AIR_MAX := 600.0
const FLY_BURN := 120.0
const FLY_RISE := 8.0 # climb rate while holding HOP: reaches semi-roof height in ~0.4 s
const REFILL_ROAD := 60.0
const REFILL_GLIDE := 25.0
const ROLL_TIME := 0.55
const FLIP_TIME := 0.70
const CRASH_ANGLE := 0.96 # ~55 degrees off level on landing = crash
const NITRO_TIME := 3.0
const NITRO_COOLDOWN := 8.0
const WHEEL_RADIUS := 0.35

var lane: int = 1
var air: float = AIR_MAX
var speed_mps: float = 0.0
var active: bool = false

var nitro_active: bool = false
var boost_ready: bool = true

var _hero: Node3D = null
var _body: Node3D = null
var _wheels: Array = []
var _vehicles: GDScript = null
var _paint: Color = Color(0.96, 0.96, 0.97)

var _vy: float = 0.0
var _steer_input: float = 0.0
var _steer_cooldown: float = 0.0
var _flying: bool = false
var _stunt: String = "" # "roll" | "flip" | ""
var _stunt_t: float = 0.0
var _stunts_this_air: Array = []
var _double_awarded: bool = false
var _nitro_timer: float = 0.0
var _nitro_cooldown: float = 0.0
var _brake_timer: float = 0.0
var _squash_timer: float = 0.0
var _airborne_flag: bool = false
var _air_emit_acc: float = 0.0

func _ready() -> void:
	if ResourceLoader.exists("res://scripts/vehicles.gd"):
		_vehicles = load("res://scripts/vehicles.gd")
	_build_hero()

func _build_hero() -> void:
	if _hero != null:
		_hero.queue_free()
		_hero = null
	if _vehicles != null:
		_hero = _vehicles.build_hero_pickup(_paint)
	else:
		_hero = _build_fallback_hero(_paint)
	add_child(_hero)
	_body = _hero.get_node_or_null("Body")
	_wheels.clear()
	var wheels_node: Node3D = _hero.get_node_or_null("Wheels")
	if wheels_node != null:
		for wname in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
			var w: Node3D = wheels_node.get_node_or_null(wname)
			if w != null:
				_wheels.append(w)
	if _body == null:
		_body = _hero

## TEMPORARY fallback only — same structure as the real Vehicles hero.
## Delete this function once scripts/vehicles.gd lands; gameplay never
## calls it when the real builder exists.
func _build_fallback_hero(paint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "HeroPickup"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = paint
	mat.metallic = 0.55
	mat.roughness = 0.35
	var lower := MeshInstance3D.new()
	var lower_mesh := BoxMesh.new()
	lower_mesh.size = Vector3(1.9, 0.55, 4.4)
	lower.mesh = lower_mesh
	lower.position = Vector3(0, 0.55, 0)
	lower.material_override = mat
	body.add_child(lower)
	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.7, 0.5, 2.0)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0, 1.05, 0.5)
	cabin.material_override = mat
	body.add_child(cabin)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.05, 0.08, 0.12, 1.0)
	glass_mat.metallic = 0.9
	glass_mat.roughness = 0.08
	var glass := MeshInstance3D.new()
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(1.72, 0.34, 1.9)
	glass.mesh = glass_mesh
	glass.position = Vector3(0, 1.02, 0.5)
	glass.material_override = glass_mat
	body.add_child(glass)
	var wheels_node := Node3D.new()
	wheels_node.name = "Wheels"
	root.add_child(wheels_node)
	var tyre_mat := StandardMaterial3D.new()
	tyre_mat.albedo_color = Color(0.05, 0.05, 0.06, 1.0)
	tyre_mat.roughness = 0.9
	var hub_mat := StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.75, 0.75, 0.78, 1.0)
	hub_mat.metallic = 0.8
	hub_mat.roughness = 0.3
	for wname in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var pivot := Node3D.new()
		pivot.name = wname
		var x: float = -0.95 if wname.ends_with("L") else 0.95
		var z: float = -1.45 if wname.begins_with("WheelF") else 1.45
		pivot.position = Vector3(x, 0.35, z)
		var tyre := MeshInstance3D.new()
		var tyre_mesh := CylinderMesh.new()
		tyre_mesh.top_radius = WHEEL_RADIUS
		tyre_mesh.bottom_radius = WHEEL_RADIUS
		tyre_mesh.height = 0.28
		tyre.mesh = tyre_mesh
		tyre.rotation_degrees = Vector3(0, 0, 90)
		tyre.material_override = tyre_mat
		pivot.add_child(tyre)
		var hub := MeshInstance3D.new()
		var hub_mesh := CylinderMesh.new()
		hub_mesh.top_radius = 0.19
		hub_mesh.bottom_radius = 0.19
		hub_mesh.height = 0.3
		hub.mesh = hub_mesh
		hub.rotation_degrees = Vector3(0, 0, 90)
		hub.material_override = hub_mat
		pivot.add_child(hub)
		wheels_node.add_child(pivot)
	return root

func set_paint(paint: Color) -> void:
	_paint = paint
	_build_hero()

func is_airborne() -> bool:
	return position.y > 0.05 or _vy != 0.0

func is_flying() -> bool:
	return _flying

func reset_run() -> void:
	lane = 1
	position = Vector3(LANE_X[lane], 0, 0)
	rotation = Vector3.ZERO
	_vy = 0.0
	air = AIR_MAX
	_steer_input = 0.0
	_steer_cooldown = 0.0
	_flying = false
	_stunt = ""
	_stunt_t = 0.0
	_stunts_this_air.clear()
	_double_awarded = false
	_nitro_timer = 0.0
	_nitro_cooldown = 0.0
	_brake_timer = 0.0
	_squash_timer = 0.0
	_airborne_flag = false
	nitro_active = false
	boost_ready = true
	if _body != null:
		_body.rotation = Vector3.ZERO
		_body.scale = Vector3.ONE
	_set_brake_lights(false)
	air_changed.emit(air)

func set_steer_input(v: float) -> void:
	_steer_input = clampf(v, -1.0, 1.0)

func move_lane(dir: int) -> void:
	lane = clampi(lane + dir, 0, 3)

func hop() -> void:
	if not active:
		return
	if is_airborne():
		# Press again in the air = barrel roll (SPEC §7.5).
		barrel_roll()
		return
	if air < HOP_COST:
		return
	air -= HOP_COST
	_vy = HOP_VELOCITY
	_flying = false
	_stunts_this_air.clear()
	_double_awarded = false
	_emit_air()

func start_fly() -> void:
	if not active:
		return
	if is_airborne() and air > 0.0 and not _flying:
		_flying = true
		if _vy < 2.0:
			_vy = 2.0

func stop_fly() -> void:
	_flying = false

func slam() -> void:
	if not active or not is_airborne():
		return
	_flying = false
	_vy = -26.0
	_brake_timer = 0.4
	_set_brake_lights(true)

## Ramp launch: high auto-launch with a free front-flip window.
func launch_ramp() -> void:
	if not active:
		return
	_flying = false
	_vy = 13.0
	_stunts_this_air.clear()
	_double_awarded = false

func barrel_roll() -> void:
	if not active or not is_airborne() or _stunt != "":
		return
	_stunt = "roll"
	_stunt_t = 0.0

func front_flip() -> void:
	if not active or not is_airborne() or _stunt != "":
		return
	_stunt = "flip"
	_stunt_t = 0.0

func boost() -> void:
	if not active or _nitro_cooldown > 0.0:
		return
	nitro_active = true
	_nitro_timer = NITRO_TIME
	_nitro_cooldown = NITRO_TIME + NITRO_COOLDOWN
	boost_ready = false

## Called by TrafficManager when an overlap with a coin / near-miss is detected.
func notify_coin(is_air: bool) -> void:
	coin_collected.emit(is_air)

func notify_near_miss() -> void:
	near_miss.emit()

func _physics_process(delta: float) -> void:
	if not active:
		return
	_steer_cooldown = maxf(0.0, _steer_cooldown - delta)
	_nitro_cooldown = maxf(0.0, _nitro_cooldown - delta)
	if _nitro_timer > 0.0:
		_nitro_timer -= delta
		if _nitro_timer <= 0.0:
			nitro_active = false
	boost_ready = _nitro_cooldown <= 0.0
	# --- steering: magnet to the target lane, one lane per input edge ---
	if absf(_steer_input) > 0.35 and _steer_cooldown <= 0.0:
		var dir: int = 1 if _steer_input > 0.0 else -1
		var new_lane: int = clampi(lane + dir, 0, 3)
		if new_lane != lane:
			lane = new_lane
			_steer_cooldown = 0.18
	var target_x: float = LANE_X[lane]
	position.x = lerpf(position.x, target_x, 1.0 - exp(-12.0 * delta))
	# Visual lean into the lane change; the camera never rolls with the car.
	var lean: float = clampf((target_x - position.x) * 0.12, -0.14, 0.14)
	rotation.z = lerpf(rotation.z, lean, 1.0 - exp(-10.0 * delta))
	# --- vertical: hop / fly / glide / fall ---
	if _flying:
		air -= FLY_BURN * delta
		if air <= 0.0:
			air = 0.0
			_flying = false # empty tank mid-flight = glide down, never crash
		else:
			_vy = move_toward(_vy, FLY_RISE, 30.0 * delta)
	else:
		_vy -= GRAVITY * delta
	if is_airborne() or _vy > 0.0:
		position.y += _vy * delta
		if _flying:
			pass
		elif _vy < 0.0:
			air = minf(AIR_MAX, air + REFILL_GLIDE * delta)
	else:
		air = minf(AIR_MAX, air + REFILL_ROAD * delta)
	# --- stunts: rotate the Body, never the root (camera stays level) ---
	if _stunt == "roll":
		_stunt_t += delta
		var p: float = clampf(_stunt_t / ROLL_TIME, 0.0, 1.0)
		_body.rotation.z = -TAU * p
		if p >= 1.0:
			_finish_stunt("barrel_roll")
	elif _stunt == "flip":
		_stunt_t += delta
		var pf: float = clampf(_stunt_t / FLIP_TIME, 0.0, 1.0)
		_body.rotation.x = -TAU * pf
		if pf >= 1.0:
			_finish_stunt("front_flip")
	# --- landing ---
	if position.y > 0.05:
		_airborne_flag = true
	if position.y <= 0.0 and _vy <= 0.0:
		position.y = 0.0
		_vy = 0.0
		_flying = false
		if _stunt != "" and _airborne_flag:
			# Landed mid-roll / mid-flip: the rotation never completed.
			_stunt = ""
			if _body != null:
				_body.rotation = Vector3.ZERO
			_airborne_flag = false
			crashed.emit()
			return
		if _airborne_flag:
			_airborne_flag = false
			_on_landed()
	# --- wheels ---
	for w in _wheels:
		if w != null:
			w.rotation.x += speed_mps * delta / WHEEL_RADIUS
	# --- brake lights ---
	if _brake_timer > 0.0:
		_brake_timer -= delta
		if _brake_timer <= 0.0:
			_set_brake_lights(false)
	# --- squash recovery ---
	if _squash_timer > 0.0:
		_squash_timer -= delta
		var k: float = clampf(_squash_timer / 0.14, 0.0, 1.0)
		if _body != null:
			_body.scale = Vector3(1.0 + 0.06 * k, 1.0 - 0.16 * k, 1.0 + 0.04 * k)
	elif _body != null and _body.scale != Vector3.ONE:
		_body.scale = Vector3.ONE
	_emit_air_throttled(delta)

func _on_landed() -> void:
	_squash_timer = 0.14
	if _body != null:
		_body.rotation = Vector3.ZERO
	if not _stunts_this_air.is_empty():
		landed.emit("perfect")
	else:
		landed.emit("clean")
	_stunts_this_air.clear()
	_double_awarded = false

func _finish_stunt(kind: String) -> void:
	_stunt = ""
	_stunt_t = 0.0
	if _body != null:
		_body.rotation = Vector3.ZERO
	_stunts_this_air.append(kind)
	stunt_completed.emit(kind)
	if _stunts_this_air.size() >= 2 and not _double_awarded:
		_double_awarded = true
		stunt_completed.emit("double_stunt")

func _set_brake_lights(on: bool) -> void:
	if _vehicles != null and _hero != null:
		_vehicles.set_brake_lights(_hero, on)

func _emit_air() -> void:
	air_changed.emit(air)

func _emit_air_throttled(delta: float) -> void:
	_air_emit_acc += delta
	if _air_emit_acc >= 0.1:
		_air_emit_acc = 0.0
		air_changed.emit(air)
