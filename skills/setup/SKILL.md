---
description: Set up scout's optional add-ons by registering their MCP servers, so a non-technical user does not hand-edit Claude Code's MCP config. Covers two optional layers — the browser-use depth layer (interactive browsing) and the SearXNG meta discovery backend (self-hosted metasearch). Invoke when the user wants to "set up scout depth", "enable interactive browsing", "register browser-use", "turn on the depth layer", "let scout drive a real browser", "set up scout meta", "enable SearXNG", or "register the metasearch backend". browser-use registers a local Chromium stack pinned to the tested version with both no-cloud env vars and an Anthropic key the user supplies (extraction runs on Anthropic via scout's shim); SearXNG registers the self-hosted metasearch MCP (no key). Idempotent and non-destructive — both layers are entirely OPTIONAL; scout works breadth-only with WebSearch without either.
allowed-tools: [Bash, Read, AskUserQuestion]
---

# /scout:setup — register scout's optional add-ons (browser-use depth layer, SearXNG meta backend)

This skill registers scout's optional MCP-backed add-ons. There are two, and they are independent — register either, both, or neither:

- **browser-use depth layer** — a real local Chromium browser for pages the breadth layer cannot reach over plain HTTP (JavaScript-rendered content, owned-account logins, interactive interfaces). Covered in the steps immediately below.
- **SearXNG meta discovery backend** — a self-hosted metasearch engine scout uses to *discover* URLs instead of the built-in `WebSearch`. Covered in **Optional: register the SearXNG meta backend** near the end.

Ask the user which they want (or offer both). The two paths share nothing except this skill's voice and the remove-then-add discipline. The browser-use path below is unchanged; the SearXNG path is opt-in, discovery-only, and needs no key.

## browser-use depth layer

This registers the **browser-use** MCP server so scout can drive a real local Chromium browser for pages the breadth layer cannot reach over plain HTTP (JavaScript-rendered content, owned-account logins, interactive interfaces).

**Depth is optional.** scout runs fine breadth-only. Without depth registered, scout records any page that genuinely needs an interactive browser as a "needs depth tools" gap in its report's blocked-sources table — it never silently drops a source. Run this skill only if you actually hit such pages.

The skill is **idempotent** and **non-destructive**: if `browser-use` is already registered, re-running removes the old user-scope entry and re-adds it with the tested pin and env vars (so a stale or broken registration is cleanly replaced); it never touches a server you registered at another scope, never deletes a project file, and never writes your Anthropic key into the repo.

The registration mechanics — the pin `browser-use[cli]@0.11.9`, both no-cloud env vars, the remove-then-add, and the verify — live in **one place**: `${CLAUDE_PLUGIN_ROOT}/skills/setup/register-browser-use.sh`. This skill drives the conversation and the key decision, then invokes that script. The script is the single source of truth for the registration command, so the pin and env vars are never duplicated in prose here. A technical user can also run the script directly without this skill.

Apply scout's short-form voice for everything you say to the user: read `${CLAUDE_PLUGIN_ROOT}/stilwerk/chat-voice-en.yaml` (or the target-language variant) and follow its intent — action-first, second person, plain words, no AI stock phrases. If no variant exists for the user's language, read the `-en` file and apply its intent in that language.

## Step 1 — State what this does, plainly

Tell the user, up front:

- This registers a local browser-use server so scout can drive a real Chromium browser when a page needs it.
- Depth is optional. scout already works breadth-only; this only adds the interactive-browser path.
- The browser runs entirely on their machine. No browser-use hosted cloud service. The only outbound call the depth layer makes is an ordinary Anthropic LLM call for content extraction (Step 3), which runs on Anthropic via scout's shim.
- Nothing installs silently. If a prerequisite is missing, the skill stops and points them at the install page.

## Step 2 — Check prerequisites (stop cleanly if missing)

The script checks prerequisites itself and stops cleanly if either is missing, but check here too so you can explain the fix in scout's voice before handing off:

```bash
command -v claude >/dev/null 2>&1 && echo "claude: ok" || echo "claude: MISSING"
command -v uvx    >/dev/null 2>&1 && echo "uvx: ok"    || echo "uvx: MISSING"
```

- If `claude` is missing: stop. Tell the user the Claude Code CLI is not on their PATH and point them at https://docs.claude.com/en/docs/claude-code. Do not continue.
- If `uvx` is missing: stop. `uvx` ships with **uv**. Point them at https://github.com/astral-sh/uv to install uv (which provides `uvx`), then re-run `/scout:setup`. Do not install anything for them.

Only continue when both report `ok`.

If the server is already registered, the script removes the old user-scope entry and re-adds it with the tested config (the CLI's `add`/`add-json` refuse to overwrite an existing server, so a clean remove-then-add is what makes the re-run replace it) — say so and continue:

```bash
claude mcp get browser-use >/dev/null 2>&1 && echo "browser-use: already registered (will re-register with the tested pin)" || echo "browser-use: not yet registered"
```

## Step 3 — Decide the Anthropic key path (never hardcode it, never write it into the repo)

The depth layer's extraction tool, `browser_extract_content` (turn a page into structured text), calls an LLM. scout's shim runs that call on Anthropic, so the key is an `ANTHROPIC_API_KEY`. This is an ordinary external LLM call, the same kind scout already makes; it is not a "no cloud" violation (the no-cloud rule bans browser-use's hosted *service*, not external LLMs). The last-resort `retry_with_browser_use_agent` loop stays OpenAI/Bedrock-only upstream — the shim patches extraction, not the agent loop — so reaching for it still needs an OpenAI or Bedrock key.

Prefer a key already in the environment. Check whether one is set, **without printing it**:

```bash
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then echo "ANTHROPIC_API_KEY: present in environment (length ${#ANTHROPIC_API_KEY})"; else echo "ANTHROPIC_API_KEY: not set"; fi
```

Make the decision with the user via `AskUserQuestion`, then carry it into Step 4:

- **If present:** ask whether scout should **inherit** the key already in their environment (recommended — the key then never lands in the MCP config file, and never appears in any process argument) or **pin** it into the config. Inherit is the default. If they choose inherit, you will invoke the script with `BROWSERUSE_INHERIT=1`. If they choose pin, collect the key as below.
- **If not set:** ask the user to supply their Anthropic key via `AskUserQuestion`. Read it from them directly. You will pass it to the script via the `BROWSERUSE_ANTHROPIC_KEY` env var in Step 4 — it goes only into Claude Code's user-scope MCP config.

> **Inherit mode reads the key at launch, not at registration — flag this whenever inherit is on the table.** With inherit, no key is written to the config; the browser-use MCP server reads `ANTHROPIC_API_KEY` from the environment of the Claude Code process *when that process starts*. So the key must be exported **before** Claude Code launches, in the shell that launches it.
>
> Two consequences to tell the user plainly:
>
> - **If the key was NOT in this session's environment when Claude Code started** (the `ANTHROPIC_API_KEY: not set` check above), then inherit cannot see it — even if you register now. Exporting it inside this running session is too late: the server inherits the environment that was live at Claude Code's launch. They must export the key and **restart Claude Code** for inherit to pick it up. If they don't want to restart, pin the key instead (`BROWSERUSE_ANTHROPIC_KEY=...`).
> - **Make it durable.** Recommend putting `export ANTHROPIC_API_KEY=sk-ant-...` in a file they source on shell start (e.g. a private `~/.scout-env` sourced from their shell profile), kept **outside any repo** so the key never lands in version control. That way every future shell — and every Claude Code launch from it — already has the key.
>
> The register script also warns loudly on this exact case (inherit selected with no key in the registering environment), so the warning is reinforced at registration time. Pinning the key sidesteps the whole launch-timing question.

Whichever path: **never** echo the full key back into chat, never write it into any file in the repo, and never put it in a commit.

## Step 4 — Register the server (invoke the script)

Invoke the single-source-of-truth script. It removes any existing user-scope `browser-use`, adds it fresh under the **exact** name `browser-use` (coupled to scout's allow-list: scout's tools are `mcp__browser-use__browser_navigate`, `mcp__browser-use__browser_get_state`, and so on — a different name means scout silently falls back to breadth-only), at **user scope** so depth works from any project directory, with the tested pin and both mandatory no-cloud env vars baked in, and then verifies.

Pass the key decision from Step 3 via env so nothing key-shaped is typed into a visible command line by hand:

**Environment-inherit path** (user chose to inherit an existing `ANTHROPIC_API_KEY`):

```bash
BROWSERUSE_INHERIT=1 bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/register-browser-use.sh"
```

When you run the inherit path, read the script's output to the user — it prints a notice that the key is read at launch time from the shell that starts Claude Code, and a loud WARNING if `ANTHROPIC_API_KEY` was absent from the registering environment. Do not bury that warning; repeat its gist in scout's voice (export the key before launching Claude Code, restart if it wasn't set when this session started).

**Pinned-key path** (user supplied a key to write into the config):

```bash
BROWSERUSE_ANTHROPIC_KEY="<the key the user supplied>" bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/register-browser-use.sh"
```

Substitute the real key only in the actual command you run; never display the substituted command back to the user with the key in it. The script prints its own prerequisite, registration, and verification output.

**Fallback — if the script cannot run in this environment** (e.g. the CLI registration forms fail in this Claude Code version): print the exact JSON `mcpServers` block below for the user to paste into their MCP settings by hand, and tell them plainly that you are falling back to the manual paste because the scripted registration was unavailable:

```json
{
  "mcpServers": {
    "browser-use": {
      "command": "uvx",
      "args": [
        "--from", "browser-use[cli]@0.11.9",
        "python", "${CLAUDE_PLUGIN_ROOT}/services/browser-use-anthropic/scout_browseruse_anthropic.py",
        "--mcp"
      ],
      "env": {
        "ANTHROPIC_API_KEY": "<your own Anthropic API key>",
        "SCOUT_DEPTH_PROVIDER": "anthropic",
        "ANONYMIZED_TELEMETRY": "False",
        "BROWSER_USE_VERSION_CHECK": "false"
      }
    }
  }
}
```

Do not guess a different registration command. Use the script, or the manual JSON block.

## Step 5 — Confirm the registration took

The script ends by running `claude mcp get browser-use` and printing the result. Read its output: it should show `Type: stdio`, `Command: uvx`, args including `--from`, `browser-use[cli]@0.11.9`, the shim path `services/browser-use-anthropic/scout_browseruse_anthropic.py`, and `--mcp`, and the env carrying `SCOUT_DEPTH_PROVIDER`, `ANONYMIZED_TELEMETRY`, and `BROWSER_USE_VERSION_CHECK`. Do not print any `ANTHROPIC_API_KEY` value from this output.

If the entry is missing or wrong, the registration did not take — report the actual script output and stop so the user can retry, rather than reporting a false success.

On success, tell the user: depth is registered. Re-run scout — pages that need an interactive browser will now be driven in a real local Chromium, and depth findings will carry the `depth (browser-use, manual drive)` method tag in the report. If they registered via inherit, remind them once more that the depth layer only works when `ANTHROPIC_API_KEY` is live in the shell that launches scout/Claude Code — a green registration alone does not prove the key is reachable at runtime.

## Step 6 — Set expectations honestly (no captcha; foreground handoff)

Be clear-eyed, so the user is not surprised later:

- **No captcha-solving.** Nothing in this local, no-cloud setup reliably defeats a modern captcha. That capability was given up by choosing local browser-use over the hosted cloud. scout caps captcha effort at a few steps and moves on.
- **Foreground handoff for walls.** When scout hits a captcha, login, hard 403, or interstitial on an essential source, it does not silently drop it. It returns a blocked-sources block naming the URL, the wall type, and what a human must do. You clear the wall live in a foreground browser-use session (the persistent local Chromium profile at `~/.config/browseruse/profiles/default` captures the authenticated state), then re-run scout to reach the now-unlocked source.

Point the user at the README's **Optional depth layer (browser-use)** section for the full handoff write-up. Do not re-narrate the whole thing here.

## Optional: register the SearXNG meta backend

This path is fully independent of browser-use. Run it when the user wants scout to discover URLs through a **self-hosted SearXNG metasearch engine** instead of the built-in `WebSearch`. Apply the same scout voice as above.

**State what it is, plainly.** SearXNG is scout's **opt-in discovery backend** — it finds URLs. It is **not** a fetcher: `WebFetch` and the depth layer still do all content fetching. scout works fine without it (default discovery is `WebSearch`), so this is purely additive. It is **self-hosted** and needs **no API key** — the skill collects nothing secret for SearXNG. There are two coupled pieces: this skill **registers the MCP**, and `scout meta` **starts the local SearXNG container**. Both are needed for scout to actually use it; if the MCP is registered but the container is not running (no `scout meta`), scout's reachability probe fails and it falls back to `WebSearch` cleanly.

**Check prerequisites (stop cleanly if missing).** SearXNG registration needs `npx` (from Node) for the MCP runner, and Docker to actually run the container via `scout meta`:

```bash
command -v claude >/dev/null 2>&1 && echo "claude: ok" || echo "claude: MISSING"
command -v npx    >/dev/null 2>&1 && echo "npx: ok"    || echo "npx: MISSING"
command -v docker >/dev/null 2>&1 && echo "docker: ok" || echo "docker: MISSING (needed for 'scout meta' to start the container)"
```

- If `claude` or `npx` is missing: stop. `npx` ships with Node.js — point the user at https://nodejs.org. Do not continue registration.
- If `docker` is missing: the MCP can still be registered, but tell the user plainly that `scout meta` cannot start the container until Docker is installed (https://docs.docker.com/get-docker), so scout will fall back to WebSearch until then. Let the user decide whether to register now or install Docker first.

**Register the server (invoke the script).** The registration mechanics — the `mcp-searxng` pin, the `SEARXNG_URL`, the remove-then-add, the verify — live in one place: `${CLAUDE_PLUGIN_ROOT}/skills/setup/register-searxng.sh`. Drive it the same way you drive the browser-use script. It writes no secret:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/register-searxng.sh"
```

The script removes any existing user-scope `searxng`, adds it fresh under the **exact** name `searxng` (coupled to scout's allow-list prefix `mcp__searxng__web_search` — a different name means scout silently falls back to WebSearch), at user scope, with `SEARXNG_URL=http://localhost:8911`, then verifies with `claude mcp get searxng`.

**Confirm and set expectations.** Read the script's verify output: it should show `Type: stdio`, `Command: npx`, the pinned `mcp-searxng` arg, and `SEARXNG_URL`. On success, tell the user: the meta backend is registered. Start scout with `scout meta` (not plain `scout`) so the SearXNG container comes up; scout then discovers URLs through SearXNG and each discovered source carries a `discovery: searxng` note in the report. If they run plain `scout`, or if the container is not up, scout discovers with WebSearch — no failure either way. Point them at the README's **Optional metasearch backend (SearXNG)** section for the full picture.

## What this skill does NOT do

- Does not install `uv`/`uvx`, `npx`/Node, Docker, Claude Code, or a browser — it only checks and points at the install page if missing.
- Does not write your Anthropic key into any repo file, print it, or commit it. The SearXNG path writes no secret at all.
- Does not start the SearXNG container — that is `scout meta`'s job. This skill only registers the MCP.
- Does not change scout's agent, plugin manifest, or style profiles.
- Does not register anything if a prerequisite is missing — it stops cleanly.
