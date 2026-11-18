# builds page/index.html for the Artifact from the repo's dump and guide numbers
import json, sys, html
D = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
T = D["tables"]
def rgbhex(c): return "#%02x%02x%02x" % tuple(c)
LAMP = {"red": (255, 60, 50), "green": (80, 255, 110), "amber": (255, 170, 40), "yellow": (255, 236, 70),
        "orange": (255, 130, 30), "white": (255, 250, 235), "blue": (80, 150, 255)}
MACH = [
 ("acorn", "pinball_acorn", "ACORN ATTACK", "Right-hand machine, facing them", "The gentle old electro-mechanical one",
  "Fill the hoard with acorns before winter.",
  "Walnut cabinet with brass trim, a tan playfield, amber plastics, rust-red bumpers. Backglass: an autumn sun over an oak.",
  ["Three top lanes under the arch, between four wire guides",
   "Three pop bumpers",
   "The A-C-O-R-N bank: five drop targets on the left, set at a slant facing down the table, with a rubber and a wooden wall behind",
   "A spinner lane up the right side",
   "Two OAK standup targets with wedge-shaped wooden backs, either side of the low bumper",
   "A rebound rubber across the left of the arch",
   "Curved rail guides that turn a ball into the inlanes",
   "Lamps: THE HOARD (five orange), bonus 2X / 3X / 5X, a green lamp beside each letter, EXTRA BALL, SHOOT AGAIN"],
  "A, C, O, R, N, THE HOARD, 2X / 3X / 5X, SPIN, OAK, EXTRA BALL, SHOOT AGAIN, and FILL THE HOARD BEFORE WINTER across the middle"),
 ("rodent", "pinball_rodent", "SPICY RODENT", "Middle machine", "The fast, hungry one",
  "Feed the rodent until it goes SUPER.",
  "Near-black cabinet with red trim, a deep red playfield, orange plastics, yellow bumpers. Backglass: a heat glow rising.",
  ["THE WIRE: one long ramp. Wide mouth middle-left (for the right flipper), climbs to 0.3 high, curves round the top, comes down the right side and drops the ball into the right inlane. Heights at each bend are marked h on the plan",
   "THE BITE: a kick-out hole top right inside a metal horseshoe that opens toward the lower left; it holds the ball, then kicks it back down the table",
   "The HOT LANE up the right side: a soft plunge rolls down it for the skill shot",
   "The nest: three pop bumpers top left",
   "S-P-I-C-Y standup targets: S and P on the left, I in the centre (with a pointed back), C and Y on the right",
   "Lamps: a HEAT meter of nine up the middle (yellow, orange, red) with CALM, FERAL, RABID, SUPER"],
  "CLIMB TO SUPER, THE WIRE, THE BITE, HOT LANE, EXTRA BALL, SHOOT AGAIN, and the letters"),
 ("space", "pinball_space", "SPACE SQUIRREL", "Left-hand machine, facing them", "The flow table",
  "Fuel the rocket, lock two balls, LIFTOFF into a three-ball multiball.",
  "Deep blue cabinet with silver trim, a navy playfield, ice-blue plastics, violet bumpers, green targets. Backglass: a ringed planet.",
  ["Two ramps that feed each other: the left ramp (shot from the right flipper) drops into the left inlane, the right ramp mirrors it. Both rise to 0.3 and run down the outside of the table",
   "The ORBIT: a lane right round under the arch inside a curved metal guide, with switches at both ends and at the top",
   "The DOCKING GAP: an opening in the orbit guide, top right, that a soft plunge falls through (the skill shot)",
   "Asteroid field: three pop bumpers inside the orbit",
   "Two LOCK PODS: holes in the floor of the orbit lanes beside the ramps; only a ball going up the table drops in. Their hood is not built yet: design one, on the side toward the top of the table, so a ball coming down rides over it",
   "The F-U-E-L standup targets at the corners of the two ramp mouths",
   "Lamps: countdown 3-2-1, five COMBO, JACKPOT, ramps, orbits, locks"],
  "COUNTDOWN TO MULTIBALL, LAUNCH, COMBO, JACKPOT, ORBIT, RAMP, LOCK, SHOOT AGAIN, and the letters"),
]
THEME_KEYS = [("body", "Cabinet"), ("trim", "Trim and rails"), ("field", "Playfield"), ("plastic", "Plastics and ramps"),
              ("bumper", "Bumper body"), ("cap", "Bumper cap"), ("target", "Targets"), ("apron", "Apron"), ("ink", "Lettering"), ("glow", "Light strip")]

def names_table(tid):
    t = T[tid]
    rows = []
    for i, f in enumerate(t["flippers"], 1):
        rows.append((f"Flipper{i}", f"{'Left' if f['button']=='left' else 'Right'} flipper: a group whose pivot part Hub sits on the pin"))
    for i, b in enumerate(t["bumpers"], 1):
        rows.append((f"BumperCap{i}", f"Cap of pop bumper {i}"))
    for i, s in enumerate(t["slings"], 1):
        rows.append((f"Sling{i}", f"{'Left' if s['id'].endswith('l') else 'Right'} slingshot rubber"))
    for i, g in enumerate(t["targets"], 1):
        if g["kind"] == "drop":
            rows.append((f"Drop{i}", f"Drop target {g['id'].split('_')[1].upper()}"))
        else:
            rows.append((f"Standup{i}", f"Standup target {g['id'].split('_')[1].upper()} (fixed)"))
    k = 0
    for s in t["sensors"]:
        if s["kind"] == "spinner":
            k += 1
            rows.append((f"Spinner{k}", "Spinner flag"))
    for i, l in enumerate(t["lamps"], 1):
        c = LAMP.get(l["colour"], LAMP["white"])
        rows.append((f"Lamp{i}", f'<span class="dot" style="--c:{rgbhex(c)}"></span>{html.escape(l["id"].replace("_", " "))} ({l["colour"]})'))
    rows += [("Ball1 to Ball3", "The balls"), ("Plunger", "A group: Rod and Knob"), ("Backglass", "The backbox's face; the score is written on it"), ("Playfield", "The board")]
    return "\n".join(f"<tr><td><code>{a}</code></td><td>{b}</td></tr>" for a, b in rows)

secs = []
for key, tid, title, where, kind, rule, look, parts, words in MACH:
    th = D["themes"][key]
    sw = "".join(f'<li><span class="sw" style="--c:{rgbhex(th[k])}"></span><span class="swl">{lab}</span><span class="num">{", ".join(map(str, th[k]))}</span></li>' for k, lab in THEME_KEYS)
    t = T[tid]
    counts = f'{len(t["bumpers"])} pop bumpers · {len(t["targets"])} targets · {len(t["rails"])} ramp{"s" if len(t["rails"]) != 1 else ""} · {len(t["saucers"])} hole{"s" if len(t["saucers"]) != 1 else ""} · {len(t["lamps"])} lamps'
    secs.append(f'''
<section class="machine" id="{key}" style="--m:{rgbhex(th['trim'])}">
  <header class="mhead">
    <p class="eyebrow">{where}</p>
    <h2>{title}</h2>
    <p class="kind">{kind}. <em>{html.escape(rule)}</em></p>
    <p class="counts num">{counts}</p>
  </header>
  <div class="mgrid">
    <figure class="plan"><a href="{key}_plan.png" target="_blank" rel="noopener"><img src="{key}_plan.png" alt="{title} playfield plan with numbered parts" loading="lazy"></a>
      <figcaption>The playfield from above, to scale, every part numbered (key under the drawing). Open it full size to zoom.</figcaption></figure>
    <div class="mtext">
      <h3>Look</h3><p>{html.escape(look)}</p>
      <ul class="swatches">{sw}</ul>
      <h3>What is on it</h3><ul class="parts">{"".join(f"<li>{html.escape(p)}</li>" for p in parts)}</ul>
      <h3>Painted on the playfield</h3><p>{html.escape(words)}</p>
      <figure class="ingame"><img src="r_{key}_above.jpg" alt="{title} from above in the game today" loading="lazy"><figcaption>In the game today, from above</figcaption></figure>
      <details><summary>Names the game looks for ({title})</summary><div class="tw"><table>{names_table(tid)}</table></div></details>
    </div>
  </div>
</section>''')

page = open(sys.argv[3]).read().replace("<!--MACHINES-->", "\n".join(secs))
open(f"{OUT}/index.html", "w").write(page)
print("ok")
