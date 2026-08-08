---
authors: K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>
state: published
discussion: https://github.com/v-sekai-multiplayer-fabric/zone-backend/pull/57
labels: cicd, docker, build-image, burrito, zig, elixir
---

# 0045 Container image builds repaired: `build-image` unblocked, the Burrito production image made buildable

## Context

`build-image` failed on `main` on every push from at least 2026-07-21 to
2026-08-08. The published error was always the same line:

```
** (Mix) Cannot compile dependency :uro_loop because it isn't available,
   please ensure the dependency is at "apps/uro_loop"
```

That error hid three more faults behind it in the root `Dockerfile`, and
`docker/uro/Dockerfile` carried five faults that no workflow reported,
because no workflow builds that file. Each fault appeared only after a
build got past the one before it. Both files now build end to end, each
verified by a complete local `docker build`.

## Decision

Root `Dockerfile`, which `build-image` publishes to ghcr.io:

| Fault | Repair |
| --- | --- |
| `apps/` never copied, but `mix.exs:143` declares `{:uro_loop, path: "apps/uro_loop"}` | `COPY apps ./apps` before `deps.get`, because Mix resolves path deps where they sit |
| `Makefile` and `c_src/` never copied, but `compilers: [:elixir_make]` needs both | Copy both, and add `cmake` and `ninja` to `apk add` |
| `mix uro.apigen` needs deploy secrets no build has | Step deleted. See the tombstones |
| Elixir 1.16, against 1.17 in `ci.yml` | `ELIXIR_VERSION=1.17`, and `as` corrected to `AS` |

`docker/uro/Dockerfile`, the Burrito production image:

| Fault | Repair |
| --- | --- |
| `COPY apps` placed after `deps.get` | Moved before it |
| `COPY Makefile` absent | Added |
| `ninja-build` puts the binary at `/usr/lib/ninja-build/bin/ninja`, off `PATH` | Package changed to `ninja` |
| Elixir 1.16 mis-parses `@fixnum_min -(1 <<< 60)` | Version raised to 1.17 |
| Burrito 1.6.0 rejects any Zig except 0.16.0, and `xz` absent | Upstream static Zig 0.16.0 tarball, and `xz` added |

The result is an 18MB static musl binary at `/usr/local/bin/uro`.

## Tombstones

Per the request of 2026-08-08, each entry carries its own tag and its own
UTC timestamp, rather than the single shared date ADR 0044 used.

| Factor | Why it died | Tag | Closed (UTC) |
| --- | --- | --- | --- |
| `mix uro.apigen` inside the backend image | It runs `app.start`, so `config/runtime.exs` demands `URL`, `DATABASE_URL`, `PHOENIX_KEY_BASE` and more. Its only output is a frontend build input this backend image never copies and never serves | `cicd/apigen` | 2026-08-08T03:05Z |
| Placeholder env vars to keep `uro.apigen` | Brittle. The `:pow_assent` block enumerates `OAUTH2_*` from the live environment, so each new `fetch_env!` breaks the image again | `cicd/apigen` | 2026-08-08T03:05Z |
| Alpine package `ninja-build` | Installs to `/usr/lib/ninja-build/bin/ninja`, which is not on `PATH`, so cmake reports `CMAKE_MAKE_PROGRAM is not set` | `cicd/toolchain` | 2026-08-08T03:12Z |
| Alpine package `zig`, version 0.14.1 | Burrito 1.6.0 pins 0.16.0 exactly and stops on any other version | `cicd/toolchain` | 2026-08-08T03:18Z |
| Elixir 1.16 for either image | It reads `@fixnum_min -(1 <<< 60)` as a read-and-subtract, not an attribute definition, and raises `ArithmeticError: nil - 1152921504606846976` | `cicd/elixir-version` | 2026-08-08T03:15Z |
| Reformatting `lib/uro/accounts/user.ex` and `lib/uro/controllers/user.ex` | A local Elixir 1.20.1 artifact. CI runs 1.17, its format step passes, and neither file belongs to this change | `cicd/format` | 2026-08-08T03:30Z |

## Consequences

`build-image` publishes again, so the `gateway_image` and `uro_image`
tofu variables in the infra repository get fresh digests.

`docker/uro/Dockerfile` is buildable for the first time since `apps/uro_loop`
arrived. No workflow builds it yet. That gap stays open, and a later change
can close it.

The two images now agree on Elixir 1.17 with `ci.yml`. A future version bump
must move all three together.
