// Keep-out mask (WorldVoxel._keep_out_image): per level tile, how far back (R8 x 255 = units) no voxel may be
// seen through it - detail's deep-forest hollows (63) and world's recessed interior rooms (their back wall
// block). A fragment is discarded when its ray to the camera crosses the gameplay plane in such a tile and it
// lies in front of z = -limit.
uniform sampler2D forest_tex : filter_nearest, repeat_disable;
uniform float has_forest = 0.0;
uniform vec2 forest_size = vec2(400.0, 200.0);
bool in_forest_hollow(vec3 wp, vec3 cam) {
	if (has_forest < 0.5 || wp.z < -255.0) {
		return false;
	}
	vec3 d = wp - cam;
	vec2 p = cam.xy + d.xy * (-cam.z / d.z);
	vec2 tc = vec2(p.x, -p.y);
	if (tc.x < 0.0 || tc.y < 0.0 || tc.x >= forest_size.x || tc.y >= forest_size.y) {
		return false;
	}
	float lim = texelFetch(forest_tex, ivec2(floor(tc)), 0).r * 255.0;
	return lim > 0.5 && wp.z > -lim;
}
