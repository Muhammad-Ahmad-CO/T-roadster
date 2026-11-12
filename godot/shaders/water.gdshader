shader_type spatial;
render_mode specular_disabled, cull_back, depth_draw_opaque;

// Animated sunset ocean. Vertex waves + analytic normals, deep blue
// water with a pink sun-glitter path toward the sun. Specular is
// DISABLED on purpose: at grazing angles a mirror-bright water just
// reflects the pink sky. Cinematic rebuild (GATE R4): the v2.1.0
// "water must stay blue" rule is SUPERSEDED for coastal — the reel
// water is mauve-pink everywhere, so the fresnel sunset/sky mixes,
// the glitter and the horizon term now push toward sunset_color and a
// far haze ramp melts distant water into the haze. Other biomes keep
// their palette ocean colours via _apply_palette (unchanged wiring).

uniform vec4 deep_color : source_color = vec4(0.04, 0.16, 0.42, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.10, 0.34, 0.60, 1.0);
uniform vec4 sunset_color : source_color = vec4(1.0, 0.45, 0.62, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.55, 0.25, 0.55, 1.0);
uniform vec3 sun_direction = vec3(0.05, 0.10, -0.99);
uniform float wave_height = 0.35;
uniform float wave_speed = 1.1;
uniform float glitter_strength = 2.4;
uniform float glitter_sharpness = 70.0; // Cinematic rebuild (GATE R4): 120 -> 70, broader glint corridor. NOTE: glitter_strength above is OVERWRITTEN by world_builder.gd:_build_ocean (1.6) — editing the default does nothing.

varying vec3 v_local;
varying float v_wave;
// Round 7 — world position of the fragment, so the glitter can fade
// with distance from the camera (the hero close-up's sea is NEAR
// water, 15-40 m away, and at that range the glitter path fills the
// frame; the chase frame's visible sea is FAR water, 90+ m away).
varying vec3 v_world;

float wave_h(vec2 p, float t) {
	float h = 0.0;
	h += sin(p.x * 0.32 + t * 1.0) * 0.55;
	h += sin(p.y * 0.27 - t * 0.75) * 0.45;
	h += sin((p.x + p.y) * 0.14 + t * 0.5) * 0.65;
	h += sin(p.x * 0.9 - t * 1.6) * 0.18;
	return h;
}

void vertex() {
	vec2 p = VERTEX.xz;
	float t = TIME * wave_speed;
	float h = wave_h(p, t);
	// Waves die out toward the shore (local x = +76.5 is the waterline
	// at world x=-14) so no wave crest ever pokes through the sand.
	float shore_fade = 1.0 - smoothstep(52.0, 76.5, p.x);
	h *= shore_fade;
	VERTEX.y += h * wave_height;
	v_wave = h;
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Analytic normal from the wave field (cheap, no texture lookups).
	// Written to NORMAL here so Godot transforms it to view space.
	float e = 0.6;
	float hx = wave_h(p + vec2(e, 0.0), t) - wave_h(p - vec2(e, 0.0), t);
	float hz = wave_h(p + vec2(0.0, e), t) - wave_h(p - vec2(0.0, e), t);
	NORMAL = normalize(vec3(-hx * wave_height / (2.0 * e), 1.0, -hz * wave_height / (2.0 * e)));
}

void fragment() {
	// NORMAL arrives in view space, matching VIEW.
	vec3 n = normalize(NORMAL);
	vec3 view = normalize(VIEW);
	float fresnel = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 3.0);

	// Base water: deep colour in troughs, lighter on crests.
	vec3 water = mix(deep_color.rgb, shallow_color.rgb, clamp(v_wave * 0.5 + 0.5, 0.0, 1.0));
	// Sunset reflection at grazing angles. Cinematic rebuild (GATE
	// R4): the v2.1.0 caps (0.10 / 0.05, "stay blue") are superseded
	// for coastal — 0.45 / 0.30, so the low-angle sea reads mauve-pink
	// like the reel instead of staying blue.
	vec3 col = mix(water, sunset_color.rgb, fresnel * 0.45);
	col = mix(col, sky_tint.rgb, fresnel * 0.30);

	// Far haze ramp (GATE R4): a SEPARATE smoothstep — 0 inside
	// ~30 m, full haze past ~150 m. The wording "reuse near_fade
	// inverted" is WRONG and FORBIDDEN: near_fade is already
	// 0-near/1-far, so literal inversion would pink near water and
	// leave far water blue. near_fade's range (20-120 m) is FROZEN.
	// The ramp runs BEFORE the glitter so the glint path still adds
	// brightening on top of the hazed far water. Falsifier: mid-water
	// (40-80 m) white-pink sheet -> push the ramp to 60-180 m.
	float far_haze = smoothstep(30.0, 150.0, distance(v_world, CAMERA_POSITION_WORLD));
	col = mix(col, sunset_color.rgb, far_haze);

	// Sun glitter: tight specular toward the sun + a shimmering path.
	vec3 sun_dir = normalize(sun_direction);
	vec3 refl = reflect(-view, n);
	float glitter = pow(clamp(dot(refl, sun_dir), 0.0, 1.0), glitter_sharpness) * glitter_strength;
	// The sun sits at world (-54, -233) = local (36.5, -123); the
	// path's centre line runs from the near shore (local x=66.5 at
	// z=+100) to the sun: cx(z) = 36.5 + 0.12 * (z + 123).
	float path_cx = 36.5 + 0.12 * (v_local.z + 123.0);
	// Round 8 — corridor narrowed again (22 m, was 30) and the
	// glitter path narrowed (9 m half-width, was 12): in the low
	// hero close-up the corridor is still broad and bright in the
	// centre-right, so blue water must win more of the frame. The
	// chase frame's far glitter is untouched by this (its sea is
	// 90+ m away, corridor is a world-space width, and the path
	// still reads as a distinct bright corridor to the sun).
	float path_wide = smoothstep(1.0, 0.0, abs(v_local.x - path_cx) / 22.0);
	glitter *= 0.15 + 0.85 * path_wide;
	// Round 7 — near-water glitter fade: at the low hero angle the
	// sea is CLOSE (15-40 m) and the glitter path's angular width
	// fills the frame, so the sea reads as one white-pink sheet with
	// blue only at the edges. The chase frame's sea is FAR (90+ m),
	// so a distance fade dims exactly the hero's near/mid water and
	// leaves the chase glitter alone: full glitter past 120 m, gone
	// inside 20 m. (The 20-65 m range tried first only dimmed the
	// bottom sliver of the hero band — most of that band is 40-250 m
	// away, so the range had to extend.)
	float near_fade = smoothstep(20.0, 120.0, distance(v_world, CAMERA_POSITION_WORLD));
	glitter *= near_fade;
	// Fine sparkle stripes running toward the sun (high frequency so
	// they read as glitter, not broad pink bands) and a modest
	// amplitude.
	float stripes = pow(0.5 + 0.5 * sin(v_local.x * 3.5 + TIME * 1.8 + sin(v_local.z * 1.4) * 2.0), 6.0);
	// Round 7: the glitter path is NARROWER again (12 m half-width,
	// was 18 in Round 4) and the sparkle weaker (0.05, was 0.10) so
	// blue water shows on both sides of the path even at the low
	// hero angle, instead of the whole centre of the sea reading as
	// one white-pink sheet.
	// Round 8: path 12 -> 9 m half-width, sparkle 0.05 -> 0.04 —
	// the hero-angle corridor is still broad/bright in the
	// centre-right; blue must dominate more of the hero shot.
	float path = smoothstep(1.0, 0.0, abs(v_local.x - path_cx) / 9.0);
	float sparkle = stripes * path * 0.04 * near_fade;
	col += sunset_color.rgb * (glitter + sparkle);
	// Shore foam: lapping white bands right at the waterline
	// (local x -> +76.5 is the shore at world x=-14). The foam
	// pattern drifts along the shore so the waterline reads as a
	// living edge, not a hard cut between water and sand.
	float foam_band = smoothstep(56.0, 74.0, v_local.x);
	float foam_pat = 0.5 + 0.5 * sin(v_local.z * 1.1 + TIME * 1.4 + sin(v_local.x * 1.7) * 2.5);
	// Lane B: foam constant 0.55 -> 0.4 per the rebuild gate.
	float foam = foam_band * pow(foam_pat, 3.0) * 0.4;
	col = mix(col, vec3(0.9, 0.93, 0.95), foam);
	// Distant horizon glow. Cinematic rebuild (GATE R4): 0.10 -> 0.35.
	float horizon = smoothstep(-120.0, -230.0, v_local.z);
	col = mix(col, sunset_color.rgb * 0.85, horizon * 0.35);

	ALBEDO = col;
	// Round 8: 0.25 -> 0.20 — the glitter's emission bloom is part
	// of why the hero-angle corridor reads broad and bright.
	EMISSION = sunset_color.rgb * glitter * 0.20;
	// Specular is disabled (see render_mode above): ROUGHNESS /
	// SPECULAR are ignored. The water's light comes from diffuse
	// (ambient + low sun) plus the explicit glitter term.
}
