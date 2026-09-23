shader_type spatial;
render_mode depth_draw_opaque, cull_back;
// WorldVoxel blocks. Faces are merged quads; everything per block is resolved here from the 3D block-id
// texture: the block's colour (the level's palette) with per-block jitter, Minecraft grass sides, log rings,
// smooth vertex-style ambient occlusion from the 8 neighbours of the face, bevelled convex edges, faint block
// seams, the shared photoscan detail (pbr_detail) and aerial haze toward the sky colour (vista_common) so the
// landscape melts into the vista and open gameplay air keeps reading as open.

#include "res://shaders/world/pbr_detail.gdshaderinc"
#include "res://shaders/world/vista_common.gdshaderinc"

uniform sampler3D vol : filter_nearest, repeat_disable;
uniform vec3 vol_origin = vec3(-72.0, -240.0, 3.0);
uniform ivec3 vol_size = ivec3(544, 280, 88);
uniform vec3 blk_col[18];
uniform vec3 grass_b = vec3(0.06, 0.23, 0.005);
uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform float fog_density = 0.0011;
uniform float haze_near = 0.10;      // readability haze at the volume front ...
uniform float haze_far = 0.46;       // ... and at its back (the vista's near haze takes over there)
uniform float haze_gain = 1.0;
uniform float fade = 1.0;            // build fade-in (0 = fully hazed)
uniform float ao_strength = 0.62;

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
	// --- colour
	vec3 bcf = vec3(bc);
	float hb = h31(bcf + 0.5);
	float hb2 = h31(bcf.zxy + 17.3);
	vec3 albedo = blk_col[clamp(id, 0, 17)];
	int mat = PBR_M_STONE;
	int layer = PBR_ROCK;
	float tscale = 0.35;
	bool top = gn.y > 0.5;
	bool side = abs(gn.y) < 0.5;
	float big = vnoise2(bcf.xz * 0.07) * 0.65 + vnoise2(bcf.xz * 0.21 + 3.1) * 0.35;
	if (id == B_GRASS || id == B_SNOW_GRASS) {
		bool open_up = occ(bc + ivec3(0, 1, 0)) < 0.5;
		// Minecraft grass side: dirt with a jagged fringe of turf hanging over the top edge
		float fy = fract(wp.y);
		float jag = pbr_hash(vec2(floor(u * 8.0), bcf.x * 3.1 + bcf.z * 7.7 + bcf.y)) * 0.22;
		bool fringe = side && open_up && fy > 0.80 - jag;
		if (top || fringe) {
			if (id == B_GRASS) {
				albedo = mix(albedo, grass_b, smoothstep(0.3, 0.75, big));
				mat = PBR_M_GRASS; layer = PBR_GRASS; tscale = 0.55;
			} else {
				mat = PBR_M_SNOW; layer = PBR_MARBLE; tscale = 0.3;
			}
		} else if (side || gn.y < -0.5) {
			albedo = blk_col[B_DIRT];
			mat = PBR_M_EARTH; layer = PBR_SOIL; tscale = 0.4;
		}
	} else if (id == B_DIRT || id == B_DIRT_L || id == B_CLAY) {
		mat = PBR_M_EARTH; layer = PBR_SOIL; tscale = 0.4;
	} else if (id == B_SAND || id == B_GRAVEL) {
		mat = PBR_M_SAND; layer = id == B_SAND ? PBR_SAND : PBR_ROCK; tscale = id == B_SAND ? 0.5 : 0.9;
	} else if (id == B_SNOW) {
		mat = PBR_M_SNOW; layer = PBR_MARBLE; tscale = 0.3;
	} else if (id == B_LOG || id == B_PINE_LOG) {
		mat = PBR_M_WOOD; layer = PBR_BARK; tscale = 0.5;
		if (!side) {
			// end grain: rings
			vec2 q = vec2(u, v) - 0.5;
			float rr = length(q);
			albedo = mix(albedo * 1.6, albedo * 1.15, 0.5 + 0.5 * sin(rr * 40.0));
			albedo *= 1.0 - smoothstep(0.42, 0.5, max(abs(q.x), abs(q.y))) * 0.5;
			layer = PBR_SOIL;
		}
	} else if (id == B_LEAVES || id == B_PINE) {
		mat = PBR_M_FOLIAGE; layer = PBR_LITTER; tscale = 0.45;
		albedo *= mix(0.78, 1.12, big);
	} else if (id == B_RUIN || id == B_RUIN_MOSS) {
		mat = PBR_M_RUIN; layer = PBR_ASHLAR; tscale = 0.5;
		if (id == B_RUIN_MOSS && top) {
			albedo = pbr_moss_color * 1.3;
			layer = PBR_MOSS;
		} else if (id == B_RUIN_MOSS) {
			albedo = mix(albedo, pbr_moss_color * 1.2, smoothstep(0.3, 0.9, fract(wp.y)));
		}
	} else if (id == B_STONE || id == B_STONE_W || id == B_STONE_L) {
		layer = (hb > 0.5) ? PBR_ROCK : PBR_STRATA;
		tscale = 0.35;
	}
	// per-block jitter (every cube a slightly different shade, like hand-placed blocks)
	albedo *= 0.9 + 0.2 * hb;
	albedo *= mix(0.92, 1.06, big);
	// --- bevels on convex edges + faint seams on every block edge
	vec3 n = gn;
	float bw = 0.14;
	float e1p = occ(bc + c1), e1n = occ(bc - c1), e2p = occ(bc + c2), e2n = occ(bc - c2);
	vec3 bend = vec3(0.0);
	bend += T1 * (1.0 - smoothstep(0.0, bw, 1.0 - u)) * (1.0 - e1p);
	bend -= T1 * (1.0 - smoothstep(0.0, bw, u)) * (1.0 - e1n);
	bend += T2 * (1.0 - smoothstep(0.0, bw, 1.0 - v)) * (1.0 - e2p);
	bend -= T2 * (1.0 - smoothstep(0.0, bw, v)) * (1.0 - e2n);
	float convex = clamp(length(bend), 0.0, 1.0);
	n = normalize(n + bend * 0.9);
	float edge = min(min(u, 1.0 - u), min(v, 1.0 - v));
	float seam = 1.0 - smoothstep(0.0, 0.03, edge);
	albedo *= 1.0 - seam * 0.16 * (1.0 - convex);
	albedo *= 1.0 + convex * 0.1;   // worn, sunlit rims
	// --- photoscan detail, sampled with a per-block offset so every block shows a different patch
	float rough = 0.88;
	float ao = block_ao;
	vec3 off = vec3(hb, hb2, h31(bcf + 5.7)) * 13.0;
	vec3 sp = floor(wp - gn * 0.25) + off + (wp - floor(wp - gn * 0.25));
	float fadek = pbr_fade(wp, CAMERA_POSITION_WORLD, 0.35) * pbr_strength;
	PbrS s = pbr_tri(layer, sp, gn, tscale, 1.0, false);
	float kalb = mat == PBR_M_SNOW ? 0.3 : 0.85;
	pbr_apply(s, kalb * fadek, 0.7 * fadek, 0.5, 0.0, albedo, n, rough, ao);
	if (mat == PBR_M_SNOW) {
		rough = 0.55;
	}
	if (gn.y < -0.5) {
		albedo *= 0.6;   // undersides: shadowed rock
	}
	// --- aerial haze toward the sky of the same direction
	vec3 sd = normalize(sun_dir);
	float f = vista_fog_f(wp, CAMERA_POSITION_WORLD, fog_density, 0.0);
	float dz = -wp.z - vol_origin.z;
	f = max(f, mix(haze_near, haze_far, smoothstep(0.0, 88.0, dz)));
	f = mix(1.0, f, fade);
	vec3 skyc = vista_sky(normalize(wp - CAMERA_POSITION_WORLD), sd);
	ALBEDO = albedo * mix(1.0, block_ao, 0.75) * (1.0 - f);
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	EMISSION = skyc * f * haze_gain;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
