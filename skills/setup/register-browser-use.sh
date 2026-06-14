#!/usr/bin/env bash
# scout depth-layer registration — single source of truth for the browser-use
# MCP registration mechanics (pin, no-cloud env vars, remove-then-add, verify).
#
# Used two ways:
#   1. Standalone (technical user):   bash register-browser-use.sh
#   2. Invoked by /scout:setup, which collects the key conversationally and
#      passes it via env so it never lands in shell history typed by a human.
#
# Key handling (in precedence order):
#   - BROWSERUSE_INHERIT=1      -> register with NO key in the config; the
#                                  running session inherits OPENAI_API_KEY from
#                                  the environment. Nothing key-shaped is written.
#   - BROWSERUSE_OPENAI_KEY=... -> pin that key into the user-scope MCP config.
#   - else, interactive tty     -> offer inherit (if OPENAI_API_KEY is set) or
#                                  prompt for a key with hidden input.
#   - else (non-interactive)    -> stop, rather than guess.
#
# Note: pinning a key via the CLI necessarily passes it in argv (visible to `ps`
# for an instant). The inherit path avoids that entirely and is the default when
# OPENAI_API_KEY is already in the environment.
#
# This script never writes the key to a file and never echoes the full key.

set -u
set -o pipefail

PIN="browser-use[cli]@0.11.9"

echo "== prerequisites =="
missing=0
if command -v claude >/dev/null 2>&1; then echo "claude: ok"; else echo "claude: MISSING -> https://docs.claude.com/en/docs/claude-code"; missing=1; fi
if command -v uvx >/dev/null 2>&1; then echo "uvx: ok"; else echo "uvx: MISSING -> install uv (ships uvx): https://github.com/astral-sh/uv"; missing=1; fi
if [ "$missing" -ne 0 ]; then echo "Stopping: install the missing prerequisite, then re-run."; exit 1; fi

# Decide key mode.
KEY=""
INHERIT=0
case "${BROWSERUSE_INHERIT:-}" in 1|true|True|TRUE|yes|Yes) INHERIT=1 ;; esac

if [ "$INHERIT" -ne 1 ] && [ -n "${BROWSERUSE_OPENAI_KEY:-}" ]; then
  KEY="$BROWSERUSE_OPENAI_KEY"
elif [ "$INHERIT" -ne 1 ]; then
  if [ -t 0 ]; then
    if [ -n "${OPENAI_API_KEY:-}" ]; then
      echo "OPENAI_API_KEY found in environment (length ${#OPENAI_API_KEY})."
      read -r -p "Inherit it instead of pinning it into the config? [Y/n] " ans
      case "${ans:-Y}" in [Nn]*) INHERIT=0 ;; *) INHERIT=1 ;; esac
    fi
    if [ "$INHERIT" -ne 1 ]; then
      read -r -s -p "Paste your OpenAI API key (input hidden): " KEY; echo
    fi
  fi
fi

if [ "$INHERIT" -ne 1 ] && [ -z "$KEY" ]; then
  echo "No OpenAI key available and not running interactively."
  echo "Set BROWSERUSE_OPENAI_KEY=... to pin a key, or BROWSERUSE_INHERIT=1 to inherit one from the environment."
  exit 1
fi

echo
echo "== register browser-use (user scope) =="
# add/add-json refuse to overwrite an existing server, so remove first (scoped to
# user so a project/local server you set up by hand is left untouched). The
# `|| true` keeps a first run (nothing to remove) from erroring under set -o
# pipefail.
claude mcp remove browser-use -s user >/dev/null 2>&1 || true

if [ "$INHERIT" -eq 1 ]; then
  # No OPENAI_API_KEY entry: the running session inherits it from the environment.
  claude mcp add-json browser-use -s user '{ "type": "stdio", "command": "uvx", "args": ["'"$PIN"'", "--mcp"], "env": { "ANONYMIZED_TELEMETRY": "False", "BROWSER_USE_VERSION_CHECK": "false" } }'
else
  # Flag form keeps the key out of a JSON blob and matches the skill's documented mechanism.
  claude mcp add browser-use uvx -s user -e OPENAI_API_KEY="$KEY" -e ANONYMIZED_TELEMETRY=False -e BROWSER_USE_VERSION_CHECK=false -- "$PIN" --mcp
fi

echo
echo "== verify =="
claude mcp get browser-use 2>&1
echo
echo "Done. If the entry shows Type: stdio, Command: uvx, the pinned args, and the two env vars, depth is registered. Re-run scout."
