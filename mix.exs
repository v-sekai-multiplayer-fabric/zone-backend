defmodule Taskweft.NIF.MixProject do
  use Mix.Project

  def project do
    [
      app: :taskweft_nif,
      version: "0.1.0",
      elixir: "~> 1.17",
      compilers: [:elixir_make] ++ Mix.compilers(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.9"},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false},
      {:benchee, "~> 1.3", only: :dev, runtime: false}
    ]
  end
end
