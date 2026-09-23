shader_type spatial;
// WorldForest block-tree layers: the level's own forest blocks (leaf-crown tiles, bark trunk tiles, pine
// needle tiles, lawn / earth floor tiles) on three depth layers (near / mid / far), each layer's same-material
// tiles greedy-merged into big slabs. Shading is continuous in world space (the shared photoscan detail via
// pbr_terrain at the world tile coordinate), so a crown reads as one tile-stepped mass: bevels, edge shade and
// rim light come only from the mass silhouette (occ_tex neighbours), then per-layer atmospheric perspective.
// INSTANCE_COLOR = layer's material colour (linear). INSTANCE_CUSTOM: r = material id, g = layer fog 0..1,
// b = layer 0/1/2, a = slab depth.
render_mode cull_back;

#include "res://shaders/world/pbr_detail.gdshaderinc"
#include "res://shaders/world/forest_mask.gdshaderinc"

uniform vec3 fog_near : source_color = vec3(0.035, 0.07, 0.04);
uniform vec3 fog_far : source_color = vec3(0.05, 0.22, 0.15);
uniform vec3 haze_col : source_color = vec3(0.07, 0.30, 0.22);   // lit mist between the layers (saturated green-teal)
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // leaf clusters (RGBA)
uniform vec3 sun_col : source_color = vec3(1.0, 0.92, 0.66);     // light through the crown gaps
uniform float shade = 0.75;          // under the closed canopy
uniform float floor_y = -60.0;       // region's lowest forest floor (world y)
uniform float canopy_y = -30.0;      // region's canopy underside (world y)
uniform sampler2D occ_tex : filter_nearest, repeat_disable;   // per world tile: R/G/B = material class / 4 of
uniform vec2 occ_origin = vec2(0.0);                             // the near / mid / far layer (0 = empty)

varying vec3 v_wp;
varying vec3 v_local;
varying vec3 v_col;
varying vec4 v_c;

void vertex() {
	v_local = VERTEX;
	// inset every slab face by 0.001 tile: its faces then never lie exactly on a depth-volume face or a
	// neighbouring cube's face (tile-aligned, coplanar -> z-fighting "flicker" while moving, 92% of the
	// audit's flicker). The 0.001-tile gaps this opens are far below a pixel.
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	VERTEX -= sign(VERTEX) * 0.001 / sc;       // 0.001 tile inset whatever the slab size
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR.rgb;
	v_c = INSTANCE_CUSTOM;
}

float fb_hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

float fb_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(fb_hash(i), fb_hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	if (vis < 0.01 || !forest_visible(v_wp, CAMERA_POSITION_WORLD)) {
		discard;
	}
	int mat = int(v_c.r + 0.5);
	int layer = clamp(int(v_c.b + 0.5), 0, 2);
	vec3 gn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// which world tile this fragment belongs to (nudged inside the slab), and which of its sides are the
	// mass silhouette (1) vs the same mass continuing (0)
	vec3 ip = v_wp - gn * 0.02;
	ivec2 cell = ivec2(floor(ip.xy - occ_origin));
	float own = texelFetch(occ_tex, cell, 0)[layer];
	float open_l = step(0.1, abs(texelFetch(occ_tex, cell + ivec2(-1, 0), 0)[layer] - own));
	float open_r = step(0.1, abs(texelFetch(occ_tex, cell + ivec2(1, 0), 0)[layer] - own));
	float open_u = step(0.1, abs(texelFetch(occ_tex, cell + ivec2(0, 1), 0)[layer] - own));
	float open_d = step(0.1, abs(texelFetch(occ_tex, cell + ivec2(0, -1), 0)[layer] - own));
	vec3 lc = vec3(fract(ip.xy) - 0.5, v_local.z);     // position inside the tile (x, y) / slab (z)
	float side_x = lc.x < 0.0 ? open_l : open_r;
	float side_y = lc.y > 0.0 ? open_u : open_d;
	// side / top / bottom faces sit in the shadow of the mass: dim them so steps read as depth, not as pale
	// sunlit planks between the fronts
	float side_face = 1.0 - smoothstep(0.5, 0.9, abs(gn.z));
	// top / bottom faces are only ever seen as thin slivers from the straight-on camera: shade them like the
	// front faces (no dark underside lines where a whole block row sits near eye height)
	float horiz = smoothstep(0.5, 0.9, abs(gn.y));
	gn = normalize(mix(gn, vec3(0.0, 0.0, 1.0), horiz * 0.85));
	// bevel + edge shade only toward open sides: inside a crown / trunk the tile grid disappears
	vec3 a = abs(lc) * 2.0;                  // 0 centre .. 1 face
	vec3 ao_a = vec3(a.x * side_x, a.y * side_y, a.z);
	vec3 bev = smoothstep(0.76, 1.0, a) * sign(lc) * vec3(side_x, side_y, 1.0);
	vec3 n = normalize(gn + (bev - gn * dot(bev, gn)) * 0.9);
	float edge = max(ao_a.x, ao_a.y);        // front face: distance to the mass silhouette
	vec3 albedo = v_col;
	float rough = 0.8;
	float ao = 1.0;
	vec2 p = vec2(v_wp.x, -v_wp.y);
	pbr_terrain(mat, v_wp, gn, p, CAMERA_POSITION_WORLD, albedo, n, rough, ao);
	albedo *= mix(0.88, 1.1, fb_noise(v_wp.x * 0.23 + v_wp.y * 0.11 + float(layer) * 7.0));   // broad world-space tone
	float rim = 0.0;
	float mass = 1.0;                        // trunk grain / core carried into the mist so far trunks stay trunks
	if (mat == 13) {
		// trunks: vertical bark grain, a dark core and lit rims, rounded toward the open sides like a cylinder
		float gx = v_wp.x * 3.2 + v_wp.z * 1.7;
		float grain = fb_noise(gx) * 0.55 + fb_noise(gx * 2.7 + 17.0) * 0.3 + fb_noise(gx * 6.1 + v_wp.y * 0.2) * 0.15;
		// photoscan bark at slab scale (no distance fade), stretched upright, plus the broad furrows
		float bl = texture(pbr_tex, vec3(v_wp.x * 0.55, -v_wp.y * 0.28, float(PBR_BARK))).r * 2.0;
		albedo *= vec3(0.98, 0.82, 0.62) * mix(0.6, 1.45, bl);
		albedo *= mix(0.5, 1.05, grain);                          // deep vertical furrows
		float ex = ao_a.x;
		float core = mix(0.5, 0.95, smoothstep(0.15, 0.95, ex));
		albedo *= core;                                           // dark core, lighter bark toward the rims
		mass = mix(0.6, 1.1, grain) * mix(0.55, 1.4, bl) * mix(0.7, 1.15, smoothstep(0.15, 0.95, ex)) * mix(1.0, 0.6, side_face);
		n = normalize(n + vec3(sign(lc.x) * smoothstep(0.35, 1.0, ex) * 0.9 * side_x, 0.0, 0.0));
		rim = smoothstep(0.72, 0.98, ex);
	} else if (mat == 11 || mat == 10) {
		// leafy slabs: two overlapping world-space layers of photoscanned leaf clusters, dark gaps between them
		// (the two layers at unrelated scales / a 37 degree turn, warped by low noise: no visible wallpaper repeat)
		vec2 wq = vec2(v_wp.x, -v_wp.y);
		vec2 warp = vec2(fb_noise(wq.y * 0.21 + wq.x * 0.05), fb_noise(wq.x * 0.19 + 5.0)) * 1.6;
		vec2 lu = (wq + warp) * 0.33 + vec2(v_wp.z * 0.37, 0.0);
		vec4 l1 = texture(leaf_tex, lu);
		vec4 l2 = texture(leaf_tex, mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799)) * (wq - warp) * 0.47 + vec2(0.31, 0.57));
		float l1v = dot(l1.rgb, vec3(0.3, 0.55, 0.15));
		float l2v = dot(l2.rgb, vec3(0.3, 0.55, 0.15));
		float leaf = max(l1.a * (0.55 + l1v * 1.6), l2.a * (0.4 + l2v * 1.3));
		float cover = max(l1.a, l2.a);
		albedo *= mix(0.35, 1.0, cover) * mix(0.8, 1.35, clamp(leaf, 0.0, 1.0));
		mass = mix(0.55, 1.2, cover * clamp(leaf, 0.0, 1.0));
		albedo *= mix(1.0, 0.8, smoothstep(0.6, 1.0, edge));
	}
	ao *= 1.0 - smoothstep(0.7, 1.0, edge) * 0.45;              // contact shadow at the silhouette only
	// canopy light: brighter up under the crowns (and more so under a gap), darker toward the floor
	float h = clamp((v_wp.y - floor_y) / max(canopy_y - floor_y, 1.0), 0.0, 1.0);
	float gap = smoothstep(0.55, 0.85, fb_noise(v_wp.x * 0.09 + v_wp.z * 0.05 + 3.0));
	float light = mix(0.55, 1.15, h) * (1.0 + gap * 0.35 * h);
	// light shafts crossing the layers: slanted bands through the gaps, strongest in the mist
	float s_u = v_wp.x + v_wp.y * 0.42 + v_wp.z * 0.2;
	float band = sin(s_u * 0.29) * 0.55 + sin(s_u * 0.113 + 1.7) * 0.45;
	float shaft = smoothstep(0.35, 0.95, band) * (0.4 + 0.6 * h);
	// atmospheric perspective: every layer back is hazier, bluer-green and flatter
	float fog = clamp(v_c.g, 0.0, 0.85);
	float fz = smoothstep(-2.0, -45.0, v_wp.z);
	vec3 fc = mix(fog_near, fog_far, fz);
	vec3 col = albedo * shade * ao * light * mix(1.0, 0.4, side_face);
	rim *= 1.0 - side_face;
	vec3 mist = mix(fc, haze_col, fz) * mix(0.55, 1.1, h);      // the mist itself is lit by the canopy
	ALBEDO = mix(col, mist * 0.35, fog) * mix(0.15, 1.0, vis) * mix(1.0, 0.5, side_face);
	vec3 e = mist * fog * 0.55 * mass;
	e += sun_col * shaft * (0.03 + 0.1 * fog);
	e += sun_col * rim * 0.03 * (1.0 - fog) * (0.5 + 0.5 * h);     // barely-there rim; silhouettes read by shadow
	EMISSION = e * vis + vec3(0.02, 0.035, 0.022) * vis + shade_floor(ALBEDO);   // never black
	ROUGHNESS = rough;
	SPECULAR = mix(0.2, 0.0, side_face);
	NORMAL = normalize((VIEW_MATRIX * vec4(safe_normal(mix(safe_normal(n, gn), gn, fog), gn), 0.0)).xyz);
}
