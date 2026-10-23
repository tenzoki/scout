---
description: Start scout's local SearXNG metasearch container on this machine, so scout can discover URLs through self-hosted SearXNG instead of WebSearch. The in-session counterpart of the `scout meta` launcher command; both run the same start script. Invoke when the user wants to "start scout meta", "start SearXNG", "turn on the metasearch backend", or "bring up the SearXNG container". Starts the container only — registering the searxng MCP is /scout:setup's job, and stopping the container is left to the user (`docker stop scout-searxng`). Entirely OPTIONAL; without it scout discovers with WebSearch.
allowed-tools: [Bash]
---

# /scout:meta — start scout's local SearXNG container

This skill starts the **SearXNG metasearch container** that scout's optional `meta` discovery backend talks to, at `http://localhost:8911/`. It is the in-session counterpart of running `scout meta` from a shell; both call the same script, `${CLAUDE_PLUGIN_ROOT}/services/searxng/start-searxng.sh`, which is the single source of truth for how the container starts. This skill drives the conversation and relays the result; it does not repeat the start logic.

Apply scout's short-form voice for everything you say to the user: read `${CLAUDE_PLUGIN_ROOT}/stilwerk/chat-voice-en.yaml` (or the target-language variant) and follow its intent — action-first, second person, plain words, no AI stock phrases. If no variant exists for the user's language, read the `-en` file and apply its intent in that language.

## Step 1 — State what this does, plainly

Tell the user, up front:

- This starts a local SearXNG container (`scout-searxng`) on their machine with Docker. SearXNG is a self-hosted metasearch engine; scout uses it to *find* URLs. It does not fetch pages — `WebFetch` and the depth layer still do that.
- It is optional. Without it, scout discovers with the built-in `WebSearch`.
- On first start the script generates a private `secret_key` into scout's state directory (`${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}/searxng/`), outside the plugin, so it survives plugin updates. No key or account is needed from the user.
- A `scout-searxng` container left by an older scout (from another compose project) is removed once and replaced with a fresh one; the script says so when it does. A current scout container that is already running is left as it is.

## Step 2 — Check prerequisites (stop cleanly if missing)

```bash
command -v docker  >/dev/null 2>&1 && echo "docker: ok"  || echo "docker: MISSING"
command -v openssl >/dev/null 2>&1 && echo "openssl: ok" || echo "openssl: MISSING"
```

- If `docker` is missing: stop. Tell the user SearXNG runs in a Docker container and point them at https://docs.docker.com/get-docker. scout keeps working with WebSearch in the meantime. Do not install anything for them.
- If `openssl` is missing: say the script needs it only once, to generate the `secret_key` on first start. If a key was generated before, the start still works; otherwise it stops with a message naming `openssl`. Run the script anyway and relay what it says.

These two checks and the start script are the only commands this skill runs.

## Step 3 — Start the container (invoke the script)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/services/searxng/start-searxng.sh"
```

The script can take a while on a cold start: `docker compose up -d` pulls the image on the first start before it returns, and the script then waits up to about 30 seconds for SearXNG to answer a JSON search. It exits **0** when SearXNG answers at `http://localhost:8911/`, and **1** when it does not, with the reason on stderr. Read the exit code and the output; do not guess.

## Step 4 — Relay the result

**Exit 0.** The script printed either `SearXNG already running at http://localhost:8911/` or `SearXNG running at http://localhost:8911/`. Say which. Either line can follow `removing container scout-searxng from compose project '...' (left by an older scout)`; if it does, say that the old container was replaced. Then tell the user:

- scout's discovery goes through SearXNG only when the `searxng` MCP server is registered. That is a one-time step: run `/scout:setup` and choose the SearXNG meta backend. If it is already registered, nothing more to do.
- Once both are in place, scout discovers URLs through SearXNG, and each source in the report carries a `discovery: searxng` note. A Claude Code session started before the MCP was registered needs a restart to see the tool.
- The container keeps running until they stop it: `docker stop scout-searxng`.

**Exit 1.** Relay the script's stderr reason in plain words, then say that scout falls back to WebSearch, so research still works. Map the reason to a fix where one is obvious:

| Script says | Tell the user |
|---|---|
| `docker not found` | Install Docker (https://docs.docker.com/get-docker), then run `/scout:meta` again. |
| `could not remove the old scout-searxng container` | An older scout's container is in the way and Docker refused to remove it. Usually the Docker daemon is not running (start Docker Desktop); otherwise run `docker rm -f scout-searxng` yourself, then run `/scout:meta` again. |
| `something answers on http://localhost:8911/, but not as SearXNG with JSON search` | Port 8911 is held by something that does not answer like scout's SearXNG. If `docker ps` shows `scout-searxng`, run `docker rm -f scout-searxng` and start again; otherwise stop whatever holds port 8911. |
| `... exists and was not written by scout (no .scout-owned marker)` | A `searxng` folder that scout did not create sits in the state directory. Move it aside, or set `SCOUT_STATE_DIR` to another directory. |
| `'docker compose up' failed:` plus Docker's output | Pass on Docker's own message. Usually the Docker daemon is not running (start Docker Desktop) or port 8911 is taken by something else. |
| `health-wait timed out after 30 s` | The container started but SearXNG did not answer a search yet (the image pull is already done by then; this is SearXNG's own startup). Run `/scout:meta` again in a minute. `docker logs scout-searxng` shows what it is doing. |
| `openssl not found` / `'openssl rand' failed` | Install OpenSSL, then run `/scout:meta` again. Only the first start needs it. |
| `... does not hold a hex secret; delete it to regenerate.` | The stored key is damaged. Deleting the named file lets the next start generate a fresh one. |
| `state directory must be an absolute path` / `lies inside the plugin cache` | `SCOUT_STATE_DIR` (or `XDG_STATE_HOME`) points somewhere unusable. Set it to an absolute path outside `~/.claude/plugins/cache/`, or unset it. |
| `plugin file missing:` | This plugin copy is incomplete. Reinstall or update scout. |

Never report success on exit 1.

## What this skill does NOT do

- Does not register the `searxng` MCP server — that is `/scout:setup`'s job.
- Does not stop the container, and removes one only when it was left by an older scout (from another compose project), to replace it. To stop it: `docker stop scout-searxng`.
- Does not install Docker, OpenSSL, or anything else — it only checks and points at the install page.
- Does not write into the plugin tree. The secret and the rendered settings live in scout's state directory.
