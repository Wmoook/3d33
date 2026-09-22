shader_type spatial;
// Distant silhouetted hills / forest layers: dark, lit only by a moon-rim, fading into the horizon haze.
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec3 base_col : source_color = vec3(0.008, 0.01, 0.022);
uniform vec3 haze_col : source_color = vec3(0.03, 0.036, 0.08);
uniform float haze = 0.5;
uniform float rim = 0.0;

varying float v_top;

void vertex() {
	v_top = UV.y;
}

void fragment() {
	vec3 c = mix(base_col, haze_col, haze);
	// faint moon rim along the crest, haze gets thicker towards the base
	c += vec3(0.05, 0.06, 0.12) * rim * smoothstep(0.985, 1.0, v_top);
	ALBEDO = c;
}
