shader_type spatial;
// WorldVista props: distant ruin spires (kind 0, stone with moss and dark window slots) and the forest
// trees on the hills (kind 1, MultiMesh, albedo = instance colour). Unshaded, no shadows, aerial haze.
render_mode unshaded, fog_disabled, cull_back, shadows_disabled;

#include "res://shaders/world/vista_common.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform int kind = 0;
uniform float fog_density = 0.0021;
uniform float fog_near = 0.38;

varying vec3 v_wpos;
varying vec3 v_n;
varying vec3 v_lpos;
varying vec4 v_col;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_lpos = VERTEX;
	v_col = COLOR;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 wp = v_wpos;
	vec3 n = normalize(v_n);
	vec3 sd = normalize(sun_dir);
	vec3 col = v_col.rgb;
	if (kind == 0) {
		// weathered stone: blotches, horizontal courses, moss on top faces and streaking down from ledges
		float nb = texture(noise_tex, wp.xy * 0.03 + wp.z * 0.011).r;
		float nm = texture(noise_tex, wp.xy * 0.09 + vec2(0.3, 0.1)).g;
		col *= 0.8 + 0.4 * nb;
		col *= 1.0 - 0.12 * step(0.85, fract(wp.y * 0.28));
		vec3 moss = vec3(0.24, 0.36, 0.16);
		float mo = smoothstep(0.6, 0.9, n.y) + smoothstep(0.62, 0.8, nm) * 0.55 * (1.0 - abs(n.y));
		col = mix(col, moss, clamp(mo, 0.0, 1.0) * v_col.a);
		// dark window slots in the wall faces (vertex alpha 0 = cap faces without windows)
		if (abs(n.y) < 0.5 && v_col.a > 0.5) {
			vec2 f = vec2(dot(wp.xz, normalize(vec2(-n.z, n.x))), wp.y);
			vec2 cell = fract(f / vec2(6.0, 11.0));
			float win = step(abs(cell.x - 0.5), 0.14) * step(abs(cell.y - 0.45), 0.25);
			float arch = step(length(vec2((cell.x - 0.5) / 0.14, (cell.y - 0.7) / 0.1)), 1.0) * step(0.7, cell.y);
			col = mix(col, vec3(0.05, 0.06, 0.07), max(win, arch) * 0.85);
		}
	} else {
		float nf = texture(noise_tex, wp.xy * 0.25 + wp.z * 0.07).r;
		col *= 0.75 + 0.5 * nf;
	}
	vec3 lit = vista_light(col, n, sd, 1.15, 0.62);
	ALBEDO = vista_fog(lit, wp, cam, sd, fog_density, fog_near);
}
