shader_type spatial;
// Piano block 77: a small carved chime tablet (rounded stone key, dark rim) with a glowing note rune whose
// hue is its pitch. MultiMesh quads. INSTANCE_CUSTOM: x = phase, y = hue (0..1), z = touch flare (0..1).
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform float hc = 0.0;
uniform vec3 ball_pos = vec3(-1000.0);

varying vec3 v_c;
varying float v_flare;
varying float v_near;

vec3 hue(float h) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return mix(vec3(1.0), k, 0.8);
}

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	v_c = hue(INSTANCE_CUSTOM.y);
	v_flare = INSTANCE_CUSTOM.z;
	v_near = smoothstep(3.0, 0.6, distance(o.xy, ball_pos.xy));
	VERTEX *= (1.0 + hc * 0.5) * (1.0 + v_flare * 0.18);
	VERTEX.y += sin(TIME * 1.4 + INSTANCE_CUSTOM.x * 6.2832) * 0.02;
}

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, -1.0);   // y up
	float d = sd_box(p, vec2(0.30, 0.44), 0.11);
	if (d > 0.0) discard;
	// note rune: tilted filled head + stem + flag
	vec2 hp = (p - vec2(-0.05, -0.14)) * mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float head = length(hp * vec2(1.0, 1.45)) - 0.085;
	float stem = seg(p, vec2(0.03, -0.12), vec2(0.03, 0.2)) - 0.022;
	float flag = seg(p, vec2(0.03, 0.2), vec2(0.13, 0.1)) - 0.022;
	float note = min(head, min(stem, flag));
	float rim = smoothstep(-0.075, -0.05, d);            // dark carved rim (readable on bright sky)
	float bevel = smoothstep(-0.13, -0.075, d) * (1.0 - rim);
	float shade = 0.72 + 0.28 * (p.y + 0.44) / 0.88;     // top-lit stone face
	vec3 stone = vec3(0.86, 0.82, 0.72) * shade;
	stone = mix(stone, vec3(1.0, 0.97, 0.9), bevel * 0.45);
	float k = 0.55 + 0.25 * v_near + v_flare * 2.4;
	vec3 col = mix(stone, v_c * k * (1.0 + hc * 0.5), smoothstep(0.012, -0.004, note));
	// the note colour washes the tablet when struck
	col += v_c * v_flare * 0.55 * (1.0 - rim);
	col = mix(col, vec3(0.06, 0.045, 0.03), rim);
	ALBEDO = col;
}
