shader_type spatial;
// Instanced soft glow billboard (halo behind crystals/crowns/coins). INSTANCE_CUSTOM.x = phase.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.2, 0.15);
uniform float intensity = 0.5;
uniform float active = 0.0;
uniform float flash = 0.0;

varying float v_ph;

void vertex() {
	v_ph = INSTANCE_CUSTOM.x * 6.2832;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv) * 2.0;
	float g = exp(-r * r * 6.0) * (1.0 - smoothstep(0.8, 1.0, r));
	float pulse = 0.7 + 0.3 * sin(TIME * (2.0 + active * 8.0) + v_ph);
	ALBEDO = color * g * intensity * pulse * (1.0 + active * 1.5 + flash * 4.0);
}
