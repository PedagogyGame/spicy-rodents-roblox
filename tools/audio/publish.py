"""The game's audio uploads: check the candidates, then record the ids the lead got (stdlib only).

  python3 -I tools/audio/publish.py --skip-upload              (check every candidate; print the lead's upload commands)
  python3 -I tools/audio/publish.py --record dog_bark=123456789 [--moderation Approved] [--approve]

Mirrors tools/blender/neighbourhood_shop/publish.py: the manifest (assets/audio/candidates/manifest.json, written
by tools/audio/make_candidates.py) holds each candidate's file, length, loudness, true peak and content hash (sha),
and after the upload its assetId and moderation state; a candidate whose sha has changed since its id was recorded
is a new take and needs a new upload. The check measures each file again (ffmpeg's EBU R128 meter): its sha is the
manifest's, it is -16 to -14 LUFS integrated and at most -1 dBTP. The upload itself is the lead's: --skip-upload
prints the command (tools/cloud upload_asset --type Audio, behind its audio-budget flag); nothing here calls
tools/cloud or any network. Upload only a take that has been heard and approved (BRIEF_ADDENDUM B3), and count it
in docs/AUDIO_BUDGET.md "Uploads".
--record writes the id into the manifest and into src/shared/Audio/Uploads.luau (the slot's `id = "..."`), which
is all the game reads: the cue sounds from then on.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MANIFEST = os.path.join(ROOT, "assets", "audio", "candidates", "manifest.json")
UPLOADS_LUAU = os.path.join(ROOT, "src", "shared", "Audio", "Uploads.luau")
MAX_SECONDS = 7  # Roblox's sound-effect length is far longer; these are short cues
MAX_BYTES = 2_000_000
LUFS_RANGE = (-16.0, -14.0)  # short effects, level with the game's other sounds
MAX_TRUE_PEAK = -1.0  # dBTP


def load():
    with open(MANIFEST) as fh:
        return json.load(fh)


def save(doc):
    with open(MANIFEST, "w") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")


def probe(path):
    """(seconds, channels, codec) of an audio file, by ffprobe."""
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,channels:format=duration",
                        "-of", "json", path], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    j = json.loads(r.stdout)
    st = (j.get("streams") or [{}])[0]
    return float(j.get("format", {}).get("duration", 0)), st.get("channels"), st.get("codec_name")


def loudness(path):
    """(integrated LUFS, true peak dBTP) of an audio file, by ffmpeg's EBU R128 meter."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null",
                        "-"], capture_output=True, text=True)
    i = re.findall(r"I:\s+(-?[\d.]+) LUFS", r.stderr)
    tp = re.findall(r"Peak:\s+(-?[\d.]+) dBFS", r.stderr)
    if r.returncode != 0 or not i or not tp:
        return None
    return float(i[-1]), float(tp[-1])


def check(doc):
    """Every candidate: its file exists, is mono Vorbis, short, small, the length the manifest says; and it has a
    slot in Shared/Audio/Uploads naming the same file and cues."""
    with open(UPLOADS_LUAU) as fh:
        luau = fh.read()
    problems = []
    for c in doc["candidates"]:
        path = os.path.join(ROOT, c["file"])
        if not os.path.exists(path):
            problems.append(f"{c['slot']}: {c['file']} is missing (run tools/audio/make_candidates.py)")
            continue
        size = os.path.getsize(path)
        p = probe(path)
        if p is None:
            problems.append(f"{c['slot']}: ffprobe cannot read {c['file']}")
            continue
        secs, channels, codec = p
        if channels != 1 or codec != "vorbis":
            problems.append(f"{c['slot']}: {channels} channels, {codec} (want mono vorbis)")
        if secs > MAX_SECONDS or abs(secs - c["seconds"]) > 0.05:
            problems.append(f"{c['slot']}: {secs:.2f} s (manifest {c['seconds']} s, at most {MAX_SECONDS})")
        if size > MAX_BYTES:
            problems.append(f"{c['slot']}: {size} bytes")
        with open(path, "rb") as fh:
            sha = hashlib.sha256(fh.read()).hexdigest()[:16]
        if sha != c.get("sha"):
            problems.append(f"{c['slot']}: the file's sha {sha} is not the manifest's {c.get('sha')} (remake it)")
        lo = loudness(path)
        if lo is None:
            problems.append(f"{c['slot']}: ffmpeg cannot measure {c['file']}")
        else:
            lufs, tp = lo
            if not (LUFS_RANGE[0] <= lufs <= LUFS_RANGE[1]) or tp > MAX_TRUE_PEAK:
                problems.append(f"{c['slot']}: {lufs} LUFS, {tp} dBTP (want {LUFS_RANGE[0]} to {LUFS_RANGE[1]} "
                                f"LUFS, at most {MAX_TRUE_PEAK} dBTP)")
        m = re.search(r"\b" + re.escape(c["slot"]) + r" = table\.freeze\(\{(.*?)\}\),\n", luau, re.S)
        if m is None:
            problems.append(f"{c['slot']}: no slot in src/shared/Audio/Uploads.luau")
        elif f'file = "{c["file"]}"' not in m.group(1) or any(f'"{cue}"' not in m.group(1) for cue in c["cues"]):
            problems.append(f"{c['slot']}: the Uploads.luau slot names another file or other cues")
        state = "uploaded " + c["assetId"] if c.get("assetId") else "to upload"
        level = f"{lo[0]:5.1f} LUFS {lo[1]:5.1f} dBTP" if lo else "unmeasured"
        print(f"  {c['slot']:14s} {secs:5.2f} s {size:7d} B  {level}  cues {', '.join(c['cues'])}  ({state})")
    return problems


def record(doc, slot, asset_id, moderation, approve):
    if not re.fullmatch(r"\d{5,20}", asset_id):
        sys.exit(f"--record {slot}={asset_id}: an asset id is digits")
    rows = [c for c in doc["candidates"] if c["slot"] == slot]
    if not rows:
        sys.exit(f"--record: no candidate {slot}")
    rows[0]["assetId"] = asset_id
    rows[0]["moderation"] = moderation
    rows[0]["approved"] = approve or rows[0].get("approved", False)
    save(doc)
    with open(UPLOADS_LUAU) as fh:
        luau = fh.read()
    pat = re.compile(r"(\b" + re.escape(slot) + r" = table\.freeze\(\{\n\t\tid = \")(\d*)(\")")
    if not pat.search(luau):
        sys.exit(f"--record: slot {slot} not found in src/shared/Audio/Uploads.luau")
    luau = pat.sub(lambda m: m.group(1) + asset_id + m.group(3), luau, count=1)
    with open(UPLOADS_LUAU, "w") as fh:
        fh.write(luau)
    print(f"recorded {slot} = {asset_id} ({moderation}) in the manifest and src/shared/Audio/Uploads.luau; "
          "add it to docs/AUDIO_BUDGET.md's upload tally")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-upload", action="store_true", help="only check the candidates (the default anyway)")
    ap.add_argument("--record", action="append", default=[], help="slot=assetId, after the lead's upload")
    ap.add_argument("--moderation", default="Pending")
    ap.add_argument("--approve", action="store_true", help="the take was heard and approved before upload")
    a = ap.parse_args()
    doc = load()
    problems = check(doc)
    if problems:
        sys.exit("candidates not ready:\n  " + "\n  ".join(problems))
    for r in a.record:
        slot, _, asset_id = r.partition("=")
        record(doc, slot, asset_id, a.moderation, a.approve)
    if not a.record:
        todo = [c for c in doc["candidates"] if not c.get("assetId")]
        print(f"{len(doc['candidates'])} candidates, {len(todo)} to upload (nothing uploaded here)"
              + (": the lead's commands, after listening and checking docs/AUDIO_BUDGET.md's tally:" if todo else ""))
        for c in todo:
            print(upload_command(c))


def upload_command(c):
    """The lead's upload of one candidate, then the record of its id."""
    def q(s):
        return "'" + s.replace("'", "'\\''") + "'"
    return (f"  node tools/cloud/cloud.mjs upload_asset {c['file']} --type Audio --name {q(c['displayName'])} "
            f"--description {q(c['description'])} --i-am-within-audio-budget --out build/audio/{c['slot']}.upload.json\n"
            f"  python3 -I tools/audio/publish.py --record {c['slot']}=<assetId> --moderation <state> --approve")


if __name__ == "__main__":
    main()
