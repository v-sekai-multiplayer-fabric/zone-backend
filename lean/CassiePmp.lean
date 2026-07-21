-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- Root of `CassiePmp` — pure-Lean replacement for the original PMP/
-- eigen FFI (no vendored C++ library, no @[extern] symbols), scoped
-- to the operations the CASSIE surface-fairing pipeline needs:
-- `uniformRemeshing` and `implicitSmoothing` on a `Mesh` with
-- boundary-feature preservation. See `Mesh.lean` for the documented
-- divergences from real PMP's exact algorithms.
--
-- Sibling to `CassieAvbd` (the proof + Slang library) and
-- `CassieGeogram` (Delaunay triangulation — also reimplemented in
-- pure Lean).

import CassiePmp.Mesh
