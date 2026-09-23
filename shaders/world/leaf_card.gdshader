shader_type spatial;
// WorldFoliage leaf-cluster cards (QuadMesh, MultiMesh). Atlas 2x2: leaf_albedo R = leaf luminance (0.5 =
// mean), G = translucency/thickness, A = coverage; leaf_normal RGB = card-space normal (GL), A = coverage.
// INSTANCE_CUSTOM: rgb = painted canopy colour (linear), a = atlas cell (int part) + depth shade (fract);
// +10 = SNAP: the card sits on the sculpted canopy surface (baked terrain height), instance z = offset.
render_mode cull_disabled, depth_draw_opaque, alpha_to_coverage;

uniform sampler2D leaf_albedo : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D leaf_normal : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 ball_pos = vec3(-1000.0);
uniform float day = 1.0;
uniform float wind_strength = 1.0;
uniform float alpha_cut = 0.45;
uniform float round_normal = 0.55;   // blend toward a spherical clump normal (reads as a round volume)
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float height_margin = 16.0;
uniform vec2 level_size = vec2(400.0, 200.0);

varying vec3 v_tint;
varying float v_shade;
varying vec2 v_cell;
varying vec3 v_right;
varying vec3 v_up;
varying vec3 v_fwd;

void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float code = INSTANCE_CUSTOM.a;
	float zs = 0.0;
	if (code >= 9.5) {
		code -= 10.0;
		vec2 hp = vec2(c.x, -c.y);
		zs = textureLod(height_tex, (hp + height_margin) / (level_size + 2.0 * height_margin), 0.0).r;
		c.z += zs;
	}
	float ph = c.x * 0.37 + c.y * 0.21 + code * 3.1;
	// whole-cluster sway + corner flutter (leaves shiver in the gusts)
	float gust = sin(TIME * 0.9 + c.x * 0.12) * 0.5 + 0.5;
	float sw = (sin(TIME * 1.7 + ph) * 0.6 + sin(TIME * 3.3 + ph * 1.7) * 0.25) * (0.4 + 0.6 * gust) * wind_strength;
	vec2 q = VERTEX.xy;
	// gentle corner flutter (a fast, large flutter flickered leaf edges every frame)
	float fl = sin(TIME * 3.2 + ph * 5.0 + q.x * 7.0 + q.y * 5.0) * 0.006 * wind_strength;
	float a = sw * 0.06;
	VERTEX.xy = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * q + vec2(fl, fl * 0.6);
	VERTEX.z += sin(TIME * 2.3 + ph + q.x * 4.0) * 0.02 * wind_strength;
	// the ball rustles the leaves it touches
	vec3 wv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 d = wv - ball_pos;
	float push = 1.0 - smoothstep(0.3, 0.9, length(d.xy));
	VERTEX.xy += (inverse(mat3(MODEL_MATRIX)) * vec3(normalize(d.xy + vec2(0.0001)) * push * 0.08, 0.0)).xy;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 0.0, zs);
	v_tint = INSTANCE_CUSTOM.rgb;
	float cell = floor(code);
	v_shade = fract(code);
	v_cell = vec2(mod(cell, 2.0), floor(cell / 2.0));
	v_right = normalize(MODEL_MATRIX[0].xyz);
	v_up = normalize(MODEL_MATRIX[1].xyz);
	v_fwd = normalize(MODEL_MATRIX[2].xyz);
}

void fragment() {
	vec2 auv = (v_cell + UV) * 0.5;
	vec4 al = texture(leaf_albedo, auv);
	vec4 nm = texture(leaf_normal, auv);
	// sharpen coverage so mips keep crisp leaf edges (alpha-to-coverage style)
	// antialiased cut-out: MSAA alpha-to-coverage across a ~1 px band around the cut (fwidth), so edges resolve
	// to fractional coverage instead of popping pixels on/off as the camera moves
	ALPHA = al.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = clamp(fwidth(al.a) * 0.75, 0.005, 0.25);
	vec3 tn = nm.rgb * 2.0 - 1.0;
	tn.y = -tn.y;   // GL green = image-up; card UV.y grows downward, card local +y is up
	vec3 fwd = FRONT_FACING ? v_fwd : -v_fwd;
	vec3 nw = normalize(v_right * tn.x - v_up * tn.y + fwd * max(tn.z, 0.2));
	vec2 cp = (UV - 0.5) * 2.0;
	vec3 ns = normalize(v_right * cp.x - v_up * cp.y + fwd * 0.9);
	nw = normalize(mix(nw, ns, round_normal));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float lum = mix(1.0, al.r * 2.0, 0.75);
	// deeper cards sit in the crown's shade; the painted colour stays the average
	vec3 col = v_tint * lum * mix(0.5, 1.0, v_shade);
	ALBEDO = col;
	BACKLIGHT = col * al.g * mix(0.35, 0.95, day);
	ROUGHNESS = 0.62;
	SPECULAR = 0.3;
	AO = mix(0.6, 1.0, v_shade);
	AO_LIGHT_AFFECT = 0.4;
}
