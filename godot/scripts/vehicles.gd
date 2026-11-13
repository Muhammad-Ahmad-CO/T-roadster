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
		# v2.3: thin rim ring proud of the hub (0 draws — same
		# metal surface) so traffic wheels read less flat.
		var rim := CylinderMesh.new()
		rim.top_radius = radius * 0.62
		rim.bottom_radius = radius * 0.62
		rim.height = width + 0.06
		rim.radial_segments = 12
		_bake_append(surf_metal, rim, rot)
		mesh = _merged_mesh([surf_dark, surf_metal], [dark, metal])
		_mesh_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	wheel.add_child(mi)
	return wheel

# --------------------------------------- wedge-loft + lathe helpers
# v2.3 wedge rebuild (GATE S4): the hero body is a SHARP FACETED
# ArrayMesh loft, NOT _bake_append primitives — that helper only bakes
# primitive meshes and is useless for loft geometry. Surf dicts are
# filled DIRECTLY here; only the dict shape + _merged_mesh are reused.
# Every quad gets its own 4 vertices (duplicated at every ring) with
# ONE face normal x4, so every quad edge is a hard break: flat
# panels, crisp edges, discrete facet tones. UVs are dummy zeros (no
# textures on the loft — _merged_mesh requires a UV array per
# surface; the glass gradient lives on baked boxes with real BoxMesh
# UVs, see _make_glass_gradient_texture).

static func _quad_append(surf: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	var v: PackedVector3Array = surf["v"]
	var n: PackedVector3Array = surf["n"]
	var uv: PackedVector2Array = surf["uv"]
	var ii: PackedInt32Array = surf["i"]
	var base: int = v.size()
	v.append(a)
	v.append(b)
	v.append(c)
	v.append(d)
	n.append(na)
	n.append(nb)
	n.append(nc)
	n.append(nd)
	uv.append(Vector2.ZERO)
	uv.append(Vector2.ZERO)
	uv.append(Vector2.ZERO)
	uv.append(Vector2.ZERO)
	# Winding (a,b,c),(a,c,d): Godot front faces wind so the
	# geometric normal (b-a)x(c-a) points INWARD (proven against
	# BoxMesh/CylinderMesh ground truth in probe_wind.gd: 12/12 and
	# 96/96 triangles have vertex normal == -(b-a)x(c-a)). The
	# (a,c,b) order tried first was inside-out (culled from
	# outside). Do not "fix" without re-running probe_wind.gd.
	ii.append(base + 0)
	ii.append(base + 1)
	ii.append(base + 2)
	ii.append(base + 0)
	ii.append(base + 2)
	ii.append(base + 3)
	surf["v"] = v
	surf["n"] = n
	surf["uv"] = uv
	surf["i"] = ii

static func _sharp_ring(hw: float, yb: float, yt: float, c: float, split_y: float) -> Array:
	# v2.3 wedge (GATE S4): chamfered-rectangle ring in the XY plane,
	# CCW seen from +Z (same order convention as the old rounded
	# ring: up the right edge, left across the top, down the left
	# edge, right across the bottom). 8 points: 4 chamfer facets +
	# top/side/bottom panels — flat facets, NOT a faceted tube.
	# When split_y falls inside the section, 2 extra points split
	# each side into an upper and a lower facet (10 points) so the
	# two-tone lower band survives faceting. The chamfer is clamped
	# so stations never invert and no two points coincide (r=0 is
	# degenerate and FORBIDDEN — _loft_append also guards).
	var cc: float = clampf(c, 0.005, minf(hw * 0.5, (yt - yb) * 0.4))
	var split: bool = split_y > yb + cc + 0.05 and split_y < yt - cc - 0.05
	var pts: Array = [
		Vector2(hw, yt - cc),
		Vector2(hw - cc, yt),
		Vector2(-hw + cc, yt),
		Vector2(-hw, yt - cc),
	]
	if split:
		pts.append(Vector2(-hw, split_y))
	pts.append(Vector2(-hw, yb + cc))
	pts.append(Vector2(-hw + cc, yb))
	pts.append(Vector2(hw - cc, yb))
	pts.append(Vector2(hw, yb + cc))
	if split:
		pts.append(Vector2(hw, split_y))
	return pts

static func _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# v2.3 wedge (GATE S4): per-quad FACE normal, replacing the
	# analytic smooth _loft_normal. Godot front faces wind so the
	# geometric normal (b-a)x(c-a) points INWARD (proven against
	# BoxMesh/CylinderMesh ground truth in probe_wind.gd), so the
	# outward face normal is the NEGATED cross product. Returns
	# Vector3.ZERO for a degenerate (zero-area) quad — the caller
	# skips those quads entirely.
	var g: Vector3 = (b - a).cross(c - a)
	if g.length() < 0.000001:
		return Vector3.ZERO
	return -g.normalized()

static func _loft_append(surfs: Array, stations: Array, mode: int, idx_paint: int, idx_low: int, idx_dark: int, low_y: float, bed_z0: float, bed_z1: float) -> void:
	# stations: Array of Dictionary {z, hw, yb, yt, r, crease, split}.
	# v2.3 wedge (GATE S4): sharp rings + per-quad FACE normals
	# (every quad edge is a hard break; the `crease` key is RETIRED
	# and ignored). mode 0 = body rules: bed-floor top faces ->
	# idx_dark, cab-back step faces (rear-facing, z in (0.90, 1.10))
	# -> idx_dark, faces below low_y -> idx_low (two-tone lower
	# band + underside), the rest -> idx_paint. mode 1 = every face
	# into surfs[0] (glasshouse loft / dark inner loft).
	# Guards: ring point counts must match across stations (the
	# split variant is deterministic per loft); degenerate
	# (zero-area) quads are skipped, never emitted.
	var nst: int = stations.size()
	var rings: Array = []
	for si in range(nst):
		var st: Dictionary = stations[si]
		var ring2: Array = _sharp_ring(float(st["hw"]), float(st["yb"]), float(st["yt"]), float(st["r"]), float(st.get("split", 0.0)))
		var ring3: Array = []
		var z: float = float(st["z"])
		for p2 in ring2:
			var pp: Vector2 = p2
			ring3.append(Vector3(pp.x, pp.y, z))
		rings.append(ring3)
	var first_ring: Array = rings[0]
	var npt: int = first_ring.size()
	for si2 in range(1, nst):
		if (rings[si2] as Array).size() != npt:
			push_error("Lane A loft: ring point count mismatch at station " + str(si2) + " — loft skipped, mesh would be corrupt.")
			return
	for s in range(nst - 1):
		var ring_a: Array = rings[s]
		var ring_b: Array = rings[s + 1]
		for j in range(npt):
			var j2: int = (j + 1) % npt
			var a: Vector3 = ring_a[j]
			var b: Vector3 = ring_b[j]
			var cc: Vector3 = ring_b[j2]
			var d: Vector3 = ring_a[j2]
			var fn: Vector3 = _face_normal(a, b, cc)
			if fn == Vector3.ZERO:
				continue
			var target: Dictionary = surfs[0]
			if mode == 0:
				var fc: Vector3 = (a + b + cc + d) * 0.25
				if fn.y > 0.5 and fc.z > bed_z0 and fc.z < bed_z1:
					target = surfs[idx_dark]
				elif fn.z > 0.7 and fc.z > 0.90 and fc.z < 1.10:
					target = surfs[idx_dark]
				elif fc.y < low_y:
					target = surfs[idx_low]
				else:
					target = surfs[idx_paint]
			_quad_append(target, a, b, cc, d, fn, fn, fn, fn)

static func _cap_append(surf: Dictionary, st: Dictionary, facing_rear: bool) -> void:
	# Flat fan cap for a loft end station. Separate vertices with a
	# flat +/-Z normal = hard break from the loft sides.
	var ring2: Array = _sharp_ring(float(st["hw"]), float(st["yb"]), float(st["yt"]), float(st["r"]), float(st.get("split", 0.0)))
	var npt: int = ring2.size()
	var cz: float = float(st["z"])
	var cy: float = (float(st["yb"]) + float(st["yt"])) * 0.5
	var center := Vector3(0.0, cy, cz)
	var nrm := Vector3(0, 0, 1) if facing_rear else Vector3(0, 0, -1)
	var v: PackedVector3Array = surf["v"]
	var n: PackedVector3Array = surf["n"]
	var uv: PackedVector2Array = surf["uv"]
	var ii: PackedInt32Array = surf["i"]
	var base: int = v.size()
	v.append(center)
	n.append(nrm)
	uv.append(Vector2.ZERO)
	for p2 in ring2:
		var pp: Vector2 = p2
		v.append(Vector3(pp.x, pp.y, cz))
		n.append(nrm)
		uv.append(Vector2.ZERO)
	for j in range(npt):
		var j2: int = (j + 1) % npt
		if facing_rear:
			ii.append(base + 0)
			ii.append(base + 1 + j2)
			ii.append(base + 1 + j)
		else:
			ii.append(base + 0)
			ii.append(base + 1 + j)
			ii.append(base + 1 + j2)
	surf["v"] = v
	surf["n"] = n
	surf["uv"] = uv
	surf["i"] = ii

static func _bake_box(surf: Dictionary, size: Vector3, xform: Transform3D) -> void:
	var m := BoxMesh.new()
	m.size = size
	_bake_append(surf, m, xform)

static func _bake_cyl(surf: Dictionary, r_top: float, r_bot: float, height: float, segments: int, xform: Transform3D) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = height
	m.radial_segments = segments
	_bake_append(surf, m, xform)

static func _xf(pos: Vector3, euler_deg: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z))), pos)

static func _revolve_append(surf: Dictionary, profile: Array, segments: int, rot: Basis) -> void:
	# Lathe: `profile` is Array[Vector2] (radius, axial), ordered
	# inboard -> outboard, revolved about the Y axis and then rotated
	# by `rot` into the X axle. Profile normals are per-point averages
	# of adjacent segment normals in the (r, axial) plane, revolved
	# and rotated — smooth shoulders, no facet banding.
	var np: int = profile.size()
	var seg_n: Array = []
	for i in range(np - 1):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var t: Vector2 = (p1 - p0).normalized()
		seg_n.append(Vector2(t.y, -t.x))
	var pt_n: Array = []
	for i in range(np):
		var acc := Vector2.ZERO
		if i > 0:
			var sn0: Vector2 = seg_n[i - 1]
			acc += sn0
		if i < np - 1:
			var sn1: Vector2 = seg_n[i]
			acc += sn1
		pt_n.append(acc.normalized())
	for i in range(np - 1):
		for j in range(segments):
			var j2: int = (j + 1) % segments
			var th0: float = TAU * float(j) / float(segments)
			var th1: float = TAU * float(j2) / float(segments)
			var pa: Array = _rev_pt(profile, pt_n, i, th0, rot)
			var pb: Array = _rev_pt(profile, pt_n, i + 1, th0, rot)
			var pc: Array = _rev_pt(profile, pt_n, i + 1, th1, rot)
			var pd: Array = _rev_pt(profile, pt_n, i, th1, rot)
			_quad_append(surf, pa[0], pb[0], pc[0], pd[0], pa[1], pb[1], pc[1], pd[1])

static func _rev_pt(profile: Array, pt_n: Array, i: int, th: float, rot: Basis) -> Array:
	var p: Vector2 = profile[i]
	var n2: Vector2 = pt_n[i]
	var s: float = sin(th)
	var co: float = cos(th)
	var pos_y := Vector3(p.x * s, p.y, p.x * co)
	var nrm_y := Vector3(n2.x * s, n2.y, n2.x * co)
	return [rot * pos_y, (rot * nrm_y).normalized()]

static func _fan_append(surf: Dictionary, center: Vector3, radius: float, axis: Vector3, segments: int) -> void:
	# Flat disc fan facing along `axis` (unit X for wheel faces).
	# Winding (center, j+1, j): the (u, w) basis makes
	# (center, j, j+1) point (b-a)x(c-a) along +axis, and Godot
	# front faces need that cross product pointing INWARD (see
	# _quad_append / probe_wind.gd), so the order is reversed.
	var up := Vector3.UP
	if absf(axis.dot(up)) > 0.9:
		up = Vector3.FORWARD
	var u: Vector3 = axis.cross(up).normalized()
	var w: Vector3 = axis.cross(u).normalized()
	var v: PackedVector3Array = surf["v"]
	var n: PackedVector3Array = surf["n"]
	var uv: PackedVector2Array = surf["uv"]
	var ii: PackedInt32Array = surf["i"]
	var base: int = v.size()
	v.append(center)
	n.append(axis)
	uv.append(Vector2.ZERO)
	for j in range(segments):
		var th: float = TAU * float(j) / float(segments)
		v.append(center + (u * cos(th) + w * sin(th)) * radius)
		n.append(axis)
		uv.append(Vector2.ZERO)
	for j in range(segments):
		var j2: int = (j + 1) % segments
		ii.append(base + 0)
		ii.append(base + 1 + j2)
		ii.append(base + 1 + j)
	surf["v"] = v
	surf["n"] = n
	surf["uv"] = uv
	surf["i"] = ii

static var _glass_grad_tex: ImageTexture = null

static func _make_glass_gradient_texture() -> ImageTexture:
	# ORIGINAL procedural baked sky-gradient reflection for the hero
	# glass (runtime-generated Image — no file, no import, no licence
	# risk, no SOURCES.md row). ZERO-UV WALL design (GATE S6): the
	# glass LOFT's UVs are all zero, so it samples the (0,0) corner
	# texel — which is the DARK base glass tone. The baked-box glass
	# panels (roof + windshield) carry real BoxMesh UVs and sample
	# the gradient: dark at v=0 rising to a bright near-white sky
	# streak at v=1. The bright band occupies only the top sliver
	# (smoothstep 0.82..0.97) and the bright end is DIM (0.55):
	# round 1 proved a 0.92 near-white end + metallic 0.45 blew the
	# roof panel white-hot via F0-amplified sky reflection, and the
	# mipmap average must stay dark. The streak reads close-up, the
	# band reads dark at chase distance. The glass material's albedo
	# is WHITE so the texture (not the albedo multiply) carries the
	# colour. Gradient orientation is RENDER-GATED: the bright end
	# lands at the panel FRONT (BoxMesh top-face v runs toward -z)
	# and reads as a sun streak — kept deliberately. Cached globally:
	# textures are never mutated, so sharing across heroes is safe
	# (same pattern as the glow texture).
	if _glass_grad_tex != null:
		return _glass_grad_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var dark := Color(0.03, 0.05, 0.09)
	var bright := Color(0.55, 0.56, 0.62)
	for y in range(size):
		var v: float = (float(y) + 0.5) / float(size)
		var t: float = smoothstep(0.82, 0.97, v)
		var c: Color = dark.lerp(bright, t)
		for x in range(size):
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	img.generate_mipmaps()
	_glass_grad_tex = ImageTexture.create_from_image(img)
	return _glass_grad_tex

static func _make_hero_halo() -> MeshInstance3D:
	# Hero taillight halo: ONE quad under Body, GATE R3
	# StandardMaterial3D pattern duplicated locally (NO cross-file
	# call): UNSHADED + TRANSPARENCY_ALPHA + BLEND_MODE_ADD +
	# BILLBOARD_ENABLED + disable_fog + DEPTH_DRAW_DISABLED (still
	# depth-TESTED, so the car occludes it from the front) + the
	# local radial texture + cast_shadow OFF (no square shadows).
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_fog = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = _make_glow_texture(128)
	mat.albedo_color = Color(1.0, 0.25, 0.20, 0.5)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, 0.86, 2.38)
	mi.name = "HeroHalo"
	return mi

static func _hero_wheel(radius: float, width: float, pos: Vector3) -> Node3D:
	# Hero-only lathe wheel: revolved tyre + GEOMETRY tread blocks +
	# brake disc + caliper + rim lip + face discs + hub + 5 outboard
	# spokes. v2.3 (GATE S6): tread is GEOMETRY (revolved UVs are
	# zero, so no tread texture) — the tread band is revolved at
	# r=0.405 and 18 blocks bring the outer face back to exactly
	# r=0.42 (frozen visual radius). Blocks are rotationally
	# symmetric (20 deg pitch), so tread survives spin. Returns an
	# UNNAMED pivot (the caller names it WheelFL/FR/RL/RR);
	# player.gd spins it via rotation.x, so ALL geometry lives on
	# the X axis. The revolve is built about Y and ROTATED into the
	# X axle (rotZ -90 deg maps +Y -> +X, so profile axial == final
	# X) — the same trap the old TorusMesh comment recorded, made
	# explicit. Outboard detail is MIRRORED by construction: two
	# mesh variants keyed by outboard sign (spokes + rim lip on the
	# outboard face only), NO negative-scale mirroring, so winding
	# and culling are identical on both sides. Visual radius stays
	# 0.42 vs WHEEL_RADIUS 0.35 (frozen mismatch, NOT fixed here).
	var wheel := Node3D.new()
	wheel.position = pos
	var out: float = 1.0 if pos.x >= 0.0 else -1.0
	var key: Array = ["herowheel_lathe", radius, width, out]
	var mesh: ArrayMesh = null
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key] as ArrayMesh
	else:
		var rs: float = radius / 0.42
		var ws: float = width / 0.34
		var half: float = width * 0.5
		var tyre_mat := _std(Color(0.05, 0.05, 0.06), 0.0, 0.9)
		var metal_mat := _std(Color(0.75, 0.77, 0.80), 1.0, 0.18)
		var surf_tyre := _surf_new()
		var surf_metal := _surf_new()
		var rot := Basis(Vector3(0, 0, 1), -PI * 0.5)
		var tyre_profile: Array = [
			Vector2(0.20 * rs, -half), Vector2(0.34 * rs, -half),
			Vector2(0.38 * rs, -0.14 * ws), Vector2(0.405 * rs, -0.08 * ws),
			Vector2(0.405 * rs, 0.08 * ws), Vector2(0.38 * rs, 0.14 * ws),
			Vector2(0.34 * rs, half), Vector2(0.20 * rs, half),
		]
		_revolve_append(surf_tyre, tyre_profile, 20, rot)
		# Tread blocks: 18 around the tread band. Block centre at
		# r=0.4014 (corner-corrected: outer face 0.4164 + tangential
		# half-width 0.055 puts the block CORNERS exactly on the
		# frozen r=0.42 visual radius). Baked directly in final
		# (axle = X) coords.
		var tread_mesh := BoxMesh.new()
		tread_mesh.size = Vector3(0.16 * ws, 0.03 * rs, 0.11 * rs)
		for k in range(18):
			var tang: float = TAU * float(k) / 18.0
			var tread_xform := Transform3D(Basis(Vector3(1, 0, 0), tang), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, 0.4014 * rs, 0))
			_bake_append(surf_tyre, tread_mesh, tread_xform)
		# Rim lip: [axial distance from centre, radius], traversed
		# inboard -> outboard in FINAL X for either side (reversed
		# list for the left wheels) so profile normals stay outward.
		var lip_d: Array = [
			[0.10, 0.29], [0.145, 0.315], [0.17, 0.305], [0.17, 0.28],
		]
		var lip: Array = []
		if out > 0.0:
			for e in lip_d:
				var ee: Array = e
				lip.append(Vector2(float(ee[1]) * rs, float(ee[0]) * ws))
		else:
			for ei in range(lip_d.size() - 1, -1, -1):
				var ee2: Array = lip_d[ei]
				lip.append(Vector2(float(ee2[1]) * rs, -float(ee2[0]) * ws))
		_revolve_append(surf_metal, lip, 20, rot)
		# Wheel face (round-2 rework): NO outboard solid fan — it
		# hid the brake disc entirely in round 1. Instead a DARK
		# backing fan (tyre surface) closes the wheel interior at
		# x=out*0.10, the brake disc sits outboard of it at
		# x=out*0.13, and the 5 spokes pass over the disc edge — so
		# the spoke gaps show disc + dark backing (real-wheel depth).
		# The inboard fan stays (closes the back).
		_fan_append(surf_tyre, Vector3(out * 0.10 * ws, 0, 0), 0.30 * rs, Vector3(out, 0, 0), 20)
		_fan_append(surf_metal, Vector3(-out * 0.155 * ws, 0, 0), 0.30 * rs, Vector3(-out, 0, 0), 20)
		# Brake disc (shiny) + dark caliper straddling the disc edge
		# at its rear, both visible through the spoke gaps.
		_bake_cyl(surf_metal, 0.17 * rs, 0.17 * rs, 0.03, 20, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(out * 0.13 * ws, 0, 0)))
		_bake_box(surf_tyre, Vector3(0.05, 0.09, 0.07), _xf(Vector3(out * 0.13 * ws, 0.0, 0.15 * rs), Vector3.ZERO))
		_bake_cyl(surf_metal, 0.09 * rs, 0.09 * rs, width + 0.06, 12, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO))
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.055, 0.26 * rs, 0.11)
		for k in range(5):
			var ang: float = TAU * float(k) / 5.0
			var xform := Transform3D(Basis(Vector3(1, 0, 0), ang), Vector3(out * 0.16 * ws, 0, 0)) * Transform3D(Basis(), Vector3(0, 0.185 * rs, 0))
			_bake_append(surf_metal, spoke_mesh, xform)
		mesh = _merged_mesh([surf_tyre, surf_metal], [tyre_mat, metal_mat])
		_mesh_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	wheel.add_child(mi)
	return wheel

# ------------------------------------------------------- hero pickup

static func _st(z: float, hw: float, yb: float, yt: float, r: float, crease: bool = false, split_y: float = 0.0) -> Dictionary:
	return {"z": z, "hw": hw, "yb": yb, "yt": yt, "r": r, "crease": crease, "split": split_y}

static func build_hero_pickup(paint: Color) -> Node3D:
	# v2.3 wedge rebuild (GATE S4): SHARP FACETED ArrayMesh loft
	# behind the FROZEN signature — flat panels, crisp edges, one
	# collinear roofline slope, dark glass band on top (NO white
	# roof cap), glowing red bar. Root "HeroPickup" (-Z forward),
	# "Body" child (all body visuals under it), "Wheels" sibling,
	# pivots (±1.02, 0.42, ±1.45), rear face z=+2.32, roof peak
	# 1.46 (dark glass), per-invocation materials (NO global/static
	# mesh cache — the merged mesh is rebuilt per call; _std cache
	# is per-invocation only). HeadlightBar / TaillightBar stay
	# SEPARATE MeshInstance3D nodes under Body; Underglow stays
	# separate; HeroHalo is ONE quad under Body. NO BrakeL/BrakeR
	# (FORBIDDEN this pass).
	# Draws: BodyMesh 7 surfaces + 2 bars + underglow + halo +
	# 4 wheels x 2 surfaces = 19 (cap 20, incl. underglow + halo;
	# the +1 slot is held in reserve for the conditional emissive
	# edge strip, GATE §V3).
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
	# (Rule preserved exactly: cool blue-white shift + lower
	# metallic for near-white paints; coloured skins untouched.)
	if paint.r > 0.8 and paint.g > 0.8 and paint.b > 0.8:
		paint_cool = Color(paint.r * 0.90, paint.g * 0.95, minf(paint.b * 1.04, 1.0))
		paint_metallic = 0.35
		paint_rough = 0.32
	# v2.3 rim test (GATE S6 fallback order step 1): fresnel edge
	# light on FRESH materials (rim is a new property — NEVER mutate
	# a cached _std material). Render-gated: if the rim reads as a
	# halo artifact, drop the three rim lines and return to _std.
	var paint_mat := _std_fresh(paint_cool, paint_metallic, paint_rough)
	paint_mat.rim_enabled = true
	paint_mat.rim = 0.35
	paint_mat.rim_tint = 0.5
	# Two-tone lower band: the cooled paint darkened x0.85, same
	# metallic/roughness as the main paint.
	var paint_low_mat := _std_fresh(Color(paint_cool.r * 0.85, paint_cool.g * 0.85, paint_cool.b * 0.85), paint_metallic, paint_rough)
	paint_low_mat.rim_enabled = true
	paint_low_mat.rim = 0.35
	paint_low_mat.rim_tint = 0.5
	var dark_mat := _std(Color(0.13, 0.13, 0.15), 0.2, 0.6)
	# v2.3 glass (GATE S6): WHITE albedo + procedural baked
	# sky-gradient texture (see _make_glass_gradient_texture) on a
	# FRESH material (texture is a new property). Zero-UV loft faces
	# sample the dark corner texel; baked-box panels sample the
	# gradient. Metallic 0.35 / roughness 0.25 (round-2: 0.45/0.22
	# blew the roof panel out via F0-amplified sky reflection).
	var glass_mat := _std_fresh(Color(1.0, 1.0, 1.0), 0.35, 0.25)
	glass_mat.albedo_texture = _make_glass_gradient_texture()
	# Consolidated mid-grey trim: absorbs the old trim (0.12),
	# rear-panel (0.38), bumper (0.32) and crease-grey (0.42)
	# materials — one grey that reads with shape on sunless faces
	# instead of a black hole (Round-6 direction). See REPORT.md.
	var trim_mat := _std(Color(0.32, 0.32, 0.35), 0.3, 0.5)
	var plate_mat := _std(Color(0.85, 0.85, 0.80), 0.2, 0.5)
	var chrome_mat := _std(Color(0.7, 0.7, 0.72), 0.9, 0.25)
	# Deep-red tail emissive — Round-6 fix PRESERVED EXACTLY:
	# albedo (0.20,0,0), pure-red emission @ 0.85. Do not "brighten".
	var tail_mat := _std(Color(0.20, 0.0, 0.0), 0.0, 0.2, Color(1.0, 0.0, 0.0), 0.85)
	# Front white emissive: bar + corner pods share one material
	# (bar energy 4.0; pods were 3.0 — consolidated, see REPORT.md).
	var front_mat := _std(Color(1, 1, 1), 0.0, 0.2, Color(1.0, 0.98, 0.9), 4.0)

	var s_paint := _surf_new()
	var s_low := _surf_new()
	var s_glass := _surf_new()
	var s_dark := _surf_new()
	var s_trim := _surf_new()
	var s_chrome := _surf_new()
	var s_plate := _surf_new()

	# --- Main body loft: 8 stations, nose -> tailgate. WEDGE. ---
	# Roofline: ONE plane, yt(z) = 0.86 + 0.12*(z+2.80) — every
	# roofline station is exactly on the line (nose 0.86 -> cab
	# rear 1.31). Stations ONLY at panel breaks: the cab-back step
	# (1.31 -> 0.96), the bed floor (one flat segment), the
	# tailgate rise (0.96 -> 1.27). The bed is NOT a convex loft
	# top: bed-region top faces go to the dark surface (bed floor)
	# and the cab-back step faces go dark too (see _loft_append);
	# separate walls/tailgate geometry below make the open bed.
	# Chamfer 0.03 (crisp 45-deg edge facets that catch the rim
	# light); side split at y=0.55 (two-tone lower band).
	var stations: Array = [
		_st(-2.80, 0.86, 0.34, 0.86, 0.03, false, 0.55),
		_st(-2.55, 0.97, 0.30, 0.89, 0.03, false, 0.55),
		_st(-1.55, 1.00, 0.30, 1.01, 0.03, false, 0.55),
		_st(-0.55, 0.99, 0.30, 1.13, 0.03, false, 0.55),
		_st(0.95, 0.93, 0.30, 1.31, 0.03, false, 0.55),
		_st(1.05, 0.98, 0.30, 0.96, 0.03, false, 0.55),
		_st(2.10, 0.98, 0.30, 0.96, 0.03, false, 0.55),
		_st(2.32, 0.96, 0.30, 1.27, 0.03, false, 0.55),
	]
	_loft_append([s_paint, s_low, s_dark], stations, 0, 0, 1, 2, 0.55, 1.06, 2.08)
	_cap_append(s_paint, stations[0], false)
	_cap_append(s_paint, stations[7], true)

	# --- Glasshouse: dark glass slab PROUD of the roofline slope. ---
	# NO white roof cap (v2.2.0's cap is what made the chase read a
	# white slab). The glass bottoms sit 0.02 below the body top
	# line (embedded, no gap); the glass top stands 0.15 above it.
	# Windshield slope face + roof slope (parallel to the body
	# line) + rear-glass drop. The dark inner loft (stations 2-4
	# only, shrunk, capped) backs the visible glass; the thin
	# leading-edge station is embedded in the body slope and needs
	# no backing (shrinking it would invert it).
	var glass_stations: Array = [
		_st(-1.30, 0.82, 1.02, 1.06, 0.02),
		_st(-0.55, 0.80, 1.11, 1.28, 0.02),
		_st(0.95, 0.77, 1.29, 1.46, 0.02),
		_st(1.08, 0.74, 1.24, 1.34, 0.02),
	]
	_loft_append([s_glass], glass_stations, 1, 0, 0, 0, 0.0, 0.0, 0.0)
	var inner_stations: Array = []
	for gi in range(1, glass_stations.size()):
		var g: Dictionary = glass_stations[gi]
		inner_stations.append(_st(float(g["z"]), float(g["hw"]) * 0.92, float(g["yb"]) + 0.03, float(g["yt"]) - 0.03, float(g["r"]) * 0.9))
	_loft_append([s_dark], inner_stations, 1, 0, 0, 0, 0.0, 0.0, 0.0)
	_cap_append(s_dark, inner_stations[0], false)
	_cap_append(s_dark, inner_stations[2], true)

	var zero := Vector3.ZERO
	# --- Paint details (baked boxes into the paint surface). ---
	# NO roof cap: the cab top IS dark glass (see glass panels
	# below). Open-bed walls (inset 0.01 from the loft side: no
	# coplanar z-fight) + inner tailgate face. Bed floor is 0.96,
	# wall tops 1.28 — unchanged vs the new stations.
	_bake_box(s_paint, Vector3(0.08, 0.34, 1.30), _xf(Vector3(-0.93, 1.11, 1.66), zero))
	_bake_box(s_paint, Vector3(0.08, 0.34, 1.30), _xf(Vector3(0.93, 1.11, 1.66), zero))
	_bake_box(s_paint, Vector3(1.86, 0.32, 0.06), _xf(Vector3(0, 1.11, 2.24), zero))
	# Tailgate INSET panel: a real 3D depth step (proud 0.04 with
	# shaded sides), NOT a flat line box — the rear face must stop
	# reading as one flat plane. Sits above the red bar (bar top
	# 0.94, panel 0.96..1.24, tailgate top 1.27). Handle below.
	_bake_box(s_paint, Vector3(1.70, 0.28, 0.04), _xf(Vector3(0, 1.10, 2.34), zero))
	# ANGULAR fenders: top + two 35-deg slopes per wheel, replacing
	# the slim brow boxes. Front slope tilts down toward -Z
	# (rot.x -35), rear slope down toward +Z (rot.x +35).
	for sx in [-1.0, 1.0]:
		for wz in [-1.45, 1.45]:
			_bake_box(s_paint, Vector3(0.22, 0.08, 0.50), _xf(Vector3(sx * 1.00, 0.90, wz), zero))
			_bake_box(s_paint, Vector3(0.22, 0.08, 0.44), _xf(Vector3(sx * 1.00, 0.76, wz - 0.38), Vector3(-35, 0, 0)))
			_bake_box(s_paint, Vector3(0.22, 0.08, 0.44), _xf(Vector3(sx * 1.00, 0.76, wz + 0.38), Vector3(35, 0, 0)))
	# Mirror caps (paint tops on the dark housings below).
	_bake_box(s_paint, Vector3(0.16, 0.04, 0.22), _xf(Vector3(-1.00, 1.25, -0.15), zero))
	_bake_box(s_paint, Vector3(0.16, 0.04, 0.22), _xf(Vector3(1.00, 1.25, -0.15), zero))

	# --- Glass gradient panels (baked boxes, real BoxMesh UVs). ---
	# Thin boxes following the glass slopes, 0.008 proud of the
	# loft faces, sampling the procedural gradient texture (the
	# loft itself has zero UVs and samples the dark corner texel).
	# Roof panel: slope 0.12 (rot.x -6.84 deg), midpoint of the
	# roof top segment (z -0.55..0.95, tops 1.28..1.46) + normal
	# offset. Windshield panel: slope 0.293 (rot.x -16.3 deg),
	# midpoint of the windshield segment (z -1.30..-0.55, tops
	# 1.06..1.28) + normal offset.
	_bake_box(s_glass, Vector3(1.50, 0.02, 1.42), _xf(Vector3(0, 1.378, 0.199), Vector3(-6.84, 0, 0)))
	_bake_box(s_glass, Vector3(1.56, 0.02, 0.72), _xf(Vector3(0, 1.178, -0.927), Vector3(-16.3, 0, 0)))

	# --- Dark details. ---
	# Grille (dark panel + chrome slats below read as the recess;
	# a true recess needs a boolean the loft cannot do). Nose face
	# unchanged (z=-2.80, y 0.34..0.86).
	_bake_box(s_dark, Vector3(1.70, 0.22, 0.08), _xf(Vector3(0, 0.52, -2.79), zero))
	# Wheel-well insets: shadow pockets smaller than the tyre, so
	# the dark shows at the tyre's sides only. (Baked AO: zero
	# draws — GATE S6 default mechanism.)
	for sx in [-1.0, 1.0]:
		for sz in [-1.45, 1.45]:
			_bake_box(s_dark, Vector3(0.05, 0.60, 0.90), _xf(Vector3(sx * 0.99, 0.44, sz), zero))
	# Side mirrors: stalk + housing + GLASS face on the rear
	# (+Z, driver-facing) side of each housing.
	for sx2 in [-1.0, 1.0]:
		_bake_box(s_dark, Vector3(0.14, 0.04, 0.06), _xf(Vector3(sx2 * 0.92, 1.16, -0.15), zero))
		_bake_box(s_dark, Vector3(0.16, 0.12, 0.22), _xf(Vector3(sx2 * 1.00, 1.18, -0.15), zero))
		_bake_box(s_glass, Vector3(0.14, 0.10, 0.02), _xf(Vector3(sx2 * 1.00, 1.18, -0.03), zero))
	# Bed roll bar (ALREADY EXISTS — kept, re-derived): crossbar
	# BELOW the glass roof peak (1.46), posts from the bed floor.
	_bake_box(s_dark, Vector3(1.70, 0.07, 0.07), _xf(Vector3(0, 1.40, 1.58), zero))
	_bake_box(s_dark, Vector3(0.07, 0.44, 0.07), _xf(Vector3(-0.80, 1.18, 1.58), zero))
	_bake_box(s_dark, Vector3(0.07, 0.44, 0.07), _xf(Vector3(0.80, 1.18, 1.58), zero))
	# Bed liner: GEOMETRY ribs across the bed floor (default —
	# bed-floor UVs are zero, so no liner texture).
	for rz in [1.25, 1.425, 1.60, 1.775, 1.95]:
		_bake_box(s_dark, Vector3(1.80, 0.02, 0.06), _xf(Vector3(0, 0.97, rz), zero))
	# Bumper tread step + number-plate recess.
	_bake_box(s_dark, Vector3(1.60, 0.03, 0.18), _xf(Vector3(0, 0.46, 2.34), zero))
	_bake_box(s_dark, Vector3(0.56, 0.17, 0.02), _xf(Vector3(0, 0.66, 2.33), zero))
	# Tailgate handle on the inset panel's top edge.
	_bake_box(s_dark, Vector3(0.30, 0.05, 0.03), _xf(Vector3(0, 1.20, 2.365), zero))
	# Door handles (one per side, on the upper side facet).
	# Door shut-lines DROPPED in round 2: the 0.55-tall dark boxes
	# read as bold black stripes/cracks on the side facet in every
	# render; the facet edges already carry the panel-gap read.
	for sx5 in [-1.0, 1.0]:
		_bake_box(s_dark, Vector3(0.06, 0.05, 0.22), _xf(Vector3(sx5 * 0.97, 1.02, 0.15), zero))
	# Mud flaps behind the rear wheels.
	for sx6 in [-1.0, 1.0]:
		_bake_box(s_dark, Vector3(0.24, 0.30, 0.03), _xf(Vector3(sx6 * 1.02, 0.30, 1.92), zero))
	# Diffuser hints: 3 small fins under the rear bumper (FIRST to
	# drop per the §V3 drop list if renders read cluttered).
	for fx in [-0.4, 0.0, 0.4]:
		_bake_box(s_dark, Vector3(0.04, 0.12, 0.14), _xf(Vector3(fx, 0.30, 2.40), zero))
	# Exhaust inners (dark bores inside the chrome tips below) —
	# DUAL exhausts (left + right).
	for ex in [-0.62, 0.62]:
		_bake_cyl(s_dark, 0.045, 0.045, 0.15, 8, _xf(Vector3(ex, 0.34, 2.42), Vector3(90, 0, 0)))

	# --- Trim details (mid-grey). ---
	_bake_box(s_trim, Vector3(2.02, 0.16, 0.22), _xf(Vector3(0, 0.38, -2.72), zero))
	# Rear bumper = the bumper STEP (proud to z=2.46, the max
	# extent): a real 3D step with shaded sides, not a flat box.
	_bake_box(s_trim, Vector3(2.04, 0.18, 0.24), _xf(Vector3(0, 0.36, 2.34), zero))
	# Split side skirts (3 segments per side, gaps at the wheels).
	# Widened to x=±0.97 / 0.10 thick so they stay in contact with
	# the tapering body side (hw 0.93 at the cab rear).
	for sx3 in [-1.0, 1.0]:
		_bake_box(s_trim, Vector3(0.10, 0.18, 0.50), _xf(Vector3(sx3 * 0.97, 0.40, -2.20), zero))
		_bake_box(s_trim, Vector3(0.10, 0.18, 1.90), _xf(Vector3(sx3 * 0.97, 0.40, 0), zero))
		_bake_box(s_trim, Vector3(0.10, 0.18, 0.50), _xf(Vector3(sx3 * 0.97, 0.40, 2.20), zero))
	# Side steps below the sills, between the wheels.
	for sx7 in [-1.0, 1.0]:
		_bake_box(s_trim, Vector3(0.24, 0.06, 1.10), _xf(Vector3(sx7 * 1.02, 0.26, 0), zero))
	# Bed rail caps.
	_bake_box(s_trim, Vector3(0.12, 0.04, 1.30), _xf(Vector3(-0.93, 1.29, 1.66), zero))
	_bake_box(s_trim, Vector3(0.12, 0.04, 1.30), _xf(Vector3(0.93, 1.29, 1.66), zero))
	# Dark lower rear valance (proud 0.008 of the tail cap: no
	# coplanar z-fight). The lone horizontal tailgate seam is
	# REMOVED — the inset panel's edges carry the panel-gap read,
	# and a seam across the panel would reintroduce stripe reads.
	_bake_box(s_trim, Vector3(1.90, 0.28, 0.02), _xf(Vector3(0, 0.62, 2.318), zero))
	# Side character lines REMOVED — the facet edges + the 0.55
	# two-tone split carry the side read; long trim strips read as
	# stuck-on.

	# --- Chrome details. ---
	for gy in [0.46, 0.52, 0.58]:
		_bake_box(s_chrome, Vector3(1.50, 0.02, 0.02), _xf(Vector3(0, gy, -2.835), zero))
	for ex2 in [-0.62, 0.62]:
		_bake_cyl(s_chrome, 0.06, 0.06, 0.14, 10, _xf(Vector3(ex2, 0.34, 2.42), Vector3(90, 0, 0)))

	# --- Number plate. ---
	_bake_box(s_plate, Vector3(0.46, 0.11, 0.015), _xf(Vector3(0, 0.66, 2.345), zero))

	var body_mesh := _merged_mesh([s_paint, s_low, s_glass, s_dark, s_trim, s_chrome, s_plate], [paint_mat, paint_low_mat, glass_mat, dark_mat, trim_mat, chrome_mat, plate_mat])
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = body_mesh
	body_mi.name = "BodyMesh"
	body.add_child(body_mi)

	# Full-width front light bar + corner pods, ONE merged mesh in
	# ONE node (name preserved, 1 draw).
	var s_front := _surf_new()
	_bake_box(s_front, Vector3(1.86, 0.09, 0.06), _xf(Vector3(0, 0.80, -2.815), zero))
	_bake_box(s_front, Vector3(0.34, 0.12, 0.06), _xf(Vector3(-0.72, 0.60, -2.815), zero))
	_bake_box(s_front, Vector3(0.34, 0.12, 0.06), _xf(Vector3(0.72, 0.60, -2.815), zero))
	var front_light := MeshInstance3D.new()
	front_light.mesh = _merged_mesh([s_front], [front_mat])
	front_light.name = "HeadlightBar"
	body.add_child(front_light)

	# Rear light bar (taller, proud of the tailgate) + red
	# wrap-around corner pods on the bed sides, ONE merged mesh in
	# ONE node (name preserved, 1 draw). Deep-red Round-6 material.
	var s_rear := _surf_new()
	_bake_box(s_rear, Vector3(1.90, 0.16, 0.05), _xf(Vector3(0, 0.86, 2.34), zero))
	_bake_box(s_rear, Vector3(0.03, 0.14, 0.30), _xf(Vector3(-0.99, 0.86, 2.05), zero))
	_bake_box(s_rear, Vector3(0.03, 0.14, 0.30), _xf(Vector3(0.99, 0.86, 2.05), zero))
	var rear_light := MeshInstance3D.new()
	rear_light.mesh = _merged_mesh([s_rear], [tail_mat])
	rear_light.name = "TaillightBar"
	body.add_child(rear_light)

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

	# Hero taillight halo (GATE R3): ONE additive billboard quad.
	body.add_child(_make_hero_halo())

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
	# v2.3 (GATE S9): darker glass for window contrast + a darkened
	# cab paint (x0.85) for sharper cab/body distinction. Colours
	# stay caller-owned (traffic_manager CAR_COLORS, FROZEN); only
	# USAGE changes. Same box count — zero new draws.
	var glass_mat := _std(Color(0.02, 0.03, 0.06), 0.6, 0.15)
	var cab_mat := _std(Color(color.r * 0.85, color.g * 0.85, color.b * 0.85), 0.65, 0.28)

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
		body.add_child(_box(Vector3(width * 0.92, 0.85, cab_len), Vector3(0, 1.25, cab_z), cab_mat))
		body.add_child(_box(Vector3(width * 0.94, 0.44, cab_len * 0.62), Vector3(0, 1.3, cab_z), glass_mat))
		var box_len := length - cab_len - 1.2
		var box_z := cab_z + cab_len * 0.5 + box_len * 0.5 + 0.6
		var box_mat := _std(Color(0.75, 0.74, 0.72), 0.3, 0.55) if kind == "truck" else _std(Color(0.55, 0.58, 0.62), 0.7, 0.4)
		body.add_child(_box(Vector3(width, 2.1, box_len), Vector3(0, 1.45, box_z), box_mat))
		body.add_child(_box(Vector3(width, 0.12, box_len), Vector3(0, 2.52, box_z), dark_mat))
	else:
		# Cabin + glasshouse. The glass box is WIDER than the cab
		# (0.92 vs 0.90) so it reads as a side glass band, but
		# shorter and lower-profile than the cab, so a paint frame
		# shows above/below/around it (cab/body distinction).
		# Round-2 fix: a 0.84-wide glass box was fully buried
		# inside the cab and invisible in renders.
		var cab_h := 0.55 if kind == "van" else 0.45
		body.add_child(_box(Vector3(width * 0.9, cab_h, cab_len), Vector3(0, 1.1, cab_z), cab_mat))
		body.add_child(_box(Vector3(width * 0.92, cab_h * 0.55, cab_len * 0.66), Vector3(0, 1.12, cab_z), glass_mat))
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
	# v2.3: brighter (0.5) + slightly taller for taillight read.
	body.add_child(_box(Vector3(width * 0.8, 0.08, 0.04), Vector3(0, 0.62, rear_z), _std(Color(0.5, 0.03, 0.03), 0.0, 0.3, Color(1.0, 0.06, 0.06), 0.5)))

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

# Palm bark texture (FROZEN path, GATE R1 — Lane B owns ALL of
# assets/; Lane A only loads this path, never writes under assets/).
const PALM_BARK_PATH := "res://assets/palm_bark_512.jpg"
static var _frond_tex: ImageTexture = null

static func _make_frond_texture(size: int) -> ImageTexture:
	# ORIGINAL procedural pinnate frond mask (runtime-generated
	# Image — no file, no import, no licence risk): central rib +
	# tapered diagonal leaflets, hard 0/1 alpha for alpha-scissor.
	# U runs along the leaf (base -> tip), V across it. Mipmaps ON
	# so distant fronds average toward solid instead of shimmering
	# (GATE R7f / D8 mip check). Cached globally: textures are never
	# mutated, so sharing across palms is safe (same pattern as the
	# glow texture). If this is ever saved as a PNG instead, it must
	# be marked ORIGINAL in a code comment + SOURCES.md via Lane B.
	if _frond_tex != null:
		return _frond_tex
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var u: float = (float(x) + 0.5) / float(size)
			var vv: float = (float(y) + 0.5) / float(size)
			var v: float = absf(vv - 0.5) * 2.0
			# Silhouette: narrow stem, full mid-leaf, pointed tip.
			var env: float = smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.70, 1.0, u))
			if u < 0.03:
				env = 0.08
			var alpha: float = 0.0
			if v <= env:
				# Central rib, tapering toward the tip.
				var rib: float = 0.07 + 0.04 * (1.0 - u)
				if v <= rib:
					alpha = 1.0
				else:
					# Diagonal leaflets, angled toward the tip and
					# TAPERING to points: wide at the rib, narrow
					# at the edge (uniform stripes read as a comb).
					# v2.3 (GATE S10): FEWER, WIDER leaflets (9.0
					# not 11.0) to reduce the stripey/comb read
					# closer than ~5 m. GLOBAL-SHARED lever: this
					# one texture serves every palm in every biome.
					var phase: float = fposmod(u * 9.0 - v * 3.2, 1.0)
					var leaf_w: float = lerpf(0.85, 0.62, v)
					if phase < leaf_w:
						alpha = 1.0
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	img.generate_mipmaps()
	_frond_tex = ImageTexture.create_from_image(img)
	return _frond_tex

static func _apply_frond_mask(m: StandardMaterial3D, tex: Texture2D) -> void:
	# Godot 4 alpha-cut: TRANSPARENCY_ALPHA_SCISSOR (depth writes,
	# no blending/sorting) + threshold. There is no separate
	# scissor-mode enum in 4.3.
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

static func _palm_materials() -> Array:
	# The 5 palm materials, created ONCE and shared by every palm:
	# leaf/trunk materials are never mutated (world_builder touches
	# only each palm root's position/rotation/scale/visible), so
	# global sharing is safe. Fronds must read GREEN, not yellow
	# umbrellas: deep green albedo, a faint GREEN (not orange)
	# emission lift, and two alternating shades so individual leaves
	# separate from each other. The third, darker shade is the
	# under-ring: leaves in shadow under the crown.
	# Cinematic rebuild: the trunk uses the frozen CC0 bark texture
	# (Lane B) when present, with a LOUD fallback to the old flat
	# material when it is missing (palm texture pending Lane B);
	# the fronds get the procedural alpha-scissor mask above
	# (alpha_scissor, NOT transparency — depth writes, no sorting).
	if _palm_trunk_mat == null:
		var bark: Texture2D = null
		if ResourceLoader.exists(PALM_BARK_PATH):
			bark = load(PALM_BARK_PATH) as Texture2D
		if bark != null:
			_palm_trunk_mat = _std_fresh(Color(1.0, 1.0, 1.0), 0.0, 0.85)
			_palm_trunk_mat.albedo_texture = bark
			_palm_trunk_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		else:
			push_warning("Lane A palm: palm bark texture missing at " + PALM_BARK_PATH + " (palm texture pending Lane B) - using flat trunk material.")
			_palm_trunk_mat = _std_fresh(Color(0.45, 0.30, 0.17), 0.0, 0.85)
		# v2.3 silhouette darkening (GATE S10/V14): the THREE leaf
		# materials are darker with less green emission lift, so
		# palms read as DARK SILHOUETTES against the bright sky
		# (motion reference r_002/r_034). Render-gated: distant
		# crowns must stay feathered, not black blobs.
		_palm_leaf_mat = _std_fresh(Color(0.05, 0.30, 0.11), 0.0, 0.6, Color(0.03, 0.18, 0.06), 0.10)
		_palm_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_palm_leaf_mat2 = _std_fresh(Color(0.04, 0.24, 0.09), 0.0, 0.6, Color(0.02, 0.14, 0.05), 0.10)
		_palm_leaf_mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
		_palm_leaf_mat3 = _std_fresh(Color(0.02, 0.14, 0.05), 0.0, 0.7, Color(0.01, 0.09, 0.03), 0.10)
		_palm_leaf_mat3.cull_mode = BaseMaterial3D.CULL_DISABLED
		_palm_nut_mat = _std_fresh(Color(0.35, 0.22, 0.1), 0.0, 0.8)
		var frond_tex := _make_frond_texture(256)
		_apply_frond_mask(_palm_leaf_mat, frond_tex)
		_apply_frond_mask(_palm_leaf_mat2, frond_tex)
		_apply_frond_mask(_palm_leaf_mat3, frond_tex)
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
