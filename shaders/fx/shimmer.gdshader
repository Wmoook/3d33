shader_type spatial;
// Invisible gravity blocks (411-414): EE hides them, so only a very faint heat-shimmer hint: a soft
// wavering glint drifting in the gravity direction (arrows) or a faint breathing speck (dot).
// INSTANCE_CUSTOM: x = phase, y = dir angle (world), z = 1 for the dot.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.8, 0.9, 1.0);
uniform float intensity = 0.08;
uniform vec3 ball_pos = vec3(-1000.0);

varying vec3 v_c;
varying float v_near;

void vertex() {
	v_c = INSTANCE_CUSTOM.xyz;
	v_near = smoothstep(4.0, 0.8, distance(MODEL_MATRIX[3].xy, ball_pos.xy));
}

void fragment() {
	vec2 p = UV - 0.5;
	p.y = -p.y;
	float ang = v_c.y;
	vec2 d = vec2(cos(ang), sin(ang));
	float ph = v_c.x * 6.2832;
	float along = dot(p, d);
	float across = dot(p, vec2(-d.y, d.x));
	float wav = sin(along * 18.0 - TIME * 3.0 + ph + sin(across * 11.0 + TIME) * 0.8);
	float streak = pow(max(wav, 0.0), 6.0) * exp(-across * across * 30.0);
	float dotg = exp(-dot(p, p) * 60.0) * (0.6 + 0.4 * sin(TIME * 2.0 + ph));
	float m = mix(streak, dotg + streak * 0.3, v_c.z);
	float edge = 1.0 - smoothstep(0.3, 0.5, length(p));
	ALBEDO = color * m * edge * intensity * (1.0 + v_near * 2.0);
}
