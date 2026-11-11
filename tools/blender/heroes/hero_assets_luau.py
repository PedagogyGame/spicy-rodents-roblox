"""Write src/shared/Actors/HeroAssets.luau from data/art/heroes.json (run after publish.py).

  python3 -I tools/blender/heroes/hero_assets_luau.py

tests/unit/hero_art.spec.luau fails when the Luau table and the JSON disagree.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
HEADER = '''--!strict
-- ReplicatedStorage.Shared.Actors.HeroAssets
-- The uploaded skinned hero models the game may show in place of the part-built puppets: asset ids, the
-- height of the game's root over the model's feet, each region's SurfaceAppearance mode (and a stock tint,
-- when one is not baked into the colour map), and the sockets to add under the bones. WRITTEN BY
-- tools/blender/heroes/hero_assets_luau.py FROM data/art/heroes.json (publish.py fills that file on
-- upload); tests/unit/hero_art.spec.luau fails when the two disagree.
-- Interface: SPECIES: { [templateName]: Entry } (templateName: "squirrel" | "rodent");
--   CLIPS: { [rig]: { [clipName]: Clip } } (rig "squirrel": Idle, Walk, Run, Climb, Wire, Leap, Pounce, Bite, Stalk).

export type Region = { alphaMode: string, tint: string? }
export type Socket = { bone: string, offset: { number } }
export type Clip = { id: string, length: number, loop: boolean }
export type Entry = {
	assetId: number,
	hipHeight: number,
	regions: { [string]: Region },
	sockets: { [string]: Socket },
}

local HeroAssets = {}

HeroAssets.SPECIES = {
'''


def num(x):
    x = float(x)
    if x == 0:
        return "0"
    return repr(x).rstrip("0").rstrip(".") if "." in repr(x) else repr(x)


def main():
    with open(os.path.join(ROOT, "data/art/heroes.json")) as fh:
        doc = json.load(fh)
    out = [HEADER.rstrip("\n")]
    for name in ("squirrel", "rodent"):
        s = doc["species"][name]
        out.append(f"\t{name} = {{")
        out.append(f"\t\tassetId = {s['model']['assetId']},")
        out.append(f"\t\thipHeight = {num(s.get('hipHeight', 0.9))},")
        out.append("\t\tregions = {")
        for rn in sorted(s["regions"]):
            r = s["regions"][rn]
            tint = f', tint = "{r["tint"]}"' if r.get("tint") else ""
            out.append(f'\t\t\t{rn} = {{ alphaMode = "{r["alphaMode"]}"{tint} }},')
        out.append("\t\t},")
        out.append("\t\tsockets = {")
        for sn in sorted(s["sockets"]):
            k = s["sockets"][sn]
            o = ", ".join(num(x) for x in k["offset"])
            out.append(f'\t\t\t{sn} = {{ bone = "{k["bone"]}", offset = {{ {o} }} }},')
        out.append("\t\t},")
        out.append("\t},")
    out.append("} :: { [string]: Entry }")
    out.append("")
    out.append("-- The squirrel rig's animation clips (the rodent shares them): asset id, seconds, whether it loops.")
    out.append("HeroAssets.CLIPS = {")
    out.append("\tsquirrel = {")
    clips = doc["species"]["squirrel"]["clips"]
    for k in sorted(clips):
        v = clips[k]
        out.append(
            f'\t\t{k} = {{ id = "rbxassetid://{v["assetId"]}", length = {round(v["duration"], 4)}, loop = {"true" if v["loop"] else "false"} }},'
        )
    out.append("\t},")
    out.append("} :: { [string]: { [string]: Clip } }")
    out.append("")
    out.append("return HeroAssets")
    path = os.path.join(ROOT, "src/shared/Actors/HeroAssets.luau")
    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")
    print(path)


if __name__ == "__main__":
    main()
