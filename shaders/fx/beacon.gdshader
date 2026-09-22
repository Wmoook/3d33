shader_type spatial;
// Spawn beacon light column: additive vertical shaft with rising rings and a soft base pool.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.7, 0.9, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float y = 1.0 - UV.y;  // 0 at bottom
	float shaft = exp(-x * x * 7.0) * pow(1.0 - y, 2.2);
	float core = exp(-x * x * 60.0) * pow(1.0 - y, 3.0);
	float rings = pow(0.5 + 0.5 * sin(y * 18.0 - TIME * 4.0), 12.0) * (1.0 - y) * exp(-x * x * 3.0);
	float flick = 0.9 + 0.1 * sin(TIME * 7.0);
	ALBEDO = color * (shaft * 0.35 + core * 0.6 + rings * 0.35) * intensity * flick;
}
