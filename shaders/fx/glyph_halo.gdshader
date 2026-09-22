shader_type spatial;
// Soft dark halo behind zero-g dot glyphs (gentle contrast backing, never a hard black disc).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float hc = 0.0;
varying float v_r;

void vertex() {
	v_r = length(VERTEX.xy) / 0.36;
	VERTEX *= 1.0 + hc * 0.5;
}

void fragment() {
	ALBEDO = vec3(0.02, 0.015, 0.01);
	ALPHA = (1.0 - smoothstep(0.15, 1.0, v_r)) * 0.5;
}
