#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
"""Lean has no canonical `gofmt`-equivalent auto-formatter, so this
enforces the concrete style rules this repo actually got burned by,
rather than reflowing/reindenting anything (that's still a human call
for Lean). Checks, per file:

  - No semicolon-joined `field : Type` declarations on one line inside
    a `structure ... where` block. This isn't cosmetic: under this
    repo's pinned toolchain, `structure Foo where a : T; b : T` only
    registers `a` as a field and silently drops `b` -- a real, hard-to-
    diagnose build break (see docs/decisions -- the CASSIE Lean port
    hit this exactly). One field per line, always.
  - No trailing whitespace.
  - No tab characters.
  - Exactly one trailing newline at end of file.

Usage: format_lean.py [--check] FILE...
  --check: exit 1 and list violations, without modifying anything --
           mirrors `mix format --check-formatted`/`format_lisp.py
           --check`'s pre-commit convention. There is no non-check
           (auto-fix) mode: unlike reindenting Lisp by paren depth,
           these violations don't have a single unambiguous automatic
           fix worth guessing at.
"""
import re
import sys

STRUCTURE_WHERE_RE = re.compile(r"^\s*(structure|class)\b.*\bwhere\s*$")
FIELD_LINE_RE = re.compile(r"^\s*[A-Za-z_][A-Za-z0-9_'!?]*\s*:\s*\S")
BLOCK_ENDERS = ("deriving", "namespace", "end", "def ", "theorem ", "instance ")


def strip_line_comment(line):
    """Drop a trailing `-- ...` line comment (Lean has no string
    literals in structure-field lines, so this simple split is safe
    here even though it isn't a general Lean comment/string lexer)."""
    idx = line.find("--")
    return line if idx == -1 else line[:idx]


def check_file(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    lines = text.split("\n")
    errors = []

    in_struct_block = False
    struct_indent = None
    for i, line in enumerate(lines, start=1):
        if line != line.rstrip():
            errors.append(f"{i}: trailing whitespace")
        if "\t" in line:
            errors.append(f"{i}: tab character (use spaces)")

        stripped = line.strip()
        if STRUCTURE_WHERE_RE.match(line):
            in_struct_block = True
            struct_indent = None
            continue
        if in_struct_block:
            if not stripped:
                continue
            indent = len(line) - len(line.lstrip(" "))
            if struct_indent is None:
                struct_indent = indent
            if indent < struct_indent or any(stripped.startswith(k) for k in BLOCK_ENDERS):
                in_struct_block = False
                continue
            code = strip_line_comment(stripped)
            if FIELD_LINE_RE.match(code) and ";" in code:
                errors.append(
                    f"{i}: semicolon-joined struct fields on one line -- "
                    "only the first field is registered under this repo's "
                    "toolchain; one field per line"
                )

    if not text.endswith("\n"):
        errors.append(f"{len(lines)}: missing trailing newline")
    elif text.endswith("\n\n"):
        errors.append("file ends with multiple blank lines")

    return errors


def main(argv):
    check = "--check" in argv
    paths = [a for a in argv if a != "--check"]
    if not paths:
        print("usage: format_lean.py [--check] FILE...", file=sys.stderr)
        return 2
    if not check:
        print("format_lean.py has no auto-fix mode -- use --check", file=sys.stderr)
        return 2

    had_errors = False
    for path in paths:
        for err in check_file(path):
            had_errors = True
            print(f"{path}:{err}", file=sys.stderr)

    return 1 if had_errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
