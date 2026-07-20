# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# Invoked by elixir_make (mix.exs's compilers list) with MIX_APP_PATH
# already set. Two independent build steps land in $(MIX_APP_PATH)/priv:
#   1. The RISC-V guest ELF, cross-compiled with the xpack
#      riscv-none-elf-gcc toolchain (newlib, not musl - matches
#      weft-warp-loop's own toolchain choice for this tier).
#   2. The host-native NIF shared library (via CMake+Ninja, wrapping
#      libriscv::Machine), compiled for whatever platform is running
#      this build.
PRIV_DIR := $(MIX_APP_PATH)/priv
RISCV_GCC := riscv-none-elf-gcc

ERTS_INCLUDE_DIR := $(shell erl -eval "io:format(\"~s\", [filename:join([code:root_dir(), \"erts-\" ++ erlang:system_info(version), \"include\"])])" -s init stop -noshell)

# Both recipes below are unconditional (not gated on the priv/ output
# file's mtime) - a plain file-target rule would make Make skip the
# whole recipe once priv/weft_sandbox_nif.dll exists, even after guest
# or NIF sources change (bit us once already: an edited .cpp silently
# didn't get rebuilt). cmake --build/ninja and the RISC-V object files
# still do their own real incremental compilation underneath, so this
# costs a few seconds per `mix compile`, not a full rebuild.
.PHONY: all guest nif clean

all: guest nif

guest:
	mkdir -p $(PRIV_DIR)
	$(RISCV_GCC) -march=rv64gc -mabi=lp64d -static -O2 \
		-Iguest -Ithirdparty/s7 -DWITH_C_LOADER=0 -DWITH_SYSTEM_EXTRAS=0 \
		-c thirdparty/s7/s7.c -o guest/s7.o
	$(RISCV_GCC) -march=rv64gc -mabi=lp64d -static -O2 \
		-Iguest -Ithirdparty/s7 -c guest/weft_guest.c -o guest/weft_guest.o
	$(RISCV_GCC) -march=rv64gc -mabi=lp64d -static -O2 \
		-c guest/content_embed.S -o guest/content_embed.o
	$(RISCV_GCC) -march=rv64gc -mabi=lp64d -static -O2 \
		-Wl,--undefined=guest_loot_roll -Wl,--undefined=guest_combat_replay \
		-Wl,--undefined=guest_progression_replay \
		guest/weft_guest.o guest/content_embed.o guest/s7.o -lm \
		-o $(PRIV_DIR)/weft_guest.elf

nif:
	cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DERTS_INCLUDE_DIR="$(ERTS_INCLUDE_DIR)" -DFINE_INCLUDE_DIR="$(FINE_INCLUDE_DIR)"
	cmake --build build --target weft_sandbox_nif
	mkdir -p $(PRIV_DIR)
	cp build/weft_sandbox_nif.dll $(PRIV_DIR)/weft_sandbox_nif.dll

clean:
	rm -rf build guest/*.o
