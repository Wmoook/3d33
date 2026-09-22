shader_type particles;
// Tornado debris/dust: particles orbit the painted funnel (EE tiles x~2..46, y~80..140), rising slowly,
// radius following the funnel profile, with a depth (z) swing so the swirl reads in 3D.

uniform float top_y = -80.0;      // world y of the funnel top
uniform float bottom_y = -138.0;  // world y of the tip
uniform float spin = 1.6;
uniform float dust = 0.0;   // 1 = big soft dust puffs, 0 = debris streaks

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

vec3 funnel(float h, float ang, float rj) {
	// h: 0 = tip, 1 = top
	float cx = 23.5 - 7.0 * (1.0 - h) * (1.0 - h);
	float hw = 21.0 * pow(h, 1.25) + 1.2;
	float y = mix(bottom_y, top_y, h);
	float r = hw * rj;
	return vec3(cx + cos(ang) * r, y, sin(ang) * r * 0.35);
}

void start() {
	float r1 = hash(NUMBER * 3u + 1u);
	float r2 = hash(NUMBER * 7u + 5u);
	float r3 = hash(NUMBER * 11u + 3u);
	CUSTOM.x = pow(r1, 0.8);
	CUSTOM.y = r2 * 6.2832;
	CUSTOM.z = 0.75 + r3 * 0.3;
	CUSTOM.w = dust > 0.5 ? 1.0 : 0.0;
	TRANSFORM[3].xyz = funnel(CUSTOM.x, CUSTOM.y, CUSTOM.z);
	float s = dust > 0.5 ? 0.6 + r2 * 1.0 : 0.7 + r3 * 0.9;
	TRANSFORM[0].xyz = vec3(s, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, s, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, s);
	COLOR = dust > 0.5 ? vec4(0.62, 0.64, 0.7, 0.22) : vec4(0.75, 0.72, 0.68, 0.9);
}

void process() {
	float h = CUSTOM.x;
	float w = spin * (1.0 + (1.0 - h) * 2.5) / (0.4 + h);
	CUSTOM.y += w * DELTA;
	CUSTOM.x = fract(h + DELTA * 0.035);
	vec3 p = funnel(CUSTOM.x, CUSTOM.y, CUSTOM.z);
	// drive by velocity so the renderer can stretch sprites along the motion (streaks)
	vec3 d = p - TRANSFORM[3].xyz;
	VELOCITY = length(d) < 4.0 ? d / max(DELTA, 1e-4) : vec3(0.0);
	if (length(d) >= 4.0) { TRANSFORM[3].xyz = p; }
	float fade = smoothstep(0.0, 0.05, CUSTOM.x) * smoothstep(1.0, 0.9, CUSTOM.x);
	float front = 0.55 + 0.45 * sin(CUSTOM.y);
	COLOR.a = (dust > 0.5 ? 0.22 : 0.9) * fade * front;
}
