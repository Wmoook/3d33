shader_type sky;
// Daytime sky for painted-sky levels (Forgotten Veil). The level's own painted sky (minimap colours of
// every sky tile) is reconstructed crisply (region-aware 2x2 blend, like the terrain) and placed far
// behind with gentle parallax. Its flat pastel blue is re-graded into a clear-morning gradient (deep
// cerulean above -> the painting's pastel near the horizon) while clouds and snowy ranges keep their
// painted colours with aerial perspective. Outside the painting the same gradient continues in every
// direction. Radiance pass: sky/ground hemisphere that becomes a shaded interior hemisphere underground.

uniform sampler2D paint : source_color, filter_nearest, repeat_disable;  // W x H, a = real sky
uniform vec2 level_size = vec2(400.0, 200.0);
uniform vec3 sun_dir = vec3(-0.3, 0.55, 0.78);
uniform float parallax = 0.6;
uniform float spread = 1.3;
uniform float brightness = 1.0;
uniform vec3 zenith = vec3(0.10, 0.30, 0.85);
uniform vec3 pastel = vec3(0.39, 0.53, 0.97);      // #a8c0fc in linear
uniform vec3 horizon_haze = vec3(0.5, 0.63, 0.97);
uniform float cave_amount = 0.0;
uniform vec3 cave_top = vec3(0.5, 0.55, 0.6);
uniform vec3 cave_bottom = vec3(0.05, 0.05, 0.06);

float h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

vec4 fetch(ivec2 t) {
	return texelFetch(paint, clamp(t, ivec2(0), ivec2(level_size) - 1), 0);
}

// Region-aware reconstruction: smooth curved boundaries between the painting's flat colour regions.
vec3 paint_at(vec2 p) {
	vec2 q = p - 0.5;
	vec2 fb = floor(q);
	vec2 f = q - fb;
	ivec2 b = ivec2(fb);
	vec3 c0 = fetch(b).rgb;
	vec3 c1 = fetch(b + ivec2(1, 0)).rgb;
	vec3 c2 = fetch(b + ivec2(0, 1)).rgb;
	vec3 c3 = fetch(b + ivec2(1, 1)).rgb;
	float w0 = (1.0 - f.x) * (1.0 - f.y);
	float w1 = f.x * (1.0 - f.y);
	float w2 = (1.0 - f.x) * f.y;
	float w3 = f.x * f.y;
	float k = 60.0;
	float s01 = exp(-k * dot(c0 - c1, c0 - c1));
	float s02 = exp(-k * dot(c0 - c2, c0 - c2));
	float s03 = exp(-k * dot(c0 - c3, c0 - c3));
	float s12 = exp(-k * dot(c1 - c2, c1 - c2));
	float s13 = exp(-k * dot(c1 - c3, c1 - c3));
	float s23 = exp(-k * dot(c2 - c3, c2 - c3));
	float a0 = w0 + w1 * s01 + w2 * s02 + w3 * s03;
	float a1 = w1 + w0 * s01 + w2 * s12 + w3 * s13;
	float a2 = w2 + w0 * s02 + w1 * s12 + w3 * s23;
	float a3 = w3 + w0 * s03 + w1 * s13 + w2 * s23;
	float m = max(max(a0, a1), max(a2, a3));
	a0 = exp((a0 - m) * 24.0);
	a1 = exp((a1 - m) * 24.0);
	a2 = exp((a2 - m) * 24.0);
	a3 = exp((a3 - m) * 24.0);
	return (c0 * a0 + c1 * a1 + c2 * a2 + c3 * a3) / (a0 + a1 + a2 + a3);
}

// v: 0 = level top, 1 = level bottom (continues beyond)
vec3 gradient(float v) {
	vec3 g = mix(zenith, pastel, smoothstep(-0.25, 0.55, v));
	return mix(g, horizon_haze, smoothstep(0.55, 1.1, v) * 0.6);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sd = normalize(sun_dir);
	if (AT_CUBEMAP_PASS) {
		vec3 top = vec3(0.30, 0.50, 0.98);
		vec3 hor = vec3(0.75, 0.83, 0.95);
		vec3 gnd = vec3(0.36, 0.30, 0.22);
		vec3 c = d.y > 0.0 ? mix(hor, top, pow(d.y, 0.6)) : mix(hor, gnd, smoothstep(0.0, -0.4, d.y));
		c += vec3(1.0, 0.85, 0.6) * pow(max(dot(d, sd), 0.0), 8.0) * 0.8;
		vec3 cave = mix(cave_bottom, cave_top, smoothstep(-0.7, 0.9, d.y + d.z * 0.35 - d.x * 0.15));
		COLOR = mix(c, cave, cave_amount);
	} else {
		vec3 cam = POSITION;
		float t = max(cam.z, 1.0) / max(-d.z, 0.05);
		vec2 hit = cam.xy + d.xy * t;
		vec2 anchor = vec2(level_size.x * 0.5, -level_size.y * 0.5);
		vec2 w = anchor + (cam.xy - anchor) * parallax + (hit - cam.xy) * spread;
		vec2 p = vec2(w.x, -w.y);
		vec2 uv = p / level_size;
		vec3 g = gradient(uv.y);
		vec3 painted = paint_at(p);
		// the painting's flat sky blue becomes the gradient; clouds / mountains keep their paint
		float skyness = 1.0 - smoothstep(0.03, 0.12, distance(painted, pastel));
		vec3 c = mix(painted, g, skyness);
		c = mix(c, horizon_haze, 0.18 * (1.0 - skyness));   // aerial perspective on ranges / clouds
		float inside = smoothstep(0.0, 0.03, uv.x) * smoothstep(1.0, 0.97, uv.x)
			* smoothstep(0.0, 0.03, uv.y) * smoothstep(1.0, 0.97, uv.y);
		c = mix(g, c, inside);
		float wisp = n2(vec2(w.x * 0.04 + TIME * 0.01, w.y * 0.1)) * n2(vec2(w.x * 0.09 - TIME * 0.006, w.y * 0.18 + 3.0));
		c = mix(c, vec3(0.95, 0.97, 1.0), smoothstep(0.25, 0.8, wisp) * 0.14 * mix(1.0, skyness, inside));
		float s = max(dot(d, sd), 0.0);
		c += vec3(1.0, 0.85, 0.6) * (pow(s, 6.0) * 0.1 + pow(s, 60.0) * 0.25);
		COLOR = c * brightness;
	}
}
