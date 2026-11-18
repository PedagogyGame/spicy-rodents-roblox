"""THE GILDED ACORN's hero pieces, modelled procedurally in Blender: one FBX in studs and the manifest the loader reads.

  /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/lounge_classic/model.py [--out build/art/lounge_classic]

The brief asks for "an elaborate Blender interior, leather and woodwork, fancy counters". The lounge is baked
from plain parts (tools/bake/lounge_classic), which stay: they carry the collision, the lamps and the lettering,
and they are what the game shows until these meshes are uploaded. This makes the pieces where the eye rests,
finer than parts can be:
  * the bar: a mahogany body with four reeded pilasters and three diamond-tufted leather panels between
    moulded frames, a walnut top with a rounded (bullnose) edge, a leather arm roll, a brass foot rail on five
    brackets with ball ends, brass edge strips;
  * the four booths: channel-tufted leather backs (rolled flutes), cushioned seats, walnut plinths, rounded caps
    and a walnut table each;
  * the side and back walls' wainscot: raised and fielded walnut panels in moulded frames, a profiled chair rail
    and a stepped crown moulding.
One mesh per material (a MeshPart has one colour): Bar_Mahogany, Bar_Walnut, Bar_Leather, Bar_Brass,
Booth<i>_Leather, Booth<i>_Walnut, Wall_Panels, Wall_Mouldings. Triangle budget BUDGET (phones first).
Frames. Every piece is built in the venue's own frame (Shared/Attractions/AlleyLayout: X across, Y up from the
floor, D into the building), in studs, with the same dimensions as tools/bake/lounge_classic/Style (a spec holds
each piece inside the baked parts it replaces). The vertices are written in Blender as (-X, -D, Y); the FBX
export (axis_forward Z, axis_up Y, 1 unit = 1 stud: HANDOFF rule 9) gives Roblox (X, Y, -D): the venue frame at
yaw 0, so each MeshPart arrives unrotated, centred on its own bounding box. The manifest gives each piece's
centre in the venue frame (X, Y, D); the loader (Server/Assets/LoungeArt) puts it there and hides the baked parts
it replaces (`replaces`, by name), keeping their collision.
Outputs in --out: lounge.fbx, manifest.json ({ format, scale, total, budget, pieces: [{ name, material,
robloxMaterial, colour, tris, centre, size }], replaces: [part names] }).
"""
import argparse
import json
import math
import os

import bpy  # noqa: I001 (bpy first: it provides bmesh and mathutils)
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
BUDGET = 20000  # triangles, every piece together

# tools/bake/lounge_classic/Style (studs; the venue frame)
INNER_X = 24.0
INNER_BACK = 27.0
FRONT_IN = -27.0  # the front wall's inner face
WAINSCOT = 4.0
CROWN = 12.2
CEILING = 13.0
BAR_X, BAR_D0, BAR_D1, BAR_TOP = 12.0, 15.0, 17.0, 3.35
BOOTHS = [(-18, -10), (18, -10), (-18, 4), (18, 4)]
BOOTH_X0, BOOTH_X1 = 13.2, 23.75
PILASTERS_D = [-24, -17, -3, 11, 24]  # walnut pilasters on the side walls (the east one at 24 is left out)
STAGE_D0 = 14.0  # the stage stands against the west wall from here back
FIRE_D = 20.0  # the fireplace on the east wall (D 16.6 .. 23.4)
BACKBAR_X = 11.2  # the back bar's half width against the back wall

COLOURS = {  # sRGB 0-255, the bake's palette
    "mahogany": [104, 44, 34],
    "walnut": [86, 54, 36],
    "leather": [110, 36, 32],
    "brass": [190, 152, 78],
}
ROBLOX_MATERIAL = {"mahogany": "Wood", "walnut": "Wood", "leather": "Leather", "brass": "Metal"}


def r4(v):
    return round(v + 0.0, 4)


class Piece:
    """One mesh being built in the venue frame (X, Y, D)."""

    def __init__(self, name, material):
        self.name = name
        self.material = material
        self.bm = bmesh.new()

    def _place(self, geom_verts, m):
        bmesh.ops.transform(self.bm, matrix=m, verts=geom_verts)

    def box(self, x0, x1, y0, y1, d0, d1, bevel=0.0, segments=2):
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = r["verts"]
        m = Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (d0 + d1) / 2)) @ Matrix.Diagonal(
            (abs(x1 - x0), abs(y1 - y0), abs(d1 - d0), 1.0)
        )
        self._place(verts, m)
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=segments, profile=0.5, affect="EDGES",
                            clamp_overlap=True)
        return verts

    def cyl(self, centre, axis, length, radius, segments=12, squash=1.0):
        """A closed cylinder along 'X', 'Y' or 'D'; squash flattens it across (a roll pressed against a wall)."""
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                                  radius2=radius, depth=length)
        # create_cone stands along z: turn z onto the axis
        if axis == "X":
            rot = Matrix.Rotation(math.pi / 2, 4, "Y")
        elif axis == "Y":
            rot = Matrix.Rotation(-math.pi / 2, 4, "X")
        else:
            rot = Matrix.Identity(4)
        sq = Matrix.Diagonal((1.0, 1.0, 1.0, 1.0))
        if squash != 1.0:
            # flatten across D (the wall side) for X or Y rolls
            sq = Matrix.Diagonal((1.0, 1.0, squash, 1.0)) if axis != "D" else Matrix.Diagonal((1.0, squash, 1.0, 1.0))
        self._place(r["verts"], Matrix.Translation(centre) @ sq @ rot)
        return r["verts"]

    def ball(self, centre, radius, segments=8):
        r = bmesh.ops.create_uvsphere(self.bm, u_segments=segments, v_segments=max(4, segments // 2), radius=radius)
        self._place(r["verts"], Matrix.Translation(centre))

    def tufted(self, x0, x1, y0, y1, d, depth, cols, rows, dent=0.05, facing=-1):
        """A buttoned (diamond-tufted) leather panel facing -D (facing=-1) or +D: a grid whose button points are
        pressed in by `dent`, the cushion between them standing proud."""
        verts = []
        nx, ny = cols * 2, rows * 2
        for j in range(ny + 1):
            row = []
            for i in range(nx + 1):
                x = x0 + (x1 - x0) * i / nx
                y = y0 + (y1 - y0) * j / ny
                button = (i % 2 == 1) == (j % 2 == 1) and 0 < i < nx and 0 < j < ny
                edge = i in (0, nx) or j in (0, ny)
                proud = 0.0 if edge else (-dent if button else depth * 0.5)
                row.append(self.bm.verts.new((x, y, d + facing * (depth * 0.5 + proud))))
            verts.append(row)
        for j in range(ny):
            for i in range(nx):
                q = [verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]]
                self.bm.faces.new(q if facing < 0 else list(reversed(q)))

    def finish(self):
        """-> a Blender object: the venue frame mapped to Blender (-X, -D, Y), its origin at its bounds' centre."""
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        # venue (X, Y, D) -> Blender (-X, -D, Y): a reflection, so the faces are turned back afterwards
        m = Matrix(((-1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        lo, hi = Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))
        c = (lo + hi) / 2
        me.transform(Matrix.Translation(-c))
        mat = bpy.data.materials.get(self.material) or bpy.data.materials.new(self.material)
        col = COLOURS[self.material]
        mat.diffuse_color = [((v / 255) ** 2.2) for v in col] + [1.0]
        me.materials.append(mat)
        ob = bpy.data.objects.new(self.name, me)
        ob.location = c
        bpy.context.scene.collection.objects.link(ob)
        size = hi - lo
        return ob, {
            "name": self.name,
            "material": self.material,
            "robloxMaterial": ROBLOX_MATERIAL[self.material],
            "colour": col,
            "tris": len(me.polygons),
            # back in the venue frame: Blender (bx, by, bz) = (-X, -D, Y)
            "centre": [r4(-c.x), r4(c.z), r4(-c.y)],
            "size": [r4(size.x), r4(size.z), r4(size.y)],
        }


def bar():
    X, D0, D1, top = BAR_X, BAR_D0, BAR_D1, BAR_TOP
    wood = Piece("Bar_Mahogany", "mahogany")
    wood.box(-X, X, 0.0, 0.5, D0 + 0.3, D1, bevel=0.03)  # the kick
    wood.box(-X, X, 0.5, top - 0.35, D0 + 0.12, D1, bevel=0.02)  # the body
    # four reeded pilasters: five half-round reeds each, between a plinth block and a capital
    for px in (-X, -X / 3, X / 3, X):
        w = 1.2
        wood.box(px - w / 2, px + w / 2, 0.5, 0.9, D0 - 0.05, D0 + 0.2, bevel=0.03)
        wood.box(px - w / 2 - 0.05, px + w / 2 + 0.05, top - 0.7, top - 0.4, D0 - 0.08, D0 + 0.2, bevel=0.04)
        for k in range(5):
            rx = px - w / 2 + w * (k + 0.5) / 5
            wood.cyl(Vector((rx, (0.9 + top - 0.7) / 2, D0 + 0.05)), "Y", top - 1.6, 0.11, segments=8)
    # moulded frames round the three leather panels
    for cx in (-X / 1.5, 0.0, X / 1.5):
        x0, x1, y0, y1 = cx - 3.2, cx + 3.2, 0.8, top - 0.65
        for (a, b, c, d) in ((x0, x1, y0, y0 + 0.14), (x0, x1, y1 - 0.14, y1), (x0, x0 + 0.14, y0, y1),
                             (x1 - 0.14, x1, y0, y1)):
            wood.box(a, b, c, d, D0 - 0.06, D0 + 0.12, bevel=0.03)
    walnut = Piece("Bar_Walnut", "walnut")
    walnut.box(-X - 0.5, X + 0.5, top - 0.35, top, D0 - 0.5, D1 + 0.6, bevel=0.14, segments=4)
    leather = Piece("Bar_Leather", "leather")
    leather.cyl(Vector((0, top + 0.12, D0 - 0.3)), "X", 2 * X + 0.8, 0.19, segments=14)
    for cx in (-X / 1.5, 0.0, X / 1.5):
        leather.tufted(cx - 3.06, cx + 3.06, 0.94, top - 0.79, D0 + 0.02, 0.14, cols=6, rows=3)
    brass = Piece("Bar_Brass", "brass")
    brass.cyl(Vector((0, 0.7, D0 - 0.8)), "X", 2 * X, 0.13, segments=14)
    for sx in (-1, 1):
        brass.ball(Vector((sx * X, 0.7, D0 - 0.8)), 0.2, segments=10)
    for bx in (-X + 1, -X / 2, 0.0, X / 2, X - 1):
        brass.cyl(Vector((bx, 0.7, D0 - 0.4)), "D", 0.8, 0.06, segments=8)
        brass.box(bx - 0.18, bx + 0.18, 0.5, 0.9, D0 - 0.04, D0 + 0.01, bevel=0.02)
    brass.box(-X - 0.5, X + 0.5, top - 0.42, top - 0.35, D0 - 0.52, D0 - 0.45)  # the edge strip under the top
    return [wood, walnut, leather, brass]


def booths():
    out = []
    for i, (bx, c) in enumerate(BOOTHS, start=1):
        s = -1 if bx < 0 else 1
        x0, x1 = sorted((s * BOOTH_X0, s * BOOTH_X1))
        leather = Piece(f"Booth{i}_Leather", "leather")
        walnut = Piece(f"Booth{i}_Walnut", "walnut")
        for side in (-1, 1):
            d0, d1 = sorted((c + side * 2.4, c + side * 4))
            back0, back1 = sorted((c + side * 3.4, c + side * 4))
            walnut.box(x0, x1, 0.0, 0.9, d0, d1, bevel=0.04)
            leather.box(x0 + 0.05, x1 - 0.05, 0.9, 1.7, d0 + 0.05, d1 - 0.05, bevel=0.18, segments=3)
            # the back: rolled flutes (channel tufting), facing the table
            n = 8
            span = (x1 - x0 - 0.2) / n
            mid = (back0 + back1) / 2
            for k in range(n):
                fx = x0 + 0.1 + span * (k + 0.5)
                leather.cyl(Vector((fx, 3.15, mid)), "Y", 2.9, span / 2, segments=10, squash=0.5)
            walnut.box(x0, x1, 4.6, 4.85, back0 - 0.1, back1 + 0.1, bevel=0.1, segments=3)
        walnut.box(min(s * (BOOTH_X0 + 1.4), x1), max(s * (BOOTH_X0 + 1.4), x1), 2.6, 2.85, c - 1.5, c + 1.5,
                   bevel=0.08, segments=3)
        out += [leather, walnut]
    return out


def walls():
    panels = Piece("Wall_Panels", "walnut")
    mould = Piece("Wall_Mouldings", "mahogany")

    def run(axis, face, n, a, b):
        """Raised and fielded panels on one stretch of wall (inner face at `face`, the room toward n), from a to b."""
        width = b - a
        count = max(1, round(width / 2.4))
        w = width / count
        for k in range(count):
            p0, p1 = a + k * w + 0.12, a + (k + 1) * w - 0.12
            for (u0, u1, y0, y1, t) in ((p0, p1, 0.35, 3.75, 0.08),):
                f0, f1 = face, face + n * t
                lo, hi = sorted((f0, f1))
                # the frame (stiles and rails) and the raised field
                for (q0, q1, z0, z1) in ((u0, u1, y0, y0 + 0.16), (u0, u1, y1 - 0.16, y1), (u0, u0 + 0.16, y0, y1),
                                         (u1 - 0.16, u1, y0, y1)):
                    if axis == "D":
                        panels.box(lo, hi, z0, z1, q0, q1)
                    else:
                        panels.box(q0, q1, z0, z1, lo, hi)
                g0, g1 = sorted((face, face + n * (t + 0.06)))
                if axis == "D":
                    panels.box(g0, g1, y0 + 0.3, y1 - 0.3, u0 + 0.3, u1 - 0.3, bevel=0.06, segments=1)
                else:
                    panels.box(u0 + 0.3, u1 - 0.3, y0 + 0.3, y1 - 0.3, g0, g1, bevel=0.06, segments=1)
        # the chair rail (a rounded nose on a flat) and the stepped crown
        lo, hi = sorted((face, face + n * 0.3))
        clo, chi = sorted((face, face + n * 0.45))
        if axis == "D":
            mould.box(lo, hi, WAINSCOT, WAINSCOT + 0.3, a, b)
            mould.cyl(Vector((face + n * 0.3, WAINSCOT + 0.15, (a + b) / 2)), "D", b - a, 0.1, segments=6)
            for k, (y0, y1, dd) in enumerate(((CROWN, CROWN + 0.25, 0.2), (CROWN + 0.25, CROWN + 0.5, 0.32),
                                              (CROWN + 0.5, CEILING, 0.45))):
                q0, q1 = sorted((face, face + n * dd))
                mould.box(q0, q1, y0, y1, a, b, bevel=0.03 if k == 1 else 0.0, segments=1)
        else:
            mould.box(a, b, WAINSCOT, WAINSCOT + 0.3, lo, hi)
            mould.cyl(Vector(((a + b) / 2, WAINSCOT + 0.15, face + n * 0.3)), "X", b - a, 0.1, segments=6)
            for k, (y0, y1, dd) in enumerate(((CROWN, CROWN + 0.25, 0.2), (CROWN + 0.25, CROWN + 0.5, 0.32),
                                              (CROWN + 0.5, CEILING, 0.45))):
                q0, q1 = sorted((face, face + n * dd))
                mould.box(a, b, y0, y1, q0, q1, bevel=0.03 if k == 1 else 0.0, segments=1)
        del clo, chi

    # the side walls in bays between the pilasters, leaving out the booths' ends (their backs stand there),
    # the stage (west, from STAGE_D0 back) and the fireplace (east); the back wall either side of the back bar
    def bays(d_from, d_to, skip):
        cuts = sorted(set([d_from, d_to] + [p for p in PILASTERS_D if d_from < p < d_to]))
        out = []
        for a, b in zip(cuts[:-1], cuts[1:]):
            a1, b1 = (a + 0.35 if a in PILASTERS_D else a), (b - 0.35 if b in PILASTERS_D else b)
            for (s0, s1) in skip:
                if a1 < s1 and b1 > s0:
                    if a1 < s0:
                        out.append((a1, s0))
                    a1 = max(a1, s1)
            if b1 - a1 > 1.0:
                out.append((a1, b1))
        return out

    booth_spans = [(c - 4.1, c + 4.1) for _, c in BOOTHS[:2]] + [(c - 4.1, c + 4.1) for _, c in BOOTHS[2:]]
    for a, b in bays(FRONT_IN, STAGE_D0, booth_spans):
        run("D", -INNER_X, 1, a, b)
    for a, b in bays(FRONT_IN, INNER_BACK, booth_spans + [(FIRE_D - 3.5, FIRE_D + 3.5)]):
        run("D", INNER_X, -1, a, b)
    run("X", INNER_BACK, -1, BACKBAR_X + 0.2, INNER_X)
    run("X", INNER_BACK, -1, -INNER_X + 10.0, -BACKBAR_X - 0.2)  # (the stage's drape covers X -24 .. -14)
    return [panels, mould]


# the baked parts the meshes stand in for (tools/bake/lounge_classic/Interior): made invisible by the loader,
# their collision kept
def replaced():
    names = ["BarKick", "BarFront", "BarTop", "ArmRoll", "FootRail"]
    names += [f"BarStrip{x}" for x in ("-12", "-4", "4", "12")]
    names += [f"BarPanel{x}" for x in ("-8", "0", "8")]
    names += [f"RailBracket{x}" for x in ("-11", "-6", "0", "6", "11")]
    for i in range(1, 5):
        for side in ("-1", "1"):
            names += [f"Booth{i}Plinth{side}", f"Booth{i}Seat{side}", f"Booth{i}Back{side}", f"Booth{i}Cap{side}"]
        names.append(f"Booth{i}Table")
    for wall in ("West", "East", "Back"):
        names += [f"{wall}Panel", f"{wall}Rail", f"{wall}Crown"]
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "art", "lounge_classic"))
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects, pieces = [], []
    for p in bar() + booths() + walls():
        ob, rec = p.finish()
        objects.append(ob)
        pieces.append(rec)
    total = sum(p["tris"] for p in pieces)
    for p in pieces:
        print(f"  {p['name']:16s} {p['tris']:6d} tris  centre {p['centre']}  size {p['size']}", flush=True)
    assert total <= BUDGET, f"{total} triangles, budget {BUDGET}"
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    fbx = os.path.join(out, "lounge.fbx")
    bpy.ops.export_scene.fbx(
        filepath=fbx,
        use_selection=True,
        object_types={"MESH"},
        axis_forward="Z",
        axis_up="Y",
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        mesh_smooth_type="FACE",
        use_mesh_modifiers=False,
        use_tspace=False,
        path_mode="COPY",
        embed_textures=False,
    )
    manifest = {
        "format": "lounge_classic art v1",
        "fbx": "lounge.fbx",
        "scale": 1,
        "budget": BUDGET,
        "total": total,
        "pieces": pieces,
        "replaces": replaced(),
    }
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
        fh.write("\n")
    print(f"LOUNGE_ART {len(pieces)} pieces, {total} triangles (budget {BUDGET}); {os.path.getsize(fbx)} bytes",
          flush=True)


main()
