shader_type sky;
// Night sky: deep gradient, dense twinkling star field, milky band, aurora curtains and a glowing moon.

uniform vec3 zenith = vec3(0.004, 0.008, 0.03);
uniform vec3 horizon = vec3(0.03, 0.035, 0.09);
uniform vec3 moon_dir = vec3(-0.35, 0.55, -0.75);
uniform float aurora_strength = 1.0;
uniform float star_strength = 1.0;
// Underground the radiance (ambient + reflections) becomes a zone-tinted cave hemisphere: light
// from above/front, dark below, so ambient still sculpts normals instead of flattening them.
uniform float cave_amount = 0.0;
uniform vec3 cave_top = vec3(0.5, 0.4, 0.35);
uniform vec3 cave_bottom = vec3(0.05, 0.04, 0.04);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 stars(vec3 d, float scale, float thresh) {
	vec3 p = d * scale;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash(id);
	if (h < thresh) return vec3(0.0);
	vec3 jit = vec3(hash(id + 1.3), hash(id + 2.7), hash(id + 5.1)) - 0.5;
	float dist = length(f - jit * 0.6);
	float tw = 0.6 + 0.4 * sin(TIME * (1.0 + h * 4.0) + h * 60.0);
	float b = smoothstep(0.08, 0.0, dist) * tw * (h - thresh) / (1.0 - thresh);
	vec3 tint = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.85, 0.7), hash(id + 9.0));
	return tint * b;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(clamp(up * 0.5 + 0.5, 0.0, 1.0), 1.6));
	if (AT_CUBEMAP_PASS) {
		vec3 night = mix(vec3(0.03, 0.035, 0.07), vec3(0.14, 0.17, 0.3), smoothstep(-0.5, 0.7, d.y));
		vec3 cave = mix(cave_bottom, cave_top, smoothstep(-0.7, 0.9, d.y + d.z * 0.35 - d.x * 0.15));
		COLOR = mix(night, cave, cave_amount);
	} else {
		// milky band
		vec3 bandn = normalize(vec3(0.3, 0.8, 0.5));
		float band = exp(-pow(dot(d, bandn) * 3.2, 2.0));
		float neb = n3(d * 6.0) * 0.6 + n3(d * 13.0) * 0.4;
		col += vec3(0.05, 0.05, 0.1) * band * neb * 1.5;
		col += stars(d, 180.0, 0.93) * 3.0 * star_strength;
		col += stars(d, 420.0, 0.9) * 1.2 * star_strength * (0.5 + band);
		// aurora curtains
		float a = 0.0;
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			float h = 0.25 + fi * 0.05;
			vec2 pp = d.xz / max(d.y + 0.25, 0.05) * (0.6 + fi * 0.08);
			float wave = n3(vec3(pp * 1.4 + vec2(TIME * 0.02, fi), fi * 3.1 + TIME * 0.03));
			float curtain = smoothstep(0.45, 0.8, wave) * smoothstep(0.05, 0.35, d.y) * smoothstep(0.85, 0.35, d.y);
			a += curtain * (1.0 - fi * 0.15);
		}
		vec3 aur = mix(vec3(0.1, 1.0, 0.55), vec3(0.55, 0.25, 1.0), smoothstep(0.2, 0.6, d.y));
		col += aur * a * 0.035 * aurora_strength * smoothstep(0.02, 0.2, d.y);
		// moon
		vec3 md = normalize(moon_dir);
		float mdot = dot(d, md);
		float disc = smoothstep(0.9993, 0.9996, mdot);
		float crater = n3(d * 400.0) * 0.35 + 0.65;
		col = mix(col, vec3(1.0, 0.97, 0.9) * 6.0 * crater, disc);
		col += vec3(0.5, 0.6, 1.0) * pow(max(mdot, 0.0), 180.0) * 0.8;
		col += vec3(0.3, 0.35, 0.6) * pow(max(mdot, 0.0), 12.0) * 0.08;
		// seen from underground (through a discarded / open patch): cave darkness, never stars
		vec3 cave = mix(cave_bottom, cave_top, smoothstep(-0.7, 0.9, d.y)) * 0.25;
		COLOR = mix(col, cave, cave_amount);
	}
}
