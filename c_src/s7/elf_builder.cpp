// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "elf_builder.h"

#include <cstring>

#include "value.h"

namespace s7 {

namespace {

constexpr uint16_t kEtExec = 2;
constexpr uint16_t kEmRiscv = 243;
constexpr uint32_t kShtProgbits = 1;
constexpr uint32_t kShtSymtab = 2;
constexpr uint32_t kShtStrtab = 3;
constexpr uint64_t kShfAlloc = 0x2;
constexpr uint64_t kShfExecinstr = 0x4;
constexpr uint32_t kPtLoad = 1;
constexpr uint32_t kPfExec = 1;
constexpr uint32_t kPfWrite = 2;
constexpr uint32_t kPfRead = 4;
constexpr uint64_t kPageSize = 0x1000;

#pragma pack(push, 1)
struct Elf64_Ehdr {
  unsigned char e_ident[16];
  uint16_t e_type;
  uint16_t e_machine;
  uint32_t e_version;
  uint64_t e_entry;
  uint64_t e_phoff;
  uint64_t e_shoff;
  uint32_t e_flags;
  uint16_t e_ehsize;
  uint16_t e_phentsize;
  uint16_t e_phnum;
  uint16_t e_shentsize;
  uint16_t e_shnum;
  uint16_t e_shstrndx;
};

struct Elf64_Phdr {
  uint32_t p_type;
  uint32_t p_flags;
  uint64_t p_offset;
  uint64_t p_vaddr;
  uint64_t p_paddr;
  uint64_t p_filesz;
  uint64_t p_memsz;
  uint64_t p_align;
};

struct Elf64_Shdr {
  uint32_t sh_name;
  uint32_t sh_type;
  uint64_t sh_flags;
  uint64_t sh_addr;
  uint64_t sh_offset;
  uint64_t sh_size;
  uint32_t sh_link;
  uint32_t sh_info;
  uint64_t sh_addralign;
  uint64_t sh_entsize;
};

struct Elf64_Sym {
  uint32_t st_name;
  unsigned char st_info;
  unsigned char st_other;
  uint16_t st_shndx;
  uint64_t st_value;
  uint64_t st_size;
};
#pragma pack(pop)

static_assert(sizeof(Elf64_Ehdr) == 64, "Elf64_Ehdr must be 64 bytes");
static_assert(sizeof(Elf64_Phdr) == 56, "Elf64_Phdr must be 56 bytes");
static_assert(sizeof(Elf64_Shdr) == 64, "Elf64_Shdr must be 64 bytes");
static_assert(sizeof(Elf64_Sym) == 24, "Elf64_Sym must be 24 bytes");

void append_bytes(std::vector<uint8_t>& out, const void* data, size_t size) {
  const uint8_t* bytes = static_cast<const uint8_t*>(data);
  out.insert(out.end(), bytes, bytes + size);
}

void pad_to(std::vector<uint8_t>& out, size_t offset) {
  if (out.size() < offset) {
    out.resize(offset, 0);
  }
}

}  // namespace

std::vector<uint8_t> build_elf(const CompiledProgram& program) {
  std::vector<uint8_t> out;
  const std::vector<uint8_t>& code = program.code;

  // Layout: Ehdr | Phdr | (pad to page) .text | .symtab | .strtab | .shstrtab | shdrs
  const uint64_t text_file_offset = kPageSize;
  const uint64_t text_vaddr = kBaseAddr;

  // .strtab (index 0 = empty string) + .symtab (index 0 = null symbol).
  std::vector<uint8_t> strtab;
  strtab.push_back(0);
  std::vector<Elf64_Sym> symtab(1, Elf64_Sym{});
  for (const CompiledFunction& func : program.functions) {
    Elf64_Sym sym{};
    sym.st_name = static_cast<uint32_t>(strtab.size());
    append_bytes(strtab, func.name.data(), func.name.size());
    strtab.push_back(0);
    sym.st_info = (1 << 4) | 2;  // STB_GLOBAL, STT_FUNC
    sym.st_shndx = 1;            // .text section index
    sym.st_value = text_vaddr + func.offset;
    sym.st_size = func.size;
    symtab.push_back(sym);
  }

  std::vector<uint8_t> shstrtab;
  shstrtab.push_back(0);
  auto add_shstr = [&shstrtab](const char* name) {
    uint32_t off = static_cast<uint32_t>(shstrtab.size());
    append_bytes(shstrtab, name, std::strlen(name) + 1);
    return off;
  };
  const uint32_t name_text = add_shstr(".text");
  const uint32_t name_symtab = add_shstr(".symtab");
  const uint32_t name_strtab = add_shstr(".strtab");
  const uint32_t name_shstrtab = add_shstr(".shstrtab");

  const uint64_t symtab_file_offset = text_file_offset + code.size();
  const uint64_t strtab_file_offset = symtab_file_offset + symtab.size() * sizeof(Elf64_Sym);
  const uint64_t shstrtab_file_offset = strtab_file_offset + strtab.size();
  const uint64_t shoff = shstrtab_file_offset + shstrtab.size();

  Elf64_Ehdr ehdr{};
  ehdr.e_ident[0] = 0x7f;
  ehdr.e_ident[1] = 'E';
  ehdr.e_ident[2] = 'L';
  ehdr.e_ident[3] = 'F';
  ehdr.e_ident[4] = 2;  // ELFCLASS64
  ehdr.e_ident[5] = 1;  // ELFDATA2LSB
  ehdr.e_ident[6] = 1;  // EV_CURRENT
  ehdr.e_type = kEtExec;
  ehdr.e_machine = kEmRiscv;
  ehdr.e_version = 1;
  ehdr.e_entry = text_vaddr;
  ehdr.e_phoff = 64;
  ehdr.e_shoff = shoff;
  ehdr.e_ehsize = sizeof(Elf64_Ehdr);
  ehdr.e_phentsize = sizeof(Elf64_Phdr);
  ehdr.e_phnum = 2;
  ehdr.e_shentsize = sizeof(Elf64_Shdr);
  ehdr.e_shnum = 5;  // null, .text, .symtab, .strtab, .shstrtab
  ehdr.e_shstrndx = 4;

  Elf64_Phdr phdr{};
  phdr.p_type = kPtLoad;
  phdr.p_flags = kPfRead | kPfExec;
  phdr.p_offset = text_file_offset;
  phdr.p_vaddr = text_vaddr;
  phdr.p_paddr = text_vaddr;
  phdr.p_filesz = code.size();
  phdr.p_memsz = code.size();
  phdr.p_align = kPageSize;

  // Guest heap: a zero-initialized (filesz 0, BSS-style) RW segment for
  // the bump allocator -- word 0 is the bump offset, so an untouched
  // segment IS an empty heap (see value.h's heap ABI comment).
  Elf64_Phdr heap{};
  heap.p_type = kPtLoad;
  heap.p_flags = kPfRead | kPfWrite;
  heap.p_offset = text_file_offset;  // filesz 0: nothing read from file
  heap.p_vaddr = kHeapBase;
  heap.p_paddr = kHeapBase;
  heap.p_filesz = 0;
  heap.p_memsz = 8 + kHeapArena;
  heap.p_align = kPageSize;

  append_bytes(out, &ehdr, sizeof(ehdr));
  append_bytes(out, &phdr, sizeof(phdr));
  append_bytes(out, &heap, sizeof(heap));
  pad_to(out, text_file_offset);
  append_bytes(out, code.data(), code.size());
  append_bytes(out, symtab.data(), symtab.size() * sizeof(Elf64_Sym));
  append_bytes(out, strtab.data(), strtab.size());
  append_bytes(out, shstrtab.data(), shstrtab.size());

  Elf64_Shdr sh_null{};
  Elf64_Shdr sh_text{};
  sh_text.sh_name = name_text;
  sh_text.sh_type = kShtProgbits;
  sh_text.sh_flags = kShfAlloc | kShfExecinstr;
  sh_text.sh_addr = text_vaddr;
  sh_text.sh_offset = text_file_offset;
  sh_text.sh_size = code.size();
  sh_text.sh_addralign = 4;

  Elf64_Shdr sh_symtab{};
  sh_symtab.sh_name = name_symtab;
  sh_symtab.sh_type = kShtSymtab;
  sh_symtab.sh_offset = symtab_file_offset;
  sh_symtab.sh_size = symtab.size() * sizeof(Elf64_Sym);
  sh_symtab.sh_link = 3;  // .strtab section index
  sh_symtab.sh_info = 1;  // index of first non-local symbol
  sh_symtab.sh_addralign = 8;
  sh_symtab.sh_entsize = sizeof(Elf64_Sym);

  Elf64_Shdr sh_strtab{};
  sh_strtab.sh_name = name_strtab;
  sh_strtab.sh_type = kShtStrtab;
  sh_strtab.sh_offset = strtab_file_offset;
  sh_strtab.sh_size = strtab.size();
  sh_strtab.sh_addralign = 1;

  Elf64_Shdr sh_shstrtab{};
  sh_shstrtab.sh_name = name_shstrtab;
  sh_shstrtab.sh_type = kShtStrtab;
  sh_shstrtab.sh_offset = shstrtab_file_offset;
  sh_shstrtab.sh_size = shstrtab.size();
  sh_shstrtab.sh_addralign = 1;

  append_bytes(out, &sh_null, sizeof(sh_null));
  append_bytes(out, &sh_text, sizeof(sh_text));
  append_bytes(out, &sh_symtab, sizeof(sh_symtab));
  append_bytes(out, &sh_strtab, sizeof(sh_strtab));
  append_bytes(out, &sh_shstrtab, sizeof(sh_shstrtab));

  return out;
}

}  // namespace s7
