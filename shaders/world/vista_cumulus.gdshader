shader_type spatial;
// WorldVista cumulus: a single puffy cloud on a world-space quad facing +z (the camera always looks down
// -z, so no billboard rotation is needed and parallax stays physical). Flat-ish base, cauliflower top made
// of noise-eroded blobs, lit from the sun (upper left, in front), bluish shaded bellies, aerial haze.
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

#include "res://shaders/world/vista_common.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float seed = 0.0;
uniform float flat_base = 0.3;     // 0 = round puff, 1 = flat-bottomed cumulus
uniform float fog_density = 0.0017;
uniform float fog_near = 0.1;
uniform float opacity = 1.0;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float dens(vec2 uv) {
	// uv: x in [-1,1], y in [0,1] (0 = base)
	vec2 s = vec2(seed * 0.173, seed * 0.311);
	float d = 0.0;
	// a few overlapping domes along the base, the middle one tallest
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float cx = -0.62 + fi * 0.31 + (v_h2(vec2(seed, fi)) - 0.5) * 0.18;
		float r = mix(0.24, 0.42, v_h2(vec2(fi, seed + 3.0))) * (1.0 - abs(cx) * 0.55);
		float cy = r * 0.55;
		vec2 q = (uv - vec2(cx, cy)) / vec2(r * 1.2, r * 1.7);
		d = max(d, 1.0 - dot(q, q));
	}
	float n = texture(noise_tex, uv * vec2(0.9, 0.6) + s).r * 0.6 + texture(noise_tex, uv * vec2(2.3, 1.8) + s * 1.7).g * 0.4;
	d = d + (n - 0.5) * 0.9;
	// flatten the base
	d *= mix(1.0, smoothstep(0.0, 0.12, uv.y), flat_base);
	return d;
}

void fragment() {
	vec2 uv = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	float d = dens(uv);
	if (d <= 0.0) {
		discard;
	}
	vec3 sd = normalize(sun_dir);
	// light: density difference toward the sun (screen-space, sun is upper left)
	vec2 ls = normalize(vec2(sd.x, sd.y)) * 0.06;
	float dl = dens(uv + ls);
	float lit = clamp(0.62 + (d - dl) * 3.0, 0.0, 1.0);
	lit *= mix(0.78, 1.0, smoothstep(0.0, 0.45, uv.y));      // shaded belly
	vec3 col = mix(vec3(0.58, 0.66, 0.82), vec3(1.05, 1.02, 0.97), lit);
	col += vec3(0.08) * (1.0 - smoothstep(0.0, 0.18, d));    // bright translucent fringe
	vec3 cam = CAMERA_POSITION_WORLD;
	ALBEDO = vista_fog(col, v_wpos, cam, sd, fog_density, fog_near);
	ALPHA = smoothstep(0.0, 0.16, d) * opacity;
}
