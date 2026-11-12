class_name Vehicles extends RefCounted

## Static builders for every vehicle / pickup in T Roadster.
## All geometry is original, built in-engine from boxes, prisms and
## cylinders — no imported models, no badges, no wordmarks, no text.
## Forward is -Z. The hero pickup keeps its wheels OUTSIDE "Body" so
## gameplay can rotate Body for stunts without spinning the wheels with it.

# ---------------------------------------------------------------- helpers

static func _std(albedo: Color, metallic: float, roughness: float, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m

static func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _cyl(top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material, segments: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = segments
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _prism(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _sphere(radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _wheel(radius: float, width: float, pos: Vector3) -> Node3D:
	var wheel := Node3D.new()
	wheel.position = pos
	var tyre := _cyl(radius, radius, width, Vector3.ZERO, _std(Color(0.05, 0.05, 0.06), 0.0, 0.9), 14)
	tyre.rotation_degrees = Vector3(0, 0, 90)
	wheel.add_child(tyre)
	var hub := _cyl(radius * 0.55, radius * 0.55, width + 0.02, Vector3.ZERO, _std(Color(0.55, 0.58, 0.62), 0.9, 0.3), 10)
	hub.rotation_degrees = Vector3(0, 0, 90)
	wheel.add_child(hub)
	var cap := _cyl(radius * 0.22, radius * 0.22, width + 0.04, Vector3.ZERO, _std(Color(0.15, 0.15, 0.17), 0.6, 0.4), 8)
	cap.rotation_degrees = Vector3(0, 0, 90)
	wheel.add_child(cap)
	return wheel

# ------------------------------------------------------- hero pickup

static func build_hero_pickup(paint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "HeroPickup"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	var paint_cool := paint
	var paint_metallic := 0.6
	var paint_rough := 0.25
	# Round 5 — keep near-white paint WHITE under the pink sunset.
	# The orange sun + mauve ambient + pink sky reflections (metallic
	# 0.6 mirrors the pink sky) turned the white pickup pink-mauve
	# (tailgate inset measured 190,129,137). Near-white paints get a
	# cool blue-white albedo shift and lower metallic (less pink sky
	# reflection); coloured garage skins are untouched.
	if paint.r > 0.8 and paint.g > 0.8 and paint.b > 0.8:
		paint_cool = Color(paint.r * 0.90, paint.g * 0.95, minf(paint.b * 1.04, 1.0))
		paint_metallic = 0.35
		paint_rough = 0.32
	var paint_mat := _std(paint_cool, paint_metallic, paint_rough)
	var dark_mat := _std(Color(0.08, 0.08, 0.1), 0.2, 0.6)
	var glass_mat := _std(Color(0.02, 0.02, 0.04), 0.9, 0.08)
	var trim_mat := _std(Color(0.12, 0.12, 0.14), 0.4, 0.5)

	# Main lower hull — long, flat, sharp-edged.
	body.add_child(_box(Vector3(2.0, 0.55, 4.6), Vector3(0, 0.62, 0), paint_mat))
	# Angular nose wedge (prism slopes down toward the front, -Z).
	var nose := _prism(Vector3(2.0, 0.5, 0.9), Vector3(0, 0.6, -2.35), paint_mat)
	nose.rotation_degrees = Vector3(0, 180, 0)
	body.add_child(nose)
	# Hood: shallow sloped panel.
	var hood := _box(Vector3(1.9, 0.1, 1.15), Vector3(0, 0.92, -1.55), paint_mat)
	hood.rotation_degrees = Vector3(-4, 0, 0)
	body.add_child(hood)
	# Cab block, set back from the nose.
	body.add_child(_box(Vector3(1.84, 0.52, 2.0), Vector3(0, 1.12, 0.55), paint_mat))
	# Full-width black glass band wrapping the cab.
	body.add_child(_box(Vector3(1.88, 0.34, 1.55), Vector3(0, 1.16, 0.55), glass_mat))
	# Roof panel.
	body.add_child(_box(Vector3(1.8, 0.08, 1.7), Vector3(0, 1.42, 0.55), paint_mat))
	# Open bed: floor + side walls + tailgate.
	body.add_child(_box(Vector3(1.9, 0.08, 1.35), Vector3(0, 0.92, 1.62), trim_mat))
	body.add_child(_box(Vector3(0.08, 0.42, 1.35), Vector3(-0.94, 1.1, 1.62), paint_mat))
	body.add_child(_box(Vector3(0.08, 0.42, 1.35), Vector3(0.94, 1.1, 1.62), paint_mat))
	body.add_child(_box(Vector3(1.9, 0.42, 0.08), Vector3(0, 1.1, 2.28), paint_mat))
	# Tailgate definition (rear face, +Z): a slightly darker inset
	# panel, a thin horizontal character line, and a top rail so the
	# rear reads as a tailgate + bumper, not one blank white slab.
	# Round 5 — the inset is a rear face lit by the warm fill light
	# plus the pink sky reflection, so a straight paint*0.78 still
	# read pink-mauve (207,159,181). It gets a cooler tint (R pulled
	# down hardest) and low metallic (less pink sky mirror) so the
	# shaded tailgate panel reads cool white-grey, as a white panel
	# in shadow should.
	var paint_dark_mat := _std(Color(paint_cool.r * 0.68, paint_cool.g * 0.82, paint_cool.b * 0.85), 0.2, 0.35)
	body.add_child(_box(Vector3(1.7, 0.30, 0.02), Vector3(0, 1.12, 2.325), paint_dark_mat))
	body.add_child(_box(Vector3(1.86, 0.025, 0.02), Vector3(0, 0.94, 2.325), dark_mat))
	body.add_child(_box(Vector3(1.92, 0.05, 0.10), Vector3(0, 1.33, 2.28), trim_mat))
	# Round 4 — rear definition (silhouette unchanged, all details
	# proud of the tailgate face at z=2.32 so nothing z-fights):
	# vertical panel gaps splitting the tailgate into three panels,
	# a number-plate recess + pale plate on the valance, a chrome
	# exhaust tip bottom-right, a tread step on the bumper top, dark
	# bed rail caps along both bed walls, and red wrap-around corner
	# pods on the bed sides so the taillights turn the corner.
	var gap_mat := dark_mat
	body.add_child(_box(Vector3(0.015, 0.26, 0.015), Vector3(-0.55, 1.12, 2.338), gap_mat))
	body.add_child(_box(Vector3(0.015, 0.26, 0.015), Vector3(0.55, 1.12, 2.338), gap_mat))
	body.add_child(_box(Vector3(1.7, 0.015, 0.015), Vector3(0, 0.985, 2.338), gap_mat))
	# Number plate: dark recess, then a pale plate inside it.
	body.add_child(_box(Vector3(0.56, 0.17, 0.02), Vector3(0, 0.66, 2.325), dark_mat))
	body.add_child(_box(Vector3(0.46, 0.11, 0.015), Vector3(0, 0.66, 2.34), _std(Color(0.85, 0.85, 0.80), 0.2, 0.5)))
	# Exhaust tip: chrome cylinder poking out under the bumper right.
	var chrome_mat := _std(Color(0.7, 0.7, 0.72), 0.9, 0.25)
	var exhaust := _cyl(0.06, 0.06, 0.14, Vector3(0.62, 0.34, 2.42), chrome_mat, 10)
	exhaust.rotation_degrees = Vector3(90, 0, 0)
	body.add_child(exhaust)
	var exhaust_inner := _cyl(0.045, 0.045, 0.15, Vector3(0.62, 0.34, 2.42), dark_mat, 8)
	exhaust_inner.rotation_degrees = Vector3(90, 0, 0)
	body.add_child(exhaust_inner)
	# Bumper tread step: a dark grip strip across the bumper top.
	body.add_child(_box(Vector3(1.6, 0.03, 0.18), Vector3(0, 0.46, 2.34), dark_mat))
	# Bed rail caps: dark caps on top of both bed side walls.
	body.add_child(_box(Vector3(0.10, 0.04, 1.35), Vector3(-0.94, 1.33, 1.62), trim_mat))
	body.add_child(_box(Vector3(0.10, 0.04, 1.35), Vector3(0.94, 1.33, 1.62), trim_mat))
	# Wrap-around rear corner pods (red, emissive) on the bed sides.
	# Round 6 — emission (1.0,0.02,0.02) @ 1.0 measured orange-red
	# (255,60,36): the G comes from ACES desaturation of the bright
	# red + the warm fill on the 0.35 albedo. Pure-red emission,
	# darker albedo, slightly lower energy for a DEEP red.
	var pod_mat := _std(Color(0.20, 0.0, 0.0), 0.0, 0.2, Color(1.0, 0.0, 0.0), 0.85)
	body.add_child(_box(Vector3(0.03, 0.14, 0.30), Vector3(-0.99, 0.86, 2.05), pod_mat))
	body.add_child(_box(Vector3(0.03, 0.14, 0.30), Vector3(0.99, 0.86, 2.05), pod_mat))
	# Dark lower rear panel: two-tone rear (white tailgate above,
	# dark valance below) so the back has shape at a glance. Uses its
	# own lighter grey — the shared trim_mat rendered as a black hole
	# on the sunless rear face.
	# Round 6 — 0.28 -> 0.38: the valance still read as a near-black
	# band under the hero; it must read as dark GREY with shape.
	var rear_panel_mat := _std(Color(0.38, 0.38, 0.42), 0.3, 0.55)
	body.add_child(_box(Vector3(1.9, 0.28, 0.02), Vector3(0, 0.62, 2.31), rear_panel_mat))
	# Bed roll bar.
	body.add_child(_box(Vector3(1.7, 0.07, 0.07), Vector3(0, 1.52, 0.95), dark_mat))
	body.add_child(_box(Vector3(0.07, 0.55, 0.07), Vector3(-0.8, 1.28, 0.95), dark_mat))
	body.add_child(_box(Vector3(0.07, 0.55, 0.07), Vector3(0.8, 1.28, 0.95), dark_mat))
	# Side skirts + wheel-arch trim.
	body.add_child(_box(Vector3(0.06, 0.18, 4.3), Vector3(-1.0, 0.42, 0), trim_mat))
	body.add_child(_box(Vector3(0.06, 0.18, 4.3), Vector3(1.0, 0.42, 0), trim_mat))
	# Front grille (dark, no logo) + bumpers.
	body.add_child(_box(Vector3(1.7, 0.22, 0.08), Vector3(0, 0.62, -2.78), dark_mat))
	body.add_child(_box(Vector3(2.02, 0.16, 0.22), Vector3(0, 0.38, -2.72), trim_mat))
	# Round 6 — the REAR bumper was the near-black band under the
	# hero (dark_mat 0.08 on a sunless rear face). It gets its own
	# mid-grey material so the rear bottom reads as dark grey with
	# shape, not a black hole; the front bumper keeps dark_mat.
	var bumper_mat := _std(Color(0.32, 0.32, 0.35), 0.3, 0.5)
	body.add_child(_box(Vector3(2.04, 0.18, 0.24), Vector3(0, 0.36, 2.34), bumper_mat))
	# Side mirrors.
	body.add_child(_box(Vector3(0.16, 0.12, 0.22), Vector3(-1.02, 1.18, -0.15), dark_mat))
	body.add_child(_box(Vector3(0.16, 0.12, 0.22), Vector3(1.02, 1.18, -0.15), dark_mat))

	# Full-width front light bar (emissive white) + rear red bar.
	var front_light := _box(Vector3(1.86, 0.09, 0.06), Vector3(0, 0.82, -2.8), _std(Color(1, 1, 1), 0.0, 0.2, Color(1.0, 0.98, 0.9), 4.0))
	front_light.name = "HeadlightBar"
	body.add_child(front_light)
	# Rear light bar: taller, brighter, proud of the tailgate so it
	# actually reads from the chase camera, plus red corner pods.
	# Emission is a DEEP red (1.0, 0.0, 0.0) at 0.85 — Round 6:
	# (1.0,0.02,0.02) @ 1.0 measured orange-red (255,60,36); the G
	# came from ACES desaturation of the bright red plus the warm
	# fill light on the 0.35 albedo. Pure-red emission, darker
	# albedo (0.20) and slightly lower energy push it back toward
	# deep red without re-blooming it white.
	var rear_light := _box(Vector3(1.9, 0.16, 0.05), Vector3(0, 0.86, 2.335), _std(Color(0.20, 0.0, 0.0), 0.0, 0.2, Color(1.0, 0.0, 0.0), 0.85))
	rear_light.name = "TaillightBar"
	body.add_child(rear_light)
	body.add_child(_box(Vector3(0.16, 0.16, 0.05), Vector3(-0.86, 0.86, 2.335), _std(Color(0.20, 0.0, 0.0), 0.0, 0.2, Color(1.0, 0.0, 0.0), 0.85)))
	body.add_child(_box(Vector3(0.16, 0.16, 0.05), Vector3(0.86, 0.86, 2.335), _std(Color(0.20, 0.0, 0.0), 0.0, 0.2, Color(1.0, 0.0, 0.0), 0.85)))
	# Headlight corner pods.
	body.add_child(_box(Vector3(0.34, 0.12, 0.06), Vector3(-0.72, 0.62, -2.8), _std(Color(1, 1, 1), 0.0, 0.2, Color(1.0, 0.98, 0.9), 3.0)))
	body.add_child(_box(Vector3(0.34, 0.12, 0.06), Vector3(0.72, 0.62, -2.8), _std(Color(1, 1, 1), 0.0, 0.2, Color(1.0, 0.98, 0.9), 3.0)))

	# Warm underglow: a SMALL soft pool of light under the car, not a
	# pink rug. Radial-gradient texture (alpha fades to zero at the
	# edges) + low alpha + low emission, so it reads as glow, not a slab.
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_texture = _make_glow_texture(128)
	glow_mat.albedo_color = Color(1.0, 0.45, 0.55, 0.28)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.4, 0.5)
	glow_mat.emission_energy_multiplier = 0.5
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow := MeshInstance3D.new()
	var glow_mesh := PlaneMesh.new()
	glow_mesh.size = Vector2(2.4, 4.6)
	glow_mesh.material = glow_mat
	glow.mesh = glow_mesh
	glow.position = Vector3(0, 0.04, 0)
	glow.name = "Underglow"
	body.add_child(glow)

	# Wheels (siblings of Body — Body rotates for stunts, wheels stay put).
	var wheels := Node3D.new()
	wheels.name = "Wheels"
	root.add_child(wheels)
	var fl := _wheel(0.38, 0.3, Vector3(-0.95, 0.38, -1.45))
	fl.name = "WheelFL"
	var fr := _wheel(0.38, 0.3, Vector3(0.95, 0.38, -1.45))
	fr.name = "WheelFR"
	var rl := _wheel(0.38, 0.3, Vector3(-0.95, 0.38, 1.45))
	rl.name = "WheelRL"
	var rr := _wheel(0.38, 0.3, Vector3(0.95, 0.38, 1.45))
	rr.name = "WheelRR"
	wheels.add_child(fl)
	wheels.add_child(fr)
	wheels.add_child(rl)
	wheels.add_child(rr)
	return root

# ------------------------------------------------------- traffic cars

static func build_traffic_car(kind: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Traffic_" + kind
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	var paint_mat := _std(color, 0.65, 0.28)
	var dark_mat := _std(Color(0.08, 0.08, 0.1), 0.2, 0.6)
	var glass_mat := _std(Color(0.03, 0.03, 0.05), 0.9, 0.1)

	var length := 4.4
	var width := 1.9
	var cab_len := 2.0
	var cab_z := 0.3
	match kind:
		"sedan":
			pass # Defaults above are the sedan (4.4 m, 1.9 m, 2.0 m cab).
		"hatch":
			length = 3.9
			cab_len = 2.2
			cab_z = 0.1
		"van":
			length = 4.7
			width = 2.0
			cab_len = 3.4
			cab_z = 0.2
		"truck":
			length = 6.0
			width = 2.2
			cab_len = 1.6
			cab_z = -1.9
		"semi":
			length = 9.5
			width = 2.4
			cab_len = 1.8
			cab_z = -3.6

	# Lower hull.
	body.add_child(_box(Vector3(width, 0.6, length), Vector3(0, 0.6, 0), paint_mat))
	if kind == "truck" or kind == "semi":
		# Cab up front + tall cargo box / trailer behind.
		body.add_child(_box(Vector3(width * 0.92, 0.85, cab_len), Vector3(0, 1.25, cab_z), paint_mat))
		body.add_child(_box(Vector3(width * 0.9, 0.5, cab_len * 0.7), Vector3(0, 1.3, cab_z), glass_mat))
		var box_len := length - cab_len - 1.2
		var box_z := cab_z + cab_len * 0.5 + box_len * 0.5 + 0.6
		var box_mat := _std(Color(0.75, 0.74, 0.72), 0.3, 0.55) if kind == "truck" else _std(Color(0.55, 0.58, 0.62), 0.7, 0.4)
		body.add_child(_box(Vector3(width, 2.1, box_len), Vector3(0, 1.45, box_z), box_mat))
		body.add_child(_box(Vector3(width, 0.12, box_len), Vector3(0, 2.52, box_z), dark_mat))
	else:
		# Cabin + glasshouse.
		var cab_h := 0.55 if kind == "van" else 0.45
		body.add_child(_box(Vector3(width * 0.9, cab_h, cab_len), Vector3(0, 1.1, cab_z), paint_mat))
		body.add_child(_box(Vector3(width * 0.92, cab_h * 0.62, cab_len * 0.72), Vector3(0, 1.12, cab_z), glass_mat))
		# Roof.
		body.add_child(_box(Vector3(width * 0.88, 0.07, cab_len * 0.95), Vector3(0, 1.38 if kind == "van" else 1.34, cab_z), paint_mat))

	# Headlights (dim, off) + grille.
	body.add_child(_box(Vector3(0.4, 0.12, 0.06), Vector3(-width * 0.32, 0.62, -length * 0.5 - 0.01), _std(Color(0.9, 0.9, 0.8), 0.0, 0.3, Color(0.9, 0.9, 0.8), 0.4)))
	body.add_child(_box(Vector3(0.4, 0.12, 0.06), Vector3(width * 0.32, 0.62, -length * 0.5 - 0.01), _std(Color(0.9, 0.9, 0.8), 0.0, 0.3, Color(0.9, 0.9, 0.8), 0.4)))
	body.add_child(_box(Vector3(width * 0.6, 0.18, 0.06), Vector3(0, 0.5, -length * 0.5 - 0.01), dark_mat))

	# Brake lights — each gets its OWN material so set_brake_lights can
	# toggle one car without lighting up every car on the road.
	# Idle emission is 0.55, not 0.15: a car driving into the sunset
	# shows its red rear lamps even when it is not braking, and at
	# 0.15 the lamps were invisible against the dark rear.
	var rear_z := length * 0.5 + 0.01
	var brake_l := _box(Vector3(0.5, 0.16, 0.06), Vector3(-width * 0.32, 0.78, rear_z), _std(Color(0.6, 0.02, 0.02), 0.0, 0.3, Color(1.0, 0.05, 0.05), 0.55))
	brake_l.name = "BrakeL"
	body.add_child(brake_l)
	var brake_r := _box(Vector3(0.5, 0.16, 0.06), Vector3(width * 0.32, 0.78, rear_z), _std(Color(0.6, 0.02, 0.02), 0.0, 0.3, Color(1.0, 0.05, 0.05), 0.55))
	brake_r.name = "BrakeR"
	body.add_child(brake_r)
	# Thin red reflector strip across the rear, low glow: a continuous
	# red line so the rear reads as a car back even at a glance.
	body.add_child(_box(Vector3(width * 0.8, 0.06, 0.04), Vector3(0, 0.62, rear_z), _std(Color(0.5, 0.03, 0.03), 0.0, 0.3, Color(1.0, 0.06, 0.06), 0.25)))

	# Indicators (amber, front + rear, per side).
	for side in [-1, 1]:
		var tag := "L" if side < 0 else "R"
		var ind_f := _box(Vector3(0.18, 0.1, 0.06), Vector3(side * width * 0.42, 0.62, -length * 0.5 - 0.01), _std(Color(0.8, 0.4, 0.0), 0.0, 0.3, Color(1.0, 0.55, 0.0), 0.12))
		ind_f.name = "IndicatorF" + tag
		body.add_child(ind_f)
		var ind_r := _box(Vector3(0.18, 0.1, 0.06), Vector3(side * width * 0.42, 0.78, rear_z), _std(Color(0.8, 0.4, 0.0), 0.0, 0.3, Color(1.0, 0.55, 0.0), 0.12))
		ind_r.name = "IndicatorR" + tag
		body.add_child(ind_r)

	# Wheels (static — traffic does not need spinning wheels, keep it cheap).
	var wheels := Node3D.new()
	wheels.name = "Wheels"
	root.add_child(wheels)
	var wheel_z := length * 0.32
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var w := _wheel(0.34, 0.26, Vector3(sx * (width * 0.5 - 0.05), 0.34, sz * wheel_z))
			wheels.add_child(w)
	return root

static func set_brake_lights(car: Node3D, on: bool) -> void:
	if car == null:
		return
	var body := car.get_node_or_null("Body")
	if body == null:
		return
	for light_name in ["BrakeL", "BrakeR"]:
		var mi := body.get_node_or_null(light_name) as MeshInstance3D
		if mi == null:
			continue
		var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if m == null:
			continue
		m.emission_enabled = true
		m.emission_energy_multiplier = 1.2 if on else 0.55

static func set_indicator(car: Node3D, side: int, on: bool) -> void:
	if car == null:
		return
	var body := car.get_node_or_null("Body")
	if body == null:
		return
	var tags: Array[String] = []
	if side < 0:
		tags = ["L"]
	elif side > 0:
		tags = ["R"]
	else:
		tags = ["L", "R"]
	for tag in tags:
		for part in ["IndicatorF" + tag, "IndicatorR" + tag]:
			var mi := body.get_node_or_null(part) as MeshInstance3D
			if mi == null:
				continue
			var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if m == null:
				continue
			m.emission_enabled = true
			m.emission_energy_multiplier = 2.5 if on else 0.12

# ------------------------------------------------------- pickups

static func _coin(color: Color, rim: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Coin"
	var face_mat := _std(color, 0.95, 0.18, color, 0.35)
	var coin := _cyl(0.35, 0.35, 0.08, Vector3.ZERO, face_mat, 20)
	coin.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(coin)
	var rim_mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.27
	torus.outer_radius = 0.35
	torus.rings = 8
	torus.ring_segments = 20
	torus.material = _std(rim, 0.9, 0.25)
	rim_mesh.mesh = torus
	root.add_child(rim_mesh)
	var hub := _cyl(0.12, 0.12, 0.1, Vector3.ZERO, _std(rim, 0.9, 0.2), 10)
	hub.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(hub)
	return root

static func build_coin() -> Node3D:
	return _coin(Color(1.0, 0.78, 0.15), Color(0.85, 0.6, 0.08))

static func build_air_coin() -> Node3D:
	return _coin(Color(0.25, 0.65, 1.0), Color(0.1, 0.4, 0.9))

static func build_pickup_orb(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Orb_" + kind
	var core_color := Color(1.0, 0.5, 0.1)
	if kind == "starman":
		core_color = Color(1.0, 0.85, 0.25)
	var core := _sphere(0.42, Vector3.ZERO, _std(core_color, 0.0, 0.2, core_color, 3.0))
	root.add_child(core)
	var shell_mat := StandardMaterial3D.new()
	shell_mat.albedo_color = Color(core_color.r, core_color.g, core_color.b, 0.22)
	shell_mat.emission_enabled = true
	shell_mat.emission = core_color
	shell_mat.emission_energy_multiplier = 0.8
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shell := _sphere(0.62, Vector3.ZERO, shell_mat)
	root.add_child(shell)
	# Inner spark: small bright octahedron-ish core (a rotated box reads
	# as a gem at speed and costs almost nothing).
	var gem := _box(Vector3(0.22, 0.22, 0.22), Vector3.ZERO, _std(Color(1, 1, 1), 0.0, 0.1, Color(1, 1, 1), 4.0))
	gem.rotation_degrees = Vector3(45, 45, 0)
	root.add_child(gem)
	return root

static func _make_glow_texture(size: int) -> ImageTexture:
	# Soft radial falloff: hot centre, transparent edges. Used by the
	# hero underglow so it reads as light pooling under the car.
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var d: float = clamp(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var t := pow(1.0 - d, 1.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, t))
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------- palm tree

static func build_palm() -> Node3D:
	var root := Node3D.new()
	root.name = "Palm"
	var trunk_mat := _std(Color(0.45, 0.30, 0.17), 0.0, 0.85)
	# Fronds must read GREEN, not yellow umbrellas: deep green albedo,
	# a faint GREEN (not orange) emission lift, and two alternating
	# shades so individual leaves separate from each other.
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.07, 0.40, 0.15)
	leaf_mat.roughness = 0.6
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat.emission_enabled = true
	leaf_mat.emission = Color(0.05, 0.25, 0.08)
	leaf_mat.emission_energy_multiplier = 0.15
	var leaf_mat2 := StandardMaterial3D.new()
	leaf_mat2.albedo_color = Color(0.05, 0.30, 0.11)
	leaf_mat2.roughness = 0.6
	leaf_mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat2.emission_enabled = true
	leaf_mat2.emission = Color(0.04, 0.20, 0.06)
	leaf_mat2.emission_energy_multiplier = 0.15
	# Third, darker shade for the under-ring: leaves in shadow under
	# the crown, so close-ups get a dark layer beneath the lit fronds.
	var leaf_mat3 := StandardMaterial3D.new()
	leaf_mat3.albedo_color = Color(0.03, 0.18, 0.07)
	leaf_mat3.roughness = 0.7
	leaf_mat3.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat3.emission_enabled = true
	leaf_mat3.emission = Color(0.02, 0.12, 0.04)
	leaf_mat3.emission_energy_multiplier = 0.15
	var nut_mat := _std(Color(0.35, 0.22, 0.1), 0.0, 0.8)

	# Bent trunk: 5 stacked tapering segments following ONE smooth
	# curve. Each segment's centre is placed along the tangent of the
	# previous one, so the segments join end-to-end with no step — the
	# old code added a fixed +0.14 x per segment while barely rotating
	# them (0.64 deg/step), so the trunk read as a zigzag of offset
	# boxes. Total lean ~8 deg, same reach as before, now smooth.
	var bx := 0.0
	var by := 0.0
	var lean_total := 0.14
	for i in range(5):
		var theta := lean_total * float(i) / 4.0
		var r_top := 0.16 - float(i) * 0.018
		var r_bot := 0.18 - float(i) * 0.018
		var seg := _cyl(r_top, r_bot, 0.95, Vector3.ZERO, trunk_mat, 7)
		seg.rotation_degrees = Vector3(0, 0, -rad_to_deg(theta))
		seg.position = Vector3(bx + sin(theta) * 0.475, by + cos(theta) * 0.475, 0)
		root.add_child(seg)
		bx += sin(theta) * 0.95
		by += cos(theta) * 0.95
	var top := Vector3(bx, by + 0.15, 0)

	# Fronds: three rings of individual drooping leaf planes. Each leaf
	# is a shallow V-fold (two halves tilted +/-30 deg around the
	# midrib) with its own length / droop / roll jitter, and alternates
	# between green shades; the third ring hangs steeply down in a
	# darker shade as an under-layer. The crown reads as separate
	# leaves with real depth, not one flat slab.
	var ring_defs := [
		[8, 1.9, -28.0, 0.10],
		[5, 1.3, -55.0, 0.28],
		[6, 1.05, -72.0, 0.02],
	]
	for ring in range(3):
		var ring_def: Array = ring_defs[ring]
		var count: int = ring_def[0]
		var length: float = ring_def[1]
		var droop: float = ring_def[2]
		var ring_y: float = top.y + ring_def[3]
		for i in range(count):
			var jitter := float((i * 37 + ring * 61) % 10) / 10.0 - 0.5
			var leaf_len := length * (1.0 + jitter * 0.25)
			var leaf_droop := droop + jitter * 28.0
			var roll := jitter * 36.0
			var lm: StandardMaterial3D = leaf_mat3 if ring == 2 else (leaf_mat if (i + ring) % 2 == 0 else leaf_mat2)
			var pivot := Node3D.new()
			pivot.position = Vector3(top.x, ring_y, top.z)
			pivot.rotation_degrees = Vector3(0, float(i) * (360.0 / float(count)) + float(ring) * 22.0, 0)
			root.add_child(pivot)
			# V-fold: two halves, outer edges tilted down from the
			# midrib, plus the per-leaf roll so no two leaves sit flat.
			var half_w := 0.24
			var leaf_a := _box(Vector3(leaf_len, 0.05, half_w), Vector3(leaf_len * 0.5, 0.05, -half_w * 0.46), lm)
			leaf_a.rotation_degrees = Vector3(-30.0 + roll, 0, leaf_droop)
			pivot.add_child(leaf_a)
			var leaf_b := _box(Vector3(leaf_len, 0.05, half_w), Vector3(leaf_len * 0.5, 0.05, half_w * 0.46), lm)
			leaf_b.rotation_degrees = Vector3(30.0 + roll, 0, leaf_droop)
			pivot.add_child(leaf_b)
			# Leaf tip flicks back up slightly (second segment).
			var tip := _box(Vector3(leaf_len * 0.35, 0.04, 0.3), Vector3(leaf_len * 0.92, -0.28, 0), lm)
			tip.rotation_degrees = Vector3(roll * 0.5, 0, leaf_droop - 22.0)
			pivot.add_child(tip)

	# Coconut cluster under the crown.
	for i in range(3):
		var a := float(i) * 2.1
		root.add_child(_sphere(0.11, top + Vector3(cos(a) * 0.18, -0.18, sin(a) * 0.18), nut_mat))
	return root
