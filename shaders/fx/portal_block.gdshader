shader_type spatial;
// EE portal (242) as a real 3D crystal block (both levels), faithful to the original sprite: a glossy
// ice-blue glass block (light cyan -> deep blue, lighter rim, soft chamfer) with a bold WHITE CHEVRON on
// its front pointing in the portal's exit direction, and a bright light band that SWEEPS across it on a
// 15-frame cycle phase-offset by tile position exactly like EE (frame = rot*15 + (offset/1.5 + cx + cy) % 15).
// It refracts what's behind it (it's passable, so it must not read as a wall) with an inner swirl glow and
// a crisp dark silhouette. The ball near it / teleports through it (flares) pulse it.
// Mesh: FxMeshes.portal_block() (UV = front coords, COLOR.r = 1 front / .5 chamfer / 0 sides).
// MultiMesh INSTANCE_CUSTOM: x = EE phase ((cx+cy) % 15) / 15, y = rotation / 4, z = random.
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 ice_light : source_color = vec3(0.42, 0.8, 1.0);
uniform vec3 ice_deep : source_color = vec3(0.02, 0.14, 0.55);
uniform float cycle = 0.9;          // seconds per 15-frame shimmer cycle
uniform float pulse = 0.0;
uniform float hc = 0.0;
uniform vec3 ball_pos = vec3(-1000.0);
uniform vec4 flares[4];

varying float v_phase;
varying float v_rot;
varying float v_kind;
varying float v_rand;
varying vec3 v_o;
varying vec3 v_local;

void vertex() {
	v_phase = INSTANCE_CUSTOM.x;
	v_rot = INSTANCE_CUSTOM.y * 4.0;
	v_rand = INSTANCE_CUSTOM.z;
	v_kind = COLOR.r;
	v_o = MODEL_MATRIX[3].xyz;
	v_local = VERTEX;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;                                  // y up, -1..1 over the tile
	float t = TIME;
	// exit direction: rot 0 down, 1 left, 2 up, 3 right (EE sprite order)
	float ang = -1.5708 - 1.5708 * floor(v_rot + 0.5);
	vec2 dir = vec2(cos(ang), sin(ang));
	vec2 side = vec2(-dir.y, dir.x);
	// excitement: ball nearby + recent teleports
	float near = smoothstep(3.0, 0.7, distance(v_o.xy, ball_pos.xy));
	float ev = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 f = flares[i];
		if (f.w > 0.0) ev += exp(-distance(v_o.xy, f.xy) * 1.5) * exp(-f.z * 2.0) * f.w;
	}
	float ex = clamp(near * 0.5 + ev * 1.5 + pulse, 0.0, 2.0);
	// EE shimmer: a bright band travelling along the exit direction, 15-step cycle offset by tile position
	float fr = floor(fract(t / cycle + v_phase) * 15.0) / 15.0;
	float fr_s = fract(t / cycle + v_phase);
	float s = dot(p, dir);
	float bandpos = mix(-1.3, 1.3, mix(fr, fr_s, 0.6));
	float band = exp(-pow((s - bandpos) / 0.22, 2.0));
	// crystal body: light at the rim, deep in the middle, inner swirl seen with a little parallax
	float rim = max(abs(p.x), abs(p.y));
	vec2 par = p + (VIEW.xy) * 0.25;
	float swirl = vnoise(par * 2.2 + vec2(sin(t * 0.4 + v_rand * 6.0), cos(t * 0.3)) * 1.5)
		* 0.6 + vnoise(par * 5.0 - t * 0.35) * 0.4;
	float facet = smoothstep(0.35, 0.65, swirl);
	vec3 body = mix(ice_deep, ice_light, clamp(smoothstep(0.35, 1.0, rim) * 0.75 + facet * 0.5, 0.0, 1.0));
	body += vec3(0.7, 0.9, 1.0) * pow(max(swirl - 0.62, 0.0) * 3.0, 2.0) * 0.6;   // bright crystal flecks
	// see-through: the world behind, refracted and strongly tinted (so it reads as glass, not a wall)
	vec2 n = (vec2(swirl) - 0.5) * 0.02 + p * 0.004;
	vec3 bg = textureLod(screen_tex, SCREEN_UV + n, 1.5).rgb;
	vec3 seen = mix(bg * vec3(0.18, 0.38, 0.7), body, 0.8);
	// chevron (front face only): bold white arrow pointing along dir, dark navy outline
	float chev = 9.0;
	if (v_kind > 0.9) {
		vec2 q = vec2(dot(p, dir), dot(p, side));
		vec2 tip = vec2(0.34, 0.0);
		chev = min(seg(q, vec2(-0.2, 0.46), tip), seg(q, vec2(-0.2, -0.46), tip));
	}
	float arrow = 1.0 - smoothstep(0.125, 0.14, chev);
	float arrow_edge = 1.0 - smoothstep(0.19, 0.205, chev);
	// EE's lighter rim on the chamfer, and a crisp dark line at the front-face edge + silhouette
	float front_edge = v_kind > 0.9 ? smoothstep(0.68, 0.76, rim) : 0.0;
	float lip = v_kind > 0.25 && v_kind < 0.9 ? 1.0 : 0.0;
	vec3 col = seen;
	col = mix(col, ice_light * 1.1, lip * 0.45);
	col += ice_light * band * (0.8 + ex * 0.6) * (v_kind > 0.25 ? 1.0 : 0.4);
	col = mix(col, vec3(0.01, 0.03, 0.1), max(front_edge * 0.8, v_kind < 0.25 ? 0.45 : 0.0));
	col = mix(col, vec3(0.01, 0.03, 0.12), arrow_edge * (1.0 - arrow) * 0.9);
	col *= 1.0 + ex * 0.35 + hc * 0.3;
	col = mix(col, vec3(1.0), arrow);
	ALBEDO = col * 0.12;
	EMISSION = col * 0.3 + vec3(1.0) * arrow * (0.8 + ex * 0.6) + ice_light * band * 0.35;
	ROUGHNESS = 0.3;
	SPECULAR = 0.15;   // strong sky reflections frosted the whole face milky; highlights are painted below
	ALPHA = max(v_kind > 0.25 ? 0.94 : 0.85, arrow_edge);
}
