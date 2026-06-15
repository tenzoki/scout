#!/usr/bin/env bash
# scout depth-layer registration — single source of truth for the browser-use
# MCP registration mechanics (pin, shim, no-cloud env vars, remove-then-add, verify).
#
# Extraction runs on Anthropic. Stock browser-use 0.11.9 hardwires its
# browser_extract_content LLM to OpenAI; scout ships a runtime shim
# (services/browser-use-anthropic/scout_browseruse_anthropic.py) that rebinds it
# to ChatAnthropic. So the registered command launches the shim inside the exact
# pinned browser-use environment, and the credential is an ANTHROPIC_API_KEY.
#
# Used two ways:
#   1. Standalone (technical user):   bash register-browser-use.sh
#   2. Invoked by /scout:setup, which collects the key conversationally and
#      passes it via env so it never lands in shell history typed by a human.
#
# Key handling (in precedence order):
#   - BROWSERUSE_INHERIT=1          -> register with NO key in the config; the
#                                      running session inherits ANTHROPIC_API_KEY
#                                      from the environment. Nothing key-shaped
#                                      is written.
#   - BROWSERUSE_ANTHROPIC_KEY=...  -> pin that key into the user-scope MCP config.
#   - else, interactive tty         -> offer inherit (if ANTHROPIC_API_KEY is set)
#                                      or prompt for a key with hidden input.
#   - else (non-interactive)        -> stop, rather than guess.
#
# Note: pinning a key via the CLI necessarily passes it in argv (visible to `ps`
# for an instant). The inherit path avoids that entirely and is the default when
# ANTHROPIC_API_KEY is already in the environment.
#
# This script never writes the key to a file and never echoes the full key.

set -u
set -o pipefail

PIN="browser-use[cli]@0.11.9"

# Resolve the shim path from this script's own location, so it is correct in
# both the installed ~/.scout tree and a direct source-tree run.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHIM_PATH="$(cd "$SCRIPT_DIR/../../" && pwd)/services/browser-use-anthropic/scout_browseruse_anthropic.py"

echo "== prerequisites =="
missing=0
if command -v claude >/dev/null 2>&1; then echo "claude: ok"; else echo "claude: MISSING -> https://docs.claude.com/en/docs/claude-code"; missing=1; fi
if command -v uvx >/dev/null 2>&1; then echo "uvx: ok"; else echo "uvx: MISSING -> install uv (ships uvx): https://github.com/astral-sh/uv"; missing=1; fi
if [ ! -f "$SHIM_PATH" ]; then echo "shim: MISSING -> expected at $SHIM_PATH"; missing=1; else echo "shim: ok"; fi
if [ "$missing" -ne 0 ]; then echo "Stopping: install the missing prerequisite, then re-run."; exit 1; fi

# Decide key mode.
KEY=""
INHERIT=0
case "${BROWSERUSE_INHERIT:-}" in 1|true|True|TRUE|yes|Yes) INHERIT=1 ;; esac

if [ "$INHERIT" -ne 1 ] && [ -n "${BROWSERUSE_ANTHROPIC_KEY:-}" ]; then
  KEY="$BROWSERUSE_ANTHROPIC_KEY"
elif [ "$INHERIT" -ne 1 ]; then
  if [ -t 0 ]; then
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
      echo "ANTHROPIC_API_KEY found in environment (length ${#ANTHROPIC_API_KEY})."
      read -r -p "Inherit it instead of pinning it into the config? [Y/n] " ans
      case "${ans:-Y}" in [Nn]*) INHERIT=0 ;; *) INHERIT=1 ;; esac
    fi
    if [ "$INHERIT" -ne 1 ]; then
      read -r -s -p "Paste your Anthropic API key (input hidden): " KEY; echo
    fi
  fi
fi

if [ "$INHERIT" -ne 1 ] && [ -z "$KEY" ]; then
  echo "No Anthropic key available and not running interactively."
  echo "Set BROWSERUSE_ANTHROPIC_KEY=... to pin a key, or BROWSERUSE_INHERIT=1 to inherit one from the environment."
  exit 1
fi

# Optional non-default extraction model.
MODEL="${SCOUT_DEPTH_EXTRACT_MODEL:-}"

echo
echo "== register browser-use (user scope) =="
# add/add-json refuse to overwrite an existing server, so remove first (scoped to
# user so a project/local server you set up by hand is left untouched). The
# `|| true` keeps a first run (nothing to remove) from erroring under set -o
# pipefail.
claude mcp remove browser-use -s user >/dev/null 2>&1 || true

if [ "$INHERIT" -eq 1 ]; then
  # No ANTHROPIC_API_KEY entry: the running session inherits it from the
  # environment. The shim still runs (SCOUT_DEPTH_PROVIDER=anthropic) and both
  # no-cloud env vars are passed.
  if [ -n "$MODEL" ]; then
    claude mcp add-json browser-use -s user '{ "type": "stdio", "command": "uvx", "args": ["--from", "'"$PIN"'", "python", "'"$SHIM_PATH"'", "--mcp"], "env": { "SCOUT_DEPTH_PROVIDER": "anthropic", "SCOUT_DEPTH_EXTRACT_MODEL": "'"$MODEL"'", "ANONYMIZED_TELEMETRY": "False", "BROWSER_USE_VERSION_CHECK": "false" } }'
  else
    claude mcp add-json browser-use -s user '{ "type": "stdio", "command": "uvx", "args": ["--from", "'"$PIN"'", "python", "'"$SHIM_PATH"'", "--mcp"], "env": { "SCOUT_DEPTH_PROVIDER": "anthropic", "ANONYMIZED_TELEMETRY": "False", "BROWSER_USE_VERSION_CHECK": "false" } }'
  fi
else
  # Flag form keeps the key out of a JSON blob and matches the skill's documented
  # mechanism. The shim runs inside the pinned browser-use env via `--from`.
  if [ -n "$MODEL" ]; then
    claude mcp add browser-use uvx -s user -e ANTHROPIC_API_KEY="$KEY" -e SCOUT_DEPTH_PROVIDER=anthropic -e SCOUT_DEPTH_EXTRACT_MODEL="$MODEL" -e ANONYMIZED_TELEMETRY=False -e BROWSER_USE_VERSION_CHECK=false -- --from "$PIN" python "$SHIM_PATH" --mcp
  else
    claude mcp add browser-use uvx -s user -e ANTHROPIC_API_KEY="$KEY" -e SCOUT_DEPTH_PROVIDER=anthropic -e ANONYMIZED_TELEMETRY=False -e BROWSER_USE_VERSION_CHECK=false -- --from "$PIN" python "$SHIM_PATH" --mcp
  fi
fi

echo
echo "== verify =="
claude mcp get browser-use 2>&1
echo
echo "Done. If the entry shows Type: stdio, Command: uvx, the --from pin + shim path + --mcp args, SCOUT_DEPTH_PROVIDER=anthropic, and the two no-cloud env vars, depth is registered. Re-run scout."
