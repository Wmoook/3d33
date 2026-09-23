
// detail's deep-forest hollows (WorldForest.hollow_image): no voxel fragment in front of z -12.5 may show
// through a hollow tile (its ray to the camera crosses the gameplay plane inside the hollow)
uniform sampler2D forest_tex : filter_nearest, repeat_disable;
uniform float has_forest = 0.0;
uniform vec2 forest_size = vec2(400.0, 200.0);
bool in_forest_hollow(vec3 wp, vec3 cam) {
	if (has_forest < 0.5 || wp.z < -12.5) {
		return false;
	}
	vec3 d = wp - cam;
	vec2 p = cam.xy + d.xy * (-cam.z / d.z);
	vec2 tc = vec2(p.x, -p.y);
	if (tc.x < 0.0 || tc.y < 0.0 || tc.x >= forest_size.x || tc.y >= forest_size.y) {
		return false;
	}
	return texelFetch(forest_tex, ivec2(floor(tc)), 0).r > 0.5;
}
