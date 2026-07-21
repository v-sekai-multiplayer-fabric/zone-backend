-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 K. S. Ernest (iFire) Lee
import Lake
open Lake DSL

package «lockstep» where

require «lean-capstone» from git
  "https://github.com/fire/lean-capstone" @ "main"

-- LockstepDeterminism.lean (RFD 0043's spec) is intentionally NOT a
-- target of this package -- it has no dependencies of its own and
-- keeps working exactly as documented (`lean --run
-- lean/LockstepDeterminism.lean`), independent of this lakefile.

-- RFD 0043's follow-on: check_no_fma.lean, using this org's own
-- fire/lean-capstone (a Lean4 Capstone binding) instead of shelling out
-- to riscv-none-elf-objdump + scripts/check_no_fma.py's regex parsing --
-- reuses an owned asset and stays in the same Lean4 tooling this
-- pipeline already depends on end to end.
lean_exe check_no_fma where
  root := `CheckNoFma
  moreLinkArgs := #["-Wl,--start-group",
    ".lake/packages/lean-capstone/thirdparty/capstone/lib/libcapstone.a",
    "-Wl,--end-group"]
