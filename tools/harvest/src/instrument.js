"use strict";
// Builds the instrumented copy of the pinned v5.4 HTML.
// Two edits only (same idea as routes_movement.md section 0):
//   1. addRoute is wrapped so every route records the call site that created it.
//   2. a dump function runs right after rebuildCanopyForks() and before tick().
// The dump code itself lives in inpage_dump.js and is inserted verbatim.
const fs = require("node:fs");
const path = require("node:path");

const MODULE_OPEN = '<script type="module">';
const MODULE_CLOSE = "</script>";

function splitHtml(html) {
  const open = html.indexOf(MODULE_OPEN);
  if (open < 0) throw new Error("module script tag not found");
  const bodyStart = open + MODULE_OPEN.length + 1; // skip the newline after the tag
  const close = html.indexOf(MODULE_CLOSE, bodyStart);
  if (close < 0) throw new Error("module script close tag not found");
  // 1-based HTML line on which the module body starts (for stack-trace line mapping)
  const bodyStartLine = html.slice(0, bodyStart).split("\n").length;
  return {
    head: html.slice(0, bodyStart),
    body: html.slice(bodyStart, close),
    tail: html.slice(close),
    bodyStartLine,
  };
}

function instrumentModule(body) {
  const dumpSrc = fs.readFileSync(path.join(__dirname, "inpage_dump.js"), "utf8");
  // (1) rename the original addRoute; the wrapper is a hoisted function declaration in the dump code
  const defRe = /function addRoute\(name,\s*points,\s*opts\s*=\s*\{\}\)\s*\{/g;
  const defs = body.match(defRe) || [];
  if (defs.length !== 1) throw new Error(`expected exactly one addRoute definition, found ${defs.length}`);
  let out = body.replace(defRe, "function addRoute__orig(name, points, opts = {}) {");
  // (2) call the dump after the fork rebuild and before the main loop starts
  const anchorRe = /rebuildCanopyForks\(\);\s*if\s*\(\s*routes\.some\(/g;
  const anchors = out.match(anchorRe) || [];
  if (anchors.length !== 1) throw new Error(`expected exactly one dump anchor, found ${anchors.length}`);
  out = out.replace(anchorRe, (m) => "rebuildCanopyForks();\n__SR_DUMP();\n" + m.slice("rebuildCanopyForks();".length).trimStart());
  return out + "\n// ---- tools/harvest instrumentation ----\n" + dumpSrc + "\n";
}

// variant "html": the module exactly as embedded in the pinned HTML (whitespace-minified).
// variant "pretty": the same module from reference/v5_4_game.js (prettier output), so that
// call-site line numbers match the line numbers the specs cite.
function buildInstrumentedHtml(html, variant, prettyJs) {
  const parts = splitHtml(html);
  const moduleBody = variant === "pretty" ? prettyJs : parts.body;
  return {
    html: parts.head + instrumentModule(moduleBody) + parts.tail,
    bodyStartLine: parts.bodyStartLine,
  };
}

module.exports = { splitHtml, instrumentModule, buildInstrumentedHtml };
