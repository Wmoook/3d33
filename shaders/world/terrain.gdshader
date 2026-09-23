shader_type spatial;
render_mode depth_draw_opaque, cull_back;

#include "res://shaders/world/terrain_common.gdshaderinc"
#include "res://shaders/world/pbr_detail.gdshaderinc"

uniform sampler2D fgcol_tex : source_color, filter_nearest, repeat_disable; // rgb colour, a = material/255 (dilated)
uniform sampler2D orig_tex : source_color, filter_nearest, repeat_disable;  // pre-merge colours (the painting's dither)
uniform float mottle = 0.35;
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
uniform vec3 keys_open = vec3(0.0);
// trial chambers (Forgotten Veil): carved runes on the back wall of each trial room
uniform sampler2D rune_atlas : filter_linear_mipmap, repeat_disable;   // 4x4 cells, L = groove
uniform sampler2D trial_tex : filter_nearest, repeat_disable;          // R8 per tile: trial index (0 none)
uniform vec4 rune_pos[16];
uniform vec4 rune_col[16];
uniform float rune_state[16];
uniform float rune_size = 4.6;
uniform sampler2D trans_tex : filter_linear, repeat_disable;   // day: r foliage, g grass, b water, a stone (soft)
uniform vec4 scroll_rect = vec4(-1.0);
uniform vec4 shrine_rect = vec4(-1.0);   // FV finish peak (tile x0, y0, x1, y1)
uniform vec2 shrine_trophy = vec2(-100.0);   // FV parchment scroll (tile x0, y0, x1, y1), -1 = none
uniform int debug_mode = 0;   // 1 grid, 2 zones, 3 solidity mask
uniform sampler2D zone_tex : filter_nearest, repeat_disable;
uniform sampler2D visual_tex : filter_nearest, repeat_disable;   // WorldPalette.Z_* per tile

varying vec3 w_pos;

// material ids (see WorldPalette)
const int M_AIR = 0; const int M_EARTH = 1; const int M_STONE = 2; const int M_MARBLE = 3; const int M_ICE = 4;
const int M_WATER = 5; const int M_CORRUPT = 6; const int M_FIRE = 7; const int M_OBSIDIAN = 8; const int M_GLASS = 9;
const int M_GRASS = 10; const int M_FOLIAGE = 11; const int M_FLESH = 12; const int M_WOOD = 13; const int M_METAL = 14;
const int M_CLOUD = 15; const int M_SAND = 16; const int M_GEM = 17; const int M_SNOW = 18; const int M_BONE = 19;
const int M_RUIN = 20; const int M_CRAG = 21;

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
	vec2 p_real = vec2(wp.x, -wp.y);
	vec2 p = level_mirror(p_real);   // outside the level: sample the mirrored edge region (no stretching)
	float p_out = level_out(p_real);
	vec4 s = sdf_bicubic(p);
	s.x = sdf_linear(p).x;
	s = margin_solidify(p_real, p, s);
	vec4 fld = field_at(p);

	// art key-door tiles (demon body...) vanish while their key is active (WorldDoors draws the ghost)
	float info_r = texelFetch(info_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(level_size) - 1), 0).r * 255.0;
	int art = (info_r > 100.0 && info_r < 220.0) ? int((info_r - 80.0) / 40.0 + 0.5) : 0;
	if (art > 0 && keys_open[art - 1] > 0.5) {
		discard;
	}
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
	// central differences on the (bilinear) baked height, one texel apart: 4 taps
	float e = 1.0 / htpt;
	float hx1 = textureLod(height_tex, huv(p_real + vec2(e, 0.0)), 0.0).r;
	float hx0 = textureLod(height_tex, huv(p_real - vec2(e, 0.0)), 0.0).r;
	float hy1 = textureLod(height_tex, huv(p_real + vec2(0.0, e)), 0.0).r;
	float hy0 = textureLod(height_tex, huv(p_real - vec2(0.0, e)), 0.0).r;
	// world y = -p.y  ->  dz/dwy = -(dz/dpy)
	vec3 gn = normalize(vec3(-(hx1 - hx0) / (2.0 * e), (hy1 - hy0) / (2.0 * e), 1.0));
	if (layer == 0 && s.x < 0.0 && p_out <= 0.0) {
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
		// colour/material regions follow noise-warped curves (no axis-aligned seams), except for fire
		// and the text/logo gems whose painted shapes must stay crisp
		vec2 warp = vec2(fbm2(p * 0.9 + 3.1), fbm2(p * 0.9 - 7.7)) * 0.32;
		region_sample(fgcol_tex, p + warp, 18.0, c, mat, boundary);
		if (mat == M_GEM || mat == M_FIRE || mat == M_MARBLE) {
			region_sample(fgcol_tex, p, 28.0, c, mat, boundary);
		}
		vec3 oc; int om; float ob;
		region_sample(orig_tex, p + vec2(fbm2(p * 1.7), fbm2(p * 1.7 + 4.0)) * 0.18, 6.0, oc, om, ob);
		albedo = mix(c, oc, mottle);
		// cliffs darken with depth (they are the sides of the solid mass)
		ao = mix(1.0, 0.4, smoothstep(0.0, 3.5, -wp.z));
	} else if (layer == 1) {
		vec3 c; int bm; float bb;
		vec2 bwarp = vec2(fbm2(p * 0.7 + 1.3), fbm2(p * 0.7 - 5.1)) * (scroll_rect.x >= 0.0 ? 0.45 : 0.0);
		region_sample(bgcol_tex, p + bwarp, 20.0, c, bm, bb);
		albedo = c * 0.85;
		if (scroll_rect.x >= 0.0) {
			float lum_b = dot(c, vec3(0.3, 0.55, 0.15));
			float greyish = 1.0 - smoothstep(0.03, 0.12, max(max(abs(c.r - c.g), abs(c.g - c.b)), abs(c.r - c.b)));
			if (greyish > 0.5) {
				// dressed stone: brick bond with varied course heights and block widths (world-space hash)
				float yy = p.y * 0.62 + 0.37;
				float course = floor(yy);
				float ch = mix(0.7, 1.3, hash12(vec2(course, 5.3)));
				float cy = fract(yy);
				float xoff = hash12(vec2(course, 9.1)) * 7.0;
				float bw = mix(1.2, 2.6, hash12(vec2(course, 2.7)));
				float xx = (p.x + xoff) / (bw * 1.6);
				float cell = floor(xx + 0.35 * sin(course * 1.7));
				float cx = fract(xx + 0.35 * sin(course * 1.7));
				float jx = min(cx, 1.0 - cx) * bw * 1.6;
				float jy = min(cy, 1.0 - cy) * ch / 0.62;
				float jn = 1.0 - smoothstep(0.03, 0.09, min(jx, jy));
				albedo *= mix(0.85, 1.1, hash12(vec2(cell, course) + 2.0)) * (1.0 - jn * 0.5);
			} else {
				// rammed earth panel: horizontal strata, root tendrils, cracks, occasional niches, edge AO
				float sy = p.y * 1.4 + fbm2(p * vec2(0.15, 0.4)) * 1.5;
				float strata = sin(sy * 3.1) * 0.5 + 0.5;
				float band = hash12(vec2(floor(sy), 7.0));
				albedo *= mix(0.82, 1.1, strata * 0.5 + band * 0.5);
				float root = smoothstep(0.93, 0.99, ridge(vec2(p.x * 0.6 + fbm2(p * 0.3) * 2.0, p.y * 0.18)));
				albedo = mix(albedo, albedo * vec3(0.55, 0.45, 0.35), root);
				float crack = smoothstep(0.96, 0.995, ridge(p * 0.35 + fbm2(p * 0.2) * 1.2));
				albedo *= 1.0 - crack * 0.0;
				vec2 ncell = floor(p / vec2(7.0, 6.0));
				vec2 nf = fract(p / vec2(7.0, 6.0));
				if (hash12(ncell + 11.0) > 0.72) {
					vec2 nd = abs(nf - vec2(0.5, 0.55)) / vec2(0.12, 0.2);
					float niche = 1.0 - smoothstep(0.85, 1.0, max(nd.x, nd.y + max(0.0, -(nf.y - 0.55)) * 0.0));
					float arch = 1.0 - smoothstep(0.85, 1.0, length((nf - vec2(0.5, 0.42)) / vec2(0.12, 0.12)));
					albedo *= 1.0 - max(niche, arch * step(nf.y, 0.45)) * 0.55;
				}
			}
			// AO gradient toward the panel's edges (where it meets the foreground mass)
			ao *= mix(0.55, 1.0, smoothstep(-0.1, -2.5, s.x));
		}		mat = -1;
		int vzb = int(texelFetch(visual_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(level_size) - 1), 0).r * 255.0 + 0.5);
		if (vzb == 2) { albedo *= 0.3; }   // inferno back walls stay the painting's near-black red
		// contact darkening where the foreground meets the back wall
		ao = mix(0.55, 1.0, smoothstep(-0.05, -0.8, s.x)) * mix(0.6, 1.0, smoothstep(-3.2, -1.7, wp.z));
		if (fld.g > 0.5) {
			// pores / burrows in one rock body: soft radial darkness, deepest at the pocket centre,
			// tinted by the surrounding rock and speckled with crumbs
			vec3 rock; int rm; float rb;
			region_sample(fgcol_tex, p, 8.0, rock, rm, rb);
			float depth_in = smoothstep(0.0, 0.5, -s.x);
			albedo = mix(rock * 0.55, c * 0.5, 0.35);
			ao = mix(0.7, 0.22, depth_in);
			float crumb = step(0.93, hash12(floor(p * 9.0))) * (1.0 - depth_in * 0.6);
			albedo = mix(albedo, rock * 0.9, crumb);
		}
		rough = 0.85;
		detail_scale = 0.5;
	} else {
		vec3 tint = texture(tint_tex, p / level_size).rgb;
		float strata = ridge(vec2(p.x * 0.05, p.y * 0.35) + fbm2(p * 0.1)) ;
		albedo = tint * (0.55 + 0.45 * strata);
		mat = -2;
		ao = mix(0.5, 1.0, smoothstep(-0.05, -1.0, s.x)) * mix(0.5, 1.0, smoothstep(-12.0, -5.0, wp.z));
		int vz = int(texelFetch(visual_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(level_size) - 1), 0).r * 255.0 + 0.5);
		if (vz == 2) {
			// inferno depths: near-black basalt (the painting's black void) with rare glowing fissures
			albedo = albedo * 0.12 + vec3(0.02, 0.012, 0.01);
			float fis = smoothstep(0.991, 0.999, ridge(p * 0.2 + fbm2(p * 0.07) * 1.4)) * smoothstep(0.2, 0.7, fbm2(p * 0.05) + 0.5);
			float pulse = 0.7 + 0.3 * sin(TIME * 0.8 + p.x * 0.1);
			emit += vec3(1.0, 0.3, 0.05) * fis * 0.35 * pulse * smoothstep(-5.0, -9.0, wp.z);
		} else if (vz == 3) {
			float vn = smoothstep(0.982, 0.998, ridge(p * 0.3 + fbm2(p * 0.1) * 1.5));
			emit += vec3(0.6, 0.15, 1.0) * vn * 0.35;
		} else if (vz == 4) {
			albedo = mix(albedo, vec3(0.55, 0.7, 0.9) * 0.6, 0.35);
		}
		rough = 0.9;
		detail_scale = 0.22;
	}

	// carved trial rune: only on back-wall / cave layers (always behind the foreground mass)
	vec3 rune_emit = vec3(0.0);
	vec3 rune_n = vec3(0.0);
	if (layer != 0) {
		int tr = int(texelFetch(trial_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(level_size) - 1), 0).r * 255.0 + 0.5);
		if (tr > 0 && tr <= 16) {
			vec4 rp = rune_pos[tr - 1];
			vec2 ruv = (vec2(wp.x, wp.y) - rp.xy) / rune_size + 0.5;
			ruv.y = 1.0 - ruv.y;
			if (all(greaterThan(ruv, vec2(0.0))) && all(lessThan(ruv, vec2(1.0)))) {
				vec2 cellp = vec2(float((tr - 1) % 4), float((tr - 1) / 4));
				vec2 auv = (cellp + ruv) / 4.0;
				float g = textureLod(rune_atlas, auv, 0.6).r;
				float e = 1.0 / 512.0;
				float gx = textureLod(rune_atlas, auv + vec2(e, 0.0), 0.6).r - textureLod(rune_atlas, auv - vec2(e, 0.0), 0.6).r;
				float gy = textureLod(rune_atlas, auv + vec2(0.0, e), 0.6).r - textureLod(rune_atlas, auv - vec2(0.0, e), 0.6).r;
				rune_n = vec3(gx, -gy, 0.0) * 2.0;              // groove walls
				albedo *= 1.0 - g * 0.75;                        // groove AO
				float st = rune_state[tr - 1];
				float breath = 0.55 + 0.45 * sin(TIME * 1.3 + float(tr) * 1.7);
				float glow = st < 0.5 ? 0.35 + 0.35 * breath : 0.45 + (st - 1.0) * 3.0;
				float core = smoothstep(0.75, 1.0, g);            // the glow lives deep inside the groove
				rune_emit = rune_col[tr - 1].rgb * core * glow * 0.35;
			}
		}
	}
	vec3 dn = triplanar_normal(detail_nrm, wp, gn, detail_scale);
	float dh = triplanar_h(detail_hgt, wp, gn, detail_scale);
	float up = clamp(gn.y, 0.0, 1.0);
	float front = clamp(gn.z, 0.0, 1.0);

	bool parchment = mat == M_SAND && p.x >= scroll_rect.x && p.y >= scroll_rect.y && p.x <= scroll_rect.z && p.y <= scroll_rect.w;
	if (layer == 0 && p.x >= shrine_rect.x && p.y >= shrine_rect.y && p.x <= shrine_rect.z && p.y <= shrine_rect.w) {
		// summit shrine: grassy alpine crag - warm grey rock strata, grass/moss mantles over every step top,
		// and a carved stone plinth right under the trophy
		vec3 rock = mix(vec3(dot(albedo, vec3(0.33))), albedo, 0.35) * vec3(1.05, 1.0, 0.92);
		float sy = p.y * 1.2 + p.x * 0.2 + fbm2(p * vec2(0.1, 0.25)) * 1.8;
		float fs = fract(sy);
		float ledge = smoothstep(0.0, 0.12, fs) * (1.0 - smoothstep(0.55, 1.0, fs));
		albedo = rock * mix(0.65, 1.15, hash12(vec2(floor(sy), 4.0))) * mix(0.7, 1.12, ledge);
		float mantle = smoothstep(0.45, 0.85, gn.y + fbm2(p * 2.5) * 0.25);
		albedo = mix(albedo, srgb_to_lin(vec3(0.36, 0.58, 0.16)) * mix(0.8, 1.2, dh), clamp(mantle, 0.0, 1.0));
		vec2 pd = abs(p - (shrine_trophy + vec2(0.5, 1.5)));
		float plinth = step(pd.x, 1.6) * step(pd.y, 0.55);
		if (plinth > 0.5) {
			float jn = 1.0 - smoothstep(0.02, 0.07, min(abs(fract((p.x - shrine_trophy.x + 1.6) / 1.07) - 0.5) * 1.07, 0.55 - pd.y));
			albedo = srgb_to_lin(vec3(0.82, 0.78, 0.7)) * (1.0 - jn * 0.35);
			emit += vec3(1.0, 0.8, 0.45) * 0.08;
		}
		rough = mix(0.8, 0.6, mantle);
		n = normalize(gn + vec3(0.0, (ledge - 0.5) * 0.35, 0.0) + (dn - gn) * 0.45);
	} else if (parchment) {
		// illuminated parchment: warm vellum with fibres, soft wrinkles, age blotches and burnt, darker edges
		vec3 vellum = srgb_to_lin(vec3(0.86, 0.72, 0.5));
		float fib = fbm2(vec2(p.x * 6.0, p.y * 0.8)) * 0.5 + 0.5;
		float blot = smoothstep(0.55, 0.9, fbm3(p * 0.35) * 0.5 + 0.5);
		float edge = 1.0 - smoothstep(0.0, 1.4, s.w);
		albedo = mix(vellum, albedo, 0.35) * mix(0.9, 1.08, fib) * mix(1.0, 0.8, blot);
		albedo = mix(albedo, srgb_to_lin(vec3(0.36, 0.2, 0.1)), edge * 0.75);
		float wrinkle = fbm2(vec2(p.x * 0.4 + p.y * 0.9, p.y * 0.5)) - 0.5;
		n = normalize(gn + vec3(wrinkle * 0.25, wrinkle * 0.12, 0.0) + (dn - gn) * 0.15);
		rough = 0.8;
		spec = 0.3;
	} else if (mat == M_EARTH || mat == M_SAND) {
		// clay/soil: strata + pebbles, slightly wet in cavities
		// continuous world-space strata + large tonal patches flowing across tile boundaries, so
		// neighbouring tiles read as one rock mass rather than individual blocks
		float st = gnoise(vec2(p.x * 0.18, p.y * 1.6)) * 0.5 + 0.5;
		if (scroll_rect.x >= 0.0) {
			float sy2 = p.y * 1.3 + fbm2(p * vec2(0.12, 0.35)) * 1.6;
			albedo *= mix(0.8, 1.12, hash12(vec2(floor(sy2), 8.0))) * mix(0.9, 1.05, sin(sy2 * 6.2831) * 0.5 + 0.5);
			float root = smoothstep(0.975, 0.995, ridge(vec2(p.x * 0.35 + fbm2(p * 0.2) * 2.5, p.y * 0.12)));
			albedo = mix(albedo, albedo * vec3(0.55, 0.42, 0.32), root * 0.5 * smoothstep(0.3, 1.5, s.w));
			float crack = smoothstep(0.985, 0.998, ridge(p * 0.22 + fbm2(p * 0.12) * 1.3)) * smoothstep(0.35, 0.65, fbm2(p * 0.07) + 0.5);
			albedo *= 1.0 - crack * 0.0;   // (contour-like lines read as a web; disabled)
			ao *= mix(0.72, 1.0, smoothstep(0.0, 2.5, s.w));
		}
		float band = sin(p.y * 0.9 + fbm2(p * vec2(0.08, 0.25)) * 3.0) * 0.5 + 0.5;
		float patch = fbm3(p * 0.12) * 0.5 + 0.5;
		albedo *= mix(0.78, 1.12, st) * mix(0.8, 1.1, dh) * mix(0.85, 1.12, band) * mix(0.82, 1.15, patch);
		// worn rims: the edge of every bevel is lighter / crumbly (dissolves the blocky outline)
		float rim = 1.0 - smoothstep(0.0, 0.2, max(s.x, 0.0));
		albedo *= 1.0 + rim * (hash12(floor(p * 12.0)) * 0.35 - 0.05);
		rough = mix(0.62, 0.92, dh);
		n = normalize(mix(gn, dn, 0.85));
	} else if (mat == M_STONE || mat == M_METAL) {
		float bev = 1.0 - smoothstep(0.0, 0.14, max(s.x, 0.0));      // worn, lighter chipped edges
		albedo *= mix(0.7, 1.15, dh) * (1.0 + bev * 0.25);
		rough = mix(0.35, 0.75, dh);
		spec = 0.55;
		n = normalize(mix(gn, triplanar_normal(detail_nrm2, wp, gn, 0.45), 0.9));
		if (mat == M_METAL) { metal = 0.7; rough = 0.3; }
	} else if (mat == M_MARBLE) {
		float cloud = fbm3(p * 0.35 + fbm2(p * 0.2) * 1.5) * 0.5 + 0.5;
		float vein = smoothstep(0.72, 0.95, fbm2(p * vec2(0.5, 0.8) + cloud * 2.0) * 0.5 + 0.5);
		albedo = albedo * mix(0.9, 1.05, cloud) * mix(1.0, 0.8, vein);
		rough = 0.42;
		spec = 0.4;
		if (scroll_rect.x >= 0.0) {
			// day levels (FV V-bird stepping stones): matte weathered pale stone - no glow, calm
			albedo *= 0.55 * mix(0.85, 1.05, dh);
			rough = 0.85;
			spec = 0.25;
			n = normalize(mix(gn, dn, 0.5));
		}
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
		// crystal: faceted (flat voronoi facets with per-facet tilt), parallax inner depth, subsurface glow
		// that brightens where the ice is thin (edges, hanging tips), fresnel rim
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
		vec2 fq = p * (mat == M_ICE ? 1.6 : 2.2);
		vec2 fi = floor(fq);
		vec2 ff = fq - fi;
		float best = 9.0; vec2 cell = vec2(0.0);
		for (int yy = -1; yy <= 1; yy++) {
			for (int xx = -1; xx <= 1; xx++) {
				vec2 g = vec2(float(xx), float(yy));
				vec2 o = hash22(fi + g) * 0.45 + 0.5;
				float d = length(g + o - ff);
				if (d < best) { best = d; cell = fi + g; }
			}
		}
		vec2 tilt = hash22(cell + 3.7) * 0.45;
		vec3 fn = normalize(gn + vec3(tilt, 0.0) * smoothstep(0.3, 0.8, gn.z));
		vec2 par = p + vec2(vdir.x, -vdir.y) * 0.6;
		float inner = fbm3(par * 1.3 + t * 0.03) * 0.5 + 0.5;
		float fres = pow(1.0 - clamp(dot(fn, vdir), 0.0, 1.0), 3.0);
		float thin = 1.0 - smoothstep(0.05, 0.6, s.w);
		float tip = smoothstep(0.2, 0.9, -gn.y) * thin;             // downward-facing edges = icicle tips
		float glow = (mat == M_GEM) ? 0.7 : (mat == M_ICE ? 0.3 : 0.4);
		vec3 base = albedo;
		albedo = base * mix(0.3, 0.65, inner) * (0.85 + 0.3 * hash12(cell));
		emit += base * glow * (0.35 + inner) * (0.6 + thin) + base * fres * 0.9 + mix(base, vec3(0.8, 0.95, 1.0), 0.5) * tip * 1.2;
		rough = 0.12;
		spec = 0.55;
		n = fn;
		if (art == 3) {
			// sealed blue-key pond: hard glassy lid with pulsing blue rune veins and a crisp edge highlight
			float veinb = smoothstep(0.975, 0.997, ridge(p * 0.4 + vec2(fbm2(p * 0.2), fbm2(p * 0.2 + 4.0)) * 1.2));
			float edgeb = 1.0 - smoothstep(0.0, 0.12, max(s.x, 0.0));
			emit += vec3(0.3, 0.55, 1.0) * (veinb * (0.35 + 0.3 * sin(TIME * 1.1 + p.x * 0.15)) + edgeb * 0.6);
			rough = 0.04;
			spec = 0.9;
		}
	} else if (mat == M_WATER) {
		// deep glossy water: dark body, light shafts + caustics near the surface, foam on the top face
		vec2 wv = vec2(fbm2(p * vec2(0.6, 1.4) + vec2(t * 0.3, 0.0)), fbm2(p * vec2(0.6, 1.4) + vec2(-t * 0.22, 3.0) + 9.0));
		n = normalize(gn + vec3(wv.x * 0.18, wv.y * 0.1, 0.0));
		float depthw = smoothstep(0.0, 5.0, s.w);
		float near_top = 1.0 - smoothstep(0.0, 2.5, s.w);
		float caust = pow(clamp(ridge(p * 0.9 + wv * 1.2 + vec2(t * 0.15, t * 0.05)), 0.0, 1.0), 10.0);
		float shaft = smoothstep(0.6, 1.0, gnoise(vec2(p.x * 0.25 + p.y * 0.12 + t * 0.05, 0.5)) + 0.4) * near_top;
		albedo = mix(albedo * 0.55, albedo * 0.18, depthw);
		emit += albedo * (caust * 0.9 * near_top + shaft * 0.25) + vec3(0.01, 0.03, 0.08) * (1.0 - depthw);
		float foam = smoothstep(0.55, 0.95, gn.y) * smoothstep(0.45, 0.8, fbm3(p * 3.0 + vec2(t * 0.4, 0.0)) * 0.5 + 0.5);
		albedo = mix(albedo, vec3(0.75, 0.85, 0.95), foam * 0.8);
		rough = mix(0.04, 0.5, foam);
		spec = 0.8;
		if (scroll_rect.x >= 0.0 && (fld.b > 0.5 || s.w < 1.2)) {   // day levels only (Odyssey keeps its approved water)
			// water held in suspension (splash droplets, thin falling sheets): translucent deep blue orb with
			// internal flow streaks running down, caustic sparkle, wobbling normals, bright fresnel rim
			vec3 vd = normalize(CAMERA_POSITION_WORLD - wp);
			vec2 wob = vec2(sin(t * 3.1 + p.y * 4.0 + p.x), cos(t * 2.7 + p.x * 3.3 - p.y)) * 0.18;
			n = normalize(gn + vec3(wob, 0.0) * smoothstep(0.2, 0.9, gn.z));
			float flow = fbm2(vec2(p.x * 2.0, p.y * 0.7 - t * 1.6)) * 0.5 + 0.5;
			// falling water: long streaks racing downward (p.y grows downward), white foam at the edges
			float streak = smoothstep(0.55, 0.9, fbm2(vec2(p.x * 5.0, p.y * 0.35 - t * 4.5)) * 0.5 + 0.5);
			float foamE = 1.0 - smoothstep(0.0, 0.3, s.w);
			flow = max(flow, streak);
			// fresnel only on the front face (vertical cube sides must not glow white)
			float fr = pow(1.0 - clamp(dot(n, vd), 0.0, 1.0), 3.0) * smoothstep(0.5, 0.9, gn.z) * 0.4;
			vec3 deep = srgb_to_lin(vec3(0.05, 0.22, 0.6));
			float streak2 = smoothstep(0.45, 0.85, fbm2(vec2(p.x * 3.5 + wob.x, p.y * 0.25 - t * 5.5)) * 0.5 + 0.5);
			albedo = deep * mix(0.3, 0.75, max(flow * 0.6, streak2));
			float spark = smoothstep(0.99, 1.0, ridge(p * 1.2 + wob * 2.0 + vec2(0.0, t * 0.6)));
			emit = srgb_to_lin(vec3(0.15, 0.45, 1.0)) * (0.05 + 0.18 * streak2) + vec3(0.7, 0.85, 1.0) * (fr + spark * 0.2 + streak2 * 0.12);
			// foam only along top edges
			float topE = foamE * smoothstep(0.35, 0.8, gn.y);
			albedo = mix(albedo, vec3(0.8, 0.88, 0.95), topE * (0.5 + 0.4 * streak));
			rough = mix(0.12, 0.4, topE);
			spec = 0.4;
		}
	} else if (mat == M_CORRUPT) {
		float vein = smoothstep(0.975, 0.997, ridge(p * 0.32 + fbm2(p * 0.21) * 1.4));
		float pulse = 0.5 + 0.5 * sin(t * 1.4 - length(p - vec2(210.0, 100.0)) * 0.12);
		albedo *= mix(0.8, 1.25, dh);
		albedo = mix(albedo, albedo * vec3(0.6, 0.3, 0.9), vein);
		emit += vec3(0.75, 0.15, 1.0) * vein * (0.3 + 0.7 * pulse) * 0.55 * smoothstep(0.05, 0.4, s.x);
		rough = 0.45;
		spec = 0.55;
		n = normalize(mix(gn, dn, 0.6));
	} else if (mat == M_FIRE) {
		// sculpted molten form: dark cooled crust, glowing crack network, hot cores deep inside each flame
		// shape and a bright rim along its silhouette; yellow (31) tiles burn hotter than orange (30)
		vec3 tint = albedo;
		float heat = smoothstep(0.3, 0.7, tint.g / max(tint.r, 0.01));
		// flame licks: cracks stretched vertically and scrolling upward, two scales mixed
		vec2 fw = vec2(fbm2(p * 0.8 + vec2(0.0, t * 0.35)), fbm2(p * 0.8 + 5.0 + vec2(0.0, t * 0.3))) * 0.9;
		vec2 lq = vec2(p.x * 1.4, p.y * 0.55 + t * 0.45) + fw;
		float plates = min(cobbles(lq), cobbles(lq * 2.1 + 7.3) + 0.12);
		float crack = (1.0 - smoothstep(0.03, 0.18, plates)) * (0.55 + 0.45 * fbm2(p * 0.4 + t * 0.1));
		float depth_in = smoothstep(0.15, 1.6, s.w);              // distance inside the painted flame
		float core = smoothstep(0.35, 1.0, depth_in * (0.55 + 0.6 * heat) + fbm2(p * 1.3 - vec2(0.0, t * 0.6)) * 0.25);
		float rim = (1.0 - smoothstep(0.0, 0.18, max(s.x, 0.0))) * smoothstep(-1.0, 0.2, wp.z);
		float flick = 0.85 + 0.15 * sin(t * 6.0 + p.x * 1.7 + p.y);
		vec3 hot = srgb_to_lin(vec3(1.0, 0.86, 0.5));
		vec3 glow_col = mix(tint, hot, 0.35 + 0.5 * heat);
		float glow = max(crack * (0.6 + 0.8 * heat), max(core, rim * 0.8));
		albedo = mix(tint * vec3(0.12, 0.07, 0.06), tint * 0.6, glow);   // crust is near-black basalt
		emit += glow_col * (crack * 1.6 + core * core * 3.2 + rim * 1.4) * mix(0.55, 1.1, heat) * flick;
		rough = mix(0.8, 0.35, glow);
		n = normalize(mix(gn, dn, 0.8 * (1.0 - glow)));
	} else if (mat == M_OBSIDIAN) {
		// volcanic glass: near-black, mirror gloss, conchoidal ripples, cool rim sheen + edge highlight so it
		// always reads as solid against dark backdrops
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
		float ripple = sin(length(fract(p * 0.5) - 0.5) * 18.0 + fbm2(p * 0.8) * 4.0) * 0.5 + 0.5;
		n = normalize(gn + vec3(dn.xy - gn.xy, 0.0) * 0.12 + vec3((ripple - 0.5) * 0.08, 0.0, 0.0));
		albedo = vec3(0.018, 0.02, 0.028) * (0.8 + 0.4 * ripple);
		rough = 0.05;
		spec = 1.0;
		float fres = pow(1.0 - clamp(dot(gn, vdir), 0.0, 1.0), 3.0);
		float edge = 1.0 - smoothstep(0.0, 0.16, max(s.x, 0.0));
		emit += vec3(0.35, 0.5, 0.75) * (fres * 0.35 + edge * 0.22) * smoothstep(-1.2, 0.0, wp.z);
	} else if (mat == M_GRASS || mat == M_FOLIAGE) {
		float fuzz = triplanar_h(detail_hgt, wp * 3.0, gn, 0.9);
		albedo *= mix(0.65, 1.2, fuzz);
		if (mat == M_FOLIAGE) {
			float dm = domes(p * 2.0 + fbm2(p * 0.8) * 0.4);
			if (scroll_rect.x >= 0.0) {
				// day levels: dome shading only on real tree crowns; lawns / ground mantles read as turf
				dm = mix(0.8, dm, textureLod(pbr_canopy_tex, p / level_size, 0.0).r);
			}
			float leaf = fbm3(p * 5.0) * 0.5 + 0.5;
			albedo *= mix(0.35, 1.15, dm) * mix(0.75, 1.15, leaf);
			albedo = mix(albedo, albedo * vec3(1.1, 1.15, 0.7), smoothstep(0.6, 1.0, dm) * 0.4);
		}
		rough = 0.75;
		n = normalize(mix(gn, triplanar_normal(detail_nrm2, wp * 2.5, gn, 0.8), 0.9));
	} else if (mat == M_FLESH) {
		// demon flesh: sinew striations flowing along the limbs (warped, anisotropic), dark crevices,
		// glossy wet highlights, subsurface red, and a cool rim from the lake
		vec2 fw2 = vec2(fbm2(p * 0.3), fbm2(p * 0.3 + 11.0)) * 2.2;
		// muscle bands: long fibres along a slowly turning direction field, grouped into bundles
		// fibres run roughly along the limbs (diagonal), domain-warped so they curve and never ring
		vec2 fd = normalize(vec2(1.0, -0.8));
		float across = dot(p, vec2(-fd.y, fd.x)) + fbm2(p * 0.12) * 3.5 + fbm2(p * 0.5) * 0.6;
		float fibre = sin(across * 1.7) * 0.5 + 0.5;
		float bundle = smoothstep(0.1, 0.9, sin(across * 0.5 + fbm2(p * 0.2) * 2.0) * 0.5 + 0.5);
		float sinew = mix(0.5, mix(fibre * 0.5 + 0.25, fibre, bundle), 0.7);
		float crevice = smoothstep(0.55, 0.15, fbm3(p * 0.5 + fw2 * 0.5) * 0.5 + 0.5);
		vec3 base = albedo;
		albedo = base * mix(0.5, 1.1, sinew) * mix(1.0, 0.45, crevice);
		rough = mix(0.22, 0.5, crevice);
		spec = 0.65;
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
		float fres = pow(1.0 - clamp(dot(gn, vdir), 0.0, 1.0), 2.5);
		emit += base * vec3(1.0, 0.35, 0.35) * 0.18 * (1.0 - crevice);                 // subsurface red
		emit += vec3(0.35, 0.55, 1.0) * fres * 0.45 * smoothstep(-0.2, 0.9, -gn.x + gn.y * 0.3);  // lake rim
		vec2 nd = vec2(-fd.y, fd.x) * cos(across * 1.7) * 0.16 + vec2(-fd.y, fd.x) * (bundle - 0.5) * 0.3;
		n = normalize(gn + vec3(nd.x, -nd.y, 0.0) + (dn - gn) * 0.2);
		if (art == 1) {
			// the key-door hint: faint slow-pulsing rune veins
			float vein = smoothstep(0.985, 0.998, ridge(p * 0.35 + fw2 * 0.4));
			emit += vec3(1.0, 0.15, 0.2) * vein * (0.06 + 0.06 * sin(TIME * 0.8 + p.y * 0.2));
		}
	} else if (mat == M_WOOD) {
		float grain = sin(p.x * 2.0 + fbm2(vec2(p.x * 0.5, p.y * 3.0)) * 4.0) * 0.5 + 0.5;
		albedo *= mix(0.7, 1.1, grain);
		rough = 0.7;
		n = normalize(mix(gn, dn, 0.5));
	} else if (mat == M_CLOUD) {
		// tornado: swirling wind-carved vapour
		// tornado: vapour bands whirling around the funnel axis
		float ax = 22.0 - (p.y - 80.0) * 0.12;
		float band = p.y * 0.55 + fbm2(vec2(p.x * 0.2, p.y * 0.3)) * 2.5 + sin((p.x - ax) * 0.35 - t * 2.2) * 0.9;
		float swirl = fbm3(vec2((p.x - ax) * 0.45 - t * 1.6, band) + fbm2(p * 0.25 - t * 0.3));
		float streak = smoothstep(0.2, 0.9, sin(band * 2.2 + swirl * 3.5) * 0.5 + 0.5) * (fbm2(p * 0.9 - t * 0.5) * 0.5 + 0.5);
		albedo *= mix(0.6, 1.25, streak + 0.2 * (swirl * 0.5 + 0.5));
		emit += albedo * 0.06;
		rough = 0.95;
		n = normalize(gn + vec3(0.0, (streak - 0.5) * 0.35, 0.0));
	} else if (mat == M_CRAG) {
		// mountain crag: tilted layered rock strata, sharp ledges catching the sun, scree on the slopes
		vec3 rock = mix(albedo, vec3(dot(albedo, vec3(0.33))) * vec3(1.05, 0.97, 0.9), 0.6);
		float sy = p.y * 1.3 + p.x * 0.22 + fbm2(p * vec2(0.08, 0.2)) * 2.0;
		float fs = fract(sy);
		float ledge = smoothstep(0.0, 0.12, fs) * (1.0 - smoothstep(0.55, 1.0, fs));
		float band = hash12(vec2(floor(sy), 3.0));
		albedo = rock * mix(0.6, 1.2, band) * mix(0.6, 1.15, ledge) * mix(0.85, 1.08, dh);
		float scree = step(0.82, hash12(floor(p * 7.0))) * up;
		albedo = mix(albedo, rock * 1.25, scree * 0.6);
		rough = 0.85;
		spec = 0.35;
		n = normalize(gn + vec3(0.0, (ledge - 0.5) * 0.5, 0.0) + (dn - gn) * 0.5);
	} else if (mat == M_RUIN) {
		// weathered temple ashlar: big irregular world-space blocks (warped running bond, not the tile grid),
		// darker mortar joints, chipped lighter edges, moss and lichen in joints and on ledges, rain streaks
		vec2 q = p + vec2(fbm2(p * 0.4), fbm2(p * 0.4 + 3.0)) * 0.3;
		float row = floor(q.y * 0.8);
		vec2 bq = vec2(q.x * 0.5 + hash12(vec2(row, 1.7)) * 3.0, q.y * 0.8);
		vec2 bi = floor(bq);
		vec2 bf = bq - bi;
		float joint = min(min(bf.x, 1.0 - bf.x) * 2.0, min(bf.y, 1.0 - bf.y));
		float jl = 1.0 - smoothstep(0.02, 0.08, joint);
		float tone = hash12(bi + 7.0);
		albedo *= mix(0.8, 1.12, tone) * mix(0.82, 1.08, dh) * (1.0 - jl * 0.5);
		float chip = 1.0 - smoothstep(0.0, 0.14, max(s.x, 0.0));
		albedo *= 1.0 + chip * 0.18;
		float mossn = fbm3(p * 0.33 + 5.0) * 0.5 + 0.5;
		float moss = smoothstep(0.45, 0.85, mossn + up * 0.45 + jl * 0.12 - 0.2) * smoothstep(-1.5, -0.2, wp.z + 0.8);
		albedo = mix(albedo, vec3(0.13, 0.24, 0.06) * mix(0.8, 1.3, dh), moss * 0.8);
		float streak = smoothstep(0.62, 0.95, fbm2(vec2(p.x * 2.6, p.y * 0.15))) * (1.0 - up);
		albedo *= 1.0 - streak * 0.22;
		rough = mix(0.72, 0.95, moss);
		spec = 0.4;
		n = normalize(mix(gn, triplanar_normal(detail_nrm2, wp, gn, 0.5), 0.75) - vec3(0.0, 0.0, jl * 0.25));
	} else if (mat == M_BONE) {
		// pale polished bone: bright ivory, porous micro-pits, a warm subsurface lift
		albedo = mix(albedo, vec3(0.92, 0.88, 0.78), 0.6) * mix(0.82, 1.05, dh);
		emit += albedo * 0.06;
		rough = 0.38;
		n = normalize(mix(gn, dn, 0.4));
	} else {
		n = normalize(mix(gn, dn, 0.8 * detail_amt));
	}

	float pbr_k = (layer == 2) ? 0.0 : pbr_terrain(mat, wp, gn, p, CAMERA_POSITION_WORLD, albedo, n, rough, ao);
	if (scroll_rect.x >= 0.0 && layer == 1) {
		// back walls behind air must read recessed and non-solid: darker (<= ~55% of the fg value), flatter
		// relief and light, strong AO toward the foreground edges, cooler, no highlights
		albedo *= 0.5;
		albedo = mix(albedo, albedo * vec3(0.85, 0.92, 1.08), 0.6);
		n = normalize(mix(vec3(0.0, 0.0, 1.0), n, 0.35));
		rough = 0.95;
		spec = 0.12;
		ao *= mix(0.45, 1.0, smoothstep(-0.05, -1.4, s.x));
		emit *= 0.3;
	}
	if (layer == 0) {
		// soft rim of the bevel catches light; tiny cavity darkening at colour boundaries
		albedo *= mix(1.0, 0.8, boundary);
		// grass / moss on up-facing edges of earth near the surface
	}

	if (debug_mode == 2) {
		float zi = texelFetch(zone_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(level_size) - 1), 0).r * 255.0;
		vec3 zc = 0.5 + 0.5 * cos(6.2831 * (zi * 0.13 + vec3(0.0, 0.33, 0.67)));
		emit += zc * 0.8;
		albedo *= 0.3;
	}
	if (debug_mode == 1) {
		vec2 g = abs(fract(p) - 0.5);
		float line = step(0.47, max(g.x, g.y));
		ivec2 ti = ivec2(floor(p));
		float solid = texelFetch(info_tex, clamp(ti, ivec2(0), ivec2(level_size) - 1), 0).r;
		emit += vec3(solid, 1.0 - solid, 0.0) * 0.25 + vec3(1.0, 1.0, 0.0) * line * 0.6;
	}

	// ---- material transitions (day levels): pair-specific blends along the soft neighbourhood masks ----
	if (scroll_rect.x >= 0.0 && layer == 0 && mat != M_WATER) {
		// warped lookup so bands never follow the tile grid
		vec2 tq = p + vec2(fbm2(p * 1.3), fbm2(p * 1.3 + 5.0)) * 0.35;
		vec4 tr = textureLod(trans_tex, tq / level_size, 0.0);
		// sample slightly above: what sits on top of this tile (canopy overhang, grass fringe)
		vec4 tr_up = textureLod(trans_tex, (tq - vec2(0.0, 0.6)) / level_size, 0.0);
		float nz = fbm2(p * 3.1) * 0.5 + 0.5;
		vec3 leaf = srgb_to_lin(vec3(0.3, 0.52, 0.16));
		vec3 soil = srgb_to_lin(vec3(0.3, 0.2, 0.12));
		if (mat != M_FOLIAGE) {
			// LEAVES -> trunk / earth / stone: leaves spill over the top (height-based: canopy is 'higher'),
			// litter speckles on up-faces below canopies
			float spill = smoothstep(0.25, 0.7, tr_up.r + (nz - 0.5) * 0.5) * smoothstep(0.0, 0.5, gn.y + 0.4);
			albedo = mix(albedo, leaf * mix(0.6, 1.1, nz), spill * 0.85);
			float litter = step(0.8, hash12(floor(p * 7.0))) * smoothstep(0.1, 0.4, tr.r + tr_up.r) * smoothstep(0.4, 0.8, gn.y);
			albedo = mix(albedo, mix(srgb_to_lin(vec3(0.45, 0.32, 0.12)), leaf, hash12(floor(p * 7.0) + 3.0)), litter * 0.8);
		}
		if (mat != M_GRASS && mat != M_FOLIAGE) {
			// GRASS -> earth: overhanging grass fringe fading down the face, with dangling root streaks
			float fringe = smoothstep(0.2, 0.75, tr_up.g + (nz - 0.5) * 0.4);
			albedo = mix(albedo, srgb_to_lin(vec3(0.3, 0.46, 0.14)) * mix(0.7, 1.1, nz), fringe * 0.7);
			float roots = smoothstep(0.93, 0.99, ridge(vec2(p.x * 3.0 + fbm2(p) * 0.6, p.y * 0.5))) * smoothstep(0.05, 0.4, tr_up.g) * (1.0 - fringe);
			albedo = mix(albedo, soil * 0.6, roots * 0.7);
		}
		if (mat == M_RUIN || mat == M_STONE) {
			// EARTH -> STONE: soil packed into the stone, moss creeping up from the earth side
			float earthy = 1.0 - max(max(tr.a, tr.r), tr.g);
			albedo = mix(albedo, soil * mix(0.8, 1.2, nz), smoothstep(0.35, 0.8, earthy + (nz - 0.5) * 0.4) * 0.45);
			float creep = smoothstep(0.3, 0.8, tr.g + tr.r * 0.6 + (nz - 0.5) * 0.5);
			albedo = mix(albedo, srgb_to_lin(vec3(0.2, 0.34, 0.1)), creep * 0.5 * smoothstep(-0.2, 0.6, gn.y));
		}
		// WATER -> stone / earth: wet dark band with algae near the waterline
		float wetb = smoothstep(0.05, 0.5, tr.b + (nz - 0.5) * 0.25);
		albedo = mix(albedo, albedo * 0.45, wetb * 0.8);
		albedo = mix(albedo, srgb_to_lin(vec3(0.12, 0.3, 0.12)), wetb * smoothstep(0.4, 0.7, nz) * 0.5);
		rough = mix(rough, 0.18, wetb * 0.8);
		spec = mix(spec, 0.7, wetb * 0.6);
	}
	// crisp micro grain on every rock-like surface
	if (pbr_k < 0.5 && mat != M_WATER && mat != M_ICE && mat != M_GLASS && mat != M_GEM && mat != M_OBSIDIAN && mat != M_MARBLE) {
		// single planar projection (front-facing) is enough for the fine grain; skipped on steep cliffs
		float fz = smoothstep(0.35, 0.7, abs(gn.z));
		vec3 mt = texture(detail_nrm2, wp.xy * 1.6).xyz * 2.0 - 1.0;
		n = normalize(n + vec3(mt.xy, 0.0) * 0.55 * fz);
		float mh = mix(0.5, texture(detail_hgt, wp.xy * 2.1).r, fz);
		albedo *= mix(0.85, 1.1, mh);
		rough = clamp(rough + (mh - 0.5) * 0.25, 0.05, 1.0);
	}
	int vzf = int(texelFetch(visual_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(level_size) - 1), 0).r * 255.0 + 0.5);
	if (vzf == 4 && layer == 0 && mat != M_OBSIDIAN && mat != M_WATER) {
		// frozen cavern: soft snow caps on every up-facing surface, with sparkle
		float cap = smoothstep(0.35, 0.75, gn.y + fbm2(p * 2.0) * 0.25);
		albedo = mix(albedo, vec3(0.86, 0.9, 0.97), cap * 0.85);
		rough = mix(rough, 0.6, cap);
		vec3 vd2 = normalize(CAMERA_POSITION_WORLD - wp);
		emit += vec3(0.8, 0.9, 1.0) * cap * step(0.996, hash12(floor(wp.xy * 40.0 + vd2.xy * 6.0))) * 2.5;
	}
	// opening readability: a crisp thin dark contact line where the recess meets the solid, and a
	// subtle lighter lip on the solid's rim bevel, around every non-solid tile
	if (layer != 0) {
		float contact = 1.0 - smoothstep(0.07, 0.16, -s.x);
		ao *= mix(1.0, 0.25, contact);
	} else {
		float lip = smoothstep(0.02, 0.06, s.x) * (1.0 - smoothstep(0.06, 0.16, s.x)) * smoothstep(-0.3, 0.2, wp.z);
		albedo *= 1.0 + lip * 0.45;
	}
	if (layer == 0) {
		// the sides of the solid mass lose emission and detail as they recede
		emit *= smoothstep(-2.2, -0.15, wp.z);
	}
	// outside the level (the margin ring): fade to dark rock
	// margin: the continuing world recedes into atmospheric depth
	albedo *= mix(1.0, 0.45, smoothstep(1.0, 12.0, p_out));
	emit *= 1.0 - smoothstep(1.0, 4.0, p_out);
	if (layer != 0 && fld.a < 0.5) {
		// inscription pocket floor: the parchment / stone itself, only slightly shaded (ink goes on top)
		vec3 fc; int fm; float fb;
		region_sample(fgcol_tex, p, 6.0, fc, fm, fb);
		albedo = fc * 0.62;
		ao = 0.85;
	}
	emit += rune_emit;
	if (scroll_rect.x >= 0.0 && layer == 0 && gn.y < -0.25) {
		// heavy undersides over open sky: shadowed, a touch of moss/damp - masses feel grounded
		float skyb = field_at(p + vec2(0.0, 0.8)).r;
		float under = smoothstep(-0.25, -0.8, gn.y) * skyb;
		albedo = mix(albedo, albedo * vec3(0.42, 0.45, 0.4), under);
		ao *= 1.0 - under * 0.35;
	}
	if (scroll_rect.x >= 0.0 && layer == 0) {
		// silhouettes against the sky: warm sun rim on sunward (upper-left) edges, cool sky rim elsewhere
		vec2 outp = vec2(gn.x, -gn.y);
		float sky_here = field_at(p + normalize(outp + vec2(0.0001)) * 0.7).r;
		float edge = pow(1.0 - clamp(gn.z, 0.0, 1.0), 1.5) + (1.0 - smoothstep(0.0, 0.2, max(s.x, 0.0))) * 0.5;
		float sunward = smoothstep(-0.2, 0.7, dot(normalize(vec2(gn.x, gn.y) + vec2(0.0001)), normalize(vec2(-0.6, 0.8))));
		vec3 rimc = mix(vec3(0.45, 0.6, 0.95) * 0.35, vec3(1.0, 0.8, 0.5) * 0.8, sunward);
		emit += albedo * rimc * clamp(edge, 0.0, 1.0) * sky_here * smoothstep(-1.5, 0.2, wp.z);
	}
	n = normalize(n + rune_n);
	ALBEDO = albedo * ao;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	if (debug_mode == 3) {
		ALBEDO = vec3(0.0); ROUGHNESS = 1.0; SPECULAR = 0.0; METALLIC = 0.0; AO = 1.0;
		EMISSION = vec3(s.x >= -0.02 ? 1.0 : 0.0);
	}
}
