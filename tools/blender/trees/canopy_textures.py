"""Leaf-spray atlases for canopy.py (numpy only). Species done: oak, elm.

One atlas per species, 1024 x 1024 RGBA (sRGB, straight alpha), 2 x 2 cells; each cell holds one
spray (a twig with side twigs and their leaves: lobed for the oak, serrated for the elm, each leaf
with its midrib and veins, tone varying from leaf to leaf) whose twig rises from the middle of the
cell's lower edge. The painter is textures.py's spray painter (same folder); here the alpha is
made crisp for Roblox (the Leaves parts are drawn double-sided with the alpha as transparency, and
soft half-transparent areas sort badly): alpha is 0 or 1 except for a one-texel edge.

    rgba = spray_atlas("oak", palette, layer="sun")          # (1024, 1024, 4) float 0..1, row 0 = top
    paths = write_atlases(out_dir, "oak", palette)           # {"LeavesShade": png, "LeavesMid": png, "LeavesSun": png}

The three layers share one layout (the same UVs) and differ only in colour.
CLI: python -I tools/blender/trees/canopy_textures.py --out build/art/trees/canopy_tex
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import textures as tx  # noqa: E402

SPECIES = ("oak", "elm")
SHAPE = {"oak": "oak", "elm": "elm"}
SEED = {"oak": 31, "elm": 32}
PALETTE = {"oak": ["#44763b", "#6d984d", "#547e42", "#8ba75b"], "elm": ["#5a9243", "#73a85c", "#507b3c", "#92ac5f"]}
LAYER_OF = {"LeavesShade": "shade", "LeavesMid": "mid", "LeavesSun": "sun"}
_layouts = {}


def layout(species):
    if species not in _layouts:
        _layouts[species] = tx.spray_layout(SHAPE[species], seed=SEED[species])
    return _layouts[species]


def spray_atlas(species, palette=None, layer="mid"):
    """RGBA atlas for one light layer ("shade" | "mid" | "sun") in the tree's palette (hex strings)."""
    rgba = tx.spray_colour(layout(species), palette or PALETTE[species], layer)
    rgba[..., 3] = np.clip((rgba[..., 3] - 0.5) * 4.0 + 0.5, 0.0, 1.0)  # crisp edges
    return rgba


def write_atlases(out_dir, species, palette=None):
    paths = {}
    for part, layer in LAYER_OF.items():
        p = os.path.join(out_dir, f"canopy_{species}_{layer}.png")
        if not os.path.exists(p):
            tx.write_png(p, spray_atlas(species, palette, layer))
        paths[part] = p
    return paths


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/art/trees/canopy_tex")
    a = ap.parse_args()
    for sp in SPECIES:
        print(sp, write_atlases(a.out, sp))
