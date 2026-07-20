defmodule WeftWarpBurrito.MixProject do
  use Mix.Project

  def project do
    [
      app: :weft_warp_burrito,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_cwd: "c_src",
      # mingw32-make (bundled with the llvm-mingw toolchain already used
      # for the RISC-V guest build) instead of nmake - a plain GNU
      # Makefile is far simpler than translating build rules to nmake's
      # dialect, and the toolchain is already a hard dependency here.
      make_executable: System.find_executable("mingw32-make") || "mingw32-make",
      # Fine (elixir-nx/fine) is a header-only C++ library, not a
      # runtime dependency - c_src/Makefile forwards this path to CMake
      # as -DFINE_INCLUDE_DIR so weft_sandbox_nif.cpp can #include
      # <fine.hpp> (RFD 3: migrate the hand-rolled erl_nif binding to
      # Fine, keep libriscv as the guest execution substrate).
      make_env: fn -> %{"FINE_INCLUDE_DIR" => Fine.include_dir()} end,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WeftWarpBurrito.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false},
      {:fine, "~> 0.1", runtime: false},
      {:burrito, "~> 1.0"}
    ]
  end

  defp releases do
    [
      weft_warp_burrito: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            windows: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end
end
