shader_type spatial;
render_mode depth_draw_opaque, cull_back, unshaded;
#include "res://shaders/world/pbr_detail.gdshaderinc"
// WorldVoxelFore: foreground blocks in front of the gameplay plane (z +1 .. +13).
//
// BLOCK-ALIGNED CLEARING (vertex): every block knows its centre (CUSTOM0). The centre's view ray is cast onto
// the gameplay plane z = 0; the block SHRINKS AWAY as a whole (never a curve through a cube) when
//   - that point is inside the screen-shaped window around the ball, or
//   - the coverable-rock distance field there (fg_dist, Chebyshev tiles) is smaller than the block's projected
//     half size, i.e. the block would not lie entirely over coverable rock.
// OCCLUSION SAFETY NET (fragment, unchanged rule): the fragment's own ray must land on a coverable tile and
// outside a hard circle around the ball, else it is discarded. With the vertex rule this never triggers on a
// full-size block; it only guarantees that nothing the player needs can ever be hidden.
// LOOK: self-lit (unshaded) so the value is controlled: the level's block colours with grass sides, photoscan
// detail, vertex AO, darker toward the bottom of each mass and toward the camera, desaturated and cool, at
// ~50-60 % of the gameplay terrain's value, so it reads as foreground depth, never as more level.

uniform sampler2D fg_mask : filter_nearest, repeat_disable;   // 1 = coverable tile (eroded solid interior)
uniform sampler2D fg_dist : filter_nearest, repeat_disable;   // Chebyshev distance to non-coverable / 255
uniform vec2 mask_size = vec2(400.0, 200.0);
uniform vec3 ball_pos = vec3(-1000.0, -1000.0, 0.0);
uniform float ball_r = 5.5;          // window half height (tiles); half width = 1.75x
uniform float safe_r = 3.0;          // hard per-fragment clear circle around the ball
uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform float value = 0.55;
uniform float desat = 0.35;
uniform vec3 cool = vec3(0.88, 0.94, 1.05);
uniform float fade = 1.0;
uniform float debug_mask = 0.0;      // tests: 1 = flat magenta (safety check)
uniform vec3 dirt_col = vec3(0.17, 0.12, 0.07);
uniform vec3 grass_col = vec3(0.06, 0.13, 0.006);

varying vec3 w_pos;
varying vec3 w_nrm;
varying vec3 v_center;
varying float v_ao;
varying float v_depth;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 on_plane(vec3 wp, vec3 cam) {
	vec3 d = wp - cam;
	float t = d.z < -1e-4 ? -cam.z / d.z : 1e6;
	return cam.xy + d.xy * t;
}

void vertex() {
	vec3 c = CUSTOM0.xyz;
	v_center = c;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 p = on_plane(c, cam);
	vec2 tc = vec2(p.x, -p.y);
	// projected half diagonal of the block on the plane (tiles) + margin
	float proj = cam.z / max(cam.z - c.z, 0.5);
	float need = 0.75 * proj + 0.6;
	float dtl = 0.0;
	if (tc.x > 0.0 && tc.y > 0.0 && tc.x < mask_size.x && tc.y < mask_size.y) {
		dtl = textureLod(fg_dist, tc / mask_size, 0.0).r * 255.0;
	}
	float s = clamp((dtl - need) * 4.0, 0.0, 1.0);   // whole blocks: in or out within a quarter tile
	vec2 q = abs(p - ball_pos.xy) / vec2(ball_r * 1.75, ball_r);
	float se = pow(q.x, 4.0) + pow(q.y, 4.0);
	s *= smoothstep(1.0, 1.12, se);
	s *= fade;
	s = s * s * (3.0 - 2.0 * s);
	VERTEX = c + (VERTEX - c) * s;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_ao = UV.x;
	v_depth = UV.y;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec2 p = on_plane(w_pos, cam);
	vec2 tc = vec2(p.x, -p.y);
	bool ok = tc.x > 0.0 && tc.y > 0.0 && tc.x < mask_size.x && tc.y < mask_size.y
		&& texelFetch(fg_mask, ivec2(floor(tc)), 0).r > 0.5
		&& length(p - ball_pos.xy) > safe_r;
	if (!ok) {
		discard;
	}
	int id = int(COLOR.a * 255.0 + 0.5);
	vec3 gn = normalize(w_nrm);
	vec3 col = COLOR.rgb;   // block colour (linear)
	vec3 bpos = floor(v_center);
	float hb = h12(bpos.xy * 1.7 + bpos.z * 13.1);
	// in-face coordinates relative to the (possibly shrinking) block
	vec3 lp = w_pos - v_center + 0.5;
	vec2 uv = abs(gn.y) > 0.5 ? lp.xz : (abs(gn.x) > 0.5 ? lp.zy : lp.xy);
	uv = clamp(uv, 0.0, 1.0);
	int layer = PBR_ROCK;
	float sc = 0.35;
	if (id == 1) {
		if (abs(gn.y) < 0.5) {
			float jag = h12(vec2(floor(uv.x * 8.0), bpos.x + bpos.z * 7.0)) * 0.22;
			if (lp.y < 0.8 - jag) {
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
		col *= 0.75;
	} else if (id == 14 || id == 15) {
		layer = PBR_ASHLAR; sc = 0.5;
	}
	// Minecraft-like 4x4 texel variation + per-block jitter + vertex AO
	float tex = h12(floor(uv * 4.0) + bpos.xy * 5.3 + bpos.z * 11.7);
	col *= (0.92 + 0.16 * hb) * (0.88 + 0.24 * tex) * mix(0.45, 1.0, v_ao);
	float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	col *= mix(0.86, 1.0, smoothstep(0.0, 0.1, e));
	vec3 n = gn;
	float rough = 0.9;
	float ao = 1.0;
	PbrS ps = pbr_tri(layer, bpos + lp + vec3(hb * 11.0, hb * 7.0, hb * 5.0), gn, sc, 1.0, false);
	pbr_apply(ps, 0.75, 1.0, 0.4, 0.05, col, n, rough, ao);
	col *= mix(1.0, ao, 0.6);
	// own soft lighting: key from the sun side, sky fill, every face textured and lit (no flat ambient faces)
	vec3 sd = normalize(sun_dir);
	float ndl = dot(n, sd) * 0.5 + 0.5;
	float light = 0.55 + 0.75 * ndl * ndl + 0.15 * max(n.y, 0.0);
	col *= light * vec3(1.0, 0.95, 0.88);
	// Trine / Ori style depth: darker toward the bottom of each mass and the nearer to the camera
	float dk = mix(1.0, 0.55, smoothstep(0.0, 9.0, v_depth)) * mix(1.0, 0.62, smoothstep(2.0, 12.0, v_center.z));
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(l), desat) * cool * value * dk;
	ALBEDO = col;
	if (debug_mask > 0.5) {
		ALBEDO = vec3(1.2, 0.0, 1.2);
	}
}
