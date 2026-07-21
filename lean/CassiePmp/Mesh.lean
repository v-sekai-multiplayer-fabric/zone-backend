-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- `CassiePmp.Mesh` — PMP SurfaceMesh FFI.
--
-- Restores the original upstream design (a pure-Lean reimplementation
-- was tried first, but the equivalent geogram module needed the same
-- reversal for performance, and this stays consistent with it): real
-- PMP (MIT), vendored at c_src/thirdparty/pmp (plus Eigen, MPL2, at
-- c_src/thirdparty/eigen -- PMP's own matrix/vector types need it,
-- independent of CASSIE's own C++ solver code which does not), built
-- by c_src/thirdparty/build_cassie_native.sh into
-- c_src/thirdparty/build/libcassie_native.a and linked into the
-- `cycle_patch`/`surface_fair` Lean executables via `moreLinkArgs`
-- (see lean/lakefile.lean). The C wrapper resolving the `@[extern]`
-- symbols below is c_src/thirdparty/ffi/cassie_pmp_ffi.cpp.
--
-- Scope, matching the operations the CASSIE surface-fairing pipeline
-- needs:
--   - construct from a flat (positions, triangles) pair
--   - feature-flag the boundary so split_long_edges keeps the polyline
--     geometry intact
--   - `pmp::uniform_remeshing` (target_edge_length, iters, use_projection)
--   - `pmp::implicit_smoothing` (timestep, hold_boundary)
--   - extract back to (positions, triangles)

namespace CassiePmp

/-- Opaque handle for a heap-allocated `pmp::SurfaceMesh`. The C side
    owns the object; `meshFree` releases it. -/
abbrev MeshHandle := USize

/-- Build a `pmp::SurfaceMesh` from flat (positions, triangles). The
    `positions` array holds `n_verts * 3` floats (xyz xyz ...). The
    `tris` array holds `n_tris * 3` uints (a b c | a b c | ...). -/
@[extern "cassie_pmp_mesh_new"]
opaque meshNew (n_verts : USize) (positions : @& FloatArray)
    (n_tris : USize) (tris : @& ByteArray) : IO MeshHandle

/-- Release a mesh allocated by `meshNew`. -/
@[extern "cassie_pmp_mesh_free"]
opaque meshFree (m : MeshHandle) : IO Unit

/-- Mark every boundary edge as `e:feature` so `split_long_edges`
    keeps the polyline curve intact during remeshing. -/
@[extern "cassie_pmp_mark_boundary_feature"]
opaque markBoundaryFeature (m : MeshHandle) : IO Unit

/-- `pmp::uniform_remeshing(mesh, target_edge_length, iterations,
    use_projection)`. Re-tessellates to roughly uniform edge length;
    when `use_projection = true`, refined vertices are projected back
    onto the input surface. -/
@[extern "cassie_pmp_uniform_remeshing"]
opaque uniformRemeshing (m : MeshHandle) (targetEdgeLength : Float)
    (iters : USize) (useProjection : Bool) : IO Unit

/-- `pmp::implicit_smoothing(mesh, timestep, hold_boundary)`.
    Backward-Euler Laplacian smoothing — pulls each interior vertex
    toward the average of its neighbors by a fraction set by
    `timestep`. Boundary feature edges stay pinned when
    `hold_boundary = true`. This is the "give the patch some volume"
    operator for the cycle-detect → triangulate → fair pipeline. -/
@[extern "cassie_pmp_implicit_smoothing"]
opaque implicitSmoothing (m : MeshHandle) (timestep : Float)
    (holdBoundary : Bool) : IO Unit

/-- Number of vertices currently in the mesh. -/
@[extern "cassie_pmp_n_vertices"]
opaque nVertices (m : MeshHandle) : IO USize

/-- Number of faces currently in the mesh. -/
@[extern "cassie_pmp_n_faces"]
opaque nFaces (m : MeshHandle) : IO USize

/-- Copy positions back into a flat float array (xyz xyz ...). The
    `out` array must be at least `n_vertices m * 3` floats long. -/
@[extern "cassie_pmp_get_positions"]
opaque getPositions (m : MeshHandle) (out : FloatArray) : IO FloatArray

/-- Copy triangle indices back into a flat uint array (a b c | ...).
    The `out` ByteArray must be at least `n_faces m * 3 * 4` bytes
    long. Returns the populated ByteArray. -/
@[extern "cassie_pmp_get_triangles"]
opaque getTriangles (m : MeshHandle) (out : ByteArray) : IO ByteArray

end CassiePmp
