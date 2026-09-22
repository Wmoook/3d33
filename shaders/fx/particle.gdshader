shader_type spatial;
// Generic additive particle sprite (soft dot or streak). Color comes from the process material's color ramp.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 3.0;
uniform float streak = 0.0; // 1 = elongated along UV.y

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= mix(1.0, 1.0, streak);
	float r = length(uv * vec2(1.0, mix(1.0, 0.35, streak))) * 2.0;
	float core = exp(-r * r * 7.0);
	float halo = exp(-r * r * 2.2) * 0.35;
	float m = (core + halo) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = COLOR.rgb * COLOR.a * m * intensity;
}
