shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// WorldVoxel water blocks: lake / river surfaces (animated ripples, sky fresnel, sun glints) and waterfall
// columns (streaks pouring down, foam at the lip and the foot). The level's water colours (54 light, 10 deep),
// the same aerial haze as the blocks.

#include "res://shaders/world/vista_common.gdshaderinc"
#include "res://shaders/world/voxel_forest.gdshaderinc"

uniform sampler3D vol : filter_nearest, repeat_disable;
uniform vec3 vol_origin = vec3(-104.0, -256.0, 3.0);
uniform ivec3 vol_size = ivec3(608, 320, 160);
uniform vec3 water_a = vec3(0.21, 0.32, 0.92);
uniform vec3 water_d = vec3(0.035, 0.085, 0.39);
uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform float fog_density = 0.0011;
uniform float haze_near = 0.08;
uniform float haze_far = 0.40;
uniform float fade = 1.0;

varying vec3 w_pos;
varying vec3 w_nrm;

int vid(ivec3 c) {
	if (c.x < 0 || c.y < 0 || c.z < 0 || c.x >= vol_size.x || c.y >= vol_size.y || c.z >= vol_size.z) {
		return 0;
	}
	return int(texelFetch(vol, c, 0).r * 255.0 + 0.5);
}

ivec3 to_cell(vec3 p) {
	return ivec3(int(floor(p.x - vol_origin.x)), int(floor(p.y - vol_origin.y)), int(floor(-p.z - vol_origin.z)));
}

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
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
	vec3 gn = normalize(w_nrm);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 sd = normalize(sun_dir);
	vec3 vd = normalize(wp - cam);
	vec3 n = gn;
	vec3 col;
	float alpha;
	float foam = 0.0;
	if (gn.y > 0.5) {
		// ripples: two scrolling noise layers -> normal
		vec2 q = wp.xz;
		float e = 0.15;
		float t = TIME;
		float h0 = vn(q * 1.3 + vec2(t * 0.35, t * 0.2)) + vn(q * 3.1 - vec2(t * 0.5, -t * 0.3)) * 0.5;
		float hx = vn((q + vec2(e, 0.0)) * 1.3 + vec2(t * 0.35, t * 0.2)) + vn((q + vec2(e, 0.0)) * 3.1 - vec2(t * 0.5, -t * 0.3)) * 0.5;
		float hz = vn((q + vec2(0.0, e)) * 1.3 + vec2(t * 0.35, t * 0.2)) + vn((q + vec2(0.0, e)) * 3.1 - vec2(t * 0.5, -t * 0.3)) * 0.5;
		n = normalize(vec3(-(hx - h0) / e * 0.18, 1.0, -(hz - h0) / e * 0.18));
		float fres = pow(1.0 - max(dot(-vd, n), 0.0), 3.0);
		col = mix(water_d, water_a * 0.7, 0.35 + 0.3 * h0);
		col = mix(col, vista_sky(reflect(vd, n), sd), 0.25 + 0.55 * fres);
		// foam where a fall lands (water column above this cell's neighbours) and along the shore
		ivec3 c = to_cell(wp - vec3(0.0, 0.3, 0.0));
		float fn = 0.0;
		fn += vid(c + ivec3(1, 1, 0)) == 64 ? 1.0 : 0.0;
		fn += vid(c + ivec3(-1, 1, 0)) == 64 ? 1.0 : 0.0;
		fn += vid(c + ivec3(0, 1, 1)) == 64 ? 1.0 : 0.0;
		fn += vid(c + ivec3(0, 1, -1)) == 64 ? 1.0 : 0.0;
		foam = clamp(fn, 0.0, 1.0) * (0.6 + 0.4 * vn(q * 4.0 + TIME * 1.5));
		alpha = 0.86;
	} else {
		// falling sheet: bright streaks racing down, foam bands
		float across = dot(wp, gn.x != 0.0 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
		float s = vn(vec2(across * 4.0, wp.y * 0.35 + TIME * 2.4)) * 0.6 + vn(vec2(across * 9.0, wp.y * 0.8 + TIME * 3.6)) * 0.4;
		col = mix(water_d * 1.6, water_a * 1.1, s);
		col = mix(col, vec3(0.9, 0.95, 1.0), 0.22 + smoothstep(0.55, 0.9, s) * 0.6);
		ivec3 c = to_cell(wp - gn * 0.3);
		int below = vid(c - ivec3(0, 1, 0));
		foam = (below > 0 && below < 64) ? smoothstep(0.6, 0.0, fract(wp.y)) : 0.0;
		alpha = 0.9;
		if (vid(c) == 65) {
			// free fall dissolving into spray: count the mist blocks still below this one
			float m = 0.0;
			for (int q = 1; q <= 8; q++) {
				m += vid(c - ivec3(0, q, 0)) == 65 ? 1.0 : 0.0;
			}
			float t = (m + fract(wp.y)) / 8.0;
			col = mix(col, vec3(0.85, 0.9, 0.97), 0.5);
			alpha *= smoothstep(0.0, 1.0, t) * (0.55 + 0.45 * s);
		}
	}
	col = mix(col, vec3(0.92, 0.96, 1.0), foam * 0.75);
	float f = vista_fog_f(wp, cam, fog_density, 0.0);
	float dz = -wp.z - vol_origin.z;
	f = max(f, mix(haze_near, haze_far, smoothstep(0.0, 120.0, dz)) * (1.0 - smoothstep(55.0, 95.0, dz)));
	f = mix(1.0, f, fade);
	vec3 lit = col * (V_SUN * (max(dot(n, sd), 0.0) * 0.5 + 0.3) + V_AMB * 0.5);
	lit += vec3(1.0, 0.95, 0.85) * pow(max(dot(reflect(sd * -1.0, n), -vd), 0.0), 90.0) * 2.0;
	ALBEDO = vec3(0.0);
	EMISSION = mix(lit, vista_sky(vd, sd), f);
	ROUGHNESS = 0.1;
	SPECULAR = 0.2;
	ALPHA = mix(alpha, 1.0, foam * 0.5);
}
