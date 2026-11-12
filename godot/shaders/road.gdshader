shader_type spatial;
render_mode specular_schlick_ggx, cull_back, depth_draw_opaque;

varying float v_spec;
// Round 7 — world Z of the fragment (road segments recycle, so UV.y
// cycles per segment and cannot tell near from far; world Z can).
// Used for the streak distance fade and the grain amplitude ramp.
varying float v_wz;
// Smoothed base colour (pre-texture asphalt + palette tints + markings,
// no texture/grain) for the light() chroma test — GATE R5 Step 2.
varying vec3 v_base_col;

void vertex() {
	v_wz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

// Dark asphalt with crisp lane dashes, solid edge lines and a wet-look
// centre strip that catches the sunset. UV-based (UV.x across the 12 m
// road, UV.y along the segment) so the markings stay sharp at any speed:
// every recycled road segment carries the same dash phase, so dashes never
// jump or stretch while scrolling.
//
// Round 5 — the road read as one big ORANGE-BROWN expanse (mid-road
// measured 197,109,75) because the orange sunset sun lights the albedo,
// and the albedo was already grey. The fix is a custom light() below:
// the direct-light diffuse is desaturated toward grey on the asphalt
// while the specular sun streak keeps its warm colour, and the yellow
// centre dashes keep their warm light. The near-field checkerboard
// (old per-cell hash, 240x1600 cells) is replaced by smooth value noise.
//
// Cinematic rebuild (GATE R5 Step 2) — Asphalt031 texture: the road
// samples res://assets/asphalt031_color_1024.jpg for mean-preserving
// luminance detail (4 x 6 tiles per segment, from RAW uv) and
// res://assets/asphalt031_rough_512.jpg for roughness variation.
// Markings/dashes/streak composite OVER the textured albedo and stay
// crisp; light() chroma weight derives from the smoothed (pre-texture)
// base colour via v_base_col, so aggregate grain cannot flicker it.

uniform vec4 asphalt_color : source_color = vec4(0.10, 0.10, 0.12, 1.0);
uniform vec4 line_color : source_color = vec4(0.92, 0.90, 0.82, 1.0);
uniform vec4 center_color : source_color = vec4(0.95, 0.88, 0.72, 1.0);
uniform vec4 wear_color : source_color = vec4(0.14, 0.14, 0.16, 1.0);
uniform vec4 sun_tint : source_color = vec4(1.0, 0.45, 0.55, 1.0);
uniform float wetness = 0.4;
// 2 cycles per 20 m segment = 10 m cycle, 25% duty = 2.5 m dash,
// 7.5 m gap (real highway dashes are ~3 m / 9 m). The count MUST stay
// an integer per segment or the dash phase jumps at every recycle seam.
uniform float dash_count = 2.0;
// How much of the warm direct light is desaturated out of the grey
// asphalt toward neutral grey (0 = keep the sunset orange, 1 = fully
// grey diffuse). The warm sun STREAK is specular and is NOT touched.
// Cinematic rebuild (GATE R5 Step 1): 1.0 -> 0.55 — the reel road is
// warm mauve, not neutral grey; the R5-R8 grey target is superseded.
// Falsifier: road goes orange-brown -> restore desat in 0.1 steps.
uniform float light_desat = 0.55;
// Round 7 — ADDITIVE sun streak (a separate mechanism from the GGX
// term): the GGX streak could never be made bold without warming the
// whole road (boost 2.5/6.0 and wider bands all failed in Round 6),
// because the GGX lobe is broad. This EMISSION term adds warm
// brightness ONLY inside a narrow band down the sun path (across
// 0.42, the same centre as the wet band) and fades with distance, so
// the grey asphalt outside the band is untouched. It is emission,
// not light, so it bypasses the custom light() desaturation on
// purpose — the streak is SUPPOSED to stay warm. Per-biome colour/
// strength come from world_builder (_apply_palette); the defaults
// below are the coastal sunset values.
uniform vec4 streak_color : source_color = vec4(1.0, 0.45, 0.18, 1.0);
uniform float streak_strength = 1.0;
// Direct-light specular boost: the fragment SPECULAR below is kept
// LOW on purpose (it also scales the sky/env reflection, and that
// reflection is what turned the road orange — see below), so the
// direct sun streak is boosted back up here to stay visible.
// Round 7 — 1.5 -> 0.4: the GGX term is the warm wash. Round 6
// proved the road's warmth lives in this GGX term (zeroing it took
// R-G 35 -> 5-7), and its magnitude is ~100x the textbook value, so
// even the dry lanes (v_spec 0.001) get a strong warm specular at
// grazing angles — the sunlit mid-distance road read as a broad
// orange-pink wash, not grey asphalt with a streak. The streak no
// longer needs the GGX: the additive EMISSION term (Round 7) is the
// streak now, so the boost can drop to a quiet sheen level and let
// the emission carry the path. The dry lanes should go grey while
// the emission band stays bold.
uniform float specular_boost = 0.10; // R7: 1.5 -> 0.4. R8: 0.4 -> 0.25 -> 0.10 — the UV flip put the wet band on the sun side, at the GGX lobe peak, so the sheen warmed the whole left lane (diagnostic D: boost 0.25 -> 0.0 took the left-lane peak R-G 61 -> 37). 0.10 keeps a whisper of wet sheen; the EMISSION streak carries the sun path.
// Scales the specular amount: the direct sun streak AND the sky/env
// reflection at grazing angles. Rain sets this low (0.4) so the wet
// road stops mirroring the pink sky on the left lane.
uniform float reflection_scale = 1.0;
// Cinematic rebuild (GATE R5 Step 2): Asphalt031 maps, set once from
// world_builder._build_road (_apply_palette never touches them, so
// they survive biome changes). Linear + mipmap filtering, repeat
// wrapping: the tiling below relies on repeat at segment edges.
// (Godot 4.3 rejects the `repeat` sampler hint — "Expected valid
// type hint" — so only the filter hint is declared; repeat is the
// RenderingServer default sampler behaviour, verified by the seam
// check: clamp wrapping would stretch one tile over the segment.)
uniform sampler2D asphalt_tex : filter_linear_mipmap;
uniform sampler2D asphalt_rough_tex : filter_linear_mipmap;
// Measured mean luminance of asphalt031_color_1024.jpg in the space
// the shader actually samples: Godot 4.3 does NOT sRGB-decode this
// VRAM-compressed texture in a custom shader — texture() returns the
// raw sRGB values (proven by render: the linear-space mean 0.195
// brightened the road ~1.5x, clamped; the sRGB mean restores Stage 5
// brightness). tex_mod = lum / this averages 1.0, so the texture
// adds ONLY luminance detail around the palette road_color.
const float TEX_MEAN_LUM = 0.471;
// Texture detail strength: full-strength modulation would swing the
// road 0.54x-1.72x (measured p5/p95 of the map) — 3x the old grain
// amplitude. 0.4 keeps the aggregate visible near the camera; the
// remap stays mean-preserving at any strength.
const float TEX_STRENGTH = 0.4;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise: soft blotches with no hard cell edges. The old
// per-cell hash (floor(uv * vec2(240, 1600))) aliased at grazing angles
// into a visible brown checkerboard / horizontal striping in the near
// field — hard-edged cells can never look like asphalt up close.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	// Round 8 — BoxMesh UV MIRROR (root cause of the right-lane
	// warmth): the top face of a BoxMesh maps UV.x RIGHT-TO-LEFT
	// in world space, so shader-across 0.42 sat at world x = +0.96
	// (RIGHT of centre, away from the sun) — proven by the green
	// debug streak (r8-scratch/diagC_green.png), which ran down
	// the RIGHT side of the road. Every asymmetric feature in this
	// shader (streak band, wet band, wet glow, left-cool tint) was
	// therefore mirrored from what its comment said: the "sun path"
	// was on the wrong side of the road, and the left-cool tint was
	// cooling the right lane. Flipping `across` here puts the sun
	// path on the LEFT (sun side, world x = -0.96), the left-cool
	// tint on the left, and the right-cool tint on the right. The
	// symmetric features (dashes, wear bands, edge lines) are
	// unaffected by the flip. The streak's bloom — the actual
	// source of the right-lane warmth (diagnostics A/B) — now sits
	// on the sun side, where warmth belongs, and the right lane
	// goes grey.
	float across = 1.0 - uv.x;

	// Round 7 — fine asphalt grain: three octaves of smooth value
	// noise. The old two-octave +/-6% grain read as a flat uniform
	// sheet at mid-distance (the far road compresses vertically, so
	// 0.5 m blotches vanish). The new third octave is a ~2 m patch
	// scale that survives the foreshortening, and the amplitude RAMPS
	// with distance: subtle (+/-6%) up close so the near field stays
	// smooth (the Round 4 checkerboard came from hard-edged cells
	// up close — smooth noise + low near amplitude cannot alias into
	// it), stronger (+/-14%) in the mid/far road where the texture
	// needs to read. All three octaves are SMOOTH value noise, no
	// hard cell edges anywhere. (Cinematic rebuild, GATE R5 Step 2:
// superseded by the Asphalt031 texture below — g1/g3 dropped, one
// fine octave kept for close-up detail.)
	// Cinematic rebuild (GATE R5 Step 2) — Asphalt031 texture.
	// tex_uv uses the RAW mesh uv, NOT `across`: asphalt is isotropic,
	// so the R8 BoxMesh mirror flip is invisible in the texture, and
	// sampling raw uv keeps the tiling phase identical on every
	// segment. 4 tiles across the 12 m road, 6 along the 20 m segment
	// — INTEGER per segment in both axes, so the texture phase matches
	// at recycle seams (a segment recycled by -240 m is
	// indistinguishable from the one it replaces). `across` stays for
	// markings/streak only; dash/marking UVs are untouched.
	vec2 tex_uv = vec2(uv.x * 4.0, uv.y * 6.0);
	vec3 tex_sample = texture(asphalt_tex, tex_uv).rgb;
	float tex_lum = dot(tex_sample, vec3(0.299, 0.587, 0.114));
	// Mean-preserving luminance detail: tex_mod averages 1.0, so the
	// palette road_color keeps control of hue/brightness. Clamped so
	// the darkest/brightest texels cannot punch through.
	float tex_mod = clamp(1.0 + (tex_lum / TEX_MEAN_LUM - 1.0) * TEX_STRENGTH, 0.6, 1.5);
	vec3 col = asphalt_color.rgb * tex_mod;
	// One fine noise octave kept (g1/g3 dropped — the texture carries
	// mid/far detail): close-up aggregate shimmer only, fading out
	// by 50 m so it never aliases at distance.
	float fine = vnoise(uv * vec2(90.0, 150.0));
	float fine_amp = mix(0.06, 0.0, smoothstep(-8.0, -50.0, v_wz));
	col *= 1.0 + (fine - 0.5) * 2.0 * fine_amp;

	// Tyre-wear bands: darker polished strips at each lane centre
	// (lane centres at 1/8, 3/8, 5/8, 7/8 of the road width).
	float wear = 0.0;
	wear = max(wear, smoothstep(0.09, 0.02, abs(across - 0.125)));
	wear = max(wear, smoothstep(0.09, 0.02, abs(across - 0.375)));
	wear = max(wear, smoothstep(0.09, 0.02, abs(across - 0.625)));
	wear = max(wear, smoothstep(0.09, 0.02, abs(across - 0.875)));
	col = mix(col, wear_color.rgb, wear * 0.45);

	// Lane dashes at the three lane boundaries (0.25 / 0.50 / 0.75).
	// Line half-width ~0.10 UV (12 cm on a 12 m road) with a 4 cm
	// feather — crisp, not a blurry blob.
	float dash_phase = fract(uv.y * dash_count);
	float dash_on = step(dash_phase, 0.25);
	float lane_line = 0.0;
	lane_line = max(lane_line, smoothstep(0.010, 0.004, abs(across - 0.25)));
	lane_line = max(lane_line, smoothstep(0.010, 0.004, abs(across - 0.5)));
	lane_line = max(lane_line, smoothstep(0.010, 0.004, abs(across - 0.75)));
	// Centre divider is warm white at sunset, others white.
	float centre = smoothstep(0.010, 0.004, abs(across - 0.5));
	vec3 dash_col = mix(line_color.rgb, center_color.rgb, centre);
	col = mix(col, dash_col, lane_line * dash_on);

	// Solid edge lines hugging both shoulders.
	float edge = max(smoothstep(0.010, 0.004, abs(across - 0.02)),
		smoothstep(0.010, 0.004, abs(across - 0.98)));
	col = mix(col, line_color.rgb, edge);

	// Wet look: a faint sunset tint pooled in the middle of the road,
	// stronger where the wear bands are polished smooth. Kept subtle —
	// the old 0.22 mix is what turned the whole road pink-red, and
	// 0.06 still washed the left lane orange.
	// Round 6 iter7 — the tint pool follows the wet band (left of
	// centre, across 0.42) instead of the road centre.
	float wet_glow = (1.0 - abs(across - 0.42) * 1.6) * wetness;
	col = mix(col, sun_tint.rgb, clamp(wet_glow, 0.0, 1.0) * 0.02);

	// Round 7 — far-road cool tint: the SUNLIT far road still reads
	// warm mauve-pink (right lane R-G ~60 at y 680 when the palm
	// shadows miss it) — fog + the grazing sky reflection warm it,
	// and the left-cool tint only covers the left half. This tint
	// uses the world-Z varying to cool the road toward blue-grey as
	// it recedes (full strength past z -120), applied to the albedo
	// only — the additive streak EMISSION below is added after, so
	// the warm path keeps its colour and gains CONTRAST against the
	// now-cooler far road. Kept modest (0.25) so the far road reads
	// as cool grey asphalt in sunset haze, not blue paint.
	// Cinematic rebuild (GATE R5 Step 1): 0.25 -> 0.15 (warmer far road).
	float far_cool = smoothstep(-30.0, -120.0, v_wz) * 0.15;
	col = mix(col, col * vec3(0.78, 0.88, 1.08), far_cool);

	// Round 6 — left-cool counter-tint strengthened (0.30 -> 0.45)
	// and cooled further: the fog + grazing sky reflection still
	// leave the road mauve (mid-road R-G ~40), so the counter-tint
	// has to work harder on the sun side.
	// Cinematic rebuild (GATE R5 Step 1): 0.45 -> 0.20 (the reel road
	// IS warm mauve; the counter-tint now only takes the edge off).
	float left_cool = smoothstep(0.45, 0.05, across) * 0.20;
	col = mix(col, col * vec3(0.72, 0.85, 1.12), left_cool);

	// Round 8 — right-cool counter-tint, mirroring the left-cool
	// tint: the sunlit RIGHT lane at mid-distance still reads warm
	// (R-G ~40-60) from streak glow + fog/grazing reflection while
	// the left lane is grey (R-G 4-12). Same strength and cooling
	// as the left side so both lanes match. Starts at across 0.55
	// so it never touches the streak band (centre 0.42, feather
	// to 0.48) or the centre dashes.
	// Cinematic rebuild (GATE R5 Step 1): 0.45 -> 0.20 (matches left).
	float right_cool = smoothstep(0.55, 0.95, across) * 0.20;
	col = mix(col, col * vec3(0.72, 0.85, 1.12), right_cool);

	// Smoothed base colour for light(): the SAME wear/marking/edge/tint
	// pipeline as `col` but WITHOUT the texture modulation and fine
	// grain, so the desaturation weight w does not vary per-texel with
	// the asphalt aggregate (GATE R5 Step 2). Markings stay in, so
	// dashes keep their warm-light behaviour exactly as in v2.1.0.
	vec3 smooth_col = asphalt_color.rgb;
	smooth_col = mix(smooth_col, wear_color.rgb, wear * 0.45);
	smooth_col = mix(smooth_col, dash_col, lane_line * dash_on);
	smooth_col = mix(smooth_col, line_color.rgb, edge);
	smooth_col = mix(smooth_col, sun_tint.rgb, clamp(wet_glow, 0.0, 1.0) * 0.02);
	smooth_col = mix(smooth_col, smooth_col * vec3(0.78, 0.88, 1.08), far_cool);
	smooth_col = mix(smooth_col, smooth_col * vec3(0.72, 0.85, 1.12), left_cool);
	smooth_col = mix(smooth_col, smooth_col * vec3(0.72, 0.85, 1.12), right_cool);
	v_base_col = smooth_col;

	ALBEDO = col;
	// Round 6 — dry SPECULAR 0.002 -> 0.001 (the grazing sky
	// reflection is still the main mauve source on the dry lanes),
	// wet SPECULAR 0.16 -> 0.24.
	// Iteration 9 — keep boost 1.5 but narrow the band back to
	// 0.06..0.14: iter8's wider band (0.08..0.18) warmed the near
	// road to R-G 18; the narrow band keeps the streak bright in
	// the mid-distance while fewer near-road pixels sit in it.
	float wet_band = 1.0 - smoothstep(0.06, 0.14, abs(across - 0.42));
	float wet_factor = clamp(wet_band * wetness * 1.2, 0.0, 1.0);
	// Cinematic rebuild (GATE R5 Step 2): roughness map (R channel,
	// same tiling) blended into the dry roughness BEFORE the wet-band
	// mix, so the wet band still overrides toward glossy.
	float rough_tex = texture(asphalt_rough_tex, tex_uv).r;
	float dry_rough = mix(0.95, rough_tex, 0.6);
	ROUGHNESS = mix(dry_rough, 0.25, wet_factor);
	SPECULAR = mix(0.001, 0.24, wet_factor) * reflection_scale;
	METALLIC = 0.0;
	v_spec = SPECULAR;

	// Round 7 — additive sun streak (EMISSION, confined to the sun
	// path). Band: ~0.7 m bright core, feathering to ~2.4 m total, centred
	// across 0.42 (left of centre — the sun sits 13 deg left of
	// straight ahead, same centre as the wet GGX band). Distance fade:
	// OFF near the camera (z > +5, so it never shines through the
	// hero's shadow or the near road), full strength z -20..-160,
	// fading out toward the horizon (z < -160) where the fog takes
	// over. The band is straight in UV, so in perspective it
	// converges toward the sun — a bright warm path running down the
	// road. Strength 0.30 (linear) + a redder colour (1.0,0.45,0.18),
	// in a NARROW band (core 0.02, feather 0.06 — ~1.4 m total):
	// the 0.24-strength, 0.04/0.10-wide band made a bold path but its
	// GLOW washed the dry right lane to R-G ~50 (diagnostic: boost
	// 0.0 changed it by only ~5, emission 0 took it to R-G 4 — the
	// wash is the emission's bloom, not the GGX). A narrow bright
	// line carries the same peak brightness with less total bloom
	// energy, so the path stays bold while the dry lanes stay grey.
	// The near fade now starts at z +18 and is full by z -2, so the
	// path reads continuously from just ahead of the hero to the
	// horizon instead of fading out in the near-mid road.
	// Round 8 — fade START moved from z +10 to z +18: the Round 7
	// fade killed the path in the near road by design, but the reel's
	// sun path runs the FULL length of the road toward the sun. The
	// road's nearest z is +15 (RECYCLE_Z), so z +18 is just off the
	// bottom edge of the frame — the path now runs from the bottom
	// of the frame, past the hero, to the horizon. Kept narrow and
	// at 0.30 strength (Round 7 lesson: the wash is the emission's
	// glow, so a narrow bright line carries the path without
	// blooming warmth across the near lanes); the near road's R-G
	// is checked after this change.
	// Round 8 iter2 — strength 0.30 -> 0.20, band 0.02/0.06 ->
	// 0.015/0.05: after the UV flip the streak sits on the sun
	// side (left) and its bloom washed the WHOLE left lane
	// (R-G up to 87, spanning the full left half) instead of a
	// narrow path. Less total bloom energy: a distinct warm line
	// on grey asphalt, not a wash. The band stays narrow and
	// bright; the lanes stay grey.
	float streak_band = 1.0 - smoothstep(0.015, 0.05, abs(across - 0.42));
	float streak_fade = smoothstep(18.0, -2.0, v_wz) * (1.0 - smoothstep(-160.0, -220.0, v_wz));
	EMISSION = streak_color.rgb * streak_band * streak_fade * 0.20 * streak_strength;
}

// Custom light (Round 5): the orange sunset sun turned the whole road
// orange-brown even though the albedo is already grey (0.17) — the
// warmth is in the LIGHT, so the fix belongs here, not in the albedo.
// The direct-light diffuse is desaturated toward its own luminance on
// grey asphalt (the road), while coloured markings keep their warm
// light (the yellow centre line must stay yellow) and the GGX specular
// sun streak keeps the warm light colour. ATTENUATION carries the
// shadow factor for directional lights, so palm/hero shadows still
// darken the road exactly as before. NOTE (Round 5 diagnostics): the
// direct diffuse is only a small part of the orange — the sunset SKY
// (ambient IRRADIANCE + env RADIANCE) is the dominant source, and
// neither passes through light(), so fragment() desaturates those too.
void light() {
	// (LIGHT_COLOR already carries the light's energy in Godot 4 —
	// there is no separate LIGHT_ENERGY built-in in light().)
	// NOTE: do NOT multiply by ALBEDO here — the engine multiplies
	// DIFFUSE_LIGHT by the albedo at the end, so doing it here would
	// apply it twice (albedo squared) and darken the road. Divide by
	// PI because LIGHT_COLOR carries the energy times PI (per the
	// Godot docs example), which matches the built-in Burley diffuse.
	float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 diffuse = LIGHT_COLOR * NdotL * ATTENUATION / 3.14159265;
	// Grey asphalt (low albedo chroma) gets the full desaturation;
	// coloured markings (high chroma, e.g. the yellow centre line)
	// keep their warm light so the dashes stay yellow, not grey.
	// Cinematic rebuild (GATE R5 Step 2): the chroma test runs on the
	// SMOOTHED base colour (v_base_col), NOT the textured albedo, so
	// aggregate grain cannot make w flicker per-texel.
	float spread = max(v_base_col.r, max(v_base_col.g, v_base_col.b)) - min(v_base_col.r, min(v_base_col.g, v_base_col.b));
	float w = (1.0 - smoothstep(0.04, 0.18, spread)) * light_desat;
	float lum = dot(diffuse, vec3(0.299, 0.587, 0.114));
	DIFFUSE_LIGHT += mix(diffuse, vec3(lum), w);

	// GGX (Schlick) specular, warm light colour kept — this is the
	// narrow sun streak down the wet band, and it must stay warm.
	// Scaled by v_spec (the fragment SPECULAR, 0.002 dry / 0.16 wet):
	// the old code used SPECULAR_AMOUNT, which is 1.0 for directional
	// lights, so the streak was 20x too strong and warmed the whole
	// road at grazing angles. specular_boost restores the streak
	// visibility without washing the dry lanes.
	vec3 H = normalize(LIGHT + VIEW);
	float NdotH = clamp(dot(NORMAL, H), 0.0, 1.0);
	float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float alpha = ROUGHNESS * ROUGHNESS;
	float alpha2 = alpha * alpha;
	float denom = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
	float D = alpha2 / (3.14159265 * denom * denom);
	float VdotH = clamp(dot(VIEW, H), 0.0, 1.0);
	float F = 0.04 + 0.96 * pow(1.0 - VdotH, 5.0);
	float k = alpha * 0.5;
	float G = (NdotL / (NdotL * (1.0 - k) + k)) * (NdotV / (NdotV * (1.0 - k) + k));
	float spec = D * G * F / max(4.0 * NdotL * NdotV, 0.001);
	SPECULAR_LIGHT += LIGHT_COLOR * spec * NdotL * ATTENUATION * v_spec * specular_boost;
}
