shader_type spatial;
render_mode depth_draw_opaque, cull_back;

#include "res://shaders/world/terrain_common.gdshaderinc"

uniform sampler2D fgcol_tex : source_color, filter_nearest, repeat_disable; // rgb colour, a = material/255 (dilated)
uniform sampler2D info_tex : filter_nearest, repeat_disable;                // r solid, g bg, b zone/255, a sky
uniform sampler2D bgcol_tex : source_color, filter_nearest, repeat_disable; // rgb bg colour (dilated), a bg present
uniform sampler2D tint_tex : source_color, filter_linear, repeat_disable;   // blurred cave tint
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nrm2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_hgt : filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : filter_linear, repeat_disable;   // baked z(p), HTPT texels / tile incl. margin
uniform float height_margin = 16.0;
uniform float htpt = 16.0;
uniform float time_scale = 1.0;
uniform bool debug_grid = false;

varying vec3 w_pos;

// material ids (see WorldPalette)
const int M_AIR = 0; const int M_EARTH = 1; const int M_STONE = 2; const int M_MARBLE = 3; const int M_ICE = 4;
const int M_WATER = 5; const int M_CORRUPT = 6; const int M_FIRE = 7; const int M_OBSIDIAN = 8; const int M_GLASS = 9;
const int M_GRASS = 10; const int M_FOLIAGE = 11; const int M_FLESH = 12; const int M_WOOD = 13; const int M_METAL = 14;
const int M_CLOUD = 15; const int M_SAND = 16; const int M_GEM = 17; const int M_SNOW = 18; const int M_BONE = 19;

vec2 huv(vec2 p) {
	return (p + height_margin) / (level_size + 2.0 * height_margin);
}

// Smooth (B-spline) sample of the baked height field, for per-pixel normals.
float height_smooth(vec2 p) {
	vec2 tsize = (level_size + 2.0 * height_margin) * htpt;
	vec2 st = huv(p) * tsize - 0.5;
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
	float t00 = textureLod(height_tex, (vec2(h0.x, h0.y) + 0.5) / tsize, 0.0).r;
	float t10 = textureLod(height_tex, (vec2(h1.x, h0.y) + 0.5) / tsize, 0.0).r;
	float t01 = textureLod(height_tex, (vec2(h0.x, h1.y) + 0.5) / tsize, 0.0).r;
	float t11 = textureLod(height_tex, (vec2(h1.x, h1.y) + 0.5) / tsize, 0.0).r;
	return g0.y * (g0.x * t00 + g1.x * t10) + g1.y * (g0.x * t01 + g1.x * t11);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = vec2(wp.x, -wp.y);
	float z = textureLod(height_tex, huv(p), 0.0).r;
	VERTEX.z = z - MODEL_MATRIX[3].z;
	w_pos = vec3(wp.xy, z);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// Region-aware 2x2 reconstruction of the pixel-art colour field: smooth curved boundaries instead of
// stair steps. Returns colour (linear), dominant material id, and a 0..1 "boundary" factor.
void region_sample(sampler2D tex, vec2 p, float sharp, out vec3 col, out int mat, out float boundary) {
	vec2 q = p - 0.5;
	vec2 fb = floor(q);
	vec2 f = q - fb;
	ivec2 b = ivec2(fb);
	ivec2 mx = ivec2(level_size) - 1;
	vec4 c0 = texelFetch(tex, clamp(b, ivec2(0), mx), 0);
	vec4 c1 = texelFetch(tex, clamp(b + ivec2(1, 0), ivec2(0), mx), 0);
	vec4 c2 = texelFetch(tex, clamp(b + ivec2(0, 1), ivec2(0), mx), 0);
	vec4 c3 = texelFetch(tex, clamp(b + ivec2(1, 1), ivec2(0), mx), 0);
	float w0 = (1.0 - f.x) * (1.0 - f.y);
	float w1 = f.x * (1.0 - f.y);
	float w2 = (1.0 - f.x) * f.y;
	float w3 = f.x * f.y;
	// similarity: colour distance
	float k = 60.0;
	float s01 = exp(-k * dot(c0.rgb - c1.rgb, c0.rgb - c1.rgb));
	float s02 = exp(-k * dot(c0.rgb - c2.rgb, c0.rgb - c2.rgb));
	float s03 = exp(-k * dot(c0.rgb - c3.rgb, c0.rgb - c3.rgb));
	float s12 = exp(-k * dot(c1.rgb - c2.rgb, c1.rgb - c2.rgb));
	float s13 = exp(-k * dot(c1.rgb - c3.rgb, c1.rgb - c3.rgb));
	float s23 = exp(-k * dot(c2.rgb - c3.rgb, c2.rgb - c3.rgb));
	float sc0 = w0 + w1 * s01 + w2 * s02 + w3 * s03;
	float sc1 = w1 + w0 * s01 + w2 * s12 + w3 * s13;
	float sc2 = w2 + w0 * s02 + w1 * s12 + w3 * s23;
	float sc3 = w3 + w0 * s03 + w1 * s13 + w2 * s23;
	float m = max(max(sc0, sc1), max(sc2, sc3));
	float a0 = exp((sc0 - m) * sharp);
	float a1 = exp((sc1 - m) * sharp);
	float a2 = exp((sc2 - m) * sharp);
	float a3 = exp((sc3 - m) * sharp);
	float inv = 1.0 / (a0 + a1 + a2 + a3);
	col = (c0.rgb * a0 + c1.rgb * a1 + c2.rgb * a2 + c3.rgb * a3) * inv;
	vec4 cm = c0;
	if (sc1 >= m) cm = c1;
	if (sc2 >= m) cm = c2;
	if (sc3 >= m) cm = c3;
	mat = int(cm.a * 255.0 + 0.5);
	boundary = 1.0 - max(max(a0, a1), max(a2, a3)) * inv;
}

vec3 triplanar_normal(sampler2D t, vec3 pos, vec3 n, float scale) {
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 tx = texture(t, pos.zy * scale).xyz * 2.0 - 1.0;
	vec3 ty = texture(t, pos.xz * scale).xyz * 2.0 - 1.0;
	vec3 tz = texture(t, pos.xy * scale).xyz * 2.0 - 1.0;
	// whiteout blend (world-space)
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * bw.x + ty.xzy * bw.y + tz.xyz * bw.z);
}

float triplanar_h(sampler2D t, vec3 pos, vec3 n, float scale) {
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	return texture(t, pos.zy * scale).r * bw.x + texture(t, pos.xz * scale).r * bw.y + texture(t, pos.xy * scale).r * bw.z;
}

void fragment() {
	float t = TIME * time_scale;
	vec3 wp = w_pos;
	vec2 p = vec2(wp.x, -wp.y);
	vec4 s = sdf_bicubic(p);
	vec4 fld = field_at(p);

	// ---- layer classification ----
	int layer = 0; // 0 fg, 1 bg wall, 2 cave
	if (s.x < -0.07) {
		layer = (s.y >= -0.13) ? 1 : 2;
	}
	if (layer == 1 && s.y < -0.07) { layer = 2; }
	if (layer == 2 && fld.r > 0.5) {
		discard; // open night sky: the Sky + backdrop show through
	}

	// ---- geometric normal (world space) from the height field ----
	float e = 0.04;
	float hx1 = height_smooth(p + vec2(e, 0.0));
	float hx0 = height_smooth(p - vec2(e, 0.0));
	float hy1 = height_smooth(p + vec2(0.0, e));
	float hy0 = height_smooth(p - vec2(0.0, e));
	// world y = -p.y  ->  dz/dwy = -(dz/dpy)
	vec3 gn = normalize(vec3(-(hx1 - hx0) / (2.0 * e), (hy1 - hy0) / (2.0 * e), 1.0));
	if (layer == 0 && s.x < 0.0) {
		// cliff: normal points outward (away from the solid), mostly horizontal
		vec2 gs = vec2(sdf_linear(p + vec2(0.02, 0.0)).x - sdf_linear(p - vec2(0.02, 0.0)).x,
			sdf_linear(p + vec2(0.0, 0.02)).x - sdf_linear(p - vec2(0.0, 0.02)).x);
		gn = normalize(vec3(-gs.x, gs.y, 0.0001));
	}

	vec3 albedo = vec3(0.5);
	float rough = 0.8;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	float ao = 1.0;
	float detail_amt = 1.0;
	float detail_scale = 0.35;
	int mat = M_EARTH;
	float boundary = 0.0;
	vec3 n = gn;

	// depth along the cliff: 0 at the gameplay plane, 1 deep in the back
	float depth01 = clamp(-wp.z / 5.0, 0.0, 1.0);

	if (layer == 0) {
		vec3 c;
		region_sample(fgcol_tex, p, 28.0, c, mat, boundary);
		albedo = c;
		// cliffs darken with depth (they are the sides of the solid mass)
		ao = mix(1.0, 0.4, smoothstep(0.0, 3.5, -wp.z));
	} else if (layer == 1) {
		vec3 c; int bm; float bb;
		region_sample(bgcol_tex, p, 20.0, c, bm, bb);
		albedo = c * 0.85;
		mat = -1;
		// contact darkening where the foreground meets the back wall
		ao = mix(0.35, 1.0, smoothstep(-0.1, -1.6, s.x)) * mix(0.55, 1.0, smoothstep(-3.2, -1.7, wp.z));
		rough = 0.85;
		detail_scale = 0.5;
	} else {
		vec3 tint = texture(tint_tex, p / level_size).rgb;
		float strata = ridge(vec2(p.x * 0.05, p.y * 0.35) + fbm2(p * 0.1)) ;
		albedo = tint * (0.55 + 0.45 * strata);
		mat = -2;
		ao = mix(0.25, 1.0, smoothstep(-0.2, -2.2, s.x)) * mix(0.35, 1.0, smoothstep(-7.5, -3.5, wp.z));
		rough = 0.9;
		detail_scale = 0.22;
	}

	vec3 dn = triplanar_normal(detail_nrm, wp, gn, detail_scale);
	float dh = triplanar_h(detail_hgt, wp, gn, detail_scale);
	float up = clamp(gn.y, 0.0, 1.0);
	float front = clamp(gn.z, 0.0, 1.0);

	if (mat == M_EARTH || mat == M_SAND) {
		// clay/soil: strata + pebbles, slightly wet in cavities
		float st = gnoise(vec2(p.x * 0.18, p.y * 1.6)) * 0.5 + 0.5;
		albedo *= mix(0.78, 1.12, st) * mix(0.8, 1.1, dh);
		rough = mix(0.62, 0.92, dh);
		n = normalize(mix(gn, dn, 0.85));
	} else if (mat == M_STONE || mat == M_METAL) {
		albedo *= mix(0.7, 1.15, dh);
		rough = mix(0.35, 0.75, dh);
		spec = 0.55;
		n = normalize(mix(gn, triplanar_normal(detail_nrm2, wp, gn, 0.45), 0.9));
		if (mat == M_METAL) { metal = 0.7; rough = 0.3; }
	} else if (mat == M_MARBLE) {
		float vein = smoothstep(0.92, 1.0, ridge(p * 0.6 + fbm2(p * 0.5) * 1.5));
		albedo = mix(albedo * 1.08, albedo * 0.72, vein);
		rough = 0.22;
		spec = 0.6;
		n = normalize(mix(gn, dn, 0.25));
	} else if (mat == M_SNOW) {
		albedo = mix(albedo, vec3(0.85, 0.9, 1.0), 0.35) * mix(0.85, 1.05, dh);
		rough = 0.55;
		n = normalize(mix(gn, dn, 0.5));
		// frost sparkle
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
		float sp = hash12(floor(wp.xy * 40.0 + vdir.xy * 6.0));
		emit += vec3(0.7, 0.85, 1.0) * step(0.996, sp) * 3.0;
	} else if (mat == M_ICE || mat == M_GLASS || mat == M_GEM) {
		// crystal: fake refraction (parallax inner layer), fresnel rim, inner glow
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
		vec2 par = p + vec2(vdir.x, -vdir.y) * 0.6;
		float inner = fbm3(par * 1.3 + t * 0.03) * 0.5 + 0.5;
		float fres = pow(1.0 - clamp(dot(gn, vdir), 0.0, 1.0), 3.0);
		float glow = (mat == M_GEM) ? 1.4 : (mat == M_ICE ? 0.35 : 0.55);
		albedo = albedo * mix(0.35, 0.7, inner);
		emit += albedo * glow * (0.5 + inner) + albedo * fres * 1.5;
		rough = 0.04;
		spec = 0.9;
		n = normalize(mix(gn, dn, 0.12));
	} else if (mat == M_WATER) {
		vec2 wv = vec2(fbm2(p * 0.8 + vec2(t * 0.25, t * 0.1)), fbm2(p * 0.8 + vec2(-t * 0.18, t * 0.21) + 9.0));
		n = normalize(gn + vec3(wv.x, wv.y, 0.0) * 0.35);
		float caust = pow(clamp(ridge(p * 1.3 + wv * 1.5 + t * 0.2), 0.0, 1.0), 6.0);
		float depthw = smoothstep(0.0, 4.0, s.w);
		albedo = mix(albedo * 1.1, albedo * 0.35, depthw);
		emit += albedo * caust * 1.2 * (1.0 - depthw * 0.6) + vec3(0.05, 0.12, 0.3) * 0.25;
		rough = 0.03;
		spec = 0.7;
	} else if (mat == M_CORRUPT) {
		float vein = smoothstep(0.955, 0.995, ridge(p * 0.32 + fbm2(p * 0.21) * 1.4));
		float pulse = 0.5 + 0.5 * sin(t * 1.4 - length(p - vec2(210.0, 100.0)) * 0.12);
		albedo *= mix(0.7, 1.1, dh);
		emit += vec3(0.9, 0.35, 1.0) * vein * (0.4 + 0.8 * pulse) * 1.3 * smoothstep(0.05, 0.4, s.x);
		rough = 0.45;
		spec = 0.55;
		n = normalize(mix(gn, dn, 0.6));
	} else if (mat == M_FIRE) {
		// molten rock: dark crust cracked with glowing flowing magma
		vec2 fp = p * 0.9 + vec2(0.0, t * 0.35);
		float flow = fbm3(fp + fbm2(p * 0.6 - t * 0.1) * 1.3) * 0.5 + 0.5;
		float crack = smoothstep(0.35, 0.75, flow);
		vec3 hot = srgb_to_lin(vec3(1.0, 0.8, 0.4));
		vec3 mid = albedo;
		albedo = mix(albedo * 0.2, albedo * 0.5, crack);
		emit += mix(mid * 0.35, mix(mid, hot, 0.5) * 2.2, crack * crack) * (0.35 + 0.65 * crack);
		rough = 0.5;
		n = normalize(mix(gn, dn, 0.6 * (1.0 - crack)));
	} else if (mat == M_OBSIDIAN) {
		albedo = vec3(0.012, 0.01, 0.016);
		rough = 0.06;
		spec = 1.0;
		n = normalize(mix(gn, dn, 0.1));
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
		float fres = pow(1.0 - clamp(dot(gn, vdir), 0.0, 1.0), 4.0);
		emit += vec3(0.25, 0.05, 0.4) * fres * 0.4;
	} else if (mat == M_GRASS || mat == M_FOLIAGE) {
		float fuzz = triplanar_h(detail_hgt, wp * 3.0, gn, 0.9);
		albedo *= mix(0.65, 1.2, fuzz);
		if (mat == M_FOLIAGE) {
			float dm = domes(p * 2.0 + fbm2(p * 0.8) * 0.4);
			float leaf = fbm3(p * 5.0) * 0.5 + 0.5;
			albedo *= mix(0.35, 1.15, dm) * mix(0.75, 1.15, leaf);
			albedo = mix(albedo, albedo * vec3(1.1, 1.15, 0.7), smoothstep(0.6, 1.0, dm) * 0.4);
		}
		rough = 0.75;
		n = normalize(mix(gn, triplanar_normal(detail_nrm2, wp * 2.5, gn, 0.8), 0.9));
	} else if (mat == M_FLESH) {
		float musc = ridge(vec2(p.x * 0.8, p.y * 0.25) + fbm2(p * 0.4) * 1.2);
		albedo *= mix(0.55, 1.1, musc);
		rough = 0.32;
		spec = 0.55;
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
		float fres = pow(1.0 - clamp(dot(gn, vdir), 0.0, 1.0), 2.0);
		emit += albedo * fres * 0.35;
		n = normalize(mix(gn, dn, 0.4));
	} else if (mat == M_WOOD) {
		float grain = sin(p.x * 2.0 + fbm2(vec2(p.x * 0.5, p.y * 3.0)) * 4.0) * 0.5 + 0.5;
		albedo *= mix(0.7, 1.1, grain);
		rough = 0.7;
		n = normalize(mix(gn, dn, 0.5));
	} else if (mat == M_CLOUD) {
		// tornado: swirling wind-carved vapour
		// tornado: vapour bands whirling around the funnel axis
		float ax = 22.0 - (p.y - 80.0) * 0.12;
		float band = p.y * 1.3 + sin((p.x - ax) * 0.35 - t * 2.2) * 1.2;
		float swirl = fbm3(vec2((p.x - ax) * 0.45 - t * 1.6, band) + fbm2(p * 0.25 - t * 0.3));
		float streak = sin(band * 3.0 + swirl * 2.5) * 0.5 + 0.5;
		albedo *= mix(0.55, 1.3, streak * (swirl * 0.5 + 0.5) + 0.25);
		emit += albedo * 0.06;
		rough = 0.95;
		n = normalize(gn + vec3(0.0, (streak - 0.5) * 0.35, 0.0));
	} else if (mat == M_BONE) {
		albedo = mix(albedo, vec3(0.78, 0.72, 0.6), 0.3) * mix(0.75, 1.05, dh);
		rough = 0.5;
		n = normalize(mix(gn, dn, 0.4));
	} else {
		n = normalize(mix(gn, dn, 0.8 * detail_amt));
	}

	if (layer == 0) {
		// soft rim of the bevel catches light; tiny cavity darkening at colour boundaries
		albedo *= mix(1.0, 0.8, boundary);
		// grass / moss on up-facing edges of earth near the surface
	}

	if (debug_grid) {
		vec2 g = abs(fract(p) - 0.5);
		float line = step(0.47, max(g.x, g.y));
		ivec2 ti = ivec2(floor(p));
		float solid = texelFetch(info_tex, clamp(ti, ivec2(0), ivec2(level_size) - 1), 0).r;
		emit += vec3(solid, 1.0 - solid, 0.0) * 0.25 + vec3(1.0, 1.0, 0.0) * line * 0.6;
	}

	if (layer == 0) {
		// the sides of the solid mass lose emission and detail as they recede
		emit *= smoothstep(-2.2, -0.15, wp.z);
	}
	ALBEDO = albedo * ao;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
