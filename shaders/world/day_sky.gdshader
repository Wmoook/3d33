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
uniform sampler2D masks : filter_linear, repeat_disable;   // R clouds, G mountain ranges (soft)
uniform sampler2D depth_mask : filter_linear, repeat_disable;  // R grounded mass, G fall-away below it
uniform vec2 sun_paint = vec2(70.0, 16.0);   // where the sun sits in the painting (tile space)
uniform float parallax = 0.6;
uniform float spread = 1.3;
uniform float brightness = 0.82;
uniform vec3 zenith = vec3(0.06, 0.2, 0.72);
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

float fbm(vec2 p) {
	float a = 0.5;
	float v = 0.0;
	for (int i = 0; i < 5; i++) { v += a * n2(p); p = p * 2.03 + 11.7; a *= 0.5; }
	return v;
}


// ---------- far / mid landscape ----------
// signed coverage of a far mountain ridge (level tile space of that layer, y down)
float ridge_line(float x, float base, float amp, float freq, float seed) {
	// sharp alpine peaks: sum of pointed (abs) waves at two scales + fine jagged noise
	float a = 1.0 - abs(fbm(vec2(x * freq, seed)) * 2.0 - 1.0);
	float b = 1.0 - abs(fbm(vec2(x * freq * 3.1, seed + 3.0)) * 2.0 - 1.0);
	return base - amp * (a * a * 0.8 + b * 0.35) - fbm(vec2(x * 0.6, seed + 9.0)) * 1.5;
}

// distant forgotten ruins (spires, arches, towers) + forested hills: returns coverage, and (out) a
// 0..1 'lit' term (sunward faces) and a waterfall streak mask
float ruins(vec2 p, float base, out float lit, out float fall) {
	lit = 0.0;
	fall = 0.0;
	float hill = base - 6.0 * fbm(vec2(p.x * 0.03, 11.0)) - 3.0 * fbm(vec2(p.x * 0.11, 3.0));
	float cov = smoothstep(-0.4, 0.4, p.y - hill);
	// tree crowns on the hill line
	float crowns = hill - 1.6 * pow(abs(sin(p.x * 0.9 + fbm(vec2(p.x * 0.2, 1.0)) * 4.0)), 0.6);
	cov = max(cov, smoothstep(-0.3, 0.3, p.y - crowns) * smoothstep(0.35, 0.6, fbm(vec2(p.x * 0.07, 8.0))));
	float cellw = 26.0;
	float ci = floor(p.x / cellw);
	for (int k = -1; k <= 1; k++) {
		float c = ci + float(k);
		float hsh = h2(vec2(c, 17.0));
		if (hsh < 0.35) continue;
		float cx = (c + 0.3 + 0.4 * h2(vec2(c, 3.0))) * cellw;
		float gy = base - 6.0 * fbm(vec2(cx * 0.03, 11.0));
		float kind = h2(vec2(c, 29.0));
		float dx = p.x - cx;
		if (kind < 0.45) {
			// broken spire: tapering shaft with a jagged, broken top and window slits
			float hh = mix(16.0, 34.0, h2(vec2(c, 5.0)));
			float top = gy - hh + 3.0 * fbm(vec2(dx * 0.8, c));
			float halfw = mix(1.6, 3.2, h2(vec2(c, 7.0))) * mix(1.0, 0.6, clamp((gy - p.y) / hh, 0.0, 1.0));
			float inside = step(abs(dx), halfw) * step(top, p.y) * step(p.y, gy + 2.0);
			float slit = step(abs(dx), 0.25) * step(0.6, fract(p.y * 0.18)) * step(top + 3.0, p.y);
			inside *= 1.0 - slit;
			cov = max(cov, inside);
			lit = max(lit, inside * step(dx, -halfw * 0.2));
		} else if (kind < 0.75) {
			// arcade of broken arches on a wall
			float hh = mix(7.0, 12.0, h2(vec2(c, 6.0)));
			float wl = mix(14.0, 22.0, h2(vec2(c, 8.0)));
			if (abs(dx) < wl * 0.5) {
				float top = gy - hh - 1.5 * step(0.5, h2(vec2(floor(dx * 0.7), c)));
				float wall = step(top, p.y) * step(p.y, gy + 2.0);
				float ax = fract(dx / 4.0) - 0.5;
				float arch = step(length(vec2(ax * 4.0, (p.y - (gy - hh * 0.45)) * 0.9)), 1.4) + step(abs(ax * 4.0), 1.4) * step(gy - hh * 0.45, p.y);
				cov = max(cov, wall * (1.0 - clamp(arch, 0.0, 1.0)));
				lit = max(lit, wall * 0.3);
			}
		} else {
			// tower draped in vines with a waterfall pouring off its ledge
			float hh = mix(18.0, 26.0, h2(vec2(c, 9.0)));
			float halfw = 3.2;
			float top = gy - hh;
			float cren = step(0.5, fract(dx * 0.6)) * 1.0;
			float inside = step(abs(dx), halfw) * step(top - cren, p.y) * step(p.y, gy + 2.0);
			cov = max(cov, inside);
			lit = max(lit, inside * step(dx, -0.5));
			float fx = cx + halfw + 1.2;
			fall = max(fall, (1.0 - smoothstep(0.3, 0.9, abs(p.x - fx))) * step(top + hh * 0.35, p.y) * step(p.y, gy + 1.0));
		}
	}
	return clamp(cov, 0.0, 1.0);
}

float inside_level(vec2 uv) {
	return step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
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
		vec3 c = g;
		float inside = smoothstep(0.0, 0.03, uv.x) * smoothstep(1.0, 0.97, uv.x)
			* smoothstep(0.0, 0.03, uv.y) * smoothstep(1.0, 0.97, uv.y);
		vec3 haze = mix(horizon_haze, vec3(0.9, 0.86, 0.8), 0.25);   // warm pale horizon
		// sun disc + bloom + raking god rays (painted sun position, parallaxed like the far layer)
		vec2 sp = p - sun_paint;
		float sd2 = length(sp);
		c += vec3(1.0, 0.92, 0.75) * (smoothstep(3.2, 2.6, sd2) * 6.0 + exp(-sd2 * 0.12) * 0.35 + exp(-sd2 * 0.03) * 0.12);
		float ang = atan(sp.y, sp.x);
		float rays = pow(n2(vec2(ang * 9.0, TIME * 0.05)), 3.0) * smoothstep(2.0, 10.0, sd2) * exp(-sd2 * 0.07);   // short crown of rays around the disc only
		c += vec3(1.0, 0.9, 0.7) * rays * 0.25;
		// high wispy cirrus
		float ci = fbm(vec2(p.x * 0.012 + TIME * 0.004, p.y * 0.09)) ;
		float cirrus = smoothstep(0.55, 0.8, ci) * smoothstep(0.55, 0.1, uv.y) * smoothstep(0.4, 0.8, fbm(vec2(p.x * 0.05, p.y * 0.8)));
		c = mix(c, vec3(1.0, 0.99, 0.97), cirrus * 0.35);
		// FAR: two procedural snowy ranges + the painting's own ranges, aerial perspective
		vec3 cam2 = POSITION;
		for (int L = 0; L < 2; L++) {
			float pf = L == 0 ? 0.15 : 0.3;
			vec2 wl = anchor + (cam2.xy - anchor) * pf + (hit - cam2.xy) * (L == 0 ? 1.6 : 1.35);
			vec2 pl = vec2(wl.x, -wl.y);
			float top = ridge_line(pl.x, L == 0 ? 112.0 : 126.0, L == 0 ? 58.0 : 36.0, L == 0 ? 0.02 : 0.034, float(L) * 7.0);
			float cov = smoothstep(-0.25, 0.25, pl.y - top);
			if (cov > 0.0) {
				float slope = ridge_line(pl.x + 0.5, L == 0 ? 112.0 : 126.0, L == 0 ? 58.0 : 36.0, L == 0 ? 0.02 : 0.034, float(L) * 7.0) - top;
				float depthb = pl.y - top;
				// sunlit east faces / shaded west faces near the crest, fading to even tone lower down
				float face = smoothstep(-0.4, 0.4, slope * 2.0 + (fbm(pl * 0.35) - 0.5) * 0.6);
				float sunlit = mix(0.55, mix(0.25, 1.0, face), exp(-depthb * 0.07));
				float snow = step(depthb, 7.0 + fbm(vec2(pl.x * 0.5, 2.0)) * 6.0) * step(top, 110.0 - float(L) * 6.0);
				float gully = smoothstep(0.55, 0.8, fbm(vec2(pl.x * 0.4 + pl.y * 0.2, pl.y * 0.3)));
				vec3 rock = mix(vec3(0.04, 0.06, 0.13), vec3(0.14, 0.18, 0.32), sunlit) * (1.0 - gully * 0.25);
				vec3 sn = mix(vec3(0.55, 0.64, 0.86), vec3(1.0, 0.97, 0.93), sunlit) * (1.0 - gully * 0.15);
				vec3 mcol = mix(rock, sn, snow);
				mcol = mix(mcol, horizon_haze, L == 0 ? 0.35 : 0.15);
				mcol = mix(mcol, horizon_haze, smoothstep(10.0, 45.0, pl.y - top) * 0.5);   // foot dissolves into haze
				c = mix(c, mcol, cov);
			}
		}
		// the painting's snowy ranges (kept where the painting has them)
		vec2 muv = p / level_size;
		float mn = texture(masks, muv).g + (fbm(p * 0.18) - 0.5) * 0.35;
		float mm = smoothstep(0.42, 0.5, mn) * inside;
		if (mm > 0.0) {
			float above = texture(masks, muv - vec2(0.0, 2.2 / level_size.y)).g + (fbm((p - vec2(0.0, 2.2)) * 0.18) - 0.5) * 0.35;
			float snow = smoothstep(0.55, 0.3, above) * smoothstep(0.35, 0.6, fbm(p * 0.5));
			float ridge2 = abs(fbm(vec2(p.x * 0.25, p.y * 0.12)) - 0.5) * 2.0;
			vec3 rock = mix(vec3(0.36, 0.42, 0.62), vec3(0.55, 0.62, 0.85), ridge2);
			vec3 mc = mix(rock, vec3(0.97, 0.97, 1.0), max(snow, 0.25 * ridge2));
			mc = mix(mc, haze, 0.3);
			c = mix(c, mc, mm);
		}
		// MID: hazy forgotten ruins, forested hills and distant waterfalls
		{
			vec2 wm = anchor + (cam2.xy - anchor) * 0.5 + (hit - cam2.xy) * 1.15;
			vec2 pm = vec2(wm.x, -wm.y);
			float lit; float fall;
			float rc = ruins(pm, 160.0, lit, fall);
			vec3 rcol = mix(vec3(0.34, 0.42, 0.55), vec3(0.62, 0.64, 0.66), lit * 0.8);
			rcol = mix(rcol, vec3(0.25, 0.4, 0.33), smoothstep(-1.0, 3.0, pm.y - (160.0 - 6.0 * fbm(vec2(pm.x * 0.03, 11.0)))) * 0.5);
			rcol = mix(rcol, haze, 0.28);
			c = mix(c, rcol, rc);
			float fs = fall * (0.6 + 0.4 * n2(vec2(pm.x * 3.0, pm.y * 0.5 - TIME * 3.0)));
			c = mix(c, vec3(0.85, 0.92, 1.0), fs * 0.7);
			// valley mist below the mid layer
			c = mix(c, haze, smoothstep(166.0, 195.0, pm.y) * 0.75);
		}
		// soft cumulus: blurred painted cloud mask as density hint + billowing fbm, sun-lit tops,
		// shaded bellies, slow drift
		vec2 drift = vec2(TIME * 0.25, 0.0);
		vec2 cq = p + drift;
		float cd = texture(masks, (p + drift * 0.15) / level_size).r;
		float bill = fbm(cq * 0.22) * 0.7 + fbm(cq * 0.6) * 0.3;
		float dens = smoothstep(0.08, 0.5, cd * 1.3 + (bill - 0.5) * 0.55) * inside;
		if (dens > 0.0) {
			float up = texture(masks, (p + drift * 0.15 - vec2(0.0, 1.5)) / level_size).r;
			float lit2 = clamp(0.55 + (cd - up) * 1.6 + (bill - 0.5) * 0.5, 0.0, 1.0);
			vec3 cc = mix(vec3(0.62, 0.68, 0.84), vec3(1.0, 0.98, 0.94), lit2);
			c = mix(c, cc, dens * 0.95);
		}
		// NEAR DEPTH: the level's own masses continue back into the backdrop - receding silhouettes at
		// increasing depth, and rock falling away beneath every mass into mist
		for (int S = 2; S >= 0; S--) {   // far to near
			float D = S == 0 ? 3.0 : (S == 1 ? 8.0 : 18.0);
			float tt = (cam2.z + D) / max(-d.z, 0.05);
			vec2 hp = cam2.xy + d.xy * tt;
			vec2 lp = vec2(hp.x, -hp.y) / level_size;
			vec2 dm = texture(depth_mask, lp).rg;
			float body = smoothstep(0.35, 0.6, dm.r);
			// backing shell: rock / ruin walls stepping back behind every structure, broken, fading to mist
			float sh = S == 0 ? 0.0 : smoothstep(0.18 + 0.1 * float(S), 0.4 + 0.1 * float(S), dm.g + (fbm(hp * 0.12) - 0.5) * 0.3);
			float cover = max(body, sh);
			float a = cover * (S == 0 ? 0.7 : (S == 1 ? 0.95 : 0.8)) * inside_level(lp);
			// shell material: weathered rock strata with moss, cooler and hazier with depth
			float strata = sin(hp.y * 1.3 + fbm(hp * 0.2) * 3.0) * 0.5 + 0.5;
			float moss = smoothstep(0.5, 0.8, fbm(hp * 0.3 + 4.0));
			vec3 rockc = mix(vec3(0.07, 0.068, 0.065), vec3(0.15, 0.14, 0.125), strata);   // linear
			rockc = mix(rockc, vec3(0.05, 0.1, 0.03), moss * 0.6);
			// wet grotto cliff behind the waterfall
			float wet = (1.0 - smoothstep(6.0, 20.0, abs(hp.x - 135.0))) * step(120.0, -hp.y) * step(-hp.y, 180.0);
			rockc = mix(rockc, vec3(0.02, 0.045, 0.06), wet * 0.7);
			float sunf = smoothstep(-0.2, 0.8, fbm(hp * 0.07));
			rockc *= mix(0.7, 1.15, sunf);
			vec3 dcol = mix(rockc, haze, S == 2 ? 0.45 : (S == 1 ? 0.22 : 0.1));
			dcol = mix(dcol, haze, (1.0 - smoothstep(0.4, 0.8, dm.g)) * 0.3 * float(S > 0));
			c = mix(c, dcol, clamp(a, 0.0, 1.0));
		}
		float wisp = n2(vec2(w.x * 0.04 + TIME * 0.01, w.y * 0.1)) * n2(vec2(w.x * 0.09 - TIME * 0.006, w.y * 0.18 + 3.0));
		c = mix(c, vec3(0.95, 0.97, 1.0), smoothstep(0.25, 0.8, wisp) * 0.1);
		float s = max(dot(d, sd), 0.0);
		c += vec3(1.0, 0.85, 0.6) * (pow(s, 6.0) * 0.1 + pow(s, 60.0) * 0.25);
		COLOR = c * brightness;
	}
}
