"use strict";
const fs = require("node:fs");
const path = require("node:path");

function table(rows, cols) {
  const head = "| " + cols.map((c) => c.title).join(" | ") + " |";
  const sep = "|" + cols.map(() => "---").join("|") + "|";
  const body = rows.map((r) => "| " + cols.map((c) => String(c.get(r)).replace(/\|/g, "\\|")).join(" | ") + " |");
  return [head, sep, ...body].join("\n");
}

function writeReport(file, { manifest, analysis, S }) {
  const m = manifest;
  const c = analysis.counts;
  const lines = [];
  lines.push("# Harvest report: v5.4 reference capture");
  lines.push("");
  lines.push(`Generated ${m.generatedAt} by \`tools/harvest\`. Output: \`data/harvest/\`. Re-run: \`node tools/harvest/src/harvest.js\` (see \`tools/harvest/README.md\`).`);
  lines.push("");
  lines.push("## Pin");
  lines.push("");
  lines.push(`- HTML: \`${m.pin.html.path}\``);
  lines.push(`- SHA-256: \`${m.pin.html.sha256}\` (${m.pin.html.bytes} bytes); the tool refuses to run on any other hash.`);
  lines.push(`- Pretty-printed module used for call-site line numbers: \`${m.pin.prettyJs.path}\` (SHA-256 \`${m.pin.prettyJs.sha256}\`). The module embedded in the HTML is byte-identical to \`reference/v5_4_game.min.js\`; the pretty file is prettier output of the same code, and the dump from both variants is identical (see Determinism).`);
  lines.push(`- Environment: Node ${m.environment.node}, Playwright ${m.environment.playwright}, Chromium ${m.environment.chromium}, ${m.environment.gl}.`);
  lines.push("");
  lines.push("## Seeds");
  lines.push("");
  for (const [k, v] of Object.entries(m.seeds)) lines.push(`- **${k}**: ${v}`);
  lines.push("");
  lines.push("Pepper seeds observed per run (never equal, by design): " + m.determinism.pepperSeeds.map((p) => `${p.label}=${p.seed}`).join(", ") + ". The 8 chili positions are written to `peppers_nondeterministic.json` with a warning and are excluded from every other file.");
  lines.push("");
  lines.push("## Runs");
  lines.push("");
  lines.push(table(m.runs, [
    { title: "run", get: (r) => r.label },
    { title: "dump after", get: (r) => `${r.dumpMs} ms` },
    { title: "in-page dump", get: (r) => `${r.inPageDumpMs} ms` },
    { title: "total", get: (r) => `${r.totalMs} ms` },
    { title: "boot ok", get: (r) => r.bootOk },
    { title: "dump ok", get: (r) => r.dumpOk },
    { title: "page errors", get: (r) => r.pageErrors.length },
    { title: "blocked requests", get: (r) => r.blockedRequests.length },
  ]));
  lines.push("");
  const r0 = m.runs[0];
  lines.push("Console lines from the first run (duplicates collapsed):");
  lines.push("");
  const collapsed = new Map();
  for (const l of r0.consoleLines) collapsed.set(l, (collapsed.get(l) || 0) + 1);
  for (const [l, n] of Array.from(collapsed.entries()).slice(0, 40)) lines.push("    " + (n > 1 ? `(x${n}) ` : "") + l.replace(/\n/g, " "));
  if (r0.pageErrors.length) {
    lines.push("");
    lines.push("Page errors from the first run:");
    for (const l of r0.pageErrors.slice(0, 10)) lines.push("    " + l.split("\n")[0]);
  }
  lines.push("");
  lines.push("Blocked external requests (first run): " + (r0.blockedRequests.length ? r0.blockedRequests.map((u) => `\`${u}\``).join(", ") : "none"));
  lines.push("");
  lines.push("## Determinism");
  lines.push("");
  lines.push(`- All html runs identical outside call sites and peppers: **${m.determinism.allHtmlRunsIdentical}**`);
  lines.push(`- Pretty-module run identical to the html run: **${m.determinism.prettyMatchesHtml}**`);
  lines.push("- Canonical hashes: " + m.determinism.runs.map((r) => `${r.label}=\`${r.hash.slice(0, 16)}\``).join(", "));
  lines.push("");
  lines.push("## Count comparisons");
  lines.push("");
  lines.push(table(c.comparisons, [
    { title: "what", get: (r) => r.what },
    { title: "expected", get: (r) => (r.expected === null ? "" : r.expected) },
    { title: "actual", get: (r) => (r.actual === null ? "" : r.actual) },
    { title: "status", get: (r) => r.status },
    { title: "note", get: (r) => r.note },
  ]));
  lines.push("");
  lines.push("Per kind (actual): " + Object.entries(c.kinds).map(([k, v]) => `${k} ${v.count} / ${v.length.toFixed(1)} u`).join("; "));
  lines.push("");
  if (analysis.callSites) {
    const cs = analysis.callSites;
    lines.push("## Routes per addRoute call site (pretty-module line numbers) vs `spec/data/routes_catalog.json`");
    lines.push("");
    lines.push(`Call sites found in the source: ${cs.callSitesInSource}; used at runtime: ${cs.callSitesUsed}; routes without attribution: ${cs.unattributedRoutes}; all rows match: **${cs.allMatch}**.`);
    lines.push("");
    lines.push(table(cs.rows, [
      { title: "line", get: (r) => r.catalogLine },
      { title: "generator", get: (r) => r.generator },
      { title: "kind", get: (r) => r.kind },
      { title: "catalog", get: (r) => r.expected },
      { title: "harvest", get: (r) => r.actual },
      { title: "status", get: (r) => r.status },
      { title: "example names", get: (r) => r.exampleNames.join("; ") },
    ]));
    if (cs.extra.length) {
      lines.push("");
      lines.push("Call sites with routes but no catalog row:");
      for (const e of cs.extra) lines.push(`- L${e.line}: ${e.count} routes (${e.kinds.join(", ")}): ${e.exampleNames.join("; ")}`);
    }
    lines.push("");
  }
  const g = analysis.graph;
  lines.push("## Connectivity (derived by the tool, `graph.json`)");
  lines.push("");
  lines.push(`- Islands by the 1.7 u sample rule: **${g.islandCount}** (spec: 149); largest island **${g.largestIsland}** routes (spec: 563); singletons ${g.singletonCount} (spec: 40 leap-only).`);
  lines.push(`- Endpoint auto-links (end windows t <= 0.07 / t >= 0.93, gap <= 0.48 u, trunks only from bridges): ${g.endLinks.length} route ends with at least one candidate; branch tips with a link: ${g.branchTipLinks} (spec: 0 of 715).`);
  lines.push("- Island sizes (top 10): " + g.islands.slice(0, 10).map((i) => i.length).join(", "));
  lines.push("");
  lines.push("## What was captured");
  lines.push("");
  lines.push(table(Object.entries(m.files).map(([name, f]) => ({ name, ...f })), [
    { title: "file", get: (r) => `\`data/harvest/${r.name}\`` },
    { title: "bytes", get: (r) => r.bytes },
    { title: "sha256", get: (r) => r.sha256.slice(0, 16) },
  ]));
  lines.push("");
  lines.push("- `routes.json`: every route in creation order: id, name, kind, speed, center, surfaceRadius, visualOffset, length, indexed, trunkClearance, control points, sample count, call site (line in `v5_4_game.js`, function).");
  lines.push("- `route_samples.json`: the game's own `getSpacedPoints` output per route (the 81,613 index samples).");
  lines.push("- `route_index.json`: the `routeSpatial` cells (8 u) with `[routeId, sampleIndex]` entries in insertion order.");
  lines.push("- `forks.json`: `canopyForks` (95 trunks) with per-fork t, height, origin, outward and the branch's trunkClearance.");
  lines.push("- `trees.json`: `trees[]` (95, apple trees included) plus the spec tables (`treeSpec`, `giantTreeSpecs`, `outerTreeCandidates`), giant perches, estate gate tree tips and Westside trees.");
  lines.push("- `utility.json`: the 110 `utilitySupports` (residential 97, estate 6, westside 7) with tops and the trunk route of each residential pole; wire route ids.");
  lines.push("- `nests.json`, `apple_trees.json`: the 24 nests (route, point) and 12 apple trees.");
  lines.push("- `houses.json`: the 24 `houses[]` records (cfg, w, d, frontZ, backZ, frontSign), the `outerHomes` table, `commercialBounds`, `houseDoors`, `riverBuildings`.");
  lines.push("- `colliders.json`: `obstacles`, `fenceCollisions`, `mallColliders`, `estateProjects`.");
  lines.push("- `world.json`: BuildInfo, WORLD_HALF, RIVER, the 48 registered pavement zones, concealment (hedge patches, garden), Tabasco plants, actor counts.");
  lines.push("- `vehicles_initial.json`, `fauna.json`: vehicle and animal registries at the dump point (before the first tick).");
  lines.push("- `graph.json`: derived islands and end links (not game state).");
  lines.push("- `manifest.json`: pin, environment, seeds, run logs, determinism, counts and file hashes.");
  lines.push("");
  lines.push("## Caveats");
  lines.push("");
  lines.push("- The instrumented copy differs from the pinned HTML in exactly two places: `addRoute` is wrapped to record its call site, and a dump runs after `rebuildCanopyForks()` and before `tick()`. No game value is changed; the dump reads registries only.");
  lines.push("- External assets (fonts, HDRI, bark textures, jsdelivr loaders) are blocked; the game tolerates that (Promise.allSettled) and world construction does not depend on them.");
  lines.push("- `trees[]` contains the 12 apple trees, so 95 is the total with apples (matches `wildlife.json`).");
  lines.push("- Vehicles are captured before the first `tick()`, so moving vehicles are at their spawn poses.");
  lines.push("- Chili peppers are random per load (crypto seed) and are flagged, not harvested.");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, lines.join("\n") + "\n");
}

module.exports = { writeReport };
