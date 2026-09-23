shader_type spatial;
// WorldGrass blades (MultiMesh clumps, no instance colours). Vertex COLOR: r = t along the blade
// (0 root .. 1 tip), g = per-blade random, b = part (0 blade, 0.5 stem, 1 leaflet/petal), a = sway weight.
// INSTANCE_CUSTOM: rgb = painted tile colour (linear), a = clump random in [0,1), or 1 + flower palette
// index + random for flowers.
render_mode cull_disabled, depth_draw_opaque;

uniform vec3 ball_pos = vec3(-1000.0);
uniform float ball_radius = 0.95;       // blades inside this are pushed aside / flattened
uniform float wind_strength = 1.0;
uniform vec2 wind_dir = vec2(1.0, 0.15);
uniform float day = 1.0;                // 1 = sunlit day level, 0 = night (less translucency)
uniform float fade_far = 85.0;          // blades shrink away beyond this camera distance

varying vec3 v_tint;
varying float v_t;
varying float v_rnd;
varying float v_part;
varying vec4 v_custom;
varying float v_ao;

float h1(float n) { return fract(sin(n) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = h1(dot(i, vec2(1.0, 57.0)));
	float b = h1(dot(i + vec2(1.0, 0.0), vec2(1.0, 57.0)));
	float c = h1(dot(i + vec2(0.0, 1.0), vec2(1.0, 57.0)));
	float d = h1(dot(i + vec2(1.0, 1.0), vec2(1.0, 57.0)));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	vec3 root_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;   // clump centre (instance origin)
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = COLOR.r;
	float sway = COLOR.a;
	float hgt = max(wp.y - root_w.y, 0.0);
	// wind: travelling gust field (slow big gusts + faster flutter), mostly along wind_dir
	vec2 wd = normalize(wind_dir);
	float gx = dot(root_w.xz, wd);
	float gust = vnoise(vec2(gx * 0.18 - TIME * 0.55, root_w.z * 0.3)) * 1.2 - 0.35;
	float flutter = sin(TIME * 4.3 + root_w.x * 3.1 + COLOR.g * 6.28) * 0.18 + sin(TIME * 7.1 + wp.x * 9.0) * 0.06;
	float w = (gust + flutter) * wind_strength;
	vec3 disp = vec3(wd.x, 0.0, wd.y) * w * 0.22 * sway * (0.6 + COLOR.g * 0.6);
	// ball push: blades bend away from the ball and lie down (keeps the ball fully readable)
	vec3 d = root_w - ball_pos;
	d.z *= 0.8;
	float dist = length(d);
	float push = 1.0 - smoothstep(ball_radius * 0.45, ball_radius, dist);
	vec2 away = normalize(vec2(d.x, d.z) + vec2(0.0001, 0.0));
	disp += vec3(away.x, 0.0, away.y) * push * 0.32 * sway;
	disp.y -= hgt * push * 0.75;
	// length preservation: tips bending over sink a little
	float bendlen = length(disp.xz);
	disp.y -= bendlen * bendlen * 1.2 * t;
	// distance fade: blades shrink into the turf far away
	float cd = length(CAMERA_POSITION_WORLD - root_w);
	float shrink = 1.0 - smoothstep(fade_far - 20.0, fade_far, cd);
	disp.y -= hgt * (1.0 - shrink);
	wp += disp;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	v_tint = INSTANCE_CUSTOM.rgb;
	v_t = t;
	v_rnd = COLOR.g;
	v_part = COLOR.b;
	v_custom = INSTANCE_CUSTOM;
	v_ao = mix(0.35, 1.0, smoothstep(0.0, 0.7, t));
}

void fragment() {
	vec3 base = v_tint;
	float t = v_t;
	vec3 col;
	if (v_part > 0.75 && v_custom.a >= 1.0) {
		// petals / flower centre: small wild-flower palette (linear)
		int fi = int(v_custom.a) - 1;
		vec3 petal = fi == 0 ? vec3(1.0, 0.83, 0.26) : fi == 1 ? vec3(0.93, 0.93, 1.0) : fi == 2 ? vec3(0.62, 0.48, 1.0) : fi == 3 ? vec3(1.0, 0.45, 0.6) : vec3(1.0, 0.6, 0.1);
		col = UV.x > 1.5 ? vec3(0.9, 0.62, 0.08) : petal * mix(0.8, 1.0, UV.y);
		BACKLIGHT = col * 0.5 * day;
	} else {
		// blades: dark humid root -> painted colour -> sun-bleached lighter tip; per-blade tonal jitter
		float tone = mix(0.8, 1.18, v_rnd);
		vec3 root = base * 0.45;
		vec3 tip = base * 1.35 + vec3(0.03, 0.03, 0.0) * day;
		col = mix(root, base, smoothstep(0.0, 0.3, t));
		col = mix(col, tip, smoothstep(0.55, 1.0, t)) * tone;
		// faint midrib highlight
		col *= 1.0 + 0.12 * (1.0 - abs(UV.x - 0.5) * 2.0);
		if (v_part > 0.75) {
			col = base * mix(0.75, 1.05, v_rnd) * mix(0.8, 1.0, UV.y);   // clover leaflets
		}
		BACKLIGHT = col * mix(0.25, 0.85, day) * smoothstep(0.1, 0.8, t);
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
	AO = v_ao;
	AO_LIGHT_AFFECT = 0.5;
}
