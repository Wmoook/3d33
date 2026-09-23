shader_type spatial;
// WorldForest block-tree layers: the level's own forest blocks (leaf-crown tiles, bark trunk tiles, pine
// needle tiles, lawn / earth floor tiles) repeated as 1-tile cubes going back into depth. Same look as the
// terrain: the painted tile colour + the shared photoscan detail (pbr_terrain with the tile's material), a
// rounded block bevel, then depth fog (dark green near -> blue-green far) and canopy shade.
// INSTANCE_COLOR = painted colour (linear). INSTANCE_CUSTOM: r = material id, g = fog 0..1,
// b/a = source tile (x, y) in the painting (for the crown / litter masks).
render_mode cull_back;

#include "res://shaders/world/pbr_detail.gdshaderinc"
#include "res://shaders/world/forest_mask.gdshaderinc"

uniform vec3 fog_near : source_color = vec3(0.035, 0.07, 0.04);
uniform vec3 fog_far : source_color = vec3(0.09, 0.22, 0.18);
uniform float shade = 0.75;          // under the closed canopy

varying vec3 v_wp;
varying vec3 v_local;
varying vec3 v_col;
varying vec4 v_c;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX;
	v_col = COLOR.rgb;
	v_c = INSTANCE_CUSTOM;
}

void fragment() {
	if (vis < 0.01 || !forest_visible(v_wp, CAMERA_POSITION_WORLD)) {
		discard;
	}
	vec3 gn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// top / bottom faces are only ever seen as thin slivers from the straight-on camera: shade them like the
	// front faces (no dark underside lines where a whole block row sits near eye height)
	float horiz = smoothstep(0.5, 0.9, abs(gn.y));
	gn = normalize(mix(gn, vec3(0.0, 0.0, 1.0), horiz * 0.85));
	// block bevel: normals round off within 0.12 of each edge (like the terrain's pillow bevel)
	vec3 a = abs(v_local) * 2.0;             // 0 centre .. 1 face
	vec3 bev = smoothstep(0.76, 1.0, a) * sign(v_local);
	vec3 n = normalize(gn + (bev - gn * dot(bev, gn)) * 0.9);
	float edge = max(max(min(a.x, a.y), min(a.y, a.z)), min(a.x, a.z));
	vec3 albedo = v_col;
	float rough = 0.8;
	float ao = 1.0 - smoothstep(0.85, 1.0, edge) * 0.25;
	int mat = int(v_c.r + 0.5);
	vec2 p = v_c.ba + vec2(v_local.x + 0.5, 0.5 - v_local.y);
	pbr_terrain(mat, v_wp, gn, p, CAMERA_POSITION_WORLD, albedo, n, rough, ao);
	if (mat == 11 || mat == 10) {
		// leafy blocks: dome-ish lumps like world's crowns
		albedo *= mix(0.8, 1.1, smoothstep(0.2, 0.9, 1.0 - edge));
	}
	float fog = v_c.g;
	float fz = smoothstep(-2.0, -45.0, v_wp.z);
	vec3 fc = mix(fog_near, fog_far, fz);
	vec3 col = albedo * shade * ao;
	ALBEDO = mix(col, fc * 0.6, fog) * mix(0.15, 1.0, vis);
	EMISSION = fc * fog * 0.45 * vis + vec3(0.02, 0.035, 0.022) * vis;   // faint ambient floor: shade, never black
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(mix(n, gn, fog)), 0.0)).xyz);
}
