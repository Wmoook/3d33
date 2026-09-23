shader_type spatial;
// WorldVista block-built scenery (stand-in until WorldTerrain renders backdrop levels): a tile map painted
// with the level's own blocks, drawn as a smooth-silhouetted relief (edges rounded from a soft mask, bevel
// normals from its gradient), the per-tile minimap colours kept, lit by the sun and hazed by distance.
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;

#include "res://shaders/world/vista_common.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.30, 0.67, 0.68);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D col_tex : filter_nearest;
uniform sampler2D col_smooth : filter_linear;
uniform sampler2D mask_tex : filter_linear;
uniform vec2 map_size = vec2(64.0, 64.0);
uniform float fog_density = 0.0011;
uniform float fog_near = 0.15;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float m = texture(mask_tex, uv).r;
	if (m < 0.5) {
		discard;
	}
	vec2 e = 1.2 / map_size;
	float mx = texture(mask_tex, uv + vec2(e.x, 0.0)).r - texture(mask_tex, uv - vec2(e.x, 0.0)).r;
	float my = texture(mask_tex, uv + vec2(0.0, e.y)).r - texture(mask_tex, uv - vec2(0.0, e.y)).r;
	float edge = 1.0 - smoothstep(0.5, 0.95, m);
	vec3 n = normalize(vec3(-mx * 2.2, my * 2.2, 0.35 + 0.65 * (1.0 - edge)));
	vec3 c = mix(texture(col_tex, uv).rgb, texture(col_smooth, uv).rgb, 0.45);
	c = pow(c, vec3(2.2));     // minimap colours are sRGB
	float nz = texture(noise_tex, uv * map_size * 0.07).r;
	c *= 0.88 + 0.24 * nz;
	vec3 sd = normalize(sun_dir);
	vec3 lit = vista_light(c, n, sd, 1.2, 0.6);
	lit *= 1.0 - edge * 0.25;
	ALBEDO = vista_fog(lit, v_wpos, CAMERA_POSITION_WORLD, sd, fog_density, fog_near);
}
