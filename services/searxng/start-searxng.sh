#!/usr/bin/env bash
# start-searxng.sh — start scout's local SearXNG metasearch container.
#
# The one start path for the opt-in `meta` discovery backend, shared by the
# shell launcher's `meta` arm and the /scout:meta skill. It only starts the
# container; registering the mcp-searxng MCP server is /scout:setup's job.
#
# State lives outside the plugin tree, in a user-scoped directory that no
# plugin update or `scout --update` touches (decision
# 261016-2323-where-does-scout-keep-state-that-must-survive-a-plugin-update):
#
#   $STATE_DIR/searxng/secret_key               generated once, mode 600
#   $STATE_DIR/searxng/config/settings.yml      re-rendered from the template
#   $STATE_DIR/searxng/docker-compose.yml       copied from the plugin
#
# The container bind-mounts the rendered settings.yml, so it keeps working after
# the plugin copy it was started from is replaced. The plugin's own template
# (config/settings.yml next to this script) ships `secret_key: ""` and is never
# written.
#
# Exit codes: 0 SearXNG answers on http://localhost:8911/; 1 it does not, with
# the reason on stderr. Callers fall back to WebSearch on 1.
#
# Standalone on purpose: the state-dir rule is repeated here rather than sourced
# from a shared file, so the script runs from any copy of the plugin.
set -euo pipefail

URL="http://localhost:8911/"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_COMPOSE="$SRC_DIR/docker-compose.yml"
SRC_SETTINGS="$SRC_DIR/config/settings.yml"

# --- State directory (same rule as skills/setup/register-browser-use.sh) ------
STATE_DIR="${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}"
case "$STATE_DIR" in
  /*) ;;
  *) echo "scout meta: state directory must be an absolute path, got '$STATE_DIR' (SCOUT_STATE_DIR / XDG_STATE_HOME)." >&2; exit 1 ;;
esac
case "$STATE_DIR" in
  */plugins/cache/*) echo "scout meta: state directory '$STATE_DIR' lies inside the plugin cache, which a plugin update deletes. Set SCOUT_STATE_DIR elsewhere." >&2; exit 1 ;;
esac
WORK_DIR="$STATE_DIR/searxng"

# --- (a) Already running: leave it alone --------------------------------------
if curl -fsS "$URL" >/dev/null 2>&1; then
  echo "scout meta: SearXNG already running at $URL"
  exit 0
fi

# --- (b) Prerequisites ---------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "scout meta: docker not found — SearXNG cannot start." >&2
  exit 1
fi
for f in "$SRC_COMPOSE" "$SRC_SETTINGS"; do
  if [ ! -f "$f" ]; then
    echo "scout meta: plugin file missing: $f" >&2
    exit 1
  fi
done

# --- (c) Secret: generated once, kept across updates ---------------------------
# The work dir is private (700). settings.yml inside it is made 644 below so the
# container user can read the bind mount on Linux; the directory guards it.
( umask 077 && mkdir -p "$WORK_DIR/config" )
chmod 700 "$WORK_DIR"
SECRET_FILE="$WORK_DIR/secret_key"
if [ ! -s "$SECRET_FILE" ]; then
  if ! command -v openssl >/dev/null 2>&1; then
    echo "scout meta: openssl not found — cannot generate SearXNG secret_key." >&2
    exit 1
  fi
  SECRET_TMP="$(umask 077 && mktemp "$WORK_DIR/.secret_key.XXXXXX")"
  if ! ( umask 077 && openssl rand -hex 32 > "$SECRET_TMP" ); then
    rm -f "$SECRET_TMP"
    echo "scout meta: 'openssl rand' failed — cannot generate SearXNG secret_key." >&2
    exit 1
  fi
  chmod 600 "$SECRET_TMP"
  mv "$SECRET_TMP" "$SECRET_FILE"
fi
SECRET="$(tr -d '[:space:]' < "$SECRET_FILE")"
if ! printf '%s' "$SECRET" | grep -Eq '^[0-9a-fA-F]{32,}$'; then
  echo "scout meta: $SECRET_FILE does not hold a hex secret; delete it to regenerate." >&2
  exit 1
fi

# --- (d) Render settings and copy compose, every run ---------------------------
# Re-rendering each time means a template change in a new scout release reaches
# the container on the next start; only the secret is carried over.
SETTINGS_TMP="$(mktemp "$WORK_DIR/config/.settings.yml.XXXXXX")"
sed "s|^\([[:space:]]*\)secret_key:.*|\1secret_key: \"$SECRET\"|" "$SRC_SETTINGS" > "$SETTINGS_TMP"
if ! grep -q "secret_key: \"$SECRET\"" "$SETTINGS_TMP"; then
  rm -f "$SETTINGS_TMP"
  echo "scout meta: template $SRC_SETTINGS has no secret_key line to fill." >&2
  exit 1
fi
chmod 644 "$SETTINGS_TMP"
mv "$SETTINGS_TMP" "$WORK_DIR/config/settings.yml"
cp "$SRC_COMPOSE" "$WORK_DIR/docker-compose.yml"

# --- (e) Start and wait for health ---------------------------------------------
if ! COMPOSE_OUT="$(docker compose -f "$WORK_DIR/docker-compose.yml" up -d 2>&1)"; then
  echo "scout meta: 'docker compose up' failed:" >&2
  printf '%s\n' "$COMPOSE_OUT" >&2
  exit 1
fi
for _ in $(seq 1 30); do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    echo "scout meta: SearXNG running at $URL"
    exit 0
  fi
  sleep 1
done
echo "scout meta: SearXNG health-wait timed out after 30 s ($URL)." >&2
exit 1
