"""Numbers for the squirrel's motion as the game shows it (system python3 or the bpy venv; numpy only).

  lune run tools/review/motion_path.luau                              # build/motion/<variant>_<take>.json
  python3 -I tools/blender/heroes/motion_metrics.py [--motion build/motion] [--heroes build/heroes] \
      [--variants squirrel,rodent] [--out build/motion/metrics.json] [--upsample 4]

Every number is measured on the takes: the body where the motor and the drawn pose put it, the clip the
driver chose at the rate it chose (tracks crossing over are mixed), the layers multiplied on, the joints
through the exported clips (motion_pose.py). Frames are 1/60 s apart; between two frames everything is
taken in a straight line (`--upsample` points per frame) so a stance of three frames is still measured.

Per gait (a take's steady stretch): what the animation is told and what the body does; the clip, its rate,
the cycle's period and the ground covered in one cycle; per paw the stance (planted: the clip alone has the
paw's joint within PLANT studs of where it rests, so a layer that shakes the body is not counted as steps)
with how long it lasts, how far the body travels meanwhile, how far the clip moves the paw back under the
body meanwhile (and `strideClip`, its whole reach fore and aft), and the SLIDE: how far the planted paw
drifts over the ground (studs per stance; 0 is a paw that stays where it was put); the bob of hips and
shoulders; the spine's flex (the chest against the pelvis, nose-down/up and side to side, degrees, range
over the stretch); the tail tip's swing in the body's own frame; the head's bob, pitch, yaw and roll
ranges. Paw joints are the ball of the hind foot and the knuckles of the fore paw (a couple of hundredths
of a stud above the sole); `gap` is how far a planted one stays from the surface (ground, bark or wire).
Per event: the turn (yaw rate, lean, and whether tail, spine or head answer it: the S against the same
sprint run straight, moment for moment), the stop, the hop and the leap (what the clip that carries each
through the air shows against what the body does), taking the trunk; and which clips are never shown. What the layers on top of the
clips add to a stop, a leap and a landing (Animation/Liveliness: the dip of the nose, the lift of the tail,
the pitch along the flight, the squash) is measured against the same frames with the clips alone.
"""
import argparse
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import motion_pose as mp  # noqa: E402

PLANT = 0.015  # studs above where it rests in its stance: the paw counts as planted
BLIP = 0.025  # seconds: a planted paw that reads as lifted for no longer than this never left the ground
LEGS = ("FrontL", "FrontR", "BackL", "BackR")


def planted_mask(height, dt):
    """True where the paw is down. Its resting height is the level it spends a fifth of the stretch at or
    under (the stance is the flat bottom of the height curve; a leg at full stretch dips a little under it
    or twitches a little over it, which is not a step)."""
    on = height <= np.quantile(height, 0.2) + PLANT
    n = len(on)
    i = 0
    while i < n:
        if not on[i]:
            j = i
            while j < n and not on[j]:
                j += 1
            if i > 0 and j < n and (j - i) * dt <= BLIP:
                on[i:j] = True
            i = j
        else:
            i += 1
    return on


def r(x, n=3):
    return round(float(x), n) + 0.0


def deg(x):
    return math.degrees(float(x))


# ---- surfaces ------------------------------------------------------------------------------------------

def surface_of(take):
    """gap(p): how far a world point is from what the body moves on."""
    for p in take["props"]:
        if p["kind"] == "trunk":
            def gap(q, p=p):
                t = min(max((q[1] - p["y0"]) / p["height"], 0.0), 1.0)
                bark = max(p["minRadius"], p["radius"] * (1 - p["taper"] * t))
                return math.hypot(q[0] - p["x"], q[2] - p["z"]) - bark
            return "bark", gap
        if p["kind"] == "wire":
            pts = np.array(p["points"], dtype=np.float64)

            def gap(q, pts=pts, radius=p["radius"]):
                best = 1e9
                for a, b in zip(pts[:-1], pts[1:]):
                    ab = b - a
                    u = min(max(float((q - a) @ ab) / float(ab @ ab), 0.0), 1.0)
                    best = min(best, float(np.linalg.norm(q - (a + ab * u))))
                return best - radius
            return "wire", gap
    y0 = take["ground"]["y"]
    return "ground", lambda q: q[1] - y0


# ---- sampling ------------------------------------------------------------------------------------------

class Samples:
    """Joints over a stretch of a take, `up` points per frame."""

    def __init__(self, take, clips, rig, t0, t1, up):
        frames = take["frames"]
        fps = take["fps"]
        i0, i1 = max(0, int(round(t0 * fps))), min(len(frames) - 1, int(round(t1 * fps)))
        self.take, self.rig = take, rig
        self.t, self.frames = [], []
        for i in range(i0, i1):
            for k in range(up):
                self.frames.append(mp.lerp_frames(frames[i], frames[i + 1], k / up))
        self.frames.append(frames[i1])
        self.dt = 1.0 / (fps * up)
        self.raw = frames[i0 : i1 + 1]
        # W: the joints as shown (clips and layers); W0: the clips alone (when a paw is down is the
        # clip's business: a layer that shakes the chest must not read as steps)
        self.W, self.W0, self.body = [], [], []
        for f in self.frames:
            self.t.append(f["t"])
            self.W.append(rig.fk(mp.frame_pose(clips, f)))
            self.W0.append(rig.fk(mp.frame_pose(clips, f, layers=False)) if f.get("layers") else self.W[-1])
            self.body.append(mp.body_frame(f))
        self.t = np.array(self.t)

    def model(self, fn, layers=True):
        """(n, 3): a point per sample in the model's frame; fn(W) -> point."""
        return np.array([fn(W) for W in (self.W if layers else self.W0)])

    def world(self, fn):
        return np.array([p + R @ fn(W) for W, (R, p) in zip(self.W, self.body)])

    def joint(self, bone):
        return lambda W: W[bone][1]

    def mid(self, a, b):
        return lambda W: (W[a][1] + W[b][1]) / 2

    def col(self, key):
        return np.array([f[key] for f in self.frames], dtype=np.float64)


def span(a):
    return float(np.max(a) - np.min(a))


def stances(planted):
    """[(first, last)] of the whole runs of True (runs cut by either end of the stretch are left out)."""
    out, start = [], None
    for i, on in enumerate(planted):
        if on and start is None:
            start = i
        elif not on and start is not None:
            if start > 0:
                out.append((start, i - 1))
            start = None
    return out


def paw_metrics(s, gap_fn, leg):
    toe = s.world(s.joint(f"{leg}_Toe"))
    toe_model = s.model(s.joint(f"{leg}_Toe"))
    # planted: the clip has the paw down on the plane the body stands on (its height in the body's own
    # frame is at its lowest); the gap is how far that leaves it from the real surface
    planted = planted_mask(s.model(s.joint(f"{leg}_Toe"), layers=False)[:, 1], s.dt)
    gaps = np.array([gap_fn(q) for q in toe])
    runs = stances(planted)
    feet = np.array([p for _, p in s.body])
    out = {
        "gap": r(gaps[planted].mean()),
        "gapLeast": r(gaps.min()),
        "lift": r(span(toe_model[:, 1])),
        "strideClip": r(span(toe_model[:, 2])),  # the paw's reach fore and aft under the body, over the cycle
        "plantedShare": r(float(planted.mean()), 2),
        "stances": len(runs),
    }
    if not runs:
        return out
    slide, path, secs, body, clip, wobble = [], [], [], [], [], []
    for a, b in runs:
        slide.append(np.linalg.norm(toe[b] - toe[a]))
        path.append(np.sum(np.linalg.norm(np.diff(toe[a : b + 1], axis=0), axis=1)))
        secs.append((b - a) * s.dt)
        body.append(np.linalg.norm(feet[b] - feet[a]))
        clip.append(np.linalg.norm(toe_model[b] - toe_model[a]))
        wobble.append(span(gaps[a : b + 1]))
    out.update(
        stanceSeconds=r(np.mean(secs), 4),
        slide=r(np.mean(slide)),
        slideMax=r(np.max(slide)),
        slidePath=r(np.mean(path)),
        slideSpeed=r(np.mean(slide) / max(np.mean(secs), 1e-9), 2),
        bodyTravelInStance=r(np.mean(body)),
        clipTravelInStance=r(np.mean(clip)),
        upDownWhilePlanted=r(np.mean(wobble)),
    )
    return out


def rel_angles(Ra, Rb):
    """(pitch, yaw, roll) of Rb seen from Ra, radians (about X, Y, Z; small-angle reading)."""
    R = Ra.T @ Rb
    return math.atan2(R[2, 1], R[1, 1]), math.atan2(R[0, 2], R[0, 0]), math.atan2(R[1, 0], R[0, 0])


def posture(s):
    """Bob, spine, tail and head over the stretch. Heights are taken in the body's own frame (above the
    plane it stands on), which on level ground is the height over the ground and on a trunk the distance
    out from the feet point: the drawn feet point itself never bobs."""
    hips = s.model(s.mid("BackL_Upper", "BackR_Upper"))
    shoulders = s.model(s.mid("FrontL_Upper", "FrontR_Upper"))
    head = s.model(s.joint("Head"))
    spine = np.array([rel_angles(W["Hips"][0], W["Chest"][0]) for W in s.W])
    headR = np.array([rel_angles(np.eye(3), W["Head"][0]) for W in s.W])
    tip = s.model(lambda W: s.rig.tip(W, "Tail8"))
    root = s.model(s.joint("Tail1"))
    tail = tip - root
    tail_side = np.degrees(np.arctan2(tail[:, 0], tail[:, 2]))  # + to the body's right
    tail_up = np.degrees(np.arctan2(tail[:, 1], np.hypot(tail[:, 0], tail[:, 2])))
    head_model = s.model(s.joint("Head"))
    return {
        "hipsBob": r(span(hips[:, 1])),
        "shouldersBob": r(span(shoulders[:, 1])),
        "spineFlexDeg": r(deg(span(spine[:, 0])), 1),
        "spineFlexFromTo": [r(deg(spine[:, 0].min()), 1), r(deg(spine[:, 0].max()), 1)],
        "spineSideBendDeg": r(deg(span(spine[:, 1])), 1),
        "spineTwistDeg": r(deg(span(spine[:, 2])), 1),
        "tailTipUpDown": r(span(tip[:, 1])),
        "tailTipSideToSide": r(span(tip[:, 0])),
        "tailSwingDeg": {"upDown": r(span(tail_up), 1), "sideToSide": r(span(tail_side), 1)},
        "headBob": r(span(head[:, 1])),
        "headSurge": r(span(head_model[:, 2])),
        "headPitchDeg": r(deg(span(headR[:, 0])), 1),
        "headYawDeg": r(deg(span(headR[:, 1])), 1),
        "headRollDeg": r(deg(span(headR[:, 2])), 1),
    }, {
        "tailSide": tail_side,
        "tailUp": tail_up,
        "spineSide": np.degrees(spine[:, 1]),
        "headYaw": np.degrees(headR[:, 1]),
        "headRoll": np.degrees(headR[:, 2]),
        "chestRoll": np.degrees(np.array([rel_angles(np.eye(3), W["Chest"][0])[2] for W in s.W])),
    }


def gait(take, clips, rig, window, up):
    t0, t1 = window
    s = Samples(take, clips, rig, t0, t1, up)
    name, gap_fn = surface_of(take)
    raw = s.raw
    clip = raw[len(raw) // 2]["clip"]
    rate = float(np.mean([f["clipRate"] for f in raw]))
    speed = float(np.mean([f["speed"] for f in raw]))
    ground = float(np.mean([f["groundSpeed"] for f in raw]))
    length = take["clips"][clip]["length"]
    period = length / rate if rate > 0 else float("inf")
    out = {
        "take": take["take"],
        "window": [t0, t1],
        "surface": name,
        "clip": clip,
        "clipRate": r(rate),
        "speedTold": r(speed, 2),
        "speedMoved": r(ground, 2),
        "cyclePeriod": r(period, 4),
        "cyclesPerSecond": r(1 / period, 2),
        "travelPerCycle": r(ground * period, 2),
        "paws": {leg: paw_metrics(s, gap_fn, leg) for leg in LEGS},
    }
    for pair, legs in (("fore", ("FrontL", "FrontR")), ("hind", ("BackL", "BackR"))):
        got = [out["paws"][leg] for leg in legs if "slide" in out["paws"][leg]]
        if got:
            keys = ("slide", "stanceSeconds", "bodyTravelInStance", "clipTravelInStance", "strideClip", "upDownWhilePlanted")
            out[pair] = {k: r(np.mean([g[k] for g in got]), 4 if k == "stanceSeconds" else 3) for k in keys}
            out[pair]["gap"] = r(min(out["paws"][leg]["gap"] for leg in legs))
    out["footSlide"] = r(np.mean([out[p]["slide"] for p in ("fore", "hind") if p in out])) if ("fore" in out or "hind" in out) else None
    post, _ = posture(s)
    out.update(post)
    return out


# ---- events --------------------------------------------------------------------------------------------

def turn_event(take, straight, clips, rig, up):
    """What the body does about a turn. The S is sprinted exactly as the straight sprint take is (same
    keys but for the mouse, same clock), so the clip and every layer that does not know about turning are
    the same in both at every moment: the difference between the two takes, moment for moment, is what
    turning changes. Signs: `tailTrail` + is the tail left behind: it still points where the body was
    heading, so its tip is on the side the body turns to (to the left of a body turning left);
    `spineInto` and `headInto` + are the chest (against the pelvis) and the head turned into the turn;
    `bank` + is a roll into it (the drawn body's lean, and with the chest's own roll on top the
    shoulders' whole bank; the head's is what is left of that at the head, 0 when it stays level)."""
    w = take["windows"]
    t0, t1 = w["turning"]
    t1 = min(t1 + 0.5, take["seconds"], straight["seconds"] if straight is not None else t1 + 0.5)  # ... and the tail's way back
    s = Samples(take, clips, rig, t0, t1, up)
    _, ser = posture(s)
    if straight is not None:
        _, ref = posture(Samples(straight, clips, rig, t0, t1, up))
    else:
        ref = {k: np.zeros_like(v) for k, v in ser.items()}
    rate = np.degrees(np.gradient(np.unwrap(s.col("yaw")), s.dt))  # + is a turn to the left
    way = np.sign(rate)
    roll = np.degrees(s.col("roll"))  # + is the left side down
    d_tail = -(ser["tailSide"] - ref["tailSide"])  # + toward the body's left
    d_spine = ser["spineSide"] - ref["spineSide"]  # + toward its left
    d_head = ser["headYaw"] - ref["headYaw"]
    chest = roll + ser["chestRoll"] - ref["chestRoll"]
    head = roll + ser["headRoll"] - ref["headRoll"]
    out = {"comparedWith": straight["take"] if straight is not None else None}
    spans = {"left": (w["left"][0], w["right"][0]), "right": (w["right"][0], t1)}
    for key in ("left", "right"):
        m = (s.t >= w[key][0]) & (s.t <= w[key][1])
        peak = int(np.argmax(np.abs(rate[m])))
        side = float(np.sign(rate[m][peak]))
        # from the start of this turn to the start of the next: the tail's swing out and back
        whole = (s.t >= spans[key][0]) & (s.t < spans[key][1])
        tw = s.t[whole]
        trail = d_tail[whole] * side
        out_i = int(np.argmax(trail))
        rate_i = int(np.argmax(rate[whole] * side))
        back = np.nonzero(trail[out_i:] < 0.2 * trail[out_i])[0]
        out[key] = {
            "yawRateMeanDegPerSec": r(np.mean(rate[m]), 1),
            "yawRatePeakDegPerSec": r(rate[m][peak], 1),
            "leanPeakDeg": r(roll[m][int(np.argmax(np.abs(roll[m])))], 1),
            "shouldersBankPeakDeg": r(np.max(chest[whole] * side), 1),
            "headRollPeakDeg": r(np.max(np.abs(head[whole])), 1),
            "tailTrailDeg": r(np.mean(d_tail[m] * way[m]), 2),
            "tailTrailPeakDeg": r(trail[out_i], 2),
            "tailTrailPeakSecondsAfterYawRatePeak": r(tw[out_i] - tw[rate_i], 3),
            "tailBackSecondsAfterItsPeak": r(tw[out_i + back[0]] - tw[out_i], 3) if len(back) else None,
            "tailSwingsPastDeg": r(max(0.0, -float(np.min(trail[out_i:]))), 2),
            "spineIntoDeg": r(np.mean(d_spine[m] * way[m]), 2),
            "spineIntoPeakDeg": r(np.max(d_spine[whole] * side), 2),
            "headIntoDeg": r(np.mean(d_head[m] * way[m]), 2),
            "headIntoPeakDeg": r(np.max(d_head[whole] * side), 2),
        }
    # a tail that follows the body like a towed thing trails it by (seconds of lag) x (turn rate): the
    # slope of its trailing angle against the turn rate over the whole S is that lag, in seconds
    out["tailLagSeconds"] = r(float(np.sum(d_tail * rate) / max(np.sum(rate * rate), 1e-9)), 4)
    out["spineIntoPerTurnRate"] = r(float(np.sum(d_spine * rate) / max(np.sum(rate * rate), 1e-9)), 4)
    out["headIntoPerTurnRate"] = r(float(np.sum(d_head * rate) / max(np.sum(rate * rate), 1e-9)), 4)
    out["anythingAnswersTheTurn"] = bool(max(np.max(np.abs(d_tail)), np.max(np.abs(d_spine)), np.max(np.abs(d_head))) > 0.05)
    return out


def layered(s, gap_fn):
    """What the layers add over a stretch, against the same frames with the clips alone: the body's pitch
    (the chest's nose-up angle in the body's frame, degrees), the tail's lift (the angle of its root-to-tip
    line above level, degrees), the hips' height (studs), and the lowest any planted-or-not toe joint gets
    to the surface with and without them (the joint rests about 0.02 above it)."""
    def chest_pitch(Ws):
        return np.degrees(np.array([rel_angles(np.eye(3), W["Chest"][0])[0] for W in Ws]))

    def tail_up(Ws):
        v = np.array([s.rig.tip(W, "Tail8") - W["Tail1"][1] for W in Ws])
        return np.degrees(np.arctan2(v[:, 1], np.hypot(v[:, 0], v[:, 2])))

    def hips(Ws):
        return np.array([(W["BackL_Upper"][1][1] + W["BackR_Upper"][1][1]) / 2 for W in Ws])

    def lowest(Ws):
        return np.array([min(gap_fn(p + R @ W[f"{leg}_Toe"][1]) for leg in LEGS) for W, (R, p) in zip(Ws, s.body)])

    return {
        "pitch": chest_pitch(s.W) - chest_pitch(s.W0),
        "tail": tail_up(s.W) - tail_up(s.W0),
        "hips": hips(s.W) - hips(s.W0),
        "toeGap": lowest(s.W),
        "toeGapClips": lowest(s.W0),
    }


def stop_event(take, clips, rig, up):
    frames = take["frames"]
    w = take["windows"]["stopping"]
    fps = take["fps"]
    i0 = int(round(w[0] * fps))
    still = next(i for i in range(i0, len(frames)) if frames[i]["groundSpeed"] < 0.5)
    told = next(i for i in range(i0, len(frames)) if frames[i]["speed"] < 0.5)
    idle = next(i for i in range(i0, len(frames)) if frames[i]["clip"] == "Idle" and len(frames[i]["tracks"]) == 1)
    a, b = mp.body_frame(frames[i0])[1], mp.body_frame(frames[still])[1]
    s = Samples(take, clips, rig, w[0], frames[idle]["t"], up)
    skate = {}
    for leg in LEGS:
        toe = s.world(s.joint(f"{leg}_Toe"))
        height = s.model(s.joint(f"{leg}_Toe"), layers=False)[:, 1]
        planted = planted_mask(height, s.dt)
        step = np.linalg.norm(np.diff(toe, axis=0), axis=1)
        skate[leg] = r(float(np.sum(step[planted[1:] & planted[:-1]])))
    clips_seen = []
    for f in frames[i0 : idle + 1]:
        if not clips_seen or clips_seen[-1] != f["clip"]:
            clips_seen.append(f["clip"])
    # the stop itself and the second after it: the dip and the tail's throw, over the clips alone
    _, gap_fn = surface_of(take)
    after = Samples(take, clips, rig, w[0], min(w[0] + 1.25, frames[-1]["t"]), up)
    add = layered(after, gap_fn)
    dip_i, lift_i = int(np.argmin(add["pitch"])), int(np.argmax(add["tail"]))
    answer = {
        "noseDipPeakDeg": r(-add["pitch"][dip_i], 1),
        "noseDipPeakAtSeconds": r(after.t[dip_i] - w[0], 3),
        "noseBackPastLevelDeg": r(max(0.0, float(np.max(add["pitch"][dip_i:]))), 1),
        "tailLiftPeakDeg": r(add["tail"][lift_i], 1),
        "tailLiftPeakAtSeconds": r(after.t[lift_i] - w[0], 3),
        "tailBackPastRestDeg": r(max(0.0, -float(np.min(add["tail"][lift_i:]))), 1),
        "hipsSinkStuds": r(-float(np.min(add["hips"]))),
        "lowestToeGap": r(float(np.min(add["toeGap"]))),
        "lowestToeGapClipsAlone": r(float(np.min(add["toeGapClips"]))),
        "settledAfterSeconds": r(float(after.t[np.nonzero((np.abs(add["pitch"]) > 0.5) | (np.abs(add["tail"]) > 2.0))[0][-1]] - w[0]), 3)
        if np.any((np.abs(add["pitch"]) > 0.5) | (np.abs(add["tail"]) > 2.0)) else 0.0,
    }
    idle_s = Samples(take, clips, rig, take["windows"]["idle"][0] + 0.2, take["windows"]["idle"][1], 1)
    post, _ = posture(idle_s)
    drift = max(span(idle_s.world(idle_s.joint(f"{leg}_Toe"))[:, k]) for leg in LEGS for k in range(3))
    return {
        "secondsToStandstill": r((still - i0) / fps, 3),
        "secondsUntilAnimationToldStill": r((told - i0) / fps, 3),
        "secondsUntilIdleAlone": r((idle - i0) / fps, 3),
        "studsCoveredStopping": r(np.linalg.norm(b - a), 2),
        "clipsOnTheWay": clips_seen,
        "pawSkateWhilePlanted": skate,
        "layers": answer,
        "idle": {"pawDrift": r(drift), **{k: post[k] for k in ("hipsBob", "headBob", "headYawDeg", "tailTipUpDown", "tailTipSideToSide", "spineFlexDeg")}},
    }


def air_event(take, window, clips=None, rig=None, up=1):
    frames = take["frames"]
    fps = take["fps"]
    i0, i1 = int(round(window[0] * fps)), int(round(window[1] * fps))
    air = [f for f in frames[i0 : i1 + 1] if f["mode"] == "air"]
    if not air:
        return None
    first, last = air[0]["i"], air[-1]["i"]
    shown = air[len(air) // 2]["clip"]  # the clip that carries it through the air (Leap, or Pounce for a pounce)
    leap = take["clips"][shown]
    held = [f for f in air if f["clipRate"] == 0]
    after = frames[min(last + 1, len(frames) - 1) : min(last + 13, len(frames))]
    answer = None
    if clips is not None:
        _, gap_fn = surface_of(take)
        t_land = frames[min(last + 1, len(frames) - 1)]["t"]
        s = Samples(take, clips, rig, frames[first]["t"], min(t_land + 0.6, frames[-1]["t"]), up)
        add = layered(s, gap_fn)
        air_m, land_m = s.t < t_land, s.t >= t_land
        sink_i = int(np.argmin(np.where(land_m, add["hips"], 0.0)))
        answer = {
            "noseUpPeakDeg": r(float(np.max(add["pitch"][air_m])), 1),
            "noseDownPeakDeg": r(-float(np.min(add["pitch"][air_m])), 1),
            "tailLowPeakDeg": r(-float(np.min(add["tail"][air_m])), 1),
            "tailHighPeakDeg": r(float(np.max(add["tail"][air_m])), 1),
            "landingSinkStuds": r(-add["hips"][sink_i]),
            "landingSinkAtSecondsAfterLanding": r(s.t[sink_i] - t_land, 3),
            "landingBounceStuds": r(max(0.0, float(np.max(add["hips"][sink_i:])))),
            "lowestToeGapAfterLanding": r(float(np.min(add["toeGap"][land_m]))),
            "lowestToeGapAfterLandingClipsAlone": r(float(np.min(add["toeGapClips"][land_m]))),
        }
    return {
        "layers": answer,
        "airSeconds": r(len(air) / fps, 3),
        "apex": r(max(f["pos"]["y"] for f in air) - take["ground"]["y"], 2),
        "studsCovered": r(abs(frames[last]["pos"]["z"] - frames[first]["pos"]["z"]), 1),
        "clip": shown,
        "clipSeconds": leap["length"],
        "clipSecondsShownInAirFrom": r(min(f["clipTime"] for f in air if f["clip"] == shown), 3),
        "clipSecondsShownInAir": r(max(f["clipTime"] for f in air if f["clip"] == shown), 3),
        "clipRateInAir": r(np.mean([f["clipRate"] for f in air if f["clip"] == shown and f["clipRate"] > 0] or [0.0])),
        "secondsFrozenOnLastPose": r(len(held) / fps, 3),
        "speedToldInAir": r(np.mean([f["speed"] for f in air]), 1),
        "speedMovedInAir": r(np.mean([f["groundSpeed"] for f in air]), 1),
        "speedMovedAfterLanding": r(np.mean([f["groundSpeed"] for f in after]), 1) if after else None,
        "speedToldAfterLanding": r(np.mean([f["speed"] for f in after]), 1) if after else None,
    }


def mount_event(take):
    frames = take["frames"]
    at = next((f["i"] for f in frames if "attach" in f["events"]), None)
    if at is None:
        return None
    fps = take["fps"]
    seen = []
    for f in frames[at:]:
        if not seen or seen[-1][0] != f["clip"]:
            seen.append([f["clip"], 0])
        seen[-1][1] += 1
        if f["clip"] == "Climb" and len(f["tracks"]) == 1:
            break
    nose = next(f["i"] for f in frames[at:] if f["pitch"] > 0.95 * max(g["pitch"] for g in frames))
    return {
        "atSeconds": r(at / fps, 3),
        "clipsWhileTaking": [[c, r(n / fps, 3)] for c, n in seen],
        "secondsUntilNoseUp": r((nose - at) / fps, 3),
        "pitchDeg": r(deg(max(g["pitch"] for g in frames)), 1),
        "peakSpeedOfTheDrawnBody": r(max(f["groundSpeed"] for f in frames[at : at + 20]), 1),
    }


def clip_use(takes):
    shown = {}
    for take in takes.values():
        for f in take["frames"]:
            shown[f["clip"]] = shown.get(f["clip"], 0) + 1
    first = next(iter(takes.values()))
    return shown, sorted(set(first["clips"]) - set(shown))


def walk_in_passing(takes):
    rows = []
    for take in takes.values():
        run = []
        for f in take["frames"]:
            if f["clip"] == "Walk":
                run.append(f)
            elif run:
                rows.append({"take": take["take"], "frames": len(run), "seconds": r(len(run) / take["fps"], 3), "speedFromTo": [r(run[0]["speed"], 1), r(run[-1]["speed"], 1)]})
                run = []
    return rows


GAITS = (
    # label, take, window
    ("Run at the walk speed", "walk", "steady"),
    ("Run at the sprint speed", "sprint", "steady"),
    ("Run after the sprint ran out", "sprint", "winded"),
    ("Stalk", "stalk", "steady"),
    ("Climb", "climb", "steady"),
    ("Wire", "wire", "steady"),
)


def measure(variant, motion, heroes, up):
    clips = mp.load_clips(os.path.join(heroes, variant, "clips"))
    rig = mp.Rig(next(iter(clips.values())).doc["bones"])
    takes = {}
    for name in ("walk", "sprint", "turn", "stop", "leap", "climb", "wire", "stalk"):
        path = os.path.join(motion, f"{variant}_{name}.json")
        if os.path.exists(path):
            takes[name] = mp.load_take(path)
    out = {"gaits": {}, "events": {}}
    for label, take, window in GAITS:
        if take in takes:
            out["gaits"][label] = gait(takes[take], clips, rig, takes[take]["windows"][window], up)
    if "turn" in takes:
        out["events"]["turn"] = turn_event(takes["turn"], takes.get("sprint"), clips, rig, up)
    if "stop" in takes:
        out["events"]["stop"] = stop_event(takes["stop"], clips, rig, up)
    if "leap" in takes:
        out["events"]["hop"] = air_event(takes["leap"], takes["leap"]["windows"]["hop"], clips, rig, up)
        out["events"]["leap"] = air_event(takes["leap"], takes["leap"]["windows"]["leap"], clips, rig, up)
    if "climb" in takes:
        out["events"]["takingTheTrunk"] = mount_event(takes["climb"])
    shown, never = clip_use(takes)
    out["clipFramesShown"] = shown
    out["clipsNeverShown"] = never
    out["walkClipInPassing"] = walk_in_passing(takes)
    any_take = next(iter(takes.values()))
    out["camera"] = any_take["camera"]
    out["bodySize"] = any_take["bodySize"]
    return out


def table(doc):
    lines = []
    for variant, m in doc["variants"].items():
        lines.append(f"== {variant}: camera {m['camera']['distance']} studs behind, {m['camera']['elevation']} rad up, FOV {m['camera']['fov']}")
        lines.append(f"{'gait':30s} {'told':>5s} {'moved':>5s} {'rate':>5s} {'cyc/s':>5s} {'st/cyc':>6s} | {'slide fore':>10s} {'hind':>6s} | {'bob hips':>8s} {'shld':>6s} | {'spine':>6s} | {'tail up/dn':>10s} {'side':>6s} | {'head bob':>8s} {'pitch':>6s} | gap fore/hind")
        for label, g in m["gaits"].items():
            fore, hind = g.get("fore", {}), g.get("hind", {})
            lines.append(
                f"{label:30s} {g['speedTold']:5.1f} {g['speedMoved']:5.1f} {g['clipRate']:5.2f} {g['cyclesPerSecond']:5.2f} {g['travelPerCycle']:6.2f} | "
                f"{fore.get('slide', float('nan')):10.2f} {hind.get('slide', float('nan')):6.2f} | {g['hipsBob']:8.3f} {g['shouldersBob']:6.3f} | {g['spineFlexDeg']:6.1f} | "
                f"{g['tailTipUpDown']:10.2f} {g['tailTipSideToSide']:6.2f} | {g['headBob']:8.3f} {g['headPitchDeg']:6.1f} | {fore.get('gap', float('nan')):.2f} / {hind.get('gap', float('nan')):.2f}"
            )
        e = m["events"]
        if "turn" in e:
            t = e["turn"]
            lines.append(f"turn: yaw rate {t['left']['yawRatePeakDegPerSec']} / {t['right']['yawRatePeakDegPerSec']} deg/s, lean {t['left']['leanPeakDeg']} / {t['right']['leanPeakDeg']} deg; "
                         f"tail trails {t['left']['tailTrailDeg']} / {t['right']['tailTrailDeg']} deg (lag {t['tailLagSeconds']} s), spine into the turn {t['left']['spineIntoDeg']} / {t['right']['spineIntoDeg']} deg, "
                         f"head into the turn {t['left']['headIntoDeg']} / {t['right']['headIntoDeg']} deg; anything answers the turn: {t['anythingAnswersTheTurn']}")
            for key in ("left", "right"):
                k = t[key]
                lines.append(f"  {key}: shoulders bank {k['shouldersBankPeakDeg']} deg at most (the drawn lean {k['leanPeakDeg']}), head roll {k['headRollPeakDeg']}; spine {k['spineIntoPeakDeg']} and head {k['headIntoPeakDeg']} deg into it at most; "
                             f"tail trails {k['tailTrailPeakDeg']} deg at most, {k['tailTrailPeakSecondsAfterYawRatePeak']} s after the turn is fastest, back {k['tailBackSecondsAfterItsPeak']} s later, swings {k['tailSwingsPastDeg']} deg past")
        if "stop" in e:
            s = e["stop"]
            lines.append(f"stop: standstill after {s['secondsToStandstill']} s and {s['studsCoveredStopping']} studs; clips {' > '.join(s['clipsOnTheWay'])}; Idle alone after {s['secondsUntilIdleAlone']} s; paws skate {s['pawSkateWhilePlanted']}")
            a = s["layers"]
            lines.append(f"  the layers: nose dips {a['noseDipPeakDeg']} deg at {a['noseDipPeakAtSeconds']} s and comes back {a['noseBackPastLevelDeg']} past level; tail lifts {a['tailLiftPeakDeg']} deg at {a['tailLiftPeakAtSeconds']} s and swings back {a['tailBackPastRestDeg']} past rest; "
                         f"hips sink {a['hipsSinkStuds']}; lowest toe {a['lowestToeGap']} from the ground (clips alone {a['lowestToeGapClipsAlone']}); settled after {a['settledAfterSeconds']} s; idle paw drift {s['idle']['pawDrift']}")
        for key in ("hop", "leap"):
            if e.get(key):
                a = e[key]
                lines.append(f"{key}: {a['airSeconds']} s in the air, apex {a['apex']}, {a['studsCovered']} studs; {a['clip']} clip {a['clipSeconds']} s, shown from {a['clipSecondsShownInAirFrom']} to {a['clipSecondsShownInAir']} s at x{a['clipRateInAir']}, frozen {a['secondsFrozenOnLastPose']} s; "
                             f"moved {a['speedMovedInAir']} st/s, told {a['speedToldInAir']}; after landing moved {a['speedMovedAfterLanding']}, told {a['speedToldAfterLanding']}")
                if a.get("layers"):
                    k = a["layers"]
                    lines.append(f"  the layers: nose up {k['noseUpPeakDeg']} deg rising, down {k['noseDownPeakDeg']} falling; tail low {k['tailLowPeakDeg']} then high {k['tailHighPeakDeg']} deg; landing sinks the hips {k['landingSinkStuds']} at {k['landingSinkAtSecondsAfterLanding']} s, bounce {k['landingBounceStuds']}; "
                                 f"lowest toe after landing {k['lowestToeGapAfterLanding']} (clips alone {k['lowestToeGapAfterLandingClipsAlone']})")
        if e.get("takingTheTrunk"):
            k = e["takingTheTrunk"]
            lines.append(f"taking the trunk: clips {k['clipsWhileTaking']}, nose up after {k['secondsUntilNoseUp']} s")
        lines.append(f"clips never shown: {', '.join(m['clipsNeverShown']) or 'none'}; Walk only in passing: {m['walkClipInPassing']}")
    return "\n".join(lines)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--motion", default="build/motion")
    ap.add_argument("--heroes", default="build/heroes")
    ap.add_argument("--variants", default="squirrel,rodent")
    ap.add_argument("--out", default=None)
    ap.add_argument("--upsample", type=int, default=4)
    opts = ap.parse_args(argv)
    t0 = time.time()
    doc = {
        "format": "spicy-motion-metrics/1",
        "units": "studs, seconds, degrees where a name says Deg; slide is studs per stance",
        "plantedWithin": PLANT,
        "variants": {},
    }
    for variant in [v for v in opts.variants.split(",") if v]:
        doc["variants"][variant] = measure(variant, opts.motion, opts.heroes, opts.upsample)
    out = opts.out or os.path.join(opts.motion, "metrics.json")
    with open(out, "w") as fh:
        json.dump(doc, fh, indent=1)
    print(table(doc))
    print(f"motion_metrics: wrote {out} in {time.time() - t0:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
