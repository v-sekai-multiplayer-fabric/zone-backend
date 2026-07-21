#include <cstdio>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <vector>
#include <libriscv/machine.hpp>
#include "fixedpoint.h"
#include "softfloat_mini.h"
using Machine64 = riscv::Machine<riscv::RISCV64>;

extern "C" {
int64_t fixed_dot_ref_i64(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);
int64_t fixed_dot_bad_i64(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);
uint64_t soft_dot_ref_bits(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t soft_dot_bad_bits(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
}

int64_t call_guest_i64(Machine64& m, const char* fn, int64_t a, int64_t b, int64_t c,
                        int64_t d, int64_t e, int64_t f) {
  auto addr = m.memory.resolve_address(fn);
  m.cpu.reset_stack_pointer();
  m.setup_call(a, b, c, d, e, f);
  m.simulate_with<true>(1'000'000ull, 0u, addr);
  return (int64_t)m.cpu.reg(riscv::REG_ARG0);
}

int main(int argc, char** argv) {
  std::ifstream f(argv[1], std::ios::binary);
  std::ostringstream ss; ss << f.rdbuf();
  std::string elf = ss.str();
  std::vector<uint8_t> elfBytes(elf.begin(), elf.end());
  Machine64 m(elfBytes, riscv::MachineOptions<riscv::RISCV64>{.memory_max = 16UL << 20});

  bool all_ok = true;

  // --- Fixed-point (Q32.32): "ban floats"/"integer-only" strategies ---
  {
    int64_t ax = fixed_from_double(0.1), ay = fixed_from_double(0.3), az = fixed_from_double(0.7);
    int64_t bx = fixed_from_double(0.11), by = fixed_from_double(0.37), bz = fixed_from_double(0.13);
    int64_t native_ref = fixed_dot_ref_i64(ax, ay, az, bx, by, bz);
    int64_t native_bad = fixed_dot_bad_i64(ax, ay, az, bx, by, bz);
    int64_t guest_ref = call_guest_i64(m, "fixed_dot_ref_i64", ax, ay, az, bx, by, bz);
    int64_t guest_bad = call_guest_i64(m, "fixed_dot_bad_i64", ax, ay, az, bx, by, bz);
    bool ref_ok = native_ref == guest_ref;
    bool bad_ok = native_bad == guest_bad;
    bool ref_eq_bad_native = native_ref == native_bad;
    printf("[fixed-point] native_ref=%lld native_bad=%lld guest_ref=%lld guest_bad=%lld\n",
           (long long)native_ref, (long long)native_bad, (long long)guest_ref, (long long)guest_bad);
    printf("[fixed-point] ref match=%d bad match=%d (ref==bad, no assoc. hazard at all)=%d\n",
           ref_ok, bad_ok, ref_eq_bad_native);
    all_ok &= ref_ok && bad_ok && ref_eq_bad_native;
  }

  // --- Softfloat: illustrative minimal software double emulation ---
  {
    uint64_t ax = sf_from_double(0.1), ay = sf_from_double(0.3), az = sf_from_double(0.7);
    uint64_t bx = sf_from_double(0.11), by = sf_from_double(0.37), bz = sf_from_double(0.13);
    uint64_t native_ref = soft_dot_ref_bits(ax, ay, az, bx, by, bz);
    uint64_t native_bad = soft_dot_bad_bits(ax, ay, az, bx, by, bz);
    uint64_t guest_ref = (uint64_t)call_guest_i64(m, "soft_dot_ref_bits", (int64_t)ax, (int64_t)ay,
                                                   (int64_t)az, (int64_t)bx, (int64_t)by, (int64_t)bz);
    uint64_t guest_bad = (uint64_t)call_guest_i64(m, "soft_dot_bad_bits", (int64_t)ax, (int64_t)ay,
                                                   (int64_t)az, (int64_t)bx, (int64_t)by, (int64_t)bz);
    bool ref_ok = native_ref == guest_ref;
    bool bad_ok = native_bad == guest_bad;
    bool ref_ne_bad = native_ref != native_bad; // softfloat still has the associativity hazard
    printf("[softfloat]   native_ref=%.17g native_bad=%.17g\n", sf_to_double(native_ref), sf_to_double(native_bad));
    printf("[softfloat]   guest_ref=%.17g  guest_bad=%.17g\n", sf_to_double(guest_ref), sf_to_double(guest_bad));
    printf("[softfloat]   ref match=%d bad match=%d (ref!=bad, assoc. hazard still present)=%d\n",
           ref_ok, bad_ok, ref_ne_bad);
    all_ok &= ref_ok && bad_ok && ref_ne_bad;
  }

  printf("\n%s\n", all_ok ? "ALL ALT-STRATEGY CHECKS HOLD" : "SOME CHECK FAILED");
  return all_ok ? 0 : 1;
}
