"""Numbers for the squirrel's motion as the game shows it (system python3 or the bpy venv; numpy only).

  lune run tools/review/motion_path.luau                              # build/motion/<variant>_<take>.json
  python3 -I tools/blender/heroes/motion_metrics.py [--motion build/motion] [--heroes build/heroes] \
      [--variants squirrel,rodent] [--out build/motion/metrics.json] [--upsample 4]

Every number is measured on the takes: the body where the motor and the drawn pose put it, the clip the
driver chose at the rate it chose (tracks crossing over are mixed), the layers multiplied on, the joints
through the exported clips (motion_pose.py). Frames are 1/60 s apart; between two frames everything is
taken in a straight line (`--upsample` points per frame) so a stance of three frames is still measured.

Per gait (a take's steady stretch): what the animation is told and what the body does; the clip, its rate,
the cycle's period and the ground covered in one cycle; per paw the stance (planted: the paw's joint within
PLANT studs of where it rests) with how long it lasts, how far the body travels meanwhile, how far the clip
moves the paw back under the body meanwhile, and the SLIDE: how far the planted paw drifts over the ground
(studs per stance; 0 is a paw that stays where it was put); the bob of hips and shoulders; the spine's flex
(the chest against the pelvis, nose-down/up and side to side, degrees, range over the stretch); the tail
tip's swing in the body's own frame; the head's bob, pitch, yaw and roll ranges. Paw joints are the ball of
the hind foot and the knuckles of the fore paw; `gap` is how far the lowest of them stays from the surface
(ground, bark or wire).
Per event: the turn (yaw rate, lean, and whether tail, spine or head answer it: each is compared with the
straight run before it), the stop, the hop and the leap (what the Leap clip shows against what the body
does), taking the trunk.
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
        self.W, self.body = [], []
        for f in self.frames:
            self.t.append(f["t"])
            self.W.append(rig.fk(mp.frame_pose(clips, f)))
            self.body.append(mp.body_frame(f))
        self.t = np.array(self.t)

    def model(self, fn):
        """(n, 3): a point per sample in the model's frame; fn(W) -> point."""
        return np.array([fn(W) for W in self.W])

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
    # planted: the paw is down on the plane the body stands on (its height in the body's own frame is at
    # its lowest); the gap is how far that leaves it from the real surface
    planted = planted_mask(toe_model[:, 1], s.dt)
    gaps = np.array([gap_fn(q) for q in toe])
    runs = stances(planted)
    feet = np.array([p for _, p in s.body])
    out = {
        "gap": r(gaps[planted].mean()),
        "gapLeast": r(gaps.min()),
        "lift": r(span(toe_model[:, 1])),
        "plantedShare": r(float(planted.mean()), 2),
        "stances": len(runs),
    }
    if not runs:
        return out
    slide, path, secs, body, clip = [], [], [], [], []
    for a, b in runs:
        slide.append(np.linalg.norm(toe[b] - toe[a]))
        path.append(np.sum(np.linalg.norm(np.diff(toe[a : b + 1], axis=0), axis=1)))
        secs.append((b - a) * s.dt)
        body.append(np.linalg.norm(feet[b] - feet[a]))
        clip.append(np.linalg.norm(toe_model[b] - toe_model[a]))
    out.update(
        stanceSeconds=r(np.mean(secs), 4),
        slide=r(np.mean(slide)),
        slideMax=r(np.max(slide)),
        slidePath=r(np.mean(path)),
        slideSpeed=r(np.mean(slide) / max(np.mean(secs), 1e-9), 2),
        bodyTravelInStance=r(np.mean(body)),
        clipTravelInStance=r(np.mean(clip)),
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
    }, {"tailSide": tail_side, "spineSide": np.degrees(spine[:, 1]), "headYaw": np.degrees(headR[:, 1])}


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
            out[pair] = {k: r(np.mean([g[k] for g in got]), 4 if k == "stanceSeconds" else 3) for k in ("slide", "stanceSeconds", "bodyTravelInStance", "clipTravelInStance")}
            out[pair]["gap"] = r(min(out["paws"][leg]["gap"] for leg in legs))
    out["footSlide"] = r(np.mean([out[p]["slide"] for p in ("fore", "hind") if p in out])) if ("fore" in out or "hind" in out) else None
    post, _ = posture(s)
    out.update(post)
    return out


# ---- events --------------------------------------------------------------------------------------------

def turn_event(take, clips, rig, up):
    w = take["windows"]
    out = {}
    series = {}
    for key in ("straight", "left", "right"):
        s = Samples(take, clips, rig, w[key][0], w[key][1], up)
        post, ser = posture(s)
        yaw = np.unwrap(s.col("yaw"))
        rate = np.gradient(yaw, s.dt)
        series[key] = ser
        out[key] = {
            "yawRateDegPerSec": r(deg(np.mean(rate)), 1),
            "yawRatePeakDegPerSec": r(deg(rate[np.argmax(np.abs(rate))]), 1),
            "leanPeakDeg": r(deg(s.col("roll")[np.argmax(np.abs(s.col("roll")))]), 1),
            "tailSideMeanDeg": r(np.mean(ser["tailSide"]), 2),
            "spineSideMeanDeg": r(np.mean(ser["spineSide"]), 2),
            "headYawMeanDeg": r(np.mean(ser["headYaw"]), 2),
        }
    # what answers the turn: each mean against the straight run's (a tail that trails a left turn swings
    # to the body's right, + here; a spine or head that leads it bends to the left, -)
    base = out["straight"]
    out["tailLagDeg"] = {k: r(out[k]["tailSideMeanDeg"] - base["tailSideMeanDeg"], 2) for k in ("left", "right")}
    out["spineBendIntoTurnDeg"] = {k: r(out[k]["spineSideMeanDeg"] - base["spineSideMeanDeg"], 2) for k in ("left", "right")}
    out["headLeadDeg"] = {k: r(out[k]["headYawMeanDeg"] - base["headYawMeanDeg"], 2) for k in ("left", "right")}
    # how long after the body's heading the tail's follows it: the tail is rigid on the body unless a layer
    # moves it, so its world heading is the body's plus its swing; the lag is the shift (in frames) that
    # best lines the tail's world heading up with the body's over the whole turn
    s = Samples(take, clips, rig, w["turning"][0], w["turning"][1], 1)
    _, ser = posture(s)
    body = np.degrees(np.unwrap(s.col("yaw")))
    tail_world = body - ser["tailSide"]
    best, best_err = 0, None
    for shift in range(0, 20):
        a, b = tail_world[shift:], body[: len(body) - shift]
        err = float(np.mean((a - b - np.mean(a - b)) ** 2))
        if best_err is None or err < best_err - 1e-9:
            best, best_err = shift, err
    out["tailLagSeconds"] = r(best / take["fps"], 3)
    return out


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
        height = s.model(s.joint(f"{leg}_Toe"))[:, 1]
        planted = planted_mask(height, s.dt)
        step = np.linalg.norm(np.diff(toe, axis=0), axis=1)
        skate[leg] = r(float(np.sum(step[planted[1:] & planted[:-1]])))
    clips_seen = []
    for f in frames[i0 : idle + 1]:
        if not clips_seen or clips_seen[-1] != f["clip"]:
            clips_seen.append(f["clip"])
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
        "idle": {"pawDrift": r(drift), **{k: post[k] for k in ("hipsBob", "headBob", "headYawDeg", "tailTipUpDown", "tailTipSideToSide", "spineFlexDeg")}},
    }


def air_event(take, window):
    frames = take["frames"]
    fps = take["fps"]
    i0, i1 = int(round(window[0] * fps)), int(round(window[1] * fps))
    air = [f for f in frames[i0 : i1 + 1] if f["mode"] == "air"]
    if not air:
        return None
    first, last = air[0]["i"], air[-1]["i"]
    leap = take["clips"]["Leap"]
    held = [f for f in air if f["clipRate"] == 0]
    after = frames[min(last + 1, len(frames) - 1) : min(last + 13, len(frames))]
    return {
        "airSeconds": r(len(air) / fps, 3),
        "apex": r(max(f["pos"]["y"] for f in air) - take["ground"]["y"], 2),
        "studsCovered": r(abs(frames[last]["pos"]["z"] - frames[first]["pos"]["z"]), 1),
        "clip": air[len(air) // 2]["clip"],
        "clipSeconds": leap["length"],
        "clipSecondsShownInAir": r(max(f["clipTime"] for f in air), 3),
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
        out["events"]["turn"] = turn_event(takes["turn"], clips, rig, up)
    if "stop" in takes:
        out["events"]["stop"] = stop_event(takes["stop"], clips, rig, up)
    if "leap" in takes:
        out["events"]["hop"] = air_event(takes["leap"], takes["leap"]["windows"]["hop"])
        out["events"]["leap"] = air_event(takes["leap"], takes["leap"]["windows"]["leap"])
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
                         f"tail lag {t['tailLagDeg']['left']} / {t['tailLagDeg']['right']} deg ({t['tailLagSeconds']} s), spine bend {t['spineBendIntoTurnDeg']['left']} / {t['spineBendIntoTurnDeg']['right']} deg, "
                         f"head lead {t['headLeadDeg']['left']} / {t['headLeadDeg']['right']} deg")
        if "stop" in e:
            s = e["stop"]
            lines.append(f"stop: standstill after {s['secondsToStandstill']} s and {s['studsCoveredStopping']} studs; clips {' > '.join(s['clipsOnTheWay'])}; Idle alone after {s['secondsUntilIdleAlone']} s; paws skate {s['pawSkateWhilePlanted']}")
        for key in ("hop", "leap"):
            if e.get(key):
                a = e[key]
                lines.append(f"{key}: {a['airSeconds']} s in the air, apex {a['apex']}, {a['studsCovered']} studs; {a['clip']} clip {a['clipSeconds']} s, shown to {a['clipSecondsShownInAir']} s, frozen {a['secondsFrozenOnLastPose']} s; "
                             f"moved {a['speedMovedInAir']} st/s, told {a['speedToldInAir']}; after landing moved {a['speedMovedAfterLanding']}, told {a['speedToldAfterLanding']}")
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
