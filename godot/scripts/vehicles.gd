class_name Vehicles extends RefCounted

## Static builders for every vehicle / pickup in T Roadster.
## All geometry is original, built in-engine from boxes, prisms and
## cylinders — no imported models, no badges, no wordmarks, no text.
## Forward is -Z. The hero pickup keeps its wheels OUTSIDE "Body" so
## gameplay can rotate Body for stunts without spinning the wheels with it.

# ---------------------------------------------------------------- helpers

# Per-invocation caches (Lane A rebuild): _std/_box/_cyl/_prism/_sphere
# share mesh/material resources WITHIN one builder call only. Every
# public builder calls _cache_begin() on entry and _cache_end() before
# returning, so nothing is ever shared across instances — two heroes /
# two traffic cars always get distinct resources. Brake, indicator and
# paint materials are ALWAYS per-instance: brake/indicator parts use
# _std_fresh() + _box_uniq(), which bypass both caches entirely, because
# set_brake_lights/set_indicator mutate the mesh's surface material (a
# shared material would light every car, or both indicator sides).
static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}
# Global (cross-instance) shares — allowed ONLY where nothing ever
# mutates the resource: the glow texture and the 5 palm materials.
static var _glow_tex_cache: Dictionary = {}
static var _palm_trunk_mat: StandardMaterial3D = null
static var _palm_leaf_mat: StandardMaterial3D = null
static var _palm_leaf_mat2: StandardMaterial3D = null
static var _palm_leaf_mat3: StandardMaterial3D = null
static var _palm_nut_mat: StandardMaterial3D = null

static func _cache_begin() -> void:
	_mat_cache.clear()
	_mesh_cache.clear()

static func _cache_end() -> void:
	_mat_cache.clear()
	_mesh_cache.clear()

static func _std(albedo: Color, metallic: float, roughness: float, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var key: Array = [albedo.r, albedo.g, albedo.b, albedo.a, metallic, roughness, emission.r, emission.g, emission.b, emission_energy]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := _std_fresh(albedo, metallic, roughness, emission, emission_energy)
	_mat_cache[key] = m
	return m

static func _std_fresh(albedo: Color, metallic: float, roughness: float, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m

# Merged-mesh baking: append a primitive's surface-0 arrays through a
# rigid transform into per-surface arrays, then build one ArrayMesh.
# Tangents are dropped (no normal-mapped materials in this file); the
# vertex/normal/uv/index sets are identical to the source primitives,
# so merged geometry rasterizes exactly like the separate parts.
static func _surf_new() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}

static func _bake_append(surf: Dictionary, prim: Mesh, xform: Transform3D) -> void:
	var arr: Array = prim.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var v: PackedVector3Array = surf["v"]
	var n: PackedVector3Array = surf["n"]
	var uv: PackedVector2Array = surf["uv"]
	var ii: PackedInt32Array = surf["i"]
	var base: int = v.size()
	var basis: Basis = xform.basis
	for k in range(verts.size()):
		v.append(xform * verts[k])
		if normals.size() == verts.size():
			n.append((basis * normals[k]).normalized())
		else:
			n.append(Vector3.UP)
		if uvs.size() == verts.size():
			uv.append(uvs[k])
		else:
			uv.append(Vector2.ZERO)
	if idx.size() > 0:
		for k in range(idx.size()):
			ii.append(idx[k] + base)
	else:
		for k in range(verts.size()):
			ii.append(k + base)
	surf["v"] = v
	surf["n"] = n
	surf["uv"] = uv
	surf["i"] = ii

static func _merged_mesh(surfs: Array, mats: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var added := 0
	for si in range(surfs.size()):
		var surf: Dictionary = surfs[si]
		var verts: PackedVector3Array = surf["v"]
		if verts.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = surf["n"]
		arrays[Mesh.ARRAY_TEX_UV] = surf["uv"]
		arrays[Mesh.ARRAY_INDEX] = surf["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(added, mats[si] as Material)
		added += 1
	return mesh

static func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var key: Array = ["box", size.x, size.y, size.z, mat.get_instance_id()]
	var mesh: BoxMesh = null
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key] as BoxMesh
	else:
		mesh = BoxMesh.new()
		mesh.size = size
		mesh.material = mat
		_mesh_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _box_uniq(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	# Cache bypass for brake/indicator parts: a FRESH mesh + the
	# caller's own (fresh) material, so set_brake_lights/set_indicator
	# can mutate this part's surface material without touching any
	# other part, car, or side.
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _cyl(top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material, segments: int = 10) -> MeshInstance3D:
	var key: Array = ["cyl", top_r, bottom_r, height, segments, mat.get_instance_id()]
	var mesh: CylinderMesh = null
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key] as CylinderMesh
	else:
		mesh = CylinderMesh.new()
		mesh.top_radius = top_r
		mesh.bottom_radius = bottom_r
		mesh.height = height
		mesh.radial_segments = segments
		mesh.material = mat
		_mesh_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _prism(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var key: Array = ["prism", size.x, size.y, size.z, mat.get_instance_id()]
	var mesh: PrismMesh = null
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key] as PrismMesh
	else:
		mesh = PrismMesh.new()
		mesh.size = size
		mesh.material = mat
		_mesh_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _prism_slope(size: Vector3, pos: Vector3, mat: Material, left_to_right: float, rot_y_deg: float) -> MeshInstance3D:
	# Single-slope wedge with its own FRESH mesh (never cached: the
	# apex offset is a per-mesh property, and sharing a cached mesh
	# would let one wedge's apex overwrite another's). PrismMesh's
	# ridge runs along Z with the apex moving along X (probed), so
	# callers pass rot_y_deg=90 to turn local X (slope run) into
	# world Z: left_to_right 0 puts the tall edge at +Z (rear),
	# 1 puts it at -Z (front).
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = left_to_right
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = Vector3(0, rot_y_deg, 0)
	return mi

static func _sphere(radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var key: Array = ["sphere", radius, mat.get_instance_id()]
	var mesh: SphereMesh = null
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key] as SphereMesh
	else:
		mesh = SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 12
		mesh.rings = 8
		mesh.material = mat
		_mesh_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _wheel(radius: float, width: float, pos: Vector3) -> Node3D:
	# Traffic wheel (signature + pivot contract UNCHANGED): ONE
	# MeshInstance3D with TWO surfaces (dark: tyre + cap, metal: hub),
	# so 4 wheels = 8 draws/car (was 12 MeshInstance3Ds). The merged
	# mesh is shared by a car's 4 wheels WITHIN this builder call via
	# the per-invocation cache. The cap's old mid-grey material is
	# folded into the dark surface — the hub covers the centre, so
	# the visible difference is negligible at traffic distance.
	var wheel := Node3D.new()
	wheel.position = pos
	var key: Array = ["mwheel", radius, width]
	var mesh: ArrayMesh = null
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key] as ArrayMesh
	else:
		var dark := _std(Color(0.05, 0.05, 0.06), 0.0, 0.9)
		var metal := _std(Color(0.55, 0.58, 0.62), 0.9, 0.3)
		var rot := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO)
		var surf_dark := _surf_new()
		var surf_metal := _surf_new()
		var tyre := CylinderMesh.new()
		tyre.top_radius = radius
		tyre.bottom_radius = radius
		tyre.height = width
		tyre.radial_segments = 14
		_bake_append(surf_dark, tyre, rot)
		var cap := CylinderMesh.new()
		cap.top_radius = radius * 0.22
		cap.bottom_radius = radius * 0.22
		cap.height = width + 0.04
		cap.radial_segments = 8
		_bake_append(surf_dark, cap, rot)
		var hub := CylinderMesh.new()
		hub.top_radius = radius * 0.55
		hub.bottom_radius = radius * 0.55
		hub.height = width + 0.02
		hub.radial_segments = 10
		_bake_append(surf_metal, hub, rot)
		mesh = _merged_mesh([surf_dark, surf_metal], [dark, metal])
		_mesh_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	wheel.add_child(mi)
	return wheel

static func _hero_wheel(radius: float, width: float, pos: Vector3) -> Node3D:
	# Hero-only wheel: tyre + torus rim + bright hub + 2 spokes.
	# Returns an UNNAMED pivot (the caller names it WheelFL/FR/RL/RR);
	# player.gd spins it via rotation.x, so ALL geometry lives on the
	# X axis. TorusMesh defaults to the Y axis (thin axis Y, probed)
	# — the rim is rotated Z 90 deg into the YZ wheel plane, or it
	# renders as a horizontal donut. Rim + spokes sit on the OUTBOARD
	# face (sign of pos.x): the tyre is a capped solid, so a centred
	# rim would be hidden inside it.
	var wheel := Node3D.new()
	wheel.position = pos
	var out := 1.0 if pos.x >= 0.0 else -1.0
	var tyre_mat := _std(Color(0.05, 0.05, 0.06), 0.0, 0.9)
	var rim_mat := _std(Color(0.62, 0.64, 0.68), 0.9, 0.3)
	var hub_mat := _std(Color(0.82, 0.82, 0.85), 0.9, 0.2)
	var spoke_mat := _std(Color(0.35, 0.36, 0.39), 0.8, 0.35)
	var tyre := _cyl(radius, radius, width, Vector3.ZERO, tyre_mat, 20)
	tyre.rotation_degrees = Vector3(0, 0, 90)
	wheel.add_child(tyre)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.45
	torus.outer_radius = radius * 0.69
	torus.rings = 8
	torus.ring_segments = 20
	torus.material = rim_mat
	rim.mesh = torus
	rim.position = Vector3(out * (width * 0.5 - 0.02), 0, 0)
	rim.rotation_degrees = Vector3(0, 0, 90)
	wheel.add_child(rim)
	var hub := _cyl(radius * 0.33, radius * 0.33, width + 0.06, Vector3.ZERO, hub_mat, 12)
	hub.rotation_degrees = Vector3(0, 0, 90)
	wheel.add_child(hub)
	var spoke_len := radius * 1.28
	for k in range(2):
		var spoke := _box(Vector3(0.05, spoke_len, 0.12), Vector3(out * (width * 0.5 - 0.01), 0, 0), spoke_mat)
		spoke.rotation_degrees = Vector3(90.0 * float(k), 0, 0)
		wheel.add_child(spoke)
	return wheel

# ------------------------------------------------------- hero pickup

static func build_hero_pickup(paint: Color) -> Node3D:
	_cache_begin()
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
	# Two-tone lower band: the cooled paint darkened x0.85, same
	# metallic/roughness as the main paint.
	var paint_low_mat := _std(Color(paint_cool.r * 0.85, paint_cool.g * 0.85, paint_cool.b * 0.85), paint_metallic, paint_rough)
	var dark_mat := _std(Color(0.08, 0.08, 0.1), 0.2, 0.6)
	# Lane A — glass no longer mirrors the pink sky: metallic 0.45 /
	# roughness 0.22 / dark blue-grey albedo, so the glasshouse reads
	# dark glass instead of a pale mirror.
	var glass_mat := _std(Color(0.03, 0.05, 0.08), 0.45, 0.22)
	var trim_mat := _std(Color(0.12, 0.12, 0.14), 0.4, 0.5)

	# Two-tone hull: darker lower band (paint x0.85) with the main
	# paint above it, so the lower body reads as a separate band.
	body.add_child(_box(Vector3(2.0, 0.28, 4.6), Vector3(0, 0.44, 0), paint_low_mat))
	body.add_child(_box(Vector3(1.94, 0.40, 4.6), Vector3(0, 0.70, 0), paint_mat))
	# Angular nose wedge (prism slopes down toward the front, -Z).
	var nose := _prism(Vector3(2.0, 0.5, 0.9), Vector3(0, 0.6, -2.35), paint_mat)
	nose.rotation_degrees = Vector3(0, 180, 0)
	body.add_child(nose)
	# Hood: shallow sloped panel.
	var hood := _box(Vector3(1.9, 0.1, 1.15), Vector3(0, 0.92, -1.55), paint_mat)
	hood.rotation_degrees = Vector3(-4, 0, 0)
	body.add_child(hood)
	# Raked cab: narrower lower cab, two sloped glass prisms
	# (windshield 25 deg, rear glass 27 deg), a narrower/shorter roof,
	# side glass, and a dark inner block so no see-through gaps show
	# between the glass prisms at glancing angles.
	body.add_child(_box(Vector3(1.70, 0.30, 1.90), Vector3(0, 1.03, 0.55), paint_mat))
	body.add_child(_box(Vector3(1.50, 0.24, 1.50), Vector3(0, 1.30, 0.50), dark_mat))
	# PrismMesh's ridge runs along Z with the apex moving along X
	# (probed: left_to_right 0 -> apex x=-half, 1 -> +half), so the
	# glass wedges are rotated Y 90 deg: local X (slope run) becomes
	# world Z. Windshield: tall edge at the rear (roof), sloping down
	# to the hood. Rear glass: tall edge at the front, sloping down
	# to the bed — the inset rear window, narrower than the cab.
	body.add_child(_prism_slope(Vector3(0.55, 0.26, 1.62), Vector3(0, 1.31, -0.12), glass_mat, 0.0, 90.0))
	body.add_child(_prism_slope(Vector3(0.50, 0.26, 1.62), Vector3(0, 1.31, 1.10), glass_mat, 1.0, 90.0))
	# Side glass. (No A/C pillar boxes: an earlier iteration had
	# them, and their white slabs covered the prisms' sloped side
	# profiles and killed the rake read from the side. The prisms'
	# triangles + the narrower roof carry the glasshouse shape.)
	body.add_child(_box(Vector3(0.04, 0.26, 0.75), Vector3(-0.80, 1.31, 0.50), glass_mat))
	body.add_child(_box(Vector3(0.04, 0.26, 0.75), Vector3(0.80, 1.31, 0.50), glass_mat))
	# Roof panel: narrower and shorter than before.
	body.add_child(_box(Vector3(1.50, 0.07, 0.85), Vector3(0, 1.455, 0.50), paint_mat))
	# Open bed: darker floor + lower side walls (0.30 m) + tailgate.
	body.add_child(_box(Vector3(1.9, 0.08, 1.35), Vector3(0, 0.92, 1.62), dark_mat))
	body.add_child(_box(Vector3(0.08, 0.30, 1.35), Vector3(-0.94, 1.11, 1.62), paint_mat))
	body.add_child(_box(Vector3(0.08, 0.30, 1.35), Vector3(0.94, 1.11, 1.62), paint_mat))
	# Tailgate in THREE bands (>=0.12 m each): the old flat tailgate
	# with micro-detail (0.015 m gaps, 0.025 m line) was below
	# resolution at chase distance, so the gaps and the thin line are
	# DELETED; the bands + one 0.06 m crease + two 0.04 m vertical
	# creases carry the rear definition instead. The tailgate face
	# stays at z=2.32 (same as before), so the exhaust anchor
	# (0, 0.55, 2.3 in player space) keeps its old relationship to
	# the rear face. All details stay proud of the face so nothing
	# z-fights.
	# Round 5 — the shaded tailgate panel is a rear face lit by the
	# warm fill light plus the pink sky reflection, so a straight
	# paint*0.78 still read pink-mauve (207,159,181). It gets a
	# cooler tint (R pulled down hardest) and low metallic (less pink
	# sky mirror) so the shaded tailgate panel reads cool white-grey,
	# as a white panel in shadow should.
	var paint_dark_mat := _std(Color(paint_cool.r * 0.68, paint_cool.g * 0.82, paint_cool.b * 0.85), 0.2, 0.35)
	# Lead tuning 2026-11-12: the tailgate creases in near-black dark_mat
	# read as a bold black cross at chase distance (coastal + neon
	# renders). Mid-grey seam tone — visible definition, not a bar.
	var crease_mat := _std(Color(0.42, 0.42, 0.46), 0.2, 0.5)
	body.add_child(_box(Vector3(1.9, 0.14, 0.08), Vector3(0, 1.24, 2.28), paint_mat))
	body.add_child(_box(Vector3(1.9, 0.14, 0.08), Vector3(0, 1.10, 2.28), paint_dark_mat))
	body.add_child(_box(Vector3(1.9, 0.14, 0.08), Vector3(0, 0.96, 2.28), paint_mat))
	body.add_child(_box(Vector3(1.92, 0.05, 0.10), Vector3(0, 1.285, 2.28), trim_mat))
	body.add_child(_box(Vector3(1.70, 0.06, 0.015), Vector3(0, 1.10, 2.325), crease_mat))
	body.add_child(_box(Vector3(0.04, 0.30, 0.015), Vector3(-0.55, 1.10, 2.325), crease_mat))
	body.add_child(_box(Vector3(0.04, 0.30, 0.015), Vector3(0.55, 1.10, 2.325), crease_mat))
	# Round 4 — rear definition kept: a number-plate recess + pale
	# plate on the valance, a chrome exhaust tip bottom-right, a
	# tread step on the bumper top, dark bed rail caps along both bed
	# walls, and red wrap-around corner pods on the bed sides so the
	# taillights turn the corner.
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
	body.add_child(_box(Vector3(0.10, 0.04, 1.35), Vector3(-0.94, 1.28, 1.62), trim_mat))
	body.add_child(_box(Vector3(0.10, 0.04, 1.35), Vector3(0.94, 1.28, 1.62), trim_mat))
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
	# Bed roll bar: crossbar BELOW the roofline (roof top 1.49), legs
	# rising from the bed floor behind the cab.
	body.add_child(_box(Vector3(1.7, 0.07, 0.07), Vector3(0, 1.41, 1.58), dark_mat))
	body.add_child(_box(Vector3(0.07, 0.42, 0.07), Vector3(-0.8, 1.17, 1.58), dark_mat))
	body.add_child(_box(Vector3(0.07, 0.42, 0.07), Vector3(0.8, 1.17, 1.58), dark_mat))
	# Split side skirts (3 segments per side, gaps at the wheels) +
	# front fender brows, rear haunches, dark wheel-well insets and
	# one side character line per side. ALL under Body: they rotate
	# with the body in stunts; only tyre/rim/spokes live under the
	# wheel pivots.
	for side in [-1, 1]:
		var sx := float(side)
		body.add_child(_box(Vector3(0.08, 0.18, 0.50), Vector3(sx * 1.0, 0.40, -2.20), trim_mat))
		body.add_child(_box(Vector3(0.08, 0.18, 1.90), Vector3(sx * 1.0, 0.40, 0), trim_mat))
		body.add_child(_box(Vector3(0.08, 0.18, 0.50), Vector3(sx * 1.0, 0.40, 2.20), trim_mat))
		body.add_child(_box(Vector3(0.38, 0.09, 1.05), Vector3(sx * 1.03, 0.87, -1.45), paint_mat))
		var haunch := _box(Vector3(0.30, 0.10, 0.95), Vector3(sx * 1.02, 0.88, 1.45), paint_mat)
		haunch.rotation_degrees = Vector3(-12, 0, 0)
		body.add_child(haunch)
		# Wheel-well insets: shadow pockets SMALLER than the tyre, so
		# the dark shows at the tyre's sides only — a full-size panel
		# read as a black slab from the side.
		body.add_child(_box(Vector3(0.05, 0.60, 0.90), Vector3(sx * 0.98, 0.44, -1.45), dark_mat))
		body.add_child(_box(Vector3(0.05, 0.60, 0.90), Vector3(sx * 0.98, 0.44, 1.45), dark_mat))
		var charline := _box(Vector3(0.03, 0.05, 3.20), Vector3(sx * 0.975, 0.74, -0.20), trim_mat)
		charline.rotation_degrees = Vector3(-2, 0, 0)
		body.add_child(charline)
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
	# Wider track (x=+-1.02) + bigger wheels (r=0.42) so the wheels
	# stand proud of the 2.0 m hull and read from the chase camera.
	var wheels := Node3D.new()
	wheels.name = "Wheels"
	root.add_child(wheels)
	var fl := _hero_wheel(0.42, 0.34, Vector3(-1.02, 0.42, -1.45))
	fl.name = "WheelFL"
	var fr := _hero_wheel(0.42, 0.34, Vector3(1.02, 0.42, -1.45))
	fr.name = "WheelFR"
	var rl := _hero_wheel(0.42, 0.34, Vector3(-1.02, 0.42, 1.45))
	rl.name = "WheelRL"
	var rr := _hero_wheel(0.42, 0.34, Vector3(1.02, 0.42, 1.45))
	rr.name = "WheelRR"
	wheels.add_child(fl)
	wheels.add_child(fr)
	wheels.add_child(rl)
	wheels.add_child(rr)
	_cache_end()
	return root

# ------------------------------------------------------- traffic cars

static func build_traffic_car(kind: String, color: Color) -> Node3D:
	_cache_begin()
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
	var brake_l := _box_uniq(Vector3(0.5, 0.16, 0.06), Vector3(-width * 0.32, 0.78, rear_z), _std_fresh(Color(0.6, 0.02, 0.02), 0.0, 0.3, Color(1.0, 0.05, 0.05), 0.55))
	brake_l.name = "BrakeL"
	body.add_child(brake_l)
	var brake_r := _box_uniq(Vector3(0.5, 0.16, 0.06), Vector3(width * 0.32, 0.78, rear_z), _std_fresh(Color(0.6, 0.02, 0.02), 0.0, 0.3, Color(1.0, 0.05, 0.05), 0.55))
	brake_r.name = "BrakeR"
	body.add_child(brake_r)
	# Thin red reflector strip across the rear, low glow: a continuous
	# red line so the rear reads as a car back even at a glance.
	body.add_child(_box(Vector3(width * 0.8, 0.06, 0.04), Vector3(0, 0.62, rear_z), _std(Color(0.5, 0.03, 0.03), 0.0, 0.3, Color(1.0, 0.06, 0.06), 0.25)))

	# Indicators (amber, front + rear, per side).
	for side in [-1, 1]:
		var tag := "L" if side < 0 else "R"
		var ind_f := _box_uniq(Vector3(0.18, 0.1, 0.06), Vector3(side * width * 0.42, 0.62, -length * 0.5 - 0.01), _std_fresh(Color(0.8, 0.4, 0.0), 0.0, 0.3, Color(1.0, 0.55, 0.0), 0.12))
		ind_f.name = "IndicatorF" + tag
		body.add_child(ind_f)
		var ind_r := _box_uniq(Vector3(0.18, 0.1, 0.06), Vector3(side * width * 0.42, 0.78, rear_z), _std_fresh(Color(0.8, 0.4, 0.0), 0.0, 0.3, Color(1.0, 0.55, 0.0), 0.12))
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
	_cache_end()
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
	_cache_begin()
	var root := Node3D.new()
	root.name = "Coin"
	var face_mat := _std(color, 0.95, 0.18, color, 0.35)
	var coin := _cyl(0.35, 0.35, 0.08, Vector3.ZERO, face_mat, 16)
	coin.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(coin)
	var rim_mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.27
	torus.outer_radius = 0.35
	torus.rings = 6
	torus.ring_segments = 16
	torus.material = _std(rim, 0.9, 0.25)
	rim_mesh.mesh = torus
	# Lead fix 2026-11-12: TorusMesh rings lie in the XZ plane — unrotated
	# the rim rendered as a horizontal bar across the coin face. Rotate
	# into the face plane (same convention as the face/hub cylinders).
	rim_mesh.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(rim_mesh)
	var hub := _cyl(0.12, 0.12, 0.1, Vector3.ZERO, _std(rim, 0.9, 0.2), 8)
	hub.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(hub)
	_cache_end()
	return root

static func build_coin() -> Node3D:
	return _coin(Color(1.0, 0.78, 0.15), Color(0.85, 0.6, 0.08))

static func build_air_coin() -> Node3D:
	return _coin(Color(0.25, 0.65, 1.0), Color(0.1, 0.4, 0.9))

static func build_pickup_orb(kind: String) -> Node3D:
	_cache_begin()
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
	_cache_end()
	return root

static func _make_glow_texture(size: int) -> ImageTexture:
	# Soft radial falloff: hot centre, transparent edges. Used by the
	# hero underglow so it reads as light pooling under the car.
	# Cached GLOBALLY (one texture per size): textures are never
	# mutated, so sharing across heroes is safe.
	if _glow_tex_cache.has(size):
		return _glow_tex_cache[size] as ImageTexture
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var d: float = clamp(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var t := pow(1.0 - d, 1.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, t))
	var tex := ImageTexture.create_from_image(img)
	_glow_tex_cache[size] = tex
	return tex

# ------------------------------------------------------- palm tree

static func _palm_materials() -> Array:
	# The 5 palm materials, created ONCE and shared by every palm:
	# leaf/trunk materials are never mutated (world_builder touches
	# only each palm root's position/rotation/scale/visible), so
	# global sharing is safe. Fronds must read GREEN, not yellow
	# umbrellas: deep green albedo, a faint GREEN (not orange)
	# emission lift, and two alternating shades so individual leaves
	# separate from each other. The third, darker shade is the
	# under-ring: leaves in shadow under the crown.
	if _palm_trunk_mat == null:
		_palm_trunk_mat = _std_fresh(Color(0.45, 0.30, 0.17), 0.0, 0.85)
		_palm_leaf_mat = _std_fresh(Color(0.07, 0.40, 0.15), 0.0, 0.6, Color(0.05, 0.25, 0.08), 0.15)
		_palm_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_palm_leaf_mat2 = _std_fresh(Color(0.05, 0.30, 0.11), 0.0, 0.6, Color(0.04, 0.20, 0.06), 0.15)
		_palm_leaf_mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
		_palm_leaf_mat3 = _std_fresh(Color(0.03, 0.18, 0.07), 0.0, 0.7, Color(0.02, 0.12, 0.04), 0.15)
		_palm_leaf_mat3.cull_mode = BaseMaterial3D.CULL_DISABLED
		_palm_nut_mat = _std_fresh(Color(0.35, 0.22, 0.1), 0.0, 0.8)
	return [_palm_trunk_mat, _palm_leaf_mat, _palm_leaf_mat2, _palm_leaf_mat3, _palm_nut_mat]

static func build_palm() -> Node3D:
	# ONE ArrayMesh, 5 surfaces (trunk, leaf x3, nuts) sharing the 5
	# global palm materials: 65 draws/palm -> 5. Every part bakes the
	# EXACT segment/leaf transforms the old 65-node builder computed
	# (same deterministic jitter), so the silhouette is identical.
	# The per-palm root Node3D keeps its origin at the trunk base;
	# scroll/_place_palm/_apply_palette touch only root
	# position/rotation/scale/visible, which this preserves exactly.
	var root := Node3D.new()
	root.name = "Palm"
	var mats := _palm_materials()
	var surf_trunk := _surf_new()
	var surf_leaf1 := _surf_new()
	var surf_leaf2 := _surf_new()
	var surf_leaf3 := _surf_new()
	var surf_nuts := _surf_new()

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
		var seg := CylinderMesh.new()
		seg.top_radius = r_top
		seg.bottom_radius = r_bot
		seg.height = 0.95
		seg.radial_segments = 7
		_bake_append(surf_trunk, seg, Transform3D(Basis(Vector3(0, 0, 1), -theta), Vector3(bx + sin(theta) * 0.475, by + cos(theta) * 0.475, 0)))
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
			var surf: Dictionary = surf_leaf3 if ring == 2 else (surf_leaf1 if (i + ring) % 2 == 0 else surf_leaf2)
			var pivot_xform := Transform3D(Basis(Vector3.UP, deg_to_rad(float(i) * (360.0 / float(count)) + float(ring) * 22.0)), Vector3(top.x, ring_y, top.z))
			# V-fold: two halves, outer edges tilted down from the
			# midrib, plus the per-leaf roll so no two leaves sit flat.
			# Basis.from_euler matches Node3D rotation exactly
			# (probed), so these baked transforms equal the old
			# pivot + rotation_degrees hierarchy.
			var half_w := 0.24
			var leaf_mesh := BoxMesh.new()
			leaf_mesh.size = Vector3(leaf_len, 0.05, half_w)
			_bake_append(surf, leaf_mesh, pivot_xform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(-30.0 + roll), 0, deg_to_rad(leaf_droop))), Vector3(leaf_len * 0.5, 0.05, -half_w * 0.46)))
			_bake_append(surf, leaf_mesh, pivot_xform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(30.0 + roll), 0, deg_to_rad(leaf_droop))), Vector3(leaf_len * 0.5, 0.05, half_w * 0.46)))
			# Leaf tip flicks back up slightly (second segment).
			var tip_mesh := BoxMesh.new()
			tip_mesh.size = Vector3(leaf_len * 0.35, 0.04, 0.3)
			_bake_append(surf, tip_mesh, pivot_xform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(roll * 0.5), 0, deg_to_rad(leaf_droop - 22.0))), Vector3(leaf_len * 0.92, -0.28, 0)))

	# Coconut cluster under the crown.
	for i in range(3):
		var a := float(i) * 2.1
		var nut := SphereMesh.new()
		nut.radius = 0.11
		nut.height = 0.22
		nut.radial_segments = 12
		nut.rings = 8
		_bake_append(surf_nuts, nut, Transform3D(Basis(), top + Vector3(cos(a) * 0.18, -0.18, sin(a) * 0.18)))
	var mi := MeshInstance3D.new()
	mi.mesh = _merged_mesh([surf_trunk, surf_leaf1, surf_leaf2, surf_leaf3, surf_nuts], mats)
	root.add_child(mi)
	return root
