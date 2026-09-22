class_name WorldSdfBaker
extends RefCounted
## Bakes the sub-tile signed distance fields of the level on the GPU (local RenderingDevice compute,
## synchronous). Output: Image FORMAT_RGBAH, size (W*SPT, H*SPT), texel (i,j) centred at tile-space
## ((i+.5)/SPT, (j+.5)/SPT) (y down). Channels (in tiles, + = inside):
##   R = foreground solid SDF after morphological OPENING (convex corners rounded by OPEN_R)
##   G = "wall" SDF (fg solid OR background block) after opening
##   B = smooth foreground pseudo-SDF from a gaussian-blurred mask (diagonal staircases -> straight lines)
##   A = raw foreground SDF (exact distance to the tile grid boundary), clamped to +-5.5

const SPT := 8          # samples per tile
const OPEN_R := 0.24    # convex corner rounding radius (tiles); < 0.5 so 1-wide strips survive
const CLOSE_R := 0.2    # concave fillet radius (covers <= 0.12 of an air tile at the corner)

const _GLSL_RAW := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer MaskBuf { uint mask[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer OutBuf { vec4 raw[]; };
layout(push_constant, std430) uniform Params { int W; int H; int SPT; int pad; } pc;
uint get_mask(ivec2 t) {
	if (t.y < 0) return 0u;                                          // above the level = open sky
	t = clamp(t, ivec2(0), ivec2(pc.W - 1, pc.H - 1));             // sides/bottom mirror the border
	return mask[t.y * pc.W + t.x];
}
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	int OW = pc.W * pc.SPT; int OH = pc.H * pc.SPT;
	if (px.x >= OW || px.y >= OH) return;
	vec2 p = (vec2(px) + 0.5) / float(pc.SPT);
	ivec2 c = ivec2(floor(p));
	uint m0 = get_mask(c);
	bool in_fg = (m0 & 1u) != 0u;
	bool in_w = (m0 & 2u) != 0u;
	float dfg = 5.5; float dw = 5.5;
	float bsum = 0.0; float wsum = 0.0;
	const float SIG = 0.62;
	for (int j = -5; j <= 5; j++) {
		for (int i = -5; i <= 5; i++) {
			ivec2 t = c + ivec2(i, j);
			uint m = get_mask(t);
			vec2 q = abs(p - (vec2(t) + 0.5)) - 0.5;
			float d = length(max(q, vec2(0.0)));
			if (((m & 1u) != 0u) != in_fg) dfg = min(dfg, d);
			if (((m & 2u) != 0u) != in_w) dw = min(dw, d);
			vec2 dc = p - (vec2(t) + 0.5);
			float g = exp(-dot(dc, dc) / (2.0 * SIG * SIG));
			wsum += g;
			if ((m & 1u) != 0u) bsum += g;
		}
	}
	// blurred-mask pseudo distance (iso 0.5 = smooth version of the outline; 0.643 = 1/(sig*sqrt(2pi)))
	float smooth_d = clamp((bsum / wsum - 0.5) / 0.643, -1.5, 1.5);
	raw[px.y * OW + px.x] = vec4(in_fg ? dfg : -dfg, in_w ? dw : -dw, smooth_d, 0.0);
}
"""

const _GLSL_OPEN := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer RawBuf { vec4 raw[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer OutBuf { vec2 outp[]; };
layout(push_constant, std430) uniform Params { int W; int H; int SPT; float R; } pc;
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	int OW = pc.W * pc.SPT; int OH = pc.H * pc.SPT;
	if (px.x >= OW || px.y >= OH) return;
	vec2 r0 = raw[px.y * OW + px.x].xy;
	vec2 res = r0;
	const int K = 10;
	float spt = float(pc.SPT);
	bool do_f = r0.x < pc.R && r0.x > -0.75;
	bool do_w = r0.y < pc.R && r0.y > -0.75;
	if (do_f || do_w) {
		float mf = 99.0; float mw = 99.0;
		for (int j = -K; j <= K; j++) {
			int y = clamp(px.y + j, 0, OH - 1);
			for (int i = -K; i <= K; i++) {
				int x = clamp(px.x + i, 0, OW - 1);
				vec2 v = raw[y * OW + x].xy;
				float d = length(vec2(float(i), float(j))) / spt;
				// sub-texel distance to the eroded set {raw >= R}
				if (v.x >= pc.R - 0.09) mf = min(mf, d + max(0.0, pc.R - v.x));
				if (v.y >= pc.R - 0.09) mw = min(mw, d + max(0.0, pc.R - v.y));
			}
		}
		if (do_f) res.x = (mf < 50.0) ? min(r0.x, pc.R - mf) : r0.x;
		if (do_w) res.y = (mw < 50.0) ? min(r0.y, pc.R - mw) : r0.y;
	}
	outp[px.y * OW + px.x] = res;
}
"""

## Closing (small concave fillets): air points within RC of the opened solid get filled.
const _GLSL_CLOSE := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer OpenBuf { vec2 opn[]; };
layout(set = 0, binding = 1, std430) restrict readonly buffer RawBuf { vec4 raw[]; };
layout(set = 0, binding = 2, std430) restrict writeonly buffer OutBuf { uvec2 outp[]; };
layout(push_constant, std430) uniform Params { int W; int H; int SPT; float R; } pc;
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	int OW = pc.W * pc.SPT; int OH = pc.H * pc.SPT;
	if (px.x >= OW || px.y >= OH) return;
	vec2 v0 = opn[px.y * OW + px.x];
	vec2 res = v0;
	const int K = 7;
	float spt = float(pc.SPT);
	bool do_f = v0.x > -pc.R && v0.x < 0.6;
	bool do_w = v0.y > -pc.R && v0.y < 0.6;
	if (do_f || do_w) {
		float mf = 99.0; float mw = 99.0;
		for (int j = -K; j <= K; j++) {
			int y = clamp(px.y + j, 0, OH - 1);
			for (int i = -K; i <= K; i++) {
				int x = clamp(px.x + i, 0, OW - 1);
				vec2 v = opn[y * OW + x];
				float d = length(vec2(float(i), float(j))) / spt;
				if (v.x <= -pc.R + 0.09) mf = min(mf, d + max(0.0, v.x + pc.R));
				if (v.y <= -pc.R + 0.09) mw = min(mw, d + max(0.0, v.y + pc.R));
			}
		}
		if (do_f) res.x = (mf < 50.0) ? max(v0.x, mf - pc.R) : v0.x;
		if (do_w) res.y = (mw < 50.0) ? max(v0.y, mw - pc.R) : v0.y;
	}
	vec4 r = raw[px.y * OW + px.x];
	outp[px.y * OW + px.x] = uvec2(packHalf2x16(res), packHalf2x16(vec2(r.z, r.x)));
}
"""

## Edge-preserving colour merge at tile resolution: dithered two-tone patterns of the same material
## melt into one mottled colour, real edges (text, region borders, other materials) stay.
const _GLSL_COLOR := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer InBuf { uint cin[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer OutBuf { uint cout_[]; };
layout(push_constant, std430) uniform Params { int W; int H; float SIG_R; float SIG_S; } pc;
void main() {
	ivec2 t = ivec2(gl_GlobalInvocationID.xy);
	if (t.x >= pc.W || t.y >= pc.H) return;
	vec4 c0 = unpackUnorm4x8(cin[t.y * pc.W + t.x]);
	uint m0 = uint(c0.a * 255.0 + 0.5);
	// checkerboard dither detection: direct neighbours differ, diagonals match -> merge regardless of colour
	int ndiff = 0; int dsame = 0;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k == 0 ? 1 : (k == 1 ? -1 : 0), k == 2 ? 1 : (k == 3 ? -1 : 0));
		ivec2 dg = ivec2(k < 2 ? 1 : -1, (k & 1) == 0 ? 1 : -1);
		vec4 cn = unpackUnorm4x8(cin[clamp(t + o, ivec2(0), ivec2(pc.W - 1, pc.H - 1)).y * pc.W + clamp(t + o, ivec2(0), ivec2(pc.W - 1, pc.H - 1)).x]);
		vec4 cd = unpackUnorm4x8(cin[clamp(t + dg, ivec2(0), ivec2(pc.W - 1, pc.H - 1)).y * pc.W + clamp(t + dg, ivec2(0), ivec2(pc.W - 1, pc.H - 1)).x]);
		if (distance(cn.rgb, c0.rgb) > 0.08 && abs(cn.a - c0.a) < 0.002) ndiff++;
		if (distance(cd.rgb, c0.rgb) < 0.02) dsame++;
	}
	float sig_r = (ndiff >= 3 && dsame >= 3) ? 4.0 : pc.SIG_R;
	vec3 acc = vec3(0.0); float wsum = 0.0;
	for (int j = -3; j <= 3; j++) {
		for (int i = -3; i <= 3; i++) {
			ivec2 q = clamp(t + ivec2(i, j), ivec2(0), ivec2(pc.W - 1, pc.H - 1));
			vec4 c = unpackUnorm4x8(cin[q.y * pc.W + q.x]);
			if (uint(c.a * 255.0 + 0.5) != m0) continue;
			vec3 d = c.rgb - c0.rgb;
			float w = exp(-dot(d, d) / (2.0 * sig_r * sig_r) - float(i * i + j * j) / (2.0 * pc.SIG_S * pc.SIG_S));
			acc += c.rgb * w; wsum += w;
		}
	}
	cout_[t.y * pc.W + t.x] = packUnorm4x8(vec4(acc / wsum, c0.a));
}
"""

## mask: PackedByteArray W*H, bit0 = fg solid, bit1 = wall (fg solid or bg block).
static func bake(mask: PackedByteArray, w: int, h: int) -> Image:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("WorldSdfBaker: no local RenderingDevice")
		return null
	var ow := w * SPT
	var oh := h * SPT
	var mask_u := PackedInt32Array()
	mask_u.resize(w * h)
	for i in w * h:
		mask_u[i] = mask[i]
	var mask_bytes := mask_u.to_byte_array()
	var buf_mask := rd.storage_buffer_create(mask_bytes.size(), mask_bytes)
	var buf_raw := rd.storage_buffer_create(ow * oh * 16)
	var buf_open := rd.storage_buffer_create(ow * oh * 8)
	var buf_out := rd.storage_buffer_create(ow * oh * 8)

	var sh_raw := _compile(rd, _GLSL_RAW)
	var sh_open := _compile(rd, _GLSL_OPEN)
	var sh_close := _compile(rd, _GLSL_CLOSE)
	var pipe_raw := rd.compute_pipeline_create(sh_raw)
	var pipe_open := rd.compute_pipeline_create(sh_open)
	var pipe_close := rd.compute_pipeline_create(sh_close)

	var set_raw := rd.uniform_set_create([_ubuf(0, buf_mask), _ubuf(1, buf_raw)], sh_raw, 0)
	var set_open := rd.uniform_set_create([_ubuf(0, buf_raw), _ubuf(1, buf_open)], sh_open, 0)
	var set_close := rd.uniform_set_create([_ubuf(0, buf_open), _ubuf(1, buf_raw), _ubuf(2, buf_out)], sh_close, 0)

	var pc1 := PackedInt32Array([w, h, SPT, 0]).to_byte_array()
	var pc2 := PackedByteArray()
	pc2.resize(16)
	pc2.encode_s32(0, w); pc2.encode_s32(4, h); pc2.encode_s32(8, SPT); pc2.encode_float(12, OPEN_R)
	var pc3 := pc2.duplicate()
	pc3.encode_float(12, CLOSE_R)

	var gx := int(ceil(ow / 8.0))
	var gy := int(ceil(oh / 8.0))
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipe_raw)
	rd.compute_list_bind_uniform_set(cl, set_raw, 0)
	rd.compute_list_set_push_constant(cl, pc1, pc1.size())
	rd.compute_list_dispatch(cl, gx, gy, 1)
	rd.compute_list_add_barrier(cl)
	rd.compute_list_bind_compute_pipeline(cl, pipe_open)
	rd.compute_list_bind_uniform_set(cl, set_open, 0)
	rd.compute_list_set_push_constant(cl, pc2, pc2.size())
	rd.compute_list_dispatch(cl, gx, gy, 1)
	rd.compute_list_add_barrier(cl)
	rd.compute_list_bind_compute_pipeline(cl, pipe_close)
	rd.compute_list_bind_uniform_set(cl, set_close, 0)
	rd.compute_list_set_push_constant(cl, pc3, pc3.size())
	rd.compute_list_dispatch(cl, gx, gy, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var data := rd.buffer_get_data(buf_out)
	for rid in [set_raw, set_open, set_close, pipe_raw, pipe_open, pipe_close, sh_raw, sh_open, sh_close, buf_mask, buf_raw, buf_open, buf_out]:
		rd.free_rid(rid)
	rd.free()
	return Image.create_from_data(ow, oh, false, Image.FORMAT_RGBAH, data)

## rgba: W*H*4 bytes (rgb colour, a = material id). Returns the merged colours (same layout).
static func merge_colors(rgba: PackedByteArray, w: int, h: int, sig_r := 0.2, sig_s := 1.4) -> PackedByteArray:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		return rgba
	var bin := rd.storage_buffer_create(rgba.size(), rgba)
	var bout := rd.storage_buffer_create(rgba.size())
	var sh := _compile(rd, _GLSL_COLOR)
	var pipe := rd.compute_pipeline_create(sh)
	var us := rd.uniform_set_create([_ubuf(0, bin), _ubuf(1, bout)], sh, 0)
	var pc := PackedByteArray()
	pc.resize(16)
	pc.encode_s32(0, w); pc.encode_s32(4, h); pc.encode_float(8, sig_r); pc.encode_float(12, sig_s)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipe)
	rd.compute_list_bind_uniform_set(cl, us, 0)
	rd.compute_list_set_push_constant(cl, pc, pc.size())
	rd.compute_list_dispatch(cl, int(ceil(w / 8.0)), int(ceil(h / 8.0)), 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var out := rd.buffer_get_data(bout)
	for rid in [us, pipe, sh, bin, bout]:
		rd.free_rid(rid)
	rd.free()
	return out

static func _compile(rd: RenderingDevice, src: String) -> RID:
	var s := RDShaderSource.new()
	s.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	s.source_compute = src
	var spirv := rd.shader_compile_spirv_from_source(s)
	if spirv.compile_error_compute != "":
		push_error("WorldSdfBaker compile: " + spirv.compile_error_compute)
	return rd.shader_create_from_spirv(spirv)

static func _ubuf(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u
