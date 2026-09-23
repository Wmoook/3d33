// Forgotten Veil background SPACES (WorldBgSpace): shading of recessed back walls by region class, with a
// continuous regional tone instead of per-tile bg colour squares. Include after terrain/pbr helpers.
// bg_space_tex (RGBA8, per tile): rgb regional tone (sRGB), a = class * 16 + deep * 15.
// Classes: 1 earth cave, 2 forest undergrowth, 3 stone hall, 4 sandstone hall, 5 water grotto, 6 deep.

uniform sampler2D bg_space_tex : filter_linear, repeat_disable;
uniform float bg_space_on = 0.0;
uniform sampler2D bg_space_aux : filter_linear, repeat_disable;   // r dist to solid /8, g dist to open sky /24

float bgs_h(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float bgs_n(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bgs_h(i), bgs_h(i + vec2(1.0, 0.0)), f.x), mix(bgs_h(i + vec2(0.0, 1.0)), bgs_h(i + vec2(1.0, 1.0)), f.x), f.y);
}
float bgs_fbm(vec2 p) {
	return bgs_n(p) * 0.5 + bgs_n(p * 2.03 + 7.1) * 0.3 + bgs_n(p * 4.1 + 3.3) * 0.2;
}
vec3 bgs_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// class at tile p (nearest), tone + deep (bilinear, continuous)
int bg_space_class(vec2 p, vec2 level_sz) {
	vec4 t = texelFetch(bg_space_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(level_sz) - 1), 0);
	return int(t.a * 255.0 + 0.5) / 16;
}

// Regional tone (linear) at tile-space p, continuous (bilinear).
vec3 bg_space_tone(vec2 p, vec2 level_sz) {
	return bgs_lin(texture(bg_space_tex, p / level_sz).rgb);
}
// 0..1 "deeper / darker" weight at p.
float bg_space_deep(vec2 p, vec2 level_sz) {
	vec4 t = texelFetch(bg_space_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(level_sz) - 1), 0);
	return mod(t.a * 255.0 + 0.5, 16.0) / 15.0;
}
// Tint for props painted from a source tile colour (linear): the regional tone, keeping only +-10% of the
// source tile's luminance as variation (no per-tile colour checkerboard).
vec3 bg_space_tint(vec2 p, vec2 level_sz, vec3 base_col) {
	vec3 tone = bg_space_tone(p, level_sz);
	float lt = max(dot(tone, vec3(0.3, 0.55, 0.15)), 1e-3);
	float lb = dot(base_col, vec3(0.3, 0.55, 0.15));
	return tone * clamp(mix(1.0, lb / lt, 0.25), 0.9, 1.1);
}

// Shades a back wall at tile-space p (x right, y down). Returns albedo (linear); writes normal (world) and ao.
vec3 bg_space_shade(vec2 p, vec2 level_sz, vec3 n_in, out vec3 n_out, out float ao) {
	vec4 t = texture(bg_space_tex, (p) / level_sz);
	int c = bg_space_class(p, level_sz);
	float dp = mod(t.a * 255.0 + 0.5, 16.0) / 15.0;
	vec3 tone = bgs_lin(t.rgb);
	vec3 alb = tone;
	vec3 n = n_in;
	ao = 1.0;
	if (c == 1) {
		// earth cave: horizontal strata that wander, packed soil with pebbles, root threads, damp dark
		float wob = bgs_fbm(vec2(p.x * 0.08, p.y * 0.3)) * 2.2;
		float sy = p.y * 1.1 + wob;
		float band = fract(sy);
		float layer = bgs_h(vec2(floor(sy), 3.0));
		float ledge = smoothstep(0.0, 0.1, band) * (1.0 - smoothstep(0.75, 1.0, band));
		float grain = bgs_fbm(p * vec2(1.4, 3.0));
		// the painted earth tones are very dark: lift them into a readable packed-earth range
		vec3 earth = mix(vec3(0.16, 0.1, 0.055), vec3(0.24, 0.16, 0.09), bgs_fbm(p * 0.3));
		vec3 base = mix(earth, tone * 3.0, 0.35);
		alb = base * mix(0.7, 1.25, layer) * mix(0.8, 1.15, grain) * mix(0.7, 1.0, ledge);
		float root = smoothstep(0.93, 0.99, bgs_n(vec2(p.x * 2.6 + bgs_fbm(p * 0.5) * 3.0, p.y * 0.35)));
		alb = mix(alb, tone * 0.45, root * 0.7);
		n = normalize(n + vec3((grain - 0.5) * 0.3, (band < 0.12 ? 0.6 : (band > 0.85 ? -0.4 : 0.0)), 0.0));
	} else if (c == 2) {
		// forest undergrowth: layered dark leaf masses over trunk silhouettes, deep green gloom
		float leaves = bgs_fbm(p * 0.9 + vec2(0.0, bgs_n(p * 0.2) * 2.0));
		float clumps = smoothstep(0.42, 0.62, leaves);
		float trunkx = abs(fract(p.x / 5.3 + bgs_n(vec2(p.y * 0.05, 1.0)) * 0.4) - 0.5);
		float trunk = 1.0 - smoothstep(0.05, 0.09, trunkx);
		vec3 dark = tone * 0.45;
		alb = mix(dark, tone * 1.15, clumps);
		alb = mix(alb, vec3(0.12, 0.08, 0.05) * 0.8, trunk * (1.0 - clumps) * 0.8);
		n = normalize(n + vec3((leaves - 0.5) * 0.8, (bgs_fbm(p * 0.9 + 0.3) - 0.5) * 0.8, 0.0));
		ao = mix(0.6, 1.0, clumps);
	} else if (c == 3 || c == 4) {
		// halls: coursed ashlar, pilasters every 6 tiles, a string course every 5 rows, darker plinth
		vec2 q = p + vec2(bgs_n(p * 0.5), bgs_n(p * 0.5 + 3.0)) * 0.15;
		float row = floor(q.y * 2.0);
		vec2 bq = vec2(q.x * 0.75 + bgs_h(vec2(row, 1.7)) * 3.0, q.y * 2.0);
		vec2 bi = floor(bq);
		vec2 bf = bq - bi;
		float joint = min(min(bf.x, 1.0 - bf.x) * 1.33, min(bf.y, 1.0 - bf.y));
		float jl = 1.0 - smoothstep(0.03, 0.1, joint);
		vec3 stone = c == 4 ? tone * 1.05 : mix(tone, vec3(dot(tone, vec3(0.33))), 0.35);
		alb = stone * mix(0.82, 1.12, bgs_h(bi + 7.0)) * (1.0 - jl * 0.45);
		float px = fract((p.x + 0.5) / 6.0) * 6.0;
		float pil = 1.0 - smoothstep(0.85, 0.95, px);
		alb = mix(alb, stone * 1.18, pil * 0.6);
		float sc = 1.0 - smoothstep(0.0, 0.12, abs(fract(p.y / 5.0) - 0.5) - 0.44);
		alb = mix(alb, stone * 1.25, sc * 0.5);
		n = normalize(n + vec3(-(bf.x - 0.5), (bf.y - 0.5), 0.0) * jl * 0.5 + vec3((px < 0.1 ? -0.5 : (px > 0.85 && px < 0.95 ? 0.5 : 0.0)), 0.0, 0.0));
	} else if (c == 5) {
		// water grotto: wet dark rock, blue tint, glints
		float g = bgs_fbm(p * 1.2);
		alb = tone * mix(0.6, 1.1, g);
		n = normalize(n + vec3(g - 0.5, bgs_fbm(p * 1.2 + 5.0) - 0.5, 0.0) * 0.6);
	} else {
		// deep alcove: near-black recess, faint rock grain
		alb = tone * 0.35 * mix(0.8, 1.15, bgs_fbm(p * 1.5));
	}
	// the painter's darker areas go into shadow
	ao *= mix(1.0, 0.55, dp);
	n_out = n;
	return alb;
}

// Interior light field at p: x = distance to solid (tiles), y = distance to open sky / window (tiles).
vec2 bg_space_dist(vec2 p, vec2 level_sz) {
	vec2 a = texture(bg_space_aux, p / level_sz).rg;
	return vec2(a.r * 8.0, a.g * 24.0);
}

// Dramatic interior lighting for a recessed back wall: light spills in from the nearest openings (warm
// daylight, falling off over ~6 tiles), the depths fall into a class-tinted gloom, corners against the
// surrounding mass are occluded. Modifies albedo, returns emission to add.
vec3 bg_space_light(vec2 p, vec2 level_sz, int cls, inout vec3 albedo, inout float ao) {
	vec2 d = bg_space_dist(p, level_sz);
	float spill = exp(-d.y / 6.0);
	float corner = mix(0.4, 1.0, smoothstep(0.0, 2.5, d.x));
	float wob = bgs_fbm(p * 0.15);
	vec3 gloom = albedo * 0.45 + (cls == 2 ? vec3(0.012, 0.03, 0.016) : (cls == 5 ? vec3(0.008, 0.02, 0.035) : vec3(0.02, 0.014, 0.01)));
	float fog = (1.0 - spill) * mix(0.25, 0.5, wob) * (cls == 6 ? 1.4 : 1.0);
	albedo = mix(albedo, gloom, clamp(fog, 0.0, 0.6));
	ao *= corner;
	vec3 day = vec3(1.0, 0.86, 0.62);
	return albedo * day * spill * 0.8 + day * spill * spill * 0.03;
}

// Blocky strata ledges (FV earth caves): WorldDepth recesses each back-wall tile to one of a few steps
// (depth_tex .g = where the tile's volume starts). Lit lips where the band above is deeper, shadowed
// overhangs where it is nearer, darker deeper steps: the carved relief reads at a glance.
vec3 bg_space_ledges(vec2 p, sampler2D dtex, vec2 level_sz, vec3 albedo) {
	ivec2 t = clamp(ivec2(floor(p)), ivec2(0), ivec2(level_sz) - 1);
	float s0 = texelFetch(dtex, t, 0).g;
	float su = texelFetch(dtex, clamp(t + ivec2(0, -1), ivec2(0), ivec2(level_sz) - 1), 0).g;
	float sd = texelFetch(dtex, clamp(t + ivec2(0, 1), ivec2(0), ivec2(level_sz) - 1), 0).g;
	float fy = fract(p.y);
	vec3 a = albedo;
	if (su > 2.5 && su < 9.0) {
		float lip = 1.0 - smoothstep(0.0, 0.22, fy);
		if (su > s0 + 0.3) {
			a *= 1.0 + lip * 0.9;        // the ledge lip catches the light from above
		} else if (su < s0 - 0.3) {
			a *= 1.0 - (1.0 - smoothstep(0.0, 0.45, fy)) * 0.6;   // under an overhang: shadow
		}
	}
	if (sd > 2.5 && sd < 9.0 && sd < s0 - 0.3) {
		a *= 1.0 - smoothstep(0.75, 1.0, fy) * 0.35;   // the step below comes forward: contact shadow
	}
	return a;
}
