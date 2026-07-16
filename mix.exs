defmodule Taskweft.MixProject do
  use Mix.Project

  @version "0.4.11"

  def project do
    [
      app: :taskweft,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      releases: releases(),
      dialyzer: [plt_add_apps: [:mix], ignore_warnings: ".dialyzer_ignore.exs"],
      description: "HTN planner exposing plan/replan over the RECTGTN model via MCP",
      package: package(),
      source_url: "https://github.com/taskweft/taskweft",
      docs: docs()
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/taskweft/taskweft"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/rectgtn.md"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [preferred_envs: [propcheck: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Taskweft.Application, []}
    ]
  end

  # Standalone Burrito binary — see issue #53 and `Taskweft.CLI`.
  #
  # The `Taskweft.Release.wrap/1` step only invokes Burrito when a zig
  # toolchain is present (or `TASKWEFT_BURRITO=1` forces it), so a plain
  # `mix release taskweft` still assembles on a machine without zig; CI
  # builds the per-triplet binaries with the toolchain installed.
  defp releases do
    [
      taskweft: [
        version: @version,
        steps: [:assemble, &Taskweft.Release.wrap/1],
        burrito: [
          targets: [
            # Linux needs two fixes for the NIF to load inside the binary:
            #   1. Burrito bundles a *musl* ERTS but its recompile defaults to
            #      glibc; override CC/CXX (via nif_env — last env value wins) to
            #      a single musl `-target` so the .so is musl + static libc++.
            #   2. taskweft_nif's Makefile writes to `priv/` (dep-relative) while
            #      Burrito's copy-back reads `$MIX_APP_PATH/priv`; redirect it
            #      with nif_make_args so the rebuilt .so actually replaces the
            #      native (glibc) one in the release.
            linux_amd64: linux_target("x86_64-linux-musl", :x86_64),
            linux_arm64: linux_target("aarch64-linux-musl", :aarch64),
            # macOS uses Burrito's default zig target (aarch64-macos, correct),
            # but still needs the PRIV_DIR redirect so the recompiled Mach-O .so
            # replaces the host-built one in the release.
            macos_arm64: [
              os: :darwin,
              cpu: :aarch64,
              nif_make_args: ["PRIV_DIR=$(MIX_APP_PATH)/priv"]
            ],
            windows_amd64: [
              os: :windows,
              cpu: :x86_64,
              # Same PRIV_DIR redirect as linux/macOS: without it the rebuilt
              # NIF lands in the dep-relative priv/ and Burrito's copy-back
              # ($MIX_APP_PATH/priv) misses it, so the binary ships without a
              # loadable libtaskweft_nif.dll and the MCP server can't plan.
              nif_make_args: ["PRIV_DIR=$(MIX_APP_PATH)/priv"]
            ]
          ]
        ]
      ]
    ]
  end

  # A Burrito Linux target that recompiles taskweft_nif as a self-contained
  # musl shared object landing in the release priv dir. `zig_triple` is e.g.
  # "x86_64-linux-musl"; the single `-target` (last env value wins over
  # Burrito's default) yields musl + statically-linked libc++, so the .so
  # loads inside the musl ERTS.
  #
  # CC/CXX route through scripts/nif-compile, which makes the otherwise
  # single-command compile+link cacheable by sccache (falls back to plain zig
  # when sccache is absent). See scripts/nif-compile.
  defp linux_target(zig_triple, cpu) do
    wrapper = Path.expand("scripts/nif-compile")
    flags = "-target #{zig_triple} -Wl,-undefined=dynamic_lookup"

    [
      os: :linux,
      cpu: cpu,
      nif_make_args: ["PRIV_DIR=$(MIX_APP_PATH)/priv"],
      nif_env: [
        {"CC", "#{wrapper} cc #{flags}"},
        {"CXX", "#{wrapper} cxx #{flags}"}
      ]
    ]
  end

  defp deps do
    [
      {:taskweft_nif, "~> 0.2.0-dev"},
      {:taskweft_rebac, "~> 0.2.0-dev"},
      {:taskweft_mcp_client, "~> 0.2.0-dev"},
      {:taskweft_mcp, "~> 0.2.0-dev"},
      {:ex_mcp, "~> 1.0.0-rc"},
      {:burrito, "~> 1.5"},
      {:json_ld, "~> 1.0"},
      {:rdf, "~> 3.0"},
      {:jason, "~> 1.4"},
      {:ex_json_schema, "~> 0.10"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:timex, "~> 3.7", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
