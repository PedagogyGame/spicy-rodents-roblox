"use strict";
// Post-processing of one harvest dump: count comparisons against the specs,
// a call-site table against spec/data/routes_catalog.json, and a DERIVED
// connectivity graph (islands and endpoint auto-links) per routes_movement.md section 3/11.
const fs = require("node:fs");

// Expected values quoted from the specs (routes_movement.md section 1.4, section 3; BUILD_PLAN 4.3).
const EXPECTED = {
  routes: 1332,
  indexEntries: 81613,
  forkTrunks: 95,
  trees: 95,
  nests: 24,
  appleTrees: 12,
  utilitySupports: 110,
  residentialPoles: 97,
  houses: 24,
  pavementZones: 48,
  islands: 149,
  largestIsland: 563,
  branchTipLinks: 0,
  kinds: {
    trunk: { count: 265, length: 4086 },
    branch: { count: 715, length: 11238 },
    bridge: { count: 78, length: 1417 },
    lookout: { count: 12, length: 55 },
    roof: { count: 99, length: 1700 },
    wire: { count: 150, length: 6979 },
    fence: { count: 12, length: 920 },
    trampoline: { count: 1, length: 32 },
  },
};

class UnionFind {
  constructor(n) {
    this.p = Array.from({ length: n }, (_, i) => i);
  }
  find(a) {
    while (this.p[a] !== a) {
      this.p[a] = this.p[this.p[a]];
      a = this.p[a];
    }
    return a;
  }
  union(a, b) {
    a = this.find(a);
    b = this.find(b);
    if (a !== b) this.p[b] = a;
  }
}

function buildSampleHash(samples, cell) {
  const grid = new Map();
  const key = (x, y, z) => `${Math.floor(x / cell)},${Math.floor(y / cell)},${Math.floor(z / cell)}`;
  for (const [id, pts] of samples) {
    for (let i = 0; i < pts.length; i++) {
      const p = pts[i];
      const k = key(p[0], p[1], p[2]);
      let b = grid.get(k);
      if (!b) grid.set(k, (b = []));
      b.push([id, i, p[0], p[1], p[2]]);
    }
  }
  return { grid, key, cell };
}

function nearby(hash, x, y, z) {
  const out = [];
  const cx = Math.floor(x / hash.cell), cy = Math.floor(y / hash.cell), cz = Math.floor(z / hash.cell);
  for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) for (let k = -1; k <= 1; k++) {
    const b = hash.grid.get(`${cx + i},${cy + j},${cz + k}`);
    if (b) for (const e of b) out.push(e);
  }
  return out;
}

function computeGraph(S) {
  const routes = S.routes;
  const byId = new Map(routes.map((r) => [r.id, r]));
  const samples = S.routeSamples;
  const sampleById = new Map(samples);
  // Islands: routes linked when any sample pair is within 1.7 u (the explicit-transfer limit).
  const LINK = 1.7;
  const hash = buildSampleHash(samples, LINK);
  const uf = new UnionFind(routes.length);
  for (const [id, pts] of samples) {
    for (const p of pts) {
      for (const e of nearby(hash, p[0], p[1], p[2])) {
        if (e[0] === id) continue;
        const dx = e[2] - p[0], dy = e[3] - p[1], dz = e[4] - p[2];
        if (dx * dx + dy * dy + dz * dz <= LINK * LINK) uf.union(id, e[0]);
      }
    }
  }
  const islands = new Map();
  for (const r of routes) {
    const root = uf.find(r.id);
    if (!islands.has(root)) islands.set(root, []);
    islands.get(root).push(r.id);
  }
  const islandList = Array.from(islands.values()).map((ids) => ids.sort((a, b) => a - b)).sort((a, b) => b.length - a.length || a[0] - b[0]);
  // Endpoint auto-links (switchRoute, L5941): other routes' samples in the end windows
  // (t <= 0.07 or t >= 0.93) within 0.48 u, closest per route; trunks only reachable from bridges.
  const END = 0.48;
  const endHash = buildSampleHash(samples, 8); // the game searches 3x3x3 cells of 8 u
  const endLinks = [];
  let branchTipLinks = 0;
  for (const r of routes) {
    const pts = sampleById.get(r.id);
    for (const atStart of [true, false]) {
      const cur = atStart ? pts[0] : pts[pts.length - 1];
      const best = new Map();
      for (const e of nearby(endHash, cur[0], cur[1], cur[2])) {
        if (e[0] === r.id) continue;
        const other = byId.get(e[0]);
        const t = e[1] / (other.sampleCount - 1);
        if (t > 0.07 && t < 0.93) continue;
        const dx = e[2] - cur[0], dy = e[3] - cur[1], dz = e[4] - cur[2];
        const gap = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (gap > END) continue;
        if (other.kind === "trunk" && r.kind !== "bridge") continue;
        const prev = best.get(e[0]);
        if (!prev || gap < prev.gap) best.set(e[0], { to: e[0], t: Number(t.toFixed(6)), gap: Number(gap.toFixed(6)) });
      }
      const links = Array.from(best.values()).sort((a, b) => a.gap - b.gap || a.to - b.to);
      if (links.length) {
        endLinks.push({ from: r.id, atStart, links });
        if (r.kind === "branch" && !atStart) branchTipLinks++;
      }
    }
  }
  return {
    linkDistance: LINK,
    endWindow: { tMax: 0.07, tMin: 0.93, gap: END, trunkFilter: "trunk candidates only from kind bridge" },
    islandCount: islandList.length,
    largestIsland: islandList[0].length,
    singletonCount: islandList.filter((i) => i.length === 1).length,
    branchTipLinks,
    islands: islandList,
    endLinks,
  };
}

// Finds every addRoute( call site in the pretty JS with its [startLine, endLine] span.
function callSiteSpans(prettyJs) {
  const lines = prettyJs.split("\n");
  const spans = [];
  for (let i = 0; i < lines.length; i++) {
    const idx = lines[i].indexOf("addRoute(");
    if (idx < 0 || /function addRoute\(/.test(lines[i])) continue;
    // walk forward to the matching paren, skipping string literals
    let depth = 0, done = false, quote = null;
    for (let j = i; j < lines.length && !done; j++) {
      const s = lines[j];
      for (let c = j === i ? idx + "addRoute".length : 0; c < s.length; c++) {
        const ch = s[c];
        if (quote) {
          if (ch === "\\") c++;
          else if (ch === quote) quote = null;
          continue;
        }
        if (ch === '"' || ch === "'" || ch === "`") quote = ch;
        else if (ch === "(") depth++;
        else if (ch === ")") {
          depth--;
          if (depth === 0) {
            spans.push({ line: i + 1, endLine: j + 1 });
            done = true;
            break;
          }
        }
      }
    }
  }
  return spans;
}

function analyze(S, paths) {
  const routes = S.routes;
  const comparisons = [];
  const cmp = (what, expected, actual, note) => {
    const status = expected === null ? "info" : actual === expected ? "match" : "MISMATCH";
    comparisons.push({ what, expected, actual, status, note: note || "" });
  };
  cmp("routes", EXPECTED.routes, routes.length);
  cmp("spatial index entries", EXPECTED.indexEntries, S.routeIndex.entryCount);
  cmp("spatial index entries == sum of samples", routes.reduce((a, r) => a + r.sampleCount, 0), S.routeIndex.entryCount);
  cmp("routes indexed", routes.length, routes.filter((r) => r.indexed).length);
  cmp("canopy fork trunks", EXPECTED.forkTrunks, S.canopyForks.length);
  cmp("trees (trees[] incl. 12 apple trees)", EXPECTED.trees, S.trees.length);
  cmp("nests", EXPECTED.nests, S.nests.length);
  cmp("apple trees", EXPECTED.appleTrees, S.appleTrees.length);
  cmp("utility supports", EXPECTED.utilitySupports, S.utilitySupports.length);
  cmp("utility supports verified by the game", EXPECTED.utilitySupports, S.verifiedUtilityPoles);
  cmp("residential poles (poles[])", EXPECTED.residentialPoles, S.poles.length);
  cmp("houses (4 core + 20 outer)", EXPECTED.houses, S.houses.length);
  cmp("registered pavement zones", EXPECTED.pavementZones, S.pavementZones.length);
  cmp("peppers (nondeterministic, flagged)", 8, S.peppers && S.peppers.list ? S.peppers.list.length : null, "positions excluded from the deterministic data");
  const kinds = {};
  for (const r of routes) {
    const k = (kinds[r.kind] ||= { count: 0, length: 0 });
    k.count++;
    k.length += r.length;
  }
  for (const [kind, exp] of Object.entries(EXPECTED.kinds)) {
    const got = kinds[kind] || { count: 0, length: 0 };
    cmp(`kind ${kind} count`, exp.count, got.count);
    cmp(`kind ${kind} total length (rounded u)`, exp.length, Math.round(got.length));
  }
  cmp("route kinds present", 8, Object.keys(kinds).length);
  // validation mirrors verifyRouteRegistry (L16037)
  const bad = routes.filter((r) => !Number.isFinite(r.length) || r.length < 0.04 || r.points.length < 2 || r.sampleCount < 21);
  cmp("routes failing registry validation", 0, bad.length);
  cmp("sample counts == max(20, ceil(3L)) + 1", routes.length, routes.filter((r) => r.sampleCount === Math.max(20, Math.ceil(r.length * 3)) + 1).length);
  cmp("route ids == creation order 0..n-1", routes.length, routes.filter((r, i) => r.id === i).length);

  // trees vs wildlife.json list (x, z)
  let treeMatch = null;
  try {
    const w = JSON.parse(fs.readFileSync(paths.wildlifePath, "utf8"));
    const list = w.v54.trees.list;
    // wildlife.json rounds jittered outer-tree coordinates to 2 decimals, so match within 0.01
    const near = (a, b, tol) => Math.abs(a.x - b.x) <= tol && Math.abs(a.z - b.z) <= tol;
    const matched = list.filter((t) => S.trees.some((h) => near(h, t, 0.0051))).length;
    treeMatch = { specCount: list.length, matchedByXZ: matched };
    cmp("trees matching wildlife.json by (x,z) to 0.005", list.length, matched);
    const nestList = w.v54.nests.list;
    const nestHave = new Set(S.nests.map((n) => `${n.point[0].toFixed(2)},${n.point[2].toFixed(2)}`));
    const nestMatched = nestList.filter((n) => nestHave.has(`${n.x.toFixed(2)},${n.z.toFixed(2)}`)).length;
    cmp("nests matching wildlife.json by (x,z) to 0.01", nestList.length, nestMatched);
    const appleList = w.v54.appleTrees.list;
    cmp("apple trees matching wildlife.json by (x,z) to 0.005", appleList.length, appleList.filter((a) => S.appleTrees.some((h) => near(h, a, 0.0051))).length);
    cmp("apple tree heights matching wildlife.json to 0.005", appleList.length, appleList.filter((a) => S.appleTrees.some((h) => near(h, a, 0.0051) && Math.abs(h.H - a.H) <= 0.0051)).length);
  } catch (e) {
    comparisons.push({ what: "wildlife.json cross-check", expected: null, actual: null, status: "info", note: `skipped: ${e.message}` });
  }

  // call-site table vs routes_catalog.json
  let callSites = null;
  try {
    const catalog = JSON.parse(fs.readFileSync(paths.catalogPath, "utf8"));
    const prettyJs = fs.readFileSync(paths.prettyPath || "/home/user/spicy-rodents/reference/v5_4_game.js", "utf8");
    const spans = callSiteSpans(prettyJs);
    const spanFor = (line) => spans.find((s) => line >= s.line && line <= s.endLine);
    const counts = new Map();
    let unattributed = 0;
    for (const r of routes) {
      const line = r.callSite && r.callSite.line;
      const span = line ? spanFor(line) : null;
      if (!span) {
        unattributed++;
        continue;
      }
      const c = counts.get(span.line) || { line: span.line, count: 0, kinds: new Set(), names: new Set() };
      c.count++;
      c.kinds.add(r.kind);
      if (c.names.size < 3) c.names.add(r.name);
      counts.set(span.line, c);
    }
    const rows = catalog.map((e) => {
      const span = spanFor(e.created_at_line);
      const got = span ? counts.get(span.line) : null;
      return {
        catalogLine: e.created_at_line,
        generator: e.generator,
        kind: e.kind,
        expected: e.count_estimate,
        actual: got ? got.count : 0,
        status: got && got.count === e.count_estimate ? "match" : "MISMATCH",
        exampleNames: got ? Array.from(got.names) : [],
      };
    });
    const catalogLines = new Set(catalog.map((e) => spanFor(e.created_at_line)?.line));
    const extra = Array.from(counts.values()).filter((c) => !catalogLines.has(c.line)).map((c) => ({ line: c.line, count: c.count, kinds: Array.from(c.kinds), exampleNames: Array.from(c.names) }));
    callSites = { callSitesInSource: spans.length, callSitesUsed: counts.size, unattributedRoutes: unattributed, rows, extra, allMatch: rows.every((r) => r.status === "match") && extra.length === 0 && unattributed === 0 };
    cmp("addRoute call sites used (of 60)", 60, counts.size);
    cmp("routes attributed to a call site", routes.length, routes.length - unattributed);
    cmp("catalog rows matching per-call-site counts", catalog.length, rows.filter((r) => r.status === "match").length);
  } catch (e) {
    comparisons.push({ what: "routes_catalog.json cross-check", expected: null, actual: null, status: "info", note: `skipped: ${e.message}` });
  }

  const graph = computeGraph(S);
  cmp("islands (1.7 u sample rule)", EXPECTED.islands, graph.islandCount);
  cmp("largest island routes", EXPECTED.largestIsland, graph.largestIsland);
  cmp("branch tips with an auto-link", EXPECTED.branchTipLinks, graph.branchTipLinks);

  return {
    counts: { comparisons, kinds: Object.fromEntries(Object.entries(kinds).map(([k, v]) => [k, { count: v.count, length: Number(v.length.toFixed(3)) }])), treeMatch },
    callSites,
    graph,
  };
}

module.exports = { analyze, EXPECTED, computeGraph, callSiteSpans };
