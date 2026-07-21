-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- `CassieGeogram.Delaunay` — was a pure-Lean constrained Delaunay
-- triangulation (ear clipping + Lawson edge flips), attempted as a
-- replacement for the upstream geogram FFI. Dropped: on the actual
-- hat-fixture boundaries this pipeline produces (hundreds of points),
-- the O(n³) ear-clip/flip approach didn't come close to geogram's
-- real O(n log n) sweep/incremental algorithm — `lake exe cycle_patch`
-- against real fixture data timed out where geogram-backed
-- `cassie_triangulator` returns quickly. Rather than ship a
-- reimplementation that's honest about correctness but not about
-- performance, this is now an explicit "not provided" stub: it
-- type-checks (so the rest of the `CyclePatch`/`SurfaceFair` pipeline
-- still builds) but throws at call time.
--
-- A real replacement needs an actual O(n log n) planar triangulation
-- algorithm (e.g. a proper incremental/sweep-line constrained
-- Delaunay, not ear clipping) — that's a distinct, larger task from
-- "port the Lean specs," not attempted here. Until then, anything
-- that needs real triangulated output should link the original
-- geogram FFI, not this module.

namespace CassieGeogram

structure Tri where
  a : Nat
  b : Nat
  c : Nat
  deriving Inhabited, Repr

structure DelaunayMesh where
  positions : Array (Float × Float × Float)
  boundaryCount : Nat
  tris : Array Tri
  deriving Inhabited

abbrev DelaunayHandle := USize

initialize delaunayTable : IO.Ref (Array (Option DelaunayMesh)) ← IO.mkRef #[]

def emptyMesh : DelaunayMesh := { positions := #[], boundaryCount := 0, tris := #[] }

/-- Not implemented — see module doc. Always throws. -/
def delaunayFromBoundary (_nPts : USize) (_positions : FloatArray)
    (_targetEdgeLength : Float) : IO DelaunayHandle :=
  throw <| IO.userError
    "CassieGeogram.Delaunay: no pure-Lean implementation (dropped for performance -- see module doc); link the real geogram FFI for triangulated output"

def delaunayFree (d : DelaunayHandle) : IO Unit := do
  let table ← delaunayTable.get
  let i := d.toNat
  if i < table.size then
    delaunayTable.set (table.set! i none)

def deref (d : DelaunayHandle) : IO DelaunayMesh := do
  let table ← delaunayTable.get
  let i := d.toNat
  return (table.getD i none).getD emptyMesh

def nVertices (d : DelaunayHandle) : IO USize := do
  return (← deref d).positions.size.toUSize

def nTriangles (d : DelaunayHandle) : IO USize := do
  return (← deref d).tris.size.toUSize

def getPositions (d : DelaunayHandle) (out : FloatArray) : IO FloatArray := do
  let mesh ← deref d
  let mut out := out
  for i in [:mesh.positions.size] do
    let (x, y, z) := mesh.positions[i]!
    out := out.set! (3*i) x |>.set! (3*i+1) y |>.set! (3*i+2) z
  return out

def getTriangles (d : DelaunayHandle) (out : ByteArray) : IO ByteArray := do
  let mesh ← deref d
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

end CassieGeogram
