#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
"""Reindent c_src/s7/fixtures/*.scm to a canonical, paren-depth-based
indentation (2 spaces per nesting level). This does not rewrap or
reflow lines -- it only recomputes each line's leading whitespace from
its parenthesis depth, the same "reindent" (not "reformat") a Lisp-aware
editor does. `;` starts a line comment; there are no string literals in
this s7 subset, so no quoting rules are needed.

Usage: format_lisp.py [--check] FILE...
  --check: exit 1 (printing a diff-free mismatch list) if reindenting
           would change a file, without writing -- mirrors `mix format
           --check-formatted`'s pre-commit convention.
  default: rewrite each file in place.
"""
import sys


def line_depths(text):
    """Depth at the START of each physical line (before that line's own
    leading close-parens are consumed), ignoring parens after `;`."""
    depths = []
    depth = 0
    at_line_start = True
    in_comment = False
    for ch in text:
        if at_line_start:
            depths.append(depth)
            at_line_start = False
        if ch == "\n":
            at_line_start = True
            in_comment = False
            continue
        if in_comment:
            continue
        if ch == ";":
            in_comment = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
    return depths


def reindent(text):
    lines = text.split("\n")
    depths = line_depths(text)
    out = []
    for line, depth_at_start in zip(lines, depths):
        stripped = line.strip()
        if not stripped:
            out.append("")
            continue
        leading_closers = 0
        for ch in stripped:
            if ch == ")":
                leading_closers += 1
            else:
                break
        indent = max(0, depth_at_start - leading_closers)
        out.append("  " * indent + stripped)
    return "\n".join(out)


def main(argv):
    check = "--check" in argv
    paths = [a for a in argv if a != "--check"]
    if not paths:
        print("usage: format_lisp.py [--check] FILE...", file=sys.stderr)
        return 2

    mismatched = []
    for path in paths:
        with open(path, encoding="utf-8") as f:
            original = f.read()
        formatted = reindent(original.rstrip("\n")) + "\n"
        if formatted == original:
            continue
        if check:
            mismatched.append(path)
        else:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(formatted)

    if check and mismatched:
        for path in mismatched:
            print(f"{path}: not correctly indented (run scripts/format_lisp.py {path})",
                  file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
