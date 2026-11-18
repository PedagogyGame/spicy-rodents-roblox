"""Posing the rigid R15 parts exactly as Motor6D joints do (numpy only), and a few poses.

Roblox places a joint's Part1 at  Part0.CFrame * C0 * Transform * C1:Inverse(); with the manifest's
translation-only C0 / C1 that is a rotation about the joint's pivot. fk() does this in Roblox axes
(+Y up, facing -Z, +X the person's right) from the root down and returns each part's 4 x 4 matrix
relative to the HumanoidRootPart; to_blender() converts one for a Blender object whose mesh was
exported with the pipeline's axis mapping. A pose maps joint name -> (rx, ry, rz) degrees, applied like
CFrame.Angles(rx, ry, rz); "_root" is an extra (x, y, z) offset of the LowerTorso (the stock clips
move the root this way too). Positive rx swings a hanging arm or leg forward and bends an elbow;
a knee bends with negative rx.
"""
import math

import numpy as np

import spec

M3 = np.array([[-1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])  # Roblox <-> Blender axes (its own inverse)


def translation(v):
    m = np.eye(4)
    m[:3, 3] = v
    return m


def angles(rx, ry, rz):
    """CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz (degrees here)."""
    a, b, c = (math.radians(t) for t in (rx, ry, rz))
    Rx = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])
    Ry = np.array([[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]])
    Rz = np.array([[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]])
    m = np.eye(4)
    m[:3, :3] = Rx @ Ry @ Rz
    return m


def fk(joints, pose):
    """joints: the manifest's {name: {part0, part1, c0, c1}}. Returns {part: 4 x 4} in root space."""
    out = {"HumanoidRootPart": np.eye(4)}
    for name, _p0, _p1, _pos in spec.JOINTS:
        j = joints[name]
        t = angles(*pose.get(name, (0, 0, 0)))
        if name == "Root" and "_root" in pose:
            t = translation(pose["_root"]) @ t
        out[j["part1"]] = out[j["part0"]] @ translation(j["c0"]) @ t @ translation(-np.array(j["c1"]))
    return out


def to_blender(m):
    """A root-space Roblox matrix -> the Blender matrix of the part's object (root at the origin)."""
    c = np.eye(4)
    c[:3, :3] = M3
    return c @ m @ c


def mirrored(pose):
    """The same pose with left and right swapped."""
    out = {}
    for k, v in pose.items():
        if k.startswith("Left"):
            k2 = "Right" + k[4:]
        elif k.startswith("Right"):
            k2 = "Left" + k[5:]
        else:
            k2 = k
        out[k2] = (v[0], -v[1], -v[2])
    return out


REST = {}
# mid-stride: the right heel has just landed, the left foot is pushing off, the arms swing against the legs
WALK = {
    "Root": (-2, 5, 0), "Waist": (-2, -11, 0), "Neck": (3, 6, 0),
    "RightHip": (27, 0, 0), "RightKnee": (-7, 0, 0), "RightAnkle": (8, 0, 0),
    "LeftHip": (-23, 0, 0), "LeftKnee": (-16, 0, 0), "LeftAnkle": (-17, 0, 0),
    "LeftShoulder": (25, 0, -2), "LeftElbow": (24, 0, 0), "RightShoulder": (-22, 0, 2), "RightElbow": (9, 0, 0),
}
# the passing position: the left leg carries the weight, the right knee comes through
PASS = {
    "Root": (-2, 0, 0), "Waist": (-1, 0, 0), "Neck": (2, 0, 0),
    "RightHip": (24, 0, 0), "RightKnee": (-56, 0, 0), "RightAnkle": (-6, 0, 0),
    "LeftHip": (-4, 0, 0), "LeftKnee": (-3, 0, 0), "LeftAnkle": (2, 0, 0),
    "LeftShoulder": (6, 0, -2), "LeftElbow": (16, 0, 0), "RightShoulder": (-5, 0, 2), "RightElbow": (14, 0, 0),
}
RUN = {
    "Root": (-13, 6, 0), "Waist": (-6, -14, 0), "Neck": (13, 8, 0),
    "RightHip": (66, 0, 0), "RightKnee": (-92, 0, 0), "RightAnkle": (-4, 0, 0),
    "LeftHip": (-30, 0, 0), "LeftKnee": (-24, 0, 0), "LeftAnkle": (-30, 0, 0),
    "LeftShoulder": (52, 0, -6), "LeftElbow": (88, 0, 0), "RightShoulder": (-50, 0, 6), "RightElbow": (72, 0, 0),
}
SIT = {
    "Waist": (-3, 0, 0), "Neck": (2, 0, 0),
    "RightHip": (88, 0, 0), "RightKnee": (-88, 0, 0), "LeftHip": (88, 0, 0), "LeftKnee": (-86, 0, 0), "LeftAnkle": (4, 0, 0),
    "LeftShoulder": (-4, 0, -9), "LeftElbow": (10, 0, 0), "RightShoulder": (-4, 0, 9), "RightElbow": (10, 0, 0),
}
STAND = {"LeftShoulder": (2, 0, -2), "RightShoulder": (2, 0, 2), "LeftElbow": (8, 0, 0), "RightElbow": (8, 0, 0)}
# startled: hands up, leaning back (for the frightened close-up)
STARTLED = {
    "Waist": (5, 0, 0), "Neck": (4, 0, 0),
    "LeftShoulder": (58, 0, -28), "LeftElbow": (100, 0, 0), "RightShoulder": (62, 0, 26), "RightElbow": (96, 0, 0),
}
POSES = {"rest": REST, "walk": WALK, "walk2": mirrored(WALK), "pass": PASS, "pass2": mirrored(PASS), "run": RUN, "sit": SIT,
         "stand": STAND, "startled": STARTLED}
