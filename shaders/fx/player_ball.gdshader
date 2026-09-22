shader_type spatial;
// The hero ball: glossy clearcoat golden sphere with a procedural, animated EE smiley face.
// The mesh lives in a "gravity frame" (local -y = gravity), so the face stays upright; the
// engraved ring of rivets rotates with pattern_angle to show the roll.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 body_color : source_color = vec3(1.0, 0.788, 0.157);   // #FFC928
uniform vec3 body_deep : source_color = vec3(0.949, 0.663, 0.0);    // #F2A900
uniform vec3 ink_color : source_color = vec3(0.10, 0.045, 0.01);
uniform vec3 outline_color : source_color = vec3(0.25, 0.12, 0.0);
uniform vec3 mouth_color : source_color = vec3(0.42, 0.06, 0.04);
uniform vec3 rim_color : source_color = vec3(0.75, 0.85, 1.0);
uniform float rim_strength = 0.3;
uniform float self_glow = 0.0;
uniform float glow = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.92, 0.7);
uniform float pattern_angle = 0.0;
uniform vec2 look = vec2(0.0);
uniform float eye_open = 1.0;
uniform float squeeze = 0.0;   // >< eyes squeezed shut (hard landing)
uniform float happy = 0.0;     // ^^ eyes
uniform float wide = 0.0;      // scared: white sclera + small pupils
uniform float dead = 0.0;      // X eyes + flat mouth
uniform float grin = 0.0;      // open D grin
uniform float gasp = 0.0;      // O mouth
uniform float dissolve = 0.0;
uniform float dissolve_edge = 0.08;
uniform vec3 dissolve_color : source_color = vec3(1.0, 0.6, 0.15);

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float sd_ellipse(vec2 p, vec2 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 1e-5);
}
float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}
// Arc around +y axis with half-aperture given by sc = (sin, cos).
float sd_arc(vec2 p, vec2 sc, float ra) {
	p.x = abs(p.x);
	return (sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra);
}

void fragment() {
	vec3 p = normalize(v_obj);
	// --- face space: rotate by look direction (eyes turn toward travel) ---
	float yaw = look.x * 0.42;
	float pitch = look.y * 0.32;
	vec3 q = p;
	q.xz = mat2(vec2(cos(yaw), sin(yaw)), vec2(-sin(yaw), cos(yaw))) * q.xz;
	q.yz = mat2(vec2(cos(pitch), sin(pitch)), vec2(-sin(pitch), cos(pitch))) * q.yz;
	vec2 f = q.xy;
	float front = smoothstep(0.02, 0.3, q.z);

	// --- eyes ---
	vec2 ex = vec2(abs(f.x), f.y);
	vec2 ec = vec2(0.25, 0.2);
	vec2 er = vec2(0.12, 0.215) * (1.0 + wide * 0.2);
	float open_amt = eye_open * (1.0 - squeeze);
	vec2 e = ex - ec;
	float d_ell = sd_ellipse(e, vec2(er.x, max(er.y * open_amt, 0.026)));
	float d_closed = sd_segment(e, vec2(-0.08, 0.0), vec2(0.08, 0.0)) - 0.036;
	float d_eye = mix(d_closed, d_ell, smoothstep(0.12, 0.5, open_amt));
	// squeezed >< (chevrons pointing inward)
	vec2 es = e;
	float d_sq = min(sd_segment(es, vec2(0.08, 0.06), vec2(-0.05, 0.0)), sd_segment(es, vec2(-0.05, 0.0), vec2(0.08, -0.06))) - 0.036;
	d_eye = mix(d_eye, d_sq, smoothstep(0.35, 0.8, squeeze));
	// happy ^^
	float d_hp = sd_arc(e + vec2(0.0, 0.045), vec2(sin(1.05), cos(1.05)), 0.11) - 0.038;
	d_eye = mix(d_eye, d_hp, happy);
	// dead X
	float d_x = min(sd_segment(e, vec2(-0.08, -0.08), vec2(0.08, 0.08)), sd_segment(e, vec2(-0.08, 0.08), vec2(0.08, -0.08))) - 0.036;
	d_eye = mix(d_eye, d_x, dead);

	// scared: white sclera with a small pupil looking along travel
	float sclera_d = d_ell;
	vec2 pup_off = clamp(look, vec2(-1.0), vec2(1.0)) * vec2(0.035, 0.05);
	float d_pupil = length((e - pup_off) / vec2(0.05, 0.065)) - 1.0;
	float wide_k = wide * (1.0 - dead) * (1.0 - happy) * smoothstep(0.3, 0.7, open_amt);

	// --- mouth (SDF morphs: smile -> D grin / O gasp / flat dead) ---
	vec2 mc = vec2(0.0, 0.14);
	float mr = 0.46;
	float ap = 0.88 + grin * 0.12;
	vec2 m = vec2(f.x, -(f.y - mc.y));
	float d_smile = sd_arc(m, vec2(sin(ap), cos(ap)), mr) - 0.072;
	float chord_y = mc.y - mr * cos(ap) * 0.98;
	float d_grin = max(length(f - mc) - mr, f.y - chord_y);
	float d_mouth = mix(d_smile, min(d_smile, d_grin), grin);
	float d_o = length((f - vec2(0.0, -0.24)) / vec2(0.085, 0.11) ) - 1.0;
	d_o *= 0.09;
	d_mouth = mix(d_mouth, d_o, gasp * (1.0 - dead));
	float d_flat = sd_segment(f, vec2(-0.19, -0.24), vec2(0.19, -0.22)) - 0.045;
	d_mouth = mix(d_mouth, d_flat, dead);
	float mouth_inside = (1.0 - smoothstep(-0.004, 0.004, max(length(f - mc) - mr + 0.05, f.y - chord_y + 0.03))) * grin * (1.0 - gasp) * (1.0 - dead);

	float aa = fwidth(f.x) * 1.2 + 0.002;
	float ink_eye = 1.0 - smoothstep(-aa, aa, d_eye);
	float ink_mouth = 1.0 - smoothstep(-aa, aa, d_mouth);
	float sclera = (1.0 - smoothstep(-aa, aa, sclera_d)) * wide_k;
	float pupil = 1.0 - smoothstep(-0.08, 0.08, d_pupil);

	// --- body shading ---
	float grad = smoothstep(-0.9, 0.7, p.y);
	vec3 col = mix(body_deep, body_color, grad);
	// fine brushed/pearl variation
	float grain = noise3(p * 9.0) * 0.5 + noise3(p * 23.0) * 0.5;
	col *= 0.96 + grain * 0.06;
	float rough = 0.28 + grain * 0.1;

	// engraved rolling ring: groove + rivets, rotated by pattern_angle (world roll)
	float ca = cos(pattern_angle), sa = sin(pattern_angle);
	vec2 rp = mat2(vec2(ca, sa), vec2(-sa, ca)) * p.xy;
	float rr = length(p.xy);
	float groove = 1.0 - smoothstep(0.004, 0.014, abs(rr - 0.9));
	float ang = atan(rp.y, rp.x);
	float cell = TAU / 10.0;
	float la = (fract(ang / cell + 0.5) - 0.5) * cell * rr;
	float rivet = 1.0 - smoothstep(0.022, 0.034, length(vec2(la, rr - 0.9)));
	col = mix(col, body_deep * 0.72, groove * 0.55);
	col = mix(col, vec3(1.0, 0.86, 0.45), rivet * 0.45);
	rough = mix(rough, 0.12, rivet);

	// face ink on top (face occludes pattern)
	float ink = max(ink_eye * (1.0 - sclera), ink_mouth) * front;
	// sclera + pupil
	vec3 scl = mix(vec3(0.96, 0.95, 0.92), ink_color, pupil);
	col = mix(col, scl, sclera * front);
	col = mix(col, ink_color, ink);
	col = mix(col, mouth_color, mouth_inside * front * ink_mouth);

	// catchlights in the eyes (painted, so the face always reads as alive)
	vec2 cl = e - vec2(-0.028, 0.06 * open_amt) - pup_off * wide_k;
	float catch = (1.0 - smoothstep(0.018, 0.028, length(cl))) * ink_eye * front * (1.0 - dead) * (1.0 - happy) * smoothstep(0.4, 0.8, open_amt) * (1.0 - squeeze);

	// soft AO where the painted features "indent" the surface
	float ao_d = min(d_eye, d_mouth);
	float ao = 1.0 - (1.0 - smoothstep(0.0, 0.05, ao_d)) * 0.28 * front * (1.0 - ink);
	col *= ao;
	// thin dark silhouette outline (EE's smiley has a dark ring) so the ball pops on bright and dark backdrops
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float outline = 1.0 - smoothstep(0.2, 0.34, ndv);
	col = mix(col, outline_color, outline * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.18, ink);
	METALLIC = 0.0;
	SPECULAR = 0.6 * (1.0 - outline * 0.8);
	CLEARCOAT = 1.0 - outline;
	CLEARCOAT_ROUGHNESS = 0.05;
	SSS_STRENGTH = 0.25 * (1.0 - ink);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 emis = rim_color * fres * rim_strength * (1.0 - ink * 0.8) * (1.0 - outline * 0.7);
	emis += col * self_glow * (1.0 - ink);
	emis += vec3(1.0) * catch * 0.9;
	emis += glow_color * glow;

	// dissolve (death shatter / respawn materialize)
	if (dissolve > 0.0) {
		float n = noise3(p * 5.0 + vec3(TIME * 0.5)) * 0.7 + noise3(p * 14.0) * 0.3;
		float th = dissolve * 1.1 - 0.05;
		if (n < th) {
			discard;
		}
		float edge = 1.0 - smoothstep(0.0, dissolve_edge, n - th);
		emis += dissolve_color * edge * 6.0;
	}
	EMISSION = emis;
}
