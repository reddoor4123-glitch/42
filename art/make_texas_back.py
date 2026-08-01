"""Turn the supplied landscape Texas-flag tile into a portrait domino back.

    python art/make_texas_back.py art/domino_back_texas_source.png art/domino_back_texas.png

The source is the artwork as supplied — a Texas flag rendered on a domino-shaped
card, 1435x607 — kept beside this script so the back can be re-derived after a
tweak. Only domino_back_texas.png is loaded by the game.

The tile paints its back into a ~58x122 rect with draw_texture_rect(..., false),
which stretches and does not preserve aspect, so the art must be authored
portrait at ~1:2.09. A Texas flag is 3:2 landscape and the supplied art is wider
still (2.36:1), so it cannot simply be resized.

What this does instead, in order:
  1. Rotates the flag a quarter turn so the blue hoist sits at the top — a real
     vertical hang, with the actual flag geometry preserved rather than
     rearranged into invented bands.
  2. Puts the star back upright. The quarter turn would leave it lying on its
     side; rotating a SQUARE patch of the blue field the other way beforehand
     cancels that out, and because the patch is square and the surrounding field
     is uniform texture, nothing else in the image changes.
  3. Trims the excess length by deleting rows from the middle of the red/white
     run. Every row down there is identical, so the join is invisible — and it
     leaves the ivory frame intact at both ends, which cropping the end would
     have cut away.
  4. Resizes to 437x914, matching domino_back_teel.png.
  5. Mutes the colour — see MUTE_SATURATION below.
"""
import sys
import numpy as np
from PIL import Image, ImageEnhance

OUT_W, OUT_H = 437, 914
TARGET_ASPECT = OUT_W / OUT_H

# How far to cool the flag off. The supplied art is vivid, which reads as loud
# against the felt table and beside the photographic Teel back; taking the
# saturation down lands it closer to a flag that has seen some sun, and closer
# to the parchment tone of the card's own frame.
#
# The dial, if this wants retuning — larger is more vivid, 1.0 is untouched:
#   0.82 / 0.96   gentle, barely reads as a change
#   0.68 / 0.92   current: clearly cooled, still unmistakably Texas red
#   0.52 / 0.88   strong, red starts drifting toward mauve
#
# Saturation does the work; the small contrast cut stops the navy going flat
# and heavy once the colour is pulled out of it. Both leave the ivory frame and
# the white stripe essentially alone — they are already near-neutral, so there
# is no saturation in them to remove.
MUTE_SATURATION = 0.68
MUTE_CONTRAST = 0.92


def mute(img):
    """Desaturate and soften, preserving the alpha channel.

    Split and rejoin rather than enhancing the RGBA directly: ImageEnhance
    blends against a greyscale copy, and letting it see the alpha channel makes
    it part of that blend.
    """
    alpha = img.getchannel("A")
    rgb = ImageEnhance.Color(img.convert("RGB")).enhance(MUTE_SATURATION)
    rgb = ImageEnhance.Contrast(rgb).enhance(MUTE_CONTRAST)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def find_star_bbox(rgb, w, h):
    """Bounding box of the ivory star inside the blue hoist field.

    Inset well away from the frame on every side: the frame is ivory too, and
    catching a single pixel of it would blow the bbox out to the whole tile.
    """
    x0, x1 = int(0.05 * w), int(0.30 * w)
    y0, y1 = int(0.10 * h), int(0.90 * h)
    roi = rgb[y0:y1, x0:x1]
    light = (roi[..., 0] > 150) & (roi[..., 1] > 150) & (roi[..., 2] > 150)
    ys, xs = np.nonzero(light)
    if len(xs) == 0:
        raise SystemExit("no star found in the hoist field")
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1)


def uniform_run(rgb, w, top, bottom):
    """The rows between `top` and `bottom` that are safe to delete.

    A row qualifies when it is near-identical to its neighbour, which is true
    everywhere below the blue band: the red and white run straight down to the
    frame without a horizontal feature anywhere.
    """
    prev = rgb[top].astype(np.int16)
    ok = []
    for y in range(top + 1, bottom):
        row = rgb[y].astype(np.int16)
        if np.abs(row - prev).mean() < 6.0:
            ok.append(y)
        prev = row
    return ok


def main(src_path, out_path):
    src = Image.open(src_path).convert("RGBA")
    w, h = src.size
    rgb = np.array(src.convert("RGB"))
    alpha = np.array(src)[..., 3]
    print("source        : %dx%d  aspect %.3f  alpha %d..%d"
          % (w, h, w / h, alpha.min(), alpha.max()))

    # ── 1/2. star upright ────────────────────────────────────────────
    sx0, sy0, sx1, sy1 = find_star_bbox(rgb, w, h)
    print("star bbox     : (%d,%d)-(%d,%d)  %dx%d"
          % (sx0, sy0, sx1, sy1, sx1 - sx0, sy1 - sy0))

    cx, cy = (sx0 + sx1) // 2, (sy0 + sy1) // 2
    side = int(max(sx1 - sx0, sy1 - sy0) * 1.15)
    half = side // 2
    # Keep the patch inside the hoist field so the turn cannot drag frame or
    # white-stripe pixels into the blue.
    half = min(half, cx - int(0.035 * w), cy - int(0.055 * h),
               int(0.31 * w) - cx, h - int(0.055 * h) - cy)
    box = (cx - half, cy - half, cx + half, cy + half)
    print("star patch    : %s  (%dx%d, square=%s)"
          % (str(box), box[2] - box[0], box[3] - box[1],
             (box[2] - box[0]) == (box[3] - box[1])))

    staged = src.copy()
    patch = staged.crop(box).transpose(Image.ROTATE_90)   # CCW, cancels the CW below
    staged.paste(patch, box)

    # ── 1. quarter turn, blue hoist to the top ───────────────────────
    rot = staged.transpose(Image.ROTATE_270)              # 90 deg clockwise
    rw, rh = rot.size
    rot_rgb = np.array(rot.convert("RGB"))
    print("rotated       : %dx%d  aspect %.3f (target %.3f)"
          % (rw, rh, rw / rh, TARGET_ASPECT))

    # Where the blue band ends, measured by how much of each ROW is blue rather
    # than by walking one column. Any single column is unreliable: near the
    # middle it runs through the star, near the edge it runs down the frame —
    # both read as "not blue" inside the band. By row, the band is ~90% blue and
    # everything below it is 0%, with the star never costing more than half.
    # The hoist is a deep navy — blue runs about 60..96, not the >128 an
    # "obviously blue" test would assume. What identifies it is that blue
    # dominates red by a wide margin, not that blue is bright.
    blue_px = (rot_rgb[..., 2] > 40) & (rot_rgb[..., 2].astype(int) > rot_rgb[..., 0].astype(int) + 25)
    blue_rows = np.nonzero(blue_px.mean(axis=1) > 0.4)[0]
    if len(blue_rows) == 0:
        raise SystemExit("no blue band found — refusing to trim blind")
    blue_start, blue_end = int(blue_rows.min()), int(blue_rows.max()) + 1
    print("blue band     : y=%d..%d (%.1f%% of height)"
          % (blue_start, blue_end, 100.0 * (blue_end - blue_start) / rh))
    if not (0.20 < (blue_end - blue_start) / rh < 0.45):
        raise SystemExit("blue band is not about a third of the flag — refusing to trim blind")

    # ── 3. delete rows from the uniform red/white run ────────────────
    want_h = int(round(rw / TARGET_ASPECT))
    drop = rh - want_h
    print("want height   : %d  ->  delete %d rows" % (want_h, drop))

    if drop > 0:
        # Strictly below the blue band, and clear of the frame at the far end.
        # The band's own lower reaches are uniform too and would otherwise
        # qualify — deleting rows there would shorten the hoist instead of the
        # red and white, which is not what was asked for.
        lo = blue_end + int((rh - blue_end) * 0.15)
        hi = rh - int(rh * 0.06)
        candidates = [y for y in uniform_run(rot_rgb, rw, lo, hi) if y > blue_end]
        print("uniform rows  : %d available between y=%d and y=%d"
              % (len(candidates), lo, hi))
        if len(candidates) < drop:
            raise SystemExit("not enough uniform rows to trim seamlessly")
        start_i = (len(candidates) - drop) // 2
        cut = set(candidates[start_i:start_i + drop])
        print("deleting rows : y=%d..%d" % (min(cut), max(cut)))
        keep = [y for y in range(rh) if y not in cut]
        arr = np.array(rot)[keep, :, :]
        rot = Image.fromarray(arr, "RGBA")
        print("after trim    : %dx%d  aspect %.4f"
              % (rot.size[0], rot.size[1], rot.size[0] / rot.size[1]))

    # ── 4/5. final size, then mute ───────────────────────────────────
    out = mute(rot.resize((OUT_W, OUT_H), Image.LANCZOS))
    print("muted         : saturation %.2f, contrast %.2f"
          % (MUTE_SATURATION, MUTE_CONTRAST))
    out.save(out_path, "PNG", optimize=True)
    print("wrote         : %s  %dx%d" % (out_path, OUT_W, OUT_H))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
