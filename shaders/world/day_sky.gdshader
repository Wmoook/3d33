shader_type sky;
// Day sky DOME (daytime levels). Direction-only, so it behaves like a real sky at infinity: no parallax,
// no painted scenery. All scenery (valley, forests, ruins, cloud sea, mountain ranges) is REAL world-space
// geometry built by WorldVista behind the level, hazed toward exactly this sky colour (vista_common).
// Here: gradient + warm sun-side glow, a high cirrus deck (projected on a plane far above, so it
// foreshortens toward the horizon), and the radiance/ambient pass (cave hemisphere underground).

#include "res://shaders/world/vista_common.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform float brightness = 1.0;
uniform float cave_amount = 0.0;
uniform vec3 cave_top = vec3(0.5, 0.55, 0.6);
uniform vec3 cave_bottom = vec3(0.05, 0.05, 0.06);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float has_noise = 0.0;
uniform float cloud_base = -236.0;   // WorldVista's cloud sea base (world y)

float cirrus(vec2 q) {
	float a = texture(noise_tex, q * vec2(0.35, 1.0)).g;
	float b = texture(noise_tex, q * vec2(1.3, 3.2) + vec2(0.31, 0.7)).r;
	float c = a * 0.8 + b * 0.35;
	return smoothstep(0.55, 0.85, c);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sd = normalize(sun_dir);
	if (AT_CUBEMAP_PASS) {
		vec3 top = vec3(0.30, 0.50, 0.98);
		vec3 hor = vec3(0.75, 0.83, 0.95);
		vec3 gnd = vec3(0.36, 0.33, 0.27);
		vec3 c = d.y > 0.0 ? mix(hor, top, pow(d.y, 0.6)) : mix(hor, gnd, smoothstep(0.0, -0.4, d.y));
		c += vec3(1.0, 0.85, 0.6) * pow(max(dot(d, sd), 0.0), 8.0) * 0.8;
		vec3 cave = mix(cave_bottom, cave_top, smoothstep(-0.7, 0.9, d.y + d.z * 0.35 - d.x * 0.15));
		COLOR = mix(c, cave, cave_amount);
	} else {
		vec3 c = vista_sky(d, sd);
		// sun disk (only visible if a view ever turns toward it; the level's sun stands behind the viewer)
		float sdot = max(dot(d, sd), 0.0);
		c += V_SUN * (smoothstep(0.9994, 0.9997, sdot) * 10.0 + pow(sdot, 300.0) * 1.5);
		// high cirrus deck on a plane far above (wind-drifted)
		if (has_noise > 0.5 && d.y > 0.0) {
			vec2 q = d.xz / (d.y + 0.06) * 0.045 + vec2(TIME * 0.0012, TIME * 0.0004);
			float ci = cirrus(q);
			float fade = smoothstep(0.015, 0.14, d.y);
			c = mix(c, vec3(1.0, 0.99, 0.97), ci * fade * 0.55);
		}
		// below the horizon: the cloud sea continues to infinity (the vista's raymarched sea ends at z -830).
		// Same field as vista_clouds (same texture, scales and wind), intersected with its top plane.
		if (d.y < -0.0005 && has_noise > 0.5) {
			float t = (POSITION.y - (cloud_base + 12.0)) / (-d.y);
			if (t > 0.0) {
				vec2 xz = POSITION.xz + d.xz * t;
				vec2 w = vec2(TIME * 0.35, TIME * 0.12);
				float a = texture(noise_tex, (xz + w) * 0.0034).r;
				float b = texture(noise_tex, (xz + w * 1.6) * 0.0115 + vec2(0.37, 0.61)).g;
				float f = clamp((a * 0.62 + b * 0.36 - 0.3) * 3.2, 0.0, 1.0);
				// broad cloud shadows (higher decks passing over the sea) and blue-grey gaps down to the depths
				float shade = smoothstep(0.35, 0.7, texture(noise_tex, (xz + w * 0.6) * 0.0009 + vec2(0.5, 0.2)).b);
				vec3 gap = V_LOW * vec3(0.52, 0.6, 0.72);
				vec3 top = mix(vec3(0.62, 0.7, 0.86), vec3(1.02, 1.0, 0.96), smoothstep(0.2, 0.9, f));
				top *= mix(1.0, 0.72, shade);
				vec3 sea = mix(gap, top, smoothstep(0.02, 0.3, f));
				float haze = 1.0 - exp(-t * 0.0008);
				c = mix(sea, c, clamp(haze * 0.75 + smoothstep(-0.02, 0.0, d.y), 0.0, 1.0));
			}
		}
		COLOR = c * brightness;
	}
}
