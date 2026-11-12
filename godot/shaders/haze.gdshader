shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Heat-haze shimmer hovering just above the road surface: two scrolling
// sine-noise fields added over the asphalt, faded at the plane edges so it
// reads as rising hot air catching the sunset, not a visible quad.

uniform vec4 haze_color : source_color = vec4(1.0, 0.55, 0.45, 1.0);
uniform float scroll_speed = 2.2;
uniform float strength = 0.10;

void fragment() {
	float n1 = 0.5 + 0.5 * sin(UV.y * 46.0 - TIME * scroll_speed + sin(UV.x * 18.0) * 1.5);
	float n2 = 0.5 + 0.5 * sin(UV.x * 30.0 + TIME * 0.9 + UV.y * 12.0);
	float band = n1 * n2;
	// Fade out at all four edges of the plane.
	float fade_x = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	float fade_y = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.75, UV.y);
	float a = band * fade_x * fade_y * strength;
	ALBEDO = haze_color.rgb;
	ALPHA = a;
}
