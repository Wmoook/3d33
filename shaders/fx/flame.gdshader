shader_type spatial;
// Flame tongue sprite (MultiMesh): noise-licked teardrop with an HDR blackbody ramp.
// Quad faces +z; its bottom edge sits on a fire tile's top. INSTANCE_CUSTOM.x = phase, .y = heat (0..1).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 0.85;
uniform float wind = 0.0;

varying float v_ph;
varying float v_heat;

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
float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_ph = INSTANCE_CUSTOM.x * 50.0;
	v_heat = INSTANCE_CUSTOM.y;
	float v = 1.0 - UV.y;
	VERTEX.x += (sin(TIME * 2.3 + v_ph) * 0.12 + wind) * v * v;
}

void fragment() {
	float t = TIME * (1.0 + v_heat * 0.3);
	float v = 1.0 - UV.y;            // 0 bottom .. 1 top
	float x = (UV.x - 0.5) * 2.0;    // -1 .. 1
	// domain-warped rising noise
	vec2 q = vec2(x * 1.4 + v_ph, v * 1.8 - t * 2.6);
	float n = fbm(q);
	float n2 = fbm(q * 2.3 + vec2(n * 1.5, -t * 1.3));
	x += (n - 0.5) * 1.7 * v + (n2 - 0.5) * 0.35;
	// tapered tongue body, ragged edges, licks that tear off near the top
	float width = mix(0.95, 0.05, pow(v, 0.9));
	float body = 1.0 - smoothstep(width * 0.15, width, abs(x));
	float f = body * (1.0 - v) * 1.7 - n2 * (0.55 + v * 0.9) + 0.18;
	f = clamp(f, 0.0, 1.0);
	f *= smoothstep(0.0, 0.1, v);
	f = pow(f, 1.3);
	vec3 c = mix(vec3(0.45, 0.03, 0.0), vec3(1.0, 0.3, 0.03), smoothstep(0.0, 0.3, f));
	c = mix(c, vec3(1.0, 0.62, 0.12), smoothstep(0.3, 0.65, f));
	c = mix(c, vec3(1.0, 0.8, 0.4), smoothstep(0.75, 1.0, f) * v_heat * 0.4);
	ALBEDO = c * f * intensity * (0.75 + v_heat * 0.4);
}
