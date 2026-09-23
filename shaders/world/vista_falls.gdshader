shader_type spatial;
// WorldVista waterfall pouring off a floating island's rim into the cloud sea: streaming white-blue
// sheet (scrolling streaks), thinning and widening into spray toward the bottom, aerial haze.
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

#include "res://shaders/world/vista_common.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float seed = 0.0;
uniform float height = 100.0;
uniform float width = 5.0;
uniform float cell = 1.5;
uniform float fog_density = 0.0010;
uniform float fog_near = 0.12;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// blocky water: everything is sampled on a grid of `cell`-unit blocks (the world's voxel language)
	vec2 uvq = (floor(UV * vec2(width, height) / cell) + 0.5) * cell / vec2(width, height);
	float x = uvq.x * 2.0 - 1.0;
	float y = uvq.y;                // 0 = lip, 1 = cloud sea
	float fall = y * height;
	// the sheet frays and fans out as it falls
	float wide = mix(0.55, 1.0, smoothstep(0.0, 0.6, y));
	float edge = 1.0 - smoothstep(wide * 0.7, wide, abs(x));
	float t = TIME;
	float s1 = texture(noise_tex, vec2(x * 0.35 + seed, fall * 0.004 - t * 0.35)).r;
	float s2 = texture(noise_tex, vec2(x * 0.9 + seed * 1.7, fall * 0.011 - t * 0.8)).g;
	float streak = step(0.55, s1 * 0.6 + s2 * 0.55);
	float body = edge * (0.55 + 0.45 * streak) * (1.0 - smoothstep(0.55, 1.0, y) * 0.75);
	body *= smoothstep(0.0, 0.02, y);
	if (body < 0.01) {
		discard;
	}
	vec3 col = mix(vec3(0.62, 0.74, 0.86), vec3(1.0, 1.0, 0.98), streak * 0.7 + 0.2);
	vec3 cam = CAMERA_POSITION_WORLD;
	ALBEDO = vista_fog(col, v_wpos, cam, normalize(sun_dir), fog_density, fog_near);
	ALPHA = clamp(body, 0.0, 0.92);
}
