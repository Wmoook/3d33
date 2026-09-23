shader_type spatial;
// Speed streak ribbon behind the ball. UV.x = 0 at head .. 1 at tail, UV.y across. COLOR.a = strength.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 head_color : source_color = vec3(1.0, 0.9, 0.55);
uniform vec3 tail_color : source_color = vec3(1.0, 0.38, 0.06);
uniform float intensity = 1.6;

void fragment() {
	float x = UV.x;
	float y = abs(UV.y - 0.5) * 2.0;
	float core = exp(-y * y * 5.0);
	float wisp = 0.6 + 0.4 * sin(x * 22.0 - TIME * 30.0 + UV.y * 3.0);
	vec3 col = mix(head_color, tail_color, smoothstep(0.0, 0.8, x));
	float a = core * pow(1.0 - x, 1.5) * COLOR.a * mix(1.0, wisp, x);
	ALBEDO = col * a * intensity;
}
