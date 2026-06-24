# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule UroLoop.MixProject do
  use Mix.Project

  def project do
    [
      app: :uro_loop,
      version: "0.1.0",
      elixir: ">= 1.16.3",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ecto, "~> 3.13"}
    ]
  end
end
