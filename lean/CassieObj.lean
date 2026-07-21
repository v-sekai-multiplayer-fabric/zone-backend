-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- `CassieObj` — Wavefront OBJ loader (FFI).
--
-- Loads a `.obj` file into a heap handle Lean accesses by USize.
-- Restores the original upstream design (the equivalent geogram/PMP
-- modules needed the same reversal for performance and dependency
-- consistency, so this stays real C++ too rather than a mixed
-- pure-Lean/FFI split): a small, dependency-free parser at
-- c_src/thirdparty/ffi/cassie_obj_ffi.cpp — minimal subset
-- (`v x y z` / `f i j k` with the standard `/` variants),
-- fan-triangulating polygons of degree > 3. Built alongside
-- CassieGeogram/CassiePmp's native code into
-- c_src/thirdparty/build/libcassie_native.a (see
-- c_src/thirdparty/build_cassie_native.sh), linked into
-- `obj_probe`/`cycle_patch` via `moreLinkArgs`.
--
-- Triangle indices come back as a flat `ByteArray` of little-endian
-- `uint32`s (3 per face), matching the convention already used by the
-- geogram FFI's `delaunay_get_triangles` and PMP's `meshNew`.

namespace CassieObj

/-- Opaque heap handle for a parsed OBJ mesh. -/
abbrev MeshHandle := USize

/-- Parse an OBJ file from `path` and return its heap handle. If the
    file can't be opened, returns a handle whose vertex/face counts are
    zero. -/
@[extern "cassie_obj_load"]
opaque load (path : @& String) : IO MeshHandle

/-- Release a mesh handle. -/
@[extern "cassie_obj_free"]
opaque free (h : MeshHandle) : IO Unit

/-- Number of vertices in the loaded mesh. -/
@[extern "cassie_obj_n_vertices"]
opaque nVertices (h : MeshHandle) : IO USize

/-- Number of triangle faces (after fan triangulation of any ngons). -/
@[extern "cassie_obj_n_faces"]
opaque nFaces (h : MeshHandle) : IO USize

/-- Copy vertex positions into a flat float array (xyz xyz ...). The
    `out` array must be at least `nVertices h * 3` floats long. -/
@[extern "cassie_obj_get_positions"]
opaque getPositions (h : MeshHandle) (out : FloatArray) : IO FloatArray

/-- Copy triangle vertex indices into a ByteArray of little-endian
    uint32s (3 per face). The `out` ByteArray must be at least
    `nFaces h * 3 * 4` bytes long. -/
@[extern "cassie_obj_get_faces"]
opaque getFaces (h : MeshHandle) (out : ByteArray) : IO ByteArray

end CassieObj
