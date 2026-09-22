shader_type spatial;
// Relic coin glint: a 4-ray star flare + soft core that blooms briefly every few seconds ("chime shimmer"),
// camera-facing. INSTANCE-free: per-node uniforms. pulse_boost adds a manual flash (collect / on-screen chime).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.85, 0.45);
uniform float intensity = 1.6;
uniform float period = 3.2;
uniform float phase = 0.0;
uniform float pulse_boost = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float t = fract((TIME + phase) / period);
	float k = exp(-pow((t - 0.08) / 0.05, 2.0)) + pulse_boost;   // short bloom near the start of each cycle
	float ang = TIME * 0.6 + phase;
	mat2 R = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 q = R * p;
	float rays = exp(-abs(q.x) * 40.0) * exp(-abs(q.y) * 2.2) + exp(-abs(q.y) * 40.0) * exp(-abs(q.x) * 2.2);
	vec2 q2 = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * q;
	float rays2 = (exp(-abs(q2.x) * 50.0) * exp(-abs(q2.y) * 4.5) + exp(-abs(q2.y) * 50.0) * exp(-abs(q2.x) * 4.5)) * 0.5;
	float core = exp(-dot(p, p) * 18.0);
	float m = (rays + rays2) * k + core * (0.25 + k);
	ALBEDO = color * m * intensity * (1.0 - smoothstep(0.85, 1.0, length(p)));
}
