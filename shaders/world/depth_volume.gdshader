shader_type spatial;
render_mode depth_draw_opaque, cull_back;
// Depth continuation volumes (WorldDepth): the level's masses extruded backward behind the gameplay slab.
// Faces are tile-exact boxes; every hue comes from the painting (the source tile's colour, jittered along
// the depth so faces don't streak), detail from the shared PBR library, and aerial haze with depth.

#include "res://shaders/world/pbr_detail.gdshaderinc"

uniform sampler2D fgcol_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D bgcol_tex : source_color, filter_nearest, repeat_disable;
uniform vec2 level_size = vec2(400.0, 200.0);
uniform sampler2D detail_nrm2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_hgt : filter_linear_mipmap, repeat_enable;
uniform vec2 haze_z = vec2(-2.0, -26.0);
uniform sampler2D depth_tex : filter_nearest, repeat_disable;   // R32F per tile: extrusion depth E (0 = none)
uniform vec3 haze_color : source_color = vec3(0.74, 0.82, 0.92);
uniform float haze_amt = 0.42;
uniform float haze_emit = 0.9;

varying vec3 w_pos;
varying vec2 tile;
varying float solid_f;
varying float kind;   // 0-3 volume face side, 10 = foreground lip top, 11 = lip cliff

const int M_EARTH = 1;
const int M_GRASS = 10;
const int M_FOLIAGE = 11;
const int M_RUIN = 20;
const int M_CRAG = 21;
const int M_MARBLE = 3;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

bool covered(ivec2 t, float d) {
	if (t.x < 0 || t.y < 0 || t.x >= int(level_size.x) || t.y >= int(level_size.y)) {
		return false;
	}
	return texelFetch(depth_tex, t, 0).r >= d;
}

// Rounded edges: bend the normal outward near every CONVEX edge of the tile box (neighbours not covered at
// this depth), so the extruded masses read as weathered rounded rock instead of sharp voxels.
vec3 bevel(vec3 n, int side, ivec2 tc, vec3 wp, float d) {
	float bw = 0.34;
	float e = texelFetch(depth_tex, tc, 0).r;
	float kb = 1.0 - smoothstep(0.0, bw, e - d);
	vec3 o = vec3(0.0, 0.0, -1.0) * kb;   // back edge (the volume ends there)
	float dt = -float(tc.y) - wp.y;        // distance below the tile's top edge
	float dl = wp.x - float(tc.x);         // distance from the tile's left edge
	if (side <= 1) {
		int sx = side == 0 ? -1 : 1;
		if (!covered(tc + ivec2(0, -1), d) && !covered(tc + ivec2(sx, -1), d)) {
			o += vec3(0.0, 1.0, 0.0) * (1.0 - smoothstep(0.0, bw, dt));
		}
		if (!covered(tc + ivec2(0, 1), d) && !covered(tc + ivec2(sx, 1), d)) {
			o += vec3(0.0, -1.0, 0.0) * (1.0 - smoothstep(0.0, bw, 1.0 - dt));
		}
	} else {
		int sy = side == 2 ? -1 : 1;
		if (!covered(tc + ivec2(-1, 0), d) && !covered(tc + ivec2(-1, sy), d)) {
			o += vec3(-1.0, 0.0, 0.0) * (1.0 - smoothstep(0.0, bw, dl));
		}
		if (!covered(tc + ivec2(1, 0), d) && !covered(tc + ivec2(1, sy), d)) {
			o += vec3(1.0, 0.0, 0.0) * (1.0 - smoothstep(0.0, bw, 1.0 - dl));
		}
	}
	return normalize(n + o * 1.5);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tile = UV;
	solid_f = UV2.x;
	kind = UV2.y;
}

void fragment() {
	vec3 wp = w_pos;
	vec3 gn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float d = -1.2 - wp.z;
	bool horiz = abs(gn.y) > 0.5;
	// colour: the source tile, jittered to its neighbours along the depth (strata / patches, not streaks)
	vec2 ps = tile;
	float jn = vnoise(vec2(d * 0.45, (horiz ? tile.x : tile.y) * 0.7)) - 0.5;
	if (horiz) {
		ps.x += jn * 1.8;
	} else {
		ps.y += jn * 1.4;
	}
	ivec2 ti = clamp(ivec2(floor(ps)), ivec2(0), ivec2(level_size) - 1);
	vec4 c = solid_f > 0.5 ? texelFetch(fgcol_tex, ti, 0) : texelFetch(bgcol_tex, ti, 0);
	int mat = solid_f > 0.5 ? int(texelFetch(fgcol_tex, ivec2(floor(tile)), 0).a * 255.0 + 0.5) : -1;
	vec3 albedo = c.rgb;
	bool lip = kind > 9.5 && kind < 11.5;
	bool skin = kind > 11.5;
	if (lip) {
		horiz = kind < 10.5;
		if (horiz) {
			mat = M_GRASS;   // the ledge's top: a lawn with patchy earth
			float pn = vnoise(wp.xz * 0.45) * 0.7 + vnoise(wp.xz * 1.7) * 0.3;
			albedo = mix(vec3(0.07, 0.14, 0.03), vec3(0.13, 0.2, 0.05), vnoise(wp.xz * 2.3));
			albedo = mix(albedo, vec3(0.17, 0.12, 0.07), smoothstep(0.6, 0.78, pn));   // bare earth patches
		} else {
			mat = M_EARTH;
			albedo = mix(c.rgb, vec3(0.2, 0.15, 0.1), 0.5) * mix(0.7, 1.0, vnoise(vec2(wp.x * 0.8, wp.y * 2.5)));
		}
	}
	float rough = 0.85;
	float ao = 1.0;
	vec3 n = gn;
	// plane coordinates of this face (u across, v along the depth)
	vec2 q = horiz ? vec2(wp.x, -wp.z) : vec2(-wp.z, -wp.y);
	if (mat == M_RUIN || mat == M_MARBLE) {
		// dressed ashlar: running bond of big blocks with darker joints
		vec2 wq = q + vec2(vnoise(q * 0.4), vnoise(q * 0.4 + 3.0)) * 0.3;
		float row = floor(wq.y * 0.8);
		vec2 bq = vec2(wq.x * 0.5 + h21(vec2(row, 1.7)) * 3.0, wq.y * 0.8);
		vec2 bi = floor(bq);
		vec2 bf = bq - bi;
		float joint = min(min(bf.x, 1.0 - bf.x) * 2.0, min(bf.y, 1.0 - bf.y));
		float jl = 1.0 - smoothstep(0.02, 0.08, joint);
		albedo *= mix(0.82, 1.1, h21(bi + 7.0)) * (1.0 - jl * 0.45);
		if (mat == M_MARBLE) {
			albedo = vec3(0.4, 0.36, 0.29) * mix(0.88, 1.05, h21(bi + 3.0));   // V-bird stone: warm grey-cream
		}
	} else if (mat == M_EARTH || mat == M_CRAG) {
		// soil / rock strata on the receding cliff walls
		float sy = -wp.y * 1.2 + vnoise(q * vec2(0.2, 0.5)) * 1.4;
		albedo *= mix(0.84, 1.08, sin(sy * 3.1) * 0.25 + 0.5 + (h21(vec2(floor(sy), 7.0)) - 0.5) * 0.5);
	} else if (mat == -1) {
		albedo *= 0.8;   // interior walls: the painted back-wall colour, a little shaded
	}
	bool leafy = mat == M_GRASS || mat == M_FOLIAGE;
	if (leafy && !horiz) {
		albedo *= 0.62;   // inside a crown / a turf wall: shaded leaves, not a lit lawn
	}
	{
		// big rock lumps so the receding faces aren't flat planes (the slab front is sculpted)
		vec3 U = horiz ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
		vec3 V = horiz ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		vec2 luv = horiz ? wp.xz : wp.zy;
		vec3 t1 = texture(detail_nrm2, luv * 0.18).xyz * 2.0 - 1.0;
		vec3 t2 = texture(detail_nrm2, luv * 0.55 + 0.37).xyz * 2.0 - 1.0;
		vec2 tb = t1.xy * 0.75 + t2.xy * 0.4;
		n = normalize(n + (U * tb.x + V * tb.y) * (mat == M_RUIN ? 0.35 : (leafy ? (horiz ? (lip ? 0.6 : 0.25) : 0.6) : 0.7)));
		albedo *= mix(0.8, 1.1, texture(detail_hgt, luv * 0.2).r);
	}
	if (kind < 9.5) {
		n = bevel(n, int(kind + 0.5), ivec2(floor(tile)), wp, d);
	}
	pbr_terrain(mat, wp, gn, vec2(wp.x, -wp.y), CAMERA_POSITION_WORLD, albedo, n, rough, ao);
	// patchy large-scale tone so the hillsides don't read as one flat colour
	albedo *= mix(0.86, 1.08, vnoise(vec2(wp.x, wp.z) * 0.12));
	if (gn.y < -0.5) {
		albedo *= 0.45;   // undersides: shadowed rock
		ao *= 0.8;
	}
	// contact shading where the volume leaves the slab (matches the slab cliff's darkening)
	if (!lip) {
		ao *= mix(0.75, 1.0, smoothstep(0.0, 2.5, d));
	}
	float hz = smoothstep(haze_z.x, haze_z.y, wp.z) * haze_amt;
	if (!horiz && !lip && !skin) {
		// structure side faces recede into the air: lighter and hazier with depth, so the open air beside a
		// tower still reads as sky
		hz = max(hz, smoothstep(0.5, 10.0, d) * 0.38);
	}
	if (lip && horiz) {
		albedo *= 0.65;   // the near ledge is seen at a grazing angle in full sun: keep it below the level's lawns
	}
	if (lip) {
		// the cliff dissolves into the sky below the world
		hz = smoothstep(-level_size.y - 0.5, -level_size.y - 6.5, wp.y) * 0.85;
	}
	ALBEDO = albedo * ao * (1.0 - hz);
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	EMISSION = haze_color * hz * haze_emit;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
