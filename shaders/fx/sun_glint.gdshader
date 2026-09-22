shader_type spatial;
// Sun glints on water surfaces and wet stone (FxVeil MultiMesh): a tiny camera-facing 4-ray star that
// sparkles in short random bursts. INSTANCE_CUSTOM: x = phase, y = rate, z = strength.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.97, 0.88);
uniform float intensity = 3.0;

varying vec3 v_c;

void vertex() {
	v_c = INSTANCE_CUSTOM.xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float ph = v_c.x * 6.2832;
	float s = sin(TIME * v_c.y + ph) * 0.6 + sin(TIME * v_c.y * 2.7 + ph * 3.0) * 0.4;
	float k = pow(max(s, 0.0), 12.0) * v_c.z;
	float rays = exp(-abs(p.x) * 30.0) * exp(-abs(p.y) * 3.0) + exp(-abs(p.y) * 30.0) * exp(-abs(p.x) * 3.0);
	float core = exp(-dot(p, p) * 30.0);
	ALBEDO = color * (rays * 0.8 + core) * k * intensity * (1.0 - smoothstep(0.8, 1.0, length(p)));
}
