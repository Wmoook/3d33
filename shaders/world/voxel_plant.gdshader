shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// WorldVoxel plants: crossed quads (Minecraft style) drawn procedurally with alpha scissor: tall grass tufts,
// ferns and flowers (red / yellow / blue heads). UV = quad coords (0..1, v up), UV2 = (block id, random).
// Tips sway in the wind; same aerial haze as the blocks.

#include "res://shaders/world/vista_common.gdshaderinc"

uniform vec3 grass_col = vec3(0.06, 0.13, 0.006);
uniform vec3 grass_b = vec3(0.056, 0.23, 0.005);
uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform float fog_density = 0.0011;
uniform float haze_near = 0.08;
uniform float haze_far = 0.40;
uniform float fade = 1.0;
uniform vec3 vol_origin = vec3(-104.0, -256.0, 3.0);

varying vec3 w_pos;
varying vec2 kind;

float h11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	kind = UV2;
	float sway = sin(TIME * 1.6 + VERTEX.x * 0.35 + VERTEX.z * 0.2) * 0.07 + sin(TIME * 3.7 + VERTEX.x * 1.3) * 0.025;
	VERTEX.x += sway * UV.y * UV.y;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	int id = int(kind.x + 0.5);
	float rnd = kind.y;
	vec2 uv = UV;
	float a = 0.0;
	vec3 col = mix(grass_col, grass_b, rnd) * mix(0.55, 1.15, uv.y);
	if (id == 70 || id == 74) {
		// blades: 6 tapered strands with a lean
		int nb = id == 70 ? 6 : 5;
		for (int b = 0; b < nb; b++) {
			float fb = float(b);
			float bx = 0.12 + 0.76 * h11(fb + rnd * 13.0);
			float hh = mix(0.55, 1.0, h11(fb * 3.7 + rnd * 7.0));
			float lean = (h11(fb * 1.9 + rnd) - 0.5) * 0.5;
			float cx = bx + lean * uv.y * uv.y;
			float w = (id == 70 ? 0.07 : 0.1) * (1.0 - uv.y / hh);
			if (id == 74) {
				// fern frond: leaflets along the stem
				w *= 0.6 + 0.8 * abs(sin(uv.y * 26.0));
			}
			if (uv.y < hh && abs(uv.x - cx) < w) {
				a = 1.0;
			}
		}
		if (id == 74) {
			col *= vec3(0.7, 1.0, 0.75);
		}
	} else {
		// flower: stem + two leaves + a round head
		float stem = abs(uv.x - 0.5 - sin(uv.y * 3.0) * 0.03);
		if (stem < 0.035 && uv.y < 0.78) {
			a = 1.0;
		}
		vec2 lf = vec2(abs(uv.x - 0.5) - 0.12, uv.y - 0.3);
		if (length(lf * vec2(1.0, 2.2)) < 0.11) {
			a = 1.0;
		}
		vec2 hq = uv - vec2(0.5, 0.84);
		float r = length(hq);
		float ang = atan(hq.y, hq.x);
		float petal = 0.13 + 0.035 * cos(ang * 5.0);
		if (r < petal) {
			a = 1.0;
			vec3 pc = id == 71 ? vec3(0.75, 0.04, 0.03) : (id == 72 ? vec3(0.95, 0.72, 0.05) : vec3(0.18, 0.3, 0.9));
			col = r < 0.045 ? vec3(0.9, 0.75, 0.2) : pc * (0.8 + 0.4 * (1.0 - r / petal));
		}
	}
	if (a < 0.5) {
		discard;
	}
	vec3 sd = normalize(sun_dir);
	vec3 cam = CAMERA_POSITION_WORLD;
	float f = vista_fog_f(w_pos, cam, fog_density, 0.0);
	float dz = -w_pos.z - vol_origin.z;
	f = max(f, mix(haze_near, haze_far, smoothstep(0.0, 120.0, dz)));
	{
		vec3 lum_w = vec3(0.2126, 0.7152, 0.0722);
		float pl = dot(col * (1.6 * max(sd.y, 0.0) * vec3(1.0, 0.86, 0.66) + 0.55), lum_w);
		float sl = dot(vista_sky(normalize(w_pos - cam), sd), lum_w);
		if (mix(pl, sl, f) < 0.42 * sl) {
			f = clamp((0.42 * sl - pl) / max(sl - pl, 1e-3), f, 1.0);
		}
	}
	f = mix(1.0, f, fade);
	ALBEDO = col * (1.0 - f);
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.35) * col;
	EMISSION = vista_sky(normalize(w_pos - cam), sd) * f;
}
