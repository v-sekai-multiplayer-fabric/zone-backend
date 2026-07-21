---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: N/A — committed directly, no PR review
labels: s7-compiler, special-forms
---

# 0025 `cond` and named `let` special forms

## Context

`c_src/guest/content/{combat,progression,loot}.scm` use `cond`
(multi-branch dispatch) and named `let` (`(let loop ((x init)) ...)`,
iteration via self-recursion) — neither existed in the AOT compiler,
which only had `if`/plain `let`.

## Decision Outcome

`cond` desugars at codegen time to nested `if` emission — no IR
changes, no macro system. Named `let` lifts to a top-level function
(reusing the existing two-pass `LowerCtx`, mangled to a unique internal
name so multiple `(let loop ...)` forms across a program don't
collide), with recursive calls to the loop name resolved via a
per-`FnCodegen` alias — **not** a closure: named-let bodies in this
subset cannot capture enclosing free variables (only their own loop
parameters and globals), unlike `lambda`. Every named-let in the three
ported files happens to only reference its own parameters and global
functions, so this restriction costs nothing here; it is a documented
compiler limitation, not a workaround.

## Consequences

No new IR opcodes for either form. Named-let's no-capture restriction
is a real, narrower semantics than full Scheme — acceptable since
nothing in scope needs it, but must stay documented so a future author
doesn't assume closures work here.

## Confirmation

`verify_s7` adds `cond`-dispatch and named-let-iteration cases,
three ways.
