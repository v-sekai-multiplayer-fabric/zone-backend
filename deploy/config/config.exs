# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

import Config

config :logger, level: :info

# The taskweft MCP validator lives in the parent app and is called only when
# loaded; nothing to configure here. Whitelist + port are read from the
# environment at boot (see TaskweftDeploy.Application).
