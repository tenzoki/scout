# Smoke test — browser-use Anthropic depth layer

This runbook verifies that scout's depth-layer shim
(`scout_browseruse_anthropic.py`) starts the pinned browser-use MCP server and
runs `browser_extract_content` on **Anthropic** instead of OpenAI.

**The model cannot self-verify this.** A live run needs a real `ANTHROPIC_API_KEY`
and a working local Chromium, neither of which exists in an assistant session. A
**human** runs every step below. The change is not DONE until a human has run it
and confirmed each step.

Under scout's pin discipline, re-run this whole runbook on every browser-use
version bump, after re-confirming the shim's patched symbols still exist
(`server.ChatOpenAI`, `BrowserUseServer._init_browser_session`, `ChatAnthropic`).

Throughout, `<plugin>` is your scout plugin root:
- installed copy: `~/.scout`
- source tree: the `scout/` repo checkout

So the shim path is
`<plugin>/services/browser-use-anthropic/scout_browseruse_anthropic.py`.

---

## 1. Export your Anthropic key

Put the real key in the shell only — never in a file.

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

## 2. Direct shim launch sanity (no Claude Code)

Launch the shim by hand and confirm the MCP server comes up on stdio. This
exercises the import guard and the Anthropic patch without involving Claude Code
or a registration.

```bash
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY SCOUT_DEPTH_PROVIDER=anthropic ANONYMIZED_TELEMETRY=False BROWSER_USE_VERSION_CHECK=false uvx --from "browser-use[cli]@0.11.9" python <plugin>/services/browser-use-anthropic/scout_browseruse_anthropic.py --mcp
```

Confirm:
- The server starts on stdio (it waits for MCP traffic; it does not exit on its own).
- You do **not** see the import-guard diagnostic
  (`scout-browseruse-anthropic: missing required browser-use symbol ...`) followed
  by an `exit 1`. If you do, an upstream rename broke the shim — re-confirm the
  patched symbols against the current browser-use version before going further.
- You do **not** see the `Error: LLM not initialized (set OPENAI_API_KEY)` path
  when extraction later runs (that error means the Anthropic patch did not take).

Stop the process (Ctrl-C) once it has come up cleanly.

## 3. Register, then drive a real extraction

Register the depth layer through the normal path:

```bash
# via the skill:
/scout:setup

# or directly, inheriting the key from your environment:
BROWSERUSE_INHERIT=1 bash <plugin>/skills/setup/register-browser-use.sh
```

Then, in a scout session, drive a JavaScript-rendered page and run an
extraction with a specific query:

1. `browser_navigate` to a JS-rendered page (one that plain HTTP cannot read).
2. `browser_get_state` to confirm the page loaded.
3. `browser_extract_content` with a **specific query** (not a bare "summarize").

Confirm:
- The extract **returns query-shaped text** — content that answers your query,
  not the `Error: LLM not initialized (set OPENAI_API_KEY)` error.
- The call **hit Anthropic, not OpenAI.** Verify one of:
  - The Anthropic console shows the usage/billing for the call, **or**
  - Temporarily `unset OPENAI_API_KEY` before the run, so any accidental OpenAI
    code path would error instead of silently succeeding. A clean extraction
    with no OpenAI key present is direct evidence the call went to Anthropic.

## 4. Confirm no-cloud egress stayed off

Both no-cloud env vars must be present in the registered server:

```bash
claude mcp get browser-use
```

Confirm the `env` block carries both:
- `ANONYMIZED_TELEMETRY=False`
- `BROWSER_USE_VERSION_CHECK=false`

These disable browser-use's PostHog telemetry ping and its version-check ping.
Without them, the server phones home on startup.

---

## Pass criteria

All four hold:
1. Direct shim launch starts the MCP server on stdio — no import-guard exit, no OpenAI-not-init error.
2. `browser_extract_content` returns query-shaped text.
3. The extraction hit Anthropic (console usage, or success with no OpenAI key set).
4. Both no-cloud env vars present in `claude mcp get browser-use`.

Record the result (date, browser-use version, Claude Code version, pass/fail per
step) in `fusion-workbench/history/` so the next bump has a baseline.
