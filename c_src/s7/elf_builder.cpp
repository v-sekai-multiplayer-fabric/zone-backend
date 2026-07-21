// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#include "elf_builder.h"

#include <cstring>

namespace s7 {

namespace {

constexpr uint16_t kEtExec = 2;
constexpr uint16_t kEmRiscv = 243;
constexpr uint32_t kShtNull = 0;
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

std::vector<uint8_t> build_elf(const std::vector<uint8_t>& code, const std::string& func_name) {
  std::vector<uint8_t> out;

  // --- Layout plan ---
  // 0                : Ehdr (64 bytes)
  // 64               : Phdr (56 bytes)
  // kPageSize (0x1000): .text (code)
  // ... (unaligned)  : .symtab, .strtab, .shstrtab
  // ... (unaligned)  : section header table

  const uint64_t text_file_offset = kPageSize;
  const uint64_t text_vaddr = kBaseAddr;

  // .strtab: index 0 is the conventional empty string.
  std::vector<uint8_t> strtab;
  strtab.push_back(0);
  const uint32_t func_name_off = static_cast<uint32_t>(strtab.size());
  append_bytes(strtab, func_name.data(), func_name.size());
  strtab.push_back(0);

  // .symtab: [0] = null symbol, [1] = our function.
  std::vector<Elf64_Sym> symtab(2, Elf64_Sym{});
  symtab[1].st_name = func_name_off;
  symtab[1].st_info = (1 << 4) | 2;  // STB_GLOBAL, STT_FUNC
  symtab[1].st_other = 0;
  symtab[1].st_shndx = 1;  // .text section index
  symtab[1].st_value = text_vaddr;
  symtab[1].st_size = code.size();

  // .shstrtab: section name strings.
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

  // --- Ehdr ---
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
  ehdr.e_flags = 0;
  ehdr.e_ehsize = sizeof(Elf64_Ehdr);
  ehdr.e_phentsize = sizeof(Elf64_Phdr);
  ehdr.e_phnum = 1;
  ehdr.e_shentsize = sizeof(Elf64_Shdr);
  ehdr.e_shnum = 5;  // null, .text, .symtab, .strtab, .shstrtab
  ehdr.e_shstrndx = 4;

  // --- Phdr: one R+X PT_LOAD segment covering .text ---
  Elf64_Phdr phdr{};
  phdr.p_type = kPtLoad;
  phdr.p_flags = kPfRead | kPfExec;
  phdr.p_offset = text_file_offset;
  phdr.p_vaddr = text_vaddr;
  phdr.p_paddr = text_vaddr;
  phdr.p_filesz = code.size();
  phdr.p_memsz = code.size();
  phdr.p_align = kPageSize;

  append_bytes(out, &ehdr, sizeof(ehdr));
  append_bytes(out, &phdr, sizeof(phdr));
  pad_to(out, text_file_offset);
  append_bytes(out, code.data(), code.size());
  append_bytes(out, symtab.data(), symtab.size() * sizeof(Elf64_Sym));
  append_bytes(out, strtab.data(), strtab.size());
  append_bytes(out, shstrtab.data(), shstrtab.size());

  // --- Section headers ---
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
