class_name TrafficManager
extends Node3D
## Traffic director + FSM + pickups + ramp + police.
## Cars live in world space relative to the hero: they spawn far ahead
## (z = -180..-220, forward is -Z) and drift toward +Z at
## (hero_speed - car_speed). Despawn past z = +14.
##
## HARD RULE (spawn director): never seal all 4 lanes with no survivable
## line — a spawn row always leaves one lane free inside the same z window,
## or a gap the player can fly over. Queues are single-lane only.
##
## Wiring note: near-miss / coin events are reported through the Player
## (player.notify_near_miss / notify_coin) so main has ONE scoring path.
## This node's own near_miss signal mirrors it for API completeness —
## main connects the Player's copy only.

signal near_miss
signal hop_over_car
signal smashed(count: int)
signal collision
signal coin_collected(is_air: bool)
signal pickup_collected(kind: String)
signal ramp_hit
signal police_spawned
signal police_escaped

const LANE_X := [-4.5, -1.5, 1.5, 4.5]
const SPAWN_Z_MIN := -220.0
const SPAWN_Z_MAX := -180.0
const DESPAWN_Z := 14.0
const TOUCH_DX := 1.85 # |dx| below this + z overlap = contact
const NEAR_MISS_DX := 2.8 # lateral gap under 0.9 m past the bodywork

const TYPE_TABLE := {
	"sedan": {"weight": 0.40, "speed_min": 16.0, "speed_max": 22.0, "length": 4.2, "height": 1.45},
	"hatch": {"weight": 0.20, "speed_min": 18.0, "speed_max": 24.0, "length": 3.9, "height": 1.50},
	"van": {"weight": 0.15, "speed_min": 15.0, "speed_max": 20.0, "length": 5.0, "height": 1.90},
	"truck": {"weight": 0.15, "speed_min": 13.0, "speed_max": 18.0, "length": 7.5, "height": 2.60},
	"semi": {"weight": 0.10, "speed_min": 12.0, "speed_max": 16.0, "length": 11.0, "height": 3.00},
}
const CAR_COLORS := [
	Color(0.75, 0.12, 0.12), Color(0.10, 0.25, 0.65), Color(0.85, 0.85, 0.85),
	Color(0.15, 0.15, 0.18), Color(0.85, 0.65, 0.10), Color(0.10, 0.55, 0.35),
	Color(0.55, 0.20, 0.55), Color(0.80, 0.80, 0.75),
]

const STATE_CRUISE := 0
const STATE_BRAKE := 1
const STATE_LANE_CHANGE := 2
const STATE_QUEUE := 3

class TrafficCar:
	extends RefCounted
	var node: Node3D = null
	var kind: String = "sedan"
	var lane: int = 1
	var x: float = 0.0
	var z: float = -200.0
	var speed: float = 18.0
	var base_speed: float = 18.0
	var state: int = 0
	var target_lane: int = 1
	var target_speed: float = 18.0
	var decide_timer: float = 0.0
	var signal_timer: float = 0.0
	var signal_dir: int = 0
	var change_cooldown: float = 0.0
	var length: float = 4.2
	var height: float = 1.45
	var passed: bool = false
	var hop_counted: bool = false
	var brake_on: bool = false
	var is_police: bool = false

var hero_node: Node3D = null
var player_ref: Player = null
var rocket_active: bool = false

var _vehicles: GDScript = null
var _cars: Array = []
var _pickups: Array = [] # {node, kind, x, y, z, lane}
var _ramps: Array = [] # {node, x, z, hit}
var _spawn_acc: float = 0.0
var _spawn_hold_until: float = 0.0 # TEST SITE intro: no director spawns before this distance
var _next_rocket_at: float = 420.0
var _next_starman_at: float = 650.0
var _next_ramp_at: float = 700.0
var _police: TrafficCar = null
var _police_timer: float = 0.0
var _police_spawned: bool = false
var _running: bool = false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	if ResourceLoader.exists("res://scripts/vehicles.gd"):
		_vehicles = load("res://scripts/vehicles.gd")

func start_run() -> void:
	clear_all()
	_running = true
	_spawn_acc = 0.0
	_spawn_hold_until = 0.0
	_next_rocket_at = 420.0 + _rng.randf_range(0.0, 120.0)
	_next_starman_at = 650.0 + _rng.randf_range(0.0, 150.0)
	_next_ramp_at = 650.0 + _rng.randf_range(0.0, 250.0)
	_police = null
	_police_timer = 0.0
	_police_spawned = false

func clear_all() -> void:
	_running = false
	for c in _cars:
		if c.node != null and is_instance_valid(c.node):
			c.node.queue_free()
	_cars.clear()
	for p in _pickups:
		if p["node"] != null and is_instance_valid(p["node"]):
			p["node"].queue_free()
	_pickups.clear()
	for r in _ramps:
		if r["node"] != null and is_instance_valid(r["node"]):
			r["node"].queue_free()
	_ramps.clear()
	_police = null

func set_rocket(active: bool) -> void:
	rocket_active = active

## TEST SITE intro: hold ALL spawn-director output (traffic rows, coin
## lines, pickups) until the hero has driven this far. The intro ramp is
## spawned directly via spawn_intro_ramp() and is unaffected — it is not
## a director spawn. While held, _spawn_acc stays 0 so the first normal
## row spawns fresh after the hold, preserving the sparse-start pattern.
func hold_spawns_until_distance(d: float) -> void:
	_spawn_hold_until = maxf(0.0, d)

## True if a car roof sits under x right now (landing check, called by main
## when the player touches down — landing on a roof is a crash).
func car_under(x: float) -> bool:
	for c in _cars:
		if absf(c.z) < c.length * 0.5 + 1.0 and absf(c.x - x) < TOUCH_DX:
			return true
	return false

func update_run(delta: float, speed_mps: float, distance_m: float, hero_lane: int, hero_y: float) -> void:
	if not _running:
		return
	var hero_x: float = LANE_X[hero_lane]
	if hero_node != null and is_instance_valid(hero_node):
		hero_x = hero_node.position.x
	_spawn_director(delta, speed_mps, distance_m)
	_update_cars(delta, speed_mps, hero_x, hero_y)
	_update_pickups(delta, speed_mps, hero_x, hero_y)
	_update_ramps(delta, speed_mps, hero_x, hero_y)
	_update_police(delta, speed_mps, distance_m, hero_x)

# ------------------------------------------------------------------ spawning

func _spacing_for(distance_m: float) -> float:
	# SPEC §5.6 difficulty ramp: sparse early, dense late.
	return maxf(28.0, 60.0 - distance_m * 0.02)

func _spawn_director(delta: float, speed_mps: float, distance_m: float) -> void:
	if distance_m < _spawn_hold_until:
		_spawn_acc = 0.0
		return
	_spawn_acc += delta * speed_mps
	var spacing: float = _spacing_for(distance_m)
	if _spawn_acc < spacing:
		return
	_spawn_acc = 0.0
	var roll: float = _rng.randf()
	if distance_m > 800.0 and roll < 0.18:
		_spawn_queue_row()
	elif roll < 0.30:
		_spawn_row(3)
	elif roll < 0.62:
		_spawn_row(2)
	else:
		_spawn_row(1)
	_maybe_spawn_coin_line(distance_m)
	_maybe_spawn_pickups(distance_m)

func _lanes_blocked_near(spawn_z: float, window: float) -> Array:
	var blocked: Array = []
	for c in _cars:
		if absf(c.z - spawn_z) < window:
			if not blocked.has(c.lane):
				blocked.append(c.lane)
	return blocked

func _spawn_row(count: int) -> void:
	var spawn_z: float = _rng.randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX)
	var blocked: Array = _lanes_blocked_near(spawn_z, 14.0)
	# HARD RULE: at most 3 of 4 lanes may be blocked in this z window.
	var free_lanes: Array = []
	for l in range(4):
		if not blocked.has(l):
			free_lanes.append(l)
	if free_lanes.is_empty():
		return # no survivable line — skip this row entirely
	var lanes: Array = free_lanes.duplicate()
	lanes.shuffle()
	var take: int = mini(count, lanes.size())
	# Never take the last free lane when spawning a triple.
	if take >= 3 and lanes.size() <= 3:
		take = 2
	for i in range(take):
		_spawn_car(int(lanes[i]), spawn_z + _rng.randf_range(-6.0, 6.0))

func _spawn_queue_row() -> void:
	# A 3-car single-lane jam: dramatic, always escapable (3 lanes free).
	var lane: int = _rng.randi_range(0, 3)
	var spawn_z: float = _rng.randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX)
	if not _lanes_blocked_near(spawn_z, 14.0).is_empty() and _lanes_blocked_near(spawn_z, 14.0).has(lane):
		return
	for i in range(3):
		var c: TrafficCar = _spawn_car(lane, spawn_z - float(i) * 9.0)
		if c != null:
			c.speed = 6.0
			c.base_speed = 6.0
			c.target_speed = 6.0
			c.state = STATE_QUEUE

func _pick_kind() -> String:
	var r: float = _rng.randf()
	var acc: float = 0.0
	for kind in TYPE_TABLE.keys():
		acc += float(TYPE_TABLE[kind]["weight"])
		if r <= acc:
			return kind
	return "sedan"

func _spawn_car(lane: int, z: float) -> TrafficCar:
	var kind: String = _pick_kind()
	var t: Dictionary = TYPE_TABLE[kind]
	var node: Node3D = null
	if _vehicles != null:
		node = _vehicles.build_traffic_car(kind, CAR_COLORS[_rng.randi_range(0, CAR_COLORS.size() - 1)])
	else:
		node = _build_fallback_car(kind)
	var c := TrafficCar.new()
	c.node = node
	c.kind = kind
	c.lane = lane
	c.target_lane = lane
	c.x = LANE_X[lane]
	c.z = z
	c.base_speed = _rng.randf_range(float(t["speed_min"]), float(t["speed_max"]))
	c.speed = c.base_speed
	c.target_speed = c.base_speed
	c.length = float(t["length"])
	c.height = float(t["height"])
	c.decide_timer = _rng.randf_range(0.0, 0.25)
	node.position = Vector3(c.x, 0, z)
	add_child(node)
	_cars.append(c)
	return c

func _build_fallback_car(kind: String) -> Node3D:
	# TEMPORARY fallback only — same Body / BrakeL / BrakeR structure as
	# Vehicles.build_traffic_car. Delete once scripts/vehicles.gd lands.
	var root := Node3D.new()
	root.name = "TrafficCar"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var t: Dictionary = TYPE_TABLE[kind]
	var len_f: float = float(t["length"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.15, 0.15)
	mat.metallic = 0.4
	mat.roughness = 0.4
	var lower := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(2.0, 0.7, len_f)
	lower.mesh = lm
	lower.position = Vector3(0, 0.55, 0)
	lower.material_override = mat
	body.add_child(lower)
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.8, 0.6, len_f * 0.45)
	cabin.mesh = cm
	cabin.position = Vector3(0, 1.15, len_f * 0.08)
	cabin.material_override = mat
	body.add_child(cabin)
	for bname in ["BrakeL", "BrakeR"]:
		var b := MeshInstance3D.new()
		b.name = bname
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 0.18, 0.1)
		b.mesh = bm
		b.position = Vector3(-0.7 if bname == "BrakeL" else 0.7, 0.75, len_f * 0.5)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.6, 0.05, 0.05)
		bmat.emission_enabled = true
		bmat.emission = Color(0.6, 0.02, 0.02)
		b.material_override = bmat
		b.visible = false
		body.add_child(b)
	return root

# ------------------------------------------------------------------ FSM + move

func _update_cars(delta: float, speed_mps: float, hero_x: float, hero_y: float) -> void:
	var i: int = _cars.size() - 1
	while i >= 0:
		var c: TrafficCar = _cars[i]
		if c.node == null or not is_instance_valid(c.node):
			_cars.remove_at(i)
			i -= 1
			continue
		c.decide_timer -= delta
		if c.decide_timer <= 0.0:
			c.decide_timer = 0.25
			_decide(c)
		c.change_cooldown = maxf(0.0, c.change_cooldown - delta)
		# Steering toward the target lane (arrive profile).
		# Indicator blinks 0.5 s BEFORE the car starts moving (SPEC §5.5).
		var tx: float = LANE_X[c.target_lane]
		if c.signal_timer > 0.0:
			c.signal_timer -= delta
		else:
			c.x = move_toward(c.x, tx, 3.2 * delta)
		if c.state == STATE_LANE_CHANGE and absf(c.x - tx) < 0.08:
			c.lane = c.target_lane
			c.state = STATE_CRUISE
			c.change_cooldown = 4.0
			_set_indicator(c, 0)
		# Speed toward target.
		c.speed = move_toward(c.speed, c.target_speed, 6.0 * delta)
		# Relative motion: the world rushes at the hero.
		c.z += (speed_mps - c.speed) * delta
		c.node.position = Vector3(c.x, 0, c.z)
		# Brake lights on the mesh.
		var want_brake: bool = c.state == STATE_BRAKE or c.state == STATE_QUEUE
		if want_brake != c.brake_on:
			c.brake_on = want_brake
			_set_brake_lights(c, want_brake)
		# Passing the hero: near-miss / hop-over / smash / collision.
		if not c.passed and c.z > 1.0:
			c.passed = true
			_on_car_passed(c, hero_x, hero_y)
		elif not c.passed:
			_check_contact(c, hero_x, hero_y)
		if c.z > DESPAWN_Z:
			c.node.queue_free()
			_cars.remove_at(i)
		i -= 1

func _decide(c: TrafficCar) -> void:
	if c.state == STATE_LANE_CHANGE:
		return # finish the move first; no new decisions mid-change
	var ahead: TrafficCar = _car_ahead(c)
	if ahead == null:
		c.state = STATE_CRUISE
		c.target_speed = c.base_speed
		return
	var gap: float = c.z - ahead.z - (ahead.length * 0.5 + c.length * 0.5)
	if ahead.speed < 4.0 and gap < 9.0:
		c.state = STATE_QUEUE
		c.target_speed = 2.0
		return
	if gap < 14.0:
		# Try a lane change (signal 0.5 s first); otherwise brake.
		if c.change_cooldown <= 0.0:
			var dir: int = _free_side(c)
			if dir != 0:
				var target: int = clampi(c.lane + dir, 0, 3)
				if not _would_seal(c, target):
					c.state = STATE_LANE_CHANGE
					c.signal_dir = dir
					c.signal_timer = 0.5
					c.target_lane = target
					_set_indicator(c, dir)
					c.target_speed = c.base_speed
					return
		c.state = STATE_BRAKE
		c.target_speed = maxf(4.0, ahead.speed * 0.85)
	else:
		c.state = STATE_CRUISE
		c.target_speed = c.base_speed

func _car_ahead(c: TrafficCar) -> TrafficCar:
	var best: TrafficCar = null
	var best_gap: float = 1e9
	for o in _cars:
		if o == c or o.lane != c.lane:
			continue
		if o.z >= c.z:
			continue # behind us (closer to the hero) is not "ahead"
		var gap: float = c.z - o.z
		if gap < 26.0 and gap < best_gap:
			best_gap = gap
			best = o
	return best

func _free_side(c: TrafficCar) -> int:
	for dir in [-1, 1]:
		var nl: int = c.lane + dir
		if nl < 0 or nl > 3:
			continue
		var free: bool = true
		for o in _cars:
			if o == c:
				continue
			if o.lane == nl and absf(o.z - c.z) < 12.0:
				free = false
				break
		if free:
			return dir
	return 0

## HARD-RULE guard for lane changes: a change must never seal the last
## free lane inside the z-window — the spawn director guarantees a
## survivable line at spawn time, and this keeps it true as traffic drifts.
func _would_seal(c: TrafficCar, target_lane: int) -> bool:
	var occupied: Array = []
	for o in _cars:
		if o == c:
			continue
		if absf(o.z - c.z) < 12.0 and not occupied.has(o.lane):
			occupied.append(o.lane)
	if occupied.has(target_lane):
		return false # target already occupied — _free_side wouldn't pick it
	occupied.append(target_lane)
	return occupied.size() >= 4

func _on_car_passed(c: TrafficCar, hero_x: float, hero_y: float) -> void:
	var dx: float = absf(c.x - hero_x)
	if hero_y < 1.0 and dx >= TOUCH_DX and dx < NEAR_MISS_DX:
		near_miss.emit()
		if player_ref != null:
			player_ref.notify_near_miss()
	elif hero_y > 1.6 and dx < TOUCH_DX and not c.hop_counted:
		c.hop_counted = true
		hop_over_car.emit()

func _check_contact(c: TrafficCar, hero_x: float, hero_y: float) -> void:
	var dz: float = absf(c.z)
	var dx: float = absf(c.x - hero_x)
	if dz < c.length * 0.5 + 1.3 and dx < TOUCH_DX and hero_y < c.height:
		if rocket_active:
			_smash_car(c)
		else:
			collision.emit()

func _smash_car(c: TrafficCar) -> void:
	var idx: int = _cars.find(c)
	if idx >= 0:
		_cars.remove_at(idx)
	if c.node != null and is_instance_valid(c.node):
		var pos: Vector3 = c.node.position
		c.node.queue_free()
		if get_parent() != null and get_parent().has_method("spawn_smash_debris"):
			get_parent().call("spawn_smash_debris", pos)
	smashed.emit(1)

# ------------------------------------------------------------------ pickups

func _maybe_spawn_coin_line(distance_m: float) -> void:
	if _rng.randf() > 0.45:
		return
	var lane: int = _rng.randi_range(0, 3)
	var base_z: float = _rng.randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX)
	var is_air: bool = _rng.randf() < 0.30
	var y: float = 2.3 if is_air else 0.9
	for k in range(4):
		_spawn_pickup("air_coin" if is_air else "coin", LANE_X[lane], y, base_z - float(k) * 7.0)

func _maybe_spawn_pickups(distance_m: float) -> void:
	if distance_m >= _next_rocket_at:
		_next_rocket_at = distance_m + _rng.randf_range(400.0, 650.0)
		_spawn_pickup("rocket", LANE_X[_rng.randi_range(0, 3)], 1.0, _rng.randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX))
	if distance_m >= _next_starman_at:
		_next_starman_at = distance_m + _rng.randf_range(550.0, 800.0)
		_spawn_pickup("starman", LANE_X[_rng.randi_range(0, 3)], 1.0, _rng.randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX))
	if distance_m >= _next_ramp_at:
		_next_ramp_at = distance_m + _rng.randf_range(600.0, 900.0)
		_spawn_ramp()

func _spawn_pickup(kind: String, x: float, y: float, z: float) -> void:
	var node: Node3D = null
	if _vehicles != null:
		match kind:
			"coin":
				node = _vehicles.build_coin()
			"air_coin":
				node = _vehicles.build_air_coin()
			"rocket", "starman":
				node = _vehicles.build_pickup_orb(kind)
	if node == null:
		node = _build_fallback_pickup(kind)
	node.position = Vector3(x, y, z)
	add_child(node)
	_pickups.append({"node": node, "kind": kind, "x": x, "y": y, "z": z})

func _build_fallback_pickup(kind: String) -> Node3D:
	# TEMPORARY fallback only — gold/blue coin or glowing orb.
	var root := Node3D.new()
	root.name = "Pickup_" + kind
	var m := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	match kind:
		"coin":
			mat.albedo_color = Color(1.0, 0.8, 0.2)
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.6, 0.05)
			var cm := CylinderMesh.new()
			cm.top_radius = 0.45
			cm.bottom_radius = 0.45
			cm.height = 0.12
			m.mesh = cm
			m.rotation_degrees = Vector3(0, 0, 90)
		"air_coin":
			mat.albedo_color = Color(0.2, 0.7, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.1, 0.5, 1.0)
			var am := CylinderMesh.new()
			am.top_radius = 0.45
			am.bottom_radius = 0.45
			am.height = 0.12
			m.mesh = am
			m.rotation_degrees = Vector3(0, 0, 90)
		_:
			mat.albedo_color = Color(1.0, 0.3, 0.2) if kind == "rocket" else Color(1.0, 0.9, 0.2)
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
			var sm := SphereMesh.new()
			sm.radius = 0.6
			sm.height = 1.2
			m.mesh = sm
	m.material_override = mat
	root.add_child(m)
	return root

func _update_pickups(delta: float, speed_mps: float, hero_x: float, hero_y: float) -> void:
	var i: int = _pickups.size() - 1
	while i >= 0:
		var p: Dictionary = _pickups[i]
		var node: Node3D = p["node"]
		if node == null or not is_instance_valid(node):
			_pickups.remove_at(i)
			i -= 1
			continue
		p["z"] = float(p["z"]) + speed_mps * delta
		node.position = Vector3(float(p["x"]), float(p["y"]), float(p["z"]))
		node.rotation.y += delta * 3.0
		var dz: float = absf(float(p["z"]))
		var dx: float = absf(float(p["x"]) - hero_x)
		var dy: float = absf(float(p["y"]) - hero_y)
		if dz < 1.6 and dx < 1.3 and dy < 1.7:
			var kind: String = String(p["kind"])
			node.queue_free()
			_pickups.remove_at(i)
			if kind == "coin" or kind == "air_coin":
				coin_collected.emit(kind == "air_coin")
				if player_ref != null:
					player_ref.notify_coin(kind == "air_coin")
			else:
				pickup_collected.emit(kind)
		elif float(p["z"]) > DESPAWN_Z:
			node.queue_free()
			_pickups.remove_at(i)
		i -= 1

# ------------------------------------------------------------------ ramp

func _spawn_ramp() -> void:
	_spawn_ramp_at(_rng.randi_range(0, 3), _rng.randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX))

## TEST SITE intro ramp: a CURVED launch ramp (SPEC §2.5/§5.1 — "the
## car launches off a curved ramp"). Same footprint (3.0 wide, 6.0 long,
## 1.6 high), same orange + chevron look, same _ramps entry, same
## hit-test in _update_ramps and the same ramp_hit signal as the in-run
## ramp — main scores and launches it through the identical path
## (player.launch_ramp(), +200, auto front-flip window). Only the
## geometry differs: a smooth quarter-pipe curve (flat tangent at the
## approach, ~28 deg at the lip) instead of the flat wedge. The in-run
## ramps keep _spawn_ramp_at() and the flat wedge exactly as built.
func spawn_intro_ramp(lane: int, z: float) -> void:
	_spawn_curved_ramp_at(clampi(lane, 0, 3), z)

func _spawn_curved_ramp_at(lane: int, z: float) -> void:
	var ramp_w := 3.0
	var ramp_h := 1.6
	var ramp_l := 6.0
	var node := Node3D.new()
	node.name = "Ramp"
	var mesh := MeshInstance3D.new()
	mesh.mesh = _build_curved_ramp_mesh(ramp_w, ramp_h, ramp_l, 10)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.22, 0.0)
	mesh.material_override = mat
	node.add_child(mesh)
	# Chevron stripes riding ON the curve: each stripe sits just above
	# the surface at its profile point and tilts to the local slope,
	# so the chevrons follow the quarter-pipe instead of floating over
	# it or cutting through it. Same size, colour and count as the
	# flat ramp's stripes.
	var stripe_ts := [0.35, 0.6, 0.85]
	for k in range(3):
		var t: float = stripe_ts[k]
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(2.6, 0.06, 0.5)
		stripe.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(1.0, 0.95, 0.2)
		smat.emission_enabled = true
		smat.emission = Color(0.8, 0.7, 0.05)
		stripe.material_override = smat
		stripe.position = Vector3(0.0, ramp_h * t * t + 0.05, ramp_l * 0.5 - t * ramp_l)
		# POSITIVE rotation: settled by the stripe-clearance probe
		# (star-ramp-scratch/stripe_probe.gd), which measures each
		# stripe's bottom-corner clearance over the curve. With a
		# negative angle the lip-side end buries (-0.07..-0.18 m)
		# and the approach end floats (+0.11..+0.23 m); with the
		# positive angle both ends sit ~0.02 m above the surface.
		# (The side-profile render misleads the eye here — the
		# stripe's width runs along the view axis — so the probe
		# numbers, not the profile view, decide the sign.)
		stripe.rotation.x = atan(2.0 * ramp_h * t / ramp_l)
		node.add_child(stripe)
	# The curved entry stays within a few cm of the road plane for its
	# first metre (flat tangent), so the node sits 5 cm up: without
	# the lift the shallow entry z-fights the asphalt at grazing
	# angles (thin black dash lines across the apron in the 3/4
	# render). The lift is invisible at speed and cannot affect the
	# launch — the trigger tests z/x only, and launch_ramp() sets a
	# fixed upward velocity.
	node.position = Vector3(LANE_X[lane], 0.05, z)
	add_child(node)
	_ramps.append({"node": node, "x": LANE_X[lane], "z": node.position.z, "hit": false})

func _build_curved_ramp_mesh(width: float, height: float, length: float, segments: int) -> ArrayMesh:
	# A solid curved ramp: low at +Z (approach), high at -Z (launch
	# lip), profile y = H * t^2 — flat tangent where the car rolls
	# on, steepening smoothly to ~28 deg at the lip, like a
	# quarter-pipe. Same ArrayMesh building-block style as
	# _build_wedge_mesh, with explicit normals: smooth analytic
	# normals on the curved top so the curve catches the light as a
	# continuous bend, flat normals on the sides/back/bottom.
	var hw: float = width * 0.5
	var hl: float = length * 0.5
	var verts: Array = []
	var normals: Array = []
	var idx: Array = []
	var prof_z: Array = []
	var prof_y: Array = []
	var prof_n: Array = []
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		prof_z.append(hl - t * length)
		prof_y.append(height * t * t)
		# Surface normal: perpendicular to the profile tangent
		# (dz, dy) = (-L, 2*H*t), pointing up and toward +Z.
		prof_n.append(Vector3(0.0, length, 2.0 * height * t).normalized())
	# Curved top surface: one quad per segment.
	for i in range(segments):
		var z0: float = prof_z[i]
		var z1: float = prof_z[i + 1]
		var y0: float = prof_y[i]
		var y1: float = prof_y[i + 1]
		var n0: Vector3 = prof_n[i]
		var n1: Vector3 = prof_n[i + 1]
		var b: int = verts.size()
		verts.append_array([Vector3(-hw, y0, z0), Vector3(hw, y0, z0), Vector3(hw, y1, z1), Vector3(-hw, y1, z1)])
		normals.append_array([n0, n0, n1, n1])
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	# Sides: one quad per segment, flat outward normals. Winding is
	# mirrored per side so both faces point outward.
	for side in [-1.0, 1.0]:
		var sx: float = side * hw
		var sn := Vector3(side, 0.0, 0.0)
		for i in range(segments):
			var z0: float = prof_z[i]
			var z1: float = prof_z[i + 1]
			var y0: float = prof_y[i]
			var y1: float = prof_y[i + 1]
			var bf := Vector3(sx, 0.0, z0)
			var bb := Vector3(sx, 0.0, z1)
			var tf := Vector3(sx, y0, z0)
			var tb := Vector3(sx, y1, z1)
			var b: int = verts.size()
			if side < 0.0:
				verts.append_array([bf, tf, tb, bb])
			else:
				verts.append_array([bf, bb, tb, tf])
			normals.append_array([sn, sn, sn, sn])
			idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	# Back face (launch lip, faces -Z).
	var b_back: int = verts.size()
	verts.append_array([Vector3(-hw, 0.0, -hl), Vector3(-hw, height, -hl), Vector3(hw, height, -hl), Vector3(hw, 0.0, -hl)])
	normals.append_array([Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -1.0)])
	idx.append_array([b_back, b_back + 1, b_back + 2, b_back, b_back + 2, b_back + 3])
	# Bottom (never seen, keeps the solid closed like the wedge).
	var b_bot: int = verts.size()
	verts.append_array([Vector3(-hw, 0.0, hl), Vector3(-hw, 0.0, -hl), Vector3(hw, 0.0, -hl), Vector3(hw, 0.0, hl)])
	normals.append_array([Vector3(0.0, -1.0, 0.0), Vector3(0.0, -1.0, 0.0), Vector3(0.0, -1.0, 0.0), Vector3(0.0, -1.0, 0.0)])
	idx.append_array([b_bot, b_bot + 1, b_bot + 2, b_bot, b_bot + 2, b_bot + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(verts)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(idx)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

func _spawn_ramp_at(lane: int, z: float) -> void:
	var node := Node3D.new()
	node.name = "Ramp"
	var mesh := MeshInstance3D.new()
	mesh.mesh = _build_wedge_mesh(3.0, 1.6, 6.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.22, 0.0)
	mesh.material_override = mat
	node.add_child(mesh)
	# Chevron stripes lying flat ON the slope: each stripe sits just
	# above the surface at its profile point and tilts to the slope,
	# mirroring the curved ramp's stripes (same t values, same size,
	# colour and count). The old placement ascended toward the
	# approach while the wedge descends, with the tilt sign reversed:
	# the probe measured one stripe buried (-1.06..-0.74 m), the
	# middle stripe cutting through the slope (-0.19..+0.14 m) and
	# one floating (+0.69..+1.02 m). The flat slope is y = 1.6 * t
	# at z = 3.0 - t * 6.0 (wedge height 1.6, length 6.0), tilted
	# +atan(1.6 / 6.0) — POSITIVE, like the curved ramp: a positive
	# X rotation drops the +Z (approach) end, which is the low end
	# of the slope. Centre offset 0.05 m above the surface minus
	# 0.03 m half thickness leaves ~0.02 m bottom clearance at both
	# ends, probe-verified (flat_stripe_probe.gd in chevron-fix
	# scratch). Wedge geometry, footprint, hit-test and launch are
	# untouched — only stripe positions/tilts move.
	var stripe_ts := [0.35, 0.6, 0.85]
	for k in range(3):
		var t: float = stripe_ts[k]
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(2.6, 0.06, 0.5)
		stripe.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(1.0, 0.95, 0.2)
		smat.emission_enabled = true
		smat.emission = Color(0.8, 0.7, 0.05)
		stripe.material_override = smat
		stripe.position = Vector3(0.0, 1.6 * t + 0.05, 3.0 - t * 6.0)
		stripe.rotation.x = atan(1.6 / 6.0)
		node.add_child(stripe)
	node.position = Vector3(LANE_X[lane], 0.0, z)
	add_child(node)
	_ramps.append({"node": node, "x": LANE_X[lane], "z": node.position.z, "hit": false})

func _build_wedge_mesh(width: float, height: float, length: float) -> ArrayMesh:
	# A solid wedge: low at +Z (approach), high at -Z (launch lip).
	var hw: float = width * 0.5
	var hl: float = length * 0.5
	var verts := PackedVector3Array([
		Vector3(-hw, 0, hl), Vector3(hw, 0, hl), Vector3(hw, 0, -hl), Vector3(-hw, 0, -hl),
		Vector3(-hw, height, -hl), Vector3(hw, height, -hl),
	])
	var idx := PackedInt32Array([
		0, 1, 2, 0, 2, 3, # bottom
		4, 5, 2, 4, 2, 3, # back face
		0, 3, 4, # left side
		1, 5, 2, # right side (wound to face out)
		0, 4, 5, 0, 5, 1, # slope
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

func _update_ramps(delta: float, speed_mps: float, hero_x: float, hero_y: float) -> void:
	var i: int = _ramps.size() - 1
	while i >= 0:
		var r: Dictionary = _ramps[i]
		var node: Node3D = r["node"]
		if node == null or not is_instance_valid(node):
			_ramps.remove_at(i)
			i -= 1
			continue
		r["z"] = float(r["z"]) + speed_mps * delta
		node.position.z = float(r["z"])
		if not bool(r["hit"]) and absf(float(r["z"])) < 2.0 and absf(float(r["x"]) - hero_x) < 1.6 and hero_y < 0.5:
			r["hit"] = true
			ramp_hit.emit()
		if float(r["z"]) > DESPAWN_Z:
			node.queue_free()
			_ramps.remove_at(i)
		i -= 1

# ------------------------------------------------------------------ police

func _update_police(delta: float, speed_mps: float, distance_m: float, hero_x: float) -> void:
	if not _police_spawned and distance_m >= 1000.0:
		_police_spawned = true
		_spawn_police()
		police_spawned.emit()
	if _police == null:
		return
	_police_timer += delta
	var p: TrafficCar = _police
	# The cruiser hangs 6-10 m behind the hero, lights flashing.
	p.z = move_toward(p.z, 8.0, 1.5 * delta)
	p.x = move_toward(p.x, hero_x, 4.0 * delta)
	if p.node != null and is_instance_valid(p.node):
		p.node.position = Vector3(p.x, 0, p.z)
		var bar: Node3D = p.node.get_node_or_null("Body/LightBar")
		if bar != null:
			bar.visible = int(_police_timer * 6.0) % 2 == 0
	if _police_timer > 25.0 or distance_m > 1500.0:
		if p.node != null and is_instance_valid(p.node):
			p.node.queue_free()
		_police = null
		police_escaped.emit()

func _spawn_police() -> void:
	var node: Node3D = null
	if _vehicles != null:
		node = _vehicles.build_traffic_car("sedan", Color(0.05, 0.05, 0.08))
	else:
		node = _build_fallback_car("sedan")
	var bar := Node3D.new()
	bar.name = "LightBar"
	var body: Node3D = node.get_node_or_null("Body")
	if body == null:
		body = node
	for cname in ["Red", "Blue"]:
		var lamp := MeshInstance3D.new()
		lamp.name = cname
		var lm := BoxMesh.new()
		lm.size = Vector3(0.4, 0.12, 0.3)
		lamp.mesh = lm
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(1, 0.05, 0.05) if cname == "Red" else Color(0.05, 0.2, 1)
		lmat.emission_enabled = true
		lmat.emission = lmat.albedo_color
		lamp.material_override = lmat
		lamp.position = Vector3(-0.25 if cname == "Red" else 0.25, 1.55, 0.3)
		bar.add_child(lamp)
	body.add_child(bar)
	var p := TrafficCar.new()
	p.node = node
	p.kind = "sedan"
	p.lane = 1
	p.x = 0.0
	p.z = 10.0
	p.speed = 0.0
	p.is_police = true
	node.position = Vector3(0, 0, 10.0)
	add_child(node)
	_cars.append(p)
	_police = p

# ------------------------------------------------------------------ helpers

func _set_brake_lights(c: TrafficCar, on: bool) -> void:
	if _vehicles != null and c.node != null:
		_vehicles.set_brake_lights(c.node, on)
	elif c.node != null:
		var body: Node3D = c.node.get_node_or_null("Body")
		if body != null:
			for bname in ["BrakeL", "BrakeR"]:
				var b: Node3D = body.get_node_or_null(bname)
				if b != null:
					b.visible = on

func _set_indicator(c: TrafficCar, dir: int) -> void:
	if _vehicles != null and c.node != null:
		_vehicles.set_indicator(c.node, dir, dir != 0)
