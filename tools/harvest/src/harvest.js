#!/usr/bin/env node
"use strict";
// tools/harvest: run the pinned v5.4 HTML headlessly and write data/harvest/*.json.
// See README.md in this directory for the exact commands and the output inventory.
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const crypto = require("node:crypto");
const { chromium } = require("playwright");
const { buildInstrumentedHtml } = require("./instrument");
const { stringify } = require("./jsonfmt");
const { analyze } = require("./analyze");
const { writeReport } = require("./report");

const REPO = path.resolve(__dirname, "..", "..", "..");
const DEFAULTS = {
  ref: "/home/user/spicy-rodents/reference/Spicy_Rodents_v5_4_Living_Town.html",
  pretty: "/home/user/spicy-rodents/reference/v5_4_game.js",
  catalog: "/home/user/spicy-rodents/spec/data/routes_catalog.json",
  wildlife: "/home/user/spicy-rodents/spec/data/wildlife.json",
  out: path.join(REPO, "data", "harvest"),
  report: path.join(REPO, "docs", "reports", "harvest_report.md"),
  cache: path.join(__dirname, "..", ".cache"),
  sha256: "fc48b387e51ce3a454898d58d1cb3dda891b22ffad7110cdcd0ade6c777a6227",
  timeoutMs: 300000,
  runs: 2,
};

function parseArgs(argv) {
  const o = { ...DEFAULTS, variant: "both" };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === "--ref") o.ref = next();
    else if (a === "--pretty") o.pretty = next();
    else if (a === "--catalog") o.catalog = next();
    else if (a === "--wildlife") o.wildlife = next();
    else if (a === "--out") o.out = next();
    else if (a === "--report") o.report = next();
    else if (a === "--cache") o.cache = next();
    else if (a === "--sha256") o.sha256 = next();
    else if (a === "--variant") o.variant = next();
    else if (a === "--runs") o.runs = Number(next());
    else if (a === "--timeout") o.timeoutMs = Number(next());
    else if (a === "--help" || a === "-h") {
      console.log(fs.readFileSync(path.join(__dirname, "..", "README.md"), "utf8"));
      process.exit(0);
    } else throw new Error(`unknown argument ${a}`);
  }
  return o;
}

function sha256(buf) {
  return crypto.createHash("sha256").update(buf).digest("hex");
}

function serve(pages) {
  // Serves the instrumented pages from memory on 127.0.0.1 at a random free port.
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const body = pages.get(req.url);
      if (!body) {
        res.writeHead(404);
        res.end();
        return;
      }
      res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
      res.end(body);
    });
    server.listen(0, "127.0.0.1", () => resolve({ server, port: server.address().port }));
  });
}

async function runOnce(browser, url, timeoutMs, label) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const consoleLines = [];
  const pageErrors = [];
  const blocked = new Set();
  page.on("console", (m) => consoleLines.push(`[${m.type()}] ${m.text()}`));
  page.on("pageerror", (e) => pageErrors.push(String(e && e.stack ? e.stack : e)));
  // Block everything that is not our local server; the game tolerates missing online
  // assets (fonts, HDRI, bark textures, jsdelivr loaders) and keeps building the world.
  await page.route("**/*", (route) => {
    const u = route.request().url();
    if (u.startsWith(url.slice(0, url.lastIndexOf("/") + 1))) return route.continue();
    blocked.add(u.length > 120 ? u.slice(0, 120) + "..." : u);
    return route.abort("blockedbyclient");
  });
  const t0 = Date.now();
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: timeoutMs });
  await page.waitForFunction(() => window.__SR_DUMP_RESULT || window.__spicyBootOk === true || document.getElementById("spicyBootError")?.style?.display === "block", null, { timeout: timeoutMs });
  const dumpMs = Date.now() - t0;
  const json = await page.evaluate(() => (window.__SR_DUMP_RESULT ? JSON.stringify(window.__SR_DUMP_RESULT) : null));
  // give startup a moment to finish so bootOk and console lines are recorded
  await page.waitForFunction(() => window.__spicyBootOk === true, null, { timeout: 20000 }).catch(() => {});
  const bootOk = await page.evaluate(() => window.__spicyBootOk === true);
  const bootError = await page.evaluate(() => {
    const el = document.getElementById("spicyBootError");
    return el && el.style.display !== "none" && el.textContent ? el.textContent.trim().slice(0, 800) : null;
  });
  await page.close();
  if (!json) throw new Error(`${label}: no dump produced; bootError=${bootError}; errors=${pageErrors.join(" | ")}`);
  const result = JSON.parse(json);
  return { result, consoleLines, pageErrors, blocked: Array.from(blocked).sort(), dumpMs, bootOk, bootError, totalMs: Date.now() - t0 };
}

function stripVolatile(sections) {
  // Everything that legitimately differs between runs or variants: call sites (line
  // numbers differ between the minified and pretty module) and the chili peppers (random seed).
  const copy = JSON.parse(JSON.stringify(sections));
  for (const r of copy.routes) delete r.callSite;
  delete copy.peppers;
  return copy;
}

async function main() {
  const opt = parseArgs(process.argv.slice(2));
  const started = new Date();
  const htmlBuf = fs.readFileSync(opt.ref);
  const actualSha = sha256(htmlBuf);
  if (actualSha !== opt.sha256) {
    throw new Error(`SHA-256 mismatch for ${opt.ref}: expected ${opt.sha256}, got ${actualSha}. Refusing to harvest an unpinned file.`);
  }
  const html = htmlBuf.toString("utf8");
  const prettyJs = fs.readFileSync(opt.pretty, "utf8");
  const prettySha = sha256(prettyJs);
  fs.mkdirSync(opt.cache, { recursive: true });
  fs.mkdirSync(opt.out, { recursive: true });

  const variants = opt.variant === "both" ? ["html", "pretty"] : [opt.variant];
  const pages = new Map();
  const built = {};
  for (const variant of variants) {
    const b = buildInstrumentedHtml(html, variant, prettyJs);
    built[variant] = b;
    pages.set(`/${variant}.html`, b.html);
    fs.writeFileSync(path.join(opt.cache, `instrumented_${variant}.html`), b.html);
  }
  const { server, port } = await serve(pages);
  const browser = await chromium.launch({
    headless: true,
    args: ["--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
  });
  const runs = [];
  try {
    for (const variant of variants) {
      const n = variant === "html" ? Math.max(1, opt.runs) : 1;
      for (let i = 0; i < n; i++) {
        const label = `${variant}#${i + 1}`;
        process.stderr.write(`harvest: running ${label} ...`);
        const run = await runOnce(browser, `http://127.0.0.1:${port}/${variant}.html`, opt.timeoutMs, label);
        process.stderr.write(` dump after ${run.dumpMs} ms, routes=${run.result.sections.routes.length}, bootOk=${run.bootOk}\n`);
        runs.push({ variant, index: i + 1, label, ...run });
      }
    }
  } finally {
    await browser.close();
    server.close();
  }

  // Determinism: every html run must agree on everything but call sites and peppers.
  const canon = runs.map((r) => ({ label: r.label, hash: sha256(JSON.stringify(stripVolatile(r.result.sections))) }));
  const htmlRuns = runs.filter((r) => r.variant === "html");
  const primary = htmlRuns[0] || runs[0];
  const determinism = {
    runs: canon,
    allHtmlRunsIdentical: htmlRuns.every((r, i) => canon[runs.indexOf(r)].hash === canon[runs.indexOf(htmlRuns[0])].hash),
    prettyMatchesHtml: null,
    pepperSeeds: runs.map((r) => ({ label: r.label, seed: r.result.sections.peppers && r.result.sections.peppers.seed })),
  };
  const prettyRun = runs.find((r) => r.variant === "pretty");
  if (prettyRun && primary) {
    determinism.prettyMatchesHtml = canon[runs.indexOf(prettyRun)].hash === canon[runs.indexOf(primary)].hash;
  }

  // Call sites come from the pretty run (line numbers = v5_4_game.js lines).
  const S = primary.result.sections;
  if (prettyRun) {
    const off = built.pretty.bodyStartLine - 1;
    const byId = new Map(prettyRun.result.sections.routes.map((r) => [r.id, r.callSite]));
    for (const r of S.routes) {
      const cs = byId.get(r.id);
      r.callSite = cs && Number.isFinite(cs.line) ? { line: cs.line - off, col: cs.col, fn: cs.fn || null } : null;
    }
  } else {
    for (const r of S.routes) r.callSite = r.callSite ? { htmlLine: r.callSite.line, col: r.callSite.col, fn: r.callSite.fn || null } : null;
  }

  // ---- write outputs ----
  const chromeVersion = await (async () => {
    const b = await chromium.launch({ headless: true, args: ["--no-sandbox"] });
    const v = b.version();
    await b.close();
    return v;
  })();
  const pin = {
    html: { path: opt.ref, sha256: actualSha, bytes: htmlBuf.length },
    prettyJs: { path: opt.pretty, sha256: prettySha, bytes: Buffer.byteLength(prettyJs) },
    moduleStartsAtHtmlLine: built[variants[0]].bodyStartLine,
  };
  const files = {};
  const write = (name, value) => {
    const text = stringify(value);
    fs.writeFileSync(path.join(opt.out, name), text);
    files[name] = { bytes: Buffer.byteLength(text), sha256: sha256(text) };
  };
  const units = "HTML world units (1 u = 2.5 studs), +Y up, exactly as the page computed them";
  write("routes.json", { $schema: "harvest/routes v1", units, pin: pin.html, count: S.routes.length, routes: S.routes });
  write("route_samples.json", { $schema: "harvest/route_samples v1", units, note: "curve.getSpacedPoints(max(20, ceil(3*length))) per route; [id, [[x,y,z],...]]", count: S.routeSamples.length, samples: S.routeSamples });
  write("route_index.json", { $schema: "harvest/route_index v1", note: "routeSpatial cells, insertion order; each entry is [routeId, sampleIndex]", ...S.routeIndex });
  write("forks.json", { $schema: "harvest/forks v1", units, note: "canopyForks after rebuildCanopyForks(); forks sorted by height as in the game", trunkCount: S.canopyForks.length, forkCount: S.canopyForks.reduce((a, f) => a + f.forks.length, 0), trunks: S.canopyForks });
  write("trees.json", { $schema: "harvest/trees v1", units, count: S.trees.length, trees: S.trees, treeSpec: S.treeSpec, giantTreeSpecs: S.giantTreeSpecs, outerTreeCandidates: S.outerTreeCandidates, giantPerches: S.giantPerches, estateGateTreeTips: S.estateGateTreeTips, westTrees: S.westTrees });
  write("utility.json", { $schema: "harvest/utility v1", units, supportCount: S.utilitySupports.length, verifiedByGame: S.verifiedUtilityPoles, supports: S.utilitySupports, residentialPoles: S.poles, westPoleTops: S.westPoleTops, wireRouteIds: S.routes.filter((r) => r.kind === "wire").map((r) => r.id) });
  write("nests.json", { $schema: "harvest/nests v1", units, count: S.nests.length, nests: S.nests, birdCount: S.birdCount });
  write("apple_trees.json", { $schema: "harvest/apple_trees v1", units, count: S.appleTrees.length, appleTrees: S.appleTrees });
  write("houses.json", { $schema: "harvest/houses v1", units, houseCount: S.houses.length, houses: S.houses, outerHomesTable: S.outerHomes, commercialBounds: S.commercialBounds, houseDoors: S.houseDoors, riverBuildings: S.riverBuildings });
  write("colliders.json", { $schema: "harvest/colliders v1", units, obstacles: S.obstacles, fenceCollisions: S.fenceCollisions, mallColliders: S.mallColliders, estateProjects: S.estateProjects });
  write("world.json", { $schema: "harvest/world v1", units, buildInfo: S.buildInfo, worldHalf: S.worldHalf, river: S.river, pavementZones: S.pavementZones, concealment: { hedgePatches: S.hedgePatches, garden: S.garden }, tabascoPlants: S.tabascoPlants, counts: { humanoids: S.humanoidCount, noveltyCast: S.noveltyCastCount, birds: S.birdCount } });
  write("vehicles_initial.json", { $schema: "harvest/vehicles v1", units, note: "state at the dump point (after world build, before the first tick)", cars: S.cars, tallVehicles: S.tallVehicles, heavyTraffic: S.heavyTraffic, streetVehicles: S.streetVehicles, motorcycles: S.motorcycles });
  write("fauna.json", { $schema: "harvest/fauna v1", units, dogs: S.dogs, yardCats: S.yardCats, chainedDogs: S.chainedDogs, normalSquirrels: S.normalSquirrels, rabbits: S.rabbits });
  write("peppers_nondeterministic.json", { $schema: "harvest/peppers v1", units, WARNING: "Chili pepper hiding places use pepperSeed = crypto.getRandomValues (L5314-5320): they change on every page load and are NOT part of the deterministic world. Recorded for information only; never consume these positions.", runs: runs.map((r) => ({ label: r.label, seed: r.result.sections.peppers.seed, list: r.result.sections.peppers.list })) });

  const analysis = analyze(S, { catalogPath: opt.catalog, wildlifePath: opt.wildlife });
  write("graph.json", { $schema: "harvest/graph v1", units, note: "DERIVED by tools/harvest/src/analyze.js (not game state): islands by the 1.7 u sample rule and endpoint auto-links by the 0.48 u end-window rule [routes_movement section 3]", ...analysis.graph });

  const manifest = {
    $schema: "harvest/manifest v1",
    generatedAt: started.toISOString(),
    tool: "tools/harvest v0.1.0",
    pin,
    environment: { node: process.version, playwright: require("playwright/package.json").version, chromium: chromeVersion, gl: "ANGLE SwiftShader (headless, --use-angle=swiftshader)", platform: process.platform },
    seeds: {
      world: "rng(20261008) at L90 (global `random`, `R`, `pick`)",
      perTree: "rng(spec.seed) at L1763 (makeTree) and rng(seed) at L2825 (estateGateOak)",
      neighborhoodDetail: "rng(51903) at L12980",
      river: "rng(5110726) at L13450",
      coins: "rng(5300811) at L14892",
      livingTown: "rng(540811) at L15133 (apple trees, nests, birds)",
      peppers: "rng(pepperSeed), pepperSeed from crypto.getRandomValues at L5314: NOT deterministic; excluded",
      runtimeOnly: "Math.random() is used only by runtime behaviour (spawns, bites, waits), never by world construction",
    },
    runs: runs.map((r) => ({ label: r.label, variant: r.variant, dumpMs: r.dumpMs, totalMs: r.totalMs, bootOk: r.bootOk, bootError: r.bootError, dumpOk: r.result.ok, dumpErrors: r.result.errors, inPageDumpMs: Math.round(r.result.dumpMs), consoleLines: r.consoleLines, pageErrors: r.pageErrors, blockedRequests: r.blocked })),
    determinism,
    counts: analysis.counts,
    files,
  };
  write("manifest.json", manifest);
  manifest.files = files; // includes manifest itself now (self hash omitted)
  writeReport(opt.report, { manifest, analysis, S });
  console.log(`harvest: wrote ${Object.keys(files).length} files to ${opt.out}`);
  console.log(`harvest: report at ${opt.report}`);
  const bad = analysis.counts.comparisons.filter((c) => c.status !== "match");
  if (bad.length) {
    console.log(`harvest: ${bad.length} count comparison(s) did not match:`);
    for (const c of bad) console.log(`  - ${c.what}: expected ${c.expected}, got ${c.actual} (${c.status})`);
    process.exitCode = 2;
  }
  if (!determinism.allHtmlRunsIdentical) {
    console.log("harvest: WARNING the html runs differ outside the known-volatile sections");
    process.exitCode = 3;
  }
}

main().catch((e) => {
  console.error(e && e.stack ? e.stack : e);
  process.exit(1);
});
