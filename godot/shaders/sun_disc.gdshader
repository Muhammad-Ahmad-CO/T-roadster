shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

// The visible sun disc. Unshaded and fog-disabled on purpose: at ~240 m
// even thin fog would wash the disc out to a pale pink blob. The glow
// sprite around it still gets fogged, so the disc reads as a hard bright
// core inside a soft haze.

uniform vec4 disc_color : source_color = vec4(1.0, 0.62, 0.32, 1.0);
uniform float energy = 7.0;

void fragment() {
	ALBEDO = disc_color.rgb * energy;
}
