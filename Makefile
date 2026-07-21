PRIV_DIR = priv

ifeq ($(OS),Windows_NT)
  NIF_EXT = dll
else
  NIF_EXT = so
endif
SANDBOX_NIF_SO = $(PRIV_DIR)/weft_sandbox_nif.$(NIF_EXT)

CXXFLAGS = -std=gnu++20 -O2 -fPIC -fvisibility=hidden
CPPFLAGS = -I$(ERTS_INCLUDE_DIR)

ifeq ($(shell uname -s),Darwin)
  LDFLAGS = -undefined dynamic_lookup
else
  LDFLAGS =
endif

all: nif

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

# The host-native NIF (CMake+Ninja, wrapping libriscv::Machine). This
# recipe is unconditional (not gated on the priv/ output file's mtime)
# so an edited NIF source always gets rebuilt - cmake/ninja still do
# their own real incremental compilation underneath, so this costs a
# few seconds per `mix compile`, not a full rebuild.
.PHONY: all clean nif

nif: | $(PRIV_DIR)
	cmake -S c_src -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DERTS_INCLUDE_DIR="$(ERTS_INCLUDE_DIR)" -DFINE_INCLUDE_DIR="$(FINE_INCLUDE_DIR)"
	cmake --build build --target weft_sandbox_nif
	cp build/weft_sandbox_nif.$(NIF_EXT) $(SANDBOX_NIF_SO)

clean:
	rm -f $(SANDBOX_NIF_SO)
	rm -rf build
