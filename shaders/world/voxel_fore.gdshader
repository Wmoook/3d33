shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_lambert_wrap;
#include "res://shaders/world/pbr_detail.gdshaderinc"
// WorldVoxelFore: foreground blocks in front of the gameplay plane (z +1 .. +13).
// OCCLUSION-SAFE: every fragment's view ray (camera -> fragment) is intersected with the gameplay plane z = 0;
// the fragment is DISCARDED unless that point is inside coverable rock (fg_mask: static solid interior, eroded,
// doors / gates / one-ways / coin doors / gameplay blocks = air), and near the ball it always is. So nothing the
// player needs can ever be hidden. Look: the level's block colours (vertex COLOR, with baked vertex AO),
// darker / cooler / slightly desaturated and soft, like out-of-focus near foliage and stone.

uniform sampler2D fg_mask : filter_linear, repeat_disable;
uniform vec2 mask_size = vec2(400.0, 200.0);
uniform vec3 ball_pos = vec3(-1000.0, -1000.0, 0.0);
uniform float ball_r = 6.0;
uniform float ball_fade = 3.0;
uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform float darken = 0.62;
uniform float desat = 0.3;
uniform vec3 cool = vec3(0.9, 0.95, 1.04);
uniform float fade = 1.0;
uniform float debug_mask = 0.0;
uniform vec3 dirt_col = vec3(0.17, 0.12, 0.07);
uniform vec3 grass_col = vec3(0.06, 0.13, 0.006);   // tests: 1 = flat magenta (safety check)

varying vec3 w_pos;
varying vec3 w_nrm;
varying float v_ao;
varying float v_depth;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_ao = UV.x;
	v_depth = UV.y;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 d = w_pos - cam;
	// camera -> fragment ray at the gameplay plane (the camera is always in front, cam.z > 0 > ... fragment z > 0)
	float t = d.z < -1e-4 ? -cam.z / d.z : 1e6;
	vec2 p = cam.xy + d.xy * t;
	vec2 tc = vec2(p.x, -p.y);   // tile space, y down
	float keep = 0.0;
	if (tc.x > 0.0 && tc.y > 0.0 && tc.x < mask_size.x && tc.y < mask_size.y) {
		// bilinear over tile centres: 1 deep inside the coverable interior, 0.5 on its edge
		float m = texture(fg_mask, tc / mask_size).r;
		// and the nearest tile itself must be coverable (never trust the blend alone)
		float mn = texelFetch(fg_mask, ivec2(floor(tc)), 0).r;
		keep = smoothstep(0.62, 0.9, m) * step(0.5, mn);
	}
	// the play area around the ball stays clear: a screen-shaped (super-elliptic) window, so the band only
	// ever frames the view from its edges and corners
	vec2 q = abs(p - ball_pos.xy) / vec2(ball_r * 1.75, ball_r);
	float se = pow(q.x, 4.0) + pow(q.y, 4.0);
	keep *= smoothstep(1.0, 1.0 + ball_fade, se);
	keep *= fade;
	// dithered edge (no transparency sorting; TAA smooths it)
	if (keep < 0.999 && keep <= h12(FRAGCOORD.xy)) {
		discard;
	}
	int id = int(COLOR.a * 255.0 + 0.5);
	vec3 gn = normalize(w_nrm);
	vec3 col = COLOR.rgb;   // block colour (linear)
	vec3 bpos = floor(w_pos - gn * 0.25);
	float hb = h12(bpos.xy * 1.7 + bpos.z * 13.1);
	// in-face coordinates
	vec2 uv = abs(gn.y) > 0.5 ? fract(w_pos.xz) : (abs(gn.x) > 0.5 ? fract(w_pos.zy) : fract(w_pos.xy));
	int layer = PBR_ROCK;
	float sc = 0.35;
	if (id == 1) {
		if (abs(gn.y) < 0.5) {
			float jag = h12(vec2(floor(uv.x * 8.0), bpos.x + bpos.z * 7.0)) * 0.22;
			if (fract(w_pos.y) < 0.8 - jag) {
				col = dirt_col;
				layer = PBR_SOIL;
			} else {
				layer = PBR_GRASS; sc = 0.55;
			}
		} else {
			layer = PBR_GRASS; sc = 0.55;
		}
	} else if (id == 2 || id == 3 || id == 4) {
		layer = PBR_SOIL; sc = 0.4;
	} else if (id == 11 || id == 17) {
		layer = PBR_BARK; sc = 0.5;
	} else if (id == 12 || id == 13) {
		layer = PBR_LITTER; sc = 0.45;
		col *= 0.6;   // near foliage reads as shade
	} else if (id == 14 || id == 15) {
		layer = PBR_ASHLAR; sc = 0.5;
	}
	col *= (0.9 + 0.2 * hb) * mix(0.4, 1.0, v_ao);
	// soft bevel on every block edge (a gentle rounded read; the band is out of focus)
	float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	col *= mix(0.88, 1.0, smoothstep(0.0, 0.1, e));
	vec3 n = gn;
	float rough = 0.9;
	float ao = 1.0;
	PbrS ps = pbr_tri(layer, w_pos + vec3(hb * 11.0, hb * 7.0, hb * 5.0), gn, sc, 1.0, false);
	pbr_apply(ps, 0.55, 0.45, 0.4, 0.05, col, n, rough, ao);
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	// Trine / Ori style depth silhouettes: darker toward the bottom of each mass and the nearer to the camera
	float dk = mix(1.0, 0.42, smoothstep(0.0, 9.0, v_depth)) * mix(1.0, 0.45, smoothstep(2.0, 12.0, w_pos.z));
	col = mix(col, vec3(l), desat) * cool * darken * dk;
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.15;
	AO = ao;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// soft "out of focus" read: a gentle rim so silhouettes stay legible but never crisp
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = vec3(0.10, 0.13, 0.18) * rim * 0.35;
	if (debug_mask > 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(1.2, 0.0, 1.2);
	}
}
