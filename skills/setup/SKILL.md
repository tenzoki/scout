---
description: Set up scout's optional depth layer by registering the browser-use MCP server, so a non-technical user does not hand-edit Claude Code's MCP config. Invoke when the user wants to "set up scout depth", "enable interactive browsing", "register browser-use", "turn on the depth layer", or "let scout drive a real browser". Registers a local Chromium browser-use stack pinned to the tested version with both no-cloud env vars baked in, and an OpenAI key the user supplies. Idempotent and non-destructive — depth is entirely OPTIONAL; scout works breadth-only without it.
allowed-tools: [Bash, Read, AskUserQuestion]
---

# /scout:setup — register scout's optional depth layer (browser-use)

This skill registers the **browser-use** MCP server so scout can drive a real local Chromium browser for pages the breadth layer cannot reach over plain HTTP (JavaScript-rendered content, owned-account logins, interactive interfaces).

**Depth is optional.** scout runs fine breadth-only. Without depth registered, scout records any page that genuinely needs an interactive browser as a "needs depth tools" gap in its report's blocked-sources table — it never silently drops a source. Run this skill only if you actually hit such pages.

The skill is **idempotent** and **non-destructive**: if `browser-use` is already registered, re-running removes the old user-scope entry and re-adds it with the tested pin and env vars (so a stale or broken registration is cleanly replaced); it never touches a server you registered at another scope, never deletes a project file, and never writes your OpenAI key into the repo.

Apply scout's short-form voice for everything you say to the user: read `${CLAUDE_PLUGIN_ROOT}/stilwerk/chat-voice-en.yaml` (or the target-language variant) and follow its intent — action-first, second person, plain words, no AI stock phrases. If no variant exists for the user's language, read the `-en` file and apply its intent in that language.

## Step 1 — State what this does, plainly

Tell the user, up front:

- This registers a local browser-use server so scout can drive a real Chromium browser when a page needs it.
- Depth is optional. scout already works breadth-only; this only adds the interactive-browser path.
- The browser runs entirely on their machine. No browser-use hosted cloud service. The only outbound call the depth layer makes is an ordinary OpenAI LLM call for content extraction (Step 3).
- Nothing installs silently. If a prerequisite is missing, the skill stops and points them at the install page.

## Step 2 — Check prerequisites (stop cleanly if missing)

```bash
command -v claude >/dev/null 2>&1 && echo "claude: ok" || echo "claude: MISSING"
command -v uvx    >/dev/null 2>&1 && echo "uvx: ok"    || echo "uvx: MISSING"
```

- If `claude` is missing: stop. Tell the user the Claude Code CLI is not on their PATH and point them at https://docs.claude.com/en/docs/claude-code. Do not continue.
- If `uvx` is missing: stop. `uvx` ships with **uv**. Point them at https://github.com/astral-sh/uv to install uv (which provides `uvx`), then re-run `/scout:setup`. Do not install anything for them.

Only continue when both report `ok`.

If the server is already registered, Step 4 removes the old user-scope entry and re-adds it with the tested config (the CLI's `add`/`add-json` refuse to overwrite an existing server, so a clean remove-then-add is what makes the re-run replace it) — say so and continue:

```bash
claude mcp get browser-use >/dev/null 2>&1 && echo "browser-use: already registered (will re-register with the tested pin)" || echo "browser-use: not yet registered"
```

## Step 3 — Obtain the OpenAI key (never hardcode it, never write it into the repo)

The depth layer's two LLM-using tools — `browser_extract_content` (turn a page into structured text) and `retry_with_browser_use_agent` (the last-resort internal loop) — call an LLM. `browser_extract_content` is hardwired to OpenAI at the MCP layer in this version, so the key is an `OPENAI_API_KEY`. This is an ordinary external LLM call, the same kind scout already makes; it is not a "no cloud" violation (the no-cloud rule bans browser-use's hosted *service*, not external LLMs).

Prefer a key already in the environment. Check whether one is set, **without printing it**:

```bash
if [ -n "${OPENAI_API_KEY:-}" ]; then echo "OPENAI_API_KEY: present in environment (length ${#OPENAI_API_KEY})"; else echo "OPENAI_API_KEY: not set"; fi
```

- **If present:** confirm with the user via `AskUserQuestion` that scout should use the key already in their environment for the depth layer. If they say yes, register the server **without** an explicit `OPENAI_API_KEY` env entry so the running session inherits it from the environment — that way the key never lands in the MCP config file. (If you prefer it pinned into the config, ask; then register with the key as shown in Step 4's key-supplied variant.)
- **If not set:** ask the user to supply their OpenAI key. Read it from them directly. **Never** echo the full key back into chat, never write it into any file in the repo, and never put it in a commit. It goes only into Claude Code's user-scope MCP config via the registration command in Step 4.

Whichever path: never print, log, or commit the full key.

## Step 4 — Register the server (verified mechanism)

Register the server under the **exact** name `browser-use`. The name is coupled to scout's allow-list: scout's tools are named `mcp__browser-use__browser_navigate`, `mcp__browser-use__browser_get_state`, and so on. If you register under a different name, scout cannot see the depth tools and silently falls back to breadth-only. Use the name `browser-use`.

The pin is `browser-use[cli]@0.11.9` — the version scout's depth layer is built and verified against. Both no-cloud env vars are mandatory: `ANONYMIZED_TELEMETRY=False` and `BROWSER_USE_VERSION_CHECK=false`. They disable browser-use's two on-by-default outbound pings (the PostHog telemetry call and the version-check call). Without them, the server quietly phones home on startup. Include both, every time.

Register at **user scope** (`-s user`) so depth works from any project directory, not just the current one.

**First, clear any existing user-scope registration.** The CLI's `add`/`add-json` refuse to overwrite an existing server (`add-json` prints "already exists" and keeps the OLD config; `add` exits 1), so a re-run would otherwise silently keep a stale or broken entry. Remove the user-scope `browser-use` first, then add fresh:

```bash
claude mcp remove browser-use -s user >/dev/null 2>&1 || true
```

Scope the remove to `-s user` so it only touches the registration this skill owns — a `browser-use` server the user deliberately set up at project or local scope is left untouched. The `|| true` keeps a first run (nothing to remove) from erroring. After this remove, run one of the add forms below.

**Primary mechanism — `claude mcp add-json` (reproduces the README JSON block exactly).**

If the user has a key to pin into the config (Step 3 "not set" path, or they chose to pin it):

```bash
claude mcp add-json browser-use -s user '{
  "type": "stdio",
  "command": "uvx",
  "args": ["browser-use[cli]@0.11.9", "--mcp"],
  "env": {
    "OPENAI_API_KEY": "PASTE_THE_KEY_HERE",
    "ANONYMIZED_TELEMETRY": "False",
    "BROWSER_USE_VERSION_CHECK": "false"
  }
}'
```

Substitute the real key for `PASTE_THE_KEY_HERE` only in the actual command you run; never display the substituted command back to the user with the key in it.

If the user confirmed an environment key should be inherited (Step 3 "present" path), omit the `OPENAI_API_KEY` entry so the session inherits it:

```bash
claude mcp add-json browser-use -s user '{
  "type": "stdio",
  "command": "uvx",
  "args": ["browser-use[cli]@0.11.9", "--mcp"],
  "env": {
    "ANONYMIZED_TELEMETRY": "False",
    "BROWSER_USE_VERSION_CHECK": "false"
  }
}'
```

**Equivalent flag form** (`claude mcp add` with `-e KEY=value`), if you prefer it — same result, same pin, same env, same user scope:

```bash
claude mcp add browser-use uvx -s user \
  -e OPENAI_API_KEY="PASTE_THE_KEY_HERE" \
  -e ANONYMIZED_TELEMETRY=False \
  -e BROWSER_USE_VERSION_CHECK=false \
  -- "browser-use[cli]@0.11.9" --mcp
```

(Drop the `OPENAI_API_KEY` line for the environment-inherit path.)

**Fallback — if neither CLI form works in this Claude Code version**: print the exact JSON `mcpServers` block from the README for the user to paste into their MCP settings by hand, and tell them plainly that you are falling back to the manual paste because the CLI registration was unavailable:

```json
{
  "mcpServers": {
    "browser-use": {
      "command": "uvx",
      "args": ["browser-use[cli]@0.11.9", "--mcp"],
      "env": {
        "OPENAI_API_KEY": "<your own OpenAI API key>",
        "ANONYMIZED_TELEMETRY": "False",
        "BROWSER_USE_VERSION_CHECK": "false"
      }
    }
  }
}
```

Do not guess a different registration command. Use one of the verified forms above, or the manual JSON block.

## Step 5 — Verify the registration took

Confirm the server is registered with the right type, command, args, and env:

```bash
claude mcp get browser-use 2>&1
```

Check the output shows `Type: stdio`, `Command: uvx`, args including `browser-use[cli]@0.11.9` and `--mcp`, and the env carrying `ANONYMIZED_TELEMETRY` and `BROWSER_USE_VERSION_CHECK`. (`claude mcp list` also lists it among the configured servers.) Do not print any `OPENAI_API_KEY` value from this output.

If the entry is missing or wrong, the registration did not take — report the actual `claude mcp get` output and stop so the user can retry, rather than reporting a false success.

On success, tell the user: depth is registered. Re-run scout — pages that need an interactive browser will now be driven in a real local Chromium, and depth findings will carry the `depth (browser-use, manual drive)` method tag in the report.

## Step 6 — Set expectations honestly (no captcha; foreground handoff)

Be clear-eyed, so the user is not surprised later:

- **No captcha-solving.** Nothing in this local, no-cloud setup reliably defeats a modern captcha. That capability was given up by choosing local browser-use over the hosted cloud. scout caps captcha effort at a few steps and moves on.
- **Foreground handoff for walls.** When scout hits a captcha, login, hard 403, or interstitial on an essential source, it does not silently drop it. It returns a blocked-sources block naming the URL, the wall type, and what a human must do. You clear the wall live in a foreground browser-use session (the persistent local Chromium profile at `~/.config/browseruse/profiles/default` captures the authenticated state), then re-run scout to reach the now-unlocked source.

Point the user at the README's **Optional depth layer (browser-use)** section for the full handoff write-up. Do not re-narrate the whole thing here.

## What this skill does NOT do

- Does not install `uv`/`uvx`, Claude Code, or a browser — it only checks and points at the install page if missing.
- Does not write your OpenAI key into any repo file, print it, or commit it.
- Does not change scout's agent, plugin manifest, or style profiles.
- Does not register anything if a prerequisite is missing — it stops cleanly.
