# scout

A web-research plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview). You give scout a fully-specified research question; it runs multi-source web research with inline cross-source verification and writes **one cited report file** per run. It returns to you only a compact cited summary plus the path to that report.

The plugin is named **scout**; its single AI agent is also named **scout** (dispatch with `claude --agent scout:scout`).

scout was carved out of [flight](https://github.com/tenzoki/flight) so that research's context-firehose traffic — dozens of search results and fetched pages — stays out of a working conversation. You run scout in its own session, get one report file, and hand that file to flight's `pilot` for synthesis. Same family.

## The two-layer model

scout has two layers, and you can stop after the first:

- **Breadth (works immediately).** No setup beyond installing the plugin. scout fires parallel web searches and page fetches, reads the results together, and cross-verifies each claim across sources over plain HTTP. This is the whole product for most questions.
- **Depth (optional, registered separately).** An add-on for pages that genuinely need an interactive browser (JavaScript-rendered content, owned-account logins). It is a separate MCP server you register yourself; until you do, scout runs breadth-only and flags any depth-needing page as a gap in the report rather than silently dropping it. See **Optional depth layer (browser-use)** below.

A user who never registers the depth layer keeps a fully working breadth research plugin.

## What scout produces

scout writes one cited report per run to `scout-workbench/research/<prefix>-<topic>.md` and returns a compact summary plus that path. The report has **two layers**:

- **A reader-facing deliverable on top** — a headline table (one row per entity, each with a confidence and a method/source column), an executive summary, per-entity verification, and a sourced "behind the numbers" analysis section. This reads as a clean briefing.
- **The full audit trail beneath** — the per-claim record where every figure is traceable: **claim → sources → method → confidence → verification**, followed by a blocked-sources table and the full list of sources consulted.

The two are the same report, not alternatives. The deliverable layer is a *view* of the audit trail and can never state a figure more confidently than its underlying claim block warrants — every headline and summary number carries its confidence and a pointer to its source, so polish can never quietly over-claim provenance. If a primary source was reached but not actually read, the headline says so.

scout returns only the compact summary inline — never the full report — so your calling session does not get re-flooded with the research traffic. That session-isolation is scout's whole reason to exist.

### Hand the report to flight's pilot

The intended flow is a bring-a-document handoff:

1. Run scout on a fully-specified question. It writes the report and prints the path.
2. Open that report file in [flight](https://github.com/tenzoki/flight)'s `pilot` agent (`claude --agent flight:pilot`) and discuss, summarize, or draft from it.

scout does the research; pilot does the synthesis.

## Specify the question fully before you run

**scout cannot ask you clarifying questions mid-run.** It runs autonomously from the moment you dispatch it. So state the full question up front: scope, constraints, language, any source preferences or exclusions, and how deep to go. If the question is under-specified, scout does its best and records the ambiguity in the report rather than stalling — but a tighter question gets a tighter report.

## Quick start (recommended — one line, no git)

In your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/tenzoki/scout/main/install.sh | bash
```

This downloads scout over plain HTTPS into `~/.scout` and installs a `scout`
launcher. No git, no SSH, no Claude Code marketplace. Then, in any project folder:

```bash
scout          # starts Claude Code with the scout agent loaded
```

- **Update:** `scout --update` (or re-run the one-liner above).
- **Uninstall:** `scout --uninstall`.
- **Where it lives:** `scout --where` (prints the install dir).

#### Pin or rotate the depth-layer key with `--key`

If you use the optional depth layer (browser-use), you can pin or rotate its Anthropic key from the launcher in two forms:

```bash
scout --update --key sk-ant-...   # update AND re-register the depth layer with this key
scout --key sk-ant-...            # reset the key only — re-registers the depth layer, no re-download
```

Both forms also accept the equals spelling (`--key=sk-ant-...`). The key is exported as `BROWSERUSE_ANTHROPIC_KEY` for the registration and is never printed.

- **Security caveat.** A key passed in `argv` can land in your shell history and is visible in `ps aux` while the command runs. On a shared machine, prefer the env-prefix form `BROWSERUSE_ANTHROPIC_KEY=sk-ant-... scout --update` or the register script's hidden interactive prompt (`bash ~/.scout/skills/setup/register-browser-use.sh`) instead.
- **Bootstrap quirk (first time only).** `--key` is parsed by the *currently installed* launcher, so the very first update from a launcher that predates this flag won't recognise it. Do that one update with the env-prefix form — `BROWSERUSE_ANTHROPIC_KEY=sk-ant-... scout --update` — and from then on `--key` works.

## Quick start (Windows)

Windows gets the same no-git path. Paste this one line into **cmd.exe** or
**PowerShell**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/tenzoki/scout/main/install.ps1 | iex"
```

Prefer not to type? Download the repo's `install.cmd` and **double-click it** —
it confirms the one prerequisite, then runs the exact same one-liner.

This downloads scout over plain HTTPS into `%USERPROFILE%\.scout` and installs a
`scout` launcher on your **User PATH**. No git, no SSH, no Claude Code
marketplace — the only thing you need already installed is the Claude Code CLI.
The `irm | iex` form runs in memory, so it is not blocked by the default
PowerShell ExecutionPolicy that gates `.ps1` files on disk. Then, in any project
folder:

```powershell
scout          # starts Claude Code with the scout agent loaded
```

- **Update:** `scout --update` (or re-run the one-liner above).
- **Uninstall:** `scout --uninstall`.
- **Where it lives:** `scout --where` (prints the install dir).

The launcher is added to your User PATH automatically; open a **new** terminal
after installing so the `scout` command is visible everywhere.

### Where scout installs

The one-line installer writes to exactly two places — both in your home folder, nothing system-wide and nothing inside Claude Code's plugin cache:

```
~/.local/bin/scout      the `scout` command (a thin launcher script)
~/.scout/               the plugin files: .claude-plugin/, agents/,
                        stilwerk/, README, LICENSE
```

The launcher is one line — `claude --plugin-dir ~/.scout --agent scout:scout "$@"` — so every run loads the plugin straight from `~/.scout`. That is why update and uninstall are reliable: there is no cache to get out of sync. `scout --where` prints the plugin path any time.

On **Windows**, the layout mirrors the home-folder convention:

```
%USERPROFILE%\.local\bin\scout.cmd   the `scout` command (a thin launcher)
%USERPROFILE%\.scout\                the plugin files: .claude-plugin\, agents\,
                                     skills\, services\, stilwerk\, README, LICENSE
```

`%USERPROFILE%\.local\bin` is added to your **User PATH** automatically (no admin
needed). `scout --where` prints the plugin path; `scout --uninstall` removes the
install dir and the launcher.

Both locations are overridable with environment variables before installing
(set them before the one-liner on Windows too):

- `SCOUT_HOME` — where the plugin files go (default `~/.scout`, or `%USERPROFILE%\.scout` on Windows)
- `SCOUT_BIN` — where the `scout` launcher goes (default `~/.local/bin`, or `%USERPROFILE%\.local\bin` on Windows)

To remove scout completely: `scout --uninstall` (which is just `rm -rf ~/.scout` plus removing the launcher). Claude Code's own `~/.claude/` directory is never touched.

### Alternative: Claude Code marketplace

If you prefer the built-in plugin system (note: it uses git, which can fail when your git is configured for SSH):

```bash
/plugin marketplace add tenzoki/claude-plugins
/plugin install scout@tenzoki-plugins
```

(Registering scout in that marketplace is out of scope for this build; the one-line installer above is the supported path today.)

## Where the report lands

Every run writes exactly one report to:

```
scout-workbench/research/<prefix>-<topic>.md
```

`scout-workbench/` is scout's runtime workbench, created in your project on the first run (scout runs `mkdir -p scout-workbench/research/` itself). It is gitignored by the plugin source tree but lives in *your* project — keep it or commit it as you see fit.

The `<prefix>` is a date-time stamp. The default renders as `YYYY-MM-DD_HH-MM` (e.g. `2026-06-14_13-45`). You can override it by setting the environment variable `SCOUT_FILE_PREFIX` to a `date(1)` strftime string — e.g. `export SCOUT_FILE_PREFIX='%Y%m%d-%H%M%S'` for full-year + seconds precision. Default keeps existing reports sorting consistently; change it only on a clean project.

### scout's shell access (and how to scope it)

scout runs two shell commands and no others: `date` (to stamp the report's date-time from the machine instead of guessing) and `mkdir -p scout-workbench/research/` (to create the report directory on the first run). To do this its agent definition grants Claude Code's built-in `Bash` tool — but it is **not** an agent-dispatch tool, and scout stays single-agent.

A plugin cannot ship a permission rule that binds its agent's own `Bash` calls — Claude Code reads permissions from the `settings.json` in the directory where you launch `scout` (and `~/.claude/settings.json`), not from `~/.scout`. To hold scout to exactly those two commands, add this to your project's `.claude/settings.json` (or `~/.claude/settings.json` for every project):

```json
{
  "permissions": {
    "allow": [
      "Bash(date:*)",
      "Bash(mkdir:*)"
    ]
  }
}
```

With this in place, `date` and `mkdir` run without a prompt and any other shell command falls outside the allowlist, so Claude Code prompts you before running it. Without the snippet scout still only *calls* `date` and `mkdir`, but Claude Code may prompt you to approve a broader `Bash` permission — approving that grants more than scout uses, so the allowlist is the way to keep its shell access scoped. `/scout:setup` walks through the same recommendation.

## Continuous briefings (`scout brief`)

A briefing is a standing version of a scout run. You write an interest profile once — a short markdown file with one heading per topic you want followed — and `scout brief` runs one research process per section, merges the results into a single document with the highlights on top, and remembers what it already told you so tomorrow's briefing carries only what is new.

**What it is not:** nothing in scout watches the clock and nothing delivers the briefing anywhere. `scout brief` runs when something starts it, and what it produces is a file on your disk. Scheduling is your cron job (see below); reading it is you opening the file. There is no daemon, no mail, no push.

### Write a profile

Copy the shipped example and edit it:

```bash
mkdir -p ~/briefings && cp ~/.scout/briefing/example-profile.md ~/briefings/ai-morning.md
```

`briefing/example-profile.md` is both the worked example and the format reference — the explanation lives inside the file, as prose the run ignores. Change the title, change `name`, then rewrite the `##` headings and the question under each. That is the whole edit.

Two things decide whether a briefing is worth reading:

- **`name` and `language` are required.** `name` (lowercase letters, digits, hyphens) names your ledger and your briefing files. A run that finds either field missing stops and says so.
- **Each section has to be a complete research question.** The run is unattended, so the agent cannot ask you what you meant — every term you leave open is one it resolves for itself. Say what counts as an item, what is out of scope, what each item must state, and where a judgement boundary sits as a number ("at or below 15 billion parameters", not "small models"). The three sections in the example are written to that standard.

### Run it

```bash
scout brief ~/briefings/ai-morning.md
```

**The profile's own directory is the run anchor.** Everything is written beside the profile, whatever directory you started from:

```
~/briefings/scout-workbench/research/    one cited report per section
~/briefings/scout-workbench/briefings/   YYYY-MM-DD-<name>.md   ← what you read
~/briefings/scout-workbench/ledgers/     <name>.md              ← what it remembers
```

The briefing carries the highlights, then every profile section in the profile's own order, then a run-figures table and any failure notes. Each item carries its sources and a confidence marker, exactly as a normal scout report does.

**A briefing file is written on every run**, including the morning where nothing survived the story test. That briefing says "Nothing new this morning" and still carries every section heading and the run figures. This is deliberate: a missing file is indistinguishable from a failed run, so silence is never the output.

### Schedule it yourself

Use your own cron. One line, 06:30 daily:

```
30 6 * * * $HOME/.local/bin/scout brief $HOME/briefings/ai-morning.md >> $HOME/briefings/scout-brief.log 2>&1
```

Two things this line gets right and a hand-written one usually does not. **The launcher is named by its full path**, because cron's `PATH` is a short default that does not contain `~/.local/bin` — a bare `scout` in a crontab fails with "command not found". And output is redirected to a log, because a run whose reasons you cannot read is a run you cannot tune. (If you installed with `SCOUT_BIN` set, use that directory instead. `scout --where` prints the install location.)

**Your machine has to be awake at that time.** cron does not wake a sleeping laptop and does not catch up on a schedule it slept through; a closed lid at 06:30 means no briefing that day. On macOS, `pmset` scheduled wake or a `launchd` job with `StartCalendarInterval` handles that better than cron does.

### What a briefing costs

**scout pins no model.** There is no `model:` field in the profile and no `--model` flag on the command. The run inherits whatever model the environment that starts the launcher supplies, which means *you choose the model by choosing how cron starts scout* — and the bill follows that choice. It also changes silently when you change your own default model, with nothing in the profile to tell you it did.

The only cost measurement that exists is **about $0.27 for one small research question answered from two sources.** Read that as a **floor for one section, not an estimate for a morning.** A briefing section carries a crawl of up to 40 pages, so the real figure is higher by an amount nobody here has measured. Multiplying $0.27 by your section count would be invention, and this documentation will not do it for you.

To put a hard bound on it, set `SCOUT_BRIEF_MAX_USD` on the cron line:

```
30 6 * * * SCOUT_BRIEF_MAX_USD=1.50 $HOME/.local/bin/scout brief $HOME/briefings/ai-morning.md >> $HOME/briefings/scout-brief.log 2>&1
```

- It is **optional and has no default**. A dollar cap is only interpretable against a model, and scout pins none.
- It applies **per invocation** — to each section and to the merge — so a three-section profile can spend up to four times the number you set.
- It **overshoots by 10 to 22 per cent** (measured), because the cap is checked between turns rather than before each API call. Set it at roughly 80 per cent of the ceiling you actually mean.
- When it fires, **that section's entire report is lost.** The wall-clock cap is gentler: a section that runs out of minutes stops and writes what it has.

The run prints its own worst case as a banner before it starts, so the arithmetic is in front of you rather than in your head.

### The caps are per section, not per morning

| Field | Starting value | What it bounds |
|---|---|---|
| `yield-target` | 8 | New items a section aims for; reaching it ends that section early |
| `max-pages` | 40 | Pages one section may fetch |
| `max-hops` | 2 | How far the agent may follow links from a page it already holds (0 = seeds and search results only) |
| `max-minutes` | 15 | Wall clock for one section (the watchdog allows 5 minutes' grace on top) |
| `depth` | `off` | Whether the browser-driven depth layer may be used |
| `ledger-window-days` | 60 | How far back the "have I already reported this?" test looks |

**The worst case for a morning is sections × cap.** Three sections at `max-pages` 40 can fetch 120 pages; three at `max-minutes` 15 can run for 80 minutes, because the watchdog allows five minutes of grace per dispatch and the merge gets a dispatch of its own (4 × 20).

**These starting values are proposals with no measurement behind them, and they are expected to be tuned.** They are not defaults anyone has validated against real mornings. Run a few, read the run-figures table, and change them.

### Read and correct the ledger

Every item a briefing publishes is appended to `scout-workbench/ledgers/<name>.md` as one entry: a sentence saying who did what, plus its sources, its section, and what the story test decided. `briefing/example-ledger.md` is a worked instance with the fields explained inside it.

The file is meant to be opened and edited by hand. **Deleting an entry makes its story eligible again** — nothing else indexes the ledger and nothing is derived from it, so removing the entry is the whole of the operation.

That matters more than it sounds: **correcting the ledger is the only remedy for a story that was wrongly suppressed.** A suppressed story leaves no trace in the briefing, so if you suspect the morning was too quiet, the ledger is the only place to look and the only place to fix it.

**What the window does.** `ledger-window-days` decides how far back the test reads. A story first reported longer ago than the window can be reported a second time, because the entry that would have caught it is no longer consulted. That is the safe direction to fail in: a window too short produces a **duplicate you can see and skip**, while the alternative would be an omission you never learn about. Widening the window costs only the size of the set the story test reads, so set it to the cadence of your topic — model releases turn over in weeks, regulatory processes in months.

### Exit codes (so a cron wrapper can act on them)

The launcher hands the orchestrator's exit code straight through to whatever started it:

| Code | Meaning | What a wrapper should do |
|---|---|---|
| `0` | A briefing was written | Nothing. Read the file. |
| `1` | The run reached the merge and no usable briefing came out of it | Alert. The log holds the merge's error output. |
| `2` | The run stopped before a briefing was possible — a bad argument, an unusable profile, a missing script | Fix the invocation or the profile; retrying unchanged will fail the same way. |
| `3` | Windows only: `scout brief` refused (see below) | Run it under WSL or Git Bash instead. |

Per-section outcomes never change the exit code. A run whose every section failed still merges, still writes a briefing and **still exits 0** — the per-section verdicts (`succeeded`, `timed out`, `failed`, `failed — exceeded its budget`) are in the briefing's run-figures table and failure notes, and a wrapper that wants to act on them reads the file.

### Windows

The briefing assets install normally: `%USERPROFILE%\.scout\briefing\` contains the scripts and the examples after any install or update. But **`scout brief` on Windows refuses and exits 3.** The orchestrator is a bash script and no PowerShell counterpart ships in this release; exit 3 sits deliberately outside the 0/1/2 contract above, so a scheduled task can never read the refusal as a real briefing outcome.

To produce a briefing on a Windows machine, run the script directly under WSL or Git Bash, pointing at the installed copy:

```bash
# Git Bash (~ is %USERPROFILE%)
bash ~/.scout/briefing/scout-brief.sh /path/to/profile.md

# WSL (your Windows home is under /mnt/c)
bash /mnt/c/Users/<you>/.scout/briefing/scout-brief.sh /path/to/profile.md
```

Both need the `claude` CLI available inside that shell, since the script dispatches through it. `scout --where` prints the install directory if you moved it.

Every other scout command works normally on Windows.

## Optional depth layer (browser-use)

The depth layer lets scout drive a **real local Chromium browser** for pages the breadth layer cannot reach over plain HTTP: JavaScript-rendered content, owned-account logins, interactive interfaces. It is the [browser-use](https://github.com/browser-use/browser-use) stack, run locally and exposed to scout as an MCP server.

It is **entirely optional**. If you never register it, scout runs breadth-only and records any page that genuinely needs an interactive browser as a "needs depth tools" gap in the report's blocked-sources table — never silently dropped. Register it only if you actually hit such pages.

### Wire the depth layer at install time (keeps your session on subscription auth)

The fastest way to wire the depth layer is to set `BROWSERUSE_ANTHROPIC_KEY` **before** the install/update one-liner. The installer then pins that key into the browser-use MCP server for you — no separate `/scout:setup` step:

```bash
# mac / Linux
BROWSERUSE_ANTHROPIC_KEY=sk-ant-... curl -fsSL https://raw.githubusercontent.com/tenzoki/scout/main/install.sh | bash
```

```powershell
# Windows (cmd.exe or PowerShell)
$env:BROWSERUSE_ANTHROPIC_KEY="sk-ant-..."; irm https://raw.githubusercontent.com/tenzoki/scout/main/install.ps1 | iex
```

This pins the key into the **browser-use MCP server only** — so you do **not** export `ANTHROPIC_API_KEY` in your shell. Your scout session stays on claude.ai-subscription/OAuth auth and **Remote Control keeps working** (an exported `ANTHROPIC_API_KEY` would flip the whole session to API-key auth and disable both — see the inherit-vs-pin note under [You need your own Anthropic API key](#you-need-your-own-anthropic-api-key) and the registration notes below).

- **Optional.** scout's breadth core needs no key; leave the var unset and install/update behave exactly as before, touching no existing browser-use registration.
- **Best-effort.** If a prerequisite is missing (`uvx`, the `claude` CLI), the installer warns and still finishes — the breadth core is installed regardless.
- **Rotate the key** by re-running update with the var set: `BROWSERUSE_ANTHROPIC_KEY=sk-ant-new scout --update` (`$env:BROWSERUSE_ANTHROPIC_KEY="sk-ant-new"; scout --update` on Windows). A plain update with the var unset leaves the existing registration alone. On mac/Linux you can also use the launcher flag — `scout --update --key sk-ant-new` to update and rotate, or `scout --key sk-ant-new` to rotate without re-downloading (see [Pin or rotate the depth-layer key with `--key`](#pin-or-rotate-the-depth-layer-key-with---key); the env-prefix form is safer on shared machines because an argv key is visible in `ps aux` and shell history).
- **Caveat.** The pinned key is stored in plaintext in your user-scope MCP config (`~/.claude.json`, or `%USERPROFILE%\.claude.json` on Windows).

### Register the MCP server

**Easiest path:** run the `/scout:setup` skill. It registers the server for you with the `0.11.9` pin and both no-cloud env vars baked in, checks `uvx`, and prompts for your Anthropic key (it never writes the key into the repo).

**Run the script directly (technical users):** the registration mechanics live in one script, `skills/setup/register-browser-use.sh`, which `/scout:setup` simply drives. You can run it yourself:

```bash
# Inherit ANTHROPIC_API_KEY from your environment (no key written into the config):
BROWSERUSE_INHERIT=1 bash ~/.scout/skills/setup/register-browser-use.sh

# Or pin a specific key into the user-scope MCP config:
BROWSERUSE_ANTHROPIC_KEY=sk-ant-... bash ~/.scout/skills/setup/register-browser-use.sh
```

Run with neither variable on an interactive terminal and it offers inherit (when `ANTHROPIC_API_KEY` is set) or prompts for a key with hidden input. It never writes the key to a file or echoes it. (Adjust the path if you set `SCOUT_HOME`.)

> **Inherit mode: export the key *before* you start Claude Code.** With `BROWSERUSE_INHERIT=1`, no key is written to the config — the browser-use MCP server reads `ANTHROPIC_API_KEY` from the environment of the Claude Code process *at the moment that process launches*. If the key was not exported before Claude Code started, registration still shows green, but your first `browser_extract_content` call fails with an opaque auth error. So export the key first, then launch Claude Code:
>
> ```bash
> export ANTHROPIC_API_KEY=sk-ant-...
> export ANONYMIZED_TELEMETRY=False
> export BROWSER_USE_VERSION_CHECK=false
> scout          # or however you launch Claude Code with the scout agent
> ```
>
> Put that `export ANTHROPIC_API_KEY=...` line in a file you source on shell start (e.g. a private `~/.scout-env` you `source` from your shell profile), kept **outside any repo** so the key never lands in version control. Registering inherit-mode in one shell and then launching Claude Code from a different shell that never sourced the key is the exact trap this avoids: the key has to be live in the launching shell, not just the shell you registered from. If you would rather not manage shell environment at all, pin the key with `BROWSERUSE_ANTHROPIC_KEY=sk-ant-...` instead — it goes only into Claude Code's user-scope MCP config.

> **Inherit mode changes your whole-session auth.** Exporting `ANTHROPIC_API_KEY` session-wide (the inherit-mode path) switches the entire Claude Code session to **API-key auth** — which disables claude.ai-subscription auth and **Remote Control** (and some orgs disallow Remote Control by policy). If you rely on subscription auth or Remote Control *and* want the depth layer, **pin** the key into the browser-use server instead (`BROWSERUSE_ANTHROPIC_KEY=...` via `/scout:setup` or the script). Then only the browser-use server sees the key, the session environment stays clean, and session auth — including Remote Control — is unaffected. (The SearXNG meta backend needs no Anthropic key, so it never triggers this.)

The manual JSON block below is the ultimate fallback if you would rather edit your MCP settings yourself.

Add this to your Claude Code MCP settings. It runs browser-use locally via `uvx`, pinned to the version scout is tested against, through scout's Anthropic shim:

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

The pin is `0.11.9` — the version scout's depth layer is built and verified against. A version bump is a deliberate, tested change, not an automatic track. The `--from "browser-use[cli]@0.11.9" python <shim>` form runs the exact tested browser-use, but launches scout's thin shim inside that environment so extraction lands on Anthropic. Both no-cloud env vars stay in this snippet — keep them in every one. (`SCOUT_DEPTH_EXTRACT_MODEL` is optional; it overrides the default `claude-3-5-haiku-latest` extraction model.)

### Both no-cloud environment variables are mandatory

`ANONYMIZED_TELEMETRY=False` and `BROWSER_USE_VERSION_CHECK=false` **must appear in every documented snippet**, here and anywhere else you register the server. They disable browser-use's two on-by-default outbound pings — the PostHog telemetry call and the version-check call. Without them, registering the server quietly phones home on startup. Do not omit either one.

### You need your own Anthropic API key

The depth layer's main LLM-using tool, `browser_extract_content` (turn a page into structured text), calls an LLM, and you supply the key via `ANTHROPIC_API_KEY`. Stock browser-use `0.11.9` hardwires that extraction call to OpenAI at the MCP layer. scout ships a small runtime shim (`services/browser-use-anthropic/scout_browseruse_anthropic.py`) that rebinds the extraction LLM to Anthropic, so a fast Claude model (`claude-3-5-haiku-latest` by default) handles extraction and you need only an Anthropic key. Override the model with `SCOUT_DEPTH_EXTRACT_MODEL`.

The shim patches **extraction only**. The last-resort internal loop, `retry_with_browser_use_agent`, stays OpenAI/Bedrock-only upstream; if you reach for it you still need an OpenAI or Bedrock key.

This is not a "no cloud" violation. scout's no-cloud rule bans browser-use's **hosted service** (browser-use Cloud) — the browser runs entirely on your machine. The LLM call for content extraction is an ordinary external LLM call, the same kind scout makes for everything else.

### Server name and tool prefix must match

The server key `browser-use` in the snippet above must equal the `mcp__browser-use__` prefix in scout's tool allow-list (`agents/scout.md`). They are coupled: scout's allow-list names the tools as `mcp__browser-use__browser_navigate`, `mcp__browser-use__browser_get_state`, and so on. **If you register the server under a different name, the allow-list prefix must track it** — otherwise scout cannot see the depth tools and silently falls back to breadth-only. Keep the name `browser-use` unless you have a reason to change both sides.

### No captcha-solving — the foreground-handoff two-step

Be clear-eyed about this: **nothing in this local, no-cloud configuration reliably defeats a modern captcha.** That capability was given up when scout chose local browser-use over browser-use Cloud. scout will not pretend otherwise — it caps captcha effort at a few steps and moves on.

When scout hits a wall on a source it judges essential — a captcha, a login, a hard 403, an interstitial — it does **not** silently drop it. It returns a **blocked-sources block** in the report: the URL, the wall type, and what a human must do to clear it. The handoff back to you is two steps:

1. scout returns the blocked-sources block. You see exactly which sources are walled and why.
2. You clear the wall **live, in a foreground browser-use session** — log in, solve the captcha, whatever it takes. The persistent local Chromium profile (`~/.config/browseruse/profiles/default`) captures the authenticated state. Then you **re-run scout**, and it reaches the now-unlocked source on the next pass.

The wall becomes structured information you act on out-of-band, not a silent gap and not a budget-burning captcha loop.

## Optional metasearch backend (SearXNG)

scout can discover URLs through a **self-hosted [SearXNG](https://github.com/searxng/searxng) metasearch engine** instead of the built-in `WebSearch`. SearXNG aggregates many search engines behind one private, local endpoint — useful when you want self-hosted, privacy-respecting discovery.

It is a **discovery backend, not a fetcher.** SearXNG only finds URLs; `WebFetch` and the optional depth layer still do all content fetching. The fetch path is unchanged.

It is **entirely optional and opt-in.** Default `scout` is unchanged and **zero-dependency** — it discovers with `WebSearch` and needs no Docker, no MCP, nothing extra. If you never enable SearXNG, you lose nothing. scout falls back to `WebSearch` on **any** absence cause — not in `meta` mode, container not running, Docker missing, MCP not registered — and never fails because SearXNG is absent.

### Enable it — two coupled steps

SearXNG needs both an MCP registration and a running container:

1. **Register the MCP** — run `/scout:setup` (it offers SearXNG alongside browser-use) or run the script directly:

   ```bash
   bash ~/.scout/skills/setup/register-searxng.sh
   ```

   This registers the `searxng` MCP server under the user scope, pointed at `http://localhost:8911`, with no API key (self-hosted needs none). It writes no secret.

2. **Start the container** — launch scout with the `meta` flag:

   ```bash
   scout meta     # starts the local SearXNG Docker container, then launches scout
   ```

   `scout meta` brings up the container (`docker compose up -d` against the bundled `services/searxng/docker-compose.yml`), waits for it to report healthy, then launches scout. If Docker is missing, the container fails to start, or the health-wait times out, it prints a plain message naming the cause and launches scout with `WebSearch` instead — it never hard-fails.

   **`scout meta` works on Windows too**, with the same behaviour: it needs **Docker Desktop** (checked when you run `scout meta`, not at install time), generates the `secret_key` with Windows-native crypto instead of openssl, and falls back to `WebSearch` on any failure — Docker absent, container start fails, or health-wait times out.

Plain `scout` (without `meta`) never touches SearXNG. When SearXNG is registered **and** the container is up, scout discovers through it and each source in the report carries a `discovery: searxng` note; otherwise sources carry `discovery: websearch`.

### `json` output is required

The bundled SearXNG settings enable `json` output (`search.formats: [html, json]`). The default SearXNG image ships `html` only, and the `mcp-searxng` MCP needs `json` — without it the MCP breaks. The shipped `services/searxng/config/settings.yml` already has this; do not remove it.

### The secret is generated per deployment — never shipped

SearXNG needs a `server.secret_key`. scout **does not ship one** — the committed `settings.yml` carries an empty `secret_key`. On the first `scout meta` start, the launcher generates a real key into your **installed** copy at `~/.scout/services/searxng/config/settings.yml` (`%USERPROFILE%\.scout\services\searxng\config\settings.yml` on Windows). On mac/Linux it uses `openssl rand -hex 32`; on Windows it uses Windows-native crypto (`System.Security.Cryptography`), since openssl is not present by default. The repo never contains a real secret, and every deployment gets its own.

The bundled settings also set `limiter: false`, which is fine for single-user localhost. If you expose this SearXNG on a shared or public host, re-enable the limiter.

### Server name and tool prefix must match

The MCP server name `searxng` must equal the `mcp__searxng__` prefix in scout's tool allow-list (`agents/scout.md`). `register-searxng.sh` registers it under exactly `searxng`. If you register it under a different name, scout cannot see the discovery tool and silently falls back to WebSearch — keep the name `searxng`.

### Troubleshooting: `searxng` defined in multiple scopes

If `/mcp` (or `claude mcp list`) shows `searxng` failing to connect with a message that it is **defined in multiple scopes with different endpoints**, a stray registration from an unrelated project is shadowing scout's. `/scout:setup` registers scout's SearXNG at **user scope** (`npx -y mcp-searxng`); if another project registered a different `searxng` endpoint at **project scope**, the two collide. Remove the project-scope one so scout's user-scope server is the one that loads:

```bash
claude mcp remove searxng -s project
```

(If the conflicting entry were instead at user scope, you'd remove that with `-s user` — but scout's is the user-scope one, so the project-scope entry is normally the one to drop.)

A subtle variant: the conflicting registration may live in a **home-level `~/.mcp.json`** rather than a per-project one. Claude Code walks **up** from your current directory and treats the nearest `.mcp.json` it finds as the "project config (shared via `.mcp.json`)", so a `~/.mcp.json` in your home directory shadows scout's user-scope `searxng` in *every* directory under your home. The catch: `claude mcp remove searxng -s project` operates on the `.mcp.json` of your **current working directory**, not necessarily the one Claude actually loaded — so if you run it from a project subfolder and get `No MCP server found with name: searxng in .mcp.json`, the conflicting entry lives in a `.mcp.json` higher up, most often `~/.mcp.json`. Re-run from that directory so the command targets the right file:

```bash
cd ~ && claude mcp remove searxng -s project
```

To find which file defines it, `claude mcp get searxng` shows the scope, and the entry is in the `.mcp.json` of whichever directory Claude resolved it from.

## Language

Default is English. scout ships professional-voice style profiles (for the report prose) and chat-voice profiles (for the compact summary it returns) in English and German. For other languages, it reads the English profile and applies the same intent in the target language.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) v2.0.12 or higher.
- That's it for the breadth layer — no git, no Node, no Python, no Docker.
- The optional depth layer adds its own requirements: `uvx` (from [uv](https://github.com/astral-sh/uv)) to run browser-use locally, an `ANTHROPIC_API_KEY` (extraction runs on Anthropic via scout's shim), and a local Chromium that browser-use manages. See **Optional depth layer (browser-use)** above. None of this is needed for breadth.
- The optional SearXNG meta backend needs `npx` (from [Node.js](https://nodejs.org)) to run the MCP, and **Docker** to run the container via `scout meta`. Docker is needed **only** for `meta` — never for the default `scout` path. See **Optional metasearch backend (SearXNG)** above.

## License

MIT. See [LICENSE](LICENSE).
