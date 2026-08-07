# Real production image for multiplayer-fabric-uro: a Burrito-wrapped
# OTP release, not the root Dockerfile's dev-shaped `iex -S mix do
# ecto.create, ecto.migrate, run priv/repo/test_seeds.exs, phx.server`
# (which seeds dummy test data on every boot -- fine for local
# docker-compose, wrong for a real deploy).
#
# Burrito (mix.exs's releases: block) wraps a real `mix release` into
# one self-contained, statically-linked executable (musl libc, bundled
# ERTS), cross-compiled via Zig. Verified locally before this Dockerfile
# was written: `mix release uro` produces burrito_out/uro_linux_musl, a
# real ELF 64-bit static binary, and `PORT=4999 ./uro_linux_musl start`
# genuinely boots Uro.Endpoint with Bandit and serves, using
# config/runtime.exs (not config.exs's old COMPILE_PHASE trick) for every
# deploy-time secret. Because the binary is fully static, the runtime
# stage below needs nothing but the binary itself and CA certs for
# outbound TLS (CockroachDB client certs, S3-compatible storage, OTLP).
#
# Migrations run via Uro.Release.migrate/0 (lib/uro/release.ex),
# `gateway_admin`/Uro.Repo.Migration only, standard Phoenix-release
# pattern -- `mix ecto.migrate` does not exist inside a compiled release.
FROM elixir:1.16-alpine AS build

RUN apk add --no-cache \
	nodejs npm inotify-tools git bash make gcc g++ curl libc-dev \
	cmake ninja-build zig

# xpack riscv-none-elf-gcc: needed by the c_src NIF build
# (WeftWarpBurrito.SandboxNif's guest target), same toolchain
# .github/workflows/casync-interop.yml already installs for CI.
RUN curl -fsSL -o /tmp/riscv-gcc.tar.gz \
		https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz \
	&& mkdir -p /opt/riscv-none-elf-gcc \
	&& tar -xzf /tmp/riscv-gcc.tar.gz -C /opt/riscv-none-elf-gcc --strip-components=1 \
	&& rm /tmp/riscv-gcc.tar.gz
ENV PATH="/opt/riscv-none-elf-gcc/bin:${PATH}"

ENV MIX_ENV=prod
WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix do deps.get, patch.exmarcel, deps.compile

COPY config ./config
COPY priv ./priv
COPY lib ./lib
COPY c_src ./c_src
COPY apps ./apps

RUN mix release uro

# Runtime stage: the release is a fully static musl binary, so this
# only needs CA certs for outbound TLS, not an Elixir/Erlang install.
FROM alpine:3.20 AS runtime
RUN apk add --no-cache ca-certificates
COPY --from=build /app/burrito_out/uro_linux_musl /usr/local/bin/uro
COPY docker/uro/fly-start.sh /usr/local/bin/fly-start.sh
RUN chmod +x /usr/local/bin/fly-start.sh

EXPOSE 4000
ENTRYPOINT ["/usr/local/bin/fly-start.sh"]
