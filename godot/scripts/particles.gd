class_name Particles
extends Node3D
## One-shot GPUParticles3D helpers. Every helper builds its emitter in code,
## fires it once at a world position, and frees it when done — callers never
## manage particle lifetimes. The exhaust emitter is the exception: it loops
## while attached to the hero and is stopped by its owner.

static func _make(parent: Node, pos: Vector3, amount: int, lifetime: float, explosiveness: float = 0.9) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = explosiveness
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 16, 24))
	parent.add_child(p)
	return p

static func _material(dir: Vector3, spread: float, speed_min: float, speed_max: float, gravity: Vector3, size_min: float, size_max: float, color: Color, damping: float = 0.0) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = dir
	m.spread = spread
	m.initial_velocity_min = speed_min
	m.initial_velocity_max = speed_max
	m.gravity = gravity
	m.damping_min = damping
	m.damping_max = damping
	m.scale_min = size_min
	m.scale_max = size_max
	m.color = color
	return m

static func _quad_mesh(color: Color) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	return q

static func _free_later(p: GPUParticles3D, delay: float) -> void:
	var t: SceneTreeTimer = p.get_tree().create_timer(delay)
	t.timeout.connect(p.queue_free)

## Grey tyre smoke at the hero's rear wheels (landing / slam / nitro).
static func tyre_smoke(parent: Node, pos: Vector3) -> void:
	var p: GPUParticles3D = _make(parent, pos, 18, 0.7, 0.8)
	p.process_material = _material(Vector3(0, 1, 1), 35.0, 2.0, 5.0, Vector3(0, 1.5, 0), 0.25, 0.6, Color(0.75, 0.72, 0.7, 0.55), 2.0)
	p.draw_pass_1 = _quad_mesh(Color(0.75, 0.72, 0.7, 0.55))
	p.emitting = true
	_free_later(p, 1.2)

## Gold/white spark burst — near miss, coin, perfect landing.
static func spark_burst(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.85, 0.3)) -> void:
	var p: GPUParticles3D = _make(parent, pos, 26, 0.5, 1.0)
	p.process_material = _material(Vector3(0, 1, 0), 180.0, 4.0, 9.0, Vector3(0, -6, 0), 0.08, 0.2, color)
	p.draw_pass_1 = _quad_mesh(color)
	p.emitting = true
	_free_later(p, 1.0)

## Colourful confetti — new record / police escape.
static func confetti(parent: Node, pos: Vector3) -> void:
	var p: GPUParticles3D = _make(parent, pos, 60, 1.6, 0.95)
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 60.0
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 9.0
	m.gravity = Vector3(0, -7, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_min = 0.1
	m.scale_max = 0.28
	m.color_ramp = _confetti_ramp()
	p.process_material = m
	p.draw_pass_1 = _quad_mesh(Color.WHITE)
	p.emitting = true
	_free_later(p, 2.2)

static func _confetti_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.2))
	g.add_point(0.33, Color(0.2, 0.7, 1.0))
	g.add_point(0.66, Color(1.0, 0.3, 0.5))
	g.set_color(1, Color(0.3, 0.9, 0.4))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

## Looping exhaust puffs. Attach to the hero once; call stop_exhaust() on crash.
static func attach_exhaust(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 0.5
	p.preprocess = 0.5
	p.explosiveness = 0.0
	p.local_coords = false
	p.position = Vector3(0, 0.55, 2.3)
	p.visibility_aabb = AABB(Vector3(-4, -2, -6), Vector3(8, 6, 12))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0.4, 1)
	m.spread = 12.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 4.0
	m.gravity = Vector3(0, 0.8, 0)
	m.scale_min = 0.15
	m.scale_max = 0.4
	m.color = Color(0.9, 0.9, 0.95, 0.35)
	p.process_material = m
	p.draw_pass_1 = _quad_mesh(Color(0.9, 0.9, 0.95, 0.35))
	parent.add_child(p)
	p.emitting = true
	return p

static func stop_exhaust(p: GPUParticles3D) -> void:
	if p != null and is_instance_valid(p):
		p.emitting = false
		_free_later(p, 0.8)

## Orange/red debris + smoke — Rocket smash and crash.
static func smash_debris(parent: Node, pos: Vector3) -> void:
	var p: GPUParticles3D = _make(parent, pos, 40, 0.9, 1.0)
	p.process_material = _material(Vector3(0, 1, 0), 160.0, 5.0, 12.0, Vector3(0, -14, 0), 0.12, 0.45, Color(1.0, 0.45, 0.1))
	p.draw_pass_1 = _quad_mesh(Color(1.0, 0.45, 0.1))
	p.emitting = true
	_free_later(p, 1.5)
	var smoke: GPUParticles3D = _make(parent, pos + Vector3(0, 0.5, 0), 14, 1.1, 0.7)
	smoke.process_material = _material(Vector3(0, 1, 0), 40.0, 1.0, 3.0, Vector3(0, 2, 0), 0.5, 1.1, Color(0.25, 0.24, 0.26, 0.6), 1.5)
	smoke.draw_pass_1 = _quad_mesh(Color(0.25, 0.24, 0.26, 0.6))
	smoke.emitting = true
	_free_later(smoke, 1.8)
