defmodule Taskweft.MixProject do
  use Mix.Project

  def project do
    [
      app: :taskweft,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix], ignore_warnings: ".dialyzer_ignore.exs"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [preferred_envs: [propcheck: :test]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:taskweft_nif, github: "V-Sekai-fire/taskweft-nif"},
      {:taskweft_rebac, github: "V-Sekai-fire/taskweft-rebac"},
      {:taskweft_mcp_client, github: "V-Sekai-fire/taskweft-mcp-client"},
      {:taskweft_mcp, github: "V-Sekai-fire/taskweft-mcp"},
      {:json_ld, "~> 1.0"},
      {:rdf, "~> 3.0"},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:timex, "~> 3.7", only: :test}
    ]
  end
end
