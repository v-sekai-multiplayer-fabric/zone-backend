/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 K. S. Ernest (iFire) Lee
 *
 * Compile-time embedding of the pinned .scm content via .incbin - no
 * generator script, no runtime "load arbitrary source" entry point in
 * the compiled guest ELF. Each blob is byte-identical to its source
 * file plus one trailing NUL, so the guest can treat it as a plain C
 * string with no extra copying.
 */
	.section .rodata
	.balign 8

	.global g_record_macros_scm
g_record_macros_scm:
	.incbin "c_src/guest/content/record-macros.scm"
	.byte 0

	.global g_loot_scm
g_loot_scm:
	.incbin "c_src/guest/content/loot.scm"
	.byte 0

	.global g_combat_scm
g_combat_scm:
	.incbin "c_src/guest/content/combat.scm"
	.byte 0

	.global g_progression_scm
g_progression_scm:
	.incbin "c_src/guest/content/progression.scm"
	.byte 0
