"""The game's audio uploads: check the candidates, then record the ids the lead got (stdlib only).

  python3 -I tools/audio/publish.py --skip-upload              (check every candidate; list what would go up)
  python3 -I tools/audio/publish.py --record dog_bark=123456789 [--moderation Approved] [--approve]

Mirrors tools/blender/neighbourhood_shop/publish.py: the manifest (assets/audio/candidates/manifest.json, written
by tools/audio/make_candidates.py) holds each candidate's file, length and content hash (sha), and after the upload
its assetId and moderation state; a candidate whose sha has changed since its id was recorded is a new take and
needs a new upload. The upload itself is the lead's, by hand: tools/cloud's upload_asset deliberately does not
expose audio (the monthly cap; D24), and nothing here calls tools/cloud or any network. Upload only a take that
has been heard and approved (BRIEF_ADDENDUM B3), and count it in docs/AUDIO_BUDGET.md "Uploads".
--record writes the id into the manifest and into src/shared/Audio/Uploads.luau (the slot's `id = "..."`), which
is all the game reads: the cue sounds from then on.
"""
import argparse
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
        m = re.search(r"\b" + re.escape(c["slot"]) + r" = table\.freeze\(\{(.*?)\}\),\n", luau, re.S)
        if m is None:
            problems.append(f"{c['slot']}: no slot in src/shared/Audio/Uploads.luau")
        elif f'file = "{c["file"]}"' not in m.group(1) or any(f'"{cue}"' not in m.group(1) for cue in c["cues"]):
            problems.append(f"{c['slot']}: the Uploads.luau slot names another file or other cues")
        state = "uploaded " + c["assetId"] if c.get("assetId") else "to upload"
        print(f"  {c['slot']:14s} {secs:5.2f} s {size:7d} B  cues {', '.join(c['cues'])}  ({state})")
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
        todo = [c["slot"] for c in doc["candidates"] if not c.get("assetId")]
        print(f"{len(doc['candidates'])} candidates, {len(todo)} to upload by hand"
              + (f": {', '.join(todo)}" if todo else "") + " (tools/cloud does not upload audio; nothing uploaded)")


if __name__ == "__main__":
    main()
