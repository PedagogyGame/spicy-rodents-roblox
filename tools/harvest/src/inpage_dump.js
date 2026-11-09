// Inserted verbatim at the end of the v5.4 game module by instrument.js.
// Everything here is hoisted function declarations, so `addRoute` (the wrapper)
// is already in place when the first route is created, and `__SR_DUMP` is callable
// from the anchor placed after rebuildCanopyForks(). No game state is modified.
/* global routes, routeSpatial, canopyForks, trees, utilitySupports, poles, houses, outerHomes,
   commercialBounds, pavementZones, hedgePatches, GARDEN_X, GARDEN_Z, livingTown, peppers,
   pepperSeed, giantPerches, estateGateTreeTips, westTrees, westPoleTops, treeSpec, giantTreeSpecs,
   outerTreeCandidates, cars, tallVehicles, heavyTraffic, obstacles, fenceCollisions, houseDoors,
   riverBuildings, mallColliders, estateProjects, tabascoPlants, dogs, yardCats, chainedDogs,
   normalSquirrels, rabbits, humanoids, noveltyCast, motorcycles, streetVehicles, BuildInfo,
   WORLD_HALF, RIVER, addRoute__orig, verifiedUtilityPoles */

function addRoute(name, points, opts = {}) {
  const route = addRoute__orig(name, points, opts);
  route.__callSite = __SR_callSite(new Error().stack);
  return route;
}

// Chrome stack frames look like "    at makeTree (http://host/game.html:1782:3)" or
// "    at http://host/game.html:733:1". Frame 0 is "Error", frame 1 is this wrapper,
// frame 2 is the addRoute call site inside the game module.
function __SR_callSite(stack) {
  const lines = String(stack || "").split("\n");
  const frame = lines[2] || "";
  const m = frame.match(/(?:at\s+(.*?)\s+\()?(?:https?:\/\/[^/]+\/[^:]*|[^\s(]+):(\d+):(\d+)\)?\s*$/);
  if (!m) return { raw: frame.trim() };
  return { fn: m[1] || null, line: Number(m[2]), col: Number(m[3]), raw: frame.trim() };
}

function __SR_DUMP() {
  const t0 = performance.now();
  const result = { ok: false, sections: {}, errors: [] };
  const routeSet = new Set(routes);
  const routeIds = new Map(routes.map((r) => [r, r.id]));
  const seen = new WeakSet();

  const num = (x) => (Number.isFinite(x) ? x : x === Infinity ? "Infinity" : x === -Infinity ? "-Infinity" : "NaN");

  // Generic, cycle-safe, depth-limited conversion to plain JSON.
  function plain(value, depth) {
    if (value === null || value === undefined) return null;
    const t = typeof value;
    if (t === "number") return num(value);
    if (t === "string" || t === "boolean") return value;
    if (t === "function" || t === "symbol" || t === "bigint") return undefined;
    if (routeSet.has(value)) return { $route: routeIds.get(value) };
    if (value.isVector3) return [num(value.x), num(value.y), num(value.z)];
    if (value.isVector2) return [num(value.x), num(value.y)];
    if (value.isColor) return "#" + value.getHexString();
    if (value.isBox3) return { min: plain(value.min, depth), max: plain(value.max, depth) };
    if (value.isCurve && Array.isArray(value.points)) {
      return { $curve: value.type, closed: !!value.closed, curveType: value.curveType, tension: value.tension, points: value.points.map((p) => plain(p, depth)) };
    }
    if (value.isObject3D) {
      return {
        $object3d: value.type,
        name: value.name || undefined,
        position: plain(value.position, depth),
        rotationY: num(value.rotation.y),
        scale: plain(value.scale, depth),
        visible: value.visible,
        children: value.children.length,
      };
    }
    if (value.isMaterial || value.isBufferGeometry || value.isTexture) return { $three: value.type };
    if (depth <= 0) return { $truncated: true };
    if (seen.has(value)) return { $cycle: true };
    // cycle detection follows the current path only (mark on entry, unmark on exit),
    // so the same object may legitimately appear in several sections (e.g. apple trees
    // are also in trees[]).
    seen.add(value);
    try {
      if (value instanceof Map) {
        const entries = [];
        for (const [k, v] of value) entries.push([plain(k, depth - 1), plain(v, depth - 1)]);
        return { $map: entries };
      }
      if (value instanceof Set) return { $set: Array.from(value, (v) => plain(v, depth - 1)) };
      if (Array.isArray(value)) {
        return value.map((v) => {
          const p = plain(v, depth - 1);
          return p === undefined ? null : p;
        });
      }
      if (t === "object") {
        const out = {};
        for (const key of Object.keys(value)) {
          if (key.startsWith("__")) continue;
          const p = plain(value[key], depth - 1);
          if (p !== undefined) out[key] = p;
        }
        return out;
      }
      return undefined;
    } finally {
      seen.delete(value);
    }
  }

  function grab(name, thunk, depth = 5) {
    try {
      const v = thunk();
      result.sections[name] = plain(v, depth);
    } catch (error) {
      result.sections[name] = { $missing: true, error: String(error && error.message ? error.message : error) };
      result.errors.push(`${name}: ${String(error && error.message ? error.message : error)}`);
    }
  }

  try {
    // ---- routes: explicit shape, samples kept separate (large) ----
    result.sections.routes = routes.map((r) => ({
      id: r.id,
      name: r.name,
      kind: r.kind,
      speed: r.speed,
      center: r.center ? [r.center.x, r.center.y, r.center.z] : null,
      surfaceRadius: r.surfaceRadius,
      visualOffset: r.visualOffset,
      length: r.length,
      indexed: !!r.indexed,
      trunkClearance: Number.isFinite(r.trunkClearance) ? r.trunkClearance : null,
      points: r.curve.points.map((p) => [p.x, p.y, p.z]),
      sampleCount: r.sampled.length,
      callSite: r.__callSite || null,
    }));
    result.sections.routeSamples = routes.map((r) => [r.id, r.sampled.map((p) => [p.x, p.y, p.z])]);

    // ---- spatial index: Map "ix,iy,iz" -> [{route, pos, t}] ----
    const cells = [];
    let entries = 0;
    for (const [key, bucket] of routeSpatial) {
      const list = bucket.map((e) => [e.route.id, Math.round(e.t * (e.route.sampled.length - 1))]);
      entries += list.length;
      cells.push([key, list]);
    }
    result.sections.routeIndex = { cellSize: 8, cellCount: cells.length, entryCount: entries, cells };

    // ---- canopy forks: Map trunk -> forks sorted by height ----
    const forks = [];
    for (const [trunk, list] of canopyForks) {
      forks.push({
        trunk: trunk.id,
        trunkName: trunk.name,
        forks: list.map((f) => ({
          branch: f.branch.id,
          branchName: f.branch.name,
          branchKind: f.branch.kind,
          t: f.t,
          height: f.height,
          origin: [f.origin.x, f.origin.y, f.origin.z],
          outward: [f.outward.x, f.outward.y, f.outward.z],
          trunkClearance: f.branch.trunkClearance,
        })),
      });
    }
    result.sections.canopyForks = forks;
  } catch (error) {
    result.errors.push("routes: " + String(error && error.stack ? error.stack : error));
  }

  grab("buildInfo", () => BuildInfo, 2);
  grab("worldHalf", () => WORLD_HALF, 1);
  grab("river", () => RIVER, 2);
  grab("trees", () => trees, 4);
  grab("treeSpec", () => treeSpec, 3);
  grab("giantTreeSpecs", () => giantTreeSpecs, 3);
  grab("outerTreeCandidates", () => outerTreeCandidates, 3);
  grab("giantPerches", () => giantPerches, 3);
  grab("estateGateTreeTips", () => estateGateTreeTips, 3);
  grab("westTrees", () => westTrees, 3);
  grab("westPoleTops", () => westPoleTops, 3);
  grab("utilitySupports", () => utilitySupports, 3);
  grab("verifiedUtilityPoles", () => verifiedUtilityPoles, 1);
  grab("poles", () => poles, 3);
  grab("houses", () => houses, 3);
  grab("outerHomes", () => outerHomes, 3);
  grab("commercialBounds", () => commercialBounds, 3);
  grab("pavementZones", () => pavementZones, 3);
  grab("hedgePatches", () => hedgePatches, 3);
  grab("garden", () => ({ x: GARDEN_X, z: GARDEN_Z }), 2);
  grab("appleTrees", () => livingTown.appleTrees, 3);
  grab("nests", () => livingTown.nests.map((n, i) => ({ index: i, route: n.route, point: n.point, groupPosition: n.group.position })), 3);
  grab("birdCount", () => livingTown.birds.length, 1);
  grab("peppers", () => ({ seed: pepperSeed, nondeterministic: true, list: peppers }), 3);
  grab("cars", () => cars, 3);
  grab("tallVehicles", () => tallVehicles, 3);
  grab("heavyTraffic", () => heavyTraffic, 3);
  grab("streetVehicles", () => streetVehicles, 3);
  grab("motorcycles", () => motorcycles, 3);
  grab("obstacles", () => obstacles, 3);
  grab("fenceCollisions", () => fenceCollisions, 3);
  grab("houseDoors", () => houseDoors, 3);
  grab("riverBuildings", () => riverBuildings, 3);
  grab("mallColliders", () => mallColliders, 3);
  grab("estateProjects", () => estateProjects, 3);
  grab("tabascoPlants", () => tabascoPlants, 3);
  grab("dogs", () => dogs, 3);
  grab("yardCats", () => yardCats, 3);
  grab("chainedDogs", () => chainedDogs, 3);
  grab("normalSquirrels", () => normalSquirrels, 3);
  grab("rabbits", () => rabbits, 3);
  grab("humanoidCount", () => humanoids.length, 1);
  grab("noveltyCastCount", () => noveltyCast.length, 1);

  result.ok = result.errors.length === 0;
  result.dumpMs = performance.now() - t0;
  window.__SR_DUMP_RESULT = result;
}
