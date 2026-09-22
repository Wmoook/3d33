shader_type sky;
// Daytime sky for painted-sky levels (Forgotten Veil): the level's own painted sky (minimap colours of
// every sky tile: pastel blue, clouds, snowy mountains) as a far backdrop with gentle parallax, deepening
// to a zenith blue above the painting, with a soft sun glow. Radiance pass: simple sky/ground hemisphere
// that turns into a cool shaded-interior hemisphere underground (cave_amount).

uniform sampler2D paint : source_color, filter_linear, repeat_disable;
uniform vec2 level_size = vec2(400.0, 200.0);
uniform vec3 sun_dir = vec3(-0.3, 0.55, 0.78);
uniform float parallax = 0.6;     // 1 = locked to the level, 0 = fixed to the camera
uniform float spread = 1.3;       // >1: the painting is seen "further away" (smaller)
uniform float brightness = 1.3;
uniform float cave_amount = 0.0;
uniform vec3 cave_top = vec3(0.5, 0.55, 0.6);
uniform vec3 cave_bottom = vec3(0.05, 0.05, 0.06);

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sd = normalize(sun_dir);
	if (AT_CUBEMAP_PASS) {
		vec3 top = vec3(0.42, 0.58, 0.95);
		vec3 hor = vec3(0.78, 0.84, 0.92);
		vec3 gnd = vec3(0.32, 0.28, 0.22);
		vec3 c = d.y > 0.0 ? mix(hor, top, pow(d.y, 0.6)) : mix(hor, gnd, smoothstep(0.0, -0.4, d.y));
		c += vec3(1.0, 0.9, 0.7) * pow(max(dot(d, sd), 0.0), 8.0) * 0.6;
		vec3 cave = mix(cave_bottom, cave_top, smoothstep(-0.7, 0.9, d.y + d.z * 0.35 - d.x * 0.15));
		COLOR = mix(c, cave, cave_amount);
	} else {
		vec3 cam = POSITION;
		float t = max(cam.z, 1.0) / max(-d.z, 0.05);
		vec2 hit = cam.xy + d.xy * t;                    // view ray on the gameplay plane
		vec2 anchor = vec2(level_size.x * 0.5, -level_size.y * 0.5);
		vec2 w = anchor + (cam.xy - anchor) * parallax + (hit - cam.xy) * spread;
		vec2 uv = vec2(w.x, -w.y) / level_size;
		vec3 c = texture(paint, clamp(uv, vec2(0.002), vec2(0.998))).rgb;
		// soft drifting cloud wisps over the painted blue
		float wisp = n2(vec2(w.x * 0.05 + TIME * 0.01, w.y * 0.12)) * n2(vec2(w.x * 0.11 - TIME * 0.006, w.y * 0.2 + 3.0));
		c = mix(c, vec3(0.92, 0.95, 1.0), smoothstep(0.35, 0.7, wisp) * 0.25 * smoothstep(0.1, 0.6, c.b));
		// above the painting: deepen towards the zenith
		c = mix(c, vec3(0.55, 0.68, 1.0), smoothstep(0.0, -0.5, uv.y));
		// keep the painting's pastel colours vivid through the tonemapper
		float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
		c = max(mix(vec3(l), c, 1.35), vec3(0.0));
		float s = max(dot(d, sd), 0.0);
		c += vec3(1.0, 0.92, 0.75) * (pow(s, 6.0) * 0.12 + pow(s, 60.0) * 0.3);
		COLOR = c * brightness;
	}
}
