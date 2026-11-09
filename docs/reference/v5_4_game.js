import * as THREE from "three";
const $ = (id) => document.getElementById(id);
const canvas = $("world");
const scene = new THREE.Scene();
scene.background = new THREE.Color(0xa8d0ef);
scene.fog = new THREE.Fog(0xbed6db, 310, 1050);
let renderer;
try {
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: "high-performance" });
} catch (error) {
  window.dispatchEvent(
    new ErrorEvent("error", {
      message:
        "3D graphics are unavailable in this browser. Enable hardware acceleration or open this file in a browser with WebGL support. Your game file is intact.",
    }),
  );
  throw error;
}
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.45));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.42;
const camera = new THREE.PerspectiveCamera(72, innerWidth / innerHeight, 0.12, 1500);
camera.position.set(-23, 8, -29);
const hemi = new THREE.HemisphereLight(0xe8f7ff, 0x657650, 2.1);
scene.add(hemi);
const sun = new THREE.DirectionalLight(0xfff4d6, 3.4);
sun.position.set(-80, 105, -42);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.camera.left = -880;
sun.shadow.camera.right = 790;
sun.shadow.camera.top = 630;
sun.shadow.camera.bottom = -560;
sun.shadow.camera.near = 10;
sun.shadow.camera.far = 270;
sun.shadow.bias = -0.00023;
sun.shadow.normalBias = 0.018;
sun.target.position.set(80, 0, 100);
scene.add(sun, sun.target);
const materialCache = new Map();
const mat = (c, r = 0.88, m = 0) => {
  const k = c + "|" + r + "|" + m;
  if (!materialCache.has(k))
    materialCache.set(k, new THREE.MeshStandardMaterial({ color: c, roughness: r, metalness: m }));
  return materialCache.get(k);
};
const M = {
  grass: mat("#819762"),
  grass2: mat("#607847"),
  asphalt: mat("#40484a"),
  sidewalk: mat("#c3beb1"),
  wood: mat("#806147"),
  bark: mat("#655342"),
  metal: mat("#737f85", 0.4, 0.62),
  white: mat("#dfdac8"),
  trim: mat("#efecdc"),
  black: mat("#29302f"),
  glass: new THREE.MeshPhysicalMaterial({
    color: 0x8db9bf,
    metalness: 0.08,
    roughness: 0.16,
    transparent: true,
    opacity: 0.72,
    side: THREE.DoubleSide,
  }),
  water: new THREE.MeshPhysicalMaterial({
    color: 0x63c3d0,
    metalness: 0.16,
    roughness: 0.13,
    transparent: true,
    opacity: 0.84,
  }),
  rubber: mat("#1e2525"),
  mail: mat("#486d88"),
};
function rng(seed) {
  let a = seed | 0;
  return () => {
    a += 0x6d2b79f5;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const random = rng(20261008);
const R = (a, b) => a + (b - a) * random();
const pick = (a) => a[Math.floor(random() * a.length)];
const PI = Math.PI;
const v = (x, y, z) => new THREE.Vector3(x, y, z);
// v5 rendering foundation. All gameplay routes and collisions remain independent
// of render meshes; immutable geometry can therefore be shared and batched safely.
const BuildInfo = Object.freeze({ version: "5.4", engine: "0.160.1", name: "River & Old Town" });
const RenderConfig = {
  mode: "auto",
  tier: "high",
  light: "golden",
  online: true,
  adaptiveScale: 1,
  frameMs: 16.7,
  samples: 0,
  sampleSeconds: 0,
  lastAdapt: 0,
  onlineState: "ready",
  effectsState: "basic",
  batches: 0,
  mergedMeshes: 0,
  contextLost: false,
};
try {
  const saved = JSON.parse(localStorage.getItem("spicy-render-v5") || "null");
  if (saved && ["auto", "high", "ultra", "performance"].includes(saved.mode)) RenderConfig.mode = saved.mode;
  if (saved && ["golden", "daylight", "dusk"].includes(saved.light)) RenderConfig.light = saved.light;
  if (typeof saved?.online === "boolean") RenderConfig.online = saved.online;
} catch {}
const GeometryPool = new Map();
function sharedGeometry(key, create) {
  if (!GeometryPool.has(key)) GeometryPool.set(key, create());
  return GeometryPool.get(key);
}
const BatchingStats = { before: 0, after: 0 };
function batchTreeBranches(root) {
  const groups = new Map();
  for (const ob of [...root.children]) {
    if (!ob.isMesh || ob.isInstancedMesh || ob.children.length || Array.isArray(ob.material)) continue;
    // Direct tree children are static decorative wood and fruit; leaf instances
    // retain their original identity for animation and local shadow selection.
    const key = ob.material.uuid + "|" + ob.castShadow + "|" + ob.receiveShadow;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(ob);
  }
  for (const objects of groups.values()) {
    if (objects.length < 4) continue;
    const chunks = [];
    let count = 0;
    for (const ob of objects) {
      ob.updateMatrix();
      const g = ob.geometry.index ? ob.geometry.toNonIndexed() : ob.geometry.clone();
      g.applyMatrix4(ob.matrix);
      chunks.push(g);
      count += g.attributes.position.count;
    }
    const merged = new THREE.BufferGeometry();
    for (const [key, size] of [
      ["position", 3],
      ["normal", 3],
      ["uv", 2],
    ]) {
      if (!chunks.every((g) => g.attributes[key])) continue;
      const array = new Float32Array(count * size);
      let offset = 0;
      for (const g of chunks) {
        array.set(g.attributes[key].array, offset);
        offset += g.attributes[key].array.length;
      }
      merged.setAttribute(key, new THREE.BufferAttribute(array, size));
    }
    merged.computeBoundingSphere();
    const draw = new THREE.Mesh(merged, objects[0].material);
    draw.castShadow = objects[0].castShadow;
    draw.receiveShadow = objects[0].receiveShadow;
    root.add(draw);
    for (const ob of objects) root.remove(ob);
    for (const g of chunks) g.dispose();
    BatchingStats.before += objects.length;
    BatchingStats.after++;
  }
}
function makeLeafGeometry() {
  const g = new THREE.BufferGeometry();
  g.setAttribute(
    "position",
    new THREE.Float32BufferAttribute(
      [0, -0.53, 0, -0.32, -0.1, 0, -0.27, 0.24, 0, 0, 0.57, 0, 0.27, 0.24, 0, 0.32, -0.1, 0, 0, 0.02, 0.085],
      3,
    ),
  );
  g.setAttribute(
    "uv",
    new THREE.Float32BufferAttribute([0.5, 0, 0, 0.4, 0.1, 0.7, 0.5, 1, 0.9, 0.7, 1, 0.4, 0.5, 0.5], 2),
  );
  g.setIndex([0, 1, 6, 1, 2, 6, 2, 3, 6, 3, 4, 6, 4, 5, 6, 5, 0, 6]);
  g.computeVertexNormals();
  return g;
}
const leafMaterialCache = new Map();
function leafMaterial(color) {
  if (!leafMaterialCache.has(color))
    leafMaterialCache.set(
      color,
      new THREE.MeshStandardMaterial({
        color,
        roughness: 0.86,
        side: THREE.DoubleSide,
        emissive: color,
        emissiveIntensity: 0.075,
      }),
    );
  return leafMaterialCache.get(color);
}

function mesh(geo, material, x = 0, y = 0, z = 0, parent = scene, shadow = true) {
  const a = new THREE.Mesh(geo, material);
  a.position.set(x, y, z);
  a.receiveShadow = shadow;
  a.castShadow = shadow;
  parent.add(a);
  return a;
}
function box(w, h, d, m, x, y, z, p = scene) {
  return mesh(
    sharedGeometry(`box:${w}:${h}:${d}`, () => new THREE.BoxGeometry(w, h, d)),
    m,
    x,
    y,
    z,
    p,
  );
}
function ball(radius, m, x, y, z, p = scene, s = 1) {
  let b = mesh(
    sharedGeometry(`ball:${radius}`, () => new THREE.IcosahedronGeometry(radius, 1)),
    m,
    x,
    y,
    z,
    p,
  );
  b.scale.set(s, s, s);
  return b;
}
function cyl(r1, r2, h, m, x, y, z, p = scene, n = 9) {
  return mesh(
    sharedGeometry(`cyl:${r1}:${r2}:${h}:${n}`, () => new THREE.CylinderGeometry(r1, r2, h, n)),
    m,
    x,
    y,
    z,
    p,
  );
}
function span(a, b, r1, r2, m, p = scene, n = 8) {
  let d = b.clone().sub(a);
  let ob = mesh(new THREE.CylinderGeometry(r2, r1, d.length(), n), m, 0, 0, 0, p);
  ob.position.copy(a).add(b).multiplyScalar(0.5);
  ob.quaternion.setFromUnitVectors(v(0, 1, 0), d.normalize());
  return ob;
}
function linePath(points, m, r = 0.065, segments = 40) {
  const curve = new THREE.CatmullRomCurve3(
    points.map((p) => p.clone()),
    false,
    "centripetal",
  );
  const obj = mesh(new THREE.TubeGeometry(curve, segments, r, 5, false), m);
  return { curve, obj };
}
// ROUTE REGISTRY — one owner of every navigable route and its spatial index.
// Route creation continues after the main neighborhood is built (treehouse,
// western homes, park). Index those later routes as they are created.
// Movement math is deliberately stateless: input and route geometry in, new
// route parameter out. No character, camera or NPC is allowed to own this value.
const RouteMotion = {
  advance(t, dir, forward, seconds, speed, length) {
    const dt = Math.max(0, Math.min(seconds, 0.05));
    return t + (forward * dir * dt * speed) / Math.max(1, length);
  },
};
const routes = [];
let uid = 0;
const routeSpatial = new Map();
let routeIndexLive = false;
function indexRoute(route) {
  if (route.indexed) return;
  if (!route.sampled?.length || route.sampled.some((p) => !p || ![p.x, p.y, p.z].every(Number.isFinite))) {
    throw new Error(`Invalid sampled climbing route: ${route.name}`);
  }
  for (let i = 0; i < route.sampled.length; i++) {
    const pos = route.sampled[i],
      key = `${Math.floor(pos.x / 8)},${Math.floor(pos.y / 8)},${Math.floor(pos.z / 8)}`;
    let bucket = routeSpatial.get(key);
    if (!bucket) {
      bucket = [];
      routeSpatial.set(key, bucket);
    }
    bucket.push({ route, pos, t: i / (route.sampled.length - 1) });
  }
  route.indexed = true;
}
function addRoute(name, points, opts = {}) {
  if (
    !Array.isArray(points) ||
    points.length < 2 ||
    points.some((p) => !p || ![p.x, p.y, p.z].every(Number.isFinite))
  ) {
    throw new Error(`Invalid climbing route control points: ${name}`);
  }
  const crv = new THREE.CatmullRomCurve3(
    points.map((p) => p.clone()),
    false,
    "centripetal",
  );
  const length = crv.getLength();
  if (!Number.isFinite(length) || length < 0.04)
    throw new Error(`Zero-length or malformed climbing route: ${name}`);
  const steps = Math.max(20, Math.ceil(length * 3));
  const sampled = crv.getSpacedPoints(steps);
  if (sampled.some((p) => !p || ![p.x, p.y, p.z].every(Number.isFinite)))
    throw new Error(`Invalid sampled climbing route: ${name}`);
  const route = {
    id: uid++,
    name,
    curve: crv,
    sampled,
    kind: opts.kind || "branch",
    length,
    speed: opts.speed || 1,
    center: opts.center || null,
    surfaceRadius: opts.surfaceRadius || 1.35,
    visualOffset: Number.isFinite(opts.visualOffset) ? opts.visualOffset : null,
  };
  routes.push(route);
  if (routeIndexLive) indexRoute(route);
  return route;
}
function noiseCanvas(kind) {
  const c = document.createElement("canvas");
  c.width = 256;
  c.height = 256;
  const g = c.getContext("2d");
  if (kind === "grass") {
    g.fillStyle = "#929f70";
    g.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 10000; i++) {
      const x = R(0, 256),
        y = R(0, 256);
      g.fillStyle = random() > 0.5 ? "#64774e" : "#b3b78d";
      g.globalAlpha = R(0.09, 0.34);
      g.fillRect(x, y, R(0.6, 2.5), R(1, 5));
    }
  } else if (kind === "road") {
    g.fillStyle = "#555b5b";
    g.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 15000; i++) {
      let col = Math.floor(R(55, 125));
      g.globalAlpha = 0.11;
      g.fillStyle = `rgb(${col},${col},${col})`;
      g.fillRect(R(0, 256), R(0, 256), R(0.3, 2.3), R(0.3, 2.3));
    }
  } else if (kind === "bark") {
    g.fillStyle = "#736354";
    g.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 2200; i++) {
      g.strokeStyle = pick(["#392f2a", "#4d4035", "#b5a58e", "#625043"]);
      g.globalAlpha = R(0.11, 0.65);
      g.lineWidth = R(0.3, 2.4);
      let x = R(0, 256),
        y = R(0, 256);
      g.beginPath();
      g.moveTo(x, y);
      g.lineTo(x + R(-4, 4), y + R(10, 90));
      g.stroke();
    }
  } else if (kind === "roof") {
    g.fillStyle = "#796c64";
    g.fillRect(0, 0, 256, 256);
    for (let y = 0; y < 256; y += 12) {
      for (let x = y % 24 ? 0 : -13; x < 256; x += 27) {
        g.fillStyle = pick(["#756963", "#91817c", "#6d6360", "#83736d"]);
        g.globalAlpha = R(0.4, 0.7);
        g.fillRect(x + 1, y + 1, 25, 10);
      }
    }
  }
  g.globalAlpha = 1;
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;
  return tex;
}
const grassTex = noiseCanvas("grass"),
  roadTex = noiseCanvas("road"),
  barkTex = noiseCanvas("bark"),
  roofTex = noiseCanvas("roof");
grassTex.repeat.set(70, 70);
roadTex.repeat.set(4, 28);
barkTex.repeat.set(1, 3);
roofTex.repeat.set(3, 2);
M.grass = new THREE.MeshStandardMaterial({ map: grassTex, color: 0xa2b78b, roughness: 1 });
M.asphalt = new THREE.MeshStandardMaterial({ map: roadTex, color: 0x929493, roughness: 1 });
M.bark = new THREE.MeshStandardMaterial({ map: barkTex, roughness: 1, color: 0xb6a99b });
M.roof = new THREE.MeshStandardMaterial({ map: roofTex, roughness: 0.97, color: 0xb4a49d });
// 520 x 520 playable neighborhood: more than four times the original land area.
const WORLD_HALF = 270,
  PEDESTRIAN_EDGE = 12.1;
// The original test intersection is graded. Beyond it Topeka-like ridges, hollows,
// and asymmetric rolling streets rise several meters instead of stretching flat.
const smoothstep = (t) => {
  t = THREE.MathUtils.clamp(t, 0, 1);
  return t * t * (3 - 2 * t);
};
function baseTerrainHeight(x, z) {
  const dist = Math.max(Math.abs(x), Math.abs(z));
  const blend = smoothstep((dist - 104) / 86);
  const hills =
    3.5 +
    2.5 * Math.sin(x * 0.016 + z * 0.008 + 1.1) +
    2.1 * Math.cos(z * 0.02 - x * 0.009) +
    1.45 * Math.sin(x * 0.034 + 1.3) * Math.cos(z * 0.029 - 0.8);
  return Math.max(-0.02, blend * Math.max(0.1, hills));
}
// v5.1: Bellwether Quay. The same functions describe the visible ground,
// water channel, bridge approach, and collision surfaces.
const RIVER = Object.freeze({
  startX: 687,
  endX: 1150,
  zMin: -244,
  zMax: 443,
  centerX: 850,
  halfWidth: 52,
  bankY: 8,
  waterY: 2.4,
  bedY: -2,
  bridgeZ: 0,
  deckY: 15.8,
  bridgeStart: 790,
  bridgeEnd: 910,
  rampStart: 744,
  rampEnd: 956,
});
function riverCenter(z) {
  return RIVER.centerX + 9 * Math.sin(z * 0.009);
}
function inRiverDistrict(x, z) {
  return x >= RIVER.startX && x <= RIVER.endX && z >= RIVER.zMin && z <= RIVER.zMax;
}
function insideRiverWater(x, z) {
  return inRiverDistrict(x, z) && Math.abs(x - riverCenter(z)) < RIVER.halfWidth - 1e-6;
}
function riverDeckAt(x, z) {
  if (Math.abs(z - RIVER.bridgeZ) > 7.8 || x < RIVER.rampStart || x > RIVER.rampEnd) return null;
  if (x < RIVER.bridgeStart)
    return (
      RIVER.bankY +
      ((RIVER.deckY - RIVER.bankY) * (x - RIVER.rampStart)) / (RIVER.bridgeStart - RIVER.rampStart)
    );
  if (x > RIVER.bridgeEnd)
    return (
      RIVER.deckY - ((RIVER.deckY - RIVER.bankY) * (x - RIVER.bridgeEnd)) / (RIVER.rampEnd - RIVER.bridgeEnd)
    );
  return RIVER.deckY;
}
function terrainHeight(x, z) {
  const original = baseTerrainHeight(x, z);
  if (!inRiverDistrict(x, z)) return original;
  if (insideRiverWater(x, z)) return RIVER.bedY;
  const t = THREE.MathUtils.smoothstep(x, RIVER.startX, 735);
  return original * (1 - t) + RIVER.bankY * t;
}

const terrainGeom = new THREE.PlaneGeometry(WORLD_HALF * 2, WORLD_HALF * 2, 128, 128);
terrainGeom.rotateX(-PI / 2);
const tv = terrainGeom.attributes.position;
for (let i = 0; i < tv.count; i++) tv.setY(i, terrainHeight(tv.getX(i), tv.getZ(i)) - 0.09);
terrainGeom.computeVertexNormals();
mesh(terrainGeom, M.grass);
// All street surfaces are ribbons conforming to the terrain, including gradients.
const pavementZones = [];
function registerPavement(axis, coord, width, start, end, material, offset, segments) {
  if (material === M.asphalt || material === concrete)
    pavementZones.push({ axis, coord, width, start, end, offset, segments });
}
function pavementDistance(x, z) {
  let best = Infinity;
  for (const r of pavementZones) {
    const across = r.axis === "z" ? Math.abs(x - r.coord) : Math.abs(z - r.coord);
    const along = r.axis === "z" ? z : x;
    const a = Math.max(0, across - r.width * 0.5),
      b = Math.max(0, r.start - along, along - r.end);
    best = Math.min(best, Math.hypot(a, b));
  }
  return best;
}
// Match the two rendered triangles in every road strip, including hillside grades.
function pavementHeightAt(r, x, z) {
  const across = r.axis === "z" ? x : z,
    along = r.axis === "z" ? z : x;
  const u = (across - r.coord) / r.width + 0.5;
  if (u < 0 || u > 1 || along < r.start || along > r.end) return null;
  const f = ((along - r.start) / (r.end - r.start)) * r.segments,
    i = Math.min(r.segments - 1, Math.floor(f)),
    t = f - i;
  const a = r.start + ((r.end - r.start) * i) / r.segments,
    b = r.start + ((r.end - r.start) * (i + 1)) / r.segments;
  const height = (side, p) =>
    r.axis === "z"
      ? terrainHeight(r.coord + (side * r.width) / 2, p)
      : terrainHeight(p, r.coord + (side * r.width) / 2);
  const h00 = height(-1, a),
    h10 = height(1, a),
    h01 = height(-1, b),
    h11 = height(1, b);
  return (
    r.offset +
    (u + t <= 1 ? h00 * (1 - u - t) + h10 * u + h01 * t : h10 * (1 - t) + h01 * (1 - u) + h11 * (u + t - 1))
  );
}
function outdoorSurfaceAt(x, z) {
  let y = terrainHeight(x, z) - 0.075;
  for (const r of pavementZones) {
    const h = pavementHeightAt(r, x, z);
    if (h !== null) y = Math.max(y, h);
  }
  // These four curb blocks are .23 high, centered at y=.13.
  for (const side of [-1, 1]) {
    if (
      (Math.abs(x) <= 129 && Math.abs(z - side * 10.1) <= 0.16) ||
      (Math.abs(z) <= 129 && Math.abs(x - side * 10.1) <= 0.16)
    )
      y = Math.max(y, 0.245);
  }
  return y;
}
const utilitySupports = [];
function verifyUtilityPlacement() {
  const wrong = utilitySupports.filter((p) => pavementDistance(p.x, p.z) < 0.95);
  if (wrong.length)
    throw new Error(
      "Street poles overlap pavement: " +
        wrong
          .slice(0, 8)
          .map((p) => `${p.label}@${p.x},${p.z}`)
          .join("; "),
    );
  return utilitySupports.length;
}
function roadRibbon(axis, coord, width, material, offset = 0.055) {
  registerPavement(axis, coord, width, -WORLD_HALF, WORLD_HALF, material, offset, 104);
  const vertices = [],
    indexes = [],
    N = 104;
  for (let i = 0; i <= N; i++) {
    const t = -WORLD_HALF + (2 * WORLD_HALF * i) / N;
    for (let k of [-1, 1]) {
      const x = axis === "z" ? coord + (k * width) / 2 : t,
        z = axis === "z" ? t : coord + (k * width) / 2;
      vertices.push(x, terrainHeight(x, z) + offset, z);
    }
    if (i < N) {
      const j = i * 2;
      axis === "z"
        ? indexes.push(j, j + 2, j + 1, j + 1, j + 2, j + 3)
        : indexes.push(j, j + 1, j + 2, j + 1, j + 3, j + 2);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
  g.setIndex(indexes);
  const uv = [];
  for (let i = 0; i < vertices.length; i += 3) uv.push(vertices[i] / 16, vertices[i + 2] / 112);
  g.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  g.computeVertexNormals();
  return mesh(g, material, 0, 0, 0, scene, false);
}
const concrete = mat("#c8c4b7");
for (const x of [0, -180, 178]) {
  roadRibbon("z", x, 18, M.asphalt);
  for (const s of [-1, 1]) roadRibbon("z", x + s * 12.1, 3.3, concrete, 0.09);
}
for (const z of [0, -174, 171]) {
  roadRibbon("x", z, 18, M.asphalt);
  for (const s of [-1, 1]) roadRibbon("x", z + s * 12.1, 3.3, concrete, 0.09);
}
// Core raised curbs, pavement joints and a striped crossing at the intersection.
for (const dir of [-1, 1]) {
  box(258, 0.23, 0.32, mat("#aaa79c"), 0, 0.13, dir * 10.1);
  box(0.32, 0.23, 258, mat("#aaa79c"), dir * 10.1, 0.13, 0);
}
for (let i = -117; i <= 117; i += 5.8)
  for (let side of [-1, 1]) {
    box(0.04, 0.016, 3.4, mat("#a6a79d"), i, 0.098, side * 12.1);
    box(3.4, 0.016, 0.04, mat("#a6a79d"), side * 12.1, 0.098, i);
  }
for (const s of [-1, 1])
  for (const t of [-1, 1])
    for (let i = 0; i < 5; i++) {
      box(0.76, 0.016, 0.17, mat("#e0ddd1"), s * (11 + i * 1.2), 0.13, t * 8.6);
      box(0.17, 0.016, 0.76, mat("#e0ddd1"), s * 8.6, 0.13, t * (11 + i * 1.2));
    }
for (const sx of [-1, 1])
  for (const sz of [-1, 1]) {
    box(1.25, 0.04, 0.67, mat("#444743", 0.65, 0.55), sx * 16, 0.12, sz * 9.7);
  }

// ------ v0.6 EAST COMMERCIAL DISTRICT (contiguous playable ground) ------
// Continues the residential arterial eastward. The old neighborhood is untouched.
const eastExtension = new THREE.PlaneGeometry(446, 488, 100, 94);
eastExtension.rotateX(-PI / 2);
eastExtension.translate(464, 0, 0);
const eastVerts = eastExtension.attributes.position;
for (let i = 0; i < eastVerts.count; i++)
  eastVerts.setY(i, terrainHeight(eastVerts.getX(i), eastVerts.getZ(i)) - 0.083);
eastExtension.computeVertexNormals();
mesh(eastExtension, M.grass);
function districtRibbon(axis, coord, width, start, end, material, offset = 0.07) {
  registerPavement(axis, coord, width, start, end, material, offset, 95);
  const verts = [],
    inds = [],
    segments = 95;
  for (let i = 0; i <= segments; i++) {
    const t = start + ((end - start) * i) / segments;
    for (const side of [-1, 1]) {
      const x = axis === "x" ? t : coord + (side * width) / 2,
        z = axis === "z" ? t : coord + (side * width) / 2;
      verts.push(x, terrainHeight(x, z) + offset, z);
    }
    if (i < segments) {
      const a = i * 2;
      axis === "z"
        ? inds.push(a, a + 2, a + 1, a + 1, a + 2, a + 3)
        : inds.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(verts, 3));
  geo.setIndex(inds);
  const uv = [];
  for (let i = 0; i < verts.length; i += 3) uv.push(verts[i] / 16, verts[i + 2] / 112);
  geo.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  geo.computeVertexNormals();
  return mesh(geo, material, 0, 0, 0, scene, false);
}
districtRibbon("x", 0, 26, 247, 681, M.asphalt, 0.065); // widened approach to the commercial intersection
for (const zz of [-17.4, 17.4]) districtRibbon("x", zz, 3.3, 249, 679, concrete, 0.13);
districtRibbon("z", 347, 29, -215, 219, M.asphalt, 0.075);
for (const xx of [329.5, 364.5]) districtRibbon("z", xx, 3.4, -212, 216, concrete, 0.135);
// Central turn lanes, dashed paint, accessible zebra walks and signal heads.
const laneWhite = mat("#e8e7da"),
  amber = mat("#e1bd59");
for (let x = 275; x < 671; x += 15)
  if (Math.abs(x - 347) > 28) box(7, 0.035, 0.13, amber, x, terrainHeight(x, 0) + 0.16, 0);
for (let z = -210; z < 215; z += 14)
  if (Math.abs(z) > 27) box(0.13, 0.03, 6, laneWhite, 347, terrainHeight(347, z) + 0.18, z);
for (const side of [-1, 1])
  for (let i = 0; i < 10; i++) {
    let x = 347 + side * 22,
      z = -11 + i * 2.5;
    box(0.72, 0.04, 1.3, laneWhite, x, terrainHeight(x, z) + 0.17, z);
    let zz = side * 22,
      xx = 335 + i * 2.6;
    box(1.35, 0.04, 0.72, laneWhite, xx, terrainHeight(xx, zz) + 0.17, zz);
  }
function signCanvas(text, bg = "#713528", fg = "#fff3d8") {
  const canvas = document.createElement("canvas");
  canvas.width = 512;
  canvas.height = 160;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, 512, 160);
  ctx.fillStyle = fg;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.font = "bold 88px Arial";
  ctx.fillText(text, 256, 88, 490);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return new THREE.MeshStandardMaterial({
    map: tex,
    roughness: 0.7,
    emissive: new THREE.Color(bg),
    emissiveIntensity: 0.14,
    side: THREE.DoubleSide,
  });
}
const districtSigns = [];
const commercialBounds = [];
function flatSign(text, x, y, z, w = 14, h = 4, bg = "#713528", fg = "#fff3d8", turn = 0) {
  // Residential / road wayfinding signs should be sized for humans, not billboards.
  const roadGuide =
    /PARK|CEMETERY|GARDEN|HOSPITAL|EMERGENCY ENTRANCE/i.test(text) &&
    !/SQUIRREL BITES|HOSPITAL  ·/i.test(text);
  if (roadGuide) {
    // Highway/destination markers are modest signs at pedestrian-eye level.
    w = Math.min(8.1, Math.max(5.2, w * 0.26));
    h = Math.min(1.32, Math.max(0.89, h * 0.34));
    y = terrainHeight(x, z) + 2.68;
    for (const dx of [-w * 0.34, w * 0.34])
      cyl(0.064, 0.072, 2.66, M.metal, x + dx, terrainHeight(x + dx, z) + 1.33, z);
  }
  const surf = box(w, h, 0.13, signCanvas(text, bg, fg), x, y, z);
  surf.rotation.y = turn;
  districtSigns.push(surf);
  return surf;
}
function trafficSignal(x, z) {
  const by = terrainHeight(x, z);
  cyl(0.13, 0.18, 10, M.metal, x, by + 5, z);
  const sx = x + (x < 347 ? 2.2 : -2.2);
  span(v(x, by + 9.2, z), v(sx, by + 9.2, z), 0.12, 0.12, M.metal);
  const g = new THREE.Group();
  g.position.set(sx, by + 8.6, z);
  scene.add(g);
  box(0.8, 2.3, 0.65, M.black, 0, 0, 0, g);
  for (let j = 0; j < 3; j++) {
    const color = [0xc53227, 0xe9a62d, 0x478a48][j];
    ball(0.22, mat("#" + color.toString(16).padStart(6, "0")), 0, 0.73 - j * 0.72, 0.38, g);
  }
}
for (const [x, z] of [
  [321, -29],
  [371, 29],
  [372, -28],
  [320, 29],
])
  trafficSignal(x, z);
// Chili's-style restaurant, with distinctive roof, patio, big readable sign and parking.
const restaurantBase = terrainHeight(474, -82),
  restaurant = new THREE.Group();
restaurant.position.set(474, restaurantBase, -82);
scene.add(restaurant);
const tanStucco = mat("#b9a48f"),
  brickRed = mat("#844c42"),
  awnRed = mat("#b23b33");
box(52, 10.2, 31, tanStucco, 0, 5.1, 0, restaurant);
box(54, 1.35, 33, brickRed, 0, 10.3, 0, restaurant);
box(56, 0.55, 34, mat("#504e46"), 0, 11.1, 0, restaurant);
commercialBounds.push({ x: 474, z: -82, w: 52, d: 31, roof: restaurantBase + 11.5 });
addRoute(
  "Chili’s restaurant rooftop",
  [v(449, restaurantBase + 11.62, -82), v(499, restaurantBase + 11.62, -82)],
  { kind: "roof" },
);
// Visible glazed restaurant front looks toward the main commercial road (+z).
for (let ix = -20; ix <= 20; ix += 8) {
  box(5.1, 5.9, 0.22, M.glass, ix, 5, 15.62, restaurant);
  box(0.13, 6, 0.31, M.metal, ix - 2.55, 5, 15.74, restaurant);
}
box(5, 6.8, 0.3, mat("#684a36"), 0, 3.5, 15.8, restaurant);
box(3.7, 5.7, 0.33, M.glass, 0, 3.3, 16.0, restaurant);
for (const side of [-1, 1]) {
  box(14, 0.85, 4.1, awnRed, side * 16, 8.1, 17.8, restaurant);
  box(0.28, 3.7, 0.28, M.metal, side * 16, 4.6, 20.0, restaurant);
}
// Long red billboard on the restaurant roof with white legible lettering.
flatSign("CHILI'S", 474, restaurantBase + 14.15, -65.3, 18, 3.2, "#a72e29", "#fff1cf");
flatSign("GRILL & BAR", 474, restaurantBase + 12.1, -65.2, 14, 1.35, "#53312a", "#ffdea8");
// Patio: tables, low planters, parasols, plants, windows & booths through glass.
for (let i = 0; i < 5; i++) {
  const px = 432 + i * 14,
    pz = -48 + (i % 2) * 5,
    by = terrainHeight(px, pz);
  cyl(1.45, 1.45, 0.15, mat("#9b7e63"), px, by + 1.1, pz);
  cyl(0.12, 0.13, 1.0, M.metal, px, by + 0.54, pz);
  for (let j = 0; j < 3; j++) {
    const a = (j * PI * 2) / 3;
    box(0.68, 0.14, 0.65, mat("#b7ac95"), px + Math.cos(a) * 2.5, by + 0.5, pz + Math.sin(a) * 2.5);
  }
  if (i % 2 === 0) {
    cyl(0.08, 0.09, 2.65, M.metal, px, by + 2.45, pz);
    let roof = new THREE.Mesh(new THREE.ConeGeometry(3.1, 1.1, 9), awnRed);
    roof.position.set(px, by + 3.9, pz);
    scene.add(roof);
  }
}
for (let j = 0; j < 8; j++) {
  const xx = 438 + j * 10,
    z = -24,
    y = terrainHeight(xx, z);
  box(0.15, 0.04, 6, laneWhite, xx, y + 0.16, z);
}
// Main gas station: consistent forecourt, north-facing market entrance, compact
// price tower, low-poly pump detail, and a reachable rooftop traversal course.
const gasGround = terrainHeight(522, 110),
  market = new THREE.Group();
market.position.set(522, gasGround, 110);
scene.add(market);
const stationCream = mat("#ded9c7"),
  stationGreen = mat("#346d5b"),
  stationTrim = mat("#294f48");
const stationConcrete = mat("#b9b8ad"),
  pumpDark = mat("#253840"),
  pumpLight = mat("#ecede1");
box(33, 8.2, 23, stationCream, 0, 4.1, 0, market);
box(35, 1, 25, stationTrim, 0, 8.7, 0, market);
// Raised parapet and shop entrance are on the side facing the fuel islands.
for (const side of [-1, 1]) box(0.38, 1.1, 25, stationGreen, side * 17.2, 9.4, 0, market);
box(35, 1.1, 0.38, stationGreen, 0, 9.4, -12.1, market);
commercialBounds.push({ x: 522, z: 110, w: 33, d: 23, roof: gasGround + 9.5 });
addRoute(
  "gas station shop roof",
  [v(506, gasGround + 9.62, 110), v(522, gasGround + 9.62, 110), v(538, gasGround + 9.62, 110)],
  { kind: "roof" },
);
for (const xx of [-11, -3, 5, 12]) {
  box(5.0, 4.0, 0.12, M.glass, xx, 4.2, -11.65, market);
  box(5.3, 0.21, 0.22, stationGreen, xx, 6.32, -11.78, market);
}
// Doors are visible but are not represented as enterable rooms in this build.
box(2.65, 4.6, 0.13, pumpDark, 1.1, 2.45, -11.86, market);
box(2.1, 3.9, 0.14, M.glass, 1.1, 2.73, -11.96, market);
box(0.11, 0.64, 0.1, M.metal, 2.04, 2.85, -12.04, market);
box(12.5, 0.65, 0.9, stationGreen, -8.2, 1.55, -12.55, market);
flatSign("FUEL MARKET", 522, gasGround + 9.65, 97.65, 14, 1.45, "#2e6552", "#f8f3dc");
flatSign("OPEN", 522 + 12.6, gasGround + 5.9, 97.7, 2.8, 0.83, "#335e51", "#f7ead3");
// The apron uses small terrain-following panels, not a single hovering slab.
const canopyBy = terrainHeight(476, 63);
for (let px = 445; px <= 508; px += 9)
  for (let pz = 47; pz <= 79; pz += 8) {
    const h = terrainHeight(px, pz);
    box(8.85, 0.12, 7.85, stationConcrete, px, h + 0.08, pz);
  }
// Four columns visually support the canopy, with readable safety paint.
for (const px of [448, 504])
  for (const pz of [50, 76]) {
    const h = terrainHeight(px, pz),
      supportTop = canopyBy + 9.65;
    const height = Math.max(6.5, supportTop - h);
    cyl(0.3, 0.37, height, M.metal, px, h + height / 2, pz);
    box(0.81, 0.78, 0.81, mat("#d5ae3a"), px, h + 0.48, pz);
  }
box(68, 1.12, 31, mat("#eee9d8"), 476, canopyBy + 10.18, 63);
box(68, 0.32, 31, stationGreen, 476, canopyBy + 9.55, 63);
for (const cz of [47.6, 78.4]) box(68, 0.49, 0.32, mat("#e5bd57"), 476, canopyBy + 10.62, cz);
flatSign("FUEL", 476, canopyBy + 10.61, 78.7, 8.2, 1.35, "#2b6854", "#f5f1db");
// Actual walkable roof routes cross on the slab instead of floating above it.
const canopyWalkY = canopyBy + 10.84;
addRoute(
  "fuel canopy east west",
  [v(445, canopyWalkY, 63), v(476, canopyWalkY, 63), v(507, canopyWalkY, 63)],
  { kind: "roof" },
);
addRoute(
  "fuel canopy crosswalk",
  [v(476, canopyWalkY, 48.5), v(476, canopyWalkY, 63), v(476, canopyWalkY, 77.4)],
  { kind: "roof" },
);
const ladderX = 504,
  ladderZ = 76,
  ladderY = terrainHeight(ladderX, ladderZ);
for (const xx of [-0.4, 0.4])
  span(
    v(ladderX + xx, ladderY + 0.25, ladderZ + 0.85),
    v(ladderX + xx, canopyWalkY, ladderZ + 0.85),
    0.055,
    0.055,
    M.metal,
  );
for (let h = 1; h <= 9; h++) box(0.83, 0.095, 0.12, mat("#9da6a1"), ladderX, ladderY + h, ladderZ + 0.86);
addRoute(
  "fuel canopy service ladder",
  [
    v(ladderX, ladderY + 0.4, ladderZ + 0.85),
    v(ladderX, canopyWalkY, ladderZ + 0.85),
    v(ladderX, canopyWalkY, ladderZ + 0.02),
  ],
  { kind: "trunk", surfaceRadius: 0.18 },
);
addRoute("fuel ladder roof link", [v(ladderX, canopyWalkY, ladderZ + 0.02), v(504, canopyWalkY, 63)], {
  kind: "bridge",
});
// Two pump islands with six dispensers, nozzles, hoses and protective bollards.
const pumpFace = signCanvas("87  89  93", "#274f4f", "#e9ecd9");
for (const px of [452, 474, 496])
  for (const pz of [55, 70]) {
    const h = terrainHeight(px, pz),
      color = mat(px === 474 ? "#ca5744" : "#477e81");
    box(5.2, 0.2, 3.8, mat("#a3a59d"), px, h + 0.17, pz);
    box(1.55, 2.85, 1.65, color, px, h + 1.68, pz);
    box(1.32, 0.66, 0.105, pumpFace, px, h + 2.55, pz + 0.89);
    box(1.24, 0.45, 0.12, pumpDark, px, h + 1.87, pz + 0.9);
    box(1.48, 0.17, 1.78, pumpLight, px, h + 3.17, pz);
    for (const side of [-1, 1]) {
      span(
        v(px + side * 0.81, h + 2.3, pz + 0.05),
        v(px + side * 1.2, h + 0.98, pz + 0.72),
        0.056,
        0.052,
        M.black,
      );
      box(0.12, 0.43, 0.15, pumpDark, px + side * 1.2, h + 1.05, pz + 0.73);
      cyl(0.14, 0.15, 1.05, mat("#cfb84e"), px + side * 2.15, h + 0.62, pz + 1.06);
    }
  }
// Scale the roadside information tower to match the human-sized forecourt.
const stationSignX = 411,
  stationSignZ = 91,
  ssY = terrainHeight(stationSignX, stationSignZ);
cyl(0.15, 0.19, 7.4, M.metal, stationSignX, ssY + 3.7, stationSignZ);
flatSign("FUEL", stationSignX, ssY + 7.5, stationSignZ, 6.8, 1.43, "#2e7057", "#f5f6e6");
flatSign("MARKET", stationSignX, ssY + 5.9, stationSignZ, 6.25, 0.98, "#f2ece0", "#35644b");
flatSign("OPEN", stationSignX, ssY + 4.85, stationSignZ, 5.2, 0.74, "#315a4b", "#fff8e8");
// Air/water station and waste container near the building, away from pumps.
const serviceY = terrainHeight(505, 91);
box(1.65, 2.45, 1.2, stationTrim, 505, serviceY + 1.35, 91);
box(1.2, 0.65, 0.1, pumpFace, 505, serviceY + 1.95, 91.68);
box(2.3, 2.8, 2.0, mat("#61756a"), 535, terrainHeight(535, 93) + 1.4, 93);
// One more diner / storefront creates depth behind the commercial strip.
const shopY = terrainHeight(609, -94);
box(36, 9.1, 28, mat("#a0b1ad"), 605, shopY + 4.55, -94);
box(38, 1.5, 30, mat("#504f4b"), 605, shopY + 9.75, -94);
commercialBounds.push({ x: 605, z: -94, w: 36, d: 28, roof: shopY + 10.7 });
addRoute("corner shops roof", [v(589, shopY + 10.9, -94), v(621, shopY + 10.9, -94)], { kind: "roof" });
for (let j = 0; j < 3; j++) box(7, 5.3, 0.2, M.glass, 592 + j * 13, shopY + 4.0, -79.8);
flatSign("CORNER SHOPS", 605, shopY + 10.5, -79.4, 21, 2.0, "#4e625e", "#fff8db");
// A modest parking lot and painted bays between gas station and restaurant.
for (const zz of [139, -135])
  for (let xx = 410; xx < 645; xx += 15) {
    const yy = terrainHeight(xx, zz);
    box(0.09, 0.04, 6, mat("#d5d7ce"), xx, yy + 0.16, zz);
  }

// A vast bright sky with thin high cirrus cloud bands.
const sky = new THREE.Mesh(
  new THREE.SphereGeometry(1200, 24, 16),
  new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    uniforms: { top: { value: new THREE.Color("#509ed9") }, bottom: { value: new THREE.Color("#e8f4f7") } },
    vertexShader:
      "varying vec3 p;void main(){p=position;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}",
    fragmentShader:
      "varying vec3 p;uniform vec3 top;uniform vec3 bottom;void main(){float a=clamp((normalize(p).y+.17)*.85,0.,1.);gl_FragColor=vec4(mix(bottom,top,smoothstep(.0,1.,a)),1.);}",
  }),
);
scene.add(sky);
const cloudmat = new THREE.MeshBasicMaterial({
  color: 0xffffff,
  transparent: true,
  opacity: 0.15,
  depthWrite: false,
});
for (let i = 0; i < 34; i++) {
  const cloud = mesh(
    new THREE.SphereGeometry(1, 10, 7),
    cloudmat,
    R(-330, 330),
    R(95, 155),
    R(-330, 330),
    scene,
    false,
  );
  cloud.scale.set(R(12, 39), R(0.28, 0.8), R(1.4, 4));
  cloud.rotation.y = R(-0.9, 0.9);
}
const houses = [];
const houseDoors = [];
const props = [];
const obstacles = [];
const fenceCollisions = [];
function addWindow(parent, x, y, z, w, h, dark = false, back = false) {
  let frame = box(w + 0.35, h + 0.35, 0.13, mat("#eee9dc"), x, y, z, parent);
  let glassmat = new THREE.MeshStandardMaterial({
    color: dark ? 0x7eacb6 : 0x9cae99,
    metalness: 0.13,
    roughness: 0.19,
    emissive: dark ? 0x061a24 : 0x806437,
    emissiveIntensity: dark ? 0.1 : 0.19,
  });
  box(w, h, 0.16, glassmat, x, y, z + Math.sign(z || 1) * 0.11, parent);
  box(0.1, h, 0.25, M.trim, x, y, z + Math.sign(z || 1) * 0.26, parent);
  box(w, 0.08, 0.25, M.trim, x, y, z + Math.sign(z || 1) * 0.26, parent);
  // interior curtains, room lights and hints of furniture behind transparent panes
  if (!dark) {
    const curtain = mat(pick(["#d8b8a4", "#e1cfb2", "#c7d3c3"]));
    box(0.14, h * 0.8, 0.06, curtain, x - w * 0.4, y, z - Math.sign(z || 1) * 0.25, parent);
    box(0.14, h * 0.8, 0.06, curtain, x + w * 0.4, y, z - Math.sign(z || 1) * 0.25, parent);
  }
  return frame;
}
function localRoof(parent, width, depth, base, peak, roofMaterial) {
  // roof gable running x, ridge along x
  const rise = peak - base;
  const shape = new THREE.BufferGeometry();
  const A = [
    -width / 2 - 0.65,
    base,
    -depth / 2 - 0.8,
    width / 2 + 0.65,
    base,
    -depth / 2 - 0.8,
    width / 2 + 0.65,
    peak,
    0,
    -width / 2 - 0.65,
    peak,
    0,
    -width / 2 - 0.65,
    peak,
    0,
    width / 2 + 0.65,
    peak,
    0,
    width / 2 + 0.65,
    base,
    depth / 2 + 0.8,
    -width / 2 - 0.65,
    base,
    depth / 2 + 0.8,
  ];
  const faces = [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7];
  let pos = [];
  for (let i of faces) pos.push(...A.slice(i * 3, i * 3 + 3));
  shape.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  const roofUV = [];
  for (let i = 0; i < pos.length; i += 3) roofUV.push(pos[i] / 7, pos[i + 2] / 5);
  shape.setAttribute("uv", new THREE.Float32BufferAttribute(roofUV, 2));
  shape.computeVertexNormals();
  let roof = mesh(shape, roofMaterial, 0, 0, 0, parent);
  roof.material.side = THREE.DoubleSide;
  for (let side of [-1, 1]) {
    let tri = new THREE.Shape();
    tri.moveTo(-depth / 2 - 0.8, base);
    tri.lineTo(depth / 2 + 0.8, base);
    tri.lineTo(0, peak);
    let geom = new THREE.ShapeGeometry(tri);
    let g = mesh(geom, mat("#d6cfc2"), side * (width / 2 + 0.67), 0, 0, parent);
    g.rotation.y = (side * PI) / 2;
    g.rotation.z = PI / 2;
  }
  return roof;
}
function doorway(parent, z, w = 2.2) {
  box(w + 0.4, 3.4, 0.2, M.trim, 0, 1.7, z, parent);
  box(w, 3.15, 0.22, mat("#584a3e"), 0, 1.58, z + 0.19, parent);
  ball(0.11, mat("#caa566", 0.35, 0.5), w * 0.36, 1.65, z + 0.38, parent);
  box(4, 0.25, 2.5, mat("#a9a094"), 0, 0.24, z + 1, parent);
  box(1, 0.16, 2.8, mat("#8a8476"), 0, 0.16, z + 2.1, parent);
}
function buildHouse(id, x, z, style, faceSign) {
  const g = new THREE.Group();
  g.position.set(x, 0, z);
  g.scale.setScalar(0.82);
  scene.add(g);
  let cfg = [
    {
      wall: "#ded7b7",
      trim: "#f5ecd5",
      roof: "#63524c",
      w: 22,
      d: 19,
      h: 8.9,
      peak: 13.5,
      kind: "VICTORIAN",
    },
    { wall: "#b6c1b1", trim: "#f2ecdf", roof: "#686a60", w: 24, d: 20, h: 7.4, peak: 10.4, kind: "BUNGALOW" },
    {
      wall: "#bb8e71",
      trim: "#e4d6c5",
      roof: "#615653",
      w: 22,
      d: 20,
      h: 9.1,
      peak: 13.1,
      kind: "BRICK HOUSE",
    },
    {
      wall: "#aebbc4",
      trim: "#f4e8cf",
      roof: "#6f6f75",
      w: 21,
      d: 18,
      h: 8.0,
      peak: 11.6,
      kind: "BLUE COTTAGE",
    },
  ][style];
  const wall = mat(cfg.wall),
    trim = mat(cfg.trim),
    rmat = new THREE.MeshStandardMaterial({
      map: roofTex,
      color: cfg.roof,
      roughness: 0.96,
      side: THREE.DoubleSide,
    });
  const h = cfg.h,
    w = cfg.w,
    d = cfg.d,
    front = (-faceSign * d) / 2;
  // Four actual rooms with an opening for the front door. Do not use a solid
  // full-house box: pedestrians now physically go through the doorway.
  const portalW = 2.6,
    portalH = 3.5,
    wallT = 0.24;
  const houseCeiling = box(w, wallT, d, wall, 0, h - 0.12, 0, g);
  box(w, 0.23, d, mat("#b3aa92"), 0, 0.115, 0, g);
  box(w, h, wallT, wall, 0, h / 2, -front, g);
  for (const side of [-1, 1]) box(wallT, h, d, wall, side * (w / 2 - wallT / 2), h / 2, 0, g);
  for (const side of [-1, 1])
    box((w - portalW) / 2, h, wallT, wall, (side * (w + portalW)) / 4, h / 2, front, g);
  box(portalW, h - portalH, wallT, wall, 0, portalH + (h - portalH) / 2, front, g);
  // Warm indoor floor, a lamp and basic furniture are visible through an open door.
  box(3.9, 0.09, 5.5, mat("#977f68"), 0, 0.19, front + faceSign * 2.5, g);
  box(1.7, 0.64, 0.75, mat("#766b5c"), -3.3, 0.55, front + faceSign * 3.1, g);
  ball(0.22, new THREE.MeshBasicMaterial({ color: 0xf6d698 }), 2.9, 2.7, front + faceSign * 3.2, g);
  box(w + 0.5, 0.28, d + 0.5, mat("#b8b2a3"), 0, 0.12, 0, g);
  for (let yy = 0.75; yy < h; yy += 0.54) {
    if (style !== 2)
      for (let zz of [-d / 2 - 0.018, d / 2 + 0.018]) box(w, 0.028, 0.029, mat(cfg.wall), 0, yy, zz, g);
  }
  if (style === 2) {
    for (let xx = -w / 2; xx < w / 2; xx += 0.77)
      for (let yy = 0.7; yy < h; yy += 0.37) {
        if (random() < 0.37)
          box(
            0.66,
            0.045,
            0.06,
            mat(pick(["#a6795d", "#cd9c75", "#ae816c"])),
            xx + (Math.round(yy / 0.37) % 2) * 0.25,
            yy,
            -d / 2 - 0.09,
            g,
          );
      }
  }
  for (const side of [-1, 1]) {
    for (let k = -1; k <= 1; k += 2) {
      const zz = (side * d) / 2 + 0.11;
      addWindow(g, k * w * 0.28, 3.7, zz, 3.6, 3.25, random() < 0.3);
      if (h > 8) addWindow(g, k * w * 0.28, 7.1, zz, 2.9, 2.25, random() < 0.25);
    }
  }
  for (let side of [-1, 1]) {
    for (let k = -1; k <= 1; k += 2) {
      let win = box(0.16, 3.0, 2.5, M.trim, side * (w / 2 + 0.16), 3.7, k * d * 0.25, g);
      const pane = box(0.22, 2.65, 2.12, M.glass, side * (w / 2 + 0.22), 3.7, k * d * 0.25, g);
      pane.material = M.glass;
    }
  }
  // Doors on the street-facing side, porches, gutters, downspouts.
  const frontZ = front + (front < 0 ? -0.16 : 0.16);
  // Hinge at the left jamb. Opening actually exposes the portal in the wall.
  const doorPivot = new THREE.Group();
  doorPivot.position.set(-1.12, 0, frontZ);
  g.add(doorPivot);
  box(2.24, 3.32, 0.14, mat(id % 2 ? "#597e77" : "#5b4239"), 1.12, 1.68, 0, doorPivot);
  ball(0.09, mat("#c7b777", 0.28, 0.55), 1.86, 1.62, front < 0 ? -0.1 : 0.1, doorPivot);
  box(2.75, 0.2, 0.24, trim, 0, 3.45, frontZ, g);
  // Door world-space waypoint lies just OUTSIDE the street-facing wall.
  const outsideZ = z + (front - faceSign * 1.25) * 0.82;
  const thresholdZ = z + front * 0.82;
  const insideZ = z + (front + faceSign * 2.15) * 0.82;
  houseDoors[id] = {
    id,
    pivot: doorPivot,
    open: 0,
    hold: 0,
    sign: faceSign,
    homeX: x,
    homeZ: z,
    outside: v(x, terrainHeight(x, outsideZ) + 0.13, outsideZ),
    threshold: v(x, terrainHeight(x, thresholdZ) + 0.13, thresholdZ),
    inside: v(x, terrainHeight(x, insideZ) + 0.13, insideZ),
  };
  for (let k of [-1, 1]) {
    const p = box(1.8, 1.6, 1.6, mat("#7f897a"), k * 2.15, 0.85, front + faceSign * 0.3, g);
    p.visible = false;
  }
  box(w + 1, 0.14, 0.26, trim, 0, h - 0.15, frontZ, g);
  box(w + 1, 0.18, 0.2, trim, 0, h - 0.17, -frontZ, g);
  const houseRoof = localRoof(g, w, d, h, cfg.peak, rmat);
  for (let side of [-1, 1]) {
    box(0.1, h, d, trim, side * (w / 2 + 0.05), h / 2, 0, g);
  }
  // Chimneys, satellite dish and roof vents.
  if (style !== 1) {
    const cx = -w * 0.28;
    box(1.6, 3, 1.6, mat(style === 2 ? "#97715f" : "#b7aea4"), cx, h + 1.1, d * 0.2, g);
    box(2, 0.28, 2, M.black, cx, h + 2.55, d * 0.2, g);
  }
  for (let k = 0; k < 2; k++)
    cyl(0.1, 0.11, 0.9, M.metal, R(-w * 0.25, w * 0.25), cfg.peak - 0.6, R(-2, 2), g);
  // Street-facing steps and a generous back deck; retain distinct parcel details.
  const stepZ = front - faceSign * 3.5;
  for (let n = 0; n < 3; n++)
    box(4 + n * 0.5, 0.26, 0.75, mat("#a7a399"), 0, 0.14 + n * 0.18, stepZ + faceSign * n * 0.54, g);
  const backZ = (faceSign * d) / 2;
  box(
    id === 0 ? 20 : 12,
    0.26,
    id === 0 ? 9 : 4.5,
    mat("#8b6b50"),
    0,
    1.0,
    backZ + faceSign * (id === 0 ? 4.5 : 2.3),
    g,
  );
  for (let k = -1; k <= 1; k++) {
    box(0.18, 2, 0.18, M.wood, k * (id === 0 ? 9 : 5), 2, backZ + faceSign * (id === 0 ? 8.5 : 4.4), g);
  }
  if (id === 0) {
    // long, covered porch with rails, cafe furniture and BBQ
    box(20, 0.26, 9, mat("#d8ccb8"), 0, 4.9, backZ + faceSign * 4.4, g);
    for (let xx of [-9, 0, 9]) box(0.36, 4, 0.36, trim, xx, 3, backZ + faceSign * 8.4, g);
    for (let xx = -8; xx <= 8; xx += 1.1) box(0.07, 0.8, 0.12, M.wood, xx, 1.7, backZ + faceSign * 8.2, g);
    box(18, 0.1, 0.17, M.wood, 0, 2.2, backZ + faceSign * 8.2, g);
  }
  // Small interior silhouettes through rear windows: cream kitchen cabinetry and warm lamps.
  box(3.1, 1, 1.1, mat("#ded5bf"), 3.6, 1.45, backZ - faceSign * 1.0, g);
  box(2.2, 0.9, 0.8, mat("#776351"), -3.6, 1.15, backZ - faceSign * 1.2, g);
  ball(
    0.24,
    new THREE.MeshStandardMaterial({ color: 0xffe6a6, emissive: 0xffd67a, emissiveIntensity: 2 }),
    -3.6,
    3,
    backZ - faceSign * 0.8,
    g,
  );
  const roofY = (lx, lz) => {
    const roofbase = h;
    return roofbase + (cfg.peak - h) * Math.max(0, 1 - Math.abs(lz) / (d / 2 + 0.8));
  };
  houses.push({
    id,
    g,
    x,
    z,
    cfg: { ...cfg, h: cfg.h * 0.82, peak: cfg.peak * 0.82 },
    w: w * 0.82,
    d: d * 0.82,
    roofY: (lx, lz) => 0.82 * roofY(lx / 0.82, lz / 0.82),
    backZ: z + backZ * 0.82,
    frontZ: z + front * 0.82,
    frontSign: faceSign,
    indoorCeiling: houseCeiling,
    indoorRoof: houseRoof,
    interiorObstacles: [],
    indoorName: ["Victorian", "Bungalow", "Brick House", "Blue Cottage"][id],
  });
  obstacles.push({ x, z, w: w * 0.82, d: d * 0.82, h: h * 0.82 });
  // roof ridge becomes a traversal rail (with extra movement from the adjacent tree)
  addRoute(
    `${cfg.kind} ridge`,
    [
      v(x - w * 0.48 * 0.82, (cfg.peak + 0.32) * 0.82, z),
      v(x, (cfg.peak + 0.32) * 0.82, z),
      v(x + w * 0.48 * 0.82, (cfg.peak + 0.32) * 0.82, z),
    ],
    { kind: "roof" },
  );
  return houses.at(-1);
}
const hNW = buildHouse(0, -56, -53, 0, -1),
  hNE = buildHouse(1, 51, -59, 1, -1),
  hSW = buildHouse(2, -53, 51, 2, 1),
  hSE = buildHouse(3, 58, 56, 3, 1);
// Yard plants, hedge shapes, pavement, paths, flowerbeds, benches, planters.
const shrubM = [mat("#527b46"), mat("#628b4d"), mat("#8e9c5b"), mat("#557849")];
for (let sx of [-1, 1])
  for (let sz of [-1, 1]) {
    const cx = sx * 56,
      cz = sz * 53;
    const hedgeMat = pick(shrubM);
    for (let i = 0; i < 10; i++) {
      const x = cx + R(-23, 23),
        z = cz + R(-23, 25);
      if (Math.abs(x) < 18 || Math.abs(z) < 18 || (Math.abs(x - cx) < 14 && Math.abs(z - cz) < 12)) continue;
      const s = R(0.42, 1.2);
      ball(s, hedgeMat, x, s * 0.67, z, scene, R(0.9, 1.3));
    }
    for (let i = 0; i < 32; i++) {
      let fx = cx + R(-28, 28),
        fz = cz + R(-25, 30);
      if (Math.abs(fx) < 18 || Math.abs(fz) < 19 || (Math.abs(fx - cx) < 13 && Math.abs(fz - cz) < 11))
        continue;
      let stem = cyl(0.025, 0.025, 0.5, mat("#547c42"), fx, 0.35, fz);
      const petal = pick(["#e8a09a", "#ead58f", "#e4e6d9", "#c7accf"]);
      ball(0.17, mat(petal), fx, 0.62, fz);
    }
  }
for (const h of houses) {
  // Front walk oriented toward cross street; driveway offset by house.
  const front = Math.sign(h.z) * -1;
  box(
    2.7,
    0.07,
    Math.abs(h.z) - 16 - h.d / 2,
    concrete,
    h.x,
    0.14,
    h.z + front * (Math.abs(h.z) - 16 - h.d / 2) * 0.5 + (front * h.d) / 2,
  );
  const dx = h.x + (h.x < 0 ? -17 : 17);
  box(5.3, 0.06, 26, mat("#b6b5a8"), dx, 0.135, h.z + front * 13);
  for (let k = 0; k < 6; k++) box(5.25, 0.009, 0.05, mat("#9b988c"), dx, 0.17, h.z + front * (k * 4 + 2));
  // Yard lamps, address plaques, curbside mailbox with flag.
  const mbz = h.z + front * (h.d / 2 + 11);
  cyl(0.12, 0.12, 1.25, M.wood, h.x + 4, 0.77, mbz);
  box(0.9, 0.54, 1.36, M.mail, h.x + 4, 1.51, mbz);
  box(0.04, 0.51, 0.11, mat("#b74938"), h.x + 4.51, 1.73, mbz);
  box(1, 0.45, 0.12, mat("#c2c5b9"), h.x - 2.6, 2.35, h.z + front * (h.d / 2 + 0.33));
}
// Distinct fences: some cedar privacy sections, some airy wire mesh.
function woodenFence(x1, z1, x2, z2, height = 2) {
  fenceCollisions.push({ x1, z1, x2, z2, height });
  const A = v(x1, 0, z1),
    B = v(x2, 0, z2);
  const len = A.distanceTo(B);
  const along = B.clone().sub(A).normalize();
  const fenceGroup = new THREE.Group();
  scene.add(fenceGroup);
  const count = Math.ceil(len / 0.49);
  const boards = new THREE.InstancedMesh(new THREE.BoxGeometry(0.44, height, 0.115), mat("#ffffff"), count);
  const dummy = new THREE.Object3D();
  const colors = ["#8c745a", "#967c61", "#7d664e", "#a08868"].map((c) => new THREE.Color(c));
  for (let k = 0; k < count; k++) {
    let pp = A.clone().addScaledVector(along, k * 0.49);
    dummy.position.set(pp.x, height / 2, pp.z);
    dummy.rotation.set(0, Math.atan2(-along.z, along.x), 0);
    dummy.scale.set(1, R(0.97, 1.04), 1);
    dummy.updateMatrix();
    boards.setMatrixAt(k, dummy.matrix);
    boards.setColorAt(k, pick(colors));
  }
  boards.castShadow = boards.receiveShadow = true;
  boards.instanceMatrix.needsUpdate = true;
  fenceGroup.add(boards);
  for (let d = 0; d <= len; d += 3.3) {
    let p = A.clone().addScaledVector(along, d);
    cyl(0.11, 0.13, height + 0.1, mat("#786348"), p.x, height / 2, p.z, fenceGroup);
  }
  let pA = v(x1, height + 0.1, z1),
    pB = v(x2, height + 0.1, z2);
  addRoute("cedar fence top", [pA, pB], { kind: "fence" });
}
function chainFence(x1, z1, x2, z2, height = 1.9) {
  fenceCollisions.push({ x1, z1, x2, z2, height });
  const a = v(x1, 0, z1),
    b = v(x2, 0, z2),
    dist = a.distanceTo(b);
  let dir = b.clone().sub(a).normalize();
  let screen = new THREE.Group();
  scene.add(screen);
  let meshmat = new THREE.MeshBasicMaterial({
    color: 0xb3b6a7,
    transparent: true,
    opacity: 0.34,
    side: THREE.DoubleSide,
    depthWrite: false,
  });
  let geo = new THREE.PlaneGeometry(dist, height, Math.ceil(dist * 0.8), Math.ceil(height * 4));
  let net = mesh(geo, meshmat, (x1 + x2) / 2, height / 2, (z1 + z2) / 2, screen, false);
  net.rotation.y = Math.atan2(dir.z, dir.x);
  for (let i = 0; i <= dist; i += 3.1) {
    let p = a.clone().addScaledVector(dir, i);
    cyl(0.055, 0.055, height + 0.12, M.metal, p.x, height / 2, p.z, screen);
  }
  span(v(x1, height, z1), v(x2, height, z2), 0.06, 0.06, M.metal, screen);
  addRoute("chain-link fence top", [v(x1, height + 0.14, z1), v(x2, height + 0.14, z2)], { kind: "fence" });
}
woodenFence(-83, -40, -83, -91);
woodenFence(-83, -91, -20, -91);
chainFence(20, -91, 84, -91);
chainFence(84, -91, 84, -42);
woodenFence(-83, 42, -83, 94);
chainFence(-82, 94, -22, 94);
woodenFence(20, 92, 84, 92);
chainFence(84, 92, 84, 39);
// The previous cross-driveway fence segments at z=±40 trapped parked cars.
// Leave both side driveways open; perimeter/backyard fences remain intact.
// Backyard functional objects: covered porch / barbecue, pool / loungers, guesthouse / trampoline, doghouse / mower.
function barbecue(x, z, scale = 1) {
  const p = new THREE.Group();
  p.position.set(x, 0, z);
  p.scale.setScalar(scale);
  scene.add(p);
  box(2.1, 1.15, 1.1, mat("#3b4342", 0.5, 0.6), 0, 1.4, 0, p);
  box(2.3, 0.2, 1.3, mat("#1d2221", 0.3, 0.65), 0, 2.05, 0, p);
  box(0.09, 1.2, 1, M.metal, 1.1, 1.4, 0, p);
  for (let i = 0; i < 3; i++) cyl(0.035, 0.035, 0.45, mat("#c0b59e"), -0.6 + i * 0.6, 2.2, 0, p);
  cyl(0.55, 0.52, 0.75, M.metal, 1.7, 1.1, 0.4, p);
  box(0.8, 0.55, 0.15, mat("#b86a37"), 1.7, 1.13, 0.8, p);
  for (let xx of [-0.7, 0.7]) for (let zz of [-0.4, 0.4]) cyl(0.11, 0.11, 0.5, M.black, xx, 0.48, zz, p);
}
barbecue(-62, -81);
barbecue(-57, -81, 0.67);
const barrel = mat("#343b41", 0.4, 0.6);
cyl(0.53, 0.56, 1.25, barrel, -38, 0.8, -83);
span(v(-38, 1.45, -83), v(-38.5, 2.0, -83), 0.08, 0.08, M.metal);
function chair(x, z, angle = 0) {
  const group = new THREE.Group();
  group.position.set(x, 0, z);
  group.rotation.y = angle;
  scene.add(group);
  box(1.6, 0.1, 2.6, mat("#e4d9c4"), 0, 0.72, 0, group);
  box(1.6, 0.12, 0.9, mat("#e4d9c4"), 0, 1.1, -1.45, group).rotation.x = -0.5;
  for (let sx of [-1, 1])
    for (let sz of [-1, 1]) box(0.06, 0.73, 0.09, M.metal, sx * 0.7, 0.39, sz * 0.9, group);
}
// Swimming pool cutout illusion: inset water framed by coping and a pale floor.
box(14, 0.15, 20, mat("#d6d0c0"), 55, 0.07, -84);
box(11.7, 0.08, 17.7, mat("#9aceca"), 55, 0.16, -84);
const water = box(11.2, 0.028, 17.1, M.water, 55, 0.25, -84);
for (let i = 0; i < 11; i++) {
  const foam = box(
    R(0.5, 2.5),
    0.016,
    0.045,
    new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: R(0.12, 0.28) }),
    R(50, 60),
    0.28,
    R(-92, -76),
  );
  foam.rotation.y = R(-0.6, 0.6);
}
for (let i = 0; i < 4; i++) chair(41 + i * 3.5, -75, PI / 2);
for (let q of [-1, 1]) {
  span(v(49, 0.8, -79 + q * 3), v(49, 0.5, -79 + q * 3), 0.08, 0.08, M.metal);
  span(v(49, 0.8, -79 + q * 3), v(50, 0.8, -79 + q * 3), 0.08, 0.08, M.metal);
}
// Guest cottage.
const guest = box(12, 5.2, 11, mat("#e7d8bf"), -58, 2.6, 83);
const guestRoof = box(13, 0.55, 12.3, mat("#8c746c"), -58, 5.6, 83);
addWindow(scene, -60, 2.7, 77.35, 2.6, 2.4, false);
box(2, 3.4, 0.18, M.wood, -55, 1.8, 77.35);
box(7, 0.09, 4.5, mat("#c9beb0"), -58, 0.1, 76);
function trampoline(x, z) {
  const group = new THREE.Group();
  group.position.set(x, 0, z);
  scene.add(group);
  const hoopM = mat("#252c32"),
    pole = mat("#9eadaf", 0.4, 0.5);
  let hoop = new THREE.Mesh(new THREE.TorusGeometry(5.1, 0.14, 8, 36), hoopM);
  hoop.rotation.x = PI / 2;
  hoop.position.y = 1.45;
  group.add(hoop);
  cyl(4.95, 4.95, 0.06, mat("#1d282b"), 0, 1.45, 0, group, 35);
  for (let i = 0; i < 12; i++) {
    let a = (i * PI) / 6,
      xp = Math.cos(a) * 5.1,
      zp = Math.sin(a) * 5.1;
    span(v(xp, 0, zp), v(xp, 5.8, zp), 0.055, 0.055, pole, group);
    if (i % 3 === 0) span(v(xp, 1.45, zp), v(xp - 0.2, 0.2, zp - 0.2), 0.07, 0.07, pole, group);
  }
  for (let y = 2; y <= 5.8; y += 0.34) {
    let meshline = new THREE.Mesh(
      new THREE.TorusGeometry(5.12, 0.01, 4, 60),
      new THREE.MeshBasicMaterial({ color: 0x8c9da1, transparent: true, opacity: 0.21 }),
    );
    meshline.rotation.x = PI / 2;
    meshline.position.y = y;
    group.add(meshline);
  }
  const guard = new THREE.Mesh(new THREE.TorusGeometry(5.12, 0.12, 8, 45), pole);
  guard.rotation.x = PI / 2;
  guard.position.y = 5.9;
  group.add(guard);
  addRoute(
    "trampoline guardrail",
    Array.from({ length: 17 }, (_, i) =>
      v(x + Math.cos((i * PI) / 8) * 5.12, 5.97, z + Math.sin((i * PI) / 8) * 5.12),
    ),
    { kind: "trampoline" },
  );
  box(2, 0.1, 0.52, M.metal, 0, 0, 5.7, group);
  return group;
}
const trampolineGroup = trampoline(-33, 80);
// Doghouse with roof, food bowl, and lawnmower waiting to become a rideable prop later.
box(4, 3.2, 4.2, mat("#976b4b"), 39, 1.6, 80);
let dr = box(4.6, 0.3, 5, mat("#584c45"), 39, 3.5, 80);
dr.rotation.z = 0.1;
box(1.45, 1.8, 0.12, M.black, 39, 0.92, 77.83);
cyl(0.54, 0.54, 0.12, mat("#bbc9cc", 0.3, 0.6), 44, 0.1, 78);
function mower(x, z) {
  let group = new THREE.Group();
  group.position.set(x, 0, z);
  scene.add(group);
  box(3.2, 0.55, 2.2, mat("#d1ae44", 0.44, 0.3), 0, 0.65, 0, group);
  box(1.1, 1.35, 1.55, mat("#3a493e"), -0.65, 1.5, 0, group);
  box(0.95, 0.16, 0.9, mat("#252b2a"), 0.9, 1.7, 0, group);
  span(v(0.85, 1.5, -0.3), v(1.3, 2.65, -0.3), 0.08, 0.08, M.black, group);
  span(v(1.3, 2.65, -0.3), v(1.4, 2.7, 0.3), 0.07, 0.07, M.black, group);
  for (let dx of [-1.18, 1.18])
    for (let dz of [-0.94, 0.94]) {
      let wheel = cyl(0.42, 0.42, 0.23, M.rubber, dx, 0.41, dz, group, 16);
      wheel.rotation.x = PI / 2;
    }
  return group;
}
mower(76, 80);
// Yard miscellany, bins, hoses, outdoor sinks, picnic tables, tire swing.
for (const z of [-76, 77])
  for (const x of [-74, 71]) {
    let bin = cyl(0.6, 0.57, 1.1, mat(pick(["#285b4a", "#3a5366", "#555850"])), x, 0.62, z);
    cyl(0.66, 0.66, 0.15, M.black, x, 1.24, z);
  }
for (let i = 0; i < 4; i++) {
  let xx = R(-76, -24),
    zz = R(-87, -71);
  box(1.7, 0.14, 1.1, M.wood, xx, 0.97, zz);
  for (let dx of [-0.7, 0.7]) box(0.12, 0.9, 0.12, M.metal, xx + dx, 0.5, zz);
}
// Cars: parked plus sparse moving cars with distinct painted body styles and actual seated drivers.
const cars = [],
  carColors = ["#658b93", "#a59a80", "#c6c7bd", "#923f33", "#59704e", "#b2b9c2", "#ccad7b"];
function makeCar(x, z, color, rot = 0, moving = false) {
  let group = new THREE.Group();
  group.position.set(x, 0, z);
  group.rotation.y = rot;
  group.scale.setScalar(0.79);
  scene.add(group);
  const paint = mat(color, 0.3, 0.46);
  box(2.75, 0.72, 5.1, paint, 0, 0.81, 0, group);
  box(2.5, 0.8, 2.95, paint, 0, 1.54, -0.35, group);
  box(2.41, 0.5, 0.075, M.glass, 0, 1.66, 1.14, group).rotation.x = -0.1;
  box(2.38, 0.54, 0.07, M.glass, 0, 1.65, -1.84, group);
  for (let side of [-1, 1]) {
    box(0.07, 0.55, 2.7, M.glass, side * 1.27, 1.61, -0.4, group);
  }
  for (let xx of [-1.3, 1.3])
    for (let zz of [-1.7, 1.7]) {
      let tire = cyl(0.54, 0.54, 0.32, M.rubber, xx, 0.48, zz, group, 16);
      tire.rotation.z = PI / 2;
      cyl(0.3, 0.3, 0.34, M.metal, xx, 0.48, zz, group, 12).rotation.z = PI / 2;
    }
  for (let xx of [-0.93, 0.93]) {
    box(0.54, 0.22, 0.15, mat("#f1dfb5", 0.22), xx, 0.86, 2.58, group);
    box(0.54, 0.16, 0.12, mat("#922f22"), xx, 0.89, -2.58, group);
  } // visible driver: head above seat and hands on steering wheel
  const skin = mat(pick(["#d8a789", "#a97753", "#c28e68", "#edbf95"]));
  ball(0.35, skin, -0.55, 1.65, 0.08, group);
  box(0.8, 0.75, 0.68, mat("#3f4a55"), -0.55, 1.15, 0.07, group);
  cyl(0.28, 0.28, 0.06, M.black, -0.55, 1.22, 0.5, group).rotation.x = PI / 2;
  cars.push({
    group,
    moving,
    velocity: R(6.5, 9.5),
    speed: 0,
    dir: rot === PI ? -1 : 1,
    lane: x,
    routeAxis: "z",
  });
  return group;
}
// Park inside each property, beyond the sidewalk and clear of fence corners.
// Cars are aligned to their own driveways, never placed on fences.
function carHitsFence(x, z, halfWidth = 1.3, halfLength = 2.5) {
  for (const f of fenceCollisions) {
    const dx = f.x2 - f.x1,
      dz = f.z2 - f.z1;
    const t = THREE.MathUtils.clamp(((x - f.x1) * dx + (z - f.z1) * dz) / (dx * dx + dz * dz), 0, 1);
    const cx = f.x1 + t * dx,
      cz = f.z1 + t * dz;
    if (Math.abs(cx - x) < halfWidth + 0.35 && Math.abs(cz - z) < halfLength + 0.35) return true;
  }
  return false;
}
for (let i = 0; i < 4; i++) {
  const hh = houses[i],
    x = hh.x + (hh.x < 0 ? -17 : 17),
    towardRoad = -Math.sign(hh.z);
  // Five units closer to the home than v0.4, with a clear separation from z=±40.
  let z = hh.z + towardRoad * 8;
  for (let retries = 0; retries < 8 && carHitsFence(x, z); retries++) z -= towardRoad * 2;
  if (carHitsFence(x, z)) throw Error("Unable to park without intersecting a fence");
  makeCar(x, z, carColors[i], i % 2 ? 0 : PI, false);
}
makeCar(-5.4, 115, carColors[5], 0, true);
makeCar(5.4, -86, carColors[3], PI, true);
// Grounded commercial parking and traffic along the new eastern arterial.
for (const [cx, cz, col, angle] of [
  [462, -29, carColors[2], 0],
  [493, -29, carColors[4], PI],
  [586, -33, carColors[6], 0],
  [558, 142, carColors[1], PI],
]) {
  const parked = makeCar(cx, cz, col, angle, false);
  parked.position.y = terrainHeight(cx, cz) + 0.04;
}
for (const [cx, cz, angle, direction] of [
  [287, -5.6, PI / 2, 1],
  [620, 5.6, -PI / 2, -1],
]) {
  const activeCar = makeCar(cx, cz, pick(carColors), angle, true);
  const car = cars[cars.length - 1];
  car.routeAxis = "x";
  car.dir = direction;
  car.velocity = R(6.5, 8.6);
  activeCar.position.y = terrainHeight(cx, cz) + 0.04;
}

const tallVehicles = [];
// Tall delivery van: visible reference for the upper jump limit (3.65 world units).
const deliveryVan = new THREE.Group();
deliveryVan.position.set(604, terrainHeight(604, 110), 110);
scene.add(deliveryVan);
const vanBody = mat("#e9e4d7"),
  vanAccent = mat("#5a7781");
box(3.0, 3.45, 5.9, vanBody, 0, 1.73, 0, deliveryVan);
box(2.8, 0.09, 3.7, vanAccent, 0, 3.53, -0.8, deliveryVan);
box(2.6, 1.24, 0.14, M.glass, 0, 2.5, 2.99, deliveryVan);
for (const side of [-1, 1])
  for (const z of [-1.8, 1.8]) {
    let w = cyl(0.61, 0.61, 0.26, M.rubber, side * 1.48, 0.55, z, deliveryVan, 14);
    w.rotation.z = PI / 2;
  }
tallVehicles.push({ group: deliveryVan, width: 3.0, length: 5.9, height: 3.65 });
// Utility poles, ceramic insulators and many webbed aerial cables.
const wireM = mat("#343d40", 0.7, 0.23),
  insulator = mat("#d6ddd0", 0.25, 0.35),
  poleMat = new THREE.MeshStandardMaterial({ map: barkTex, color: 0x88775e, roughness: 1 });
const poles = [],
  poleLookup = new Map();
function poleKey(x, z) {
  return `${x.toFixed(2)},${z.toFixed(2)}`;
}
// Every support is built at its FINAL position.  The pole mesh, trunk route and
// all cable endpoints share that coordinate; no post-hoc mesh relocation.
function pole(x, z) {
  const k = poleKey(x, z);
  if (poleLookup.has(k)) return poleLookup.get(k);
  const clearance = pavementDistance(x, z);
  if (clearance < 0.95)
    throw new Error(`Utility pole on street or sidewalk (${x},${z}): ${clearance.toFixed(2)}`);
  const by = terrainHeight(x, z),
    top = v(x, by + 17.05, z);
  cyl(0.3, 0.4, 17.05, poleMat, x, by + 8.525, z, scene, 10);
  span(v(x - 1.75, by + 16.35, z), v(x + 1.75, by + 16.35, z), 0.13, 0.13, poleMat);
  for (const dx of [-1.3, 0, 1.3]) cyl(0.12, 0.13, 0.27, insulator, x + dx, by + 16.56, z);
  box(0.2, 0.2, 0.2, M.metal, x, top.y + 0.1, z);
  const trunk = addRoute(`telephone pole climb ${k}`, [v(x, by + 0.48, z), v(x, by + 8.5, z), top.clone()], {
    kind: "trunk",
    surfaceRadius: 0.4,
  });
  const support = { x, z, top, trunk, label: "residential" };
  poles.push(support);
  poleLookup.set(k, support);
  utilitySupports.push(support);
  return support;
}
function droopBetween(a, b, sag = 0.6) {
  return Array.from({ length: 13 }, (_, i) => {
    const t = i / 12;
    return a
      .clone()
      .lerp(b, t)
      .add(v(0, -sag * Math.sin(t * PI), 0));
  });
}
function stringUtilityRoute(name, a, b) {
  const dist = a.top.distanceTo(b.top);
  const pts = droopBetween(a.top, b.top, Math.min(0.84, 0.26 + dist * 0.004));
  linePath(pts, wireM, 0.034, Math.max(24, Math.ceil(dist * 0.7)));
  return addRoute(name, pts, { kind: "wire" });
}
// Verge-side rows and columns. No supports at road centerlines (x=0,
// z=0, x=-180/178, z=-174/171). Long wire spans cross those streets overhead.
// Where rows and columns meet, they share an actual pole and identical endpoints.
const residentialRowX = [-244, -205, -154, -101, -50, -16.5, 16.5, 50, 101, 155, 205, 244];
const residentialColumnZ = [-244, -206, -156, -104, -51, -16.5, 16.5, 51, 104, 153, 199, 244];
const residentialRows = [-156, -16.5, 16.5, 153];
const residentialColumns = [-154, -16.5, 16.5, 155];
for (const z of residentialRows) {
  const supports = residentialRowX.map((x) => pole(x, z));
  for (let j = 1; j < supports.length; j++)
    stringUtilityRoute("east–west utility wire", supports[j - 1], supports[j]);
}
for (const x of residentialColumns) {
  const supports = residentialColumnZ.map((z) => pole(x, z));
  for (let j = 1; j < supports.length; j++)
    stringUtilityRoute("north–south telephone wire", supports[j - 1], supports[j]);
}
// Door drops start at actual street-side support heads (not old abandoned x=0 poles).
for (const h of houses) {
  const nearest = poles.reduce((best, p) => {
    const d = Math.hypot(p.x - h.x, p.z - h.frontZ);
    return !best || d < best.d ? { p, d } : best;
  }, null)?.p;
  if (!nearest) continue;
  const end = v(h.x, terrainHeight(h.x, h.frontZ) + 8.65, h.frontZ - Math.sign(h.z) * 2),
    pts = droopBetween(nearest.top, end, 1.0);
  linePath(pts, wireM, 0.022, 40);
  addRoute("house service cable", pts, { kind: "wire" });
}
// Commercial road is wider: supports stand beyond its sidewalks, at z=±21.2.
// The first span bends smoothly from the residential line into the district.
for (const side of [-1, 1]) {
  const z = side * 21.2;
  let prev = pole(244, side * 16.5);
  for (const x of [310, 369, 433, 499, 567, 631, 667]) {
    const p = pole(x, z);
    stringUtilityRoute("commercial utility span", prev, p);
    prev = p;
  }
}
// Four individually seeded, asymmetrical trees. Distinct branch bones, bark fissures,
// irregular exposed roots, crown spread and leaves + acorns (oak only).
const treeSpec = [
  {
    name: "BUR OAK",
    x: -34,
    z: -33,
    seed: 7,
    h: 29,
    crown: 20.5,
    color: ["#44763b", "#6d984d", "#547e42", "#8ba75b"],
    branches: 6,
    acorn: true,
  },
  {
    name: "AMERICAN ELM",
    x: 32,
    z: -37,
    seed: 17,
    h: 34,
    crown: 23.5,
    color: ["#5a9243", "#73a85c", "#507b3c", "#92ac5f"],
    branches: 7,
  },
  {
    name: "SYCAMORE",
    x: -37,
    z: 29,
    seed: 29,
    h: 32,
    crown: 22.5,
    color: ["#6c9a48", "#82ab54", "#5c8745", "#a9b76a"],
    branches: 6,
    sycamore: true,
  },
  {
    name: "RED MAPLE",
    x: 34,
    z: 34,
    seed: 61,
    h: 27,
    crown: 18.8,
    color: ["#658f40", "#8ca953", "#698a3b", "#acb65a"],
    branches: 7,
  },
];
const trees = [];
const canopyAnimated = [];
const canopyShadowCasters = [];
const leavesGeometry = makeLeafGeometry();
const leafPalette = [];
// Supports the original lowercase `h` tree specs as well as later `H` specs.
// A missing height used to produce NaN branch geometry and crash startup in Three.js.
function makeTree(spec) {
  const height = Number.isFinite(spec.h) ? spec.h : spec.H;
  if (
    !Number.isFinite(spec.x) ||
    !Number.isFinite(spec.z) ||
    !Number.isFinite(height) ||
    height <= 2 ||
    !Number.isFinite(spec.crown) ||
    spec.crown <= 0 ||
    !Number.isFinite(spec.branches) ||
    spec.branches < 2 ||
    !Array.isArray(spec.color) ||
    spec.color.length === 0
  ) {
    throw new Error(
      `Invalid tree specification for ${spec.name || "(unnamed)"}: height=${String(height)}, crown=${String(spec.crown)}, branches=${String(spec.branches)}`,
    );
  }
  let r = rng(spec.seed);
  const rr = (lo, hi) => lo + (hi - lo) * r();
  const x = spec.x,
    z = spec.z,
    H = height,
    treeY = terrainHeight(x, z);
  if (!Number.isFinite(treeY)) throw new Error(`Invalid terrain height for tree ${spec.name} at ${x}, ${z}`);
  const tree = new THREE.Group();
  tree.position.set(x, treeY, z);
  scene.add(tree);
  let bark = spec.sycamore ? mat("#a3a089") : M.bark;
  const trunkH = H * 0.61;
  const mainTrunk = [];
  for (let j = 0; j <= 7; j++) {
    let t = j / 7;
    mainTrunk.push(v(rr(-0.45, 0.45) * t, 0.35 + t * trunkH, rr(-0.5, 0.5) * t));
  }
  for (let j = 0; j < 7; j++)
    span(mainTrunk[j], mainTrunk[j + 1], 1.3 * (1 - j / 9), 1.3 * (1 - (j + 1) / 9), bark, tree, 11);
  addRoute(
    spec.name + " trunk",
    mainTrunk.map((a) => a.clone().add(v(x, treeY, z))),
    { kind: "trunk", speed: 0.82, center: v(x, treeY, z), surfaceRadius: 1.18 },
  );
  // Roots twist irregularly through grass, rather than looking like cylinders stuck in dirt.
  for (let k = 0; k < 8; k++) {
    const angle = (k * PI) / 4 + rr(-0.24, 0.24),
      len = rr(2.6, 5.8),
      base = v(Math.cos(angle) * 0.55, 0.29, Math.sin(angle) * 0.55),
      mid = v(Math.cos(angle) * len * 0.54, 0.3, Math.sin(angle) * len * 0.54),
      end = v(Math.cos(angle) * len, 0.03, Math.sin(angle) * len);
    span(base, mid, rr(0.22, 0.36), 0.19, bark, tree);
    span(mid, end, 0.19, 0.018, bark, tree);
    for (let q = 0; q < 2; q++) {
      let tiny = mid.clone().lerp(end, rr(0.3, 0.9));
      span(tiny, tiny.clone().add(v(rr(-1.2, 1.2), -0.15, rr(-1.2, 1.2))), 0.095, 0.018, bark, tree);
    }
  }
  const tips = [],
    branchPaths = [];
  const primaryBranchCount = Math.max(3, Math.round(spec.branches + (spec.canopyBoost ?? 0) + rr(0, 2.49)));
  for (let i = 0; i < primaryBranchCount; i++) {
    const angle = (i * 2 * PI) / primaryBranchCount + rr(-0.4, 0.4),
      s = rr(0.73, 1.05);
    const start = mainTrunk[Math.floor(rr(3.5, 5.5))].clone();
    const end = v(
      Math.cos(angle) * spec.crown * rr(0.6, 0.91),
      H * rr(0.64, 0.89),
      Math.sin(angle) * spec.crown * rr(0.57, 0.88),
    );
    const mid = start
      .clone()
      .lerp(end, 0.49)
      .add(v(rr(-1.8, 1.8), rr(1.7, 4.6), rr(-1.8, 1.8)));
    const high = end
      .clone()
      .lerp(mid, 0.23)
      .add(v(0, rr(0, 2), 0));
    const path = [start, mid, high, end];
    branchPaths.push(path);
    const c = new THREE.CatmullRomCurve3(path);
    const steps = 11;
    for (let j = 0; j < steps; j++) {
      let a = c.getPoint(j / steps),
        b = c.getPoint((j + 1) / steps);
      span(a, b, rr(0.41, 0.59) * (1 - j / steps) + 0.055, 0.37 * (1 - j / steps) + 0.035, bark, tree, 7);
    }
    addRoute(
      spec.name + " bough " + (i + 1),
      path.map((p) => p.clone().add(v(x, treeY, z))),
      { kind: "branch" },
    );
    const lateralCount = 8 + Math.floor(rr(0, 4));
    for (let b = 0; b < lateralCount; b++) {
      let t = rr(0.42, 0.95),
        at = c.getPoint(t);
      let ta = angle + rr(-1.65, 1.65);
      let e = at.clone().add(v(Math.cos(ta) * rr(2.5, 6.4), rr(0.7, 4.3), Math.sin(ta) * rr(2.2, 5.7)));
      span(at, e, rr(0.12, 0.25), 0.026, bark, tree, 6);
      tips.push(e);
      for (let j = 0; j < 3; j++) {
        let e2 = e.clone().add(v(rr(-2.1, 2.1), rr(-0.7, 2.3), rr(-2.1, 2.1)));
        span(e, e2, 0.068, 0.008, bark, tree, 5);
        tips.push(e2);
      }
    }
    // Smaller tertiary twigs are visual detail only, never another navigable rail.
    const twigCount = 6 + Math.floor(rr(0, 4));
    for (let q = 0; q < twigCount; q++) {
      const a = c.getPoint(rr(0.3, 0.91)),
        along = angle + rr(-1.8, 1.8);
      const e = a
        .clone()
        .add(v(Math.cos(along) * rr(1.2, 3.6), rr(0.6, 3.2), Math.sin(along) * rr(1.2, 3.6)));
      span(a, e, 0.085, 0.008, bark, tree, 5);
      tips.push(e);
    }
    tips.push(end);
  }
  // Branch bridges connect the actual trunk tip to the actual wire geometry.
  // No fake visual near-misses: curves share exact positions with the main routes.
  const wireRoutes = routes.filter((r) => r.kind === "wire");
  let closest = null,
    closestDistance = 1e9;
  for (const wr of wireRoutes) {
    for (const pp of wr.sampled) {
      const d = Math.hypot(pp.x - x, pp.z - z);
      if (d < closestDistance) {
        closestDistance = d;
        closest = pp;
      }
    }
  }
  if (closest && closestDistance < 49) {
    const trunkTip = mainTrunk.at(-1).clone(),
      wireAt = closest.clone().sub(v(x, treeY, z));
    const wiring = [
      trunkTip,
      v(wireAt.x * 0.32, H * 0.88, wireAt.z * 0.32),
      v(wireAt.x * 0.77, wireAt.y + 2.1, wireAt.z * 0.77),
      wireAt,
    ];
    const wireCrv = new THREE.CatmullRomCurve3(wiring);
    for (let j = 0; j < 22; j++)
      span(
        wireCrv.getPoint(j / 22),
        wireCrv.getPoint((j + 1) / 22),
        0.34 * (1 - j / 22) + 0.032,
        0.32 * (1 - (j + 1) / 22) + 0.018,
        bark,
        tree,
        7,
      );
    addRoute(
      spec.name + " living bridge to utility wire",
      wiring.map((p) => p.clone().add(v(x, treeY, z))),
      { kind: "bridge" },
    );
  }
  // A separately connected bough approaches the nearest roof ridge.
  const roof = routes
    .filter((r) => r.kind === "roof")
    .sort(
      (a, b) =>
        a.curve.getPointAt(0.5).distanceTo(v(x, treeY, z)) -
        b.curve.getPointAt(0.5).distanceTo(v(x, treeY, z)),
    )[0];
  if (roof && roof.curve.getPointAt(0.5).distanceTo(v(x, treeY, z)) < 64) {
    const trunkTip = mainTrunk.at(-1).clone();
    const roofPt = roof.curve.getPointAt(0.5);
    const nearRoof = roofPt.clone().sub(v(x, treeY, z));
    const toHome = [trunkTip.clone(), v(nearRoof.x * 0.5, H * 0.76, nearRoof.z * 0.5), nearRoof];
    const link = new THREE.CatmullRomCurve3(toHome);
    for (let j = 0; j < 16; j++)
      span(
        link.getPoint(j / 16),
        link.getPoint((j + 1) / 16),
        0.3 * (1 - j / 16) + 0.025,
        0.3 * (1 - (j + 1) / 16) + 0.015,
        bark,
        tree,
        7,
      );
    addRoute(
      spec.name + " rooftop canopy crossing",
      toHome.map((p) => p.clone().add(v(x, treeY, z))),
      { kind: "bridge" },
    );
  }
  // Clumpy crown made of thousands of separate pieces: shapes, pitches and tones vary.
  const palettes = spec.color.map((c) => leafMaterial(c));
  let leafCount = (spec.leafCount ?? (spec.name.includes("ELM") ? 2820 : 2430)) + Math.floor(rr(120, 420));
  const ims = palettes.map((m) => {
    let q = new THREE.InstancedMesh(leavesGeometry, m, Math.ceil(leafCount / palettes.length) + 20);
    q.castShadow = true;
    q.receiveShadow = true;
    q.instanceMatrix.setUsage(THREE.StaticDrawUsage);
    tree.add(q);
    canopyAnimated.push({ mesh: q, phase: rr(-PI, PI), amplitude: rr(0.003, 0.007) });
    canopyShadowCasters.push({ mesh: q, x, z, r: 100 });
    return q;
  });
  let counters = ims.map(() => 0);
  const dummy = new THREE.Object3D();
  let spread = spec.crown;
  for (let i = 0; i < leafCount; i++) {
    let tip = pick(tips);
    const dx = rr(-3.9, 3.9),
      dy = rr(-2.0, 3.0),
      dz = rr(-3.9, 3.9);
    let px = tip.x + dx,
      py = tip.y + dy,
      pz = tip.z + dz;
    const hNorm = Math.hypot(px, pz);
    if (hNorm > spread + 3) {
      px *= 0.9;
      pz *= 0.9;
    }
    dummy.position.set(px, py, pz);
    dummy.rotation.set(rr(-PI, PI), rr(-PI, PI), rr(-PI, PI));
    const sc = rr(0.48, 1.45);
    dummy.scale.set(sc * rr(0.65, 1.25), sc * rr(0.45, 1.3), sc * rr(0.6, 1.2));
    // Keep the running surface readable while maintaining a thick crown all around it.
    let closeToWalkway = false;
    for (const path of branchPaths) {
      for (let k = 0; k < path.length - 1; k++) {
        const a = path[k],
          b = path[k + 1],
          d = b.clone().sub(a),
          q = THREE.MathUtils.clamp(v(px, py, pz).sub(a).dot(d) / Math.max(0.001, d.lengthSq()), 0, 1);
        if (v(px, py, pz).distanceToSquared(a.clone().addScaledVector(d, q)) < 2.2 * 2.2) {
          closeToWalkway = true;
          break;
        }
      }
      if (closeToWalkway) break;
    }
    if (closeToWalkway) {
      dummy.position.y += rr(2.6, 4.3);
      dummy.position.x += rr(-2.2, 2.2);
    }
    dummy.updateMatrix();
    let paletteIdx = i % ims.length,
      index = counters[paletteIdx]++;
    if (index < ims[paletteIdx].count) {
      ims[paletteIdx].setMatrixAt(index, dummy.matrix);
      const shade = rr(0.78, 1.15);
      ims[paletteIdx].setColorAt(
        index,
        new THREE.Color().setRGB(shade, shade * rr(0.97, 1.03), shade * rr(0.9, 1.0)),
      );
    }
  }
  for (let k = 0; k < ims.length; k++) {
    ims[k].count = counters[k];
    ims[k].instanceMatrix.needsUpdate = true;
    if (ims[k].instanceColor) ims[k].instanceColor.needsUpdate = true;
  }
  // Warts, cavities, small knotholes and real acorn-shaped fruit on the oak.
  for (let i = 0; i < 5; i++) {
    let yy = rr(2, trunkH),
      theta = rr(0, PI * 2);
    let hole = ball(
      rr(0.12, 0.21),
      mat("#282521"),
      Math.sin(theta) * (0.95 - yy / (trunkH * 6)),
      yy,
      Math.cos(theta) * (0.95 - yy / (trunkH * 6)),
      tree,
    );
    hole.scale.z = 0.15;
  }
  if (spec.acorn) {
    const acornmat = mat("#886641"),
      capmat = mat("#6c4c2c");
    for (let i = 0; i < 55; i++) {
      let p = pick(tips);
      const X = p.x + rr(-2.5, 2.5),
        Y = p.y + rr(-1.3, 0.8),
        Z = p.z + rr(-2.5, 2.5);
      ball(0.15, acornmat, X, Y, Z, tree);
      cyl(0.12, 0.16, 0.075, capmat, X, Y + 0.13, Z, tree);
    }
  }
  // Bark speckling on sycamore.
  if (spec.sycamore)
    for (let j = 0; j < 32; j++) {
      const t = rr(0.1, 0.88),
        a = rr(0, PI * 2),
        rad = 1.29 * (1 - t * 0.7);
      ball(
        rr(0.11, 0.33),
        mat(pick(["#d1c8ac", "#8e8970", "#cdcbbb"])),
        Math.cos(a) * rad,
        t * trunkH,
        Math.sin(a) * rad,
        tree,
      );
    }
  batchTreeBranches(tree);
  trees.push({ x, z, H, spec, root: v(x, treeY, z) });
  return tree;
}
treeSpec.forEach(makeTree);
// Additional blocks: varied setback, appearance, topography, and mature trees.
// Homes do not mirror each other and terrain changes gradually by up to several meters.
const outerHomes = [
  [-135, -74, 0],
  [-217, -72, 2],
  [-217, -130, 1],
  [-127, -209, 3],
  [-63, -215, 2],
  [62, -208, 1],
  [139, -207, 0],
  [216, -136, 2],
  [216, -57, 3],
  [124, -72, 1],
  [127, 69, 3],
  [211, 76, 0],
  [216, 142, 1],
  [132, 207, 2],
  [48, 216, 3],
  [-62, 213, 0],
  [-139, 204, 1],
  [-216, 140, 3],
  [-209, 62, 2],
  [-128, 72, 0],
];
function buildOuterHome(x, z, style, i) {
  const base = terrainHeight(x, z),
    width = 12 + ((i * 7) % 5),
    depth = 10 + (i % 4),
    height = 5.2 + (i % 3) * 0.8;
  const wall = mat(["#c1b5a2", "#b7c5c1", "#d4b998", "#a69f8b", "#dfd6ba", "#a6b5ac"][i % 6]);
  const trim = mat("#f0e8d8"),
    roof = mat(["#5e5d5d", "#71625c", "#5d6b65", "#755a50"][i % 4]);
  const nearX = Math.min(Math.abs(x + 180), Math.abs(x - 178)),
    nearZ = Math.min(Math.abs(z + 174), Math.abs(z - 171));
  const rot = nearX < nearZ ? PI / 2 : 0;
  const face = rot ? Math.sign(x - (x < 0 ? -180 : 178)) : Math.sign(z - (z < 0 ? -174 : 171));
  const g = new THREE.Group();
  g.position.set(x, base, z);
  g.rotation.y = rot;
  scene.add(g);
  box(width, height, depth, wall, 0, height * 0.5, 0, g);
  localRoof(g, width, depth, height, height + 2.8 + (i % 3) * 0.55, roof);
  // No repeated identical façade: window counts, treatments and porch depth vary.
  for (const side of [-1, 1])
    for (let k = -1; k <= 1; k++) {
      if ((k + i) % 3 === 0) continue;
      addWindow(g, k * width * 0.27, 2.7, side * (depth / 2 + 0.09), 1.6 + (i % 3) * 0.18, 2.0, i % 5 === 0);
    }
  const doorSide = face || 1;
  box(
    1.35,
    2.55,
    0.14,
    mat(["#4b6d61", "#6e5144", "#3d5e78", "#a3835b"][i % 4]),
    0,
    1.26,
    doorSide * (depth / 2 + 0.19),
    g,
  );
  const porch = 2.5 + (i % 3);
  box(width * 0.63, 0.22, porch, mat("#9c8b73"), 0, 0.33, doorSide * (depth / 2 + porch * 0.52), g);
  for (const dx of [-1, 1]) {
    box(0.14, 2.7, 0.14, trim, dx * width * 0.27, 1.45, doorSide * (depth / 2 + porch - 0.5), g);
  }
  if (i % 4 === 0) {
    box(width * 0.3, 3, depth * 0.47, mat("#d2cfbd"), -width * 0.38, 1.5, depth * 0.3, g);
  }
  if (i % 3 === 0) {
    let ch = box(0.9, 1.5, 1, mat("#968476"), -width * 0.22, height + 1.2, 0, g);
  }
  // Visible house base is seated in the rising land, not hovering.
  const rw = rot ? depth : width,
    rd = rot ? width : depth,
    peak = base + height + 2.8 + (i % 3) * 0.55;
  const meta = {
    id: houses.length,
    g,
    x,
    z,
    cfg: { h: base + height, peak },
    w: rw,
    d: rd,
    roofY: () => peak,
    frontZ: z,
    backZ: z,
    frontSign: face,
  };
  houses.push(meta);
  if (rot)
    addRoute(
      "neighborhood rooftop ridge",
      [v(x, peak + 0.2, z - depth * 0.48), v(x, peak + 0.2, z + depth * 0.48)],
      { kind: "roof" },
    );
  else
    addRoute(
      "neighborhood rooftop ridge",
      [v(x - width * 0.48, peak + 0.2, z), v(x + width * 0.48, peak + 0.2, z)],
      { kind: "roof" },
    );
  // Short paths, unique shrubs and driveway connections to the closest street.
  const park = rot ? x - (x < 0 ? -180 : 178) : z - (z < 0 ? -174 : 171),
    toward = -Math.sign(park || 1);
  if (rot) {
    box(
      Math.max(5, Math.abs(park) - 4),
      0.09,
      2.3,
      concrete,
      x + toward * (Math.abs(park) - 4) * 0.5,
      base + 0.055,
      z + 5,
    );
  } else {
    box(
      2.3,
      0.09,
      Math.max(5, Math.abs(park) - 4),
      concrete,
      x + width * 0.25,
      base + 0.055,
      z + toward * (Math.abs(park) - 4) * 0.5,
    );
  }
  for (let j = 0; j < 5; j++) {
    const dx = R(-width * 0.9, width * 0.9),
      dz = R(-depth * 1.5, depth * 1.5);
    if (Math.abs(dx) < width * 0.6 && Math.abs(dz) < depth * 0.65) continue;
    const gy = terrainHeight(x + dx, z + dz);
    const foliage = ball(R(0.34, 0.72), pick(shrubM), x + dx, gy + 0.36, z + dz);
    foliage.scale.set(1.1, R(0.6, 1.7), 1.2);
  }
}
outerHomes.forEach((a, i) => buildOuterHome(...a, i));
const outerTreeCount = 36,
  outerTrees = [];
const outerTreeCandidates = [
  [-150, -118],
  [-227, -32],
  [-227, -201],
  [-100, -227],
  [-29, -201],
  [30, -233],
  [104, -119],
  [157, -117],
  [233, -204],
  [233, -24],
  [157, -31],
  [102, 33],
  [238, 19],
  [235, 230],
  [109, 235],
  [14, 227],
  [-107, 230],
  [-236, 224],
  [-228, 22],
  [-151, 24],
  [-109, -109],
  [-92, 119],
  [-26, 141],
  [30, 110],
  [91, 123],
  [-236, -241],
  [-44, -125],
  [153, 124],
  [-157, 127],
  [103, -242],
  [-101, 12],
  [13, -106],
  [230, -100],
  [-27, 238],
  [-235, 118],
  [154, 238],
];
const outLeafGeo = new THREE.IcosahedronGeometry(0.62, 0);
function makeOuterTree(spec, index) {
  const { x, z } = spec,
    base = terrainHeight(x, z),
    height = R(22, 39),
    trunkH = height * 0.55;
  const g = new THREE.Group();
  g.position.set(x, base, z);
  scene.add(g);
  const species = index % 5,
    bark = species === 2 ? mat("#a5a394") : M.bark;
  const trunk = [
    v(0, 0.1, 0),
    v(R(-0.5, 0.5), trunkH * 0.38, R(-0.5, 0.5)),
    v(R(-1, 1), trunkH * 0.75, R(-1, 1)),
    v(R(-1.5, 1.5), trunkH, R(-1.5, 1.5)),
  ];
  for (let j = 0; j < trunk.length - 1; j++)
    span(trunk[j], trunk[j + 1], 0.85 - j * 0.13, 0.72 - j * 0.15, bark, g);
  addRoute(
    "outer " + index + " tree trunk",
    trunk.map((q) => q.clone().add(v(x, base, z))),
    { kind: "trunk", center: v(x, base, z), surfaceRadius: 0.81 },
  );
  const tips = [],
    outerBoughs = [],
    twigBatch = [];
  for (let j = 0; j < 5 + species; j++) {
    const a = (j * PI * 2) / (5 + species) + R(-0.38, 0.38),
      length = R(6.5, 12.3),
      t0 = trunk[2].clone(),
      mid = v(Math.cos(a) * length * 0.55, trunkH + R(2.5, 7), Math.sin(a) * length * 0.55),
      end = v(Math.cos(a) * length, height * R(0.7, 0.9), Math.sin(a) * length);
    span(t0, mid, 0.29, 0.17, bark, g);
    span(mid, end, 0.17, 0.035, bark, g);
    tips.push(mid, end);
    outerBoughs.push([t0, mid, end]);
    addRoute(
      "outer " + index + " bough " + j,
      [t0, mid, end].map((q) => q.clone().add(v(x, base, z))),
      { kind: "branch" },
    );
    for (let k = 0; k < 3; k++) {
      const small = end.clone().add(v(R(-4, 4), R(-2, 3), R(-4, 4)));
      if (k < 2) twigBatch.push([end.clone(), small.clone()]); // ornamental twigs, no extra player routes
      tips.push(small);
    }
  }
  // The small ornamental limbs are one batched mesh per tree: richer silhouettes without hundreds of draw calls.
  if (twigBatch.length) {
    const twigs = new THREE.InstancedMesh(new THREE.CylinderGeometry(1, 1, 1, 5), bark, twigBatch.length);
    const q = new THREE.Object3D();
    for (let i = 0; i < twigBatch.length; i++) {
      const [a, b] = twigBatch[i],
        d = b.clone().sub(a);
      q.position.copy(a).add(b).multiplyScalar(0.5);
      q.quaternion.setFromUnitVectors(v(0, 1, 0), d.clone().normalize());
      q.scale.set(0.035 + 0.023 * (i % 3), d.length(), 0.035 + 0.023 * (i % 3));
      q.updateMatrix();
      twigs.setMatrixAt(i, q.matrix);
    }
    twigs.instanceMatrix.needsUpdate = true;
    twigs.castShadow = false;
    g.add(twigs);
  }
  const m = [mat("#658d4e"), mat("#789956"), mat("#537d43"), mat("#8fa568")][species % 4];
  const foliage = new THREE.InstancedMesh(outLeafGeo, m, 530);
  const d = new THREE.Object3D();
  for (let j = 0; j < 530; j++) {
    const tip = pick(tips),
      sz = R(0.4, 1.8);
    d.position.set(tip.x + R(-3.8, 3.8), tip.y + R(-2.8, 2.8), tip.z + R(-3.8, 3.8));
    let tooClose = false;
    for (const b of outerBoughs) {
      for (let k = 0; k < 2; k++) {
        const ab = b[k + 1].clone().sub(b[k]);
        const projection = THREE.MathUtils.clamp(
          d.position.clone().sub(b[k]).dot(ab) / Math.max(0.1, ab.lengthSq()),
          0,
          1,
        );
        if (d.position.distanceToSquared(b[k].clone().addScaledVector(ab, projection)) < 1.45 * 1.45) {
          tooClose = true;
          break;
        }
      }
      if (tooClose) break;
    }
    if (tooClose) d.position.y += R(1.9, 3.1);
    d.rotation.set(R(-PI, PI), R(-PI, PI), R(-PI, PI));
    d.scale.set(sz, sz * R(0.6, 1.4), sz * R(0.5, 1.2));
    d.updateMatrix();
    foliage.setMatrixAt(j, d.matrix);
    const tint = 0.78 + R(0, 0.34);
    foliage.setColorAt(j, new THREE.Color().setRGB(tint, tint * R(0.95, 1.03), tint * R(0.88, 1.01)));
  }
  foliage.instanceMatrix.needsUpdate = true;
  if (foliage.instanceColor) foliage.instanceColor.needsUpdate = true;
  foliage.castShadow = true;
  g.add(foliage);
  canopyShadowCasters.push({ mesh: foliage, x, z, r: 100 });
  canopyAnimated.push({ mesh: foliage, phase: index * 0.51, amplitude: 0.0045 });
  for (let j = 0; j < 5; j++) {
    let a = (j * PI * 2) / 5 + R(-0.3, 0.3),
      len = R(2, 4.8);
    span(v(0, 0.26, 0), v(Math.cos(a) * len, 0.05, Math.sin(a) * len), 0.22, 0.022, bark, g);
  }
  // Route connector ends ON the nearest wire, and uses the very top of the trunk.
  let wire = null,
    dist = 1e9;
  for (const route of routes) {
    if (route.kind !== "wire") continue;
    for (const pp of route.sampled) {
      const d = Math.hypot(pp.x - x, pp.z - z);
      if (d < dist) {
        dist = d;
        wire = pp;
      }
    }
  }
  if (wire && dist < 39) {
    const a = trunk
        .at(-1)
        .clone()
        .add(v(x, base, z)),
      b = wire.clone();
    const mid = a
      .clone()
      .lerp(b, 0.6)
      .add(v(0, 1.8, 0));
    addRoute("outer " + index + " canopy-to-wire bridge", [a, mid, b], { kind: "bridge" });
    span(a, mid, 0.17, 0.09, bark);
    span(mid, b, 0.09, 0.025, bark);
  }
  trees.push({ x, z, H: height, spec: { name: "neighborhood canopy" }, root: v(x, base, z) });
  outerTrees.push({ x, z, height });
}
outerTreeCandidates.forEach(([tx, tz], i) => {
  const x = THREE.MathUtils.clamp(tx + R(-6, 6), -245, 245),
    z = THREE.MathUtils.clamp(tz + R(-7, 7), -245, 245);
  makeOuterTree({ x, z }, i);
});
// Litter, driveway stones, and a few little landscaped earth banks.
const bermMat = mat("#79935e");
for (let i = 0; i < 52; i++) {
  const x = R(-248, 248),
    z = R(-248, 248);
  if (Math.abs(x) < 19 || Math.abs(z) < 19) continue;
  const y = terrainHeight(x, z);
  const tuft = ball(R(0.3, 0.66), bermMat, x, y + 0.29, z, scene);
  tuft.scale.set(R(1, 2.7), 0.4, R(0.6, 1.6));
}

// Lower shrubs, sidewalk cracks, distant additional small vegetation, scattered leaf litter.
const groundLeaves = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 0.012, 1), mat("#ffffff"), 650);
const leafDummy = new THREE.Object3D();
const leafColors = ["#aa8653", "#b6a167", "#6c7945", "#8e744a"].map((c) => new THREE.Color(c));
let groundLeafCount = 0;
for (let i = 0; i < 650; i++) {
  let x = R(-111, 111),
    z = R(-111, 111);
  if (Math.abs(x) < 10 || Math.abs(z) < 10) continue;
  leafDummy.position.set(x, 0.045, z);
  leafDummy.rotation.set(0, R(0, PI), 0);
  leafDummy.scale.set(R(0.1, 0.32), 1, R(0.12, 0.3));
  leafDummy.updateMatrix();
  groundLeaves.setMatrixAt(groundLeafCount, leafDummy.matrix);
  groundLeaves.setColorAt(groundLeafCount, pick(leafColors));
  groundLeafCount++;
}
groundLeaves.count = groundLeafCount;
groundLeaves.instanceMatrix.needsUpdate = true;
groundLeaves.castShadow = false;
groundLeaves.receiveShadow = true;
scene.add(groundLeaves);
for (let i = 0; i < 120; i++) {
  let x = R(-115, 115),
    z = R(-115, 115);
  if (Math.abs(x) < 17 || Math.abs(z) < 17) continue;
  let clump = ball(R(0.19, 0.57), pick(shrubM), x, R(0.14, 0.5), z);
  clump.scale.set(R(0.65, 1.3), R(0.5, 1), R(0.8, 1.6));
}

// Exactly THREE giant lookout trees. Distinct silhouettes and true climbable paths.
const giantTreeSpecs = [
  { name: "SENTINEL OAK", x: -101, z: -146, h: 61, r: 2.05, reach: 25, color: "#607e41" },
  { name: "HIGHLAND ELM", x: 88, z: 139, h: 70, r: 1.87, reach: 27, color: "#6c9551" },
  { name: "OLD WATCH SYCAMORE", x: 216, z: -109, h: 65, r: 2.1, reach: 28, color: "#81945b" },
];
const giantPerches = [];
function makeLookoutTree(spec, index) {
  const { x, z, h, r, reach, name } = spec,
    by = terrainHeight(x, z),
    g = new THREE.Group();
  g.position.set(x, by, z);
  scene.add(g);
  const trunkMat = index === 2 ? mat("#a3a48f") : M.bark,
    leafMat = [mat(spec.color), mat("#49753e"), mat("#759c55")];
  const trunk = [
    v(0, 0.1, 0),
    v(0.28, h * 0.2, -0.3),
    v(-0.5, h * 0.42, 0.5),
    v(0.55, h * 0.57, 0.1),
    v(0.05, h * 0.73, 0.2),
  ];
  for (let i = 0; i < trunk.length - 1; i++)
    span(trunk[i], trunk[i + 1], r - i * 0.3, r - (i + 1) * 0.3, trunkMat, g, 11);
  addRoute(
    name + " giant trunk",
    trunk.map((q) => q.clone().add(v(x, by, z))),
    { kind: "trunk", center: v(x, by, z), surfaceRadius: r * 0.95 },
  );
  const tips = [],
    branchEnds = [],
    giantBoughs = [];
  for (let j = 0; j < 7; j++) {
    const angle = ((j + 0.17 * index) * 2 * PI) / 7 + 0.14 * Math.sin(j * 3),
      height = h * (0.73 + 0.085 * Math.cos(j * 1.7));
    const end = v(
      Math.cos(angle) * reach * (0.71 + (j % 3) * 0.1),
      height,
      Math.sin(angle) * reach * (0.75 + (j % 2) * 0.12),
    );
    const mid = v(end.x * 0.45, h * (0.77 + 0.05 * Math.sin(j)), end.z * 0.45);
    const path = [trunk.at(-1).clone(), mid, end];
    giantBoughs.push(path);
    const bcrv = new THREE.CatmullRomCurve3(path);
    for (let k = 0; k < 22; k++)
      span(
        bcrv.getPoint(k / 22),
        bcrv.getPoint((k + 1) / 22),
        0.78 * (1 - k / 22) + 0.065,
        0.78 * (1 - (k + 1) / 22) + 0.055,
        trunkMat,
        g,
        8,
      );
    addRoute(
      name + " high lookout bough " + (j + 1),
      path.map((q) => q.clone().add(v(x, by, z))),
      { kind: "branch" },
    );
    branchEnds.push(end);
    tips.push(end, mid);
    for (let k = 0; k < 6; k++) {
      const a = angle + (k - 3) * 0.25;
      const fork = end.clone().add(v(Math.cos(a) * R(2, 8), R(1, 6), Math.sin(a) * R(2, 8)));
      span(end, fork, 0.13, 0.025, trunkMat, g, 5);
      tips.push(fork);
    }
  }
  // Two discrete lookout perches per giant, reachable by walking out a branch.
  for (const i of [1, 4]) {
    const end = branchEnds[i],
      world = end.clone().add(v(x, by, z));
    const knot = ball(1.16, trunkMat, end.x, end.y - 0.43, end.z, g);
    knot.scale.set(1.25, 0.38, 1.25);
    const pad = addRoute(
      name + " OPEN SKY LOOKOUT",
      [world.clone().add(v(-0.28, 0.47, -0.18)), world.clone().add(v(0.5, 0.47, 0.18))],
      { kind: "lookout" },
    );
    giantPerches.push({ x: world.x, y: world.y, z: world.z, name });
  }
  // Open sky is kept near each perch instead of burying the player in foliage.
  const inst = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.9, 0), leafMat[index % 3], 1780);
  let n = 0;
  const dum = new THREE.Object3D();
  for (let j = 0; j < 1780; j++) {
    const t = pick(tips),
      px = t.x + R(-6, 6),
      pz = t.z + R(-6, 6);
    let py = t.y + R(-3.8, 4.4);
    if (branchEnds.some((pt, k) => (k === 1 || k === 4) && Math.hypot(px - pt.x, py - pt.y, pz - pt.z) < 5.8))
      continue;
    // Keep the squirrel readable against the grand upper boughs.
    let nearRail = false;
    for (const b of giantBoughs) {
      for (let k = 0; k < 2; k++) {
        const ab = b[k + 1].clone().sub(b[k]),
          p = v(px, py, pz),
          q = THREE.MathUtils.clamp(p.clone().sub(b[k]).dot(ab) / Math.max(0.1, ab.lengthSq()), 0, 1);
        if (p.distanceToSquared(b[k].clone().addScaledVector(ab, q)) < 2.35 * 2.35) {
          nearRail = true;
          break;
        }
      }
      if (nearRail) break;
    }
    if (nearRail) py += R(2.6, 4.1);
    dum.position.set(px, py, pz);
    dum.rotation.set(R(-PI, PI), R(-PI, PI), R(-PI, PI));
    const scale = R(0.65, 1.7);
    dum.scale.set(scale, scale * R(0.65, 1.35), scale * R(0.6, 1.4));
    dum.updateMatrix();
    inst.setMatrixAt(n, dum.matrix);
    const tint = R(0.79, 1.17);
    inst.setColorAt(n, new THREE.Color().setRGB(tint, tint * R(0.95, 1.06), tint * R(0.88, 1.03)));
    n++;
  }
  inst.count = n;
  inst.instanceMatrix.needsUpdate = true;
  if (inst.instanceColor) inst.instanceColor.needsUpdate = true;
  inst.castShadow = true;
  g.add(inst);
  canopyShadowCasters.push({ mesh: inst, x, z, r: 110 });
  canopyAnimated.push({ mesh: inst, phase: index * 0.92, amplitude: 0.0038 });
  for (let i = 0; i < 11; i++) {
    const a = (i * PI * 2) / 11 + R(-0.2, 0.2),
      len = R(4.1, 7.3);
    span(
      v(Math.cos(a) * 0.7, 0.5, Math.sin(a) * 0.7),
      v(Math.cos(a) * len, 0.05, Math.sin(a) * len),
      0.34,
      0.02,
      trunkMat,
      g,
      8,
    );
  }
  trees.push({ x, z, H: h, spec: { name }, root: v(x, by, z), radius: r });
}
giantTreeSpecs.forEach(makeLookoutTree);
// ------ SOUTH ESTATE DISTRICT / v1.1 ------
// Beyond the existing neighborhood's south boundary, across an east-west access street.
// Two architecturally distinct parcels; not more copies of the four starting homes.
const ESTATE_SOUTH = -565;
const estateTerrain = new THREE.PlaneGeometry(540, 300, 90, 56);
estateTerrain.rotateX(-PI / 2);
estateTerrain.translate(0, 0, -415);
const estateVerts = estateTerrain.attributes.position;
for (let i = 0; i < estateVerts.count; i++)
  estateVerts.setY(i, terrainHeight(estateVerts.getX(i), estateVerts.getZ(i)) - 0.084);
estateTerrain.computeVertexNormals();
mesh(estateTerrain, M.grass, 0, 0, 0, scene, false);
// Connect the older southern residential street to the estate avenue.
districtRibbon("z", 0, 18, -329, -263, M.asphalt);
for (const x of [-12.1, 12.1]) districtRibbon("z", x, 3.3, -329, -263, concrete, 0.12);
districtRibbon("x", -305, 20, -258, 258, M.asphalt);
for (const z of [-317.1, -292.9]) districtRibbon("x", z, 3.5, -258, 258, concrete, 0.12);
const estatePaint = mat("#e6e2ce");
for (let x = -246; x <= 247; x += 19) {
  box(7, 0.022, 0.15, estatePaint, x, terrainHeight(x, -305) + 0.16, -305);
}
for (let z = -322; z < -264; z += 13) {
  box(0.14, 0.02, 5.2, estatePaint, 0, terrainHeight(0, z) + 0.16, z);
}
const estateProjects = [];
function estateHedgeLine(ax, az, bx, bz, height = 1.5, color = "#54784d") {
  const length = Math.hypot(bx - ax, bz - az),
    n = Math.max(1, Math.floor(length / 3.3));
  const hedge = mat(color);
  for (let i = 0; i <= n; i++) {
    const t = i / n,
      x = ax + (bx - ax) * t,
      z = az + (bz - az) * t,
      y = terrainHeight(x, z);
    const ob = ball(1.22, hedge, x, y + height * 0.45, z, scene, 1);
    ob.scale.set(1.3, height * 0.52, 0.74);
  }
}
function estatePool(cx, cz, style) {
  const y = terrainHeight(cx, cz),
    deck = mat(style ? "#e1d9c6" : "#d9c6b0"),
    tile = mat(style ? "#2d7c90" : "#4e9eac");
  box(41, 0.32, 31, deck, cx, y + 0.18, cz);
  box(34, 0.11, 24, tile, cx, y + 0.27, cz);
  const glimmer = new THREE.MeshBasicMaterial({
    color: 0x9cdfe3,
    transparent: true,
    opacity: 0.46,
    depthWrite: false,
  });
  box(33, 0.04, 23, glimmer, cx, y + 0.36, cz);
  for (let s of [-1, 1]) {
    box(35, 0.18, 0.65, mat("#f7f0dd"), cx, y + 0.38, cz + s * 12.05);
    box(0.65, 0.18, 24, mat("#f7f0dd"), cx + s * 17.05, y + 0.38, cz);
  }
  for (let i = 0; i < 7; i++) {
    let xx = cx - 14 + i * 4.6,
      zz = cz + ((i % 3) - 1) * 4.2;
    box(
      2.4,
      0.012,
      0.06,
      new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.2 }),
      xx,
      y + 0.405,
      zz,
    ).rotation.y = (i % 2) * 0.35;
  }
  for (let i = 0; i < 4; i++) {
    const xx = cx - 15 + i * 9.9,
      zz = cz + 19;
    box(2.8, 0.14, 5.3, mat("#efe5d5"), xx, terrainHeight(xx, zz) + 0.62, zz).rotation.x = -0.1;
    const umb = cyl(0.1, 0.1, 2.7, M.metal, xx, terrainHeight(xx, zz) + 1.5, zz + 3);
    const cone = new THREE.Mesh(new THREE.ConeGeometry(2.6, 0.92, 9), mat(style ? "#f4f2e8" : "#e5b99b"));
    cone.position.set(xx, terrainHeight(xx, zz) + 3, zz + 3);
    scene.add(cone);
  }
  for (let k = -1; k <= 1; k += 2) {
    span(v(cx - 18.5, y + 0.35, cz + k * 2.6), v(cx - 18.5, y + 1.2, cz + k * 2.6), 0.08, 0.08, M.metal);
    span(v(cx - 18.5, y + 1.2, cz + k * 2.6), v(cx - 17.6, y + 1.2, cz + k * 2.6), 0.07, 0.07, M.metal);
  }
  return { cx, cz };
}
function estateCourt(cx, cz, style) {
  const y = terrainHeight(cx, cz) + 0.08,
    green = mat(style ? "#356785" : "#476c59"),
    inside = mat(style ? "#447ea1" : "#637c59"),
    white = mat("#faf3dc");
  box(42, 0.26, 26, mat("#b9b1a2"), cx, y, cz);
  box(39, 0.07, 23, green, cx, y + 0.18, cz);
  box(35, 0.02, 18.1, inside, cx, y + 0.23, cz);
  for (const xx of [-17.45, 17.45]) box(0.13, 0.03, 18.2, white, cx + xx, y + 0.26, cz);
  for (const zz of [-9.12, 9.12]) box(35, 0.03, 0.13, white, cx, y + 0.26, cz + zz);
  box(0.13, 0.03, 18.1, white, cx, y + 0.26, cz);
  for (const xx of [-11.5, 11.5]) box(0.12, 0.03, 18.1, white, cx + xx, y + 0.26, cz);
  for (const side of [-1, 1]) box(11.3, 0.03, 0.1, white, cx + side * 5.7, y + 0.26, cz);
  const netM = new THREE.MeshBasicMaterial({
    color: 0xe8e6dd,
    transparent: true,
    opacity: 0.55,
    side: THREE.DoubleSide,
  });
  box(0.045, 1.25, 18.5, netM, cx, y + 0.84, cz); // net divides two halves of the court
  for (let zz = -9; zz <= 9; zz += 1.3)
    span(v(cx, y + 0.28, cz + zz), v(cx, y + 1.47, cz + zz), 0.02, 0.02, white);
  span(v(cx, y + 1.5, cz - 9.25), v(cx, y + 1.5, cz + 9.25), 0.055, 0.055, white);
  for (const dx of [-20, 20])
    for (const dz of [-12, 12]) {
      const x = cx + dx,
        z = cz + dz;
      cyl(0.08, 0.09, 4.6, M.metal, x, y + 2.3, z);
      ball(0.27, mat("#e5e2d1"), x, y + 4.7, z);
    }
  // Mesh is deliberately low-cost. Fence has a gap toward the estate house.
  const fenceMaterial = new THREE.MeshBasicMaterial({
    color: 0x95aca2,
    side: THREE.DoubleSide,
    transparent: true,
    opacity: 0.28,
    depthWrite: false,
  });
  for (const [dx, dz, w, d] of [
    [-20.8, 0, 0.075, 24.2],
    [20.8, 0, 0.075, 24.2],
    [0, -12.25, 41.5, 0.07],
    [-14, 12.25, 13, 0.07],
    [14, 12.25, 13, 0.07],
  ]) {
    box(w, 3.8, d, fenceMaterial, cx + dx, y + 2.1, cz + dz);
  }
  addRoute("estate tennis net top", [v(cx, y + 1.55, cz - 9.3), v(cx, y + 1.55, cz + 9.3)], {
    kind: "fence",
  });
}
function estateGuest(cx, cz, style) {
  const by = terrainHeight(cx, cz),
    g = new THREE.Group();
  g.position.set(cx, by, cz);
  scene.add(g);
  const wall = mat(style ? "#dacdb0" : "#d2b69c"),
    roof = mat(style ? "#686764" : "#765848");
  box(20, 6.7, 15, wall, 0, 3.35, 0, g);
  box(22, 0.73, 17, roof, 0, 7.02, 0, g);
  for (const x of [-6, 6]) {
    box(4.5, 3.5, 0.1, M.glass, x, 3.8, 7.61, g);
    box(4.9, 0.18, 0.17, M.trim, x, 5.63, 7.7, g);
  }
  box(3.1, 4, 0.2, mat("#765946"), 0, 2.05, 7.72, g);
  box(19, 0.24, 5, mat("#d2c1a2"), 0, 0.25, 10, g);
  for (const x of [-7, 0, 7]) cyl(0.17, 0.19, 4.1, M.trim, x, 2.2, 11.6, g);
  commercialBounds.push({ x: cx, z: cz, w: 20, d: 15, roof: by + 7.45 });
  addRoute("estate guesthouse roof", [v(cx - 9, by + 7.48, cz), v(cx + 9, by + 7.48, cz)], { kind: "roof" });
}
function estateMansion(cx, cz, style) {
  const by = terrainHeight(cx, cz),
    g = new THREE.Group();
  g.position.set(cx, by, cz);
  scene.add(g);
  const wall = mat(style ? "#d6cab2" : "#ad7964"),
    accent = mat(style ? "#ece5d3" : "#d7c6ae"),
    roof = mat(style ? "#6b6b60" : "#514846"),
    dark = mat("#605447");
  // Broad two-storey main house, two set-back wings, and a substantial entrance.
  box(46, 14.0, 29, wall, 0, 7, 0, g);
  for (const side of [-1, 1]) {
    box(19, 10.2, 24, wall, side * 30, 5.1, 2, g);
    box(21, 0.82, 26, roof, side * 30, 10.6, 2, g);
  }
  box(48, 0.9, 31, roof, 0, 14.15, 0, g);
  box(49, 0.3, 32, accent, 0, 13.9, 0, g);
  for (const x of [-35, -15, 0, 15, 35])
    for (const yy of [4.0, 10.1]) {
      box(5.1, 3.6, 0.15, accent, x, yy, 14.76 + (Math.abs(x) > 23 ? -0.9 : 0), g);
      box(4.55, 3.08, 0.22, M.glass, x, yy, 14.85 + (Math.abs(x) > 23 ? -0.9 : 0), g);
      box(0.13, 3.13, 0.25, accent, x, yy, 15, g);
    }
  // Southern garden-facing glass doors; north frontage faces the road.
  for (const x of [-31, -17, 17, 31]) {
    box(5.1, 3.3, 0.13, accent, x, 4, -14.8 + (Math.abs(x) > 23 ? 1 : 0), g);
    box(4.65, 3.0, 0.17, M.glass, x, 4, -14.95 + (Math.abs(x) > 23 ? 1 : 0), g);
  }
  if (style) {
    // Formal modern limestone villa and stepped roof terrace.
    box(17, 1.1, 11, accent, 0, 15.7, 0, g);
    for (const x of [-21, 21]) box(0.3, 2.0, 27, accent, x, 14.95, 0, g);
    for (const z of [-11.2, 11.2]) box(42, 1.0, 0.23, accent, 0, 15.2, z, g);
    box(15, 0.35, 8, mat("#beae91"), 0, 1.0, 19, g);
    for (const x of [-6.3, 6.3]) cyl(0.42, 0.47, 10, accent, x, 6.7, 18.0, g, 14);
    box(17, 0.55, 7, accent, 0, 11.95, 18, g);
  } else {
    // Grand brick revival with central projecting portico and gable silhouette.
    box(19, 15.8, 4, wall, 0, 7.9, 15, g);
    const ped = new THREE.Mesh(new THREE.ConeGeometry(11, 4.9, 4), roof);
    ped.rotation.y = PI / 4;
    ped.position.set(0, 17.0, 15);
    g.add(ped);
    box(21, 0.6, 7, accent, 0, 12.2, 18, g);
    for (const x of [-8, -2.6, 2.6, 8]) cyl(0.44, 0.51, 8.6, accent, x, 7.2, 20.3, g, 14);
    for (const x of [-19, 19]) box(3.8, 4, 3.3, wall, x, 16.25, 0, g);
  }
  box(6.5, 5.6, 0.27, dark, 0, 2.81, 16.25 + (style ? 0 : 3.2), g);
  box(9.7, 0.2, 8.2, accent, 0, 0.28, 21, g);
  for (let i = 0; i < 4; i++) box(10 + i * 0.9, 0.17, 1.25, accent, 0, 0.1 + i * 0.18, 24 + i * 1.08, g);
  commercialBounds.push({ x: cx, z: cz, w: 81, d: 35, roof: by + 14.62 });
  addRoute(
    "grand estate main roof",
    [v(cx - 22, by + 14.7, cz), v(cx, by + 14.7, cz), v(cx + 22, by + 14.7, cz)],
    { kind: "roof" },
  );
}
function createEstate(index, cx) {
  const style = index === 1,
    baseZ = -370,
    poolX = cx + (style ? 12 : -12),
    courtX = cx + (style ? 47 : -47),
    guestX = cx + (style ? -67 : 67);
  // One continuous walk and driveway from the estate avenue; gate openings remain clear.
  const pavers = mat(style ? "#c7c6b4" : "#bfae9a");
  for (let zz = -331; zz >= -349; zz -= 6) {
    let y = terrainHeight(cx, zz);
    box(9, 0.1, 5.9, pavers, cx, y + 0.14, zz);
  }
  for (let zz = -350; zz >= -379; zz -= 6) {
    let y = terrainHeight(cx, zz);
    box(8.7, 0.1, 5.9, pavers, cx, y + 0.14, zz);
  }
  const tx = cx + (style ? 55 : -55);
  for (let i = 0; i < 12; i++) {
    const xx = cx + (i - 5.5) * 5.1,
      zz = -335;
    if (Math.abs(xx - cx) < 9) continue;
    const y = terrainHeight(xx, zz);
    ball(0.75, mat(style ? "#617f52" : "#5c7b46"), xx, y + 0.62, zz, scene, 1.0);
  }
  const gateY = terrainHeight(cx, -331);
  for (const dx of [-9, 9]) {
    box(1.5, 6.2, 1.5, mat(style ? "#e1dbc9" : "#b88d70"), cx + dx, gateY + 3.1, -330);
    ball(0.75, mat("#f2e8bc"), cx + dx, gateY + 6.5, -330);
  }
  estateMansion(cx, baseZ, style);
  estatePool(poolX, -425, style);
  estateCourt(courtX, -504, style);
  estateGuest(guestX, -463, style);
  // Long clipped hedges define the parcel and separate driveway, lawns and tennis area.
  estateHedgeLine(cx - 105, -332, cx - 105, -548, 1.7, style ? "#537958" : "#557547");
  estateHedgeLine(cx + 105, -332, cx + 105, -548, 1.7, style ? "#537958" : "#557547");
  estateHedgeLine(cx - 105, -548, cx + 105, -548, 1.7);
  // Walks to guesthouse and the tennis court.
  for (const end of [
    { x: guestX, z: -455 },
    { x: courtX, z: -490 },
  ]) {
    const first = v(cx, 0, -402),
      last = v(end.x, 0, end.z),
      steps = 15;
    for (let i = 0; i <= steps; i++) {
      const x = first.x + ((last.x - first.x) * i) / steps,
        z = first.z + ((last.z - first.z) * i) / steps;
      box(2.1, 0.07, 2.15, pavers, x, terrainHeight(x, z) + 0.14, z);
    }
  }
  // Terrace + pergola above the swimming pool, plus a summer kitchen.
  const pergolaX = cx + (style ? -46 : 46),
    pergolaZ = -424,
    py = terrainHeight(pergolaX, pergolaZ);
  for (const dx of [-6, 6])
    for (const dz of [-4, 4]) cyl(0.18, 0.18, 5.8, mat("#a89272"), pergolaX + dx, py + 2.9, pergolaZ + dz);
  for (let x = -6; x <= 6; x += 1.8) box(0.19, 0.17, 9.0, mat("#9a805c"), pergolaX + x, py + 5.87, pergolaZ);
  box(5, 1.5, 2.1, mat("#746c62"), pergolaX, py + 0.9, pergolaZ);
  for (const dx of [-3.5, 3.5]) box(1.4, 0.8, 1.0, mat("#d9c8ad"), pergolaX + dx, py + 0.65, pergolaZ);
  // Estate residents own a parked vehicle, not placed across their fence or a roadway.
  const parked = makeCar(cx + (style ? -18 : 18), -350, style ? "#a6aeb0" : "#617768", 0, false);
  parked.position.y = terrainHeight(parked.position.x, parked.position.z) + 0.04;
  estateProjects.push({ cx, baseZ, poolX, courtX, guestX });
}
createEstate(0, -130);
createEstate(1, 130);
// Additional elevated canopy routes at the gate: a few strong climbable limbs,
// numerous smaller decorative twigs and clusters instead of dozens of new rails.
const estateGateTreeTips = [];
function estateGateOak(cx, cz, seed) {
  const r = rng(seed),
    rand = (a, b) => a + (b - a) * r(),
    by = terrainHeight(cx, cz),
    g = new THREE.Group();
  g.position.set(cx, by, cz);
  scene.add(g);
  const bark = mat("#716050"),
    foliage = [mat("#557c43"), mat("#698c4e"), mat("#8ba85e")];
  const trunk = [v(0, 0.5, 0), v(0.25, 8, 0.2), v(-0.2, 17, -0.15), v(0.4, 25, 0.1)];
  for (let j = 0; j < 3; j++) span(trunk[j], trunk[j + 1], 1.65 - j * 0.32, 1.38 - j * 0.3, bark, g, 10);
  addRoute(
    "estate oak trunk",
    trunk.map((p) => p.clone().add(v(cx, by, cz))),
    { kind: "trunk", surfaceRadius: 1.55 },
  );
  const tips = [],
    boughWalkPaths = [];
  for (let j = 0; j < 6; j++) {
    const a = (j * PI) / 3 + 0.16 + rand(-0.32, 0.32),
      t = rand(0.72, 1),
      end = v(Math.cos(a) * rand(12, 19), rand(19, 28), Math.sin(a) * rand(12, 19));
    const p = [trunk[2].clone(), v(end.x * 0.42, rand(21, 25), end.z * 0.42), end];
    const c = new THREE.CatmullRomCurve3(p);
    boughWalkPaths.push(p);
    for (let k = 0; k < 8; k++)
      span(
        c.getPoint(k / 8),
        c.getPoint((k + 1) / 8),
        0.61 * (1 - k / 8) + 0.05,
        0.51 * (1 - k / 8) + 0.03,
        bark,
        g,
        7,
      );
    addRoute(
      "estate oak major bough " + j,
      p.map((q) => q.clone().add(v(cx, by, cz))),
      { kind: "branch" },
    );
    tips.push(end);
    for (let k = 0; k < 6; k++) {
      const st = c.getPoint(rand(0.43, 0.95)),
        tip = st.clone().add(v(rand(-5, 5), rand(0.5, 3.7), rand(-5, 5)));
      span(st, tip, 0.12, 0.014, bark, g, 5);
      tips.push(tip);
    }
  }
  const dummy = new THREE.Object3D();
  const inst = foliage.map((m) => {
    const im = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.7, 0), m, 470);
    g.add(im);
    return im;
  });
  const used = [0, 0, 0];
  for (let i = 0; i < 1300; i++) {
    const pt = tips[Math.floor(rand(0, tips.length))],
      k = i % 3;
    dummy.position.set(pt.x + rand(-2.7, 2.7), pt.y + rand(-2.8, 2.9), pt.z + rand(-2.7, 2.7));
    // No distracting leaves directly in front of the squirrel on climbable wood.
    if (boughWalkPaths.some((path) => path.some((q) => dummy.position.distanceToSquared(q) < 2.9 * 2.9)))
      dummy.position.y += 3.0;
    dummy.rotation.set(rand(-PI, PI), rand(-PI, PI), rand(-PI, PI));
    dummy.scale.set(rand(0.6, 1.3), rand(0.5, 1.2), rand(0.6, 1.2));
    dummy.updateMatrix();
    inst[k].setMatrixAt(used[k]++, dummy.matrix);
  }
  inst.forEach((im, i) => {
    im.count = used[i];
    im.instanceMatrix.needsUpdate = true;
    im.castShadow = false;
    canopyAnimated.push({ mesh: im, phase: seed * 0.5, amplitude: 0.004 });
  });
  trees.push({ x: cx, z: cz, H: 28, root: v(cx, by, cz), radius: 1.65 });
  estateGateTreeTips.push({ x: cx, z: cz, tip: v(cx + 0.4, by + 25, cz + 0.1) });
}
for (const [x, z, s] of [
  [-230, -329, 189],
  [230, -329, 191],
  [-219, -453, 193],
  [219, -456, 197],
])
  estateGateOak(x, z, s);
// Estate utility route: the cable and supports use the SAME verge coordinates.
// There is intentionally no pole at x=0, where the north/south driveway meets
// the estate avenue. A cable spans that intersection overhead.
const estateWire = mat("#465052", 0.65, 0.3),
  estatePoleZ = -286;
const estateCableX = [-250, -228, -125, 125, 228, 250];
const estateCableNodes = estateCableX.map((x) => v(x, terrainHeight(x, estatePoleZ) + 16.4, estatePoleZ));
for (let j = 1; j < estateCableNodes.length; j++) {
  const pts = droopBetween(estateCableNodes[j - 1], estateCableNodes[j], 0.3);
  linePath(
    pts,
    estateWire,
    0.035,
    Math.max(24, Math.ceil(estateCableNodes[j].distanceTo(estateCableNodes[j - 1]) * 0.8)),
  );
  addRoute("estate avenue cable", pts, { kind: "wire" });
}
for (const j of [0, 1, 2, 3, 4, 5]) {
  const x = estateCableX[j],
    z = estatePoleZ,
    by = terrainHeight(x, z),
    top = estateCableNodes[j];
  if (pavementDistance(x, z) < 0.95) throw new Error("Estate pole obstructs pavement " + x + "," + z);
  cyl(0.3, 0.4, 16.4, M.wood, x, by + 8.2, z);
  span(v(x - 2, by + 15.85, z), v(x + 2, by + 15.85, z), 0.16, 0.16, M.wood);
  utilitySupports.push({ x, z, label: "estate", top: top.clone() });
  addRoute("estate avenue telephone pole climb", [v(x, by + 0.48, z), v(x, by + 8, z), top.clone()], {
    kind: "trunk",
    surfaceRadius: 0.4,
  });
}

// Actual wood-to-cable contacts at the two estate front oaks: intersections
// use the cable's sampled vertices, not nearby imaginary transfer locations.
for (const tree of estateGateTreeTips.filter((t) => t.z > -380)) {
  const wire = routes.filter((r) => r.name === "estate avenue cable");
  let dest = null,
    best = Infinity;
  for (const rail of wire)
    for (const point of rail.sampled) {
      const d = Math.hypot(point.x - tree.x, point.z - tree.z);
      if (d < best) {
        best = d;
        dest = point;
      }
    }
  if (dest) {
    const pts = [
      tree.tip,
      tree.tip.clone().add(v(1.5, 2, 7.5)),
      v((tree.x + dest.x) * 0.5, Math.max(dest.y + 4, tree.tip.y - 0.5), (tree.z + dest.z) * 0.5),
      dest.clone(),
    ];
    const curve = new THREE.CatmullRomCurve3(pts);
    for (let j = 0; j < 14; j++)
      span(
        curve.getPoint(j / 14),
        curve.getPoint((j + 1) / 14),
        0.31 * (1 - j / 14) + 0.028,
        0.28 * (1 - (j + 1) / 14) + 0.016,
        M.bark,
        scene,
        7,
      );
    addRoute("estate oak living utility bridge", pts, { kind: "bridge" });
  }
}

// Exactly one radio lattice tower and one cellular monopole on the far skyline.
function radioTower(x, z) {
  const base = terrainHeight(x, z),
    steel = mat("#aeb6b1", 0.38, 0.6),
    red = mat("#b34c45");
  const H = 114,
    foot = 6.3,
    top = 1.3,
    vertices = (i) =>
      Array.from({ length: 3 }, (_, j) => {
        const a = (j * PI * 2) / 3 + PI / 6,
          size = foot + ((top - foot) * i) / 10;
        return v(x + Math.cos(a) * size, base + (i * H) / 10, z + Math.sin(a) * size);
      });
  for (let i = 0; i < 10; i++) {
    const a = vertices(i),
      b = vertices(i + 1);
    for (let j = 0; j < 3; j++) {
      span(a[j], b[j], 0.19, 0.13, i % 2 ? red : steel);
      span(a[j], b[(j + 1) % 3], 0.085, 0.06, steel);
      span(a[j], a[(j + 1) % 3], 0.085, 0.06, steel);
    }
  }
  span(v(x, base + H, z), v(x, base + H + 11, z), 0.13, 0.07, steel);
  const beacon = ball(0.53, mat("#e2553d", 0.3), x, base + H + 12, z);
  beacon.material.emissive = new THREE.Color("#ff351e");
  beacon.material.emissiveIntensity = 0.55;
  return beacon;
}
const radioBeacon = radioTower(646, -213);
function cellTower(x, z) {
  const by = terrainHeight(x, z),
    metal = mat("#8f9d98", 0.36, 0.74),
    panel = mat("#d0d5cc", 0.4, 0.3);
  const H = 99;
  cyl(0.9, 1.65, H, metal, x, by + H / 2, z, scene, 14);
  for (const level of [H * 0.67, H * 0.88]) {
    const y = by + level;
    span(v(x - 4, y, z), v(x + 4, y, z), 0.15, 0.15, metal);
    span(v(x, y, z - 4), v(x, y, z + 4), 0.15, 0.15, metal);
    for (let i = 0; i < 6; i++) {
      const a = (i * PI) / 3,
        px = x + Math.sin(a) * 4,
        pz = z + Math.cos(a) * 4;
      const ob = box(0.8, 6.5, 1.6, panel, px, y + 1.25, pz);
      ob.rotation.y = a;
    }
  }
  const top = new THREE.Mesh(new THREE.ConeGeometry(0.78, 3.6, 10), metal);
  top.position.set(x, by + H + 1.8, z);
  scene.add(top);
}
cellTower(629, 218);

// ---- Nineteen kinds of detailed neighborhood objects, each with variations. ----
// Set dressing is sparse per property rather than mirrored or cloned into rows.
const bicycleWheelMeshes = new Map();
const decorativeTypes = [
  "fire hydrant",
  "park bench",
  "trash can",
  "streetlight",
  "stop sign",
  "garden gnome",
  "bird feeder",
  "sprinkler head",
  "porch swing",
  "window box",
  "driveway basketball hoop",
  "kids bike",
  "lawn flamingo",
  "wind chime",
  "garden hose reel",
  "wheelbarrow",
  "compost bin",
  "rain barrel",
  "porch light",
];
const neighborhoodDetails = [];
function addDetail(type, x, z, variation = 0) {
  const g = new THREE.Group();
  g.position.set(x, terrainHeight(x, z), z);
  g.rotation.y = variation * 0.71;
  scene.add(g);
  neighborhoodDetails.push({ type, x, z, variation });
  const brass = mat("#baa769", 0.32, 0.6),
    iron = mat("#4c6262", 0.45, 0.53),
    red = mat(variation % 2 ? "#cead4e" : "#b44332"),
    green = mat(variation % 2 ? "#527b64" : "#47664c"),
    blue = mat("#517b97"),
    white = mat("#e6ddca"),
    wood = mat(variation % 2 ? "#9f8365" : "#84694f"),
    pink = mat("#e89ab0");
  if (type === "fire hydrant") {
    cyl(0.55, 0.7, 1.55, red, 0, 0.82, 0, g);
    cyl(0.75, 0.76, 0.23, red, 0, 0.26, 0, g);
    cyl(0.43, 0.56, 0.42, red, 0, 1.77, 0, g);
    for (const side of [-1, 1]) {
      const nozzle = cyl(0.28, 0.29, 0.48, red, side * 0.73, 1.18, 0, g, 12);
      nozzle.rotation.z = PI / 2;
      cyl(0.32, 0.32, 0.09, brass, side * 0.98, 1.18, 0, g).rotation.z = PI / 2;
    }
    cyl(0.23, 0.23, 0.12, brass, 0, 2, 0, g);
  } else if (type === "park bench") {
    for (let slat = 0; slat < 4; slat++) box(4.2, 0.17, 0.48, wood, 0, 1.13, -0.65 + slat * 0.48, g);
    for (let slat = 0; slat < 3; slat++) box(4.2, 0.2, 0.14, wood, 0, 1.4 + slat * 0.36, -1.07, g);
    for (const xx of [-1.65, 1.65]) {
      box(0.2, 1.2, 0.22, iron, xx, 0.58, -0.75, g);
      box(0.22, 0.84, 0.22, iron, xx, 0.48, 0.74, g);
    }
  } else if (type === "trash can") {
    cyl(0.72, 0.62, 1.58, variation % 2 ? green : iron, 0, 0.89, 0, g, 16);
    cyl(0.78, 0.78, 0.13, M.black, 0, 1.75, 0, g, 16);
    for (let j = 0; j < 12; j++) {
      const a = (j * PI) / 6;
      box(0.035, 1.23, 0.025, mat("#284236"), Math.sin(a) * 0.66, 0.91, Math.cos(a) * 0.66, g);
    }
  } else if (type === "streetlight") {
    cyl(0.16, 0.23, 9, iron, 0, 4.5, 0, g, 12);
    span(v(0, 8.8, 0), v(3.3, 9.3, 0), 0.12, 0.1, iron, g);
    box(1.8, 0.38, 1.15, M.metal, 3.4, 9.15, 0, g);
    box(1.6, 0.13, 1, mat("#fff3c4", 0.55), 3.4, 8.87, 0, g);
  } else if (type === "stop sign") {
    cyl(0.055, 0.068, 2.75, iron, 0, 1.375, 0, g);
    const stopMat = signCanvas("STOP", "#a72e2e", "#fff8e2");
    const border = mesh(new THREE.CylinderGeometry(0.68, 0.68, 0.055, 8), mat("#f2e9d8"), 0, 2.4, 0.09, g);
    border.rotation.x = PI / 2;
    border.rotation.z = PI / 8;
    const sign = mesh(
      new THREE.CylinderGeometry(0.61, 0.61, 0.059, 8),
      [mat("#a42d2c"), stopMat, stopMat],
      0,
      2.4,
      0.14,
      g,
    );
    sign.rotation.x = PI / 2;
    sign.rotation.z = PI / 8;
  } else if (type === "garden gnome") {
    ball(0.49, mat("#7f8a9c"), 0, 0.46, 0, g).scale.set(0.85, 1.2, 0.72);
    ball(0.31, mat("#e5ba9e"), 0, 1.08, 0.1, g);
    const hat = new THREE.Mesh(new THREE.ConeGeometry(0.5, 1.2, 9), red);
    hat.position.set(0, 1.72, 0);
    g.add(hat);
    ball(0.18, white, 0, 0.91, 0.35, g).scale.set(0.75, 1.1, 0.5);
    ball(0.075, mat("#e3a490"), 0, 1.15, 0.45, g);
  } else if (type === "bird feeder") {
    cyl(0.09, 0.12, 4.8, wood, 0, 2.4, 0, g);
    box(1.9, 0.12, 1.9, wood, 0, 3.7, 0, g);
    const roof = new THREE.Mesh(new THREE.ConeGeometry(1.4, 0.85, 4), red);
    roof.rotation.y = PI / 4;
    roof.position.set(0, 4.6, 0);
    g.add(roof);
    for (const xx of [-0.65, 0.65])
      for (const zz of [-0.65, 0.65]) box(0.095, 0.75, 0.095, wood, xx, 4.1, zz, g);
  } else if (type === "sprinkler head") {
    cyl(0.18, 0.23, 0.33, iron, 0, 0.22, 0, g);
    cyl(0.39, 0.39, 0.07, blue, 0, 0.4, 0, g);
    if (variation % 2 === 0)
      for (let i = 0; i < 5; i++) {
        const a = (i * PI * 2) / 5;
        span(
          v(0, 0.47, 0),
          v(Math.sin(a) * 1.5, 1.05 + Math.sin(a) * 0.2, Math.cos(a) * 1.5),
          0.023,
          0.009,
          mat("#9ddae2", 0.1),
          g,
          5,
        );
      }
  } else if (type === "porch swing") {
    for (const xx of [-2.3, 2.3]) box(0.2, 4.1, 0.2, wood, xx, 2.05, 0, g);
    span(v(-2.6, 4.1, 0), v(2.6, 4.1, 0), 0.17, 0.17, wood, g);
    for (const xx of [-1.7, 1.7])
      for (const zz of [-0.63, 0.63]) span(v(xx, 3.98, zz), v(xx, 1.23, zz), 0.028, 0.028, iron, g);
    box(4, 0.22, 1.5, wood, 0, 1.1, 0, g);
    box(4, 1.1, 0.2, wood, 0, 1.67, -0.72, g);
  } else if (type === "window box") {
    box(3.1, 0.6, 0.75, wood, 0, 1.12, 0, g);
    for (let i = 0; i < 7; i++) {
      const xx = (i - 3) * 0.39;
      ball(0.33, green, xx, 1.67, 0.12, g);
      ball(0.13, i % 2 ? pink : red, xx, 1.91, -0.05, g);
    }
  } else if (type === "driveway basketball hoop") {
    cyl(0.13, 0.2, 7.3, iron, 0, 3.65, 0, g);
    box(3.6, 2.2, 0.22, white, 0, 7.5, 0.12, g);
    box(1.3, 0.05, 0.06, red, 0, 7.28, 0.28, g);
    const rim = new THREE.Mesh(new THREE.TorusGeometry(0.66, 0.075, 8, 24), red);
    rim.position.set(0, 6.7, 1.2);
    rim.rotation.x = PI / 2;
    g.add(rim);
    for (let j = 0; j < 9; j++) {
      const a = (j * 2 * PI) / 9;
      span(
        v(Math.cos(a) * 0.65, 6.68, 1.2 + Math.sin(a) * 0.65),
        v(Math.cos(a) * 0.33, 5.75, 1.2 + Math.sin(a) * 0.33),
        0.023,
        0.014,
        white,
        g,
        5,
      );
    }
  } else if (type === "kids bike") {
    for (const zz of [-0.85, 0.85]) makeSpokedBicycleWheel(g, zz, 0.6);
    span(v(0, 0.68, -0.85), v(0, 1.48, 0), 0.07, 0.06, red, g);
    span(v(0, 1.48, 0), v(0, 0.68, 0.85), 0.07, 0.06, red, g);
    span(v(0, 0.68, -0.85), v(0, 0.68, 0.85), 0.055, 0.055, red, g);
    span(v(-0.55, 1.6, 0.85), v(0.55, 1.6, 0.85), 0.06, 0.06, iron, g);
    box(0.75, 0.1, 0.33, M.black, 0, 1.45, -0.16, g);
  } else if (type === "lawn flamingo") {
    for (const xx of [-0.18, 0.18]) span(v(xx, 0.03, 0), v(xx, 0.8, 0), 0.027, 0.02, iron, g);
    ball(0.54, pink, 0, 1.2, 0, g).scale.set(0.75, 0.6, 1.25);
    span(v(0, 1.45, 0.25), v(0.21, 2.5, 0.35), 0.2, 0.13, pink, g, 10);
    ball(0.24, pink, 0.28, 2.66, 0.37, g);
    const beak = new THREE.Mesh(new THREE.ConeGeometry(0.14, 0.45, 7), mat("#222724"));
    beak.rotation.z = PI / 2;
    beak.position.set(0.56, 2.58, 0.38);
    g.add(beak);
  } else if (type === "wind chime") {
    cyl(0.045, 0.045, 3.5, wood, 0, 1.8, 0, g);
    cyl(0.58, 0.58, 0.1, wood, 0, 3.42, 0, g);
    for (let j = 0; j < 6; j++) {
      const a = (j * PI) / 3;
      const xx = Math.cos(a) * 0.43,
        zz = Math.sin(a) * 0.43;
      span(v(xx, 3.4, zz), v(xx, 2.35 - (j % 3) * 0.14, zz), 0.02, 0.02, iron, g);
      cyl(0.07, 0.07, 0.86 + (j % 3) * 0.21, brass, xx, 2.04 - (j % 3) * 0.14, zz, g);
    }
  } else if (type === "garden hose reel") {
    for (const xx of [-0.4, 0.4]) {
      const wheel = new THREE.Mesh(new THREE.TorusGeometry(0.81, 0.16, 8, 20), green);
      wheel.position.set(xx, 1.3, 0);
      wheel.rotation.y = PI / 2;
      g.add(wheel);
    }
    cyl(0.36, 0.36, 0.9, iron, 0, 1.28, 0, g).rotation.z = PI / 2;
    for (const xx of [-0.6, 0.6]) box(0.12, 1.1, 0.1, iron, xx, 0.57, 0, g);
  } else if (type === "wheelbarrow") {
    box(2.4, 0.62, 1.3, variation % 2 ? blue : green, 0, 1.0, 0, g);
    box(2.6, 0.09, 1.45, iron, 0, 1.4, 0, g);
    for (const zz of [-0.55, 0.55]) span(v(-1.1, 0.82, zz), v(2.1, 0.85, zz), 0.09, 0.065, wood, g);
    const wheel = new THREE.Mesh(new THREE.TorusGeometry(0.45, 0.16, 8, 14), M.black);
    wheel.position.set(-1.35, 0.48, 0);
    wheel.rotation.y = PI / 2;
    g.add(wheel);
  } else if (type === "compost bin") {
    for (const yy of [0.5, 1.15, 1.8]) for (const zz of [-1.1, 1.1]) box(2.5, 0.21, 0.15, wood, 0, yy, zz, g);
    for (const yy of [0.5, 1.15, 1.8])
      for (const xx of [-1.15, 1.15]) box(0.14, 0.21, 2.4, wood, xx, yy, 0, g);
    box(2.6, 0.22, 2.5, wood, 0, 2.12, 0, g);
  } else if (type === "rain barrel") {
    cyl(0.85, 0.83, 2.5, variation % 2 ? blue : wood, 0, 1.32, 0, g, 15);
    for (const yy of [0.45, 1.4, 2.37]) cyl(0.9, 0.9, 0.13, iron, 0, yy, 0, g, 15);
    span(v(0.83, 0.65, 0), v(1.15, 0.65, 0.1), 0.11, 0.1, brass, g);
  } else if (type === "porch light") {
    box(0.24, 3.6, 0.24, wood, 0, 1.8, 0, g);
    span(v(0, 3.3, 0), v(0.8, 3.5, 0), 0.085, 0.075, iron, g);
    box(0.74, 1.08, 0.65, mat("#e7d9aa", 0.45), 0.83, 3.01, 0, g);
    const crown = new THREE.Mesh(new THREE.ConeGeometry(0.58, 0.5, 4), iron);
    crown.position.set(0.83, 3.75, 0);
    crown.rotation.y = PI / 4;
    g.add(crown);
  }
}
// Every type appears at least twice, across different homes and terrain heights.
for (let i = 0; i < decorativeTypes.length; i++)
  for (let variant = 0; variant < 2; variant++) {
    const h = houses[4 + ((i * 3 + variant * 7) % 20)];
    const dx = variant === 0 ? 11 : -12,
      dz = i % 2 ? 12 : -13;
    addDetail(decorativeTypes[i], h.x + dx, h.z + dz, variant + (i % 3));
  }
// Additional believable public fixtures and random-looking commercial landscaping.
for (const [kind, x, z, k] of [
  ["fire hydrant", 312, 23, 2],
  ["fire hydrant", 387, -22, 3],
  ["park bench", 418, -39, 4],
  ["park bench", 562, 46, 5],
  ["trash can", 538, -38, 2],
  ["trash can", 419, 77, 3],
  ["streetlight", 294, -22, 3],
  ["streetlight", 397, 23, 4],
  ["streetlight", 583, -21, 2],
  ["stop sign", 324, 31, 1],
  ["stop sign", 371, -34, 3],
  ["sprinkler head", 574, 145, 4],
  ["lawn flamingo", 571, -149, 4],
  ["kids bike", 251, 126, 3],
])
  addDetail(kind, x, z, k);

// --- v0.7 ADDITIVE NORTHERN EXPANSION. Existing houses, commercial district, and routes preserved. ---
// Final bounded level footprint: x=-270..687, z=-270..444. ~35% more modeled area than v0.6.
const NORTH_LIMIT = 440;
function addNorthernGround(x1, x2, z1, z2) {
  const geo = new THREE.PlaneGeometry(x2 - x1, z2 - z1, 70, 28);
  geo.rotateX(-PI / 2);
  geo.translate((x1 + x2) / 2, 0, (z1 + z2) / 2);
  const verts = geo.attributes.position;
  for (let i = 0; i < verts.count; i++) verts.setY(i, terrainHeight(verts.getX(i), verts.getZ(i)) - 0.088);
  geo.computeVertexNormals();
  mesh(geo, M.grass);
}
addNorthernGround(-270, 270, 269.95, 443); // 520x520 base ends at z=270
addNorthernGround(270, 687, 243.95, 443); // eastern commercial ground ends at z=244
const pathTan = mat("#bcae90"),
  graveStone = mat("#a8afa6"),
  agedStone = mat("#7e8781"),
  leafGreen = mat("#496a41");
function earthTile(x, z, w, d, material, thickness = 0.1) {
  const y = terrainHeight(x, z);
  return box(w, thickness, d, material, x, y + thickness * 0.35, z);
}
function pavedSegment(a, b, width, material = pathTan) {
  const d = b.clone().sub(a);
  const distance = Math.hypot(d.x, d.z);
  const center = a.clone().add(b).multiplyScalar(0.5);
  const plank = box(
    width,
    0.12,
    distance,
    material,
    center.x,
    terrainHeight(center.x, center.z) + 0.12,
    center.z,
  );
  plank.rotation.y = -Math.atan2(d.x, d.z);
  return plank;
}
// Exit the original neighborhood at its north edge, then divide into two meaningful destinations.
districtRibbon("z", 175, 12.5, 233, 422, M.asphalt, 0.12);
districtRibbon("z", 175 - 10.0, 2.8, 248, 421, concrete, 0.17);
districtRibbon("z", 175 + 10.0, 2.8, 248, 421, concrete, 0.17);
districtRibbon("x", 283, 11, -241, 651, M.asphalt, 0.14);
for (const zz of [283])
  for (const dz of [-9.3, 9.3]) districtRibbon("x", zz + dz, 2.2, -241, 650, concrete, 0.18);
for (const x of [-220, -176, -128, -80, -32, 16, 64, 112, 160, 212, 264, 312, 360, 409, 458, 506, 554, 602]) {
  const z = 283,
    h = terrainHeight(x, z);
  if (Math.abs(x - 175) > 24) box(6, 0.02, 0.12, mat("#e3cfa6"), x, h + 0.25, z);
}
// Park to the northwest: undulating grassy lawn, shaded paths, pond, bandstand and water crossing.
const parkCenter = v(-35, 0, 357);
const parkBoundary = { xmin: -245, xmax: 145, zmin: 296, zmax: 429 };
for (const [x, z] of [
  [-214, 305],
  [-210, 417],
  [108, 307],
  [111, 417],
  [-72, 418],
]) {
  const h = terrainHeight(x, z);
  cyl(0.34, 0.47, 3.6, M.wood, x, h + 1.8, z);
}
const parkPaths = [
  [
    [-216, 320],
    [-132, 336],
    [-56, 355],
  ],
  [
    [-56, 355],
    [11, 329],
    [106, 312],
  ],
  [
    [-56, 355],
    [-15, 411],
    [98, 414],
  ],
  [
    [-203, 409],
    [-137, 376],
    [-56, 355],
  ],
];
for (const poly of parkPaths)
  for (let j = 0; j < poly.length - 1; j++)
    pavedSegment(v(poly[j][0], 0, poly[j][1]), v(poly[j + 1][0], 0, poly[j + 1][1]), 3.2);
// Pond is deliberately shallow: its surface is above ground, rather than an accidental terrain hole.
const pondX = -147,
  pondZ = 371,
  pondY = terrainHeight(pondX, pondZ);
let pondBed = mesh(new THREE.CircleGeometry(19, 48), mat("#8b8873"), pondX, pondY + 0.1, pondZ);
pondBed.rotation.x = -PI / 2;
pondBed.scale.set(1.45, 1, 1);
let pondWater = mesh(new THREE.CircleGeometry(17.8, 48), M.water, pondX, pondY + 0.15, pondZ, scene, false);
pondWater.rotation.x = -PI / 2;
pondWater.scale.set(1.48, 1, 1);
// Footbridge at the pond rim; valid overhead squirrel route at the actual deck height.
for (let i = 0; i < 11; i++) {
  const x = -122 + i * 1.3,
    z = 371,
    yy = terrainHeight(x, z);
  box(1.25, 0.18, 4.3, M.wood, x, yy + 0.65, z);
}
for (let s of [-1, 1])
  for (let i = 0; i < 6; i++) {
    const x = -122 + i * 2.6;
    span(
      v(x, terrainHeight(x, 371) + 0.6, 371 + s * 2),
      v(x, terrainHeight(x, 371) + 2.3, 371 + s * 2),
      0.1,
      0.08,
      M.wood,
    );
  }
addRoute(
  "park footbridge",
  [
    v(-122, terrainHeight(-122, 371) + 0.78, 371),
    v(-116, terrainHeight(-116, 371) + 0.78, 371),
    v(-109, terrainHeight(-109, 371) + 0.78, 371),
  ],
  { kind: "bridge" },
);
// Park shade trees, some arranged beside paths, all asymmetrical, all climbable.
const parkTreePositions = [
  [-221, 355],
  [-185, 313],
  [-115, 412],
  [-64, 317],
  [14, 395],
  [90, 358],
  [-15, 426],
  [-238, 397],
];
parkTreePositions.forEach(([x, z], i) => makeOuterTree({ x, z }, 90 + i));
// Select park trees get a raised perch with an additional cross-bough.
for (const [x, z] of [
  [-221, 355],
  [-115, 412],
  [90, 358],
]) {
  const trunk = routes.find(
    (r) => r.kind === "trunk" && Math.hypot(r.curve.getPointAt(0).x - x, r.curve.getPointAt(0).z - z) < 2,
  );
  if (trunk) {
    const tip = trunk.curve.getPointAt(0.83);
    const high = tip.clone().add(v(6, 4, 2));
    span(tip, high, 0.23, 0.09, M.bark);
    addRoute("park high watch perch", [tip, high, high.clone().add(v(4, -1, 0))], { kind: "lookout" });
  }
}
// Northern park crossing: all supports live on verges, not the roadway.
const parkWireStart = pole(159, 244).top,
  parkWireMid = pole(159, 301).top,
  parkWireEnd = pole(142, 331).top;
for (const [name, a, b] of [
  ["north park phone wire", parkWireStart, parkWireMid],
  ["park branch-side phone wire", parkWireMid, parkWireEnd],
]) {
  const pts = droopBetween(a, b, 0.36);
  linePath(pts, wireM, 0.037, 36);
  addRoute(name, pts, { kind: "wire" });
}
const farParkTree = routes.find(
  (r) => r.kind === "trunk" && Math.hypot(r.curve.getPointAt(0).x - 90, r.curve.getPointAt(0).z - 358) < 2,
);
if (farParkTree) {
  const high = farParkTree.curve.getPointAt(1),
    pts = droopBetween(high, parkWireEnd, 1.1);
  linePath(pts, wireM, 0.037, 35);
  addRoute("high park tree to phone line", pts, { kind: "wire" });
}
for (const [x, z, k] of [
  [-59, 355, 2],
  [7, 333, 4],
  [-185, 326, 6],
  [112, 396, 1],
])
  addDetail("park bench", x, z, k);
for (const [x, z, k] of [
  [-201, 331, 2],
  [-30, 405, 0],
  [82, 311, 3],
])
  addDetail("trash can", x, z, k);
for (const [x, z] of [
  [-118, 326],
  [10, 398],
]) {
  const y = terrainHeight(x, z);
  cyl(0.12, 0.16, 5.9, M.metal, x, y + 2.95, z);
  ball(0.43, mat("#efdf9a"), x, y + 6, z);
}
// Gazebo and park's visible name board; distinct from the nearby cemetery.
const gz = v(52, terrainHeight(52, 411), 411);
cyl(6.4, 6.4, 0.42, M.wood, gz.x, gz.y + 0.24, gz.z, scene, 10);
for (let i = 0; i < 8; i++) {
  const a = (i * PI) / 4,
    x = gz.x + 5.65 * Math.cos(a),
    z = gz.z + 5.65 * Math.sin(a);
  span(v(x, gz.y + 0.5, z), v(x, gz.y + 6.4, z), 0.14, 0.13, M.wood);
}
const gazeboRoof = new THREE.Mesh(new THREE.ConeGeometry(7.1, 3.0, 8), mat("#6c7a65"));
gazeboRoof.position.set(gz.x, gz.y + 7, gz.z);
gazeboRoof.rotation.y = PI / 8;
scene.add(gazeboRoof);
flatSign("SYCAMORE PARK", -61, terrainHeight(-61, 296) + 5, 296, 26, 3, "#2e6551", "#f1f4ce");
flatSign("PARK / CEMETERY ↑", 192, terrainHeight(192, 250) + 6, 250, 33, 3.8, "#315a44", "#f2f3df");
// Cemetery east of the park: stone wall, entry gate, curving path, monuments and chapel.
const graveRegion = { xmin: 277, xmax: 643, zmin: 309, zmax: 429 };
for (const [x1, z1, x2, z2] of [
  [277, 304, 442, 304],
  [466, 304, 647, 304],
  [277, 304, 277, 428],
  [647, 304, 647, 428],
  [277, 428, 647, 428],
]) {
  const dx = x2 - x1,
    dz = z2 - z1,
    length = Math.hypot(dx, dz);
  for (let t = 0; t < length; t += 5) {
    const u = t / length,
      x = x1 + u * dx,
      z = z1 + u * dz;
    const y = terrainHeight(x, z);
    box(
      Math.abs(dx) > Math.abs(dz) ? 4.95 : 0.82,
      1.35,
      Math.abs(dx) > Math.abs(dz) ? 0.82 : 4.95,
      agedStone,
      x,
      y + 0.67,
      z,
    );
  }
}
for (const x of [442, 466]) {
  const h = terrainHeight(x, 304);
  cyl(0.61, 0.7, 4.3, graveStone, x, h + 2.15, 304);
  ball(0.65, graveStone, x, h + 4.45, 304);
}
flatSign("CEDAR REST CEMETERY", 453, terrainHeight(453, 302) + 7.8, 303, 42, 4, "#373f38", "#f0e8d8");
const gyRoad = [v(451, 0, 307), v(447, 0, 333), v(464, 0, 356), v(484, 0, 394), v(513, 0, 411)];
for (let j = 0; j < gyRoad.length - 1; j++) pavedSegment(gyRoad[j], gyRoad[j + 1], 5.5, mat("#b4aea1"));
const burialPlots = [];
for (let row = 0; row < 5; row++)
  for (let col = 0; col < 12; col++) {
    const x = 300 + col * 27 + (row % 2) * 6,
      z = 322 + row * 20 + (col % 4) * 1.7;
    if (Math.abs(x - 450) < 24 || x > 644 || z > 418) continue;
    burialPlots.push({ x, z, type: (row * 17 + col) % 5 });
  }
const graveMaterials = [graveStone, agedStone, mat("#929795"), mat("#b9b7ab")];
for (const [idx, g] of burialPlots.entries()) {
  const h = terrainHeight(g.x, g.z),
    stone = graveMaterials[idx % graveMaterials.length];
  if (g.type === 0) {
    const m = box(2.3, 3.4, 0.66, stone, g.x, h + 1.7, g.z);
    ball(1.16, stone, g.x, h + 3.35, g.z).scale.set(1, 0.62, 0.34);
  } else if (g.type === 1) {
    box(2.5, 2.2, 0.8, stone, g.x, h + 1.1, g.z);
    box(2.0, 0.42, 0.9, stone, g.x, h + 2.42, g.z);
  } else if (g.type === 2) {
    cyl(0.54, 0.7, 3.9, stone, g.x, h + 2, g.z, scene, 9);
    let o = new THREE.Mesh(new THREE.ConeGeometry(0.83, 1.9, 8), stone);
    o.position.set(g.x, h + 4.75, g.z);
    scene.add(o);
  } else if (g.type === 3) {
    box(0.7, 3.1, 0.65, stone, g.x, h + 1.55, g.z);
    box(2.0, 0.68, 0.65, stone, g.x, h + 2.35, g.z);
  } else {
    box(3.1, 1.25, 1.55, stone, g.x, h + 0.63, g.z);
    box(2.3, 0.43, 1.65, agedStone, g.x, h + 1.45, g.z);
  }
  const plot = box(2.8, 0.055, 4.8, mat(idx % 3 ? "#6c8a57" : "#797b60"), g.x, h + 0.11, g.z + 2.4);
  plot.castShadow = false;
}
const cryptY = terrainHeight(594, 378),
  crypt = new THREE.Group();
crypt.position.set(594, cryptY, 378);
scene.add(crypt);
box(23, 9.2, 17, mat("#969991"), 0, 4.6, 0, crypt);
box(24.6, 1.3, 18.7, agedStone, 0, 9.65, 0, crypt);
for (const sx of [-9, 9]) {
  cyl(1, 1, 7, graveStone, sx, 5, 9, crypt, 10);
  const cap = new THREE.Mesh(new THREE.ConeGeometry(1.7, 2.9, 6), agedStone);
  cap.position.set(sx, 9, 9);
  crypt.add(cap);
}
box(5.7, 6.8, 0.4, mat("#42463e"), 0, 3.4, 8.85, crypt);
box(2, 0.35, 0.2, graveStone, 0, 8.2, 9.05, crypt);
addRoute("cemetery crypt roof", [v(583, cryptY + 10.45, 378), v(605, cryptY + 10.45, 378)], { kind: "roof" });
for (const [x, z] of [
  [308, 414],
  [385, 335],
  [624, 341],
]) {
  const h = terrainHeight(x, z);
  cyl(0.15, 0.17, 3.2, agedStone, x, h + 1.6, z);
  ball(0.35, mat("#e0dfc1"), x, h + 3.4, z);
}
// Living evergreen hedges break sightlines without cloning entire fence lines.
const hedgePatches = [
  [125, 303, 14, 2.3],
  [118, 372, 11, 3],
  [-104, 305, 18, 2.4],
  [290, 306, 22, 2.6],
  [613, 421, 15, 2.2],
];
for (const [x, z, len, h] of hedgePatches) {
  for (let t = -len / 2; t <= len / 2; t += 1.7) {
    const xx = x + t,
      yy = terrainHeight(xx, z);
    const b = ball(h * 0.51, leafGreen, xx, yy + h * 0.51, z);
    b.scale.set(0.95, 1, 0.83);
  }
}

// The plot is a concealment spot and part of the *existing* eight-chili hunt.
const GARDEN_X = 115,
  GARDEN_Z = 341;
for (let col = 0; col < 4; col++) {
  const xx = GARDEN_X - 13 + col * 6.2;
  earthTile(xx, GARDEN_Z, 4.5, 24, mat("#5a4935"), 0.17);
}
const stemGreen = mat("#66823d"),
  cornMat = mat("#c0a45c");
for (let i = 0; i < 16; i++) {
  const x = GARDEN_X - 22 + (i % 4) * 2.0,
    z = GARDEN_Z - 10 + Math.floor(i / 4) * 5.5,
    y = terrainHeight(x, z),
    ht = R(3.7, 5.9);
  cyl(0.055, 0.085, ht, stemGreen, x, y + ht / 2, z, scene, 6);
  for (let k = 0; k < 4; k++) {
    let leaf = ball(0.48, stemGreen, x + (k % 2 ? 0.65 : -0.65), y + 1 + k * 0.7, z);
    leaf.scale.set(1.7, 0.13, 0.44);
  }
  box(0.75, 0.75, 0.75, cornMat, x, y + ht - 0.52, z); // distance legibility: avoid shimmering thin corn
}
for (let i = 0; i < 14; i++) {
  const x = GARDEN_X - 2 + (i % 4) * 2.8,
    z = GARDEN_Z - 10 + Math.floor(i / 4) * 5.5,
    y = terrainHeight(x, z);
  const base = ball(0.75, mat("#7fa155"), x, y + 0.7, z);
  base.scale.set(1.3, 0.85, 1.1);
  for (let j = 0; j < 4; j++)
    ball(0.3, mat("#96b76c"), x + Math.sin(j * 1.7) * 0.55, y + 0.93, z + Math.cos(j * 1.7) * 0.46);
}
const tabascoPlants = [];
for (let i = 0; i < 9; i++) {
  const x = GARDEN_X + 10 + (i % 3) * 2.6,
    z = GARDEN_Z - 10 + Math.floor(i / 3) * 5.5,
    y = terrainHeight(x, z);
  const g = new THREE.Group();
  g.position.set(x, y, z);
  scene.add(g);
  cyl(0.09, 0.13, 1.6, stemGreen, 0, 0.8, 0, g, 7);
  for (let j = 0; j < 5; j++) {
    const a = (j * PI * 2) / 5,
      h = 0.65 + (j % 3) * 0.37,
      xx = Math.sin(a) * 0.48,
      zz = Math.cos(a) * 0.48;
    span(v(0, 0.45, 0), v(xx, h, zz), 0.052, 0.024, stemGreen, g, 5);
    ball(0.26, leafGreen, xx, h, zz, g).scale.set(1.5, 0.15, 0.72);
    // Fruit points upright: tiny vivid red caps, visually connected to stalk.
    const pep = new THREE.Mesh(
      new THREE.ConeGeometry(0.13, 0.51, 8),
      mat(j % 4 === 0 ? "#f28b27" : "#cb2520", 0.25),
    );
    pep.rotation.z = PI;
    pep.position.set(xx, h + 0.32, zz);
    g.add(pep);
  }
  tabascoPlants.push(g);
}
flatSign(
  "TABASCO GARDEN",
  GARDEN_X,
  terrainHeight(GARDEN_X, GARDEN_Z - 16) + 2.6,
  GARDEN_Z - 16,
  21,
  2.3,
  "#476947",
  "#f2f5da",
);
// Wheelbarrow is above ground and doubles as a lookout perch.
const wx = GARDEN_X + 24,
  wz = GARDEN_Z + 1,
  wy = terrainHeight(wx, wz);
box(3.5, 0.75, 2.2, mat("#477461"), wx, wy + 1.75, wz);
for (const z of [-0.75, 0.75])
  span(v(wx - 1, wy + 1.3, wz + z), v(wx + 1.7, wy + 0.2, wz + z), 0.1, 0.08, M.metal);
let wheel = cyl(0.55, 0.55, 0.34, M.rubber, wx - 1.35, wy + 0.66, wz, scene, 13);
wheel.rotation.x = PI / 2;
span(v(wx + 1, wy + 1, wz - 0.2), v(wx + 3.1, wy + 4.2, wz - 0.5), 0.1, 0.12, M.wood);
box(0.75, 1.0, 0.16, M.metal, wx + 3.24, wy + 4.35, wz - 0.54).rotation.z = 0.15;
addRoute("garden wheelbarrow watch perch", [v(wx - 1.4, wy + 2.35, wz), v(wx + 1.4, wy + 2.35, wz)], {
  kind: "lookout",
});
// Hanging ristra, one and only one, on the park shed's porch beam.
const SHED_X = 203,
  SHED_Z = 328,
  SHED_Y = terrainHeight(SHED_X, SHED_Z);
const shedGroup = new THREE.Group();
shedGroup.position.set(SHED_X, SHED_Y, SHED_Z);
scene.add(shedGroup);
box(12, 6.1, 10, mat("#a89c7d"), 0, 3.05, 0, shedGroup);
const shedRoof = box(14, 0.52, 12, mat("#5f5d56"), 0, 6.36, 0, shedGroup);
shedRoof.rotation.z = 0.09;
box(3.1, 4.3, 0.25, mat("#6a5743"), 0, 2.15, -5.1, shedGroup);
box(7, 0.16, 5, M.wood, 0, 0.32, -7.5, shedGroup);
for (const xx of [-4, 4]) span(v(xx, 0.38, -10), v(xx, 6.0, -10), 0.13, 0.13, M.wood, shedGroup);
span(v(-5, 6, -10), v(5, 6, -10), 0.14, 0.14, M.wood, shedGroup);
for (let i = 0; i < 9; i++) {
  const y = SHED_Y + 5.65 - i * 0.36,
    z = SHED_Z - 10;
  const hot = ball(
    0.17,
    mat(i % 3 === 0 ? "#e05a21" : "#b52620", 0.26),
    SHED_X + 2 + Math.sin(i * 0.9) * 0.08,
    y,
    z,
  );
  hot.scale.set(0.55, 1.65, 0.7);
} // few missing peppers midway down, no special quest marker
// Tiny enterable indoor pocket behind doorway, not an entire house interior.
const houseCorner = { x: 255, z: 328, w: 13, d: 11 };
const hy = terrainHeight(houseCorner.x, houseCorner.z);
box(13, 5, 11, mat("#d4c8b4"), 255, hy + 2.5, 328);
box(14, 0.3, 12, mat("#756955"), 255, hy + 5.25, 328);
box(3.4, 3.2, 0.24, M.black, 255, hy + 1.6, 322.3);
// Hollowed logs, hollow tree pocket and simple shelter markers feed the predator test.
const shelterZones = [
  { type: "log", x: -19, z: 376, r: 4 },
  { type: "bridge", x: -116, z: 371, r: 4 },
  { type: "hollow", x: 95, z: 359, r: 4 },
  { type: "shed", x: 203, z: 328, r: 6 },
  { type: "house", x: 255, z: 328, r: 7 },
];
for (const s of shelterZones.slice(0, 3)) {
  const y = terrainHeight(s.x, s.z),
    g = new THREE.Group();
  g.position.set(s.x, y, s.z);
  scene.add(g);
  if (s.type === "log") {
    let log = cyl(2.4, 2.3, 9.2, M.bark, 0, 1.9, 0, g, 13);
    log.rotation.z = PI / 2;
    let cavity = cyl(1.3, 1.3, 0.08, M.black, 4.65, 1.9, 0, g, 13);
    cavity.rotation.z = PI / 2;
  }
  if (s.type === "hollow") {
    cyl(1.7, 2.3, 8, M.bark, 0, 4, 0, g);
    ball(1.2, M.black, 0, 1.9, -1.53, g).scale.z = 0.2;
  }
}
// L-shaped accessible sewer. ENTER through E at either labeled grate, exit using E.
const sewerA = v(123, 0, 334),
  sewerCorner = v(123, 0, 264),
  sewerB = v(200, 0, 264);
const sewerFloorY = -3.4,
  SEWER_Z1 = 334,
  SEWER_X1 = 123,
  SEWER_Z2 = 264,
  SEWER_X2 = 200;
const sewerSegments = [
    [sewerA, sewerCorner],
    [sewerCorner, sewerB],
  ],
  sewerFixtures = [];
for (const [a, b] of sewerSegments) {
  const dist = Math.hypot(a.x - b.x, a.z - b.z),
    mid = a.clone().add(b).multiplyScalar(0.5),
    angle = -Math.atan2(b.x - a.x, b.z - a.z);
  const grp = new THREE.Group();
  grp.position.set(mid.x, 0, mid.z);
  grp.rotation.y = angle;
  scene.add(grp);
  box(5.8, 0.24, dist + 2, mat("#454a41"), 0, sewerFloorY - 0.16, 0, grp);
  for (const s of [-1, 1]) {
    box(0.44, 4.6, dist + 1, mat("#777d70"), s * 2.85, sewerFloorY + 2.3, 0, grp);
    box(0.22, 0.12, dist + 1, mat("#d7cd9c"), s * 2.63, sewerFloorY + 2.75, 0, grp);
  }
  box(5.8, 0.3, dist + 1, agedStone, 0, sewerFloorY + 4.7, 0, grp);
  for (let i = 1; i < dist / 9; i++) {
    const zz = -dist / 2 + i * 9;
    box(0.18, 4.6, 0.18, M.metal, 0, sewerFloorY + 2.3, zz, grp);
  }
}
for (const grate of [sewerA, sewerB]) {
  const yy = terrainHeight(grate.x, grate.z);
  cyl(2.1, 2.1, 0.13, M.metal, grate.x, yy + 0.17, grate.z, scene, 18);
  for (let i = -2; i <= 2; i++) box(0.14, 0.09, 3.5, mat("#b0b7a7"), grate.x + i * 0.7, yy + 0.24, grate.z);
  const label = box(4.2, 0.12, 1, mat("#e5b56c"), grate.x, yy + 0.22, grate.z + 3.2);
  label.castShadow = false;
}
for (const p of [v(123, 0, 281), v(165, 0, 264)]) {
  const light = box(
    0.36,
    0.16,
    4.1,
    new THREE.MeshBasicMaterial({ color: 0xc6c89a }),
    p.x,
    sewerFloorY + 3.1,
    p.z,
  );
  light.castShadow = false;
  sewerFixtures.push(light);
}
// Little freestanding sewer outfitter at the elbow. No extra shop interior.
const standPoint = v(130, sewerFloorY + 0.2, 264);
const stand = box(2.3, 3.2, 1.3, mat("#ac8058"), standPoint.x, sewerFloorY + 1.6, standPoint.z);
for (let i = 0; i < 3; i++)
  box(1.8, 0.1, 0.7, agedStone, standPoint.x, sewerFloorY + 0.85 + i * 0.72, standPoint.z + 0.72);
const miniHat = new THREE.Mesh(new THREE.ConeGeometry(0.45, 0.95, 7), mat("#d2b16f"));
miniHat.position.set(standPoint.x, sewerFloorY + 3.9, standPoint.z);
scene.add(miniHat);

// Slightly busier yards on the *new* northern edge; dogs are handled in the update loop.
for (const [x, z] of [
  [203, 365],
  [236, 397],
  [90, 308],
]) {
  const y = terrainHeight(x, z);
  box(3.9, 2.5, 3.8, mat("#8d694b"), x, y + 1.25, z);
  box(4.4, 0.27, 4.4, mat("#635044"), x, y + 2.63, z);
  ball(0.67, M.black, x, y + 0.75, z - 1.94).scale.set(1, 1.15, 0.22);
}

// --- v0.8 WEST HOSPITAL SPUR: additive to north park + Cedar Rest cemetery. ---
// Compact west spur increases total land ~8%, far below the double-area ceiling.
const HOSP_X = -356,
  HOSP_Z = 353,
  HOSP_W = 94,
  HOSP_D = 96;
const HOSP_BASE = terrainHeight(HOSP_X, HOSP_Z),
  HOSPITAL_FLOOR = HOSP_BASE + 0.42;
addNorthernGround(-429, -269.96, 245, 440);
districtRibbon("x", 283, 12, -417, -238, M.asphalt, 0.14);
for (const zz of [273.5, 292.5]) districtRibbon("x", zz, 2.7, -421, -238, concrete, 0.18);
districtRibbon("z", -356, 8, 284, 305, M.asphalt, 0.16);
for (const xx of [-362.5, -349.5]) districtRibbon("z", xx, 1.7, 283, 306, concrete, 0.2);
const hospitalGroup = new THREE.Group();
hospitalGroup.position.set(HOSP_X, HOSP_BASE, HOSP_Z);
scene.add(hospitalGroup);
const hospitalWhite = mat("#e6e5db"),
  hospitalBrick = mat("#a5ada9"),
  hospitalBlue = mat("#628e9d"),
  hospitalFloorMat = mat("#b9c4ba"),
  hospitalTile = mat("#e5eee9"),
  hospitalGlow = new THREE.MeshBasicMaterial({ color: 0xf0f6db });
box(HOSP_W + 3, 0.8, HOSP_D + 3, mat("#abb4ac"), 0, 0.15, 0, hospitalGroup);
box(HOSP_W, 0.18, HOSP_D, hospitalFloorMat, 0, 0.57, 0, hospitalGroup);
// Walls are individual panels; the front doors show the lit entry from outside.
for (const side of [-1, 1]) {
  box(1.2, 12, HOSP_D, hospitalWhite, (side * HOSP_W) / 2, 6.3, 0, hospitalGroup);
  for (const z of [-34, -14, 12, 31]) {
    box(0.08, 4.3, 9.1, M.glass, side * (HOSP_W / 2 + 0.68), 5.4, z, hospitalGroup);
  }
}
box(HOSP_W, 12, 1.3, hospitalWhite, 0, 6.3, HOSP_D / 2, hospitalGroup);
for (const x of [-29, 29]) box(35.5, 12, 1.2, hospitalWhite, x, 6.3, -HOSP_D / 2, hospitalGroup);
box(19, 5.0, 1.25, hospitalWhite, 0, 10.0, -HOSP_D / 2, hospitalGroup);
const hospitalDoorHinges = [];
for (const side of [-1, 1]) {
  const pivot = new THREE.Group();
  pivot.position.set(side * 8.2, 0, -HOSP_D / 2 - 0.67);
  hospitalGroup.add(pivot);
  const pane = box(7.55, 7.6, 0.15, M.glass, -side * 3.78, 4.18, 0, pivot);
  pane.castShadow = false;
  box(0.15, 7.65, 0.22, M.metal, -side * 7.5, 4.18, 0, pivot);
  box(0.12, 0.65, 0.24, M.metal, -side * 2.0, 4.0, 0.15, pivot);
  hospitalDoorHinges.push({ pivot, side });
}
box(22, 0.75, 7.3, mat("#4a6b69"), 0, 8.1, -HOSP_D / 2 - 3, hospitalGroup);
for (const x of [-9, 9]) cyl(0.3, 0.3, 7.5, M.metal, x, 3.85, -HOSP_D / 2 - 6, hospitalGroup);
const hospitalRoof = box(HOSP_W + 3, 0.75, HOSP_D + 3, mat("#718c90"), 0, 12.8, 0, hospitalGroup);
for (const z of [-21, 5, 30])
  for (const x of [-34, -12, 14, 33]) {
    const l = box(8, 0.07, 3.4, hospitalGlow, x, 11.0, z, hospitalGroup);
    l.castShadow = false;
  }
for (const x of [-30, -14, 16, 32])
  for (const z of [-35, -18]) {
    let seat = box(5, 0.5, 2.1, mat("#7e9ba1"), x, 1.23, z, hospitalGroup);
    box(5, 2.0, 0.35, hospitalBlue, x, 2.1, z + 1.1, hospitalGroup);
  }
const nurseDesk = box(12, 2.2, 3.2, mat("#9faeae"), -18, 1.66, -3, hospitalGroup);
box(5, 1.4, 0.3, M.black, -18, 3.1, -4.5, hospitalGroup);
box(12, 0.16, 3.8, hospitalWhite, -18, 2.9, -3, hospitalGroup);
const patientCheckin = box(12, 2.2, 3.2, mat("#9faeae"), 18, 1.66, -3, hospitalGroup);
box(5, 1.4, 0.3, M.black, 18, 3.1, -4.5, hospitalGroup);
box(12, 0.16, 3.8, hospitalWhite, 18, 2.9, -3, hospitalGroup);
// Eight hospital beds with their own curtains and believable treatment bays.
// Zoned emergency wing.  Partition breaks preserve central passages and sightlines.
const hospitalObstacles = [];
function innerWall(x, z, w, d, h = 6.7, material = hospitalWhite) {
  box(w, h, d, material, x, h / 2 + 0.68, z, hospitalGroup);
  hospitalObstacles.push({ x: HOSP_X + x, z: HOSP_Z + z, w, d });
}
// Waiting / triage / treatment are physically distinguishable rooms. Open doors at the center.
innerWall(-29, -12, 34, 0.65);
innerWall(29, -12, 34, 0.65);
innerWall(-22, -34, 0.55, 21);
innerWall(22, -34, 0.55, 21);
innerWall(-38, 2, 17, 0.55, 5.0);
innerWall(37, 2, 19, 0.55, 5.0);
innerWall(-22, 43, 26, 0.55, 4.6);
innerWall(27, 43, 26, 0.55, 4.6);
const signLocal = (text, x, z, w = 11, bg = "#486d70") => {
  const sign = box(w, 2.2, 0.13, signCanvas(text, bg, "#f7f7e9"), x, 6.5, z, hospitalGroup);
  sign.castShadow = false;
  return sign;
};
signLocal("WAITING / TRIAGE", 0, -17, 21);
signLocal("TREATMENT WARD", 0, 9, 21);
signLocal("OBSERVATION", 26, 42, 16);
signLocal("SUPPLIES", -31, 42, 12);
// Color-coded hospital circulation: leave a clear central spine and cross aisle.
const hospitalSpine = mat("#6ca99e"),
  hospitalTriageLine = mat("#bda17d");
box(3.4, 0.026, 67, hospitalSpine, 0, 0.697, 0, hospitalGroup);
box(69, 0.026, 2.6, hospitalTriageLine, 0, 0.701, 5.9, hospitalGroup);
for (const [text, x, z, width] of [
  ["EMERGENCY ENTRY", 0, -39, 12],
  ["RECEPTION", -20, -8, 11],
  ["PATIENT CHECK-IN", 19, -8, 17],
  ["BAYS 1 - 4", -24, 11, 13],
  ["BAYS 5 - 8", 23, 31, 13],
  ["EXIT", 0, -44, 9],
]) {
  signLocal(text, x, z, width, "#456b67");
}

// Floor stripes guide the eye along the public path, away from the gurneys.
for (const x of [-8.3, 8.3]) box(0.22, 0.025, 43, mat("#5e8f8c"), x, 0.69, -24, hospitalGroup);
for (let z = -42; z < 44; z += 7) box(1.2, 0.028, 0.22, mat("#819c96"), 0, 0.7, z, hospitalGroup);
// Check-in: countertops, chart cubbies, monitors, plants and overhead lighting.
for (let i = 0; i < 5; i++) {
  box(2.35, 1.9, 1.1, mat(i % 2 ? "#889b92" : "#aebcb6"), -18 + i * 2.35, 2.05, -7, hospitalGroup);
  box(1.35, 0.92, 0.15, M.black, -18 + i * 2.35, 3.42, -7.55, hospitalGroup);
}
for (const [x, z] of [
  [-42, -43],
  [40, -42],
  [-40, 39],
  [40, 39],
]) {
  cyl(0.7, 0.55, 1.05, mat("#9c8a74"), x, 1.16, z, hospitalGroup);
  for (let j = 0; j < 4; j++)
    ball(
      0.95,
      mat(j % 2 ? "#416b53" : "#63896c"),
      x + Math.sin(j * 2.5) * 0.36,
      2.1 + j * 0.32,
      z + Math.cos(j * 2.5) * 0.38,
      hospitalGroup,
    ).scale.set(0.7, 0.83, 0.71);
}
// Supply shelving and mobile clinical carts are set against the walls.
for (const x of [-42, -36])
  for (let j = 0; j < 4; j++) {
    box(5, 0.16, 2.5, mat("#7c9c9e"), x, 1.8 + j * 1.25, 40, hospitalGroup);
    for (let k = 0; k < 3; k++)
      box(
        1.1,
        0.58,
        0.75,
        mat(k % 2 ? "#c8d5c7" : "#93aeba"),
        x - 1.25 + k * 1.25,
        2.18 + j * 1.25,
        40,
        hospitalGroup,
      );
  }
for (const [x, z] of [
  [-31, -17],
  [31, -18],
  [39, 7],
]) {
  box(3.6, 1.35, 2.3, hospitalWhite, x, 1.32, z, hospitalGroup);
  for (const dx of [-1.2, 1.2])
    for (const dz of [-0.8, 0.8]) ball(0.26, M.rubber, x + dx, 0.4, z + dz, hospitalGroup);
  box(2.1, 0.16, 1.4, hospitalBlue, x, 2.07, z, hospitalGroup);
}
// Surgical lamps, cardiac monitors, hanging IV bags and wall rails give each bay detail.
for (const x of [-33, -11, 11, 33])
  for (const z of [15, 35]) {
    box(2.3, 1.8, 0.24, mat("#394f54"), x - 3.5, 4.8, z + 3.4, hospitalGroup);
    box(1.9, 0.08, 0.09, mat("#8edf95"), x - 3.5, 4.9, z + 3.54, hospitalGroup);
    span(v(x + 3.2, 1.0, z - 3), v(x + 3.2, 5.7, z - 3), 0.075, 0.075, M.metal, hospitalGroup);
    box(0.65, 1, 0.22, mat("#c6ded9"), x + 3.2, 4.55, z - 3, hospitalGroup);
    cyl(1.65, 1.65, 0.15, mat("#e7e9d4"), x, 10.7, z, hospitalGroup);
    ball(1.0, hospitalGlow, x, 10.52, z, hospitalGroup).scale.set(1.3, 0.14, 1.3);
  }
// Keep the central aisle open; furniture bounds apply to the player without
// accidentally changing the staff's partition-based circuits.
const hospitalFurnitureColliders = [
  { x: HOSP_X - 18, z: HOSP_Z - 3, w: 12.5, d: 3.8 },
  { x: HOSP_X + 18, z: HOSP_Z - 3, w: 12.5, d: 3.8 },
];
const hospitalBeds = [];
for (let i = 0; i < 8; i++) {
  const x = -33 + (i % 4) * 22,
    z = 15 + Math.floor(i / 4) * 20;
  const b = box(7, 0.7, 11, mat("#d9e7e6"), x, 1.36, z, hospitalGroup);
  box(7, 0.35, 2, hospitalWhite, x, 1.75, z + 4.3, hospitalGroup);
  for (const side of [-1, 1])
    for (const end of [-1, 1]) cyl(0.14, 0.14, 0.9, M.metal, x + side * 3, 1.0, z + end * 4.6, hospitalGroup);
  const curtain = box(0.22, 5, 11, mat(i % 3 ? "#b8cac4" : "#d0d9cb"), x + 4.1, 3.3, z, hospitalGroup);
  curtain.material.transparent = true;
  curtain.material.opacity = 0.67;
  hospitalBeds.push({ x: HOSP_X + x, z: HOSP_Z + z });
  hospitalFurnitureColliders.push({ x: HOSP_X + x, z: HOSP_Z + z, w: 7.3, d: 11.3 });
}
// v1.0 hospital readable micro-spaces: triage benches, intake desk, fluid bags,
// colored treatment screens and a small central isolation curtain. Decorative only;
// pathways stay clear of the real partition collision bounds.
const woodTone = mat("#a4b8ae"),
  sterileSteel = mat("#84999a", 0.4, 0.62),
  scrubBlue = mat("#427e89");
for (const [xx, zz, rotate] of [
  [-32, -26, 0],
  [-31, -22, 0],
  [32, -27, PI],
  [32, -23, PI],
]) {
  const q = new THREE.Group();
  q.position.set(xx, 0, zz);
  q.rotation.y = rotate;
  hospitalGroup.add(q);
  box(4.8, 0.24, 1.45, woodTone, 0, 1.04, 0, q);
  box(4.8, 1.15, 0.22, woodTone, 0, 1.55, -0.65, q);
  for (const off of [-2, 2]) {
    box(0.13, 1.15, 0.18, sterileSteel, off, 0.53, -0.42, q);
    box(0.13, 1.15, 0.18, sterileSteel, off, 0.53, 0.42, q);
  }
}
for (const [xx, zz] of [
  [-30, 14],
  [-8, 35],
  [12, 15],
  [33, 35],
]) {
  span(v(xx, 1.0, zz), v(xx, 6.2, zz), 0.055, 0.06, sterileSteel, hospitalGroup);
  const bag = box(0.46, 0.76, 0.25, mat("#d3e9dd", 0.28), xx, 5.76, zz + 0.08, hospitalGroup);
  bag.castShadow = false;
  span(v(xx, 5.38, zz), v(xx + 0.33, 4.7, zz + 0.12), 0.012, 0.012, sterileSteel, hospitalGroup);
}
for (const [xx, zz] of [
  [-18, 2],
  [18, 2],
]) {
  box(5.8, 1.5, 2.3, woodTone, xx, 1.5, zz, hospitalGroup);
  box(3.1, 0.22, 0.12, scrubBlue, xx, 2.39, zz + 1.23, hospitalGroup);
  box(1.5, 0.82, 0.09, M.black, xx - 1.2, 3.03, zz - 0.3, hospitalGroup);
  box(1.3, 0.08, 0.09, mat("#9fe4ad"), xx - 1.2, 3.1, zz - 0.18, hospitalGroup);
}
for (let k = 0; k < 6; k++) {
  const xx = k % 2 === 0 ? -43.5 : 43.5,
    zz = -8 + Math.floor(k / 2) * 13;
  box(0.22, 3.8, 4.0, mat("#bed5d0", 0.75), xx, 2.77, zz, hospitalGroup);
}
// A clearly marked emergency sign and a deliberately straight-faced squirrel-bite notice.
flatSign("HOSPITAL  ·  EMERGENCY", HOSP_X, HOSP_BASE + 14.35, HOSP_Z - 49.5, 35, 2.65, "#335f67", "#f8fbf7");
flatSign("SQUIRREL BITES  →", HOSP_X + 11, HOSP_BASE + 9.25, HOSP_Z - 49.8, 13.5, 1.3, "#9d4037", "#fff7e8");
flatSign(
  "EMERGENCY ENTRANCE",
  HOSP_X + 29,
  terrainHeight(HOSP_X + 29, HOSP_Z - 54) + 3.6,
  HOSP_Z - 54,
  27,
  2.6,
  "#386a70",
  "#f8f9ed",
);
flatSign("HOSPITAL  ←", -232, terrainHeight(-232, 298) + 5, 298, 21, 3.1, "#315d60", "#f5f6ee");
// Stretcher trolley props, gurney rail and visitor silhouettes can be seen through glass.
function stretcherModel(parent) {
  const g = new THREE.Group();
  parent.add(g);
  box(5.3, 0.27, 2.25, hospitalWhite, 0, 1.55, 0, g);
  box(1.0, 0.34, 2.1, hospitalBlue, 1.95, 1.84, 0, g);
  for (const side of [-1, 1]) {
    span(v(-2.4, 1.6, side * 1.2), v(2.5, 1.6, side * 1.2), 0.085, 0.085, M.metal, g);
  }
  for (const x of [-2, 2])
    for (const z of [-0.86, 0.86]) {
      cyl(0.18, 0.18, 1.4, M.metal, x, 0.79, z, g);
      ball(0.25, M.rubber, x, 0.24, z, g);
    }
  return g;
}
const stretchers = [];
for (const [x, z] of [
  [-33, -1],
  [28, 3],
  [-18, 33],
]) {
  const st = stretcherModel(hospitalGroup);
  st.position.set(x, 0, z);
  stretchers.push(st);
}
// Purpose-built connected ventilation path with a climbing section to an overhead ward hatch.
// Nodes are WORLD coordinates. The first four preserve the existing duct layout.
const ductNodes = [
  v(HOSP_X - 38, HOSPITAL_FLOOR + 2.8, HOSP_Z - 12),
  v(HOSP_X - 9, HOSPITAL_FLOOR + 2.8, HOSP_Z - 12),
  v(HOSP_X - 9, HOSPITAL_FLOOR + 2.8, HOSP_Z + 25),
  v(HOSP_X + 30, HOSPITAL_FLOOR + 2.8, HOSP_Z + 25),
  v(HOSP_X + 30, HOSPITAL_FLOOR + 4.2, HOSP_Z + 29),
  v(HOSP_X + 30, HOSPITAL_FLOOR + 7.6, HOSP_Z + 36),
  v(HOSP_X + 11, HOSPITAL_FLOOR + 7.6, HOSP_Z + 36),
];
const ductLengths = [0];
for (let i = 1; i < ductNodes.length; i++)
  ductLengths.push(ductLengths[i - 1] + ductNodes[i].distanceTo(ductNodes[i - 1]));
const ductTotalLength = ductLengths[ductLengths.length - 1];
function ductPointAt(s) {
  s = THREE.MathUtils.clamp(s, 0, ductTotalLength);
  let i = 1;
  while (i < ductLengths.length - 1 && ductLengths[i] < s) i++;
  return ductNodes[i - 1]
    .clone()
    .lerp(ductNodes[i], (s - ductLengths[i - 1]) / (ductLengths[i] - ductLengths[i - 1]));
}
function ductDistanceFromPoint(p) {
  let best = 0,
    d = Infinity;
  for (let i = 1; i < ductNodes.length; i++) {
    const a = ductNodes[i - 1],
      delta = ductNodes[i].clone().sub(a),
      t = THREE.MathUtils.clamp(p.clone().sub(a).dot(delta) / delta.lengthSq(), 0, 1);
    const projected = a.clone().addScaledVector(delta, t),
      dd = projected.distanceToSquared(p);
    if (dd < d) {
      d = dd;
      best = ductLengths[i - 1] + t * (ductLengths[i] - ductLengths[i - 1]);
    }
  }
  return best;
}
function ductTangentAt(s) {
  const back = ductPointAt(Math.max(0, s - 0.6)),
    ahead = ductPointAt(Math.min(ductTotalLength, s + 0.6));
  return ahead.sub(back).normalize();
}
// low wall grilles are reachable from the hospital floor; the raised hatch is IN-DUCT only.
const ductVents = [
  { x: HOSP_X - 38, z: HOSP_Z - 12, height: 2.8, first: true, open: false, chew: 0 },
  { x: HOSP_X - 9, z: HOSP_Z - 12, height: 2.8, first: false, open: false, chew: 0 },
  { x: HOSP_X - 9, z: HOSP_Z + 25, height: 2.8, first: false, open: false, chew: 0 },
  { x: HOSP_X + 30, z: HOSP_Z + 25, height: 2.8, first: false, open: false, chew: 0 },
  { x: HOSP_X + 11, z: HOSP_Z + 36, height: 7.6, first: false, upper: true, open: false, chew: 0 },
];
const ductM = mat("#7e9291", 0.42, 0.6),
  ductWindowM = new THREE.MeshStandardMaterial({
    color: 0x829a96,
    metalness: 0.5,
    roughness: 0.5,
    transparent: true,
    opacity: 0.29,
    side: THREE.DoubleSide,
    depthWrite: false,
  });
for (let i = 0; i < ductNodes.length - 1; i++) {
  const a = ductNodes[i],
    b = ductNodes[i + 1],
    len = a.distanceTo(b),
    mid = a.clone().add(b).multiplyScalar(0.5);
  const tube = new THREE.Group();
  tube.position.set(mid.x - HOSP_X, mid.y - HOSP_BASE, mid.z - HOSP_Z);
  const delta = b.clone().sub(a);
  tube.quaternion.setFromUnitVectors(v(0, 0, 1), delta.clone().normalize());
  hospitalGroup.add(tube);
  // Leave an actual hole in the overhead duct floor, not merely a texture.
  if (i === ductNodes.length - 2) box(2.7, 0.13, Math.max(0.3, len - 3.1), ductM, 0, -0.88, -1.55, tube);
  else box(2.7, 0.13, len + 0.35, ductM, 0, -0.88, 0, tube);
  box(2.7, 0.12, len + 0.35, ductWindowM, 0, 0.88, 0, tube);
  for (const side of [-1, 1]) box(0.12, 1.76, len + 0.35, ductWindowM, side * 1.33, 0, 0, tube);
  for (let k = 1; k < Math.floor(len / 5); k++) {
    const p = -len / 2 + k * 5;
    box(2.72, 0.08, 0.1, mat("#566e70"), 0, 0.85, p, tube);
    for (const s of [-1, 1]) box(0.09, 1.68, 0.11, mat("#526367"), s * 1.24, 0, p, tube);
  }
  // Small, warm maintenance strip lights and grippy floor markings in the vents.
  for (let k = 3; k < len - 2; k += 8) {
    box(0.34, 0.025, 1.1, mat("#adb4a1", 0.35, 0.18), -1.07, -0.78, k - len / 2, tube);
    box(0.34, 0.025, 1.1, mat("#adb4a1", 0.35, 0.18), 1.07, -0.78, k - len / 2, tube);
    box(0.55, 0.045, 0.16, mat("#b6c9b0", 0.32), 0, 0.785, k - len / 2, tube);
  }
}
for (const ve of ductVents) {
  if (ve.upper) {
    // Suspended hatch / surround directly above a treatment bay.
    const x = ve.x - HOSP_X,
      z = ve.z - HOSP_Z,
      y = HOSPITAL_FLOOR - HOSP_BASE + ve.height - 0.84;
    for (const side of [-1, 1]) {
      box(0.22, 0.24, 3.65, M.metal, x + side * 1.53, y, z, hospitalGroup);
      box(3.35, 0.24, 0.22, M.metal, x, y, z + side * 1.62, hospitalGroup);
    }
    const panel = new THREE.Group();
    hospitalGroup.add(panel);
    panel.position.set(x, y, z);
    ve.panel = panel;
    box(2.7, 0.16, 2.9, mat("#7a8585"), 0, 0, 0, panel);
    for (let j = -2; j <= 2; j++) box(0.13, 0.1, 2.65, M.black, j * 0.47, 0.14, 0, panel);
    box(3.1, 0.12, 0.2, mat("#d5b25f"), x, y + 0.1, z + 1.45, hospitalGroup);
  } else {
    const grille = box(
      2.6,
      1.3,
      0.12,
      M.metal,
      ve.x - HOSP_X,
      HOSPITAL_FLOOR - HOSP_BASE + ve.height + 0.38,
      ve.z - HOSP_Z,
      hospitalGroup,
    );
    grille.rotation.y = ve.first ? PI / 2 : 0;
    ve.panel = grille;
    for (let t = -1; t <= 1; t++)
      box(
        2.4,
        0.08,
        0.18,
        M.black,
        ve.x - HOSP_X,
        HOSPITAL_FLOOR - HOSP_BASE + ve.height + 0.27 + t * 0.27,
        ve.z - HOSP_Z + 0.1,
        hospitalGroup,
      );
  }
}
// Accent lights give each duct bend and the elevated hatch a readable destination.
for (const index of [1, 2, 3, 5, 6]) {
  const p = ductNodes[index];
  const lamp = ball(0.2, hospitalGlow, p.x - HOSP_X, p.y - HOSP_BASE + 0.62, p.z - HOSP_Z, hospitalGroup);
  lamp.castShadow = false;
}
// Overhead attack landing indicator: only visible from the opened upper hatch.
const hatchLandingTarget = new THREE.Group();
scene.add(hatchLandingTarget);
hatchLandingTarget.visible = false;
const landingMat = new THREE.MeshBasicMaterial({
  color: 0xeaf5af,
  transparent: true,
  opacity: 0.68,
  depthTest: false,
  depthWrite: false,
});
const landingRing = new THREE.Mesh(new THREE.RingGeometry(0.42, 0.54, 32), landingMat);
landingRing.rotation.x = -PI / 2;
landingRing.renderOrder = 100;
hatchLandingTarget.add(landingRing);
for (let k = 0; k < 4; k++) {
  let theta = (k * PI) / 2;
  const tick = box(
    0.12,
    0.025,
    0.29,
    landingMat,
    Math.sin(theta) * 0.83,
    0.02,
    Math.cos(theta) * 0.83,
    hatchLandingTarget,
  );
  tick.rotation.y = theta;
}
function updateHatchLanding() {
  const hatch = overheadHatch();
  hatchLandingTarget.visible = !!hatch;
  if (!hatch) return;
  const lead = v(-Math.sin(yaw), 0, -Math.cos(yaw));
  hatchLandingTarget.position.set(
    ductVents[4].x + lead.x * 4.0,
    HOSPITAL_FLOOR + 0.05,
    ductVents[4].z + lead.z * 4.0,
  );
  hatchLandingTarget.scale.setScalar(1 + 0.06 * Math.sin(time * 3));
}
// Muted playground, deliberately beside the already-grown trees rather than a new park.
const playX = -13,
  playZ = 318,
  playY = terrainHeight(playX, playZ);
for (const swingX of [-4.2, 4.2]) {
  for (const leg of [-1, 1])
    span(
      v(playX + swingX + leg * 2.2, playY, playZ - 2),
      v(playX + swingX, playY + 5.8, playZ),
      0.16,
      0.14,
      M.metal,
    );
  for (const side of [-0.7, 0.7])
    span(
      v(playX + swingX + side, playY + 5.8, playZ),
      v(playX + swingX + side, playY + 1.2, playZ),
      0.038,
      0.038,
      M.metal,
    );
  box(2, 0.16, 0.6, mat("#d09b45"), playX + swingX, playY + 1.14, playZ);
}
const slideX = 27,
  slideZ = 317,
  slideY = terrainHeight(slideX, slideZ);
box(5, 0.25, 4.5, mat("#6d9eb0"), slideX, slideY + 3.0, slideZ);
const chute = box(2, 0.17, 8, mat("#d3a54b"), slideX, slideY + 1.6, slideZ + 5);
chute.rotation.x = 0.36;
for (const xx of [-2, 2])
  for (const zz of [-2, 2]) cyl(0.16, 0.18, 3, M.metal, slideX + xx, slideY + 1.5, slideZ + zz);
const sandX = 49,
  sandZ = 326,
  sandY = terrainHeight(sandX, sandZ);
box(9, 0.14, 8, mat("#dbc795"), sandX, sandY + 0.1, sandZ);
for (const x of [-4.5, 4.5]) box(0.35, 0.56, 8, M.wood, sandX + x, sandY + 0.31, sandZ);
for (const z of [-4, 4]) box(9, 0.56, 0.35, M.wood, sandX, sandY + 0.31, sandZ + z);

// Vertical downspouts are traversable gutter climbs, with real material and a roof join.
function addHouseGutters() {
  const metal = mat("#b6b9af", 0.46, 0.61);
  for (const h of houses) {
    const side = (h.id ?? 0) % 2 === 0 ? 1 : -1;
    const gx = h.x + side * (h.w * 0.5 - 0.66),
      gz = h.z + h.d * 0.5 + 0.2;
    const gy = terrainHeight(gx, gz) + 0.3,
      top = terrainHeight(gx, gz) + (h.cfg?.h || 5.3) - 0.15;
    const roof = routes
      .filter((r) => r.kind === "roof")
      .flatMap((r) => r.sampled.map((pt) => ({ pt, r, d: pt.distanceTo(v(gx, top, gz)) })))
      .sort((a, b) => a.d - b.d)[0];
    if (!roof || roof.d > 24) continue;
    span(v(gx, gy, gz), v(gx, top, gz), 0.12, 0.13, metal, scene, 7);
    addRoute("house downspout", [v(gx, gy, gz), v(gx, (gy + top) * 0.53, gz), v(gx, top, gz)], {
      kind: "trunk",
      surfaceRadius: 0.14,
    });
    const joint = v(gx, top, gz),
      ridge = roof.pt.clone();
    span(joint, ridge, 0.105, 0.11, metal, scene, 7);
    addRoute("gutter to roof", [joint, ridge], { kind: "bridge" });
  }
}
addHouseGutters();
// Overhead wires between branches and homes become the skeleton of the traversal network.
// Index sampled route points spatially so 40 trees and long wires remain responsive.
routeIndexLive = true;
for (const route of routes) indexRoute(route);
// Squirrel-readable tree forks: built ONLY from existing routes, not new playable branches.
// Each bough begins at the trunk; this registers its attachment even between sampled points.
const canopyForks = new Map();
function rebuildCanopyForks() {
  canopyForks.clear();
  for (const trunk of routes.filter((q) => q.kind === "trunk")) {
    const forks = [];
    const tname = trunk.name.replace(/ (?:giant |tree )?trunk$/, "");
    for (const branch of routes.filter(
      (q) => q.kind === "branch" || q.kind === "bridge" || q.kind === "lookout",
    )) {
      // Cheap name gate BEFORE comparing every sample point; avoids quadratic startup.
      const parkWatch = branch.name === "park high watch perch" && branch.kind === "lookout";
      if (!branch.name.startsWith(tname + " ") && !parkWatch) continue;
      const start = branch.curve.getPointAt(0);
      let nearest = null,
        nearDist = parkWatch ? 1.4 : 3.0;
      for (let i = 0; i < trunk.sampled.length; i++) {
        const pt = trunk.sampled[i],
          dist = pt.distanceTo(start);
        if (dist < nearDist) {
          nearDist = dist;
          nearest = { t: i / (trunk.sampled.length - 1), pos: pt };
        }
      }
      if (!nearest) continue;
      const outward = branch.curve.getPointAt(0.19).sub(start).setY(0).normalize();
      branch.trunkClearance = Math.max(branch.trunkClearance || 0, trunk.surfaceRadius || 1.3);
      forks.push({ trunk, branch, t: nearest.t, height: nearest.pos.y, origin: start, outward });
    }
    if (forks.length)
      canopyForks.set(
        trunk,
        forks.sort((a, b) => a.height - b.height),
      );
  }
}
// Registration happens once, after all world zones are created.
const forkVisual = new THREE.Group();
scene.add(forkVisual);
forkVisual.visible = false;
const forkMarkerMat = new THREE.MeshBasicMaterial({
  color: 0xe6faac,
  transparent: true,
  opacity: 0.87,
  depthTest: false,
  depthWrite: false,
});
const forkMarkers = [];
for (let k = 0; k < 5; k++) {
  const glow = new THREE.Mesh(new THREE.IcosahedronGeometry(0.105 + k * 0.01, 1), forkMarkerMat);
  glow.renderOrder = 100;
  forkVisual.add(glow);
  forkMarkers.push(glow);
}
let pendingFork = null,
  canopyHintTime = 0;
function clearPendingFork() {
  pendingFork = null;
  forkVisual.visible = false;
  $("branchGuide").style.display = "none";
}
function screenRightForTrunk() {
  return cameraRightXZ();
}
function nearbyCanopyForks() {
  if (!player.rail || player.rail.kind !== "trunk") return [];
  const all = canopyForks.get(player.rail) || [];
  const height = player.rail.curve.getPointAt(player.railT).y;
  const ahead = all.filter((f) => f.height >= height - 1.9 && f.height <= height + 10.5);
  if (ahead.length) return ahead;
  return all.filter((f) => Math.abs(f.height - height) < 5.5);
}
function chooseCanopyFork(side) {
  const branches = nearbyCanopyForks();
  if (!branches.length) {
    clearPendingFork();
    return false;
  }
  const right = screenRightForTrunk();
  const best = branches
    .map((f) => ({ ...f, delta: f.height - player.pos.y, side: f.outward.dot(right) }))
    .filter((f) => side * f.side > -0.1)
    .sort(
      (a, b) =>
        Math.max(0, a.delta) * 0.48 +
        Math.abs(a.delta) * 0.1 -
        Math.max(0, side * a.side) * 3.2 -
        (Math.max(0, b.delta) * 0.48 + Math.abs(b.delta) * 0.1 - Math.max(0, side * b.side) * 3.2),
    )[0];
  if (!best) return false;
  // Repeating A/D cycles through reachable choices instead of randomly grabbing a wire.
  const bySide = branches
    .filter((f) => side * f.outward.dot(right) > -0.1)
    .sort((a, b) => Math.abs(a.height - player.pos.y) - Math.abs(b.height - player.pos.y));
  const currentIdx = bySide.findIndex((f) => f.branch === pendingFork?.branch);
  const selected = currentIdx < 0 ? best : bySide[(currentIdx + 1) % bySide.length];
  pendingFork = selected;
  canopyHintTime = 5;
  flash(`Chosen: ${selected.branch.name}. Climb toward the fork; E to take it.`, 2.6);
  return true;
}
function sideStepToSibling(side) {
  if (player.rail?.kind !== "branch" || player.railT > 0.21) return false;
  const current = player.rail,
    up = Array.from(canopyForks.values()).flat();
  const parent = up.find((f) => f.branch === current);
  if (!parent) return false;
  const right = cameraRightXZ();
  const siblings = (canopyForks.get(parent.trunk) || []).filter(
    (f) => f.branch !== current && Math.abs(f.height - parent.height) < 2.9,
  );
  if (!siblings.length) return false;
  const selected = siblings
    .map((f) => ({ ...f, s: f.outward.dot(right) }))
    .filter((f) => f.s * side > -0.12)
    .sort((a, b) => b.s * side - a.s * side)[0];
  if (!selected) return false;
  if (!enterRoute({ route: selected.branch, t: 0.03, dir: 1 })) return false;
  player.transferCooldown = 0.4;
  flash(`BRANCH HOP · ${selected.branch.name} · W to run`, 2.3);
  return true;
}
function takeSelectedFork(force = false) {
  if (!pendingFork || player.rail !== pendingFork.trunk) return false;
  const f = pendingFork,
    dist = Math.abs(player.pos.y - f.height);
  if (dist > 2.15 && !force) return false;
  if (dist > 2.75) return false;
  const target = f.branch;
  clearPendingFork();
  if (!enterRoute({ route: target, t: 0.018, dir: 1 })) return false;
  player.transferCooldown = 0.55;
  flash(`ONTO ${target.name} · W out along the branch · S back`, 2.3);
  return true;
}
function updateCanopyGuide(dt) {
  const box = $("branchGuide");
  if (!player.rail || player.rail.kind !== "trunk") {
    if (pendingFork) clearPendingFork();
    else {
      forkVisual.visible = false;
      box.style.display = "none";
    }
    return;
  }
  const near = nearbyCanopyForks();
  if (
    pendingFork &&
    !near.some((f) => f.branch === pendingFork.branch) &&
    Math.abs(player.pos.y - pendingFork.height) > 12
  )
    clearPendingFork();
  const nearPrompt = near.length
    ? `${near.length} bough${near.length === 1 ? "" : "s"} nearby · A / D choose · E transfer`
    : "W climb · A / D choose at fork";
  box.style.display = "block";
  if (pendingFork) {
    const remaining = Math.max(0, pendingFork.height - player.pos.y);
    box.textContent = `↗ ${pendingFork.branch.name.toUpperCase()} · ${remaining < 2.2 ? "E TO TAKE BRANCH" : "CLIMB " + remaining.toFixed(1) + "m"} · A/D switch`;
    forkVisual.visible = true;
    for (let k = 0; k < forkMarkers.length; k++) {
      const p = pendingFork.branch.curve.getPointAt(0.055 + k * 0.05);
      forkMarkers[k].position.copy(p).add(v(0, 0.63 + Math.sin(time * 4 + k * 0.5) * 0.04, 0));
      forkMarkers[k].scale.setScalar(1 + 0.12 * Math.sin(time * 3 + k));
    }
  } else {
    forkVisual.visible = false;
    box.textContent = nearPrompt;
  }
}
// NPCs: 26 distinct cast members with schedules, silhouettes, personalities and reactions.
const NPC_DEFS = [
  ["Donna", "resident", 0, "#cc9b7e", "#b9a27b", "wary"],
  ["Frank", "resident", 0, "#d2b294", "#4d6885", "bluster"],
  ["Mrs. Abbott", "resident", 0, "#967058", "#b3b9a9", "panic"],
  ["Marty", "resident", 1, "#c99c7d", "#a26a48", "bluster"],
  ["Helen", "resident", 1, "#e6bea1", "#8f9b8d", "wary"],
  ["Tessa", "resident", 1, "#91654b", "#d1a575", "panic"],
  ["Calvin", "resident", 2, "#b88161", "#5b746f", "brave"],
  ["Ruth", "resident", 2, "#d1ab8d", "#a6a8c0", "wary"],
  ["Oliver", "resident", 2, "#ead0a8", "#718f8a", "panic"],
  ["Diana", "resident", 3, "#a8775c", "#e4c6ae", "wary"],
  ["Sam", "resident", 3, "#c79a71", "#516a8e", "brave"],
  ["Molly", "resident", 3, "#e4ba91", "#ad836c", "panic"],
  ["Eddie", "walker", -1, "#9e684d", "#88946d", "bluster"],
  ["Lou", "walker", -1, "#dfb28e", "#c7a9a4", "wary"],
  ["Kate", "walker", -1, "#b18767", "#a4bada", "panic"],
  ["Ray", "walker", -1, "#dfbc92", "#696a63", "brave"],
  ["Nina", "walker", -1, "#704f40", "#c4b082", "panic"],
  ["Jordan", "walker", -1, "#ba8361", "#576c56", "wary"],
  ["Dale", "walker", -1, "#c4a584", "#9e7e75", "bluster"],
  ["Kim", "jogger", -1, "#aa785d", "#d36e53", "wary"],
  ["Miles", "cyclist", -1, "#d8b18d", "#6d8586", "panic"],
  ["Zoe", "cyclist", -1, "#a67753", "#b65869", "wary"],
  ["Ari", "cyclist", -1, "#8d6a4f", "#bcb884", "brave"],
  ["Parker", "skater", -1, "#dfb99b", "#4e606e", "bluster"],
  ["Pat", "mail", -1, "#d3b08b", "#728ca6", "panic"],
  ["June", "walker", -1, "#855c48", "#b0a7bc", "wary"],
];
const humanoids = [];
const fleshCache = {};
function sharedSkin(hex) {
  return fleshCache[hex] || (fleshCache[hex] = mat(hex, 0.92));
}
// v3.9 bicycle geometry: wheel axle is X, the riding direction is local +Z.
// The entire rim/spoke assembly spins about X; use actual travel distance for rotation.
function makeSpokedBicycleWheel(parent, z, radius = 0.6) {
  const r = radius;
  const hub = new THREE.Group();
  hub.position.set(0, r + 0.045, z);
  parent.add(hub);
  hub.userData.spicyBicycleWheel = true;
  hub.userData.rollingRadius = r;
  let geometry = bicycleWheelMeshes.get(r);
  if (!geometry) {
    geometry = {
      tire: new THREE.TorusGeometry(r, 0.075, 8, 36),
      rim: new THREE.TorusGeometry(r - 0.083, 0.024, 6, 36),
      spoke: new THREE.CylinderGeometry(0.013, 0.013, 1, 5),
      hub: new THREE.CylinderGeometry(0.105, 0.105, 0.23, 12),
    };
    bicycleWheelMeshes.set(r, geometry);
  }
  const tire = new THREE.Mesh(geometry.tire, M.rubber);
  tire.rotation.y = PI / 2;
  hub.add(tire);
  const rim = new THREE.Mesh(geometry.rim, M.metal);
  rim.rotation.y = PI / 2;
  hub.add(rim);
  // Thin paired spokes form a wheel that reads clearly from either side.
  const count = 16,
    spokes = new THREE.InstancedMesh(geometry.spoke, M.metal, count);
  const origin = new THREE.Vector3(),
    tip = new THREE.Vector3(),
    mid = new THREE.Vector3();
  const q = new THREE.Quaternion(),
    m = new THREE.Matrix4(),
    scale = new THREE.Vector3();
  const up = new THREE.Vector3(0, 1, 0);
  for (let i = 0; i < count; i++) {
    const a = (2 * PI * i) / count;
    origin.set(i % 2 ? 0.068 : -0.068, 0, 0);
    tip.set(0, Math.sin(a) * (r - 0.1), Math.cos(a) * (r - 0.1));
    const d = tip.clone().sub(origin);
    mid.copy(origin).addScaledVector(d, 0.5);
    q.setFromUnitVectors(up, d.clone().normalize());
    scale.set(1, d.length(), 1);
    m.compose(mid, q, scale);
    spokes.setMatrixAt(i, m);
  }
  spokes.instanceMatrix.needsUpdate = true;
  spokes.frustumCulled = false;
  hub.add(spokes);
  const axle = new THREE.Mesh(geometry.hub, M.metal);
  axle.rotation.z = PI / 2;
  hub.add(axle);
  // Readable colored valve stem that visibly spins with the hub.
  ball(0.045, mat("#e4cb73"), 0.1, r - 0.1, 0, hub);
  return hub;
}
function makeHuman(def, idx) {
  const [name, role, home, skinColor, dress, personality] = def;
  const root = new THREE.Group();
  scene.add(root);
  const body = new THREE.Group();
  root.add(body);
  let proportion = R(0.87, 1.13);
  body.scale.setScalar(proportion * 0.59);
  const skin = sharedSkin(skinColor),
    shirt = mat(dress),
    pants = mat(pick(["#3d494b", "#646c61", "#55585a", "#827a6c", "#484957"])),
    shoe = mat("#2f3431");
  let torso = box(0.87, 1.42, 0.42, shirt, 0, 1.82, 0, body);
  let hips = box(0.75, 0.37, 0.5, pants, 0, 0.98, 0, body);
  let neck = cyl(0.14, 0.15, 0.3, skin, 0, 2.62, 0, body);
  let head = new THREE.Group();
  head.position.set(0, 2.9, 0);
  body.add(head);
  let skull = ball(0.47, skin, 0, 0.13, 0, head);
  skull.scale.set(0.84, 1.1, 0.78);
  let hair = mat(pick(["#40382f", "#755a45", "#bba27e", "#666663", "#2d2928", "#937d57"]));
  ball(0.43, hair, 0, 0.44, -0.03, head).scale.set(0.9, 0.45, 0.92);
  if (idx % 4 === 0) ball(0.24, hair, 0, 0.34, -0.36, head);
  for (let s of [-1, 1]) {
    ball(0.045, M.black, s * 0.17, 0.22, 0.36, head);
    ball(0.068, skin, s * 0.38, 0.11, 0, head);
  }
  ball(0.085, skin, 0, 0.04, 0.4, head).scale.set(0.8, 1, 0.7);
  const arms = [],
    legs = [];
  for (let s of [-1, 1]) {
    let a = new THREE.Group();
    a.position.set(s * 0.59, 2.37, 0);
    body.add(a);
    span(v(0, 0, 0), v(s * 0.14, -1.17, 0.06), 0.19, 0.135, shirt, a, 8);
    ball(0.14, skin, s * 0.14, -1.15, 0.06, a);
    arms.push(a);
    let leg = new THREE.Group();
    leg.position.set(s * 0.22, 0.86, 0);
    body.add(leg);
    span(v(0, 0, 0), v(0, -0.76, 0), 0.21, 0.14, pants, leg, 8);
    box(0.25, 0.18, 0.44, shoe, 0, -0.77, 0.13, leg);
    legs.push(leg);
  }
  const npc = {
    idx,
    name,
    role,
    home,
    personality,
    root,
    body,
    head,
    arms,
    legs,
    state: "walk",
    alert: 0,
    attention: 0,
    sayCooldown: 0,
    visible: false,
    goal: null,
    speed: R(0.8, 1.7),
    phase: R(0, PI * 2),
    facing: R(0, PI * 2),
    timeAway: 0,
    reacting: 0,
    bike: null,
    skill: R(0, 1),
    bubbles: [],
    maxLife: R(21, 51),
  };

  for (let s of [-1, 1]) {
    const glowEye = ball(
      0.06,
      new THREE.MeshStandardMaterial({
        color: 0x4b0a0a,
        emissive: 0x7e1111,
        emissiveIntensity: 0.0,
        roughness: 0.35,
        metalness: 0.0,
      }),
      s * 0.17,
      0.22,
      0.36,
      head,
    );
    glowEye.visible = false;
    (npc.redEyes || (npc.redEyes = [])).push(glowEye);
  }
  if (role === "mail") {
    box(1.4, 0.9, 0.36, mat("#6b7070"), 0.65, 1.4, 0.3, body);
    box(0.28, 0.14, 0.6, mat("#e8ebdb"), 0.45, 1.88, 0.3, body);
    box(0.85, 0.23, 0.88, mat("#54738a"), 0, 3.55, 0, body);
  }
  if (role === "cyclist" || role === "skater") {
    const vehicle = new THREE.Group();
    vehicle.position.set(0, 0.1, 0);
    root.add(vehicle);
    if (role === "cyclist") {
      const paint = mat(["#405979", "#b65e53", "#59826d", "#a58b4d"][idx % 4]);
      npc.bikeWheels = [
        makeSpokedBicycleWheel(vehicle, -1.05, 0.6),
        makeSpokedBicycleWheel(vehicle, 1.05, 0.6),
      ];
      // Rear triangle, main diamond, steering fork and handlebars all meet real axle points.
      const rear = v(0, 0.645, -1.05),
        front = v(0, 0.645, 1.05),
        seat = v(0, 1.42, -0.35);
      const crank = v(0, 0.83, -0.23),
        headTube = v(0, 1.39, 0.68);
      for (const [a, b, w] of [
        [rear, seat, 0.065],
        [rear, crank, 0.055],
        [seat, crank, 0.066],
        [seat, headTube, 0.068],
        [crank, headTube, 0.067],
        [headTube, front, 0.072],
      ])
        span(a, b, w, w * 0.86, paint, vehicle, 7);
      span(v(0, 1.42, -0.35), v(0, 1.59, -0.35), 0.055, 0.05, M.metal, vehicle);
      box(0.76, 0.12, 0.38, M.black, 0, 1.61, -0.36, vehicle);
      span(v(0, 1.39, 0.68), v(0, 1.67, 0.9), 0.065, 0.058, M.metal, vehicle);
      span(v(-0.49, 1.67, 0.91), v(0.49, 1.67, 0.91), 0.057, 0.057, M.metal, vehicle);
      for (const x of [-0.48, 0.48]) ball(0.075, M.black, x, 1.67, 0.91, vehicle);
      const pedals = new THREE.Group();
      pedals.position.copy(crank);
      vehicle.add(pedals);
      npc.bikeCrank = pedals;
      for (const s of [-1, 1]) {
        span(v(s * 0.17, 0, 0), v(s * 0.22, s * 0.27, 0), 0.035, 0.03, M.metal, pedals, 6);
        box(0.3, 0.07, 0.17, M.black, s * 0.22, s * 0.27, 0, pedals);
      }
      ball(0.085, mat("#fff3b5"), 0, 1.48, 0.91, vehicle);
      box(0.19, 0.16, 0.09, mat("#bd4d3e"), 0, 0.99, -1.1, vehicle);
      body.position.y = 0.72;
    } else {
      box(0.62, 0.14, 2.1, mat("#7f4e43"), 0, 0.22, 0, vehicle);
      for (let s of [-1, 1])
        for (let z of [-0.73, 0.73])
          cyl(0.13, 0.13, 0.13, M.rubber, s * 0.4, 0.12, z, vehicle).rotation.z = PI / 2;
      body.position.y = 0.24;
    }
    npc.bike = vehicle;
  }
  humanoids.push(npc);
  return npc;
}
NPC_DEFS.forEach(makeHuman);
makeHuman(["Tori", "park", -1, "#ae7c58", "#829476", "brave"], humanoids.length);
makeHuman(["Gene", "park", -1, "#e3c49b", "#5e8195", "wary"], humanoids.length);
makeHuman(["Evelyn", "mourner", -1, "#9e7662", "#414743", "panic"], humanoids.length);
const sentences = {
  spot: [
    "Oh, God! It’s one of those squirrels!",
    "OH NO! It’s one of those squirrels!",
    "Get away from me, you little bastard!",
    "It’s in the trees! IT’S IN THE TREES!",
    "What the hell is WRONG with that squirrel?!",
    "I TOLD you about those damn squirrels!",
  ],
  surprise: ["Oh my God! WHAT IS THAT?!", "What in the world is THAT?!"],
  hit: ["GET IT OFF! GET IT OFF!", "GET IT OFF ME!", "AAAH! SOMEONE HELP!"],
  escape: ["Not today!", "Stay AWAY!", "Oh, absolutely NOT!"],
};
const bubbleLayer = $("bubbleLayer");
let bubbles = [];
let speechOn = true;
const voiceCooldown = { next: 0 };
let lastVoiceName = "";
function speakCitizen(npc, text) {
  if (!speechOn || !("speechSynthesis" in window) || !("SpeechSynthesisUtterance" in window) || !playing)
    return;
  if (performance.now() < voiceCooldown.next) return;
  try {
    const synth = window.speechSynthesis;
    if (synth.pending || synth.speaking) return;
    const u = new SpeechSynthesisUtterance(text);
    const voices = synth.getVoices().filter((voice) => /^en/i.test(voice.lang));
    if (voices.length) {
      const options = voices.filter((voice) => voice.name !== lastVoiceName);
      const voice = (options.length ? options : voices)[
        npc.idx % Math.max(1, (options.length ? options : voices).length)
      ];
      u.voice = voice;
      lastVoiceName = voice.name;
    }
    u.rate = 0.98 + (npc.idx % 4) * 0.045;
    u.pitch = npc.personality === "panic" ? 1.23 : npc.personality === "bluster" ? 0.84 : 1.06;
    u.volume = 0.8;
    synth.speak(u);
    voiceCooldown.next = performance.now() + 2400;
  } catch (e) {}
}
function say(npc, text, color = "normal") {
  npc.sayCooldown = 8;
  let ob = document.createElement("div");
  ob.className = "bubble";
  ob.innerHTML = `<i>${npc.name}</i>${text.replaceAll("&", "&amp;").replaceAll("<", "&lt;")}`;
  bubbleLayer.appendChild(ob);
  bubbles.push({ npc, ob, life: 4.6 });
  speakCitizen(npc, text);
}
function squirrelActuallyInTree() {
  return Boolean(
    player.rail &&
      (player.rail.kind === "branch" || player.rail.kind === "trunk" || player.rail.kind === "lookout") &&
      player.pos.y > 3.2,
  );
}
function npcHasCompanion(npc) {
  return humanoids.some((p) => p !== npc && p.visible && p.root.position.distanceTo(npc.root.position) < 11);
}
function chooseLine(npc, kind) {
  if (kind === "hit") return pick(sentences.hit);
  if (kind === "spot") {
    if (random() < 0.065) return pick(sentences.surprise);
    const tree = squirrelActuallyInTree(),
      company = npcHasCompanion(npc);
    const options = sentences.spot.filter((line, i) => (i !== 3 || tree) && (i !== 5 || company));
    // Recognition is common. "In the trees" is impossible when on rooftops,
    // fence tops, the trampoline, the ground, or other non-tree routes.
    if (random() < 0.43) return pick([sentences.spot[0], sentences.spot[1]]);
    if (npc.personality === "bluster")
      return pick(
        options
          .filter((_, i) => true)
          .filter((line) => [sentences.spot[0], sentences.spot[2], sentences.spot[4]].includes(line)),
      );
    if (npc.personality === "panic" && tree && random() < 0.34) return sentences.spot[3];
    if (npc.personality === "wary" && company && random() < 0.35) return sentences.spot[5];
    return pick(options);
  }
  return pick(sentences.escape);
}
const sidewalkLanes = [
  { axis: "x", fixed: -12.1 },
  { axis: "x", fixed: 12.1 },
  { axis: "z", fixed: -12.1 },
  { axis: "z", fixed: 12.1 },
  { axis: "x", fixed: -161.9 },
  { axis: "x", fixed: -186.1 },
  { axis: "x", fixed: 158.9 },
  { axis: "x", fixed: 183.1 },
  { axis: "z", fixed: -167.9 },
  { axis: "z", fixed: -192.1 },
  { axis: "z", fixed: 165.9 },
  { axis: "z", fixed: 190.1 },
];
function pointOnLane(lane, u) {
  const x = lane.axis === "x" ? u : lane.fixed,
    z = lane.axis === "z" ? u : lane.fixed;
  return v(x, terrainHeight(x, z) + 0.13, z);
}
function pointOnSidewalk() {
  const lane = pick(sidewalkLanes.slice(0, 4));
  return pointOnLane(lane, R(-110, 110));
}
function pedestrianGoal(n) {
  const lane = n.pedLane;
  let u = lane.axis === "x" ? n.root.position.x : n.root.position.z;
  let direction = random() < 0.5 ? -1 : 1;
  if (lane.north) {
    const lo = lane.fixed === 326 ? -205 : 306,
      hi = lane.fixed === 326 ? 112 : 628;
    return pointOnLane(lane, THREE.MathUtils.clamp(u + direction * R(21, 65), lo, hi));
  }
  if (lane.commercial) {
    if (u > 615) direction = -1;
    if (u < 424) direction = 1;
  } else {
    if (u > WORLD_HALF - 45) direction = -1;
    if (u < -WORLD_HALF + 45) direction = 1;
  }
  return pointOnLane(
    lane,
    THREE.MathUtils.clamp(
      u + direction * R(37, 95),
      lane.commercial ? 390 : -260,
      lane.commercial ? 651 : 260,
    ),
  );
}
function spawnNpc(npc) {
  npc.onAccess = npc.role === "resident" && npc.home >= 0 && random() < 0.52;
  if (npc.role === "park" || npc.role === "mourner") {
    npc.pedLane = { axis: "x", fixed: npc.role === "park" ? 326 : 405, north: true };
    npc.root.position.copy(pointOnLane(npc.pedLane, npc.role === "park" ? R(-195, 112) : R(315, 624)));
    npc.goal = pedestrianGoal(npc);
  } else if (!npc.onAccess && [15, 18, 21, 25].includes(npc.idx)) {
    npc.pedLane = { axis: "x", fixed: npc.idx % 2 ? 17.4 : -17.4, commercial: true };
    npc.root.position.copy(pointOnLane(npc.pedLane, R(400, 635)));
    npc.goal = pedestrianGoal(npc);
  } else if (npc.onAccess) {
    const h = houses[npc.home],
      side = Math.sign(h.z);
    npc.pedLane = { axis: "x", fixed: side * 12.1 };
    const x = h.x + R(-2, 2),
      z = h.frontZ - side * R(0, 2.4);
    npc.root.position.set(x, terrainHeight(x, z) + 0.13, z);
    npc.accessX = x;
    npc.goal = pointOnLane({ axis: "z", fixed: x }, side * 12.1);
  } else {
    npc.pedLane = pick(sidewalkLanes.slice(0, random() < 0.8 ? 4 : sidewalkLanes.length));
    npc.root.position.copy(pointOnLane(npc.pedLane, R(-115, 115)));
    npc.goal = pedestrianGoal(npc);
  }
  npc.state = "walk";
  npc.alert = 0;
  npc.reacting = 0;
  npc.timeAway = 0;
  npc.sayCooldown = 0;
  npc.doorEscape = null;
  npc.hiddenInHomeUntil = 0;
  npc.visible = true;
  npc.root.visible = true;
  if (npc.role === "cyclist" || npc.role === "skater") npc.speed = R(3.2, 5.2);
  else if (npc.role === "jogger") npc.speed = 3.1;
  else npc.speed = R(0.8, 1.6);
}
// Show active cast for review; everyone is scheduled to rotate into the scene.
for (let i = 0; i < humanoids.length; i++) {
  humanoids[i].root.visible = false;
}
let npcTimer = 0,
  npcSpawnCursor = 0,
  demoCrowd = true;
// Place a small cross-section of the cast in view immediately, rather than waiting
// for the entire resident-only group to rotate through before special roles appear.
for (const [idx, x, z] of [
  [0, -31, -18],
  [14, -36, -16],
  [20, -11, -32],
  [23, -10, 23],
  [24, -13, -53],
  [15, 445, -17],
  [21, 496, 17],
]) {
  const n = humanoids[idx];
  spawnNpc(n); /* assigned safe house walkway or sidewalk lane during spawn */
}
npcSpawnCursor = 1;
for (const idx of [26, 27, 28]) spawnNpc(humanoids[idx]);
function manageNpcSpawns(dt) {
  npcTimer += dt;
  const count = humanoids.filter((n) => n.visible && !n.hospital && !n.specialStreetCast).length;
  const max = demoCrowd ? 14 : 7;
  if (count >= max || npcTimer < (demoCrowd ? 1.75 : 5)) return;
  const first =
    humanoids.find(
      (n, i) =>
        !n.visible &&
        !n.hospital &&
        !n.specialStreetCast &&
        (n.hiddenInHomeUntil || 0) <= time &&
        i >= npcSpawnCursor,
    ) ||
    humanoids.find(
      (n) => !n.visible && !n.hospital && !n.specialStreetCast && (n.hiddenInHomeUntil || 0) <= time,
    );
  if (first) {
    spawnNpc(first);
    npcSpawnCursor = (first.idx + 1) % 29;
    // Roughly 50% more paired appearances; keep companions on the same walkway.
    if (count + 1 < max && Math.random() < 0.56) {
      const mate = humanoids.find(
        (n) => n !== first && !n.visible && !n.hospital && !n.motorcycle && !n.specialStreetCast,
      );
      if (mate) {
        spawnNpc(mate);
        mate.onAccess = false;
        mate.pedLane = { ...first.pedLane };
        mate.root.position
          .copy(first.root.position)
          .add(v(first.pedLane?.axis === "z" ? 1.6 : 2.1, 0, first.pedLane?.axis === "z" ? 1.9 : 0));
        mate.goal = first.goal.clone();
        mate.speed = first.speed * 0.93;
      }
    }
  }
  npcTimer = 0;
}
// Hospital cast is fixed to the hospital and must not enter the roaming NPC scheduler.
const hospitalActors = [],
  hospitalStaff = [],
  hospitalPatients = [];
const hospitalNames = [
  ["Dr. Ellis", "doctor", "#d1a988", "#e9eee7"],
  ["Nurse Reed", "nurse", "#855946", "#75b0af"],
  ["Nurse Taylor", "nurse", "#d6b192", "#83ada3"],
  ["Guard Miller", "guard", "#98715a", "#4a6772"],
  ["Guard Shaw", "guard", "#d8b296", "#425e69"],
  ["Orderly Lane", "orderly", "#ad886f", "#9dabb3"],
  ["Orderly Park", "orderly", "#8a624d", "#9da9b1"],
  ["Ms. Vale", "extinguisher", "#c9a184", "#bc8172"],
];
const hospitalCoordinates = [
  [-14, -21],
  [2, -6],
  [19, -8],
  [-12, -32],
  [24, -30],
  [-28, 8],
  [29, 24],
  [38, -26],
];
for (let i = 0; i < hospitalNames.length; i++) {
  const [name, job, skin, color] = hospitalNames[i];
  const n = makeHuman([name, "hospital", -1, skin, color, i % 3 ? "brave" : "wary"], humanoids.length);
  n.hospital = true;
  n.hospitalRole = job;
  n.visible = true;
  n.root.visible = true;
  n.speed = job === "guard" ? 2.3 : job === "orderly" ? 1.6 : 1.05;
  n.nextBite = 0;
  const [rx, rz] = hospitalCoordinates[i];
  n.root.position.set(HOSP_X + rx, HOSPITAL_FLOOR, HOSP_Z + rz);
  n.station = n.root.position.clone();
  n.wayTarget = n.station.clone();
  n.hospitalPhase = i * 0.7;
  n.telegraph = 0;
  n.hitCooldown = 0;
  if (job === "orderly") {
    const trolley = stretcherModel(n.root);
    trolley.scale.setScalar(0.48);
    trolley.position.set(0, 0, 2.1);
  }
  if (job === "extinguisher") {
    const tank = cyl(0.32, 0.32, 1.14, mat("#cc3326"), 0.58, 1.33, 0.22, n.body);
    span(v(0.6, 1.8, 0.2), v(0.75, 2, 0.2), 0.07, 0.06, M.black, n.body);
  }
  if (job === "guard") box(0.86, 0.22, 0.74, mat("#2c3d43"), 0, 3.55, 0, n.body);
  hospitalActors.push(n);
  hospitalStaff.push(n);
}
for (let i = 0; i < 8; i++) {
  const name = ["Margie", "Bernard", "Lydia", "Walter", "Camille", "Edgar", "Joyce", "Toby"][i];
  const n = makeHuman(
    [
      name,
      "hospital",
      -1,
      ["#dbb795", "#b68a6b", "#9c6d55"][i % 3],
      ["#c99c83", "#8f99af", "#a9b793"][i % 3],
      "panic",
    ],
    humanoids.length,
  );
  n.hospital = true;
  n.hospitalRole = "patient";
  n.visible = true;
  n.root.visible = true;
  n.speed = 0.68;
  n.hospitalPhase = i * 0.87;
  n.nextBite = 0;
  const bed = hospitalBeds[i];
  n.station = v(bed.x, HOSPITAL_FLOOR, bed.z - 6.35);
  n.root.position.copy(n.station);
  n.wayTarget = n.station.clone();
  // A small, unobtrusive wrist wrap illustrates their injuries came from elsewhere.
  box(0.37, 0.22, 0.3, mat("#f2f0e1"), 0.43, 1.08, 0.08, n.body);
  hospitalPatients.push(n);
  hospitalActors.push(n);
}
function hospitalExitPoint() {
  return v(HOSP_X, HOSPITAL_FLOOR + 0.2, HOSP_Z - HOSP_D / 2 + 7);
}
// Smooth, cached character geometry keeps ears, muzzle and tail readable up close.
function squirrelBall(radius, material, x, y, z, parent) {
  return mesh(
    sharedGeometry(`squirrel:${radius}`, () => new THREE.SphereGeometry(radius, 16, 12)),
    material,
    x,
    y,
    z,
    parent,
  );
}
// Seven normal squirrels with independent 25-minute bite-triggered infection timers.
const normalSquirrels = [];
const normalSquirrelHides = [
  [-74, -71],
  [84, 70],
  [-196, 97],
  [217, -111],
  [-105, 321],
  [103, 409],
  [414, 332],
];
const squirrelFurs = ["#b78453", "#9a6b47", "#b19b7b", "#675e4d", "#a48c68", "#8c7463", "#c19c66"];
for (let i = 0; i < 7; i++) {
  const [x, z] = normalSquirrelHides[i],
    root = new THREE.Group();
  scene.add(root);
  const fur = mat(squirrelFurs[i]);
  const torso = squirrelBall(0.3, fur, 0, 0.27, 0, root);
  torso.scale.set(0.72, 0.68, 1.35);
  squirrelBall(0.2, fur, 0, 0.47, 0.31, root);
  for (let s of [-1, 1]) {
    squirrelBall(0.07, fur, s * 0.13, 0.65, 0.3, root);
    squirrelBall(0.039, M.black, s * 0.12, 0.49, 0.49, root);
  }
  const tail = squirrelBall(0.3, fur, 0, 0.71, -0.48, root);
  tail.scale.set(0.46, 1.7, 0.5);
  for (const side of [-1, 1])
    for (const fore of [-1, 1]) squirrelBall(0.068, fur, side * 0.18, 0.14, fore * 0.28, root);
  root.position.set(x, outdoorSurfaceAt(x, z) - 0.06, z);
  normalSquirrels.push({
    i,
    root,
    torso,
    tail,
    x,
    z,
    phase: i * 1.7,
    infected: false,
    progress: 0,
    component: 0,
  });
}
// Four rabbits, each circling a distinct bush/yard anchor; evasion is guaranteed.
const rabbits = [];
for (const [i, x, z] of [
  [0, -64, 93],
  [1, 72, 96],
  [2, -97, -70],
  [3, 206, 325],
]) {
  const root = new THREE.Group();
  scene.add(root);
  let color = mat(["#ab9d87", "#c2b39c", "#786d62", "#a88e78"][i]);
  ball(0.36, color, 0, 0.3, 0, root).scale.set(0.8, 0.7, 1.65);
  ball(0.24, color, 0, 0.45, 0.43, root);
  for (let s of [-1, 1]) {
    ball(0.13, color, s * 0.15, 0.75, 0.47, root).scale.set(0.5, 2.5, 0.64);
    ball(0.045, M.black, s * 0.16, 0.5, 0.6, root);
  }
  ball(0.21, M.white, 0, 0.34, -0.6, root);
  root.position.set(x, terrainHeight(x, z) + 0.1, z);
  const bush = ball(2.0, mat("#496c42"), x, terrainHeight(x, z) + 1.8, z);
  bush.scale.set(1.7, 1, 1.2);
  rabbits.push({ root, x, z, i, phase: i * 1.4, escapeUntil: 0 });
}

// Player: small articulated zombie squirrel, long tail, paws and pointed face.
const player = {
  pos: v(-36, 0.31, -36),
  vel: v(0, 0, 0),
  yaw: 0,
  grounded: true,
  rail: null,
  railT: 0,
  railDir: 1,
  transferCooldown: 0,
  moveSpeed: 0,
  focus: false,
  points: 0,
  hits: 0,
  inactiveSeconds: 0,
  boostRemaining: 0,
  cooldown: 0,
  attack: 0,
  attackWindow: 0,
  attackAlert: null,
  attackTarget: null,
  cameraCommit: 0,
  committedAirborne: false,
  turnLean: 0,
  alive: true,
  nearRoute: null,
  visible: true,
};
// Model is exactly 50% of the v0.4 squirrel size; movement speed stays agile.
const SQUIRREL_VISUAL_SCALE = 0.335;
const squirrel = new THREE.Group();
squirrel.scale.setScalar(SQUIRREL_VISUAL_SCALE);
scene.add(squirrel);
squirrel.position.copy(player.pos);
const sqroot = new THREE.Group();
squirrel.add(sqroot);
let fur = mat("#87694d"),
  fur2 = mat("#725b48"),
  furDark = mat("#3f3d37"),
  eyeMat = new THREE.MeshStandardMaterial({
    color: 0xbe2f25,
    emissive: 0xad1e16,
    emissiveIntensity: 0.92,
    roughness: 0.23,
  });
let sqBody = squirrelBall(0.55, fur, 0, 0.39, -0.04, sqroot);
sqBody.scale.set(0.79, 0.67, 1.51);
let sqHead = squirrelBall(0.36, fur, 0, 0.62, 0.65, sqroot);
sqHead.scale.set(0.79, 0.84, 1.06);
// Warm countershading separates the tiny animal from near-identical bark colors.
squirrelBall(0.33, mat("#c2a78a"), 0, 0.33, 0.4, sqroot).scale.set(0.65, 0.45, 0.95);
const paleFur = mat("#c6ae8c"),
  snoutMat = mat("#514a41"),
  toothMat = mat("#e5dbb8");
// The entire face turns as one assembly; eyes cannot drift away from the head.
const sqFace = new THREE.Group();
sqFace.position.copy(sqHead.position);
sqroot.add(sqFace);
sqHead.position.set(0, 0, 0);
sqFace.add(sqHead);
const faceBaseline = new Set(sqroot.children);
for (let side of [-1, 1]) {
  let ear = squirrelBall(0.145, fur2, side * 0.25, 0.96, 0.53, sqroot);
  ear.scale.set(0.69, 1.35, 0.6);
  let eartip = new THREE.Mesh(new THREE.ConeGeometry(0.092, 0.28, 6), furDark);
  eartip.position.set(side * 0.25, 1.135, 0.52);
  sqroot.add(eartip);
  squirrelBall(0.057, eyeMat, side * 0.205, 0.72, 0.886, sqroot);
  squirrelBall(0.016, mat("#fbe6bb", 0.18), side * 0.196, 0.747, 0.932, sqroot);
  squirrelBall(0.15, snoutMat, side * 0.12, 0.51, 1.04, sqroot).scale.set(0.7, 0.55, 1.14);
}
squirrelBall(0.056, mat("#a77972"), 0, 0.51, 1.23, sqroot);
for (const side of [-1, 1]) {
  let tooth = box(0.049, 0.14, 0.065, toothMat, side * 0.055, 0.37, 1.16, sqroot);
  tooth.rotation.x = -0.14;
}
for (const part of [...sqroot.children])
  if (!faceBaseline.has(part)) {
    part.position.sub(sqFace.position);
    sqFace.add(part);
  }
for (let i = 0; i < 18; i++) {
  const a = (i / 18) * 2 * PI;
  let tuft = new THREE.Mesh(
    new THREE.ConeGeometry(0.052 + random() * 0.04, 0.18 + random() * 0.2, 4),
    i % 3 ? fur : fur2,
  );
  tuft.position.set(Math.cos(a) * 0.3, 0.41 + Math.sin(a) * 0.19, -0.45 + random() * 0.4);
  tuft.rotation.z = PI / 2 + Math.sin(a) * 0.6;
  tuft.rotation.x = Math.cos(a) * 1.15;
  sqroot.add(tuft);
}
const sqLegs = [];
for (let side of [-1, 1])
  for (let front of [-1, 1]) {
    let pivot = new THREE.Group();
    pivot.position.set(side * 0.29, 0.18, front * 0.46);
    sqroot.add(pivot);
    let leg = squirrelBall(0.15, furDark, 0, -0.035, 0.1, pivot);
    leg.scale.set(0.9, 0.57, 1.52);
    sqLegs.push({ pivot, side, front });
    for (let claw = 0; claw < 3; claw++) {
      let nail = new THREE.Mesh(new THREE.ConeGeometry(0.018, 0.16, 4), mat("#c7bca3", 0.65));
      nail.position.set((claw - 1) * 0.09, -0.115, 0.3);
      nail.rotation.x = PI / 2;
      pivot.add(nail);
    }
  }
for (let side of [-1, 1])
  for (let q = 0; q < 3; q++) {
    let whisker = span(
      v(side * 0.1, 0.56, 1.04),
      v(side * (0.5 + q * 0.08), 0.58 + (q - 1) * 0.1, 1.3),
      0.013,
      0.004,
      mat("#c9baa0"),
      sqroot,
      5,
    );
    whisker.position.sub(sqFace.position);
    sqFace.add(whisker);
  }
// Dense overlapping tapered sections make a flexible tail without spherical beads.
const tailParts = [];
for (let i = 0; i < 22; i++) {
  const part = squirrelBall(1, i % 4 === 0 ? fur : fur2, 0, 0, 0, sqroot);
  tailParts.push(part);
}
function updateTail(t) {
  for (let i = 0; i < tailParts.length; i++) {
    const u = i / (tailParts.length - 1);
    const px = Math.sin(t * 4.2 + u * 4) * (0.035 + u * 0.18);
    const climbing = player.rail?.kind === "trunk";
    const py = climbing ? 0.26 + u * 0.11 : 0.43 + u * 1.38 + Math.sin(u * PI) * 0.34;
    const pz = -0.5 - u * 0.84 + u * u * 0.06;
    const segment = tailParts[i];
    segment.position.set(px, py, pz);
    const thick = 0.075 + Math.sin(u * PI) ** 0.8 * 0.33;
    segment.scale.set(thick, thick * 0.95, 0.15 + thick * 0.78);
    segment.rotation.x = -0.48 + u * 0.54;
  }
}
updateTail(0);
// Cache contact corners once; animate the real transforms before resolving feet.
const squirrelContactSamples = [];
for (const parent of [sqBody, ...sqLegs.map((leg) => leg.pivot)])
  parent.traverse((part) => {
    if (!part.isMesh) return;
    part.geometry.computeBoundingBox();
    const bounds = part.geometry.boundingBox,
      points = [];
    for (const x of [bounds.min.x, bounds.max.x])
      for (const y of [bounds.min.y, bounds.max.y])
        for (const z of [bounds.min.z, bounds.max.z]) points.push(v(x, y, z));
    squirrelContactSamples.push({ part, points });
  });
const squirrelContactPoint = v(0, 0, 0);
function squirrelSurfaceAt(x, z) {
  let height = outdoorSurfaceAt(x, z);
  const mall = mallSurfaceAt(x, z);
  if (mall !== null) height = Math.max(height, mall);
  const river = riverSurfaceAt(x, z);
  if (river !== null && player.pos.y >= river - 0.5) height = Math.max(height, river);
  return height;
}
function settleSquirrelFeet() {
  squirrel.updateWorldMatrix(true, true);
  let lift = 0;
  for (const sample of squirrelContactSamples)
    for (const point of sample.points) {
      squirrelContactPoint.copy(point).applyMatrix4(sample.part.matrixWorld);
      lift = Math.max(
        lift,
        squirrelSurfaceAt(squirrelContactPoint.x, squirrelContactPoint.z) + 0.017 - squirrelContactPoint.y,
      );
    }
  squirrel.position.y += lift;
  squirrel.updateWorldMatrix(true, true);
}

// Hidden chilies: precisely eight one-time collectibles per run. Their entropy is
// independent of the stable neighborhood seed so refreshing changes hiding places.
const CHILI_COUNT = 8,
  POWER_DECAY_INTERVAL = 600,
  POWER_DECAY_RATE = 0.15,
  RUSH_DURATION = 30,
  RUSH_SPEED = 1.6;
const pepperSeed = (() => {
  try {
    const a = new Uint32Array(1);
    crypto.getRandomValues(a);
    return a[0];
  } catch {
    return (Date.now() ^ Math.floor(Math.random() * 4294967296)) >>> 0;
  }
})();
const pepperRand = rng(pepperSeed),
  spiceR = (a, b) => a + (b - a) * pepperRand(),
  spicePick = (a) => a[Math.floor(pepperRand() * a.length)];
function shuffleSpice(a) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(pepperRand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}
const peppers = [],
  chiliColors = ["#d7241b", "#ff5a17", "#ce251e", "#e6ac27", "#d13023", "#e84d10", "#ad1b23", "#f5a232"];
function makeChiliMesh(hex) {
  const group = new THREE.Group();
  const positions = [],
    indices = [],
    rings = 13,
    sides = 10;
  for (let j = 0; j < rings; j++) {
    const u = j / (rings - 1),
      r = (0.045 + 0.245 * Math.sin(Math.PI * Math.pow(u, 0.74))) * (1 - Math.pow(u, 5)) + 0.011;
    const x = 0.24 * u * u,
      z = 0.06 * Math.sin(u * Math.PI * 1.4),
      y = -0.78 * u;
    for (let k = 0; k < sides; k++) {
      const a = (k / sides) * PI * 2;
      positions.push(x + r * Math.cos(a), y, z + r * Math.sin(a));
    }
  }
  for (let j = 0; j < rings - 1; j++)
    for (let k = 0; k < sides; k++) {
      const a = j * sides + k,
        b = j * sides + ((k + 1) % sides),
        c = (j + 1) * sides + k,
        d = (j + 1) * sides + ((k + 1) % sides);
      indices.push(a, c, b, b, c, d);
    }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  const pepperMaterial = new THREE.MeshStandardMaterial({
    color: hex,
    roughness: 0.27,
    metalness: 0.05,
    emissive: hex,
    emissiveIntensity: 0.14,
    side: THREE.DoubleSide,
  });
  const fruit = new THREE.Mesh(geo, pepperMaterial);
  fruit.castShadow = true;
  fruit.receiveShadow = true;
  group.add(fruit);
  const green = mat("#3b672d");
  cyl(0.095, 0.17, 0.13, green, 0, 0.04, 0, group, 7);
  const stem = span(v(0, 0.08, 0), v(-0.06, 0.37, 0.025), 0.065, 0.038, mat("#66893b"), group);
  for (let a = 0; a < 5; a++) {
    const ang = (a * PI * 2) / 5;
    const leaf = ball(0.11, green, Math.cos(ang) * 0.13, 0.01, Math.sin(ang) * 0.13, group);
    leaf.scale.set(1.2, 0.32, 0.61);
    leaf.rotation.y = ang;
  }
  return group;
}
function candidateOn(route, t, offset = v(0, 0.18, 0)) {
  return { pos: route.curve.getPointAt(t).add(offset), kind: route.kind, area: route.name };
}
const treeHides = treeSpec.map((spec, idx) => {
  const treeRoutes = routes.filter(
    (r) =>
      r.name.startsWith(spec.name) &&
      ((idx % 2 === 0 && r.kind === "trunk") || (idx % 2 === 1 && r.name.includes("bough"))),
  );
  const route = spicePick(treeRoutes);
  const t = spiceR(route.kind === "trunk" ? 0.34 : 0.32, route.kind === "trunk" ? 0.82 : 0.77);
  return candidateOn(
    route,
    t,
    route.kind === "trunk"
      ? v(spiceR(-0.32, 0.32), spiceR(0.15, 0.35), spiceR(-0.32, 0.32))
      : v(spiceR(-0.25, 0.25), spiceR(-0.24, 0.1), spiceR(-0.25, 0.25)),
  );
});
const elevatedHides = [
  () => candidateOn(spicePick(routes.filter((r) => r.kind === "roof")), spiceR(0.27, 0.76), v(0, 0.32, 0)),
  () => candidateOn(spicePick(routes.filter((r) => r.kind === "fence")), spiceR(0.18, 0.78), v(0, 0.34, 0)),
  () =>
    candidateOn(
      routes.find((r) => r.kind === "trampoline"),
      spiceR(0.11, 0.87),
      v(0, 0.28, 0),
    ),
  () =>
    candidateOn(
      spicePick(routes.filter((r) => r.kind === "wire" && r.name.includes("phone line"))),
      spiceR(0.2, 0.78),
      v(0, -0.25, 0),
    ),
];
const groundHides = [
  (() => {
    const x = GARDEN_X + 10 + spiceR(0, 5.5),
      z = GARDEN_Z - 10 + spiceR(0, 11);
    return {
      pos: v(x, terrainHeight(x, z) + 0.7, z),
      kind: "ground",
      area: "among the garden Tabasco peppers",
    };
  })(),
  { pos: v(-65, 0.67, -80), kind: "ground", area: "behind the barbecue" },
  { pos: v(43, 0.68, 83.3), kind: "ground", area: "behind the doghouse" },
  { pos: v(44, 0.67, -73), kind: "ground", area: "near a pool chair" },
  { pos: v(-67, 0.66, 87), kind: "ground", area: "outside the guesthouse" },
  { pos: v(75, 0.69, 83.5), kind: "ground", area: "behind the lawnmower" },
  { pos: v(-68, 0.67, -69), kind: "ground", area: "the long porch" },
  { pos: v(72, 0.71, 78.3), kind: "ground", area: "beside the bins" },
  { pos: v(39, 0.69, -83), kind: "ground", area: "behind the smoker" },
];
const chosenHides = [
  ...treeHides,
  ...shuffleSpice(elevatedHides)
    .slice(0, 2)
    .map((fn) => fn()),
  groundHides[0],
  ...shuffleSpice(groundHides.slice(1)).slice(0, 1),
];
chosenHides.forEach((hide, i) => {
  const model = makeChiliMesh(chiliColors[i]);
  model.position.copy(hide.pos);
  model.rotation.y = spiceR(-PI, PI);
  model.scale.setScalar(spiceR(0.85, 1.15));
  scene.add(model);
  peppers.push({ ...hide, model, found: false, phase: spiceR(0, PI * 2), baseY: hide.pos.y });
});
let chiliesFound = 0,
  hudRefreshTimer = 0;
let squirrelCoins = 0,
  goldCoins = 0,
  totalCoinsEarned = 0;
function mmss(seconds) {
  const s = Math.ceil(Math.max(0, seconds));
  return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}
function refreshPowerUI() {
  $("score").textContent = String(player.points).padStart(4, "0");
  $("hits").textContent = String(player.hits);
  $("evolution").textContent = player.points >= 1500 ? "SUPER" : player.points >= 600 ? "RABID" : "FERAL";
  $("powerFill").style.width = Math.min(100, (player.points / 1500) * 100) + "%";
  $("chiliCount").textContent = `${chiliesFound} / ${CHILI_COUNT}`;
  $("coinScore").textContent = String(squirrelCoins);
  $("goldScore").textContent = String(goldCoins);
  $("fadeTimer").textContent = mmss(POWER_DECAY_INTERVAL - player.inactiveSeconds);
  const active = player.boostRemaining > 0;
  $("boostBadge").classList.toggle("active", active);
  $("boostLabel").textContent = active ? "CHILI RUSH · +60%" : "CHILI RUSH";
  $("boostTime").textContent = active
    ? `${Math.ceil(player.boostRemaining)}s remaining · faster leaps`
    : chiliesFound === CHILI_COUNT
      ? "ALL PEPPERS FOUND"
      : "FIND A HIDDEN PEPPER";
}
function updatePepperPickups(dt) {
  for (const pep of peppers) {
    if (pep.found) continue;
    pep.model.position.y = pep.baseY + Math.sin(time * 1.45 + pep.phase) * 0.065;
    pep.model.rotation.z = Math.sin(time * 1.23 + pep.phase) * 0.09;
    if (player.pos.distanceTo(pep.model.position) < (pep.kind === "trunk" ? 2.2 : 1.4)) {
      pep.found = true;
      pep.model.visible = false;
      chiliesFound++;
      player.boostRemaining = Math.min(90, player.boostRemaining + RUSH_DURATION);
      goldCoins++;
      idleTime = 0;
      refreshPowerUI();
      fx(990, 0.13, "triangle", 0.07);
      flash(
        chiliesFound === CHILI_COUNT
          ? "ALL EIGHT CHILIS FOUND! No more will appear this run."
          : `SECRET CHILI FOUND! ${chiliesFound}/${CHILI_COUNT} · +60% speed for ${Math.ceil(player.boostRemaining)}s`,
        4,
      );
    }
  }
}
function updatePowerAndHeat(realActiveDt) {
  player.inactiveSeconds += realActiveDt;
  while (player.inactiveSeconds >= POWER_DECAY_INTERVAL) {
    player.inactiveSeconds -= POWER_DECAY_INTERVAL;
    if (player.points > 0) {
      const lost = Math.max(1, Math.ceil(player.points * POWER_DECAY_RATE));
      player.points = Math.max(0, player.points - lost);
      flash(`The hunger returns. No bite for 10 minutes: −${lost} Power (15%).`, 4);
      fx(160, 0.2, "sine", 0.035);
    }
  }
  const wasHot = player.boostRemaining > 0;
  player.boostRemaining = Math.max(0, player.boostRemaining - realActiveDt);
  if (wasHot && player.boostRemaining === 0)
    flash("The chili rush has faded. Find another hidden pepper.", 2.7);
  hudRefreshTimer -= realActiveDt;
  if (hudRefreshTimer <= 0) {
    hudRefreshTimer = 0.2;
    refreshPowerUI();
  }
}
refreshPowerUI();

// Human-readable status messages and camera orientation.
let messageTime = 0;
function flash(str, time = 3) {
  $("status").textContent = str;
  $("status").classList.add("show");
  messageTime = time;
}
let yaw = PI,
  pitch = 0.12;
const keys = new Set();
let pointer = false,
  playing = false,
  focusMouse = false,
  focusToggle = false;
let time = 0;
const raycaster = new THREE.Raycaster();
function requestMouse() {
  if (document.pointerLockElement === canvas) return;
  try {
    const result = canvas.requestPointerLock?.();
    result?.catch?.(() => flash("Click the world to enable mouse look.", 3));
  } catch {
    flash("Click the world to enable mouse look.", 3);
  }
}
document.addEventListener("pointerlockerror", () => {
  clearControls();
  flash("Mouse look needs another click on the world.", 3);
});
$("playButton").addEventListener("click", () => {
  playing = true;
  document.body.classList.add("started");
  $("start").classList.add("hidden");
  canvas.focus();
  if (speechOn && "speechSynthesis" in window) {
    try {
      speechSynthesis.resume();
      const u = new SpeechSynthesisUtterance("Watch out!");
      u.volume = 0.3;
      u.rate = 1.12;
      speechSynthesis.speak(u);
      voiceCooldown.next = performance.now() + 2100;
    } catch (e) {}
  }
  requestMouse();
  flash("Find eight hidden chilis for a speed rush. Keep biting to preserve your Power.", 5);
});
document.addEventListener("pointerlockchange", () => {
  pointer = document.pointerLockElement === canvas;
  if (!pointer) {
    focusMouse = false;
    focusToggle = false;
    player.focus = false;
  }
});
// Pounce works in normal traversal as well as in stalking view; one event per button-down.
canvas.addEventListener("mousedown", (e) => {
  if (!playing || gamePaused) return;
  if (!pointer) {
    requestMouse();
    return;
  }
  if (e.button === 0) {
    e.preventDefault();
    attemptPounce();
  }
});
document.addEventListener("mousemove", (e) => {
  if (!pointer || !playing || gamePaused) return;
  const dx = THREE.MathUtils.clamp(e.movementX, -90, 90),
    dy = THREE.MathUtils.clamp(e.movementY, -90, 90);
  const sensitivity = player.focus ? 0.0025 : 0.00315;
  const boost = Math.min(1.25, Math.hypot(dx, dy) / 35);
  if (player.rail) routeFreeLook = 1.7;
  yaw -= dx * sensitivity * (1 + 0.18 * boost);
  if (player.rail?.kind === "trunk" && !player.focus) {
    // Orbit the climbing squirrel around the bark, keeping body and camera on the same visible side.
    player.trunkNormal?.applyAxisAngle(v(0, 1, 0), -dx * 0.004);
  }
  pitch = THREE.MathUtils.clamp(pitch - dy * sensitivity, -0.6, 1.07);
});
document.addEventListener("mousedown", (e) => {
  if (e.button === 2 && playing && !gamePaused && e.target === canvas) {
    e.preventDefault();
    focusMouse = true;
  }
});
document.addEventListener("mouseup", (e) => {
  if (e.button === 2) focusMouse = false;
});
canvas.addEventListener("contextmenu", (e) => e.preventDefault());
window.addEventListener("keydown", (e) => {
  if (
    !document.getElementById("pauseShield").hidden ||
    !document.getElementById("graphicsPanel").hidden ||
    (["INPUT", "SELECT", "TEXTAREA", "BUTTON"].includes(document.activeElement?.tagName) && e.code !== "KeyG")
  )
    return;
  if (["Space", "Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(e.code))
    e.preventDefault();
  keys.add(e.code);
  if (!e.repeat && e.code === "KeyM") {
    toggleAllHud();
    return;
  }
  if (!e.repeat && e.code === "Tab") {
    cycleHudView();
    return;
  }
  if (!e.repeat && e.code === "KeyK") {
    toggleHudEditor();
    return;
  }
  if (!playing) return;
  if (e.code === "KeyP" && !e.repeat) {
    gamePaused = !gamePaused;
    flash(gamePaused ? "PAUSED · P to resume" : "RESUMED", 2);
    return;
  }
  if (e.code === "KeyH" && !e.repeat) toggleHelp();
  if (e.code === "KeyL" && !e.repeat) {
    document.getElementById("spicyDiagnostic")?.classList.toggle("open");
    flash("Diagnostic panel toggled (L).", 1.4);
  }
  if (e.code === "KeyC" && !e.repeat) {
    yaw = player.yaw + PI;
    cameraHardCut = true;
    flash("Camera centered on squirrel.", 1.5);
  }
  if (gamePaused) return;
  if (!e.repeat && (e.code === "KeyA" || e.code === "KeyD") && player.rail) {
    const choiceSide = e.code === "KeyD" ? 1 : -1;
    if (player.rail.kind === "trunk") chooseCanopyFork(choiceSide);
    else if (player.rail.kind === "branch") {
      if (!sideStepToSibling(choiceSide)) chooseRouteJunction(choiceSide);
    } else chooseRouteJunction(choiceSide);
  }
  if (e.code === "KeyE" && !e.repeat) {
    if (!handleInteraction()) {
      if (!takeSelectedFork()) attachRoute();
    }
  }
  if (["Digit1", "Digit2", "Digit3"].includes(e.code) && !e.repeat) cycleFashion(Number(e.code.at(-1)) - 1);
  if (e.code === "KeyQ" && !e.repeat && player.rail) {
    launchFromVisibleRoute();
    clearPendingFork();
    player.rail = null;
    player.vel.y = 3.3;
    player.committedAirborne = true;
    player.cameraCommit = 0.32;
    flash("Dropped from the route. Space to leap.", 1.8);
  }
  if (e.code === "Space" && !e.repeat) leap();
  if (e.code === "KeyF" && !e.repeat) focusToggle = !focusToggle;
});
window.addEventListener("keyup", (e) => keys.delete(e.code));
window.addEventListener("blur", () => {
  keys.clear();
  focusMouse = false;
  focusToggle = false;
});
$("crowdBtn").onclick = () => {
  demoCrowd = !demoCrowd;
  $("crowdBtn").textContent = "NPC FLOW: " + (demoCrowd ? "DEMO" : "QUIET");
  flash(
    demoCrowd
      ? "Demo rotation: up to eleven characters at once."
      : "Quiet street: about five people visible.",
    3,
  );
};
let shadowHigh = true;
$("qualityBtn").onclick = () => {
  shadowHigh = !shadowHigh;
  renderer.shadowMap.enabled = shadowHigh;
  sun.castShadow = shadowHigh;
  $("qualityBtn").textContent = "SHADOWS: " + (shadowHigh ? "HIGH" : "OFF");
  flash(shadowHigh ? "Sun shadows enabled." : "Shadows disabled for performance.", 2.4);
};
$("voiceBtn").onclick = () => {
  speechOn = !speechOn;
  $("voiceBtn").textContent = "VOICES: " + (speechOn ? "ON" : "OFF");
  if (!speechOn && "speechSynthesis" in window) speechSynthesis.cancel();
  else if ("speechSynthesis" in window) speechSynthesis.resume();
  flash(
    speechOn ? "Voiced reactions ON — browsers may require sound permission." : "Voice playback muted.",
    3,
  );
};
function nearestRoute(maxDist = 4.5, excluding = null, point = player.pos) {
  let best = null,
    bd = maxDist;
  const cell = 8,
    tx = Math.floor(point.x / cell),
    ty = Math.floor(point.y / cell),
    tz = Math.floor(point.z / cell);
  const r = Math.ceil(maxDist / cell);
  for (let i = -r; i <= r; i++)
    for (let j = -r; j <= r; j++)
      for (let k = -r; k <= r; k++) {
        for (const entry of routeSpatial.get(`${tx + i},${ty + j},${tz + k}`) || []) {
          if (entry.route === excluding) continue;
          const d = entry.pos.distanceTo(point);
          if (d < bd) {
            bd = d;
            best = { route: entry.route, t: entry.t, d };
          }
        }
      }
  return best;
}
// TRUNK ACQUISITION — stable contact-point selection instead of an invisible
// high-altitude nearest-route search. Returns a route at its physical foot.
function groundTrunkCandidate(point = player.pos, reach = 2.85) {
  let best = null,
    score = Infinity;
  for (const route of routes) {
    if (route.kind !== "trunk" || /downspout|gutter|ladder/i.test(route.name)) continue;
    const isPole = /telephone pole/i.test(route.name);
    if (
      isPole &&
      reach > 1.85 &&
      Math.hypot(point.x - route.sampled[0].x, point.z - route.sampled[0].z) > 1.85
    )
      continue;
    const foot = route.sampled[0];
    if (!foot) continue;
    const horizontal = Math.hypot(point.x - foot.x, point.z - foot.z);
    const rise = Math.abs(point.y - foot.y);
    if (horizontal > reach || rise > 3.1) continue;
    const rank = horizontal + rise * 0.24 + (isPole ? 0.2 : 0);
    if (rank < score) {
      score = rank;
      best = { route, t: 0, d: horizontal };
    }
  }
  return best;
}
function forwardIntoTrunk(candidate, fw, side) {
  if (!candidate || fw <= 0) return false;
  const foot = candidate.route.sampled[0];
  const dx = foot.x - player.pos.x,
    dz = foot.z - player.pos.z;
  const distance = Math.hypot(dx, dz);
  if (distance < 0.12) return true;
  const mvx = -Math.sin(yaw) * fw + Math.cos(yaw) * side;
  const mvz = -Math.cos(yaw) * fw - Math.sin(yaw) * side;
  const length = Math.hypot(mvx, mvz);
  return length > 0.1 && (mvx * dx + mvz * dz) / (length * distance) > 0.43;
}
// A route is both geometry and a path through a junction. The player's position
// travels across the gap over a few frames; a branch swap cannot teleport them.
// These helpers are intentionally pure so they can be unit-tested independently.
const RouteJunction = {
  inward(t, desired) {
    return t < 0.035 ? 1 : t > 0.965 ? -1 : desired;
  },
  canTransfer(gap, explicit = false) {
    return Number.isFinite(gap) && gap <= (explicit ? 1.7 : 0.48);
  },
  ease(p) {
    p = Math.max(0, Math.min(1, p));
    return p * p * (3 - 2 * p);
  },
};
let routeBridge = null;
// Route input is camera-relative; preserve direction during a held key so a
// bending cable can't reverse W half-way through a curve.
let routeWasMoving = false,
  routeFreeLook = 0;
function cameraForwardXZ() {
  return v(-Math.sin(yaw), 0, -Math.cos(yaw));
}
function cameraRightXZ() {
  return v(Math.cos(yaw), 0, -Math.sin(yaw));
}
function routeTangentXZ(route, t) {
  const q = route.curve.getTangentAt(THREE.MathUtils.clamp(t, 0.006, 0.994));
  q.y = 0;
  return q.lengthSq() > 0.0001 ? q.normalize() : null;
}
function directionFromView(route, t, fallback = 1) {
  if (route.kind === "trunk") return 1;
  const tan = routeTangentXZ(route, t);
  if (!tan) return fallback;
  const d = tan.dot(cameraForwardXZ());
  if (Math.abs(d) > 0.18) return d >= 0 ? 1 : -1;
  // Near perpendicular: continue the currently facing heading, never choose randomly.
  const facing = tan.dot(v(Math.sin(player.yaw), 0, Math.cos(player.yaw)));
  return Math.abs(facing) > 0.28 ? (facing >= 0 ? 1 : -1) : fallback;
}
function resyncRouteHeading(route, t, dir) {
  const tan = routeTangentXZ(route, t);
  if (!tan) return;
  const h = tan.multiplyScalar(dir);
  player.yaw = Math.atan2(h.x, h.z);
}
function enterRoute(found) {
  if (!found?.route || !Number.isFinite(found.t)) return false;
  const approach = player.pos.clone(),
    wasOnRoute = Boolean(player.rail);
  const dest = found.route.curve.getPointAt(found.t),
    gap = approach.distanceTo(dest);
  // Only deliberate, connected transfers are permitted. Grabbing from the
  // ground can be farther from the route centerline because of trunk radius.
  if (wasOnRoute && gap > 3.15) {
    flash("Move to the highlighted junction before switching.", 1.7);
    return false;
  }
  routeBridge =
    wasOnRoute && gap > 0.11
      ? {
          from: approach.clone(),
          to: dest.clone(),
          elapsed: 0,
          duration: THREE.MathUtils.clamp(0.13 + gap * 0.065, 0.15, 0.31),
        }
      : null;
  player.rail = found.route;
  player.railT = found.t;
  player.railDir = RouteJunction.inward(found.t, found.dir ?? directionFromView(found.route, found.t, 1));
  player.pos.copy(routeBridge ? approach : dest);
  routeWasMoving = found.dir !== undefined && (keys.has("KeyW") || keys.has("KeyS"));
  // Preserve camera heading during transfers instead of cutting to a different
  // wire's authored forward direction. The chase view gradually settles behind.
  if (wasOnRoute) routeFreeLook = Math.max(routeFreeLook, 0.65);
  resyncRouteHeading(found.route, found.t, player.railDir);
  if (found.route.kind === "trunk") {
    const radial = approach.sub(dest);
    radial.y = 0;
    player.trunkNormal =
      radial.lengthSq() > 0.015 ? radial.normalize() : v(-Math.sin(yaw), 0, -Math.cos(yaw));
  }
  if (found.route.kind !== "trunk") clearPendingFork();
  selectedJunction = null;
  player.vel.set(0, 0, 0);
  player.grounded = false;
  player.committedAirborne = false;
  flash(`On ${found.route.name} · W forward · S back · A/D choose path · E transfer`, 2.1);
  return true;
}
function attachRoute() {
  if (player.rail) {
    if (takeSelectedJunction()) return;
    if (takeSelectedFork()) return;
    if (pendingFork && player.rail.kind === "trunk") {
      flash("Climb closer to the highlighted branch; then press E.", 2);
      return;
    }
    const next = nearestRoute(1.95, player.rail);
    if (next && RouteJunction.canTransfer(next.d, true)) {
      const previous = player.rail;
      if (enterRoute(next)) flash(`Transferred: ${previous.name} → ${next.route.name}`, 2.5);
    } else flash("Continue toward a branch junction, or press Q to drop.", 1.5);
  } else {
    const found = (player.grounded ? groundTrunkCandidate(player.pos, 3.1) : null) || nearestRoute(3.4);
    if (found) enterRoute(found);
    else flash("Get closer to a trunk, fence, rooftop, or overhead line.", 2.3);
  }
}
// The camera shows the squirrel OUTSIDE the bark or sitting atop a branch.
// A leap begins at that visible position rather than the hidden route centerline.
function launchFromVisibleRoute() {
  if (player.rail) {
    player.pos.copy(squirrel.position);
    clearPendingFork();
  }
  routeBridge = null;
}
// Every committed leap faces the way the ANIMAL is facing, not the camera's
// independent orbit. Reposition the camera behind that heading immediately.
function attackHeading() {
  if (player.rail?.kind === "trunk") {
    const radial = player.trunkNormal || v(0, 0, 1);
    return Math.atan2(radial.x, radial.z);
  }
  return player.yaw;
}
function commitToAir(heading = player.yaw) {
  player.yaw = heading;
  yaw = heading + PI; // View forward matches the squirrel's physical forward direction.
  player.cameraCommit = 0.52;
  player.committedAirborne = true;
  player.focus = false;
  cameraHardCut = true;
}
function jumpVelocity() {
  // Ground / fence traversal: measured apex 2.73 world units, independent of view pitch.
  // The 2m garden fences and low sedans are passable; a 3.5m van is not.
  const hd = attackHeading(),
    forward = player.boostRemaining > 0 ? 18.5 : 16.5;
  return v(Math.sin(hd) * forward, 12.8, Math.cos(hd) * forward);
}
function leap() {
  if (gamePaused || !player.alive) return;
  if (player.inDuct) {
    if (!dropFromHatch(false)) flash("Crawl to the OPEN high hatch to drop.", 1.7);
    return;
  }
  if (player.rail || player.grounded) {
    // Space uses a separate, higher traversal jump; left-click retains the low attack pounce.
    // A pounce differs by opening the NPC attack window, not by ignoring aim.
    const heading = attackHeading(),
      launchVel = jumpVelocity();
    launchFromVisibleRoute();
    player.vel.copy(launchVel);
    player.rail = null;
    player.grounded = false;
    commitToAir(heading);
    flash("LEAP · camera pulled back to track your landing", 1.2);
  }
}
function switchRoute(old, atStart) {
  // No arbitrary switch between nearby lines: an automatic transition is only
  // allowed at a physical junction, with heading continuity and a unique winner.
  const cur = old.curve.getPointAt(atStart ? 0 : 1);
  const outward = old.curve.getTangentAt(atStart ? 0 : 1).multiplyScalar(atStart ? -1 : 1);
  const seen = new Map(),
    xi = Math.floor(cur.x / 8),
    yi = Math.floor(cur.y / 8),
    zi = Math.floor(cur.z / 8);
  for (let i = -1; i <= 1; i++)
    for (let j = -1; j <= 1; j++)
      for (let k = -1; k <= 1; k++)
        for (const e of routeSpatial.get(`${xi + i},${yi + j},${zi + k}`) || []) {
          if (e.route === old || (e.t > 0.07 && e.t < 0.93)) continue;
          const gap = e.pos.distanceTo(cur);
          if (!RouteJunction.canTransfer(gap)) continue;
          const oldCandidate = seen.get(e.route);
          if (!oldCandidate || gap < oldCandidate.gap) seen.set(e.route, { route: e.route, t: e.t, gap });
        }
  const forward = cameraForwardXZ();
  const candidates = [...seen.values()]
    .map((c) => {
      const tangent = c.route.curve.getTangentAt(THREE.MathUtils.clamp(c.t, 0.002, 0.998));
      const toward = tangent.dot(outward) >= 0 ? 1 : -1;
      const dir = RouteJunction.inward(c.t, toward);
      const travel = tangent.multiplyScalar(dir),
        xz = v(travel.x, 0, travel.z).normalize();
      const view = forward.dot(xz),
        continuity = travel.dot(outward);
      // With multiple choices, use the camera's intended direction rather than a
      // hard-coded bridge/wire preference that made W reverse on certain spans.
      return { ...c, dir, score: continuity * 2 + view * 2.9 - c.gap * 1.6 };
    })
    .filter((c) => c.route.kind !== "trunk" || old.kind === "bridge");
  if (!candidates.length) return false;
  candidates.sort((a, b) => b.score - a.score);
  const chosen = selectedJunction ? candidates.find((c) => c.route === selectedJunction.route) : null;
  const best = chosen || candidates[0];
  if (!chosen && candidates.length > 1 && best.score - candidates[1].score < 0.65) {
    if (messageTime <= 0) flash("Junction ahead · A/D choose a line · E transfer", 2);
    return false;
  }
  // Do not auto-turn sharply away from the current view unless chosen by A/D.
  if (!chosen && best.score < -0.75) return false;
  return enterRoute({ route: best.route, t: best.t, dir: best.dir });
}
// Dedicated wire / rooftop junction choices. A/D previews paths on the
// visible left/right of the camera; E enters exactly the highlighted route.
const junctionPreview = new THREE.Group();
scene.add(junctionPreview);
const junctionDots = [];
const junctionMaterial = new THREE.MeshBasicMaterial({
  color: 0xf7e4a3,
  transparent: true,
  opacity: 0.92,
  depthTest: false,
});
for (let j = 0; j < 4; j++) {
  const dot = new THREE.Mesh(new THREE.SphereGeometry(0.13 - j * 0.012, 8, 6), junctionMaterial);
  junctionPreview.add(dot);
  junctionDots.push(dot);
}
let selectedJunction = null;
function junctionCandidates() {
  if (!player.rail || player.rail.kind === "trunk") return [];
  const p = player.rail.curve.getPointAt(player.railT),
    radius = 2.15,
    seen = new Map();
  const xi = Math.floor(p.x / 8),
    yi = Math.floor(p.y / 8),
    zi = Math.floor(p.z / 8);
  for (let i = -1; i <= 1; i++)
    for (let j = -1; j <= 1; j++)
      for (let k = -1; k <= 1; k++)
        for (const e of routeSpatial.get(`${xi + i},${yi + j},${zi + k}`) || []) {
          if (e.route === player.rail || e.route.kind === "trunk") continue;
          const distance = e.pos.distanceTo(p);
          if (distance > radius) continue;
          if (!seen.has(e.route) || distance < seen.get(e.route).d)
            seen.set(e.route, { route: e.route, t: e.t, d: distance });
        }
  return [...seen.values()].filter((c) => RouteJunction.canTransfer(c.d, true)).sort((a, b) => a.d - b.d);
}
function junctionOutward(c) {
  const p = player.rail.curve.getPointAt(player.railT),
    start = c.route.curve.getPointAt(Math.max(0, c.t - 0.09)),
    end = c.route.curve.getPointAt(Math.min(1, c.t + 0.09));
  const tan = end.sub(start).setY(0).normalize(),
    delta = c.route.curve.getPointAt(c.t).sub(p).setY(0);
  const intended = RouteJunction.inward(c.t, directionFromView(c.route, c.t, player.railDir));
  return delta.lengthSq() > 0.24 ? delta.normalize() : tan.multiplyScalar(intended);
}
function chooseRouteJunction(side) {
  const candidates = junctionCandidates();
  if (!candidates.length) {
    selectedJunction = null;
    return false;
  }
  const right = cameraRightXZ();
  const choices = candidates
    .map((c) => ({ ...c, side: side * right.dot(junctionOutward(c)) }))
    .filter((c) => c.side > -0.08)
    .sort((a, b) => b.side - a.side || a.d - b.d);
  if (!choices.length) return false;
  const oldIndex = choices.findIndex((c) => c.route === selectedJunction?.route);
  selectedJunction = choices[oldIndex < 0 ? 0 : (oldIndex + 1) % choices.length];
  flash(`JUNCTION: ${selectedJunction.route.name} · E to transfer`, 1.6);
  return true;
}
function takeSelectedJunction() {
  if (!selectedJunction || !player.rail) return false;
  const c = junctionCandidates().find((x) => x.route === selectedJunction.route);
  if (!c) {
    selectedJunction = null;
    return false;
  }
  const dir = directionFromView(c.route, c.t, player.railDir);
  const ok = enterRoute({ route: c.route, t: c.t, dir });
  if (ok) selectedJunction = null;
  return ok;
}
function drawJunctionPreview() {
  const sel = selectedJunction;
  const valid = sel && player.rail && junctionCandidates().some((c) => c.route === sel.route);
  junctionPreview.visible = !!valid;
  if (!valid) {
    selectedJunction = null;
    return;
  }
  for (let j = 0; j < junctionDots.length; j++) {
    const toward = RouteJunction.inward(sel.t, directionFromView(sel.route, sel.t, player.railDir));
    const at = THREE.MathUtils.clamp(sel.t + toward * (j + 0.4) * 0.018, 0, 1);
    junctionDots[j].position
      .copy(sel.route.curve.getPointAt(at))
      .add(v(0, 0.42 + Math.sin(time * 4 + j) * 0.06, 0));
  }
}
// Vehicle bodies share world-space footprints with jumping, not magical pass-throughs.
function vehicleHitboxAt(x, z) {
  const all = cars
    .map((c) => ({ group: c.group, width: 2.35, length: 4.45, height: 2.04 }))
    .concat(tallVehicles);
  let inside = null;
  for (const o of all) {
    if (!o.group.visible) continue;
    const dx = x - o.group.position.x,
      dz = z - o.group.position.z,
      angle = o.group.rotation.y;
    const lx = Math.cos(angle) * dx - Math.sin(angle) * dz,
      lz = Math.sin(angle) * dx + Math.cos(angle) * dz;
    if (Math.abs(lx) < o.width * 0.5 && Math.abs(lz) < o.length * 0.5) {
      const top = o.group.position.y + o.height;
      if (!inside || top > inside.top) inside = { top, object: o };
    }
  }
  return inside;
}
function preventVehicleOverlap(previous) {
  const hit = vehicleHitboxAt(player.pos.x, player.pos.z);
  if (hit && player.pos.y < hit.top - 0.1) {
    player.pos.x = previous.x;
    player.pos.z = previous.z;
    // A leap into the side of a tall vehicle loses forward momentum.
    player.vel.x *= 0.18;
    player.vel.z *= 0.18;
  }
}
// v4.0: Roof landing uses continuous downward-crossing detection, not only
// the current frame's height.  This prevents high-speed leaps from tunneling
// beneath the gables and into house shells.
function roofSurfaceAt(x, z) {
  let best = riverRoofAt(x, z);
  const mall = mallRoofAt(x, z);
  if (mall !== null) best = Math.max(best ?? -Infinity, mall);
  const riverSurface = riverSurfaceAt(x, z);
  if (riverSurface !== null) best = Math.max(best ?? -Infinity, riverSurface + 0.18);
  for (const h of houses) {
    if (h === activeHouseInterior) continue;
    const dx = x - h.x,
      dz = z - h.z;
    if (Math.abs(dx) >= h.w / 2 + 0.24 || Math.abs(dz) >= h.d / 2 + 0.2) continue;
    const top = h.roofY(dx, dz) + 0.29;
    if (Number.isFinite(top) && (best === null || top > best)) best = top;
  }
  for (const h of oldDistrictHomes) {
    if (h === activeOldHome) continue;
    if (Math.abs(x - h.x) >= (h.depth + 1.7) / 2 || Math.abs(z - h.z) >= (h.width + 1.7) / 2) continue;
    const top = h.by + h.height + 0.56;
    if (best === null || top > best) best = top;
  }
  for (const b of commercialBounds) {
    if (Math.abs(x - b.x) < b.w / 2 + 0.15 && Math.abs(z - b.z) < b.d / 2 + 0.15) {
      if (best === null || b.roof + 0.17 > best) best = b.roof + 0.17;
    }
  }
  if (
    !player.inHospital &&
    !player.inDuct &&
    Math.abs(x - HOSP_X) < HOSP_W / 2 + 1.2 &&
    Math.abs(z - HOSP_Z) < HOSP_D / 2 + 1.2
  ) {
    const top = HOSP_BASE + 13.34;
    if (best === null || top > best) best = top;
  }
  return best;
}
function resolveRoofLanding(old) {
  if (
    player.inSewer ||
    player.inHospital ||
    player.inDuct ||
    activeHouseInterior ||
    houseTransit ||
    activeOldHome ||
    oldHomeTransit ||
    hospitalTransition ||
    player.rail
  )
    return false;
  if (player.vel.y > 0 || player.pos.y > old.y + 0.01) return false;
  const top = roofSurfaceAt(player.pos.x, player.pos.z);
  if (top === null) return false;
  const prevTop = roofSurfaceAt(old.x, old.z);
  // Permit a landing while crossing the edge horizontally, provided the prior
  // airborne position was above the new roof surface.
  if (
    player.pos.y <= top + 0.08 &&
    old.y >= top - 0.5 &&
    (prevTop === null || old.y >= Math.min(top, prevTop) - 0.5)
  ) {
    player.pos.y = top;
    player.vel.y = 0;
    player.grounded = true;
    player.committedAirborne = false;
    return true;
  }
  return false;
}
function recoverTrappedInHouse() {
  if (
    activeHouseInterior ||
    activeOldHome ||
    houseTransit ||
    oldHomeTransit ||
    player.rail ||
    player.inHospital ||
    player.inSewer ||
    player.inDuct
  )
    return;
  const h = houses.find(
    (h) => Math.abs(player.pos.x - h.x) < h.w / 2 - 0.5 && Math.abs(player.pos.z - h.z) < h.d / 2 - 0.5,
  );
  const old = oldDistrictHomes.find(
    (h) =>
      Math.abs(player.pos.x - h.x) < h.depth / 2 - 0.5 && Math.abs(player.pos.z - h.z) < h.width / 2 - 0.5,
  );
  const top = h
    ? h.roofY(player.pos.x - h.x, player.pos.z - h.z) + 0.29
    : old
      ? old.by + old.height + 0.56
      : null;
  if (top === null || player.pos.y >= top - 0.7) return;
  // If already trapped at floor height, move outside to the nearest wall rather
  // than dropping the player in a room that is only entered with E.
  const ground = terrainHeight(player.pos.x, player.pos.z) + 0.2;
  if (player.pos.y < ground + 1.05) {
    const hw = h ? h.w / 2 : old.depth / 2,
      hd = h ? h.d / 2 : old.width / 2;
    const cx = h ? h.x : old.x,
      cz = h ? h.z : old.z;
    const west = Math.abs(player.pos.x - (cx - hw)),
      east = Math.abs(player.pos.x - (cx + hw));
    const north = Math.abs(player.pos.z - (cz - hd)),
      south = Math.abs(player.pos.z - (cz + hd));
    const nearest = Math.min(west, east, north, south);
    if (nearest === west) player.pos.x = cx - hw - 1.1;
    else if (nearest === east) player.pos.x = cx + hw + 1.1;
    else if (nearest === north) player.pos.z = cz - hd - 1.1;
    else player.pos.z = cz + hd + 1.1;
    player.pos.y = terrainHeight(player.pos.x, player.pos.z) + 0.2;
  } else player.pos.y = top;
  player.vel.set(0, 0, 0);
  player.grounded = true;
  player.committedAirborne = false;
}
function getGroundAt(x, z) {
  let y = Math.max(terrainHeight(x, z), outdoorSurfaceAt(x, z)) + 0.18;
  const mall = mallSurfaceAt(x, z);
  if (mall !== null) y = Math.max(y, mall + 0.18);
  const riverSurface = riverSurfaceAt(x, z);
  if (riverSurface !== null && player.pos.y >= riverSurface - 0.5) y = Math.max(y, riverSurface + 0.18);
  const car = vehicleHitboxAt(x, z);
  if (car && player.pos.y >= car.top - 0.32) y = Math.max(y, car.top + 0.16); // Roof occupancy within building footprint and approachable while falling from above.
  const roof = roofSurfaceAt(x, z);
  if (roof !== null && player.pos.y >= roof - 0.47) y = Math.max(y, roof);
  // raised porch, guest roof, pool deck and trampoline.
  if (Math.abs(x + 58) < 6.5 && Math.abs(z - 83) < 6.0 && player.pos.y > 5.2) y = Math.max(y, 6);
  if (Math.hypot(x + 33, z - 80) < 5 && player.pos.y > 1.1) y = Math.max(y, 1.65);
  if (
    Math.abs(x - treehouseSite.x) < 4.2 &&
    Math.abs(z - treehouseSite.z) < 4.0 &&
    player.pos.y > treehouseSite.base + treehouseSite.height - 1.1
  )
    y = Math.max(y, treehouseSite.base + treehouseSite.height + 0.26);
  return y;
}
let activeHouseInterior = null,
  houseTransit = null;
function collisionHouses(lastPos) {
  for (const b of commercialBounds) {
    if (
      Math.abs(player.pos.x - b.x) < b.w / 2 + 0.25 &&
      Math.abs(player.pos.z - b.z) < b.d / 2 + 0.25 &&
      player.pos.y < b.roof - 0.35
    ) {
      player.pos.x = lastPos.x;
      player.pos.z = lastPos.z;
      return;
    }
  }
  if (player.pos.y < 3.1) {
    for (const tr of trees) {
      if (Math.hypot(player.pos.x - tr.x, player.pos.z - tr.z) < 1.48) {
        player.pos.x = lastPos.x;
        player.pos.z = lastPos.z;
        return;
      }
    }
    for (const f of fenceCollisions) {
      if (player.pos.y > f.height + 0.25) continue;
      const dx = f.x2 - f.x1,
        dz = f.z2 - f.z1,
        t = THREE.MathUtils.clamp(
          ((player.pos.x - f.x1) * dx + (player.pos.z - f.z1) * dz) / (dx * dx + dz * dz),
          0,
          1,
        );
      if (Math.hypot(player.pos.x - f.x1 - t * dx, player.pos.z - f.z1 - t * dz) < 0.4) {
        player.pos.x = lastPos.x;
        player.pos.z = lastPos.z;
        return;
      }
    }
  }
  if (player.pos.y > 18) return;
  for (const h of houses) {
    if (h === activeHouseInterior) {
      if (houseTransit) continue;
      const limX = h.w / 2 - 0.67,
        limZ = h.d / 2 - 0.65;
      player.pos.x = THREE.MathUtils.clamp(player.pos.x, h.x - limX, h.x + limX);
      if (player.pos.y > h.cfg.h - 0.9) {
        player.pos.y = h.cfg.h - 0.9;
        player.vel.y = 0;
      }
      player.pos.z = THREE.MathUtils.clamp(player.pos.z, h.z - limZ, h.z + limZ);
      for (const ob of h.interiorObstacles) {
        const inside = (x, z) => Math.abs(x - ob.x) < ob.w / 2 + 0.35 && Math.abs(z - ob.z) < ob.d / 2 + 0.35;
        if (!inside(player.pos.x, player.pos.z)) continue;
        if (!inside(lastPos.x, player.pos.z)) player.pos.z = lastPos.z;
        else if (!inside(player.pos.x, lastPos.z)) player.pos.x = lastPos.x;
        else {
          player.pos.x = lastPos.x;
          player.pos.z = lastPos.z;
        }
      }
      continue;
    }
    if (
      Math.abs(player.pos.x - h.x) < h.w / 2 + 0.53 &&
      Math.abs(player.pos.z - h.z) < h.d / 2 + 0.53 &&
      player.pos.y < h.cfg.h - 0.35
    ) {
      player.pos.x = lastPos.x;
      player.pos.z = lastPos.z;
      return;
    }
  }
}
// v2.3 — grounded swept 2D motion with per-axis sliding.
// Ground motion has physical momentum, but colliders no longer cancel a
// diagonal stride just because its forward component grazes a fence or car.
function outdoorBlocked(x, z, height) {
  if (mallBlocked(x, z, height)) return true;
  if (riverBlocked(x, z, height)) return true;
  const r = 0.32;
  // Westside homes are separate from the original four houses. Their walls
  // must still block the squirrel; only the four open-bay homes can be entered.
  for (const h of oldDistrictHomes) {
    if (height >= h.by + h.height + 0.15) continue;
    const inside = Math.abs(x - h.x) < h.depth / 2 + r && Math.abs(z - h.z) < h.width / 2 + r;
    if (!inside) continue;
    if (h === activeOldHome) return false;
    if (oldHomeTransit?.home === h) return false;
    return true;
  }
  if (activeHouseInterior) {
    const h = activeHouseInterior;
    if (Math.abs(x - h.x) > h.w / 2 - 0.68 - r * 0.08 || Math.abs(z - h.z) > h.d / 2 - 0.68 - r * 0.08)
      return true;
    if (
      (h.interiorObstacles || []).some(
        (o) => Math.abs(x - o.x) < o.w / 2 + r && Math.abs(z - o.z) < o.d / 2 + r,
      )
    )
      return true;
  } else {
    for (const h of houses) {
      if (height >= h.cfg.h - 0.35) continue;
      if (Math.abs(x - h.x) < h.w / 2 + 0.53 && Math.abs(z - h.z) < h.d / 2 + 0.53) return true;
    }
  }
  for (const b of commercialBounds) {
    if (height < b.roof - 0.35 && Math.abs(x - b.x) < b.w / 2 + r && Math.abs(z - b.z) < b.d / 2 + r)
      return true;
  }
  if (height < 3.1) {
    for (const t of trees) {
      const dx = x - t.x,
        dz = z - t.z;
      if (Math.abs(dx) < 2 && Math.abs(dz) < 2 && dx * dx + dz * dz < 1.48 * 1.48) return true;
    }
    for (const f of fenceCollisions) {
      if (height > f.height + 0.25) continue;
      const minx = Math.min(f.x1, f.x2) - r - 0.08,
        maxx = Math.max(f.x1, f.x2) + r + 0.08;
      const minz = Math.min(f.z1, f.z2) - r - 0.08,
        maxz = Math.max(f.z1, f.z2) + r + 0.08;
      if (x < minx || x > maxx || z < minz || z > maxz) continue;
      const dx = f.x2 - f.x1,
        dz = f.z2 - f.z1;
      const t = THREE.MathUtils.clamp(((x - f.x1) * dx + (z - f.z1) * dz) / (dx * dx + dz * dz || 1), 0, 1);
      if (Math.hypot(x - f.x1 - t * dx, z - f.z1 - t * dz) < r + 0.05) return true;
    }
  }
  // Broad phase before vehicle rectangle tests. Each car has a rotation.
  for (const c of cars) {
    if (!c.group.visible) continue;
    const g = c.group,
      dx = x - g.position.x,
      dz = z - g.position.z;
    if (Math.abs(dx) > 4.5 || Math.abs(dz) > 4.5) continue;
    const a = g.rotation.y,
      lx = Math.cos(a) * dx - Math.sin(a) * dz,
      lz = Math.sin(a) * dx + Math.cos(a) * dz;
    if (
      Math.abs(lx) < 1.175 + r &&
      Math.abs(lz) < 2.225 + r &&
      height < terrainHeight(g.position.x, g.position.z) + 1.94
    )
      return true;
  }
  for (const o of tallVehicles) {
    const g = o.group,
      dx = x - g.position.x,
      dz = z - g.position.z;
    if (Math.abs(dx) > o.length + 2 || Math.abs(dz) > o.length + 2) continue;
    const a = g.rotation.y,
      lx = Math.cos(a) * dx - Math.sin(a) * dz,
      lz = Math.sin(a) * dx + Math.cos(a) * dz;
    if (
      Math.abs(lx) < o.width / 2 + r &&
      Math.abs(lz) < o.length / 2 + r &&
      height < g.position.y + o.height - 0.1
    )
      return true;
  }
  return false;
}
function resolveOutdoorMovement(previous) {
  const goalX = player.pos.x,
    goalZ = player.pos.z,
    dx = goalX - previous.x,
    dz = goalZ - previous.z;
  const length = Math.hypot(dx, dz),
    steps = Math.max(1, Math.min(18, Math.ceil(length / 0.24)));
  let x = previous.x,
    z = previous.z,
    blockedX = false,
    blockedZ = false;
  const stepX = dx / steps,
    stepZ = dz / steps;
  for (let i = 0; i < steps; i++) {
    const px = x,
      pz = z;
    // Separate axes keep a glancing run moving along the wall or fence.
    if (Math.abs(stepX) > 1e-7) {
      if (!outdoorBlocked(x + stepX, z, player.pos.y)) x += stepX;
      else blockedX = true;
    }
    if (Math.abs(stepZ) > 1e-7) {
      if (!outdoorBlocked(x, z + stepZ, player.pos.y)) z += stepZ;
      else blockedZ = true;
    }
    // If both axes fail, try diagonal once; important around rotated cars.
    if (x === px && z === pz && !outdoorBlocked(px + stepX, pz + stepZ, player.pos.y)) {
      x = px + stepX;
      z = pz + stepZ;
      blockedX = false;
      blockedZ = false;
    }
  }
  player.pos.x = x;
  player.pos.z = z;
  if (blockedX) player.vel.x *= 0.28;
  if (blockedZ) player.vel.z *= 0.28;
}

let audioContext = null;
function fx(f = 440, d = 0.12, wave = "sine", volume = 0.07) {
  if (!playing) return;
  try {
    audioContext ||= new (window.AudioContext || window.webkitAudioContext)();
    const o = audioContext.createOscillator(),
      g = audioContext.createGain();
    o.type = wave;
    o.frequency.setValueAtTime(f, audioContext.currentTime);
    o.frequency.exponentialRampToValueAtTime(Math.max(40, f * 0.64), audioContext.currentTime + d);
    g.gain.setValueAtTime(volume, audioContext.currentTime);
    g.gain.exponentialRampToValueAtTime(0.001, audioContext.currentTime + d);
    o.connect(g);
    g.connect(audioContext.destination);
    o.start();
    o.stop(audioContext.currentTime + d);
  } catch (e) {}
}
// Pounce uses an actual launch vector. The same velocity is used by the subtle
// first-person arc, so the guidance predicts the committed trajectory.
// Low, forward-biased squirrel bound: capped vertical takeoff, much flatter
// than the exaggerated v0.4 vault. Aim still changes the leap direction.
const SQUIRREL_GRAVITY = 30;
function pounceVelocity() {
  const p = THREE.MathUtils.clamp(pitch, -0.54, 0.9);
  const speed =
    (player.focus ? 12.4 : player.moveSpeed > 12 ? 13.5 : 11.3) * (player.boostRemaining > 0 ? 1.12 : 1);
  const vertical = 3.45 + Math.sin(p) * 2.1;
  const heading = attackHeading();
  // Heading belongs to the squirrel, never to a free-orbiting camera.
  return v(Math.sin(heading) * speed * Math.cos(p), vertical, Math.cos(heading) * speed * Math.cos(p));
}
function attemptPounce() {
  if (player.cooldown > 0 || !playing || gamePaused || !player.alive) return;
  if (activeHouseInterior) {
    flash("Go outside before launching an ambush.", 1.6);
    return;
  }
  if (player.inDuct) {
    if (!dropFromHatch(true)) flash("Find and CHEW the high hatch before pouncing.", 1.8);
    return;
  }
  const heading = attackHeading(),
    vel = pounceVelocity();
  player.cooldown = 0.7;
  player.attack = 0.38;
  player.attackWindow = 0.78;
  player.attackTarget = null;
  player.attackAlert = new Map(humanoids.filter((n) => n.visible).map((n) => [n.idx, n.alert]));
  launchFromVisibleRoute();
  player.vel.copy(vel);
  player.rail = null;
  player.grounded = false;
  commitToAir(heading);
  fx(640, 0.1, "sawtooth", 0.025);
}
function resolvePounce(n) {
  if (player.attackWindow <= 0) return;
  const to = n.root.position.clone().sub(player.pos).setY(0).normalize();
  const aim = v(Math.sin(player.yaw), 0, Math.cos(player.yaw));
  const perfectCounter = (n.kickWindup || 0) > 0 && n.kickWindup < 0.34 && aim.dot(to) > 0.72;
  player.attackWindow = 0;
  player.attackTarget = n;
  const alreadyAlert = (player.attackAlert?.get(n.idx) || 0) > 0.45;
  // Stealth should decide the encounter. Alerted people dodge almost all ordinary head-on attacks.
  const successful =
    Boolean(n.motorcycle?.active) ||
    perfectCounter ||
    (alreadyAlert ? Math.random() < 0.035 : Math.random() < 0.955);
  if (perfectCounter && successful) {
    goldCoins++;
    n.kickWindup = 0;
    n.kickCooldown = 12;
    flash("PERFECT COUNTER! +1 GOLDEN SQUIRREL COIN", 2.8);
    fx(880, 0.12, "triangle", 0.06);
  }
  if (successful) {
    const pts = player.pos.y > 4 ? 150 : 100;
    player.points += pts;
    player.hits++;
    player.inactiveSeconds = 0;
    squirrelCoins += 10;
    totalCoinsEarned += 10;
    onSuccessfulBite(n);
    grantInfectionBite(n);
    refreshPowerUI();
    say(n, chooseLine(n, "hit"));
    flash("Successful ambush! +" + pts + " Power · 10-minute fade timer reset", 2.8);
    n.state = "flee";
    n.alert = 7;
    n.reacting = 2.5;
    player.vel.multiplyScalar(0.08);
    player.vel.y = 1.9;
    fx(150, 0.24, "triangle", 0.08);
  } else {
    n.state = "flee";
    n.alert = 7;
    n.reacting = 2.9;
    if (n.sayCooldown <= 0) say(n, chooseLine(n, "spot"));
    flash("Batted away! They saw you coming.", 2.5);
    player.vel.multiplyScalar(-0.12);
    player.vel.y = 3.7;
    fx(100, 0.25, "square", 0.047);
  }
}
function updatePounceCollision() {
  if (player.attackWindow <= 0 || player.inDuct) return;
  for (const n of humanoids) {
    if (!n.visible || n.injured || n === player.attackTarget || (n.hospital && n.nextBite > 0)) continue;
    const dist = Math.hypot(player.pos.x - n.root.position.x, player.pos.z - n.root.position.z);
    const dy = player.pos.y - n.root.position.y;
    if (dist < (n.motorcycle?.active ? 2.0 : 1.38) && dy > -0.35 && dy < (n.motorcycle?.active ? 3.2 : 2.7)) {
      resolvePounce(n);
      return;
    }
  }
  // Officers are dangerous, but an unseen approach can still bite and stun them.
  if (tryPolicePounce()) return;
  tryWildlifePounce();
}
function turnToward(old, desired, rate, dt) {
  return old + Math.atan2(Math.sin(desired - old), Math.cos(desired - old)) * (1 - Math.exp(-rate * dt));
}
function updatePlayer(dt) {
  if (hospitalTransition) {
    player.vel.set(0, 0, 0);
    player.rail = null;
    return;
  }
  player.cameraCommit = Math.max(0, player.cameraCommit - dt);
  player.focus =
    (focusMouse || focusToggle) &&
    !player.inDuct &&
    playing &&
    !player.committedAirborne &&
    player.cameraCommit === 0 &&
    player.rail?.kind !== "trunk";
  document.body.classList.toggle("focus", player.focus);
  document.body.classList.toggle("hatch-aim", Boolean(overheadHatch()));
  $("aimState").textContent = overheadHatch()
    ? "DROP AIM · LEFT CLICK TO POUNCE"
    : "ESTIMATED LEAP / POUNCE PATH";
  $("focusHeader").textContent = player.focus ? "PREDATOR’S EYE" : "SCOUTING";
  $("focusHeader").classList.toggle("dim", !player.focus);
  $("scoutText").innerHTML = player.focus
    ? "FIRST PERSON · slow, silent aim<br>Space to leap · left-click to pounce"
    : player.inDuct
      ? overheadHatch()
        ? "OVERHEAD EXIT OPEN · SPACE to drop<br>LEFT CLICK to pounce from above"
        : "VENT CRAWL · W/S along the duct<br>HOLD E at a closed grille to chew"
      : player.inHospital
        ? "EMERGENCY WING · E to use doors or vents<br>First vent: hold E to chew."
        : activeHouseInterior
          ? `INSIDE ${activeHouseInterior.indoorName.toUpperCase()} · E near front door to exit<br>WASD explore · SHIFT run · M HUD`
          : "Park NORTH · estates SOUTH · hospital WEST<br>Old town westside: E at open garages · police station nearby.";
  player.cooldown = Math.max(0, player.cooldown - dt);
  player.attack = Math.max(0, player.attack - dt);
  const priorWindow = player.attackWindow;
  player.attackWindow = Math.max(0, player.attackWindow - dt);
  if (priorWindow > 0 && player.attackWindow === 0 && !player.attackTarget)
    flash("Missed. Look down the landing path before committing.", 1.7);
  const fw = houseTransit
    ? 0
    : (keys.has("KeyW") || keys.has("ArrowUp") ? 1 : 0) - (keys.has("KeyS") || keys.has("ArrowDown") ? 1 : 0);
  const side = houseTransit ? 0 : (keys.has("KeyD") ? 1 : 0) - (keys.has("KeyA") ? 1 : 0);
  const moving = player.rail || player.inDuct ? fw !== 0 : Math.hypot(fw, side) > 0;
  const sprint = keys.has("ShiftLeft") || keys.has("ShiftRight");
  const treeTravel = player.rail && ["trunk", "branch", "bridge", "lookout"].includes(player.rail.kind);
  const base =
    (player.inDuct ? (sprint ? 3.8 : 2.8) : player.focus ? 1.65 : sprint ? 16.8 : 8.0) *
    (player.boostRemaining > 0 && !player.focus ? 1.6 : 1) *
    (treeTravel ? 0.6 : 1);
  player.moveSpeed = THREE.MathUtils.lerp(
    player.moveSpeed,
    moving ? base : 0,
    1 - Math.exp(-dt * (player.focus ? 11 : 17)),
  );
  const old = player.pos.clone(),
    oldYaw = player.yaw;
  // Ground approach is a real interaction: no grab if looking or running away.
  if (
    !player.rail &&
    player.grounded &&
    !player.inSewer &&
    !player.inHospital &&
    !houseTransit &&
    player.attackWindow === 0 &&
    fw > 0 &&
    player.moveSpeed > 0.45
  ) {
    const nearby = groundTrunkCandidate(player.pos, 2.0);
    if (forwardIntoTrunk(nearby, fw, side)) enterRoute(nearby);
  }
  if (player.inDuct) {
    // Fixed-distance traversal prevents cutting through metal at sharp corners.
    if (fw !== 0) {
      ductTravel = THREE.MathUtils.clamp(ductTravel + fw * player.moveSpeed * dt, 0, ductTotalLength);
      ductViewAhead = fw > 0 ? 1 : -1;
    }
    const centre = ductPointAt(ductTravel);
    player.pos.set(centre.x, centre.y - 0.72, centre.z);
    const forward = ductTangentAt(ductTravel).multiplyScalar(ductViewAhead);
    player.yaw = turnToward(player.yaw, Math.atan2(forward.x, forward.z), 11.0, dt);
    player.vel.set(0, 0, 0);
    player.grounded = true;
  } else if (player.rail) {
    const rs = player.rail;
    if (routeBridge) {
      routeBridge.elapsed = Math.min(routeBridge.duration, routeBridge.elapsed + Math.min(dt, 0.05));
      const progress = RouteJunction.ease(routeBridge.elapsed / routeBridge.duration);
      player.pos.copy(routeBridge.from).lerp(routeBridge.to, progress);
      player.vel.set(0, 0, 0);
      if (progress >= 1) routeBridge = null;
    } else {
      if (!routeWasMoving && fw !== 0) {
        player.railDir = directionFromView(rs, player.railT, player.railDir);
      }
      routeWasMoving = fw !== 0;
      const railSpeed =
          (player.focus ? 1.2 : sprint ? 12.2 : 7.2) *
          (player.boostRemaining > 0 && !player.focus ? 1.6 : 1) *
          (["trunk", "branch", "bridge", "lookout"].includes(rs.kind) ? 0.6 : 1),
        dir = fw;
      const before = player.railT;
      player.railT = RouteMotion.advance(player.railT, player.railDir, dir, dt, railSpeed, rs.length);
      // Once a bough has been deliberately selected, holding W takes it at the junction.
      if (
        pendingFork &&
        rs.kind === "trunk" &&
        dir > 0 &&
        player.railT * rs.length >= pendingFork.t * rs.length - 0.42 &&
        before <= pendingFork.t + 0.022
      ) {
        player.railT = pendingFork.t;
        player.pos.copy(rs.curve.getPointAt(player.railT));
        takeSelectedFork(true);
      }
      if (player.railT > 1 || player.railT < 0) {
        const atStart = player.railT < 0;
        player.railT = THREE.MathUtils.clamp(player.railT, 0, 1);
        if (dir !== 0 && !switchRoute(rs, atStart)) player.railT = atStart ? 0 : 1;
      }
      // On trunks A/D chooses a visible fork; no random nearest-route teleportation.
      // On wires or roofs, E remains the deliberate route-transfer key.
      if (player.rail !== rs) player.railT = THREE.MathUtils.clamp(player.railT, 0, 1);
      player.transferCooldown = Math.max(0, player.transferCooldown - dt);
      if (!routeBridge) player.pos.copy(player.rail.curve.getPointAt(player.railT));
      const tangent = player.rail.curve.getTangentAt(player.railT);
      if (tangent.lengthSq() > 0.1 && Math.abs(tangent.x) + Math.abs(tangent.z) > 0.25) {
        const sense = dir !== 0 ? Math.sign(dir) * player.railDir : player.railDir;
        const angle = Math.atan2(sense * tangent.x, sense * tangent.z);
        player.yaw = turnToward(player.yaw, angle, 14, dt);
        // Follow behind the squirrel except while the player is manually orbiting.
        if (dir !== 0 && routeFreeLook <= 0) yaw = turnToward(yaw, player.yaw + PI, 3.4, dt);
      }
      player.vel.set(0, 0, 0);
    } // end ordinary route motion; active transfers are eased separately.
  } else {
    routeWasMoving = false;
    selectedJunction = null;
    routeBridge = null;
    if (moving && player.attackWindow === 0) {
      const dir = v(
        -Math.sin(yaw) * fw + Math.cos(yaw) * side,
        0,
        -Math.cos(yaw) * fw - Math.sin(yaw) * side,
      ).normalize();
      const accel = player.grounded ? 23 : 4.2;
      const a = 1 - Math.exp(-dt * accel);
      player.vel.x = THREE.MathUtils.lerp(player.vel.x, dir.x * player.moveSpeed, a);
      player.vel.z = THREE.MathUtils.lerp(player.vel.z, dir.z * player.moveSpeed, a);
      player.yaw = turnToward(player.yaw, Math.atan2(dir.x, dir.z), player.focus ? 19 : 25, dt);
    } else if (player.attackWindow === 0) {
      const friction = Math.exp(-dt * (player.grounded ? 13 : 1.15));
      player.vel.x *= friction;
      player.vel.z *= friction;
    }
    if (player.focus && !moving) player.yaw = turnToward(player.yaw, yaw + PI, 11, dt);
    player.vel.y -= SQUIRREL_GRAVITY * dt;
    player.pos.addScaledVector(player.vel, dt);
    constrainMallCeiling(old);
    const landedOnRoof = resolveMallLanding(old) || resolveRoofLanding(old);
    if (player.inHospital) adjustHospitalMovement(old);
    else if (!player.inSewer) {
      resolveOutdoorMovement(old);
      if (insideHospitalBuilding() && !hospitalTransition) {
        player.pos.x = old.x;
        player.pos.z = old.z;
      }
    } else constrainSewer(old);
    recoverTrappedInHouse();
    const ground = player.inSewer
      ? sewerFloorY + 0.25
      : player.inHospital
        ? player.inDuct
          ? ductNearestPoint(player.pos).y - 0.72
          : HOSPITAL_FLOOR + 0.2
        : getGroundAt(player.pos.x, player.pos.z);
    if (landedOnRoof) {
      player.pos.y = Math.max(player.pos.y, ground);
      player.grounded = true;
      player.vel.y = 0;
    } else if (attemptTrampolineBounce(old)) {
      // Preserve vertical spring impulse and airborne control.
    } else if (player.pos.y <= ground) {
      player.pos.y = ground;
      player.grounded = true;
      player.vel.y = 0;
      if (player.committedAirborne) {
        player.committedAirborne = false;
        player.cameraCommit = Math.max(player.cameraCommit, 0.35);
      }
    } else player.grounded = false;
  }
  routeFreeLook = Math.max(0, routeFreeLook - dt);
  player.pos.x = THREE.MathUtils.clamp(player.pos.x, -586, RIVER.endX - 4);
  player.pos.z = THREE.MathUtils.clamp(player.pos.z, -560, NORTH_LIMIT - 4);
  recoverRiverFall();
  updatePounceCollision();
  // Route curves run through wood centerlines; the visible squirrel must NOT.
  updateCanopyGuide(dt);
  drawJunctionPreview();
  const isTrunk = player.rail?.kind === "trunk";
  const isWoodTop = player.rail && ["branch", "bridge", "lookout"].includes(player.rail.kind);
  const visualPos = player.pos.clone();
  if (isTrunk) {
    const builtSurface = player.rail.name.includes("downspout") || player.rail.name.includes("gutter");
    const poleSurface = player.rail.name.includes("telephone pole");
    // A gutter is fixed on the positive-Z facade; don't bury the squirrel in plaster.
    const surface = builtSurface ? v(0, 0, 1) : player.trunkNormal || v(0, 0, 1);
    const r = player.rail.surfaceRadius || 1.3;
    const tapered = player.rail.name.includes("giant trunk")
      ? Math.max(0.45, r / 0.95 - 1.05 * player.railT)
      : Math.max(0.32, r * (1 - 0.48 * player.railT));
    const offset = builtSurface || poleSurface ? r + 0.2 : tapered + 0.28;
    visualPos.addScaledVector(surface, offset);
    // Face the bark while climbing: paws and claws point IN, not at the camera.
    squirrel.rotation.y = Math.atan2(-surface.x, -surface.z);
  } else {
    if (isWoodTop) {
      visualPos.y += player.rail.visualOffset ?? (player.rail.kind === "lookout" ? 0.61 : 0.5);
      if (player.rail.kind === "branch" && player.rail.trunkClearance && player.railT < 0.2) {
        const a = player.rail.curve.getPointAt(0),
          b = player.rail.curve.getPointAt(0.16),
          out = b.sub(a).setY(0).normalize();
        const blend = Math.pow(1 - THREE.MathUtils.clamp(player.railT / 0.2, 0, 1), 2);
        visualPos.addScaledVector(out, (player.rail.trunkClearance + 0.31) * blend);
      }
    } else if (player.rail?.kind === "wire") visualPos.y += 0.22;
    squirrel.rotation.y = player.yaw;
  }
  // On lawn/street level, set paws closer to the actual terrain without moving
  // the physics body. Do not alter roofs, wires, trees, ducts, or airborne leaps.
  const onGroundSurface =
    !player.rail &&
    player.grounded &&
    !player.inHospital &&
    !player.inSewer &&
    Math.abs(player.pos.y - squirrelSurfaceAt(player.pos.x, player.pos.z)) < 0.7;
  if (onGroundSurface) visualPos.y = squirrelSurfaceAt(player.pos.x, player.pos.z);
  // Render smoothing is cosmetic and bounded; gameplay uses player.pos exclusively.
  if (
    (!routeBridge && squirrel.position.distanceTo(visualPos) > 2.5) ||
    (player.rail && !routeBridge && squirrel.position.distanceTo(visualPos) > 1.6)
  )
    squirrel.position.copy(visualPos);
  else squirrel.position.lerp(visualPos, 1 - Math.exp(-dt * (routeBridge ? 17 : 23)));
  // Body banking, sprint gallop, and independent head counterturn.
  const turning =
    Math.atan2(Math.sin(player.yaw - oldYaw), Math.cos(player.yaw - oldYaw)) / Math.max(dt, 0.012);
  player.turnLean = THREE.MathUtils.lerp(
    player.turnLean,
    THREE.MathUtils.clamp(-turning * 0.035, -0.31, 0.31),
    1 - Math.exp(-dt * 12),
  );
  const cadence = player.moveSpeed * (player.rail ? 0.7 : 2.85) * (player.boostRemaining > 0 ? 1.14 : 1);
  const gallop =
    player.moveSpeed > 1.3
      ? Math.sin(time * cadence) *
        (onGroundSurface
          ? 0.022 + Math.min(player.moveSpeed, 17) * 0.0011
          : 0.042 + Math.min(player.moveSpeed, 17) * 0.002)
      : 0;
  sqroot.position.y = isTrunk ? 0 : gallop;
  sqroot.rotation.z = isTrunk ? 0 : player.turnLean;
  const grip = THREE.MathUtils.smoothstep(
    player.pos.y - terrainHeight(player.pos.x, player.pos.z),
    0.25,
    2.4,
  );
  sqroot.rotation.x = isTrunk
    ? THREE.MathUtils.lerp(-0.83, -1.43, grip)
    : player.attackWindow > 0
      ? -0.16
      : player.focus
        ? 0.05
        : Math.sin(time * cadence) * (onGroundSurface ? 0.022 : 0.034);
  const squash = isTrunk ? 1 : player.focus ? 0.9 : sprint ? 0.92 : 1;
  eyeMat.emissiveIntensity = player.boostRemaining > 0 ? 1.65 : 0.92;
  sqroot.scale.set(1, squash, player.attackWindow > 0 ? 1.13 : 1);
  sqFace.rotation.y =
    THREE.MathUtils.clamp(
      Math.atan2(Math.sin(yaw - player.yaw), Math.cos(yaw - player.yaw)) * 0.38,
      -0.4,
      0.4,
    ) +
    Math.sin(time * 1.8) * 0.035;
  sqFace.rotation.x = player.focus ? -0.05 : player.attackWindow > 0 ? -0.17 : 0;
  for (const leg of sqLegs) {
    if (isTrunk) {
      const stepping = player.moveSpeed > 1 ? 0.16 : 0;
      leg.pivot.rotation.x =
        (leg.front > 0 ? -0.26 : 0.22) +
        Math.sin(time * cadence + (leg.front > 0 ? 0 : PI) + (leg.side > 0 ? 0.9 : 0)) * stepping;
      leg.pivot.rotation.z = leg.side * 0.12;
    } else {
      leg.pivot.rotation.x = player.focus
        ? 0.12
        : Math.sin(time * cadence + (leg.front > 0 ? 0 : PI) + (leg.side > 0 ? 0.9 : 0)) *
          (player.moveSpeed > 1 ? (onGroundSurface ? 0.35 : 0.4) : 0);
      leg.pivot.rotation.z = 0;
    }
  }
  updateTail(time);
  if (onGroundSurface) settleSquirrelFeet();
  squirrel.visible = !player.focus;
  player.nearRoute = player.rail ? null : nearestRoute(2.3);
  if (player.nearRoute && messageTime <= 0 && Math.random() < dt * 0.09)
    flash(`E to grab: ${player.nearRoute.route.name}`, 1.9);
}
function npcDestination(n) {
  n.onAccess = false;
  n.goal = pedestrianGoal(n);
}
// A resident only retreats through a real, hinged doorway. Other walkers must
// respect the solid footprints and never ghost through any house wall.
function beginHomeRetreat(n) {
  if (n.home < 0 || n.home >= 4 || n.injured || n.doorEscape) return false;
  const door = houseDoors[n.home];
  if (!door) return false;
  const dist = Math.hypot(n.root.position.x - door.outside.x, n.root.position.z - door.outside.z);
  if (dist > 38) return false;
  // Route around the SIDE when the player catches someone in the backyard.
  // Never select a straight path that crosses the home's solid walls.
  const h = houses[n.home],
    position = n.root.position;
  const behind = (position.z - h.z) * -door.sign < -0.3;
  const boundsX = h.w / 2 + 1.6,
    boundsZ = h.d / 2 + 1.6;
  const lineCrossesWall = (() => {
    for (let i = 1; i < 18; i++) {
      const t = i / 19;
      const xx = position.x + (door.outside.x - position.x) * t;
      const zz = position.z + (door.outside.z - position.z) * t;
      if (Math.abs(xx - h.x) < h.w / 2 + 0.35 && Math.abs(zz - h.z) < h.d / 2 + 0.35) return true;
    }
    return false;
  })();
  const path = [];
  if (behind || lineCrossesWall) {
    const side = position.x >= h.x ? 1 : -1;
    const xx = h.x + side * boundsX;
    path.push(v(xx, 0, Math.max(h.z - boundsZ, Math.min(h.z + boundsZ, position.z))));
    path.push(v(xx, 0, door.outside.z + -door.sign * 1.25));
  }
  path.push(door.outside.clone());
  n.doorEscape = { stage: "approach", waypoints: path, time: 0 };
  n.state = "homeRetreat";
  n.speed = 4.7;
  n.reacting = Math.max(n.reacting, 4);
  door.hold = Math.max(door.hold, 3);
  return true;
}
function advanceHomeRetreat(n, dt) {
  const d = houseDoors[n.home];
  if (!d || !n.doorEscape) {
    n.doorEscape = null;
    return;
  }
  const r = n.doorEscape;
  r.time += dt;
  d.hold = Math.max(d.hold, 1.2);
  // Wait for the door to swing open before crossing the threshold.
  const destination =
    r.stage === "approach" ? r.waypoints?.[0] || d.outside : r.stage === "threshold" ? d.threshold : d.inside;
  const p = n.root.position,
    dx = destination.x - p.x,
    dz = destination.z - p.z,
    dist = Math.hypot(dx, dz);
  if (r.stage === "approach" && dist < 0.65) {
    r.waypoints.shift();
    if (!r.waypoints.length) {
      r.stage = "threshold";
      d.hold = 3.1;
    }
    return;
  }
  if (r.stage === "threshold" && !houseDoorPassable(d)) return;
  if (r.stage === "threshold" && dist < 0.22) {
    r.stage = "inside";
    return;
  }
  if (r.stage === "inside" && dist < 0.42) {
    n.visible = false;
    n.root.visible = false;
    n.doorEscape = null;
    n.hiddenInHomeUntil = time + 16 + Math.random() * 12;
    d.hold = 2.2;
    return;
  }
  if (dist > 0.07) {
    const step = Math.min(dist, (r.stage === "approach" ? 4.9 : 2.65) * dt);
    p.x += (dx / dist) * step;
    p.z += (dz / dist) * step;
    n.facing = turnToward(n.facing, Math.atan2(dx, dz), 8, dt);
    n.root.rotation.y = n.facing;
  }
  p.y = terrainHeight(p.x, p.z) + 0.13;
  const run = Math.sin(time * 13 + n.phase);
  n.arms.forEach(
    (arm, k) => (arm.rotation.x = -1.25 + (k ? 0.24 : -0.24) + Math.sin(time * 11 + k * 3) * 0.22),
  );
  n.legs.forEach((leg, k) => (leg.rotation.x = (k ? 1 : -1) * run * 0.46));
  n.head.rotation.y = Math.sin(time * 11) * 0.3;
}
// A shared clearance rule for pedestrians and squirrel interior transitions.
// The collision/visual animation may lag the interaction trigger on slow frames.
function houseDoorPassable(d) {
  return Boolean(d && d.open >= 0.86);
}
function animateHouseDoors(dt) {
  for (const d of houseDoors) {
    if (!d) continue;
    d.hold = Math.max(0, d.hold - dt);
    const active = humanoids.some((n) => n.visible && n.doorEscape && n.home === d.id);
    d.open = THREE.MathUtils.damp(d.open, d.hold > 0 || active ? 1 : 0, 7.2, dt);
    d.pivot.rotation.y = d.sign * d.open * 1.35;
  }
}
function humanHouseCollision(n, beforeX, beforeZ) {
  const pos = n.root.position;
  // Both residential and commercial walls are solid for pedestrians.
  for (const h of houses.concat(commercialBounds)) {
    const a = h.w / 2 + 0.3,
      b = h.d / 2 + 0.3;
    if (Math.abs(pos.x - h.x) >= a || Math.abs(pos.z - h.z) >= b) continue;
    const canX = Math.abs(beforeX - h.x) >= a,
      canZ = Math.abs(beforeZ - h.z) >= b;
    if (canX) pos.x = beforeX;
    else if (canZ) pos.z = beforeZ;
    else {
      // If old geometry spawned someone inside, move them to the nearest exterior edge.
      const sides = [
        { val: a - Math.abs(pos.x - h.x), axis: "x" },
        { val: b - Math.abs(pos.z - h.z), axis: "z" },
      ].sort((p, q) => p.val - q.val);
      if (sides[0].axis === "x") pos.x = h.x + (pos.x >= h.x ? 1 : -1) * (a + 0.04);
      else pos.z = h.z + (pos.z >= h.z ? 1 : -1) * (b + 0.04);
    }
    if (n.state !== "flee") n.goal = null;
  }
}
function updateHumans(dt) {
  manageNpcSpawns(dt);
  for (const n of humanoids) {
    if (!n.visible || n.hospital || n.specialStreetCast) continue;
    if (n.doorEscape) {
      advanceHomeRetreat(n, dt);
      continue;
    }
    n.timeAway += dt;
    n.sayCooldown = Math.max(0, n.sayCooldown - dt);
    n.alert = Math.max(0, n.alert - dt);
    n.reacting = Math.max(0, n.reacting - dt);
    let pos = n.root.position;
    const prevPedX = pos.x,
      prevPedZ = pos.z;
    const diff = player.pos.clone().sub(pos);
    const dist2 = Math.hypot(diff.x, diff.z);
    const isVisible = !activeHouseInterior && (player.pos.y < 4 || (player.pos.y > 4 && dist2 < 4.7));
    // People recognize the squirrel by sight, but quiet waiting in the canopy defeats detection.
    let towards = v(Math.sin(n.facing), 0, Math.cos(n.facing));
    const inView = diff.clone().setY(0).normalize().dot(towards) > 0.28;
    const noise = player.moveSpeed > (player.focus ? 2.5 : 4.7) && dist2 < 8.6 && player.pos.y - pos.y < 22;
    const gardenBlind =
      player.pos.y < 2.4 && Math.abs(player.pos.x - GARDEN_X) < 27 && Math.abs(player.pos.z - GARDEN_Z) < 15;
    const hedgeBlind =
      player.pos.y < 2.8 &&
      hedgePatches.some(
        ([x, z, len, h]) =>
          Math.abs(player.pos.x - x) < len / 2 + 1.8 && Math.abs(player.pos.z - z) < h + 1.1,
      );
    const concealed = (gardenBlind || hedgeBlind) && player.moveSpeed < 3.4;
    const hotHere = crimeScenes.some(
      (s) => s.ttl > 0 && Math.hypot(pos.x - s.center.x, pos.z - s.center.z) < s.radius,
    );
    const remembered = (n.witnessUntil || 0) > time;
    const radar = hotHere || remembered ? 3 : 1;
    const spotted =
      !concealed &&
      ((isVisible && dist2 < Math.min(20, 14.5 * radar) && (inView || dist2 < 6.8) && player.pos.y < 5.2) ||
        (noise && dist2 < Math.min(16, 10.3 * radar)));
    if (hotHere && spotted) n.witnessUntil = Math.max(n.witnessUntil || 0, time + 600);
    if (n.wantedSawAt && time - n.wantedSawAt < 90 && spotted && dist2 < 8.5 * 3 && !n.wantedCalled) {
      n.wantedCalled = true;
      n.witnessUntil = time + 600;
      say(n, "That is the squirrel from that poster!");
      sendPosterPolice(n.root.position);
    }
    if (player.hits > 8 && (!n.wantedSawAt || time - n.wantedSawAt >= 90)) {
      for (const poster of wantedPosters) {
        if (Math.hypot(pos.x - poster.x, pos.z - poster.z) < 10) {
          n.wantedSawAt = time;
          n.wantedCalled = false;
          break;
        }
      }
    }
    if (spotted && n.alert <= 0 && !["flee", "homeRetreat", "defend", "kick"].includes(n.state)) {
      n.state = "flee";
      n.alert = 8;
      n.reacting = 3;
      if (n.sayCooldown <= 0) say(n, chooseLine(n, "spot"));
      fx(410, 0.09, "sine", 0.009);
      if (beginHomeRetreat(n)) {
        advanceHomeRetreat(n, dt);
        continue;
      }
    }
    if (player.inSewer || player.inHospital) continue;
    handleKickWindup(n, dt, dist2, spotted);
    n.dodgeCooldown = Math.max(0, (n.dodgeCooldown || 0) - dt);
    if (n.dodgeTimer > 0) n.dodgeTimer = Math.max(0, n.dodgeTimer - dt);
    if (
      player.attackWindow > 0 &&
      spotted &&
      n.alert > 1.5 &&
      dist2 < 5.4 &&
      n.dodgeCooldown <= 0 &&
      !n.doorEscape &&
      n.state !== "kick"
    ) {
      n.dodgeCooldown = 2.4;
      n.dodgeTimer = 0.38;
      n.dodgeSide = n.idx % 2 ? 1 : -1;
    }
    if (n.state === "defend" && ((n.defenseUntil || 0) <= time || !spotted || dist2 > 17)) {
      n.defenseUntil = 0;
      n.state = "flee";
    }
    let target = n.state === "kick" ? pos.clone() : n.goal;
    if (n.state === "defend") {
      if (dist2 > 2.8 && dist2 < 17) {
        target = player.pos.clone().addScaledVector(pos.clone().sub(player.pos).setY(0).normalize(), 2.4);
        n.speed = 5.6;
      } else {
        target = pos.clone();
        n.speed = 0;
      }
    }
    if (n.state === "flee") {
      // Panic keeps to the footpath instead of charging diagonally across traffic.
      const along = n.onAccess ? "z" : n.pedLane.axis;
      const val = along === "x" ? pos.x : pos.z,
        enemy = along === "x" ? player.pos.x : player.pos.z;
      const delta = (val >= enemy ? 1 : -1) * 22;
      const corridor = n.onAccess ? { axis: "z", fixed: pos.x } : n.pedLane;
      target = pointOnLane(
        corridor,
        THREE.MathUtils.clamp(
          val + delta,
          n.pedLane?.commercial ? 385 : -260,
          n.pedLane?.commercial ? 655 : 260,
        ),
      );
      n.speed = n.role === "cyclist" ? 8.25 : 7.1;
      if (n.alert < 2) {
        n.state = "walk";
        npcDestination(n);
        n.speed = n.role === "cyclist" ? 4.2 : R(0.9, 1.8);
      }
    }
    if (!target) npcDestination(n), (target = n.goal);
    let dd = target.clone().sub(pos).setY(0);
    if (n.state !== "kick" && n.state !== "defend" && dd.length() < 1.7) {
      npcDestination(n);
      dd = n.goal.clone().sub(pos).setY(0);
    }
    if (n.state !== "kick" && dd.lengthSq() > 0.3) {
      dd.normalize();
      let moveRate = THREE.MathUtils.damp(n.smoothedSpeed || 0, n.speed, n.state === "flee" ? 10 : 6.8, dt);
      n.smoothedSpeed = moveRate;
      let step = dd
        .clone()
        .multiplyScalar(
          Math.min(
            moveRate * dt,
            dd.length() > 0
              ? n.goal && n.state === "walk"
                ? Math.max(0.08, Math.hypot(target.x - pos.x, target.z - pos.z))
                : moveRate * dt
              : 0,
          ),
        );
      // Pedestrians physically wait if a vehicle is already occupying the next step.
      const next = pos.clone().add(step);
      if (
        cars.some(
          (c) => c.moving && Math.hypot(c.group.position.x - next.x, c.group.position.z - next.z) < 3.25,
        ) ||
        streetVehicleAt(next.x, next.z, 0.55)
      )
        step.set(0, 0, 0);
      pos.add(step);
      if (n.dodgeTimer > 0) {
        const side = v(dd.z * n.dodgeSide, 0, -dd.x * n.dodgeSide);
        pos.addScaledVector(side, dt * 8.6);
      }
      const desired = Math.atan2(dd.x, dd.z);
      let turn = ((desired - n.facing + PI * 3) % (PI * 2)) - PI;
      n.facing += THREE.MathUtils.clamp(turn, -dt * 4, dt * 4);
      n.root.rotation.y = n.facing;
    }
    pos.x = THREE.MathUtils.clamp(pos.x, -265, 671);
    pos.z = THREE.MathUtils.clamp(pos.z, -241, 436);
    // Lock pedestrians to their walkable corridor: no invisible cross-lot diagonals.
    // Do not snap fleeing or defending people onto a different path each frame.
    if (n.state === "walk" && n.onAccess) pos.x = THREE.MathUtils.damp(pos.x, n.accessX ?? pos.x, 8, dt);
    else if (n.state === "walk" && n.pedLane) {
      if (n.pedLane.axis === "x") pos.z = THREE.MathUtils.damp(pos.z, n.pedLane.fixed, 8, dt);
      else pos.x = THREE.MathUtils.damp(pos.x, n.pedLane.fixed, 8, dt);
    }
    humanHouseCollision(n, prevPedX, prevPedZ);
    pos.y = terrainHeight(pos.x, pos.z) + 0.13;
    // Rotate road bicycles by actual displacement, not by frame count or jitter from a blocked path.
    if (n.role === "cyclist" && n.bike?.visible && n.bikeWheels?.length) {
      const travelled = Math.min(3, Math.hypot(pos.x - prevPedX, pos.z - prevPedZ));
      for (const wheel of n.bikeWheels) wheel.rotation.x += travelled / wheel.userData.rollingRadius;
      if (n.bikeCrank) n.bikeCrank.rotation.x += travelled / 0.34;
    }

    const gait = Math.sin(
        time * (n.role === "cyclist" ? 8 : n.state === "flee" ? 12 : n.role === "jogger" ? 10 : 6) + n.phase,
      ),
      panic = n.reacting > 0;
    for (let k = 0; k < 2; k++) {
      n.arms[k].rotation.x = panic ? -2.5 + Math.sin(time * 14 + k * 3) * 0.45 : (k ? 1 : -1) * gait * 0.45;
      n.arms[k].rotation.z = panic ? (k ? 0.35 : -0.35) : 0;
      n.legs[k].rotation.x = n.role === "cyclist" ? 0.1 : (k ? 1 : -1) * gait * 0.52;
    }
    n.head.rotation.y = panic ? Math.sin(time * 13) * 0.28 : Math.sin(time * 1.5 + n.phase) * 0.05;
    n.body.rotation.z = panic ? Math.sin(time * 11) * 0.095 : 0;
    if (n.kickWindup > 0) n.legs[1].rotation.x = -1.1 - (1 - n.kickWindup) * 0.65;
    if (n.timeAway > n.maxLife || pos.x > 670 || pos.x < -265 || pos.z < -242 || pos.z > 438) {
      n.visible = false;
      n.root.visible = false;
      n.timeAway = 0;
      n.maxLife = R(24, 56);
      for (const b of bubbles.filter((b) => b.npc === n)) b.life = 0;
    }
  }
}
const _tempV = new THREE.Vector3();
function updateBubbles(dt) {
  for (let i = bubbles.length - 1; i >= 0; i--) {
    const b = bubbles[i];
    b.life -= dt;
    if (b.life <= 0 || !b.npc.visible) {
      b.ob.remove();
      bubbles.splice(i, 1);
      continue;
    }
    let p = b.npc.root.position.clone().add(v(0, 4.7, 0));
    p.project(camera);
    const x = (p.x * 0.5 + 0.5) * innerWidth,
      y = (-p.y * 0.5 + 0.5) * innerHeight;
    if (p.z > 1 || x < -100 || x > innerWidth + 100 || y < -100 || y > innerHeight + 100)
      b.ob.style.display = "none";
    else {
      b.ob.style.display = "block";
      b.ob.style.left = x + "px";
      b.ob.style.top = y + "px";
      b.ob.style.opacity = Math.min(1, b.life / 0.7);
    }
  }
}
// Faint first-person ballistic sightline, rendered in world space (not an opaque UI).
const trailCoords = new Float32Array(34 * 3),
  trailGeo = new THREE.BufferGeometry();
trailGeo.setAttribute("position", new THREE.BufferAttribute(trailCoords, 3).setUsage(THREE.DynamicDrawUsage));
const trailLine = new THREE.Line(
  trailGeo,
  new THREE.LineBasicMaterial({ color: 0xc9ddb0, transparent: true, opacity: 0.33, depthWrite: false }),
);
trailLine.frustumCulled = false;
scene.add(trailLine);
const landingMark = new THREE.Mesh(
  new THREE.RingGeometry(0.24, 0.3, 40),
  new THREE.MeshBasicMaterial({
    color: 0xe4f1d4,
    transparent: true,
    opacity: 0.54,
    depthWrite: false,
    side: THREE.DoubleSide,
  }),
);
landingMark.rotation.x = -PI / 2;
scene.add(landingMark);
function updateAimPath() {
  trailLine.visible = landingMark.visible = player.focus && player.attackWindow === 0;
  if (!trailLine.visible) return;
  const vel = pounceVelocity();
  const start = player.pos.clone();
  let count = 0,
    hit = null;
  for (let i = 0; i < 34; i++) {
    const t = 0.06 + i * 0.05;
    const p = start
      .clone()
      .addScaledVector(vel, t)
      .add(v(0, -0.5 * SQUIRREL_GRAVITY * t * t, 0));
    const y = getGroundAt(p.x, p.z);
    if (p.y < y) {
      hit = v(p.x, y + 0.028, p.z);
      break;
    }
    trailCoords[count * 3] = p.x;
    trailCoords[count * 3 + 1] = p.y + 0.14;
    trailCoords[count * 3 + 2] = p.z;
    count++;
  }
  trailGeo.setDrawRange(0, count);
  trailGeo.attributes.position.needsUpdate = true;
  landingMark.visible = !!hit;
  if (hit) {
    landingMark.position.copy(hit);
    landingMark.rotation.z = time * 0.12;
  }
}
// Predator mode places the eye at the squirrel's head; committing the jump
// immediately cuts to a wider, trailing camera for spatial awareness.
let camPos = v(-36, 3, -30),
  lookPoint = v(-36, 0.6, -36),
  cameraHardCut = false;
function updateCamera(dt) {
  const horizontal = v(-Math.sin(yaw), 0, -Math.cos(yaw));
  let desired, target;
  if (player.inDuct) {
    // Rail-mounted chase camera: both eye and target run ALONG the curved duct path,
    // so turns cannot throw the view through walls or behind the squirrel.
    ductViewTravel = THREE.MathUtils.lerp(ductViewTravel, ductTravel, 1 - Math.exp(-dt * 15));
    const trailing = ductPointAt(ductViewTravel - ductViewAhead * 1.15);
    const ahead = ductPointAt(ductTravel + ductViewAhead * 2.55);
    desired = trailing.add(v(0, -0.4, 0));
    target = ahead.add(v(0, -0.47, 0));
    // Looking through a cleared hatch reveals the people below before the drop.
    if (overheadHatch()) {
      const lookDir = v(-Math.sin(yaw), 0, -Math.cos(yaw));
      target = v(ductVents[4].x + lookDir.x * 4.3, HOSPITAL_FLOOR + 0.5, ductVents[4].z + lookDir.z * 4.3);
      desired = player.pos
        .clone()
        .add(v(0, 0.38, 0))
        .addScaledVector(ductTangentAt(ductTravel), -1.0);
    }
  } else if (player.focus) {
    desired = player.pos.clone().add(v(0, 0.27 + Math.sin(time * 1.65) * 0.005, 0));
    const aim = v(horizontal.x * Math.cos(pitch), Math.sin(pitch), horizontal.z * Math.cos(pitch));
    target = desired.clone().addScaledVector(aim, 24);
  } else if (player.rail?.kind === "trunk") {
    // Level, side-on third-person view: visible animal OUTSIDE the bark.
    const n = player.trunkNormal || v(0, 0, 1);
    target = squirrel.position.clone().add(v(0, 0.18, 0));
    desired = target
      .clone()
      .addScaledVector(n, 3.25)
      .add(v(0, 0.58, 0));
  } else if (player.rail && player.rail.kind !== "trunk") {
    // On branches: elevated camera looking down at the squirrel's back.
    const tangent = player.rail.curve.getTangentAt(player.railT).multiplyScalar(player.railDir);
    let along = v(tangent.x, 0, tangent.z).normalize();
    if (along.lengthSq() < 0.01) along = horizontal;
    // Free-look orbits without redirecting a held W; chase view returns smoothly.
    const orbit = THREE.MathUtils.clamp(routeFreeLook / 1.7, 0, 1);
    along.lerp(horizontal, orbit * 0.8).normalize();
    const wire = player.rail.kind === "wire",
      roof = player.rail.kind === "roof";
    const behind = wire ? 3.5 : roof ? 3.7 : 3.2;
    target = squirrel.position
      .clone()
      .addScaledVector(along, 0.85)
      .add(v(0, 0.28, 0));
    desired = squirrel.position
      .clone()
      .addScaledVector(along, -behind)
      .addScaledVector(v(-along.z, 0, along.x), 0.45)
      .add(v(0, wire ? 2.35 : 2.6 + Math.sin(pitch) * 0.55, 0));
  } else {
    const airborne = player.committedAirborne || (!player.grounded && !player.rail);
    // Keep the original small animal scale, but frame its full silhouette.
    const distance = airborne ? 5.5 : player.moveSpeed > 11 ? 4.2 : 3.35;
    const rise = airborne ? 2.15 : 1.4;
    desired = squirrel.position
      .clone()
      .addScaledVector(horizontal, -distance * Math.cos(pitch * 0.6))
      .addScaledVector(v(-horizontal.z, 0, horizontal.x), 0.62)
      .add(v(0, rise + Math.sin(pitch) * distance * 0.57, 0));
    target = squirrel.position
      .clone()
      .addScaledVector(horizontal, airborne ? 1.1 : 0.55)
      .add(v(0, airborne ? 0.46 : 0.24, 0));
  }
  if (!player.inHospital && !player.inSewer && !player.inDuct && !player.focus)
    desired.y = Math.max(desired.y, squirrelSurfaceAt(desired.x, desired.z) + 0.4);
  if (player.inHospital && !player.inDuct) {
    desired.x = THREE.MathUtils.clamp(desired.x, HOSP_X - HOSP_W / 2 + 1.8, HOSP_X + HOSP_W / 2 - 1.8);
    desired.z = THREE.MathUtils.clamp(desired.z, HOSP_Z - HOSP_D / 2 + 1.8, HOSP_Z + HOSP_D / 2 - 1.8);
    desired.y = THREE.MathUtils.clamp(desired.y, HOSPITAL_FLOOR + 0.22, HOSPITAL_FLOOR + 11.2);
    // Avoid filming THROUGH an interior partition as the squirrel rounds a door.
    const at = target.clone();
    for (let i = 1; i <= 16; i++) {
      const q = at.clone().lerp(desired, i / 16);
      if (q.y > HOSPITAL_FLOOR + 7) break;
      if (
        hospitalObstacles.some(
          (b) => Math.abs(q.x - b.x) < b.w / 2 + 0.16 && Math.abs(q.z - b.z) < b.d / 2 + 0.16,
        )
      ) {
        desired = at.lerp(desired, Math.max(0, (i - 1) / 16));
        break;
      }
    }
  }
  if (activeHouseInterior) {
    const h = activeHouseInterior,
      pad = 0.55;
    const innerX = h.w / 2 - pad,
      innerZ = h.d / 2 - pad;
    desired.x = THREE.MathUtils.clamp(desired.x, h.x - innerX, h.x + innerX);
    desired.z = THREE.MathUtils.clamp(desired.z, h.z - innerZ, h.z + innerZ);
    desired.y = THREE.MathUtils.clamp(desired.y, 0.6, h.cfg.h - 0.85);
    target.x = THREE.MathUtils.clamp(target.x, h.x - innerX, h.x + innerX);
    target.z = THREE.MathUtils.clamp(target.z, h.z - innerZ, h.z + innerZ);
    target.y = Math.min(target.y, h.cfg.h - 0.8);
  }
  if (!player.focus) desired = constrainMallCamera(squirrel.position.clone().add(v(0, 0.28, 0)), desired);
  const damp =
    1 -
    Math.exp(-dt * (player.inDuct ? 11 : player.inHospital ? 9.5 : player.focus ? 17 : airborneCameraRate()));
  if (player.inDuct) {
    // Camera rides the tunnel centerline: don't interpolate across solid corners.
    camPos.copy(desired);
    lookPoint.lerp(target, 1 - Math.exp(-dt * 13));
    cameraHardCut = false;
  } else if (cameraHardCut) {
    camPos.copy(desired);
    lookPoint.copy(target);
    cameraHardCut = false;
  } else {
    camPos.lerp(desired, damp);
    lookPoint.lerp(target, damp);
  }
  if (!player.inHospital && !player.inSewer && !player.inDuct && !player.focus)
    camPos.y = Math.max(camPos.y, squirrelSurfaceAt(camPos.x, camPos.z) + 0.4);
  if (!player.focus) camPos.copy(constrainMallCamera(squirrel.position.clone().add(v(0, 0.28, 0)), camPos));
  camera.position.copy(camPos);
  camera.lookAt(lookPoint);
  camera.near = player.inDuct ? 0.065 : 0.12;
  const fov = player.inDuct
    ? 66
    : player.focus
      ? 61
      : player.committedAirborne
        ? 74
        : player.moveSpeed > 12
          ? 68
          : 62;
  camera.fov = THREE.MathUtils.lerp(camera.fov, fov, 1 - Math.exp(-dt * 9));
  camera.updateProjectionMatrix();
  updateAimPath();
  updateHatchLanding();
}
function airborneCameraRate() {
  return player.committedAirborne ? 12 : 8.5;
}

function updateCars(dt) {
  for (const c of cars) {
    if (!c.moving) continue;
    const p = c.group.position,
      dir = c.dir,
      isEastWest = c.routeAxis === "x";
    let danger = false;
    for (const n of humanoids) {
      if (!n.visible || n.hospital) continue;
      const q = n.root.position,
        along = (isEastWest ? q.x - p.x : q.z - p.z) * dir;
      if (Math.abs(isEastWest ? q.z - p.z : q.x - p.x) < 3.3 && along > -3.5 && along < 16) {
        danger = true;
        break;
      }
    }
    // Vehicles remain in their lanes and yield to larger traffic as well as pedestrians.
    if (!danger)
      danger = trafficVehicleAhead(
        c.group,
        isEastWest ? dir : 0,
        isEastWest ? 0 : dir,
        9 + c.speed * 0.65,
        1.2,
      );
    const desired = danger ? 0 : c.velocity;
    c.speed = THREE.MathUtils.lerp(c.speed, desired, 1 - Math.exp(-dt * (danger ? 9 : 1.3)));
    const next = p.clone();
    if (isEastWest) next.x += dir * c.speed * dt;
    else next.z += dir * c.speed * dt;
    if (
      !humanoids.some(
        (n) => n.visible && Math.hypot(n.root.position.x - next.x, n.root.position.z - next.z) < 3.1,
      )
    )
      p.copy(next);
    else c.speed = 0;
    if (isEastWest) {
      if (p.x > 660) p.x = 280;
      if (p.x < 280) p.x = 660;
    } else {
      if (p.z > 260) p.z = -260;
      if (p.z < -260) p.z = 260;
    }
    p.y = terrainHeight(p.x, p.z) + 0.04;
  }
}

// ============================================================================
// v3.8 — Two street vehicles; deliberately independent from the pedestrian,
// ambulance and general car schedulers. Each has one world-space position owner.
// - Ice cream van: gently looping a central two-lane neighborhood street with
//   actual customer stops and an animated service awning.
// - Heritage trolley: a two-ended streetcar following dedicated rails down
//   the eastern commercial boulevard with station dwell and sliding doors.
// Both register honest rectangular hitboxes and yield to people ahead.
// ============================================================================
const streetVehicles = [];
const StreetVehicleLogic = {
  approach(value, goal, amount) {
    return value < goal ? Math.min(goal, value + amount) : Math.max(goal, value - amount);
  },
  shortestSigned(angle) {
    return Math.atan2(Math.sin(angle), Math.cos(angle));
  },
  closeEnough(x, z, ob, r) {
    return Math.hypot(x - ob.position.x, z - ob.position.z) < r;
  },
  seesHazard(x, z, dx, dz, range, halfWidth, exclude) {
    // Body heading, not camera angle, determines a vehicle's braking corridor.
    const len = Math.hypot(dx, dz) || 1,
      fx = dx / len,
      fz = dz / len;
    const candidate = (qx, qz, r) => {
      const px = qx - x,
        pz = qz - z,
        along = px * fx + pz * fz;
      return along > -0.55 && along < range + r && Math.abs(px * fz - pz * fx) < halfWidth + r;
    };
    if (
      player.alive &&
      !player.inSewer &&
      !player.inHospital &&
      player.pos.y < 4.8 &&
      candidate(player.pos.x, player.pos.z, 0.56)
    )
      return true;
    for (const n of humanoids) {
      if (!n.visible || n.injured || n.hospital || !n.root.visible) continue;
      if (candidate(n.root.position.x, n.root.position.z, 0.4)) return true;
    }
    for (const c of cars) {
      if (!c.group.visible || c.group === exclude) continue;
      if (candidate(c.group.position.x, c.group.position.z, 1.15)) return true;
    }
    for (const v of streetVehicles) {
      if (v.group === exclude || !v.group.visible) continue;
      if (candidate(v.group.position.x, v.group.position.z, v.width * 0.5)) return true;
    }
    return trafficVehicleAhead(exclude, fx, fz, range, halfWidth);
  },
};
function shopVehicleWheel(parent, x, z, r) {
  const mount = new THREE.Group();
  parent.add(mount);
  mount.position.set(x, r, z);
  const wheel = cyl(r, r, 0.2, M.rubber, 0, 0, 0, mount, 14);
  wheel.rotation.z = PI / 2;
  const hub = cyl(r * 0.42, r * 0.42, 0.22, M.metal, 0, 0, 0, mount, 12);
  hub.rotation.z = PI / 2;
  return mount;
}
function makeIceCreamVan() {
  const root = new THREE.Group();
  scene.add(root);
  const chassis = mat("#435b61", 0.52, 0.35),
    cream = mat("#fff2dc"),
    mint = mat("#82c9bb"),
    pink = mat("#e5a0af");
  // Mobile street vendor: recognizable food truck silhouette, short cab, high
  // rear box, small awning and selling window on the sidewalk-facing side.
  box(3.35, 0.4, 6.55, chassis, 0, 0.68, 0, root);
  box(3.2, 2.75, 4.08, cream, 0, 2.0, -1.05, root);
  box(3.07, 0.18, 4.15, mint, 0, 3.48, -1.05, root);
  box(3.13, 2.1, 2.42, mint, 0, 1.81, 2.09, root);
  box(2.88, 0.22, 2.51, cream, 0, 2.88, 2.03, root);
  box(2.57, 0.9, 0.055, M.glass, 0, 2.13, 3.34, root);
  for (const side of [-1, 1]) {
    box(0.07, 0.87, 1.54, M.glass, side * 1.58, 2.1, 2.13, root);
    box(0.09, 0.22, 3.45, pink, side * 1.61, 1.11, -0.69, root);
  }
  // The serving hatch faces the sidewalk on either leg (-local X).
  box(0.09, 1.25, 2.65, mat("#c1deeb"), -1.64, 2.28, -1.04, root);
  const hatchPivot = new THREE.Group();
  hatchPivot.position.set(-1.68, 2.88, -1.04);
  root.add(hatchPivot);
  box(0.1, 0.15, 2.94, mint, -0.1, 0, 0, hatchPivot);
  box(0.1, 0.77, 2.88, pink, -0.13, -0.38, 0, hatchPivot);
  box(0.32, 0.15, 2.87, cream, -1.77, 1.55, -1.04, root); // lower counter
  const logo = signCanvas("SCOOP MOBILE", "#428e93", "#fff7df");
  for (const sx of [-1, 1]) box(0.075, 1.04, 3.27, logo, sx * 1.68, 2.67, -1.12, root);
  box(2.85, 0.72, 0.1, signCanvas("ICE CREAM", "#e4a4b4", "#fffdf0"), 0, 3.1, 3.37, root);
  // Roof-top soft-serve sculpture; geometry is lightweight and not a light.
  const cone = cyl(0.04, 0.47, 1.14, mat("#bf8b55"), 0, 4.19, -0.95, root, 12);
  cone.rotation.z = PI;
  const scoop = ball(0.63, pink, 0, 4.94, -0.95, root);
  scoop.scale.set(1, 0.83, 1);
  const siren = ball(0.16, mat("#f5d57c"), 0, 3.03, 3.09, root);
  for (const z of [-2.17, 2.28])
    for (const side of [-1, 1]) {
      box(0.2, 0.13, 0.24, mat("#dae5d9"), side * 1.17, 0.92, z + (z > 0 ? 0.99 : -1.13), root);
    }
  const wheels = [];
  for (const z of [-2.35, 2.25])
    for (const x of [-1.68, 1.68]) wheels.push(shopVehicleWheel(root, x, z, 0.54));
  // Continuous, gentle U-turns stay inside the original N/S arterial roadway.
  const routePoints = [
    [-5.7, -120],
    [-5.7, -45],
    [-5.7, 45],
    [-5.7, 120],
    [-4.0, 125],
    [0, 127],
    [4.0, 125],
    [5.7, 120],
    [5.7, 45],
    [5.7, -45],
    [5.7, -120],
    [4, -125],
    [0, -127],
    [-4, -125],
  ].map(([x, z]) => v(x, 0, z));
  const curve = new THREE.CatmullRomCurve3(routePoints, true, "centripetal");
  const length = curve.getLength();
  const stops = [0.16, 0.59].map((t) => t * length).sort((a, b) => a - b);
  const obj = {
    group: root,
    width: 3.35,
    length: 6.55,
    height: 3.58,
    type: "ice-cream",
    curve,
    routeLength: length,
    distance: 0,
    speed: 0,
    cruise: 7.6,
    stops,
    nextStop: 0,
    dwell: 0,
    deliveries: 0,
    hatchPivot,
    wheels,
    phase: 0,
  };
  streetVehicles.push(obj);
  tallVehicles.push({ group: root, width: obj.width, length: obj.length, height: obj.height });
  const first = curve.getPointAt(0);
  root.position.set(first.x, terrainHeight(first.x, first.z) + 0.08, first.z);
  const tangent = curve.getTangentAt(0.002);
  root.rotation.y = Math.atan2(tangent.x, tangent.z);
  return obj;
}
function makeHeritageTrolley() {
  const root = new THREE.Group();
  scene.add(root);
  root.rotation.y = PI / 2;
  const cream = mat("#f5e8cb"),
    burgundy = mat("#a54b4a"),
    trim = mat("#d7bd6e"),
    steel = mat("#525960");
  // Slab-mounted heritage electric streetcar (not a vehicle teleporter).
  box(3.5, 0.34, 11.0, steel, 0, 0.71, 0, root);
  box(3.5, 2.9, 10.65, cream, 0, 2.2, 0, root);
  box(3.54, 0.58, 10.72, burgundy, 0, 1.23, 0, root);
  box(3.56, 0.49, 10.72, burgundy, 0, 3.45, 0, root);
  box(3.71, 0.22, 10.97, trim, 0, 3.85, 0, root);
  box(3.2, 0.12, 10.54, cream, 0, 4.08, 0, root);
  // Rounded roof equipment and a folding pantograph.
  for (const zz of [-2.4, 2.4]) box(1.72, 0.23, 2.0, steel, 0, 4.26, zz, root);
  for (const side of [-1, 1]) {
    span(v(side * 0.72, 4.2, -0.85), v(side * 0.1, 5.55, 0.26), 0.045, 0.045, steel, root);
    span(v(side * 0.1, 5.55, 0.26), v(side * 0.7, 4.22, 1.11), 0.045, 0.045, steel, root);
  }
  box(1.42, 0.09, 0.17, steel, 0, 5.59, 0.26, root);
  // Two-ended cab windows; reversing requires no sudden 180° vehicle rotation.
  for (const sign of [-1, 1]) {
    box(2.74, 1.55, 0.07, M.glass, 0, 2.55, sign * 5.37, root);
    box(2.5, 0.45, 0.1, signCanvas("CITY TROLLEY", "#824044", "#f9ebcb"), 0, 3.58, sign * 5.46, root);
    for (const side of [-1, 1]) ball(0.17, mat("#f6e4ad"), side * 1.12, 1.18, sign * 5.47, root);
  }
  // Repeating side windows and passenger silhouettes; avoid transparent double-walls.
  for (const side of [-1, 1])
    for (let i = -3; i <= 3; i++) {
      const z = i * 1.35;
      if (Math.abs(z) < 1.0) continue;
      box(0.075, 1.42, 1.11, M.glass, side * 1.77, 2.61, z, root);
      box(0.085, 0.07, 1.16, trim, side * 1.82, 1.87, z, root);
    }
  const passengerSkin = mat("#c49470"),
    passengerCoats = [mat("#668277"), mat("#62728d"), mat("#8b6765")];
  for (let i = 0; i < 5; i++) {
    const z = -3.6 + i * 1.8;
    box(0.65, 0.89, 0.65, passengerCoats[i % 3], i % 2 ? -0.82 : 0.82, 1.59, z, root);
    ball(0.3, passengerSkin, i % 2 ? -0.82 : 0.82, 2.24, z, root);
  }
  const doors = [];
  for (const side of [-1, 1])
    for (const sign of [-1, 1]) {
      const door = box(0.11, 2.42, 0.78, burgundy, side * 1.81, 2.03, sign * 0.4, root);
      box(0.13, 1.13, 0.56, M.glass, 0, 0.35, 0, door);
      doors.push({ door, side, sign, homeZ: sign * 0.4 });
    }
  const wheels = [];
  for (const x of [-1.75, 1.75])
    for (const z of [-3.48, -2.4, 2.4, 3.48]) wheels.push(shopVehicleWheel(root, x, z, 0.4));
  // Track following the existing 26-unit wide commercial road. Both rails and
  // stops are outside the pedestrian sidewalks; no street-center support poles.
  const railZ = 8.65;
  const metal = mat("#6b6d65", 0.28, 0.56),
    tie = mat("#777165");
  for (const rz of [railZ - 1.27, railZ + 1.27]) districtRibbon("x", rz, 0.12, 263, 675, metal, 0.15);
  for (let x = 265; x <= 669; x += 3.2) box(0.14, 0.08, 2.82, tie, x, terrainHeight(x, railZ) + 0.105, railZ);
  // Low stops/bench fixtures outside the rail corridor.
  for (const x of [310, 465, 616]) {
    const y = terrainHeight(x, 20.2);
    box(9.7, 0.12, 1.95, mat("#bab8ad"), x, y + 0.14, 20.2);
    box(2.4, 0.18, 0.6, trim, x + 2.4, y + 0.85, 20.6);
    for (const ox of [-0.93, 0.93]) box(0.13, 0.62, 0.13, steel, x + 2.4 + ox, y + 0.5, 20.6);
    cyl(0.075, 0.075, 3.1, steel, x - 2.9, y + 1.57, 20.75);
    box(2.6, 0.52, 0.15, signCanvas("TROLLEY STOP", "#91504b", "#fff2d8"), x - 2.9, y + 3.03, 20.75);
  }
  const car = {
    group: root,
    width: 3.5,
    length: 11.0,
    height: 4.12,
    type: "trolley",
    trackZ: railZ,
    schedule: [310, 465, 616, 657, 616, 465, 310, 283],
    nextStop: 0,
    speed: 0,
    cruise: 10.7,
    dwell: 0,
    doors,
    wheels,
    phase: 0,
    lastBell: 0,
  };
  root.position.set(283, terrainHeight(283, railZ) + 0.05, railZ);
  streetVehicles.push(car);
  tallVehicles.push({ group: root, width: car.width, length: car.length, height: car.height });
  return car;
}
const iceCreamTruck = makeIceCreamVan();
const neighborhoodTrolley = makeHeritageTrolley();
function updateStreetVehicles(dt) {
  const step = Math.min(0.055, Math.max(0, dt));
  const truck = iceCreamTruck;
  // The van is paced in real distance around its closed curve. The service
  // stop waits in-place and reopens only on the next lap (not every frame).
  if (truck.dwell > 0) {
    truck.dwell = Math.max(0, truck.dwell - step);
    truck.speed = 0;
  } else {
    const stopDistance = truck.stops[truck.nextStop];
    const distToStop =
      stopDistance >= truck.distance
        ? stopDistance - truck.distance
        : truck.routeLength - truck.distance + stopDistance;
    const pt = truck.curve.getPointAt((truck.distance / truck.routeLength) % 1),
      tan = truck.curve.getTangentAt((truck.distance / truck.routeLength) % 1);
    const danger = StreetVehicleLogic.seesHazard(pt.x, pt.z, tan.x, tan.z, 7.7, 1.85, truck.group);
    const desired = danger ? 0 : Math.min(truck.cruise, Math.sqrt(Math.max(0, 2 * 5.0 * distToStop)));
    truck.speed = StreetVehicleLogic.approach(
      truck.speed,
      desired,
      (desired < truck.speed ? 11 : 4.5) * step,
    );
    const advance = truck.speed * step;
    if (!danger && distToStop <= Math.max(0.35, advance + 0.35)) {
      truck.distance = stopDistance;
      truck.speed = 0;
      truck.dwell = 5.8 + (truck.deliveries % 3);
      truck.deliveries++;
      truck.nextStop = (truck.nextStop + 1) % truck.stops.length;
      if (playing) fx(760, 0.08, "sine", 0.019);
    } else truck.distance = (truck.distance + advance) % truck.routeLength;
  }
  const progress = (truck.distance / truck.routeLength) % 1;
  const truckAt = truck.curve.getPointAt(progress),
    truckTangent = truck.curve.getTangentAt(progress);
  truck.group.position.set(truckAt.x, terrainHeight(truckAt.x, truckAt.z) + 0.07, truckAt.z);
  const heading = Math.atan2(truckTangent.x, truckTangent.z);
  truck.group.rotation.y +=
    StreetVehicleLogic.shortestSigned(heading - truck.group.rotation.y) * Math.min(1, step * 5.4);
  for (const wheel of truck.wheels) wheel.rotation.x += (truck.speed * step) / 0.54;
  const truckOpen = truck.dwell > 0 ? 1 : 0;
  truck.phase += (truckOpen - truck.phase) * Math.min(1, step * 3.7);
  truck.hatchPivot.rotation.z = -truck.phase * 0.4;
  // The tram serves stations in both directions, with actual station pauses.
  const tram = neighborhoodTrolley;
  if (tram.dwell > 0) {
    tram.dwell = Math.max(0, tram.dwell - step);
    tram.speed = 0;
  } else {
    const destination = tram.schedule[tram.nextStop];
    const delta = destination - tram.group.position.x;
    const dir = Math.sign(delta) || 1;
    const danger = StreetVehicleLogic.seesHazard(
      tram.group.position.x,
      tram.trackZ,
      dir,
      0,
      11.0,
      1.85,
      tram.group,
    );
    const cap = Math.min(tram.cruise, Math.sqrt(Math.max(0, 2 * 6.2 * Math.abs(delta))));
    const desired = danger ? 0 : cap;
    tram.speed = StreetVehicleLogic.approach(tram.speed, desired, (desired < tram.speed ? 12 : 4.6) * step);
    const move = Math.min(Math.abs(delta), tram.speed * step) * dir;
    tram.group.position.x += move;
    if (!danger && Math.abs(destination - tram.group.position.x) < 0.25) {
      tram.group.position.x = destination;
      tram.speed = 0;
      tram.dwell = destination === 283 || destination === 657 ? 2.3 : 4.2;
      tram.nextStop = (tram.nextStop + 1) % tram.schedule.length;
      if (playing) fx(610, 0.13, "sine", 0.023);
    }
  }
  tram.group.position.y = terrainHeight(tram.group.position.x, tram.trackZ) + 0.05;
  for (const w of tram.wheels) w.rotation.x += (tram.speed * step) / 0.4;
  const doorTarget = tram.dwell > 0 ? 1 : 0;
  tram.phase += (doorTarget - tram.phase) * Math.min(1, step * 4);
  for (const d of tram.doors) d.door.position.z = d.homeZ + d.sign * tram.phase * 0.48;
}
function streetVehicleAt(x, z, extra = 0) {
  for (const v of streetVehicles) {
    const p = v.group.position,
      a = v.group.rotation.y,
      dx = x - p.x,
      dz = z - p.z;
    const localX = Math.cos(a) * dx - Math.sin(a) * dz;
    const localZ = Math.sin(a) * dx + Math.cos(a) * dz;
    if (Math.abs(localX) < v.width / 2 + extra && Math.abs(localZ) < v.length / 2 + extra) return v;
  }
  return null;
}
// ============================================================================

function resize() {
  resizeGraphics();
}
window.addEventListener("resize", resize);
// Fixed capped dt for animation stability, plus default orbit and idle NPC simulation behind menu.
// --- v0.7 ACTIVE SYSTEMS: no changes to original bite/pepper/Power rules. ---
let gamePaused = false,
  idleTime = 0,
  predatorWarning = 0,
  predatorKind = "",
  lastMovement = v(-36, 0.31, -36),
  northAlertCooldown = 0,
  nearShop = false;
const helpBox = $("hints"),
  helpToggle = $("helpToggle");
let helpTouched = false;
function syncHelpToggle() {
  const collapsed = helpBox.classList.contains("collapsed");
  helpToggle.setAttribute("aria-expanded", String(!collapsed));
  if (collapsed) {
    helpToggle.style.top = "auto";
    helpToggle.style.bottom = "23px";
    return;
  }
  const css = getComputedStyle(helpBox),
    panelBottom = parseFloat(css.bottom) || 24;
  const top = innerHeight - panelBottom - helpBox.offsetHeight;
  // Keep the toggle just ABOVE the entire responsive controls card, not over its text.
  helpToggle.style.bottom = "auto";
  helpToggle.style.top = Math.max(7, top - helpToggle.offsetHeight - 8) + "px";
  helpToggle.style.left = Math.max(10, helpBox.getBoundingClientRect().left) + "px";
}
function toggleHelp(force) {
  helpTouched = true;
  helpBox.classList.toggle(
    "collapsed",
    force === undefined ? !helpBox.classList.contains("collapsed") : !force,
  );
  syncHelpToggle();
}
helpToggle.addEventListener("click", () => toggleHelp());
window.addEventListener("resize", syncHelpToggle);
new ResizeObserver(syncHelpToggle).observe(helpBox);
requestAnimationFrame(syncHelpToggle);
$("restartGame").addEventListener("click", () => window.location.reload());

function sewerClosest(pos) {
  const a = v(SEWER_X1, 0, SEWER_Z1),
    c = v(SEWER_X1, 0, SEWER_Z2),
    b = v(SEWER_X2, 0, SEWER_Z2);
  const p = v(pos.x, 0, pos.z);
  const proj = (u, w) => {
    const d = w.clone().sub(u);
    return u.clone().addScaledVector(d, THREE.MathUtils.clamp(p.clone().sub(u).dot(d) / d.lengthSq(), 0, 1));
  };
  const q1 = proj(a, c),
    q2 = proj(c, b);
  return p.distanceTo(q1) <= p.distanceTo(q2) ? q1 : q2;
}
function constrainSewer(previous) {
  const q = sewerClosest(player.pos),
    d = Math.hypot(player.pos.x - q.x, player.pos.z - q.z);
  if (d > 2.2) {
    player.pos.x = q.x + ((player.pos.x - q.x) * 2.2) / d;
    player.pos.z = q.z + ((player.pos.z - q.z) * 2.2) / d;
  }
}
function teleportSewer(exit) {
  const at = exit === "b" ? sewerB : sewerA;
  player.rail = null;
  player.inSewer = !player.inSewer;
  player.vel.set(0, 0, 0);
  player.attackWindow = 0;
  player.grounded = true;
  player.committedAirborne = false;
  player.pos.set(
    at.x,
    player.inSewer ? sewerFloorY + 0.25 : terrainHeight(at.x, at.z) + 0.3,
    at.z + (player.inSewer ? (exit === "b" ? -0.55 : -0.85) : 2.5),
  );
  cameraHardCut = true;
  idleTime = 0;
  flash(
    player.inSewer
      ? "SEWER ENTRY · Follow the L-shaped tunnel. Fashion stand at the corner."
      : "BACK ABOVE GROUND · Eight peppers are still one-time only.",
    3.4,
  );
}
function handleInteraction() {
  if (handleMallInteraction()) return true;
  if (handleHospitalInteraction()) return true;
  const p = player.pos;
  if (player.inSewer) {
    if (Math.hypot(p.x - standPoint.x, p.z - standPoint.z) < 6) {
      buySelectedFashion();
      return true;
    }
    if (Math.hypot(p.x - sewerA.x, p.z - sewerA.z) < 5) {
      teleportSewer("a");
      return true;
    }
    if (Math.hypot(p.x - sewerB.x, p.z - sewerB.z) < 5) {
      teleportSewer("b");
      return true;
    }
    flash("Follow the L-shaped tunnel. E at a grate or the fashion stand.", 1.9);
    return true;
  }
  if (
    Math.hypot(p.x - sewerA.x, p.z - sewerA.z) < 5 &&
    Math.abs(p.y - terrainHeight(sewerA.x, sewerA.z)) < 3
  ) {
    teleportSewer("a");
    return true;
  }
  if (
    Math.hypot(p.x - sewerB.x, p.z - sewerB.z) < 5 &&
    Math.abs(p.y - terrainHeight(sewerB.x, sewerB.z)) < 3
  ) {
    teleportSewer("b");
    return true;
  }
  return false;
}
// Small collection of recognizable, independently moving yard dogs.
const dogs = [];
const dogFur = [mat("#956e51"), mat("#b79e74"), mat("#3e3a33"), mat("#e0c8a1")];
for (const [i, x, z] of [
  [0, 203, 363],
  [1, 240, 402],
  [2, 98, 311],
  [3, 55, 345],
]) {
  const yy = terrainHeight(x, z),
    body = new THREE.Group();
  body.position.set(x, yy, z);
  scene.add(body);
  const fur = dogFur[i];
  let torso = ball(0.79, fur, 0, 0.8, 0, body);
  torso.scale.set(0.8, 0.67, 1.5);
  ball(0.49, fur, 0, 1.12, 0.84, body);
  for (const xx of [-0.38, 0.38]) {
    ball(0.23, dogFur[(i + 1) % 4], xx, 1.28, 1.0, body).scale.set(0.7, 1.5, 0.5);
    for (const zz of [-0.55, 0.55]) cyl(0.12, 0.15, 0.72, fur, xx, 0.39, zz, body, 7);
  }
  ball(0.18, M.black, 0, 0.98, 1.28, body);
  let tail = span(v(0, 0.9, -0.9), v(0, 1.65, -1.4), 0.1, 0.025, fur, body);
  dogs.push({ body, x, z, yy, i, phase: i * 2.1, barkCooldown: 0 });
}
// Police patrol uses a normal car in the existing vehicle system, but manages its own stops.
const patrolCar = makeCar(95, -5.6, "#e0e6de", PI / 2, false);
const patrolVehicle = cars.at(-1);
patrolCar.position.y = terrainHeight(95, -5.6) + 0.05;
box(1.1, 0.25, 0.62, mat("#274a79"), 0, 2.17, 0, patrolCar);
box(1.1, 0.23, 0.24, mat("#cf312d"), 0, 2.19, 0.35, patrolCar);
const officer = new THREE.Group();
scene.add(officer);
officer.visible = false;
const copBlue = mat("#324b70"),
  copSkin = mat("#c99870");
box(0.78, 1.5, 0.52, copBlue, 0, 1.8, 0, officer);
ball(0.34, copSkin, 0, 2.91, 0, officer);
box(0.8, 0.22, 0.65, mat("#202c41"), 0, 3.22, 0, officer);
box(0.21, 0.18, 0.15, mat("#e6c46f"), 0, 2.12, 0.3, officer);
for (const side of [-1, 1]) {
  span(v(side * 0.29, 1.2, 0), v(side * 0.32, 0.12, 0), 0.16, 0.11, mat("#343c4d"), officer);
  span(v(side * 0.58, 2.3, 0), v(side * 0.76, 1.36, 0.05), 0.13, 0.12, copBlue, officer);
}
const copBaton = span(v(0.74, 1.45, 0.11), v(0.83, 0.56, 0.8), 0.08, 0.07, mat("#45403e"), officer);
const copState = { out: false, alert: 0, hitCooldown: 0, phase: 0, patrolDir: 1, windup: 0, stun: 0 };
function onSuccessfulBite(n) {
  // A bite triggers medical response; police are probabilistic, or called by poster witnesses.
  if (n.kickWindup > 0) {
    n.kickWindup = 0;
    n.kickCooldown = 12;
  }
}
function dispatchCop(reason) {
  if (copState.out) return;
  copState.out = true;
  copState.alert = 23;
  officer.visible = true;
  officer.position.copy(patrolCar.position).add(v(0, 0, 3.4));
  officer.position.y = terrainHeight(officer.position.x, officer.position.z);
  flash(`POLICE OFFICER! ${reason} · Baton only.`, 3.3);
}
function officerBatonContact(p, knock = 12) {
  const away = player.pos.clone().sub(p).setY(0);
  if (away.lengthSq() < 0.001) away.set(Math.sin(player.yaw), 0, Math.cos(player.yaw));
  away.normalize();
  player.vel.x = away.x * knock;
  player.vel.z = away.z * knock;
  player.vel.y = Math.max(player.vel.y, 3.1);
  player.rail = null;
  player.grounded = false;
  player.points = Math.max(0, player.points - 19);
  refreshPowerUI();
  fx(180, 0.18, "square", 0.05);
}
// A chase is fast, but a visible baton wind-up keeps a dodge possible.
function updateCop(dt) {
  if (player.inSewer) return;
  if (!copState.out) {
    patrolCar.position.x += dt * 10.5 * copState.patrolDir;
    if (patrolCar.position.x > 645) {
      copState.patrolDir = -1;
      patrolCar.rotation.y = -PI / 2;
    }
    if (patrolCar.position.x < 55) {
      copState.patrolDir = 1;
      patrolCar.rotation.y = PI / 2;
    }
    patrolCar.position.y = terrainHeight(patrolCar.position.x, patrolCar.position.z) + 0.05;
    return;
  }
  copState.alert = Math.max(0, copState.alert - dt);
  copState.hitCooldown = Math.max(0, copState.hitCooldown - dt);
  copState.stun = Math.max(0, copState.stun - dt);
  const delta = player.pos.clone().sub(officer.position).setY(0),
    dist = delta.length();
  const canEngage = !player.inSewer && !activeHouseInterior && player.pos.y - officer.position.y < 2.4;
  if (copState.stun > 0) {
    copState.windup = 0;
    copBaton.rotation.x = -0.8;
  } else if (copState.windup > 0) {
    copState.windup -= dt;
    copBaton.rotation.x = -1.2 + Math.sin(time * 15) * 0.2;
    if (copState.windup <= 0) {
      copState.windup = 0;
      copState.hitCooldown = 2.0;
      if (canEngage && dist < 2.85) {
        officerBatonContact(officer.position, 14);
        flash("POLICE BATON! Dodge the wind-up or ambush from behind.", 2.4);
      } else if (dist < 6) flash("The officer swung and missed.", 1.35);
    }
  } else {
    if (copState.alert > 0 && canEngage && dist > 2.55 && dist < 86) {
      const prev = officer.position.clone();
      officer.position.addScaledVector(delta.normalize(), Math.min(dist - 2.5, dt * 6.15));
      keepEmergencyActorsOutside(officer.position, prev);
    }
    if (copState.alert > 0 && canEngage && dist < 3.6 && copState.hitCooldown <= 0) {
      copState.windup = 0.54;
      flash("The officer raises a baton — jump or retreat!", 1.45);
    }
    copBaton.rotation.x = Math.sin(time * 10) * 0.57;
  }
  officer.position.y = terrainHeight(officer.position.x, officer.position.z);
  if (dist > 0.001) officer.rotation.y = turnToward(officer.rotation.y, Math.atan2(delta.x, delta.z), 9, dt);
  if (copState.alert <= 0 || dist > 155) {
    copState.out = false;
    officer.visible = false;
    copState.windup = 0;
  }
}
// Police are not magically bite-proof: stealth and height can overcome even
// the toughest officers, but a direct approach is exceptionally unlikely.
function tryPolicePounce() {
  if (player.attackWindow <= 0 || player.inSewer || player.inHospital || activeHouseInterior) return false;
  const candidates = [];
  if (copState.out && officer.visible)
    candidates.push({ g: officer, owner: copState, name: "patrol officer" });
  for (const o of incidentPoliceOfficers)
    if (o.g.visible) candidates.push({ g: o.g, owner: o, name: "responding officer" });
  for (const o of stationReinforcements)
    if (o.g.visible) candidates.push({ g: o.g, owner: o, name: "station officer" });
  for (const o of precinctOfficers)
    if (o.g.visible) candidates.push({ g: o.g, owner: o, name: "station guard" });
  for (const c of candidates) {
    const dx = player.pos.x - c.g.position.x,
      dz = player.pos.z - c.g.position.z;
    const distance = Math.hypot(dx, dz),
      dy = player.pos.y - c.g.position.y;
    if (distance > 1.85 || dy < -0.3 || dy > 2.8) continue;
    const toSquirrel = v(dx / (distance || 1), 0, dz / (distance || 1));
    const forward = v(Math.sin(c.g.rotation.y), 0, Math.cos(c.g.rotation.y));
    const behind = toSquirrel.dot(forward) < -0.3;
    const surprised = behind || dy > 1.35 || (c.owner.stun || 0) > 0;
    const chance = surprised ? 0.88 : 0.035;
    const success = Math.random() < chance;
    player.attackWindow = 0;
    player.attackTarget = { officer: true };
    if (success) {
      c.owner.stun = 5.5;
      c.owner.windup = 0;
      c.owner.hitCooldown = 6;
      if (c.owner === copState) copState.alert = Math.max(copState.alert, 30);
      player.points += 130;
      player.hits++;
      squirrelCoins += 10;
      totalCoinsEarned += 10;
      player.inactiveSeconds = 0;
      grantInfectionBite({});
      refreshPowerUI();
      player.vel.multiplyScalar(0.14);
      player.vel.y = 2.6;
      flash(`SURPRISE BITE! ${c.name} stunned — escape before backup arrives.`, 2.6);
      fx(180, 0.23, "triangle", 0.05);
    } else {
      c.owner.windup = 0;
      c.owner.hitCooldown = 0;
      player.vel.x = toSquirrel.x * 8;
      player.vel.z = toSquirrel.z * 8;
      player.vel.y = 3.2;
      flash(`${c.name} anticipated your attack!`, 1.9);
    }
    return true;
  }
  return false;
}
// No instant NPC kicking. Brave characters telegraph a readable wind-up first.
function handleKickWindup(n, dt, dist, spotted) {
  // A defensive witness keeps the role assigned at the injury scene. Don't let
  // the scene updater force that person back into "flee" mid-kick.
  const committed = (n.defenseUntil || 0) > time;
  const brave = n.personality === "brave";
  n.kickCooldown = Math.max(0, (n.kickCooldown || 0) - dt);
  if (n.kickWindup > 0) {
    n.kickWindup = Math.max(0, n.kickWindup - dt);
    n.state = "kick";
    n.legs[1].rotation.x = -1.25 - (1 - n.kickWindup) * 0.7;
    n.facing = Math.atan2(player.pos.x - n.root.position.x, player.pos.z - n.root.position.z);
    if (n.kickWindup === 0) {
      n.kickCooldown = committed ? 2.6 : 6.0;
      n.state = committed ? "defend" : "flee";
      n.alert = 7;
      const delta = player.pos.clone().sub(n.root.position).setY(0);
      const away = delta.lengthSq() > 0.001 ? delta.normalize() : v(1, 0, 0);
      const facing = v(Math.sin(n.facing), 0, Math.cos(n.facing));
      if (
        dist < 2.65 &&
        player.pos.y - n.root.position.y < 1.6 &&
        facing.dot(away) > 0.55 &&
        player.attackWindow <= 0
      ) {
        officerBatonContact(n.root.position, 11);
        flash(`${n.name} kicked the squirrel away!`, 1.65);
      } else if (dist < 5.1) flash(`${n.name}'s kick missed — move away or counter.`, 1.1);
    }
    return;
  }
  const ready =
    (committed || (brave && (n.witnessUntil || 0) > time)) &&
    !n.doorEscape &&
    !n.injured &&
    n.kickCooldown <= 0 &&
    dist < 3.7 &&
    player.pos.y - n.root.position.y < 1.7 &&
    player.attackWindow <= 0 &&
    spotted &&
    !player.inSewer;
  if (ready) {
    n.kickWindup = 0.58;
    n.state = "kick";
    n.speed = 0;
    if (n.sayCooldown <= 0) say(n, pick(["Get back!", "I said get away!", "Back off!"]));
    if (dist < 6.1) flash(`${n.name} prepares to kick — dodge or counter!`, 1.2);
  }
}
// Independent 13-minute *movement* watchdog with a one-second warning and contextual predators.
function predatorForPlace() {
  if (player.inHospital) return ["hospital security guard", "Footsteps close in at the hospital entrance"];
  if (player.inSewer) return ["small alligator", "A low hiss and a ripple in the sewer water"];
  const inShelter = shelterZones.find(
    (s) =>
      Math.hypot(player.pos.x - s.x, player.pos.z - s.z) < s.r && player.pos.y < terrainHeight(s.x, s.z) + 5,
  );
  if (inShelter?.type === "house" || inShelter?.type === "shed")
    return ["cat", "A low yowl from behind the shelving"];
  if (inShelter) return ["snake", "A sharp hiss from the shadows"];
  return ["eagle", "A broad-winged shadow sweeps across the ground"];
}
function predatorGameOver() {
  if (!player.alive) return;
  player.alive = false;
  playing = false;
  document.exitPointerLock?.();
  $("dangerTitle").textContent = "CAUGHT BY A " + predatorKind.toUpperCase();
  $("dangerText").textContent =
    `You stayed still for thirteen minutes. The ${predatorKind} got you. Final Power: ${player.points}. Successful bites: ${player.hits}. Coins: ${squirrelCoins} · Golden: ${goldCoins}.`;
  $("dangerOverlay").classList.remove("hidden");
}
function updateIdle(dt) {
  if (!player.alive) return;
  const delta = player.pos.distanceTo(lastMovement);
  const activeMovement = delta > 0.035; // actual translation, not merely holding Shift while stationary
  lastMovement.copy(player.pos);
  if (activeMovement) {
    idleTime = 0;
    predatorWarning = 0;
    return;
  }
  idleTime += dt;
  if (!predatorWarning && idleTime >= 779) {
    const [kind, warning] = predatorForPlace();
    predatorKind = kind;
    predatorWarning = 1.03;
    flash(`${warning}...`, 1.15);
    fx(kind === "eagle" ? 310 : 130, 0.6, "sawtooth", 0.043);
    return;
  }
  if (predatorWarning > 0) {
    predatorWarning -= Math.min(dt, 0.1);
    if (predatorWarning <= 0 && idleTime >= 780) predatorGameOver();
  }
}
// The sewer stand sells independently selectable outfit slots; no ten-costume locks.
const wardrobeNames = [
  [
    "Bandana",
    "Fedora",
    "Pointed gnome cap",
    "Straw hat",
    "Red cap",
    "Wheel collar",
    "Toy police hat",
    "Pepper necklace",
    "Golden crown",
    "Skull cowboy hat",
  ],
  [
    "Red hoodie",
    "Trench coat",
    "Mossy vest",
    "Yellow jacket",
    "Flame-print jacket",
    "Denim jacket",
    "Blue police jacket",
    "Striped poncho",
    "Gold jacket",
    "Black skull jacket",
  ],
  [
    "Cargo shorts",
    "Dark jeans",
    "Brown shorts",
    "Plaid shorts",
    "Black shorts",
    "Work pants",
    "Badge shorts",
    "Striped shorts",
    "Royal shorts",
    "Checkered shorts",
  ],
];
const garmentColors = [
  [
    "#b82d23",
    "#655b49",
    "#6f8753",
    "#c3a86b",
    "#d23526",
    "#667b62",
    "#263a5d",
    "#b7442e",
    "#d9bd66",
    "#25262b",
  ],
  [
    "#b8352e",
    "#797667",
    "#6a8752",
    "#d7b557",
    "#d54124",
    "#496681",
    "#334e78",
    "#b77245",
    "#ddc36e",
    "#333337",
  ],
  [
    "#826e53",
    "#34393d",
    "#8b7758",
    "#b9aa78",
    "#232c2b",
    "#858276",
    "#44546c",
    "#aa674a",
    "#cfb46c",
    "#625854",
  ],
];
let closet = { owned: [[], [], []], equipped: [-1, -1, -1] };
try {
  const stored = JSON.parse(localStorage.getItem("spicy-rodents-wardrobe-v1") || "null");
  if (
    Array.isArray(stored?.owned) &&
    stored.owned.length === 3 &&
    stored.owned.every(Array.isArray) &&
    Array.isArray(stored.equipped) &&
    stored.equipped.length === 3
  ) {
    closet.owned = stored.owned.map((a) => [
      ...new Set(a.filter((n) => Number.isInteger(n) && n >= 0 && n < 10)),
    ]);
    closet.equipped = stored.equipped.map((n, i) =>
      Number.isInteger(n) && closet.owned[i].includes(n) ? n : -1,
    );
  }
} catch {}
let selectedStyle = [0, 0, 0],
  fashionSlot = 0;
const wearableGroups = [[], [], []];
for (let slot = 0; slot < 3; slot++)
  for (let k = 0; k < 10; k++) {
    const g = new THREE.Group();
    sqroot.add(g);
    g.visible = false;
    const color = mat(garmentColors[slot][k]);
    if (slot === 0) {
      if ([1, 3, 6, 8, 9].includes(k)) {
        const c = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.39, 0.24, 9), color);
        c.position.set(0, 1.2, 0.56);
        g.add(c);
        cyl(0.52, 0.42, 0.07, color, 0, 1.12, 0.56, g, 11);
      } else if (k === 2) {
        const tip = new THREE.Mesh(new THREE.ConeGeometry(0.32, 0.66, 8), color);
        tip.position.set(0, 1.43, 0.56);
        g.add(tip);
      } else if (k === 7) {
        for (let p = 0; p < 8; p++)
          ball(0.095, color, Math.cos(p * 0.79) * 0.32, 0.61 + Math.sin(p * 0.79) * 0.1, 0.56, g);
      } else {
        box(0.74, 0.18, 0.4, color, 0, 1.09, 0.64, g);
      }
    } else if (slot === 1) {
      const torso = ball(0.51, color, 0, 0.43, -0.02, g);
      torso.scale.set(0.85, 0.66, 1.33);
      for (let s of [-1, 1]) ball(0.17, color, s * 0.35, 0.31, 0.38, g);
    } else {
      for (let s of [-1, 1]) for (let z of [-0.52, 0.51]) box(0.24, 0.2, 0.43, color, s * 0.23, 0.11, z, g);
    }
    wearableGroups[slot][k] = g;
  }
function wearOutfit() {
  for (let slot = 0; slot < 3; slot++)
    for (let k = 0; k < 10; k++) wearableGroups[slot][k].visible = closet.equipped[slot] === k;
}
function saveWardrobe() {
  try {
    localStorage.setItem("spicy-rodents-wardrobe-v1", JSON.stringify(closet));
  } catch (e) {}
}
wearOutfit();
function cycleFashion(slot) {
  if (!player.inSewer || !nearShop) return;
  fashionSlot = slot;
  selectedStyle[slot] = (selectedStyle[slot] + 1) % 10;
  flash(
    `SELECTED ${["HAT", "JACKET", "PANTS"][slot]}: ${wardrobeNames[slot][selectedStyle[slot]]} · E to buy / equip`,
    2.2,
  );
}
function buySelectedFashion() {
  if (totalCoinsEarned < 150) {
    flash(`Fashion stand locked: earn ${150 - totalCoinsEarned} more Squirrel Coins from bites.`, 2.4);
    return;
  }
  const slot = fashionSlot,
    k = selectedStyle[slot],
    name = wardrobeNames[slot][k],
    owned = closet.owned[slot].includes(k),
    isGold = k === 8 && slot <= 2;
  if (!owned) {
    if (isGold && goldCoins < 3) {
      flash("Golden outfit piece costs 3 GOLD coins.", 2.4);
      return;
    }
    if (!isGold && squirrelCoins < 35) {
      flash(`Need 35 coins to buy ${name}.`, 2.5);
      return;
    }
    if (isGold) goldCoins -= 3;
    else squirrelCoins -= 35;
    closet.owned[slot].push(k);
  }
  closet.equipped[slot] = k;
  wearOutfit();
  saveWardrobe();
  refreshPowerUI();
  flash(
    `${owned ? "EQUIPPED" : "PURCHASED"} ${name}! Press ${slot + 1} to choose another ${["hat", "jacket", "pair of pants"][slot]}.`,
    3,
  );
}
// --- v0.8 hospital, duct chase, patient treatment and unobtrusive community infection. ---
let infectionOwn = 0,
  infectionFromSquirrels = 0,
  infectionDisplayed = 0,
  secondsSinceBite = 1e6,
  won = false;
const bittenStaff = new Set(),
  bittenPatients = new Set();
let hospitalChew = null;
const ductEntrance = ductVents[0];
let ductTravel = 0,
  ductViewTravel = 0,
  ductViewAhead = 1;
const hospitalExit = v(HOSP_X, HOSPITAL_FLOOR + 0.2, HOSP_Z - HOSP_D / 2 + 7);
let hospitalTransition = null,
  hospitalDoorHold = 0,
  hospitalDoorOpen = 0;
function updateHospitalDoors(dt) {
  const near = Math.hypot(player.pos.x - HOSP_X, player.pos.z - (HOSP_Z - HOSP_D / 2)) < 15;
  if (near) hospitalDoorHold = Math.max(hospitalDoorHold, 1.5);
  else hospitalDoorHold = Math.max(0, hospitalDoorHold - dt);
  const target = near || hospitalTransition || hospitalDoorHold > 0 ? 1 : 0;
  hospitalDoorOpen = THREE.MathUtils.damp(hospitalDoorOpen, target, 7.5, dt);
  for (const h of hospitalDoorHinges) h.pivot.rotation.y = -h.side * hospitalDoorOpen * 1.36;
  if (!hospitalTransition) return;
  const tr = hospitalTransition;
  tr.t = Math.min(tr.duration, tr.t + dt);
  const progress = tr.t / tr.duration,
    eased = progress * progress * (3 - 2 * progress);
  const next = tr.from.clone().lerp(tr.to, eased);
  player.pos.copy(next);
  player.vel.set(0, 0, 0);
  player.rail = null;
  player.grounded = true;
  if (progress > 0.47) {
    player.inHospital = tr.enter;
    hospitalRoof.visible = !tr.enter;
  }
  if (progress >= 1) {
    player.inHospital = tr.enter;
    hospitalRoof.visible = !tr.enter;
    hospitalTransition = null;
    hospitalDoorHold = 2.4;
  }
}

function infectionReading() {
  return THREE.MathUtils.clamp(infectionOwn + infectionFromSquirrels, 0, 100);
}
function drawInfection() {
  const reading = infectionReading();
  infectionDisplayed = reading;
  $("infectionScore").textContent = reading.toFixed(1) + "%";
  $("infectionFill").style.width = reading + "%";
}
function insideHospitalBuilding(p = player.pos) {
  return (
    p.x >= HOSP_X - HOSP_W / 2 + 2 &&
    p.x <= HOSP_X + HOSP_W / 2 - 2 &&
    p.z >= HOSP_Z - HOSP_D / 2 + 2 &&
    p.z <= HOSP_Z + HOSP_D / 2 - 2
  );
}
function hospitalTeleport(enter) {
  if (hospitalTransition) return;
  player.rail = null;
  player.inDuct = false;
  player.inSewer = false;
  player.vel.set(0, 0, 0);
  player.grounded = true;
  player.committedAirborne = false;
  player.attackWindow = 0;
  const outside = v(HOSP_X, terrainHeight(HOSP_X, HOSP_Z - HOSP_D / 2 - 11) + 0.2, HOSP_Z - HOSP_D / 2 - 11),
    inside = v(HOSP_X, HOSPITAL_FLOOR + 0.2, HOSP_Z - HOSP_D / 2 + 9);
  hospitalTransition = {
    t: 0,
    duration: 1.45,
    from: player.pos.clone(),
    to: enter ? inside : outside,
    enter,
  };
  hospitalDoorHold = 4.0;
  idleTime = 0;
  flash(enter ? "EMERGENCY DOORS OPENING" : "LEAVING EMERGENCY WING", 1.8);
}
function ductNearestPoint(p) {
  return ductPointAt(ductDistanceFromPoint(p));
}
function enterDuct() {
  player.inDuct = true;
  player.inHospital = true;
  player.rail = null;
  player.vel.set(0, 0, 0);
  player.grounded = true;
  player.committedAirborne = false;
  ductTravel = ductDistanceFromPoint(player.pos.clone().add(v(0, 3.05, 0)));
  ductViewTravel = ductTravel;
  ductViewAhead = 1;
  const p = ductPointAt(ductTravel);
  player.pos.set(p.x, p.y - 0.72, p.z);
  cameraHardCut = true;
  flash("VENT ROUTE · W/S crawl · follow the lights toward the high hatch.", 3);
}
function leaveDuct(vent) {
  player.inDuct = false;
  player.inHospital = true;
  player.vel.set(0, 0, 0);
  player.grounded = true;
  const x = THREE.MathUtils.clamp(vent.x + 2.8, HOSP_X - HOSP_W / 2 + 3, HOSP_X + HOSP_W / 2 - 3),
    z = vent.z + 2.4;
  player.pos.set(x, HOSPITAL_FLOOR + 0.2, z);
  cameraHardCut = true;
  flash("BACK IN THE EMERGENCY WING", 2.2);
}
function overheadHatch() {
  const vent = ductVents.find((ve) => ve.upper);
  return player.inDuct &&
    vent?.open &&
    Math.hypot(player.pos.x - vent.x, player.pos.z - vent.z) < 2.9 &&
    player.pos.y > HOSPITAL_FLOOR + 4
    ? vent
    : null;
}
function dropFromHatch(attack) {
  const vent = overheadHatch();
  if (!vent) return false;
  player.inDuct = false;
  player.rail = null;
  player.grounded = false;
  player.pos.set(vent.x, HOSPITAL_FLOOR + vent.height - 1.15, vent.z);
  const aim = v(-Math.sin(yaw), 0, -Math.cos(yaw));
  player.vel.set(aim.x * (attack ? 7.4 : 2.3), -5.7, aim.z * (attack ? 7.4 : 2.3));
  if (attack) {
    player.cooldown = 0.86;
    player.attack = 0.55;
    player.attackWindow = 2.5;
    player.attackTarget = null;
    player.attackAlert = new Map(humanoids.filter((n) => n.visible).map((n) => [n.idx, n.alert]));
    fx(580, 0.13, "triangle", 0.05);
  }
  commitToAir();
  flash(attack ? "OVERHEAD AMBUSH! Aim at the ward floor." : "DROPPING INTO THE TREATMENT WARD", 2.5);
  return true;
}
function handleHospitalInteraction() {
  if (hospitalTransition) return true;
  const p = player.pos;
  if (!player.inHospital && !player.inDuct) {
    if (
      Math.hypot(p.x - HOSP_X, p.z - (HOSP_Z - HOSP_D / 2 - 7)) < 8 &&
      Math.abs(p.y - terrainHeight(p.x, p.z)) < 4
    ) {
      hospitalTeleport(true);
      return true;
    }
    return false;
  }
  if (!player.inDuct && Math.hypot(p.x - hospitalExit.x, p.z - hospitalExit.z) < 6) {
    hospitalTeleport(false);
    return true;
  }
  const nearby = ductVents
    .filter((ve) => !ve.upper || player.inDuct)
    .find(
      (ve) =>
        Math.hypot(p.x - ve.x, p.z - ve.z) < (ve.upper ? 3.2 : 4.7) &&
        (!player.inDuct || Math.abs(p.y - (HOSPITAL_FLOOR + ve.height - 0.72)) < 2.6),
    );
  if (nearby) {
    if (nearby.open) {
      if (nearby.upper) {
        flash("UPPER HATCH OPEN · SPACE drops · LEFT CLICK pounces into the ward!", 3);
      } else if (player.inDuct) leaveDuct(nearby);
      else enterDuct();
    } else {
      hospitalChew = { vent: nearby, origin: player.pos.clone() };
      flash(
        `HOLD E to chew the ${nearby.upper ? "OVERHEAD HATCH" : "grille"}. ${nearby.first ? "This first entry needs two minutes." : "Keep still until it opens."}`,
        4,
      );
    }
    return true;
  }
  flash(
    player.inDuct
      ? "Follow the duct lights toward a grille."
      : "Find a grille in the wards or the emergency doors.",
    2,
  );
  return true;
}
function adjustHospitalMovement(old) {
  if (!player.inHospital) return;
  if (player.inDuct) {
    const q = ductPointAt(ductTravel);
    player.pos.set(q.x, q.y - 0.72, q.z);
    player.vel.set(0, 0, 0);
    return;
  }
  const xmin = HOSP_X - HOSP_W / 2 + 2.3,
    xmax = HOSP_X + HOSP_W / 2 - 2.3;
  const zmin = HOSP_Z - HOSP_D / 2 + 2.4,
    zmax = HOSP_Z + HOSP_D / 2 - 2.4;
  const blocks = [...hospitalObstacles, ...hospitalFurnitureColliders];
  const hit = (x, z) =>
    blocks.some((b) => Math.abs(x - b.x) < b.w / 2 + 0.23 && Math.abs(z - b.z) < b.d / 2 + 0.23);
  const tx = THREE.MathUtils.clamp(player.pos.x, xmin, xmax);
  const tz = THREE.MathUtils.clamp(player.pos.z, zmin, zmax);
  const dx = tx - old.x,
    dz = tz - old.z;
  const steps = Math.max(1, Math.min(18, Math.ceil(Math.hypot(dx, dz) / 0.28)));
  let x = old.x,
    z = old.z;
  for (let i = 0; i < steps; i++) {
    const nextX = THREE.MathUtils.clamp(x + dx / steps, xmin, xmax);
    if (!hit(nextX, z)) x = nextX;
    const nextZ = THREE.MathUtils.clamp(z + dz / steps, zmin, zmax);
    if (!hit(x, nextZ)) z = nextZ;
  }
  player.pos.x = x;
  player.pos.z = z;
}
function grantInfectionBite(n) {
  secondsSinceBite = 0;
  if (n.hospitalRole) {
    infectionOwn = Math.min(100, infectionOwn + (n.hospitalRole === "patient" ? 5.7 : 6.2));
    if (n.hospitalRole === "patient") bittenPatients.add(n.idx);
    else bittenStaff.add(n.idx);
    n.nextBite = 14;
  } else infectionOwn = Math.min(100, infectionOwn + 3.6);
  drawInfection();
  checkUnannouncedEnd();
}
function checkUnannouncedEnd() {
  if (won || !player.alive || infectionReading() < 50) return;
  if (
    bittenStaff.size < Math.ceil(hospitalStaff.length / 2) ||
    bittenPatients.size < Math.ceil(hospitalPatients.length / 2)
  )
    return;
  won = true;
  player.alive = false;
  playing = false;
  document.exitPointerLock?.();
  $("dangerTitle").textContent = "THE CITY IS YOURS";
  $("dangerText").textContent =
    "The town is changing. You found a path nobody told you about. Power " +
    player.points +
    " · " +
    player.hits +
    " bites.";
  $("dangerOverlay").classList.remove("hidden");
}
function knockPlayer(dir, str, msg) {
  if (player.inDuct || !player.alive) return;
  const d = dir.lengthSq() > 0.001 ? dir.clone().normalize() : v(0, 0, -1);
  player.rail = null;
  player.attackWindow = 0;
  player.committedAirborne = true;
  player.cameraCommit = 0.38;
  player.vel.set(d.x * str, Math.min(3, str * 0.22), d.z * str);
  player.grounded = false;
  cameraHardCut = true;
  flash(msg, 2.5);
  fx(185, 0.16, "square", 0.045);
}
// Defenders take the open triage doorway when crossing between lobby and wards.
function hospitalPatrolTarget(from, to) {
  const a = from.z - HOSP_Z,
    b = to.z - HOSP_Z;
  // The two side triage alcoves have rear access around the ends of the partitions.
  if (a < -24 && Math.abs(from.x - HOSP_X) > 22 && Math.abs(to.x - HOSP_X) < 20)
    return v(from.x, HOSPITAL_FLOOR, HOSP_Z - 20);
  if ((a < -12.5 && b > -11.5) || (a > -11.5 && b < -12.5)) {
    if (Math.abs(from.x - HOSP_X) > 10) return v(HOSP_X, HOSPITAL_FLOOR, HOSP_Z + (a < -12.5 ? -16 : -8));
    return v(HOSP_X, HOSPITAL_FLOOR, HOSP_Z + (a < -12.5 ? -10 : -14));
  }
  return to;
}
// Hospital circulation stays within each department; patients make short trips
// along the foot of their beds rather than crossing through partitions.
const staffCircuits = [
  [
    [-14, -21],
    [-7, -22],
    [-7, -28],
    [-14, -29],
  ],
  [
    [2, -6],
    [5, -10],
    [-4, -10],
    [-5, -6],
  ],
  [
    [19, -8],
    [18, -4],
    [18, 0],
    [24, -4],
  ],
  [
    [-12, -32],
    [-7, -37],
    [-1, -35],
    [-3, -27],
  ],
  [
    [24, -30],
    [29, -31],
    [34, -35],
    [26, -37],
  ],
  [
    [-28, 8],
    [-24, 9],
    [-23, 17],
    [-27, 18],
  ],
  [
    [29, 24],
    [25, 23],
    [25, 30],
    [28, 32],
  ],
  [
    [38, -26],
    [37, -24],
    [41, -24],
    [41, -33],
  ],
];
for (let i = 0; i < hospitalStaff.length; i++) {
  const n = hospitalStaff[i];
  n.hospitalCircuit = staffCircuits[i].map(([x, z]) => v(HOSP_X + x, HOSPITAL_FLOOR, HOSP_Z + z));
  n.hospitalRouteIndex = 0;
  n.hospitalPause = (i % 3) * 0.35;
  n.hospitalStep = 0;
}
for (let i = 0; i < hospitalPatients.length; i++) {
  const n = hospitalPatients[i],
    p = n.station;
  const direction = i % 2 ? 1 : -1;
  n.hospitalCircuit = [
    p.clone(),
    p.clone().add(v(direction * 2.6, 0, -0.65)),
    p.clone().add(v(direction * 2.1, 0, -2.8)),
    p.clone().add(v(0, 0, -2.0)),
  ];
  n.hospitalRouteIndex = i % 4;
  n.hospitalPause = 0.4 + (i % 3) * 0.3;
  n.hospitalStep = 0;
}
// Defenders still respond to squirrel incursions, without breaking normal patrols.
function updateHospitalActors(dt) {
  if (player.inDuct) return;
  const inside = !!player.inHospital;
  for (const n of hospitalActors) {
    if (n.injured) continue;
    n.nextBite = Math.max(0, (n.nextBite || 0) - dt);
    n.hitCooldown = Math.max(0, (n.hitCooldown || 0) - dt);
    const pos = n.root.position,
      distance = Math.hypot(pos.x - player.pos.x, pos.z - player.pos.z);
    const isDefender = ["guard", "orderly", "extinguisher"].includes(n.hospitalRole);
    const pursuing = inside && isDefender && distance < 15;
    let walking = false;
    if (pursuing) {
      n.wayTarget.copy(player.pos);
      n.wayTarget.y = HOSPITAL_FLOOR;
    } else {
      n.hospitalPause = Math.max(0, n.hospitalPause - dt);
      const next = n.hospitalCircuit[n.hospitalRouteIndex];
      n.wayTarget.copy(next);
      if (pos.distanceTo(next) < 0.75 && n.hospitalPause === 0) {
        n.hospitalRouteIndex = (n.hospitalRouteIndex + 1) % n.hospitalCircuit.length;
        n.hospitalPause = n.hospitalRole === "patient" ? 0.48 : 0.24;
        n.wayTarget.copy(n.hospitalCircuit[n.hospitalRouteIndex]);
      }
    }
    const desired = hospitalPatrolTarget(pos, n.wayTarget).clone().sub(pos).setY(0),
      dist = desired.length();
    if (dist > 0.18 && (!n.hospitalPause || pursuing)) {
      desired.multiplyScalar(1 / dist);
      const pace = pursuing
        ? n.hospitalRole === "guard"
          ? 3.9
          : 2.7
        : n.hospitalRole === "patient"
          ? 1.15
          : n.hospitalRole === "orderly"
            ? 1.85
            : 1.62;
      const step = Math.min(dist, dt * pace);
      pos.addScaledVector(desired, step);
      n.root.rotation.y = Math.atan2(desired.x, desired.z);
      walking = step > 0.002;
    }
    pos.y = HOSPITAL_FLOOR;
    // Animated strides and arms: hospital occupants no longer glide or stand frozen.
    n.hospitalStep += dt * (walking ? (n.hospitalRole === "patient" ? 6.1 : 8.3) : 3.0);
    const stride = walking ? Math.sin(n.hospitalStep + n.hospitalPhase) * 0.42 : 0;
    for (let k = 0; k < 2; k++) {
      n.legs[k].rotation.x = (k ? 1 : -1) * stride;
      n.arms[k].rotation.x = (k ? -1 : 1) * stride * 0.67;
    }
    n.head.rotation.y = walking
      ? Math.sin(n.hospitalStep * 0.36) * 0.07
      : Math.sin(time * 0.85 + n.hospitalPhase) * 0.1;
    if (!inside || !isDefender || n.hitCooldown > 0) continue;
    if (n.telegraph <= 0 && distance < (n.hospitalRole === "orderly" ? 7.2 : 4)) {
      n.telegraph = n.hospitalRole === "orderly" ? 1.0 : 0.76;
      if (n.hospitalRole === "orderly") flash("Stretcher rail shoves forward — get clear!", 1.2);
      else if (n.hospitalRole === "extinguisher") flash("The woman winds up the fire extinguisher!", 1.2);
      else flash("Security guard lunges — dodge!", 1.2);
    } else if (n.telegraph > 0) {
      n.telegraph -= dt;
      n.arms[1].rotation.x = -1.55;
      if (n.telegraph <= 0) {
        n.hitCooldown = 6;
        n.telegraph = 0;
        n.arms[1].rotation.x = 0;
        const dd = v(player.pos.x - pos.x, 0, player.pos.z - pos.z);
        if (dd.length() < (n.hospitalRole === "orderly" ? 3.6 : 2.45))
          knockPlayer(
            dd,
            10.8,
            n.hospitalRole === "orderly"
              ? "STRETCHER CHARGE! You were knocked aside."
              : n.hospitalRole === "extinguisher"
                ? "CLANG! The extinguisher sent you rolling."
                : "SECURITY! The guard grabbed you.",
          );
      }
    }
  }
}
// Hospital treatment is independent of the player's victims; they're already busy.
let treatmentNotice = 0;
function updateInfection(dt) {
  secondsSinceBite += dt;
  infectionOwn = Math.max(0, infectionOwn - dt * (player.inDuct ? 0.05 : 0.011));
  // Each of seven converted squirrels matures over 25 minutes of *unpaused* play.
  // Their combined final share cannot exceed 25%, nor finish without player effort.
  let share = 0;
  for (const s of normalSquirrels) {
    if (!s.infected) continue;
    const canAdvance = infectionOwn >= 25 && secondsSinceBite < 600;
    if (canAdvance) s.progress = Math.min(1500, s.progress + dt);
    const portion = Math.min(s.progress / 1500, infectionOwn >= 25 ? 1 : 0.92);
    s.component = (25 / 7) * portion;
    share += s.component;
  }
  infectionFromSquirrels = Math.min(25, share);
  drawInfection();
  checkUnannouncedEnd();
}
function updateChewing(dt) {
  if (!hospitalChew) return;
  const { vent, origin } = hospitalChew;
  if (
    !keys.has("KeyE") ||
    player.pos.distanceTo(origin) > 1.3 ||
    Math.hypot(player.pos.x - vent.x, player.pos.z - vent.z) > (vent.upper ? 3.2 : 4.9)
  ) {
    hospitalChew = null;
    $("chewPanel").style.display = "none";
    return;
  }
  vent.chew = Math.min(vent.first ? 120 : 24, vent.chew + dt);
  const required = vent.first ? 120 : 24;
  $("chewPanel").style.display = "block";
  $("chewPanel").textContent =
    `${vent.upper ? "CHEWING OVERHEAD HATCH" : "CHEWING VENT"} · ${Math.floor(vent.chew)} / ${required} sec · EXPOSED`;
  if (vent.chew >= required) {
    vent.open = true;
    vent.panel.visible = false;
    hospitalChew = null;
    $("chewPanel").style.display = "none";
    fx(560, 0.24, "triangle", 0.05);
    flash(
      vent.upper
        ? "UPPER HATCH OPEN! SPACE drops · LEFT CLICK pounces."
        : "VENT OPEN! E to enter or leave the duct.",
      3,
    );
  }
}
function updateWildlife(dt) {
  for (const s of normalSquirrels) {
    s.phase += dt * (s.infected ? 1.3 : 1);
    const wander = s.infected ? 6 : 8,
      x = s.x + Math.sin(s.phase * 0.83 + s.i) * wander,
      z = s.z + Math.cos(s.phase * 0.63 + s.i * 1.3) * wander;
    s.root.position.x = THREE.MathUtils.lerp(s.root.position.x, x, Math.min(1, dt * 2));
    s.root.position.z = THREE.MathUtils.lerp(s.root.position.z, z, Math.min(1, dt * 2));
    s.root.position.y = outdoorSurfaceAt(s.root.position.x, s.root.position.z) - 0.06;
    s.root.rotation.y = Math.atan2(x - s.root.position.x, z - s.root.position.z);
    const c = Math.cos(s.root.rotation.y),
      sn = Math.sin(s.root.rotation.y);
    for (const side of [-1, 1])
      for (const front of [-1, 1]) {
        const px = s.root.position.x + c * side * 0.24 + sn * front * 0.36,
          pz = s.root.position.z - sn * side * 0.24 + c * front * 0.36;
        s.root.position.y = Math.max(s.root.position.y, outdoorSurfaceAt(px, pz) - 0.05);
      }
    s.tail.rotation.x = Math.sin(s.phase * 7) * 0.17;
  }
  for (const r of rabbits) {
    r.phase += dt * 1.6;
    const danger =
      !player.inHospital &&
      !player.inSewer &&
      Math.hypot(player.pos.x - r.root.position.x, player.pos.z - r.root.position.z) < 12;
    if (danger) {
      r.escapeUntil = 2.5;
      r.phase += dt * 9.5;
    }
    r.escapeUntil = Math.max(0, r.escapeUntil - dt);
    const nx = r.x + Math.sin(r.phase * 0.66 + r.i) * (r.escapeUntil > 0 ? 15 : 7),
      nz = r.z + Math.cos(r.phase * 0.43 + r.i) * (r.escapeUntil > 0 ? 14 : 9);
    r.root.rotation.y = Math.atan2(nx - r.root.position.x, nz - r.root.position.z);
    r.root.position.x = THREE.MathUtils.lerp(
      r.root.position.x,
      nx,
      Math.min(1, dt * (r.escapeUntil > 0 ? 10 : 2)),
    );
    r.root.position.z = THREE.MathUtils.lerp(
      r.root.position.z,
      nz,
      Math.min(1, dt * (r.escapeUntil > 0 ? 10 : 2)),
    );
    r.root.position.y =
      terrainHeight(r.root.position.x, r.root.position.z) + 0.13 + Math.abs(Math.sin(r.phase * 4)) * 0.12;
  }
}
function tryWildlifePounce() {
  if (player.attackWindow <= 0 || player.inSewer || player.inHospital) return;
  for (const rabbit of rabbits) {
    if (player.pos.distanceTo(rabbit.root.position) < 2.25) {
      rabbit.escapeUntil = 4;
      rabbit.phase += 4;
      player.attackWindow = 0;
      flash("Too quick! The rabbit slipped away. No reward.", 2);
      return true;
    }
  }
  for (const normal of normalSquirrels) {
    if (normal.infected || player.pos.distanceTo(normal.root.position) > 1.42) continue;
    normal.infected = true;
    normal.phase += 3;
    normal.torso.material = mat("#83544d");
    normal.root.children.find((c) => c !== normal.torso)?.material?.color?.set?.("#a67860");
    player.hits++;
    player.points += 90;
    player.inactiveSeconds = 0;
    squirrelCoins += 10;
    totalCoinsEarned += 10;
    normal.progress = 0;
    player.attackWindow = 0;
    secondsSinceBite = 0;
    idleTime = 0;
    refreshPowerUI();
    flash("ANOTHER SQUIRREL TURNS! +90 Power · +10 Coins", 3);
    fx(810, 0.12, "triangle", 0.04);
    return true;
  }
  return false;
}
// The ambulance follows the new arterial, slows around pedestrians and pulls into Emergency.
const ambulance = makeCar(629, 283, "#f0eee6", PI / 2, false);
ambulance.visible = false;
box(2.5, 0.8, 3.15, hospitalWhite, 0, 2.38, -0.42, ambulance);
for (const side of [-1, 1]) {
  box(0.12, 0.35, 1.25, mat("#b42c28"), side * 1.43, 1.56, 0, ambulance);
  box(0.32, 0.65, 1.25, mat("#be332f"), side * 1.43, 2.35, -0.3, ambulance);
}
box(0.75, 0.22, 0.31, mat("#cf382f"), -0.48, 3.07, 0.12, ambulance);
box(0.75, 0.22, 0.31, hospitalBlue, 0.48, 3.07, 0.12, ambulance);
const ambulanceState = { mode: "waiting", wait: 18, sirenDelay: 0 };
function updateAmbulance(dt) {
  const st = ambulanceState;
  if (st.mode === "waiting") {
    st.wait -= dt;
    if (st.wait <= 0) {
      ambulance.visible = true;
      ambulance.position.set(639, terrainHeight(639, 283) + 0.06, 283);
      ambulance.rotation.y = -PI / 2;
      st.mode = "arterial";
    }
    return;
  }
  const a = ambulance.position,
    speed = 12.5;
  if (st.mode === "arterial") {
    const blocked = humanoids.some(
      (n) => n.visible && !n.hospital && Math.hypot(n.root.position.x - a.x, n.root.position.z - a.z) < 5,
    );
    if (!blocked) a.x -= speed * dt;
    if (a.x <= HOSP_X) {
      a.x = HOSP_X;
      st.mode = "turn";
      ambulance.rotation.y = 0;
    }
  } else if (st.mode === "turn") {
    a.z += speed * 0.85 * dt;
    if (a.z >= HOSP_Z - 58) {
      st.mode = "park";
      st.wait = 16;
      a.z = HOSP_Z - 58;
    }
  } else if (st.mode === "park") {
    st.wait -= dt;
    if (st.wait <= 0) {
      st.mode = "waiting";
      st.wait = 145;
      ambulance.visible = false;
    }
  }
  a.y = terrainHeight(a.x, a.z) + 0.09;
  st.sirenDelay -= dt;
  if (st.sirenDelay <= 0 && st.mode !== "park") {
    st.sirenDelay = 1.45;
    const highPriority =
      predatorWarning > 0 ||
      humanoids.some((n) => n.visible && (n.kickWindup > 0 || (n.hospital && n.telegraph > 0)));
    fx(430, 0.21, "sine", highPriority ? 0.001 : 0.018); // emergency sound yields to nearby action warnings
  }
}
function updateHospital(dt) {
  const enclosed = player.inHospital || player.inDuct;
  hospitalRoof.visible = !enclosed;
  // Invisible NPC simulation outside the hospital is paused while enclosed.
  if (enclosed) {
    updateChewing(dt);
  } else {
    $("chewPanel").style.display = "none";
    hospitalChew = null;
  }
  if (!player.inDuct && (player.inHospital || Math.hypot(player.pos.x - HOSP_X, player.pos.z - HOSP_Z) < 150))
    updateHospitalActors(Math.min(dt, 0.08));
}

function updateNewSystems(realDt, dt) {
  if (!helpTouched && time > 60 && !helpBox.classList.contains("collapsed")) {
    helpBox.classList.add("collapsed");
    helpTouched = true;
    syncHelpToggle();
  }
  updateIdle(realDt);
  if (!player.alive) return;
  const p = player.pos;
  $("districtTag").textContent = player.inDuct
    ? "HOSPITAL · DUCTS"
    : player.inHospital
      ? "HOSPITAL · EMERGENCY"
      : p.x < -270 && p.z > 245
        ? "HOSPITAL DISTRICT"
        : player.inSewer
          ? "UNDERGROUND · SEWER"
          : p.z > 303 && p.x < 150
            ? "SYCAMORE PARK"
            : p.z > 303 && p.x > 270
              ? "CEDAR REST · GRAVEYARD"
              : p.z > 295
                ? "NORTHERN GARDENS"
                : p.x > 280
                  ? "COMMERCIAL DISTRICT"
                  : "OLD TOWN";
  const close = player.inSewer && Math.hypot(p.x - standPoint.x, p.z - standPoint.z) < 6;
  nearShop = close;
  $("shopHint").style.display = close ? "block" : "none";
  if (close) {
    const slot = ["HAT", "JACKET", "PANTS"][fashionSlot],
      name = wardrobeNames[fashionSlot][selectedStyle[fashionSlot]],
      unlocked = totalCoinsEarned >= 150;
    $("shopDetails").textContent = unlocked
      ? `${slot}: ${name} · ${selectedStyle[fashionSlot] === 8 ? "3 gold" : "35 Squirrel Coins"} · E buy/equip · 1/2/3 cycle categories. Owned outfits persist.`
      : `Unlock at 150 earned Squirrel Coins (${Math.max(0, 150 - totalCoinsEarned)} to go). Bites pay 10.`;
  }
  for (const d of dogs) {
    if (player.inSewer || player.inHospital) continue;
    d.barkCooldown = Math.max(0, d.barkCooldown - dt);
    d.phase += dt;
    const targetX = d.x + Math.sin(d.phase * (0.18 + d.i * 0.03)) * (2 + d.i * 0.4),
      targetZ = d.z + Math.cos(d.phase * 0.33) * (1.5 + d.i * 0.2);
    d.body.position.x = THREE.MathUtils.lerp(d.body.position.x, targetX, dt);
    d.body.position.z = THREE.MathUtils.lerp(d.body.position.z, targetZ, dt);
    d.body.position.y = terrainHeight(d.body.position.x, d.body.position.z);
    d.body.rotation.y = Math.atan2(targetX - d.body.position.x, targetZ - d.body.position.z);
    if (
      !player.inSewer &&
      p.y < 5 &&
      Math.hypot(p.x - d.body.position.x, p.z - d.body.position.z) < 10 &&
      d.barkCooldown === 0
    ) {
      d.barkCooldown = 8;
      flash("WOOF! A yard dog spotted the squirrel.", 2);
      fx(210, 0.13, "square", 0.018);
      for (const n of humanoids) {
        if (n.visible && n.root.position.distanceTo(d.body.position) < 12) n.alert = Math.max(n.alert, 3);
      }
    }
  }
  if (!player.inHospital) updateCop(dt);
  // Set short draw distance underground and hide outdoor detail. Avoid changing original graphics settings.
  const enclosed =
    player.inSewer ||
    player.inHospital ||
    shelterZones.some((s) => Math.hypot(p.x - s.x, p.z - s.z) < 2 && p.y < terrainHeight(s.x, s.z) + 3);
  scene.fog.near = THREE.MathUtils.lerp(scene.fog.near, enclosed ? 15 : 310, 0.12);
  scene.fog.far = THREE.MathUtils.lerp(scene.fog.far, enclosed ? 53 : 1050, 0.12);
  camera.far = player.inDuct ? 55 : player.inHospital ? 125 : player.inSewer ? 65 : 1500;
  if (player.inHospital) {
    scene.background.set("#455c5b");
    renderer.toneMappingExposure = 1.19;
  } else if (player.inSewer) {
    scene.background.set("#373f38");
    renderer.toneMappingExposure = 1.1;
  } else {
    scene.background.set("#a8d0ef");
    renderer.toneMappingExposure = 1.42;
  }
}

let nextCanopyShadowUpdate = 0;
function updateCanopyShadows() {
  if (time < nextCanopyShadowUpdate) return;
  nextCanopyShadowUpdate = time + 0.8;
  const x = player.pos.x,
    z = player.pos.z;
  for (const c of canopyShadowCasters) {
    const near = Math.hypot(x - c.x, z - c.z) < c.r;
    c.mesh.castShadow = near && renderer.shadowMap.enabled;
  }
}

// --- v1.2 ADDITIVE PATCH: denser canopy, treehouse, and crime-scene aftermath ---
const responderAmbulances = [];
function makeResponderAmbulance() {
  const amb = makeCar(HOSP_X, 283, "#f4f0ea", 0, false);
  amb.visible = false;
  amb.userData = { state: "idle", target: null, wait: 0, stage: null, homeX: -9999, homeZ: -9999 };
  box(2.5, 0.8, 3.15, hospitalWhite, 0, 2.38, -0.42, amb);
  for (const side of [-1, 1]) {
    box(0.12, 0.35, 1.25, mat("#b42c28"), side * 1.43, 1.56, 0, amb);
    box(0.32, 0.65, 1.25, mat("#be332f"), side * 1.43, 2.35, -0.3, amb);
  }
  box(0.75, 0.22, 0.31, mat("#cf382f"), -0.48, 3.07, 0.12, amb);
  box(0.75, 0.22, 0.31, hospitalBlue, 0.48, 3.07, 0.12, amb);
  amb.flashBars = amb.children.slice(-2);
  responderAmbulances.push(amb);
  return amb;
}
for (let i = 0; i < 3; i++) makeResponderAmbulance();
const crimeScenes = [];
function nearestRoadStage(pos) {
  // Distances are to the existing road centerlines. Each segment has real limits;
  // an ambulance doesn't cut directly through a house to park next to a patient.
  const segs =
    pos.x < -257
      ? [
          { axis: "z", coord: -289, lo: -239, hi: 267 },
          { axis: "x", coord: -179, lo: -299, hi: -176 },
        ]
      : pos.x > 267
        ? [
            { axis: "z", coord: 347, lo: -213, hi: 218 },
            { axis: "x", coord: 0, lo: 247, hi: 680 },
          ]
        : [
            { axis: "z", coord: -180, lo: -255, hi: 255 },
            { axis: "z", coord: 0, lo: -330, hi: 255 },
            { axis: "z", coord: 178, lo: -255, hi: 255 },
            { axis: "x", coord: 0, lo: -262, hi: 266 },
            { axis: "x", coord: 171, lo: -262, hi: 266 },
            { axis: "x", coord: -174, lo: -262, hi: 266 },
            { axis: "x", coord: -305, lo: -258, hi: 258 },
          ];
  const stage = segs
    .map((s) => {
      const xx = s.axis === "z" ? s.coord : THREE.MathUtils.clamp(pos.x, s.lo, s.hi);
      const zz = s.axis === "x" ? s.coord : THREE.MathUtils.clamp(pos.z, s.lo, s.hi);
      return { ...s, stop: pathPoint(xx, zz), distance: Math.hypot(pos.x - xx, pos.z - zz) };
    })
    .sort((a, b) => a.distance - b.distance)[0];
  return stage;
}
function scheduleCrimeScene(victim) {
  if (!victim || victim.sceneHot) return;
  victim.sceneHot = true;
  victim.injured = true;
  victim.hospital = true; // removes from normal roaming update
  victim.injuredTimer = 0;
  victim.recoverAt = 120;
  victim.alert = 12;
  victim.state = "injured";
  victim.speed = 0;
  victim.crimeOrigin = victim.root.position.clone();
  if (victim.redEyes)
    for (const e of victim.redEyes) {
      e.visible = false;
      e.material.emissiveIntensity = 0.0;
    }
  // Sit them down.
  victim.root.rotation.y = victim.facing;
  if (victim.legs?.[0]) victim.legs[0].rotation.x = -1.25;
  if (victim.legs?.[1]) victim.legs[1].rotation.x = -1.25;
  if (victim.arms?.[0]) victim.arms[0].rotation.z = -0.18;
  if (victim.arms?.[1]) victim.arms[1].rotation.z = 0.18;
  const stage = nearestRoadStage(victim.root.position);
  queueMedicalResponse(victim, stage);
  const scene = { victim, center: victim.root.position.clone(), radius: 72, ttl: 600, boosted: false, stage };
  crimeScenes.push(scene);
  gatherAtCrime(scene);
  rollIncidentPolice(scene);
}
function alarmNearbyWitnesses(victim) {
  if (!victim?.root) return;
  const center = victim.root.position;
  const nearby = humanoids
    .filter(
      (n) =>
        n !== victim && n.visible && !n.hospital && !n.injured && n.root.position.distanceTo(center) < 25,
    )
    .sort((a, b) => a.root.position.distanceTo(center) - b.root.position.distanceTo(center));
  // A minority stand their ground. Most citizens escape or call for help.
  let defenders = 0;
  for (const [i, n] of nearby.entries()) {
    const defend =
      defenders < 2 && (n.personality === "brave" || (i < 4 && n.personality === "wary" && n.idx % 5 === 0));
    n.alert = Math.max(n.alert, 10);
    n.reacting = Math.max(n.reacting, 3.4);
    n.witnessUntil = Math.max(n.witnessUntil || 0, time + 70);
    n.facing = Math.atan2(center.x - n.root.position.x, center.z - n.root.position.z);
    if (defend) {
      defenders++;
      n.defenseUntil = time + 19;
      n.state = "defend";
      n.doorEscape = null;
      n.kickCooldown = 0.3 + i * 0.36;
      if (i < 3 && n.sayCooldown <= 0)
        say(n, pick(["Hey! Get away from them!", "Back off!", "Leave them alone!"]));
    } else {
      n.defenseUntil = 0;
      n.state = "flee";
      n.speed = n.role === "cyclist" ? 8.2 : 7.1;
      if (i < 4 && n.sayCooldown <= 0)
        say(
          n,
          pick([
            "Call an ambulance!",
            "Look out! Get inside!",
            "That squirrel bit someone!",
            "Get away from it!",
          ]),
        );
      if (i < 3) beginHomeRetreat(n);
    }
  }
}
const __oldOnSuccessfulBite = onSuccessfulBite;
onSuccessfulBite = function (n) {
  try {
    __oldOnSuccessfulBite(n);
  } catch (e) {}
  if (n.hospitalRole) return; // Hospital patients are already inside treatment.
  if (n.motorcycle?.active) crashMotorcycle(n);
  if (n.bike && !n.motorcycle) {
    n.bike.visible = true;
    n.bike.position.set(1.15, 0.12, -0.6);
    n.bike.rotation.z = 1.12;
    n.body.position.y = 0;
  }
  scheduleCrimeScene(n);
  alarmNearbyWitnesses(n);
};
function updateCrimeScenes(dt) {
  for (let i = crimeScenes.length - 1; i >= 0; i--) {
    const s = crimeScenes[i];
    s.ttl -= dt;
    if (!s.boosted) {
      for (const n of humanoids) {
        if (!n.visible || n === s.victim || n.hospital) continue;
        const d = n.root.position.distanceTo(s.center);
        if (d < s.radius) {
          n.alert = Math.max(n.alert, 7);
          if (n.state === "walk" && !n.doorEscape) n.state = "flee";
          n.reacting = Math.max(n.reacting, 2.2);
        }
      }
      s.boosted = true;
    }
    if (copState.out && officer.visible && officer.position.distanceTo(s.center) < 36)
      copState.alert = Math.max(copState.alert, 6.5);
    if (s.victim && s.victim.visible && !s.victim.medicalPickup && !s.victim.medicalTriage) {
      const n = s.victim;
      n.injuredTimer = (n.injuredTimer || 0) + dt;
      n.root.position.x = THREE.MathUtils.lerp(n.root.position.x, n.crimeOrigin.x, Math.min(1, dt * 4));
      n.root.position.z = THREE.MathUtils.lerp(n.root.position.z, n.crimeOrigin.z, Math.min(1, dt * 4));
      n.root.position.y = terrainHeight(n.root.position.x, n.root.position.z) + 0.13;
      n.body.rotation.z = Math.sin(time * 3.2 + n.idx) * 0.06;
      n.head.rotation.x = 0.14 + Math.sin(time * 2.2 + n.idx) * 0.09;
      // The injured rider sits, guards a knee and groans rather than vanishing.
      if (n.legs?.[0]) n.legs[0].rotation.x = -1.13 + Math.sin(time * 1.9) * 0.1;
      if (n.legs?.[1]) n.legs[1].rotation.x = -1.42;
      if (n.arms?.[0]) n.arms[0].rotation.x = -0.85;
      if (n.arms?.[1]) n.arms[1].rotation.x = -1.25 + Math.sin(time * 1.5) * 0.07;
      if (!n.injuryMoanAt || time > n.injuryMoanAt) {
        n.injuryMoanAt = time + 12 + Math.random() * 9;
        if (n.sayCooldown <= 0)
          say(
            n,
            pick([
              "Ow! My knee!",
              "Ohhh... that really hurts.",
              "I need a doctor!",
              "Somebody help me, please!",
            ]),
          );
      }
      if (n.injuredTimer >= 120 && n.redEyes)
        for (const e of n.redEyes) {
          e.visible = true;
          e.material.emissiveIntensity = 0.55;
        }

      n.facing = Math.atan2(player.pos.x - n.root.position.x, player.pos.z - n.root.position.z);
      // Nearby people stay jumpy around the scene.
      for (const other of humanoids) {
        if (!other.visible || other === n || other.hospital) continue;
        const d = other.root.position.distanceTo(n.root.position);
        if (d < 20) {
          other.alert = Math.max(other.alert, 4); /* preserve kicks, defenders and door retreats */
        }
      }
    }
    if (s.ttl <= 0) crimeScenes.splice(i, 1);
  }
  updateMedicalResponders(dt);
}
// Skip wounded victims in the normal roaming update.
const __oldUpdateHumans = updateHumans;
updateHumans = function (dt) {
  const stash = [];
  for (const n of humanoids) {
    if (n.injured && !n.medicalTransit) {
      stash.push(n);
      n.hospital = true;
    }
  }
  __oldUpdateHumans(dt);
  // Keep victims visible after the original update.
  for (const n of stash) {
    n.visible = true;
    n.root.visible = true;
    n.hospital = true;
  }
};

// Extra canopy around the commercial district and estates.
function addExtraCanopy() {
  const specs = [
    {
      name: "Shop Oak A",
      x: 332,
      z: -24,
      H: 22,
      crown: 6.2,
      branches: 7,
      seed: 7101,
      color: ["#6f9447", "#7ea44a", "#5f7e37"],
      canopyBoost: 2,
      acorn: true,
    },
    {
      name: "Shop Oak B",
      x: 362,
      z: 24,
      H: 24,
      crown: 6.5,
      branches: 8,
      seed: 7102,
      color: ["#6f9447", "#97b45c", "#63873f"],
      canopyBoost: 2,
      acorn: true,
    },
    {
      name: "Chilis Sycamore",
      x: 412,
      z: -62,
      H: 27,
      crown: 7.1,
      branches: 8,
      seed: 7103,
      color: ["#7c9d4b", "#9db35b", "#6e8b3f"],
      canopyBoost: 3,
      sycamore: true,
    },
    {
      name: "Pump Elm",
      x: 468,
      z: 34,
      H: 25,
      crown: 6.4,
      branches: 7,
      seed: 7104,
      color: ["#8fa756", "#759043", "#abc267"],
      canopyBoost: 2,
    },
    {
      name: "Estate Oak South 1",
      x: 118,
      z: -356,
      H: 29,
      crown: 7.9,
      branches: 9,
      seed: 7201,
      color: ["#698a3b", "#8ca953", "#a3b962"],
      canopyBoost: 3,
      acorn: true,
    },
    {
      name: "Estate Oak South 2",
      x: 166,
      z: -327,
      H: 26,
      crown: 7.1,
      branches: 8,
      seed: 7202,
      color: ["#7e9a45", "#98b15c", "#5f8234"],
      canopyBoost: 2,
    },
    {
      name: "Estate Sycamore South",
      x: 228,
      z: -346,
      H: 30,
      crown: 8.0,
      branches: 9,
      seed: 7203,
      color: ["#7c9e4b", "#9ab85e", "#6d8a42"],
      canopyBoost: 3,
      sycamore: true,
    },
    {
      name: "Villa Elm South",
      x: 324,
      z: -333,
      H: 25,
      crown: 6.9,
      branches: 8,
      seed: 7204,
      color: ["#709047", "#86a651", "#abc364"],
      canopyBoost: 2,
    },
    {
      name: "Villa Oak South",
      x: 377,
      z: -354,
      H: 28,
      crown: 7.4,
      branches: 9,
      seed: 7205,
      color: ["#69823b", "#8aa14f", "#b0c067"],
      canopyBoost: 3,
      acorn: true,
    },
    {
      name: "Villa Sycamore South",
      x: 438,
      z: -327,
      H: 27,
      crown: 7.1,
      branches: 8,
      seed: 7206,
      color: ["#71934c", "#8bac58", "#a9c266"],
      canopyBoost: 2,
      sycamore: true,
    },
  ];
  for (const spec of specs) {
    try {
      makeTree(spec);
    } catch (error) {
      console.error("[Spicy Rodents] Tree build rejected:", spec.name, error);
    }
  }
}
addExtraCanopy();

const treehouseSite = { x: -142, z: 154, base: terrainHeight(-142, 154), height: 13.2, roof: null };
function buildTreehouse() {
  const { x, z, base, height: h } = treehouseSite;
  makeTree({
    name: "Treehouse Oak",
    x,
    z,
    H: 31,
    crown: 7.8,
    branches: 8,
    seed: 9301,
    color: ["#6a8c3e", "#89ab55", "#a4bb66"],
    canopyBoost: 3,
    acorn: true,
  });
  const g = new THREE.Group();
  g.position.set(x, base, z);
  scene.add(g);
  const wood = mat("#916c47"),
    pine = mat("#b9986c"),
    dark = mat("#63482e");
  box(8, 0.38, 7.8, dark, 0, h, 0, g); // enclosed main floor
  box(4.2, 0.35, 3.2, wood, 5.9, h, 0, g); // external lookout deck
  for (const xx of [-3.75, 3.75])
    for (const zz of [-3.5, 3.5]) {
      span(v(xx, 0.24, zz), v(xx, h - 0.22, zz), 0.29, 0.23, dark, g, 8);
      span(v(xx, 0.7, zz), v(xx * 0.38, h - 0.25, zz * 0.38), 0.17, 0.11, wood, g, 7);
    }
  // A tangible ladder reaches the floor, and it is selectable as a trunk route.
  for (const xx of [-0.65, 0.65]) span(v(xx, 0.3, 4.15), v(xx, h + 0.2, 4.15), 0.105, 0.1, wood, g, 7);
  for (let yy = 0.5; yy < h; yy += 0.75) box(1.6, 0.13, 0.25, pine, 0, yy, 4.15, g);
  addRoute("treehouse ladder", [v(x, base + 0.4, z + 4.15), v(x, base + h + 0.24, z + 4.15)], {
    kind: "trunk",
    surfaceRadius: 0.35,
  });
  // Side and back walls deliberately leave the south face open to an enterable room.
  box(7.8, 4.1, 0.24, pine, 0, h + 2.3, -3.72, g);
  for (const xx of [-3.85, 3.85]) box(0.25, 4.1, 7.5, pine, xx, h + 2.3, 0, g);
  for (const xx of [-2.8, 2.8]) box(1.65, 1.5, 0.16, M.glass, xx, h + 2.5, -3.59, g);
  treehouseSite.roof = box(8.7, 0.3, 8.4, mat("#615044"), 0, h + 4.64, 0, g);
  // Partial front wall with a central open entrance, plus railings on the deck.
  for (const xx of [-2.65, 2.65]) box(2.2, 2.8, 0.18, pine, xx, h + 2.7, 3.76, g);
  for (const zz of [-1.55, 1.55]) box(4.0, 0.79, 0.13, wood, 5.9, h + 0.62, zz, g);
  box(0.16, 0.88, 3.1, wood, 7.97, h + 0.63, 0, g);
  // Real, visible furniture inside: narrow table, bunk, little storage chest and lantern.
  box(2.4, 0.26, 1.15, mat("#876548"), -2, h + 0.56, -1.5, g);
  box(2.1, 0.48, 0.94, mat("#a9a083"), -2, h + 0.73, -1.5, g);
  box(1.45, 0.81, 1.45, dark, 2.1, h + 0.6, -1.4, g);
  box(1.7, 0.13, 1.25, wood, 1.5, h + 1.4, 1.2, g);
  ball(0.19, new THREE.MeshBasicMaterial({ color: 0xffe3a6 }), 1.5, h + 1.72, 1.2, g);
  addRoute(
    "treehouse floor",
    [v(x, base + h + 0.4, z + 4.15), v(x, base + h + 0.4, z + 2.5), v(x, base + h + 0.4, z - 2.0)],
    { kind: "lookout" },
  );
  addRoute("treehouse deck", [v(x, base + h + 0.4, z), v(x + 5.9, base + h + 0.4, z)], { kind: "lookout" });
}
buildTreehouse();

// Small number of motorcycles riding real road lanes; separate from the 26 pedestrian schedules.
const motorcycles = [];
function createMotorcycle(i) {
  const rider = makeHuman(
    [
      i ? "Alex Rider" : "Morgan Rider",
      "motorcyclist",
      -1,
      i ? "#ba896c" : "#c99a77",
      i ? "#3b5b6d" : "#5f554c",
      "wary",
    ],
    humanoids.length,
  );
  rider.visible = false;
  rider.root.visible = false;
  rider.hospital = true;
  rider.motorcycle = { active: false };
  const g = new THREE.Group();
  scene.add(g);
  g.visible = false;
  const rubber = M.rubber,
    chrome = mat("#858c86", 0.37),
    paint = mat(i ? "#324f68" : "#9f3632", 0.32);
  for (const z of [-1.0, 1.0]) {
    const wheel = new THREE.Mesh(new THREE.TorusGeometry(0.55, 0.14, 8, 20), rubber);
    wheel.rotation.y = PI / 2;
    wheel.position.set(0, 0.56, z);
    g.add(wheel);
    cyl(0.3, 0.3, 0.13, chrome, 0, 0.56, z, g, 12).rotation.z = PI / 2;
  }
  box(0.56, 0.44, 1.65, paint, 0, 1.03, 0, g);
  span(v(0, 0.92, -0.93), v(0, 1.48, -0.48), 0.09, 0.09, chrome, g, 6);
  span(v(0, 0.95, 0.94), v(0, 1.52, 0.65), 0.1, 0.1, chrome, g, 6);
  box(0.8, 0.14, 0.5, mat("#393c3b"), 0, 1.45, -0.18, g);
  span(v(-0.62, 1.6, 0.65), v(0.62, 1.6, 0.65), 0.06, 0.06, chrome, g, 6);
  ball(
    0.26,
    new THREE.MeshStandardMaterial({ color: 0xf6dfa0, emissive: 0xffe0a0, emissiveIntensity: 0.5 }),
    0,
    1.25,
    1.13,
    g,
  );
  const obj = {
    i,
    group: g,
    rider,
    active: false,
    crashed: false,
    wait: i ? 83 : 19,
    direction: i ? -1 : 1,
    velocity: i ? 11.9 : 10.4,
    skid: 0,
    crashPoint: null,
  };
  motorcycles.push(obj);
  rider.motorcycle = obj;
}
createMotorcycle(0);
createMotorcycle(1);
function crashMotorcycle(n) {
  const m = n.motorcycle;
  if (!m || !m.active || m.crashed) return;
  m.crashed = true;
  m.active = false;
  m.skid = 0;
  const p = m.group.position;
  const dx = m.direction * 1.4;
  m.crashPoint = v(p.x + dx, terrainHeight(p.x + dx, p.z) + 0.13, p.z + (p.z >= 0 ? 5.8 : -5.8));
  n.root.position.copy(m.crashPoint);
  n.body.position.set(0, 0, 0);
  n.root.rotation.y = m.direction > 0 ? Math.PI / 2 : -Math.PI / 2;
  n.motorcycle.active = false;
  flash("MOTORCYCLE CRASH! A bitten rider falls beside the road — people rush over.", 3.0);
  fx(260, 0.3, "sawtooth", 0.043);
}
function updateMotorcycles(dt) {
  for (const m of motorcycles) {
    if (m.crashed) {
      m.skid += dt;
      m.group.rotation.z = THREE.MathUtils.lerp(m.group.rotation.z, m.direction * 0.96, Math.min(1, dt * 3));
      m.group.position.x += m.direction * m.velocity * dt * Math.max(0, 1 - m.skid / 1.8) * 0.55;
      m.group.position.y = terrainHeight(m.group.position.x, m.group.position.z) + 0.1;
      if (m.skid > 8) {
        m.group.visible = false;
        m.crashed = false;
        m.wait = 90 + m.i * 37;
      }
      continue;
    }
    if (!m.active) {
      m.wait -= dt;
      if (m.wait > 0 || m.rider.injured) continue;
      m.active = true;
      m.rider.motorcycle.active = true;
      m.group.visible = true;
      m.rider.visible = true;
      m.rider.root.visible = true;
      m.rider.injured = false;
      m.rider.root.rotation.z = 0;
      m.group.rotation.set(0, m.direction > 0 ? Math.PI / 2 : -Math.PI / 2, 0);
      m.group.position.set(m.direction > 0 ? 296 : 650, 0, m.i ? 5.7 : -5.7);
    }
    m.group.position.x += m.direction * m.velocity * dt;
    m.group.position.y = terrainHeight(m.group.position.x, m.group.position.z) + 0.07;
    const n = m.rider;
    n.root.position.copy(m.group.position).add(v(0, 0.42, 0));
    n.root.rotation.y = m.group.rotation.y;
    n.body.position.set(0, 0.4, -0.12);
    n.body.rotation.x = -0.14;
    n.arms[0].rotation.x = -0.9;
    n.arms[1].rotation.x = -0.9;
    if (m.group.position.x < 283 || m.group.position.x > 657) {
      m.active = false;
      m.rider.motorcycle.active = false;
      m.group.visible = false;
      n.visible = false;
      n.root.visible = false;
      m.wait = 53 + m.i * 22;
    }
  }
}
// The crowd is small and comes from different points; it does not appear in a full ring at once.
const emergencyBystanders = [];
for (let i = 0; i < 7; i++) {
  const n = makeHuman(
    [
      ["Avery", "Lee", "Casey", "Sam", "Rowan", "Emery", "Dana"][i],
      "bystander",
      -1,
      ["#ad8569", "#d6ae86", "#87614e", "#c49976"][i % 4],
      ["#9d9a82", "#587b68", "#b68e75", "#7b8998"][i % 4],
      "wary",
    ],
    humanoids.length,
  );
  n.hospital = true;
  n.visible = false;
  n.root.visible = false;
  n.sceneAssignment = null;
  emergencyBystanders.push(n);
}
function gatherAtCrime(scene) {
  const n = 2 + Math.floor(Math.random() * 3);
  const base = scene.center;
  for (let i = 0; i < n; i++) {
    const p = emergencyBystanders.find((c) => !c.sceneAssignment);
    if (!p) break;
    p.sceneAssignment = scene;
    p.visible = true;
    p.root.visible = true;
    const angle = ((i + 0.33) * Math.PI * 2) / n;
    const side = scene.stage?.stop || base;
    const offX = Math.cos(angle) * 8,
      offZ = Math.sin(angle) * 8;
    const clear = (x, z) =>
      !houses
        .concat(commercialBounds)
        .some((h) => Math.abs(x - h.x) < h.w / 2 + 2 && Math.abs(z - h.z) < h.d / 2 + 2);
    let sx = base.x + offX * 1.65,
      sz = base.z + offZ * 1.65,
      tx = base.x + offX,
      tz = base.z + offZ;
    if (!clear(sx, sz) || !clear(tx, tz)) {
      const road = scene.stage?.stop || base;
      sx = road.x + (i - 1) * 2.8;
      sz = road.z + (i % 2 ? 4 : -4);
      tx = sx;
      tz = sz;
      if (!clear(sx, sz)) {
        sx = road.x + 6 + i * 2.6;
        sz = road.z + 9;
        tx = sx;
        tz = sz;
      }
    }
    p.root.position.set(sx, terrainHeight(sx, sz) + 0.13, sz);
    p.sceneTarget = v(tx, terrainHeight(tx, tz) + 0.13, tz);
    p.body.position.y = 0;
    p.reactionSpeech = 2.2 + i * 0.85;
  }
}
function updateEmergencyBystanders(dt) {
  for (const n of emergencyBystanders) {
    if (!n.sceneAssignment) continue;
    const scene = n.sceneAssignment;
    if (scene.ttl <= 0 || !scene.victim?.visible) {
      n.sceneAssignment = null;
      n.visible = false;
      n.root.visible = false;
      continue;
    }
    const p = n.root.position,
      d = n.sceneTarget.clone().sub(p).setY(0),
      distance = d.length();
    // Squirrel returns to the crime scene: civilians recoil instead of calmly greeting it.
    const danger = !player.inSewer && !player.inHospital && player.pos.distanceTo(p) < 7;
    if (danger) {
      d.copy(p).sub(player.pos).setY(0).normalize().multiplyScalar(4.0);
    }
    if (distance > 0.35 || danger) {
      const before = p.clone();
      d.normalize();
      p.addScaledVector(d, dt * (danger ? 5.4 : 1.5));
      keepEmergencyActorsOutside(p, before);
      p.y = terrainHeight(p.x, p.z) + 0.13;
      n.root.rotation.y = Math.atan2(d.x, d.z);
    }
    n.reactionSpeech -= dt;
    if (n.reactionSpeech <= 0) {
      n.reactionSpeech = 999;
      if (n.sayCooldown <= 0)
        say(
          n,
          [
            "Somebody call an ambulance!",
            "Stay back — it might still be here!",
            "Is that another squirrel bite?",
            "Give them some room!",
          ][Math.floor(Math.random() * 4)],
        );
    }
    const gait = Math.sin(time * 6 + n.idx);
    for (let i = 0; i < 2; i++) {
      n.arms[i].rotation.x = (i ? 1 : -1) * gait * 0.2 - (danger ? 1.1 : 0.13);
      n.legs[i].rotation.x = (i ? 1 : -1) * gait * (distance > 0.5 ? 0.24 : 0.02);
    }
  }
}

// Slightly denser commercial / mansion reaction to hospital-style scene response
const __oldUpdateNewSystems = updateNewSystems;
updateNewSystems = function (realDt, dt) {
  __oldUpdateNewSystems(realDt, dt);
  updateCrimeScenes(dt);
  updateMotorcycles(dt);
  updateEmergencyBystanders(dt);
};
// --- end v1.2 patch ---

// Display groups and compact layouts can be changed without interrupting gameplay.
const hudParts = ["stats", "compass", "world", "hunt", "help", "settings"];
const hudPresets = [
  { name: "FULL", show: [...hudParts] },
  { name: "PLAY", show: ["stats", "compass", "hunt", "world"] },
  { name: "NAVIGATION", show: ["compass", "world", "help"] },
  { name: "CLEAN", show: ["compass"] },
];
let hudVisible = new Set(hudParts),
  hudLast = new Set(hudParts),
  hudPreset = 0;
function applyHud() {
  for (const part of hudParts) document.body.classList.toggle("hud-hide-" + part, !hudVisible.has(part));
  document
    .querySelectorAll("#hudChooser input[data-hud]")
    .forEach((el) => (el.checked = hudVisible.has(el.dataset.hud)));
  $("hudMode").textContent =
    hudVisible.size === 0 ? "OFF" : hudPreset >= 0 ? hudPresets[hudPreset].name : "CUSTOM";
}
function toggleAllHud() {
  if (hudVisible.size === hudParts.length && !helpBox.classList.contains("collapsed")) {
    hudVisible.clear();
    hudPreset = -1;
  } else {
    hudVisible = new Set(hudParts);
    hudLast = new Set(hudVisible);
    hudPreset = 0;
    toggleHelp(true);
  }
  applyHud();
}
function cycleHudView() {
  hudPreset = (hudPreset + 1) % hudPresets.length;
  hudVisible = new Set(hudPresets[hudPreset].show);
  hudLast = new Set(hudVisible);
  applyHud();
}
function toggleHudEditor() {
  const e = $("hudChooser");
  e.classList.toggle("open");
  if (e.classList.contains("open") && document.pointerLockElement) document.exitPointerLock?.();
}
$("allHudBtn").addEventListener("click", toggleAllHud);
$("hudCycleBtn").addEventListener("click", cycleHudView);
$("hudCustomBtn").addEventListener("click", toggleHudEditor);
for (const el of document.querySelectorAll("#hudChooser input[data-hud]"))
  el.addEventListener("change", () => {
    if (el.checked) hudVisible.add(el.dataset.hud);
    else hudVisible.delete(el.dataset.hud);
    if (hudVisible.size) hudLast = new Set(hudVisible);
    hudPreset = -1;
    applyHud();
  });
function updateCompass() {
  // World coordinates: +Z south, -Z north. Camera forward is (-sin(yaw),-cos(yaw)).
  const heading = ((((-yaw * 180) / Math.PI) % 360) + 360) % 360;
  const card = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(heading / 45) % 8];
  $("compassHeading").textContent = `${card} · ${String(Math.round(heading) % 360).padStart(3, "0")}°`;
  const parts = [];
  for (let k = -4; k <= 12; k++) {
    const angle = (k * 45 + 360) % 360;
    const text = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][((k % 8) + 8) % 8];
    parts.push(`<span style="display:inline-block;width:46px;text-align:center">${text}</span>`);
  }
  if (!$("compassLetters").dataset.init) {
    $("compassLetters").innerHTML = parts.join("");
    $("compassLetters").dataset.init = "1";
  }
  $("compassLetters").style.transform = `translateX(-50%) translateX(${(4 - heading / 45) * 46}px)`;
}
applyHud();

// =====================================================================
// v1.5 — WESTSIDE EXTENSION / INTERIORS / RESPONDERS / ANIMATION
// =====================================================================
const WEST_X = -289,
  oldDistrictHomes = [],
  oldHomeInteriors = [];
// 7 real individual older properties across a newly connected street.
addNorthernGround(-590, -260, -264, 244);
addNorthernGround(-590, -429, 244, 278);
districtRibbon("z", WEST_X, 15, -244, 267, M.asphalt, 0.19);
for (const dx of [-10, 10]) districtRibbon("z", WEST_X + dx, 2.5, -249, 272, concrete, 0.23);
districtRibbon("x", -179, 12, -296, -176, M.asphalt, 0.18);
for (const dz of [-187, -171]) districtRibbon("x", dz, 2.1, -299, -178, concrete, 0.2);
const westAsphalt = mat("#555958"),
  fadedConcrete = mat("#aba89d"),
  weatheredWood = mat("#977b5f");
const oldGas = { x: -397, z: 229, closed: false, attackSeconds: 0, lastAttack: -1e9, bites: 0, sign: null };
const westTrees = [];
// Westside wooden poles and their overhead lines share exact attachment points.
const westPoleTops = [];
for (let i = 0; i < 7; i++) {
  const z = -235 + i * 77,
    x = WEST_X - 14,
    by = terrainHeight(x, z),
    top = v(x, by + 16.6, z);
  if (pavementDistance(x, z) < 0.95) throw new Error("Westside pole obstructs street " + i);
  cyl(0.42, 0.5, 16.6, mat("#695740"), x, by + 8.3, z, scene, 9);
  span(v(x - 2.2, by + 15.8, z), v(x + 2.2, by + 15.8, z), 0.15, 0.15, weatheredWood);
  utilitySupports.push({ x, z, label: "westside", top: top.clone() });
  westPoleTops.push(top);
  addRoute("Westside telephone pole " + i, [v(x, by + 0.5, z), top.clone()], {
    kind: "trunk",
    surfaceRadius: 0.5,
  });
}
for (let i = 1; i < westPoleTops.length; i++) {
  const pts = droopBetween(westPoleTops[i - 1], westPoleTops[i], 0.42);
  linePath(pts, wireM, 0.033, 42);
  addRoute("Westside overhead phone line " + i, pts, { kind: "wire" });
}
function oldHouse(index) {
  const x = -365 + ((index % 3) - 1) * 5,
    z = -224 + index * 61,
    by = terrainHeight(x, z);
  const wall = mat(["#a69a7c", "#bdab92", "#919b8a", "#bcafa1", "#99917f", "#bcb28a", "#9b988d"][index]);
  const trim = mat(index % 2 ? "#e4dbbf" : "#d8d5c4"),
    roofMat = mat(["#6f6257", "#605a57", "#746359"][index % 3]);
  const width = 21 + (index % 3) * 2,
    depth = 20 + (index % 2) * 3,
    height = 6.1 + (index % 4) * 0.45;
  const canEnter = index < 4;
  let g = new THREE.Group();
  g.position.set(x, by, z);
  g.rotation.y = Math.PI / 2;
  scene.add(g);
  box(width, 0.32, depth, mat("#99978a"), 0, 0.14, 0, g);
  box(width, height, 0.4, wall, 0, height / 2, -depth / 2, g);
  for (const side of [-1, 1]) box(0.45, height, depth, wall, (side * width) / 2, height / 2, 0, g);
  if (canEnter) {
    // Open garage/back entrance, not an impenetrable facade.
    for (const side of [-1, 1])
      box((width - 6) / 2, height, 0.45, wall, (side * (width + 6)) / 4, height / 2, depth / 2, g);
    box(6, 0.8, 0.45, trim, 0, height - 0.4, depth / 2, g);
  } else box(width, height, 0.45, wall, 0, height / 2, depth / 2, g);
  const houseRoof = box(width + 2, 0.56, depth + 1, roofMat, 0, height + 0.14, 0, g);
  for (const wx of [-width * 0.28, width * 0.28]) {
    box(2.6, 2.8, 0.1, M.glass, wx, 3.6, depth / 2 + 0.3, g);
    box(3.1, 0.23, 0.14, trim, wx, 5.0, depth / 2 + 0.34, g);
  }
  box(1.3, 2.0, 0.4, trim, -width * 0.31, 1.2, depth / 2 + 0.1, g);
  // Garage tools, sitting room furniture and a small kitchen are actually inside.
  box(4.2, 1.15, 1.4, mat("#746e63"), -width * 0.24, 0.84, 0, g);
  box(2, 0.6, 1.8, mat("#c0a58a"), width * 0.23, 0.65, -depth * 0.2, g);
  box(2.2, 1.6, 1.1, mat("#87755d"), width * 0.25, 0.85, depth * 0.2, g);
  box(1.6, 1.0, 1.0, mat("#9b8b6e"), -width * 0.28, 0.66, -depth * 0.28, g);
  // Old single-car concrete drive and bins keep seven houses visibly different.
  for (let k = 0; k < 12; k++) {
    const dx = x + depth / 2 + 3 + k * 4.6,
      dz = z + width * 0.22;
    box(4.9, 0.07, 4.2, fadedConcrete, dx, terrainHeight(dx, dz) + 0.16, dz);
  }
  for (const dx of [-width / 2 - 3, width / 2 + 3]) {
    let by2 = terrainHeight(x + dx, z - 8);
    box(0.75, 1.35, 0.85, mat("#686a61"), x + dx, by2 + 0.68, z - 8);
  }
  if (index % 2 === 0) {
    box(3.4, 2.25, 2.3, mat("#71786d"), width / 2 + 4.4, 1.15, 0, g);
  }
  const home = {
    index,
    x,
    z,
    by,
    width,
    depth,
    height,
    roof: houseRoof,
    enterable: canEnter,
    door: v(x + depth / 2 + 2.8, by + 0.3, z),
  };
  oldDistrictHomes.push(home);
  if (canEnter) oldHomeInteriors.push(home);
  if (index % 2 === 0) {
    const bx = x - 31,
      bz = z + 6,
      yy = terrainHeight(bx, bz);
    box(3.3, 2.5, 2.9, mat("#66655e"), bx, yy + 1.25, bz);
    box(3.8, 0.16, 3.3, mat("#8b8b83"), bx, yy + 2.58, bz);
  }
  // Large thick-trunked oaks and elms—but no cloned symmetrical alignment.
  const treeX = x - 33 - (index % 3) * 3,
    treeZ = z + (index % 2 ? 19 : -14);
  makeTree({
    name: "Westside " + index + " shade oak",
    x: treeX,
    z: treeZ,
    h: 34 + ((index * 3) % 14),
    crown: 18 + (index % 5),
    branches: 7 + (index % 3),
    seed: 8100 + index * 83,
    color: ["#567943", "#75964c", "#90ab5a", "#4d763f"],
    acorn: index % 2 === 0,
  });
  westTrees.push({ x: treeX, z: treeZ });
}
for (let i = 0; i < 7; i++) oldHouse(i);
// Additional natural canopy along the road, carefully away from the road center.
for (let i = 0; i < 4; i++) {
  const x = -319 - (i % 2) * 9,
    z = -185 + i * 95;
  makeTree({
    name: "Westside street elm " + i,
    x,
    z,
    h: 30 + (i % 2) * 7,
    crown: 14,
    branches: 7,
    seed: 9102 + i * 63,
    color: ["#618844", "#9caf60", "#4c783a"],
  });
}
// Chained dogs: visible, gentle movement constrained to a finite radius (never infinitely roaming).
const chainedDogs = [];
for (const [i, x, z] of [
  [0, -403, -206],
  [1, -404, -75],
  [2, -418, 63],
  [3, -403, 134],
]) {
  const y = terrainHeight(x, z),
    g = new THREE.Group();
  scene.add(g);
  g.position.set(x, y, z);
  const fur = mat(i % 2 ? "#a08a68" : "#625447"),
    collar = mat("#a04032");
  const torso = ball(0.58, fur, 0, 0.6, 0, g);
  torso.scale.set(0.95, 0.8, 1.5);
  ball(0.39, fur, 0, 0.91, 0.7, g);
  for (const legX of [-0.34, 0.34])
    for (const legZ of [-0.49, 0.49]) cyl(0.12, 0.14, 0.56, fur, legX, 0.3, legZ, g, 7);
  ball(0.14, M.black, 0, 0.84, 1.04, g);
  box(0.52, 0.13, 0.54, collar, 0, 0.66, 0.57, g);
  const stake = v(x + 4, terrainHeight(x + 4, z) + 0.21, z + 2);
  cyl(0.13, 0.14, 0.85, M.metal, stake.x, stake.y, stake.z);
  const leash = span(v(x, y + 0.9, z), stake, 0.027, 0.027, mat("#77746b"), scene, 5);
  chainedDogs.push({
    g,
    x,
    z,
    phase: i * 0.7,
    radius: 3.4,
    leash,
    stake,
    chainOriginal: Math.hypot(stake.x - x, stake.z - z),
  });
}
// Police station has accessible reception, marked patrol parking and a dispatch courtyard.
const policeStation = { x: -510, z: -107 },
  stationY = terrainHeight(-510, -107);
const policeRoot = new THREE.Group();
policeRoot.position.set(policeStation.x, stationY, policeStation.z);
scene.add(policeRoot);
const blueGray = mat("#89979d"),
  policeDark = mat("#344852");
box(46, 0.28, 31, fadedConcrete, 0, 0.2, 0, policeRoot);
for (const xx of [-22.7, 22.7]) box(0.7, 8.8, 31, blueGray, xx, 4.6, 0, policeRoot);
box(46, 8.8, 0.75, blueGray, 0, 4.6, -15.2, policeRoot);
for (const xx of [-17, 17]) box(12, 8.8, 0.7, blueGray, xx, 4.6, 15.3, policeRoot);
const policeRoof = box(48, 0.52, 33, policeDark, 0, 9.25, 0, policeRoot);
box(10, 1.2, 0.24, signCanvas("WEST TOPEKA POLICE", "#344654", "#fff9d9"), 0, 10.8, 15.7, policeRoot);
box(13, 2.0, 2.2, mat("#797e79"), 0, 1.3, -5, policeRoot); // reception
box(4.2, 3.1, 0.3, M.glass, 0, 4.3, 15.4, policeRoot);
for (const px of [-15, 15]) {
  const y = terrainHeight(policeStation.x + px, policeStation.z + 26);
  box(9, 0.08, 15, fadedConcrete, policeStation.x + px, y + 0.13, policeStation.z + 26);
  const car = makeCar(policeStation.x + px, policeStation.z + 26, "#d5dcdb", 0, false);
  car.position.y = terrainHeight(car.position.x, car.position.z) + 0.08;
  box(0.8, 0.2, 0.5, mat("#274c77"), 0, 2.2, 0, car);
  box(0.38, 0.24, 0.45, mat("#a32b32"), 0.55, 2.19, 0, car);
}
addRoute(
  "police roof",
  [v(-527, stationY + 9.7, -107), v(-510, stationY + 9.7, -107), v(-493, stationY + 9.7, -107)],
  { kind: "roof" },
);
// Local patrol actors appear in daylight and respond to nearby bites via the existing officer chase AI.
const precinctOfficers = [];
for (const [i, x, z] of [
  [0, -517, -79],
  [1, -499, -83],
]) {
  const y = terrainHeight(x, z),
    g = new THREE.Group();
  g.position.set(x, y, z);
  scene.add(g);
  box(0.65, 1.35, 0.54, mat("#345070"), 0, 1.3, 0, g);
  ball(0.3, mat("#d4a080"), 0, 2.12, 0, g);
  box(0.8, 0.19, 0.7, policeDark, 0, 2.49, 0, g);
  for (const a of [-1, 1]) span(v(a * 0.3, 1.8, 0), v(a * 0.33, 0.65, 0.08), 0.12, 0.1, mat("#345070"), g);
  precinctOfficers.push({ g, x, z, t: i });
}
// A weathered neighborhood gas station and rows of outdoor storage doors beyond it.
const gasRoot = new THREE.Group();
gasRoot.position.set(oldGas.x, terrainHeight(oldGas.x, oldGas.z), oldGas.z);
scene.add(gasRoot);
box(34, 0.25, 25, mat("#87877c"), 0, 0.1, 0, gasRoot);
box(27, 5.0, 17, mat("#b7a991"), 0, 2.6, 4.0, gasRoot);
box(29, 0.5, 19, mat("#736d61"), 0, 5.4, 4.0, gasRoot);
for (const xx of [-9, 0, 9]) {
  box(3.4, 3.0, 0.16, M.glass, xx, 3.0, -4.6, gasRoot);
  box(2.9, 0.18, 0.2, mat("#dbcdb1"), xx, 4.6, -4.52, gasRoot);
}
box(15, 1.18, 0.2, signCanvas("WESTSIDE FUEL", "#74695b", "#f7ebcb"), 0, 6.5, -5.1, gasRoot);
box(34, 0.35, 18, mat("#746b5c"), 0, 6.6, -20, gasRoot);
for (const xx of [-12, 12]) for (const zz of [-27, -13]) cyl(0.22, 0.24, 6.5, M.metal, xx, 3.3, zz, gasRoot);
for (const xx of [-7, 7]) {
  box(2.4, 3.0, 1.9, mat("#afa999"), xx, 1.52, -18, gasRoot);
  box(1.8, 1.3, 0.1, mat("#4c6268"), xx, 2.1, -19.03, gasRoot);
  span(v(xx + 0.7, 2.5, -18), v(xx + 1.5, 0.9, -17.5), 0.065, 0.035, M.rubber, gasRoot);
  // A pump screen, nozzle and two low safety guards, built into the group.
  box(1.42, 0.49, 0.12, signCanvas("87", "#49584f", "#f4e7ca"), xx, 2.8, -19.13, gasRoot);
  box(0.15, 0.64, 0.13, M.black, xx + 1.03, 1.87, -18.95, gasRoot);
  for (const side of [-1, 1]) cyl(0.15, 0.17, 1.05, mat("#b29d60"), xx + side * 2.3, 0.6, -17.45, gasRoot);
}
// Older forecourt: small lights and pavement stripes follow the existing slab.
for (const xx of [-14, 0, 14]) {
  box(0.19, 0.065, 2.85, mat("#c9c1ac"), xx, 0.27, -29.8, gasRoot);
  box(4.6, 0.13, 0.15, mat("#baac8d"), xx, 6.44, -29.06, gasRoot);
}
for (const xx of [-10, 10]) {
  box(0.62, 0.12, 1.25, mat("#e7ddc9"), xx, 6.36, -20, gasRoot);
  box(1.85, 0.36, 0.18, mat("#b0a693"), xx, 5.45, -12.95, gasRoot);
}
box(2.9, 2.4, 1.6, mat("#76867f"), 15, 1.27, -6.35, gasRoot);
box(2.35, 0.76, 0.18, signCanvas("AIR / WATER", "#53665e", "#f3ead4"), 15, 2.0, -7.2, gasRoot);
// Low hanging shop opening awning reads clearly from the driveway.
box(27, 0.28, 3.15, mat("#998674"), 0, 5.08, -6.2, gasRoot);
const closeCanvas = document.createElement("canvas");
closeCanvas.width = 768;
closeCanvas.height = 192;
const closeCtx = closeCanvas.getContext("2d");
closeCtx.fillStyle = "#8f281f";
closeCtx.fillRect(0, 0, 768, 192);
closeCtx.fillStyle = "#fff4e6";
closeCtx.textAlign = "center";
closeCtx.textBaseline = "middle";
closeCtx.font = "bold 54px Arial";
closeCtx.fillText("WE ARE CLOSED DUE TO", 384, 64);
closeCtx.font = "bold 47px Arial";
closeCtx.fillText("VIOLENT DANGEROUS SQUIRRELS", 384, 136);
const closeTex = new THREE.CanvasTexture(closeCanvas);
closeTex.colorSpace = THREE.SRGBColorSpace;
oldGas.sign = box(
  18,
  2.55,
  0.25,
  new THREE.MeshStandardMaterial({ map: closeTex, roughness: 0.8, side: THREE.DoubleSide }),
  0,
  7.65,
  -5.2,
  gasRoot,
);
oldGas.sign.visible = false;
const storageY = terrainHeight(-513, 213),
  storage = new THREE.Group();
storage.position.set(-513, storageY, 213);
scene.add(storage);
box(94, 0.18, 79, mat("#8b8980"), 0, 0.09, 0, storage);
for (const side of [-1, 1]) {
  for (let u = 0; u < 6; u++) {
    const xx = -38 + u * 15;
    const door = box(11, 5.8, 0.22, mat(u % 2 ? "#8c928e" : "#a9aca8"), xx, 3.0, side * 26, storage);
    for (let r = 0; r < 6; r++)
      box(10.5, 0.09, 0.24, mat("#757d7b"), xx, 1.0 + r * 0.71, side * 26 - 0.12, storage);
    box(12.1, 0.54, 13, mat("#7a746b"), xx, 6.2, side * 30, storage);
  }
}
box(18, 1.05, 0.18, signCanvas("WESTSIDE STORAGE", "#4f656b", "#f5e8ca"), 0, 8.4, -37, storage);
// Small slow turtles along the garden, estate pondside and park walkways.
const turtles = [];
for (const [i, x, z] of [
  [0, -125, 328],
  [1, -104, 349],
  [2, -25, 84],
  [3, 164, -448],
  [4, -406, 180],
]) {
  const y = terrainHeight(x, z),
    g = new THREE.Group();
  g.position.set(x, y, z);
  scene.add(g);
  const shell = mat(["#596e3d", "#6e7750", "#5a6341", "#877958", "#73804e"][i]);
  const dome = new THREE.Mesh(
    new THREE.SphereGeometry(0.65, 10, 7, 0, Math.PI * 2, 0, Math.PI * 0.55),
    shell,
  );
  dome.scale.set(1.16, 0.65, 1.0);
  dome.position.y = 0.28;
  g.add(dome);
  for (let j = 0; j < 5; j++) {
    let ang = (j * 2 * Math.PI) / 5;
    ball(0.16, mat("#928e64"), Math.sin(ang) * 0.53, 0.1, Math.cos(ang) * 0.48, g);
  }
  ball(0.25, mat("#8a9864"), 0, 0.29, 0.77, g);
  for (const xx of [-0.13, 0.13]) ball(0.035, M.black, xx, 0.35, 0.965, g);
  turtles.push({ g, x, z, phase: i * 1.6 });
}
let activeOldHome = null,
  oldHomeTransit = null,
  gasCloseAnnouncement = false;
function openOldHome(home, enter) {
  if (oldHomeTransit) return;
  const pos = player.pos.clone();
  const door = home.door;
  const to = enter
    ? v(home.x + home.depth / 2 - 4, home.by + 0.35, home.z)
    : v(home.x + home.depth / 2 + 5, terrainHeight(home.x + home.depth / 2 + 5, home.z) + 0.35, home.z);
  oldHomeTransit = { home, enter, from: pos, to, t: 0, duration: 0.85 };
  activeOldHome = enter ? home : activeOldHome;
  player.vel.set(0, 0, 0);
  player.rail = null;
  player.grounded = true;
  cameraHardCut = false;
  home.roof.visible = false;
  flash(enter ? "INSIDE THE OLD HOUSE · E near doorway to go outside." : "LEAVING THE HOUSE", 1.6);
}
function handleOldHomeInteraction() {
  if (oldHomeTransit) return true;
  if (activeOldHome) {
    const home = activeOldHome;
    if (Math.hypot(player.pos.x - (home.x + home.depth / 2 - 4), player.pos.z - home.z) < 8) {
      openOldHome(home, false);
      return true;
    }
    return false;
  }
  for (const h of oldHomeInteriors) {
    if (
      Math.hypot(player.pos.x - h.door.x, player.pos.z - h.door.z) < 7 &&
      Math.abs(player.pos.y - h.by) < 4
    ) {
      openOldHome(h, true);
      return true;
    }
  }
  return false;
}
function updateWestside(dt) {
  updateHospitalDoors(dt);
  if (Math.hypot(player.pos.x + 33, player.pos.z - 80) > 9) trampolineBounceCount = 0;
  trampolineFlex = Math.max(0, trampolineFlex - dt * 2.8);
  if (trampolineGroup?.children[1])
    trampolineGroup.children[1].position.y = 1.45 - 0.35 * Math.sin(trampolineFlex * Math.PI);
  if (oldHomeTransit) {
    const q = oldHomeTransit;
    q.t = Math.min(q.duration, q.t + dt);
    const t = q.t / q.duration,
      s = t * t * (3 - 2 * t);
    player.pos.copy(q.from).lerp(q.to, s);
    player.vel.set(0, 0, 0);
    player.rail = null;
    player.grounded = true;
    if (q.t >= q.duration) {
      activeOldHome = q.enter ? q.home : null;
      q.home.roof.visible = !q.enter;
      oldHomeTransit = null;
    }
  }
  if (activeOldHome && !oldHomeTransit) {
    const h = activeOldHome;
    player.pos.x = THREE.MathUtils.clamp(player.pos.x, h.x - h.depth / 2 + 0.7, h.x + h.depth / 2 - 0.7);
    player.pos.z = THREE.MathUtils.clamp(player.pos.z, h.z - h.width / 2 + 0.7, h.z + h.width / 2 - 0.7);
    if (player.pos.y < h.by + 0.32) {
      player.pos.y = h.by + 0.35;
      player.vel.y = 0;
      player.grounded = true;
    }
  }
  if (treehouseSite.roof) {
    const h = treehouseSite;
    const visit =
      Math.abs(player.pos.x - h.x) < 6.9 &&
      Math.abs(player.pos.z - h.z) < 5.9 &&
      player.pos.y > h.base + h.height - 0.7;
    h.roof.visible = !visit;
  }
  for (const t of turtles) {
    t.phase += dt * 0.15;
    const x = t.x + Math.sin(t.phase + 0.5) * 2.3,
      z = t.z + Math.cos(t.phase * 0.87) * 2.0;
    t.g.position.x = THREE.MathUtils.lerp(t.g.position.x, x, Math.min(1, dt * 0.35));
    t.g.position.z = THREE.MathUtils.lerp(t.g.position.z, z, Math.min(1, dt * 0.35));
    t.g.position.y = terrainHeight(t.g.position.x, t.g.position.z);
    t.g.rotation.y = Math.atan2(x - t.g.position.x, z - t.g.position.z);
  }
  for (const d of chainedDogs) {
    d.phase += dt * 0.7;
    d.g.position.x = d.x + Math.sin(d.phase) * d.radius * 0.55;
    d.g.position.z = d.z + Math.cos(d.phase) * d.radius * 0.48;
    d.g.position.y = terrainHeight(d.g.position.x, d.g.position.z);
    const a = d.g.position.clone().add(v(0, 0.8, 0)),
      b = d.stake,
      offset = b.clone().sub(a),
      length = offset.length();
    d.leash.position.copy(a).add(b).multiplyScalar(0.5);
    d.leash.quaternion.setFromUnitVectors(v(0, 1, 0), offset.normalize());
    d.leash.scale.y = length / Math.sqrt((d.stake.x - d.x) ** 2 + (d.stake.z - d.z) ** 2 + 0.69 ** 2);
    if (
      Math.hypot(player.pos.x - d.g.position.x, player.pos.z - d.g.position.z) < 9 &&
      player.pos.y < 4 &&
      Math.floor(time) % 9 === 0 &&
      Math.random() < dt * 0.3
    )
      flash("A yard dog barks from its lead!", 1.6);
  }
  policeRoof.visible = true; // The guarded station is never a freely enterable interior.
  for (const o of precinctOfficers) {
    o.t += dt * 0.21;
    o.g.position.x = o.x + Math.sin(o.t) * 3;
    o.g.position.z = o.z + Math.cos(o.t) * 3;
    o.g.position.y = terrainHeight(o.g.position.x, o.g.position.z);
  }
  if (
    !oldGas.closed &&
    time - oldGas.lastAttack < 50 &&
    Math.hypot(player.pos.x - oldGas.x, player.pos.z - oldGas.z) < 66
  ) {
    oldGas.attackSeconds += dt;
  }
  if (!oldGas.closed && oldGas.attackSeconds >= 600 && oldGas.bites >= 3) {
    oldGas.closed = true;
    oldGas.sign.visible = true;
    flash("WESTSIDE FUEL CLOSED · We are closed due to violent dangerous squirrels!", 5);
  }
  // If it was closed earlier, the sign remains for the entire current run.
}
// E works at open-house garage entrances as well as existing sewer/vent interactions.
const _previousInteraction = handleInteraction;
handleInteraction = function () {
  if (handleOldHomeInteraction()) return true;
  return _previousInteraction();
};
// Count actual bites only, not button clicks; time towards gas closure runs during sustained attacks.
const _previousOnBite = onSuccessfulBite;
onSuccessfulBite = function (n) {
  _previousOnBite(n);
  if (n?.root && Math.hypot(n.root.position.x - oldGas.x, n.root.position.z - oldGas.z) < 74) {
    oldGas.lastAttack = time;
    oldGas.bites++;
  }
  // Westside bites follow the same rare police-response rules as every other district.
};
// Each decade of successful bites triggers a brief non-blocking dance animation.
let danceSeconds = 0,
  lastCelebratedDecade = 0;
function animateBiteDance(dt) {
  const decade = Math.floor(player.hits / 10);
  if (decade > lastCelebratedDecade) {
    lastCelebratedDecade = decade;
    if (decade > 0) {
      danceSeconds = 2.1;
      flash(`${player.hits} BITES · THE SQUIRREL DOES A VICTORY DANCE!`, 2.4);
      fx(680, 0.17, "triangle", 0.05);
    }
  }
  if (danceSeconds <= 0) {
    sqroot.rotation.y = 0;
    return;
  }
  danceSeconds = Math.max(0, danceSeconds - dt);
  const t = 2.1 - danceSeconds,
    k = Math.min(1, t * 6, danceSeconds * 6);
  sqroot.rotation.y = Math.sin(t * 12) * 0.78 * k;
  sqroot.rotation.z += Math.sin(t * 15) * 0.17 * k;
  sqroot.position.y += Math.abs(Math.sin(t * 10)) * 0.19 * k;
  sqHead.rotation.y += Math.sin(t * 7) * 0.24 * k;
}
// Trampoline: physical landing and elastic bounce, not a decorative ring.
let trampolineBounceCount = 0,
  trampolineFlex = 0;
function attemptTrampolineBounce(previous) {
  if (player.rail || player.inDuct || player.inHospital || player.inSewer) return false;
  const distance = Math.hypot(player.pos.x + 33, player.pos.z - 80),
    surface = 1.68;
  if (distance >= 4.67 || previous.y < surface + 0.04 || player.pos.y > surface + 0.24 || player.vel.y >= 0)
    return false;
  trampolineBounceCount = Math.min(4, trampolineBounceCount + 1);
  trampolineFlex = 1.0;
  player.pos.y = surface + 0.22;
  player.vel.y = 14.2 + trampolineBounceCount * 0.9;
  player.grounded = false;
  player.committedAirborne = true;
  player.cameraCommit = 0.4;
  const forward = v(-Math.sin(yaw), 0, -Math.cos(yaw));
  player.vel.x += forward.x * 1.6;
  player.vel.z += forward.z * 1.6;
  if (trampolineBounceCount === 1)
    flash("BOING! Hold a direction to steer · bounce again for extra height.", 2.0);
  return true;
}
// Exactly eight pepper locations are retained. Accessible route/ground-space audit,
// with a corrective shift when a candidate was generated inside a wall or solid car.
function auditPepperAccessibility() {
  if (peppers.length !== 8) throw new Error("Pepper hunt must have eight pickups");
  for (const pep of peppers) {
    const p = pep.model.position;
    const ground = terrainHeight(p.x, p.z);
    if (pep.kind === "trunk") {
      const nearest = treeSpec
        .map((t) => ({ t, d: Math.hypot(p.x - t.x, p.z - t.z) }))
        .sort((a, b) => a.d - b.d)[0]?.t;
      if (nearest) {
        const dx = p.x - nearest.x,
          dz = p.z - nearest.z,
          a = Math.atan2(dz, dx);
        p.x = nearest.x + Math.cos(a) * 1.4;
        p.z = nearest.z + Math.sin(a) * 1.4;
        p.y = Math.max(p.y, terrainHeight(p.x, p.z) + 1.0);
      }
    }
    if (pep.kind === "ground") {
      if (p.y < ground + 0.43) p.y = ground + 0.7;
      if (
        commercialBounds.some((b) => Math.abs(p.x - b.x) < b.w / 2 && Math.abs(p.z - b.z) < b.d / 2) ||
        vehicleHitboxAt(p.x, p.z)
      ) {
        p.x += 5.2;
        p.z += 5.2;
        p.y = terrainHeight(p.x, p.z) + 0.75;
      }
    } else {
      const nearby = routes
        .filter((r) => r.kind === pep.kind || (pep.kind === "trunk" && r.kind === "trunk"))
        .flatMap((r) => r.sampled.map((q) => ({ r, q, d: q.distanceTo(p) })))
        .sort((a, b) => a.d - b.d)[0];
      if (nearby && nearby.d > 2.5) {
        p.copy(nearby.q).add(v(0, 0.3, 0));
      }
    }
    pep.baseY = p.y;
  }
}
auditPepperAccessibility();

// --- v1.8 LIVING COMMUNITY, CONTROLLED ENCOUNTERS & EMERGENCY CARE ---
// Medical response is routine; police response is intentionally rare (18% single,
// 5% two cruisers / three officers; all other incidents receive no routine police).
const INCIDENT_SINGLE_POLICE = 0.18,
  INCIDENT_MULTI_POLICE = 0.05;
const WITNESS_MEMORY_SECONDS = 600;
const medicalHome = v(HOSP_X, terrainHeight(HOSP_X, 295) + 0.1, 295);
function pathPoint(x, z) {
  return v(x, terrainHeight(x, z) + 0.13, z);
}
function makeRoadTrip(destination) {
  // City-street approach via west arterial, then a horizontal connecting street.
  // All but the short hospital driveway use axis-aligned legs; no diagonal lawn driving.
  const p = [medicalHome.clone(), pathPoint(HOSP_X, 283), pathPoint(-289, 283)];
  const tx = destination.x,
    tz = destination.z;
  if (tx < -255) {
    p.push(pathPoint(-289, tz), destination.clone());
  } else {
    p.push(pathPoint(-289, -179), pathPoint(-180, -179));
    if (Math.abs(tx + 180) < 4) {
      p.push(pathPoint(-180, tz));
    } else if (tz < -240) {
      p.push(pathPoint(-180, -174), pathPoint(0, -174), pathPoint(0, -305), destination.clone());
    } else {
      const crossZ = tz < -239 ? -174 : tz > 220 ? 171 : Math.abs(tz - 171) < Math.abs(tz) ? 171 : 0;
      p.push(pathPoint(-180, crossZ));
      const junctionX = tx > 267 ? 347 : tx;
      p.push(pathPoint(junctionX, crossZ), pathPoint(junctionX, tz));
    }
    p.push(destination.clone());
  }
  return p.filter((point, i) => i === 0 || point.distanceTo(p[i - 1]) > 0.35);
}
function queueMedicalResponse(victim, stage) {
  let a = responderAmbulances.find((amb) => amb.userData.state === "idle");
  if (!a) {
    victim.queuedMedical = true;
    victim.medicalStage = stage;
    return;
  }
  a.visible = false;
  a.position.copy(medicalHome);
  a.userData = {
    state: "waiting",
    wait: 9 + Math.random() * 10,
    target: victim,
    stage,
    route: makeRoadTrip(stage.stop),
    leg: 0,
    triage: 0,
    medic: null,
    responseStyle: Math.floor(Math.random() * 3),
    crewDelay: 0,
  };
  victim.queuedMedical = false;
}
function advanceVehicleRoute(vehicle, ud, dt, speed, reverse = false) {
  const route = ud.route;
  if (reverse && ud.leg < 0) return true;
  if (!reverse && ud.leg >= route.length - 1) return true;
  const dest = route[ud.leg + (reverse ? 0 : 1)];
  const delta = dest.clone().sub(vehicle.position);
  delta.y = 0;
  const length = delta.length();
  if (length < 0.7) {
    ud.leg += reverse ? -1 : 1;
    return reverse ? ud.leg < 0 : ud.leg >= route.length - 1;
  }
  delta.multiplyScalar(1 / length);
  vehicle.position.addScaledVector(delta, Math.min(length, speed * dt));
  vehicle.rotation.y = Math.atan2(delta.x, delta.z);
  vehicle.position.y = terrainHeight(vehicle.position.x, vehicle.position.z) + 0.1;
  return false;
}
const ambulanceMedics = [];
const ambulanceStretchers = [];
for (const amb of responderAmbulances) {
  const medic = new THREE.Group();
  scene.add(medic);
  medic.visible = false;
  const shirt = mat("#f4f1e7"),
    pants = mat("#4b637a"),
    skin = mat("#bd9377");
  box(0.68, 1.1, 0.42, shirt, 0, 1.4, 0, medic);
  ball(0.28, skin, 0, 2.14, 0, medic);
  for (const xx of [-0.2, 0.2]) span(v(xx, 1.0, 0), v(xx, 0.1, 0), 0.14, 0.11, pants, medic, 6);
  for (const xx of [-0.44, 0.44]) span(v(xx, 1.75, 0), v(xx * 0.97, 0.9, 0.2), 0.12, 0.08, shirt, medic, 6);
  ambulanceMedics.push({ amb, group: medic });
  const stretcher = new THREE.Group();
  scene.add(stretcher);
  stretcher.visible = false;
  box(2.0, 0.14, 0.8, mat("#c9d0cc"), 0, 0.64, 0, stretcher);
  box(1.75, 0.18, 0.74, mat("#708694"), 0, 0.78, 0, stretcher);
  for (const xx of [-0.72, 0.72])
    for (const zz of [-0.31, 0.31]) {
      span(v(xx, 0.52, zz), v(xx, 0.18, zz), 0.047, 0.045, M.metal, stretcher);
      ball(0.115, M.black, xx, 0.16, zz, stretcher);
    }
  ambulanceStretchers.push({ amb, group: stretcher });
}
function finishTreatment(n) {
  n.visible = false;
  n.root.visible = false;
  n.sceneHot = false;
  n.injured = false;
  n.injuryMoanAt = 0;
  n.medicalTriage = false;
  n.medicalPickup = false;
  n.medicalTransit = false;
  n.body.rotation.set(0, 0, 0);
  n.body.position.set(0, 0, 0);
  n.head.rotation.set(0, 0, 0);
  if (n.bike) {
    n.bike.rotation.set(0, 0, 0);
    n.bike.position.set(0, 0.1, 0);
  }
  if (n.redEyes)
    for (const eye of n.redEyes) {
      eye.visible = false;
      eye.material.emissiveIntensity = 0;
    }
  n.hospital = Boolean(n.hospitalRole || n.motorcycle || n.sceneAssignment !== undefined);
  n.timeAway = 0;
  n.maxLife = R(24, 55);
  n.witnessUntil = 0;
}
// Collision-aware sidewalk walking. The corners are intentionally spaced from
// walls, so two medics pushing a stretcher have room to turn without clipping.
let medicalBuildingCache = [],
  medicalBuildingCount = -1;
function medicalBuildings() {
  const count = houses.length + commercialBounds.length;
  if (count !== medicalBuildingCount) {
    medicalBuildingCache = houses.concat(commercialBounds);
    medicalBuildingCount = count;
  }
  return medicalBuildingCache;
}
function medicalSegmentBlocked(a, b) {
  for (const h of medicalBuildings()) {
    const x0 = h.x - h.w / 2 - 0.92,
      x1 = h.x + h.w / 2 + 0.92,
      z0 = h.z - h.d / 2 - 0.92,
      z1 = h.z + h.d / 2 + 0.92;
    let t0 = 0,
      t1 = 1,
      dx = b.x - a.x,
      dz = b.z - a.z;
    const clip = (p, q) => {
      if (Math.abs(p) < 1e-9) return q >= 0;
      const r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        t0 = Math.max(t0, r);
      } else {
        if (r < t0) return false;
        t1 = Math.min(t1, r);
      }
      return true;
    };
    if (clip(-dx, a.x - x0) && clip(dx, x1 - a.x) && clip(-dz, a.z - z0) && clip(dz, z1 - a.z) && t0 <= t1)
      return true;
  }
  return false;
}
function medicalWalkRoute(from, to) {
  const source = from.clone(),
    destination = to.clone();
  if (!medicalSegmentBlocked(source, destination)) return [source, destination];
  const all = [source, destination];
  const near = medicalBuildings()
    .filter((h) => {
      const dx = destination.x - source.x,
        dz = destination.z - source.z;
      const t = THREE.MathUtils.clamp(
        ((h.x - source.x) * dx + (h.z - source.z) * dz) / (dx * dx + dz * dz || 1),
        0,
        1,
      );
      return Math.hypot(h.x - source.x - dx * t, h.z - source.z - dz * t) < Math.max(h.w, h.d) / 2 + 11;
    })
    .slice(0, 18);
  for (const h of near) {
    const px = h.w / 2 + 2.65,
      pz = h.d / 2 + 2.65;
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) all.push(v(h.x + sx * px, 0, h.z + sz * pz));
  }
  const n = all.length,
    dist = Array(n).fill(Infinity),
    previous = Array(n).fill(-1),
    used = Array(n).fill(false);
  dist[0] = 0;
  for (let step = 0; step < n; step++) {
    let u = -1;
    for (let i = 0; i < n; i++) if (!used[i] && (u < 0 || dist[i] < dist[u])) u = i;
    if (u < 0 || !isFinite(dist[u]) || u === 1) break;
    used[u] = true;
    for (let j = 0; j < n; j++)
      if (j !== u && !used[j] && !medicalSegmentBlocked(all[u], all[j])) {
        const d = dist[u] + Math.hypot(all[u].x - all[j].x, all[u].z - all[j].z);
        if (d < dist[j]) {
          dist[j] = d;
          previous[j] = u;
        }
      }
  }
  if (!isFinite(dist[1])) return [source, destination]; // rare unusual lot configuration
  const path = [];
  let node = 1;
  while (node >= 0) {
    path.unshift(all[node]);
    node = previous[node];
    if (path.length > n) break;
  }
  return path;
}
function medicalWalkDistance(points) {
  let length = 0;
  for (let i = 1; i < points.length; i++)
    length += Math.hypot(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z);
  return length;
}
function medicalWalkPoint(points, t) {
  let remaining = medicalWalkDistance(points) * THREE.MathUtils.clamp(t, 0, 1);
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1],
      b = points[i],
      length = Math.hypot(b.x - a.x, b.z - a.z);
    if (remaining <= length || i === points.length - 1)
      return a.clone().lerp(b, length > 0 ? Math.min(1, remaining / length) : 1);
    remaining -= length;
  }
  return points[points.length - 1].clone();
}

// Each truck carries two caregivers; one can assess while the other handles equipment.
const medicalTeams = new Map();
for (let i = 0; i < responderAmbulances.length; i++) {
  const amb = responderAmbulances[i];
  const first = ambulanceMedics.find((m) => m.amb === amb)?.group;
  if (!first) continue;
  box(0.32, 0.46, 0.12, mat("#a23735"), 0.39, 1.42, 0.28, first); // trauma pouch
  const second = new THREE.Group();
  scene.add(second);
  second.visible = false;
  box(0.68, 1.08, 0.44, mat(i === 1 ? "#e2f0e9" : "#e9e9df"), 0, 1.42, 0, second);
  box(0.34, 0.15, 0.08, mat("#ca5449"), 0, 1.65, 0.26, second);
  ball(0.28, mat(["#c39a78", "#b98765", "#966b58"][i]), 0, 2.15, 0, second);
  for (const x of [-0.2, 0.2]) span(v(x, 0.98, 0), v(x, 0.1, 0), 0.12, 0.11, mat("#415d72"), second);
  for (const x of [-0.43, 0.43]) span(v(x, 1.84, 0), v(x, 0.91, 0.12), 0.12, 0.09, mat("#e1e7e0"), second);
  const receiver = new THREE.Group();
  scene.add(receiver);
  receiver.visible = false;
  box(0.78, 1.2, 0.5, mat("#73aca3"), 0, 1.4, 0, receiver);
  ball(0.3, mat("#b88d71"), 0, 2.19, 0, receiver);
  for (const x of [-0.22, 0.22]) span(v(x, 1.03, 0), v(x, 0.1, 0), 0.13, 0.1, mat("#566872"), receiver);
  for (const x of [-0.52, 0.52]) span(v(x, 1.76, 0), v(x, 0.91, 0.1), 0.12, 0.1, mat("#77a9a2"), receiver);
  const clipboard = box(0.42, 0.58, 0.05, mat("#b69d78"), 0.54, 1.44, 0.28, receiver);
  const kit = new THREE.Group();
  scene.add(kit);
  kit.visible = false;
  box(0.9, 0.65, 0.52, mat("#a74237"), 0, 0.38, 0, kit);
  box(0.37, 0.08, 0.03, mat("#f1f0e8"), 0, 0.57, 0.27, kit);
  medicalTeams.set(amb, {
    first,
    second,
    receiver,
    kit,
    stretcher: ambulanceStretchers.find((m) => m.amb === amb)?.group,
    index: i,
    speaker: {
      root: first,
      name: ["Paramedic Lee", "Paramedic Quinn", "Paramedic Morgan"][i],
      idx: 87 + i,
      visible: false,
      sayCooldown: 0,
      personality: "brave",
    },
  });
}
function emergencyY(x, z) {
  return terrainHeight(x, z) + 0.13;
}
function clinicDepthY(z) {
  return z > HOSP_Z - HOSP_D / 2 + 2 ? HOSPITAL_FLOOR + 0.1 : terrainHeight(HOSP_X, z) + 0.12;
}
function orientResponder(mesh, forward) {
  if (forward.lengthSq() > 0.0001) mesh.rotation.y = Math.atan2(forward.x, forward.z);
}
function treatmentArrivalLine(team, spoken) {
  if (Math.hypot(player.pos.x - team.first.position.x, player.pos.z - team.first.position.z) > 45) return;
  team.speaker.root = team.first;
  team.speaker.visible = true;
  if (spoken === "assess")
    say(
      team.speaker,
      pick([
        "We are here. Give us some room, please.",
        "Can you hear me? Stay still.",
        "Keep the path clear for the stretcher.",
      ]),
    );
  if (spoken === "handoff")
    say(
      team.speaker,
      pick([
        "Patient arriving at emergency intake.",
        "We need a nurse at triage, please.",
        "Ready to transfer on three.",
      ]),
    );
}
function placeSceneCrew(team, route, t, walking, loaded, variation) {
  const p = medicalWalkPoint(route, THREE.MathUtils.clamp(t, 0, 1));
  const pb = medicalWalkPoint(route, THREE.MathUtils.clamp(t + (walking ? 0.012 : -0.012), 0, 1));
  const dir = pb.sub(p).setY(0);
  if (dir.lengthSq() < 0.0001) dir.set(0, 0, 1);
  dir.normalize();
  const right = v(dir.z, 0, -dir.x);
  const pos = p.clone();
  pos.y = emergencyY(pos.x, pos.z);
  const stretcher = team.stretcher;
  stretcher.position.copy(pos);
  stretcher.rotation.y = Math.atan2(-dir.z, dir.x);
  team.first.position.copy(pos).addScaledVector(dir, 0.8).addScaledVector(right, 0.92);
  team.second.position.copy(pos).addScaledVector(dir, -0.75).addScaledVector(right, -0.88);
  for (const m of [team.first, team.second]) {
    m.position.y = emergencyY(m.position.x, m.position.z);
    orientResponder(m, dir);
  }
  if (loaded) team.kit.visible = false;
}
function rideMedicalStretcher(patient, trolley) {
  if (!patient) return;
  patient.visible = true;
  patient.root.visible = true;
  patient.medicalPickup = true;
  patient.root.position.copy(trolley.position).add(v(0, 0.68, 0));
  patient.root.rotation.y = trolley.rotation.y;
  patient.body.rotation.x = PI / 2;
  patient.body.rotation.z = 0;
  for (const leg of patient.legs) leg.rotation.x = -0.15;
}
function beginHospitalHandoff(amb, ud, team) {
  ud.state = "receive";
  ud.stageElapsed = 0;
  ud.laneX = HOSP_X + (team.index - 1) * 3.4;
  const parking = v(
    medicalHome.x + (team.index - 1) * 5.9,
    emergencyY(medicalHome.x + (team.index - 1) * 5.9, medicalHome.z),
    medicalHome.z,
  );
  amb.position.copy(parking);
  team.first.visible = true;
  team.second.visible = true;
  team.stretcher.visible = true;
  team.receiver.visible = true;
  ud.dock = v(ud.laneX, emergencyY(ud.laneX, HOSP_Z - HOSP_D / 2 - 11), HOSP_Z - HOSP_D / 2 - 11);
  team.stretcher.position.copy(ud.dock);
  team.receiver.position.set(ud.laneX - 1.7, HOSPITAL_FLOOR + 0.1, HOSP_Z - HOSP_D / 2 + 7);
  if (ud.target) {
    ud.target.medicalTransit = false;
    ud.target.medicalTriage = true;
    rideMedicalStretcher(ud.target, team.stretcher);
  }
  hospitalDoorHold = Math.max(hospitalDoorHold, 8);
}
function updateMedicalResponders(dt) {
  for (const amb of responderAmbulances) {
    const ud = amb.userData,
      n = ud.target,
      team = medicalTeams.get(amb);
    if (ud.state === "idle" || !team?.stretcher) continue;
    if (ud.state === "waiting") {
      ud.wait -= dt;
      if (ud.wait <= 0) {
        amb.visible = true;
        amb.position.copy(medicalHome);
        ud.state = "outbound";
        ud.leg = 0;
      }
    } else if (ud.state === "outbound") {
      if (advanceVehicleRoute(amb, ud, dt, 24 + (ud.responseStyle === 2 ? 3 : 0))) {
        ud.state = "approach";
        ud.stageElapsed = 0;
        ud.walkPath = medicalWalkRoute(
          amb.position.clone().add(v(2, 0, 0)),
          n?.root?.position || amb.position,
        );
        ud.walkTime = Math.max(3, Math.min(55, medicalWalkDistance(ud.walkPath) / 3.45));
        team.first.visible = true;
        team.second.visible = true;
        team.stretcher.visible = true;
        team.kit.visible = false;
        placeSceneCrew(team, ud.walkPath, 0, true, false, ud.responseStyle);
      }
    } else if (ud.state === "approach") {
      ud.stageElapsed += dt;
      const t = Math.min(1, ud.stageElapsed / ud.walkTime);
      placeSceneCrew(team, ud.walkPath, t, true, false, ud.responseStyle);
      // One variation sends the first medic to the patient before the stretcher.
      if (ud.responseStyle === 1) {
        const advance = medicalWalkPoint(ud.walkPath, Math.min(1, t + 0.19));
        team.first.position.set(advance.x, emergencyY(advance.x, advance.z), advance.z);
      }
      if (t >= 1) {
        ud.state = "assess";
        ud.stageElapsed = 0;
        ud.assessment = ud.responseStyle === 2 ? 2.1 : ud.responseStyle === 1 ? 5.0 : 3.3;
        if (n) {
          team.kit.visible = true;
          team.kit.position.copy(n.root.position).add(v(0.9, 0, 0.6));
        }
        treatmentArrivalLine(team, "assess");
      }
    } else if (ud.state === "assess") {
      ud.stageElapsed += dt;
      // Visible crouch, arm gesture, equipment examination; second medic readies trolley.
      const crouch = Math.sin((Math.min(1, ud.stageElapsed / 0.7) * PI) / 2);
      team.first.rotation.x = -0.18 * crouch;
      team.first.position.y = emergencyY(team.first.position.x, team.first.position.z) - 0.2 * crouch;
      team.second.rotation.x = Math.sin(time * 1.1) * 0.055;
      if (ud.stageElapsed >= ud.assessment) {
        ud.state = "load";
        ud.stageElapsed = 0;
        team.first.rotation.x = 0;
        team.second.rotation.x = 0;
      }
    } else if (ud.state === "load") {
      ud.stageElapsed += dt;
      const t = Math.min(1, ud.stageElapsed / (ud.responseStyle === 2 ? 2.15 : 3.25));
      team.kit.visible = false;
      if (n) {
        if (!ud.liftOrigin) ud.liftOrigin = n.root.position.clone();
        n.medicalPickup = true;
        const trolleyPos = team.stretcher.position.clone().add(v(0, 0.68, 0));
        n.root.position.copy(ud.liftOrigin).lerp(trolleyPos, THREE.MathUtils.smoothstep(t, 0, 1));
        n.body.rotation.x = (PI / 2) * THREE.MathUtils.smoothstep(t, 0, 1);
      }
      team.first.rotation.x = -0.1 * Math.sin(t * PI);
      if (t >= 1) {
        ud.state = "retrieve";
        ud.stageElapsed = 0;
      }
    } else if (ud.state === "retrieve") {
      ud.stageElapsed += dt;
      const t = Math.max(0, 1 - ud.stageElapsed / ud.walkTime);
      placeSceneCrew(team, ud.walkPath, t, false, true, ud.responseStyle);
      if (n) rideMedicalStretcher(n, team.stretcher);
      if (t <= 0) {
        if (n) {
          n.visible = false;
          n.root.visible = false;
          n.medicalTransit = true;
          n.medicalPickup = false;
        }
        team.first.visible = false;
        team.second.visible = false;
        team.stretcher.visible = false;
        team.kit.visible = false;
        ud.state = "return";
        ud.leg = ud.route.length - 2;
      }
    } else if (ud.state === "return") {
      if (advanceVehicleRoute(amb, ud, dt, 25, true)) ud.state = "hospitalQueue";
    } else if (ud.state === "hospitalQueue") {
      const active = responderAmbulances.some(
        (other) => other !== amb && ["receive", "admit", "handoff", "sendoff"].includes(other.userData.state),
      );
      const space = medicalHome.clone().add(v((team.index - 1) * 6.5, 0, team.index * 2.2));
      amb.position.copy(space);
      amb.position.y = emergencyY(space.x, space.z);
      if (!active) beginHospitalHandoff(amb, ud, team);
    } else if (ud.state === "receive") {
      ud.stageElapsed += dt;
      hospitalDoorHold = Math.max(hospitalDoorHold, 1.5);
      const t = Math.min(1, ud.stageElapsed / 3.2);
      const from = v(ud.laneX - 1.7, HOSPITAL_FLOOR + 0.12, HOSP_Z - HOSP_D / 2 + 8);
      team.receiver.position.copy(from).lerp(ud.dock.clone().add(v(-1.6, 0, 0)), t);
      team.receiver.position.y = clinicDepthY(team.receiver.position.z);
      team.receiver.rotation.y = PI;
      if (n) rideMedicalStretcher(n, team.stretcher);
      if (t >= 1) {
        ud.state = "admit";
        ud.stageElapsed = 0;
        treatmentArrivalLine(team, "handoff");
      }
    } else if (ud.state === "admit") {
      ud.stageElapsed += dt;
      hospitalDoorHold = Math.max(hospitalDoorHold, 2.0);
      const t = THREE.MathUtils.smoothstep(Math.min(1, ud.stageElapsed / 8.0), 0, 1);
      const last = v(ud.laneX, HOSPITAL_FLOOR + 0.12, HOSP_Z - HOSP_D / 2 + 23);
      team.stretcher.position.copy(ud.dock).lerp(last, t);
      team.stretcher.position.y = clinicDepthY(team.stretcher.position.z);
      team.stretcher.rotation.y = -PI / 2; // stretcher long axis points down the entry hallway
      const p = team.stretcher.position;
      team.first.position.set(p.x + 1.08, clinicDepthY(p.z), p.z - 1.0);
      team.second.position.set(p.x - 1.03, clinicDepthY(p.z), p.z + 1.15);
      team.receiver.position.set(p.x - 1.45, clinicDepthY(p.z), p.z + 0.2);
      for (const m of [team.first, team.second, team.receiver]) m.rotation.y = 0;
      if (n) rideMedicalStretcher(n, team.stretcher);
      if (t >= 1) {
        ud.state = "handoff";
        ud.stageElapsed = 0;
      }
    } else if (ud.state === "handoff") {
      ud.stageElapsed += dt;
      hospitalDoorHold = Math.max(hospitalDoorHold, 1.8);
      team.receiver.rotation.y = Math.sin(time * 1.5) * 0.15;
      team.first.rotation.x = -0.05;
      team.second.rotation.x = 0.06;
      if (n) rideMedicalStretcher(n, team.stretcher);
      if (ud.stageElapsed > 5.5) {
        if (n) finishTreatment(n);
        ud.state = "sendoff";
        ud.stageElapsed = 0;
        team.first.rotation.x = 0;
        team.second.rotation.x = 0;
      }
    } else if (ud.state === "sendoff") {
      ud.stageElapsed += dt;
      hospitalDoorHold = Math.max(hospitalDoorHold, 1.8);
      const t = THREE.MathUtils.smoothstep(Math.min(1, ud.stageElapsed / 7.0), 0, 1);
      const inside = v(ud.laneX, HOSPITAL_FLOOR + 0.12, HOSP_Z - HOSP_D / 2 + 23);
      team.stretcher.position.copy(inside).lerp(ud.dock, t);
      team.stretcher.position.y = clinicDepthY(team.stretcher.position.z);
      team.first.position.copy(team.stretcher.position).add(v(1.05, 0, -1));
      team.second.position.copy(team.stretcher.position).add(v(-1.05, 0, 1));
      team.first.position.y = clinicDepthY(team.first.position.z);
      team.second.position.y = clinicDepthY(team.second.position.z);
      team.receiver.position.set(ud.laneX - 1.65, HOSPITAL_FLOOR + 0.1, HOSP_Z - HOSP_D / 2 + 7);
      if (t >= 1) {
        team.first.visible = false;
        team.second.visible = false;
        team.stretcher.visible = false;
        team.receiver.visible = false;
        team.kit.visible = false;
        amb.visible = false;
        amb.userData = { state: "idle", target: null, wait: 0, stage: null };
      }
    }
  }
  for (const n of humanoids) {
    if (
      n.queuedMedical &&
      n.injured &&
      !responderAmbulances.some((a) => a.userData.target === n) &&
      responderAmbulances.some((a) => a.userData.state === "idle")
    )
      queueMedicalResponse(n, n.medicalStage);
  }
}
const incidentPoliceCars = [],
  incidentPoliceOfficers = [];
for (let i = 0; i < 2; i++) {
  const car = makeCar(policeStation.x - 9 + i * 18, policeStation.z + 26, "#e4e8e5", 0, false);
  car.visible = false;
  box(1, 0.2, 0.4, mat("#2e4d83"), 0, 2.24, 0, car);
  box(0.45, 0.25, 0.3, mat("#b53632"), 0.6, 2.22, 0, car);
  incidentPoliceCars.push(car);
}
for (let i = 0; i < 3; i++) {
  const g = new THREE.Group();
  scene.add(g);
  g.visible = false;
  box(0.72, 1.5, 0.52, mat("#3b5274"), 0, 1.25, 0, g);
  ball(0.31, mat("#b99377"), 0, 2.18, 0, g);
  box(0.79, 0.2, 0.65, mat("#242d3b"), 0, 2.49, 0, g);
  for (const xx of [-0.22, 0.22]) span(v(xx, 0.6, 0), v(xx, 0.09, 0), 0.15, 0.11, mat("#263950"), g, 7);
  const baton = span(v(0.65, 1.38, 0.1), v(0.82, 0.43, 0.7), 0.065, 0.052, mat("#353c42"), g);
  incidentPoliceOfficers.push({ g, baton, phase: i * 2, hitCooldown: 0 });
}
const policeIncidents = [];
function rollIncidentPolice(scene) {
  const roll = Math.random();
  if (roll < INCIDENT_MULTI_POLICE) {
    startIncidentPolice(scene, 3, 2);
  } else if (roll < INCIDENT_MULTI_POLICE + INCIDENT_SINGLE_POLICE) {
    startIncidentPolice(scene, 1, 1);
  }
}
function startIncidentPolice(scene, numOfficers, numCars) {
  const p = scene.center;
  if (numOfficers === 1) {
    patrolCar.position.copy(pathPoint(p.x + 12, p.z + 7));
    dispatchCop("A patrol responds to the emergency.");
    copState.alert = Math.max(copState.alert, 43);
    return;
  }
  // Two cars approach from the station before three officers disembark.
  if (policeIncidents.some((e) => e.phase !== "depart")) return;
  const carRoutes = [];
  for (let i = 0; i < 2; i++) {
    const car = incidentPoliceCars[i];
    car.visible = true;
    const start = pathPoint(policeStation.x + (i ? 15 : -15), policeStation.z + 26);
    car.position.copy(start);
    const target = pathPoint(p.x + (i ? 9 : -9), p.z + 10);
    car.userData = {
      route: [start, pathPoint(-300, policeStation.z + 26), pathPoint(-300, p.z + 10), target],
      leg: 0,
    };
    carRoutes.push(car);
  }
  for (const o of incidentPoliceOfficers) o.g.visible = false;
  policeIncidents.push({ center: p.clone(), until: 0, phase: "arrive" });
}
function sendPosterPolice(p) {
  patrolCar.position.copy(pathPoint(p.x + 17, p.z + 12));
  if (!copState.out) dispatchCop("Poster witness called police!");
  copState.alert = Math.max(copState.alert, 52);
}
function updatePoliceResponse(dt) {
  for (let i = policeIncidents.length - 1; i >= 0; i--) {
    const inc = policeIncidents[i];
    if (inc.phase === "arrive") {
      const all = incidentPoliceCars.map((c) => advanceVehicleRoute(c, c.userData, dt, 23));
      if (all.every(Boolean)) {
        inc.phase = "patrol";
        inc.until = time + 48;
        for (const [j, o] of incidentPoliceOfficers.entries()) {
          o.g.visible = true;
          o.g.position.copy(incidentPoliceCars[j % 2].position).add(v((j - 1) * 1.6, 0, 1.8));
          o.hitCooldown = 1.0 + j * 0.5;
        }
      }
    } else if (inc.phase === "patrol" && time >= inc.until) {
      inc.phase = "depart";
      for (const c of incidentPoliceCars) c.userData.leg = c.userData.route.length - 2;
      for (const o of incidentPoliceOfficers) o.g.visible = false;
    } else if (inc.phase === "depart") {
      const arrived = incidentPoliceCars.map((c) => advanceVehicleRoute(c, c.userData, dt, 23, true));
      if (arrived.every(Boolean)) {
        policeIncidents.splice(i, 1);
        for (const c of incidentPoliceCars) c.visible = false;
      }
    }
  }
  const patrol = policeIncidents.some((e) => e.phase === "patrol");
  for (const o of incidentPoliceOfficers) {
    o.g.visible = patrol;
    if (!patrol) continue;
    o.hitCooldown = Math.max(0, o.hitCooldown - dt);
    o.stun = Math.max(0, (o.stun || 0) - dt);
    o.phase += dt;
    if (o.stun > 0) {
      o.windup = 0;
      o.baton.rotation.x = -0.85;
      continue;
    }
    const p = o.g.position,
      delta = player.pos.clone().sub(p).setY(0),
      dist = delta.length();
    const assigned = policeIncidents.find((e) => e.phase === "patrol");
    const investigating =
      assigned && (dist > 27 || player.inHospital || player.inSewer || activeHouseInterior);
    if (investigating) {
      const slot = incidentPoliceOfficers.indexOf(o);
      const offsets = [
        [-3, 1],
        [5, -4],
        [-6, -7],
      ];
      const off = offsets[slot];
      const target = v(assigned.center.x + off[0], 0, assigned.center.z + off[1]);
      if (!o.scenePath || o.scenePathCenter?.distanceToSquared(assigned.center) > 4) {
        o.scenePath = medicalWalkRoute(p, target);
        o.scenePathCenter = assigned.center.clone();
        o.sceneStep = 1;
      }
      const waypoint = o.scenePath[Math.min(o.sceneStep || 1, o.scenePath.length - 1)];
      const toward = waypoint.clone().sub(p).setY(0);
      if (toward.length() < 0.6) o.sceneStep = Math.min((o.sceneStep || 1) + 1, o.scenePath.length - 1);
      else {
        const before = p.clone();
        p.addScaledVector(toward.normalize(), dt * (slot === 0 ? 2.3 : 1.9));
        keepEmergencyActorsOutside(p, before);
        o.g.rotation.y = Math.atan2(toward.x, toward.z);
      }
      // One officer examines the scene, one holds back a crowd, one keeps watch.
      o.baton.rotation.x =
        slot === 0
          ? -0.18 + Math.sin(o.phase * 1.8) * 0.1
          : slot === 1
            ? -0.55
            : Math.sin(o.phase * 0.8) * 0.19;
    } else {
      o.scenePath = null;
      if (dist > 2.0 && !player.inHospital && !player.inSewer && !activeHouseInterior && !(o.stun > 0)) {
        const before = p.clone();
        p.addScaledVector(delta.normalize(), dt * 5.5);
        keepEmergencyActorsOutside(p, before);
      }
      o.g.rotation.y = Math.atan2(player.pos.x - p.x, player.pos.z - p.z);
      o.baton.rotation.x = Math.sin(o.phase * 8) * 0.5;
    }
    p.y = terrainHeight(p.x, p.z);
    if (o.windup > 0) {
      o.windup = Math.max(0, o.windup - dt);
      o.baton.rotation.x = -1.25;
      if (o.windup === 0) {
        o.hitCooldown = 2.4;
        if (dist < 2.9 && !activeHouseInterior && player.pos.y - p.y < 2.3 && !(o.stun > 0)) {
          officerBatonContact(p, 12);
          flash("An officer landed a baton strike!", 1.8);
        }
      }
    } else if (
      dist < 3.4 &&
      !activeHouseInterior &&
      player.pos.y - p.y < 2.4 &&
      o.hitCooldown <= 0 &&
      !(o.stun > 0)
    ) {
      o.windup = 0.48;
      flash("Police closing in — baton raised!", 1.1);
    }
  }
  // The police station is not a dungeon to clear: approach the locked entrance
  // and stationed officers come out to drive the squirrel away.
  const stationDistance = Math.hypot(player.pos.x - policeStation.x, player.pos.z - policeStation.z);
  for (const [i, o] of stationReinforcements.entries()) {
    const active = stationDistance < 40 && !player.inSewer;
    o.g.visible = active;
    if (!active) {
      o.t = 0;
      continue;
    }
    o.stun = Math.max(0, (o.stun || 0) - dt);
    if (o.stun > 0) continue;
    o.t = Math.min(10, o.t + dt);
    const entrance = pathPoint(policeStation.x + (i ? 2 : -2), policeStation.z + 19);
    const p = o.g.position;
    if (o.t < 2) {
      p.lerp(entrance, Math.min(1, dt * 2));
    } else if (stationDistance < 24) {
      const delta = player.pos.clone().sub(p).setY(0),
        dist = delta.length();
      if (dist > 2 && dist < 34) p.addScaledVector(delta.normalize(), dt * 4);
      o.hitCooldown = Math.max(0, o.hitCooldown - dt);
      if (dist < 2.3 && o.hitCooldown === 0 && player.pos.y - p.y < 2.3) {
        o.hitCooldown = 4.4;
        player.vel.y = 2.3;
        player.vel.x = (delta.x / (dist || 1)) * 10;
        player.vel.z = (delta.z / (dist || 1)) * 10;
        flash("More officers emerge from the station — retreat!", 2.1);
      }
    }
    p.y = terrainHeight(p.x, p.z);
  }

  for (const [i, o] of precinctOfficers.entries()) {
    o.stun = Math.max(0, (o.stun || 0) - dt);
    if (o.stun > 0) continue;
    if (stationDistance < 34 && !player.inSewer) {
      const target = player.pos.clone(),
        p = o.g.position;
      const d = target.sub(p).setY(0),
        dist = d.length();
      if (dist > 2 && dist < 30) p.addScaledVector(d.normalize(), Math.min(dist, dt * 3.3));
      p.y = terrainHeight(p.x, p.z);
      o.hitCooldown = Math.max(0, (o.hitCooldown || 0) - dt);
      if (dist < 2.3 && player.pos.y - p.y < 2.4 && o.hitCooldown === 0) {
        o.hitCooldown = 4.1;
        const push = d.lengthSq() > 0.02 ? d.normalize() : v(0, 0, 1);
        player.vel.x = push.x * 11;
        player.vel.z = push.z * 11;
        player.vel.y = 2.4;
        flash("Police station security! The officers will not let you inside.", 2.4);
      }
    }
  }
}
const stationReinforcements = [];
for (let i = 0; i < 2; i++) {
  const g = new THREE.Group();
  scene.add(g);
  g.visible = false;
  g.position.copy(pathPoint(policeStation.x + (i ? 2 : -2), policeStation.z + 11));
  box(0.68, 1.35, 0.49, mat("#354f72"), 0, 1.34, 0, g);
  ball(0.3, mat("#c09979"), 0, 2.24, 0, g);
  box(0.8, 0.19, 0.7, mat("#202b3a"), 0, 2.56, 0, g);
  for (const xx of [-0.2, 0.2]) span(v(xx, 0.66, 0), v(xx, 0.11, 0), 0.15, 0.1, mat("#303e54"), g);
  stationReinforcements.push({ g, t: 0, hitCooldown: 0 });
}
// Existing police station geometry cannot be entered: it is guarded continuously.
commercialBounds.push({ x: policeStation.x, z: policeStation.z, w: 45.8, d: 30.8, roof: stationY + 9.25 });

// Wanted notices materialize after 15 successful bites, near actual footpaths.
const wantedPosterMaterial = (() => {
  const cn = document.createElement("canvas");
  cn.width = 320;
  cn.height = 424;
  const c = cn.getContext("2d");
  c.fillStyle = "#e6dcc3";
  c.fillRect(0, 0, 320, 424);
  c.strokeStyle = "#6b5143";
  c.lineWidth = 13;
  c.strokeRect(9, 9, 302, 405);
  c.fillStyle = "#47322a";
  c.textAlign = "center";
  c.font = "bold 68px Georgia";
  c.fillText("WANTED", 160, 91);
  c.font = "bold 28px Georgia";
  c.fillText("DANGEROUS", 160, 135);
  c.fillStyle = "#493831";
  c.beginPath();
  c.ellipse(160, 240, 64, 81, 0, 0, Math.PI * 2);
  c.fill();
  c.beginPath();
  c.ellipse(206, 197, 42, 45, 0, 0, Math.PI * 2);
  c.fill();
  c.beginPath();
  c.ellipse(117, 178, 14, 30, -0.4, 0, Math.PI * 2);
  c.fill();
  c.fillStyle = "#bd3f2c";
  c.fillRect(212, 183, 10, 10);
  c.fillStyle = "#47322a";
  c.font = "bold 37px Georgia";
  c.fillText("SQUIRREL", 160, 357);
  c.font = "18px Georgia";
  c.fillText("REPORT ALL SIGHTINGS", 160, 391);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return new THREE.MeshBasicMaterial({ map: t, side: THREE.DoubleSide });
})();
// Every seventh actual telephone pole gets a poster, with no separate post
// planted in the road.  The signs appear after NINE successful bites.
const wantedPosters = [];
for (let i = 6; i < utilitySupports.length; i += 7) {
  const p = utilitySupports[i],
    x = p.x,
    z = p.z;
  const by = terrainHeight(x, z);
  const display = box(1.3, 1.79, 0.09, wantedPosterMaterial, x + 0.38, by + 2.45, z + 0.23);
  const backing = box(1.39, 1.88, 0.1, mat("#65594b"), x + 0.39, by + 2.45, z + 0.17);
  display.visible = false;
  backing.visible = false;
  wantedPosters.push({ x, z, ob: display, backing, poleIndex: i + 1 });
}
function updatePosterAwareness(dt) {
  const active = player.hits > 8;
  for (const p of wantedPosters) {
    p.ob.visible = active;
    p.backing.visible = active;
  }
}
let posterVoiceRotation = 0;
function speakWantedRecognition(n) {
  if (!speechOn || !("speechSynthesis" in window) || !("SpeechSynthesisUtterance" in window)) return;
  try {
    const line = "That is the squirrel from that poster!";
    const voiceType = posterVoiceRotation++ % 3;
    const utter = new SpeechSynthesisUtterance(line);
    const voices = speechSynthesis.getVoices();
    if (voices.length) {
      const en = voices.filter((x) => /^en/i.test(x.lang));
      const female = en.filter((x) => /female|samantha|victoria|zira|karen|ava/i.test(x.name));
      const male = en.filter((x) => /male|david|daniel|alex|fred/i.test(x.name));
      const subset = voiceType === 0 ? female : voiceType === 1 ? male : en;
      if (subset.length) utter.voice = subset[0];
    }
    utter.pitch = voiceType === 2 ? 1.65 : voiceType === 1 ? 0.77 : 1.15;
    utter.rate = voiceType === 2 ? 1.16 : 0.97;
    utter.volume = 0.53;
    speechSynthesis.speak(utter);
  } catch (e) {}
}

// Two community routines repeating every 40 minutes, 20 minutes apart.
// Each gathering lasts 10 minutes. No day/night changes or cinematic teleportation.
const livingEvents = [];
function newLivingEvent(kind, center, offset, count) {
  const isBall = kind === "softball";
  const data = { kind, center, offset, count, cycle: null, actors: [], cars: [], smoke: [], active: false };
  const turf = mat(isBall ? "#b18b68" : "#6c725b");
  if (isBall) {
    const diamond = box(31, 0.08, 31, turf, center.x, terrainHeight(center.x, center.z) + 0.09, center.z);
    diamond.rotation.y = Math.PI / 4;
    for (const [x, z] of [
      [0, 0],
      [-8, -8],
      [8, -8],
      [0, -16],
    ])
      box(
        0.6,
        0.11,
        0.6,
        mat("#ecebdc"),
        center.x + x,
        terrainHeight(center.x + x, center.z + z) + 0.16,
        center.z + z,
      );
    // Low backstop; the field stays traversable and isn't a huge opaque structure.
    for (const xx of [-9, 9])
      for (let j = 0; j < 5; j++)
        box(
          0.055,
          5,
          0.07,
          mat("#727d70"),
          center.x + xx,
          terrainHeight(center.x + xx, center.z - 16) + 2.5,
          center.z - 16 + j * 0.2,
        );
  } else {
    barbecue(center.x - 3, center.z - 1, 0.86);
    for (let j = 0; j < 3; j++) {
      const smoke = ball(
        0.42,
        new THREE.MeshBasicMaterial({ color: 0xb6b3a9, transparent: true, opacity: 0.26, depthWrite: false }),
        center.x - 3,
        terrainHeight(center.x - 3, center.z - 1) + 3,
        center.z - 1,
      );
      smoke.visible = false;
      data.smoke.push(smoke);
    }
    for (let j = 0; j < 2; j++)
      box(
        3,
        0.35,
        1.6,
        mat("#a49073"),
        center.x + (j ? 7 : -8),
        terrainHeight(center.x, center.z) + 1.05,
        center.z + (j ? 3 : 5),
      );
  }
  for (let i = 0; i < count; i++) {
    const colors = ["#8a7272", "#687c69", "#a88a54", "#758ba0", "#ab7b61", "#877b9b"];
    const n = makeHuman(
      [
        `${isBall ? "Player" : "Neighbor"} ${i + 1}`,
        isBall ? "softball" : "barbecue",
        -1,
        ["#ae8061", "#d3aa87", "#986c51"][i % 3],
        colors[i % colors.length],
        i % 4 === 0 ? "brave" : "wary",
      ],
      humanoids.length,
    );
    n.hospital = true;
    n.visible = false;
    n.root.visible = false;
    n.eventNPC = true;
    const a = (i * 2 * Math.PI) / count;
    const dest = v(center.x + Math.cos(a) * (isBall ? 10 : 7), 0, center.z + Math.sin(a) * (isBall ? 10 : 7));
    const origin = v(
      center.x + Math.cos(a) * (isBall ? 33 : 35),
      0,
      center.z + Math.sin(a) * (isBall ? 25 : 30),
    );
    data.actors.push({ n, dest, origin, phase: i * 1.8 });
  }
  for (let j = 0; j < 3; j++) {
    const home = v(center.x + (j - 1) * 8, 0, center.z + (isBall ? 40 : -36));
    const parked = v(center.x + (j - 1) * 8, 0, center.z + (isBall ? 26 : -22));
    const car = makeCar(home.x, home.z, ["#7c8e8b", "#977c65", "#627789"][j], Math.PI, false);
    car.visible = false;
    data.cars.push({ car, home, parked });
  }
  livingEvents.push(data);
}
newLivingEvent("barbecue", v(-66, 0, -84), 0, 7);
newLivingEvent("softball", v(66, 0, 356), 1200, 10);
function updateLivingEvents(dt) {
  for (const e of livingEvents) {
    const elapsed = time - e.offset;
    const cycle = Math.floor(elapsed / 2400);
    const phase = ((elapsed % 2400) + 2400) % 2400;
    const ongoing = elapsed >= 0 && phase < 600;
    const departing = elapsed >= 0 && phase >= 600 && phase < 655;
    if (ongoing && e.cycle !== cycle) {
      e.cycle = cycle;
      e.active = true;
      for (const a of e.actors)
        if (!a.n.injured) {
          a.n.root.position.copy(a.origin);
          a.n.root.position.y = terrainHeight(a.origin.x, a.origin.z) + 0.13;
          a.n.visible = true;
          a.n.root.visible = true;
          a.n.sayCooldown = 0;
        }
      for (const c of e.cars) c.car.visible = true;
    }
    if (!ongoing && !departing) {
      e.active = false;
      for (const a of e.actors)
        if (!a.n.injured) {
          a.n.visible = false;
          a.n.root.visible = false;
        }
      for (const c of e.cars) c.car.visible = false;
      for (const s of e.smoke) s.visible = false;
      continue;
    }
    for (const [i, a] of e.actors.entries()) {
      const n = a.n;
      if (n.injured) continue;
      n.visible = n.root.visible = true;
      n.sayCooldown = Math.max(0, (n.sayCooldown || 0) - dt);
      n.reacting = Math.max(0, (n.reacting || 0) - dt);
      let target;
      if (phase < 55) {
        target = a.origin.clone().lerp(a.dest, Math.min(1, phase / 55));
      } else if (phase < 600) {
        const swirl = (phase - 55) * 0.38 + a.phase;
        const movement = e.kind === "softball" ? 3.5 : 1.7;
        target = a.dest.clone().add(v(Math.sin(swirl) * movement, 0, Math.cos(swirl * 0.7) * movement));
      } else target = a.dest.clone().lerp(a.origin, Math.min(1, (phase - 600) / 55));
      const dx = target.x - n.root.position.x,
        dz = target.z - n.root.position.z;
      n.root.position.x = THREE.MathUtils.lerp(n.root.position.x, target.x, Math.min(1, dt * 2.2));
      n.root.position.z = THREE.MathUtils.lerp(n.root.position.z, target.z, Math.min(1, dt * 2.2));
      n.root.position.y = terrainHeight(n.root.position.x, n.root.position.z) + 0.13;
      if (Math.hypot(dx, dz) > 0.04) n.root.rotation.y = Math.atan2(dx, dz);
      const squirrelDistance = Math.hypot(n.root.position.x - player.pos.x, n.root.position.z - player.pos.z);
      const threatened =
        squirrelDistance < 16 &&
        !player.inSewer &&
        !player.inHospital &&
        !activeHouseInterior &&
        player.pos.y < 4.7;
      if (threatened) {
        n.witnessUntil = Math.max(n.witnessUntil || 0, time + 600);
        n.reacting = Math.max(n.reacting, 3.5);
        const previousPosition = n.root.position.clone();
        const flee = n.root.position.clone().sub(player.pos).setY(0);
        if (flee.lengthSq() > 0.2) {
          const separation = flee.normalize();
          n.root.position.addScaledVector(separation, dt * (squirrelDistance < 7 ? 6.5 : 4.2));
          n.root.rotation.y = Math.atan2(separation.x, separation.z);
        }
        keepEmergencyActorsOutside(n.root.position, previousPosition);
        n.root.position.y = terrainHeight(n.root.position.x, n.root.position.z) + 0.13;
        if (n.sayCooldown <= 0)
          say(
            n,
            pick([
              "Oh no, it’s that squirrel!",
              "Everybody, get away from it!",
              "What the hell is that thing doing here?!",
              "Get back! It just attacked someone!",
            ]),
          );
      }
      const gait = Math.sin(time * (e.kind === "softball" ? 7 : 4) + i) * (threatened ? 0.58 : 0.36);
      for (let k = 0; k < 2; k++) {
        n.legs[k].rotation.x = (k ? 1 : -1) * gait;
        n.arms[k].rotation.x = threatened ? -1.55 + Math.sin(time * 10 + k * 3) * 0.28 : -(k ? 1 : -1) * gait;
      }
      n.head.rotation.y = threatened ? Math.sin(time * 12) * 0.29 : 0;
      n.body.rotation.z = threatened ? Math.sin(time * 9) * 0.07 : 0;
    }
    for (const [i, c] of e.cars.entries()) {
      const t = ongoing ? Math.min(1, phase / 48) : Math.max(0, 1 - (phase - 600) / 50);
      c.car.visible = true;
      c.car.position.copy(c.home.clone().lerp(c.parked, t));
      c.car.position.y = terrainHeight(c.car.position.x, c.car.position.z) + 0.07;
    }
    for (const [i, smoke] of e.smoke.entries()) {
      smoke.visible = ongoing && phase > 38;
      if (smoke.visible) {
        const theta = (time * 0.5 + i * 0.65) % 3.5;
        smoke.position.set(
          e.center.x - 3 + Math.sin(time * 0.6 + i) * 0.5,
          terrainHeight(e.center.x - 3, e.center.z - 1) + 2.8 + theta,
          e.center.z - 1 + Math.cos(time * 0.7 + i) * 0.3,
        );
        smoke.scale.setScalar(0.7 + theta * 0.32);
      }
    }
  }
}
// --- v1.9: active household cats. They patrol, stalk, swat and can be dodged. ---
const yardCats = [];
function makeYardCat(index, x, z, shade) {
  const root = new THREE.Group();
  scene.add(root);
  const fur = mat(shade),
    lightFur = mat(index ? "#ddd3bd" : "#bd9f7e"),
    eyes = mat("#d7e36e");
  const body = ball(0.72, fur, 0, 0.58, -0.13, root);
  body.scale.set(0.8, 0.52, 1.28);
  const head = ball(0.38, fur, 0, 0.78, 0.62, root);
  head.scale.set(1, 0.86, 0.91);
  for (const side of [-1, 1]) {
    const ear = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.34, 4), fur);
    ear.position.set(side * 0.28, 1.13, 0.6);
    ear.rotation.z = side * 0.14;
    root.add(ear);
    ball(0.086, eyes, side * 0.17, 0.83, 0.94, root);
    ball(0.038, M.black, side * 0.17, 0.84, 1.015, root);
    for (const z2 of [-0.43, 0.42]) box(0.2, 0.51, 0.21, lightFur, side * 0.38, 0.22, z2, root);
  }
  ball(0.085, mat("#bb8b89"), 0, 0.67, 1.0, root);
  const tail = new THREE.Group();
  tail.position.set(0, 0.64, -0.8);
  root.add(tail);
  span(v(0, 0, 0), v(0.28, 0.42, -0.55), 0.14, 0.105, fur, tail, 8);
  span(v(0.28, 0.42, -0.55), v(0.38, 0.7, -0.87), 0.105, 0.07, fur, tail, 8);
  const cat = {
    root,
    tail,
    x,
    z,
    phase: index * 2.83,
    home: v(x, 0, z),
    state: "wander",
    windup: 0,
    hitCooldown: 0,
    voiceCooldown: 0,
    target: null,
  };
  root.position.set(x, terrainHeight(x, z) + 0.11, z);
  yardCats.push(cat);
  return cat;
}
makeYardCat(0, hNW.x + 11, hNW.z - 23, "#80614b");
makeYardCat(1, hSE.x - 10, hSE.z + 23, "#454647");
makeYardCat(2, hNE.x - 11, hNE.z - 20, "#a19e88");
function catSafeMove(cat, desired, dt) {
  const p = cat.root.position;
  const dx = desired.x - p.x,
    dz = desired.z - p.z,
    mag = Math.hypot(dx, dz);
  if (mag < 0.12) return;
  const speed = cat.state === "chase" ? 8.5 : cat.state === "stalk" ? 3.1 : 1.6;
  const nx = p.x + (dx / mag) * Math.min(mag, speed * dt),
    nz = p.z + (dz / mag) * Math.min(mag, speed * dt);
  const inside = houses.some((h) => Math.abs(nx - h.x) < h.w / 2 + 1 && Math.abs(nz - h.z) < h.d / 2 + 1);
  if (!inside) {
    p.x = nx;
    p.z = nz;
  }
  p.y = terrainHeight(p.x, p.z) + 0.11;
  cat.root.rotation.y = turnToward(cat.root.rotation.y, Math.atan2(dx, dz), 5, dt);
}
function updateYardCats(dt) {
  if (player.inHospital || player.inSewer) return;
  for (const c of yardCats) {
    c.phase += dt;
    c.hitCooldown = Math.max(0, c.hitCooldown - dt);
    c.voiceCooldown = Math.max(0, c.voiceCooldown - dt);
    const p = c.root.position,
      dist = Math.hypot(player.pos.x - p.x, player.pos.z - p.z);
    const heightAbove = player.pos.y - terrainHeight(player.pos.x, player.pos.z);
    const inTerritory = Math.hypot(player.pos.x - c.home.x, player.pos.z - c.home.z) < 26;
    const seesSquirrel =
      dist < 17.5 && heightAbove < 2.8 && inTerritory && !player.rail && !activeHouseInterior;
    c.state = seesSquirrel ? (dist < 8 ? "chase" : "stalk") : "wander";
    let target = seesSquirrel
      ? player.pos
      : v(c.home.x + Math.sin(c.phase * 0.31 + c.x) * 7, 0, c.home.z + Math.cos(c.phase * 0.23 + c.z) * 6);
    if (c.windup > 0) {
      c.windup -= dt;
      c.state = "windup";
      // A visible crouch and tail flick before the cat strikes.
      c.root.scale.y = 0.72;
      c.tail.rotation.x = Math.sin(c.phase * 21) * 0.32;
      if (c.windup <= 0) {
        c.root.scale.y = 1;
        const hit =
          Math.hypot(player.pos.x - p.x, player.pos.z - p.z) < 2.75 &&
          heightAbove < 2.4 &&
          !activeHouseInterior;
        if (hit) {
          const away = v(player.pos.x - p.x, 0, player.pos.z - p.z).normalize();
          player.vel.x = away.x * 10.5;
          player.vel.z = away.z * 10.5;
          player.vel.y = Math.max(player.vel.y, 3.9);
          player.rail = null;
          player.grounded = false;
          c.hitCooldown = 7;
          player.points = Math.max(0, player.points - 12);
          refreshPowerUI();
          flash("CAT SWAT! It knocked the squirrel backward. Leap or climb to escape!", 2.7);
          fx(170, 0.23, "sawtooth", 0.05);
        } else {
          c.hitCooldown = 4;
          flash("The cat lunged and missed!", 1.8);
          fx(280, 0.13, "triangle", 0.024);
        }
      }
    } else {
      c.root.scale.y = 1;
      catSafeMove(c, target, dt);
      if (seesSquirrel && dist < 3.0 && c.hitCooldown <= 0) {
        c.windup = 0.68;
        if (c.voiceCooldown <= 0) {
          fx(220, 0.32, "sawtooth", 0.038);
          c.voiceCooldown = 4.5;
        }
        flash("A yard cat crouches to pounce — JUMP!", 1.2);
      } else if (seesSquirrel && c.voiceCooldown <= 0 && dist < 10) {
        c.voiceCooldown = 6;
        fx(310, 0.22, "sawtooth", 0.018);
      }
    }
    c.tail.rotation.y = Math.sin(c.phase * 3.7) * 0.4;
  }
}
// --- end v1.9 additions ---

// Hospital occupants occasionally chart, examine displays or sit beside the ward.
// Each schedule is offset, avoiding synchronized NPC motions and route changes.
const wardClipboards = [];
for (const [i, n] of hospitalStaff.entries()) {
  if (!["nurse", "doctor"].includes(n.hospitalRole)) continue;
  const cb = new THREE.Group();
  n.body.add(cb);
  cb.position.set(0.65, 1.44, 0.22);
  box(0.41, 0.56, 0.06, mat("#b7a68c"), 0, 0, 0, cb);
  box(0.29, 0.04, 0.07, mat("#dbe7e2"), 0, 0.16, 0.05, cb);
  wardClipboards.push({ n, cb, offset: i * 4.4 });
}
const oldHospitalActorUpdate = updateHospitalActors;
updateHospitalActors = function (dt) {
  oldHospitalActorUpdate(dt);
  if (player.inDuct) return;
  for (const { n, cb, offset } of wardClipboards) {
    if (n.injured || n.telegraph > 0) continue;
    const idle = (n.hospitalPause || 0) > 0.07;
    const charting = idle && Math.sin(time * 0.23 + offset) > 0.15;
    cb.rotation.x = charting ? -0.33 : 0;
    if (charting) {
      n.head.rotation.x = -0.13;
      n.arms[1].rotation.x = -0.54 + Math.sin(time * 2.1 + offset) * 0.05;
    } else n.head.rotation.x = 0;
  }
  for (const n of hospitalPatients) {
    if (n.injured) continue;
    if ((n.hospitalPause || 0) > 0.05) {
      n.head.rotation.y = Math.sin(time * 0.3 + n.hospitalPhase) * 0.2;
      n.arms[0].rotation.x = -0.12;
    }
  }
};

// ============================================================================
// v2.1 — FOUR WALK-IN HOMES / STREET-BASED EMERGENCY RESPONDERS
// ============================================================================
function furnishOriginalHouse(h) {
  const id = h.id,
    interior = new THREE.Group(),
    wallW = h.w / 0.82,
    wallD = h.d / 0.82,
    sign = h.frontSign;
  h.g.add(interior);
  const g = interior;
  h.indoorGroup = interior;
  const palette = [
    ["#aa795d", "#d8c2a0", "#536b61", "#b7a18f"],
    ["#769497", "#d0ccbb", "#a0785b", "#bbc8b5"],
    ["#825e50", "#dac6af", "#627a87", "#c2aa8d"],
    ["#6f87a6", "#efe1cc", "#b98d86", "#b0b7a1"],
  ][id];
  const timber = mat(palette[0]),
    cloth = mat(palette[1]),
    accent = mat(palette[2]);
  const pale = mat(palette[3]),
    darkWood = mat("#655747"),
    appliance = mat("#d9ded9");
  const floor = box(wallW - 1, 0.045, wallD - 0.9, mat(id % 2 ? "#ac9379" : "#bea98b"), 0, 0.259, 0, g);
  // The front door opens onto an unobstructed corridor at x=0.
  const couchZ = sign * 1.0;
  box(5.2, 0.67, 2.45, accent, -wallW * 0.265, 0.62, couchZ, g);
  box(5.2, 1.35, 0.43, accent, -wallW * 0.265, 1.22, couchZ - sign * 1.02, g);
  for (const arm of [-1, 1]) box(0.48, 0.85, 2.2, timber, -wallW * 0.265 + arm * 2.4, 0.91, couchZ, g);
  box(3.2, 0.25, 1.65, darkWood, -wallW * 0.265, 0.59, couchZ + sign * 2.85, g);
  box(7, 0.042, 6.1, mat(id % 2 ? "#ab806d" : "#a39b8a"), -wallW * 0.26, 0.29, couchZ + sign * 0.55, g);
  for (let i = -2; i <= 2; i++)
    box(5.6, 0.016, 0.037, cloth, -wallW * 0.26, 0.321, couchZ + sign * (i * 0.63), g);
  // Kitchen across the rear wall with refrigerator, sideboard, stove and sink.
  const backZ = sign * wallD * 0.405;
  for (const localX of [-wallW * 0.34, -wallW * 0.1, wallW * 0.16, wallW * 0.39]) {
    box(wallW * 0.205, 1.3, 0.99, cloth, localX, 0.89, backZ, g);
    box(wallW * 0.205, 0.12, 1.3, darkWood, localX, 1.6, backZ, g);
  }
  box(1.9, 3.05, 1.35, appliance, wallW * 0.385, 1.75, backZ - sign * 1.35, g); // fridge
  box(1.7, 0.17, 1.55, M.metal, wallW * 0.16, 1.72, backZ, g); // sink
  box(1.55, 0.13, 1.3, M.black, -wallW * 0.12, 1.7, backZ, g); // stove
  for (const burner of [-0.48, 0.48])
    for (const dz of [-0.36, 0.36])
      cyl(0.22, 0.22, 0.02, M.metal, -wallW * 0.12 + burner, 1.79, backZ + dz, g, 8);
  // Four chairs at a dining table; leave a central path to the entrance.
  const diningX = wallW * 0.255,
    diningZ = -sign * wallD * 0.12;
  box(3.7, 0.23, 3.0, timber, diningX, 1.39, diningZ, g);
  for (const dd of [-2.0, 2.0]) {
    box(1.24, 0.2, 1.0, accent, diningX, 0.69, diningZ + dd, g);
    box(1.25, 1.35, 0.2, accent, diningX, 1.09, diningZ + dd + Math.sign(dd) * 0.55, g);
  }
  for (const dx of [-2.45, 2.45]) {
    box(1.0, 0.18, 1.04, accent, diningX + dx, 0.69, diningZ, g);
    box(0.18, 1.1, 1.04, timber, diningX + dx + Math.sign(dx) * 0.55, 1.03, diningZ, g);
  }
  // Bedroom corner: bed, pillow, nightstand, wardrobe, lamp and small art.
  const bedX = -wallW * 0.3,
    bedZ = -sign * wallD * 0.29;
  box(4.0, 0.65, 4.1, darkWood, bedX, 0.63, bedZ, g);
  box(3.75, 0.25, 3.83, cloth, bedX, 1.03, bedZ, g);
  for (const bx of [-0.85, 0.85]) box(1.38, 0.22, 0.75, appliance, bedX + bx, 1.25, bedZ + sign * 1.38, g);
  box(4.12, 1.48, 0.31, timber, bedX, 1.49, bedZ + sign * 2.01, g);
  box(1.45, 0.74, 1.2, timber, bedX + 3.22, 0.64, bedZ - sign * 0.9, g);
  ball(
    0.22,
    new THREE.MeshStandardMaterial({ color: 0xffebbe, emissive: 0xffd598, emissiveIntensity: 0.67 }),
    bedX + 3.22,
    1.48,
    bedZ - sign * 0.9,
    g,
  );
  box(1.8, 3.2, 0.95, pale, wallW * 0.4, 1.9, -sign * wallD * 0.35, g);
  for (const px of [-wallW * 0.31, wallW * 0.28]) {
    box(2.2, 1.7, 0.11, timber, px, 4.25, backZ, g);
    box(1.9, 1.38, 0.12, mat(id % 2 ? "#71948e" : "#b4a27c"), px, 4.25, backZ - sign * 0.16, g);
  }
  // Soft interior illumination is a fixed emissive shade; no extra shadow lights.
  ball(
    0.46,
    new THREE.MeshStandardMaterial({ color: 0xffe5b3, emissive: 0xffd49a, emissiveIntensity: 1.0 }),
    0,
    5.6,
    0,
    g,
  );
  // Low furniture should be solid and slideable; use world-unit collision boxes.
  const addO = (x, z, w, d) =>
    h.interiorObstacles.push({ x: h.x + x * 0.82, z: h.z + z * 0.82, w: w * 0.82, d: d * 0.82 });
  addO(-wallW * 0.265, couchZ, 5.55, 2.5);
  addO(-wallW * 0.265, couchZ + sign * 2.85, 3.65, 1.95);
  addO(diningX, diningZ, 4.15, 3.45);
  addO(bedX, bedZ, 4.5, 4.6);
  addO(wallW * 0.385, backZ - sign * 1.35, 2.2, 1.9);
  addO(wallW * 0.4, -sign * wallD * 0.35, 2.1, 1.5);
  // small pale entrance mat + brass wall sconce
  box(2.0, 0.022, 1.6, pale, 0, 0.284, -sign * (wallD / 2 - 2), g);
  h.indoorDecor = floor;
  // All interior models share the parent's single transform and skip expensive shadows.
  interior.traverse((obj) => {
    if (obj.isMesh) {
      obj.castShadow = false;
      obj.receiveShadow = false;
    }
  });
  interior.visible = false;
}
const enterableHouses = houses.filter(
  (h) => h.indoorGroup && h.indoorCeiling && h.indoorRoof && houseDoors[h.id] && h.id >= 0 && h.id < 4,
);
for (const h of enterableHouses) furnishOriginalHouse(h);
// v2.1: Furnish the spaces people actually see. Props are intentionally low-poly
// and shared with the house visibility group; no new real-time lights or shadows.
const interiorMotion = [];
function makeHomeDetails(h) {
  const g = h.indoorGroup,
    W = h.w / 0.82,
    D = h.d / 0.82,
    sg = h.frontSign,
    id = h.id;
  const walnut = mat(id === 0 ? "#71513d" : "#87725a"),
    ivory = mat("#e5ddca"),
    metal = mat("#a4aca7"),
    accent = mat(["#aa7054", "#75958c", "#ab8568", "#7893a8"][id]),
    green = mat("#537451");
  // Television, slim console, and framed artwork along side walls, away from the entrance.
  const tvX = W * 0.44,
    tvZ = sg * D * 0.02;
  box(0.16, 2.35, 3.15, walnut, tvX, 3.12, tvZ, g);
  const screen = box(
    0.12,
    1.85,
    2.75,
    new THREE.MeshStandardMaterial({
      color: 0x283f42,
      emissive: 0x132e38,
      emissiveIntensity: 0.2,
      roughness: 0.52,
    }),
    tvX - 0.11,
    3.16,
    tvZ,
    g,
  );
  for (let j = 0; j < 3; j++) box(0.65, 0.13, 0.75, walnut, tvX - 0.15, 1.06, tvZ + (j - 1) * 0.96, g);
  interiorMotion.push({ kind: "tv", object: screen, id, phase: id * 2.1 });
  for (let j = 0; j < 3; j++) {
    const x = -W * 0.28 + j * 2.4,
      z = -sg * (D * 0.45 - 0.2);
    box(2.05, 1.66, 0.16, walnut, x, 4.35, z, g);
    box(
      1.78,
      1.4,
      0.19,
      mat(["#8eaa9c", "#c09a7b", "#7995b2", "#aca382"][(id + j) % 4]),
      x,
      4.35,
      z + sg * 0.13,
      g,
    );
    box(0.98, 0.72, 0.2, mat(["#d1d1ad", "#d6bca5", "#879fa0"][j]), x, 4.35, z + sg * 0.26, g);
  }
  // Bookshelf / dishes, small appliances, cookware and individual cookbooks.
  const shelfX = -W * 0.43,
    shelfZ = sg * D * 0.25;
  box(1.0, 3.9, 3.2, walnut, shelfX, 2.28, shelfZ, g);
  for (let y of [0.8, 1.63, 2.46, 3.28]) box(0.97, 0.16, 3.2, ivory, shelfX, y, shelfZ, g);
  for (let j = 0; j < 12; j++)
    box(
      0.52,
      0.55 + (j % 3) * 0.11,
      0.13,
      mat(["#728776", "#b38a74", "#78919a", "#cbb68e"][j % 4]),
      shelfX - 0.02,
      1.01 + (j % 3) * 0.78,
      shelfZ - 1.2 + (j % 8) * 0.32,
      g,
    );
  const rear = sg * D * 0.405;
  for (let j = 0; j < 6; j++) {
    box(1.48, 1.09, 0.75, mat(id === 2 ? "#b79d84" : "#ddd5c7"), -W * 0.32 + j * W * 0.129, 3.05, rear, g);
    box(0.07, 0.42, 0.04, metal, -W * 0.32 + j * W * 0.129 + 0.4, 3.03, rear - sg * 0.39, g);
  }
  const kettle = ball(0.35, metal, -W * 0.12, 1.94, rear - sg * 0.1, g);
  kettle.scale.set(1, 0.82, 0.72);
  const spout = span(
    v(-W * 0.12 + 0.27, 2.03, rear),
    v(-W * 0.12 + 0.52, 2.22, rear),
    0.075,
    0.045,
    metal,
    g,
  );
  box(0.52, 0.3, 0.46, ivory, W * 0.28, 1.9, rear - sg * 0.12, g); // toaster
  const fruit = box(0.85, 0.12, 0.76, walnut, W * 0.255, 1.64, -sg * D * 0.12, g);
  for (let j = 0; j < 3; j++)
    ball(
      0.17,
      mat(["#bb4838", "#dbaf55", "#77934c"][j]),
      W * 0.255 + (j - 1) * 0.23,
      1.78,
      -sg * D * 0.12,
      g,
    );
  // Entrance details and room-scale softness: shoes, coat pegs, tall plant, side lamp.
  for (let j = 0; j < 3; j++) {
    const x = -W * 0.18 + j * 0.75,
      z = -sg * (D / 2 - 1.15);
    box(0.56, 0.18, 0.86, mat(j % 2 ? "#74695e" : "#bda88b"), x, 0.39, z, g);
  }
  for (const [x, z] of [
    [W * 0.42, -sg * D * 0.31],
    [-W * 0.43, -sg * D * 0.1],
  ]) {
    cyl(0.55, 0.4, 0.64, walnut, x, 0.58, z, g);
    span(v(x, 1.0, z), v(x, 3.4, z), 0.08, 0.06, green, g);
    for (let k = 0; k < 5; k++) {
      const a = k * 2.4;
      const p = ball(0.42, green, x + Math.sin(a) * 0.48, 2.17 + (k % 3) * 0.44, z + Math.cos(a) * 0.44, g);
      p.scale.set(1, 0.6, 0.7);
    }
  }
  // Plausible physical clocks and subtle movement: quiet fans/pendulums, no draw calls per tick.
  if (id === 0) {
    box(0.42, 2.65, 1.05, walnut, -W * 0.445, 3.2, sg * 0.02, g);
    const pend = box(0.14, 0.77, 0.13, mat("#c8a365"), -W * 0.45, 2.65, sg * 0.02, g);
    interiorMotion.push({ kind: "pendulum", object: pend, phase: 0.7, id });
    for (const z of [-sg * D * 0.13, sg * D * 0.19]) box(1.95, 0.16, 1.0, walnut, W * 0.39, 2.1, z, g);
  } else if (id === 1) {
    const fan = new THREE.Group();
    fan.position.set(0, 6.6, 0);
    g.add(fan);
    cyl(0.2, 0.2, 0.55, metal, 0, 0, 0, fan);
    for (let k = 0; k < 4; k++) {
      const blade = box(2.6, 0.07, 0.44, walnut, 1.34, 0.08, 0, fan);
      blade.rotation.y = (k * PI) / 2;
      blade.position.set(Math.cos((k * PI) / 2) * 1.34, 0.08, Math.sin((k * PI) / 2) * 1.34);
    }
    interiorMotion.push({ kind: "fan", object: fan, id, phase: 0 });
    box(2.35, 0.12, 1.25, walnut, -W * 0.1, 1.1, -sg * D * 0.4, g); // breakfast ledge
  } else if (id === 2) {
    // Student's small desk by the wall, including open school notebooks and a chair.
    const x = W * 0.34,
      z = -sg * D * 0.36;
    box(2.1, 0.22, 1.23, walnut, x, 1.45, z, g);
    box(0.72, 0.06, 0.42, ivory, x, 1.6, z, g);
    for (let j = 0; j < 3; j++) box(0.035, 0.01, 0.3, accent, x - 0.25 + j * 0.18, 1.65, z, g);
    box(1.0, 0.2, 0.95, accent, x - 1.2, 0.67, z, g);
    box(1.02, 1.25, 0.15, accent, x - 1.2, 1.18, z - sg * 0.4, g);
  } else {
    box(2.15, 0.38, 1.35, accent, -W * 0.405, 0.53, sg * D * 0.05, g); // pet sleeping cushion
    box(1.24, 1.65, 1.32, walnut, W * 0.405, 1.25, -sg * D * 0.3, g);
    for (let j = 0; j < 4; j++) box(1.02, 0.15, 1.14, ivory, W * 0.405, 0.7 + j * 0.4, -sg * D * 0.3, g);
  }
  h.indoorDecor?.updateMatrix?.();
  g.traverse((obj) => {
    if (obj.isMesh) {
      obj.castShadow = false;
      obj.receiveShadow = false;
    }
  });
}
for (const h of enterableHouses) makeHomeDetails(h);
function updateInteriorMotion(dt) {
  for (const a of interiorMotion) {
    if (!houses[a.id]?.indoorGroup?.visible) continue;
    if (a.kind === "fan") a.object.rotation.y += dt * 0.85;
    else if (a.kind === "pendulum") a.object.rotation.z = Math.sin(time * 1.8 + a.phase) * 0.1;
    else if (a.kind === "tv")
      a.object.material.emissiveIntensity = 0.15 + 0.06 * Math.sin(time * 0.68 + a.phase);
  }
}

function setHouseRoof(h, inside) {
  h.indoorRoof.visible = !inside;
  h.indoorCeiling.visible = !inside;
}
function houseInteriorEntry(h, enter) {
  const d = houseDoors[h.id];
  if (!d) return;
  d.hold = Math.max(d.hold, 3.0);
  player.rail = null;
  player.vel.set(0, 0, 0);
  player.grounded = true;
  player.committedAirborne = false;
  player.attackWindow = 0;
  const from = player.pos.clone(),
    to = enter ? d.inside.clone() : d.outside.clone();
  to.y = terrainHeight(to.x, to.z) + 0.28;
  houseTransit = { h, enter, from, to, elapsed: 0, duration: 0.85 };
  if (enter) {
    activeHouseInterior = h;
    setHouseRoof(h, true);
  }
  flash(enter ? `Opening ${h.indoorName} · exploring indoors` : `Leaving the ${h.indoorName}`, 1.8);
}
function handleHouseInteriorInteraction() {
  if (houseTransit) return true;
  if (activeHouseInterior) {
    const d = houseDoors[activeHouseInterior.id];
    if (Math.hypot(player.pos.x - d.inside.x, player.pos.z - d.inside.z) < 4.4) {
      houseInteriorEntry(activeHouseInterior, false);
      return true;
    }
    flash("Find the front entrance and press E to leave the house.", 2);
    return true;
  }
  if (player.inSewer || player.inHospital || player.inDuct || player.rail || activeOldHome) return false;
  for (const h of enterableHouses) {
    const d = houseDoors[h.id];
    if (Math.hypot(player.pos.x - d.outside.x, player.pos.z - d.outside.z) < 3.85 && player.pos.y < 3.6) {
      houseInteriorEntry(h, true);
      return true;
    }
  }
  return false;
}
const v19Interaction = handleInteraction;
handleInteraction = function () {
  if (handleHouseInteriorInteraction()) return true;
  return v19Interaction();
};
function updateHouseInteriors(dt) {
  for (const h of enterableHouses)
    h.indoorGroup.visible =
      h === activeHouseInterior || Math.hypot(player.pos.x - h.x, player.pos.z - h.z) < 32;
  if (houseTransit) {
    const q = houseTransit;
    q.elapsed = Math.min(q.duration, q.elapsed + dt);
    const f = q.elapsed / q.duration;
    // Open the real front door before crossing it, using the same threshold as residents.
    houseDoors[q.h.id].hold = 3.0;
    // Hold just outside the threshold until the door has physically cleared.
    if (f >= 0.36 && !houseDoorPassable(houseDoors[q.h.id])) {
      q.elapsed = Math.min(q.elapsed, q.duration * 0.35);
    }
    const passF = q.elapsed / q.duration;
    if (passF < 0.36) {
      // ease toward the outside threshold while door swings
      player.pos
        .copy(q.from)
        .lerp(
          q.enter ? houseDoors[q.h.id].outside : houseDoors[q.h.id].inside,
          THREE.MathUtils.smoothstep(passF / 0.36, 0, 1),
        );
    } else {
      const threshold = houseDoors[q.h.id].threshold;
      const base = q.enter ? houseDoors[q.h.id].outside : houseDoors[q.h.id].inside;
      const passage = passF < 0.62 ? (passF - 0.36) / 0.26 : 1;
      if (passF < 0.62) player.pos.copy(base).lerp(threshold, THREE.MathUtils.smoothstep(passage, 0, 1));
      else player.pos.copy(threshold).lerp(q.to, THREE.MathUtils.smoothstep((passF - 0.62) / 0.38, 0, 1));
    }
    player.pos.y = terrainHeight(player.pos.x, player.pos.z) + 0.28;
    player.vel.set(0, 0, 0);
    player.grounded = true;
    if (q.elapsed >= q.duration) {
      player.pos.copy(q.to);
      player.vel.set(0, 0, 0);
      if (!q.enter) {
        activeHouseInterior = null;
        setHouseRoof(q.h, false);
      }
      houseTransit = null;
      cameraHardCut = true;
      flash(q.enter ? "INSIDE · WASD walk · E by the front door to exit." : "BACK IN THE NEIGHBORHOOD", 2.6);
    }
    return;
  }
  if (!activeHouseInterior && !houseTransit && !player.inSewer && !player.inHospital && !activeOldHome) {
    for (const h of enterableHouses) {
      const d = houseDoors[h.id];
      if (Math.hypot(player.pos.x - d.outside.x, player.pos.z - d.outside.z) < 5 && player.pos.y < 3.5) {
        $("scoutText").innerHTML =
          `${h.indoorName.toUpperCase()} · E at the door to go inside<br>Living room · kitchen · dining · bedroom`;
        break;
      }
    }
  }
  if (activeHouseInterior) {
    const h = activeHouseInterior;
    if (!player.rail && player.pos.y < 0.3) {
      player.pos.y = 0.3;
      player.vel.y = 0;
      player.grounded = true;
    }
    // House roofs also stay open while the squirrel freely walks around indoors.
    setHouseRoof(h, true);
    const d = houseDoors[h.id];
    if (Math.hypot(player.pos.x - d.inside.x, player.pos.z - d.inside.z) < 3.7)
      d.hold = Math.max(d.hold, 0.35);
  }
}
// Emergency characters should not walk straight through homes or shops.
function keepEmergencyActorsOutside(position, previous) {
  for (const h of houses) {
    if (Math.abs(position.x - h.x) < h.w / 2 + 0.65 && Math.abs(position.z - h.z) < h.d / 2 + 0.65) {
      if (Math.abs(previous.x - h.x) >= h.w / 2 + 0.65) position.x = previous.x;
      else if (Math.abs(previous.z - h.z) >= h.d / 2 + 0.65) position.z = previous.z;
      else {
        position.x = previous.x;
        position.z = previous.z;
      }
    }
  }
  for (const b of commercialBounds) {
    if (Math.abs(position.x - b.x) < b.w / 2 + 0.6 && Math.abs(position.z - b.z) < b.d / 2 + 0.6) {
      if (Math.abs(previous.x - b.x) >= b.w / 2 + 0.6) position.x = previous.x;
      else if (Math.abs(previous.z - b.z) >= b.d / 2 + 0.6) position.z = previous.z;
      else {
        position.x = previous.x;
        position.z = previous.z;
      }
    }
  }
}
const responderBeaconMats = [];
for (const ambulance of responderAmbulances) {
  ambulance.flashBars.forEach((bar, j) => {
    const color = j ? 0x276ac2 : 0xdc2929;
    const lampMat = new THREE.MeshStandardMaterial({
      color,
      emissive: color,
      emissiveIntensity: 0.4,
      roughness: 0.25,
    });
    bar.material = lampMat;
    responderBeaconMats.push({ vehicle: ambulance, mat: lampMat, offset: j });
  });
}
for (const car of incidentPoliceCars) {
  car.children.slice(-2).forEach((bar, j) => {
    const color = j ? 0xe84539 : 0x426fd7;
    const lampMat = new THREE.MeshStandardMaterial({
      color,
      emissive: color,
      emissiveIntensity: 0.4,
      roughness: 0.25,
    });
    bar.material = lampMat;
    responderBeaconMats.push({ vehicle: car, mat: lampMat, offset: j });
  });
}
function updateEmergencyBeacons() {
  const phase = Math.floor(time * 4.7) % 2;
  for (const lamp of responderBeaconMats) {
    lamp.mat.emissiveIntensity = lamp.vehicle.visible && phase === lamp.offset ? 2.6 : 0.13;
  }
}
// ============================================================================

// ============================================================================
// v3.6 — Extraordinary street cast: a juggling mime on an oversize unicycle,
// and a handful of young cyclists. One update owner, one state machine each.
// They do NOT use the generic pedestrian goal/spawn scheduler.
// ============================================================================
const noveltyCast = [];
const stationWelcome = v(policeStation.x, 0, policeStation.z + 20.5);
const stationThreshold = v(policeStation.x, 0, policeStation.z + 14.9);
const stationInner = v(policeStation.x, 0, policeStation.z + 8.8);
const stationDoors = new THREE.Group();
policeRoot.add(stationDoors);
const stationDoorPanels = [];
for (const sign of [-1, 1]) {
  const pivot = new THREE.Group();
  pivot.position.set(sign * 2.25, 0, 15.5);
  stationDoors.add(pivot);
  const panel = box(2.18, 3.35, 0.14, mat("#406c86"), -sign * 1.09, 1.76, 0, pivot);
  box(1.25, 1.8, 0.16, M.glass, -sign * 1.1, 2.0, 0.035, pivot);
  ball(0.105, mat("#ddc88b"), -sign * 1.84, 1.59, 0.15, pivot);
  stationDoorPanels.push({ pivot, sign, panel });
}
let stationEscapeDoorOpen = 0,
  stationDoorHold = 0;
function noveltyActorSafeVector(x, z) {
  return v(x, terrainHeight(x, z) + 0.13, z);
}
function noveltyUnit(x, z) {
  return v(x, 0, z);
}
function createNoveltyResident(def, index, opts) {
  const n = makeHuman(def, humanoids.length);
  n.specialStreetCast = true;
  n.visible = true;
  n.root.visible = true;
  n.alert = 0;
  n.reacting = 0;
  n.root.position.copy(noveltyActorSafeVector(opts.x, opts.z));
  n.state = "ride";
  n.facing = opts.heading;
  n.root.rotation.y = n.facing;
  const a = {
    n,
    index,
    kind: opts.kind,
    speed: opts.speed,
    escapeSpeed: opts.escapeSpeed,
    travelZ: opts.z,
    origin: noveltyUnit(opts.x, opts.z),
    destination: noveltyUnit(opts.endX, opts.endZ),
    phase: index * 1.13,
    walkSpeed: 0,
    rideDirection: 1,
    route: null,
    routeStep: 0,
    repath: 0,
    sightCooldown: index * 0.35,
    escaped: false,
    resetTime: 0,
    sirenNotified: false,
    reactionTime: 0,
    sway: 0,
    seenAt: 0,
    lights: [],
    popped: false,
  };
  noveltyCast.push(a);
  return a;
}
const mimeN = createNoveltyResident(["Marcel the Mime", "unicyclist", -1, "#dbc3a8", "#ededeb", "panic"], 0, {
  kind: "mime",
  x: -94,
  z: -8,
  heading: PI / 2,
  endX: 80,
  endZ: -8,
  speed: 5.9,
  escapeSpeed: 18.4,
});
// Black-and-white mime clothing, stripes, beret, white gloves and red scarf.
const mimeFabric = mat("#f7f6ed"),
  mimeInk = mat("#24252b"),
  mimeRed = mat("#a92831");
for (let k = 0; k < 5; k++)
  box(0.68, 0.11, 0.49, k % 2 ? mimeFabric : mimeInk, 0, 1.29 + k * 0.255, 0.02, mimeN.n.body);
box(0.84, 0.17, 0.52, mimeInk, 0, 2.58, 0, mimeN.n.body);
const beret = ball(0.42, mimeInk, 0.13, 3.53, 0.02, mimeN.n.body);
beret.scale.set(1.25, 0.25, 1.15);
box(0.28, 0.13, 0.26, mimeRed, 0, 2.51, 0.36, mimeN.n.body);
for (const s of [-1, 1]) ball(0.19, mimeFabric, s * 0.78, 1.23, 0.08, mimeN.n.body);
// The high wheel is a real visible prop, and the juggling balls follow parabolic arcs.
const tallWheel = new THREE.Group();
mimeN.n.root.add(tallWheel);
const wheelTurn = new THREE.Group();
wheelTurn.position.y = 1.8;
tallWheel.add(wheelTurn);
const wheelRing = new THREE.Mesh(new THREE.TorusGeometry(1.63, 0.13, 10, 38), M.rubber);
wheelRing.rotation.y = PI / 2;
wheelTurn.add(wheelRing);
for (let i = 0; i < 8; i++) {
  const a = (i * PI) / 4;
  span(v(0, 0, 0), v(0, Math.sin(a) * 1.56, Math.cos(a) * 1.56), 0.025, 0.025, M.metal, wheelTurn);
}
span(v(0, 1.8, 0), v(0, 3.77, 0), 0.11, 0.1, M.metal, tallWheel);
box(1.05, 0.14, 0.58, mimeInk, 0, 3.8, 0, tallWheel);
for (const s of [-1, 1]) span(v(0, 2.06, 0), v(s * 0.65, 1.93, 0), 0.065, 0.06, M.metal, tallWheel);
mimeN.n.body.position.y = 3.55;
const jugglingColors = ["#f44336", "#e8d761", "#55a9dc", "#7ebf80"];
const jugglingBalls = jugglingColors.map((col, i) => {
  const b = ball(0.23, mat(col, 0.4), 0, 5.45, 0, mimeN.n.root);
  return b;
});
mimeN.wheelTurn = wheelTurn;
mimeN.jugglingBalls = jugglingBalls;
// Smaller independent bicycle riders: they do not occupy ordinary adult spawn slots.
const youngRiders = [
  { name: "Ellie", x: -54, z: 17, endX: 66, endZ: 17, color: "#ef9e58", shirt: "#e69a54" },
  { name: "Theo", x: 37, z: -17, endX: -88, endZ: -17, color: "#64a2cf", shirt: "#70b6dd" },
  { name: "Jules", x: -152, z: 18, endX: -32, endZ: 18, color: "#ce719f", shirt: "#d79cc2" },
  { name: "Avery", x: -294, z: 92, endX: -294, endZ: -126, color: "#68aa8d", shirt: "#66b495" },
  { name: "Riley", x: -288, z: -173, endX: -288, endZ: 102, color: "#b98b55", shirt: "#b5a06e" },
];
for (const [i, spec] of youngRiders.entries()) {
  const heading = Math.atan2(spec.endX - spec.x, spec.endZ - spec.z);
  const a = createNoveltyResident(
    [spec.name, "cyclist", -1, ["#e6b995", "#b78364", "#a5785c"][i % 3], spec.shirt, "panic"],
    i + 1,
    {
      kind: "kid",
      x: spec.x,
      z: spec.z,
      heading,
      endX: spec.endX,
      endZ: spec.endZ,
      speed: 4.6 + i * 0.35,
      escapeSpeed: 12.8 + i * 0.45,
    },
  );
  a.n.body.scale.multiplyScalar(0.76);
  a.n.body.position.y = 0.55;
  if (a.n.bike) {
    a.n.bike.scale.setScalar(0.82);
    a.n.bike.position.y = 0.08;
    a.lights.push(...a.n.bikeWheels);
  }
  // Simple bicycle helmets in different colors, mounted on the rider's head.
  const helmet = ball(0.43, mat(spec.color), 0, 0.46, -0.02, a.n.head);
  helmet.scale.set(1, 0.43, 1);
  box(0.55, 0.085, 0.27, mat("#33383c"), 0, 0.35, 0.31, a.n.head);
  a.parkedBike = a.n.bike.clone();
  scene.add(a.parkedBike);
  a.parkedBike.visible = false;
}
function novelEscapePath(a) {
  const n = a.n,
    p = n.root.position;
  const outside = stationWelcome.clone();
  outside.y = terrainHeight(outside.x, outside.z) + 0.13;
  let candidate = medicalWalkRoute(p.clone(), outside);
  // A failed route is never treated as permission to run through a house.
  if (!candidate?.length || candidate.some((q, i) => i && medicalSegmentBlocked(candidate[i - 1], q))) {
    const overSouth = p.z < policeStation.z;
    const rim = overSouth ? -245 : 245;
    const around = [p.clone(), noveltyActorSafeVector(-318, rim), noveltyActorSafeVector(-472, rim), outside];
    candidate = [p.clone()];
    for (let i = 1; i < around.length; i++) {
      const sub = medicalWalkRoute(candidate[candidate.length - 1], around[i]);
      candidate.push(...sub.slice(1));
    }
  }
  // The first move is decisively AWAY from the creature that startled them.
  if (a.reactionTime > 0 && !a.escapeBurstUsed) {
    const away = p.clone().sub(player.pos).setY(0);
    if (away.lengthSq() < 0.05) away.set(-1, 0, 0);
    const burst = p.clone().addScaledVector(away.normalize(), a.kind === "mime" ? 18 : 11);
    if (!medicalSegmentBlocked(p, burst)) {
      const tail = medicalWalkRoute(burst, outside);
      if (tail?.length >= 2 && !tail.some((q, i) => i && medicalSegmentBlocked(tail[i - 1], q))) {
        candidate = [p.clone(), burst, ...tail.slice(1)];
        a.escapeBurstUsed = true;
      }
    }
  }
  a.route = candidate.map((q) => noveltyUnit(q.x, q.z));
  a.routeStep = 1;
  a.repath = 5;
}
function noveltySpotSquirrel(a) {
  const n = a.n,
    p = n.root.position;
  if (player.inSewer || player.inHospital || activeHouseInterior || player.pos.y > 6.4) return false;
  const dx = player.pos.x - p.x,
    dz = player.pos.z - p.z,
    dist = Math.hypot(dx, dz);
  const look = noveltyUnit(Math.sin(n.facing), Math.cos(n.facing));
  const faces = (dx * look.x + dz * look.z) / Math.max(1, dist) > 0.08;
  const fast = player.moveSpeed > 6.5;
  return (
    dist < (a.kind === "mime" ? 36 : 24) &&
    (faces || dist < (a.kind === "mime" ? 14 : 10) || (fast && dist < 17))
  );
}
function noveltySpotResponse(a) {
  const n = a.n;
  if (n.state === "escape" || n.state === "entering" || n.state === "inside" || n.injured) return;
  n.state = "escape";
  n.alert = 32;
  n.reacting = 3.6;
  a.seenAt = time;
  a.reactionTime = 2.3;
  a.sirenNotified = false;
  novelEscapePath(a);
  if (n.sayCooldown <= 0)
    say(
      n,
      a.kind === "mime"
        ? pick(["Nope! Police station, now!", "Oh! That squirrel! Help!"])
        : pick(["Look out! Go to the station!", "That squirrel is after us!", "Come on, get to the police!"]),
    );
  if (a.kind === "mime")
    flash("The juggling unicyclist spotted you and is racing to the police station!", 2.9);
}
function updateNoveltyCast(dt) {
  let peopleApproachingDoor = 0;
  const fpsDt = Math.min(dt, 0.055);
  for (const a of noveltyCast) {
    const n = a.n;
    if (n.injured) {
      if (!a.popped) {
        a.popped = true;
        if (a.kind === "mime") {
          tallWheel.rotation.z = 1.12;
          n.body.position.y = 0;
          for (const b of jugglingBalls) b.visible = false;
        } else if (n.bike) {
          n.bike.position.x = 0.9;
          n.bike.rotation.z = 1.02;
          n.body.position.y = 0;
        }
      }
      continue;
    }
    if (a.escaped) {
      a.resetTime -= fpsDt;
      if (a.resetTime <= 0) {
        a.escaped = false;
        a.popped = false;
        a.dismounted = false;
        a.escapeBurstUsed = false;
        if (a.parkedBike) a.parkedBike.visible = false;
        n.state = "ride";
        n.visible = true;
        n.root.visible = true;
        n.root.position.copy(noveltyActorSafeVector(a.origin.x, a.origin.z));
        n.facing = Math.atan2(a.destination.x - a.origin.x, a.destination.z - a.origin.z);
        n.root.rotation.y = n.facing;
        n.alert = 0;
        n.reacting = 0;
        a.route = null;
        a.routeStep = 0;
        a.walkSpeed = 0;
        if (a.kind === "mime") {
          tallWheel.rotation.z = 0;
          n.body.position.y = 3.55;
          for (const b of jugglingBalls) b.visible = true;
        } else if (n.bike) {
          n.bike.visible = true;
          n.bike.rotation.z = 0;
          n.bike.position.set(0, 0.1, 0);
          n.body.position.y = 0.55;
        }
      }
      continue;
    }
    if (!n.visible) continue;
    n.sayCooldown = Math.max(0, (n.sayCooldown || 0) - fpsDt);
    n.reacting = Math.max(0, (n.reacting || 0) - fpsDt);
    if (n.state === "ride" && noveltySpotSquirrel(a)) noveltySpotResponse(a);
    let desiredSpeed = n.state === "escape" ? a.escapeSpeed : a.speed;
    if (n.state === "entering" || a.dismounted) desiredSpeed = 6.8;
    // A well-telegraphed emergency dodge makes the special riders tough, not invulnerable.
    const p = n.root.position;
    const proximity = Math.hypot(p.x - player.pos.x, p.z - player.pos.z);
    if (n.state === "escape" && player.attackWindow > 0 && proximity < 8.5) {
      a.reactionTime = Math.max(a.reactionTime, 0.55);
    }
    if (n.state === "escape") {
      if (
        a.kind === "kid" &&
        !a.dismounted &&
        Math.hypot(p.x - policeStation.x, p.z - stationWelcome.z) < 10
      ) {
        a.dismounted = true;
        n.bike.visible = false;
        n.body.position.y = 0;
        if (a.parkedBike) {
          a.parkedBike.visible = true;
          const bx = policeStation.x + (((a.index - 1) % 5) - 2) * 3.25,
            bz = stationWelcome.z + 4;
          a.parkedBike.position.set(bx, terrainHeight(bx, bz) + 0.13, bz);
          a.parkedBike.rotation.y = n.facing;
        }
      }
      if (Math.hypot(p.x - stationWelcome.x, p.z - stationWelcome.z) < 23)
        stationDoorHold = Math.max(stationDoorHold, 2.6);
      if (!a.route || a.routeStep >= a.route.length) {
        novelEscapePath(a);
      }
    }
    let target;
    if (n.state === "ride") target = a.destination;
    else if (n.state === "entering") {
      peopleApproachingDoor++;
      desiredSpeed = 4.0;
      target = stationEscapeDoorOpen > 0.82 ? stationInner : stationThreshold;
    } else if (n.state === "escape")
      target = a.route?.[Math.min(a.routeStep, a.route.length - 1)] || stationWelcome;
    else continue;
    const dx = target.x - p.x,
      dz = target.z - p.z,
      dist = Math.hypot(dx, dz);
    if (n.state === "ride" && dist < 3) {
      const last = a.origin;
      a.origin = a.destination;
      a.destination = last;
      n.facing = turnToward(n.facing, Math.atan2(a.destination.x - p.x, a.destination.z - p.z), 2.8, fpsDt);
      target = a.destination;
    }
    if (n.state === "escape" && dist < 2.15) {
      a.routeStep++;
      if (a.routeStep >= a.route.length) {
        n.state = "entering";
        peopleApproachingDoor++;
        stationDoorHold = Math.max(stationDoorHold, 6);
        target = stationThreshold;
      } else target = a.route[a.routeStep];
    }
    if (n.state === "entering" && Math.hypot(p.x - stationInner.x, p.z - stationInner.z) < 1.75) {
      a.escaped = true;
      a.resetTime = 55 + (a.index % 4) * 16;
      n.state = "inside";
      n.visible = false;
      n.root.visible = false;
      stationDoorHold = Math.max(stationDoorHold, 2.0);
      if (!a.sirenNotified) {
        a.sirenNotified = true;
        dispatchCop("A frightened cyclist reported the squirrel at the station!");
      }
      continue;
    }
    const theta = Math.atan2(target.x - p.x, target.z - p.z);
    const turnRate = n.state === "escape" ? 5.8 : 3.65;
    n.facing = turnToward(n.facing, theta, turnRate, fpsDt);
    n.root.rotation.y = n.facing;
    a.walkSpeed = THREE.MathUtils.damp(a.walkSpeed, desiredSpeed, n.state === "escape" ? 6.9 : 3.2, fpsDt);
    let remaining = noveltyUnit(target.x - p.x, target.z - p.z);
    let step = Math.min(remaining.length(), a.walkSpeed * fpsDt);
    const old = p.clone();
    if (remaining.lengthSq() > 0.00001) p.addScaledVector(remaining.normalize(), step);
    // A station doorway is passable only while its doors are swung clear.
    const passingStationEntrance =
      n.state === "entering" &&
      stationEscapeDoorOpen > 0.82 &&
      Math.abs(p.x - policeStation.x) < 2.65 &&
      p.z > policeStation.z + 7.2 &&
      p.z < policeStation.z + 22;
    // Everywhere else buildings remain solid to riders and pedestrians.
    if (!passingStationEntrance && medicalSegmentBlocked(old, p)) {
      p.copy(old);
      if (n.state === "escape") {
        a.repath -= fpsDt;
        if (a.repath <= 0) {
          novelEscapePath(a);
          a.repath = 2.0;
        }
      } else {
        a.destination = a.origin.clone();
        a.origin = noveltyUnit(old.x, old.z);
      }
    }
    p.y = terrainHeight(p.x, p.z) + 0.13;
    const rolled = Math.hypot(p.x - old.x, p.z - old.z); // no wheel spin while blocked
    if (a.kind === "mime") {
      if (n.state === "escape") {
        for (const b of jugglingBalls) b.visible = false;
      } else {
        for (let j = 0; j < jugglingBalls.length; j++) {
          const phase = time * 4.4 + (j * 2 * PI) / jugglingBalls.length;
          jugglingBalls[j].position.set(
            Math.sin(phase) * 0.82,
            5.7 + 1.15 * Math.max(0, Math.cos(phase)),
            0.15 + Math.sin(phase * 0.5) * 0.1,
          );
        }
      }
      mimeN.wheelTurn.rotation.x += rolled / 1.63;
      n.body.rotation.z = Math.sin(time * 4.5) * 0.055;
      for (let k = 0; k < 2; k++) n.arms[k].rotation.x = -1.2 + Math.sin(time * 8.8 + k * PI) * 0.5;
    } else {
      for (const wheel of a.lights)
        wheel.rotation.x += rolled / (wheel.userData.rollingRadius * n.bike.scale.x);
      if (n.bikeCrank) n.bikeCrank.rotation.x += rolled / (0.34 * n.bike.scale.x);
      n.body.rotation.z = Math.sin(time * 6 + a.phase) * 0.035;
      for (let k = 0; k < 2; k++) n.legs[k].rotation.x = Math.sin(time * 10 + a.phase + k * PI) * 0.4;
      n.arms.forEach((arm) => (arm.rotation.x = -0.68));
    }
    // A modest short-range avoidance sidestep, disabled near the police entrance.
    if (n.state === "escape" && a.reactionTime > 0) {
      a.reactionTime = Math.max(0, a.reactionTime - fpsDt);
      if (proximity < 8 && Math.hypot(p.x - policeStation.x, p.z - policeStation.z) > 25) {
        const strafe = noveltyUnit(Math.cos(n.facing), -Math.sin(n.facing));
        const alternate = p.clone().addScaledVector(strafe, (a.index % 2 ? 1 : -1) * fpsDt * 3.7);
        if (!medicalSegmentBlocked(p, alternate)) {
          p.x = alternate.x;
          p.z = alternate.z;
        }
      }
    }
  }
  stationDoorHold = Math.max(0, stationDoorHold - fpsDt);
  const target = stationDoorHold > 0 || peopleApproachingDoor > 0 ? 1 : 0;
  stationEscapeDoorOpen = THREE.MathUtils.damp(stationEscapeDoorOpen, target, 6.4, fpsDt);
  for (const door of stationDoorPanels) door.pivot.rotation.y = door.sign * stationEscapeDoorOpen * 1.25;
}

// ===== v3.5 environment pass: poles, shrubs, fences, gardens, stream, ice cream shops =====
(function () {
  function addBox(w, h, d, color) {
    const g = new THREE.BoxGeometry(w, h, d);
    const m = new THREE.MeshLambertMaterial({ color });
    return new THREE.Mesh(g, m);
  }
  function addCyl(r1, r2, h, color, radial = 8) {
    const g = new THREE.CylinderGeometry(r1, r2, h, radial);
    const m = new THREE.MeshLambertMaterial({ color });
    return new THREE.Mesh(g, m);
  }
  function addShrub(x, z, s = 1, color = 0x557a37) {
    const root = new THREE.Group();
    const a = addCyl(0.55 * s, 0.7 * s, 0.55 * s, color, 7);
    a.position.y = 0.25 * s;
    const b = addCyl(0.45 * s, 0.6 * s, 0.42 * s, color, 7);
    b.position.set(0.35 * s, 0.42 * s, 0.1 * s);
    const c = addCyl(0.4 * s, 0.55 * s, 0.4 * s, color, 7);
    c.position.set(-0.25 * s, 0.36 * s, -0.15 * s);
    root.add(a, b, c);
    root.position.set(x, 0, z);
    if (scene) scene.add(root);
    return root;
  }
  function addFenceRun(x1, z1, x2, z2, style = "wood") {
    const dx = x2 - x1,
      dz = z2 - z1;
    const len = Math.hypot(dx, dz);
    const root = new THREE.Group();
    const count = Math.max(2, Math.floor(len / 2.4));
    const angle = Math.atan2(dz, dx);
    for (let i = 0; i <= count; i++) {
      const t = i / count;
      const px = x1 + dx * t,
        pz = z1 + dz * t;
      const post = addBox(
        style === "chain" ? 0.12 : 0.16,
        style === "chain" ? 1.0 : 1.1,
        style === "chain" ? 0.12 : 0.16,
        style === "chain" ? 0x8e8e8e : 0x8b6a44,
      );
      post.position.set(px, 0.55, pz);
      root.add(post);
      if (i < count) {
        const segLen = len / count;
        if (style === "chain") {
          const rail = addBox(segLen, 0.55, 0.04, 0xb7c0c0);
          rail.position.set(px + dx / count / 2, 0.62, pz + dz / count / 2);
          rail.rotation.y = angle;
          root.add(rail);
        } else {
          const rail1 = addBox(segLen, 0.1, 0.08, 0x9a7750);
          const rail2 = addBox(segLen, 0.1, 0.08, 0x9a7750);
          rail1.position.set(px + dx / count / 2, 0.72, pz + dz / count / 2);
          rail2.position.set(px + dx / count / 2, 0.36, pz + dz / count / 2);
          rail1.rotation.y = rail2.rotation.y = angle;
          root.add(rail1, rail2);
        }
      }
    }
    if (scene) scene.add(root);
    return root;
  }
  function addGardenPlot(x, z, w, d, variant = 0) {
    const root = new THREE.Group();
    const soil = addBox(w, 0.08, d, 0x7a5132);
    soil.position.y = 0.04;
    root.add(soil);
    const border = addBox(w + 0.16, 0.12, d + 0.16, 0x6f5339);
    border.position.y = 0.02;
    root.add(border);
    const soilTop = addBox(w, 0.07, d, 0x7a5132);
    soilTop.position.y = 0.08;
    root.add(soilTop);
    const rows = Math.max(2, Math.floor(d / 1.3));
    for (let r = 0; r < rows; r++) {
      const z0 = -d / 2 + 0.5 + (r * (d - 1)) / (rows - 1 || 1);
      for (let i = 0; i < Math.max(3, Math.floor(w / 1.0)); i++) {
        const x0 = -w / 2 + 0.5 + (i * (w - 1)) / (Math.max(3, Math.floor(w / 1.0)) - 1 || 1);
        const col = variant % 3 === 0 ? 0x5d9c41 : variant % 3 === 1 ? 0xc94f2d : 0x7bbf53;
        const plant = addCyl(0.12, 0.18, 0.35 + ((i + r) % 3) * 0.08, col, 6);
        plant.position.set(x0, 0.23, z0);
        root.add(plant);
      }
    }
    // wheelbarrow-ish accent
    const wb = addBox(0.7, 0.18, 1.0, 0x607078);
    wb.position.set(w / 2 + 0.6, 0.28, d / 2 - 0.2);
    const wh = addCyl(0.18, 0.18, 0.08, 0x2b2b2b, 10);
    wh.rotation.z = Math.PI / 2;
    wh.position.set(w / 2 + 0.28, 0.16, d / 2 - 0.2);
    root.add(wb, wh);
    root.position.set(x, 0, z);
    if (scene) scene.add(root);
    return root;
  }
  function addIceCreamStandalone(x, z) {
    const root = new THREE.Group();
    const base = addBox(8.5, 0.3, 6.8, 0xcfc3ad);
    base.position.y = 0.15;
    root.add(base);
    const shop = addBox(7.4, 4.2, 5.8, 0xffd6df);
    shop.position.y = 2.25;
    root.add(shop);
    const roof = addBox(8.4, 0.45, 6.8, 0x6fb6d8);
    roof.position.y = 4.6;
    root.add(roof);
    const awn = addBox(3.0, 0.18, 1.0, 0xffffff);
    awn.position.set(0, 3.2, 3.35);
    root.add(awn);
    const window = addBox(2.3, 1.2, 0.08, 0xbfe8ff);
    window.position.set(0, 2.25, 2.94);
    root.add(window);
    const sign = addBox(3.2, 0.6, 0.18, 0xfff0a8);
    sign.position.set(0, 3.95, 3.0);
    root.add(sign);
    const cone = addCyl(0.0, 0.35, 1.0, 0xc48a56, 12);
    cone.position.set(-2.8, 1.1, 3.6);
    const scoop1 = addCyl(0.28, 0.34, 0.35, 0xf5c7d7, 10);
    scoop1.position.set(-2.8, 1.68, 3.6);
    const scoop2 = addCyl(0.24, 0.28, 0.28, 0xc7f0b0, 10);
    scoop2.position.set(-2.62, 1.88, 3.6);
    root.add(cone, scoop1, scoop2);
    // benches
    const b1 = addBox(1.4, 0.12, 0.38, 0x7d573d);
    b1.position.set(2.6, 0.55, 2.8);
    root.add(b1);
    root.position.set(x, 0, z);
    if (scene) scene.add(root);
    return root;
  }
  function addIceCreamStrip(x, z) {
    const root = new THREE.Group();
    const slab = addBox(12, 0.25, 7.5, 0xcbc0aa);
    slab.position.y = 0.125;
    root.add(slab);
    const shell = addBox(10.5, 4.2, 5.6, 0xe9eef0);
    shell.position.y = 2.2;
    root.add(shell);
    const fascia = addBox(10.8, 0.42, 0.5, 0x5ec0dd);
    fascia.position.set(0, 3.8, 2.55);
    root.add(fascia);
    const glass = addBox(2.4, 1.8, 0.08, 0xc7ebff);
    glass.position.set(-2.3, 2.1, 2.82);
    const glass2 = addBox(2.4, 1.8, 0.08, 0xc7ebff);
    glass2.position.set(1.3, 2.1, 2.82);
    const door = addBox(1.0, 2.0, 0.08, 0x6c4b3b);
    door.position.set(4.0, 1.2, 2.82);
    const sign = addBox(4.2, 0.7, 0.15, 0xfff2b6);
    sign.position.set(0, 3.3, 2.9);
    root.add(glass, glass2, door, sign);
    // parking bumpers / umbrellas
    for (let i = 0; i < 3; i++) {
      const umb = addCyl(0.08, 0.08, 2.0, 0x6c6c6c, 8);
      umb.position.set(-2.5 + i * 2.6, 1.0, -2.1);
      root.add(umb);
      const top = addCyl(0, 0.95, 0.35, i % 2 ? 0xff7da8 : 0x73d0f2, 14);
      top.position.set(-2.5 + i * 2.6, 2.05, -2.1);
      root.add(top);
    }
    root.position.set(x, 0, z);
    if (scene) scene.add(root);
    return root;
  }
  function addStream(points) {
    const root = new THREE.Group();
    for (let i = 0; i < points.length - 1; i++) {
      const a = points[i],
        b = points[i + 1];
      const dx = b.x - a.x,
        dz = b.z - a.z,
        len = Math.hypot(dx, dz);
      const water = addBox(len, 0.04, 2.1, 0x6dbfd6);
      water.position.set((a.x + b.x) / 2, 0.02, (a.z + b.z) / 2);
      water.rotation.y = Math.atan2(dz, dx);
      root.add(water);
      const bank1 = addBox(len, 0.08, 0.22, 0x8c7a5d);
      const bank2 = addBox(len, 0.08, 0.22, 0x8c7a5d);
      bank1.position.set((a.x + b.x) / 2, 0.03, (a.z + b.z) / 2 + 1.05);
      bank2.position.set((a.x + b.x) / 2, 0.03, (a.z + b.z) / 2 - 1.05);
      bank1.rotation.y = bank2.rotation.y = Math.atan2(dz, dx);
      root.add(bank1, bank2);
    }
    // crossing
    const mid = points[Math.floor(points.length / 2)];
    const bridge = addBox(3.2, 0.12, 1.2, 0x8f6f4b);
    bridge.position.set(mid.x, 0.14, mid.z);
    root.add(bridge);
    if (scene) scene.add(root);
    return root;
  }

  // Poles, routes and cable meshes are constructed in a single road-aware
  // utility network above. No detached post-generation pole moving is needed.

  function addNeighborhoodScenery() {
    // stream near park edge / west side
    addStream([
      { x: -175, z: 92 },
      { x: -160, z: 88 },
      { x: -142, z: 82 },
      { x: -126, z: 76 },
      { x: -112, z: 74 },
    ]);
    // shrubs clusters
    [
      [-30, 18],
      [-28, 23],
      [-26, 17],
      [44, -12],
      [48, -16],
      [53, -11],
      [86, 34],
      [91, 36],
      [120, -48],
      [124, -45],
      [-88, -52],
      [-92, -55],
      [-96, -50],
    ].forEach(([x, z], i) => addShrub(x, z, 0.9 + (i % 3) * 0.15, i % 4 ? 0x557a37 : 0x648843));
    // fences
    addFenceRun(-58, 38, -22, 38, "wood");
    addFenceRun(18, 44, 50, 44, "chain");
    addFenceRun(96, -36, 128, -36, "wood");
    addFenceRun(-118, -46, -118, -10, "chain");
    // gardens
    addGardenPlot(-36, 52, 7, 4, 0);
    addGardenPlot(116, -24, 6.5, 4.5, 1);
    addGardenPlot(-104, -18, 7.5, 3.8, 2);
    // ice cream shops: opposite sides / competitor vibe
    addIceCreamStandalone(152, 56);
    addIceCreamStrip(-154, -66);
  }

  function afterBuildWorldPass() {
    try {
      addNeighborhoodScenery();
    } catch (e) {
      console.warn("Environment scenery:", e);
    }
  }

  afterBuildWorldPass();
})();

const ONLINE_ASSETS = {
  bark: [
    "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/bark_willow/bark_willow_diff_1k.jpg",
    "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/bark_willow/bark_willow_nor_gl_1k.jpg",
  ],
  sky: "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/kloppenheim_06_puresky_1k.hdr",
};
// v5 presentation and resilience systems. No network resource is required to play.
const LightPresets = {
  golden: {
    sun: "#ffe0ab",
    sky: "#72a8ca",
    horizon: "#efdcb5",
    fog: "#c8d1bd",
    ground: "#56664a",
    power: 2.35,
    fill: 1.55,
    exposure: 1.12,
    direction: [-83, 94, -49],
  },
  daylight: {
    sun: "#fff5df",
    sky: "#569dd2",
    horizon: "#deebee",
    fog: "#bfd4d9",
    ground: "#657753",
    power: 2.7,
    fill: 1.8,
    exposure: 1.08,
    direction: [-55, 125, -40],
  },
  dusk: {
    sun: "#f4b88b",
    sky: "#485a8a",
    horizon: "#c29596",
    fog: "#89929e",
    ground: "#434757",
    power: 1.15,
    fill: 1.2,
    exposure: 1.18,
    direction: [-105, 55, -35],
  },
};
const graphicsRuntime = {
  composer: null,
  bloom: null,
  environment: null,
  pmrem: null,
  resizeTimer: 0,
  assetEpoch: 0,
  loadedMaterials: [],
  grass: [],
  motes: null,
  wind: { value: 0 },
  lastShadow: new THREE.Vector3(Infinity, Infinity, Infinity),
  lastSafe: new THREE.Vector3(-36, 0.31, -36),
  safeClock: 0,
  hidden: false,
  lastFar: camera.far,
};

function makeAtmosphere() {
  sky.material.dispose();
  sky.material = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    toneMapped: false,
    uniforms: {
      zenith: { value: new THREE.Color("#72a8ca") },
      horizon: { value: new THREE.Color("#efdcb5") },
      sunColor: { value: new THREE.Color("#ffe0ab") },
      sunDir: { value: new THREE.Vector3(-83, 94, -49).normalize() },
      t: { value: 0 },
    },
    vertexShader:
      "varying vec3 direction;void main(){direction=position;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}",
    fragmentShader: `varying vec3 direction;uniform vec3 zenith,horizon,sunColor,sunDir;uniform float t;
 float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123);}
 float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.)),f.x),f.y);}
 float fbm(vec2 p){return noise(p)*.57+noise(p*2.03)*.27+noise(p*4.09)*.12;}
 void main(){vec3 d=normalize(direction);float h=max(d.y,0.);vec3 col=mix(horizon,zenith,pow(h,.5));
 float sun=max(dot(d,sunDir),0.);col+=sunColor*(pow(sun,28.)*.18+pow(sun,750.)*.8);
 vec2 uv=d.xz/max(.22,d.y)*1.3+vec2(t*.003,t*.001);float clouds=smoothstep(.52,.73,fbm(uv));
 clouds*=smoothstep(.025,.20,d.y)*.6;col=mix(col,vec3(.98,.96,.90),clouds);
 gl_FragColor=vec4(col,1.);#include <colorspace_fragment>
 }`.replace(";#include", ";\n#include"),
  });
  cloudmat.opacity = 0.065;
}
function applyLighting() {
  const p = LightPresets[RenderConfig.light];
  sun.color.set(p.sun);
  sun.intensity = p.power;
  hemi.color.set(p.horizon);
  hemi.groundColor.set(p.ground);
  hemi.intensity = p.fill;
  scene.fog.color.set(p.fog);
  scene.background.set(p.horizon);
  if (sky.material.uniforms.zenith) {
    sky.material.uniforms.zenith.value.set(p.sky);
    sky.material.uniforms.horizon.value.set(p.horizon);
    sky.material.uniforms.sunColor.value.set(p.sun);
    sky.material.uniforms.sunDir.value.fromArray(p.direction).normalize();
  }
  renderer.toneMappingExposure = p.exposure;
  graphicsRuntime.lastShadow.set(Infinity, Infinity, Infinity);
}
function saveGraphics() {
  try {
    localStorage.setItem(
      "spicy-render-v5",
      JSON.stringify({ mode: RenderConfig.mode, light: RenderConfig.light, online: RenderConfig.online }),
    );
  } catch {}
}
function setGraphicsQuality(mode, announce = true) {
  if (!["auto", "high", "ultra", "performance"].includes(mode)) return;
  RenderConfig.mode = mode;
  RenderConfig.tier = mode === "auto" ? "high" : mode;
  RenderConfig.adaptiveScale = 1;
  applyQuality();
  saveGraphics();
  if (announce) flash("Graphics: " + mode.toUpperCase(), 2);
}
function applyQuality() {
  const tier = RenderConfig.tier;
  const shadows = tier !== "performance";
  renderer.shadowMap.enabled = shadows;
  sun.castShadow = shadows;
  const size = tier === "ultra" ? 4096 : 2048;
  if (sun.shadow.mapSize.x !== size) {
    sun.shadow.map?.dispose();
    sun.shadow.map = null;
    sun.shadow.mapSize.set(size, size);
  }
  const range = tier === "ultra" ? 100 : 76;
  sun.shadow.camera.left = -range;
  sun.shadow.camera.right = range;
  sun.shadow.camera.top = range;
  sun.shadow.camera.bottom = -range;
  sun.shadow.camera.near = 1;
  sun.shadow.camera.far = 300;
  sun.shadow.camera.updateProjectionMatrix();
  sun.shadow.bias = -0.00012;
  sun.shadow.normalBias = 0.09;
  for (const c of canopyShadowCasters)
    c.mesh.castShadow = shadows && Math.hypot(player.pos.x - c.x, player.pos.z - c.z) < 100;
  resizeGraphics();
  updateGraphicsLabels();
}
function resizeGraphics() {
  const w = Math.max(1, innerWidth),
    h = Math.max(1, innerHeight),
    tier = RenderConfig.tier;
  const max = tier === "ultra" ? 2 : tier === "performance" ? 1 : 1.5;
  const pixelBudget = tier === "ultra" ? 5e6 : tier === "performance" ? 1.4e6 : 2.8e6;
  const ratio = Math.max(
    0.6,
    Math.min(devicePixelRatio || 1, max, Math.sqrt(pixelBudget / (w * h))) * RenderConfig.adaptiveScale,
  );
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  renderer.setPixelRatio(ratio);
  renderer.setSize(w, h);
  if (graphicsRuntime.composer) {
    graphicsRuntime.composer.setPixelRatio(ratio);
    graphicsRuntime.composer.setSize(w, h);
  }
}
function updateGraphicsLabels() {
  $("qualityBtn").textContent = "GRAPHICS: " + RenderConfig.mode.toUpperCase();
  $("renderQuality").value = RenderConfig.mode;
  $("lightPreset").value = RenderConfig.light;
  $("onlineAssets").checked = RenderConfig.online;
  $("assetStatus").textContent = RenderConfig.onlineState;
  $("graphicsReadout").textContent =
    `${Math.round(1000 / Math.max(1, RenderConfig.frameMs))} fps · ${RenderConfig.tier} · ${renderer.getPixelRatio().toFixed(2)}× resolution · ${RenderConfig.effectsState}`;
}
function makeGroundDetail() {
  const randomDetail = rng(51903),
    rand = (a, b) => a + (b - a) * randomDetail(),
    buckets = new Map();
  // Decorative tufts stay away from streets, interiors, and running routes.
  for (const t of trees) {
    if (t.x > 700 || t.x < -700) continue;
    for (let i = 0; i < 90; i++) {
      const angle = rand(0, PI * 2),
        radius = rand(3.5, Math.min(20, (t.spec?.crown ?? 10) + 2));
      const x = t.x + Math.cos(angle) * radius,
        z = t.z + Math.sin(angle) * radius;
      if (
        pavementDistance(x, z) < 2 ||
        obstacles.some((o) => Math.abs(x - o.x) < o.w * 0.5 + 1 && Math.abs(z - o.z) < o.d * 0.5 + 1)
      )
        continue;
      const key = Math.floor(x / 32) + "," + Math.floor(z / 32);
      if (!buckets.has(key)) buckets.set(key, []);
      buckets.get(key).push({ x, z, y: terrainHeight(x, z), height: rand(0.18, 0.55), angle });
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute(
    "position",
    new THREE.Float32BufferAttribute(
      [-0.15, 0, 0, 0.15, 0, 0, 0.03, 1, 0.06, 0, 0, -0.16, 0, 0, 0.16, 0.06, 0.8, 0.03],
      3,
    ),
  );
  geo.computeVertexNormals();
  const material = new THREE.MeshStandardMaterial({ color: "#7d9852", roughness: 1, side: THREE.DoubleSide });
  material.onBeforeCompile = (s) => {
    s.uniforms.spicyWind = graphicsRuntime.wind;
    s.vertexShader = "uniform float spicyWind;\n" + s.vertexShader;
    s.vertexShader = s.vertexShader.replace(
      "#include <begin_vertex>",
      "#include <begin_vertex>\n#ifdef USE_INSTANCING\ntransformed.x += sin(spicyWind*1.4+instanceMatrix[3].x*.4+instanceMatrix[3].z*.3)*.12*position.y;\n#endif",
    );
  };
  const dummy = new THREE.Object3D(),
    color = new THREE.Color();
  for (const items of buckets.values()) {
    const ob = new THREE.InstancedMesh(geo, material, items.length);
    ob.receiveShadow = true;
    ob.castShadow = false;
    items.forEach((p, i) => {
      dummy.position.set(p.x, p.y + 0.015, p.z);
      dummy.scale.set(1, p.height, 1);
      dummy.rotation.y = p.angle;
      dummy.updateMatrix();
      ob.setMatrixAt(i, dummy.matrix);
      color.setHSL(rand(0.19, 0.25), rand(0.3, 0.44), rand(0.26, 0.43));
      ob.setColorAt(i, color);
    });
    ob.computeBoundingSphere();
    scene.add(ob);
    graphicsRuntime.grass.push({ mesh: ob, x: items[0].x, z: items[0].z });
  }
  const coords = new Float32Array(96 * 3);
  for (let i = 0; i < coords.length; i += 3) {
    coords[i] = rand(-22, 22);
    coords[i + 1] = rand(0.5, 15);
    coords[i + 2] = rand(-22, 22);
  }
  const particleGeo = new THREE.BufferGeometry();
  particleGeo.setAttribute("position", new THREE.BufferAttribute(coords, 3));
  const dots = new THREE.Points(
    particleGeo,
    new THREE.PointsMaterial({
      color: "#ffe4a7",
      size: 0.055,
      transparent: true,
      opacity: 0.45,
      depthWrite: false,
    }),
  );
  scene.add(dots);
  graphicsRuntime.motes = dots;
}

// Fetches are bounded and can be cancelled. Every replacement is atomic: the
// procedural material stays in place until its full downloaded set is ready.
const assetControllers = new Set();
async function fetchAsset(url, kind = "blob") {
  const controller = new AbortController();
  assetControllers.add(controller);
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const res = await fetch(url, { signal: controller.signal, credentials: "omit" });
    if (!res.ok) throw new Error("HTTP " + res.status);
    return kind === "buffer" ? await res.arrayBuffer() : await res.blob();
  } finally {
    clearTimeout(timer);
    assetControllers.delete(controller);
  }
}
async function textureFromURL(url, color) {
  const blob = await fetchAsset(url),
    objectURL = URL.createObjectURL(blob);
  try {
    const texture = await new THREE.TextureLoader().loadAsync(objectURL);
    texture.colorSpace = color ? THREE.SRGBColorSpace : THREE.NoColorSpace;
    texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
    texture.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
    return texture;
  } finally {
    URL.revokeObjectURL(objectURL);
  }
}
function timedImport(spec) {
  let timer;
  return Promise.race([
    import(spec),
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error("Optional graphics download timed out")), 14000);
    }),
  ]).finally(() => clearTimeout(timer));
}
function disposeComposer() {
  if (!graphicsRuntime.composer) return;
  for (const pass of graphicsRuntime.composer.passes) pass.dispose?.();
  graphicsRuntime.composer.dispose();
  graphicsRuntime.composer = null;
  graphicsRuntime.bloom = null;
}
function resetOnlineGraphics() {
  graphicsRuntime.assetEpoch++;
  for (const c of assetControllers) c.abort();
  assetControllers.clear();
  disposeComposer();
  RenderConfig.effectsState = "basic";
  for (const record of graphicsRuntime.loadedMaterials) {
    Object.assign(record.material, record.previous);
    record.material.needsUpdate = true;
    for (const tex of record.textures) tex.dispose();
  }
  graphicsRuntime.loadedMaterials = [];
  scene.environment = null;
  graphicsRuntime.environment?.dispose();
  graphicsRuntime.environment = null;
  graphicsRuntime.pmrem?.dispose();
  graphicsRuntime.pmrem = null;
}
async function loadOnlineGraphics() {
  const epoch = ++graphicsRuntime.assetEpoch;
  RenderConfig.onlineState = "Loading optional detail…";
  updateGraphicsLabels();
  const active = () => epoch === graphicsRuntime.assetEpoch && RenderConfig.online;
  const pack = async (material, urls, repeat) => {
    const results = await Promise.allSettled(urls.map((url, i) => textureFromURL(url, i === 0)));
    const textures = results.filter((r) => r.status === "fulfilled").map((r) => r.value);
    if (!active() || results.some((r) => r.status === "rejected")) {
      textures.forEach((t) => t.dispose());
      throw new Error("Material pack unavailable");
    }
    textures.forEach((t) => t.repeat.set(...repeat));
    const previous = {
      map: material.map,
      normalMap: material.normalMap,
      normalScale: material.normalScale.clone(),
      color: material.color.clone(),
    };
    material.map = textures[0];
    material.normalMap = textures[1];
    material.normalScale.set(0.6, 0.6);
    material.color.set("#b0ac9b");
    material.needsUpdate = true;
    graphicsRuntime.loadedMaterials.push({ material, previous, textures });
  };
  const textureJob = pack(M.bark, ONLINE_ASSETS.bark, [1, 3]);
  const effectsJob = (async () => {
    if (!renderer.capabilities.isWebGL2 || !renderer.extensions.has("EXT_color_buffer_float"))
      throw new Error("Using built-in rendering on this graphics device");
    const modules = await Promise.all([
      timedImport("three/addons/postprocessing/EffectComposer.js"),
      timedImport("three/addons/postprocessing/RenderPass.js"),
      timedImport("three/addons/postprocessing/UnrealBloomPass.js"),
      timedImport("three/addons/postprocessing/OutputPass.js"),
    ]);
    if (!active()) return;
    const composer = new modules[0].EffectComposer(renderer);
    graphicsRuntime.composer = composer;
    composer.addPass(new modules[1].RenderPass(scene, camera));
    const bloom = new modules[2].UnrealBloomPass(
      new THREE.Vector2(innerWidth, innerHeight),
      0.13,
      0.35,
      1.15,
    );
    composer.addPass(bloom);
    composer.addPass(new modules[3].OutputPass());
    graphicsRuntime.bloom = bloom;
    RenderConfig.effectsState = "soft bloom";
    resizeGraphics();
  })();
  const environmentJob = (async () => {
    if (!renderer.capabilities.isWebGL2 || !renderer.extensions.has("EXT_color_buffer_float"))
      throw new Error("Using built-in lighting on this graphics device");
    const [{ RGBELoader }, bytes] = await Promise.all([
      timedImport("three/addons/loaders/RGBELoader.js"),
      fetchAsset(ONLINE_ASSETS.sky, "buffer"),
    ]);
    if (!active()) return;
    const data = new RGBELoader().parse(bytes),
      texture = new THREE.DataTexture(data.data, data.width, data.height, THREE.RGBAFormat, data.type);
    texture.colorSpace = THREE.LinearSRGBColorSpace;
    texture.mapping = THREE.EquirectangularReflectionMapping;
    texture.flipY = true;
    texture.needsUpdate = true;
    const pmrem = new THREE.PMREMGenerator(renderer);
    let env;
    try {
      env = pmrem.fromEquirectangular(texture);
    } finally {
      texture.dispose();
      pmrem.dispose();
    }
    if (!active()) {
      env.dispose();
      return;
    }
    graphicsRuntime.environment = env;
    scene.environment = env.texture;
    // Reflections add depth without bleaching painted surfaces or the canopy.
    scene.traverse((o) => {
      for (const m of Array.isArray(o.material) ? o.material : [o.material])
        if (m?.isMeshStandardMaterial) m.envMapIntensity = 0.3;
    });
  })();
  const results = await Promise.allSettled([textureJob, effectsJob, environmentJob]);
  if (!active()) return;
  if (results[1].status === "rejected") {
    disposeComposer();
    RenderConfig.effectsState = "basic";
  }
  const passed = results.filter((r) => r.status === "fulfilled").length;
  RenderConfig.onlineState =
    passed === 3
      ? "Online detail loaded"
      : passed
        ? `${passed}/3 enhancements loaded · built-in fallback active`
        : "Built-in graphics active · downloads unavailable";
  updateGraphicsLabels();
}
function updateVisuals(dt, frameDt) {
  const indoor =
    player.inHospital || player.inSewer || player.inDuct || !!activeHouseInterior || mallState.inside;
  sky.visible = !indoor || mallState.inside;
  sky.position.set(camera.position.x, 0, camera.position.z);
  sky.material.uniforms.t.value = time;
  graphicsRuntime.wind.value = time;
  const p = LightPresets[RenderConfig.light];
  renderer.toneMappingExposure = player.inHospital
    ? 1.12
    : player.inSewer
      ? 1.05
      : mallState.inside
        ? 1.15
        : p.exposure;
  if (!indoor) scene.fog.color.set(p.fog);
  if (graphicsRuntime.lastFar !== camera.far) {
    camera.updateProjectionMatrix();
    graphicsRuntime.lastFar = camera.far;
  }
  const center = new THREE.Vector3(
    Math.round(player.pos.x * 8) / 8,
    Math.max(0, player.pos.y) + 9,
    Math.round(player.pos.z * 8) / 8,
  );
  if (center.distanceToSquared(graphicsRuntime.lastShadow) > 0.25) {
    sun.target.position.copy(center);
    sun.position.copy(center).add(new THREE.Vector3().fromArray(p.direction));
    sun.target.updateMatrixWorld();
    graphicsRuntime.lastShadow.copy(center);
  }
  for (const chunk of graphicsRuntime.grass)
    chunk.mesh.visible =
      !indoor &&
      RenderConfig.tier !== "performance" &&
      Math.hypot(player.pos.x - chunk.x, player.pos.z - chunk.z) < 125;
  if (graphicsRuntime.motes) {
    graphicsRuntime.motes.visible = !indoor && RenderConfig.tier !== "performance";
    graphicsRuntime.motes.position.copy(player.pos);
    graphicsRuntime.motes.rotation.y = time * 0.012;
  }
  // Ignore tab restoration and exceptional stalls; adjust only after sustained load.
  if (frameDt > 0 && frameDt < 0.25 && !document.hidden && !gamePaused) {
    RenderConfig.frameMs = THREE.MathUtils.lerp(RenderConfig.frameMs, frameDt * 1000, 0.035);
    RenderConfig.sampleSeconds += frameDt;
    if (RenderConfig.mode === "auto" && RenderConfig.sampleSeconds > 10) {
      if (RenderConfig.frameMs > 30 && RenderConfig.adaptiveScale > 0.72) {
        RenderConfig.adaptiveScale = Math.max(0.7, RenderConfig.adaptiveScale - 0.12);
        resizeGraphics();
      } else if (RenderConfig.frameMs > 40 && RenderConfig.tier === "high") {
        RenderConfig.tier = "performance";
        applyQuality();
      }
      RenderConfig.sampleSeconds = 0;
    }
  }
  if (time - RenderConfig.lastAdapt > 0.75) {
    RenderConfig.lastAdapt = time;
    updateGraphicsLabels();
  }
}
function renderFrame(dt) {
  if (graphicsRuntime.composer && RenderConfig.tier !== "performance") {
    try {
      graphicsRuntime.composer.render(dt);
      return;
    } catch (error) {
      console.warn("Optional postprocessing disabled:", error);
      disposeComposer();
      RenderConfig.effectsState = "basic fallback";
      updateGraphicsLabels();
    }
  }
  renderer.setRenderTarget(null);
  renderer.render(scene, camera);
}
function validatePlayerState(dt) {
  const p = player.pos;
  if (![p.x, p.y, p.z, player.vel.x, player.vel.y, player.vel.z].every(Number.isFinite) || p.y < -150) {
    p.copy(graphicsRuntime.lastSafe);
    player.vel.set(0, 0, 0);
    player.rail = null;
    player.grounded = false;
    cameraHardCut = true;
    flash("Recovered to your last safe position.", 3);
  }
  graphicsRuntime.safeClock += dt;
  if (graphicsRuntime.safeClock > 0.5 && player.grounded && !player.rail && !player.inDuct) {
    graphicsRuntime.lastSafe.copy(p);
    graphicsRuntime.safeClock = 0;
  }
}
function clearControls() {
  keys.clear();
  focusMouse = false;
  focusToggle = false;
  player.focus = false;
}
function setGraphicsPanel(open) {
  $("graphicsPanel").hidden = !open;
  if (open) {
    clearControls();
    document.exitPointerLock?.();
    gamePaused = true;
    $("renderQuality").focus();
  } else {
    gamePaused = graphicsPanelWasPaused;
    $("graphicsBtn").focus();
  }
}
let graphicsPanelWasPaused = false;
function openGraphics() {
  graphicsPanelWasPaused = gamePaused;
  setGraphicsPanel(true);
}
function initRefresh() {
  makeAtmosphere();
  makeGroundDetail();
  applyLighting();
  setGraphicsQuality(RenderConfig.mode, false);
  $("graphicsBtn").onclick = openGraphics;
  $("closeGraphics").onclick = () => setGraphicsPanel(false);
  $("qualityBtn").onclick = () => {
    const choices = ["auto", "high", "ultra", "performance"];
    setGraphicsQuality(choices[(choices.indexOf(RenderConfig.mode) + 1) % choices.length]);
  };
  $("renderQuality").onchange = (e) => setGraphicsQuality(e.target.value);
  $("lightPreset").onchange = (e) => {
    RenderConfig.light = e.target.value;
    applyLighting();
    saveGraphics();
  };
  $("onlineAssets").onchange = (e) => {
    RenderConfig.online = e.target.checked;
    resetOnlineGraphics();
    saveGraphics();
    if (RenderConfig.online) void loadOnlineGraphics();
    else {
      RenderConfig.onlineState = "Built-in graphics · online detail off";
      updateGraphicsLabels();
    }
  };
  $("resumeAfterBlur").onclick = () => {
    if (RenderConfig.contextLost) return;
    $("pauseShield").hidden = true;
    gamePaused = false;
    wallLast = performance.now();
    clock.getDelta();
    canvas.focus();
    requestMouse();
  };
  window.addEventListener("blur", () => {
    clearControls();
    if (playing && !gamePaused) {
      gamePaused = true;
      $("pauseShield").hidden = false;
    }
  });
  document.addEventListener("visibilitychange", () => {
    clearControls();
    wallLast = performance.now();
    clock.getDelta();
    if (document.hidden && playing && !gamePaused) {
      gamePaused = true;
      $("pauseShield").hidden = false;
    }
  });
  canvas.addEventListener("webglcontextlost", (e) => {
    e.preventDefault();
    RenderConfig.contextLost = true;
    gamePaused = true;
    clearControls();
    $("pauseShield").hidden = false;
    $("pauseMessage").textContent =
      "Graphics interrupted. Waiting for your browser to restore the 3D context…";
    $("resumeAfterBlur").disabled = true;
  });
  canvas.addEventListener("webglcontextrestored", () => {
    RenderConfig.contextLost = false;
    resetOnlineGraphics();
    applyQuality();
    applyLighting();
    $("pauseMessage").textContent = "Graphics restored. Your run is still here.";
    $("resumeAfterBlur").disabled = false;
    if (RenderConfig.online) void loadOnlineGraphics();
  });
  window.addEventListener("keydown", (e) => {
    if (!$("pauseShield").hidden) return;
    if (e.code === "KeyG" && !e.repeat) {
      e.preventDefault();
      $("graphicsPanel").hidden ? openGraphics() : setGraphicsPanel(false);
    }
    if (e.code === "Escape" && !$("graphicsPanel").hidden) setGraphicsPanel(false);
  });
  RenderConfig.batches = BatchingStats.after;
  RenderConfig.mergedMeshes = BatchingStats.before;
  if (RenderConfig.online) void loadOnlineGraphics();
  else {
    RenderConfig.onlineState = "Built-in graphics · online detail off";
    updateGraphicsLabels();
  }
}

// BELLWETHER QUAY — an additive, traversable eastern district.
const riverDistrictGroup = new THREE.Group();
riverDistrictGroup.name = "Bellwether Quay / Willow River";
scene.add(riverDistrictGroup);
const riverBuildings = [],
  riverColliders = [],
  riverPlatforms = [],
  riverBoats = [],
  riverBanners = [],
  riverWalkers = [];
const riverVisuals = { water: null, elapsed: 0, rescueCooldown: 0, visited: false };
const riverMaterials = {
  stone: mat("#aaa697"),
  stoneLight: mat("#d1c7ae"),
  stoneDark: mat("#777b70"),
  wood: mat("#4e4136"),
  oak: mat("#75604b"),
  copper: mat("#718679", 0.58, 0.3),
  iron: mat("#364b51", 0.55, 0.55),
  blue: mat("#4e7c87", 0.52, 0.35),
  glass: mat("#c3cfb5", 0.22, 0.15),
  roof: mat("#4c5a60"),
};
const riverRand = rng(5110726);
const rriv = (a, b) => a + (b - a) * riverRand();
function riverBox(w, h, d, m, x, y, z, parent = riverDistrictGroup) {
  return box(w, h, d, m, x, y, z, parent);
}
function riverLine(points, material, radius, segments) {
  const result = linePath(points, material, radius, segments);
  riverDistrictGroup.add(result.obj);
  return result;
}
function riverCollider(x, z, w, d, y0, y1, label) {
  const c = { x, z, w, d, y0, y1, label };
  riverColliders.push(c);
  return c;
}
function riverSurfaceAt(x, z) {
  let y = riverDeckAt(x, z);
  for (const s of riverPlatforms) {
    if (Math.abs(x - s.x) <= s.w / 2 && Math.abs(z - s.z) <= s.d / 2)
      y = Math.max(y ?? -Infinity, s.height ? s.height(x, z) : s.y);
  }
  return y;
}
function riverRoofAt(x, z) {
  let top = null;
  for (const b of riverBuildings) {
    const dx = x - b.x,
      dz = z - b.z,
      c = Math.cos(b.rotation),
      s = Math.sin(b.rotation),
      lx = c * dx - s * dz,
      lz = s * dx + c * dz;
    if (Math.abs(lx) > b.w / 2 + 0.55 || Math.abs(lz) > b.d / 2 + 0.65) continue;
    const y = b.base + b.h + b.rise * Math.max(0, 1 - Math.abs(lz) / (b.d / 2 + 0.65)) + 0.29;
    if (top === null || y > top) top = y;
  }
  return top;
}
function riverBlocked(x, z, height) {
  if (!inRiverDistrict(x, z)) return false;
  for (const c of riverColliders) {
    if (height >= c.y1 - 0.05 || height < c.y0 - 0.25) continue;
    if (Math.abs(x - c.x) < c.w / 2 + 0.32 && Math.abs(z - c.z) < c.d / 2 + 0.32) return true;
  }
  // Approaches have a solid ramp face. A player may walk uphill from either end,
  // but cannot cut through the steep side of a raised bridge approach.
  const deck = riverDeckAt(x, z);
  if (deck !== null && height < deck - 0.55) return true;
  return false;
}
function cobbleTexture() {
  const c = document.createElement("canvas");
  c.width = c.height = 512;
  const g = c.getContext("2d");
  g.fillStyle = "#6b6b5e";
  g.fillRect(0, 0, 512, 512);
  for (let row = 0; row < 16; row++)
    for (let col = -1; col < 13; col++) {
      const x = col * 44 + (row % 2) * 22,
        y = row * 32;
      const shade = Math.round(rriv(112, 158));
      g.fillStyle = `rgb(${shade + 13},${shade + 9},${shade - 4})`;
      g.beginPath();
      g.roundRect(x + 2, y + 2, 40, 28, 5);
      g.fill();
      g.strokeStyle = "#dfd2b33d";
      g.lineWidth = 2;
      g.stroke();
    }
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  return tex;
}
const riverCobble = new THREE.MeshStandardMaterial({
  map: cobbleTexture(),
  color: "#c4bdab",
  roughness: 0.97,
});
function groundPatch(x0, x1, z0, z1, material, heightFn, segmentsX = 16, segmentsZ = 32) {
  const geo = new THREE.PlaneGeometry(x1 - x0, z1 - z0, segmentsX, segmentsZ);
  geo.rotateX(-PI / 2);
  geo.translate((x0 + x1) / 2, 0, (z0 + z1) / 2);
  const pos = geo.attributes.position,
    uv = geo.attributes.uv;
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i),
      z = pos.getZ(i);
    pos.setY(i, heightFn(x, z));
    uv.setXY(i, x / 8, z / 8);
  }
  geo.computeVertexNormals();
  const ob = mesh(geo, material, 0, 0, 0, riverDistrictGroup, false);
  ob.receiveShadow = true;
  return ob;
}
function makeRiverBanks() {
  for (const side of [-1, 1]) {
    const vertices = [],
      uv = [],
      indices = [],
      rows = 128,
      cols = 20;
    for (let j = 0; j <= rows; j++) {
      const z = RIVER.zMin + ((RIVER.zMax - RIVER.zMin) * j) / rows,
        edge = riverCenter(z) + side * RIVER.halfWidth;
      const start = side < 0 ? RIVER.startX : edge,
        end = side < 0 ? edge : RIVER.endX;
      for (let i = 0; i <= cols; i++) {
        const x = THREE.MathUtils.lerp(start, end, i / cols);
        vertices.push(x, terrainHeight(x, z) - 0.07, z);
        uv.push(x / 8, z / 8);
      }
    }
    for (let j = 0; j < rows; j++)
      for (let i = 0; i < cols; i++) {
        const a = j * (cols + 1) + i;
        indices.push(a, a + cols + 1, a + 1, a + 1, a + cols + 1, a + cols + 2);
      }
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
    g.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
    g.setIndex(indices);
    g.computeVertexNormals();
    const bank = mesh(g, riverCobble, 0, 0, 0, riverDistrictGroup, false);
    bank.receiveShadow = true;
    // Continuous curved stone embankments with coping, mooring rings and lamps.
    for (let z = RIVER.zMin; z < RIVER.zMax; z += 6) {
      const zz = Math.min(RIVER.zMax, z + 6),
        mx = (riverCenter(z) + riverCenter(zz)) / 2 + side * RIVER.halfWidth;
      const wall = riverBox(1.3, 7.8, zz - z + 0.15, riverMaterials.stoneDark, mx, 3.95, (z + zz) / 2);
      wall.rotation.y = Math.atan2(riverCenter(zz) - riverCenter(z), zz - z);
      const cap = riverBox(1.9, 0.32, zz - z + 0.15, riverMaterials.stoneLight, mx, 8.02, (z + zz) / 2);
      cap.rotation.y = wall.rotation.y;
    }
    for (let z = -218; z < 420; z += 34) {
      const x = riverCenter(z) + side * (RIVER.halfWidth + 3);
      if (Math.abs(z) < 24) continue;
      riverLamp(x, z, 8);
      riverBox(0.55, 0.6, 0.55, riverMaterials.iron, x - side * 2.2, 8.3, z + 7);
    }
  }
  // Retain the existing eastern road and carry it to the bridge approach.
  groundPatch(650, 744, -8, 8, M.asphalt, (x, z) => terrainHeight(x, z) + 0.1, 28, 2);
  for (const z of [-11, 11])
    groundPatch(650, 744, z - 1.7, z + 1.7, riverCobble, (x, zz) => terrainHeight(x, zz) + 0.13, 28, 1);
}
function riverLamp(x, z, y) {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  riverDistrictGroup.add(g);
  cyl(0.13, 0.23, 4.1, riverMaterials.iron, 0, 2.05, 0, g, 8);
  riverBox(0.57, 0.16, 0.57, riverMaterials.iron, 0, 4.05, 0, g);
  const glass = new THREE.MeshStandardMaterial({
    color: "#f5d999",
    emissive: "#ffc66d",
    emissiveIntensity: 1.2,
    roughness: 0.4,
  });
  riverBox(0.42, 0.67, 0.42, glass, 0, 4.43, 0, g);
  const top = mesh(new THREE.ConeGeometry(0.54, 0.42, 4), riverMaterials.iron, 0, 4.95, 0, g);
  top.rotation.y = PI / 4;
}
function makeRiverWater() {
  const vertices = [],
    uv = [],
    indices = [],
    rows = 150,
    cols = 20;
  for (let j = 0; j <= rows; j++) {
    const z = RIVER.zMin + ((RIVER.zMax - RIVER.zMin) * j) / rows;
    for (let i = 0; i <= cols; i++) {
      const x = riverCenter(z) - RIVER.halfWidth + (2 * RIVER.halfWidth * i) / cols;
      vertices.push(x, RIVER.waterY, z);
      uv.push(i / cols, j / rows);
    }
  }
  for (let j = 0; j < rows; j++)
    for (let i = 0; i < cols; i++) {
      const a = j * (cols + 1) + i;
      indices.push(a, a + cols + 1, a + 1, a + 1, a + cols + 1, a + cols + 2);
    }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
  geo.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  const material = new THREE.ShaderMaterial({
    side: THREE.DoubleSide,
    uniforms: {
      t: { value: 0 },
      deep: { value: new THREE.Color("#315c61") },
      glint: { value: new THREE.Color("#b7d2c1") },
    },
    vertexShader: `uniform float t;varying vec3 worldP;varying vec2 flowUV;void main(){vec3 p=position;p.y+=sin(p.x*.24+p.z*.08+t*.65)*.10+sin(p.z*.39-t*.8)*.035;worldP=(modelMatrix*vec4(p,1.)).xyz;flowUV=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(p,1.);}`,
    fragmentShader: `uniform float t;uniform vec3 deep,glint;varying vec3 worldP;varying vec2 flowUV;
 void main(){float wave=sin(worldP.x*.40+worldP.z*.18-t*.8)*sin(worldP.x*.13-worldP.z*.51+t*.54);float threads=pow(max(0.,wave),14.);float edge=pow(abs(flowUV.x-.5)*2.,14.);vec3 eye=normalize(cameraPosition-worldP);float fresnel=pow(1.-abs(eye.y),3.);vec3 col=mix(deep,glint,.13+fresnel*.28)+threads*.16+edge*.065;gl_FragColor=vec4(col,1.);
 #include <tonemapping_fragment>
 #include <colorspace_fragment>
 }`,
  });
  const water = new THREE.Mesh(geo, material);
  water.name = "Willow River — animated current";
  riverDistrictGroup.add(water);
  riverVisuals.water = water;
}
function bridgeArch(cx, width) {
  const outer = width / 2,
    inner = outer - 2.4,
    spring = 3.5;
  const shape = new THREE.Shape();
  shape.moveTo(-outer, 1);
  shape.lineTo(-outer, RIVER.deckY - 0.3);
  shape.lineTo(outer, RIVER.deckY - 0.3);
  shape.lineTo(outer, 1);
  shape.lineTo(inner, 1);
  shape.lineTo(inner, spring);
  shape.absarc(0, spring, inner, 0, PI, false);
  shape.lineTo(-inner, 1);
  shape.closePath();
  const g = new THREE.ExtrudeGeometry(shape, { depth: 15.7, bevelEnabled: false, curveSegments: 18 });
  g.translate(cx, 0, -7.85);
  mesh(g, riverMaterials.stone, 0, 0, 0, riverDistrictGroup);
  for (const z of [-8, 8])
    for (let i = 0; i < 15; i++) {
      const a = (PI * (i + 0.5)) / 15,
        r = inner + 0.7;
      const block = riverBox(
        1.9,
        1.25,
        0.32,
        i % 3 ? riverMaterials.stoneLight : riverMaterials.stoneDark,
        cx + Math.cos(a) * r,
        spring + Math.sin(a) * r,
        z,
      );
      block.rotation.z = a - PI / 2;
    }
  // Streamlined cutwaters at the base of the piers.
  const pier = cyl(2.3, 3.0, 3.6, riverMaterials.stoneDark, cx - outer, 3.1, 0, riverDistrictGroup, 4);
  pier.scale.z = 3.2;
  pieFace(pier);
}
function pieFace(object) {
  object.rotation.y = PI / 4;
  return object;
}
function makeBridgeTower(x) {
  const g = new THREE.Group();
  g.position.set(x, RIVER.deckY, 0);
  riverDistrictGroup.add(g);
  for (const side of [-1, 1]) {
    const z = side * 10.7;
    riverBox(8, 19, 7.2, riverMaterials.stoneLight, 0, 9.5, z, g);
    riverBox(9.2, 0.8, 8.4, riverMaterials.stone, 0, 0.4, z, g);
    for (const yy of [3.5, 9, 14.5]) {
      riverBox(8.45, 0.4, 7.7, riverMaterials.stone, 0, yy, z, g);
      for (const face of [-1, 1]) {
        riverBox(1.05, 2.2, 0.12, riverMaterials.glass, face * 2.1, yy + 2, z - side * 3.66, g);
        riverBox(1.05, 2.2, 0.12, riverMaterials.glass, face * 2.1, yy + 2, z + side * 3.66, g);
      }
    }
    for (const xx of [-3.7, 3.7])
      for (const zz of [-3.3, 3.3]) {
        cyl(0.72, 0.86, 20.4, riverMaterials.stone, xx, 10.2, z + zz, g, 8);
        const cap = mesh(new THREE.ConeGeometry(1.04, 3.1, 8), riverMaterials.roof, xx, 21.4, z + zz, g);
        cap.castShadow = true;
      }
    const roof = mesh(new THREE.ConeGeometry(5.5, 4.5, 4), riverMaterials.roof, 0, 21.3, z, g);
    roof.rotation.y = PI / 4;
    roof.scale.z = 0.86;
    riverCollider(x, z, 8.4, 7.6, RIVER.deckY, RIVER.deckY + 19.3, "bridge tower");
  }
  riverBox(8, 3.4, 15.5, riverMaterials.stone, 0, 15.2, 0, g);
  riverBox(8.6, 0.45, 15.8, riverMaterials.stoneLight, 0, 17.1, 0, g);
  for (const z of [-5, 0, 5]) riverBox(0.15, 1.5, 1.5, riverMaterials.glass, -4.1, 15.4, z, g);
  riverCollider(x, 0, 8, 14, RIVER.deckY + 13.4, RIVER.deckY + 17.4, "tower overhead arch");
  const banner = riverBox(0.05, 4.0, 1.6, mat("#af5949"), 4.5, 11.6, sideForBanner(x) * 8.2, g);
  riverBanners.push({ mesh: banner, phase: x });
  // Drainpipe routes connect deck level to the tower gallery.
  const routeZ = 7.0;
  span(
    v(x + 4.5, RIVER.deckY + 0.2, routeZ),
    v(x + 4.5, RIVER.deckY + 17.7, routeZ),
    0.13,
    0.13,
    riverMaterials.copper,
    riverDistrictGroup,
  );
  addRoute(
    "River bridge tower downspout",
    [v(x + 4.5, RIVER.deckY + 0.25, routeZ), v(x + 4.5, RIVER.deckY + 17.7, routeZ)],
    { kind: "trunk", surfaceRadius: 0.15 },
  );
  addRoute(
    "River bridge tower gallery",
    [v(x + 4.5, RIVER.deckY + 17.7, routeZ), v(x + 4.5, RIVER.deckY + 17.7, -7)],
    { kind: "roof" },
  );
}
function sideForBanner(x) {
  return x < 850 ? -1 : 1;
}
function makeRiverBridge() {
  for (let i = 0; i < 5; i++) bridgeArch(802 + i * 24, 24);
  groundPatch(RIVER.rampStart, RIVER.rampEnd, -7.8, 7.8, riverCobble, (x, z) => riverDeckAt(x, z), 106, 4);
  for (const side of [-1, 1]) {
    const points = [];
    for (let x = RIVER.rampStart; x <= RIVER.rampEnd; x += 2)
      points.push(v(x, riverDeckAt(x, 0) + 1.1, side * 7.7));
    riverLine(points, riverMaterials.stoneLight, 0.2, 120);
    addRoute("River bridge stone parapet " + (side < 0 ? "north" : "south"), points, { kind: "fence" });
    for (let x = RIVER.rampStart + 1; x < RIVER.rampEnd; x += 4) {
      const y = riverDeckAt(x, 0);
      riverBox(0.32, 1.05, 0.3, riverMaterials.stone, x, y + 0.52, side * 7.7);
      riverCollider(x, side * 7.7, 4, 0.3, y, y + 1.05, "bridge parapet");
    }
    // Blue suspension chains give the bridge its familiar London-like silhouette.
    const cable = [
      v(772, 14, side * 8.7),
      v(814, 34, side * 8.7),
      v(850, 25, side * 8.7),
      v(886, 34, side * 8.7),
      v(928, 14, side * 8.7),
    ];
    const curve = new THREE.CatmullRomCurve3(cable, false, "centripetal");
    riverLine(cable, riverMaterials.blue, 0.19, 100);
    for (let i = 0; i <= 44; i++) {
      const p = curve.getPointAt(i / 44);
      if (p.x < 790 || p.x > 910) continue;
      span(v(p.x, RIVER.deckY + 0.7, p.z), p, 0.055, 0.055, riverMaterials.blue, riverDistrictGroup, 5);
    }
    addRoute("River bridge suspension cable " + side, cable, { kind: "wire" });
  }
  makeBridgeTower(814);
  makeBridgeTower(886);
  for (const x of [752, 777, 838, 862, 925, 947])
    for (const side of [-1, 1]) riverLamp(x, side * 6.45, riverDeckAt(x, 0));
}
function riverWindow(parent, x, y, z, w = 1.3, h = 1.8) {
  riverBox(w + 0.22, h + 0.22, 0.1, riverMaterials.wood, x, y, z, parent);
  riverBox(w, h, 0.14, riverMaterials.glass, x, y, z - 0.08, parent);
  riverBox(0.09, h, 0.18, riverMaterials.oak, x, y, z - 0.16, parent);
  riverBox(w, 0.09, 0.18, riverMaterials.oak, x, y, z - 0.16, parent);
}
function quayRoof(parent, w, d, eave, ridge, roofMaterial, wallMaterial) {
  const hw = w / 2 + 0.5,
    hd = d / 2 + 0.6;
  const positions = [-hw, eave, -hd, hw, eave, -hd, hw, ridge, 0, -hw, ridge, 0, -hw, eave, hd, hw, eave, hd];
  const roof = new THREE.BufferGeometry();
  roof.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  roof.setIndex([0, 2, 1, 0, 3, 2, 4, 5, 2, 4, 2, 3]);
  roof.setAttribute(
    "uv",
    new THREE.Float32BufferAttribute([0, 0, w / 5, 0, w / 5, d / 10, 0, d / 10, 0, d / 5, w / 5, d / 5], 2),
  );
  roof.computeVertexNormals();
  mesh(roof, roofMaterial, 0, 0, 0, parent);
  // End gables use explicit coordinates, avoiding rotations around the origin
  // that would displace a tall facade triangle away from its house.
  for (const side of [-1, 1]) {
    const x = (side * w) / 2,
      cap = new THREE.BufferGeometry();
    cap.setAttribute(
      "position",
      new THREE.Float32BufferAttribute([x, eave, -d / 2, x, ridge, 0, x, eave, d / 2], 3),
    );
    cap.setIndex(side > 0 ? [0, 1, 2] : [2, 1, 0]);
    cap.setAttribute("uv", new THREE.Float32BufferAttribute([0, 0, 0.5, 1, 1, 0], 2));
    cap.computeVertexNormals();
    mesh(cap, wallMaterial, 0, 0, 0, parent);
    span(v(x, eave, -d / 2), v(x, ridge, 0), 0.13, 0.13, riverMaterials.wood, parent, 4);
    span(v(x, ridge, 0), v(x, eave, d / 2), 0.13, 0.13, riverMaterials.wood, parent, 4);
  }
}
function makeQuayBuilding(x, z, rotation, index, label) {
  const w = 15 + (index % 3) * 1.8,
    d = 12 + (index % 2) * 2,
    h = 10 + (index % 4) * 1.25,
    rise = 4.0 + (index % 3) * 0.6,
    base = terrainHeight(x, z),
    g = new THREE.Group();
  g.position.set(x, base, z);
  g.rotation.y = rotation;
  riverDistrictGroup.add(g);
  const plaster = mat(["#d8c6a1", "#c0b9a0", "#d7b399", "#b9c2b0", "#c9bda7"][index % 5]);
  const roofMat = mat(["#6e635a", "#505e63", "#71695b", "#72615b"][index % 4]);
  riverBox(w, 0.65, d, riverMaterials.stoneDark, 0, 0.325, 0, g);
  riverBox(w, h, d, plaster, 0, h / 2, 0, g);
  // Overhanging upper storey, exposed framing, and diagonal Tudor braces.
  riverBox(w + 0.7, h * 0.47, d + 0.6, plaster, 0, h * 0.755, 0, g);
  for (const yy of [0.9, h * 0.51, h - 0.2])
    riverBox(w + 0.9, 0.28, d + 0.8, riverMaterials.wood, 0, yy, 0, g);
  for (const side of [-1, 1]) {
    const zz = side * (d / 2 + 0.39);
    for (const xx of [-w / 2, -w / 4, 0, w / 4, w / 2])
      riverBox(0.23, h - 0.5, 0.2, riverMaterials.wood, xx, h / 2, zz, g);
    for (const xx of [-w * 0.36, w * 0.36]) {
      span(v(xx - 1.5, h * 0.54, zz), v(xx + 1.5, h - 0.4, zz), 0.12, 0.12, riverMaterials.wood, g, 4);
    }
  }
  quayRoof(g, w + 0.6, d + 0.6, h, h + rise, roofMat, plaster);
  for (const xx of [-w * 0.32, 0, w * 0.32]) {
    riverWindow(g, xx, h * 0.72, -d / 2 - 0.54, 1.45, 2.0);
    if (xx !== 0) riverWindow(g, xx, 2.85, -d / 2 - 0.14, 2.5, 2.6);
  }
  riverBox(1.55, 3.4, 0.2, riverMaterials.oak, 0, 1.7, -d / 2 - 0.2, g);
  ball(0.08, mat("#d3bb7e", 0.35, 0.65), 0.55, 1.7, -d / 2 - 0.37, g);
  riverBox(1.3, 3, 1.5, mat("#98755d"), w * 0.27, h + rise * 0.45, 1, g);
  riverBox(1.6, 0.25, 1.8, riverMaterials.stone, w * 0.27, h + rise * 0.45 + 1.6, 1, g);
  const fascia = signCanvas(label, index % 2 ? "#405b51" : "#745547", "#f4e5bd");
  riverBox(w * 0.8, 0.95, 0.16, fascia, 0, 4.82, -d / 2 - 0.66, g);
  if (index % 3 === 0) {
    const awning = riverBox(
      w * 0.83,
      0.17,
      2.5,
      mat(index % 2 ? "#80987a" : "#b26d52"),
      0,
      4.3,
      -d / 2 - 1.3,
      g,
    );
    awning.rotation.x = 0.14;
  }
  for (const xx of [-w * 0.38, w * 0.38]) {
    riverBox(2.1, 0.4, 0.52, riverMaterials.wood, xx, 1.0, -d / 2 - 0.8, g);
    for (let j = 0; j < 5; j++)
      ball(0.21, mat(j % 2 ? "#8caa68" : "#b87b76"), xx - 0.8 + j * 0.4, 1.34, -d / 2 - 0.8, g);
  }
  const b = { x, z, rotation, w, d, h, rise, base, name: label, group: g };
  riverBuildings.push(b);
  const sideways = Math.abs(Math.sin(rotation)) > 0.5;
  riverCollider(
    x,
    z,
    sideways ? d + 0.7 : w + 0.9,
    sideways ? w + 0.9 : d + 0.7,
    base,
    base + h - 0.05,
    label,
  );
  const world = (lx, ly, lz) =>
    new THREE.Vector3(lx, ly, lz)
      .applyAxisAngle(new THREE.Vector3(0, 1, 0), rotation)
      .add(new THREE.Vector3(x, base, z));
  const ridges = [world(-w * 0.48, h + rise + 0.22, 0), world(w * 0.48, h + rise + 0.22, 0)];
  addRoute("Bellwether roof · " + label, ridges, { kind: "roof" });
  const pipeBase = world(w / 2 + 0.65, 0.24, -d / 2 - 0.65),
    pipeTop = world(w / 2 + 0.65, h + 0.32, -d / 2 - 0.65);
  span(pipeBase, pipeTop, 0.12, 0.12, riverMaterials.copper, riverDistrictGroup);
  addRoute("Bellwether downspout · " + label, [pipeBase, pipeTop], { kind: "trunk", surfaceRadius: 0.14 });
  addRoute(
    "Bellwether gutter to ridge · " + label,
    [pipeTop, world(w / 2 + 0.65, h + rise + 0.28, 0), ridges[1]],
    { kind: "roof" },
  );
  batchTreeBranches(g);
  return b;
}
function makeClockTower() {
  const x = 1051,
    z = 35,
    base = 8,
    g = new THREE.Group();
  g.position.set(x, base, z);
  riverDistrictGroup.add(g);
  riverBox(13, 1.1, 13, riverMaterials.stone, 0, 0.55, 0, g);
  riverBox(9, 29, 9, riverMaterials.stoneLight, 0, 14.5, 0, g);
  for (const y of [2, 14, 24, 28]) riverBox(10, 0.6, 10, riverMaterials.stone, 0, y, 0, g);
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 256;
  const c = canvas.getContext("2d");
  c.fillStyle = "#e3d7af";
  c.fillRect(0, 0, 256, 256);
  c.strokeStyle = "#3f493e";
  c.lineWidth = 9;
  c.beginPath();
  c.arc(128, 128, 112, 0, PI * 2);
  c.stroke();
  for (let i = 0; i < 12; i++) {
    const a = (i * PI) / 6;
    c.beginPath();
    c.moveTo(128 + Math.sin(a) * 89, 128 - Math.cos(a) * 89);
    c.lineTo(128 + Math.sin(a) * 103, 128 - Math.cos(a) * 103);
    c.stroke();
  }
  c.lineCap = "round";
  c.lineWidth = 8;
  c.beginPath();
  c.moveTo(128, 128);
  c.lineTo(164, 88);
  c.moveTo(128, 128);
  c.lineTo(74, 113);
  c.stroke();
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  const m = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.8 });
  for (const side of [-1, 1]) {
    riverBox(3.6, 3.6, 0.08, m, 0, 24, side * 4.55, g);
    riverBox(0.08, 3.6, 3.6, m, side * 4.55, 24, 0, g);
  }
  const roof = mesh(new THREE.ConeGeometry(8, 8, 4), riverMaterials.roof, 0, 33, 0, g);
  roof.rotation.y = PI / 4;
  cyl(0.13, 0.2, 3.4, riverMaterials.iron, 0, 38.4, 0, g, 6);
  riverCollider(x, z, 9, 9, 8, 37, "market clocktower");
  riverPlatforms.push({
    x,
    z,
    w: 11.3,
    d: 11.3,
    height: (px, pz) => 37 + 8 * Math.max(0, 1 - Math.max(Math.abs(px - x), Math.abs(pz - z)) / 5.66),
  });
}
function marketStall(x, z, index) {
  const g = new THREE.Group();
  g.position.set(x, 8, z);
  riverDistrictGroup.add(g);
  const cloth = mat(index % 2 ? "#879e76" : "#b7785d");
  riverBox(5, 1.2, 2.8, riverMaterials.oak, 0, 0.6, 0, g);
  for (const xx of [-2.6, 2.6])
    for (const zz of [-1.5, 1.5]) cyl(0.1, 0.1, 3.8, riverMaterials.wood, xx, 1.9, zz, g, 6);
  for (let i = 0; i < 7; i++)
    riverBox(0.78, 0.16, 3.6, i % 2 ? cloth : mat("#dfd1a8"), -2.35 + i * 0.78, 3.85, 0, g);
  for (let i = 0; i < 12; i++)
    ball(
      0.23,
      mat(["#b8773c", "#a8b066", "#ba6050"][i % 3]),
      -2 + (i % 6) * 0.72,
      1.46,
      -0.5 + Math.floor(i / 6),
      g,
    );
  riverCollider(x, z, 5, 2.8, 8, 9.3, "market stall");
}
function makeMooredBoat(x, z, index) {
  const g = new THREE.Group();
  g.position.set(x, RIVER.waterY + 0.14, z);
  g.rotation.y = index % 2 ? 0.22 : -0.2;
  riverDistrictGroup.add(g);
  const hull = mesh(new THREE.SphereGeometry(1, 14, 8), mat(index % 2 ? "#526e68" : "#856854"), 0, 0, 0, g);
  hull.scale.set(2.6, 0.9, 7.0);
  riverBox(4.1, 0.14, 9, riverMaterials.oak, 0, 0.55, 0, g);
  for (const zz of [-3, 0, 3]) riverBox(4.5, 0.2, 0.65, riverMaterials.wood, 0, 0.85, zz, g);
  cyl(0.11, 0.14, 5, riverMaterials.wood, 0, 3, 0, g, 7);
  riverBox(2.9, 2.1, 0.06, mat("#d3c6a3"), 1.5, 3.4, 0, g);
  riverBoats.push({ group: g, baseY: g.position.y, phase: index * 1.9 });
}
function quayDock(side, z) {
  const x = riverCenter(z) + side * (RIVER.halfWidth - 6),
    y = 8;
  riverBox(14, 0.5, 7, riverMaterials.oak, x, y - 0.25, z);
  riverPlatforms.push({ x, z, w: 14, d: 7, y });
  for (const xx of [-5.5, 5.5])
    for (const zz of [-2.8, 2.8])
      cyl(0.23, 0.3, 7, riverMaterials.wood, x + xx, 4.5, z + zz, riverDistrictGroup, 7);
  for (let i = -6; i <= 6; i++) riverBox(0.035, 0.02, 6.8, riverMaterials.wood, x + i, 8.02, z);
  makeMooredBoat(x - side * 8, z, riverBoats.length);
}
function riverSign(text, x, z, angle = 0) {
  const y = terrainHeight(x, z),
    g = new THREE.Group();
  g.position.set(x, y, z);
  g.rotation.y = angle;
  riverDistrictGroup.add(g);
  cyl(0.12, 0.16, 3.2, riverMaterials.wood, 0, 1.6, 0, g);
  riverBox(8, 1.3, 0.2, signCanvas(text, "#304c44", "#f6e9bd"), 0, 3.1, 0, g);
}
function makeRiverTown() {
  const labels = [
    "THE OLD ANCHOR",
    "QUAYSIDE BOOKS",
    "WILLOW BAKERY",
    "FERRY & FINCH",
    "COPPER KETTLE",
    "RIVER APOTHECARY",
    "THE LANTERN",
    "BRIDGE HOUSE",
    "TIDE & TIMBER",
    "THE COBBLER",
    "WREN COTTAGE",
    "THE TEA ROOM",
  ];
  const leftZ = [-162, -141, -120, -99, 63, 84, 105, 126, 147, 168];
  leftZ.forEach((z, i) => makeQuayBuilding(758, z, -PI / 2, i, labels[i]));
  const rightZ = [-166, -144, -122, -100, 62, 84, 106, 128, 150, 172, 194, 216];
  rightZ.forEach((z, i) =>
    makeQuayBuilding(950 + (i % 3) * 2, z, PI / 2, i + 2, labels[(i + 3) % labels.length]),
  );
  for (const [i, z] of [-164, -118, -72, 91, 137, 183, 229, 275].entries())
    makeQuayBuilding(1008 + (i % 2) * 24, z, i % 2 ? PI : 0, i + 6, labels[(i + 7) % labels.length]);
  groundPatch(1075, 1149, 82, 425, M.grass, () => 8.01, 8, 22);
  groundPatch(705, 737, 208, 425, M.grass, (x, z) => terrainHeight(x, z) + 0.015, 5, 20);
  makeClockTower();
  for (const [i, x, z] of [
    [0, 996, -23],
    [1, 1010, -23],
    [2, 1024, -23],
    [3, 994, 42],
    [4, 1007, 42],
  ])
    marketStall(x, z, i);
  // Open square, planters, benches and hanging lines tie the waterfront together.
  for (const x of [978, 1010, 1092])
    for (const z of [-40, 68]) {
      riverLamp(x, z, 8);
      riverBox(3.6, 0.45, 1.3, riverMaterials.oak, x + 5, 8.6, z);
      for (const xx of [x + 3.5, x + 6.5]) riverBox(0.17, 0.7, 1.3, riverMaterials.iron, xx, 8.32, z);
    }
  for (const [x, z] of [
    [715, -28],
    [715, 43],
    [1004, 79],
    [1108, 52],
    [1094, 192],
    [1015, 370],
  ]) {
    makeTree({
      name: "QUAY WILLOW",
      x,
      z,
      seed: Math.round(x + z),
      h: 19,
      crown: 9,
      color: ["#769377", "#95a580", "#586f5b"],
      branches: 4,
      leafCount: 850,
    });
  }
  for (const side of [-1, 1])
    for (let z = -180; z < 350; z += 40) {
      const edge = riverCenter(z) + side * (RIVER.halfWidth + 7),
        other = edge + side * 23;
      const cable = [v(edge, 14, z), v((edge + other) / 2, 12.6, z), v(other, 15, z)];
      riverLine(cable, riverMaterials.iron, 0.045, 16);
      addRoute("Bellwether bunting line", cable, { kind: "wire" });
      for (let i = 1; i < 8; i++) {
        const x = THREE.MathUtils.lerp(edge, other, i / 8),
          h = 14 - Math.sin((i / 8) * PI) * 1.5 + i / 8;
        const flag = riverBox(0.72, 0.92, 0.05, mat(i % 2 ? "#b16c58" : "#879a75"), x, h - 0.6, z);
        riverBanners.push({ mesh: flag, phase: i + z });
      }
    }
  quayDock(-1, 208);
  quayDock(1, -124);
  quayDock(1, 290);
  riverSign("BELLWETHER QUAY →", 650, 25, -0.15);
  riverSign("WILLOW RIVER", 780, 38, PI / 2);
  riverSign("OLD TOWN MARKET →", 974, 20, PI / 2);
  // Low-detail waterside figures add life without expanding the city's combat
  // and emergency registries. They are explicitly ambient townspeople.
  for (let i = 0; i < 8; i++) {
    const x = i < 4 ? 778 : 926,
      z = -150 + (i % 4) * 105,
      g = new THREE.Group();
    g.position.set(x, 8, z);
    riverDistrictGroup.add(g);
    const coat = mat(["#927a60", "#647e78", "#a57964", "#747a5f"][i % 4]),
      skin = mat("#c1a285");
    riverBox(0.6, 1.0, 0.34, coat, 0, 1.05, 0, g);
    ball(0.25, skin, 0, 1.83, 0, g);
    for (const xx of [-0.17, 0.17]) cyl(0.09, 0.11, 0.65, riverMaterials.wood, xx, 0.33, 0, g, 6);
    riverWalkers.push({ group: g, x, z, phase: i * 1.3 });
  }
}
function recoverRiverFall() {
  if (
    player.inHospital ||
    player.inSewer ||
    player.inDuct ||
    player.rail ||
    !insideRiverWater(player.pos.x, player.pos.z) ||
    player.pos.y > RIVER.waterY + 0.45
  )
    return false;
  const side = player.pos.x < riverCenter(player.pos.z) ? -1 : 1,
    z = THREE.MathUtils.clamp(player.pos.z, -225, 425);
  player.pos.set(riverCenter(z) + side * (RIVER.halfWidth + 5), RIVER.bankY + 0.18, z);
  player.vel.set(0, 0, 0);
  player.grounded = true;
  player.committedAirborne = false;
  player.cameraCommit = 0;
  player.attackWindow = 0;
  cameraHardCut = true;
  if (riverVisuals.rescueCooldown <= 0) {
    flash("SPLASH! You scramble back onto the quay.", 3);
    fx(180, 0.18, "triangle", 0.035);
    riverVisuals.rescueCooldown = 2;
  }
  return true;
}
function updateRiverDistrict(dt) {
  riverVisuals.elapsed += dt;
  riverVisuals.rescueCooldown = Math.max(0, riverVisuals.rescueCooldown - dt);
  const near = player.pos.x > 610 && !player.inHospital && !player.inSewer;
  riverDistrictGroup.visible = near || !playing;
  if (!near && playing) return;
  const t = riverVisuals.elapsed;
  if (riverVisuals.water) riverVisuals.water.material.uniforms.t.value = t;
  for (const b of riverBoats) {
    b.group.position.y = b.baseY + Math.sin(t * 0.7 + b.phase) * 0.12;
    b.group.rotation.z = Math.sin(t * 0.55 + b.phase) * 0.026;
  }
  for (const b of riverBanners) b.mesh.rotation.x = Math.sin(t * 1.8 + b.phase) * 0.1;
  for (const w of riverWalkers) {
    w.group.position.z = w.z + Math.sin(t * 0.095 + w.phase) * 15;
    w.group.rotation.y = Math.cos(t * 0.095 + w.phase) > 0 ? 0 : PI;
  }
  if (inRiverDistrict(player.pos.x, player.pos.z)) {
    $("districtTag").textContent = insideRiverWater(player.pos.x, player.pos.z)
      ? "WILLOW RIVER · STONEBRIDGE"
      : "BELLWETHER QUAY · RIVERSIDE OLD TOWN";
    if (!riverVisuals.visited) {
      riverVisuals.visited = true;
      flash("BELLWETHER QUAY · Explore the bridge, rooftops and riverside market.", 5);
    }
  }
}
function startAtRiver() {
  player.pos.set(780, RIVER.bankY + 0.18, 51);
  player.vel.set(0, 0, 0);
  player.rail = null;
  player.grounded = true;
  squirrel.position.copy(player.pos);
  graphicsRuntime.lastSafe.copy(player.pos);
  yaw = -0.94;
  pitch = 0.3;
  player.yaw = yaw + PI;
  cameraHardCut = true;
  $("playButton").click();
  updateCamera(1);
  flash("BELLWETHER QUAY · The stone bridge is ahead. E grabs pipes and parapets.", 6);
}
makeRiverBanks();
makeRiverWater();
makeRiverBridge();
makeRiverTown();
$("riverPlayButton").addEventListener("click", startAtRiver);

// BELLWETHER GALLERIA — continuous interior, gallery and fountain plaza.
const MALL = Object.freeze({
  x: 1102,
  z: 338,
  w: 78,
  d: 108,
  floor: 8.14,
  gallery: 14.6,
  roof: 22.94,
  front: 284,
  back: 392,
  fountainX: 1102,
  fountainZ: 252,
});
const mallGroup = new THREE.Group();
mallGroup.name = "Bellwether Galleria";
scene.add(mallGroup);
const mallStatic = new THREE.Group(),
  mallRoofGroup = new THREE.Group();
mallGroup.add(mallStatic, mallRoofGroup);
const mallColliders = [],
  mallCameraBoxes = [],
  mallDoors = [],
  mallCoins = [],
  mallShops = [],
  mallJets = [],
  mallRipples = [],
  mallLights = [];
const mallState = {
  elapsed: 0,
  open: 0,
  tosses: [],
  tossCooldown: 0,
  collected: 0,
  visited: false,
  inside: false,
};
const mallMat = {
  stone: mat("#ded2ba", 0.84),
  trim: mat("#f0e4cb", 0.7),
  dark: mat("#344c49", 0.5, 0.2),
  brass: mat("#b69a53", 0.33, 0.65),
  wood: mat("#82634b"),
  ink: mat("#283638"),
  green: mat("#64876b"),
  terracotta: mat("#bc805d"),
  cream: mat("#eadbbd"),
  blue: mat("#477b88"),
  pink: mat("#ba7f87"),
  book: mat("#9c654d"),
  gold: mat("#e9be4e", 0.25, 0.7),
  silver: mat("#d1d7ce", 0.3, 0.65),
};
mallMat.glass = new THREE.MeshPhysicalMaterial({
  color: "#a8d7d4",
  transparent: true,
  opacity: 0.27,
  roughness: 0.16,
  metalness: 0.12,
  side: THREE.DoubleSide,
  depthWrite: false,
});
mallMat.glow = new THREE.MeshStandardMaterial({
  color: "#fff0c8",
  emissive: "#ffda98",
  emissiveIntensity: 1.1,
  roughness: 0.5,
});
mallMat.water = new THREE.MeshPhysicalMaterial({
  color: "#57bcb9",
  transparent: true,
  opacity: 0.43,
  roughness: 0.15,
  metalness: 0.18,
  side: THREE.DoubleSide,
  depthWrite: false,
});
mallMat.spray = new THREE.MeshBasicMaterial({
  color: "#ceffff",
  transparent: true,
  opacity: 0.7,
  depthWrite: false,
});
function mallBox(w, h, d, material, x, y, z, solid = false, parent = mallStatic) {
  const ob = box(w, h, d, material, MALL.x + x, MALL.floor + y, MALL.z + z, parent);
  if (material === mallMat.glass) {
    ob.castShadow = false;
    ob.receiveShadow = false;
  }
  if (solid) {
    const c = {
      x: ob.position.x,
      z: ob.position.z,
      w,
      d,
      y0: ob.position.y - h / 2,
      y1: ob.position.y + h / 2,
    };
    mallColliders.push(c);
    mallCameraBoxes.push(c);
  }
  return ob;
}
function mallCylinder(r1, r2, h, material, x, y, z, parent = mallStatic) {
  return cyl(r1, r2, h, material, MALL.x + x, MALL.floor + y, MALL.z + z, parent, 24);
}
function mallSign(text, x, y, z, width = 12, height = 1.5, angle = 0, bg = "#344c49", parent = mallStatic) {
  const canvas = document.createElement("canvas");
  canvas.height = 128;
  canvas.width = Math.min(4096, Math.max(256, Math.round((width / height) * 128)));
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, canvas.width, 128);
  ctx.fillStyle = "#f9ebc9";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.font = "bold 78px Arial";
  ctx.fillText(text, canvas.width / 2, 68, canvas.width - 36);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  const material = new THREE.MeshStandardMaterial({
    map: tex,
    roughness: 0.7,
    emissive: new THREE.Color(bg),
    emissiveIntensity: 0.16,
    side: THREE.DoubleSide,
  });
  const ob = mesh(
    new THREE.PlaneGeometry(width, height),
    material,
    MALL.x + x,
    MALL.floor + y,
    MALL.z + z,
    parent,
    false,
  );
  ob.rotation.y = angle;
  return ob;
}
function inMall(x, z, pad = 0) {
  return Math.abs(x - MALL.x) < MALL.w / 2 + pad && Math.abs(z - MALL.z) < MALL.d / 2 + pad;
}
function atMall(x = player.pos.x, z = player.pos.z) {
  return inMall(x, z, 24) || Math.hypot(x - MALL.fountainX, z - MALL.fountainZ) < 18;
}
function mallUpperAt(x, z) {
  const dx = Math.abs(x - MALL.x),
    zz = z - MALL.z;
  if (dx <= 38.5 && zz >= -53 && zz <= 53 && (dx >= 13.0 || zz <= -47 || zz >= 48)) return MALL.gallery;
  return null;
}
function mallStairAt(x, z) {
  const dx = Math.abs(x - MALL.x),
    zz = z - MALL.z;
  if (dx < 5.0 || dx > 10.0 || zz < 25 || zz > 48) return null;
  const t = THREE.MathUtils.clamp((zz - 25) / 23, 0, 1);
  return MALL.floor + ((MALL.gallery - MALL.floor) * Math.min(24, Math.floor(t * 24) + 1)) / 24;
}
function mallBaseAt(x, z) {
  if (inMall(x, z)) return MALL.floor;
  if (x >= 1061 && x <= 1145 && z >= 234 && z <= 415) return 8.12;
  if (x >= 1065 && x <= 1073 && z >= 68 && z <= 238) return 8.12;
  return null;
}
function mallSurfaceAt(x, z, referenceY = player.pos.y) {
  let y = mallBaseAt(x, z);
  const upper = mallUpperAt(x, z),
    stair = mallStairAt(x, z);
  if (upper !== null && referenceY >= upper - 0.55) y = Math.max(y ?? -Infinity, upper);
  if (stair !== null && referenceY >= stair - 0.55) y = Math.max(y ?? -Infinity, stair);
  const r = Math.hypot(x - MALL.fountainX, z - MALL.fountainZ);
  if (r < 7.95) {
    const top = r > 7.05 ? MALL.floor + 1.12 : MALL.floor + 0.34;
    if (referenceY >= top - 0.55) y = Math.max(y ?? -Infinity, top);
  }
  return y;
}
function mallRoofAt(x, z) {
  return inMall(x, z) ? MALL.roof + 0.18 : null;
}
function mallDoorBoxes() {
  return mallDoors.map((door) => ({
    x: door.position.x,
    z: MALL.front,
    w: 5.8,
    d: 0.3,
    y0: MALL.floor,
    y1: MALL.floor + 6.4,
  }));
}
function mallBlocked(x, z, y) {
  if (!atMall(x, z)) return false;
  for (const c of [...mallColliders, ...mallDoorBoxes()])
    if (
      y < c.y1 - 0.02 &&
      y + 0.38 > c.y0 &&
      Math.abs(x - c.x) < c.w / 2 + 0.27 &&
      Math.abs(z - c.z) < c.d / 2 + 0.27
    )
      return true;
  const stair = mallStairAt(x, z);
  if (stair !== null && y < stair - 0.5) return true;
  const r = Math.hypot(x - MALL.fountainX, z - MALL.fountainZ);
  if (r < 1.5 && y < MALL.floor + 4.7) return true;
  if (r > 6.8 && r < 8.22 && y < MALL.floor + 0.7) return true;
  return false;
}
function resolveMallLanding(old) {
  if (player.inHospital || player.inSewer || player.rail || player.vel.y > 0 || !atMall()) return false;
  const x = player.pos.x,
    z = player.pos.z,
    candidates = [mallBaseAt(x, z), mallUpperAt(x, z), mallStairAt(x, z)];
  const r = Math.hypot(x - MALL.fountainX, z - MALL.fountainZ);
  if (r < 7.95) candidates.push(MALL.floor + (r > 7.05 ? 1.12 : 0.34));
  let best = null;
  for (const surface of candidates)
    if (surface !== null) {
      const y = surface + 0.18;
      if (old.y >= y - 0.04 && player.pos.y <= y && (best === null || y > best)) best = y;
    }
  if (best === null) return false;
  player.pos.y = best;
  player.vel.y = 0;
  player.grounded = true;
  player.committedAirborne = false;
  return true;
}
function constrainMallCeiling(old) {
  if (!inMall(player.pos.x, player.pos.z) || player.rail || player.vel.y <= 0) return;
  const levels = [MALL.roof - 0.55];
  if (mallUpperAt(player.pos.x, player.pos.z) !== null) levels.push(MALL.gallery - 0.65);
  for (const ceiling of levels)
    if (old.y <= ceiling && player.pos.y > ceiling) {
      player.pos.y = ceiling;
      player.vel.y = 0;
    }
}
// Segment/AABB camera collision also runs after damping, so a corner cannot
// interpolate the camera through a shop wall or through the gallery floor.
function constrainMallCamera(origin, end) {
  if (!atMall(origin.x, origin.z)) return end;
  const direction = end.clone().sub(origin);
  let closest = 1;
  for (const b of [...mallCameraBoxes, ...mallDoorBoxes()]) {
    let lo = 0,
      hi = 1;
    const bounds = [
      [b.x - b.w / 2 - 0.1, b.x + b.w / 2 + 0.1],
      [b.y0 - 0.1, b.y1 + 0.1],
      [b.z - b.d / 2 - 0.1, b.z + b.d / 2 + 0.1],
    ];
    for (let a = 0; a < 3; a++) {
      const key = ["x", "y", "z"][a],
        delta = direction[key],
        p = origin[key];
      if (Math.abs(delta) < 1e-8) {
        if (p < bounds[a][0] || p > bounds[a][1]) {
          hi = -1;
          break;
        }
      } else {
        let t0 = (bounds[a][0] - p) / delta,
          t1 = (bounds[a][1] - p) / delta;
        if (t0 > t1) [t0, t1] = [t1, t0];
        lo = Math.max(lo, t0);
        hi = Math.min(hi, t1);
      }
    }
    if (lo <= hi && hi >= 0 && lo > 0) closest = Math.min(closest, Math.max(0.08, lo - 0.035));
  }
  return origin.clone().addScaledVector(direction, closest);
}
function mallPlanter(x, z, y = 0, size = 1.5) {
  mallBox(size * 2, 0.95, size * 2, mallMat.stone, x, y + 0.475, z, true);
  mallBox(size * 1.8, 0.1, size * 1.8, mallMat.ink, x, y + 0.95, z);
  for (let i = 0; i < 7; i++) {
    const a = i * 2.4;
    const leaf = ball(
      0.65,
      mallMat.green,
      MALL.x + x + Math.cos(a) * size * 0.6,
      MALL.floor + y + 1.35 + (i % 3) * 0.22,
      MALL.z + z + Math.sin(a) * size * 0.6,
      mallStatic,
    );
    leaf.scale.set(0.6, 1.7, 0.65);
    leaf.rotation.z = Math.cos(a) * 0.55;
  }
}
function mallBench(x, z, angle = 0, y = 0) {
  const g = new THREE.Group();
  g.position.set(MALL.x + x, MALL.floor + y, MALL.z + z);
  g.rotation.y = angle;
  mallStatic.add(g);
  for (let i = 0; i < 4; i++) box(4, 0.13, 0.21, mallMat.wood, 0, 0.72, -0.36 + i * 0.24, g);
  box(4, 0.55, 0.16, mallMat.wood, 0, 1.05, 0.48, g);
  for (const xx of [-1.5, 1.5]) box(0.15, 0.68, 0.85, mallMat.dark, xx, 0.34, 0, g);
  const c = {
    x: g.position.x,
    z: g.position.z,
    w: angle ? 1.15 : 4.2,
    d: angle ? 4.2 : 1.15,
    y0: MALL.floor + y,
    y1: MALL.floor + y + 1.35,
  };
  mallColliders.push(c);
  mallCameraBoxes.push(c);
  batchTreeBranches(g);
}
function mallCoin(x, y, z, gold = false) {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  mallGroup.add(g);
  const m = gold ? mallMat.gold : mallMat.brass;
  const face = mesh(
    sharedGeometry("mallCoin", () => new THREE.CylinderGeometry(0.29, 0.29, 0.075, 20)),
    m,
    0,
    0,
    0,
    g,
  );
  face.rotation.x = PI / 2;
  const center = mesh(
    sharedGeometry("mallCoinInset", () => new THREE.TorusGeometry(0.2, 0.022, 6, 18)),
    mallMat.trim,
    0,
    0,
    0.046,
    g,
    false,
  );
  mallCoins.push({ group: g, baseY: y, gold, found: false, phase: mallCoins.length * 0.9 });
  return g;
}
function makeMallShop(side, index, z, name, color) {
  const cx = side * 26,
    front = side * 13;
  mallShops.push({ name, x: MALL.x + cx, z: MALL.z + z, side, index });
  const accent = mat(color);
  // Walk-in opening in the storefront; glass occupies the two flanking bays.
  for (const dz of [-9.5, 9.5]) mallBox(0.18, 4.8, 10, mallMat.glass, front, 2.4, z + dz, true);
  mallBox(0.65, 1.25, 28, accent, front, 5.1, z);
  mallSign(name, front - side * 0.39, 5.15, z, 24, 1.0, (-side * PI) / 2, color);
  mallBox(24, 0.04, 27, accent, cx, 0.025, z);
  mallBox(20, 0.12, 0.25, mallMat.glow, cx, 5.9, z - 12.3);
  const type = index + (side > 0 ? 3 : 0);
  if (type === 0) {
    // Bookshop: low reading tables and five stocked bookcases.
    for (const dz of [-10, -5, 0, 5, 10]) {
      const xx = side * 35;
      mallBox(2.2, 3.5, 3.5, mallMat.wood, xx, 1.75, z + dz, true);
      for (let row = 0; row < 3; row++)
        for (let j = 0; j < 6; j++)
          mallBox(
            0.3,
            0.72,
            0.34,
            [mallMat.cream, mallMat.book, mallMat.green, mallMat.blue][(j + row) % 4],
            xx - side * 1.25,
            0.65 + row * 0.95,
            z + dz - 1.25 + j * 0.49,
          );
    }
    mallBox(6, 0.3, 3.8, mallMat.wood, side * 23, 1.0, z, true);
    mallBench(side * 20, z + 7, PI / 2);
  } else if (type === 1) {
    // Arcade cabinets with individual glowing screens.
    for (let j = 0; j < 7; j++) {
      const xx = side * (j < 4 ? 34 : 23),
        zz = z - 9 + (j % 4) * 5.4;
      mallBox(2.1, 2.1, 1.75, mallMat.dark, xx, 1.05, zz, true);
      mallBox(2.2, 1.15, 0.3, accent, xx, 2.55, zz + 0.1);
      const screen = new THREE.MeshStandardMaterial({
        color: ["#49c2c0", "#dfad64", "#bc8abd"][j % 3],
        emissive: ["#247c86", "#b57e32", "#753b8d"][j % 3],
        emissiveIntensity: 0.75,
        roughness: 0.3,
      });
      mallBox(1.65, 0.88, 0.06, screen, xx, 2.55, zz - 1.02);
      mallBox(2.15, 0.13, 0.7, mallMat.ink, xx, 1.95, zz - 0.65);
      for (let k = 0; k < 3; k++)
        mallCylinder(0.09, 0.09, 0.08, mallMat.gold, xx - 0.5 + k * 0.35, 2.06, zz - 0.7);
    }
  } else if (type === 2) {
    // Outfitters, hanging rails and display mannequins.
    for (const dz of [-8, 8]) {
      mallBox(12, 0.12, 0.12, mallMat.brass, cx, 2.8, z + dz);
      for (const xx of [-5.5, 5.5]) mallBox(0.12, 2.8, 0.12, mallMat.brass, cx + xx, 1.4, z + dz, true);
      for (let j = 0; j < 9; j++)
        mallBox(
          0.9,
          1.4,
          0.35,
          [mallMat.blue, mallMat.cream, mallMat.pink][j % 3],
          cx - 4.8 + j * 1.2,
          2.0,
          z + dz,
        );
    }
    mallBox(4, 0.9, 4, mallMat.trim, cx, 0.45, z, true);
    for (const dx of [-1, 1]) {
      mallCylinder(0.3, 0.35, 0.75, mallMat.wood, cx + dx, 1.3, z);
      ball(0.32, mallMat.cream, MALL.x + cx + dx, MALL.floor + 2.4, MALL.z + z, mallStatic);
      mallBox(0.8, 0.85, 0.4, mallMat.green, cx + dx, 1.94, z);
    }
  } else if (type === 3) {
    // Conservatory shop.
    for (const dx of [-7, 2]) for (const dz of [-9, 0, 9]) mallPlanter(cx + dx, z + dz, 0, 1.2);
    mallSign("PLANTS / POTS / LITTLE JUNGLES", side * 37, 3.9, z, 19, 0.8, (-side * PI) / 2, color);
  } else if (type === 4) {
    // Record shop: browseable crates and listening table.
    for (const dz of [-8, 0, 8]) {
      mallBox(14, 1.0, 2.6, mallMat.wood, cx, 0.5, z + dz, true);
      for (let j = 0; j < 12; j++)
        mallBox(
          0.08,
          0.75,
          1.1,
          [mallMat.ink, mallMat.book, mallMat.blue][j % 3],
          cx - 6 + j * 1.1,
          1.32,
          z + dz,
        );
    }
    for (let j = 0; j < 5; j++) {
      const disc = mallCylinder(0.72, 0.72, 0.08, mallMat.ink, side * 37, 3.8, z - 9 + j * 4.5);
      disc.rotation.z = PI / 2;
    }
  } else {
    // Cafe counter, clear center aisle and tables.
    mallBox(3, 1.5, 22, mallMat.wood, side * 35, 0.75, z, true);
    mallBox(3.4, 0.12, 22.5, mallMat.trim, side * 35, 1.55, z);
    mallSign("COFFEE / PASTRIES", side * 37.2, 4, z, 16, 1, (-side * PI) / 2, color);
    for (const dz of [-8, 2, 9]) {
      mallCylinder(1.4, 1.4, 0.16, mallMat.wood, side * 23, 1.3, z + dz);
      mallBox(0.35, 1.2, 0.35, mallMat.dark, side * 23, 0.6, z + dz, true);
      for (const dx of [-2.3, 2.3]) mallBox(0.9, 0.6, 0.9, accent, side * 23 + dx, 0.3, z + dz, true);
      mallCylinder(0.13, 0.13, 0.25, mallMat.cream, side * 23, 1.5, z + dz);
    }
  }
  for (const dz of [-10, 9]) mallCoin(MALL.x + side * 17.5, MALL.floor + 0.55, MALL.z + z + dz);
}
function makeMallBuilding() {
  const tile = document.createElement("canvas");
  tile.width = tile.height = 256;
  const c = tile.getContext("2d");
  c.fillStyle = "#e3d8be";
  c.fillRect(0, 0, 256, 256);
  c.fillStyle = "#c4ccbf";
  c.fillRect(0, 0, 128, 128);
  c.fillRect(128, 128, 128, 128);
  c.strokeStyle = "#a2a797";
  c.lineWidth = 2;
  for (const n of [1, 128, 255]) {
    c.beginPath();
    c.moveTo(n, 0);
    c.lineTo(n, 256);
    c.moveTo(0, n);
    c.lineTo(256, n);
    c.stroke();
  }
  const texture = new THREE.CanvasTexture(tile);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(12, 16);
  const floorMat = new THREE.MeshStandardMaterial({ map: texture, roughness: 0.32, metalness: 0.12 });
  mallBox(78, 0.3, 108, floorMat, 0, -0.15, 0);
  // Solid walls are only the perimeter and shop partitions, never a filled box.
  for (const side of [-1, 1]) {
    mallBox(1, 14.6, 108, mallMat.stone, side * 38.5, 7.3, 0, true);
    mallBox(32.5, 14.6, 1, mallMat.stone, side * 22.75, 7.3, -53.5, true);
    for (const zz of [-48, -16, 16, 48]) mallBox(25, 6.35, 0.55, mallMat.trim, side * 26, 3.175, zz, true);
    // Exterior window bays, bronze frames and vertical fluting.
    for (const xx of [side * 15, side * 27, side * 35]) {
      mallBox(5.8, 7, 0.14, mallMat.blue, xx, 5.2, -54.07);
      for (const dx of [-3, 3]) mallBox(0.15, 7.6, 0.23, mallMat.brass, xx + dx, 5.2, -54.15);
      mallBox(5.8, 0.16, 0.23, mallMat.brass, xx, 5.2, -54.15);
    }
    for (const xx of [side * 7, side * 20, side * 38]) mallBox(0.6, 14.4, 0.85, mallMat.trim, xx, 7.2, -54.2);
    for (const zz of [-40, -20, 0, 20, 40]) {
      mallBox(0.1, 4.6, 10, mallMat.blue, side * 39.04, 9.2, zz);
      for (const dz of [-5.1, 0, 5.1]) mallBox(0.15, 5.0, 0.15, mallMat.brass, side * 39.12, 9.2, zz + dz);
      for (const yy of [6.8, 11.6]) mallBox(0.15, 0.15, 10.4, mallMat.brass, side * 39.12, yy, zz);
    }
    mallBox(0.55, 0.38, 108, mallMat.dark, side * 38.9, 14.35, 0);
  }
  mallBox(78, 14.6, 1, mallMat.stone, 0, 7.3, 53.5, true);
  mallBox(13, 7.8, 1, mallMat.trim, 0, 10.7, -53.5, true);
  mallSign("BELLWETHER GALLERIA", 0, 12.3, -54.57, 58, 2.1, PI);
  // Automatic doors are kept separate from static batching and collision follows them.
  for (const side of [-1, 1]) {
    const door = mallBox(5.8, 6.4, 0.19, mallMat.glass, side * 2.9, 3.2, -54, false, mallGroup);
    door.userData.side = side;
    mallDoors.push(door);
    const frame = box(0.12, 6.4, 0.2, mallMat.brass, 0, 0, 0, door);
    frame.position.x = side * 2.8;
  }
  mallBox(16, 0.3, 7, mallMat.dark, 0, 6.9, -56.5);
  mallBox(14, 0.08, 6, mallMat.glass, 0, 7.1, -56.5);
  mallSign("COME ON IN", 0, 5.8, -54.24, 8, 0.7, PI);
  // Upper gallery above the stores, with bridges at both ends of the atrium.
  for (const side of [-1, 1]) {
    mallBox(25.5, 0.38, 106, floorMat, side * 25.75, MALL.gallery - MALL.floor - 0.19, 0);
    mallCameraBoxes.push({
      x: MALL.x + side * 25.75,
      z: MALL.z,
      w: 25.5,
      d: 106,
      y0: MALL.gallery - 0.38,
      y1: MALL.gallery,
    });
    mallBox(0.16, 1.15, 95, mallMat.glass, side * 13.05, MALL.gallery - MALL.floor + 0.575, 0.5, true);
    mallBox(0.13, 0.13, 95, mallMat.brass, side * 13.05, MALL.gallery - MALL.floor + 1.2, 0.5);
    for (let zz = -46; zz <= 48; zz += 8)
      mallBox(0.12, 1.25, 0.12, mallMat.brass, side * 13.05, MALL.gallery - MALL.floor + 0.625, zz);
  }
  for (const zz of [-50, 50.5]) {
    mallBox(26, 0.38, zz < 0 ? 6 : 5, floorMat, 0, MALL.gallery - MALL.floor - 0.19, zz);
    mallCameraBoxes.push({
      x: MALL.x,
      z: MALL.z + zz,
      w: 26,
      d: zz < 0 ? 6 : 5,
      y0: MALL.gallery - 0.38,
      y1: MALL.gallery,
    });
  }
  mallBox(26, 1.15, 0.16, mallMat.glass, 0, MALL.gallery - MALL.floor + 0.575, -47, true);
  for (const [xx, w] of [
    [0, 9.3],
    [-11.7, 2.6],
    [11.7, 2.6],
  ])
    mallBox(w, 1.15, 0.16, mallMat.glass, xx, MALL.gallery - MALL.floor + 0.575, 48, true);
  for (const side of [-1, 1]) {
    for (let i = 0; i < 24; i++) {
      const h = ((MALL.gallery - MALL.floor) * (i + 1)) / 24,
        zz = 25 + ((i + 0.5) * 23) / 24;
      mallBox(5, h, 23 / 24 + 0.01, mallMat.dark, side * 7.5, h / 2, zz);
      mallCameraBoxes.push({
        x: MALL.x + side * 7.5,
        z: MALL.z + zz,
        w: 5,
        d: 23 / 24 + 0.01,
        y0: MALL.floor,
        y1: MALL.floor + h,
      });
      mallBox(4.9, 0.025, 0.09, mallMat.brass, side * 7.5, h + 0.014, zz - 23 / 48 + 0.08);
    }
    for (const edge of [5, 10]) {
      const path = [
        v(MALL.x + side * edge, MALL.floor + 1.2, MALL.z + 25),
        v(MALL.x + side * edge, MALL.gallery + 1.2, MALL.z + 48),
      ];
      const rail = linePath(path, mallMat.brass, 0.07, 12).obj;
      mallStatic.add(rail);
    }
    mallSign("GALLERY UPSTAIRS", side * 7.5, 1.8, 24.7, 5, 0.55, PI);
    for (const zz of [-35, -5, 27]) {
      mallBench(side * 29, zz, 0, MALL.gallery - MALL.floor);
      mallPlanter(side * 19, zz + 6, MALL.gallery - MALL.floor, 1.2);
    }
    for (const zz of [-38, -10, 18, 44]) mallCoin(MALL.x + side * 18, MALL.gallery + 0.55, MALL.z + zz);
  }
  mallCoin(MALL.x, MALL.gallery + 0.6, MALL.z - 50, true);
  for (let z = -42; z <= 42; z += 12) {
    mallBox(78, 0.22, 0.2, mallMat.dark, 0, 14.5, z, false, mallRoofGroup);
    mallBox(25.3, 0.12, 11.5, mallMat.glass, 0, 14.63, z, false, mallRoofGroup);
  }
  for (const side of [-1, 1])
    mallBox(25.5, 0.28, 108, mallMat.stone, side * 25.75, 14.66, 0, false, mallRoofGroup);
  mallCameraBoxes.push({ x: MALL.x, z: MALL.z, w: 78, d: 108, y0: MALL.roof - 0.5, y1: MALL.roof });
  for (const x of [-12, 12])
    for (const z of [-44, -12, 20, 44]) {
      mallBox(0.65, 14.4, 0.65, mallMat.trim, x, 7.2, z, true);
      mallBox(0.85, 0.18, 0.85, mallMat.brass, x, 6.5, z);
    }
  for (const z of [-35, -3, 29]) {
    mallBox(11, 0.13, 2.2, mallMat.glow, 0, 12.9, z);
    for (const x of [-4.5, 4.5]) mallBox(0.04, 1.5, 0.04, mallMat.brass, x, 13.7, z);
  }
  const names = [
    ["WILLOW BOOKS", "#6d8265"],
    ["PIXEL PALACE", "#68577c"],
    ["ACORN OUTFITTERS", "#986f53"],
    ["LITTLE JUNGLE", "#597e70"],
    ["GROOVE RECORDS", "#527a85"],
    ["COPPER CUP CAFE", "#a37254"],
  ];
  for (const side of [-1, 1])
    for (let i = 0; i < 3; i++) {
      const n = names[i + (side > 0 ? 3 : 0)];
      makeMallShop(side, i, -32 + i * 32, n[0], n[1]);
    }
  for (const side of [-1, 1]) {
    mallPlanter(side * 8, -41, 0, 1.3);
    mallBench(side * 7, -22, PI / 2);
    mallBench(side * 7, 10, PI / 2);
  }
  mallSign("BELLWETHER / SIX SHOPS / UPPER GALLERY", 0, 6.4, 51.8, 27, 1.1, PI);
  for (const [x, z] of [
    [-25, -30],
    [25, -30],
    [-25, 30],
    [25, 30],
  ]) {
    const light = new THREE.PointLight("#ffdfa9", 38, 46, 2);
    light.position.set(MALL.x + x, MALL.floor + 5.4, MALL.z + z);
    light.castShadow = false;
    mallGroup.add(light);
    mallLights.push(light);
  }
  // Climbable outside downspouts connect to the mall roof without entering walls.
  for (const side of [-1, 1]) {
    const a = v(MALL.x + side * 39.6, MALL.floor + 0.25, MALL.front + 4),
      b = v(a.x, MALL.roof + 0.25, a.z);
    span(a, b, 0.12, 0.12, mallMat.brass, mallStatic);
    addRoute("Galleria downspout", [a, b], { kind: "trunk", surfaceRadius: 0.15 });
    addRoute("Galleria rooftop", [b, v(a.x, MALL.roof + 0.25, MALL.back - 4)], { kind: "roof" });
  }
}
function makeCoinFountain() {
  const x = MALL.fountainX,
    z = MALL.fountainZ,
    y = MALL.floor;
  function lathe(points, material, yy) {
    const ob = mesh(
      new THREE.LatheGeometry(
        points.map((p) => new THREE.Vector2(...p)),
        64,
      ),
      material,
      x,
      y + yy,
      z,
      mallStatic,
    );
    return ob;
  }
  lathe(
    [
      [0, 0],
      [7.5, 0],
      [7.95, 0.25],
      [7.95, 0.9],
      [7.7, 1.12],
      [7.1, 1.12],
      [7.05, 0.85],
      [7.05, 0.34],
      [0, 0.34],
    ],
    mallMat.stone,
    0,
  );
  lathe(
    [
      [0.5, 0],
      [1.4, 0.1],
      [1.25, 0.8],
      [0.6, 1.0],
      [0.38, 3.9],
      [0.62, 4.1],
    ],
    mallMat.brass,
    0.34,
  );
  lathe(
    [
      [0, 0],
      [2.7, 0],
      [2.9, 0.25],
      [2.7, 0.6],
      [2.5, 0.6],
      [2.3, 0.2],
      [0, 0.2],
    ],
    mallMat.trim,
    2.55,
  );
  lathe(
    [
      [0, 0],
      [1.55, 0],
      [1.7, 0.15],
      [1.5, 0.48],
      [1.3, 0.48],
      [1.2, 0.2],
      [0, 0.2],
    ],
    mallMat.trim,
    4.4,
  );
  const water = mesh(new THREE.CircleGeometry(7.05, 64), mallMat.water, x, y + 0.64, z, mallGroup, false);
  water.rotation.x = -PI / 2;
  for (const [r, yy] of [
    [2.48, 3.03],
    [1.28, 4.78],
  ]) {
    const disk = mesh(new THREE.CircleGeometry(r, 48), mallMat.water, x, y + yy, z, mallGroup, false);
    disk.rotation.x = -PI / 2;
  }
  const randomCoin = rng(5300811),
    dummy = new THREE.Object3D();
  for (const material of [mallMat.gold, mallMat.silver]) {
    const coins = new THREE.InstancedMesh(
      sharedGeometry("fountainCoins", () => new THREE.CylinderGeometry(0.105, 0.105, 0.025, 12)),
      material,
      52,
    );
    for (let i = 0; i < 52; i++) {
      const a = randomCoin() * PI * 2,
        r = 2 + Math.sqrt(randomCoin()) * 4.8;
      dummy.position.set(x + Math.cos(a) * r, y + 0.37, z + Math.sin(a) * r);
      dummy.rotation.set((randomCoin() - 0.5) * 0.16, randomCoin() * PI, 0);
      dummy.updateMatrix();
      coins.setMatrixAt(i, dummy.matrix);
    }
    coins.computeBoundingSphere();
    mallGroup.add(coins);
  }
  for (let i = 0; i < 12; i++) {
    const a = (i * PI) / 6,
      curve = new THREE.QuadraticBezierCurve3(
        v(x + Math.cos(a) * 0.7, y + 4.87, z + Math.sin(a) * 0.7),
        v(x + Math.cos(a) * 3.7, y + 6.4, z + Math.sin(a) * 3.7),
        v(x + Math.cos(a) * 5.5, y + 0.65, z + Math.sin(a) * 5.5),
      );
    const stream = mesh(
      new THREE.TubeGeometry(curve, 24, 0.034, 5, false),
      mallMat.spray,
      0,
      0,
      0,
      mallGroup,
      false,
    );
    mallJets.push(curve);
  }
  const droplets = new THREE.InstancedMesh(new THREE.SphereGeometry(0.065, 6, 4), mallMat.spray, 96);
  droplets.frustumCulled = false;
  mallGroup.add(droplets);
  mallState.droplets = droplets;
  mallState.dummy = dummy;
  for (let i = 0; i < 5; i++) {
    const material = new THREE.MeshBasicMaterial({
      color: "#d6ffff",
      transparent: true,
      opacity: 0.3,
      depthWrite: false,
      side: THREE.DoubleSide,
    });
    const ring = mesh(
      new THREE.RingGeometry(0.93, 1, 48),
      material,
      x,
      y + 0.66 + i * 0.001,
      z,
      mallGroup,
      false,
    );
    ring.rotation.x = -PI / 2;
    mallRipples.push(ring);
  }
  for (let i = 0; i < 48; i++) {
    const a = (i * PI) / 24;
    const tile = box(
      0.68,
      0.045,
      0.28,
      i % 2 ? mallMat.brass : mallMat.blue,
      x + Math.cos(a) * 7.48,
      y + 1.145,
      z + Math.sin(a) * 7.48,
      mallStatic,
    );
    tile.rotation.y = -a + PI / 2;
  }
  mallBox(13.4, 1.8, 0.28, mallMat.trim, 0, 1.2, -96.8, true);
  mallSign("THE WISHING FOUNTAIN", 0, 1.6, -97, 13, 1.0, PI);
  mallSign("E / TOSS 1 SQUIRREL COIN", 0, 0.85, -97.02, 11, 0.55, PI);
  for (const side of [-1, 1]) {
    mallBench(side * 13, -86, (side * PI) / 2);
    mallPlanter(side * 19, -96, 0, 1.5);
    mallPlanter(side * 19, -70, 0, 1.5);
  }
  for (const [dx, dz] of [
    [-10, -8],
    [10, -8],
    [-10, 6],
    [10, 6],
  ])
    mallCoin(x + dx, y + 0.55, z + dz);
}
function makeMallPlaza() {
  const plaza = groundPatch(1061, 1145, 234, 415, mallMat.stone, () => 8.12, 2, 2);
  mallStatic.add(plaza);
  const path = groundPatch(1065, 1073, 68, 238, riverCobble, () => 8.12, 2, 24);
  mallStatic.add(path);
  for (let z = 82; z < 230; z += 28) {
    riverLamp(1071, z, 8.12);
  }
  for (const side of [-1, 1])
    for (const zz of [-100, -65, 64]) {
      const x = side * 33;
      mallCylinder(0.12, 0.18, 4.5, mallMat.dark, x, 2.25, zz);
      mallBox(0.6, 0.8, 0.6, mallMat.glow, x, 4.6, zz);
    }
  riverSign("GALLERIA + FOUNTAIN →", 1069, 70, 0);
  riverSign("GALLERIA ↑", 1069, 206, 0);
  mallSign("SHOPS / FOUNTAIN / GALLERY", -26, 3.0, -104, 24, 1.2, PI);
}
function handleMallInteraction() {
  if (player.inHospital || player.inSewer || player.rail || Math.abs(player.pos.y - MALL.floor) > 2.8)
    return false;
  if (Math.hypot(player.pos.x - MALL.fountainX, player.pos.z - MALL.fountainZ) > 11.5) return false;
  if (mallState.tossCooldown > 0) return true;
  if (squirrelCoins < 1) {
    flash("Find a coin inside the Galleria, then E to make a wish.", 3);
    return true;
  }
  squirrelCoins--;
  refreshPowerUI();
  mallState.tossCooldown = 0.7;
  const g = new THREE.Mesh(
    sharedGeometry("tossCoin", () => new THREE.CylinderGeometry(0.12, 0.12, 0.03, 16)),
    mallMat.gold,
  );
  mallGroup.add(g);
  const from = player.pos.clone().add(v(0, 0.5, 0)),
    angle = mallState.elapsed * 2.4,
    to = v(MALL.fountainX + Math.cos(angle) * 4, MALL.floor + 0.4, MALL.fountainZ + Math.sin(angle) * 4);
  mallState.tosses.push({ mesh: g, from, to, t: 0 });
  flash("One coin, one wish. Listen for the splash.", 2.4);
  fx(740, 0.12, "sine", 0.035);
  return true;
}
function updateMall(dt) {
  const near = atMall() || Math.hypot(player.pos.x - MALL.x, player.pos.z - MALL.z) < 190;
  mallGroup.visible = near || !playing;
  mallLights.forEach((light) => (light.visible = near && RenderConfig.tier !== "performance"));
  if (!near && playing) return;
  mallState.elapsed += dt;
  mallState.tossCooldown = Math.max(0, mallState.tossCooldown - dt);
  const t = mallState.elapsed,
    frontDist = Math.hypot(player.pos.x - MALL.x, player.pos.z - MALL.front);
  const wantOpen = frontDist < 16 && player.pos.y < MALL.floor + 5;
  mallState.open = THREE.MathUtils.lerp(mallState.open, wantOpen ? 1 : 0, 1 - Math.exp(-dt * 5));
  mallDoors.forEach((d) => (d.position.x = MALL.x + d.userData.side * (2.9 + mallState.open * 6.1)));
  mallState.inside = inMall(player.pos.x, player.pos.z) && player.pos.y < MALL.roof - 0.25;
  if (atMall() && !player.inHospital && !player.inSewer) {
    $("districtTag").textContent = mallState.inside
      ? "BELLWETHER GALLERIA · " + (player.pos.y > MALL.gallery - 0.4 ? "UPPER GALLERY" : "SHOPS & ATRIUM")
      : "BELLWETHER GALLERIA · WISHING FOUNTAIN";
    if (!player.focus)
      $("scoutText").innerHTML = mallState.inside
        ? "Explore six shops · coins on both floors<br>Twin stairs at the back lead to the gallery"
        : "Walk through the automatic doors<br>E near the fountain: toss 1 Squirrel Coin";
    if (!mallState.visited) {
      mallState.visited = true;
      flash("BELLWETHER GALLERIA · Six shops, an upper gallery, and a wishing fountain.", 5);
    }
  }
  const dummy = mallState.dummy;
  for (let i = 0; i < 96; i++) {
    const u = (t * 0.68 + i * 0.618) % 1;
    dummy.position.copy(mallJets[i % 12].getPoint(u));
    dummy.scale.setScalar(0.55 + 0.55 * Math.sin(u * PI));
    dummy.updateMatrix();
    mallState.droplets.setMatrixAt(i, dummy.matrix);
  }
  mallState.droplets.instanceMatrix.needsUpdate = true;
  for (let i = 0; i < mallRipples.length; i++) {
    const u = (t * 0.22 + i / mallRipples.length) % 1,
      r = 1.7 + u * 5.0;
    mallRipples[i].scale.setScalar(r);
    mallRipples[i].material.opacity = (1 - u) * 0.26;
  }
  for (const coin of mallCoins) {
    if (coin.found) continue;
    coin.group.rotation.y = t * 1.7 + coin.phase;
    coin.group.position.y = coin.baseY + Math.sin(t * 2 + coin.phase) * 0.09;
    if (playing && !gamePaused && player.alive && player.pos.distanceTo(coin.group.position) < 0.95) {
      coin.found = true;
      coin.group.visible = false;
      mallState.collected++;
      if (coin.gold) goldCoins++;
      else {
        squirrelCoins++;
        totalCoinsEarned++;
      }
      refreshPowerUI();
      fx(coin.gold ? 1040 : 720, 0.08, "sine", 0.025);
      flash(
        coin.gold
          ? "GOLD COIN · You explored the upper gallery!"
          : `Galleria coin ${mallState.collected} / ${mallCoins.length}`,
        1.1,
      );
    }
  }
  for (let i = mallState.tosses.length - 1; i >= 0; i--) {
    const toss = mallState.tosses[i];
    toss.t = Math.min(1, toss.t + dt / 0.9);
    toss.mesh.position.copy(toss.from).lerp(toss.to, toss.t);
    toss.mesh.position.y += Math.sin(toss.t * PI) * 3;
    toss.mesh.rotation.z = toss.t * 16;
    if (toss.t === 1) {
      mallGroup.remove(toss.mesh);
      mallState.tosses.splice(i, 1);
      fx(330, 0.15, "sine", 0.025);
    }
  }
}
function startAtMall() {
  player.pos.set(MALL.x, MALL.floor + 0.18, 238);
  player.vel.set(0, 0, 0);
  player.rail = null;
  player.grounded = true;
  player.inHospital = false;
  player.inSewer = false;
  player.inDuct = false;
  player.committedAirborne = false;
  squirrel.position.copy(player.pos);
  graphicsRuntime.lastSafe.copy(player.pos);
  yaw = PI;
  pitch = 0.22;
  player.yaw = 0;
  cameraHardCut = true;
  $("playButton").click();
  updateMall(1 / 60);
  updateCamera(1);
  flash("BELLWETHER GALLERIA · Circle the fountain and walk into the shops.", 5);
}
makeMallPlaza();
makeMallBuilding();
makeCoinFountain();
batchTreeBranches(mallStatic);
batchTreeBranches(mallRoofGroup);
$("mallPlayButton").addEventListener("click", startAtMall);

// v5.4: orchard trees, branch-mounted nests, birds, silent overflights and traffic.
const livingTown = { elapsed: 0, appleTrees: [], nests: [], birds: [] };
const livingRand = rng(540811);
const lr = (a, b) => a + (b - a) * livingRand();
const appleMaterials = [mat("#bf3e30", 0.58), mat("#d5b54b", 0.6)],
  appleWood = mat("#766047"),
  nestWood = mat("#8b7048");
const appleGeometry = sharedGeometry("orchard-apple", () => {
  const geo = new THREE.SphereGeometry(0.205, 12, 9),
    p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i),
      y = p.getY(i),
      z = p.getZ(i),
      a = Math.atan2(z, x),
      lobe = 1 + 0.045 * Math.cos(a * 5);
    p.setXYZ(i, x * lobe, y * 0.91 - (y > 0.12 ? 0.025 : 0), z * lobe);
  }
  geo.computeVertexNormals();
  return geo;
});
function appleSiteClear(x, z) {
  if (pavementDistance(x, z) < 8 || insideRiverWater(x, z) || inMall(x, z, 14)) return false;
  if (Math.abs(x - HOSP_X) < HOSP_W / 2 + 15 && Math.abs(z - HOSP_Z) < HOSP_D / 2 + 15) return false;
  if (houses.some((h) => Math.abs(x - h.x) < h.w / 2 + 9 && Math.abs(z - h.z) < h.d / 2 + 9)) return false;
  if (
    oldDistrictHomes.some((h) => Math.abs(x - h.x) < h.depth / 2 + 9 && Math.abs(z - h.z) < h.width / 2 + 9)
  )
    return false;
  if (commercialBounds.some((b) => Math.abs(x - b.x) < b.w / 2 + 10 && Math.abs(z - b.z) < b.d / 2 + 10))
    return false;
  if (
    riverBuildings.some((b) => Math.hypot(x - b.x, z - b.z) < 24) ||
    trees.some((t) => Math.hypot(x - t.x, z - t.z) < 15)
  )
    return false;
  if (utilitySupports.some((p) => Math.hypot(x - p.x, z - p.z) < 8)) return false;
  for (const dx of [-3, 0, 3])
    for (const dz of [-3, 0, 3]) if (outdoorBlocked(x + dx, z + dz, terrainHeight(x, z) + 0.18)) return false;
  return true;
}
function makeAppleTree(x, z, index) {
  const base = terrainHeight(x, z),
    H = 8.8 + lr(-0.5, 1.0),
    g = new THREE.Group();
  g.position.set(x, base, z);
  g.name = "Apple tree " + (index + 1);
  scene.add(g);
  const name = "APPLE " + (index + 1),
    trunk = [v(0, 0.15, 0), v(0.15, 2.0, 0.08), v(-0.1, 4.0, 0.13), v(0.08, H * 0.7, 0)];
  for (let i = 0; i < 3; i++)
    span(trunk[i], trunk[i + 1], 0.58 - i * 0.13, 0.45 - i * 0.13, appleWood, g, 10);
  const world = (p) => p.clone().add(v(x, base, z));
  addRoute(name + " trunk", trunk.map(world), { kind: "trunk", surfaceRadius: 0.5, center: v(x, base, z) });
  for (let i = 0; i < 5; i++) {
    const a = i * PI * 0.4;
    span(
      v(Math.cos(a) * 0.2, 0.18, Math.sin(a) * 0.2),
      v(Math.cos(a) * 2.4, 0.01, Math.sin(a) * 2.4),
      0.22,
      0.015,
      appleWood,
      g,
      7,
    );
  }
  const tips = [];
  for (let i = 0; i < 6; i++) {
    const a = (i * PI) / 3 + lr(-0.2, 0.2),
      r = lr(3.7, 5.0),
      start = trunk[i % 2 ? 2 : 1].clone(),
      mid = v(Math.cos(a) * r * 0.5, H * 0.62, Math.sin(a) * r * 0.5),
      tip = v(Math.cos(a) * r, H * lr(0.7, 0.87), Math.sin(a) * r);
    span(start, mid, 0.32, 0.22, appleWood, g, 8);
    span(mid, tip, 0.22, 0.065, appleWood, g, 7);
    addRoute(name + " bough " + (i + 1), [start, mid, tip].map(world), { kind: "branch", visualOffset: 0.3 });
    for (let j = 0; j < 3; j++) {
      const twig = tip.clone().add(v(lr(-1.2, 1.2), lr(0.3, 1.1), lr(-1.2, 1.2)));
      span(tip, twig, 0.07, 0.016, appleWood, g, 5);
      tips.push(twig);
    }
  }
  const dummy = new THREE.Object3D(),
    colors = ["#617f3c", "#829e4d", "#4e7138"];
  for (let k = 0; k < 3; k++) {
    const leaves = new THREE.InstancedMesh(leavesGeometry, leafMaterial(colors[k]), 230);
    leaves.castShadow = true;
    leaves.receiveShadow = true;
    g.add(leaves);
    for (let i = 0; i < 230; i++) {
      const tip = tips[(i * 5 + k) % tips.length],
        angle = lr(0, PI * 2),
        r = Math.sqrt(livingRand()) * 1.7;
      dummy.position.copy(tip).add(v(Math.cos(angle) * r, lr(-0.8, 1.4), Math.sin(angle) * r));
      dummy.rotation.set(lr(-PI, PI), lr(-PI, PI), lr(-PI, PI));
      dummy.scale.set(lr(0.35, 0.7), lr(0.38, 0.7), lr(0.4, 0.75));
      dummy.updateMatrix();
      leaves.setMatrixAt(i, dummy.matrix);
    }
    leaves.computeBoundingSphere();
    canopyAnimated.push({ mesh: leaves, phase: index + k, amplitude: 0.004 });
    canopyShadowCasters.push({ mesh: leaves, x, z, r: 90 });
  }
  const stems = new THREE.InstancedMesh(
    sharedGeometry("apple-stem", () => new THREE.CylinderGeometry(0.018, 0.025, 0.15, 5)),
    appleWood,
    40,
  );
  g.add(stems);
  for (let k = 0; k < 2; k++) {
    const fruit = new THREE.InstancedMesh(appleGeometry, appleMaterials[k], 20);
    fruit.castShadow = true;
    g.add(fruit);
    for (let i = 0; i < 20; i++) {
      const tip = tips[(i * 7 + k) % tips.length],
        p = tip.clone().add(v(lr(-1.0, 1.0), lr(-1.15, -0.45), lr(-1.0, 1.0)));
      dummy.position.copy(p);
      dummy.rotation.set(0, lr(0, PI * 2), lr(-0.12, 0.12));
      dummy.scale.setScalar(lr(0.85, 1.15));
      dummy.updateMatrix();
      fruit.setMatrixAt(i, dummy.matrix);
      dummy.position.y += 0.22;
      dummy.scale.setScalar(1);
      dummy.rotation.set(0, 0, 0.1);
      dummy.updateMatrix();
      stems.setMatrixAt(k * 20 + i, dummy.matrix);
    }
    fruit.computeBoundingSphere();
  }
  stems.computeBoundingSphere();
  for (let i = 0; i < 5; i++) {
    const a = lr(0, PI * 2),
      r = lr(2.2, 4.2),
      px = x + Math.cos(a) * r,
      pz = z + Math.sin(a) * r;
    mesh(appleGeometry, appleMaterials[i % 2], px, outdoorSurfaceAt(px, pz) + 0.2, pz);
  }
  batchTreeBranches(g);
  const meta = { x, z, H, spec: { name, crown: 6 }, root: v(x, base, z), group: g };
  trees.push(meta);
  livingTown.appleTrees.push(meta);
}
function plantAppleTrees() {
  const sectors = [
    [
      [-84, -24],
      [-24, -84],
      [-24, 80],
      [80, 24],
      [-94, 24],
      [24, -94],
      [94, -24],
      [24, 94],
      [-102, 42],
      [42, 103],
      [-110, -45],
      [110, 43],
    ],
    [
      [-85, 352],
      [-58, 382],
      [-28, 399],
      [12, 381],
      [38, 410],
      [-97, 414],
      [-117, 345],
      [86, 402],
      [123, 414],
      [142, 348],
      [-82, 296],
      [-108, 282],
    ],
    [
      [988, -214],
      [1018, -214],
      [1048, -214],
      [1078, -214],
      [1108, -214],
      [1078, -187],
      [1108, -182],
      [1039, 405],
      [1051, 362],
      [733, 373],
    ],
  ];
  for (const candidates of sectors) {
    let count = 0;
    for (const [x, z] of candidates) {
      if (!appleSiteClear(x, z)) continue;
      makeAppleTree(x, z, livingTown.appleTrees.length);
      if (++count === 4) break;
    }
  }
  // Fill any crowded sector with clear positions along the southern orchard.
  for (let x = 982; livingTown.appleTrees.length < 12 && x < 1120; x += 24)
    for (const z of [-226, -192])
      if (livingTown.appleTrees.length < 12 && appleSiteClear(x, z))
        makeAppleTree(x, z, livingTown.appleTrees.length);
}
function makeTownBird(color = "#52656e", scale = 1) {
  const group = new THREE.Group(),
    bodyMat = mat(color),
    dark = mat("#34413d"),
    body = new THREE.Group();
  group.add(body);
  group.scale.setScalar(scale);
  const b = mesh(
    sharedGeometry("bird-body", () => new THREE.SphereGeometry(0.19, 10, 7)),
    bodyMat,
    0,
    0,
    0,
    body,
  );
  b.scale.set(0.85, 1, 1.8);
  ball(0.15, bodyMat, 0, 0.18, 0.27, body);
  ball(0.1, mat("#d4c9a7"), 0, -0.04, 0.2, body).scale.set(0.85, 0.8, 1.5);
  const beak = mesh(
    sharedGeometry("bird-beak", () => new THREE.ConeGeometry(0.055, 0.2, 6)),
    mat("#c3a564"),
    0,
    0.16,
    0.45,
    body,
  );
  beak.rotation.x = PI / 2;
  for (const side of [-1, 1]) ball(0.025, dark, side * 0.11, 0.23, 0.35, body);
  const tail = box(0.24, 0.035, 0.36, dark, 0, 0.015, -0.43, body);
  tail.rotation.x = -0.12;
  const wings = [];
  for (const side of [-1, 1]) {
    const pivot = new THREE.Group();
    pivot.position.set(side * 0.1, 0.045, 0);
    group.add(pivot);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute(
      "position",
      new THREE.Float32BufferAttribute(
        [0, 0, 0.19, side * 0.48, 0, 0.13, side * 0.96, 0, -0.11, side * 0.72, 0, -0.32, 0, 0, -0.23],
        3,
      ),
    );
    geo.setIndex([0, 1, 4, 1, 2, 3, 1, 3, 4]);
    geo.computeVertexNormals();
    const m = mat(color);
    const wingMaterial = m.clone();
    wingMaterial.side = THREE.DoubleSide;
    mesh(geo, wingMaterial, 0, 0, 0, pivot, false);
    wings.push({ pivot, side });
  }
  batchTreeBranches(body);
  scene.add(group);
  return { group, wings, phase: lr(0, PI * 2), scale };
}
function makeBirdNest(route, index) {
  const point = route.curve.getPointAt(0.66),
    g = new THREE.Group();
  g.position.copy(point).add(v(0, route.name.startsWith("APPLE") ? 0.3 : 0.48, 0));
  scene.add(g);
  const bowl = mesh(
    new THREE.SphereGeometry(0.5, 16, 8, 0, PI * 2, PI / 2, PI / 2),
    mat("#5c4934"),
    0,
    0.18,
    0,
    g,
  );
  bowl.scale.y = 0.38;
  bowl.material.side = THREE.DoubleSide;
  const rim = mesh(new THREE.TorusGeometry(0.47, 0.085, 6, 20), nestWood, 0, 0.17, 0, g);
  rim.rotation.x = PI / 2;
  for (let i = 0; i < 24; i++) {
    const a = (i * PI) / 12 + lr(-0.2, 0.2),
      b = a + lr(0.35, 0.95);
    span(
      v(Math.cos(a) * 0.49, lr(0.08, 0.22), Math.sin(a) * 0.49),
      v(Math.cos(b) * 0.52, lr(0.06, 0.24), Math.sin(b) * 0.52),
      0.018,
      0.012,
      i % 2 ? nestWood : appleWood,
      g,
      4,
    );
  }
  for (let i = 0; i < 3; i++) {
    const egg = ball(
      0.09,
      mat(i % 2 ? "#c7d8cc" : "#e4d7b9"),
      Math.cos((i * PI * 2) / 3) * 0.18,
      0.16,
      Math.sin((i * PI * 2) / 3) * 0.18,
      g,
    );
    egg.scale.set(0.8, 1.25, 0.8);
  }
  batchTreeBranches(g);
  livingTown.nests.push({ group: g, route, point: g.position.clone() });
  if (index % 2 === 0) {
    const bird = makeTownBird(["#8f4d35", "#536b7a", "#64594c"][index % 3], 0.75);
    bird.nest = g.position.clone().add(v(0.28, 0.35, 0.08));
    bird.cycle = lr(0, 36);
    livingTown.birds.push(bird);
  }
}
function populateNestsAndBirds() {
  const branches = routes.filter((r) => r.kind === "branch" && /bough/.test(r.name) && r.length > 3),
    used = new Set();
  for (let i = 0; i < 24; i++) {
    const index = Math.floor((i * branches.length) / 24),
      route = branches[index];
    if (route && !used.has(route.id)) {
      used.add(route.id);
      makeBirdNest(route, i);
    }
  }
  const anchors = [
    [-42, 42, 44],
    [50, 345, 48],
    [460, 95, 46],
    [782, 125, 49],
    [998, 110, 53],
  ];
  for (let flock = 0; flock < anchors.length; flock++)
    for (let i = 0; i < 4; i++) {
      const bird = makeTownBird(["#536b7a", "#785d43", "#4d5350"][i % 3], 1 + lr(-0.1, 0.15));
      bird.anchor = new THREE.Vector3(...[anchors[flock][0], anchors[flock][2], anchors[flock][1]]);
      bird.offset = i * 0.38;
      bird.flock = flock;
      livingTown.birds.push(bird);
    }
}
function updateTownBirds(dt) {
  livingTown.elapsed += dt;
  const t = livingTown.elapsed,
    hidden = player.inHospital || player.inSewer || player.inDuct;
  for (let i = 0; i < livingTown.birds.length; i++) {
    const bird = livingTown.birds[i];
    let flying = true,
      heading = 0,
      bank = 0;
    if (bird.nest) {
      const cycle = (t + bird.cycle) % 48;
      flying = cycle > 12;
      if (!flying) {
        bird.group.position.copy(bird.nest);
        heading = bird.phase + Math.sin(t) * 0.12;
      } else {
        const u = (cycle - 12) / 36,
          a = u * PI * 2,
          r = 15 + Math.sin(u * PI) * 12;
        bird.group.position
          .copy(bird.nest)
          .add(v(Math.sin(a) * r, Math.sin(u * PI) ** 0.7 * 20, (1 - Math.cos(a)) * r * 0.55));
        heading = Math.atan2(Math.cos(a), Math.sin(a) * 0.55);
        bank = Math.sin(a) * 0.15;
      }
    } else {
      const a = t * 0.095 + bird.offset + bird.flock,
        r = 24 + bird.flock * 2;
      bird.group.position
        .copy(bird.anchor)
        .add(v(Math.cos(a) * r, Math.sin(a * 2) * 2.5, Math.sin(a) * r * 0.7));
      heading = Math.atan2(-Math.sin(a), Math.cos(a) * 0.7);
      bank = -0.17;
    }
    bird.group.rotation.set(flying ? Math.sin(t * 0.8 + bird.phase) * 0.045 : 0, heading, bank);
    for (const wing of bird.wings)
      wing.pivot.rotation.z = wing.side * (flying ? Math.sin(t * 10 + bird.phase) * 0.55 + 0.1 : 1.1);
    bird.group.visible =
      !hidden &&
      bird.group.position.distanceTo(player.pos) < 210 &&
      (RenderConfig.tier !== "performance" || i % 2 === 0);
  }
  for (const nest of livingTown.nests)
    nest.group.visible = !hidden && nest.point.distanceTo(player.pos) < 165;
}

// One visual-only airliner. No audio, effects sound, speech, or announcements.
const overflight = {
  group: new THREE.Group(),
  wait: 34,
  active: false,
  elapsed: 0,
  duration: 48,
  passes: 0,
  from: v(0, 0, 0),
  to: v(0, 0, 0),
};
scene.add(overflight.group);
overflight.group.visible = false;
function makeSilentAirplane() {
  const g = overflight.group,
    paint = new THREE.MeshStandardMaterial({
      color: "#ecece1",
      emissive: "#808a91",
      emissiveIntensity: 0.12,
      roughness: 0.55,
    }),
    blue = mat("#477783"),
    dark = mat("#5b6a70");
  const fuselage = mesh(new THREE.SphereGeometry(1, 16, 10), paint, 0, 0, 0, g, false);
  fuselage.scale.set(0.72, 0.76, 8.1);
  function fin(points, material) {
    const geo = new THREE.BufferGeometry();
    geo.setAttribute("position", new THREE.Float32BufferAttribute(points.flat(), 3));
    geo.setIndex([0, 1, 2, 0, 2, 3]);
    geo.computeVertexNormals();
    const m = material.clone();
    m.side = THREE.DoubleSide;
    return mesh(geo, m, 0, 0, 0, g, false);
  }
  for (const side of [-1, 1]) {
    fin(
      [
        [side * 0.45, 0, 2],
        [side * 10, 0.12, -1.8],
        [side * 9, 0.12, -3.2],
        [side * 0.45, 0, -2.3],
      ],
      paint,
    );
    fin(
      [
        [side * 0.3, 0.3, -5.3],
        [side * 3.7, 0.4, -7],
        [side * 3.4, 0.4, -8],
        [side * 0.3, 0.3, -7.5],
      ],
      paint,
    );
    const engine = cyl(0.48, 0.42, 2.5, paint, side * 3.2, -0.6, 0.05, g, 12);
    engine.rotation.x = PI / 2;
    const inlet = cyl(0.36, 0.36, 0.06, dark, side * 3.2, -0.6, 1.33, g, 12);
    inlet.rotation.x = PI / 2;
  }
  fin(
    [
      [0, 0.4, -4.7],
      [0, 3.2, -6.8],
      [0, 3.0, -8],
      [0, 0.4, -7.6],
    ],
    blue,
  );
  const cockpit = ball(0.6, dark, 0, 0.35, 6.6, g);
  cockpit.scale.set(1, 0.45, 1.3);
  const trailGeo = sharedGeometry("contrail-segment", () => new THREE.CylinderGeometry(1, 0.92, 1, 7));
  for (const side of [-1, 1])
    for (let i = 0; i < 18; i++) {
      const u = i / 18,
        m = new THREE.MeshBasicMaterial({
          color: "#f5f3e8",
          transparent: true,
          opacity: 0.25 * (1 - u) ** 1.7,
          depthWrite: false,
        });
      const trail = mesh(trailGeo, m, side * 3.2, -0.6, -7 - i * 4.4, g, false);
      trail.rotation.x = PI / 2;
      trail.scale.set(0.09 + u * 0.31, 4.6, 0.09 + u * 0.31);
    }
  g.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = false;
      o.receiveShadow = false;
    }
  });
}
function launchOverflight() {
  const a = lr(-1.1, 1.1) + (overflight.passes % 2 ? PI : 0),
    direction = v(Math.sin(a), 0, Math.cos(a)),
    center = v(player.pos.x + lr(-95, 95), lr(165, 205), player.pos.z + lr(-75, 75));
  overflight.from.copy(center).addScaledVector(direction, -630);
  overflight.to.copy(center).addScaledVector(direction, 630);
  overflight.elapsed = 0;
  overflight.active = true;
  overflight.passes++;
  overflight.group.position.copy(overflight.from);
  overflight.group.rotation.y = Math.atan2(direction.x, direction.z);
  overflight.group.visible = true;
}
function updateOverflight(dt) {
  if (!playing || !player.alive) {
    overflight.group.visible = false;
    return;
  }
  if (!overflight.active) {
    overflight.wait -= dt;
    if (overflight.wait <= 0) launchOverflight();
    else return;
  }
  overflight.elapsed = Math.min(overflight.duration, overflight.elapsed + dt);
  overflight.group.position
    .copy(overflight.from)
    .lerp(overflight.to, overflight.elapsed / overflight.duration);
  overflight.group.visible = !player.inHospital && !player.inSewer && !player.inDuct;
  if (overflight.elapsed >= overflight.duration) {
    overflight.active = false;
    overflight.wait = lr(90, 150);
    overflight.group.visible = false;
  }
}

const heavyTraffic = [];
function buildHeavyVehicle(type, x, z, axis, direction, moving, color) {
  const g = new THREE.Group();
  g.name = type === "dump" ? "Dump truck" : "RV";
  scene.add(g);
  const paint = mat(color, 0.48, 0.25),
    metal = mat("#6f7a78", 0.4, 0.65),
    glass = mat("#507d88", 0.22, 0.35),
    cream = mat("#e5e0cf");
  const width = type === "dump" ? 3.35 : 3.2,
    length = type === "dump" ? 8.9 : 8.7,
    height = type === "dump" ? 4.12 : 4.3;
  box(2.7, 0.35, length - 0.3, M.black, 0, 0.8, 0, g);
  const wheels = [];
  for (const zz of type === "dump" ? [-3.0, -1.4, 3.0] : [-2.8, 2.8])
    for (const side of [-1, 1]) wheels.push(shopVehicleWheel(g, side * 1.55, zz, 0.62));
  if (type === "dump") {
    box(3.15, 2.45, 2.45, paint, 0, 2.08, 2.82, g);
    box(2.85, 0.9, 0.2, glass, 0, 2.7, 4.08, g);
    box(3.28, 0.38, 0.25, metal, 0, 1.03, 4.4, g);
    box(1.5, 0.55, 0.11, M.black, 0, 1.6, 4.13, g);
    for (const side of [-1, 1]) {
      box(0.1, 1.0, 1.65, glass, side * 1.6, 2.67, 2.7, g);
      box(0.16, 0.65, 0.42, metal, side * 1.76, 2.65, 3.5, g);
      box(0.52, 0.28, 0.13, mat("#f0dba5"), side * 1.08, 1.65, 4.18, g);
    }
    box(3.25, 0.3, 5.45, metal, 0, 1.9, -1.14, g);
    for (const side of [-1, 1]) {
      box(0.18, 1.75, 5.55, paint, side * 1.6, 2.85, -1.15, g);
      for (let i = 0; i < 5; i++) box(0.12, 1.85, 0.12, metal, side * 1.72, 2.85, -3.4 + i * 1.1, g);
    }
    box(3.28, 1.75, 0.18, paint, 0, 2.85, -3.98, g);
    box(3.28, 1.75, 0.18, paint, 0, 2.85, 1.58, g);
    const gravel = mat("#8b8980");
    for (let i = 0; i < 32; i++) {
      const rock = ball(lr(0.25, 0.48), gravel, lr(-1.14, 1.14), lr(2.6, 3.34), lr(-3.4, 1.0), g);
      rock.scale.y = 0.7;
    }
    cyl(0.09, 0.09, 2.4, metal, -1.5, 2.85, 1.25, g, 7);
    box(0.65, 0.15, 0.28, mat("#d5a13f"), 0, 3.43, 2.65, g);
  } else {
    box(3.12, 2.9, 8.35, cream, 0, 2.18, -0.1, g);
    box(3.18, 0.2, 8.45, paint, 0, 3.72, -0.1, g);
    box(2.78, 1.25, 0.15, glass, 0, 2.7, 4.12, g);
    box(3.2, 0.35, 0.26, metal, 0, 0.95, 4.28, g);
    for (const side of [-1, 1]) {
      box(0.07, 0.34, 8.36, paint, side * 1.59, 1.32, -0.1, g);
      box(0.08, 0.12, 8.25, metal, side * 1.6, 1.7, -0.1, g);
      for (const zz of [-2.5, -0.25, 2.25]) {
        box(0.09, 1.0, 1.5, M.black, side * 1.59, 2.75, zz, g);
        box(0.1, 0.83, 1.32, glass, side * 1.65, 2.75, zz, g);
      }
      box(0.18, 0.6, 0.42, metal, side * 1.8, 2.68, 3.66, g);
      box(0.55, 0.25, 0.13, mat("#f4dfad"), side * 1.05, 1.43, 4.19, g);
    }
    box(0.1, 2.45, 1.16, paint, 1.65, 2.07, 1.15, g);
    box(0.12, 0.75, 0.82, glass, 1.72, 2.6, 1.15, g);
    box(0.23, 0.2, 5.0, cream, 1.67, 3.65, -0.65, g);
    box(1.2, 0.35, 1.65, metal, 0, 4.0, -1.6, g);
    box(0.9, 0.2, 0.9, cream, 0, 3.94, 1.2, g);
    for (const xx of [-1.12, -0.62]) box(0.055, 2.8, 0.055, metal, xx, 2.25, -4.32, g);
    for (let i = 0; i < 7; i++) box(0.55, 0.055, 0.055, metal, -0.87, 1.1 + i * 0.36, -4.32, g);
  }
  for (const side of [-1, 1]) box(0.4, 0.22, 0.12, mat("#ae3c2c"), side * 1.1, 1.22, -length / 2, g);
  const ground = Math.max(terrainHeight(x, z), mallBaseAt(x, z) ?? -Infinity);
  g.position.set(x, ground + 0.04, z);
  g.rotation.y = axis === "x" ? (direction * PI) / 2 : direction > 0 ? 0 : PI;
  batchTreeBranches(g);
  const entry = {
    group: g,
    width,
    length,
    height,
    label: g.name,
    type,
    axis,
    direction,
    moving,
    wheels,
    speed: moving ? 5 : 0,
    cruise: type === "dump" ? 6.7 : 7.5,
    min: axis === "x" ? 280 : -250,
    max: axis === "x" ? 660 : 250,
  };
  heavyTraffic.push(entry);
  tallVehicles.push(entry);
  return entry;
}
function trafficVehicleAhead(root, fx, fz, range, halfWidth) {
  for (const item of trafficFleet()) {
    const q = item.group;
    if (q === root || !q.visible) continue;
    const dx = q.position.x - root.position.x,
      dz = q.position.z - root.position.z,
      along = dx * fx + dz * fz;
    const across = Math.abs(dx * fz - dz * fx),
      yaw = q.rotation.y,
      otherAlong =
        (Math.abs(Math.sin(yaw) * fx + Math.cos(yaw) * fz) * item.length) / 2 +
        (Math.abs(Math.cos(yaw) * fx - Math.sin(yaw) * fz) * item.width) / 2;
    if (along > 0 && along < range + otherAlong && across < halfWidth + item.width / 2 + 0.2) return true;
  }
  return false;
}
function updateHeavyTraffic(dt) {
  for (const c of heavyTraffic) {
    if (!c.moving) continue;
    const p = c.group.position,
      fx = c.axis === "x" ? c.direction : 0,
      fz = c.axis === "z" ? c.direction : 0;
    const danger =
      StreetVehicleLogic.seesHazard(p.x, p.z, fx, fz, 10, c.width / 2, c.group) ||
      trafficVehicleAhead(c.group, fx, fz, 11, c.width / 2);
    const desired = danger ? 0 : c.cruise;
    c.speed = StreetVehicleLogic.approach(c.speed, desired, (danger ? 10 : 3.2) * dt);
    p.x += fx * c.speed * dt;
    p.z += fz * c.speed * dt;
    const key = c.axis;
    if (p[key] > c.max) p[key] = c.min;
    else if (p[key] < c.min) p[key] = c.max;
    p.y = terrainHeight(p.x, p.z) + 0.04;
    for (const wheel of c.wheels) wheel.rotation.x += (c.speed * dt) / 0.62;
  }
}

// Run-over detection covers every actual vehicle mover, including emergency
// vehicles whose legacy `moving` flag is false. No collision is inferred from speed.
const TrafficRuntime = { frames: new Map(), playerBefore: v(0, 0, 0), enabled: false, lastFatal: null };
function trafficFleet() {
  const fleet = cars.map((c) => ({
    group: c.group,
    width: 2.35,
    length: 4.45,
    height: 2.04,
    label: "vehicle",
  }));
  for (const t of tallVehicles) if (!fleet.some((c) => c.group === t.group)) fleet.push(t);
  return fleet;
}
function beginTrafficFrame() {
  TrafficRuntime.enabled =
    playing && player.alive && !gamePaused && !player.inHospital && !player.inSewer && !player.inDuct;
  TrafficRuntime.frames.clear();
  TrafficRuntime.playerBefore.copy(player.pos);
  if (!TrafficRuntime.enabled) return;
  for (const vehicle of trafficFleet())
    TrafficRuntime.frames.set(vehicle.group, {
      vehicle,
      position: vehicle.group.position.clone(),
      yaw: vehicle.group.rotation.y,
      visible: vehicle.group.visible,
    });
}
function segmentBoxEntry(a, b, halfWidth, halfLength, minY, maxY) {
  let enter = 0,
    exit = 1;
  for (const [key, lo, hi] of [
    ["x", -halfWidth, halfWidth],
    ["y", minY, maxY],
    ["z", -halfLength, halfLength],
  ]) {
    const d = b[key] - a[key];
    if (Math.abs(d) < 1e-10) {
      if (a[key] < lo || a[key] > hi) return null;
      continue;
    }
    let t0 = (lo - a[key]) / d,
      t1 = (hi - a[key]) / d;
    if (t0 > t1) [t0, t1] = [t1, t0];
    enter = Math.max(enter, t0);
    exit = Math.min(exit, t1);
    if (enter > exit) return null;
  }
  return enter;
}
function sweptVehicleHit(p0, p1, v0, v1, yaw0, yaw1, width, length, height) {
  if (
    ![
      ...p0.toArray(),
      ...p1.toArray(),
      ...v0.toArray(),
      ...v1.toArray(),
      yaw0,
      yaw1,
      width,
      length,
      height,
    ].every(Number.isFinite)
  )
    return false;
  const turn = Math.atan2(Math.sin(yaw1 - yaw0), Math.cos(yaw1 - yaw0)),
    steps = Math.max(1, Math.ceil(Math.abs(turn) / 0.05));
  const relative0 = p0.clone().sub(v0),
    relative1 = p1.clone().sub(v1),
    radius = Math.hypot(width, length) / 2;
  for (let i = 0; i < steps; i++) {
    const t0 = i / steps,
      t1 = (i + 1) / steps,
      a = relative0.clone().lerp(relative1, t0),
      b = relative0.clone().lerp(relative1, t1),
      yaw = yaw0 + (turn * (t0 + t1)) / 2;
    const c = Math.cos(yaw),
      s = Math.sin(yaw),
      rotate = (p) => v(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
    const padding = 0.18 + ((radius * Math.abs(turn)) / steps) * 0.5;
    if (
      segmentBoxEntry(
        rotate(a),
        rotate(b),
        width / 2 + padding,
        length / 2 + padding,
        -0.3,
        height - 0.16,
      ) !== null
    )
      return true;
  }
  return false;
}
function vehicleGameOver(vehicle) {
  if (!player.alive) return;
  TrafficRuntime.lastFatal = vehicle.label || "vehicle";
  player.alive = false;
  playing = false;
  gamePaused = true;
  player.vel.set(0, 0, 0);
  player.rail = null;
  player.attackWindow = 0;
  player.focus = false;
  squirrel.visible = true;
  clearControls();
  document.exitPointerLock?.();
  $("dangerTitle").textContent = "RUN OVER";
  $("dangerText").textContent =
    `A ${TrafficRuntime.lastFatal.toLowerCase()} ran you over. The run is over. Power: ${player.points} · Bites: ${player.hits} · Coins: ${squirrelCoins}. Restart to play again.`;
  $("dangerOverlay").classList.remove("hidden");
}
function finishTrafficFrame(dt) {
  if (!TrafficRuntime.enabled || !player.alive) return false;
  for (const old of TrafficRuntime.frames.values()) {
    const vehicle = old.vehicle,
      g = vehicle.group;
    if (!old.visible || !g.visible) continue;
    const travel = Math.hypot(g.position.x - old.position.x, g.position.z - old.position.z);
    // Wrapping/spawning is not a journey through all the intervening streets.
    if (travel < 1e-5 || travel > Math.max(12, dt * 80 + 2)) continue;
    if (
      sweptVehicleHit(
        TrafficRuntime.playerBefore,
        player.pos,
        old.position,
        g.position,
        old.yaw,
        g.rotation.y,
        vehicle.width,
        vehicle.length,
        vehicle.height,
      )
    ) {
      vehicleGameOver(vehicle);
      return true;
    }
  }
  return false;
}
plantAppleTrees();
populateNestsAndBirds();
makeSilentAirplane();
buildHeavyVehicle("dump", 383, -5.6, "x", 1, true, "#c69b44");
buildHeavyVehicle("dump", -185.4, -210, "z", 1, true, "#ad6843");
buildHeavyVehicle("rv", 579, 5.6, "x", -1, true, "#688b83");
buildHeavyVehicle("rv", 5.4, 180, "z", -1, true, "#9b8264");
buildHeavyVehicle("dump", 1084, 409, "z", -1, false, "#c4a24f");
buildHeavyVehicle("rv", 1123, 409, "z", -1, false, "#6d8e92");

// GAME FRAME — central scheduler. The movement/camera core is never silently
// swallowed; peripheral NPC and scenery subsystems are isolated and report errors.
const clock = new THREE.Clock();
let wallLast = performance.now();
let mainLoopFailed = false;
const disabledSubsystems = new Set();
const runtimeErrors = [];
function reportRuntimeError(name, error, critical = false) {
  const message = `${name}: ${error?.message || String(error)}`;
  console.error("[Spicy Rodents]", message, error);
  if (!runtimeErrors.includes(message)) runtimeErrors.push(message);
  if (critical) {
    mainLoopFailed = true;
    const panel = document.getElementById("spicyBootError");
    const reason = document.getElementById("spicyBootReason");
    if (reason)
      reason.textContent = `Game loop error — ${message}${error?.stack ? "\n" + error.stack.split("\n").slice(0, 4).join("\n") : ""}`;
    if (panel) panel.style.display = "block";
    gamePaused = true;
  } else if (!disabledSubsystems.has(name)) {
    disabledSubsystems.add(name);
    flash(`${name} temporarily disabled. Press L for diagnostics.`, 4);
  }
}
function updateOptional(name, dt, fn) {
  if (disabledSubsystems.has(name)) return;
  try {
    fn(dt);
  } catch (error) {
    reportRuntimeError(name, error);
  }
}
function updateGameplay(dt, realDt) {
  if (!player.alive || gamePaused) return;
  beginTrafficFrame();
  updatePowerAndHeat(realDt);
  const movementSteps = Math.max(1, Math.ceil(dt / (1 / 60)));
  for (let step = 0; step < movementSteps; step++) updatePlayer(dt / movementSteps);
  validatePlayerState(dt);
  updatePepperPickups(dt);
  if (!player.inSewer && !player.inHospital) {
    updateOptional("Pedestrians", dt, updateHumans);
    updateOptional("Special cyclists", dt, updateNoveltyCast);
    updateOptional("Cars", dt, updateCars);
    updateOptional("Dump trucks + RVs", dt, updateHeavyTraffic);
    updateOptional("Ice cream truck + trolley", dt, updateStreetVehicles);
    updateOptional("Wildlife", dt, updateWildlife);
    updateOptional("Cats", dt, updateYardCats);
    updateOptional("Ambulances", dt, updateAmbulance);
  }
  updateOptional("Infection", Math.min(realDt, 0.2), updateInfection);
  updateOptional("Hospital", Math.min(realDt, 0.2), updateHospital);
  updateOptional("City systems", dt, (step) => updateNewSystems(realDt, step));
  updateOptional("Westside", dt, updateWestside);
  updateOptional("Gatherings", dt, updateLivingEvents);
  updateOptional("Doors", dt, animateHouseDoors);
  updateHouseInteriors(dt); // Player access and door state stay core.
  updateOptional("Indoor animations", dt, updateInteriorMotion);
  updateOptional("Posters", dt, updatePosterAwareness);
  updateOptional("Police", dt, updatePoliceResponse);
  finishTrafficFrame(dt); // Fatal impact is core gameplay, never an optional visual effect.
}
function updateScenery(dt) {
  for (const leaf of canopyAnimated) {
    const breeze = Math.sin(time * 0.51 + leaf.phase) * leaf.amplitude;
    leaf.mesh.rotation.z = breeze;
    leaf.mesh.rotation.x = Math.sin(time * 0.37 + leaf.phase * 1.3) * leaf.amplitude * 0.6;
  }
  updateCanopyShadows();
  updateEmergencyBeacons();
  updateRiverDistrict(gamePaused ? 0 : dt);
  updateMall(gamePaused ? 0 : dt);
  updateTownBirds(gamePaused ? 0 : dt);
  updateOverflight(gamePaused ? 0 : dt);
  if (playing && !gamePaused) animateBiteDance(dt);
}
let debugAccum = 0;
function updateDiagnostics(dt) {
  debugAccum += dt;
  if (debugAccum < 0.2) return;
  debugAccum = 0;
  const element = document.getElementById("spicyDiagnostic");
  if (!element || !element.classList.contains("open")) return;
  const p = player.pos;
  element.textContent =
    `v5.4 · ${Math.round(1000 / Math.max(1, RenderConfig.frameMs))} fps · ${renderer.info.render.calls} draws · ${Math.round(renderer.info.render.triangles / 1000)}k triangles
${BatchingStats.before} static meshes → ${BatchingStats.after} batches ·  · ${player.rail?.name || "ground"}\n` +
    `player ${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)} · ${player.grounded ? "grounded" : "air/route"}\n` +
    `routes ${routes.length}/${routes.filter((r) => r.indexed).length} indexed · forks ${canopyForks.size} · errors ${runtimeErrors.length}` +
    (runtimeErrors.length ? "\n" + runtimeErrors.slice(-2).join(" | ") : "");
}
function tick() {
  if (mainLoopFailed) return;
  requestAnimationFrame(tick);
  const now = performance.now(),
    realDt = Math.max(0, (now - wallLast) / 1000);
  wallLast = now;
  const clockDelta = clock.getDelta();
  if (document.hidden || RenderConfig.contextLost) return;
  const dt = Math.min(clockDelta, 0.08),
    activeDt = Math.min(realDt, 0.2);
  if (!gamePaused) {
    time += dt;
    messageTime -= dt;
  }
  if (messageTime <= 0) $("status").classList.remove("show");
  try {
    if (playing && !gamePaused && player.alive) updateGameplay(dt, activeDt);
    else if (!playing && player.alive) {
      yaw = PI + Math.sin(time * 0.08) * 0.18;
      pitch = 0.2;
      updateTail(time * 0.7);
    }
    updateScenery(dt);
    updateCamera(dt);
    updateCompass();
    updateBubbles(dt);
    updateDiagnostics(dt);
    updateVisuals(dt, realDt);
    renderFrame(dt);
  } catch (error) {
    reportRuntimeError("Main movement/render loop", error, true);
  }
}
// Fail safely on a malformed climbing route rather than quietly poisoning the
// whole spatial index or having the camera jump to an invalid coordinate.
function verifyRouteRegistry() {
  const bad = routes.filter(
    (r) =>
      !Number.isFinite(r.length) ||
      r.length < 0.04 ||
      !r.sampled?.length ||
      r.sampled.some((p) => !p || ![p.x, p.y, p.z].every(Number.isFinite)),
  );
  if (bad.length)
    throw new Error(
      `Corrupt climbing routes (${bad.length}): ${bad
        .slice(0, 5)
        .map((r) => r.name)
        .join(", ")}`,
    );
  return routes.length;
}
// Final registry rebuild includes westside trees and the later treehouse.
verifyRouteRegistry();
const verifiedUtilityPoles = verifyUtilityPlacement();
console.info(`[Spicy Rodents] ${verifiedUtilityPoles} utility supports verified off pavement`);
rebuildCanopyForks();
if (routes.some((r) => !r.indexed)) console.warn("[Spicy Rodents] Incomplete route registry");
try {
  initRefresh();
  drawInfection();
  flash("v5.4 · APPLE TREES, BIRDS & TRAFFIC · Watch for moving vehicles", 6);
  tick();
  if (!mainLoopFailed) {
    window.__spicyBootOk = true;
    $("loading").classList.add("done");
    const errOverlay = document.getElementById("spicyBootError");
    if (errOverlay) errOverlay.style.display = "none";
  }
} catch (error) {
  reportRuntimeError("Game startup", error, true);
}
