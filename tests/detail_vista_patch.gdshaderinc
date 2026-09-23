// TEST COPY of shaders/world/vista_common.gdshaderinc with the zoom-independent haze proposal (detail).
// Shared day-sky model (WorldVista). The sky dome AND every vista mesh use the same sky colour, so the
// aerial perspective of far layers melts exactly into the sky behind them.
// World space: 1 tile = 1 unit, y up, level ground (valley floor) at y = -172, camera looks down -z.

const vec3 V_ZENITH = vec3(0.10, 0.30, 0.80);
const vec3 V_UPPER = vec3(0.20, 0.45, 0.92);
const vec3 V_HORIZON = vec3(0.50, 0.68, 0.96);
const vec3 V_LOW = vec3(0.52, 0.66, 0.92);      // below the horizon: the hazy lowlands under the cloud sea
const vec3 V_WARM = vec3(1.0, 0.9, 0.76);
const vec3 V_SUN = vec3(1.0, 0.9, 0.74);        // sunlight on the vista
const vec3 V_AMB = vec3(0.50, 0.62, 0.86);      // skylight on the vista

float v_h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Sky colour seen along world direction d (normalized). sd = direction TO the sun.
vec3 vista_sky(vec3 d, vec3 sd) {
	float y = d.y;
	vec3 c = mix(V_HORIZON, V_UPPER, smoothstep(-0.02, 0.26, y));
	c = mix(c, V_ZENITH, smoothstep(0.22, 0.75, y));
	c = mix(c, V_LOW, smoothstep(0.0, -0.12, y));
	// the sun stands high behind the viewer's left shoulder: a warm brightening on that side of the sky
	vec2 hd = normalize(d.xz + vec2(1e-4));
	vec2 hs = normalize(sd.xz + vec2(1e-4));
	float side = 0.5 + 0.5 * dot(hd, hs);
	c = mix(c, V_WARM, (1.0 - smoothstep(0.0, 0.22, abs(y))) * side * side * 0.2);
	c += V_SUN * pow(max(dot(d, sd), 0.0), 5.0) * 0.18;
	return c;
}

// Aerial perspective: haze toward the sky colour of the same direction. Thicker in the low valley air,
// thinner up at the peaks, never below `near_f` (the vista never competes with gameplay).
float vista_fog_f(vec3 wpos, vec3 cam, float density, float near_f) {
	// distance counted from where a zoom-30 camera would stand: pulling the camera back (overview) adds no haze
	float d = max(length(wpos - cam) - max(cam.z - 26.0, 0.0), 0.0);
	float hy = 0.5 * (wpos.y + cam.y);
	float hf = mix(1.3, 0.45, smoothstep(-175.0, 40.0, hy));
	float f = 1.0 - exp(-d * density * hf);
	// the haze floor only builds up with distance: the nearest layers keep their sunlit colour
	float nf = near_f * smoothstep(35.0, 230.0, d);
	return clamp(nf + (1.0 - nf) * f, 0.0, 1.0);
}

vec3 vista_fog(vec3 col, vec3 wpos, vec3 cam, vec3 sd, float density, float near_f) {
	vec3 dir = normalize(wpos - cam);
	return mix(col, vista_sky(dir, sd), vista_fog_f(wpos, cam, density, near_f));
}

// Simple outdoor lighting for unshaded vista materials (no shadows, no GI): sun wrap + sky hemisphere.
vec3 vista_light(vec3 albedo, vec3 n, vec3 sd, float sun_k, float amb_k) {
	float ndl = max(dot(n, sd) * 0.8 + 0.2, 0.0);
	float hemi = 0.55 + 0.45 * n.y;
	return albedo * (V_SUN * ndl * sun_k + V_AMB * hemi * amb_k);
}
