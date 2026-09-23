shader_type spatial;
render_mode depth_draw_opaque, cull_back;
// WorldVoxelFore: foreground blocks in front of the gameplay plane (z +1 .. +13).
// OCCLUSION-SAFE: every fragment's view ray (camera -> fragment) is intersected with the gameplay plane z = 0;
// the fragment is DISCARDED unless that point is inside coverable rock (fg_mask: static solid interior, eroded,
// doors / gates / one-ways / coin doors / gameplay blocks = air), and near the ball it always is. So nothing the
// player needs can ever be hidden. Look: the level's block colours (vertex COLOR, with baked vertex AO),
// darker / cooler / slightly desaturated and soft, like out-of-focus near foliage and stone.

uniform sampler2D fg_mask : filter_linear, repeat_disable;
uniform vec2 mask_size = vec2(400.0, 200.0);
uniform vec3 ball_pos = vec3(-1000.0, -1000.0, 0.0);
uniform float ball_r = 2.6;
uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform float darken = 0.52;
uniform float desat = 0.3;
uniform vec3 cool = vec3(0.86, 0.93, 1.06);
uniform float fade = 1.0;

varying vec3 w_pos;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 d = w_pos - cam;
	// camera -> fragment ray at the gameplay plane (the camera is always in front, cam.z > 0 > ... fragment z > 0)
	float t = d.z < -1e-4 ? -cam.z / d.z : 1e6;
	vec2 p = cam.xy + d.xy * t;
	vec2 tc = vec2(p.x, -p.y);   // tile space, y down
	float keep = 0.0;
	if (tc.x > 0.0 && tc.y > 0.0 && tc.x < mask_size.x && tc.y < mask_size.y) {
		// bilinear over tile centres: 1 deep inside the coverable interior, 0.5 on its edge
		float m = texture(fg_mask, tc / mask_size).r;
		// and the nearest tile itself must be coverable (never trust the blend alone)
		float mn = texelFetch(fg_mask, ivec2(floor(tc)), 0).r;
		keep = smoothstep(0.62, 0.9, m) * step(0.5, mn);
	}
	keep *= smoothstep(ball_r, ball_r + 1.0, length(p - ball_pos.xy));
	keep *= fade;
	// dithered edge (no transparency sorting; TAA smooths it)
	if (keep < 0.999 && keep <= h12(FRAGCOORD.xy)) {
		discard;
	}
	vec3 col = COLOR.rgb;
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(l), desat) * cool * darken;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	// soft "out of focus" read: a gentle rim so silhouettes stay legible but never crisp
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = vec3(0.10, 0.13, 0.18) * rim * 0.35;
}
