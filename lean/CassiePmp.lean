-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- Root of `CassiePmp` — Lean FFI bindings into the vendored (real)
-- PMP library at c_src/thirdparty/pmp, scoped to the operations the
-- CASSIE surface-fairing pipeline needs: `uniform_remeshing` and
-- `implicit_smoothing` on a `pmp::SurfaceMesh` with `e:feature`
-- boundary preservation.
--
-- Sibling to `CassieAvbd` (the proof + Slang library) and
-- `CassieGeogram` (Delaunay / BDEL triangulator bindings — also real
-- vendored C++ via FFI).

import CassiePmp.Mesh
