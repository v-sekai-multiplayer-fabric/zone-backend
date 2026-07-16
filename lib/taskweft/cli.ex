# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.CLI do
  @moduledoc """
  Single entrypoint for the standalone Taskweft binary (issue #53).

  Unifies the two historical entrypoints — the C++ `cli/main.cpp` planner
  and the Elixir `mix taskweft.mcp` server — behind one dispatcher so a
  Burrito-packaged binary can serve both without a dev toolchain.

  ## Subcommands

      taskweft plan <domain.jsonld>                     plan from a self-contained file
      taskweft plan --problem <domain> <problem>        plan from split domain + problem
      taskweft plan                                     plan from JSON-LD on stdin
      taskweft replan <fail_step> <domain> [problem]    replan after a step failure (JSON)
      taskweft mcp [--http] [--port N] [--host H]        run the MCP server (stdio / HTTP)
      taskweft version                                   print version + build commit
      taskweft help                                      print this usage

  The legacy `--replan` / `--problem` flag forms from the C++ CLI are accepted
  as aliases, and a bare `taskweft <domain.jsonld>` (no subcommand) plans that
  file, so existing callers keep working.

  ## I/O contract

  `plan` prints the bare JSON array of steps (`[["a", "arg"], ...]`) that the
  C++ CLI emitted, so byte-for-byte callers are unaffected. `replan` prints
  the planner's JSON envelope. Domain + problem pairs are merged the same way
  the C++ `TwLoader::load_file_pair`
  merges them: problem `variables` override domain state by name, problem
  `methods` / `actions` / `goal_methods` extend or override the domain, and a
  non-empty problem `todo_list` replaces the domain's todo list.

  ## Structure

  `run/1` is pure with respect to process control — it returns a tagged
  result and never writes to a device or halts, so it is unit-testable.
  `main/1` is the release entrypoint: it resolves argv (via Burrito when
  packaged), calls `run/1`, prints, and halts.
  """

  alias Taskweft.NIF

  @version Mix.Project.config()[:version]
  @commit System.get_env("TASKWEFT_COMMIT") || "unknown"

  @typedoc "Outcome of `run/1` — never performs IO or halts the VM."
  @type outcome ::
          {:ok, iodata()}
          | {:error, iodata(), non_neg_integer()}
          | {:mcp, keyword()}

  @doc """
  Burrito/release entrypoint. Resolves argv, dispatches, prints, and halts.
  """
  @spec main([String.t()] | nil) :: no_return()
  def main(argv \\ nil) do
    argv = argv || resolve_argv()

    # Every non-`mcp` path must terminate the VM — a raised error or an
    # unexpected return becomes a non-zero exit, never an idle VM that hangs
    # the standalone binary. `serve_mcp/1` is the one path that blocks forever.
    case run(argv) do
      {:mcp, opts} -> serve_mcp(opts)
      other -> emit(other)
    end
  rescue
    e ->
      IO.puts(:stderr, "taskweft: #{Exception.message(e)}")
      halt(1)
  catch
    kind, reason ->
      IO.puts(:stderr, "taskweft: #{Exception.format(kind, reason, __STACKTRACE__)}")
      halt(1)
  end

  defp emit({:ok, output}) do
    IO.puts(output)
    halt(0)
  end

  defp emit({:error, message, code}) do
    IO.puts(:stderr, message)
    halt(code)
  end

  @doc """
  Dispatch `argv` to a subcommand and return its outcome without doing IO.
  """
  @spec run([String.t()]) :: outcome()
  def run(argv)

  def run([]), do: plan([])

  def run([cmd | _rest]) when cmd in ["version", "--version", "-v"], do: {:ok, version_string()}
  def run([cmd | _rest]) when cmd in ["help", "--help", "-h"], do: {:ok, usage()}

  def run(["mcp" | rest]), do: parse_mcp(rest)

  def run([cmd | rest]) when cmd in ["replan", "--replan"], do: replan(rest)
  def run(["plan" | rest]), do: plan(rest)

  # Bare `taskweft <domain.jsonld>` or `taskweft --problem d p` → plan.
  def run(argv), do: plan(argv)

  # ---------- plan ----------

  defp plan(args) do
    with {:ok, domain_json} <- load_domain(args) do
      {:ok, NIF.plan(domain_json)}
    end
  end

  # ---------- replan ----------

  defp replan([fail_step_str | rest]) do
    case Integer.parse(fail_step_str) do
      {fail_step, ""} ->
        with {:ok, domain_json} <- load_domain(rest) do
          plan_json = NIF.plan(domain_json)
          {:ok, NIF.replan(domain_json, plan_json, fail_step)}
        end

      _ ->
        {:error, "taskweft replan: <fail_step> must be an integer, got #{inspect(fail_step_str)}",
         2}
    end
  end

  defp replan([]),
    do: {:error, "taskweft replan: usage: replan <fail_step> <domain> [problem]", 2}

  # ---------- mcp ----------

  defp parse_mcp(args), do: parse_mcp(args, transport: :stdio)

  defp parse_mcp(["--http" | rest], opts),
    do: parse_mcp(rest, Keyword.put(opts, :transport, :http))

  defp parse_mcp(["--port", value | rest], opts) do
    case Integer.parse(value) do
      {port, ""} ->
        parse_mcp(rest, opts |> Keyword.put(:transport, :http) |> Keyword.put(:port, port))

      _ ->
        {:error, "taskweft mcp: --port must be an integer, got #{inspect(value)}", 2}
    end
  end

  defp parse_mcp(["--host", value | rest], opts),
    do: parse_mcp(rest, opts |> Keyword.put(:transport, :http) |> Keyword.put(:host, value))

  defp parse_mcp([unknown | _rest], _opts),
    do: {:error, "taskweft mcp: unknown option #{inspect(unknown)}", 2}

  defp parse_mcp([], opts), do: {:mcp, opts}

  # Blocks forever running the MCP server; only reached from `main/1`.
  defp serve_mcp(opts) do
    # The MCP stack (ex_mcp's Horde ServiceRegistry, SessionManager, the
    # reliability supervisor) is marked `:load` in the release and started
    # here, lazily, only for the `mcp` subcommand.
    {:ok, _} = Application.ensure_all_started(:taskweft_mcp)

    server_opts =
      case Keyword.get(opts, :transport, :stdio) do
        :stdio ->
          [transport: :stdio]

        :http ->
          [
            transport: :http,
            port: Keyword.get(opts, :port, 4000),
            host: Keyword.get(opts, :host, "localhost")
          ]
      end

    {:ok, _server} = Taskweft.MCP.Server.start_link(server_opts)
    Process.sleep(:infinity)
  end

  # ---------- domain / problem loading ----------

  # Mirror the C++ `TwLoader` file handling: raw pass-through to the NIF (the
  # NIF's own loader resolves the compact JSON-LD), with `--problem` merging
  # done at the JSON level to match `load_file_pair`.
  defp load_domain([]), do: read_stdin()

  defp load_domain(["--problem", domain_path, problem_path | _rest]),
    do: load_pair(domain_path, problem_path)

  defp load_domain([domain_path | _rest]), do: read_domain_file(domain_path)

  defp read_stdin do
    case IO.read(:stdio, :eof) do
      :eof -> {:error, "taskweft: no domain on stdin", 1}
      {:error, reason} -> {:error, "taskweft: stdin read failed: #{inspect(reason)}", 1}
      data -> {:ok, data}
    end
  end

  defp read_domain_file(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, _reason} -> {:error, "taskweft: cannot read #{path}", 1}
    end
  end

  defp load_pair(domain_path, problem_path) do
    with {:ok, domain_body} <- read_domain_file(domain_path),
         {:ok, problem_body} <- read_pair_problem(problem_path),
         {:ok, domain} <- decode(domain_path, domain_body),
         {:ok, problem} <- decode(problem_path, problem_body) do
      encode(merge(domain, problem))
    end
  end

  defp read_pair_problem(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, _reason} -> {:error, "taskweft: cannot read problem #{path}", 1}
    end
  end

  defp decode(path, body) do
    case Jason.decode(body) do
      {:ok, %{} = map} -> {:ok, map}
      {:ok, _other} -> {:error, "taskweft: #{path} is not a JSON object", 1}
      {:error, e} -> {:error, "taskweft: #{path} is invalid JSON: #{Exception.message(e)}", 1}
    end
  end

  defp encode(map) do
    case Jason.encode(map) do
      {:ok, json} -> {:ok, json}
      {:error, e} -> {:error, "taskweft: merge encode failed: #{Exception.message(e)}", 1}
    end
  end

  # State from the problem overrides the domain; methods/actions/goal_methods
  # extend or override; a non-empty problem task list replaces the domain's.
  defp merge(domain, problem) do
    domain
    |> merge_variables(problem)
    |> merge_map_field(problem, "methods")
    |> merge_map_field(problem, "actions")
    |> merge_map_field(problem, "goal_methods")
    |> merge_tasks(problem)
  end

  defp merge_variables(domain, problem) do
    case {Map.get(domain, "variables"), Map.get(problem, "variables")} do
      {_, nil} ->
        domain

      {dom_vars, prob_vars} when is_list(prob_vars) ->
        dom_vars = List.wrap(dom_vars)
        overridden = MapSet.new(prob_vars, &Map.get(&1, "name"))
        kept = Enum.reject(dom_vars, &MapSet.member?(overridden, Map.get(&1, "name")))
        Map.put(domain, "variables", kept ++ prob_vars)
    end
  end

  defp merge_map_field(domain, problem, key) do
    case Map.get(problem, key) do
      value when is_map(value) ->
        Map.put(domain, key, Map.merge(Map.get(domain, key, %{}), value))

      _ ->
        domain
    end
  end

  defp merge_tasks(domain, problem) do
    case Map.get(problem, "todo_list") do
      tasks when is_list(tasks) and tasks != [] -> Map.put(domain, "todo_list", tasks)
      _ -> domain
    end
  end

  # ---------- misc ----------

  defp version_string, do: "taskweft #{@version} (#{@commit})"

  defp usage do
    """
    taskweft #{@version} — standalone HTN planner + MCP server

    Usage:
      taskweft plan <domain.jsonld>                  plan from a self-contained file
      taskweft plan --problem <domain> <problem>     plan from split domain + problem
      taskweft plan                                  plan from JSON-LD on stdin
      taskweft replan <fail_step> <domain> [problem] replan after a step failure (JSON)
      taskweft mcp                                   run the MCP server over stdio
      taskweft mcp --http [--port N] [--host H]      run the MCP server over HTTP
      taskweft version                               print version + build commit
      taskweft help                                  print this help

    A bare `taskweft <domain.jsonld>` (no subcommand) plans that file.
    """
  end

  # Under the Burrito standalone binary (`__BURRITO` set by the zig wrapper),
  # the CLI args arrive as plain init arguments; elsewhere use `System.argv/0`.
  # Reading `:init.get_plain_arguments/0` directly avoids depending on the
  # `Burrito.Util.Args` module being loaded (it mirrors that module's logic).
  defp resolve_argv do
    if System.get_env("__BURRITO") != nil do
      :init.get_plain_arguments() |> Enum.map(&to_string/1)
    else
      System.argv()
    end
  end

  # Wrapped so tests can stub the boundary if needed; real halts the VM.
  defp halt(code), do: System.halt(code)
end
