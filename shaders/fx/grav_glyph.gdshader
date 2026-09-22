shader_type spatial;
// Per-tile gravity glyphs (MultiMesh, opaque): amber chevrons for arrows 1/2/3 and pale-gold orbs + floating
// ring for dots 4. Surface "outline" = dark backing that keeps glyphs readable over bright terrain.
// INSTANCE_CUSTOM: x = phase, y = flow direction angle (radians, world), z = kind (0 chevron, 1 dot).
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.72, 0.2);
uniform float intensity = 1.25;
uniform float outline = 0.0;
uniform vec3 ball_pos = vec3(-1000.0);
uniform float hc = 0.0;   // high-contrast accessibility: +50% size and emission

varying float v_k;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = INSTANCE_CUSTOM.x * 6.2832;
	float ang = INSTANCE_CUSTOM.y;
	vec2 d = vec2(cos(ang), sin(ang));
	float kind = INSTANCE_CUSTOM.z;
	VERTEX *= 1.0 + hc * 0.5;
	// travelling pulse along the flow direction (and a slow breathe for dots)
	float wave = sin(dot(o.xy, d) * 1.4 - TIME * 4.0);
	float near = smoothstep(9.0, 1.5, distance(o.xy, ball_pos.xy));
	if (kind < 0.5) {
		VERTEX.xy += d * wave * 0.04 / max(length(MODEL_MATRIX[0].xyz), 0.01);
		v_k = 0.78 + 0.22 * wave;
	} else {
		VERTEX.y += sin(TIME * 1.5 + ph) * 0.05 / max(length(MODEL_MATRIX[1].xyz), 0.01);
		v_k = 0.85 + 0.15 * sin(TIME * 2.0 + ph);
	}
	v_k *= 0.72 + 0.28 * near + near * 0.25;
}

void fragment() {
	if (outline > 0.5) {
		ALBEDO = vec3(0.03, 0.018, 0.005);
	} else {
		ALBEDO = color * intensity * v_k * (1.0 + hc * 0.5);
	}
}
