"""Fill tools/cloud/tasks/heroes_check.luau's constants from data/art/heroes.json and write the runnable
copy to build/heroes/heroes_check.luau.

  python3 -I tools/blender/heroes/check_task.py [--variant squirrel] [--clips Run,Pounce]
"""
import argparse
import json
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="squirrel")
    ap.add_argument("--clips", default="Run,Pounce")
    a = ap.parse_args()
    with open(os.path.join(ROOT, "data/art/heroes.json")) as fh:
        doc = json.load(fh)
    sp = doc["species"][a.variant]
    src = open(os.path.join(ROOT, "tools/cloud/tasks/heroes_check.luau")).read()
    clips = ", ".join(f"{c} = {sp['clips'][c]['assetId']}" for c in a.clips.split(","))
    socks = ", ".join(
        f'{n} = {{ bone = "{s["bone"]}", offset = {{ {s["offset"][0]}, {s["offset"][1]}, {s["offset"][2]} }} }}'
        for n, s in sp["sockets"].items()
    )
    src = re.sub(r"local MODEL_ID = 0 -- @@MODEL_ID@@", f"local MODEL_ID = {sp['model']['assetId']}", src)
    src = re.sub(r"local CLIPS = \{ Run = 0, Pounce = 0 \} -- @@CLIPS@@", f"local CLIPS = {{ {clips} }}", src)
    src = src.replace("local SOCKETS = {} :: { [string]: { bone: string, offset: { number } } } -- @@SOCKETS@@",
                      f"local SOCKETS = {{ {socks} }} :: {{ [string]: {{ bone: string, offset: {{ number }} }} }}")
    src = src.replace('model.Name = "squirrel"', f'model.Name = "{a.variant}"')
    out = os.path.join(ROOT, "build/heroes/heroes_check.luau")
    with open(out, "w") as fh:
        fh.write(src)
    print(out)


if __name__ == "__main__":
    main()
