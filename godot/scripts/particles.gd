class_name Particles
extends Node3D
## One-shot GPUParticles3D helpers. Every helper builds its emitter in code,
## fires it once at a world position, and frees it when done — callers never
## manage particle lifetimes. The exhaust emitter is the exception: it loops
## while attached to the hero and is stopped by its owner.
##
## All emitters share ONE soft radial texture (built once, cached below) on
## per-emitter materials: the texture gives every puff a round falloff, the
## per-emitter material keeps each emitter's own colour. Without the texture
## + TRANSPARENCY_ALPHA the quads render as hard opaque white squares.

# Shared soft radial texture, built once on first use. Colours live on the
# per-emitter materials, never in this texture (it is pure white + alpha).
static var _radial_texture: ImageTexture = null

static func _shared_radial_texture() -> ImageTexture:
	if _radial_texture == null:
		_radial_texture = _make_radial_texture(64)
	return _radial_texture

static func _make_radial_texture(size: int) -> ImageTexture:
	# Soft radial falloff: opaque centre, transparent edges — same pattern
	# as Vehicles._make_glow_texture (the hero underglow texture).
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var d: float = clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var t := pow(1.0 - d, 1.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, t))
	return ImageTexture.create_from_image(img)

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
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _shared_radial_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	return q

## Smoke-only quad: smoke puffs get their OWN size — the shared 0.35 m
## _quad_mesh above must NEVER change (all other emitters depend on it).
## Same v2.1.0 fix pattern: TRANSPARENCY_ALPHA + shared radial texture on
## a per-emitter material, so puffs stay soft and round, never hard squares.
static func _smoke_quad_mesh(color: Color, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _shared_radial_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	return q

static func _free_later(p: GPUParticles3D, delay: float) -> void:
	var t: SceneTreeTimer = p.get_tree().create_timer(delay)
	t.timeout.connect(p.queue_free)

## White tyre smoke at the hero's rear wheels (landing / slam / nitro).
## Lane C whitening (GATE R11): near-white, larger soft puffs on their own
## 0.7 m quad — the reel's smoke is white, not grey. Call sites unchanged.
static func tyre_smoke(parent: Node, pos: Vector3) -> void:
	var p: GPUParticles3D = _make(parent, pos, 22, 0.9, 0.8)
	p.process_material = _material(Vector3(0, 1, 1), 35.0, 2.0, 5.0, Vector3(0, 1.5, 0), 0.6, 1.2, Color(0.96, 0.95, 0.94, 0.60), 2.0)
	p.draw_pass_1 = _smoke_quad_mesh(Color(0.96, 0.95, 0.94, 0.60), 0.7)
	p.emitting = true
	_free_later(p, 1.4)

## Big soft WHITE burst blooming behind the hero when a stunt completes
## (the first moment main can know a stunt happened — see SMOKE_DESIGN.md).
## Own 1.0 m quad; puffs ~0.8–1.6 m.
static func stunt_smoke_burst(parent: Node, pos: Vector3) -> void:
	var p: GPUParticles3D = _make(parent, pos, 28, 1.1, 0.85)
	p.process_material = _material(Vector3(0, 1, 1), 40.0, 2.0, 5.0, Vector3(0, 1.5, 0), 0.8, 1.6, Color(0.97, 0.96, 0.95, 0.60), 2.0)
	p.draw_pass_1 = _smoke_quad_mesh(Color(0.97, 0.96, 0.95, 0.60), 1.0)
	p.emitting = true
	_free_later(p, 1.6)

## Big soft WHITE burst on nitro activation (one per activation; the
## activation edge in main._physics_process is the only clean trigger).
## Own 1.0 m quad; puffs ~0.9–1.7 m, thrown rearward.
static func boost_smoke_burst(parent: Node, pos: Vector3) -> void:
	var p: GPUParticles3D = _make(parent, pos, 24, 1.0, 0.9)
	p.process_material = _material(Vector3(0, 0.35, 1), 45.0, 4.0, 8.0, Vector3(0, 0.8, 0), 0.9, 1.7, Color(0.97, 0.96, 0.95, 0.50), 1.2)
	p.draw_pass_1 = _smoke_quad_mesh(Color(0.97, 0.96, 0.95, 0.50), 1.0)
	p.emitting = true
	_free_later(p, 1.5)

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
