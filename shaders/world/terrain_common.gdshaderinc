// Shared terrain field functions (height profile + region sampling). World units: 1 tile = 1.0,
// world (x, y) -> tile space p = (x, -y) (y down, like EE).

uniform sampler2D sdf_tex : filter_linear, repeat_disable;      // RGBAH: open_fg, open_wall, raw_fg, raw_wall
uniform sampler2D field_tex : filter_linear, repeat_disable;    // RGBA8 (1 texel / tile): r sky, g cave depth mod, b glow, a surface
uniform sampler2D relief_tex : filter_linear, repeat_disable;   // RG8 per tile: r = height offset (+0.5), g = relief amplitude
uniform vec2 level_size = vec2(400.0, 200.0);

const float SPT = 8.0;

// ---------- noise ----------
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
// Quintic gradient noise, C2 continuous, range ~[-0.7, 0.7].
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(hash22(i), f);
	float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm2(vec2 p) {
	return gnoise(p) + 0.5 * gnoise(p * 2.03 + 17.1);
}
float fbm3(vec2 p) {
	return gnoise(p) + 0.5 * gnoise(p * 2.03 + 17.1) + 0.25 * gnoise(p * 4.01 - 7.3);
}
// Ridged noise for rocky strata.
float ridge(vec2 p) {
	return 1.0 - abs(gnoise(p) * 1.4);
}

// Rounded cobbles / boulders: 1 at cell centres falling to 0 at the cell borders (smooth F2-F1).
float cobbles(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g) * 0.4 + 0.5;
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return smoothstep(0.0, 0.35, d2 - d1);
}

// Round leaf-clump domes (F1 based).
float domes(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	float b = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g) * 0.45 + 0.5;
			float r = 0.55 + 0.25 * hash12(i + g + 7.0);
			float d = length(g + o - f) / r;
			b = max(b, sqrt(max(0.0, 1.0 - d * d)));
		}
	}
	return b;
}

// ---------- smooth (B-spline) sampling of the SDF texture ----------
vec4 sdf_bicubic(vec2 p) {
	// p in tile space; texel centres at (i+.5)/SPT
	vec2 tsize = level_size * SPT;
	vec2 st = p * SPT - 0.5;
	vec2 i = floor(st);
	vec2 f = st - i;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 h0 = (w1 / g0) - 0.5 + i;
	vec2 h1 = (w3 / g1) + 1.5 + i;
	vec4 t00 = textureLod(sdf_tex, (vec2(h0.x, h0.y) + 0.5) / tsize, 0.0);
	vec4 t10 = textureLod(sdf_tex, (vec2(h1.x, h0.y) + 0.5) / tsize, 0.0);
	vec4 t01 = textureLod(sdf_tex, (vec2(h0.x, h1.y) + 0.5) / tsize, 0.0);
	vec4 t11 = textureLod(sdf_tex, (vec2(h1.x, h1.y) + 0.5) / tsize, 0.0);
	vec4 r = g0.y * (g0.x * t00 + g1.x * t10) + g1.y * (g0.x * t01 + g1.x * t11);
	return min(r, vec4(p.y + 0.02));   // above the level top: open sky
}

vec4 sdf_linear(vec2 p) {
	return min(textureLod(sdf_tex, p / level_size, 0.0), vec4(p.y + 0.02));
}

float round_prof(float t) {
	float u = 1.0 - clamp(t, 0.0, 1.0);
	return sqrt(max(1.0 - u * u, 0.0));
}

// Layer depths
const float Z_FG_TOP = 0.62;
const float Z_BG = -1.9;

float cave_depth(vec2 p, vec4 fld) {
	// deep cave back wall; the sky region is shallower (and discarded in the fragment shader)
	float n = fbm2(p * 0.11) * 0.9 + ridge(p * 0.045 + 3.0) * 0.7;
	return mix(-4.6 + n, -3.0, fld.r);
}

// Full height field z(p). `s` = sdf sample (open_fg, open_wall, raw_fg, raw_wall).
float height_from(vec2 p, vec4 s, vec4 fld) {
	float sf = s.x;
	float sw = s.y;
	// foreground front surface: rounded pillow bevel + gentle bulge + rocky relief
	float s_front = max(min(sf, s.z), sf - 0.32);
	vec2 rel = textureLod(relief_tex, p / level_size, 0.0).rg;
	float hoff = rel.r - 0.5;
	float amp = rel.g * 2.0;
	// foliage (amp > 1.6): dense small round leaf clumps instead of cobbles
	float leafy = smoothstep(1.5, 1.9, amp);
	float cob = leafy > 0.5 ? domes(p * 2.0 + fbm2(p * 0.8) * 0.4) * 1.2 : cobbles(p * 0.9 + fbm2(p * 0.3) * 0.6);
	float relief = (cob * mix(0.2, 0.12, leafy) + fbm3(p * 0.9) * 0.07) * min(amp, 1.5) + gnoise(p * 0.23 + 5.0) * 0.12
		+ hoff * smoothstep(0.0, 0.45, s_front);
	// (s_front: the main bevel follows the SMOOTH outline so staircases read as slopes; the true grid
	// footprint keeps a low lip so every solid tile is still covered at the gameplay plane)
	float zf = Z_FG_TOP * round_prof(s_front / 0.5) + 0.26 * smoothstep(0.5, 3.5, s.w)
		+ relief * smoothstep(0.0, 0.8, s_front);
	zf = max(zf, 0.13 * round_prof(sf / 0.14));
	if (sf >= 0.0) {
		return zf;
	}
	// background wall (tiny enclosed pockets sit much shallower: pits in the rock)
	float zbase = mix(Z_BG, -0.75, fld.g);
	float zb = zbase + 0.42 * round_prof(sw / 0.45) + (fbm2(p * 0.7) * 0.10) * smoothstep(0.0, 0.6, sw);
	float back;
	if (sw >= 0.0) {
		back = zb;
	} else {
		back = mix(zbase, cave_depth(p, fld), smoothstep(0.0, -0.0625, sw));
	}
	return mix(0.0, back, smoothstep(0.0, -0.0625, sf));
}

vec4 field_at(vec2 p) {
	vec4 f = textureLod(field_tex, p / level_size, 0.0);
	f.r = max(f.r, step(p.y, 0.0));   // above the level top is always open sky
	return f;
}

float height_at(vec2 p) {
	vec4 fld = field_at(p);
	return height_from(p, sdf_bicubic(p), fld);
}
