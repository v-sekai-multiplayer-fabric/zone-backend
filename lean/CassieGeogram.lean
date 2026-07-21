-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- Root of `CassieGeogram` — Lean FFI bindings into the vendored
-- (real) geogram library at c_src/thirdparty/geogram. Scope:
--   - constrained Delaunay (BDEL) construction from a 2D boundary
--   - refinement to a target edge length
-- Matches the surface area `cassie_triangulator` already implements in
-- C++; Lean side is a thin re-exposure for the cycle-detect pipeline
-- (boundary loop → Delaunay → PMP smoothing).
--
-- Sibling to `CassieAvbd` (proofs + Slang) and `CassiePmp` (PMP
-- surface mesh remeshing/smoothing — also real vendored C++ via FFI).

import CassieGeogram.Delaunay
