shader_type sky;
// Fully PROCEDURAL day sky for daytime levels (Forgotten Veil). No tile / painting shapes at all: every
// sky-painted bg tile is simply sky. Built in view-slope space (s = ray.xy / -ray.z), so every band sits
// in the visible view behind the gameplay, with its own gentle parallax against the camera position:
//   gradient (deep cerulean zenith -> warm pale horizon), sun + bloom, high cirrus, two ridge-noise
//   mountain ranges with snow and aerial perspective, a far band of smooth-silhouette forgotten ruins,
//   forested hills, several depths of fbm cumulus with lit tops / shaded bellies, and a sunlit valley
//   mist bank at the bottom. Radiance pass: sky/ground hemisphere (cave hemisphere underground).

uniform vec3 sun_dir = vec3(-0.3, 0.55, 0.78);
uniform vec3 zenith : source_color = vec3(0.16, 0.42, 0.86);
uniform vec3 mid_sky : source_color = vec3(0.45, 0.66, 0.96);
uniform vec3 horizon : source_color = vec3(0.86, 0.88, 0.9);
uniform vec3 warm : source_color = vec3(1.0, 0.9, 0.78);
uniform float brightness = 1.0;
uniform float cave_amount = 0.0;
uniform vec3 cave_top = vec3(0.5, 0.55, 0.6);
uniform vec3 cave_bottom = vec3(0.05, 0.05, 0.06);
// level-level placement (world units): where the "horizon" of the scenery sits
uniform float scenery_y = -70.0;

float h1(float x) { return fract(sin(mod(x, 1000.0) * 127.1) * 43758.5453); }
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
float fbm(vec2 p) {
	float a = 0.5;
	float v = 0.0;
	for (int i = 0; i < 5; i++) { v += a * n2(p); p = p * 2.03 + 11.7; a *= 0.5; }
	return v;
}
float n1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(h1(i), h1(i + 1.0), f);
}
float fbm1(float x) {
	float a = 0.5;
	float v = 0.0;
	for (int i = 0; i < 5; i++) { v += a * n1(x); x = x * 2.07 + 3.1; a *= 0.5; }
	return v;
}
// sharp alpine ridge line (height above the band base, slope units)
float ridge_h(float x, float amp, float seed) {
	float a = 1.0 - abs(fbm1(x + seed) * 2.0 - 1.0);
	float b = 1.0 - abs(fbm1(x * 2.9 + seed * 3.0) * 2.0 - 1.0);
	return amp * (a * a * 0.75 + b * 0.3);
}

// smooth-primitive forgotten ruins: tapered spires with rounded broken tops, and arches on walls
float ruins_cov(vec2 q, float base, out float lit) {
	lit = 0.0;
	float cov = 0.0;
	float cw = 0.16;
	float ci = floor(q.x / cw);
	for (int k = -1; k <= 1; k++) {
		float c = ci + float(k);
		float r = h1(c * 1.37 + 5.0);
		if (r < 0.45) continue;
		float cx = (c + 0.3 + 0.4 * h1(c + 2.0)) * cw;
		float dx = q.x - cx;
		float gy = base + 0.01 * sin(c * 3.1);
		if (h1(c + 9.0) < 0.6) {
			float hh = mix(0.07, 0.17, h1(c + 4.0));
			float w = mix(0.006, 0.013, h1(c + 6.0)) * mix(1.0, 0.55, clamp((q.y - gy) / hh, 0.0, 1.0));
			float top = gy + hh - 0.012 * n1(dx * 300.0 + c);
			float d = abs(dx) - w;
			float in_s = (1.0 - smoothstep(-0.0015, 0.0015, d)) * (1.0 - smoothstep(top - 0.003, top + 0.003, q.y)) * step(gy - 0.05, q.y);
			cov = max(cov, in_s);
			lit = max(lit, in_s * smoothstep(0.0, -w, dx));
		} else {
			float wl = mix(0.05, 0.09, h1(c + 7.0));
			float hh = mix(0.03, 0.05, h1(c + 8.0));
			if (abs(dx) < wl) {
				float wall = (1.0 - smoothstep(gy + hh - 0.002, gy + hh + 0.002, q.y)) * step(gy - 0.05, q.y);
				float ax = fract(dx / 0.018) - 0.5;
				float arch_r = length(vec2(ax * 0.018, q.y - (gy + hh * 0.35))) - 0.006;
				float hole = (1.0 - smoothstep(-0.001, 0.001, arch_r)) + step(abs(ax * 0.018), 0.006) * step(q.y, gy + hh * 0.35);
				cov = max(cov, wall * (1.0 - clamp(hole, 0.0, 1.0)));
				lit = max(lit, wall * 0.35);
			}
		}
	}
	return cov;
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
		vec2 s = d.xy / max(-d.z, 0.08);                     // view slope
		float vy = s.y + clamp((cam.y - scenery_y) * 0.0006, -0.04, 0.04);   // gentle, bounded parallax: the bands stay in view
		// ---- gradient ----
		vec3 c = mix(horizon, mid_sky, smoothstep(-0.25, 0.1, vy));
		c = mix(c, zenith, smoothstep(0.05, 0.6, vy));
		// warm glow toward the sun side of the horizon
		float sun_side = smoothstep(-0.2, 0.9, dot(normalize(vec2(d.x, 0.2)), normalize(vec2(sd.x, 0.2))));
		c = mix(c, warm, (1.0 - smoothstep(-0.3, 0.15, vy)) * sun_side * 0.35);
		// ---- sun ----
		float sdot = max(dot(d, sd), 0.0);
		c += vec3(1.0, 0.92, 0.78) * (smoothstep(0.9993, 0.9996, sdot) * 8.0 + pow(sdot, 400.0) * 1.2 + pow(sdot, 24.0) * 0.18);
		// ---- high cirrus ----
		{
			vec2 q = vec2(s.x * 1.2 + cam.x * 0.0006 + TIME * 0.002, vy * 9.0);
			float ci = fbm(vec2(q.x * 3.0, q.y * 0.9)) * smoothstep(0.5, 0.75, fbm(vec2(q.x * 0.8, q.y * 0.4) + 7.0));
			c = mix(c, vec3(1.0, 0.99, 0.97), smoothstep(0.35, 0.65, ci) * smoothstep(0.08, 0.35, vy) * 0.45);
		}
		// ---- far cumulus (behind the ranges) ----
		{
			vec2 q = vec2(s.x * 2.0 + cam.x * 0.0012 + TIME * 0.003, vy * 5.0);
			float den = smoothstep(0.58, 0.74, fbm(q * vec2(1.0, 1.6)) + 0.06 * (1.0 - smoothstep(-0.05, 0.25, vy)));
			float lit = clamp(0.5 + (fbm(q * vec2(1.0, 1.6) + vec2(0.0, 0.08)) - fbm(q * vec2(1.0, 1.6) - vec2(0.0, 0.08))) * 3.0, 0.0, 1.0);
			vec3 cc = mix(vec3(0.72, 0.78, 0.9), vec3(1.0, 0.98, 0.95), lit);
			c = mix(c, mix(cc, horizon, 0.3), den * smoothstep(-0.2, 0.0, vy) * 0.8);
		}
		// ---- far mountain range ----
		{
			float x = s.x * 3.0 + cam.x * 0.004;
			float base = -0.1;
			float top = base + ridge_h(x, 0.19, 1.0);
			float cov = smoothstep(-0.002, 0.002, top - vy);
			if (cov > 0.0) {
				float below = top - vy;
				// facets: slope of the ridge over a wide window, bent by 2D noise so faces taper downwards
				float slope = ridge_h(x + 0.08, 0.19, 1.0) - ridge_h(x - 0.08, 0.19, 1.0);
				// 2D relief: ridges branch down from the crest (sunlit east / shaded west), fading with depth
				vec2 rq = vec2(x * 5.0, below * 7.0);
				float rel = fbm(rq + vec2(fbm(rq * 0.7) * 1.5, 0.0));
				float relx = fbm(rq + vec2(0.05, 0.0) + vec2(fbm((rq + vec2(0.05, 0.0)) * 0.7) * 1.5, 0.0)) - rel;
				float face = smoothstep(-0.03, 0.03, mix(slope, relx, smoothstep(0.0, 0.06, below)));
				float snow = (1.0 - smoothstep(0.008, 0.03 + 0.025 * fbm(vec2(x * 4.0, 1.0)), below)) * smoothstep(base + 0.1, base + 0.14, top);
				float gully = smoothstep(0.55, 0.8, fbm(vec2(x * 9.0, below * 9.0)));
				vec3 rock = mix(vec3(0.2, 0.26, 0.45), vec3(0.5, 0.55, 0.72), face) * (1.0 - gully * 0.2);
				vec3 sn = mix(vec3(0.72, 0.78, 0.92), vec3(1.0, 0.98, 0.95), face) * (1.0 - gully * 0.08);
				vec3 mc = mix(rock, sn, snow);
				mc = mix(mc, horizon, 0.15 + 0.3 * smoothstep(0.08, 0.35, below));   // aerial perspective to the base
				c = mix(c, mc, cov);
			}
		}
		// ---- near mountain range ----
		{
			float x = s.x * 2.2 + cam.x * 0.008 + 11.0;
			float base = -0.15;
			float top = base + ridge_h(x, 0.12, 5.0);
			float cov = smoothstep(-0.002, 0.002, top - vy);
			if (cov > 0.0) {
				float below = top - vy;
				float slope = ridge_h(x + 0.08, 0.12, 5.0) - ridge_h(x - 0.08, 0.12, 5.0);
				// 2D relief: ridges branch down from the crest (sunlit east / shaded west), fading with depth
				vec2 rq = vec2(x * 5.0, below * 7.0);
				float rel = fbm(rq + vec2(fbm(rq * 0.7) * 1.5, 0.0));
				float relx = fbm(rq + vec2(0.05, 0.0) + vec2(fbm((rq + vec2(0.05, 0.0)) * 0.7) * 1.5, 0.0)) - rel;
				float face = smoothstep(-0.03, 0.03, mix(slope, relx, smoothstep(0.0, 0.06, below)));
				float snow = (1.0 - smoothstep(0.006, 0.025 + 0.02 * fbm(vec2(x * 4.0, 2.0)), below)) * smoothstep(base + 0.07, base + 0.1, top);
				vec3 rock = mix(vec3(0.16, 0.22, 0.38), vec3(0.44, 0.5, 0.66), face);
				vec3 sn = mix(vec3(0.68, 0.74, 0.9), vec3(1.0, 0.97, 0.93), face);
				vec3 mc = mix(rock, sn, snow);
				mc = mix(mc, horizon, 0.05 + 0.3 * smoothstep(0.06, 0.3, below));
				c = mix(c, mc, cov);
			}
		}
		// ---- far band of forgotten ruins (smooth primitives, strongly hazed) ----
		{
			vec2 q = vec2(s.x * 1.6 + cam.x * 0.012, vy);
			float lit;
			float rc = ruins_cov(q, -0.19, lit);
			vec3 rcol = mix(vec3(0.5, 0.56, 0.68), vec3(0.72, 0.72, 0.74), lit);
			c = mix(c, mix(rcol, horizon, 0.45), rc);
		}
		// ---- forested hills ----
		{
			float x = s.x * 1.4 + cam.x * 0.02 + 3.0;
			float hill = -0.22 + 0.035 * fbm1(x * 2.0 + 9.0);
			float trees = 0.012 * pow(abs(sin(x * 90.0 + fbm1(x * 20.0) * 3.0)), 0.5) * smoothstep(0.35, 0.6, fbm1(x * 5.0 + 1.0));
			float cov = smoothstep(-0.002, 0.002, hill + trees - vy);
			vec3 hc = mix(vec3(0.28, 0.42, 0.34), vec3(0.4, 0.52, 0.42), fbm(vec2(x * 30.0, vy * 40.0)));
			c = mix(c, mix(hc, horizon, 0.4), cov);
		}
		// ---- nearer cumulus (in front of the far scenery) ----
		{
			vec2 q = vec2(s.x * 1.1 + cam.x * 0.003 + TIME * 0.006, vy * 3.2 + 4.0);
			float f = fbm(q * vec2(1.0, 1.7));
			float den = smoothstep(0.62, 0.76, f) * smoothstep(-0.12, 0.05, vy) * (1.0 - smoothstep(0.35, 0.6, vy));
			float up = fbm((q + vec2(0.0, 0.06)) * vec2(1.0, 1.7));
			float lit = clamp(0.55 + (f - up) * 4.0, 0.0, 1.0);
			vec3 cc = mix(vec3(0.66, 0.72, 0.86), vec3(1.05, 1.02, 0.98), lit);
			c = mix(c, cc, den * 0.9);
		}
		// ---- sunlit valley mist bank ----
		{
			float x = s.x * 1.2 + cam.x * 0.025 + TIME * 0.004;
			float billow = 0.03 * fbm1(x * 6.0) + 0.012 * fbm1(x * 25.0);
			float bank = 1.0 - smoothstep(-0.26 + billow, -0.21 + billow, vy);
			float lit = smoothstep(-0.34, -0.22 + billow, vy);
			c = mix(c, mix(vec3(0.78, 0.82, 0.9), vec3(1.02, 0.99, 0.94), lit), bank);
		}
		COLOR = c * brightness;
	}
}
