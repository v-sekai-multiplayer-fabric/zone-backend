Application.ensure_all_started(:propcheck)
# Integration tests against external MCP servers are opt-in (npx subprocess).
ExUnit.start(exclude: [:integration])
