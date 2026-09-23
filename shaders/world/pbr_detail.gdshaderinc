// PBR surface detail library (CC0 Poly Haven photoscans, see assets/world/pbr/LICENSES.md).
// Textures add DETAIL ONLY (luminance, height, AO, roughness, normal); every hue still comes from the
// painting (the tile's minimap colour), so the canonical art is preserved.
//
// Array (bound by WorldPbr.bind(material)), ONE fetch per sample:
//   pbr_tex : R = grey-balanced luminance * 0.5 (0.5 = x1.0, cavity AO baked in), G = height,
//             B/A = OpenGL tangent normal x/y (z reconstructed)
// All sampling is world-space (1 tile = 1 unit), triplanar with sharpened weights (1-2 planes per pixel),
// stochastic hex tiling (Mikkelsen 2022) against repetition, RNM normal blending, height-based layer
// blends and a camera-distance detail fade.

uniform sampler2DArray pbr_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float pbr_hex_dist = 60.0;     // stochastic (3-tap) tiling only closer than this; plain tiling beyond
uniform float pbr_strength = 1.0;      // global detail multiplier (0 disables the library's effect)
uniform float pbr_fade_near = 45.0;    // camera distance where detail starts to fade
uniform float pbr_fade_far = 110.0;    // camera distance where only a faint residue remains
uniform int pbr_level = 0;             // 0 = Forgotten Veil (day), 1 = Odyssey (night)
uniform sampler2D pbr_canopy_tex : filter_nearest, repeat_disable;   // R8 per tile: 1 = tree canopy foliage
uniform vec2 pbr_level_size = vec2(400.0, 200.0);

// layer indices in the arrays
const int PBR_GRASS = 0;     // leafy_grass
const int PBR_MOSS = 1;      // mossy_rock
const int PBR_ASHLAR = 2;    // castle_wall_varriation (dressed stone courses)
const int PBR_STRATA = 3;    // cliff_side (layered sedimentary cliff)
const int PBR_ROCK = 4;      // rock_face_03 (weathered rock surface)
const int PBR_BARK = 5;      // bark_brown_02
const int PBR_LITTER = 6;    // forest_leaves_02 (leaf litter / forest floor)
const int PBR_SOIL = 7;      // brown_mud
const int PBR_SAND = 8;      // sand_01
const int PBR_MARBLE = 9;    // marble_rock_01
const int PBR_BASALT = 10;   // dark_rock (volcanic)
const int PBR_REDEARTH = 11; // red_dirt_mud_01
const int PBR_LICHEN = 12;   // lichen_rock

struct PbrS {
	float lum;    // detail luminance multiplier, mean 1.0
	float h;      // height 0..1
	float ao;     // cavity AO 0..1
	float rough;  // roughness 0..1
	vec3 n;       // WORLD-space detail normal (already combined with the base normal)
};

float pbr_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Reoriented normal mapping (Barré-Brisebois & Hill), both in tangent space, z up.
vec3 pbr_rnm(vec3 base, vec3 detail) {
	vec3 t = base + vec3(0.0, 0.0, 1.0);
	vec3 u = detail * vec3(-1.0, -1.0, 1.0);
	return t * dot(t, u) / t.z - u;
}

vec3 pbr_unpack_n(vec4 t) {
	vec2 xy = t.ba * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// One planar sample, hex-tiled when `hex`. uv is in plane space (world units * scale). rot_amt 0 = offsets
// only (directional textures: strata, bark, ashlar), 1 = full random rotation. Returns m = (lum*0.5, h, -, -)
// and the tangent normal in PLANE space (x along uv.x, y along uv.y), z out of the plane.
void pbr_hex(int layer, vec2 uv, float rot_amt, bool hex, out vec4 m, out vec3 tn) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	float lf = float(layer);
	if (!hex) {
		m = textureGrad(pbr_tex, vec3(uv, lf), dx, dy);
		vec3 t = pbr_unpack_n(m);
		tn = vec3(t.x, -t.y, t.z);   // GL green = image-up = -v
		return;
	}
	// triangle grid (hex tiles)
	vec2 st = uv * 1.1547005 * 1.6;   // ~1.4 texture repeats per hex cell
	vec2 sk = vec2(st.x - 0.57735027 * st.y, 1.15470054 * st.y);
	vec2 base = floor(sk);
	vec3 tmp = vec3(fract(sk), 0.0);
	tmp.z = 1.0 - tmp.x - tmp.y;
	float s = step(0.0, -tmp.z);
	float s2 = 2.0 * s - 1.0;
	vec3 w = vec3(-tmp.z * s2, s - tmp.y * s2, s - tmp.x * s2);
	vec2 vs[3] = vec2[3](base + vec2(s, s), base + vec2(s, 1.0 - s), base + vec2(1.0 - s, s));
	vec4 ms[3];
	vec3 ns[3];
	for (int k = 0; k < 3; k++) {
		float a = (pbr_hash(vs[k] + 0.37) - 0.5) * 6.2831853 * rot_amt;
		float ca = cos(a);
		float sa = sin(a);
		mat2 r = mat2(vec2(ca, sa), vec2(-sa, ca));
		vec2 off = vec2(pbr_hash(vs[k] + 11.7), pbr_hash(vs[k] - 5.3)) * 17.0;
		ms[k] = textureGrad(pbr_tex, vec3(r * uv + off, lf), r * dx, r * dy);
		vec3 t = pbr_unpack_n(ms[k]);
		ns[k] = vec3(transpose(r) * vec2(t.x, -t.y), t.z);
	}
	// height-aware, contrast-sharpened blend: the higher texel wins at hex borders (no ghosting)
	vec3 bw = pow(w, vec3(3.0)) * exp(vec3(ms[0].g, ms[1].g, ms[2].g) * 7.0);
	bw /= (bw.x + bw.y + bw.z);
	m = ms[0] * bw.x + ms[1] * bw.y + ms[2] * bw.z;
	tn = normalize(ns[0] * bw.x + ns[1] * bw.y + ns[2] * bw.z);
}

// Triplanar world-space detail around the base WORLD normal `n` (RNM-combined, Golus-style swizzles).
// Only planes with a meaningful weight are sampled (usually 1, 2 at bends).
PbrS pbr_tri(int layer, vec3 wp, vec3 n, float scale, float rot_amt, bool hex) {
	vec3 bw = pow(abs(n), vec3(8.0));
	bw /= (bw.x + bw.y + bw.z);
	bw = max(bw - 0.06, vec3(0.0));   // drop weak planes (1 plane on flats, 2 only on real bends)
	bw /= (bw.x + bw.y + bw.z);
	vec3 an = abs(n);
	vec3 sg = vec3(n.x < 0.0 ? -1.0 : 1.0, n.y < 0.0 ? -1.0 : 1.0, n.z < 0.0 ? -1.0 : 1.0);
	vec4 m = vec4(0.0);
	vec3 wn = vec3(0.0);
	if (bw.x > 0.0) {
		vec4 mm; vec3 tn;
		pbr_hex(layer, vec2(wp.z * sg.x, -wp.y) * scale, rot_amt, hex, mm, tn);   // side cliffs
		tn = vec3(tn.x, -tn.y, tn.z);                                              // uv.y = -world y
		tn = pbr_rnm(vec3(n.z * sg.x, n.y, an.x), tn);
		tn.z *= sg.x;
		m += mm * bw.x;
		wn += vec3(tn.z, tn.y, tn.x * sg.x) * bw.x;
	}
	if (bw.y > 0.0) {
		vec4 mm; vec3 tn;
		pbr_hex(layer, vec2(wp.x, wp.z) * scale, rot_amt, hex, mm, tn);            // tops / ceilings
		tn = pbr_rnm(vec3(n.x, n.z, an.y), tn);
		tn.z *= sg.y;
		m += mm * bw.y;
		wn += vec3(tn.x, tn.z, tn.y) * bw.y;
	}
	if (bw.z > 0.0) {
		vec4 mm; vec3 tn;
		pbr_hex(layer, vec2(wp.x * sg.z, -wp.y) * scale, rot_amt, hex, mm, tn);   // front faces (upright image)
		tn = vec3(tn.x, -tn.y, tn.z);
		tn = pbr_rnm(vec3(n.x * sg.z, n.y, an.z), tn);
		tn.z *= sg.z;
		m += mm * bw.z;
		wn += vec3(tn.x * sg.z, tn.y, tn.z) * bw.z;
	}
	PbrS r;
	r.lum = m.r * 2.0;
	r.h = m.g;
	r.ao = mix(0.6, 1.0, smoothstep(0.0, 0.55, m.g));   // cavities (low height) darker
	r.rough = clamp(0.62 + (1.0 - r.lum) * 0.22 + (0.5 - m.g) * 0.2, 0.2, 1.0);
	r.n = normalize(wn);
	return r;
}

// Height-based blend between two layers: t = coverage of b (0..1); b pushes through where it is higher.
float pbr_hblend(float ha, float hb, float t, float contrast) {
	float a = (1.0 - t) + ha;
	float b = t + hb;
	float ma = max(a, b) - contrast;
	float wa = max(a - ma, 0.0);
	float wb = max(b - ma, 0.0);
	return wb / max(wa + wb, 1e-4);
}

PbrS pbr_mix(PbrS a, PbrS b, float t) {
	PbrS r;
	r.lum = mix(a.lum, b.lum, t);
	r.h = mix(a.h, b.h, t);
	r.ao = mix(a.ao, b.ao, t);
	r.rough = mix(a.rough, b.rough, t);
	r.n = normalize(mix(a.n, b.n, t));
	return r;
}

// 1 near the camera, fading to `floor_v` far away.
float pbr_fade(vec3 wp, vec3 cam, float floor_v) {
	float d = length(cam - wp);
	return mix(1.0, floor_v, smoothstep(pbr_fade_near, pbr_fade_far, d));
}

// Apply a detail sample to the lit surface: luminance and cavity AO modulate the painted colour
// (hue untouched), normal and roughness blend toward the photoscan.
void pbr_apply(PbrS s, float k_alb, float k_nrm, float k_rough, float rough_bias, inout vec3 albedo, inout vec3 n, inout float rough, inout float ao) {
	float l = mix(1.0, s.lum, k_alb);
	float cav = mix(1.0, s.ao, k_alb * 0.7);
	albedo *= l * cav;
	n = normalize(mix(n, s.n, k_nrm));
	rough = clamp(mix(rough, s.rough + rough_bias, k_rough), 0.04, 1.0);
	ao *= mix(1.0, s.ao, 0.35 * k_alb);
}

// Terrain material ids (mirror WorldPalette.M_*); duplicated here so the include is self-contained.
const int PBR_M_EARTH = 1; const int PBR_M_STONE = 2; const int PBR_M_MARBLE = 3; const int PBR_M_OBSIDIAN = 8;
const int PBR_M_GRASS = 10; const int PBR_M_FOLIAGE = 11; const int PBR_M_WOOD = 13; const int PBR_M_METAL = 14;
const int PBR_M_SAND = 16; const int PBR_M_SNOW = 18; const int PBR_M_BONE = 19; const int PBR_M_RUIN = 20;
const int PBR_M_CRAG = 21; const int PBR_M_FLESH = 12; const int PBR_M_CORRUPT = 6;

// One-call terrain integration. Returns 1.0 if detail was applied (callers can then skip their own
// procedural micro grain), 0.0 otherwise.
//   mat   : material id of the pixel (-1 = back wall, -2 = deep cave)
//   wp    : world position; gn: geometric world normal; p: tile-space position (x, -y)
//   cam   : CAMERA_POSITION_WORLD
//   up    : clamp(gn.y, 0, 1)
float pbr_terrain(int mat, vec3 wp, vec3 gn, vec2 p, vec3 cam, inout vec3 albedo, inout vec3 n, inout float rough, inout float ao) {
	if (pbr_strength <= 0.0) {
		return 0.0;
	}
	float dist = length(cam - wp);
	float fade = pbr_fade(wp, cam, 0.35) * pbr_strength;
	float up = clamp(gn.y, 0.0, 1.0);
	bool hex = dist < pbr_hex_dist;   // far away: plain tiling (mips hide repeats, 1 tap instead of 3)
	// low-frequency world-space patch mask for secondary layers (smooth value noise, no tile grid)
	vec2 q = p * 0.23 + vec2(sin(p.y * 0.17), cos(p.x * 0.13)) * 1.3;
	vec2 qi = floor(q);
	vec2 fq = smoothstep(0.0, 1.0, fract(q));
	float patchv = mix(mix(pbr_hash(qi), pbr_hash(qi + vec2(1.0, 0.0)), fq.x),
		mix(pbr_hash(qi + vec2(0.0, 1.0)), pbr_hash(qi + vec2(1.0, 1.0)), fq.x), fq.y);
	bool leafy = mat == PBR_M_FOLIAGE || mat == PBR_M_GRASS;
	if (leafy && texelFetch(pbr_canopy_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(pbr_level_size) - 1), 0).r > 0.5) {
		// tree crowns: dense leaf scan, big leaves, strong relief
		PbrS l = pbr_tri(PBR_LITTER, wp, gn, 0.3, 1.0, hex);
		pbr_apply(l, 1.0 * fade, 0.9 * fade, 0.6, 0.0, albedo, n, rough, ao);
		return 1.0;
	}
	if (leafy) {
		// lawn, broken up by leaf-litter patches (secondary layer only where the patch mask is on)
		PbrS s = pbr_tri(PBR_GRASS, wp, gn, 0.55, 1.0, hex);
		float cov = smoothstep(0.45, 0.85, patchv) * 0.6;
		if (cov > 0.01) {
			PbrS l = pbr_tri(PBR_LITTER, wp, gn, 0.45, 1.0, false);
			s = pbr_mix(s, l, pbr_hblend(s.h, l.h, cov, 0.25));
		}
		pbr_apply(s, 1.0 * fade, 0.85 * fade, 0.6, 0.1, albedo, n, rough, ao);
		return 1.0;
	}
	if (mat == PBR_M_RUIN) {
		// weathered stone with lichen crusts (more on the tops)
		PbrS s = pbr_tri(PBR_ROCK, wp, gn, 0.33, 1.0, hex);
		float cov = smoothstep(0.4, 0.9, patchv) * 0.6 + up * 0.2;
		if (cov > 0.01) {
			PbrS m = pbr_tri(PBR_LICHEN, wp, gn, 0.4, 1.0, false);
			s = pbr_mix(s, m, pbr_hblend(s.h, m.h, cov, 0.2));
		}
		pbr_apply(s, 0.9 * fade, 0.8 * fade, 0.5, 0.05, albedo, n, rough, ao);
		return 1.0;
	}
	if (mat == PBR_M_EARTH) {
		// soil with embedded stones; Odyssey's earth uses the red laterite scan (still tinted by the painting)
		PbrS s = pbr_tri(pbr_level == 1 ? PBR_REDEARTH : PBR_SOIL, wp, gn, 0.4, 1.0, hex);
		float cov = smoothstep(0.6, 0.95, patchv) * 0.5;
		if (cov > 0.01) {
			PbrS r = pbr_tri(PBR_ROCK, wp, gn, 0.25, 1.0, false);
			s = pbr_mix(s, r, pbr_hblend(s.h, r.h, cov, 0.2));
		}
		pbr_apply(s, 0.9 * fade, 0.8 * fade, 0.5, 0.05, albedo, n, rough, ao);
		return 1.0;
	}
	if (mat == PBR_M_CRAG) {
		PbrS s = pbr_tri(PBR_STRATA, wp, gn, 0.2, 0.0, hex);
		pbr_apply(s, 0.9 * fade, 0.8 * fade, 0.5, 0.0, albedo, n, rough, ao);
		return 1.0;
	}
	if (mat == PBR_M_STONE || mat == PBR_M_METAL || mat == PBR_M_BONE) {
		PbrS s = pbr_tri(mat == PBR_M_BONE ? PBR_MARBLE : PBR_ROCK, wp, gn, 0.35, 1.0, hex);
		pbr_apply(s, 0.8 * fade, 0.75 * fade, mat == PBR_M_METAL ? 0.0 : 0.4, 0.0, albedo, n, rough, ao);
		return 1.0;
	}
	if (mat == PBR_M_SAND) {
		PbrS s = pbr_tri(PBR_SAND, wp, gn, 0.5, 1.0, hex);
		pbr_apply(s, 0.6 * fade, 0.6 * fade, 0.4, 0.0, albedo, n, rough, ao);
		return 1.0;
	}
	if (mat == PBR_M_WOOD) {
		PbrS s = pbr_tri(PBR_BARK, wp, gn, 0.5, 0.0, hex);
		pbr_apply(s, 0.9 * fade, 0.8 * fade, 0.5, 0.0, albedo, n, rough, ao);
		return 1.0;
	}
	if (mat == PBR_M_MARBLE) {
		PbrS s = pbr_tri(PBR_MARBLE, wp, gn, 0.3, 1.0, hex);
		pbr_apply(s, 0.35 * fade, 0.3 * fade, 0.0, 0.0, albedo, n, rough, ao);
		return 1.0;
	}
	if (mat == PBR_M_OBSIDIAN) {
		// normals only: keeps the glassy near-black readable
		PbrS s = pbr_tri(PBR_BASALT, wp, gn, 0.4, 1.0, false);
		n = normalize(mix(n, s.n, 0.35 * fade));
		return 1.0;
	}
	if (mat == -1) {
		// back walls: subtle rock grain (the wall pattern itself is world's); plain tiling is enough
		PbrS s = pbr_tri(PBR_ROCK, wp, gn, 0.3, 1.0, false);
		pbr_apply(s, 0.55 * fade, 0.55 * fade, 0.3, 0.05, albedo, n, rough, ao);
		return 1.0;
	}
	return 0.0;
}
