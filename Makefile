PRIV_DIR = priv

ifeq ($(OS),Windows_NT)
  NIF_EXT = dll
  EXE = .exe
else
  NIF_EXT = so
  EXE =
endif
NIF_SO   = $(PRIV_DIR)/libtaskweft_nif.$(NIF_EXT)
SANDBOX_NIF_SO = $(PRIV_DIR)/weft_sandbox_nif.$(NIF_EXT)

CXXFLAGS = -std=gnu++20 -O2 -fPIC -fvisibility=hidden
CPPFLAGS = -I$(ERTS_INCLUDE_DIR) -Istandalone

ifeq ($(shell uname -s),Darwin)
  LDFLAGS = -undefined dynamic_lookup
else
  LDFLAGS =
endif

RISCV_GCC := riscv-none-elf-gcc

all: $(NIF_SO) guest nif s7fixtures

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(NIF_SO): c_src/taskweft_nif.cpp | $(PRIV_DIR)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -shared $< -o $@ $(LDFLAGS)

# weft_warp_burrito's sandbox: RISC-V guest ELF (xpack riscv-none-elf-gcc,
# newlib) plus the host-native NIF (CMake+Ninja, wrapping libriscv::Machine).
# Both recipes are unconditional (not gated on the priv/ output file's mtime)
# so an edited guest/NIF source always gets rebuilt - cmake/ninja and the
# RISC-V object files still do their own real incremental compilation
# underneath, so this costs a few seconds per `mix compile`, not a full
# rebuild.
.PHONY: all clean guest nif s7fixtures

guest: | $(PRIV_DIR)
	$(RISCV_GCC) -march=rv64gc -mabi=lp64d -static -O2 \
		-Ic_src/guest -Ic_src/thirdparty/s7 -DWITH_C_LOADER=0 -DWITH_SYSTEM_EXTRAS=0 \
		-c c_src/thirdparty/s7/s7.c -o c_src/guest/s7.o
	$(RISCV_GCC) -march=rv64gc -mabi=lp64d -static -O2 \
		-Ic_src/guest -Ic_src/thirdparty/s7 -c c_src/guest/weft_guest.c -o c_src/guest/weft_guest.o
	$(RISCV_GCC) -march=rv64gc -mabi=lp64d -static -O2 \
		-c c_src/guest/content_embed.S -o c_src/guest/content_embed.o
	$(RISCV_GCC) -march=rv64gc -mabi=lp64d -static -O2 \
		-Wl,--undefined=guest_loot_roll -Wl,--undefined=guest_combat_replay \
		-Wl,--undefined=guest_progression_replay \
		c_src/guest/weft_guest.o c_src/guest/content_embed.o c_src/guest/s7.o -lm \
		-o $(PRIV_DIR)/weft_guest.elf

nif: | $(PRIV_DIR)
	cmake -S c_src -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DERTS_INCLUDE_DIR="$(ERTS_INCLUDE_DIR)" -DFINE_INCLUDE_DIR="$(FINE_INCLUDE_DIR)"
	cmake --build build --target weft_sandbox_nif
	cp build/weft_sandbox_nif.$(NIF_EXT) $(SANDBOX_NIF_SO)

# Build the in-repo s7 AOT compiler (c_src/s7, RFD 0019 -- no
# cross-toolchain) and compile the test fixture programs that
# WeftWarpBurrito.Program's tests load from priv/.
s7fixtures: | $(PRIV_DIR)
	cmake -S c_src -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DERTS_INCLUDE_DIR="$(ERTS_INCLUDE_DIR)" -DFINE_INCLUDE_DIR="$(FINE_INCLUDE_DIR)"
	cmake --build build --target s7c
	build/s7c$(EXE) c_src/s7/fixtures/basic.scm -o $(PRIV_DIR)/s7_basic.elf

clean:
	rm -f $(NIF_SO) $(SANDBOX_NIF_SO) $(PRIV_DIR)/weft_guest.elf $(PRIV_DIR)/s7_basic.elf
	rm -f c_src/guest/*.o
	rm -rf build
