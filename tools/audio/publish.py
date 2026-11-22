"""The game's audio uploads: check the candidates, then record the ids the lead got (stdlib only).

  python3 -I tools/audio/publish.py --skip-upload              (check every candidate; print the lead's upload commands)
  python3 -I tools/audio/publish.py --record dog_bark=123456789 [--moderation Approved] [--approve] [--take dog_bark_v2]

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
A second take of a slot (a candidate with "replaces": "<slot>", e.g. dog_bark_v2) has its own file and sha and waits
in the manifest beside the take in the game. --record <slot>=<assetId> records the id onto the slot's one waiting
take (or onto the candidate --take names) and points the slot in Uploads.luau at that take's file as well; the
earlier take keeps its old id in the manifest, the record of that upload.
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


def slot_of(c):
    """The Uploads.luau slot a candidate is a take for: its own, or the one it replaces."""
    return c.get("replaces") or c["slot"]


def slot_block(luau, slot):
    m = re.search(r"\b" + re.escape(slot) + r" = table\.freeze\(\{(.*?)\}\),\n", luau, re.S)
    return m.group(1) if m else None


def check(doc):
    """Every candidate: its file exists, is mono Vorbis, short, small, the length the manifest says; and it is a
    take for a slot in Shared/Audio/Uploads with the same cues. Each slot names one of its takes' files, and the
    slot's id is that take's."""
    with open(UPLOADS_LUAU) as fh:
        luau = fh.read()
    problems = []
    live = {}
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
        block = slot_block(luau, slot_of(c))
        in_game = False
        if block is None:
            problems.append(f"{c['slot']}: no slot {slot_of(c)} in src/shared/Audio/Uploads.luau")
        elif any(f'"{cue}"' not in block for cue in c["cues"]):
            problems.append(f"{c['slot']}: the Uploads.luau slot {slot_of(c)} names other cues")
        elif f'file = "{c["file"]}"' in block:
            in_game = True
            live[slot_of(c)] = c
            if f'id = "{c.get("assetId") or ""}"' not in block:
                problems.append(f"{c['slot']}: the Uploads.luau slot's id is not this take's ({c.get('assetId')})")
        state = "uploaded " + c["assetId"] if c.get("assetId") else "to upload"
        if c.get("replaces"):
            state += f"; a take for {c['replaces']}" + ("" if in_game else ", not in the game yet")
        elif not in_game:
            state += "; replaced in the game by a later take"
        level = f"{lo[0]:5.1f} LUFS {lo[1]:5.1f} dBTP" if lo else "unmeasured"
        print(f"  {c['slot']:14s} {secs:5.2f} s {size:7d} B  {level}  cues {', '.join(c['cues'])}  ({state})")
    for slot in sorted({slot_of(c) for c in doc["candidates"]} - set(live)):
        if slot_block(luau, slot) is not None:
            problems.append(f"{slot}: the Uploads.luau slot's file is none of its takes in the manifest")
    return problems


def record(doc, slot, asset_id, moderation, approve, take=None):
    """The id onto the take uploaded (--take's; else the slot's one waiting second take; else the slot's own row),
    then the slot in Uploads.luau gets that id and that take's file."""
    if not re.fullmatch(r"\d{5,20}", asset_id):
        sys.exit(f"--record {slot}={asset_id}: an asset id is digits")
    family = [c for c in doc["candidates"] if slot_of(c) == slot]
    if not family:
        sys.exit(f"--record: no candidate for slot {slot}")
    if take:
        rows = [c for c in family if c["slot"] == take]
    else:
        rows = [c for c in family if c.get("replaces") and not c.get("assetId")]
        if len(rows) > 1:
            sys.exit(f"--record {slot}: takes {', '.join(c['slot'] for c in rows)} are waiting; name one with --take")
        rows = rows or [c for c in family if c["slot"] == slot]
    if not rows:
        sys.exit(f"--record {slot}: {take} is not one of its takes")
    row = rows[0]
    with open(UPLOADS_LUAU) as fh:
        luau = fh.read()
    pat = re.compile(r"(\b" + re.escape(slot) + r" = table\.freeze\(\{\n\t\tid = \")(\d*)"
                     r"(\",\n\t\tfile = \")([^\"]*)(\")")
    if not pat.search(luau):
        sys.exit(f"--record: slot {slot} not found in src/shared/Audio/Uploads.luau")
    row["assetId"] = asset_id
    row["moderation"] = moderation
    row["approved"] = approve or row.get("approved", False)
    save(doc)
    luau = pat.sub(lambda m: m.group(1) + asset_id + m.group(3) + row["file"] + m.group(5), luau, count=1)
    with open(UPLOADS_LUAU, "w") as fh:
        fh.write(luau)
    print(f"recorded {slot} = {asset_id} ({moderation}; take {row['slot']}, {row['file']}) in the manifest and "
          "src/shared/Audio/Uploads.luau; add it to docs/AUDIO_BUDGET.md's upload tally")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-upload", action="store_true", help="only check the candidates (the default anyway)")
    ap.add_argument("--record", action="append", default=[], help="slot=assetId, after the lead's upload")
    ap.add_argument("--moderation", default="Pending")
    ap.add_argument("--approve", action="store_true", help="the take was heard and approved before upload")
    ap.add_argument("--take", default=None, help="with --record: the candidate uploaded (default: the slot's one "
                    "waiting second take, else the slot's own)")
    a = ap.parse_args()
    doc = load()
    problems = check(doc)
    if problems:
        sys.exit("candidates not ready:\n  " + "\n  ".join(problems))
    for r in a.record:
        slot, _, asset_id = r.partition("=")
        record(doc, slot, asset_id, a.moderation, a.approve, a.take)
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
            f"  python3 -I tools/audio/publish.py --record {slot_of(c)}=<assetId> --moderation <state> --approve"
            + (f" --take {c['slot']}" if c.get("replaces") else ""))


if __name__ == "__main__":
    main()
