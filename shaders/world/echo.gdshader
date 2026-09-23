shader_type spatial;
// Terrain ECHO layer (day levels): a second rank of the level's own silhouettes behind the gameplay plane,
// with every mass extruded down into foundations. Drawn only where the terrain in front shows open sky, so
// behind every block you see its own ruin / cliff continuing back into depth. Darker, desaturated and
// hazed with distance; no shadows.
render_mode cull_back, shadows_disabled, unshaded, fog_disabled;

uniform sampler2D echo_sdf : filter_linear, repeat_disable;     // R = echo mask SDF (tiles, + inside), B smooth
uniform sampler2D echo_col : source_color, filter_linear, repeat_disable;   // colour per tile (foundations inherit)
uniform sampler2D sky_field : filter_linear, repeat_disable;    // r = sky-connected air (1) in the level
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 level_size = vec2(400.0, 200.0);
uniform float layer_z = -4.0;
uniform vec2 layer_offset = vec2(0.0);   // world units (x right, y up)
uniform float layer_scale = 1.0;         // around the level centre
uniform float darken = 0.7;
uniform float haze_amt = 0.3;
uniform vec3 haze_col : source_color = vec3(0.62, 0.72, 0.92);
uniform float spt = 8.0;

varying vec2 v_p;   // echo-space tile coords

vec2 to_echo(vec2 world_xy) {
	vec2 c = vec2(level_size.x * 0.5, -level_size.y * 0.5);
	vec2 q = (world_xy - layer_offset - c) / layer_scale + c;
	return vec2(q.x, -q.y);
}

float esdf(vec2 p) {
	vec4 t = textureLod(echo_sdf, p / level_size, 0.0);
	return t.r;
}

float round_prof(float t) {
	float u = 1.0 - clamp(t, 0.0, 1.0);
	return sqrt(max(1.0 - u * u, 0.0));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = to_echo(wp.xy);
	float sd = esdf(p);
	float z = layer_z + (sd > 0.0 ? 0.55 * round_prof(sd / 0.6) : -0.4);
	VERTEX.z = z - MODEL_MATRIX[3].z;
	v_p = p;
}

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = v_p;
	float sd = esdf(p);
	if (sd < -0.02) discard;
	// only where the gameplay plane in front is open sky (never inside caves / behind back walls)
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 dir = normalize(wpos - cam);
	float tz = -cam.z / dir.z;
	vec2 front = (cam + dir * tz).xy;
	float sky_front = textureLod(sky_field, vec2(front.x, -front.y) / level_size, 0.0).r;
	if (sky_front < 0.5) discard;
	float e = 0.06;
	vec2 g = vec2(esdf(p + vec2(e, 0.0)) - esdf(p - vec2(e, 0.0)), esdf(p + vec2(0.0, e)) - esdf(p - vec2(0.0, e)));
	float bev = 1.0 - smoothstep(0.0, 0.6, sd);
	vec3 n = normalize(vec3(-g.x, g.y, 0.0) * bev * 6.0 + vec3(0.0, 0.0, 1.0));
	vec3 dn = texture(detail_nrm, p * 0.35).xyz * 2.0 - 1.0;
	n = normalize(n + vec3(dn.xy, 0.0) * 0.5);
	vec4 ec = textureLod(echo_col, p / level_size, 0.0);
	vec3 c = ec.rgb;
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	c = mix(vec3(l), c, 0.4) * darken;
	float tone = 0.85 + 0.25 * smoothstep(-0.2, 0.6, n.y + 0.3 - n.x * 0.5);   // gentle sun-side lift
	c *= tone;
	// strong aerial perspective: value close to the sky, low contrast; foundations and edges dissolve
	float fade = max(ec.a, 1.0 - smoothstep(0.0, 0.8, sd) * 0.4);
	c = mix(c, haze_col, clamp(haze_amt + ec.a * 0.25, 0.0, 0.97));
	ALBEDO = c;
	ROUGHNESS = 0.9;
	AO = 0.6;
	AO_LIGHT_AFFECT = 0.5;
	SPECULAR = 0.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
