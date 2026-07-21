-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- `CassieObj` — Wavefront OBJ loader, pure Lean (no C++ FFI).
--
-- Replaces the upstream `cassie_obj_ffi.cpp` handle/extern pair with a
-- plain in-process handle table (`IO.Ref`) over a Lean-native `Mesh`
-- structure. The public API (`load`/`free`/`nVertices`/`nFaces`/
-- `getPositions`/`getFaces`) is unchanged so `ObjProbe.lean` and any
-- other caller need no edits.
--
-- Parser scope matches the original FFI's documented subset: `v x y z`
-- and `f i j k` (with the standard `i/j/k`, `i//k`, `i/j` slash
-- variants -- only the leading vertex index of each `f` token is used,
-- matching Wavefront OBJ where the vertex index always comes first),
-- fan-triangulating faces of degree > 3. No normals/UVs/materials/
-- groups/`o`/`g` -- out of scope, same as upstream.

namespace CassieObj

/-- A parsed OBJ mesh: flat position list and triangle index list
    (post fan-triangulation). -/
structure Mesh where
  positions : Array Float   -- xyz xyz ...
  faces     : Array UInt32  -- a b c a b c ...
  deriving Inhabited

/-- Opaque handle -- an index into the process-global mesh table below.
    Kept as `USize` to match the original FFI's handle type exactly. -/
abbrev MeshHandle := USize

/-- Process-global table of loaded meshes, indexed by handle. A `none`
    slot is a freed handle. -/
initialize meshTable : IO.Ref (Array (Option Mesh)) ← IO.mkRef #[]

/-- The empty mesh a failed/degenerate load returns -- callers check
    `nVertices h = 0` exactly as the FFI version documented. -/
def emptyMesh : Mesh := { positions := #[], faces := #[] }

/-- Parse the leading vertex index out of one `f` face-vertex token:
    `"i"`, `"i/j"`, `"i//k"`, or `"i/j/k"` -- the vertex index is
    always the first slash-separated field. OBJ indices are 1-based;
    this returns the 0-based index. Negative (relative) indices are
    not supported (same scope cut as upstream). -/
def parseFaceVertex (tok : String) : Option Nat :=
  match tok.splitOn "/" with
  | idxStr :: _ => idxStr.toNat?.map (· - 1)
  | [] => none

/-- Parse a decimal float (`[+-]?digits('.'digits)?([eE][+-]?digits)?`).
    Lean's stdlib ships no `String.toFloat?` -- OBJ's `v` lines need
    this to read `x y z`. -/
def parseFloat (s : String) : Option Float := Id.run do
  let cs := s.toList
  let mut i := 0
  let n := cs.length
  let arr := cs.toArray
  let isDigit := fun (c : Char) => '0' ≤ c && c ≤ '9'
  let mut neg := false
  if i < n && (arr[i]! == '-' || arr[i]! == '+') then
    neg := arr[i]! == '-'
    i := i + 1
  let start := i
  let mut intVal : Nat := 0
  while i < n && isDigit arr[i]! do
    intVal := intVal * 10 + (arr[i]!.toNat - '0'.toNat)
    i := i + 1
  let mut frac : Float := 0.0
  if i < n && arr[i]! == '.' then
    i := i + 1
    let mut scale : Float := 0.1
    while i < n && isDigit arr[i]! do
      frac := frac + scale * (arr[i]!.toNat - '0'.toNat).toFloat
      scale := scale / 10.0
      i := i + 1
  let mut mantissa : Float := intVal.toFloat + frac
  if neg then mantissa := -mantissa
  -- Optional exponent.
  let mut expMag : Nat := 0
  let mut expNeg := false
  let mut hasExp := false
  if i < n && (arr[i]! == 'e' || arr[i]! == 'E') then
    let save := i
    let mut j := i + 1
    if j < n && (arr[j]! == '-' || arr[j]! == '+') then
      expNeg := arr[j]! == '-'
      j := j + 1
    let expStart := j
    let mut e : Nat := 0
    while j < n && isDigit arr[j]! do
      e := e * 10 + (arr[j]!.toNat - '0'.toNat)
      j := j + 1
    if j > expStart then
      hasExp := true
      expMag := e
      i := j
    else
      i := save
  if start == i && !hasExp then
    return none  -- no digits were consumed anywhere: not a number
  let result :=
    if hasExp then
      let expFloat : Float := if expNeg then -(expMag.toFloat) else expMag.toFloat
      mantissa * (Float.exp (expFloat * Float.log 10.0))
    else
      mantissa
  return some result

/-- Fan-triangulate a polygon's vertex-index list (already 0-based):
    `[v0, v1, v2, v3, ...] -> [(v0,v1,v2), (v0,v2,v3), ...]`. -/
def fanTriangulate (idxs : Array Nat) : Array (Nat × Nat × Nat) := Id.run do
  if idxs.size < 3 then return #[]
  let v0 := idxs[0]!
  let mut out : Array (Nat × Nat × Nat) := #[]
  for i in [1 : idxs.size - 1] do
    out := out.push (v0, idxs[i]!, idxs[i + 1]!)
  return out

/-- Parse OBJ text into a `Mesh`. Blank lines, comments (`#`), and any
    line whose keyword isn't `v`/`f` are ignored. -/
def parseObj (text : String) : Mesh := Id.run do
  let mut positions : Array Float := #[]
  let mut faces : Array UInt32 := #[]
  for line0 in text.splitOn "\n" do
    let line := line0.trimAscii.toString
    if line.isEmpty || line.startsWith "#" then continue
    let toks := (line.splitOn " ").filter (· ≠ "")
    match toks with
    | [] => pure ()
    | kw :: rest =>
      if kw == "v" then
        match rest with
        | xs :: ys :: zs :: _ =>
          match parseFloat xs, parseFloat ys, parseFloat zs with
          | some x, some y, some z =>
            positions := positions.push x |>.push y |>.push z
          | _, _, _ => pure ()
        | _ => pure ()
      else if kw == "f" then
        let idxs := (rest.filterMap parseFaceVertex).toArray
        for (a, b, c) in fanTriangulate idxs do
          faces := faces.push a.toUInt32 |>.push b.toUInt32 |>.push c.toUInt32
      else
        pure ()
  return { positions, faces }

/-- Parse an OBJ file from `path` and return its heap handle. If the
    file can't be opened, returns a handle whose vertex/face counts are
    zero -- matches the original FFI's failure contract exactly (no
    exception). -/
def load (path : String) : IO MeshHandle := do
  let mesh ←
    try
      let text ← IO.FS.readFile path
      pure (parseObj text)
    catch _ =>
      pure emptyMesh
  let table ← meshTable.get
  let handle := table.size
  meshTable.set (table.push (some mesh))
  return handle.toUSize

/-- Release a mesh handle. -/
def free (h : MeshHandle) : IO Unit := do
  let table ← meshTable.get
  let i := h.toNat
  if i < table.size then
    meshTable.set (table.set! i none)

/-- Look up a handle, defaulting to the empty mesh for a freed/invalid
    handle (mirrors how the original C++ handle would dereference a
    zeroed struct rather than crash). -/
def deref (h : MeshHandle) : IO Mesh := do
  let table ← meshTable.get
  let i := h.toNat
  return (table.getD i none).getD emptyMesh

/-- Number of vertices in the loaded mesh. -/
def nVertices (h : MeshHandle) : IO USize := do
  return ((← deref h).positions.size / 3).toUSize

/-- Number of triangle faces (after fan triangulation of any ngons). -/
def nFaces (h : MeshHandle) : IO USize := do
  return ((← deref h).faces.size / 3).toUSize

/-- Copy vertex positions into a flat float array (xyz xyz ...). -/
def getPositions (h : MeshHandle) (out : FloatArray) : IO FloatArray := do
  let mesh ← deref h
  let mut out := out
  for i in [:mesh.positions.size] do
    out := out.set! i mesh.positions[i]!
  return out

/-- Copy triangle vertex indices into a ByteArray of little-endian
    uint32s (3 per face). -/
def getFaces (h : MeshHandle) (out : ByteArray) : IO ByteArray := do
  let mesh ← deref h
  let mut out := out
  for i in [:mesh.faces.size] do
    let v := mesh.faces[i]!
    out := out.set! (4 * i)     (UInt8.ofNat (v.toNat &&& 0xff))
    out := out.set! (4 * i + 1) (UInt8.ofNat ((v.toNat >>> 8) &&& 0xff))
    out := out.set! (4 * i + 2) (UInt8.ofNat ((v.toNat >>> 16) &&& 0xff))
    out := out.set! (4 * i + 3) (UInt8.ofNat ((v.toNat >>> 24) &&& 0xff))
  return out

end CassieObj
