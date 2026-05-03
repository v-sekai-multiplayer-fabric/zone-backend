PRIV_DIR = priv
NIF_SO   = $(PRIV_DIR)/libtaskweft_nif.so

CXXFLAGS = -std=c++20 -O2 -fPIC -fvisibility=hidden
CPPFLAGS = -I$(ERTS_INCLUDE_DIR) -Istandalone

ifeq ($(shell uname -s),Darwin)
  LDFLAGS = -undefined dynamic_lookup
else
  LDFLAGS =
endif

all: $(NIF_SO)

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(NIF_SO): c_src/taskweft_nif.cpp | $(PRIV_DIR)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -shared $< -o $@ $(LDFLAGS)

clean:
	rm -f $(NIF_SO)

.PHONY: all clean
