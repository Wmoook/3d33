shader_type spatial;
render_mode depth_draw_opaque, cull_back;
// WorldVoxel blocks. Faces are merged quads; everything per block is resolved here from the 3D block-id
// texture: the block's colour (the level's palette) with per-block jitter, Minecraft grass sides, log rings,
// smooth vertex-style ambient occlusion from the 8 neighbours of the face, bevelled convex edges, faint block
// seams, the shared photoscan detail (pbr_detail) and aerial haze toward the sky colour (vista_common) so the
// landscape melts into the vista and open gameplay air keeps reading as open.

#include "res://shaders/world/pbr_detail.gdshaderinc"
#include "res://shaders/world/vista_common.gdshaderinc"
#include "res://shaders/world/voxel_forest.gdshaderinc"

uniform sampler3D vol : filter_nearest, repeat_disable;
uniform vec3 vol_origin = vec3(-104.0, -256.0, 3.0);
uniform ivec3 vol_size = ivec3(608, 320, 160);
uniform vec3 blk_col[18];
uniform vec3 grass_b = vec3(0.06, 0.23, 0.005);
uniform sampler2D detail_nrm2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_hgt : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform float fog_density = 0.0011;
uniform float haze_near = 0.08;      // readability haze at the volume front ...
uniform float haze_far = 0.40;       // ... and at its back (the vista's near haze takes over there)
uniform float haze_gain = 1.0;
uniform float fade = 1.0;            // build fade-in (0 = fully hazed)
uniform float ao_strength = 0.42;
// readability: everything here is seen through open sky air, so no pixel may read much darker than the sky
// behind it. The lit luminance is predicted (sun + sky ambient, no shadows) and extra haze is added where it
// would fall below min_rel x the sky's luminance (linear), which keeps world's sky-luma check OK.
uniform float min_rel = 0.42;
uniform float k_sun = 1.6;
uniform float k_amb = 0.55;

varying vec3 w_pos;
varying vec3 w_nrm;

const int B_GRASS = 1; const int B_DIRT = 2; const int B_DIRT_L = 3; const int B_CLAY = 4;
const int B_STONE = 5; const int B_STONE_W = 6; const int B_STONE_L = 7; const int B_SAND = 8;
const int B_SNOW = 9; const int B_SNOW_GRASS = 10; const int B_LOG = 11; const int B_LEAVES = 12;
const int B_PINE = 13; const int B_RUIN = 14; const int B_RUIN_MOSS = 15; const int B_GRAVEL = 16;
const int B_PINE_LOG = 17;

ivec3 to_cell(vec3 p) {
	return ivec3(int(floor(p.x - vol_origin.x)), int(floor(p.y - vol_origin.y)), int(floor(-p.z - vol_origin.z)));
}

int vid(ivec3 c) {
	if (c.x < 0 || c.y < 0 || c.z < 0 || c.x >= vol_size.x || c.y >= vol_size.y || c.z >= vol_size.z) {
		return 0;
	}
	return int(texelFetch(vol, c, 0).r * 255.0 + 0.5);
}

float occ(ivec3 c) {
	int v = vid(c);
	return (v > 0 && v < 64) ? 1.0 : 0.0;
}

float h31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(pbr_hash(i), pbr_hash(i + vec2(1.0, 0.0)), f.x), mix(pbr_hash(i + vec2(0.0, 1.0)), pbr_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float ao_corner(float s1, float s2, float c) {
	return (s1 + s2 > 1.5) ? 0.0 : (3.0 - s1 - s2 - c) / 3.0;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 wp = w_pos;
	if (in_forest_hollow(w_pos, CAMERA_POSITION_WORLD)) {
		discard;
	}
	// under the level the keel dissolves (dithered) so the sky's cloud sea shows below the world, as without
	// voxels; only the first rows under the level's bottom edge stay as its rock edge
	if (wp.y < -201.0) {
		float kd = smoothstep(-201.0, -207.0, wp.y);
		if (kd > 0.999 || kd > pbr_hash(FRAGCOORD.xy * 0.73 + 0.5)) {
			discard;
		}
	}
	vec3 gn = normalize(w_nrm);
	ivec3 nc = ivec3(int(round(gn.x)), int(round(gn.y)), -int(round(gn.z)));   // cell-space normal
	ivec3 bc = to_cell(wp - gn * 0.25);
	ivec3 ac = bc + nc;
	int id = vid(bc);
	// in-face tangent frame (world) and its cell-space steps
	vec3 T1;
	vec3 T2;
	if (abs(gn.y) > 0.5) {
		T1 = vec3(1.0, 0.0, 0.0); T2 = vec3(0.0, 0.0, 1.0);
	} else if (abs(gn.x) > 0.5) {
		T1 = vec3(0.0, 0.0, 1.0); T2 = vec3(0.0, 1.0, 0.0);
	} else {
		T1 = vec3(1.0, 0.0, 0.0); T2 = vec3(0.0, 1.0, 0.0);
	}
	ivec3 c1 = ivec3(int(T1.x), int(T1.y), -int(T1.z));
	ivec3 c2 = ivec3(int(T2.x), int(T2.y), -int(T2.z));
	float u = fract(dot(wp, T1));
	float v = fract(dot(wp, T2));
	// --- smooth block AO (Minecraft-style corner occlusion, bilinear across the face)
	float s1p = occ(ac + c1), s1n = occ(ac - c1), s2p = occ(ac + c2), s2n = occ(ac - c2);
	float a00 = ao_corner(s1n, s2n, occ(ac - c1 - c2));
	float a10 = ao_corner(s1p, s2n, occ(ac + c1 - c2));
	float a01 = ao_corner(s1n, s2p, occ(ac - c1 + c2));
	float a11 = ao_corner(s1p, s2p, occ(ac + c1 + c2));
	float aov = mix(mix(a00, a10, u), mix(a01, a11, u), v);
	aov = aov * aov * (3.0 - 2.0 * aov);
	float block_ao = mix(1.0 - ao_strength, 1.0, aov);
	// sub-pixel detail fades with the pixel footprint (no sparkle / shimmer on distant blocks as the camera moves)
	float foot = length(fwidth(wp));
	float hf = 1.0 - smoothstep(0.04, 0.16, foot);
	// --- material: the SAME classes / look as the level's own blocks (world's depth_volume + terrain):
	// continuous world-space textures (no per-block patches, no pixel pattern), pillow bevels on convex edges,
	// detail lumps, lawn turf with blade texture, strata earth, ashlar ruin stone with moss, leaf-cluster crowns
	vec3 bcf = vec3(bc);
	vec3 albedo = blk_col[clamp(id, 0, 17)];
	bool top = gn.y > 0.5;
	bool side = abs(gn.y) < 0.5;
	bool horiz = abs(gn.y) > 0.5;
	vec2 pp = vec2(wp.x, -wp.y);
	float big = vnoise2(wp.xz * 0.07) * 0.65 + vnoise2(wp.xz * 0.21 + 3.1) * 0.35;
	int mat = PBR_M_STONE;
	bool lawn = false;     // grass top or the turf fringe of a grass block
	bool turf_side = false;
	if (id == B_GRASS || id == B_SNOW_GRASS) {
		bool open_up = occ(bc + ivec3(0, 1, 0)) < 0.5;
		// turf fringe hanging over the top edge (irregular, continuous along the face)
		float fy = fract(wp.y);
		// the level's turf wraps over the block sides: green down to a ragged soil edge near the bottom
		float jag = vnoise2(vec2(dot(wp, T1) * 3.1, bcf.y * 1.7)) * 0.35;
		bool fringe = side && open_up && fy > 0.18 + jag;
		if (top || fringe) {
			if (id == B_GRASS) {
				albedo = mix(albedo, grass_b, smoothstep(0.3, 0.75, big));
				mat = PBR_M_GRASS;
				lawn = true;
			} else {
				mat = PBR_M_SNOW;
				albedo = mix(albedo, vec3(0.62, 0.66, 0.7), 0.35);   // softer, less contrasty snow
			}
		} else {
			albedo = blk_col[B_DIRT];
			mat = PBR_M_EARTH;
			turf_side = side && open_up;
		}
	} else if (id == B_DIRT || id == B_DIRT_L || id == B_CLAY) {
		mat = PBR_M_EARTH;
	} else if (id == B_SAND || id == B_GRAVEL) {
		mat = PBR_M_SAND;
	} else if (id == B_SNOW) {
		mat = PBR_M_SNOW;
	} else if (id == B_LOG || id == B_PINE_LOG) {
		mat = PBR_M_WOOD;
	} else if (id == B_LEAVES || id == B_PINE) {
		mat = PBR_M_FOLIAGE;
	} else if (id == B_RUIN || id == B_RUIN_MOSS) {
		mat = PBR_M_RUIN;
	} else {
		mat = PBR_M_CRAG;   // natural rock: the strata cliff scan, like the level's crags
	}
	float rough = 0.85;
	float ao = block_ao;
	vec3 n = gn;
	// plane coordinates of this face (u across, v along the depth), as world's depth volume
	vec2 q = horiz ? vec2(wp.x, -wp.z) : (abs(gn.x) > 0.5 ? vec2(-wp.z, -wp.y) : vec2(wp.x, -wp.y));
	if (mat == PBR_M_RUIN) {
		// dressed ashlar: running bond of big blocks with darker mortar joints (world's depth_volume)
		vec2 wq = q + vec2(vnoise2(q * 0.4), vnoise2(q * 0.4 + 3.0)) * 0.3;
		float row = floor(wq.y * 0.8);
		vec2 bq = vec2(wq.x * 0.5 + pbr_hash(vec2(row, 1.7)) * 3.0, wq.y * 0.8);
		vec2 bi = floor(bq);
		vec2 bf = bq - bi;
		float joint = min(min(bf.x, 1.0 - bf.x) * 2.0, min(bf.y, 1.0 - bf.y));
		float jl = 1.0 - smoothstep(0.02, 0.08, joint);
		albedo *= mix(0.82, 1.1, pbr_hash(bi + 7.0)) * (1.0 - jl * 0.45);
		// moss in the joints and on the tops (the level's mossy ruins)
		float mz = (top ? 0.75 : 0.0) + jl * 0.5 + (id == B_RUIN_MOSS ? 0.4 : 0.0);
		mz *= smoothstep(0.35, 0.7, vnoise2(pp * 0.5) + (top ? 0.25 : 0.0));
		albedo = mix(albedo, pbr_moss_color * mix(0.7, 1.1, vnoise2(pp * 3.0)), clamp(mz, 0.0, 1.0) * 0.8);
	} else if (mat == PBR_M_EARTH || mat == PBR_M_CRAG) {
		// soil / rock strata on the faces (continuous across blocks)
		float sy = -wp.y * 1.2 + vnoise2(q * vec2(0.2, 0.5)) * 1.4;
		albedo *= mix(0.84, 1.08, sin(sy * 3.1) * 0.25 + 0.5 + (pbr_hash(vec2(floor(sy), 7.0)) - 0.5) * 0.5);
	} else if (mat == PBR_M_WOOD && horiz) {
		vec2 rq = fract(horiz ? wp.xz : wp.zy) - 0.5;
		albedo = mix(albedo * 1.5, albedo * 1.1, 0.5 + 0.5 * sin(length(rq) * 40.0));
	}
	bool leafy = mat == PBR_M_GRASS || mat == PBR_M_FOLIAGE;
	if (mat == PBR_M_FOLIAGE && side) {
		albedo *= 0.8;   // inside a crown: shaded leaves
	}
	{
		// big rock lumps / leaf clumps so faces aren't flat planes (world's detail normals, two scales)
		vec3 U = horiz ? vec3(1.0, 0.0, 0.0) : (abs(gn.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
		vec3 V = horiz ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		vec2 luv = horiz ? wp.xz : (abs(gn.x) > 0.5 ? wp.zy : wp.xy);
		vec3 t1 = texture(detail_nrm2, luv * 0.18).xyz * 2.0 - 1.0;
		vec3 t2 = texture(detail_nrm2, luv * 0.55 + 0.37).xyz * 2.0 - 1.0;
		vec2 tb = t1.xy * 0.75 + t2.xy * 0.4;
		float lump = mat == PBR_M_RUIN ? 0.35 : (mat == PBR_M_FOLIAGE ? 0.9 : (leafy ? 0.3 : 0.7));
		n = normalize(n + (U * tb.x + V * tb.y) * lump * hf);
		albedo *= mix(0.8, 1.1, texture(detail_hgt, luv * 0.2).r);
	}
	// pillow bevel: bend the normal outward near every CONVEX edge (world's day bevel profile)
	{
		float bw = 0.34;
		float e1p = occ(bc + c1), e1n = occ(bc - c1), e2p = occ(bc + c2), e2n = occ(bc - c2);
		vec3 bend = vec3(0.0);
		bend += T1 * (1.0 - smoothstep(0.0, bw, 1.0 - u)) * (1.0 - e1p);
		bend -= T1 * (1.0 - smoothstep(0.0, bw, u)) * (1.0 - e1n);
		bend += T2 * (1.0 - smoothstep(0.0, bw, 1.0 - v)) * (1.0 - e2p);
		bend -= T2 * (1.0 - smoothstep(0.0, bw, v)) * (1.0 - e2n);
		n = normalize(n + bend * 1.5 * mix(0.35, 1.0, hf));
	}
	// photoscan detail: the same library calls the level uses
	float fadek = pbr_fade(wp, CAMERA_POSITION_WORLD, 0.35) * pbr_strength * hf;
	bool hex = length(CAMERA_POSITION_WORLD - wp) < pbr_hex_dist;
	if (mat == PBR_M_GRASS) {
		// the level's lawn: grass scan broken by leaf-litter patches
		PbrS sg = pbr_tri(PBR_GRASS, wp, gn, 0.55, 1.0, hex);
		float cov = smoothstep(0.45, 0.85, vnoise2(pp * 0.23)) * 0.6;
		if (cov > 0.01) {
			PbrS l = pbr_tri(PBR_LITTER, wp, gn, 0.45, 1.0, false);
			sg = pbr_mix(sg, l, pbr_hblend(sg.h, l.h, cov, 0.25));
		}
		pbr_apply(sg, fadek, 0.85 * fadek, 0.6, 0.1, albedo, n, rough, ao);
	} else if (mat == PBR_M_FOLIAGE) {
		// leaf-cluster crowns: the dense leaf scan with big leaves, deep cavities
		PbrS sl2 = pbr_tri(PBR_LITTER, wp, gn, 0.3, 1.0, hex);
		pbr_apply(sl2, fadek, 0.9 * fadek, 0.6, 0.0, albedo, n, rough, ao);
		albedo *= mix(0.6, 1.0, sl2.h);
	} else if (mat == PBR_M_SNOW) {
		PbrS ss = pbr_tri(PBR_MARBLE, wp, gn, 0.3, 1.0, false);
		pbr_apply(ss, 0.3 * fadek, 0.5 * fadek, 0.3, 0.0, albedo, n, rough, ao);
		rough = 0.55;
	} else {
		vec3 a0 = albedo; vec3 n0 = n; float r0 = rough; float o0 = ao;
		pbr_terrain(mat, wp, gn, pp, CAMERA_POSITION_WORLD, albedo, n, rough, ao);
		albedo = mix(a0, albedo, hf); n = normalize(mix(n0, n, hf)); rough = mix(r0, rough, hf); ao = mix(o0, ao, hf);
	}
	if (turf_side) {
		// turf side under the lawn: soil laced with hanging roots (the level's turf edge)
		vec2 ruv = vec2(wp.x * 1.3 + wp.z * 1.3, -wp.y * 0.28);
		float rl = texture(pbr_tex, vec3(ruv, float(PBR_BARK))).r * 2.0;
		float roots = smoothstep(0.75, 0.25, rl) * (1.0 - smoothstep(0.0, 0.7, 1.0 - fract(wp.y)));
		albedo *= 1.0 - roots * 0.45 * fadek;
	}
	// patchy large-scale tone so the hillsides don't read as one flat colour
	albedo *= mix(0.88, 1.06, vnoise2(wp.xz * 0.12));
	if (gn.y < -0.5) {
		albedo *= 0.45;   // undersides: shadowed rock (as the level's volumes)
		ao *= 0.8;
	}
	// the keel under the level and the land's cut cliffs: darker toward the bottom (a rock mass seen from
	// above), and melting into the sky / cloud sea below y -215 (sky's cloud tops ~ -222)
	float low = smoothstep(-185.0, -215.0, wp.y);
	albedo *= mix(1.0, 0.55, low);
	// --- aerial haze toward the sky of the same direction
	vec3 sd = normalize(sun_dir);
	float f = vista_fog_f(wp, CAMERA_POSITION_WORLD, fog_density, 0.0);
	float dz = -wp.z - vol_origin.z;
	// the readability floors only matter near the gameplay plane: far things (z < -60) keep crisp colour
	float rk = 1.0 - smoothstep(55.0, 95.0, dz);
	f = max(f, mix(haze_near, haze_far, smoothstep(0.0, 120.0, dz)) * rk);
	vec3 skyc = vista_sky(normalize(wp - CAMERA_POSITION_WORLD), sd);
	vec3 lift = vec3(0.0);
	{
		vec3 lum_w = vec3(0.2126, 0.7152, 0.0722);
		float ndl = max(dot(n, sd), 0.0);
		vec3 pred = albedo * mix(1.0, block_ao, 0.75) * (k_sun * ndl * vec3(1.0, 0.86, 0.66) + k_amb * (0.6 + 0.4 * n.y));
		float pl = dot(pred, lum_w);
		float sl = dot(skyc, lum_w);
		// (no readability floor under the level: no gameplay air there, the keel may read as dark rock)
		float target = min_rel * sl * (0.8 + 0.2 * rk) * (1.0 - smoothstep(-199.0, -204.0, wp.y));
		float lit_l = mix(pl, sl, f);
		if (lit_l < target) {
			// near: lift with more haze (reads as air). Far: lift with the block's OWN hue (a touch of sky
			// blue), so distant islands stay colourful instead of milky
			float fh = clamp((target - pl) / max(sl - pl, 1e-3), f, 1.0);
			float far_w = 1.0 - rk;
			f = mix(fh, f, far_w);
			vec3 hue = albedo / max(dot(albedo, lum_w), 1e-3);
			hue = mix(hue, skyc / max(sl, 1e-3), 0.3);
			lift = hue * max(target - mix(pl, sl, f), 0.0) * far_w;
		}
	}
	f = max(f, smoothstep(-200.5, -217.0, wp.y));
	f = mix(1.0, f, fade);
	ALBEDO = albedo * mix(1.0, block_ao, 0.75) * (1.0 - f);
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	EMISSION = skyc * f * haze_gain + lift * fade;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
