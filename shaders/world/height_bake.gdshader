shader_type canvas_item;
// One-shot bake of the full terrain height field z(p) (same function the terrain used to evaluate per
// vertex) into an HDR SubViewport, 16 texels per tile, covering the level plus a margin.
render_mode unshaded, blend_disabled;

#include "res://shaders/world/terrain_common.gdshaderinc"

uniform float margin = 16.0;

void fragment() {
	vec2 dom = level_size + 2.0 * margin;
	vec2 p = UV * dom - margin;
	COLOR = vec4(height_at(p), 0.0, 0.0, 1.0);
}
