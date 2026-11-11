"""The owner's review sheets from render_people.py's shots (system python3 with Pillow; the bpy venv has none).

  python3 -I tools/blender/people/sheets.py --dir build/people/renders --out docs/renders/people

Writes 1600-px-wide JPEGs under 400 KB each:
  lineup_front.jpg, lineup_back.jpg   the eight roles mid-stride
  faces.jpg                           calm, worried, frightened
  poses.jpg                           a run and a sit: the joints hold
  scale.jpg                           both builds, turned round, beside a 5.5-stud staff
  hair_hats.jpg                       the eight hair styles and the two hats
"""
import argparse
import io
import json
import os

from PIL import Image, ImageDraw, ImageFont

W = 1600
LIMIT = 390_000


def font(size, bold=False):
    names = ["DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"]
    for d in ("/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/dejavu"):
        for n in names:
            p = os.path.join(d, n)
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def text(dr, xy, s, f, anchor="mm", fill=(255, 255, 255)):
    x, y = xy
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1), (0, 2), (2, 0), (-2, 0), (0, -2)):
        dr.text((x + dx, y + dy), s, font=f, anchor=anchor, fill=(20, 20, 24))
    dr.text((x, y), s, font=f, anchor=anchor, fill=fill)


def load(d, name):
    im = Image.open(os.path.join(d, name + ".png")).convert("RGB")
    with open(os.path.join(d, name + ".json")) as fh:
        meta = json.load(fh)
    return im, meta


def save(im, path):
    if im.width != W:
        im = im.resize((W, round(im.height * W / im.width)), Image.LANCZOS)
    for q in (90, 86, 82, 78, 74, 70, 64, 58):
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=q, optimize=True, progressive=True)
        if buf.tell() <= LIMIT:
            break
    with open(path, "wb") as fh:
        fh.write(buf.getvalue())
    print(f"{path}  {im.width}x{im.height}  q{q}  {buf.tell() // 1024} KB")


def labelled(d, name, size=22, dy=0, where="below", title=None):
    im, meta = load(d, name)
    s = im.width / meta["size"][0]
    dr = ImageDraw.Draw(im)
    f = font(size, bold=True)
    for lab in meta["labels"]:
        x, y = lab["at"][0] * s, lab["at"][1] * s
        if where == "below":
            text(dr, (x, min(y + size + dy, im.height - size * 0.8)), lab["text"], f)
        elif where == "left":
            text(dr, (x, y + dy), lab["text"], f, anchor="rm")
        else:
            text(dr, (x, y + dy), lab["text"], f)
    if title:
        text(dr, (16, 12), title, font(20), anchor="la")
    return im


def hstack(ims):
    h = max(i.height for i in ims)
    out = Image.new("RGB", (sum(i.width for i in ims), h), (30, 30, 34))
    x = 0
    for i in ims:
        out.paste(i, (x, 0))
        x += i.width
    return out


def vstack(ims):
    out = Image.new("RGB", (max(i.width for i in ims), sum(i.height for i in ims)), (30, 30, 34))
    y = 0
    for i in ims:
        out.paste(i, (0, y))
        y += i.height
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/people/renders")
    ap.add_argument("--out", default="docs/renders/people")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    d = a.dir

    def have(*names):
        return all(os.path.exists(os.path.join(d, n + ".png")) for n in names)

    if have("lineup_front"):
        save(labelled(d, "lineup_front", title="Townspeople: the eight roles, mid-stride (front)"), os.path.join(a.out, "lineup_front.jpg"))
    if have("lineup_back"):
        save(labelled(d, "lineup_back", title="The same eight from behind"), os.path.join(a.out, "lineup_back.jpg"))
    if have("face_calm", "face_worried", "face_frightened"):
        save(hstack([labelled(d, "face_" + e, size=26, where="at") for e in ("calm", "worried", "frightened")]), os.path.join(a.out, "faces.jpg"))
    if have("run", "sit"):
        save(hstack([labelled(d, "run", size=20, dy=6), labelled(d, "sit", size=20, dy=6)]), os.path.join(a.out, "poses.jpg"))
    if have("scale"):
        im, meta = load(d, "scale")
        s = im.width / meta["size"][0]
        dr = ImageDraw.Draw(im)
        for lab in meta["labels"]:
            x, y = lab["at"][0] * s, lab["at"][1] * s
            if "build" in lab["text"]:
                text(dr, (x, min(y + 30, im.height - 18)), lab["text"], font(22, True))
            else:
                text(dr, (x, y), lab["text"], font(18, True), anchor="rm")
        text(dr, (16, 12), "Two builds on one rig, beside a 5.5-stud staff", font(20), anchor="la")
        save(im, os.path.join(a.out, "scale.jpg"))
    if have("hair_0", "hair_1"):
        save(vstack([labelled(d, "hair_0", size=16, where="at"), labelled(d, "hair_1", size=16, where="at")]), os.path.join(a.out, "hair_hats.jpg"))


if __name__ == "__main__":
    main()
