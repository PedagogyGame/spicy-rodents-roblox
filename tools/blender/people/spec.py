"""The townspeople's contract: the R15 skeleton, builds, outfits, roles, hair and hats (pure data, no bpy).

Coordinates. Two frames are used and converted with to_roblox / to_blender:
  * Blender (sculpting, rendering): studs, +Z up, the person faces -Y, the ground is z = 0 and the
    person's LEFT is +X (the heroes pipeline's convention: Blender (x, y, z) -> Roblox (-x, z, y)).
  * Roblox (the manifest): studs, +Y up, facing -Z, relative to the HumanoidRootPart's centre, which
    stands ROOT_HEIGHT above the soles.

Joints. The names, hierarchy and positions are the stock R15 block rig's (Humanoid rig attachments of
the classic 2 x 2 x 1 torso figure): Root (0, -1, 0), Waist (0, -0.6, 0), Neck (0, 1, 0), shoulders
(+-1, 0.763, 0), hips (+-0.5, -1, 0), knees (+-0.5, -1.822, 0), ankles (+-0.5, -2.748, 0), soles at
-3, so the root's height, the stride of the stock walk and run and the HipHeight of 2 are unchanged.
Elbows and wrists keep the stock heights (0.035 and -0.75) but hang under the shoulder at x = +-1.08
and +-1.10 instead of the block arm's centre line x = +-1.5: a 1-stud-wide block arm pivots at its
inner top edge, a round arm has to pivot inside its own shoulder ball or a gap opens when it swings.
The stock animations only rotate these joints, so they play unchanged.
"""
import math
import os
import re

ROOT_HEIGHT = 3.0  # HumanoidRootPart centre above the soles (HRP 2 x 2 x 1, HipHeight 2)
HEIGHT = 5.5  # studs, soles to the top of the hair

# ---- skeleton (Roblox frame, relative to the HumanoidRootPart centre) ---------------------------------

ARM_X_ELBOW = 1.08
ARM_X_WRIST = 1.10

# name, part0, part1, position
JOINTS = [
    ("Root", "HumanoidRootPart", "LowerTorso", (0.0, -1.0, 0.0)),
    ("Waist", "LowerTorso", "UpperTorso", (0.0, -0.6, 0.0)),
    ("Neck", "UpperTorso", "Head", (0.0, 1.0, 0.0)),
    ("LeftShoulder", "UpperTorso", "LeftUpperArm", (-1.0, 0.763, 0.0)),
    ("LeftElbow", "LeftUpperArm", "LeftLowerArm", (-ARM_X_ELBOW, 0.035, 0.0)),
    ("LeftWrist", "LeftLowerArm", "LeftHand", (-ARM_X_WRIST, -0.75, 0.0)),
    ("RightShoulder", "UpperTorso", "RightUpperArm", (1.0, 0.763, 0.0)),
    ("RightElbow", "RightUpperArm", "RightLowerArm", (ARM_X_ELBOW, 0.035, 0.0)),
    ("RightWrist", "RightLowerArm", "RightHand", (ARM_X_WRIST, -0.75, 0.0)),
    ("LeftHip", "LowerTorso", "LeftUpperLeg", (-0.5, -1.0, 0.0)),
    ("LeftKnee", "LeftUpperLeg", "LeftLowerLeg", (-0.5, -1.822, 0.0)),
    ("LeftAnkle", "LeftLowerLeg", "LeftFoot", (-0.5, -2.748, 0.0)),
    ("RightHip", "LowerTorso", "RightUpperLeg", (0.5, -1.0, 0.0)),
    ("RightKnee", "RightUpperLeg", "RightLowerLeg", (0.5, -1.822, 0.0)),
    ("RightAnkle", "RightLowerLeg", "RightFoot", (0.5, -2.748, 0.0)),
]
STOCK_BLOCK_RIG = {  # what the classic block rig has where this rig differs (for the manifest)
    "LeftElbow": (-1.5, 0.035, 0.0), "LeftWrist": (-1.5, -0.75, 0.0),
    "RightElbow": (1.5, 0.035, 0.0), "RightWrist": (1.5, -0.75, 0.0),
}

PARTS = [
    "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
]
# the limb parts are sculpted once (the left one) and mirrored
SIDED = ["UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot"]


def to_blender(p):
    """Roblox (root-relative) -> Blender (ground at z = 0)."""
    return (-p[0], p[2], p[1] + ROOT_HEIGHT)


def to_roblox(p):
    return (-p[0], p[2] - ROOT_HEIGHT, p[1])


def joint_b(name):
    for n, _p0, _p1, pos in JOINTS:
        if n == name:
            return to_blender(pos)
    raise KeyError(name)


# Blender-frame joint positions of the LEFT side (x > 0) and the midline
J = {n: to_blender(pos) for n, _a, _b, pos in JOINTS}

# ---- attachments (Roblox frame, root-relative; the builder converts them to part-relative) -------------
# Roblox's own accessory and grip attachments plus the game's sockets (Avatar/PuppetSpec HUMAN_SOCKETS,
# Actors/RigSpec human.sockets). Positions are on this body's surface, not the block rig's.
ATTACHMENTS = [
    # name, part, position
    ("HairAttachment", "Head", (0.0, 2.44, 0.0)),
    ("HatAttachment", "Head", (0.0, 2.44, 0.0)),
    ("FaceCenterAttachment", "Head", (0.0, 1.85, 0.0)),
    ("FaceFrontAttachment", "Head", (0.0, 1.85, -0.62)),
    ("MaskAttachment", "Head", (0.0, 1.72, -0.64)),
    ("NeckAttachment", "UpperTorso", (0.0, 1.0, 0.0)),
    ("BodyFrontAttachment", "UpperTorso", (0.0, 0.3, -0.46)),
    ("BodyBackAttachment", "UpperTorso", (0.0, 0.3, 0.46)),
    ("LeftCollarAttachment", "UpperTorso", (-0.62, 1.02, 0.0)),
    ("RightCollarAttachment", "UpperTorso", (0.62, 1.02, 0.0)),
    ("BadgeAttachment", "UpperTorso", (-0.38, 0.5, -0.45)),
    ("ChestRigAttachment", "UpperTorso", (0.0, 0.3, -0.46)),
    ("WaistCenterAttachment", "LowerTorso", (0.0, -0.75, 0.0)),
    ("WaistFrontAttachment", "LowerTorso", (0.0, -0.75, -0.46)),
    ("WaistBackAttachment", "LowerTorso", (0.0, -0.75, 0.46)),
    ("LeftShoulderAttachment", "LeftUpperArm", (-1.1, 1.06, 0.0)),
    ("RightShoulderAttachment", "RightUpperArm", (1.1, 1.06, 0.0)),
    ("PadAttachmentL", "LeftUpperArm", (-1.1, 1.06, 0.0)),
    ("PadAttachmentR", "RightUpperArm", (1.1, 1.06, 0.0)),
    ("LeftGripAttachment", "LeftHand", (-1.04, -1.02, -0.03)),
    ("RightGripAttachment", "RightHand", (1.04, -1.02, -0.03)),
    ("LeftFootAttachment", "LeftFoot", (-0.5, -3.0, 0.0)),
    ("RightFootAttachment", "RightFoot", (0.5, -3.0, 0.0)),
]

# ---- builds ------------------------------------------------------------------------------------------
# Both builds share the skeleton, the mesh topology and the UV layout (so one texture set dresses both).
BUILDS = {
    "slim": dict(
        chest_w=0.74, chest_d=0.42, chest_z=3.46, waist_w=0.62, waist_d=0.39, belly=0.0, yoke=0.84, yoke_r=0.24,
        hip_r=0.325, pelvis_w=0.665, pelvis_d=0.415, thigh=0.29, knee=0.24, shin=0.222, calf=0.25, ankle=0.205,
        shoulder=0.258, uarm=0.205, elbow=0.182, farm=0.168, wrist=0.148, hand=1.0, shoe=1.0,
    ),
    "broad": dict(
        chest_w=0.83, chest_d=0.50, chest_z=3.42, waist_w=0.77, waist_d=0.52, belly=0.1, yoke=0.84, yoke_r=0.265,
        hip_r=0.355, pelvis_w=0.81, pelvis_d=0.51, thigh=0.325, knee=0.27, shin=0.25, calf=0.28, ankle=0.218,
        shoulder=0.288, uarm=0.238, elbow=0.208, farm=0.195, wrist=0.166, hand=1.07, shoe=1.05,
    ),
}
BUILD_ORDER = ["slim", "broad"]

# ---- regions, outfits, roles -------------------------------------------------------------------------
# A region is a MeshPart whose Color is set at runtime; its SurfaceAppearance colour map (AlphaMode
# Overlay) only carries the detail on top. A tint is a RolePalettes look key (skin, shirt, pants, hair,
# cap) or a fixed colour "#rrggbb".
SHOE = {"brown": "#5a4334", "black": "#26262a", "white": "#e6e6e0", "navy": "#2b3445", "tan": "#8a6a4a"}

# outfit -> body-atlas painter, sleeves and what tints each part
OUTFITS = {
    # a buttoned shirt with a collar and short sleeves, belted trousers
    "shirt": dict(label="Short-sleeved shirt", lower_arm="skin", lower_torso="pants", hand="skin", shoe=SHOE["brown"],
                  extras=[]),
    # a zipped jacket with long sleeves and cuffs
    "jacket": dict(label="Zipped jacket", lower_arm="shirt", lower_torso="pants", hand="skin", shoe=SHOE["tan"],
                   extras=[]),
    # the doctor's white coat: buttoned, lapels over a shirt and tie, hip pockets, coat tails on the thighs
    "coat": dict(label="Doctor's coat", lower_arm="shirt", lower_torso="shirt", hand="skin", shoe=SHOE["brown"],
                 extras=["Stethoscope", "LeftCoatTail", "RightCoatTail"]),
    # scrubs: V neck (bare skin in the V), chest pocket, loose untucked top, drawstring trousers
    "scrubs": dict(label="Scrubs", lower_arm="skin", lower_torso="shirt", hand="skin", shoe=SHOE["white"],
                   extras=["VNeck"]),
    # police: badge, tie, epaulettes, duty belt
    "police": dict(label="Police uniform", lower_arm="shirt", lower_torso="pants", hand="skin", shoe=SHOE["black"],
                   extras=[]),
    # hospital guard: shield patch, radio, plain belt
    "guard": dict(label="Guard uniform", lower_arm="skin", lower_torso="pants", hand="skin", shoe=SHOE["black"],
                  extras=[]),
    # the mime: black-and-white hoops, braces, white gloves
    "mime": dict(label="Mime", lower_arm="shirt", lower_torso="pants", hand="#f1f1ec", shoe=SHOE["black"],
                 extras=[]),
}
OUTFIT_ORDER = ["shirt", "jacket", "coat", "scrubs", "police", "guard", "mime"]

EXTRAS = {  # extra region meshes: the R15 part they are welded to and their tint
    "Stethoscope": dict(part="UpperTorso", tint="#ffffff", note="opaque texture: grey tube, steel chest piece"),
    "VNeck": dict(part="UpperTorso", tint="skin", note="bare skin in the V of the scrubs"),
    "LeftCoatTail": dict(part="LeftUpperLeg", tint="shirt", note="the coat's skirt, swings with the thigh"),
    "RightCoatTail": dict(part="RightUpperLeg", tint="shirt", note="the coat's skirt, swings with the thigh"),
}


def region_tints(outfit):
    """R15 part (and extra) -> tint key for an outfit."""
    o = OUTFITS[outfit]
    t = {"Head": "skin", "UpperTorso": "shirt", "LowerTorso": o["lower_torso"]}
    for side in ("Left", "Right"):
        t[side + "UpperArm"] = "shirt"
        t[side + "LowerArm"] = o["lower_arm"]
        t[side + "Hand"] = o["hand"]
        t[side + "UpperLeg"] = "pants"
        t[side + "LowerLeg"] = "pants"
        t[side + "Foot"] = o["shoe"]
    for e in o["extras"]:
        t[e] = EXTRAS[e]["tint"]
    return t


EXPRESSIONS = ["calm", "worried", "frightened"]
FACES = ["plain", "mime"]  # the mime's white greasepaint is a second set of head colour maps

HAIR = {
    # name: label, fits under the peaked cap
    "short": dict(label="Short crop", under_cap=True),
    "parted": dict(label="Side parting", under_cap=False),
    "bob": dict(label="Bob with a fringe", under_cap=False),
    "ponytail": dict(label="Ponytail", under_cap=True),
    "curly": dict(label="Round curls", under_cap=False),
    "bun": dict(label="Bun", under_cap=True),
    "balding": dict(label="Balding, grey at the sides", under_cap=True),
    "long": dict(label="Long, behind the shoulders", under_cap=False),
}
HAIR_ORDER = ["short", "parted", "bob", "ponytail", "curly", "bun", "balding", "long"]
HATS = {
    "cap": dict(label="Peaked cap", tint="cap", note="guards, officers and drivers; badge and glossy peak painted"),
    "beret": dict(label="Beret", tint="#202020", note="the mime"),
}
HAT_ORDER = ["cap", "beret"]

ROLES = {
    "townsperson": dict(outfits=["shirt", "jacket"], face="plain", hat=None, hair=HAIR_ORDER),
    "doctor": dict(outfits=["coat"], face="plain", hat=None, hair=["short", "parted", "bob", "bun", "balding", "ponytail"]),
    "nurse": dict(outfits=["scrubs"], face="plain", hat=None, hair=["bun", "ponytail", "bob", "short", "curly"]),
    "guard": dict(outfits=["guard"], face="plain", hat="cap", hair=["short", "balding", "bun", "ponytail"]),
    "orderly": dict(outfits=["scrubs"], face="plain", hat=None, hair=["short", "curly", "parted", "ponytail"]),
    "officer": dict(outfits=["police"], face="plain", hat="cap", hair=["short", "ponytail", "bun", "balding"]),
    "driver": dict(outfits=["police"], face="plain", hat="cap", hair=["short", "balding", "ponytail", "bun"]),
    "mime": dict(outfits=["mime"], face="mime", hat="beret", hair=["short", "parted", "bob"]),
}
ROLE_ORDER = ["townsperson", "doctor", "nurse", "guard", "orderly", "officer", "driver", "mime"]

# ---- RolePalettes (read from the game's Luau so the renders wear the real colours) ---------------------

_HERE = os.path.dirname(os.path.abspath(__file__))
_PALETTES_LUAU = os.path.join(_HERE, "..", "..", "..", "src", "shared", "Avatar", "RolePalettes.luau")


def _hexes(s):
    return re.findall(r'"(#[0-9a-fA-F]{6})"', s)


def load_palettes(path=_PALETTES_LUAU):
    with open(path) as fh:
        src = fh.read()

    def lst(name):
        m = re.search(r"RolePalettes\." + name + r"\s*=\s*\{([^}]*)\}", src)
        return _hexes(m.group(1))

    out = {"SKINS": lst("SKINS"), "PANTS": lst("PANTS"), "HAIR": lst("HAIR"), "CLOTHES": lst("CLOTHES"), "roles": {}}
    for role in ROLE_ORDER:
        m = re.search(r"\b" + role + r"\s*=\s*\{(.*)", src)
        line = m.group(1)
        shirts = _hexes(re.search(r"shirts\s*=\s*\{([^}]*)\}", line).group(1))
        pm = re.search(r"pants\s*=\s*\{([^}]*)\}", line)
        pants = _hexes(pm.group(1)) if pm else out["PANTS"]
        cm = re.search(r'cap\s*=\s*"(#[0-9a-fA-F]{6})"', line)
        out["roles"][role] = {"shirts": shirts, "pants": pants, "cap": cm.group(1) if cm else None}
    return out


def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def _hsv(c):
    mx, mn = max(c), min(c)
    d = mx - mn
    h = 0.0
    if d > 1e-9:
        if mx == c[0]:
            h = ((c[1] - c[2]) / d) % 6
        elif mx == c[1]:
            h = (c[2] - c[0]) / d + 2
        else:
            h = (c[0] - c[1]) / d + 4
        h /= 6
    return h, (d / mx if mx > 0 else 0.0), mx


def _reads_as_skin(shirt, skin):
    h, s, v = _hsv(shirt)
    if 0.02 <= h <= 0.14 and 0.15 <= s <= 0.75 and 0.25 <= v <= 0.97:
        return True
    return math.dist(shirt, skin) < 0.22


def look(role, index, pal=None):
    """RolePalettes.look(role, index) (the same picks, as hex strings)."""
    pal = pal or load_palettes()
    p = pal["roles"][role]
    i = max(1, int(index))

    def pick(lst_, k):
        return lst_[(k - 1) % len(lst_)]

    skin = pick(pal["SKINS"], i * 3 + 1)
    shirt = pick(p["shirts"], i)
    if _reads_as_skin(_rgb(shirt), _rgb(skin)):
        for k in range(len(pal["CLOTHES"])):
            c = pal["CLOTHES"][(i + k - 1) % len(pal["CLOTHES"])]
            if not _reads_as_skin(_rgb(c), _rgb(skin)):
                shirt = c
                break
    return {"role": role, "skin": skin, "shirt": shirt, "pants": pick(p["pants"], i * 2 + 1),
            "hair": pick(pal["HAIR"], i * 5 + 2), "cap": p["cap"]}
