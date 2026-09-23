shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;   // inner faces close every slit (see below)
// Depth continuation volumes (WorldDepth): the level's masses extruded backward behind the gameplay slab.
// Faces are tile-exact boxes; every hue comes from the painting (the source tile's colour, jittered along
// the depth so faces don't streak), detail from the shared PBR library, and aerial haze with depth.

#include "res://shaders/world/pbr_detail.gdshaderinc"

uniform sampler2D fgcol_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D bgcol_tex : source_color, filter_nearest, repeat_disable;
uniform vec2 level_size = vec2(400.0, 200.0);
uniform sampler2D detail_nrm2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_hgt : filter_linear_mipmap, repeat_enable;
uniform vec2 haze_z = vec2(-8.0, -30.0);   // no aerial haze on near faces
uniform sampler2D forest_tex : filter_nearest, repeat_disable;
uniform vec3 forest_fog : source_color = vec3(0.035, 0.07, 0.04);
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
	vec2 v = texelFetch(depth_tex, t, 0).rg;
	return v.r >= d && v.g <= d + 0.01;
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
	float sf = solid_f;
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
	vec4 c = sf > 0.5 ? texelFetch(fgcol_tex, ti, 0) : texelFetch(bgcol_tex, ti, 0);
	int mat = sf > 0.5 ? int(texelFetch(fgcol_tex, ivec2(floor(tile)), 0).a * 255.0 + 0.5) : -1;
	vec3 albedo = c.rgb;
	bool back = kind > 3.5 && kind < 4.5;   // a room's recessed back wall
	bool earth_back = back && sf > 0.5;   // (UV2.x = 1 on a back wall: an earth cave, not masonry)
	back = back && !earth_back;
	if (earth_back) {
		sf = 0.0;
	}
	// side faces bordering a room tile are the room's receding side walls / floor / ceiling
	ivec2 tcell = ivec2(floor(tile));
	int sidei = int(kind + 0.5);
	ivec2 across = sidei == 0 ? ivec2(-1, 0) : (sidei == 1 ? ivec2(1, 0) : (sidei == 2 ? ivec2(0, -1) : ivec2(0, 1)));
	float nstart = kind < 3.5 ? texelFetch(depth_tex, clamp(tcell + across, ivec2(0), ivec2(level_size) - 1), 0).g : 0.0;
	bool inroom = kind < 3.5 && nstart > 2.5 && nstart < 7.5;
	// any face of a solid that looks into non-sky air (a room, a recess, a pocket): it is the solid's own
	// shadowed rock / dirt - never sky-lit, no sky reflection
	float ownstart = texelFetch(depth_tex, clamp(tcell, ivec2(0), ivec2(level_size) - 1), 0).g;
	// ... and the edges of a room's back-wall block (where a room meets a forest hollow / open air)
	bool wallblock = kind < 3.5 && sf < 0.5 && ownstart > 2.5 && ownstart < 7.5;
	bool inner = kind < 3.5 && ((sf > 0.5 && nstart < 50.0) || wallblock);
	vec3 emit_x = vec3(0.0);
	bool lip = kind > 9.5 && kind < 11.5;
	bool prop = kind > 13.5 && kind < 15.5;   // cave roots (14) / floor rocks (15)
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
	} else if (mat == -1 && !back) {
		albedo *= 0.8;   // interior walls: the painted back-wall colour, a little shaded
	}
	if (earth_back) {
		// ---- earth cave back wall: packed dirt in the painted colour, strata, damp, pebbles, roots, darkness ----
		vec2 p = vec2(wp.x, -wp.y);
		float lum_c = dot(c.rgb, vec3(0.3, 0.55, 0.15));
		vec3 dirt = mix(vec3(0.13, 0.085, 0.045), vec3(0.19, 0.13, 0.07), vnoise(p * 0.35));
		albedo = mix(dirt * (0.6 + lum_c * 2.5), c.rgb * 0.7, 0.3);
		float sy = p.y * 1.3 + vnoise(p * vec2(0.12, 0.4)) * 1.6;
		albedo *= mix(0.75, 1.06, smoothstep(0.2, 0.8, fract(sy)));
		albedo *= 1.0 - smoothstep(0.55, 0.85, vnoise(p * 0.22 + 9.0)) * 0.3;
		vec2 pc = p * 2.3;
		vec2 pci = floor(pc);
		vec2 pcf = fract(pc) - 0.5 - (vec2(h21(pci), h21(pci + 3.1)) - 0.5) * 0.5;
		float peb = (1.0 - smoothstep(0.12, 0.2, length(pcf))) * step(0.8, h21(pci + 7.7));
		albedo = mix(albedo, vec3(0.24, 0.21, 0.18) * mix(0.8, 1.2, h21(pci + 1.3)), peb);
		n = normalize(vec3(pcf * 2.0 * peb * 0.8, 1.0));
		float rootl = abs(fract(p.x * 0.7 + vnoise(p * vec2(0.5, 0.15)) * 2.0) - 0.5);
		float root = (1.0 - smoothstep(0.02, 0.05, rootl)) * smoothstep(0.4, 0.7, vnoise(p * vec2(0.3, 0.1) + 5.0));
		albedo = mix(albedo, vec3(0.07, 0.045, 0.025), root * 0.8);
		mat = M_EARTH;
		rough = 0.97;
		vec2 fcell = p - floor(p);
		float edge_ao = 1.0;
		for (int k = 0; k < 4; k++) {
			ivec2 o = k == 0 ? ivec2(-1, 0) : (k == 1 ? ivec2(1, 0) : (k == 2 ? ivec2(0, -1) : ivec2(0, 1)));
			vec2 nv = texelFetch(depth_tex, clamp(tcell + o, ivec2(0), ivec2(level_size) - 1), 0).rg;
			float dist = k == 0 ? fcell.x : (k == 1 ? 1.0 - fcell.x : (k == 2 ? fcell.y : 1.0 - fcell.y));
			if (nv.g < 2.5) {
				edge_ao = min(edge_ao, mix(0.45, 1.0, smoothstep(0.0, 0.9, dist)));
			}
		}
		ao *= edge_ao;
		emit_x = albedo * 0.08;
	}
	if (back) {
		// ---- the room's back wall: warm dressed stone, pilasters, string courses, blind arches, moss ----
		vec2 p = vec2(wp.x, -wp.y);
		// warm stone kept well below the glyphs (~25-35% on screen), deepening into the recess
		// painted sky / cloud bg left in a wall (dropped window specks, notches) must not turn the stone pale:
		// cap the painted value and pull it toward grey stone
		vec3 pc = c.rgb;
		float pl = dot(pc, vec3(0.3, 0.55, 0.15));
		pc = mix(pc, vec3(pl), smoothstep(0.12, 0.35, pl) * 0.8) * min(1.0, 0.14 / max(pl, 0.001));
		vec3 stone = mix(pc * 0.8, vec3(0.2, 0.17, 0.135), 0.55);
		vec2 wq = p + vec2(vnoise(p * 0.5), vnoise(p * 0.5 + 3.0)) * 0.2;
		float row = floor(wq.y * 2.0);
		vec2 bq = vec2(wq.x * 0.75 + h21(vec2(row, 1.7)) * 3.0, wq.y * 2.0);
		vec2 bi = floor(bq);
		vec2 bf = bq - bi;
		float joint = min(min(bf.x, 1.0 - bf.x) * 1.33, min(bf.y, 1.0 - bf.y));
		float jl = 1.0 - smoothstep(0.03, 0.1, joint);
		albedo = stone * mix(0.8, 1.14, h21(bi + 7.0)) * mix(0.9, 1.05, vnoise(p * 3.1)) * (1.0 - jl * 0.5);
		n = normalize(vec3(0.0, 0.0, 1.0) + vec3((bf.x < 0.5 ? -1.0 : 1.0) * 0.0, 0.0, 0.0));
		n = normalize(n + vec3(-(bf.x - 0.5), (bf.y - 0.5), 0.0) * jl * 0.5);
		// pilasters every 6 tiles (stand proud: lighter, lit edges)
		float px = fract((p.x + 0.5) / 6.0) * 6.0;
		float pil = 1.0 - smoothstep(0.85, 0.95, px);
		float pedge = smoothstep(0.0, 0.08, px) * (1.0 - smoothstep(0.72, 0.9, px));
		albedo = mix(albedo, stone * 1.18 * mix(0.9, 1.05, vnoise(vec2(p.x * 4.0, p.y * 0.6))), pil);
		n = normalize(mix(n, vec3(px < 0.45 ? -0.7 : 0.7, 0.0, 0.7), pil * (1.0 - pedge) * 0.8));
		// string course every 8 rows, with a shadow under it
		float sy = fract(p.y / 8.0) * 8.0;
		float sc = smoothstep(0.0, 0.05, sy) * (1.0 - smoothstep(0.3, 0.36, sy));
		float scs = smoothstep(0.36, 0.4, sy) * (1.0 - smoothstep(0.4, 0.75, sy));
		albedo = mix(albedo, stone * 1.25, sc);
		albedo *= 1.0 - scs * 0.35;
		n = normalize(mix(n, vec3(0.0, 0.8, 0.6), sc * 0.6));
		// blind arch in every bay under the string course
		float u = (px - 0.95) / 5.05;
		if (u > 0.0 && u < 1.0) {
			float ay = sy - 0.4;
			float crown = 1.2 + 1.3 * (1.0 - sqrt(max(1.0 - pow(u * 2.0 - 1.0, 2.0), 0.0)));
			float inside = step(crown, ay) * step(0.08, u) * step(u, 0.92);
			float ring = (1.0 - smoothstep(0.0, 0.18, abs(ay - crown))) * step(0.08, u) * step(u, 0.92);
			albedo *= 1.0 - inside * 0.25;
			albedo = mix(albedo, stone * 1.2, ring * 0.8);
		}
		// moss in the lower joints and along the floor line
		float moss = smoothstep(0.55, 0.85, vnoise(p * 0.7 + 11.0) + jl * 0.35 - 0.15);
		albedo = mix(albedo, vec3(0.12, 0.2, 0.06), moss * 0.55);
		// inner-corner AO against the side walls / floor / ceiling, and stone frames around window holes
		vec2 fcell = p - floor(p);
		float edge_ao = 1.0;
		float frame = 0.0;
		for (int k = 0; k < 4; k++) {
			ivec2 o = k == 0 ? ivec2(-1, 0) : (k == 1 ? ivec2(1, 0) : (k == 2 ? ivec2(0, -1) : ivec2(0, 1)));
			vec2 nv = texelFetch(depth_tex, clamp(tcell + o, ivec2(0), ivec2(level_size) - 1), 0).rg;
			float dist = k == 0 ? fcell.x : (k == 1 ? 1.0 - fcell.x : (k == 2 ? fcell.y : 1.0 - fcell.y));
			if (nv.g < 2.5) {
				edge_ao = min(edge_ao, mix(0.5, 1.0, smoothstep(0.0, 0.9, dist)));
			} else if (nv.g > 50.0) {
				float fw = k == 3 ? 0.42 : 0.3;   // sill under a window is deeper
				frame = max(frame, 1.0 - smoothstep(fw - 0.06, fw, dist));
			}
		}
		albedo = mix(albedo, stone * 1.3 * mix(0.9, 1.05, vnoise(p * 6.0)), frame);
		n = normalize(mix(n, vec3(0.0, 0.3, 1.0), frame * 0.5));
		ao *= edge_ao;
		rough = 0.88;
		// interior light floor: the hall is never a black hole (the slab shades it)
		emit_x = albedo * 0.1;
	}
	bool leafy = mat == M_GRASS || mat == M_FOLIAGE;
	if (leafy && !horiz) {
		albedo *= 0.62;   // inside a crown / a turf wall: shaded leaves, not a lit lawn
	}
	{
		// big rock lumps so the receding faces aren't flat planes (the slab front is sculpted)
		vec3 U = (back || earth_back) ? vec3(1.0, 0.0, 0.0) : (horiz ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0));
		vec3 V = horiz ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		vec2 luv = (back || earth_back) ? wp.xy : (horiz ? wp.xz : wp.zy);
		vec3 t1 = texture(detail_nrm2, luv * 0.18).xyz * 2.0 - 1.0;
		vec3 t2 = texture(detail_nrm2, luv * 0.55 + 0.37).xyz * 2.0 - 1.0;
		vec2 tb = t1.xy * 0.75 + t2.xy * 0.4;
		n = normalize(n + (U * tb.x + V * tb.y) * (mat == M_RUIN ? 0.35 : (leafy ? (horiz ? (lip ? 0.6 : 0.25) : 0.6) : 0.7)));
		albedo *= mix(0.8, 1.1, texture(detail_hgt, luv * 0.2).r);
	}
	if (kind < 3.5) {
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
	if (inroom) {
		// the room's receding side walls / floor / ceiling: AO into the back corner, interior light floor
		ao *= mix(0.55, 1.0, smoothstep(nstart, nstart - 1.4, d));
		emit_x = albedo * 0.08;
	}
	if (lip && horiz) {
		albedo *= 0.65;   // the near ledge is seen at a grazing angle in full sun: keep it below the level's lawns
	}
	if (lip) {
		// the cliff dissolves into the sky below the world
		hz = smoothstep(-level_size.y - 0.5, -level_size.y - 6.5, wp.y) * 0.85;
	}
	vec3 hcol = haze_color;
	if (texelFetch(forest_tex, clamp(ivec2(floor(tile)), ivec2(0), ivec2(level_size) - 1), 0).r > 0.5) {
		hcol = forest_fog;   // forest: faces recede into the dark forest fog, not the sky
		hz = max(hz, smoothstep(0.3, 6.0, d) * 0.8);
		albedo *= 0.7;
		if (gn.y < -0.5) {
			albedo /= 0.45 * 1.6;   // crown / trunk undersides in the forest: no near-black dashes along slab edges
		}
	}
	ALBEDO = albedo * ao * (1.0 - hz);
	if (prop) {
		// roots are dirt-brown, rocks the floor's colour (never black specks against the dark cave)
		ALBEDO = kind < 14.5 ? vec3(0.17, 0.115, 0.07) * mix(0.8, 1.2, vnoise(wp.xy * 7.0)) : max(c.rgb * 0.7, vec3(0.08, 0.07, 0.06)) * mix(0.85, 1.15, vnoise(wp.xz * 9.0));
		rough = 1.0;
	}
	if (earth_back || prop || (inroom && sf > 0.5 && ownstart < 2.5)) {
		ALBEDO *= mix(1.0, 0.5, smoothstep(1.0, 6.0, d));   // the cave darkens as it recedes
	}
	if (inner || earth_back) {
		ALBEDO *= 0.75;
		rough = 1.0;
	}
	if (wallblock) {
		ALBEDO = min(ALBEDO, vec3(0.06, 0.045, 0.03));   // edge of a back-wall slab: dark packed rock, never lit
	}
	ROUGHNESS = rough;
	SPECULAR = (inner || earth_back || back) ? 0.08 : 0.35;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	EMISSION = hcol * hz * haze_emit + emit_x * ao * (1.0 - hz);
	if (hcol == forest_fog) {
		EMISSION = max(EMISSION, ALBEDO * 0.3 + forest_fog * 0.6);   // forest faces never sink to black lines
	}
	if (wallblock) {
		EMISSION *= 0.2;
	}
	if (prop) {
		EMISSION = vec3(0.0);
	}
	if (earth_back) {
		// rare glowworms deep in the dirt
		vec2 gq = wp.xy * 1.7;
		vec2 gi = floor(gq);
		float gl = step(0.985, h21(gi + 17.0)) * (1.0 - smoothstep(0.02, 0.07, length(fract(gq) - 0.5)));
		EMISSION += vec3(0.35, 0.8, 0.55) * gl * (0.6 + 0.4 * sin(TIME * 1.3 + gi.x * 3.1));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	if (back || earth_back || inroom || prop) {
		// interiors (rooms, caves, corridors) never fall to black: a soft ambient floor in the surface's own tone
		vec3 tone = normalize(max(ALBEDO, vec3(0.001))) * 0.577;
		EMISSION = max(EMISSION, tone * 0.035 + vec3(0.006, 0.005, 0.004));
	}
	if (!FRONT_FACING) {
		// the inside of a volume: only ever seen through the hairline where the slab's bevelled cliff meets a
		// side face. Before, back faces were culled and those slits showed the sky as bright vertical lines.
		ALBEDO = c.rgb * 0.08;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		AO = 0.2;
		EMISSION = vec3(0.0);
		NORMAL = -NORMAL;
	}
}
