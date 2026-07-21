// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
//
// Reference host-side implementation of the host-call ABI (RFD 0018):
// bignums AND structured values (List/Tuple/Map/Binary/Atom) are
// host-owned handles the guest reaches through the trampoline ecall.
// Bignums are computed here with __int128 and demoted back to fixnums
// when they fit 61 bits. Used by the IR interpreter oracle and the
// standalone C++ verify harnesses; the production BEAM/NIF trampoline
// implements the same ABI with Elixir's native integers and terms
// instead (this reference is therefore capped at 128-bit integers --
// wide enough for every test vector, documented, and not shipped as
// the production math).
#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "value.h"

namespace s7 {

// 128-bit divmod without compiler-rt libcalls (__divti3/__modti3 are
// missing on MSVC-target clang): plain shift-subtract long division.
// Truncating semantics, remainder takes the dividend's sign -- matching
// C, RISC-V div/rem, and Scheme quotient/remainder.
inline void divmod_i128(__int128 a, __int128 b, __int128& q, __int128& r) {
  bool neg_q = (a < 0) != (b < 0);
  bool neg_r = a < 0;
  unsigned __int128 ua =
      a < 0 ? ~static_cast<unsigned __int128>(a) + 1 : static_cast<unsigned __int128>(a);
  unsigned __int128 ub =
      b < 0 ? ~static_cast<unsigned __int128>(b) + 1 : static_cast<unsigned __int128>(b);
  unsigned __int128 uq = 0, ur = 0;
  for (int i = 127; i >= 0; --i) {
    ur = (ur << 1) | ((ua >> i) & 1);
    if (ur >= ub) {
      ur -= ub;
      uq |= static_cast<unsigned __int128>(1) << i;
    }
  }
  q = neg_q ? -static_cast<__int128>(uq) : static_cast<__int128>(uq);
  r = neg_r ? -static_cast<__int128>(ur) : static_cast<__int128>(ur);
}

// One host-owned value. List/Tuple elements and Map entries are stored
// as *tagged* words, so nesting is handles-all-the-way-down, exactly
// like the Elixir side (where the stored terms are simply real terms).
struct HostValue {
  enum class Kind { Bignum, List, Tuple, Map, Binary, Atom };
  Kind kind = Kind::Bignum;
  __int128 big = 0;
  std::vector<int64_t> items;                        // List / Tuple (tagged)
  std::vector<std::pair<int64_t, int64_t>> entries;  // Map (tagged k/v)
  std::string bytes;                                 // Binary payload / Atom name
};

struct HostBignumTable {
  std::vector<HostValue> values;
  std::unordered_map<std::string, int64_t> interned_atoms;

  int64_t add(HostValue v) {
    values.push_back(std::move(v));
    int64_t idx = static_cast<int64_t>(values.size()) - 1;
    return (idx << 3) | kHandleTag;
  }

  const HostValue& deref(int64_t tagged) {
    if ((tagged & 7) != kHandleTag) throw std::runtime_error("host_math: not a handle");
    int64_t idx = tagged >> 3;
    if (idx < 0 || idx >= static_cast<int64_t>(values.size())) {
      throw std::runtime_error("host_math: bad handle");
    }
    return values[static_cast<size_t>(idx)];
  }

  // --- Constructors (test harnesses / argument marshalling) ---

  // The empty list is nil (an immediate), never a handle -- so null?
  // stays a pure-guest tag test on both execution paths.
  int64_t make_list(std::vector<int64_t> tagged_items) {
    if (tagged_items.empty()) return kNil;
    HostValue v;
    v.kind = HostValue::Kind::List;
    v.items = std::move(tagged_items);
    return add(std::move(v));
  }

  int64_t make_tuple(std::vector<int64_t> tagged_items) {
    HostValue v;
    v.kind = HostValue::Kind::Tuple;
    v.items = std::move(tagged_items);
    return add(std::move(v));
  }

  int64_t make_map(std::vector<std::pair<int64_t, int64_t>> tagged_entries) {
    HostValue v;
    v.kind = HostValue::Kind::Map;
    v.entries = std::move(tagged_entries);
    return add(std::move(v));
  }

  int64_t make_binary(std::string bytes) {
    HostValue v;
    v.kind = HostValue::Kind::Binary;
    v.bytes = std::move(bytes);
    return add(std::move(v));
  }

  // Atoms are interned: the same name always yields the same handle, so
  // the guest's raw-word eq? works on atoms (mirrors the Elixir side).
  int64_t make_atom(const std::string& name) {
    auto it = interned_atoms.find(name);
    if (it != interned_atoms.end()) return it->second;
    HostValue v;
    v.kind = HostValue::Kind::Atom;
    v.bytes = name;
    int64_t tagged = add(std::move(v));
    interned_atoms[name] = tagged;
    return tagged;
  }

  // --- Numbers ---

  __int128 unbox(int64_t tagged) {
    if ((tagged & 7) == 0) return static_cast<__int128>(tagged >> 3);
    if ((tagged & 7) == kHandleTag) {
      const HostValue& v = deref(tagged);
      if (v.kind != HostValue::Kind::Bignum) {
        throw std::runtime_error("host_math: arithmetic on a non-number");
      }
      return v.big;
    }
    throw std::runtime_error("host_math: arithmetic on a non-number");
  }

  int64_t box(__int128 v) {
    if (v >= static_cast<__int128>(kFixnumMin) && v <= static_cast<__int128>(kFixnumMax)) {
      return static_cast<int64_t>(v) << 3;  // demote to fixnum
    }
    HostValue hv;
    hv.kind = HostValue::Kind::Bignum;
    hv.big = v;
    return add(std::move(hv));
  }

  // --- Structured values ---

  const HostValue& deref_kind(int64_t tagged, HostValue::Kind kind, const char* what) {
    if ((tagged & 7) != kHandleTag) {
      throw std::runtime_error(std::string("host_math: ") + what + " on a non-handle");
    }
    const HostValue& v = deref(tagged);
    if (v.kind != kind) {
      throw std::runtime_error(std::string("host_math: ") + what + " type mismatch");
    }
    return v;
  }

  int64_t fixnum_index(int64_t tagged, const char* what) {
    if ((tagged & 7) != 0) {
      throw std::runtime_error(std::string("host_math: ") + what + " index must be a fixnum");
    }
    return tagged >> 3;
  }

  // Structural equality for map-key lookup: fixnums/immediates by word,
  // handles by content per kind (interned atoms already compare by
  // word, but content comparison keeps this robust either way).
  bool value_equal(int64_t a, int64_t b) {
    if (a == b) return true;
    if ((a & 7) != kHandleTag || (b & 7) != kHandleTag) return false;
    const HostValue& va = deref(a);
    const HostValue& vb = deref(b);
    if (va.kind != vb.kind) return false;
    switch (va.kind) {
      case HostValue::Kind::Bignum: return va.big == vb.big;
      case HostValue::Kind::Atom:
      case HostValue::Kind::Binary: return va.bytes == vb.bytes;
      default: return false;  // deep structural equality: not needed for keys yet
    }
  }

  int64_t apply(int64_t op, int64_t a_tagged, int64_t b_tagged) {
    switch (op) {
      case kHostAdd: return box(unbox(a_tagged) + unbox(b_tagged));
      case kHostSub: return box(unbox(a_tagged) - unbox(b_tagged));
      case kHostMul: return box(unbox(a_tagged) * unbox(b_tagged));
      case kHostQuot: {
        __int128 b = unbox(b_tagged);
        if (b == 0) throw std::runtime_error("host_math: division by zero");
        __int128 q, r;
        divmod_i128(unbox(a_tagged), b, q, r);
        return box(q);
      }
      case kHostRem: {
        __int128 b = unbox(b_tagged);
        if (b == 0) throw std::runtime_error("host_math: remainder by zero");
        __int128 q, r;
        divmod_i128(unbox(a_tagged), b, q, r);
        return box(r);
      }
      case kHostLt: return (unbox(a_tagged) < unbox(b_tagged)) ? 1 : 0;
      case kHostEq: return (unbox(a_tagged) == unbox(b_tagged)) ? 1 : 0;

      case kHostCar: {
        const HostValue& v = deref_kind(a_tagged, HostValue::Kind::List, "car");
        return v.items.front();
      }
      case kHostCdr: {
        const HostValue& v = deref_kind(a_tagged, HostValue::Kind::List, "cdr");
        return make_list({v.items.begin() + 1, v.items.end()});
      }
      case kHostCons: {
        std::vector<int64_t> items{a_tagged};
        if (b_tagged != kNil) {
          const HostValue& rest = deref_kind(b_tagged, HostValue::Kind::List, "cons");
          items.insert(items.end(), rest.items.begin(), rest.items.end());
        }
        return make_list(std::move(items));
      }
      case kHostLength: {
        if (a_tagged == kNil) return tag_fixnum(0);
        const HostValue& v = deref_kind(a_tagged, HostValue::Kind::List, "length");
        return tag_fixnum(static_cast<int64_t>(v.items.size()));
      }
      case kHostListRef: {
        const HostValue& v = deref_kind(a_tagged, HostValue::Kind::List, "list-ref");
        int64_t i = fixnum_index(b_tagged, "list-ref");
        if (i < 0 || i >= static_cast<int64_t>(v.items.size())) {
          throw std::runtime_error("host_math: list-ref out of range");
        }
        return v.items[static_cast<size_t>(i)];
      }
      case kHostIsPair: {
        if ((a_tagged & 7) != kHandleTag) return 0;
        return deref(a_tagged).kind == HostValue::Kind::List ? 1 : 0;
      }
      case kHostTupleRef: {
        const HostValue& v = deref_kind(a_tagged, HostValue::Kind::Tuple, "vector-ref");
        int64_t i = fixnum_index(b_tagged, "vector-ref");
        if (i < 0 || i >= static_cast<int64_t>(v.items.size())) {
          throw std::runtime_error("host_math: vector-ref out of range");
        }
        return v.items[static_cast<size_t>(i)];
      }
      case kHostTupleSize: {
        const HostValue& v = deref_kind(a_tagged, HostValue::Kind::Tuple, "vector-length");
        return tag_fixnum(static_cast<int64_t>(v.items.size()));
      }
      case kHostMapRef: {
        // Copy the entries: value_equal derefs, and deref may not run
        // against a reference the vector could invalidate via box().
        std::vector<std::pair<int64_t, int64_t>> entries =
            deref_kind(a_tagged, HostValue::Kind::Map, "hash-table-ref").entries;
        for (const auto& [k, v] : entries) {
          if (value_equal(k, b_tagged)) return v;
        }
        return kFalse;  // s7 hash-table-ref: missing key -> #f
      }
      case kHostMapSize: {
        const HostValue& v = deref_kind(a_tagged, HostValue::Kind::Map, "hash-table-size");
        return tag_fixnum(static_cast<int64_t>(v.entries.size()));
      }
      case kHostBinSize: {
        const HostValue& v = deref_kind(a_tagged, HostValue::Kind::Binary, "string-length");
        return tag_fixnum(static_cast<int64_t>(v.bytes.size()));
      }
      case kHostStrEq: {
        const HostValue& va = deref_kind(a_tagged, HostValue::Kind::Binary, "string=?");
        const HostValue& vb = deref_kind(b_tagged, HostValue::Kind::Binary, "string=?");
        return (va.bytes == vb.bytes) ? 1 : 0;
      }
      default: throw std::runtime_error("host_math: unknown op");
    }
  }
};

}  // namespace s7
