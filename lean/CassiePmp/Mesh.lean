-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- `CassiePmp.Mesh` — surface mesh remeshing/smoothing, pure Lean (no
-- PMP/eigen FFI).
--
-- Replaces the upstream `cassie_pmp_ffi.cpp`/`pmp::SurfaceMesh`
-- binding for the two operations the cycle-detect → triangulate →
-- fair pipeline actually calls: `uniformRemeshing` and
-- `implicitSmoothing`, plus `markBoundaryFeature`.
--
-- Documented divergences from real PMP (both deliberate scope cuts,
-- not oversights):
--   - `uniformRemeshing` here only splits over-length edges, flips
--     edges toward the target valence (6 interior / 4 boundary), and
--     tangentially relaxes vertices — it does NOT collapse
--     under-length edges. PMP's real remesher also decimates, keeping
--     element count roughly stable across repeated calls; this
--     remesher's element count is monotonically non-decreasing. This
--     is a real limitation, but not one that matters for this
--     pipeline's actual use (`SurfaceFair`/`CyclePatch` call it once
--     on a freshly ear-clipped/Delaunay patch, not repeatedly on an
--     already-fine mesh).
--   - `implicitSmoothing` approximates PMP's backward-Euler linear
--     solve with bounded Gauss-Seidel sweeps rather than a direct
--     sparse factorization (PMP uses Eigen's `SimplicialLDLT` on the
--     cotangent Laplacian) — same fixed-point target, uniform
--     (not cotangent) weights, iterative instead of direct.
--   - `useProjection` on `uniformRemeshing` has no separate reference
--     surface to project onto (PMP projects relaxed vertices back
--     onto the pre-remesh surface via an AABB tree); this
--     implementation's relaxation already stays on the current
--     surface's local tangent plane, so `useProjection` is accepted
--     for API compatibility but is a no-op beyond that.

namespace CassiePmp

structure Tri where
  a : Nat
  b : Nat
  c : Nat
  deriving Inhabited, Repr

structure Mesh where
  positions : Array (Float × Float × Float)
  tris : Array Tri
  /-- Vertices on a marked feature (boundary) edge — held fixed by
      smoothing/relaxation when `holdBoundary`/pinning is requested. -/
  featureVerts : Array Bool
  deriving Inhabited

abbrev MeshHandle := USize

initialize meshTable : IO.Ref (Array (Option Mesh)) ← IO.mkRef #[]

def emptyMesh : Mesh := { positions := #[], tris := #[], featureVerts := #[] }

-- ══════════════════════════════════════════════════════════════════
-- Topology helpers
-- ══════════════════════════════════════════════════════════════════

/-- Every undirected edge, paired with how many triangles touch it —
    an edge with exactly one incident triangle is a boundary edge.
    A plain association array (mesh sizes here are small, so linear
    lookup is fine — avoids depending on a hash-map import). -/
def edgeIncidence (tris : Array Tri) : Array ((Nat × Nat) × Nat) := Id.run do
  let mut m : Array ((Nat × Nat) × Nat) := #[]
  for t in tris do
    for (u, v) in #[(t.a, t.b), (t.b, t.c), (t.c, t.a)] do
      let key := if u < v then (u, v) else (v, u)
      match m.findIdx? (fun kv => kv.1 == key) with
      | some idx => m := m.set! idx (key, m[idx]!.2 + 1)
      | none => m := m.push (key, 1)
  return m

/-- Lookup helper for `edgeIncidence`'s association array. -/
def incidenceOf (m : Array ((Nat × Nat) × Nat)) (key : Nat × Nat) : Nat :=
  match m.find? (fun kv => kv.1 == key) with
  | some kv => kv.2
  | none => 0

/-- 1-ring neighbor list per vertex (as a plain Array indexed by
    vertex id, since triangle vertex ids are dense `0..nVerts-1`). -/
def oneRings (nVerts : Nat) (tris : Array Tri) : Array (Array Nat) := Id.run do
  let mut rings : Array (Array Nat) := Array.replicate nVerts #[]
  let addEdge := fun (rings : Array (Array Nat)) (u v : Nat) =>
    let ring := rings[u]!
    if ring.contains v then rings else rings.set! u (ring.push v)
  let mut r := rings
  for t in tris do
    for (u, v) in #[(t.a, t.b), (t.b, t.a), (t.b, t.c), (t.c, t.b), (t.c, t.a), (t.a, t.c)] do
      r := addEdge r u v
  return r

/-- Find the other triangle across edge `(u,v)` from triangle index
    `skipIdx`, and the vertex opposite that edge in it. `none` if
    `(u,v)` is a boundary edge (only one incident triangle). -/
def findOpposite (tris : Array Tri) (skipIdx u v : Nat) : Option (Nat × Nat) := Id.run do
  for j in [:tris.size] do
    if j ≠ skipIdx then
      let t := tris[j]!
      let vs := #[t.a, t.b, t.c]
      if vs.contains u && vs.contains v then
        let opp := (vs.filter (fun x => x ≠ u && x ≠ v))[0]!
        return some (j, opp)
  return none

-- ══════════════════════════════════════════════════════════════════
-- Public API (matches the original FFI signatures)
-- ══════════════════════════════════════════════════════════════════

/-- Build a `Mesh` from flat (positions, triangles). -/
def meshNew (nVerts : USize) (positions : FloatArray) (nTris : USize)
    (tris : ByteArray) : IO MeshHandle := do
  let nv := nVerts.toNat
  let nt := nTris.toNat
  let mut pts : Array (Float × Float × Float) := #[]
  for i in [:nv] do
    pts := pts.push (positions[3*i]!, positions[3*i+1]!, positions[3*i+2]!)
  let readU32 := fun (off : Nat) =>
    tris[off]!.toNat ||| (tris[off+1]!.toNat <<< 8) |||
      (tris[off+2]!.toNat <<< 16) ||| (tris[off+3]!.toNat <<< 24)
  let mut triArr : Array Tri := #[]
  for i in [:nt] do
    triArr := triArr.push {
      a := readU32 (12*i), b := readU32 (12*i + 4), c := readU32 (12*i + 8) }
  let mesh : Mesh := { positions := pts, tris := triArr, featureVerts := Array.replicate nv false }
  let table ← meshTable.get
  let handle := table.size
  meshTable.set (table.push (some mesh))
  return handle.toUSize

/-- Release a mesh allocated by `meshNew`. -/
def meshFree (m : MeshHandle) : IO Unit := do
  let table ← meshTable.get
  let i := m.toNat
  if i < table.size then
    meshTable.set (table.set! i none)

def deref (m : MeshHandle) : IO Mesh := do
  let table ← meshTable.get
  let i := m.toNat
  return (table.getD i none).getD emptyMesh

def update (m : MeshHandle) (f : Mesh → Mesh) : IO Unit := do
  let table ← meshTable.get
  let i := m.toNat
  if i < table.size then
    match table[i]! with
    | some mesh => meshTable.set (table.set! i (some (f mesh)))
    | none => pure ()

/-- Mark every boundary edge's endpoints as feature (pinned) vertices,
    so `uniformRemeshing`/`implicitSmoothing` keep them fixed when
    asked to hold the boundary. -/
def markBoundaryFeature (m : MeshHandle) : IO Unit := do
  update m fun mesh => Id.run do
    let inc := edgeIncidence mesh.tris
    let mut feat := Array.replicate mesh.positions.size false
    for t in mesh.tris do
      for (u, v) in #[(t.a, t.b), (t.b, t.c), (t.c, t.a)] do
        let key := if u < v then (u, v) else (v, u)
        if incidenceOf inc key = 1 then
          feat := feat.set! u true
          feat := feat.set! v true
    return { mesh with featureVerts := feat }

-- ══════════════════════════════════════════════════════════════════
-- Implicit (approximate backward-Euler) Laplacian smoothing
-- ══════════════════════════════════════════════════════════════════

/-- One Gauss-Seidel sweep toward solving `(I + timestep·L) x = x₀`
    for the uniform graph Laplacian `L = deg(v)·x_v - Σ neighbors`,
    i.e. per-vertex fixed point
    `x_v = (x₀_v + timestep · Σ_neighbors x_n) / (1 + timestep · deg(v))`.
    Pinned vertices (feature, when `holdBoundary`) are left unchanged. -/
def smoothSweep (positions0 positions : Array (Float × Float × Float))
    (rings : Array (Array Nat)) (featureVerts : Array Bool)
    (timestep : Float) (holdBoundary : Bool) : Array (Float × Float × Float) := Id.run do
  let mut pos := positions
  for v in [:pos.size] do
    if holdBoundary && featureVerts.getD v false then
      continue
    let ring := rings[v]!
    if ring.isEmpty then continue
    let deg := ring.size.toFloat
    let mut sx := 0.0; let mut sy := 0.0; let mut sz := 0.0
    for n in ring do
      let (nx, ny, nz) := pos[n]!
      sx := sx + nx; sy := sy + ny; sz := sz + nz
    let (x0, y0, z0) := positions0[v]!
    let denom := 1.0 + timestep * deg
    pos := pos.set! v
      ((x0 + timestep * sx) / denom, (y0 + timestep * sy) / denom, (z0 + timestep * sz) / denom)
  return pos

/-- `pmp::implicit_smoothing(mesh, timestep, hold_boundary)` — pulls
    each free vertex toward its neighbors' (weighted) average by a
    backward-Euler step, approximated via bounded Gauss-Seidel. -/
def implicitSmoothing (m : MeshHandle) (timestep : Float) (holdBoundary : Bool) : IO Unit := do
  update m fun mesh => Id.run do
    let rings := oneRings mesh.positions.size mesh.tris
    let mut pos := mesh.positions
    for _ in [:25] do
      pos := smoothSweep mesh.positions pos rings mesh.featureVerts timestep holdBoundary
    return { mesh with positions := pos }

-- ══════════════════════════════════════════════════════════════════
-- Uniform remeshing (split + valence-equalizing flip + relax; see
-- module doc for the documented no-collapse divergence)
-- ══════════════════════════════════════════════════════════════════

def edgeLen (p q : Float × Float × Float) : Float :=
  let (px, py, pz) := p
  let (qx, qy, qz) := q
  Float.sqrt ((px-qx)*(px-qx) + (py-qy)*(py-qy) + (pz-qz)*(pz-qz))

/-- Split every edge longer than `4/3 · targetLen` at its midpoint. -/
partial def splitLongEdges (mesh : Mesh) (targetLen : Float) : Mesh := Id.run do
  let mut best : Option (Nat × Nat) := none
  for i in [:mesh.tris.size] do
    let t := mesh.tris[i]!
    for (u, v) in #[(t.a, t.b), (t.b, t.c), (t.c, t.a)] do
      if edgeLen mesh.positions[u]! mesh.positions[v]! > (4.0/3.0) * targetLen then
        best := some (u, v)
  match best with
  | none => return mesh
  | some (u, v) =>
    let (px, py, pz) := mesh.positions[u]!
    let (qx, qy, qz) := mesh.positions[v]!
    let mid := ((px+qx)/2.0, (py+qy)/2.0, (pz+qz)/2.0)
    let newIdx := mesh.positions.size
    let mut positions := mesh.positions.push mid
    let mut tris : Array Tri := #[]
    for t in mesh.tris do
      let vs := #[t.a, t.b, t.c]
      if vs.contains u && vs.contains v then
        let apex := (vs.filter (fun x => x ≠ u && x ≠ v))[0]!
        if (t.a = u && t.b = v) || (t.b = u && t.c = v) || (t.c = u && t.a = v) then
          tris := tris.push { a := u, b := newIdx, c := apex }
          tris := tris.push { a := newIdx, b := v, c := apex }
        else
          tris := tris.push { a := v, b := newIdx, c := apex }
          tris := tris.push { a := newIdx, b := u, c := apex }
      else
        tris := tris.push t
    let uWasFeature := mesh.featureVerts.getD u false
    let vWasFeature := mesh.featureVerts.getD v false
    let featureVerts := mesh.featureVerts.push (uWasFeature && vWasFeature)
    return splitLongEdges { positions, tris, featureVerts } targetLen

/-- One bounded pass of valence-equalizing edge flips (target valence:
    6 interior, 4 boundary), skipping edges whose endpoints are both
    feature vertices (treated as constrained, mirroring PMP's
    feature-respecting remesh). -/
def natDiff (a b : Nat) : Nat := if a ≥ b then a - b else b - a

def equalizeValence (mesh : Mesh) (maxPasses : Nat := 10) : Mesh := Id.run do
  let mut tris := mesh.tris
  let targetValence := fun (x : Nat) =>
    if mesh.featureVerts.getD x false then 4 else 6
  for _ in [:maxPasses] do
    let valence := Id.run do
      let mut v := Array.replicate mesh.positions.size 0
      for t in tris do
        for x in #[t.a, t.b, t.c] do
          v := v.set! x ((v[x]!) + 1)
      return v
    let mut changed := false
    for i in [:tris.size] do
      let t := tris[i]!
      for (u, v, opp1) in #[(t.a, t.b, t.c), (t.b, t.c, t.a), (t.c, t.a, t.b)] do
        if !(mesh.featureVerts.getD u false && mesh.featureVerts.getD v false) then
          match findOpposite tris i u v with
          | some (j, opp2) =>
            let before :=
              natDiff valence[u]! (targetValence u) + natDiff valence[v]! (targetValence v) +
              natDiff valence[opp1]! (targetValence opp1) + natDiff valence[opp2]! (targetValence opp2)
            let after :=
              natDiff (valence[u]! - 1) (targetValence u) + natDiff (valence[v]! - 1) (targetValence v) +
              natDiff (valence[opp1]! + 1) (targetValence opp1) + natDiff (valence[opp2]! + 1) (targetValence opp2)
            if after < before then
              tris := tris.set! i { a := u, b := opp1, c := opp2 }
              tris := tris.set! j { a := v, b := opp2, c := opp1 }
              changed := true
          | none => pure ()
    if !changed then break
  return { mesh with tris := tris }

/-- Tangential relaxation: move each free vertex toward its 1-ring
    centroid, projected onto the vertex's local (Newell) normal plane
    so the surface doesn't drift off its own shape. `useProjection` is
    accepted for API compatibility (see module doc). -/
def relax (mesh : Mesh) (_useProjection : Bool) : Mesh := Id.run do
  let rings := oneRings mesh.positions.size mesh.tris
  let mut pos := mesh.positions
  for v in [:pos.size] do
    if mesh.featureVerts.getD v false then continue
    let ring := rings[v]!
    if ring.size < 3 then continue
    let (vx, vy, vz) := pos[v]!
    -- Newell's method for an approximate vertex normal from the ring.
    let mut nx := 0.0; let mut ny := 0.0; let mut nz := 0.0
    let mut cx := 0.0; let mut cy := 0.0; let mut cz := 0.0
    for k in [:ring.size] do
      let (ax, ay, az) := pos[ring[k]!]!
      let (bx, byy, bz) := pos[ring[(k + 1) % ring.size]!]!
      nx := nx + (ay - byy) * (az + bz)
      ny := ny + (az - bz) * (ax + bx)
      nz := nz + (ax - bx) * (ay + byy)
      cx := cx + ax; cy := cy + ay; cz := cz + az
    let centroid := (cx / ring.size.toFloat, cy / ring.size.toFloat, cz / ring.size.toFloat)
    let nlen := Float.sqrt (nx*nx + ny*ny + nz*nz)
    let (cnx, cny, cnz) := centroid
    let dx := cnx - vx; let dy := cny - vy; let dz := cnz - vz
    if nlen < 1e-12 then
      pos := pos.set! v centroid
    else
      let (ux, uy, uz) := (nx/nlen, ny/nlen, nz/nlen)
      let dot := dx*ux + dy*uy + dz*uz
      -- Displacement with the normal component removed — stays
      -- tangent to the local surface instead of drifting along it.
      pos := pos.set! v (vx + (dx - dot*ux), vy + (dy - dot*uy), vz + (dz - dot*uz))
  return { mesh with positions := pos }

/-- `pmp::uniform_remeshing(mesh, target_edge_length, iterations,
    use_projection)` — see module doc for the documented divergence
    (no edge collapse). -/
def uniformRemeshing (m : MeshHandle) (targetEdgeLength : Float) (iters : USize)
    (useProjection : Bool) : IO Unit := do
  update m fun mesh => Id.run do
    let mut mesh := mesh
    for _ in [:iters.toNat] do
      mesh := splitLongEdges mesh targetEdgeLength
      mesh := equalizeValence mesh
      mesh := relax mesh useProjection
    return mesh

/-- Number of vertices currently in the mesh. -/
def nVertices (m : MeshHandle) : IO USize := do
  return (← deref m).positions.size.toUSize

/-- Number of faces currently in the mesh. -/
def nFaces (m : MeshHandle) : IO USize := do
  return (← deref m).tris.size.toUSize

/-- Copy positions back into a flat float array (xyz xyz ...). -/
def getPositions (m : MeshHandle) (out : FloatArray) : IO FloatArray := do
  let mesh ← deref m
  let mut out := out
  for i in [:mesh.positions.size] do
    let (x, y, z) := mesh.positions[i]!
    out := out.set! (3*i) x |>.set! (3*i+1) y |>.set! (3*i+2) z
  return out

/-- Copy triangle indices back into a flat little-endian uint32 array. -/
def getTriangles (m : MeshHandle) (out : ByteArray) : IO ByteArray := do
  let mesh ← deref m
  let mut out := out
  for i in [:mesh.tris.size] do
    let t := mesh.tris[i]!
    for (slot, v) in #[(0, t.a), (1, t.b), (2, t.c)] do
      let off := 12*i + 4*slot
      out := out.set! off (UInt8.ofNat (v &&& 0xff))
      out := out.set! (off+1) (UInt8.ofNat ((v >>> 8) &&& 0xff))
      out := out.set! (off+2) (UInt8.ofNat ((v >>> 16) &&& 0xff))
      out := out.set! (off+3) (UInt8.ofNat ((v >>> 24) &&& 0xff))
  return out

end CassiePmp
