"""Analyser for tests/fv_audit.tscn captures.

usage: python tests/fv_audit_report.py <audit dir> [--watch] [--keep] [--workers N]
  <audit dir>: the fv_audit out dir (user://audit globalized), containing tiles.png and raw/
  --watch: analyse captures as fv_audit writes them (raw/<base>.json appears after its .bin frames),
           finish once raw/capture_done exists and everything is analysed
  --keep:  keep the raw .bin frames (default: deleted once analysed)

Per capture (a = normal camera, b = camera distance x (1 + 1e-5), c = normal again, d/e = moved 0.45 px):
  SKY LEAK   (frame s, primary) pure-sentinel background pixels (sky, vista, voxel, backdrop replaced by magenta)
             on non-open-sky tiles, outside the bevel + parallax band. PALE (secondary, the old test):
             sky-coloured pixels (pale blue sky / pale cyan-white cloud) whose z = 0 tile is NOT open sky, static
             (a == c: waterfalls / spray / glints animate), outside the bevel + parallax band along open-sky edges
  FLICKER    |lum(b) - lum(a|c)| > 0.12 on pixels that are stable between a and c (z-fighting)
  SHIMMER    lum(d) (camera moved 0.45 px) outside lum(a)'s 3x3 range by > 0.10, stable a vs c (move flicker)
  BLACK LINE near-black (luma < 0.02) thin runs (<= 4 px @1080p thick, >= 40 px @1080p long, both sides > 0.06)
             over air tiles
Excluded: gameplay glyph tiles (+1 ring), window tiles (+1 ring: terrain windows, enclosed painted sky, world_depth.win), water / waterfall tiles (+2 ring, flicker and
shimmer; sky ignores them within 1 tile), the ball (1.7 tiles), pixels outside the level.
Writes <dir>/<base>.png (dimmed frame; sky leak magenta, flicker yellow, shimmer orange, black line cyan), report.json, report.txt.
"""
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image
from scipy import ndimage

LUM = np.array([0.2126, 0.7152, 0.0722], np.float32)
FLICKER_D = 0.12        # luminance change under the depth-precision change
ANIM_D = 0.04           # a vs c: above this the pixel animates by itself (particles, wind, water)
BLACK_L = 0.02
BLACK_SIDE = 0.06        # both sides of a black line must be brighter than this
CLUSTER_MIN = {"sky": 4.0, "black": 4.0, "flicker": 30.0, "shimmer": 30.0, "pale": 4.0, "zero": 4.0}
                        # per-mille of a tile's area for a tile to count / join a cluster; flicker / shimmer
                        # need >= 3 % of the tile (SSAO / SSR noise stays below; z-fighting is blocky patches)
SHIMMER_M = 0.10       # d (camera moved 0.45 px) outside a's 3x3 luminance range by more than this
BEVEL = 0.16            # sky within this many tiles of a sky-neighbour edge = the block's rounded bevel, not a leak
SKY_MIN_PX = 24         # sky blobs smaller than this (px @1080p) are specks (glints / sparkles), not leaks
BACK_D = 1.0            # air tiles: tiles of depth behind z = 0 through which perspective may see the sky neighbour
CATS = ("sky", "flicker", "shimmer", "black", "pale", "zero")   # zero = pixels exactly (0,0,0) (not drawn)   # sky = sentinel pass; pale = the colour-test metric
COLS = {"black": (0, 1, 1), "shimmer": (1, 0.5, 0), "flicker": (1, 1, 0), "sky": (1, 0, 1)}   # pale is not drawn
SENT_MIN_PX = 6         # sentinel blobs smaller than this (px @1080p) are dropped (single AA pixels)
MAT_BLUE = {4, 5, 9, 15, 17, 18}   # ice, water, glass, cloud, gem, snow: legitimately pale blue materials

_tiles = None


def load_tiles(d):
    global _tiles
    if _tiles is None:
        t = np.array(Image.open(os.path.join(d, "tiles.png")).convert("RGBA"))
        cls = t[:, :, 0].astype(np.int8)
        mat = t[:, :, 1]
        glyph = (t[:, :, 2] & 1) > 0
        window = (t[:, :, 2] & 2) > 0
        # glass panes / frames overhang their opening tiles by up to a tile
        win_fb = ndimage.binary_dilation(window & ~((t[:, :, 2] & 16) > 0), structure=np.ones((3, 3), bool))
        window = ndimage.binary_dilation(window, structure=np.ones((3, 3), bool))
        api_masked = window & ~win_fb   # tiles only the is_window() API masks (report: what it removed)
        painted = (t[:, :, 2] & 8) > 0   # painted-sky air: sky, but world may frame it (window frames are not lines)
        sky = cls == 1
        near_sky = ndimage.binary_dilation(sky, structure=np.ones((3, 3), bool))
        blue_mat = np.isin(mat, list(MAT_BLUE)) | ((t[:, :, 2] & 4) > 0)   # + painted water / waterfalls
        blue_mat = ndimage.binary_dilation(blue_mat, structure=np.ones((3, 3), bool))
        wet = np.isin(mat, [4, 5]) | ((t[:, :, 2] & 4) > 0)
        wet = ndimage.binary_dilation(wet, structure=np.ones((5, 5), bool))   # + the splash / mist ring
        _tiles = dict(cls=cls, mat=mat, glyph=glyph, near_sky=near_sky, blue_mat=blue_mat, sky=sky, window=window, wet=wet, painted=painted, api_masked=api_masked)
    return _tiles


def read_frame(path, w, h, fmt):
    ch = 4 if fmt == 5 else 3
    a = np.fromfile(path, np.uint8)
    return a.reshape(h, w, ch)[:, :, :3].astype(np.float32) / 255.0


def runlen(m, axis):
    """Length of the run of True that each True pixel belongs to, along axis."""
    if axis == 0:
        return runlen(m.T, 1).T
    h, w = m.shape
    p = np.zeros((h, w + 2), np.int8)
    p[:, 1:-1] = m
    f = p.ravel()
    d = np.diff(f)
    starts = np.flatnonzero(d == 1)
    ends = np.flatnonzero(d == -1)
    out = np.zeros(f.size, np.int32)
    lens = ends - starts
    if lens.size:
        idx = np.repeat(lens, lens)
        pos = np.repeat(starts + 1, lens) + (np.arange(lens.sum()) - np.repeat(np.cumsum(lens) - lens, lens))
        out[pos] = idx
    return out.reshape(h, w + 2)[:, 1:-1]


def analyse(d, meta, keep):
    T = load_tiles(d)
    H, W = T["cls"].shape
    iw, ih = meta["img"]
    fmt = int(meta.get("format", 4))
    base = meta["base"]
    raw = os.path.join(d, "raw")
    A = read_frame(os.path.join(raw, base + "_a.bin"), iw, ih, fmt)
    nfr = int(meta.get("frames", 1))
    B = read_frame(os.path.join(raw, base + "_b.bin"), iw, ih, fmt) if nfr >= 3 else None
    C = read_frame(os.path.join(raw, base + "_c.bin"), iw, ih, fmt) if nfr >= 3 else None
    D = read_frame(os.path.join(raw, base + "_d.bin"), iw, ih, fmt) if nfr >= 4 else None
    E = read_frame(os.path.join(raw, base + "_e.bin"), iw, ih, fmt) if nfr >= 5 else None
    s = ih / 1080.0
    x0, y0 = meta["p00"]
    x1, y1 = meta["p11"]
    wx = x0 + (np.arange(iw) + 0.5) / iw * (x1 - x0)
    wy = y0 + (np.arange(ih) + 0.5) / ih * (y1 - y0)
    txs = np.floor(wx).astype(np.int32)
    tys = np.floor(-wy).astype(np.int32)
    inside = ((tys >= 0) & (tys < H))[:, None] & ((txs >= 0) & (txs < W))[None, :]
    tx = np.clip(txs, 0, W - 1)[None, :]
    ty = np.clip(tys, 0, H - 1)[:, None]
    cls = T["cls"][ty, tx]
    glyph = T["glyph"][ty, tx]
    bx, by = meta["ball"]
    ball = ((wx[None, :] - (bx + 0.5)) ** 2 + ((-wy)[:, None] - (by + 0.5)) ** 2) < 1.7 ** 2
    valid = inside & ~glyph & ~ball & ~T["window"][ty, tx]
    px_per_tile = iw / abs(x1 - x0)

    r, g, b = A[..., 0], A[..., 1], A[..., 2]
    sky_col = ((b > 150 / 255) & (b > r + 25 / 255) & (b > g + 5 / 255) & (g > 120 / 255)) | \
              ((np.minimum(np.minimum(r, g), b) > 0.80) & (b > r + 0.02))
    # tolerance at edges shared with open sky: the bevel, plus (air tiles) perspective into the sky neighbour
    sk = T["sky"]
    fx = (wx - np.floor(wx))[None, :]
    fy = ((-wy) - np.floor(-wy))[:, None]
    camx, camy, camz = meta["cam"]
    slx = ((wx - camx) / camz)[None, :]          # + = the ray drifts right with depth
    sly = ((-(wy - camy)) / camz)[:, None]       # + = the ray drifts down (tile y) with depth
    back = np.where(cls == 0, BACK_D, 0.0)
    def nb(dx, dy):
        return sk[np.clip(ty + dy, 0, H - 1), np.clip(tx + dx, 0, W - 1)]
    tol_r = BEVEL + back * np.maximum(slx, 0)
    tol_l = BEVEL + back * np.maximum(-slx, 0)
    tol_d = BEVEL + back * np.maximum(sly, 0)
    tol_u = BEVEL + back * np.maximum(-sly, 0)
    er, el, ed, eu = (1 - fx) < tol_r, fx < tol_l, (1 - fy) < tol_d, fy < tol_u
    edge = (nb(1, 0) & er) | (nb(-1, 0) & el) | (nb(0, 1) & ed) | (nb(0, -1) & eu) | \
        (nb(1, 1) & er & ed) | (nb(-1, 1) & el & ed) | (nb(1, -1) & er & eu) | (nb(-1, -1) & el & eu)
    sky_any = sky_col & valid & (cls != 1) & ~T["blue_mat"][ty, tx]
    sky_leak = sky_any & ~edge
    sky_edge_n = int((sky_any & edge).sum())

    lumA = A @ LUM
    flick = np.zeros_like(sky_leak)
    anim_n = 0
    if B is not None:
        lumB = B @ LUM
        lumC = C @ LUM
        anim = np.abs(lumA - lumC) > ANIM_D
        anim = ndimage.binary_dilation(anim, iterations=2)
        anim_n = int(anim.sum())
        wet = T["wet"][ty, tx]   # animated water / waterfall tiles: never z-fighting evidence
        flick = (np.abs(lumB - lumA) > FLICKER_D) & (np.abs(lumB - lumC) > FLICKER_D) & ~anim & valid & ~wet
        flick = ndimage.binary_opening(flick, structure=np.ones((1, 2), bool)) | \
            ndimage.binary_opening(flick, structure=np.ones((2, 1), bool))   # drop isolated single pixels
        # pale animated overlays (waterfalls, spray, glints) are not sky: drop sky pixels at / near motion
        sky_leak &= ~ndimage.binary_dilation(anim, iterations=max(int(4 * s), 1))

    # isolated pale specks (glints, sparkles, speculars) are not leaks: keep sky blobs of >= SKY_MIN_PX @1080p
    lab, n = ndimage.label(sky_leak, structure=np.ones((3, 3)))
    if n:
        sizes = ndimage.sum(sky_leak, lab, index=np.arange(1, n + 1))
        keep_ids = np.flatnonzero(sizes >= SKY_MIN_PX * s * s) + 1
        sky_leak = np.isin(lab, keep_ids)

    # sentinel pass (frame s: sky / vista / voxel / backdrop replaced by pure magenta): the primary sky metric;
    # the colour test above stays as the secondary "pale" column (it also flags sky-ambient-lit blue-grey stone)
    pale = sky_leak
    S = read_frame(os.path.join(raw, base + "_s.bin"), iw, ih, fmt) if meta.get("sentinel") else None
    if S is not None:
        # pure sentinel only: behind glass it comes out pink (g ~0.4-0.5), a real hole is (1, 0, 1)
        sent = (S[..., 0] > 0.8) & (S[..., 2] > 0.8) & (S[..., 1] < 0.2)
        sky_leak = sent & valid & (cls != 1) & ~edge & ~T["blue_mat"][ty, tx]
        lab, n = ndimage.label(sky_leak, structure=np.ones((3, 3)))
        if n:
            sizes = ndimage.sum(sky_leak, lab, index=np.arange(1, n + 1))
            sky_leak = np.isin(lab, np.flatnonzero(sizes >= SENT_MIN_PX * s * s) + 1)
        sky_edge_n = int((sent & valid & (cls != 1) & edge).sum())

    shim = np.zeros_like(sky_leak)
    if D is not None:
        lumD = D @ LUM
        lo = ndimage.minimum_filter(np.minimum(lumA, lumC), size=3)
        hi = ndimage.maximum_filter(np.maximum(lumA, lumC), size=3)
        shim = ((lumD < lo - SHIMMER_M) | (lumD > hi + SHIMMER_M)) & ~anim & valid & ~wet
        if E is not None:
            lumE = E @ LUM
            shim &= (np.abs(lumE - lumD) < ANIM_D)   # static in the moved camera too (not a passing particle)
        shim = ndimage.binary_opening(shim, structure=np.ones((1, 2), bool)) | \
            ndimage.binary_opening(shim, structure=np.ones((2, 1), bool))

    dark = lumA < BLACK_L
    hr = runlen(dark, 1)
    vr = runlen(dark, 0)
    thin = max(int(round(4 * s)), 1)
    long_ = int(round(40 * s))
    # a line, not a dark area: both sides (thin + 2 px across the run) clearly brighter
    k = thin + 2
    def side_min(dy, dx):
        a1 = np.roll(lumA, (dy, dx), (0, 1))
        a2 = np.roll(lumA, (-dy, -dx), (0, 1))
        return np.minimum(a1, a2)
    hline = (hr >= long_) & (vr <= thin) & (side_min(k, 0) > BLACK_SIDE)
    vline = (vr >= long_) & (hr <= thin) & (side_min(0, k) > BLACK_SIDE)
    black = dark & (hline | vline) & valid
    black_air = black & (cls != 2) & ~T["painted"][ty, tx]
    # what the is_window() mask removed: the same tests on the API-only window tiles
    apim = T["api_masked"][ty, tx] & inside & ~glyph & ~ball
    black_api_n = int((dark & (hline | vline) & apim & (cls != 2) & ~T["painted"][ty, tx]).sum())
    sky_api_n = int((sent & apim & (cls != 1) & ~edge & ~T["blue_mat"][ty, tx]).sum()) if S is not None else 0
    black_solid_n = int((black & (cls == 2)).sum())

    # per-tile scores (per-mille of a tile's area) + details
    area = px_per_tile * px_per_tile
    tile_idx = (ty * W + tx)
    res = {"base": base, "name": meta["name"], "zoom": meta["zoom"], "tile": meta["tile"], "px_per_tile": px_per_tile,
           "anim_px": anim_n, "black_solid_px": black_solid_n, "sky_edge_px": sky_edge_n,
           "sky_api_px": sky_api_n, "black_api_px": black_api_n}
    zero = (A.max(axis=-1) == 0.0) & valid   # exactly (0,0,0): nothing lit / a guard failed, never intended
    masks = {"sky": sky_leak, "flicker": flick, "shimmer": shim, "black": black_air, "pale": pale, "zero": zero}
    for k, m in masks.items():
        n = int(m.sum())
        res[k + "_px"] = n
        res[k + "_tiles"] = {}
        if n:
            ids = np.broadcast_to(tile_idx, m.shape)[m]
            u, cnt = np.unique(ids, return_counts=True)
            sc = cnt / area * 1000.0
            res[k + "_tiles"] = {int(i): round(float(v), 2) for i, v in zip(u, sc)}
    if sky_leak.any():
        cl = cls[sky_leak]
        res["sky_on_solid"] = int((cl == 2).sum())
        res["sky_on_air"] = int((cl == 0).sum())
        res["sky_edge"] = int(T["near_sky"][ty, tx][sky_leak].sum())

    # marked image (dimmed frame, marks max-pooled when downscaling to <= 1920 wide)
    f = max(1, int(np.ceil(iw / 1920)))
    out = (A * 0.38)
    for k, col in COLS.items():
        m = masks[k]
        if f > 1:
            m = ndimage.maximum_filter(m, size=f)
        out[m] = col
    img = (np.clip(out, 0, 1) * 255).astype(np.uint8)
    if f > 1:
        img = img[::f, ::f]
    Image.fromarray(img).save(os.path.join(d, base + ".png"), compress_level=3)
    if not keep:
        for sfx in "abcdes":
            p = os.path.join(raw, "%s_%s.bin" % (base, sfx))
            if os.path.exists(p):
                os.remove(p)
    return res


def clusters(score, W, k, top=40):
    """8-connected clusters of tiles with score >= CLUSTER_MIN (gap of 1 tile bridged)."""
    m = score >= CLUSTER_MIN[k]
    if not m.any():
        return []
    lab, n = ndimage.label(ndimage.binary_dilation(m, structure=np.ones((3, 3), bool)), structure=np.ones((3, 3)))
    lab = lab * m
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        if sl is None:
            continue
        sub = (lab[sl] == i)
        sc = score[sl] * sub
        tot = float(sc.sum())
        py, px = np.unravel_index(np.argmax(sc), sc.shape)
        out.append({"x0": sl[1].start, "y0": sl[0].start, "x1": sl[1].stop - 1, "y1": sl[0].stop - 1,
                    "tiles": int(sub.sum()), "score": round(tot, 1),
                    "peak": [int(sl[1].start + px), int(sl[0].start + py)], "peak_score": round(float(sc.max()), 1)})
    out.sort(key=lambda c: -c["score"])
    return out[:top]


def report(d, results):
    T = load_tiles(d)
    H, W = T["cls"].shape
    glob = {k: np.zeros((H, W), np.float32) for k in CATS}
    seen = {k: {} for k in CATS}
    for r in results:
        for k in CATS:
            for i, v in r[k + "_tiles"].items():
                y, x = divmod(int(i), W)
                if v > glob[k][y, x]:
                    glob[k][y, x] = v
                seen[k].setdefault(int(i), []).append((r["base"], v))
    tot = {k + "_px": sum(r[k + "_px"] for r in results) for k in CATS}
    tot["captures"] = len(results)
    tot["black_solid_px"] = sum(r["black_solid_px"] for r in results)
    tot["sky_edge_px"] = sum(r.get("sky_edge_px", 0) for r in results)
    tot["sky_api_px"] = sum(r.get("sky_api_px", 0) for r in results)
    tot["black_api_px"] = sum(r.get("black_api_px", 0) for r in results)
    cl = {}
    for k in CATS:
        cl[k] = clusters(glob[k], W, k)
        for c in cl[k]:
            caps = {}
            for y in range(c["y0"], c["y1"] + 1):
                for x in range(c["x0"], c["x1"] + 1):
                    for b, v in seen[k].get(y * W + x, []):
                        caps[b] = caps.get(b, 0.0) + v
            c["captures"] = [b for b, v in sorted(caps.items(), key=lambda kv: -kv[1])][:8]   # worst first
            c["cls"] = {n: int(((T["cls"][c["y0"]:c["y1"] + 1, c["x0"]:c["x1"] + 1] == v) &
                               (glob[k][c["y0"]:c["y1"] + 1, c["x0"]:c["x1"] + 1] >= CLUSTER_MIN[k])).sum())
                        for n, v in (("air", 0), ("sky", 1), ("solid", 2))}
            if k == "sky":
                c["edge_tiles"] = int((T["near_sky"][c["y0"]:c["y1"] + 1, c["x0"]:c["x1"] + 1] &
                                       (glob[k][c["y0"]:c["y1"] + 1, c["x0"]:c["x1"] + 1] >= CLUSTER_MIN[k])).sum())
        tot[k + "_tiles"] = int((glob[k] >= CLUSTER_MIN[k]).sum())
        for c in cl[k]:
            c["zero_score"] = round(float(glob["zero"][c["y0"]:c["y1"] + 1, c["x0"]:c["x1"] + 1].sum()), 1)
        tot[k + "_clusters"] = len(cl[k])
    results = sorted(results, key=lambda r: -sum(r[k + "_px"] for k in CATS) / r["px_per_tile"] ** 2)
    for r in results:
        r["worst"] = {}
        for k in CATS:
            tl = sorted(r[k + "_tiles"].items(), key=lambda kv: -kv[1])[:5]
            r["worst"][k] = [[int(i) % W, int(i) // W, v] for i, v in tl]
    slim = [{k: v for k, v in r.items() if not k.endswith("_tiles")} for r in results]
    # per-capture tile scores ("x,y": per-mille), for "which capture sees this cluster" breakdowns
    per = {r["base"]: {k: {"%d,%d" % (int(i) % W, int(i) // W): v for i, v in r[k + "_tiles"].items()} for k in CATS}
           for r in results}
    json.dump(per, open(os.path.join(d, "capture_tiles.json"), "w"))
    json.dump({"totals": tot, "clusters": cl, "captures": slim}, open(os.path.join(d, "report.json"), "w"), indent=1)
    np.save(os.path.join(d, "heat.npy"), np.stack([glob[k] for k in CATS]))
    heat = np.zeros((H, W, 3), np.float32)
    heat[..., :] = np.where(T["cls"] == 2, 0.25, np.where(T["cls"] == 1, 0.08, 0.14))[..., None]
    for k, col in COLS.items():
        v = np.clip(glob[k] / 40.0, 0, 1)[..., None]
        heat = heat * (1 - v) + np.array(col, np.float32) * v
    Image.fromarray((heat * 255).astype(np.uint8)).resize((W * 4, H * 4), Image.NEAREST).save(os.path.join(d, "heatmap.png"))

    L = ["FV AUDIT  %d captures   %s" % (len(results), time.strftime("%Y-%m-%d %H:%M"))]
    L.append("TOTALS  sky leak %(sky_px)d px on %(sky_tiles)d tiles (%(sky_clusters)d clusters) | flicker %(flicker_px)d px on "
             "%(flicker_tiles)d tiles (%(flicker_clusters)d) | shimmer %(shimmer_px)d px on %(shimmer_tiles)d tiles "
             "(%(shimmer_clusters)d) | black lines %(black_px)d px on %(black_tiles)d tiles (%(black_clusters)d)" % tot)
    L.append("  removed by the world_depth.is_window() mask alone: sky %(sky_api_px)d px, black lines %(black_api_px)d px" % tot)
    L.append("  exact (0,0,0) pixels %(zero_px)d on %(zero_tiles)d tiles" % tot)
    L.append("  secondary: pale-colour sky test %(pale_px)d px on %(pale_tiles)d tiles (the pre-sentinel metric)" % tot)
    L.append("  (not counted: sky at sky-edges within bevel/parallax tolerance %(sky_edge_px)d px, black lines over "
             "solids %(black_solid_px)d px)" % tot)
    L.append("score = per-mille of a tile's area flagged (max over captures); tiles join clusters at %s" % CLUSTER_MIN)
    for k in CATS:
        L.append("")
        L.append("== %s clusters (worst first) ==" % k.upper())
        for c in cl[k][:25]:
            extra = (" edge-of-sky tiles %d" % c["edge_tiles"]) if k == "sky" else ""
            L.append("  tiles (%d,%d)-(%d,%d) n=%d score %.0f peak (%d,%d) %.0f  on %s%s  seen in %s" % (
                c["x0"], c["y0"], c["x1"], c["y1"], c["tiles"], c["score"], c["peak"][0], c["peak"][1], c["peak_score"],
                c["cls"], extra, ",".join(c["captures"][:4])))
    L.append("")
    L.append("== captures (worst first; px normalised by tile area) ==")
    for r in results[:60]:
        L.append("  %-16s sky %6d  flicker %6d  shimmer %6d  black %5d  (anim %d)  worst sky %s flick %s shim %s black %s" % (
            r["base"], r["sky_px"], r["flicker_px"], r["shimmer_px"], r["black_px"], r["anim_px"],
            r["worst"]["sky"][:2], r["worst"]["flicker"][:2], r["worst"]["shimmer"][:2], r["worst"]["black"][:2]))
    open(os.path.join(d, "report.txt"), "w", encoding="utf-8").write("\n".join(L) + "\n")
    return L


def main():
    d = sys.argv[1]
    watch = "--watch" in sys.argv
    keep = "--keep" in sys.argv
    nw = 6
    if "--workers" in sys.argv:
        nw = int(sys.argv[sys.argv.index("--workers") + 1])
    raw = os.path.join(d, "raw")
    log = open(os.path.join(d, "analyser.log"), "w")
    if watch:
        for fn in os.listdir(d):
            if fn.endswith(".png") and fn not in ("tiles.png", "heatmap.png"):
                os.remove(os.path.join(d, fn))
    done, futs, results = set(), {}, []
    t0 = time.time()
    with ProcessPoolExecutor(nw) as ex:
        while True:
            finished = os.path.exists(os.path.join(raw, "capture_done")) or not watch
            for fn in sorted(os.listdir(raw)):
                if fn.endswith(".json") and fn not in done:
                    done.add(fn)
                    meta = json.load(open(os.path.join(raw, fn)))
                    futs[ex.submit(analyse, d, meta, keep)] = fn
            for fu in [f for f in futs if f.done()]:
                fn = futs.pop(fu)
                try:
                    r = fu.result()
                    results.append(r)
                    log.write("%s sky %d flicker %d black %d\n" % (fn, r["sky_px"], r["flicker_px"], r["black_px"]))
                except Exception as e:  # keep going: one bad capture must not kill the audit
                    log.write("%s FAILED %r\n" % (fn, e))
                log.flush()
            if finished and not futs:
                # a capture json may have landed between the listing and the done check: list once more
                if all(fn in done for fn in os.listdir(raw) if fn.endswith(".json")):
                    break
            time.sleep(0.2)
    L = report(d, results)
    log.write("report in %.1f s\n" % (time.time() - t0))
    log.close()
    print("\n".join(L[:40]))


if __name__ == "__main__":
    main()
