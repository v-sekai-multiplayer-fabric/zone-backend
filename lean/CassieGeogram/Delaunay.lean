-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- `CassieGeogram.Delaunay` — geogram BDEL Delaunay FFI.
--
-- A pure-Lean reimplementation (ear clipping + Lawson flips) was tried
-- first and dropped: it couldn't match geogram's real O(n log n)
-- performance on this pipeline's actual boundary sizes. This restores
-- the original upstream design instead -- real geogram (BSD-3),
-- vendored at c_src/thirdparty/geogram (the exact source subset
-- fabric-godot-core's modules/cassie/SCsub compiles, minus the
-- AGPL/non-commercial-licensed TetGen/Triangle backends and Voronoi/
-- CSG/IO code this pipeline never uses), built by
-- c_src/thirdparty/build_cassie_native.sh into
-- c_src/thirdparty/build/libcassie_native.a and linked into the
-- `cycle_patch`/`surface_fair`/`obj_probe` Lean executables via
-- `moreLinkArgs` (see lean/lakefile.lean). The C wrapper resolving
-- the `@[extern]` symbols below is
-- c_src/thirdparty/ffi/cassie_geogram_ffi.cpp.
--
-- The minimum surface needed from the geogram side for the
-- cycle-detect → triangulate → fair pipeline:
--   - construct a 2D boundary polyline as a constrained delaunay
--   - refine to a target edge length
--   - extract vertices + triangles
--
-- `cassie_triangulator::triangulate(boundary, edge_length)` already
-- implements this in C++ — the FFI is a thin re-exposure of that entry
-- plus the geogram bindings the wrapper relies on.

namespace CassieGeogram

/-- Opaque handle for a heap-allocated geogram Delaunay context. -/
abbrev DelaunayHandle := USize

/-- Build a constrained Delaunay from a flat boundary polyline
    (xyz xyz ...). The input must be a closed loop — the last vertex
    implicitly connects back to the first. `target_edge_length` sets
    the BDEL refinement budget. -/
@[extern "cassie_geogram_delaunay_from_boundary"]
opaque delaunayFromBoundary (n_pts : USize) (positions : @& FloatArray)
    (targetEdgeLength : Float) : IO DelaunayHandle

/-- Release a Delaunay handle. -/
@[extern "cassie_geogram_delaunay_free"]
opaque delaunayFree (d : DelaunayHandle) : IO Unit

/-- Number of vertices in the produced triangulation. -/
@[extern "cassie_geogram_delaunay_n_vertices"]
opaque nVertices (d : DelaunayHandle) : IO USize

/-- Number of triangles in the produced triangulation. -/
@[extern "cassie_geogram_delaunay_n_triangles"]
opaque nTriangles (d : DelaunayHandle) : IO USize

/-- Copy positions back into a flat float array (xyz xyz ...). The
    `out` array must be at least `n_vertices d * 3` floats long. -/
@[extern "cassie_geogram_delaunay_get_positions"]
opaque getPositions (d : DelaunayHandle) (out : FloatArray) : IO FloatArray

/-- Copy triangle vertex indices back. The `out` ByteArray must be at
    least `n_triangles d * 3 * 4` bytes long. -/
@[extern "cassie_geogram_delaunay_get_triangles"]
opaque getTriangles (d : DelaunayHandle) (out : ByteArray) : IO ByteArray

end CassieGeogram
