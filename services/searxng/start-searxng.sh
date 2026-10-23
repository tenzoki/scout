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
#   $STATE_DIR/searxng/.scout-owned             marker: scout wrote this folder
#
# The marker is what `scout --uninstall` checks before it removes the folder, so
# a folder named `searxng` that scout did not write is never deleted. This script
# also refuses to write into such a folder (see step (c)).
#
# The container bind-mounts the rendered settings.yml, so it keeps working after
# the plugin copy it was started from is replaced. The plugin's own template
# (config/settings.yml next to this script) ships `secret_key: ""` and is never
# written.
#
# Exit codes: 0 SearXNG answers a JSON search on http://localhost:8911/; 1 it
# does not, with the reason on stderr. Callers fall back to WebSearch on 1.
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
  */plugins/cache|*/plugins/cache/*) echo "scout meta: state directory '$STATE_DIR' lies inside the plugin cache, which a plugin update deletes. Set SCOUT_STATE_DIR elsewhere." >&2; exit 1 ;;
esac
WORK_DIR="$STATE_DIR/searxng"
MARKER="$WORK_DIR/.scout-owned"
# Every compose call names the project explicitly: Compose ranks
# COMPOSE_PROJECT_NAME above the file's `name:`, so without -p a user's exported
# variable would relabel scout's own container and step (0) would remove it.
PROJECT="scout-searxng"

# SearXNG answers only when a JSON search works: that identifies the service on
# port 8911 as SearXNG (not any web server) and proves the `json` output the
# mcp-searxng server needs is switched on. limiter is off in the template, so a
# local curl is not throttled.
searxng_answers() {
  curl -fsS --max-time 10 "${URL}search?q=scout&format=json" 2>/dev/null | grep -q '"results"'
}

# --- (0) Replace a scout-searxng container from another compose project --------
# scout 0.5.0 ran the same container_name under the implicit project "searxng".
# Such a container blocks "compose up" on the name conflict when stopped, and
# mounts a stale config when running. The name is scout's own, so remove it.
if command -v docker >/dev/null 2>&1; then
  LEGACY_PROJECT="$(docker inspect --type container -f '{{ index .Config.Labels "com.docker.compose.project" }}' scout-searxng 2>/dev/null)" && {
    if [ "$LEGACY_PROJECT" != "$PROJECT" ]; then
      echo "scout meta: removing container scout-searxng from compose project '$LEGACY_PROJECT' (left by an older scout)."
      docker rm -f scout-searxng >/dev/null || { echo "scout meta: could not remove the old scout-searxng container; run: docker rm -f scout-searxng" >&2; exit 1; }
    fi
  }
fi

# --- (a) Already running: leave it alone --------------------------------------
# Reached only after (0), so a container left by an older scout has been
# replaced by now. A running container is not recreated here, so the settings
# rendered in (d) reach it only after it is stopped and the next start runs.
if searxng_answers; then
  echo "scout meta: SearXNG already running at $URL"
  exit 0
fi
if curl -fsS --max-time 5 "$URL" >/dev/null 2>&1; then
  echo "scout meta: something answers on $URL, but not as SearXNG with JSON search. If it is scout's container, run: docker rm -f scout-searxng, then start again. Otherwise free port 8911." >&2
  exit 1
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

# --- (c) Ownership, then the secret: generated once, kept across updates -------
# Write only into a folder scout owns: one that does not exist yet, is empty,
# carries the marker, or is recognisably scout's (the default state directory,
# which only scout uses, or a folder holding scout's own compose file, as 0.6.0
# left it before the marker existed). Anything else is someone else's folder.
if [ -e "$WORK_DIR" ] && [ ! -f "$MARKER" ]; then
  if [ -d "$WORK_DIR" ] && [ -z "$(ls -A "$WORK_DIR" 2>/dev/null)" ]; then
    :
  elif [ -d "$WORK_DIR" ] && { [ -z "${SCOUT_STATE_DIR:-}" ] || grep -qs 'container_name: scout-searxng' "$WORK_DIR/docker-compose.yml"; }; then
    :
  else
    echo "scout meta: $WORK_DIR exists and was not written by scout (no .scout-owned marker). Move it aside or set SCOUT_STATE_DIR to another directory." >&2
    exit 1
  fi
fi
# The work dir is private (700). settings.yml inside it is made 644 below so the
# container user can read the bind mount on Linux; the directory guards it.
( umask 077 && mkdir -p "$WORK_DIR/config" )
chmod 700 "$WORK_DIR"
if [ ! -f "$MARKER" ]; then
  printf '%s\n' "Written by scout (start-searxng.sh). scout --uninstall removes this folder only while this file is here." > "$MARKER"
fi
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
# Re-rendering each time keeps the rendered file in step with the template of
# the plugin copy that ran last; only the secret is carried over. A container
# that is already running keeps the settings it started with (step (a) exits
# before this point, and compose does not watch a bind-mounted file), so a
# template change in a new scout release reaches it only once it has been
# stopped (`docker stop scout-searxng`) and this script runs again.
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
if ! COMPOSE_OUT="$(docker compose -p "$PROJECT" -f "$WORK_DIR/docker-compose.yml" up -d 2>&1)"; then
  echo "scout meta: 'docker compose up' failed:" >&2
  printf '%s\n' "$COMPOSE_OUT" >&2
  exit 1
fi
# `compose up -d` returns once the image is pulled and the container started, so
# this wait covers SearXNG's own startup only.
WAIT_START=$SECONDS
while [ $((SECONDS - WAIT_START)) -lt 30 ]; do
  if searxng_answers; then
    echo "scout meta: SearXNG running at $URL"
    exit 0
  fi
  sleep 1
done
echo "scout meta: SearXNG health-wait timed out after 30 s ($URL)." >&2
exit 1
