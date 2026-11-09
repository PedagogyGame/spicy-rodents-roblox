"use strict";
// Deterministic JSON writer: objects keep insertion order, arrays of numbers (or of
// numeric arrays) stay on one line, everything else is indented. Numbers print with
// JSON.stringify (shortest round-trip), so values are exactly what the page produced.
function isFlat(v) {
  if (!Array.isArray(v)) return false;
  return v.every(
    (x) =>
      x === null ||
      typeof x === "number" ||
      typeof x === "string" ||
      typeof x === "boolean" ||
      (Array.isArray(x) && x.every((y) => y === null || typeof y === "number" || typeof y === "string")),
  );
}
function fmt(v, indent) {
  const pad = "  ".repeat(indent);
  const padIn = "  ".repeat(indent + 1);
  if (Array.isArray(v)) {
    if (v.length === 0) return "[]";
    if (isFlat(v)) return JSON.stringify(v);
    return "[\n" + v.map((x) => padIn + fmt(x, indent + 1)).join(",\n") + "\n" + pad + "]";
  }
  if (v && typeof v === "object") {
    const keys = Object.keys(v).filter((k) => v[k] !== undefined);
    if (keys.length === 0) return "{}";
    return "{\n" + keys.map((k) => padIn + JSON.stringify(k) + ": " + fmt(v[k], indent + 1)).join(",\n") + "\n" + pad + "}";
  }
  return JSON.stringify(v === undefined ? null : v);
}
function stringify(v) {
  return fmt(v, 0) + "\n";
}
module.exports = { stringify };
