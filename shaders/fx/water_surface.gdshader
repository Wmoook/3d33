shader_type spatial;
// Water surface line: bright rolling crest, foam flecks and a soft glow band just under the surface.
// Strip mesh: UV.x = world x, UV.y = 0 at the top edge .. 1 deep (crest sits ~0.28 into the strip).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 crest : source_color = vec3(0.75, 0.92, 1.0);
uniform vec3 deep : source_color = vec3(0.15, 0.45, 1.0);
uniform float intensity = 1.0;
uniform float flow = 0.0;   // tiles/s the surface drifts toward +x (0 = still, Odyssey)

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
	float x = UV.x - TIME * flow;
	float d = UV.y;
	float t = TIME;
	float wave = sin(x * 1.7 + t * 1.6) * 0.05 + sin(x * 4.3 - t * 2.3) * 0.03 + (vnoise(vec2(x * 2.0, t * 0.6)) - 0.5) * 0.06;
	float yy = d - 0.28 - wave;
	float line = exp(-yy * yy * 900.0);
	float glow = exp(-max(yy, 0.0) * 5.0) * step(0.0, yy) * 0.35;
	float foam = step(0.72, vnoise(vec2(x * 6.0 - t * 0.8, t * 0.3))) * exp(-yy * yy * 250.0);
	float fleck = step(0.93, hash12(floor(vec2(x * 14.0, t * 3.0)))) * exp(-yy * yy * 400.0);
	vec3 c = crest * (line * 1.6 + foam * 1.2 + fleck * 1.5) + deep * glow;
	ALBEDO = c * intensity;
}
