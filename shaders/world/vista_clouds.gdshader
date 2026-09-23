shader_type spatial;
// WorldVista CLOUD SEA: a world-space cloud layer filling the valleys beyond the level, raymarched as a
// heightfield slab (puffy lens: tops bulge up to base+up, bellies sag to base-down). Drawn on the back faces
// of its bounding box with depth test off; the march stops at the opaque scene depth, so mountains and
// ruins poke through and the level in front always wins. From above it is a sunlit sea of cloud tops,
// from below a broken deck of grey bellies wrapping the mountains' waists.
render_mode unshaded, fog_disabled, cull_front, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled;

#include "res://shaders/world/vista_common.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 box_min = vec3(-700.0, -140.0, -830.0);
uniform vec3 box_max = vec3(1100.0, -90.0, -200.0);
uniform float base_y = -120.0;
uniform float up = 18.0;
uniform float down = 6.0;
uniform float near_z = -215.0;     // clouds fade in behind this depth
uniform float feather = 110.0;
uniform float coverage = 0.5;
uniform float fog_density = 0.0008;
uniform float fog_near = 0.12;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// lod: texture footprint of one pixel at ray distance t (grazing rays stretch it)
float field(vec2 xz, float lod) {
	vec2 w = vec2(TIME * 0.35, TIME * 0.12);
	float a = textureLod(noise_tex, (xz + w) * 0.0034, max(lod + log2(0.0034 * 256.0), 0.0)).r;
	float b = textureLod(noise_tex, (xz + w * 1.6) * 0.0115 + vec2(0.37, 0.61), max(lod + log2(0.0115 * 256.0), 0.0)).g;
	float c = textureLod(noise_tex, (xz + w * 2.0) * 0.031 + vec2(0.13, 0.29), max(lod + log2(0.031 * 256.0), 0.0)).b;
	float depth_in = smoothstep(near_z, near_z - feather, xz.y);
	// denser toward the far ranges, broken near the level so the valley floor shows through
	float cov = coverage + 0.22 * smoothstep(near_z - 60.0, -600.0, xz.y);
	float t = a * 0.62 + b * 0.30 + c * 0.14 - (1.02 - cov);
	return clamp(t * 3.2, 0.0, 1.0) * depth_in;
}

float top_h(float t) { return base_y + up * pow(t, 0.55); }
float bot_h(float t) { return base_y - down * t; }

float lodf(float t, vec3 rd, float pxs) {
	return log2(max(t * pxs / max(abs(rd.y), 0.08), 1e-4));
}

void fragment() {
	float pxs = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(v_wpos - cam);
	// ray vs box
	vec3 inv = 1.0 / rd;
	vec3 ta = (box_min - cam) * inv;
	vec3 tb = (box_max - cam) * inv;
	vec3 tmn = min(ta, tb);
	vec3 tmx = max(ta, tb);
	float t0 = max(max(max(tmn.x, tmn.y), tmn.z), 0.0);
	float t1 = min(min(tmx.x, tmx.y), tmx.z);
	// opaque scene depth along the ray
	float dz = texture(depth_tex, SCREEN_UV).r;
	if (dz > 1e-7) {
		vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, dz, 1.0);
		vp.xyz /= vp.w;
		t1 = min(t1, length(vp.xyz));
	}
	if (t1 <= t0) {
		discard;
	}
	const int N = 40;
	float dt = (t1 - t0) / float(N);
	float tp = t0;
	float th = -1.0;
	for (int i = 1; i <= N; i++) {
		float t = t0 + dt * float(i);
		vec3 p = cam + rd * t;
		float f = field(p.xz, lodf(t, rd, pxs));
		if (f > 0.004 && p.y < top_h(f) && p.y > bot_h(f)) {
			th = t;
			break;
		}
		tp = t;
	}
	if (th < 0.0) {
		discard;
	}
	// refine the hit
	float lo = tp;
	float hi = th;
	for (int k = 0; k < 5; k++) {
		float tm = 0.5 * (lo + hi);
		vec3 p = cam + rd * tm;
		float f = field(p.xz, lodf(tm, rd, pxs));
		if (f > 0.004 && p.y < top_h(f) && p.y > bot_h(f)) { hi = tm; } else { lo = tm; }
	}
	vec3 p = cam + rd * hi;
	float lh = lodf(hi, rd, pxs);
	float f = field(p.xz, lh);
	vec3 sd = normalize(sun_dir);
	vec3 col;
	float e = 3.0;
	if (p.y >= base_y) {
		// sunlit billowing top
		float fx = field(p.xz + vec2(e, 0.0), lh);
		float fz = field(p.xz + vec2(0.0, e), lh);
		float h0 = top_h(f);
		vec3 n = normalize(vec3(-(top_h(fx) - h0) / e, 1.0, -(top_h(fz) - h0) / e));
		float ndl = clamp(dot(n, sd) * 0.7 + 0.3, 0.0, 1.0);
		float crev = mix(0.72, 1.0, smoothstep(0.0, 0.7, f));
		col = mix(vec3(0.60, 0.68, 0.84), vec3(1.04, 1.01, 0.97), ndl) * crev;
		// thin edges glow a little (light passing through)
		col += vec3(0.10, 0.10, 0.09) * (1.0 - smoothstep(0.0, 0.25, f));
	} else {
		// grey belly seen from below, darker where the cloud is thick
		col = mix(vec3(0.80, 0.84, 0.92), vec3(0.50, 0.56, 0.68), smoothstep(0.1, 0.9, f));
	}
	// broad cloud shadows, matching the sky dome's continuation of the sea
	float shade = smoothstep(0.35, 0.7, texture(noise_tex, (p.xz + vec2(TIME * 0.35, TIME * 0.12) * 0.6) * 0.0009 + vec2(0.5, 0.2)).b);
	col *= mix(1.0, 0.72, shade);
	float a = smoothstep(0.0, 0.12, f);
	ALBEDO = vista_fog(col, p, cam, sd, fog_density, fog_near);
	ALPHA = a;
}
