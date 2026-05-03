defmodule Taskweft.ReBAC.MixProject do
  use Mix.Project

  def project do
    [
      app: :taskweft_rebac,
      version: "0.1.0",
      elixir: "~> 1.17",
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:taskweft_nif, github: "V-Sekai-fire/taskweft-nif"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false}
    ]
  end
end
