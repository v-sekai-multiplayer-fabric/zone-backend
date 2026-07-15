defmodule Taskweft.ReBAC.MixProject do
  use Mix.Project

  @version "0.2.0-dev.0"

  def project do
    [
      app: :taskweft_rebac,
      version: @version,
      elixir: "~> 1.17",
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      description: "ReBAC graph traversal for Elixir, backed by taskweft-nif",
      package: package(),
      source_url: "https://github.com/taskweft/rebac"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:taskweft_nif, "~> 0.2.0-dev"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib mix.exs LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/taskweft/rebac"}
    ]
  end
end
