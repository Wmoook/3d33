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
uniform vec3 haze_color : source_color = vec3(0.74, 0.82, 0.92);
uniform float haze_amt = 0.42;
uniform float haze_emit = 0.9;

varying vec3 w_pos;
varying vec2 tile;
varying float solid_f;

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
	} else if (mat == M_EARTH || mat == M_CRAG) {
		// soil / rock strata on the receding cliff walls
		float sy = -wp.y * 1.2 + vnoise(q * vec2(0.2, 0.5)) * 1.4;
		albedo *= mix(0.84, 1.08, sin(sy * 3.1) * 0.25 + 0.5 + (h21(vec2(floor(sy), 7.0)) - 0.5) * 0.5);
	} else if (mat == -1) {
		albedo *= 0.8;   // interior walls: the painted back-wall colour, a little shaded
	}
	pbr_terrain(mat, wp, gn, vec2(wp.x, -wp.y), CAMERA_POSITION_WORLD, albedo, n, rough, ao);
	// patchy large-scale tone so the hillsides don't read as one flat colour
	albedo *= mix(0.86, 1.08, vnoise(vec2(wp.x, wp.z) * 0.12));
	if (gn.y < -0.5) {
		albedo *= 0.45;   // undersides: shadowed rock
		ao *= 0.8;
	}
	// contact shading where the volume leaves the slab (matches the slab cliff's darkening)
	ao *= mix(0.75, 1.0, smoothstep(0.0, 2.5, d));
	float hz = smoothstep(haze_z.x, haze_z.y, wp.z) * haze_amt;
	ALBEDO = albedo * ao * (1.0 - hz);
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	EMISSION = haze_color * hz * haze_emit;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
