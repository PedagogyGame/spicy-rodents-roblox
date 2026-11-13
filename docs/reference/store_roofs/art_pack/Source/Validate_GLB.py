#!/usr/bin/env python3
"""Inspect standalone glTF 2.0 binary assets without altering them.

Run:
    python3 sewer_build/validate_pack.py
    python3 sewer_build/validate_pack.py --glob 'path/*.glb' --report path/qa.json

Only Python 3 and numpy are needed. Triangle budgets are evaluated on the
active scene (including instances). File size is an advisory by default.
This checks asset structure and geometry; it is not an engine playtest.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
from pathlib import Path
import struct
import sys

import numpy as np


COMPONENTS = {5120: np.dtype("i1"), 5121: np.dtype("u1"),
              5122: np.dtype("<i2"), 5123: np.dtype("<u2"),
              5125: np.dtype("<u4"), 5126: np.dtype("<f4")}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4,
          "MAT2": 4, "MAT3": 9, "MAT4": 16}
DEFAULT_GLOB = str(Path(__file__).resolve().parents[1] / "GLB" / "*.glb")
DEFAULT_REPORT = str(Path(__file__).resolve().parents[1] / "Metadata" / "GLB_Validation.json")


def rounded(value):
    return np.asarray(value).round(6).tolist()


def node_matrix(node):
    """glTF column-major matrix, or T * R * S with x/y/z/w quaternion."""
    if "matrix" in node:
        return np.asarray(node["matrix"], dtype=float).reshape(4, 4).T
    x, y, z, w = node.get("rotation", (0, 0, 0, 1))
    rot = np.array([
        [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), 0],
        [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), 0],
        [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), 0],
        [0, 0, 0, 1]], dtype=float)
    scale = np.diag([*node.get("scale", (1, 1, 1)), 1.0])
    result = rot @ scale
    result[:3, 3] = node.get("translation", (0, 0, 0))
    return result


class Asset:
    def __init__(self, path):
        self.path = Path(path)
        self.errors = []
        self.warnings = []
        self.accessor_cache = {}
        raw = self.path.read_bytes()
        if len(raw) < 20:
            raise ValueError("File is too short for a GLB header and JSON chunk")
        magic, version, length = struct.unpack_from("<4sII", raw)
        if magic != b"glTF" or version != 2:
            raise ValueError(f"Expected GLB 2.0; got {magic!r}, version {version}")
        if length != len(raw):
            raise ValueError(f"Declared GLB length {length} differs from file size {len(raw)}")
        self.size = length
        chunks = []
        offset = 12
        while offset < length:
            if offset+8 > length:
                raise ValueError("Truncated chunk header")
            n, kind = struct.unpack_from("<I4s", raw, offset)
            offset += 8
            if n % 4:
                self.errors.append("GLB chunk length is not a multiple of four")
            if offset+n > length:
                raise ValueError("GLB chunk extends beyond declared file length")
            chunks.append((kind, raw[offset:offset+n]))
            offset += n
        if not chunks or chunks[0][0] != b"JSON":
            raise ValueError("First GLB chunk must be JSON")
        self.doc = json.loads(chunks[0][1].decode("utf-8").rstrip(" \t\r\n\x00"))
        bins = [data for kind, data in chunks if kind == b"BIN\x00"]
        self.binary = bins[0] if bins else b""
        if len(bins) > 1:
            self.errors.append("GLB contains more than one BIN chunk")
        if self.doc.get("asset", {}).get("version") != "2.0":
            self.errors.append("JSON asset.version is not 2.0")

    def view(self, index):
        views = self.doc.get("bufferViews", [])
        if not 0 <= index < len(views):
            raise ValueError(f"Invalid bufferView {index}")
        view = views[index]
        if view.get("buffer", 0) != 0:
            raise ValueError(f"bufferView {index} uses unsupported/external buffer")
        start = view.get("byteOffset", 0)
        end = start + view["byteLength"]
        if start < 0 or end > len(self.binary):
            raise ValueError(f"bufferView {index} is out of BIN bounds")
        return view, start, end

    def accessor(self, index):
        if index in self.accessor_cache:
            return self.accessor_cache[index]
        accessors = self.doc.get("accessors", [])
        if not 0 <= index < len(accessors):
            raise ValueError(f"Invalid accessor {index}")
        acc = accessors[index]
        dtype = COMPONENTS[acc["componentType"]]
        columns = WIDTHS[acc["type"]]
        count = acc["count"]
        if count < 0:
            raise ValueError(f"Accessor {index} has a negative count")
        # Matrix byte-padding is irrelevant to vertex attributes, but reject
        # unsupported compact matrix cases instead of silently misreading them.
        if acc["type"].startswith("MAT") and dtype.itemsize < 4:
            raise ValueError(f"Accessor {index}: compact matrix columns not supported")
        if "bufferView" in acc:
            view, base, end = self.view(acc["bufferView"])
            stride = view.get("byteStride", columns*dtype.itemsize)
            offset = base + acc.get("byteOffset", 0)
            required = (count-1)*stride + columns*dtype.itemsize if count else 0
            if stride < columns*dtype.itemsize or offset < base or offset+required > end:
                raise ValueError(f"Accessor {index} extends beyond its bufferView")
            values = np.ndarray((count, columns), dtype=dtype, buffer=self.binary,
                                offset=offset, strides=(stride, dtype.itemsize)).copy()
        else:
            values = np.zeros((count, columns), dtype=dtype)
        if "sparse" in acc:
            sparse = acc["sparse"]
            count_sparse = sparse["count"]
            ix = sparse["indices"]
            _, base, end = self.view(ix["bufferView"])
            ix_type = COMPONENTS[ix["componentType"]]
            off = base + ix.get("byteOffset", 0)
            if off+count_sparse*ix_type.itemsize > end:
                raise ValueError(f"Accessor {index} sparse indices are out of bounds")
            indices = np.frombuffer(self.binary, dtype=ix_type, count=count_sparse, offset=off)
            vals = sparse["values"]
            _, base, end = self.view(vals["bufferView"])
            off = base + vals.get("byteOffset", 0)
            if off+count_sparse*columns*dtype.itemsize > end:
                raise ValueError(f"Accessor {index} sparse values are out of bounds")
            if np.any(indices >= count):
                raise ValueError(f"Accessor {index} sparse index exceeds accessor count")
            values[indices] = np.frombuffer(self.binary, dtype=dtype,
                                           count=count_sparse*columns, offset=off).reshape(-1, columns)
        if acc.get("normalized") and acc["componentType"] != 5126:
            limits = np.iinfo(dtype)
            values = values.astype(float)/limits.max
            if limits.min < 0:
                values = np.maximum(values, -1.0)
        self.accessor_cache[index] = values
        return values

    def inspect(self, args):
        d = self.doc
        buffers = d.get("buffers", [])
        embedded_buffers = len(buffers) == 1 and "uri" not in buffers[0]
        if not embedded_buffers:
            self.errors.append("Expected exactly one embedded buffer with no URI")
        elif not (buffers[0].get("byteLength", -1) <= len(self.binary) <= buffers[0].get("byteLength", -1)+3):
            self.errors.append("BIN length does not match buffers[0].byteLength plus padding")
        for index in range(len(d.get("bufferViews", []))):
            self.view(index)
        images = []
        for i, im in enumerate(d.get("images", [])):
            embedded = "bufferView" in im and "uri" not in im
            if not embedded:
                self.errors.append(f"Image {i} is not embedded in a bufferView")
            image_info = {"index": i, "name": im.get("name", ""),
                          "mime_type": im.get("mimeType"), "embedded": embedded}
            if embedded:
                _, start, end = self.view(im["bufferView"])
                image_info["bytes"] = end-start
                data = self.binary[start:end]
                if im.get("mimeType") == "image/png" and not data.startswith(b"\x89PNG\r\n\x1a\n"):
                    self.errors.append(f"Image {i} claims PNG but has the wrong signature")
                if im.get("mimeType") == "image/jpeg" and not data.startswith(b"\xff\xd8"):
                    self.errors.append(f"Image {i} claims JPEG but has the wrong signature")
            images.append(image_info)
        meshes = []
        mesh_positions = {}
        total_triangles = total_degenerate = 0
        materials = d.get("materials", [])
        for mesh_index, mesh in enumerate(d.get("meshes", [])):
            positions_all = []
            primitives = []
            for pi, primitive in enumerate(mesh.get("primitives", [])):
                label = f"Mesh {mesh_index} primitive {pi}"
                attrs = primitive.get("attributes", {})
                if "POSITION" not in attrs:
                    self.errors.append(f"{label} has no POSITION")
                    continue
                pos = self.accessor(attrs["POSITION"]).astype(float)
                if pos.shape[1] != 3 or not np.isfinite(pos).all():
                    self.errors.append(f"{label} has invalid/nonfinite positions")
                    continue
                positions_all.append(pos)
                indices = self.accessor(primitive["indices"]).ravel().astype(np.int64) if "indices" in primitive else np.arange(len(pos))
                if len(indices) and (indices.min() < 0 or indices.max() >= len(pos)):
                    raise ValueError(f"{label} has out-of-range indices")
                mode = primitive.get("mode", 4)
                if mode == 4:
                    if len(indices) % 3:
                        self.errors.append(f"{label} triangle index count not divisible by three")
                    tri = indices[:len(indices)//3*3].reshape(-1, 3)
                elif mode == 5:
                    tri = np.array([indices[i:i+3] for i in range(max(0, len(indices)-2))], dtype=np.int64).reshape(-1, 3)
                elif mode == 6:
                    tri = np.array([[indices[0], indices[i], indices[i+1]] for i in range(1, len(indices)-1)], dtype=np.int64).reshape(-1, 3)
                else:
                    tri = np.empty((0, 3), dtype=np.int64)
                    self.warnings.append(f"{label} is primitive mode {mode}, not triangles")
                cross = np.cross(pos[tri[:, 1]]-pos[tri[:, 0]], pos[tri[:, 2]]-pos[tri[:, 0]])
                degenerate = int(np.sum(np.einsum("ij,ij->i", cross, cross) < 1e-16))
                total_triangles += len(tri)
                total_degenerate += degenerate
                has_normals = "NORMAL" in attrs
                has_uv = "TEXCOORD_0" in attrs
                if not has_normals:
                    self.errors.append(f"{label} has no normals")
                else:
                    normal = self.accessor(attrs["NORMAL"])
                    norms = np.linalg.norm(normal, axis=1)
                    if len(normal) != len(pos) or not np.isfinite(normal).all() or np.any(norms < 0.99) or np.any(norms > 1.01):
                        self.errors.append(f"{label} has invalid or non-unit normals")
                if has_uv:
                    uv = self.accessor(attrs["TEXCOORD_0"])
                    if len(uv) != len(pos) or not np.isfinite(uv).all():
                        self.errors.append(f"{label} has invalid/nonfinite UVs")
                material_index = primitive.get("material")
                material = materials[material_index] if material_index is not None and 0 <= material_index < len(materials) else None
                if material_index is not None and material is None:
                    self.errors.append(f"{label} has invalid material index {material_index}")
                if material and not has_uv and ("baseColorTexture" in material.get("pbrMetallicRoughness", {}) or "normalTexture" in material):
                    self.errors.append(f"{label} uses textured material but has no UVs")
                if degenerate:
                    self.warnings.append(f"{label} has {degenerate} degenerate triangles")
                primitives.append({"index": pi, "vertices": len(pos), "triangles": len(tri),
                                   "degenerate_triangles": degenerate, "normals": has_normals,
                                   "uv0": has_uv, "material": material_index,
                                   "material_name": material.get("name", "") if material else None,
                                   "bounds_min": rounded(pos.min(axis=0)), "bounds_max": rounded(pos.max(axis=0))})
            mesh_positions[mesh_index] = np.concatenate(positions_all) if positions_all else np.empty((0, 3))
            meshes.append({"index": mesh_index, "name": mesh.get("name", ""), "primitives": primitives,
                           "triangles": sum(p["triangles"] for p in primitives)})

        nodes = d.get("nodes", [])
        parents = {}
        for index, node in enumerate(nodes):
            for child in node.get("children", []):
                if child in parents:
                    self.errors.append(f"Node {child} has multiple parents")
                parents[child] = index
        scene_index = d.get("scene", 0)
        scenes = d.get("scenes", [])
        if not scenes or not 0 <= scene_index < len(scenes):
            raise ValueError("No valid active scene")
        roots = scenes[scene_index].get("nodes", [])
        visited = set()
        ports = []
        lights = []
        geometry_bounds = []
        scene_triangles = 0
        node_records = []

        def walk(index, parent_world, stack):
            nonlocal scene_triangles
            if index in stack:
                raise ValueError(f"Cycle in node hierarchy at node {index}")
            if not 0 <= index < len(nodes):
                raise ValueError(f"Invalid node index {index}")
            if index in visited:
                self.errors.append(f"Node {index} is instantiated more than once in scene hierarchy")
            visited.add(index)
            node = nodes[index]
            world = parent_world @ node_matrix(node)
            if not np.isfinite(world).all():
                self.errors.append(f"Node {index} has nonfinite transform")
            name = node.get("name", f"node_{index}")
            record = {"index": index, "name": name, "mesh": node.get("mesh"),
                      "parent": parents.get(index), "position": rounded(world[:3, 3]),
                      "scale": rounded(np.linalg.norm(world[:3, :3], axis=0)), "extras": node.get("extras", {})}
            node_records.append(record)
            if name.startswith("PORT_"):
                record = dict(record)
                record["local_negative_z_world_direction"] = rounded(world[:3, :3] @ np.array([0, 0, -1.0]))
                ports.append(record)
                if "mesh" in node:
                    self.warnings.append(f"Port marker {name} unexpectedly has a visible mesh")
            if name.startswith("LIGHT_") or "KHR_lights_punctual" in node.get("extensions", {}):
                lights.append(record)
            if "mesh" in node:
                mi = node["mesh"]
                if mi not in mesh_positions:
                    raise ValueError(f"Node {name} references invalid mesh {mi}")
                points = mesh_positions[mi]
                if len(points):
                    world_points = points @ world[:3, :3].T + world[:3, 3]
                    geometry_bounds.append((world_points.min(axis=0), world_points.max(axis=0)))
                    scene_triangles += meshes[mi]["triangles"]
            for child in node.get("children", []):
                walk(child, world, stack | {index})

        for root in roots:
            walk(root, np.eye(4), set())
        if not geometry_bounds:
            self.errors.append("Active scene has no geometry")
            lo = hi = np.zeros(3)
        else:
            lo = np.min([v[0] for v in geometry_bounds], axis=0)
            hi = np.max([v[1] for v in geometry_bounds], axis=0)
        if scene_triangles > args.max_triangles:
            self.errors.append(f"Scene triangle count {scene_triangles:,} exceeds {args.max_triangles:,}")
        if self.size > args.max_bytes:
            msg = f"File size {self.size:,} bytes exceeds target {args.max_bytes:,}"
            (self.errors if args.strict_size else self.warnings).append(msg)
        if len(ports) < args.require_ports:
            self.errors.append(f"Only {len(ports)} PORT_ markers; need {args.require_ports}")
        names = [n.get("name") for n in nodes if n.get("name")]
        if len(names) != len(set(names)):
            self.warnings.append("Duplicate node names may make game-side selection ambiguous")
        unreachable = sorted(set(range(len(nodes)))-visited)
        if unreachable:
            self.warnings.append(f"{len(unreachable)} nodes are not used by the active scene")
        material_summary = []
        for i, mat in enumerate(materials):
            pbr = mat.get("pbrMetallicRoughness", {})
            material_summary.append({"index": i, "name": mat.get("name", ""),
                                     "base_color_texture": pbr.get("baseColorTexture", {}).get("index"),
                                     "normal_texture": mat.get("normalTexture", {}).get("index"),
                                     "metallic_roughness_texture": pbr.get("metallicRoughnessTexture", {}).get("index"),
                                     "occlusion_texture": mat.get("occlusionTexture", {}).get("index"),
                                     "metallic_factor": pbr.get("metallicFactor", 1),
                                     "roughness_factor": pbr.get("roughnessFactor", 1),
                                     "double_sided": mat.get("doubleSided", False),
                                     "alpha_mode": mat.get("alphaMode", "OPAQUE")})
        return {"file": str(self.path), "name": self.path.name, "size_bytes": self.size,
                "status": "PASS" if not self.errors else "FAIL", "errors": self.errors, "warnings": self.warnings,
                "asset": d.get("asset"), "embedded_buffers": embedded_buffers,
                "all_images_embedded": all(i["embedded"] for i in images),
                "extensions_used": d.get("extensionsUsed", []), "extensions_required": d.get("extensionsRequired", []),
                "mesh_count": len(meshes), "primitive_count": sum(len(m["primitives"]) for m in meshes),
                "material_count": len(materials), "unique_mesh_triangles": total_triangles,
                "scene_triangles": scene_triangles, "degenerate_triangles": total_degenerate,
                "world_bounds_min": rounded(lo), "world_bounds_max": rounded(hi),
                "dimensions_meters_xyz": rounded(hi-lo),
                "active_scene": scene_index, "scene_root_indices": roots, "node_count": len(nodes),
                "ports": ports, "lights": lights, "images": images, "materials": material_summary,
                "meshes": meshes, "nodes": node_records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glob", default=DEFAULT_GLOB, help="Glob matching GLB files")
    parser.add_argument("--report", default=DEFAULT_REPORT, help="JSON report path")
    parser.add_argument("--max-triangles", type=int, default=30000)
    parser.add_argument("--max-bytes", type=int, default=2000000)
    parser.add_argument("--strict-size", action="store_true")
    parser.add_argument("--require-ports", type=int, default=1)
    args = parser.parse_args()
    paths = sorted(glob.glob(args.glob))
    if not paths:
        print(f"No GLB files found: {args.glob}", file=sys.stderr)
        return 2
    results = []
    for path in paths:
        try:
            result = Asset(path).inspect(args)
        except Exception as exc:
            result = {"file": path, "name": Path(path).name, "status": "FAIL",
                      "errors": [f"{type(exc).__name__}: {exc}"], "warnings": []}
        results.append(result)
        print(f"{result['status']} {result['name']}: {result.get('scene_triangles', '?')} triangles; "
              f"{result.get('size_bytes', '?')} bytes; {result.get('dimensions_meters_xyz', '?')} meters; "
              f"{len(result.get('ports', []))} ports")
        for message in result["errors"]:
            print(f"  ERROR: {message}")
        for message in result["warnings"]:
            print(f"  NOTE: {message}")
    report = {"validation": "GLB structure, geometry, embedding and budget checks; not an engine playtest",
              "budgets": {"max_scene_triangles": args.max_triangles, "max_bytes": args.max_bytes,
                          "strict_size": args.strict_size},
              "all_passed": all(r["status"] == "PASS" for r in results), "assets": results}
    dest = Path(args.report)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Report: {dest}")
    return 0 if report["all_passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
