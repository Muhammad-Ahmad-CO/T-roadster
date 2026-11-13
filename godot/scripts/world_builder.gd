class_name WorldBuilder
extends Node3D

## Builds and scrolls the T Roadster world: coastal highway at sunset.
## Coordinate convention: the road runs along -Z (horizon at far -Z),
## the player sits near z = 0, the camera sits behind at +Z. The world
## scrolls +Z past the player — the player never moves.
##
## Hyper-real push (this rebuild exists for the look): low sun disc +
## glow over the ocean on the LEFT, fake god-ray shafts, a wet road that
## catches the sunset, palms with individual drooping fronds and warm rim
## light, heat-haze shimmer above the asphalt, layered horizon haze,
## emissive-window skyline, drifting clouds, ACES tone mapping (glow OFF
## — brightness compensation lives in _apply_palette / get_biome_palette).
## Everything is procedural and original — no imported art, no brands.
##
## Performance (Oppo F9, Android 8.1): shared materials everywhere,
## one sun shadow-caster only (1024 map), low-poly props, recycled
## segments, and zero allocations in scroll() — the hot loop only moves
## existing nodes and reuses prebuilt arrays.

const LANE_X := [-4.5, -1.5, 1.5, 4.5]

const ROAD_WIDTH := 12.0
const LANE_WIDTH := 3.0
const SEGMENT_LEN := 20.0
const SEGMENT_COUNT := 12
const WORLD_SPAN := 240.0
const RECYCLE_Z := 15.0
const FAR_Z := -225.0
const PALM_COUNT := 40 # v2.3 GATE §V5: 34 -> 40 (+6 net, the V12 cap; +30 draws). Denser palms where the reel shows them (left ocean side).
const POLE_SPACING := 40.0
# Cinematic rebuild (follow-up: near-camera intrusion at the Lane C R8
# camera, z=20, FOV 64): poles/palms recycle well BEFORE the camera
# plane. The old thresholds let poles reach z=35 (15 m BEHIND the
# camera) and palms z=15 (5 m ahead), so poles loomed huge and clipped
# at the frame edges and palm crowns intruded at the corners (proven
# in lane-c R8 renders + lane-b/newcam-before_*.png). -10 keeps every
# pole/palm >= 30 m ahead of the z=20 camera. Count/spacing/density
# are unchanged: the recycle window just shifts 25-45 m forward, and
# subtracting WORLD_SPAN (6x the pole spacing) keeps the pole lattice.
# Road/guard segments keep RECYCLE_Z: the road edge must extend under
# the camera, and guards are low roadside geometry, not looming.
const POLE_RECYCLE_Z := -10.0
const PALM_RECYCLE_Z := -10.0
const CLOUD_COUNT := 0
# v2.3 GATE §V2 [S3]: DEFAULT NO CLOUDS — the motion reference shows
# NO clouds in the reel in motion, and the flat pink discs were the
# single most fake element on the phone. Removal mechanism: COUNT=0
# (the _build_clouds loop no-ops; _clouds stays empty so scroll()'s
# drift/wrap loop is safe; _apply_palette never touched _clouds).
# Faint wisps ONLY if the sky reads empty AND the lead approves from
# a render — not pre-approved; see REPORT.md per-biome decisions.
# v2.3 GATE §V1: sun disc HEIGHT, staged (33 -> 26 -> 20 -> 15, each
# render-judged vs the reel). ONE value drives all three position
# literals in _build_sun (disc + 2 halo quads) — no stale height can
# survive. Disc radius + sun/fill light directions stay FROZEN.
# FINAL height is recorded in v23-scratch/lane-b/REPORT.md.
const SUN_Y := 20.0

var _biome := "coastal"
var _palette: Dictionary = {}

var _env: WorldEnvironment
var _environment: Environment
var _sky: Sky
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _sun_disc: MeshInstance3D
var _sun_disc_mat: ShaderMaterial
var _sun_halo: MeshInstance3D
var _sun_halo2: MeshInstance3D
var _sun_halo_mat: StandardMaterial3D
var _sun_halo2_mat: StandardMaterial3D
var _sun_streak: MeshInstance3D
var _sun_streak_mat: StandardMaterial3D
var _halo_tex: Texture2D
var _lamp_halo_mat: StandardMaterial3D

var _scroll_root: Node3D
var _road_segments: Array[Node3D] = []
var _guard_segments: Array[Node3D] = []
var _pole_segments: Array[Node3D] = []
var _palm_nodes: Array[Node3D] = []
var _verge_nodes: Array[Node3D] = []
var _clouds: Array[Node3D] = []
var _stars: MeshInstance3D
var _shafts: Array[MeshInstance3D] = []
var _haze_plane: MeshInstance3D
var _ocean: MeshInstance3D
var _ocean_mat: ShaderMaterial
var _road_mat: ShaderMaterial
var _ground: MeshInstance3D
var _ground_mat: StandardMaterial3D
var _sand: MeshInstance3D
var _sand_mat: StandardMaterial3D
var _skyline: Node3D
var _window_mat: StandardMaterial3D
var _window_dark_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _pole_lamp_mat: StandardMaterial3D
var _rail_mat: StandardMaterial3D
var _shaft_mat: StandardMaterial3D
var _haze_mat: ShaderMaterial
var _skyline_mat: StandardMaterial3D

var _rng := RandomNumberGenerator.new()
var _built := false

# Preloaded (not just class_name) so this file also parses standalone
# under --check-only without a built global class cache.
const _Vehicles := preload("res://scripts/vehicles.gd")

# ---------------------------------------------------------------- palettes

static func get_biome_palette(biome: String) -> Dictionary:
	match biome:
		"neon":
			return {
				"sky_top": Color(0.02, 0.01, 0.10), "sky_horizon": Color(0.55, 0.08, 0.55),
				"ground_bottom": Color(0.03, 0.02, 0.08), "ground_horizon": Color(0.20, 0.05, 0.30),
				"sun_color": Color(1.0, 0.25, 0.85), "sun_energy": 1.4,
				"fill_color": Color(1.0, 0.4, 0.9), "fill_energy": 0.25,
				"fog_color": Color(0.25, 0.08, 0.35), "fog_density": 0.006,
				"ambient_color": Color(0.35, 0.2, 0.5),
				"ocean_color": Color(0.05, 0.02, 0.15), "road_color": Color(0.04, 0.04, 0.08),
				"haze_color": Color(0.85, 0.3, 1.0),
			}
		"canyon":
			return {
				"sky_top": Color(0.10, 0.16, 0.38), "sky_horizon": Color(1.0, 0.55, 0.25),
				"ground_bottom": Color(0.25, 0.12, 0.07), "ground_horizon": Color(0.65, 0.35, 0.18),
				"sun_color": Color(1.0, 0.62, 0.3), "sun_energy": 1.9,
				"fill_color": Color(1.0, 0.6, 0.4), "fill_energy": 0.35,
				"fog_color": Color(0.85, 0.5, 0.28), "fog_density": 0.005,
				"ambient_color": Color(0.6, 0.45, 0.35),
				"ocean_color": Color(0.10, 0.08, 0.12), "road_color": Color(0.07, 0.06, 0.06),
				"haze_color": Color(1.0, 0.6, 0.35),
			}
		"desert":
			return {
				"sky_top": Color(0.12, 0.30, 0.55), "sky_horizon": Color(1.0, 0.75, 0.45),
				"ground_bottom": Color(0.45, 0.30, 0.15), "ground_horizon": Color(0.85, 0.6, 0.35),
				"sun_color": Color(1.0, 0.85, 0.6), "sun_energy": 2.2,
				"fill_color": Color(1.0, 0.75, 0.55), "fill_energy": 0.4,
				"fog_color": Color(0.95, 0.75, 0.5), "fog_density": 0.004,
				"ambient_color": Color(0.75, 0.6, 0.45),
				"ocean_color": Color(0.10, 0.08, 0.12), "road_color": Color(0.08, 0.07, 0.06),
				"haze_color": Color(1.0, 0.8, 0.55),
			}
		"snow":
			return {
				"sky_top": Color(0.25, 0.35, 0.55), "sky_horizon": Color(0.85, 0.75, 0.85),
				"ground_bottom": Color(0.75, 0.78, 0.85), "ground_horizon": Color(0.9, 0.88, 0.92),
				"sun_color": Color(0.95, 0.9, 0.95), "sun_energy": 1.5,
				"fill_color": Color(0.85, 0.9, 1.0), "fill_energy": 0.3,
				"fog_color": Color(0.85, 0.86, 0.9), "fog_density": 0.007,
				"ambient_color": Color(0.7, 0.72, 0.8),
				"ocean_color": Color(0.2, 0.3, 0.45), "road_color": Color(0.06, 0.06, 0.08),
				"haze_color": Color(0.9, 0.92, 0.95),
			}
		"rain":
			return {
				"sky_top": Color(0.08, 0.09, 0.18), "sky_horizon": Color(0.35, 0.22, 0.35),
				"ground_bottom": Color(0.05, 0.05, 0.09), "ground_horizon": Color(0.2, 0.12, 0.22),
				"sun_color": Color(1.0, 0.55, 0.5), "sun_energy": 1.3,
				"fill_color": Color(0.7, 0.6, 0.8), "fill_energy": 0.2,
				# Round 6 — fog/ambient cooled toward blue-violet so the
				# wet left lane stops reading pink (was 0.35,0.25,0.35 /
				# 0.4,0.35,0.45; left lane measured 170,72,83).
				# Iteration 4 — 0.16 still read (14,12,32): the dense
				# rain fog (0.009) darkens the far road toward its
				# dark fog colour, so the albedo alone can't lift
				# it. 0.16 -> 0.22 for a dark blue-grey readable
				# road; the pink stays out because the mirror is
				# still only 0.20 and the fog/ambient are cool.
				"fog_color": Color(0.29, 0.28, 0.38), "fog_density": 0.009,
				"ambient_color": Color(0.36, 0.37, 0.46),
				"ocean_color": Color(0.04, 0.06, 0.16), "road_color": Color(0.22, 0.22, 0.24),
				"haze_color": Color(0.8, 0.45, 0.55),
			}
		_: # "coastal" — the hero sunset. Cinematic rebuild (GATE R9):
			# purple-top -> magenta -> peach horizon sky, warm peach
			# fog so the far skyline melts into the sunset (the
			# v2.1.0 cool/thin fog is superseded for coastal).
			return {
				"sky_top": Color(0.12, 0.02, 0.20), "sky_horizon": Color(1.00, 0.55, 0.45),
				"ground_bottom": Color(0.08, 0.06, 0.14), "ground_horizon": Color(0.55, 0.32, 0.30), # Lead amendment A1 (2026-11-12): 0.35,0.20,0.22 left a black horizon wedge; this value warmed it. A1b (0.70,0.42,0.38) tried + REVERTED: no further effect on the residual thin line, proving it is geometry (plane far edge), not sky. Coastal only.
				"sun_color": Color(1.0, 0.62, 0.38), "sun_energy": 1.7,
				# Lane B glow-OFF compensation: fill 0.38 -> 0.50,
				# palette dict only — _apply_palette overwrites
				# build-time fill values on every biome change.
				"fill_color": Color(1.0, 0.55, 0.42), "fill_energy": 0.50,
				# Cinematic rebuild (GATE R9, inv1 §4.2): warm peach fog
				# (0.90,0.60,0.55 — the PROBED colour) + density
				# 0.0018 -> 0.0022. The v2.1.0 Round 6 cool/thin fog
				# is superseded: the reel's horizon haze IS warm.
				# v2.3 §V8: 0.0022 -> 0.0026 (COASTAL-only staged
				# render; beyond 0.0022 requires one per §V8/S13).
				# Stronger aerial perspective so skyline crowns melt.
				# Falsifier: near road/hero wash pink -> step back.
				"fog_color": Color(0.90, 0.60, 0.55), "fog_density": 0.0026,
				"ambient_color": Color(0.44, 0.44, 0.48),
				"ocean_color": Color(0.04, 0.16, 0.42), "road_color": Color(0.30, 0.29, 0.32),
				# Cinematic rebuild (GATE R4): haze 0.95,0.50,0.42 -> 1.00,0.62,0.50 (feeds the ocean sunset_color + road sun_tint + heat haze via _apply_palette).
				"haze_color": Color(1.00, 0.62, 0.50),
			}

# ---------------------------------------------------------------- build

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_rng.randomize()
	_palette = get_biome_palette("coastal")
	_scroll_root = Node3D.new()
	_scroll_root.name = "ScrollRoot"
	add_child(_scroll_root)
	_build_environment()
	_build_sun()
	_build_ground()
	_build_ocean()
	_build_road()
	_build_guardrails()
	_build_poles()
	_build_palms()
	_build_verge()
	_build_skyline()
	_build_clouds()
	_build_stars()
	_build_shafts()
	_build_haze()
	_apply_palette()

func _std(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	return m

func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	return mi

# Merges primitive meshes into one ArrayMesh with one surface per
# material. Each part is [mesh, transform, material_index]; the
# transform is baked into the vertices (normals via the
# inverse-transpose, so non-uniform squash stays correct). Only
# vertex / normal / UV / index arrays are carried over — tangents
# are dropped, because none of the merged materials uses a normal
# map. Source meshes are never modified, so one BoxMesh can feed
# many parts. Used by the Lane B cloud / guardrail / pole merges.
func _merge_parts(parts: Array, materials: Array) -> ArrayMesh:
	var group_count := materials.size()
	var verts: Array = []
	var normals: Array = []
	var uvs: Array = []
	var indices: Array = []
	for g in range(group_count):
		verts.append(PackedVector3Array())
		normals.append(PackedVector3Array())
		uvs.append(PackedVector2Array())
		indices.append(PackedInt32Array())
	for part in parts:
		var src: Mesh = part[0]
		var xform: Transform3D = part[1]
		var gi: int = part[2]
		var arrays: Array = src.surface_get_arrays(0)
		var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var src_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var src_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var src_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := (verts[gi] as PackedVector3Array).size()
		var normal_xform := xform.basis.inverse().transposed()
		var gv: PackedVector3Array = verts[gi]
		var gn: PackedVector3Array = normals[gi]
		var gu: PackedVector2Array = uvs[gi]
		var gidx: PackedInt32Array = indices[gi]
		for vi in range(src_verts.size()):
			gv.append(xform * src_verts[vi])
			gn.append((normal_xform * src_normals[vi]).normalized())
			gu.append(src_uvs[vi] if vi < src_uvs.size() else Vector2.ZERO)
		for idx in src_indices:
			gidx.append(base + idx)
		verts[gi] = gv
		normals[gi] = gn
		uvs[gi] = gu
		indices[gi] = gidx
	var out := ArrayMesh.new()
	for g in range(group_count):
		var out_arrays: Array = []
		out_arrays.resize(Mesh.ARRAY_MAX)
		out_arrays[Mesh.ARRAY_VERTEX] = verts[g]
		out_arrays[Mesh.ARRAY_NORMAL] = normals[g]
		out_arrays[Mesh.ARRAY_TEX_UV] = uvs[g]
		out_arrays[Mesh.ARRAY_INDEX] = indices[g]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
		out.surface_set_material(g, materials[g])
	return out

func _build_environment() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = _palette["sky_top"]
	_sky_mat.sky_horizon_color = _palette["sky_horizon"]
	_sky_mat.sky_curve = 0.18 # Cinematic rebuild (GATE R9): 0.12 -> 0.18 widens the pale horizon band. GLOBAL (all biomes). Falsifier: zenith pinks -> back to 0.14-0.15, widen via the ribbon instead.
	_sky_mat.sky_energy_multiplier = 1.0
	_sky_mat.ground_bottom_color = _palette["ground_bottom"]
	_sky_mat.ground_horizon_color = _palette["ground_horizon"]
	_sky_mat.ground_curve = 0.08
	_sky_mat.ground_energy_multiplier = 0.6
	# Tiny sky sun: the manual sun-disc sphere IS the sun — the sky's
	# own disc must not double it (it sits at the same light direction).
	_sky_mat.sun_angle_max = 1.0
	_sky_mat.sun_curve = 0.05
	_sky = Sky.new()
	_sky.sky_material = _sky_mat
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = _sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = _palette["ambient_color"]
	_environment.ambient_light_energy = 2.0
	_environment.ambient_light_sky_contribution = 0.0
	# Round 5 — ambient_light_sky_contribution defaults to 1.0, which
	# REPLACES the palette ambient colour with the sky's irradiance:
	# the pink-orange sunset sky then washed every surface (the grey
	# road read orange-brown, the white hero read pink-mauve) and no
	# road-shader light() could fix it, because the ambient never
	# passes through light(). 0.0 keeps the palette colour (nearly
	# neutral mauve-grey for coastal) so the ambient is neutral and
	# the sunset warmth comes from the sun + sky + fog instead.
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 1.28
	_environment.tonemap_white = 1.2
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = 1.05
	_environment.adjustment_contrast = 1.05
	_environment.adjustment_brightness = 1.0
	# Lane B: glow OFF — the fullscreen blur passes are the most
	# expensive effect on tile-based Mali GPUs. Brightness is
	# compensated per-biome in _apply_palette (window emission,
	# sun-disc energy, sun-halo alpha) plus the coastal fill lift in
	# get_biome_palette. The intensity/strength/bloom values below
	# are kept so the recorded fallback (glow for neon only) can be
	# re-enabled from _apply_palette without re-tuning.
	_environment.glow_enabled = false
	_environment.glow_intensity = 0.25
	_environment.glow_strength = 0.7
	_environment.glow_bloom = 0.15
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_environment.fog_enabled = true
	_environment.fog_light_color = _palette["fog_color"]
	_environment.fog_light_energy = 0.4
	# Cinematic rebuild (GATE R9, inv1 §4.2): sun scatter 0.15 -> 0.35
	# (warms fog toward the sun, i.e. down the road ahead) and height
	# density 0.01 -> 0.003 (height fog was ~half the near-road fog
	# lift). Both GLOBAL (all biomes) — all-6-biome renders required.
	# Falsifier order if the near road/hero wash pink: scatter ->
	# height_density -> density. fog_mode is NEVER set (depth fog is
	# a measured no-op); aerial perspective left untouched (dead).
	_environment.fog_sun_scatter = 0.35
	_environment.fog_density = float(_palette["fog_density"])
	_environment.fog_height = 8.0
	_environment.fog_height_density = 0.003
	_environment.fog_aerial_perspective = 0.12
	_env = WorldEnvironment.new()
	_env.environment = _environment
	add_child(_env)

func _build_sun() -> void:
	# Low warm key light from the FRONT-LEFT (-X, -Z), over the ocean,
	# so the sun disc, the light and the glitter path all agree: the
	# sun sits ~13 deg left of straight ahead, ~8 deg above the
	# horizon, i.e. at direction (-0.23, +0.14, -0.96) from the scene.
	# Rotation is (-8, -166.6, 0) — VERIFIED with a Godot probe
	# (sun_test.gd): -basis.z of that rotation is (0.23, -0.14, +0.96),
	# so the sun sits at (-0.23, +0.14, -0.96). The earlier (-8, -13.4,
	# 0) put the sun BEHIND the camera (+Z) and blew the hero's rear
	# face out to pure white; the original (-10, -52, 0) had the same
	# bug, so the sky sun never matched the disc.
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-8.0, -166.6, 0)
	_sun.light_color = _palette["sun_color"]
	_sun.light_energy = float(_palette["sun_energy"])
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# Lane B shadow diet: max distance 150 -> 80 m, blur 2.0 -> 0
	# (the shadow pass was ~54% of all draw calls). Opacity stays
	# 0.3; rotation, colour and energy are unchanged. The 1024
	# shadow-map size is Lane C's project.godot change.
	_sun.directional_shadow_max_distance = 60.0
	_sun.shadow_blur = 0.0
	_sun.shadow_bias = 0.03
	# Round 4: the hero's own shadow used to swallow the bottom third
	# of the chase frame as a solid black slab. shadow_opacity 0.55
	# lets the (now brighter) ambient light show through the shadow
	# so it reads as a soft sunset shadow, not a black hole; the wider
	# blur softens its edge. Light angle/position unchanged.
	_sun.shadow_opacity = 0.3
	add_child(_sun)

	# Warm fill from behind the camera (above, +Z side): the rear faces
	# of traffic and the hero face AWAY from the sun, so direct sun
	# never touches them — without a fill they read as black boxes.
	# Energy 0.3 just models the shape; the scene must still read as
	# "driving into the sunset". No shadows — this light only lifts.
	_fill = DirectionalLight3D.new()
	_fill.name = "SunsetFill"
	_fill.rotation_degrees = Vector3(-30, 5, 0)
	_fill.light_color = _palette["fill_color"]
	_fill.light_energy = float(_palette["fill_energy"])
	_fill.shadow_enabled = false
	add_child(_fill)

	# Visible sun disc: fog-disabled shader sphere sitting on the
	# horizon over the ocean, plus soft radial halo quads around it
	# (GATE R3 — the old SunGlow Sprite3D never read in renders).
	# Disc at x=-54 keeps it ~13 deg left of centre in the portrait
	# chase frame (horizontal FOV is only ~37 deg — the old x=-95 disc
	# at 22 deg off-axis fell outside the frame entirely).
	var disc_shader := load("res://shaders/sun_disc.gdshader") as Shader
	var disc_mat := ShaderMaterial.new()
	disc_mat.shader = disc_shader
	# Cinematic rebuild (GATE R9 §4.3): near-white disc colour BEFORE
	# energy — on this LDR renderer energy alone cannot un-yellow an
	# orange base (the old (1,0.38,0.08) clipped R first -> yellow).
	# Build-time defaults are the COASTAL values; _apply_palette
	# overwrites them per biome on every biome change (both sites
	# must agree). Radius UNCHANGED; height is SUN_Y (v2.3 §V1).
	disc_mat.set_shader_parameter("disc_color", Color(1.0, 0.85, 0.70))
	disc_mat.set_shader_parameter("energy", 3.0)
	_sun_disc_mat = disc_mat
	_sun_disc = MeshInstance3D.new()
	_sun_disc.name = "SunDisc"
	var disc_mesh := SphereMesh.new()
	disc_mesh.radius = 10.0
	disc_mesh.height = 20.0
	disc_mesh.radial_segments = 16
	disc_mesh.rings = 8
	disc_mesh.material = disc_mat
	_sun_disc.mesh = disc_mesh
	_sun_disc.position = Vector3(-54, SUN_Y, -233)
	add_child(_sun_disc)

	# Cinematic rebuild (GATE R3): the SunGlow Sprite3D is REMOVED
	# (it never read in renders — fogged + low contrast) and replaced
	# by billboarded halo quads using the proven in-repo pattern
	# (StandardMaterial3D + shared radial texture, as in
	# particles.gd): UNSHADED, TRANSPARENCY_ALPHA, BLEND_MODE_ADD,
	# BILLBOARD_ENABLED, fog disabled, depth-draw DISABLED (still
	# depth-TESTED, so skyline/palms occlude; never depth-WRITES),
	# cast_shadow OFF (a transparent quad must not cast a square
	# shadow or add shadow-pass draws). NO custom halo shader.
	# Inner halo ~44 m at the disc +0.5 m toward the camera, peak
	# alpha ~0.75; outer halo ~80 m, peak alpha ~0.28 (lead
	# iteration 1: 0.55/0.18 read too weak — hard disc edge).
	# Additive blending is order-independent, so the shared
	# position is safe.
	_halo_tex = _make_radial_texture(256, Color(1.0, 0.9, 0.8), Color(1.0, 0.55, 0.40))
	_sun_halo_mat = _halo_material(Color(1.0, 1.0, 1.0, 0.75))
	_sun_halo = _halo_quad(44.0, _sun_halo_mat)
	_sun_halo.name = "SunHalo"
	_sun_halo.position = Vector3(-54, SUN_Y, -232.5)
	add_child(_sun_halo)
	_sun_halo2_mat = _halo_material(Color(1.0, 1.0, 1.0, 0.28))
	_sun_halo2 = _halo_quad(80.0, _sun_halo2_mat)
	_sun_halo2.name = "SunHalo2"
	_sun_halo2.position = Vector3(-54, SUN_Y, -232.5)
	add_child(_sun_halo2)

	# v2.3 GATE §V1 [S2]: ONE horizontal flare streak quad (anamorphic
	# streak INTERPRETATION of the motion reference's horizontal flare
	# glow — render-gated, drop falsifier applies: solid bar or horizon
	# blowout -> narrow/fade/drop). Additive R3 halo pattern via the
	# SHARED _halo_tex/_halo_material (NOT modified — the billboarded
	# radial texture stretched wide gives soft horizontal ends; camera
	# roll = 0 keeps it horizontal). Bounds: 140 m wide x 9 m tall,
	# centred on the disc, peak alpha 0.22 coastal (rain dims in
	# _apply_palette). +1 draw. Non-square size needs _halo_quad_rect
	# (_halo_quad makes SQUARE quads only).
	_sun_streak_mat = _halo_material(Color(1.0, 1.0, 1.0, 0.22))
	_sun_streak = _halo_quad_rect(140.0, 9.0, _sun_streak_mat)
	_sun_streak.name = "SunStreak"
	_sun_streak.position = Vector3(-54, SUN_Y, -232.5)
	add_child(_sun_streak)

func _make_radial_texture(size: int, inner: Color, outer: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var d: float = clamp(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			# Hot core, long soft falloff. Lead iteration 1
			# (2026-11-12): exponent 1.6 -> 1.2 and alpha t*t
			# -> t — the steeper falloff left the sun disc
			# hard-edged in the final renders (visible glow
			# only ~1.5 disc radii). Wider/softer for sun
			# AND lamp halos (shared texture).
			var t := pow(1.0 - d, 1.2)
			var c := outer.lerp(inner, t)
			c.a = t
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# Halo pattern (GATE R3, shared by the sun halos in _build_sun and the
# lamp halos in _build_poles): one radial texture, one material per
# tint, one quad per halo. The texture carries the warm inner->outer
# falloff; the material albedo_color carries the per-use tint + peak
# alpha (texture alpha x material alpha).
func _halo_material(tint: Color) -> StandardMaterial3D:
	if _halo_tex == null:
		_halo_tex = _make_radial_texture(256, Color(1.0, 0.9, 0.8), Color(1.0, 0.55, 0.40))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_fog = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_texture = _halo_tex
	m.albedo_color = tint
	return m

func _halo_quad(size_m: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size_m, size_m)
	q.material = mat
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# v2.3 §V1: non-square halo quad for the horizontal flare streak.
# Same R3 pattern as _halo_quad (material carries the shared radial
# texture + additive blend); only the quad size is rectangular.
func _halo_quad_rect(width_m: float, height_m: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width_m, height_m)
	q.material = mat
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _build_ground() -> void:
	# Far ground plane under everything (right side / scrub land).
	# NOTE: it must NOT extend over the ocean: it used to span
	# x=-100..220 at y=-0.15, sitting ABOVE the ocean plane (y=-0.35)
	# and hiding the water entirely. Now it starts at the sand's right
	# edge (x=-6) and runs right.
	# Round 7 — ground cooled toward grey-mauve (was 0.22,0.17,0.19):
	# under the warm sun + fill the old albedo read as a big
	# tan/orange expanse on the right of the road, competing with the
	# asphalt. The cooler, less saturated ground reads as scrub
	# verge instead of desert.
	_ground_mat = _std(Color(0.15, 0.14, 0.18), 0.0, 0.95)
	# Round 7 — specular DISABLED on the ground and sand: at the
	# grazing angles the low chase/hero cameras see them at, the
	# default specular (0.5) mirrors the pink-purple sunset sky
	# across the whole plane — that sky mirror was the tan/pink wash
	# on the right-side ground (the cooled albedo alone did not fix
	# it; the wash is a reflection, not the albedo). Matte scrub
	# land has no sky mirror, so the ground now gets its colour from
	# diffuse + ambient only.
	_ground_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_ground = MeshInstance3D.new()
	_ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(226, 300)
	ground_mesh.material = _ground_mat
	_ground.mesh = ground_mesh
	_ground.position = Vector3(107, -0.15, -110)
	# Lane B: ground planes cast no visible shadow — OFF.
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)
	# Warm sand strip between the road's left shoulder and the water.
	# NARROW (8 m, x=-14..-6): the old 16 m strip pushed the waterline
	# so far from the road that the low chase camera saw the sea nearly
	# edge-on as a thin band. A closer shoreline puts the water's near
	# edge inside the frame sooner, so the ocean reads as an expanse.
	# Sand is also darker now — the old pale sand blew out peach in the
	# sun and washed the whole left side of the frame.
	_sand_mat = _std(Color(0.20, 0.16, 0.14), 0.0, 0.9)
	_sand_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_sand = MeshInstance3D.new()
	_sand.name = "Sand"
	var sand_mesh := PlaneMesh.new()
	sand_mesh.size = Vector2(8, 300)
	sand_mesh.material = _sand_mat
	_sand.mesh = sand_mesh
	_sand.position = Vector3(-10, -0.08, -110)
	_sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sand)

func _build_ocean() -> void:
	var water_shader := load("res://shaders/water.gdshader") as Shader
	_ocean_mat = ShaderMaterial.new()
	_ocean_mat.shader = water_shader
	_ocean_mat.set_shader_parameter("deep_color", Color(0.04, 0.22, 0.55))
	_ocean_mat.set_shader_parameter("shallow_color", Color(0.10, 0.42, 0.72))
	_ocean_mat.set_shader_parameter("sunset_color", Color(1.0, 0.45, 0.62))
	_ocean_mat.set_shader_parameter("sky_tint", Color(0.55, 0.25, 0.55))
	# Lane B: sun_direction now matches the true sun direction
	# (-0.23, 0.14, -0.96) — the direction FROM the fragment TO the
	# sun, as water.gdshader uses it (dot(reflect(-view, n),
	# sun_dir)): -X = toward the disc over the ocean, +Y = above
	# the horizon. The old (0.05, 0.28, -0.96) pointed right/up.
	_ocean_mat.set_shader_parameter("sun_direction", Vector3(-0.23, 0.14, -0.96))
	_ocean_mat.set_shader_parameter("wave_height", 0.35)
	_ocean_mat.set_shader_parameter("wave_speed", 1.1)
	_ocean_mat.set_shader_parameter("glitter_strength", 1.6) # Cinematic rebuild (GATE R4): 0.8 -> 1.6 CODE-side — the shader default (2.4) is overwritten, editing it does nothing.
	_ocean = MeshInstance3D.new()
	_ocean.name = "Ocean"
	var ocean_mesh := PlaneMesh.new()
	ocean_mesh.size = Vector2(153, 450)
	ocean_mesh.subdivide_width = 48
	ocean_mesh.subdivide_depth = 96
	ocean_mesh.material = _ocean_mat
	_ocean.mesh = ocean_mesh
	# Ocean spans x=-167..-14 (left of the sand strip at -14..-6) and
	# z=-400..+50: the far edge must sit BEYOND the visual horizon,
	# or a strip of dark sky-ground shows between the sea and the sky
	# as a hard black band at the horizon (seen in the R3 first render).
	# It sits just BELOW the sand top (-0.08) so the shoreline reads as a
	# step down into the water, not a floating plane. Waves fade out
	# toward the shore inside the shader so they never poke through
	# the sand; the shader also draws animated foam at the waterline.
	_ocean.position = Vector3(-90.5, -0.12, -175)
	# Lane B: the ocean is 9,506 tris in the shadow pass and shadows
	# nothing visible — OFF. Subdivision is unchanged (gate cut).
	_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ocean)

func _build_road() -> void:
	var road_shader := load("res://shaders/road.gdshader") as Shader
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = road_shader
	_road_mat.set_shader_parameter("asphalt_color", Color(0.10, 0.10, 0.12))
	_road_mat.set_shader_parameter("line_color", Color(0.92, 0.9, 0.82))
	_road_mat.set_shader_parameter("center_color", Color(0.95, 0.93, 0.86)) # v2.3 GATE §V6: pale warm WHITE (was yellow 0.98,0.78,0.25) — the reel uses white dashes, no yellow centre line. EFFECTIVE site (shader default is overwritten).
	_road_mat.set_shader_parameter("wear_color", Color(0.15, 0.15, 0.17))
	_road_mat.set_shader_parameter("sun_tint", Color(1.0, 0.45, 0.55))
	_road_mat.set_shader_parameter("wetness", 0.35)
	# Cinematic rebuild (GATE R5 Step 2): Asphalt031 maps. Set once here
	# at build; _apply_palette overwrites only asphalt_color/sun_tint/
	# streak/wetness/reflection, so the texture params survive biome
	# changes. (Load probe verified both paths, lane-b/load_probe.gd.)
	_road_mat.set_shader_parameter("asphalt_tex", load("res://assets/asphalt031_color_1024.jpg") as Texture2D)
	_road_mat.set_shader_parameter("asphalt_rough_tex", load("res://assets/asphalt031_rough_512.jpg") as Texture2D)
	# Shoulders: pale concrete strips flanking the asphalt.
	var shoulder_mat := _std(Color(0.32, 0.3, 0.3), 0.0, 0.9)
	for i in range(SEGMENT_COUNT):
		var z := FAR_Z + float(i) * SEGMENT_LEN + SEGMENT_LEN * 0.5
		var seg := MeshInstance3D.new()
		seg.name = "RoadSeg%d" % i
		var seg_mesh := BoxMesh.new()
		seg_mesh.size = Vector3(ROAD_WIDTH, 0.12, SEGMENT_LEN)
		seg_mesh.material = _road_mat
		seg.mesh = seg_mesh
		seg.position = Vector3(0, -0.06, z)
		# Lane B: road segments + shoulders are flush with the
		# ground and shadow nothing visible — OFF.
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_scroll_root.add_child(seg)
		_road_segments.append(seg)
		for side in [-1, 1]:
			var shoulder := _box(Vector3(1.2, 0.1, SEGMENT_LEN), Vector3(side * 6.6, -0.05, z), shoulder_mat)
			shoulder.name = "Shoulder%d" % i
			shoulder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_scroll_root.add_child(shoulder)
			_road_segments.append(shoulder)

func _build_guardrails() -> void:
	_rail_mat = _std(Color(0.7, 0.72, 0.75), 0.7, 0.45)
	var post_mat := _std(Color(0.25, 0.26, 0.28), 0.6, 0.5)
	# Lane B merge: one MeshInstance (2 surfaces: rail + posts) per
	# segment instead of 10 separate boxes — 12 instances / 24
	# surfaces instead of 120 / 120. Box sizes, positions and
	# materials are exactly the old ones; the Guard%d group nodes
	# (moved by scroll()) are unchanged, and guardrails keep
	# casting shadows.
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.08, 0.28, SEGMENT_LEN)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 0.8, 0.12)
	for i in range(SEGMENT_COUNT):
		var z := FAR_Z + float(i) * SEGMENT_LEN + SEGMENT_LEN * 0.5
		var group := Node3D.new()
		group.name = "Guard%d" % i
		group.position = Vector3(0, 0, z)
		var parts: Array = []
		for side in [-1, 1]:
			parts.append([rail_mesh, Transform3D(Basis(), Vector3(side * 7.4, 0.75, 0)), 0])
			for pz in [-7.5, -2.5, 2.5, 7.5]:
				parts.append([post_mesh, Transform3D(Basis(), Vector3(side * 7.4, 0.4, pz)), 1])
		var merged := MeshInstance3D.new()
		merged.name = "GuardMesh%d" % i
		merged.mesh = _merge_parts(parts, [_rail_mat, post_mat])
		group.add_child(merged)
		_scroll_root.add_child(group)
		_guard_segments.append(group)

func _build_poles() -> void:
	var pole_mat := _std(Color(0.16, 0.17, 0.2), 0.7, 0.45)
	_pole_lamp_mat = StandardMaterial3D.new()
	_pole_lamp_mat.albedo_color = Color(1.0, 0.85, 0.6)
	_pole_lamp_mat.emission_enabled = true
	_pole_lamp_mat.emission = Color(1.0, 0.8, 0.5)
	_pole_lamp_mat.emission_energy_multiplier = 2.5
	# Cinematic rebuild (GATE R3): one shared halo material for the
	# lamp halos below (retinted per biome in _apply_palette).
	_lamp_halo_mat = _halo_material(Color(1.0, 0.95, 0.85, 0.5))
	var pole_count := int(WORLD_SPAN / POLE_SPACING)
	# Lane B merge: one MeshInstance (2 surfaces: pole + lamp) per
	# pole instead of 3 boxes — 6 instances / 12 surfaces instead
	# of 18 / 18. Sizes, positions and materials are exactly the
	# old ones; the Pole%d group nodes (moved by scroll()) are
	# unchanged, and poles keep casting shadows. The old "LampHead"
	# child node is gone (no code referenced it — the lamp is now
	# the second surface of the merged mesh).
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.22, 7.5, 0.22)
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(2.4, 0.18, 0.18)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.7, 0.14, 0.3)
	for i in range(pole_count):
		var z := FAR_Z + float(i) * POLE_SPACING + POLE_SPACING * 0.5
		var side := -1.0 if i % 2 == 0 else 1.0
		var group := Node3D.new()
		group.name = "Pole%d" % i
		group.position = Vector3(0, 0, z)
		var parts: Array = [
			[pole_mesh, Transform3D(Basis(), Vector3(side * 7.0, 3.75, 0)), 0],
			[arm_mesh, Transform3D(Basis(), Vector3(side * 5.9, 7.4, 0)), 0],
			[head_mesh, Transform3D(Basis(), Vector3(side * 4.8, 7.3, 0)), 1],
		]
		var merged := MeshInstance3D.new()
		merged.name = "PoleMesh%d" % i
		merged.mesh = _merge_parts(parts, [pole_mat, _pole_lamp_mat])
		group.add_child(merged)
		# Cinematic rebuild (GATE R3): ONE halo quad (~1.6 m) per pole
		# GROUP, parented to the scrolling Pole%d group at the
		# lamp-head local position — +6 draws. A halo parented to
		# static world (not scrolling) would be a bug.
		var halo := _halo_quad(1.6, _lamp_halo_mat)
		halo.name = "LampHalo%d" % i
		halo.position = Vector3(side * 4.8, 7.3, 0)
		group.add_child(halo)
		_scroll_root.add_child(group)
		_pole_segments.append(group)

func _build_palms() -> void:
	for i in range(PALM_COUNT):
		var palm := _Vehicles.build_palm()
		# Lane B near-palm guarantee: the first three palms are
		# placed in the near field (z -20..-60, one per band) so
		# every run has palms beside the road near the camera.
		# Initial placement ONLY — scroll()/recycling is untouched.
		# Palm 0 is forced to the sand strip (always in frame),
		# palm 1 to the land side, palm 2 takes a random side.
		# Cinematic rebuild (follow-up): initial z capped at
		# PALM_RECYCLE_Z so no palm EVER starts closer than 30 m
		# ahead of the z=20 camera (the boot/countdown frame is
		# static — a palm starting at z=+14 would loom for the
		# whole countdown). Forced near-field palms below are
		# already inside the window.
		var z := _rng.randf_range(FAR_Z, PALM_RECYCLE_Z)
		var side := -1
		if i == 0:
			z = _rng.randf_range(-30.0, -20.0)
			side = 1
		elif i == 1:
			z = _rng.randf_range(-45.0, -30.0)
			side = 0
		elif i == 2:
			z = _rng.randf_range(-60.0, -45.0)
		_place_palm(palm, z, side)
		_scroll_root.add_child(palm)
		_palm_nodes.append(palm)

func _place_palm(palm: Node3D, z: float, force_side: int = -1) -> void:
	# Ocean side gets the taller, wind-bent palms; the land side gets
	# shorter, fuller ones. Keep clear of the road and guardrails.
	# v2.3 GATE §V5: left bias 0.45 -> 0.60 — the reel's palms read
	# mostly LEFT (ocean side, dark silhouettes). Expected split at
	# PALM_COUNT 40: ~24 left / ~16 right. Left-strip crowding is a
	# render check (24 palms over 240 m in a 5 m strip, ~10 m mean
	# spacing). x-bounds UNCHANGED (no palm in sea/road).
	var left := _rng.randf() < 0.60
	# Lane B: initial placement may force a side (1 = sand strip,
	# 0 = land side); recycling calls pass no side and keep the
	# random draw above. The x-bounds below are unchanged, so a
	# forced palm still lands on sand or verge — never in the sea
	# or on the road.
	if force_side == 1:
		left = true
	elif force_side == 0:
		left = false
	var x: float
	if left:
		# Beach strip only: x=-14 is the waterline, so palms must stay
		# on the sand (-13.5..-8.5) or they stand in the sea — and stay
		# clear of the left guardrail at x=-7.4.
		x = -_rng.randf_range(8.5, 13.5)
	else:
		x = _rng.randf_range(9.5, 42.0)
	var s := _rng.randf_range(0.85, 1.5) if left else _rng.randf_range(0.85, 1.35)
	palm.position = Vector3(x, 0, z)
	palm.rotation = Vector3(0, _rng.randf() * TAU, 0)
	palm.scale = Vector3.ONE * s

func _build_verge() -> void:
	# Round 7 — roadside verge detail for the RIGHT (land) side, so
	# the ground between the road and the skyline reads as a planted
	# verge with a city edge, not one empty tan sheet: low scrub
	# bushes (dark olive-grey flattened spheres) scattered x 9.5..28,
	# plus a few low dark city-edge blocks (3-6 m) further out
	# (x 30..55) as the near edge of the skyline city. All nodes live
	# in the scroll root and recycle in scroll() like the palms.
	# Round 8 — bushes get colour/size variation so they read as
	# shrubs, not dark blobs: three olive-green-grey materials (one
	# in three is a lighter sage), varied radius (0.5..1.2 m) and
	# squash (0.40..0.60), and every third bush gets a smaller
	# lighter top puff (a second sphere sitting on the crown, in a
	# pale green-grey) so the silhouette breaks up instead of one
	# smooth dark dome. All still dark enough for a roadside verge
	# at sunset — nothing bright. Top puffs are separate nodes in
	# the same verge list so they recycle in scroll() exactly with
	# their bush (same start z, same dz, same WORLD_SPAN).
	var bush_mats: Array[StandardMaterial3D] = [
		_std(Color(0.20, 0.28, 0.15), 0.0, 0.95),
		_std(Color(0.24, 0.30, 0.18), 0.0, 0.95),
		_std(Color(0.30, 0.38, 0.22), 0.0, 0.95),
	]
	var bush_top_mat := _std(Color(0.36, 0.44, 0.26), 0.0, 0.95)
	var block_mat := _std(Color(0.10, 0.08, 0.13), 0.0, 0.9)
	for i in range(18):
		var bush := MeshInstance3D.new()
		bush.name = "Bush%d" % i
		var br := _rng.randf_range(0.5, 1.2)
		var bm := SphereMesh.new()
		bm.radius = br
		bm.height = br * 2.0
		bm.radial_segments = 8
		bm.rings = 5
		bm.material = bush_mats[i % 3]
		bush.mesh = bm
		var bsquash := _rng.randf_range(0.40, 0.60)
		bush.scale = Vector3(1.0, bsquash, 1.0)
		var bx := _rng.randf_range(9.5, 28.0)
		var bz := FAR_Z + _rng.randf() * WORLD_SPAN
		bush.position = Vector3(bx, 0.15, bz)
		bush.rotation = Vector3(0, _rng.randf() * TAU, 0)
		_scroll_root.add_child(bush)
		_verge_nodes.append(bush)
		if i % 3 == 0:
			var top := MeshInstance3D.new()
			top.name = "BushTop%d" % i
			var tm := SphereMesh.new()
			tm.radius = br * 0.55
			tm.height = br * 1.1
			tm.radial_segments = 8
			tm.rings = 5
			tm.material = bush_top_mat
			top.mesh = tm
			top.scale = Vector3(1.0, 0.55, 1.0)
			top.position = Vector3(bx + _rng.randf_range(-0.3, 0.3), 0.15 + br * bsquash * 0.75, bz)
			top.rotation = Vector3(0, _rng.randf() * TAU, 0)
			_scroll_root.add_child(top)
			_verge_nodes.append(top)
	for i in range(4):
		var bh := _rng.randf_range(3.0, 6.0)
		var block := _box(Vector3(_rng.randf_range(5.0, 9.0), bh, _rng.randf_range(5.0, 8.0)), Vector3(_rng.randf_range(30.0, 55.0), bh * 0.5 - 0.5, FAR_Z + _rng.randf() * WORLD_SPAN), block_mat)
		block.name = "VergeBlock%d" % i
		_scroll_root.add_child(block)
		_verge_nodes.append(block)
	# v2.3 GATE §V5: 12 low undergrowth tufts (scrub clumps, flattened
	# spheres on the verge-bush pattern — 1 draw each, within the V12
	# +12 cap; NOT alpha quads: no new alpha texture, no banding risk).
	# Sides: 6 on the LEFT sand strip (x -13..-8.5, at palm bases,
	# clear of the -7.4 guardrail and the -14 waterline) + 6 on the
	# RIGHT verge (x 8.5..20). Placement + recycle = the verge
	# mechanism exactly: scroll-root children appended to
	# _verge_nodes, recycled in scroll() (z > RECYCLE_Z -= WORLD_SPAN).
	var tuft_mats: Array[StandardMaterial3D] = [
		_std(Color(0.16, 0.24, 0.12), 0.0, 0.95),
		_std(Color(0.22, 0.30, 0.16), 0.0, 0.95),
	]
	for i in range(12):
		var tuft := MeshInstance3D.new()
		tuft.name = "Tuft%d" % i
		var tr := _rng.randf_range(0.3, 0.6)
		var tm := SphereMesh.new()
		tm.radius = tr
		tm.height = tr * 2.0
		tm.radial_segments = 8
		tm.rings = 4
		tm.material = tuft_mats[i % 2]
		tuft.mesh = tm
		tuft.scale = Vector3(1.0, _rng.randf_range(0.35, 0.5), 1.0)
		var tx := _rng.randf_range(-13.0, -8.5) if i < 6 else _rng.randf_range(8.5, 20.0)
		tuft.position = Vector3(tx, 0.1, FAR_Z + _rng.randf() * WORLD_SPAN)
		tuft.rotation = Vector3(0, _rng.randf() * TAU, 0)
		_scroll_root.add_child(tuft)
		_verge_nodes.append(tuft)

func _build_skyline() -> void:
	# A city at dusk: dark silhouettes, far away, windows that vary —
	# and ONLY on the land side (x >= -15), so the horizon over the
	# ocean stays open water and sky. Depth is staggered (z -270..-234)
	# so the towers overlap instead of lining up like a flat wall.
	_skyline = Node3D.new()
	_skyline.name = "Skyline"
	add_child(_skyline)
	_skyline_mat = _std(Color(0.08, 0.06, 0.15), 0.0, 0.9)
	_window_mat = StandardMaterial3D.new()
	_window_mat.albedo_color = Color(1.0, 0.75, 0.4)
	_window_mat.emission_enabled = true
	_window_mat.emission = Color(1.0, 0.7, 0.35)
	_window_mat.emission_energy_multiplier = 0.5
	# Most windows at dusk are DARK — a tower of all-lit windows reads
	# as a billboard. Dark windows give the lit ones something to be.
	_window_dark_mat = _std(Color(0.05, 0.05, 0.09), 0.0, 0.9)
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1.0, 0.1, 0.1)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.05, 0.05)
	_beacon_mat.emission_energy_multiplier = 2.0
	var x := -15.0
	var tower_i := 0
	while x < 95.0:
		var w := _rng.randf_range(8.0, 16.0)
		# v2.3 §V8: heights 9-24 -> 8-27 m (wider RNG spread = more
		# varied roofline; landmarks unchanged 34-42 m). Silhouette
		# albedo stays (0.08,0.06,0.15) near-black — NO darkening
		# (stated decision: already near-black; the melt comes from
		# fog/ribbon, not a darker albedo).
		var h := _rng.randf_range(8.0, 27.0)
		var d := _rng.randf_range(8.0, 12.0)
		var tz := -252.0 + _rng.randf_range(-18.0, 18.0)
		# Two landmark towers — clearly taller, stepped tops — so the
		# skyline has a shape instead of a flat roofline.
		var landmark := tower_i == 3 or tower_i == 8
		if landmark:
			h = _rng.randf_range(34.0, 42.0)
		var tower := _box(Vector3(w, h, d), Vector3(x + w * 0.5, h * 0.5 - 1.0, tz), _skyline_mat)
		_skyline.add_child(tower)
		if landmark:
			# Stepped crown: a smaller box on top, plus a red beacon.
			_skyline.add_child(_box(Vector3(w * 0.55, 3.5, d * 0.55), Vector3(x + w * 0.5, h + 1.75 - 1.0, tz), _skyline_mat))
			_skyline.add_child(_box(Vector3(0.5, 0.5, 0.5), Vector3(x + w * 0.5, h + 3.75 - 1.0, tz), _beacon_mat))
		# Window clusters at several floors: 3-5 small panes per tower
		# (v2.3 §V8: was 2-4; +1/tower ≈ +8 draws, within the V12 +24
		# cap), each randomly lit or dark, at random heights and x
		# offsets. Lit probability 0.70 (was 0.55) — MORE lit windows,
		# emissive warm, at zero extra draw cost per lit pane.
		var clusters := _rng.randi_range(3, 5)
		for c in range(clusters):
			var cw := w * _rng.randf_range(0.12, 0.22)
			var cy := _rng.randf_range(2.0, h - 2.0)
			var cx := x + w * 0.5 + _rng.randf_range(-w * 0.3, w * 0.3)
			var lit := _rng.randf() < 0.70
			var wm := _window_mat if lit else _window_dark_mat
			_skyline.add_child(_box(Vector3(cw, 0.55, 0.12), Vector3(cx, cy, tz + d * 0.5 + 0.07), wm))
		# Rooftop details: AC boxes (dark silhouette bumps) and, on
		# some towers, a thin antenna with a red tip.
		var ac_count := _rng.randi_range(0, 3)
		for a in range(ac_count):
			_skyline.add_child(_box(Vector3(0.9, 0.5, 0.9), Vector3(x + _rng.randf_range(1.5, w - 1.5), h + 0.25 - 1.0, tz + _rng.randf_range(-d * 0.3, d * 0.3)), _skyline_mat))
		if _rng.randf() < 0.35:
			var ah := _rng.randf_range(3.0, 6.0)
			_skyline.add_child(_box(Vector3(0.12, ah, 0.12), Vector3(x + w * 0.5, h + ah * 0.5 - 1.0, tz), _skyline_mat))
			_skyline.add_child(_box(Vector3(0.3, 0.3, 0.3), Vector3(x + w * 0.5, h + ah - 1.0, tz), _beacon_mat))
		# Rooftop beacon only on the tallest non-landmark towers.
		elif h > 20.0:
			_skyline.add_child(_box(Vector3(0.6, 1.0, 0.6), Vector3(x + w * 0.5, h + 0.5 - 1.0, tz), _window_mat))
		x += w + _rng.randf_range(2.0, 9.0)
		tower_i += 1
	# Lane B: the skyline sits 200+ m away, beyond the 80 m shadow
	# range, and its silhouette shadows nothing visible — every
	# tower / window / beacon / rooftop box stops casting.
	for child in _skyline.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_clouds() -> void:
	# Three depth layers (far/low near the horizon, mid, near/high),
	# warm pink-orange tint on the sun (left) side, cool purple-grey
	# on the far (right) side, and per-cloud size/opacity variety —
	# no more identical pale blobs in a single row.
	var warm := StandardMaterial3D.new()
	warm.albedo_color = Color(0.98, 0.62, 0.60, 0.75)
	warm.emission_enabled = true
	warm.emission = Color(1.0, 0.45, 0.50)
	warm.emission_energy_multiplier = 0.3
	warm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mid := StandardMaterial3D.new()
	mid.albedo_color = Color(0.88, 0.55, 0.66, 0.65)
	mid.emission_enabled = true
	mid.emission = Color(1.0, 0.45, 0.55)
	mid.emission_energy_multiplier = 0.22
	mid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mid.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cool := StandardMaterial3D.new()
	cool.albedo_color = Color(0.60, 0.48, 0.68, 0.55)
	cool.emission_enabled = true
	cool.emission = Color(0.5, 0.35, 0.62)
	cool.emission_energy_multiplier = 0.15
	cool.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cool.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cool.cull_mode = BaseMaterial3D.CULL_DISABLED
	var layer_z := [-235.0, -180.0, -120.0]
	for i in range(CLOUD_COUNT):
		var layer := i % 3
		var px := _rng.randf_range(-120.0, 120.0)
		var base: StandardMaterial3D = warm
		if px > 40.0:
			base = cool
		elif px > -20.0:
			base = mid
		# Each cloud gets its own material copy so opacity can vary.
		var mat := base.duplicate() as StandardMaterial3D
		mat.albedo_color.a = _rng.randf_range(0.35, 0.9)
		var cloud := Node3D.new()
		cloud.name = "Cloud%d" % i
		# Lane B merge: the lit puffs and the underside puffs are
		# baked into ONE ArrayMesh with 2 surfaces (lit + under)
		# instead of one MeshInstance per puff — 14 instances / 28
		# surfaces instead of ~102 / ~102. Puff counts, radii,
		# positions and squashes are drawn in exactly the old order
		# with the old parameters, so each cloud keeps its shape;
		# only the node-per-puff overhead is gone. Clouds never
		# cast shadows.
		var lit_parts: Array = []
		var puffs := 3 + _rng.randi_range(0, 3)
		var size_boost := 1.0 + float(layer) * 0.3
		for p in range(puffs):
			var puff_mesh := SphereMesh.new()
			puff_mesh.radius = _rng.randf_range(4.0, 9.0) * size_boost
			puff_mesh.height = puff_mesh.radius * 1.1
			puff_mesh.radial_segments = 10
			puff_mesh.rings = 6
			# Vertical squash VARIES per puff (0.35..0.6) and puffs sit
			# at different heights (-1.5..+2.2) so the cloud has a
			# domed top instead of one flat row of identical ellipses.
			var puff_pos := Vector3(float(p) * _rng.randf_range(5.0, 8.0) - 8.0, _rng.randf_range(-1.5, 2.2), _rng.randf_range(-2.0, 2.0))
			var puff_scale := Vector3(1.6, _rng.randf_range(0.35, 0.6), 1.0)
			lit_parts.append([puff_mesh, Transform3D(Basis.from_scale(puff_scale), puff_pos), 0])
		# Round 4 — dark purple-grey UNDERSIDE: a second, lower layer
		# of smaller puffs hanging under the lit top, so each cloud
		# reads as a volume with a shadowed belly instead of a flat
		# paper cutout. Same horizontal spread, ~2 m lower, darker
		# and slightly more transparent than the lit layer.
		var under_mat := base.duplicate() as StandardMaterial3D
		under_mat.albedo_color = Color(0.42, 0.30, 0.52, _rng.randf_range(0.4, 0.6))
		under_mat.emission = Color(0.30, 0.20, 0.42)
		under_mat.emission_energy_multiplier = 0.12
		var under_parts: Array = []
		var under_puffs := 2 + _rng.randi_range(0, 2)
		for u in range(under_puffs):
			var up_mesh := SphereMesh.new()
			up_mesh.radius = _rng.randf_range(3.0, 6.5) * size_boost
			up_mesh.height = up_mesh.radius * 1.1
			up_mesh.radial_segments = 10
			up_mesh.rings = 6
			var up_pos := Vector3(float(u) * _rng.randf_range(5.0, 8.0) - 6.0, _rng.randf_range(-3.2, -1.8), _rng.randf_range(-1.5, 1.5))
			var up_scale := Vector3(1.6, _rng.randf_range(0.3, 0.45), 1.0)
			under_parts.append([up_mesh, Transform3D(Basis.from_scale(up_scale), up_pos), 1])
		var parts: Array = []
		parts.append_array(lit_parts)
		parts.append_array(under_parts)
		var merged := MeshInstance3D.new()
		merged.name = "CloudMesh%d" % i
		merged.mesh = _merge_parts(parts, [mat, under_mat])
		merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.add_child(merged)
		# Far layer hugs the horizon, near layer rides higher — the
		# perspective reads as real depth instead of one flat row.
		cloud.position = Vector3(px, 28.0 + float(layer) * 6.0 + _rng.randf_range(0.0, 10.0), layer_z[layer] + _rng.randf_range(-12.0, 12.0))
		cloud.set_meta("drift", _rng.randf_range(0.4, 1.4))
		add_child(cloud)
		_clouds.append(cloud)

func _build_stars() -> void:
	# Spec-gap pass — SPEC §2.5: the TEST SITE night is "dark,
	# starry". A single static ArrayMesh of small unshaded quads far
	# ahead in the upper sky: one draw call, no textures, no shaders,
	# nothing to scroll or recycle (this node is NOT in the scroll
	# root — the stars hang fixed in the sky like the sun disc and
	# the skyline). Visibility is neon-only, set in _apply_palette,
	# so every other biome renders pixel-identical to before.
	# Fog is DISABLED on the material: at ~250 m even the thin neon
	# fog would wash the points out toward the fog colour (the same
	# reason the sun disc shader is fog_disabled). Unshaded + vertex
	# colours carry the varied brightness; with glow OFF the
	# brightest points render as hard points (no bloom) and the
	# brightness variation still reads as glare.
	# Sizes: at ~250 m the chase camera resolves ~4.6 px/m at 720p,
	# so 0.36..1.0 m quads read as 2..5 px points — stars, not
	# noise. A few larger bright stars anchor the field. Low stars
	# (near the magenta horizon glow) are thinned and dimmed: stars
	# belong in the dark upper sky, not sitting on the horizon.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var star_count := 170
	for i in range(star_count + 8):
		var bright_star := i >= star_count
		var x := _rng.randf_range(-125.0, 125.0)
		var y := _rng.randf_range(24.0, 150.0)
		if y < 48.0 and _rng.randf() > 0.35:
			y = _rng.randf_range(48.0, 150.0)
		var z := _rng.randf_range(-265.0, -245.0)
		var alt_factor: float = clampf((y - 20.0) / 55.0, 0.3, 1.0)
		var brightness := (0.45 + 0.55 * _rng.randf()) * alt_factor
		var h := 0.18 + 0.32 * _rng.randf()
		if bright_star:
			brightness = 1.0
			h = _rng.randf_range(0.55, 0.70)
		var tint := Color(1.0, 1.0, 1.0)
		var tint_roll := _rng.randf()
		if tint_roll < 0.25:
			tint = Color(0.78, 0.86, 1.0)
		elif tint_roll > 0.85:
			tint = Color(1.0, 0.88, 0.70)
		var c := Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, 1.0)
		# One in five stars is a diamond (quad rotated 45 degrees in
		# the sky plane) — the mix of squares and diamonds reads as
		# sparkle instead of a grid of identical pixels.
		var diamond := _rng.randf() < 0.2
		var base := verts.size()
		if diamond:
			verts.append(Vector3(x, y - h * 1.3, z))
			verts.append(Vector3(x + h * 1.3, y, z))
			verts.append(Vector3(x, y + h * 1.3, z))
			verts.append(Vector3(x - h * 1.3, y, z))
		else:
			verts.append(Vector3(x - h, y - h, z))
			verts.append(Vector3(x + h, y - h, z))
			verts.append(Vector3(x + h, y + h, z))
			verts.append(Vector3(x - h, y + h, z))
		for k in range(4):
			normals.append(Vector3(0.0, 0.0, 1.0))
			colors.append(c)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var star_mesh := ArrayMesh.new()
	star_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.vertex_color_use_as_albedo = true
	star_mat.albedo_color = Color(1.0, 1.0, 1.0)
	star_mat.disable_fog = true
	star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	star_mesh.surface_set_material(0, star_mat)
	_stars = MeshInstance3D.new()
	_stars.name = "Stars"
	_stars.mesh = star_mesh
	_stars.visible = false
	# Lane B: star quads hang in the sky and shadow nothing — OFF.
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stars)

func _build_shafts() -> void:
	# Fake god rays: tall translucent planes fanning down from the sun's
	# direction across the road. Additive, unshaded, very low alpha —
	# they read as light in the air, not as geometry.
	_shaft_mat = StandardMaterial3D.new()
	_shaft_mat.albedo_color = Color(1.0, 0.6, 0.4, 0.05)
	_shaft_mat.emission_enabled = true
	_shaft_mat.emission = Color(1.0, 0.55, 0.35)
	_shaft_mat.emission_energy_multiplier = 0.5
	_shaft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shaft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shaft_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in range(4):
		var shaft := MeshInstance3D.new()
		shaft.name = "Shaft%d" % i
		var shaft_mesh := PlaneMesh.new()
		shaft_mesh.size = Vector2(7.0 + float(i) * 2.0, 55.0)
		# Each shaft gets its OWN copy of the material: scroll() breathes
		# each one's alpha on a different phase, which would fight if
		# all four shared a single material.
		shaft_mesh.material = _shaft_mat.duplicate() as StandardMaterial3D
		shaft.mesh = shaft_mesh
		shaft.position = Vector3(-32.0 + float(i) * 9.0, 16.0, -120.0 - float(i) * 18.0)
		# Lane B: translucent light shafts shadow nothing — OFF.
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shaft.rotation_degrees = Vector3(8, 28, 24)
		shaft.set_meta("phase", float(i) * 1.7)
		add_child(shaft)
		_shafts.append(shaft)

func _build_haze() -> void:
	var haze_shader := load("res://shaders/haze.gdshader") as Shader
	_haze_mat = ShaderMaterial.new()
	_haze_mat.shader = haze_shader
	_haze_mat.set_shader_parameter("haze_color", Color(0.95, 0.50, 0.42))
	_haze_mat.set_shader_parameter("strength", 0.05)
	_haze_plane = MeshInstance3D.new()
	_haze_plane.name = "HeatHaze"
	var haze_mesh := PlaneMesh.new()
	haze_mesh.size = Vector2(13.0, 90.0)
	haze_mesh.material = _haze_mat
	_haze_plane.mesh = haze_mesh
	_haze_plane.position = Vector3(0, 0.6, -45)
	# Lane B: haze planes shadow nothing — OFF.
	_haze_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_haze_plane)
	# Distant haze band: a wide translucent ribbon hugging the horizon
	# so the skyline melts into the sunset instead of ending in a hard
	# cut. Cinematic rebuild (GATE R9): z -248 -> -226 (clears the
	# skyline front faces at ~-228), alpha 0.18 -> 0.25, peach
	# (1.0,0.62,0.52) albedo + emission. Coverage caveat: the ribbon
	# spans y -1..11 m while landmark towers reach 34-42 m — upper
	# towers rely on fog alone; "all towers melt" is NOT promised.
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(1.0, 0.62, 0.52, 0.25)
	band_mat.emission_enabled = true
	band_mat.emission = Color(1.0, 0.62, 0.52)
	band_mat.emission_energy_multiplier = 0.3
	band_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var band := MeshInstance3D.new()
	band.name = "HorizonHaze"
	var band_mesh := PlaneMesh.new()
	band_mesh.size = Vector2(340, 12)
	band_mesh.material = band_mat
	band.mesh = band_mesh
	# PlaneMesh is HORIZONTAL (XZ, +Y normal): unrotated, this "ribbon"
	# was a foreshortened 1-2 px sliver at y=5, not the vertical haze
	# band the GATE/spec assumes (y -1..11 m) — proven by the
	# pixel-identical horizon band before/after the z move. Rotate
	# +90 deg about X so the 12 m dimension stands vertical (normal
	# +Z, facing the camera) and the band spans y -1..11 m at z=-226,
	# in front of the skyline front faces (~-228). Render-gated.
	band.position = Vector3(0, 5, -226)
	band.rotation_degrees = Vector3(90, 0, 0)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(band)

# ---------------------------------------------------------------- runtime

func scroll(delta: float, speed_mps: float) -> void:
	_ensure_built()
	var dz := speed_mps * delta
	# Hot loop: move existing nodes only, no allocation, no lookups.
	for seg in _road_segments:
		seg.position.z += dz
		if seg.position.z > RECYCLE_Z + SEGMENT_LEN * 0.5:
			seg.position.z -= WORLD_SPAN
	for guard in _guard_segments:
		guard.position.z += dz
		if guard.position.z > RECYCLE_Z + SEGMENT_LEN * 0.5:
			guard.position.z -= WORLD_SPAN
	for pole in _pole_segments:
		pole.position.z += dz
		if pole.position.z > POLE_RECYCLE_Z:
			pole.position.z -= WORLD_SPAN
	for palm in _palm_nodes:
		palm.position.z += dz
		if palm.position.z > PALM_RECYCLE_Z:
			_place_palm(palm, palm.position.z - WORLD_SPAN)
	for verge in _verge_nodes:
		verge.position.z += dz
		if verge.position.z > RECYCLE_Z:
			verge.position.z -= WORLD_SPAN
	# Clouds drift sideways, slowly, and wrap.
	for cloud in _clouds:
		cloud.position.x += float(cloud.get_meta("drift")) * delta
		if cloud.position.x > 130.0:
			cloud.position.x = -130.0
	# God-ray shafts breathe almost imperceptibly.
	for shaft in _shafts:
		var phase := float(shaft.get_meta("phase"))
		var a := 0.04 + 0.02 * sin(Time.get_ticks_msec() * 0.0004 + phase)
		(shaft.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a = a

func set_biome(biome: String) -> void:
	_ensure_built()
	if not get_biome_palette(biome).is_empty():
		_biome = biome
		_palette = get_biome_palette(biome)
		_apply_palette()

func _apply_palette() -> void:
	var p := _palette
	# The star field is neon-only (SPEC §2.5 calls the neon night
	# "dark, starry"). Hidden in every other biome, so those skies
	# render exactly as before; the node is never in the scroll
	# root, so world recycling cannot move or duplicate the stars.
	# (The TEST SITE intro no longer forces neon — Lane C decouples
	# it — but the stars stay tied to the neon biome itself.)
	_stars.visible = _biome == "neon"
	_sky_mat.sky_top_color = p["sky_top"]
	_sky_mat.sky_horizon_color = p["sky_horizon"]
	_sky_mat.ground_bottom_color = p["ground_bottom"]
	_sky_mat.ground_horizon_color = p["ground_horizon"]
	_sun.light_color = p["sun_color"]
	_sun.light_energy = float(p["sun_energy"])
	_fill.light_color = p["fill_color"]
	_fill.light_energy = float(p["fill_energy"])
	# The sun disc follows the biome's sun: near-white on the coast,
	# pink in neon, pale in the desert, white in the snow.
	_sun_disc_mat.set_shader_parameter("disc_color", p["sun_color"] if _biome != "coastal" else Color(1.0, 0.85, 0.70))
	# Lane B glow-OFF compensation: disc energy is per-biome HERE
	# (this runs on every biome change and overwrites the
	# build-time default): coastal 3.0 (cinematic rebuild, was 2.5),
	# neon 1.2, desert/canyon 2.0, snow 1.5, rain 1.0.
	var disc_energy := 3.0
	match _biome:
		"neon":
			disc_energy = 1.2
		"desert", "canyon":
			disc_energy = 2.0
		"snow":
			disc_energy = 1.5
		"rain":
			disc_energy = 1.0
	_sun_disc_mat.set_shader_parameter("energy", disc_energy)
	# Halo tints per biome (GATE R3/R9 — Lane B decision, recorded):
	# the radial texture is warm, so tints multiply toward each
	# biome's sun. Coastal warm peach (texture as-is); neon pink
	# (matches the pink disc) + cool lamp halos; snow muted white;
	# rain muted + dimmer; canyon/desert warm. The ribbon keeps its
	# peach in all biomes this pass (decision: no palette keys may
	# change; all-6 renders are the check — see REPORT.md).
	var sun_tint := Color(1.0, 1.0, 1.0)
	var sun_alpha := 0.75
	var sun2_alpha := 0.28
	var streak_alpha := 0.22
	var lamp_tint := Color(1.0, 0.95, 0.85, 0.5)
	match _biome:
		"neon":
			sun_tint = Color(1.0, 0.75, 0.95)
			lamp_tint = Color(0.75, 0.85, 1.0, 0.5)
		"snow":
			sun_tint = Color(0.9, 0.92, 1.0)
			lamp_tint = Color(0.9, 0.92, 1.0, 0.4)
		"rain":
			sun_tint = Color(1.0, 0.85, 0.8)
			sun_alpha = 0.45
			sun2_alpha = 0.16
			streak_alpha = 0.12
			lamp_tint = Color(1.0, 0.9, 0.85, 0.35)
		"canyon":
			sun_tint = Color(1.0, 0.9, 0.75)
		"desert":
			sun_tint = Color(1.0, 0.95, 0.85)
	_sun_halo_mat.albedo_color = Color(sun_tint.r, sun_tint.g, sun_tint.b, sun_alpha)
	_sun_halo2_mat.albedo_color = Color(sun_tint.r, sun_tint.g, sun_tint.b, sun2_alpha)
	_sun_streak_mat.albedo_color = Color(sun_tint.r, sun_tint.g, sun_tint.b, streak_alpha)
	_lamp_halo_mat.albedo_color = lamp_tint
	_environment.ambient_light_color = p["ambient_color"]
	_environment.fog_light_color = p["fog_color"]
	_environment.fog_density = float(p["fog_density"])
	_ocean_mat.set_shader_parameter("deep_color", p["ocean_color"])
	_ocean_mat.set_shader_parameter("sunset_color", p["haze_color"])
	_road_mat.set_shader_parameter("asphalt_color", p["road_color"])
	_road_mat.set_shader_parameter("sun_tint", p["haze_color"])
	_haze_mat.set_shader_parameter("haze_color", p["haze_color"])
	# Lane B glow-OFF compensation: window emission is raised per
	# biome in the match below (neon 5.0, snow 1.2, coastal/rain
	# 0.6); canyon/desert leave it unset as before (skyline hidden).
	# Prop sets per biome — ocean only where there is a sea, palms only
	# where trees grow, skyline only where a city makes sense.
	match _biome:
		"coastal":
			_ocean.visible = true
			_skyline.visible = true
			_sand.visible = true
			# Round 7 — coastal ground cooled (0.15,0.14,0.18, was
			# 0.22,0.17,0.19): the old warm albedo read as a big tan
			# expanse on the right of the road under the sunset sun.
			_ground_mat.albedo_color = Color(0.15, 0.14, 0.18)
			for palm in _palm_nodes:
				palm.visible = true
			_window_mat.emission_energy_multiplier = 0.6
			# Round 7 — additive sun streak: full warm sunset path.
			_road_mat.set_shader_parameter("streak_strength", 1.0)
			_road_mat.set_shader_parameter("streak_color", Color(1.0, 0.45, 0.18))
		"rain":
			_ocean.visible = true
			_skyline.visible = true
			_sand.visible = true
			_ground_mat.albedo_color = Color(0.22, 0.17, 0.19)
			for palm in _palm_nodes:
				palm.visible = true
			_window_mat.emission_energy_multiplier = 0.6
			# Rain: a dimmer, pinker streak — the wet night road
			# still catches the sunset, but a full warm path would
			# bring back the pink left-lane wash Round 6 killed.
			_road_mat.set_shader_parameter("streak_strength", 0.5)
			_road_mat.set_shader_parameter("streak_color", Color(1.0, 0.55, 0.45))
		"neon":
			_ocean.visible = false
			_skyline.visible = true
			_sand.visible = false
			_ground_mat.albedo_color = Color(0.22, 0.17, 0.19)
			for palm in _palm_nodes:
				palm.visible = true
			_window_mat.emission_energy_multiplier = 5.0
			_road_mat.set_shader_parameter("streak_strength", 0.6)
			_road_mat.set_shader_parameter("streak_color", Color(1.0, 0.4, 0.8))
		"canyon", "desert":
			_ocean.visible = false
			_skyline.visible = false
			_sand.visible = true
			for palm in _palm_nodes:
				palm.visible = true
			_ground_mat.albedo_color = Color(0.45, 0.3, 0.15) if _biome == "desert" else Color(0.3, 0.16, 0.1)
			_road_mat.set_shader_parameter("streak_strength", 0.8)
			_road_mat.set_shader_parameter("streak_color", Color(1.0, 0.6, 0.3) if _biome == "canyon" else Color(1.0, 0.75, 0.5))
		"snow":
			_ocean.visible = true
			_skyline.visible = true
			_sand.visible = false
			for palm in _palm_nodes:
				palm.visible = false
			_ground_mat.albedo_color = Color(0.8, 0.82, 0.88)
			_window_mat.emission_energy_multiplier = 1.2
			# Snow: a faint WHITE streak only — the sun is white
			# here, so a warm orange path would read as dirt.
			_road_mat.set_shader_parameter("streak_strength", 0.3)
			_road_mat.set_shader_parameter("streak_color", Color(0.95, 0.92, 0.9))
		_:
			_ocean.visible = true
			_skyline.visible = true
			_sand.visible = true
			for palm in _palm_nodes:
				palm.visible = true
			_road_mat.set_shader_parameter("streak_strength", 1.0)
			_road_mat.set_shader_parameter("streak_color", Color(1.0, 0.45, 0.18))
	# Wet road everywhere except the dry desert; rain is the wettest
	# (0.85 — Round 6 lowered it from 0.95 to dim the pink sky
	# mirror on the left lane; see the reflection_scale note below).
	if _biome == "desert":
		_road_mat.set_shader_parameter("wetness", 0.15)
	elif _biome == "rain":
		_road_mat.set_shader_parameter("wetness", 0.85)
	elif _biome == "snow":
		_road_mat.set_shader_parameter("wetness", 0.4)
	elif _biome == "coastal":
		# v2.3 §V6 stage 2: coastal 0.35 -> 0.45 — stronger wet-band
		# GGX for the reel's wet reflective road (r_034). Render-gated;
		# falsifier = plastic/glossy road -> step back to 0.35.
		_road_mat.set_shader_parameter("wetness", 0.45)
	else:
		_road_mat.set_shader_parameter("wetness", 0.35)
	# Round 5 — rain's wet road mirrored the pink sky hardest on the
	# left lane (left lane measured 244,144,145 at wetness 0.95).
	# Cut the road's specular reflection there; the wet sheen still
	# reads from the roughness contrast between the wet band and the
	# dry asphalt. Every other biome keeps the full reflection.
	# Round 6 — 0.25 was not enough (left lane still 170,72,83):
	# reflection_scale 0.25 -> 0.20, so the pink sky mirror dims
	# while the moody wet sheen stays. (0.10 was tried first and
	# made the road black; 0.20 + the lighter rain albedo keeps
	# the sheen readable.)
	if _biome == "rain":
		_road_mat.set_shader_parameter("reflection_scale", 0.20)
	else:
		_road_mat.set_shader_parameter("reflection_scale", 1.0)
