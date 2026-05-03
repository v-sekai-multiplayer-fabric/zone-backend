[
  {"lib/taskweft/nif.ex", :no_return},
  {"lib/taskweft/nif.ex", :call},
  {"lib/taskweft/mcp/server.ex", :pattern_match},
  # ExMCP.Client.list_tools/call_tool typespecs say they return plain maps,
  # but in practice they return %ExMCP.Response{} structs. Our wrapper
  # matches both forms; dialyzer can only see the typespec.
  {"lib/taskweft/mcp/client.ex", :pattern_match}
]
