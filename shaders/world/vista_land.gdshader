shader_type spatial;
// WorldVista landscape heightfield (valley, forested hills, river, snowy mountain ranges). World-anchored,
// unshaded (own sun + sky lighting, no shadows/GI), hazed toward the day sky by distance (vista_common).
// COLOR: r = river water, g = forest cover, b = mountain (rock / snow rules), a = meadow.
render_mode unshaded, fog_disabled, cull_back, shadows_disabled;

#include "res://shaders/world/vista_common.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float fog_density = 0.0011;
uniform float fog_near = 0.2;
uniform float snow_line = -175.0;
uniform float water_y = -172.0;

varying vec3 v_wpos;
varying vec3 v_n;
varying vec4 v_col;
varying vec4 v_seam;
// world's depth continuation haze at its back edge (WorldDepth): albedo * (1 - 0.42) + haze * 0.42 * 0.9
const vec3 SEAM_HAZE = vec3(0.74, 0.82, 0.92);

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
	v_seam = CUSTOM0;
}

float tn(vec2 p, int ch) {
	vec4 t = texture(noise_tex, p);
	return ch == 0 ? t.r : (ch == 1 ? t.g : t.b);
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 wp = v_wpos;
	float dist = length(wp - cam);
	vec3 n = normalize(v_n);
	vec3 sd = normalize(sun_dir);
	// steep faces (cliffs, the handoff front face) sample their detail on the wall plane, not stretched
	vec2 q = abs(n.y) < 0.35 ? vec2(wp.x + wp.z, wp.y * 1.3) : wp.xz;
	// detail normal (forest canopy / rock strata) from the noise texture, fading with distance
	float e = 0.004;
	vec2 uq = q * 0.035;
	float h0 = tn(uq, 0);
	float hx = tn(uq + vec2(e, 0.0), 0);
	float hz = tn(uq + vec2(0.0, e), 0);
	float dk = mix(1.0, 0.25, smoothstep(120.0, 600.0, dist));
	float forest = v_col.g;
	float mtn = v_col.b;
	float bump = mix(3.5, 1.6, mtn) * dk;
	n = normalize(n + vec3(-(hx - h0), 0.0, -(hz - h0)) / e * 0.035 * bump * 0.12);
	float slope = 1.0 - n.y;
	float big = tn(q * 0.004, 1);
	float mid = tn(q * 0.013, 2);
	// ---- base albedo ----
	vec3 meadow = mix(vec3(0.30, 0.52, 0.14), vec3(0.48, 0.62, 0.18), big);
	vec3 wood = mix(vec3(0.07, 0.18, 0.08), vec3(0.15, 0.30, 0.11), h0) * (0.75 + 0.45 * mid);
	vec3 rock = mix(vec3(0.44, 0.42, 0.40), vec3(0.56, 0.54, 0.52), mid);
	vec3 mrock = mix(vec3(0.24, 0.26, 0.33), vec3(0.44, 0.44, 0.50), h0 * 0.6 + mid * 0.4);
	vec3 col = mix(meadow, wood, smoothstep(0.25, 0.6, forest + (h0 - 0.5) * 0.4));
	col = mix(col, rock, smoothstep(0.35, 0.6, slope) * (1.0 - mtn));
	// mountains: rock with strata, alpine meadow at the feet, snow above the snow line
	vec3 mc = mix(mix(vec3(0.30, 0.40, 0.24), mrock, smoothstep(-260.0, -230.0, wp.y + (mid - 0.5) * 30.0)), mrock, smoothstep(0.25, 0.5, slope));
	float sl = snow_line + (big - 0.5) * 55.0 + (h0 - 0.5) * 12.0;
	float snow = smoothstep(sl - 4.0, sl + 4.0, wp.y) * (1.0 - smoothstep(0.55, 0.8, slope + (h0 - 0.5) * 0.25));
	snow = max(snow, smoothstep(sl + 30.0, sl + 45.0, wp.y) * 0.85);
	mc = mix(mc, vec3(0.93, 0.95, 1.0), snow);
	col = mix(col, mc, mtn);
	// ---- lighting ----
	vec3 lit = vista_light(col, n, sd, 1.15, mix(0.62, 0.42, mtn));
	// ---- river water: reflects the sky, sun glints, soft banks ----
	float water = v_col.r;
	if (water > 0.01) {
		vec3 v = normalize(wp - cam);
		vec3 wn = normalize(vec3((tn(q * 0.08 + TIME * vec2(0.0, -0.02), 1) - 0.5) * 0.25, 1.0, (tn(q * 0.11 - TIME * vec2(0.01, 0.03), 2) - 0.5) * 0.25));
		vec3 r = reflect(v, wn);
		float fres = 0.35 + 0.65 * pow(1.0 - max(-v.y, 0.0), 4.0);
		vec3 wc = mix(vec3(0.12, 0.26, 0.30), vista_sky(r, sd) * 1.05, fres);
		wc += V_SUN * pow(max(dot(r, sd), 0.0), 60.0) * 1.5;
		lit = mix(lit, wc, smoothstep(0.2, 0.7, water));
	}
	// at the seam: world's painted colour and haze, melting into the vista's own look
	if (v_seam.a > 0.001) {
		vec3 sc = pow(v_seam.rgb, vec3(2.2));
		vec3 slit = vista_light(sc * (0.85 + 0.3 * h0), n, sd, 1.15, 0.62);
		slit = slit * (1.0 - 0.42) + SEAM_HAZE * 0.42 * 0.9;
		lit = mix(lit, slit, smoothstep(0.0, 1.0, v_seam.a));
	}
	ALBEDO = vista_fog(lit, wp, cam, sd, fog_density, fog_near * (1.0 - v_seam.a));
}
