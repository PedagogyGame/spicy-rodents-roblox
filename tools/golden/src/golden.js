#!/usr/bin/env node
"use strict";
// tools/golden: golden vectors from the original v5.4 functions. See README.md.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const O = require("./original");
const { stringify } = require("./jsonfmt");
const { THREE, v } = O;
const THREE_VERSION = JSON.parse(fs.readFileSync(path.join(path.dirname(require.resolve("three")), "..", "package.json"), "utf8")).version;

const REPO = path.resolve(__dirname, "..", "..", "..");
const DEFAULTS = {
  reference: "/home/user/spicy-rodents/reference/v5_4_game.js",
  harvest: path.join(REPO, "data", "harvest"),
  out: path.join(REPO, "data", "golden"),
  report: path.join(REPO, "docs", "reports", "golden_report.md"),
};
function parseArgs(argv) {
  const o = { ...DEFAULTS };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--reference") o.reference = argv[++i];
    else if (a === "--harvest") o.harvest = argv[++i];
    else if (a === "--out") o.out = argv[++i];
    else if (a === "--report") o.report = argv[++i];
    else if (a === "--help" || a === "-h") {
      console.log(fs.readFileSync(path.join(__dirname, "..", "README.md"), "utf8"));
      process.exit(0);
    } else throw new Error(`unknown argument ${a}`);
  }
  return o;
}
const sha256 = (s) => crypto.createHash("sha256").update(s).digest("hex");
const arr = (p) => [p.x, p.y, p.z];
const SEEDS = { terrain: 4101, curves: 4102, advance: 4103, railMotion: 4104, swept: 4105, segmentBox: 4106, spotted: 4107 };
const uniform = (r, a, b) => a + (b - a) * r();
const pick = (r, a) => a[Math.floor(r() * a.length)];

// ---------------------------------------------------------------- terrain
function terrainSet() {
  const r = O.rng(SEEDS.terrain);
  const points = [];
  const add = (x, z, tag) => points.push({ x, z, tag });
  for (let x = -700; x <= 1200; x += 20) for (let z = -700; z <= 700; z += 20) add(x, z, "grid20");
  for (let i = 0; i < 3000; i++) add(uniform(r, -700, 1200), uniform(r, -700, 700), "random");
  for (let i = 0; i < 600; i++) add(uniform(r, 687, 1150), uniform(r, -244, 443), "river_district");
  for (let i = 0; i < 300; i++) add(uniform(r, 740, 960), uniform(r, -8, 8), "bridge_deck");
  for (let i = 0; i < 300; i++) {
    const z = uniform(r, -244, 443);
    add(O.riverCenter(z) + pick(r, [-1, 1]) * uniform(r, 50, 54), z, "water_edge");
  }
  // exact boundary values: Chebyshev 104 and 190 (flat core / full hills), x = 687 and 735 (bank blend)
  for (const d of [103.99, 104, 104.01, 150, 189.99, 190, 190.01]) {
    add(d, 0, "core_boundary"); add(-d, 37, "core_boundary"); add(12, d, "core_boundary"); add(-80, -d, "core_boundary");
  }
  for (const x of [686.99, 687, 687.01, 700, 734.99, 735, 735.01, 1149.99, 1150, 1150.01]) add(x, 50, "river_x_boundary");
  for (const z of [-244.01, -244, -243.99, 442.99, 443, 443.01]) add(800, z, "river_z_boundary");
  const columns = ["tag", "x", "z", "base", "height", "riverCenter", "inRiverDistrict", "insideRiverWater", "riverDeck"];
  const rows = points.map((p) => [p.tag, p.x, p.z, O.baseTerrainHeight(p.x, p.z), O.terrainHeight(p.x, p.z), O.riverCenter(p.z), O.inRiverDistrict(p.x, p.z), O.insideRiverWater(p.x, p.z), O.riverDeckAt(p.x, p.z)]);
  return {
    $schema: "golden/terrain v1",
    units: "HTML units",
    source: "baseTerrainHeight L407-416, terrainHeight L458-464, riverCenter/inRiverDistrict/insideRiverWater/riverDeckAt L436-457, RIVER L419-435, smoothstep L403-406 (THREE.MathUtils.smoothstep for the bank blend)",
    seed: SEEDS.terrain,
    tolerance: "1e-9 absolute (pure arithmetic; port verbatim)",
    river: O.RIVER,
    columns,
    count: rows.length,
    rows,
  };
}

// ---------------------------------------------------------------- curves
function loadHarvest(dir) {
  const routes = JSON.parse(fs.readFileSync(path.join(dir, "routes.json"), "utf8")).routes;
  const samples = new Map(JSON.parse(fs.readFileSync(path.join(dir, "route_samples.json"), "utf8")).samples);
  return { routes, samples };
}
function makeCurve(points) {
  return new THREE.CatmullRomCurve3(points.map((p) => v(p[0], p[1], p[2])), false, "centripetal");
}
function curveSet(H) {
  // (a) cross-check npm three@0.160.1 against the inlined r160 for ALL routes
  let maxLenDiff = 0, maxSampleDiff = 0, sampleCountMismatch = 0;
  for (const r of H.routes) {
    const c = makeCurve(r.points);
    const len = c.getLength();
    maxLenDiff = Math.max(maxLenDiff, Math.abs(len - r.length));
    const steps = Math.max(20, Math.ceil(len * 3));
    const pts = c.getSpacedPoints(steps);
    const hs = H.samples.get(r.id);
    if (pts.length !== hs.length) sampleCountMismatch++;
    else for (let i = 0; i < pts.length; i++) maxSampleDiff = Math.max(maxSampleDiff, pts[i].distanceTo(v(hs[i][0], hs[i][1], hs[i][2])));
  }
  // (b) 200-route subset: every lookout, fence, trampoline and bridge-rich sample, then seeded picks
  const r = O.rng(SEEDS.curves);
  const chosen = new Map();
  for (const rt of H.routes) if (["lookout", "fence", "trampoline"].includes(rt.kind)) chosen.set(rt.id, rt);
  const byKind = {};
  for (const rt of H.routes) (byKind[rt.kind] ||= []).push(rt);
  const quota = { trunk: 40, branch: 55, bridge: 25, roof: 25, wire: 30 };
  for (const [kind, n] of Object.entries(quota)) {
    const list = byKind[kind];
    let guard = 0;
    while ([...chosen.values()].filter((x) => x.kind === kind).length < n && guard++ < 10000) {
      const rt = pick(r, list);
      chosen.set(rt.id, rt);
    }
  }
  const ids = [...chosen.keys()].sort((a, b) => a - b);
  const tFixed = Array.from({ length: 21 }, (_, i) => i / 20);
  const routes = ids.map((id) => {
    const rt = chosen.get(id);
    const c = makeCurve(rt.points);
    const ts = tFixed.concat(Array.from({ length: 10 }, () => uniform(r, 0, 1)));
    const length = c.getLength();
    const steps = Math.max(20, Math.ceil(length * 3));
    return {
      id: rt.id,
      name: rt.name,
      kind: rt.kind,
      points: rt.points,
      length,
      arcLengthDivisions: c.arcLengthDivisions,
      lengths200: c.getLengths(c.arcLengthDivisions),
      steps,
      spacedPoints: c.getSpacedPoints(steps).map(arr),
      at: ts.map((t) => ({ t, u2t: c.getUtoTmapping(t), point: arr(c.getPoint(t)), pointAt: arr(c.getPointAt(t)), tangentAt: arr(c.getTangentAt(t)) })),
    };
  });
  return {
    file: {
      $schema: "golden/curves v1",
      units: "HTML units",
      source: "THREE.CatmullRomCurve3(points, closed=false, 'centripetal') as in addRoute L302-311; three@0.160.1 from npm (REVISION " + THREE.REVISION + ")",
      seed: SEEDS.curves,
      notes: [
        "lengths200 = curve.getLengths(200): cumulative chord lengths at t = i/200 (arcLengthDivisions 200), the table getUtoTmapping bisects",
        "pointAt/tangentAt are arc-length parameterised (getPointAt/getTangentAt); point is the raw getPoint(t)",
        "spacedPoints = getSpacedPoints(steps) with steps = max(20, ceil(3*length)); equals data/harvest/route_samples.json for these ids",
        "tolerance for a port: 0.01 u on points (BUILD_PLAN S3), 1e-6 on lengths if the 200-division table is reproduced exactly",
      ],
      count: routes.length,
      routes,
    },
    check: { routesChecked: H.routes.length, maxLengthDiff: maxLenDiff, maxSamplePointDiff: maxSampleDiff, sampleCountMismatch },
  };
}

// ---------------------------------------------------------------- RouteMotion.advance and rail motion
function advanceSet() {
  const r = O.rng(SEEDS.advance);
  const cases = [];
  for (let i = 0; i < 2000; i++) {
    const t = uniform(r, -0.1, 1.1);
    const dir = pick(r, [-1, 1]);
    const forward = pick(r, [-1, 0, 1, 0.5, -0.25]);
    const seconds = pick(r, [uniform(r, 0, 0.05), uniform(r, 0.05, 0.2), uniform(r, -0.02, 0), 1 / 60, 0.05, 0.08]);
    const speed = pick(r, [4.32, 7.32, 0.72, 6.91, 11.71, 7.2, 12.2, 1.2, 11.52, 19.52, uniform(r, 0, 25)]);
    const length = pick(r, [uniform(r, 0.04, 1), uniform(r, 1, 120), 0.86, 1, 32, 50]);
    cases.push([t, dir, forward, seconds, speed, length, O.RouteMotion.advance(t, dir, forward, seconds, speed, length)]);
  }
  return { $schema: "golden/advance v1", source: "RouteMotion.advance L267-272 (dt clamped to [0, 0.05], divided by max(1, length))", seed: SEEDS.advance, tolerance: "1e-12", columns: ["t", "dir", "forward", "seconds", "speed", "length", "result"], count: cases.length, rows: cases };
}
function railMotionSet(H) {
  // Sequences along real routes: t advanced with RouteMotion.advance, clamped to [0,1] as the
  // movement code does at route ends (routes_movement 10), position/tangent from the curve.
  const r = O.rng(SEEDS.railMotion);
  const kinds = { wood: ["trunk", "branch", "bridge", "lookout"] };
  const routes = [];
  const pool = H.routes.filter((x) => x.length > 2);
  for (let i = 0; i < 60; i++) routes.push(pick(r, pool));
  const sequences = routes.map((rt) => {
    const c = makeCurve(rt.points);
    const wood = kinds.wood.includes(rt.kind);
    const base = pick(r, [7.2, 12.2, 1.2]) * (pick(r, [false, false, true]) ? 1.6 : 1);
    const speed = base * (wood ? 0.6 : 1);
    let t = uniform(r, 0, 1);
    const dir = pick(r, [-1, 1]);
    const steps = [];
    for (let k = 0; k < 40; k++) {
      const forward = pick(r, [1, 1, 1, -1, 0]);
      const dt = pick(r, [1 / 60, 1 / 30, 0.05, 0.08, uniform(r, 0.001, 0.1)]);
      const raw = O.RouteMotion.advance(t, dir, forward, dt, speed, rt.length);
      t = Math.max(0, Math.min(1, raw));
      const p = c.getPointAt(t), tg = c.getTangentAt(t);
      steps.push({ forward, dt, raw, t, pos: arr(p), tangent: arr(tg) });
    }
    return { id: rt.id, name: rt.name, kind: rt.kind, length: rt.length, speed, dir, start: steps.length ? null : null, steps };
  });
  for (const s of sequences) delete s.start;
  return { $schema: "golden/rail_motion v1", units: "HTML units", source: "RouteMotion.advance L267-272; railSpeed rule routes_movement 10 (x0.6 on trunk/branch/bridge/lookout); clamp at ends L6687-6690; pose = curve.getPointAt(railT)", seed: SEEDS.railMotion, tolerance: "t: 1e-12; pos: 0.01 u", count: sequences.length, sequences };
}

// ---------------------------------------------------------------- swept collision
const VEHICLES = [
  { label: "sedan", W: 2.35, L: 4.45, H: 2.04 },
  { label: "delivery_van", W: 3.0, L: 5.9, H: 3.65 },
  { label: "ice_cream_van", W: 3.35, L: 6.55, H: 3.58 },
  { label: "trolley", W: 3.5, L: 11.0, H: 4.12 },
  { label: "dump_truck", W: 3.35, L: 8.9, H: 4.12 },
  { label: "rv", W: 3.2, L: 8.7, H: 4.3 },
];
function sweptCase(name, p0, p1, v0, v1, yaw0, yaw1, veh, note) {
  const enc = (x) => (Number.isFinite(x) ? x : String(x));
  return [name, veh.label, veh.W, veh.L, veh.H, p0.toArray().map(enc), p1.toArray().map(enc), v0.toArray().map(enc), v1.toArray().map(enc), enc(yaw0), enc(yaw1), O.sweptVehicleHit(p0, p1, v0, v1, yaw0, yaw1, veh.W, veh.L, veh.H), note];
}
function sweptRandom() {
  const r = O.rng(SEEDS.swept);
  const cases = [];
  for (let i = 0; i < 10000; i++) {
    const veh = pick(r, VEHICLES);
    const v0 = v(uniform(r, -30, 30), uniform(r, 0, 9) + 0.04, uniform(r, -30, 30));
    const yaw0 = uniform(r, -Math.PI, Math.PI);
    const travel = pick(r, [0, uniform(r, 0, 0.1), uniform(r, 0, 1.2), uniform(r, 1.2, 12), uniform(r, 12, 20)]);
    const turn = pick(r, [0, 0, 0, uniform(r, -0.3, 0.3), Math.PI / 2, -Math.PI / 2, Math.PI, -Math.PI, uniform(r, -Math.PI, Math.PI)]);
    const yaw1 = yaw0 + turn;
    const v1 = v(v0.x + Math.sin(yaw0) * travel, v0.y, v0.z + Math.cos(yaw0) * travel);
    // squirrel start relative to the vehicle at the frame start, in vehicle-local-ish extents
    const spread = pick(r, [1.0, 1.0, 1.6, 3]);
    const rel = v(uniform(r, -1, 1) * (veh.W / 2 + 0.5) * spread, uniform(r, -0.6, veh.H + 1.0), uniform(r, -1, 1) * (veh.L / 2 + 0.5) * spread);
    const c = Math.cos(yaw0), s = Math.sin(yaw0);
    const p0 = v(v0.x + c * rel.x + s * rel.z, v0.y + rel.y, v0.z - s * rel.x + c * rel.z);
    const move = pick(r, [0, uniform(r, 0, 0.4), uniform(r, 0, 1.4), uniform(r, 0, 3)]);
    const ang = uniform(r, -Math.PI, Math.PI);
    const dy = pick(r, [0, 0, uniform(r, -1, 1)]);
    const p1 = v(p0.x + Math.sin(ang) * move, p0.y + dy, p0.z + Math.cos(ang) * move);
    cases.push(sweptCase(`random_${i}`, p0, p1, v0, v1, yaw0, yaw1, veh, ""));
  }
  return cases;
}
function sweptHand() {
  const sedan = VEHICLES[0], van = VEHICLES[1], trolley = VEHICLES[3];
  const cases = [];
  const G = O.SQUIRREL_GRAVITY, VY = 12.8, DT = 1 / 60;
  // 1. sedan jump: squirrel runs +x at 8 u/s over a parked-then-moving sedan; leap at frame 0 from x = -4.
  //    The reference point clears the box while y_rel >= H - 0.16 = 1.88 (traffic 8.4: window about 0.17..0.68 s).
  for (const moving of [false, true]) {
    const carSpeed = moving ? 6 : 0; // car drives -x toward the squirrel
    for (let k = 0; k <= 50; k++) {
      const t0 = k * DT, t1 = (k + 1) * DT;
      const sq = (t) => v(-4 + 8 * t, 0.18 + VY * t - 0.5 * G * t * t, 0);
      const car = (t) => v(-carSpeed * t, 0.04, 0);
      cases.push(sweptCase(`sedan_jump_${moving ? "moving" : "parked"}_f${k}`, sq(t0), sq(t1), car(t0), car(t1), Math.PI / 2, Math.PI / 2, sedan, `leap vy 12.8 g 30 over a sedan facing +x (yaw pi/2); frame ${k} of 1/60 s`));
    }
  }
  // 2. tall vehicles cannot be jumped from the ground: apex 2.73 + 0.18 < H - 0.16 for the van and trolley
  for (const veh of [van, trolley]) {
    const tApex = VY / G;
    const sq = (t) => v(0, 0.18 + VY * t - 0.5 * G * t * t, 0);
    cases.push(sweptCase(`${veh.label}_apex_inside_box`, sq(tApex - DT / 2), sq(tApex + DT / 2), v(0, 0.04, -0.5), v(0, 0.04, 0.5), 0, 0, veh, "squirrel at the leap apex (2.73 u) is still below H - 0.16"));
  }
  // 3. below the box (sewer): relative y < -0.3 never hits
  cases.push(sweptCase("below_box_sewer", v(0, -3.4, 0), v(0.5, -3.4, 0), v(0, 0.04, -1), v(0, 0.04, 1), 0, 0, sedan, "relative y -3.44 is below minY -0.3"));
  cases.push(sweptCase("just_below_box", v(0, 0.04 - 0.31, 0), v(0.2, 0.04 - 0.31, 0), v(0, 0.04, -1), v(0, 0.04, 1), 0, 0, sedan, "relative y -0.31 < -0.3: miss"));
  cases.push(sweptCase("just_inside_bottom", v(0, 0.04 - 0.29, 0), v(0.2, 0.04 - 0.29, 0), v(0, 0.04, -1), v(0, 0.04, 1), 0, 0, sedan, "relative y -0.29 >= -0.3: hit"));
  cases.push(sweptCase("just_above_top", v(0, 0.04 + sedan.H - 0.16 + 0.001, 0), v(0, 0.04 + sedan.H - 0.16 + 0.001, 0), v(0, 0.04, -1), v(0, 0.04, 1), 0, 0, sedan, "relative y 1.881 > maxY 1.88: miss"));
  cases.push(sweptCase("exactly_top", v(0, 0.04 + sedan.H - 0.16, 0), v(0, 0.04 + sedan.H - 0.16, 0), v(0, 0.04, -1), v(0, 0.04, 1), 0, 0, sedan, "relative y == maxY: slab test is inclusive -> hit"));
  // 4. start inside: segment starting inside the box returns enter = 0 -> hit, even when leaving
  cases.push(sweptCase("start_inside_leaving", v(0.2, 0.3, 0.5), v(6, 0.3, 0.5), v(0, 0.04, 0), v(0, 0.04, 0.01), 0, 0, sedan, "starts inside, leaves: still a hit (enter = 0)"));
  // 5. stationary vehicle (travel 0) with the squirrel passing through: sweptVehicleHit itself says hit; finishTrafficFrame filters it (see travel_filter)
  cases.push(sweptCase("stationary_car_passthrough", v(-4, 0.18, 0), v(4, 0.18, 0), v(0, 0.04, 0), v(0, 0.04, 0), 0, 0, sedan, "the function hits; the per-vehicle travel filter (L15878) is what spares the player"));
  // 6. 180-degree flip (patrol car end turn): 63 sub-steps; squirrel standing beside the car gets swept by the box corners
  for (const [i, dx] of [0.9, 2.0, 2.6, 3.2, 4.0].entries()) {
    cases.push(sweptCase(`flip180_side_${i}`, v(dx, 0.18, 0), v(dx, 0.18, 0), v(0, 0.04, 0), v(0.001, 0.04, 0), 0, Math.PI, sedan, `squirrel ${dx} u beside a sedan that flips 180 degrees in one frame (63 sub-steps, pad grows with the corner arc)`));
  }
  // 7. 90-degree snap (advanceVehicleRoute corner): 32 sub-steps
  for (const [i, dz] of [1.5, 2.3, 2.5, 3.0].entries()) {
    cases.push(sweptCase(`snap90_front_${i}`, v(0, 0.18, dz), v(0, 0.18, dz), v(0, 0.04, 0), v(0, 0.04, 0.3), 0, Math.PI / 2, sedan, `squirrel ${dz} u ahead of a sedan that snaps 90 degrees while moving 0.3 u`));
  }
  // 8. tunnelling: a fast car (12 u in one frame) through a standing squirrel; and the squirrel dodging sideways
  cases.push(sweptCase("tunnel_fast_car", v(0, 0.18, 0), v(0, 0.18, 0), v(0, 0.04, -8), v(0, 0.04, 4), 0, 0, sedan, "12 u of travel in one frame still hits (relative sweep)"));
  cases.push(sweptCase("dodge_sideways_fast_car", v(0, 0.18, 0), v(1.6, 0.18, 0), v(0, 0.04, -8), v(0, 0.04, 4), 0, 0, sedan, "squirrel jumps 1.6 u sideways (> W/2 + 0.18 = 1.355) while the car passes: combined path still crosses the box"));
  cases.push(sweptCase("dodge_sideways_clear", v(1.5, 0.18, 0), v(2.5, 0.18, 0), v(0, 0.04, -8), v(0, 0.04, 4), 0, 0, sedan, "starts outside the padded width and moves away: miss"));
  // 9. non-finite inputs -> false
  cases.push(sweptCase("nan_input", v(NaN, 0.18, 0), v(0, 0.18, 0), v(0, 0.04, -1), v(0, 0.04, 1), 0, 0, sedan, "any non-finite input returns false"));
  cases.push(sweptCase("infinite_yaw", v(0, 0.18, 0), v(0, 0.18, 0), v(0, 0.04, -1), v(0, 0.04, 1), 0, Infinity, sedan, "non-finite yaw returns false"));
  // 10. yaw wrap: yaw1 = yaw0 + 2pi is a zero turn (atan2 wrap), 1 sub-step
  cases.push(sweptCase("yaw_wrap_2pi", v(1.3, 0.18, 0), v(1.3, 0.18, 0), v(0, 0.04, 0), v(0, 0.04, 0.5), 0.3, 0.3 + 2 * Math.PI, sedan, "turn wraps to 0: 1 sub-step, pad 0.18"));
  return cases;
}
function sweptSet() {
  const random = sweptRandom();
  const hand = sweptHand();
  const cases = hand.concat(random);
  const hits = cases.filter((c) => c[11]).length;
  return {
    $schema: "golden/swept v1",
    columns: ["name", "vehicle", "W", "L", "H", "p0", "p1", "v0", "v1", "yaw0", "yaw1", "hit", "note"],
    units: "HTML units",
    source: "sweptVehicleHit L15808-15851 and segmentBoxEntry L15786-15807; boxes from traffic.md 1 (sedan 2.35x4.45x2.04, van 3.0x5.9x3.65, ice cream 3.35x6.55x3.58, trolley 3.5x11x4.12, dump 3.35x8.9x4.12, RV 3.2x8.7x4.3)",
    seed: SEEDS.swept,
    encoding: "non-finite numbers are the strings \"NaN\", \"Infinity\", \"-Infinity\"",
    tolerance: "exact boolean agreement (BUILD_PLAN S4: 100 %)",
    count: cases.length,
    handCount: hand.length,
    randomCount: random.length,
    hits,
    rows: cases,
  };
}
function segmentBoxSet() {
  const r = O.rng(SEEDS.segmentBox);
  const cases = [];
  for (let i = 0; i < 3000; i++) {
    const hw = uniform(r, 0.5, 2.5), hl = uniform(r, 1, 6), minY = -0.3, maxY = uniform(r, 1, 4.2);
    const a = v(uniform(r, -2, 2) * hw * 1.5, uniform(r, -1, maxY + 1), uniform(r, -2, 2) * hl * 1.5);
    const axisParallel = r() < 0.15;
    const b = axisParallel ? v(a.x, a.y, a.z + uniform(r, -3, 3)) : v(a.x + uniform(r, -4, 4), a.y + uniform(r, -1, 1), a.z + uniform(r, -6, 6));
    if (r() < 0.05) b.copy(a); // zero-length segment: parallel on every axis
    cases.push([arr(a), arr(b), hw, hl, minY, maxY, O.segmentBoxEntry(a, b, hw, hl, minY, maxY)]);
  }
  return { $schema: "golden/segment_box_entry v1", source: "segmentBoxEntry L15786-15807 (slab test; |d| < 1e-10 counts as parallel; returns enter or null)", seed: SEEDS.segmentBox, tolerance: "enter: 1e-12; null exact", columns: ["a", "b", "halfWidth", "halfLength", "minY", "maxY", "enter"], count: cases.length, rows: cases };
}
function travelFilterSet() {
  const cases = [];
  for (const dt of [1 / 60, 1 / 30, 0.05, 0.08, 0.1, 0.2]) for (const travel of [0, 5e-6, 1e-5, 1.1e-5, 0.29, 1, 11.99, 12, 12.01, 18, 19.5, 30]) cases.push({ travel, dt, skip: O.trafficTravelFilterSkips(travel, dt) });
  return { $schema: "golden/travel_filter v1", source: "finishTrafficFrame L15870-15897: skip when travel < 1e-5 or travel > max(12, dt*80 + 2) (dt is already capped at 0.08 by tick L16007)", count: cases.length, cases };
}

// ---------------------------------------------------------------- pounce / jump
function pounceSet() {
  const cases = [];
  const headings = [
    { yaw: 0 }, { yaw: 0.5 }, { yaw: -2.2 }, { yaw: Math.PI }, { yaw: 3.9 },
    { rail: "trunk", trunkNormal: [0, 0, 1] }, { rail: "trunk", trunkNormal: [1, 0, 0] }, { rail: "trunk", trunkNormal: [-0.6, 0, -0.8] }, { rail: "trunk", trunkNormal: null },
    { rail: "branch", yaw: 1.1 },
  ];
  const pitches = Array.from({ length: 21 }, (_, i) => -0.8 + (2.0 * i) / 20).concat([-0.54, 0.9, 0.12, -0.6, 1.07]);
  for (const h of headings) for (const p of pitches) for (const focus of [false, true]) for (const moveSpeed of [0, 8, 12, 12.01, 16.8]) for (const boost of [0, 3.2]) {
    const player = { yaw: h.yaw ?? 0, rail: h.rail ? { kind: h.rail } : null, trunkNormal: h.trunkNormal ? v(...h.trunkNormal) : null, focus, moveSpeed, boostRemaining: boost };
    O.setPlayer(player);
    O.setPitch(p);
    cases.push([h.yaw ?? 0, h.rail ?? null, h.trunkNormal ?? null, p, focus, moveSpeed, boost, O.attackHeading(), arr(O.pounceVelocity()), arr(O.jumpVelocity())]);
  }
  return {
    $schema: "golden/pounce v1",
    units: "HTML units per second",
    source: "pounceVelocity L6473-6481 (pitch clamp [-0.54, 0.9]; speed 12.4 focus / 13.5 when moveSpeed > 12 / 11.3, x1.12 with boost; vy 3.45 + 2.1 sin p), jumpVelocity L5915-5921 (forward 16.5 / 18.5 boosted, vy 12.8), attackHeading L5900-5906 (trunk: atan2 of trunkNormal, default (0,0,1))",
    gravity: O.SQUIRREL_GRAVITY,
    tolerance: "1e-9",
    columns: ["yaw", "railKind", "trunkNormal", "pitch", "focus", "moveSpeed", "boostRemaining", "attackHeading", "pounce", "jump"],
    notes: ["railKind null means no rail; trunkNormal null on a trunk means the (0,0,1) default"],
    count: cases.length,
    rows: cases,
  };
}

// ---------------------------------------------------------------- spotted
function spottedSet() {
  const r = O.rng(SEEDS.spotted);
  const cases = [];
  const run = (name, playerState, human, hotHere, remembered, note) => {
    O.setPlayer({ pos: v(...playerState.pos), moveSpeed: playerState.moveSpeed, focus: playerState.focus });
    O.setActiveHouseInterior(playerState.activeHouseInterior ? {} : null);
    O.setTime(100);
    O.setCrimeScenes(hotHere ? [{ ttl: 5, center: v(human.pos[0], 0, human.pos[2]), radius: 1 }] : []);
    const n = { facing: human.facing, witnessUntil: remembered ? 200 : 0 };
    const out = O.spottedPredicate(n, v(...human.pos));
    cases.push([name, playerState.pos, playerState.moveSpeed, playerState.focus, !!playerState.activeHouseInterior, human.pos, human.facing, hotHere, remembered, out.dist2, out.isVisible, out.inView, out.noise, out.gardenBlind, out.hedgeBlind, out.concealed, out.radar, out.spotted, note]);
  };
  // hand cases around the concealment volumes and thresholds
  run("garden_quiet", { pos: [115, 2.0, 341], moveSpeed: 1.0, focus: true, activeHouseInterior: false }, { pos: [118, 5.1, 344], facing: 3.0 }, false, false, "inside the Tabasco plot, below y 2.4, slow: concealed");
  run("garden_moving", { pos: [115, 2.0, 341], moveSpeed: 8, focus: false, activeHouseInterior: false }, { pos: [118, 5.1, 344], facing: 3.0 }, false, false, "inside the plot but moving >= 3.4: not concealed");
  run("hedge_quiet", { pos: [125, 2.5, 303], moveSpeed: 2.0, focus: false, activeHouseInterior: false }, { pos: [128, 2.3, 305], facing: -1.0 }, false, false, "inside hedge [125,303,14,2.3] below y 2.8, slow: concealed");
  run("canopy_quiet", { pos: [10, 9, 10], moveSpeed: 0, focus: false, activeHouseInterior: false }, { pos: [12, 0, 12], facing: 0.7 }, false, false, "above 5.2 and silent: never spotted");
  run("canopy_noisy", { pos: [10, 9, 10], moveSpeed: 8, focus: false, activeHouseInterior: false }, { pos: [12, 0, 12], facing: 0.7 }, false, false, "above 5.2 but noisy within 8.6: spotted by noise");
  run("behind_far", { pos: [0, 0.3, -10], moveSpeed: 0, focus: false, activeHouseInterior: false }, { pos: [0, 0, 0], facing: 0 }, false, false, "10 u behind (facing +z): not in view, beyond 6.8");
  run("behind_near", { pos: [0, 0.3, -5], moveSpeed: 0, focus: false, activeHouseInterior: false }, { pos: [0, 0, 0], facing: 0 }, false, false, "5 u behind: peripheral range 6.8");
  run("hot_radar", { pos: [0, 0.3, 18], moveSpeed: 0, focus: false, activeHouseInterior: false }, { pos: [0, 0, 0], facing: 0 }, true, false, "18 u ahead: only seen with radar 3 (cap 20)");
  run("remembered_radar", { pos: [0, 0.3, 18], moveSpeed: 0, focus: false, activeHouseInterior: false }, { pos: [0, 0, 0], facing: 0 }, false, true, "witness memory also triples the radius");
  run("interior", { pos: [0, 0.3, 3], moveSpeed: 8, focus: false, activeHouseInterior: true }, { pos: [0, 0, 0], facing: 0 }, false, false, "inside a house interior: not visible, but noise still counts");
  for (let i = 0; i < 3000; i++) {
    const human = { pos: [uniform(r, -300, 700), uniform(r, 0, 9), uniform(r, -300, 450)], facing: uniform(r, -Math.PI, Math.PI) };
    const d = pick(r, [uniform(r, 0, 5), uniform(r, 0, 9), uniform(r, 0, 22), uniform(r, 0, 30)]);
    const ang = uniform(r, -Math.PI, Math.PI);
    let pos = [human.pos[0] + Math.sin(ang) * d, human.pos[1] + pick(r, [uniform(r, -0.5, 3.9), uniform(r, 3.9, 5.3), uniform(r, 5.3, 30), 0.3]), human.pos[2] + Math.cos(ang) * d];
    if (r() < 0.08) {
      const hp = pick(r, O.hedgePatches);
      pos = [hp[0] + uniform(r, -hp[2] / 2 - 2.5, hp[2] / 2 + 2.5), uniform(r, 0, 3.2), hp[1] + uniform(r, -hp[3] - 1.5, hp[3] + 1.5)];
    } else if (r() < 0.08) {
      pos = [O.GARDEN_X + uniform(r, -30, 30), uniform(r, 0, 3), O.GARDEN_Z + uniform(r, -18, 18)];
    }
    const playerState = { pos, moveSpeed: pick(r, [0, 1.65, 2.6, 3.3, 3.5, 4.8, 8, 16.8, uniform(r, 0, 17)]), focus: r() < 0.25, activeHouseInterior: r() < 0.05 };
    run(`random_${i}`, playerState, human, r() < 0.15, r() < 0.1, "");
  }
  return {
    $schema: "golden/spotted v1",
    units: "HTML units; player.pos.y is ABSOLUTE world height (porting risk, humans_actors 5.3)",
    source: "updateHumans L7027-7051 (isVisible, inView > 0.28, noise, gardenBlind, hedgeBlind, concealed, radar, spotted); hedgePatches L3573-3579; GARDEN_X/Z L3590-3591",
    seed: SEEDS.spotted,
    hedgePatches: O.hedgePatches,
    garden: { x: O.GARDEN_X, z: O.GARDEN_Z },
    notes: ["hotHere models a live crime scene whose radius covers the human; remembered models n.witnessUntil > time", "activeHouseInterior true means the squirrel is inside a house interior (isVisible false)"],
    tolerance: "exact booleans; dist2 1e-9",
    columns: ["name", "playerPos", "moveSpeed", "focus", "activeHouseInterior", "humanPos", "humanFacing", "hotHere", "remembered", "dist2", "isVisible", "inView", "noise", "gardenBlind", "hedgeBlind", "concealed", "radar", "spotted", "note"],
    count: cases.length,
    rows: cases,
  };
}

// ---------------------------------------------------------------- RouteJunction helpers
function junctionSet() {
  const cases = [];
  for (const t of [0, 0.01, 0.034, 0.035, 0.036, 0.5, 0.964, 0.965, 0.966, 1]) for (const desired of [-1, 1]) cases.push({ fn: "inward", t, desired, result: O.RouteJunction.inward(t, desired) });
  for (const gap of [0, 0.3, 0.48, 0.4800001, 1.0, 1.7, 1.7000001, 5, "NaN", "Infinity"]) for (const explicit of [false, true]) {
    const g = typeof gap === "string" ? Number(gap) : gap;
    cases.push({ fn: "canTransfer", gap, explicit, result: O.RouteJunction.canTransfer(g, explicit) });
  }
  for (const p of [-1, 0, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 2]) cases.push({ fn: "ease", p, result: O.RouteJunction.ease(p) });
  return { $schema: "golden/junction v1", source: "RouteJunction L5782-5793", count: cases.length, cases };
}

// ---------------------------------------------------------------- main
function main() {
  const opt = parseArgs(process.argv.slice(2));
  const verified = O.verifyVerbatim(opt.reference);
  fs.mkdirSync(opt.out, { recursive: true });
  const H = loadHarvest(opt.harvest);
  const files = {};
  const write = (name, value) => {
    const text = stringify(value);
    fs.writeFileSync(path.join(opt.out, name), text);
    files[name] = { bytes: Buffer.byteLength(text), sha256: sha256(text), count: value.count };
  };
  const curves = curveSet(H);
  write("terrain.json", terrainSet());
  write("curves.json", curves.file);
  write("advance.json", advanceSet());
  write("rail_motion.json", railMotionSet(H));
  const swept = sweptSet();
  write("swept.json", swept);
  write("segment_box_entry.json", segmentBoxSet());
  write("travel_filter.json", travelFilterSet());
  write("pounce.json", pounceSet());
  write("spotted.json", spottedSet());
  write("junction.json", junctionSet());
  const manifest = {
    $schema: "golden/manifest v1",
    generatedAt: new Date().toISOString(),
    tool: "tools/golden v0.1.0",
    three: { npm: THREE_VERSION, revision: THREE.REVISION },
    reference: { path: opt.reference, verbatimBlocks: O.BLOCKS, verified },
    harvest: { dir: opt.harvest, routes: H.routes.length },
    threeCrossCheck: curves.check,
    seeds: SEEDS,
    sweptHits: swept.hits,
    files,
  };
  write("manifest.json", manifest);
  writeReport(opt.report, manifest, swept);
  console.log(`golden: wrote ${Object.keys(files).length} files to ${opt.out}; three cross-check maxLenDiff=${curves.check.maxLengthDiff} maxSampleDiff=${curves.check.maxSamplePointDiff}`);
  console.log(`golden: report at ${opt.report}`);
}

function writeReport(file, m, swept) {
  const L = [];
  L.push("# Golden vectors report");
  L.push("");
  L.push(`Generated ${m.generatedAt} by \`tools/golden\` (Node, three@${m.three.npm}, REVISION ${m.three.revision}). Output: \`data/golden/\`. Re-run: \`node tools/golden/src/golden.js\` (see \`tools/golden/README.md\`).`);
  L.push("");
  L.push("## Provenance");
  L.push("");
  L.push(`Every function is a byte-exact copy of \`reference/v5_4_game.js\` lines, generated by \`tools/golden/gen_original.py\` into \`tools/golden/src/original.js\` and re-verified at run time (verified: **${m.reference.verified.verified}**, ${m.reference.verified.blocks} blocks):`);
  L.push("");
  L.push("| block | lines | sha256 | what |");
  L.push("|---|---|---|---|");
  for (const b of m.reference.verbatimBlocks) L.push(`| ${b.name} | L${b.from}-${b.to} | \`${b.sha256.slice(0, 16)}\` | ${b.what} |`);
  L.push("");
  L.push("Glue that is ours: module-level `player`, `pitch`, `activeHouseInterior`, `time`, `crimeScenes` (set per case), the `v()` helper (L94), and `spottedPredicate(n, pos)` which wraps the verbatim statements and returns the intermediates. `trafficTravelFilterSkips` restates the L15878 filter because the original is interleaved with game state.");
  L.push("");
  L.push("## npm three@0.160.1 versus the inlined r160");
  L.push("");
  L.push(`All ${m.threeCrossCheck.routesChecked} harvested routes were rebuilt as \`CatmullRomCurve3(points, false, "centripetal")\` with the npm package: max |getLength() - harvest length| = ${m.threeCrossCheck.maxLengthDiff}, max distance between \`getSpacedPoints\` and the harvest samples = ${m.threeCrossCheck.maxSamplePointDiff}, sample-count mismatches = ${m.threeCrossCheck.sampleCountMismatch}. The npm build is therefore the same curve code as the inlined one.`);
  L.push("");
  L.push("## Vector sets");
  L.push("");
  L.push("| file | count | seed | how it was produced |");
  L.push("|---|---|---|---|");
  const how = {
    "terrain.json": "grid x -700..1200, z -700..700 step 20; 3,000 seeded random points; 600 in the river district; 300 on the bridge deck strip; 300 at the water edge (riverCenter +/- 50..54); exact boundary values at Chebyshev 104/190 and x 687/735/1150, z -244/443. Fields: base, height, riverCenter, inRiverDistrict, insideRiverWater, riverDeck",
    "curves.json": "200 harvested routes (all 12 lookouts, 12 fences, the trampoline, then seeded picks: 40 trunk, 55 branch, 25 bridge, 25 roof, 30 wire): control points, getLength, getLengths(200), getSpacedPoints(steps), and at 21 fixed + 10 random t: getUtoTmapping, getPoint, getPointAt, getTangentAt",
    "advance.json": "2,000 seeded RouteMotion.advance cases incl. seconds > 0.05 (clamped), negative seconds, length < 1 (divisor max(1, L)), forward in {-1, -0.25, 0, 0.5, 1}",
    "rail_motion.json": "60 seeded routes x 40 steps: railSpeed per routes_movement 10 (walk/sprint/stalk, boost, x0.6 on wood kinds), t clamped to [0,1] at the ends, pose = getPointAt, tangent = getTangentAt",
    "swept.json": `${swept.handCount} hand cases (sedan jump frame-by-frame parked and moving, van/trolley apex, below-box sewer, top/bottom slab edges, start inside, stationary pass-through, 180-degree flip, 90-degree snap, tunnelling, sideways dodge, NaN/Infinity, 2pi yaw wrap) + ${swept.randomCount} seeded random cases over the six fleet boxes; ${swept.hits} hits in total`,
    "segment_box_entry.json": "3,000 seeded slab-test cases incl. axis-parallel and zero-length segments; result is enter (number) or null",
    "travel_filter.json": "finishTrafficFrame per-vehicle filter over dt x travel grid incl. the 1e-5 and 12 thresholds",
    "pounce.json": "exhaustive grid: 10 heading sources (yaw values, trunk rail with trunkNormal variants incl. null default, non-trunk rail) x 26 pitches (clamp exercised) x focus x moveSpeed {0, 8, 12, 12.01, 16.8} x boost {0, 3.2}: attackHeading, pounceVelocity, jumpVelocity",
    "spotted.json": "10 hand cases (garden/hedge concealment, canopy silent vs noisy, behind near/far, crime-scene and witness radar, interior) + 3,000 seeded random cases biased to the interesting ranges; result carries every intermediate boolean",
    "junction.json": "RouteJunction.inward/canTransfer/ease at the thresholds (0.035, 0.965, 0.48, 1.7)",
    "manifest.json": "this run's metadata and file hashes",
  };
  for (const [name, f] of Object.entries(m.files)) {
    const seed = name === "terrain.json" ? m.seeds.terrain : name === "curves.json" ? m.seeds.curves : name === "advance.json" ? m.seeds.advance : name === "rail_motion.json" ? m.seeds.railMotion : name === "swept.json" ? m.seeds.swept : name === "segment_box_entry.json" ? m.seeds.segmentBox : name === "spotted.json" ? m.seeds.spotted : "";
    L.push(`| \`${name}\` | ${f.count ?? ""} | ${seed} | ${how[name] || ""} |`);
  }
  L.push("");
  L.push("All random draws use the game's own `rng(seed)` (L80-89), so the sets regenerate byte-identically. Units are HTML units; a Luau port tests in HTML units or scales inputs and outputs by 2.5 (constants inside the functions such as 0.18, -0.3, 0.16 and the 104/190/687/735 bands then scale too).");
  L.push("");
  L.push("## Location note");
  L.push("");
  L.push("BUILD_PLAN 6.3 names `tests/golden/*.json`; this task wrote them to `data/golden/` (assigned path). The Lune golden tests can read `data/golden/` directly or the lead can move the directory; nothing else depends on the location.");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, L.join("\n") + "\n");
}

main();
