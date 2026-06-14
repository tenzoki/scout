---
description: Set up scout's optional depth layer by registering the browser-use MCP server, so a non-technical user does not hand-edit Claude Code's MCP config. Invoke when the user wants to "set up scout depth", "enable interactive browsing", "register browser-use", "turn on the depth layer", or "let scout drive a real browser". Registers a local Chromium browser-use stack pinned to the tested version with both no-cloud env vars baked in, and an OpenAI key the user supplies. Idempotent and non-destructive — depth is entirely OPTIONAL; scout works breadth-only without it.
allowed-tools: [Bash, Read, AskUserQuestion]
---

# /scout:setup — register scout's optional depth layer (browser-use)

This skill registers the **browser-use** MCP server so scout can drive a real local Chromium browser for pages the breadth layer cannot reach over plain HTTP (JavaScript-rendered content, owned-account logins, interactive interfaces).

**Depth is optional.** scout runs fine breadth-only. Without depth registered, scout records any page that genuinely needs an interactive browser as a "needs depth tools" gap in its report's blocked-sources table — it never silently drops a source. Run this skill only if you actually hit such pages.

The skill is **idempotent** and **non-destructive**: if `browser-use` is already registered, re-running removes the old user-scope entry and re-adds it with the tested pin and env vars (so a stale or broken registration is cleanly replaced); it never touches a server you registered at another scope, never deletes a project file, and never writes your OpenAI key into the repo.

The registration mechanics — the pin `browser-use[cli]@0.11.9`, both no-cloud env vars, the remove-then-add, and the verify — live in **one place**: `${CLAUDE_PLUGIN_ROOT}/skills/setup/register-browser-use.sh`. This skill drives the conversation and the key decision, then invokes that script. The script is the single source of truth for the registration command, so the pin and env vars are never duplicated in prose here. A technical user can also run the script directly without this skill.

Apply scout's short-form voice for everything you say to the user: read `${CLAUDE_PLUGIN_ROOT}/stilwerk/chat-voice-en.yaml` (or the target-language variant) and follow its intent — action-first, second person, plain words, no AI stock phrases. If no variant exists for the user's language, read the `-en` file and apply its intent in that language.

## Step 1 — State what this does, plainly

Tell the user, up front:

- This registers a local browser-use server so scout can drive a real Chromium browser when a page needs it.
- Depth is optional. scout already works breadth-only; this only adds the interactive-browser path.
- The browser runs entirely on their machine. No browser-use hosted cloud service. The only outbound call the depth layer makes is an ordinary OpenAI LLM call for content extraction (Step 3).
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

## Step 3 — Decide the OpenAI key path (never hardcode it, never write it into the repo)

The depth layer's two LLM-using tools — `browser_extract_content` (turn a page into structured text) and `retry_with_browser_use_agent` (the last-resort internal loop) — call an LLM. `browser_extract_content` is hardwired to OpenAI at the MCP layer in this version, so the key is an `OPENAI_API_KEY`. This is an ordinary external LLM call, the same kind scout already makes; it is not a "no cloud" violation (the no-cloud rule bans browser-use's hosted *service*, not external LLMs).

Prefer a key already in the environment. Check whether one is set, **without printing it**:

```bash
if [ -n "${OPENAI_API_KEY:-}" ]; then echo "OPENAI_API_KEY: present in environment (length ${#OPENAI_API_KEY})"; else echo "OPENAI_API_KEY: not set"; fi
```

Make the decision with the user via `AskUserQuestion`, then carry it into Step 4:

- **If present:** ask whether scout should **inherit** the key already in their environment (recommended — the key then never lands in the MCP config file, and never appears in any process argument) or **pin** it into the config. Inherit is the default. If they choose inherit, you will invoke the script with `BROWSERUSE_INHERIT=1`. If they choose pin, collect the key as below.
- **If not set:** ask the user to supply their OpenAI key via `AskUserQuestion`. Read it from them directly. You will pass it to the script via the `BROWSERUSE_OPENAI_KEY` env var in Step 4 — it goes only into Claude Code's user-scope MCP config.

Whichever path: **never** echo the full key back into chat, never write it into any file in the repo, and never put it in a commit.

## Step 4 — Register the server (invoke the script)

Invoke the single-source-of-truth script. It removes any existing user-scope `browser-use`, adds it fresh under the **exact** name `browser-use` (coupled to scout's allow-list: scout's tools are `mcp__browser-use__browser_navigate`, `mcp__browser-use__browser_get_state`, and so on — a different name means scout silently falls back to breadth-only), at **user scope** so depth works from any project directory, with the tested pin and both mandatory no-cloud env vars baked in, and then verifies.

Pass the key decision from Step 3 via env so nothing key-shaped is typed into a visible command line by hand:

**Environment-inherit path** (user chose to inherit an existing `OPENAI_API_KEY`):

```bash
BROWSERUSE_INHERIT=1 bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/register-browser-use.sh"
```

**Pinned-key path** (user supplied a key to write into the config):

```bash
BROWSERUSE_OPENAI_KEY="<the key the user supplied>" bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/register-browser-use.sh"
```

Substitute the real key only in the actual command you run; never display the substituted command back to the user with the key in it. The script prints its own prerequisite, registration, and verification output.

**Fallback — if the script cannot run in this environment** (e.g. the CLI registration forms fail in this Claude Code version): print the exact JSON `mcpServers` block below for the user to paste into their MCP settings by hand, and tell them plainly that you are falling back to the manual paste because the scripted registration was unavailable:

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

Do not guess a different registration command. Use the script, or the manual JSON block.

## Step 5 — Confirm the registration took

The script ends by running `claude mcp get browser-use` and printing the result. Read its output: it should show `Type: stdio`, `Command: uvx`, args including `browser-use[cli]@0.11.9` and `--mcp`, and the env carrying `ANONYMIZED_TELEMETRY` and `BROWSER_USE_VERSION_CHECK`. Do not print any `OPENAI_API_KEY` value from this output.

If the entry is missing or wrong, the registration did not take — report the actual script output and stop so the user can retry, rather than reporting a false success.

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
