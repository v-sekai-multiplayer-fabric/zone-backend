-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- Root of `CassieGeogram` — no vendored C++ library, no @[extern]
-- symbols, but also no working pure-Lean constrained Delaunay: a
-- from-scratch attempt (ear clipping + Lawson edge flips) was dropped
-- for not matching geogram's real O(n log n) performance on this
-- pipeline's actual boundary sizes. `Delaunay.lean` now type-checks
-- but throws at call time — see its module doc.
--
-- Sibling to `CassieAvbd` (proofs + Slang) and `CassiePmp` (PMP
-- surface mesh remeshing/smoothing, which IS a working pure-Lean
-- reimplementation).

import CassieGeogram.Delaunay
