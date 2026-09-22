shader_type spatial;
// Plunge-pool splash rings where a waterfall hits the water: foam ellipses spreading out on the surface
// (the quad is stretched wide and flat so it reads as a ring seen at a low angle), churning foam core.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 foam : source_color = vec3(0.95, 0.98, 1.0);
uniform float rate = 0.55;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = 0.0;
	for (int i = 0; i < 3; i++) {
		float age = fract(TIME * rate + float(i) / 3.0);
		float rr = 0.15 + age * 0.8;
		float w = 0.04 + age * 0.05;
		float ring = exp(-pow((r - rr) / w, 2.0)) * (1.0 - age);
		float brk = vnoise(vec2(atan(p.y, p.x) * 4.0 + float(i) * 5.0, age * 3.0));
		a += ring * smoothstep(0.25, 0.7, brk);
	}
	float core = exp(-r * r * 9.0) * (0.55 + 0.45 * vnoise(p * 6.0 + vec2(TIME * 3.0, 0.0)));
	a = clamp(a * 0.9 + core * 0.8, 0.0, 1.0) * (1.0 - smoothstep(0.9, 1.0, r));
	ALBEDO = foam;
	ALPHA = a * 0.85;
}
