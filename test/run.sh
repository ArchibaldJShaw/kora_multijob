#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
lua test/logging.lua
lua test/client.lua
lua test/server.lua
