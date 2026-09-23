// WorldForest shared bits: the hard hollow mask (a fragment may only show where its camera ray crosses the
// gameplay plane inside a forest-hollow tile, so the illusion never draws over the painting's sky, halls or
// solids, whatever the parallax) and the per-region fade `vis` (0 = camera outside the forest).
uniform sampler2D hollow_tex : filter_nearest, repeat_disable;   // WorldForest.hollow_image (R8, 255 = hollow)
uniform vec2 hollow_size = vec2(400.0, 200.0);
uniform float vis = 1.0;

bool forest_visible(vec3 wp, vec3 cam) {
	vec3 d = wp - cam;
	if (abs(d.z) < 1e-4) {
		return false;
	}
	vec2 p = cam.xy + d.xy * (-cam.z / d.z);
	vec2 tc = vec2(p.x, -p.y);
	if (tc.x < 0.0 || tc.y < 0.0 || tc.x >= hollow_size.x || tc.y >= hollow_size.y) {
		return false;
	}
	return texelFetch(hollow_tex, ivec2(floor(tc)), 0).r > 0.5;
}
