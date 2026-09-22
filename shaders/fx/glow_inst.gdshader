shader_type spatial;
// Instanced additive glow billboard coloured per instance (fireflies, moths, wisps). COLOR.a = brightness.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 3.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = exp(-r * r * 22.0);
	float halo = exp(-r * r * 4.0) * 0.35;
	ALBEDO = COLOR.rgb * (core * 1.5 + halo) * COLOR.a * intensity * (1.0 - smoothstep(0.8, 1.0, r));
}
