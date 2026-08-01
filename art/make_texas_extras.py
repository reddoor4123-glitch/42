"""Generate the three cream-field domino backs: Texas Map, Texas Outline, Cream.

    python art/make_texas_extras.py

Same portrait constraint as make_texas_back.py — the tile stretches its back
texture into a ~58x122 rect with no aspect correction, so everything is authored
at 437x914 to match domino_back_teel.png.

The cream field is not a flat colour. It is real paper grain lifted from the
white stripe of domino_back_texas_source.png and mirror-tiled, so these sit
beside the flag back as the same material rather than as flat vector art next to
a photograph. Same reason the mute settings are imported from make_texas_back
rather than re-chosen here: one dial for the whole Texas set.

The silhouettes are MULTIPLIED onto that field rather than keyed onto it. Both
sources are artwork on a white background, and keying would mean deciding which
white is background and which is the flag's own white stripe — a flood fill that
has to be told how much anti-aliased edge to eat, and leaves a pale halo when it
guesses wrong. Multiply needs no decision: white becomes the field exactly,
black stays black, every anti-aliased pixel in between lands where it should,
and the paper grain reads through the colours as if printed on the stock.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# Run from the repo root (the art paths below are repo-relative) while importing
# a sibling in art/ — so the script's own directory has to go on the path
# explicitly. Without this the documented invocation needs a PYTHONPATH set.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_texas_back import OUT_W, OUT_H, mute  # noqa: E402

FLAG_SOURCE = "art/domino_back_texas_source.png"
MAP_SOURCE = "art/texas_map_source.png"
OUTLINE_SOURCE = "art/texas_outline_source.png"

# Where the flag's white stripe sits in the source art, as fractions of its
# size. A large clean rectangle of nothing but paper.
STRIPE_BOX = (0.40, 0.10, 0.95, 0.42)

# How much of the tile's width the silhouette spans. Wide enough to be the
# subject rather than a motif floating in space, with enough margin that it
# never touches the tile's own border.
SILHOUETTE_WIDTH = 0.88


def paper_field(w, h):
    """A w x h field of the flag art's own paper grain, seamlessly tiled.

    Mirror-tiled rather than repeat-tiled: a 2x2 block of the patch and its
    flips matches itself on every edge by construction, so the field has no
    seams to hide and the grain keeps its original scale instead of being
    stretched to fit.
    """
    src = Image.open(FLAG_SOURCE).convert("RGB")
    sw, sh = src.size
    patch = src.crop((int(STRIPE_BOX[0] * sw), int(STRIPE_BOX[1] * sh),
                      int(STRIPE_BOX[2] * sw), int(STRIPE_BOX[3] * sh)))
    pw, ph = patch.size
    block = Image.new("RGB", (pw * 2, ph * 2))
    block.paste(patch, (0, 0))
    block.paste(patch.transpose(Image.FLIP_LEFT_RIGHT), (pw, 0))
    block.paste(patch.transpose(Image.FLIP_TOP_BOTTOM), (0, ph))
    block.paste(patch.transpose(Image.ROTATE_180), (pw, ph))
    field = Image.new("RGB", (w, h))
    for y in range(0, h, ph * 2):
        for x in range(0, w, pw * 2):
            field.paste(block, (x, y))
    return field


def trimmed(path):
    """The artwork cropped to its content, ignoring the white page around it.

    Thresholded at 200 rather than at "not pure white": both screenshots carry a
    faint grey cast down one edge, and a near-white test drags the bounding box
    out to the full page.
    """
    im = Image.open(path).convert("RGB")
    a = np.array(im)
    ys, xs = np.nonzero(a.max(axis=2) < 200)
    if len(xs) == 0:
        raise SystemExit("no artwork found in %s" % path)
    return im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


# Thickness, in final-image pixels, of the border traced around the map's
# silhouette. The source already has one, but it is a hairline: the tile renders
# the back at roughly 58px wide, a 6.6x reduction, and a hairline simply
# disappears. Without this the map loses its whole northeast — that part of the
# state is the flag's white stripe, which multiply lands on the cream field at
# almost exactly the field's own value, so the only thing distinguishing state
# from background there is the border.
MAP_BORDER_PX = 5
MAP_BORDER_INK = (46, 52, 64)


def stroke_silhouette(art, thickness, ink):
    """Trace a border around the artwork's outer shape.

    The shape is whatever the white page does NOT reach: found by flooding in
    from all four corners, so the flag's own white stripe stays part of the
    state instead of being read as background. Then the ring is the shape minus
    an eroded copy of itself, which follows the coastline exactly without
    needing to know anything about it.
    """
    w, h = art.size
    flooded = art.copy()
    sentinel = (255, 0, 255)
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(flooded, seed, sentinel, thresh=40)
    is_bg = (np.array(flooded) == np.array(sentinel)).all(axis=-1)

    shape = Image.fromarray(np.where(is_bg, 0, 255).astype(np.uint8), "L")
    # MinFilter erodes; its window must be odd and spans both sides of a pixel,
    # so a `thickness`-wide ring needs a window of 2*thickness+1.
    inner = shape.filter(ImageFilter.MinFilter(2 * thickness + 1))
    ring = np.array(shape).astype(np.int16) - np.array(inner).astype(np.int16)

    out = np.array(art).copy()
    out[ring > 127] = ink
    return Image.fromarray(out, "RGB")


def multiply_onto(field, art, border=0):
    """Print `art` onto `field`, centred, at SILHOUETTE_WIDTH of the tile."""
    w, h = field.size
    target_w = int(w * SILHOUETTE_WIDTH)
    target_h = max(1, round(art.size[1] * target_w / art.size[0]))
    art = art.resize((target_w, target_h), Image.LANCZOS)
    # Stroked after the resize, so the thickness is in the pixels that ship
    # rather than in whatever resolution the source happened to arrive at.
    if border:
        art = stroke_silhouette(art, border, MAP_BORDER_INK)

    # A full-size white sheet with the art placed on it: multiplying by white is
    # the identity, so everywhere outside the art the field is left untouched.
    sheet = Image.new("RGB", (w, h), (255, 255, 255))
    sheet.paste(art, ((w - target_w) // 2, (h - target_h) // 2))

    out = (np.array(field).astype(np.uint16) * np.array(sheet).astype(np.uint16)) // 255
    return Image.fromarray(out.astype(np.uint8), "RGB")


def save(img, path):
    out = mute(img.convert("RGBA"))
    out.save(path, "PNG", optimize=True)
    print("wrote %-44s %dx%d" % (path, out.size[0], out.size[1]))


def main():
    field = paper_field(OUT_W, OUT_H)
    save(field, "art/domino_back_cream.png")
    save(multiply_onto(field, trimmed(MAP_SOURCE), border=MAP_BORDER_PX),
         "art/domino_back_texas_map.png")
    save(multiply_onto(field, trimmed(OUTLINE_SOURCE)), "art/domino_back_texas_outline.png")


if __name__ == "__main__":
    main()
