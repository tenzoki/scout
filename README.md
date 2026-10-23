# scout

A web-research plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview). You give scout a fully-specified research question; it runs multi-source web research with inline cross-source verification and writes **one cited report file** per run. It returns to you only a compact cited summary plus the path to that report.

The plugin is named **scout**; its single AI agent is also named **scout**, addressed as `scout:scout`. It runs two ways: as the main agent of its own session (`claude --agent scout:scout`, or the `scout` launcher), or as a sub-agent that another agent dispatches (see [Use scout from another agent](#use-scout-from-another-agent)).

scout was carved out of [flight](https://github.com/tenzoki/flight) so that research's context-firehose traffic — dozens of search results and fetched pages — stays out of a working conversation. You run scout in its own session, or let another agent dispatch it, get one report file, and hand that file to flight's `pilot` for synthesis. Same family.

## The two-layer model

scout has two layers, and you can stop after the first:

- **Breadth (works immediately).** No setup beyond installing the plugin. scout fires parallel web searches and page fetches, reads the results together, and cross-verifies each claim across sources over plain HTTP. This is the whole product for most questions.
- **Depth (optional, registered separately).** An add-on for pages that genuinely need an interactive browser (JavaScript-rendered content, owned-account logins). It is a separate MCP server you register yourself; until you do, scout runs breadth-only and flags any depth-needing page as a gap in the report rather than silently dropping it. See **Optional depth layer (browser-use)** below.

A user who never registers the depth layer keeps a fully working breadth research plugin.

## What scout produces

scout writes one cited report per run, by default to `scout-workbench/research/<prefix>-<topic>.md` (the caller can choose another folder, see [Where the report lands](#where-the-report-lands)), and returns a compact summary plus that path. The report has **two layers**:

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

## Use scout from another agent

Any agent in a session where the scout plugin is loaded can hand research to scout and get the report path back. The plugin is loaded when it is installed and enabled through the marketplace (see [Install through the Claude Code marketplace](#install-through-the-claude-code-marketplace)), or when the session was started with `--plugin-dir ~/.scout`. Dispatch it through Claude Code's `Agent` tool:

```
Agent(subagent_type: "scout:scout", prompt: "<one fully specified question>")
```

What goes into the prompt:

- **One fully specified question.** The rule above applies unchanged: scope, constraints, language, source preferences and depth, all stated up front. scout cannot ask the dispatching agent anything mid-run either.
- **Optionally, one `REPORT DIR:` line** to choose the folder the report is written to, relative to the session's working directory. Example: `REPORT DIR: fusion-workbench/shared/research`. Without it the report goes to `scout-workbench/research/`. The rules for the value are under [Where the report lands](#where-the-report-lands).
- **Never a line reading `CRAWL DIRECTIVE`.** That line switches scout into briefing mode and is reserved for `scout brief`.

What comes back is the compact cited summary plus the absolute path of the report file, never the full report. The dispatching agent reads the file when it needs the detail, so the research traffic stays out of its context.

### For plugin authors: depend on scout softly

scout is an optional companion, not a requirement. The pattern we recommend for another plugin's agent is a soft dependency: **if `scout:scout` is among your available agent types, dispatch it; otherwise research with `WebSearch` and `WebFetch` yourself.** The agent reads its own list of available agent types at dispatch time, so it never has to predict whether the user installed scout.

Do not declare scout in your plugin's `dependencies`. That field is a hard dependency, which forces scout onto every user of your plugin.

## Quick start with the launcher (one line, no git)

scout installs two ways, and both are supported: this one-line installer, which also gives you the `scout` command, and the [Claude Code marketplace](#install-through-the-claude-code-marketplace). Read [Two copies](#two-copies-launcher-and-marketplace) before you use both.

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

The one-line installer itself writes to two places — both in your home folder, nothing system-wide and nothing inside Claude Code's plugin cache:

```
~/.local/bin/scout      the `scout` command (a thin launcher script)
~/.scout/               the plugin files: .claude-plugin/, agents/,
                        stilwerk/, README, LICENSE
```

The launcher is one line — `claude --plugin-dir ~/.scout --agent scout:scout "$@"` — so every run loads the plugin straight from `~/.scout`. That is why update and uninstall are reliable: there is no cache to get out of sync. `scout --where` prints the plugin path any time. The optional depth layer and SearXNG backend keep their files in a third place, [scout's state directory](#scouts-state-directory), which `scout --update` does not touch. The installer writes there too when you set `BROWSERUSE_ANTHROPIC_KEY`, because it then registers the depth layer.

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

`scout --uninstall` removes `~/.scout` and the launcher. On mac and Linux it also removes the SearXNG container and scout's folders in its [state directory](#scouts-state-directory), naming each one as it goes. It leaves the MCP registrations in place, because they live in Claude Code's own config; [Remove scout completely](#remove-scout-completely) lists the commands for those.

## Install through the Claude Code marketplace

scout is published in the `tenzoki-plugins` marketplace. Inside a Claude Code session:

```
/plugin marketplace add tenzoki/claude-plugins
/plugin install scout@tenzoki-plugins
```

The marketplace route fetches through git, which can fail when your git is configured for SSH. The one-line installer above needs no git.

A marketplace install loads scout in every session where the plugin is enabled. That gives you the `scout:scout` agent for [dispatch from other agents](#use-scout-from-another-agent), `/scout:setup` and `/scout:meta`. It gives you no `scout` shell command, so `scout brief` and the `--key` flag need the launcher install; `/scout:meta` replaces `scout meta`.

### Updates arrive with a version bump, and you pull them

Claude Code installs the version named in scout's manifest, so a change reaches marketplace users only when scout's version is bumped. Third-party marketplaces do not auto-update by default, so pull a new release yourself. First refresh the marketplace listing inside a Claude Code session:

```
/plugin marketplace update tenzoki-plugins
```

Then update the plugin from your terminal:

```bash
claude plugin update scout@tenzoki-plugins
```

Restart Claude Code afterwards to load the new version. If the release notes say the shim or the browser-use pin changed, re-run `/scout:setup` as well (see [After an update](#after-an-update-re-run-scoutsetup-when-the-shim-or-the-pin-changed)).

### Two copies: launcher and marketplace

With both installs on one machine you have **two separate copies of scout**, and they do not know about each other:

- **A `scout` launcher session loads `~/.scout`.** The launcher starts Claude Code with `--plugin-dir ~/.scout`, and a `--plugin-dir` plugin takes precedence over an installed plugin of the same name for that session. The marketplace copy is silently replaced; nothing tells you which copy is running.
- **The update commands refresh different copies.** `scout --update` refreshes `~/.scout` only. `claude plugin update scout@tenzoki-plugins` refreshes the marketplace copy only.

So a fix you pulled with one command is missing from sessions that load the other copy. Keep one install, or update both together. Both copies share one [state directory](#scouts-state-directory), so the depth-layer registration and the SearXNG secret are the same whichever copy you run.

## Upgrading from 0.5.0

Two things changed in 0.6.0 that an existing install does not pick up by itself:

- **SearXNG container.** 0.5.0 created `scout-searxng` under the compose project `searxng`; 0.6.0 uses the project `scout-searxng`. The next `scout meta` or `/scout:meta` finds the old container, removes it and says so, then starts a fresh one. To do it by hand instead, run `docker rm -f scout-searxng` once before the first start on 0.6.0.
- **Depth layer.** Re-run `/scout:setup` once, so the shim is copied into the [state directory](#scouts-state-directory) and the registration names that copy instead of a path inside the plugin folder.

## scout's state directory

Some of scout's files must outlive every copy of the plugin: the browser-use shim that the depth-layer registration points at, and the SearXNG secret and rendered config that the container mounts. A plugin update replaces the plugin folder, and `scout --update` replaces `~/.scout`, so scout keeps these files in one user-scoped state directory instead:

```
${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}
```

By default that is `~/.local/state/scout`. Set `SCOUT_STATE_DIR` to move it; it must be an absolute path outside `~/.claude/plugins/cache/`, and the scripts refuse any other value. Every caller uses the same directory: the launcher, `/scout:setup`, `/scout:meta`, and the scripts run by hand.

scout writes two subfolders there and drops a `.scout-owned` marker file into each. In a directory you chose with `SCOUT_STATE_DIR`, the scripts refuse to write into a `searxng/` or `browser-use-anthropic/` folder that has no marker and does not hold scout's own files, and `scout --uninstall` removes only marked folders.

```
~/.local/state/scout/browser-use-anthropic/scout_browseruse_anthropic.py   the registered shim copy
~/.local/state/scout/searxng/secret_key                                    generated once, mode 600
~/.local/state/scout/searxng/config/settings.yml                           rendered on every start
~/.local/state/scout/searxng/docker-compose.yml                            copied on every start
~/.local/state/scout/*/.scout-owned                                        marker: scout wrote this folder
```

The state directory applies to the mac and Linux scripts. The Windows launcher still keeps the shim and the SearXNG secret inside `%USERPROFILE%\.scout`.

## Where the report lands

Every run writes exactly one report. By default it goes to:

```
scout-workbench/research/<prefix>-<topic>.md
```

`scout-workbench/` is scout's runtime workbench, created in your project on the first run (scout runs `mkdir -p scout-workbench/research/` itself). It is gitignored by the plugin source tree but lives in *your* project — keep it or commit it as you see fit.

### Choose the folder with `REPORT DIR`

Whoever dispatches scout can choose the folder by adding one line to the question that is exactly `REPORT DIR: <path>`:

```
REPORT DIR: fusion-workbench/shared/research
```

The report then lands at `<path>/<prefix>-<topic>.md`, and scout creates that folder instead of `scout-workbench/research/`. The path is relative to the directory scout runs in, and scout reports the resulting absolute path back.

scout accepts the value only if it is non-empty, relative (no leading `/` or `~`), uses only `A–Z a–z 0–9 . _ - /`, and no `/`-separated part of it starts with `-` or `.`. That last rule rules out `..`, a value `mkdir` would read as an option, and dot-folders such as `.claude/commands` or `.git`. `flight-workbench/research` and `fusion-workbench/shared/research` are valid. A value that breaks a rule is not repaired: scout writes to the default folder and says in its summary that the `REPORT DIR` value was rejected and why. In a briefing run (`scout brief`) the line is ignored, because the briefing locates its section reports under `scout-workbench/research/`.

The `<prefix>` is a date-time stamp. The default renders as `YYYY-MM-DD_HH-MM` (e.g. `2026-06-14_13-45`). You can override it by setting the environment variable `SCOUT_FILE_PREFIX` to a `date(1)` strftime string — e.g. `export SCOUT_FILE_PREFIX='%Y%m%d-%H%M%S'` for full-year + seconds precision. Default keeps existing reports sorting consistently; change it only on a clean project.

### scout's shell access (and how to scope it)

scout's agent definition grants Claude Code's built-in `Bash` tool — it is **not** an agent-dispatch tool, and scout stays single-agent. This is everything scout runs with it:

- **Every run:** `date` (to stamp the report's date-time from the machine instead of guessing), `mkdir -p scout-workbench/research/` or the `REPORT DIR` folder (to create the report directory), and `pwd` (to report the report's absolute path back).
- **Briefing runs only** (`scout brief`): `date +%s` (to measure the time budget), the ledger retriever `briefing/ledger-retrieve.sh` (to check what was already reported), and `curl` (to fetch each host's `robots.txt`).

A plugin cannot ship a permission rule that binds its agent's own `Bash` calls — Claude Code reads permissions from the `settings.json` in the directory where you launch `scout` (and `~/.claude/settings.json`), not from `~/.scout`. To hold scout to the commands of a normal run, add this to your project's `.claude/settings.json` (or `~/.claude/settings.json` for every project):

```json
{
  "permissions": {
    "allow": [
      "Bash(date:*)",
      "Bash(mkdir:*)",
      "Bash(pwd)"
    ]
  }
}
```

With this in place, those commands run without a prompt and any other shell command falls outside the allowlist, so Claude Code prompts you before running it. If briefings run under these settings, also allow `Bash(curl:*)` and the retriever. **Do not deny `curl` where briefings run:** scout then cannot read any host's `robots.txt`, so it fetches nothing from hosts it could not check and lists them in the report as blocked. Without the snippet scout still only *calls* the commands above, but Claude Code may prompt you to approve a broader `Bash` permission — approving that grants more than scout uses, so the allowlist is the way to keep its shell access scoped. `/scout:setup` walks through the same recommendation.

## Continuous briefings (`scout brief`)

A briefing is a standing version of a scout run. You write an interest profile once — a short markdown file with one heading per topic you want followed — and `scout brief` runs one research process per section, merges the results into a single document with the highlights on top, and remembers what it already told you so tomorrow's briefing carries only what is new.

**What it is not:** nothing in scout watches the clock and nothing delivers the briefing anywhere. `scout brief` runs when you run it, and what it produces is a file on your disk. There is no daemon, no mail, no push.

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

**Run it from your own terminal.** The run dispatches through the `claude` CLI and uses that shell's Claude Code login, so it has to happen somewhere you are signed in. An interactive terminal is; a context detached from your login session is not.

**The profile's own directory is the run anchor.** Everything is written beside the profile, whatever directory you started from:

```
~/briefings/scout-workbench/research/    one cited report per section
~/briefings/scout-workbench/briefings/   YYYY-MM-DD-<name>.md   ← what you read
~/briefings/scout-workbench/ledgers/     <name>.md              ← what it remembers
```

The briefing carries the highlights, then every profile section in the profile's own order, then a run-figures table and any failure notes. Each item carries its sources and a confidence marker, exactly as a normal scout report does.

**A briefing file is written on every run**, including the morning where nothing survived the story test. That briefing says "Nothing new this morning" and still carries every section heading and the run figures. This is deliberate: a missing file is indistinguishable from a failed run, so silence is never the output.

### What a briefing spends

**Which resource you spend depends on how you are signed in.** On a claude.ai subscription nothing is billed: the dollar figure Claude Code reports is token usage priced at the published list rate and worked out locally, and what a run draws on is your subscription's rolling usage allowance. On an API-key install that same figure is money. Both are measured the same way, so everything below reads the same for both — as dollars on an API key, as list-priced usage on a subscription. Whether a subscription's usage windows are debited by that same list-price arithmetic is not something scout can see, and this documentation does not claim it either way.

**scout pins no model.** There is no `model:` field in the profile and no `--model` flag on the command. The run inherits whatever model the environment you start it from supplies, so you choose the model by choosing where you run. It also changes silently when you change your own default model, with nothing in the profile to tell you it did. The choice is worth making deliberately: the model is the largest single factor in what a run spends.

The only measurement that exists is **about $0.27 of list-priced usage for one small research question answered from two sources.** Read that as a **floor for one section, not an estimate for a whole profile.** A briefing section carries a crawl of up to 40 pages, so the real figure is higher by an amount nobody here has measured. Multiplying $0.27 by your section count would be invention, and this documentation will not do it for you.

To cap it, set `SCOUT_BRIEF_MAX_USD` on the command:

```bash
SCOUT_BRIEF_MAX_USD=1.50 scout brief ~/briefings/ai-morning.md
```

- It is **optional and has no default**. A cap in dollars is only interpretable against a model, and scout pins none.
- It applies **per invocation** — to each section and to the merge — so a three-section profile can spend up to four times the number you set.
- **The overshoot is one whole turn, not a percentage.** The cap is checked between turns rather than before each API call, so a run stops at the first check *after* it has already gone over. Read the real ceiling as **your cap plus one turn**. One turn on a large model with scout's system prompt was measured at about $0.19, which is the whole of a small cap: a $0.02 cap ran to $0.19 before anything could stop it. Anything under roughly a dollar is dominated by that term, so treat a small cap as a hint rather than a limit.
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

**The two worst cases for a morning do not have the same shape.** Pages are sections × `max-pages`. Minutes are **(sections + 1) × (`max-minutes` + 5)**: the watchdog allows each dispatch five minutes of grace on top of the cap, and the merge is a dispatch like any other. The run banner fills both formulas in with your own numbers, which is the arithmetic to read rather than any worked out here.

**These starting values are proposals with no measurement behind them, and they are expected to be tuned.** They are not defaults anyone has validated against real mornings. Run a few, read the run-figures table, and change them.

### Read and correct the ledger

Every item a briefing publishes is appended to `scout-workbench/ledgers/<name>.md` as one entry: a sentence saying who did what, plus its sources, its section, and what the story test decided. `briefing/example-ledger.md` is a worked instance with the fields explained inside it.

The file is meant to be opened and edited by hand. **Deleting an entry makes its story eligible again** — nothing else indexes the ledger and nothing is derived from it, so removing the entry is the whole of the operation.

That matters more than it sounds: **correcting the ledger is the only remedy for a story that was wrongly suppressed.** A suppressed story leaves no trace in the briefing, so if you suspect the morning was too quiet, the ledger is the only place to look and the only place to fix it.

**What the window does.** `ledger-window-days` decides how far back the test reads. A story first reported longer ago than the window can be reported a second time, because the entry that would have caught it is no longer consulted. That is the safe direction to fail in: a window too short produces a **duplicate you can see and skip**, while the alternative would be an omission you never learn about. Widening the window costs only the size of the set the story test reads, so set it to the cadence of your topic — model releases turn over in weeks, regulatory processes in months.

### Exit codes (so a wrapper can act on them)

The launcher hands the orchestrator's exit code straight through to whatever started it:

| Code | Meaning | What a wrapper should do |
|---|---|---|
| `0` | A briefing was written | Nothing. Read the file. |
| `1` | The run reached the merge and no usable briefing came out of it | Alert. The log holds the merge's error output. |
| `2` | The run stopped before a briefing was possible — a bad argument, an unusable profile, a missing script | Fix the invocation or the profile; retrying unchanged will fail the same way. |
| `3` | Windows only: `scout brief` refused (see below) | Run it under WSL or Git Bash instead. |

Per-section outcomes never change the exit code. A run whose every section failed still merges, still writes a briefing and **still exits 0** — the per-section verdicts (`succeeded`, `timed out`, `failed`, `failed — exceeded its budget`) are in the briefing's run-figures table and failure notes, and a wrapper that wants to act on them reads the file.

### Windows

The briefing assets install normally: `%USERPROFILE%\.scout\briefing\` contains the scripts and the examples after any install or update. But **`scout brief` on Windows refuses and exits 3.** The orchestrator is a bash script and no PowerShell counterpart ships in this release; exit 3 sits deliberately outside the 0/1/2 contract above, so a wrapper can never read the refusal as a real briefing outcome.

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

Run with neither variable on an interactive terminal and it offers inherit (when `ANTHROPIC_API_KEY` is set) or prompts for a key with hidden input. It never writes the key to a file or echoes it. (Adjust the path if you set `SCOUT_HOME`. With a marketplace install the script sits in Claude Code's plugin cache, so use `/scout:setup` there.)

**The registration names a copy of the shim in scout's state directory, never a file inside the plugin.** The script copies `services/browser-use-anthropic/scout_browseruse_anthropic.py` to `~/.local/state/scout/browser-use-anthropic/` (see [scout's state directory](#scouts-state-directory)), checks the copy byte for byte, and registers that path. A plugin update replaces the plugin folder, and a marketplace update deletes the old version's folder 14 days later; a registration pointing into it would stop starting without an error. `claude mcp get browser-use` should show the shim under `~/.local/state/scout/`. The script stops with a non-zero exit if the entry is missing, does not name that copy, or names a path under `~/.claude/plugins/cache/` instead, and a failed `claude mcp add` stops it the same way; the installer and `scout --key` then report the failure instead of success.

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

### After an update, re-run `/scout:setup` when the shim or the pin changed

The shim copy is refreshed only when the registration runs. Updating scout, by either route, leaves the old copy in place, and the depth layer keeps working with it. When a scout release's notes say the shim or the browser-use pin changed, re-run `/scout:setup` (or the register script) once to copy the new shim and register the new pin.

### Manual registration

The manual JSON block below is the ultimate fallback if you would rather edit your MCP settings yourself.

First copy the shim into the state directory, from your scout install (`~/.scout` for the launcher; adjust for a marketplace install):

```bash
mkdir -p "${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}/browser-use-anthropic"
cp ~/.scout/services/browser-use-anthropic/scout_browseruse_anthropic.py "${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}/browser-use-anthropic/"
```

Then add this to your Claude Code MCP settings, with `<state dir>` replaced by the absolute path that directory expands to (by default `/Users/<you>/.local/state/scout` or `/home/<you>/.local/state/scout`, written out in full). It runs browser-use locally via `uvx`, pinned to the version scout is tested against, through scout's Anthropic shim:

```json
{
  "mcpServers": {
    "browser-use": {
      "command": "uvx",
      "args": [
        "--from", "browser-use[cli]@0.11.9",
        "python", "<state dir>/browser-use-anthropic/scout_browseruse_anthropic.py",
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

It is **entirely optional and opt-in.** Default `scout` is unchanged and **zero-dependency** — it discovers with `WebSearch` and needs no Docker, no MCP, nothing extra. If you never enable SearXNG, you lose nothing. scout falls back to `WebSearch` on **any** absence cause — MCP not registered, container not running, Docker missing — and never fails because SearXNG is absent.

### Enable it — two coupled steps

SearXNG needs both an MCP registration and a running container:

1. **Register the MCP** — run `/scout:setup` (it offers SearXNG alongside browser-use) or run the script directly:

   ```bash
   bash ~/.scout/skills/setup/register-searxng.sh
   ```

   This registers the `searxng` MCP server under the user scope, pointed at `http://localhost:8911`, with no API key (self-hosted needs none). It writes no secret.

2. **Start the container** — launch scout with the `meta` flag, or run `/scout:meta` in a Claude Code session:

   ```bash
   scout meta     # starts the local SearXNG Docker container, then launches scout
   ```

   ```
   /scout:meta    # starts the container from inside any session; the marketplace install's route
   ```

   Both run the same script, `services/searxng/start-searxng.sh`. First it replaces a `scout-searxng` container left by an older scout (one from another compose project), once, and says so. A scout container that already answers a JSON search on port 8911 is then left running as it is; if something else answers on that port, the script stops and says so. Otherwise it renders the settings and copies the compose file into scout's [state directory](#scouts-state-directory), runs `docker compose up -d` against that copy, and waits up to 30 seconds for SearXNG to answer. Because the container mounts the files in the state directory, it keeps running after the plugin copy it was started from is updated. If Docker is missing, an old container cannot be removed, the container fails to start, or the health-wait times out, `scout meta` prints a plain message naming the cause and launches scout with `WebSearch` instead — it never hard-fails. `/scout:meta` relays the same cause and says that scout falls back to `WebSearch`. The container runs until you stop it with `docker stop scout-searxng`.

   **`scout meta` works on Windows too**, with the same behaviour: it needs **Docker Desktop** (checked when you run `scout meta`, not at install time), generates the `secret_key` with Windows-native crypto instead of openssl, and falls back to `WebSearch` on any failure — Docker absent, container start fails, or health-wait times out.

The rule is one rule: whenever the `searxng` MCP is registered **and** the container answers, scout discovers through it — in plain `scout` runs, `scout meta` runs and dispatches from other agents alike, whoever started the container. `meta` only starts the container. Each source in the report then carries a `discovery: searxng` note; otherwise sources carry `discovery: websearch`. The container restarts with Docker until you stop it, so to send every run back to `WebSearch`, run `docker stop scout-searxng`.

### `json` output is required

The bundled SearXNG settings enable `json` output (`search.formats: [html, json]`). The default SearXNG image ships `html` only, and the `mcp-searxng` MCP needs `json` — without it the MCP breaks. The shipped `services/searxng/config/settings.yml` already has this; do not remove it.

### The secret is generated per deployment — never shipped

SearXNG needs a `server.secret_key`. scout **does not ship one** — the committed `settings.yml` carries an empty `secret_key`, and the start script never writes to it. On mac/Linux, the first start (`scout meta` or `/scout:meta`) generates a key with `openssl rand -hex 32` into `~/.local/state/scout/searxng/secret_key` (mode 600). Every start then renders `~/.local/state/scout/searxng/config/settings.yml` from the shipped template with that key filled in, so the key survives `scout --update` and plugin updates. A template change in a new release reaches the container only after it restarts from the new file: a running container keeps the settings it started with, so run `docker stop scout-searxng` and then start it again. On Windows the launcher generates the key with Windows-native crypto (`System.Security.Cryptography`), since openssl is not present by default, into the installed copy at `%USERPROFILE%\.scout\services\searxng\config\settings.yml`. The repo never contains a real secret, and every deployment gets its own.

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

## Remove scout completely

scout leaves pieces in four places: the plugin copy, two user-scope MCP registrations in Claude Code's config, the SearXNG container, and the [state directory](#scouts-state-directory). Remove the plugin copy with `scout --uninstall` (launcher) or `claude plugin uninstall scout@tenzoki-plugins` (marketplace), then the rest:

```bash
claude mcp remove browser-use -s user
claude mcp remove searxng -s user
docker rm -f scout-searxng
rm -rf ~/.local/state/scout
```

On mac and Linux, `scout --uninstall` already removes the container and the state directory's two subfolders, `browser-use-anthropic/` and `searxng/`. In a directory you chose with `SCOUT_STATE_DIR` it removes a subfolder only if it carries scout's `.scout-owned` marker, and names any it leaves. It then removes the state directory only if it is empty, so other files in that directory are left alone. A marketplace copy on the same machine shares those subfolders, so re-run `/scout:setup` there afterwards if you keep it. Run only the lines for the parts you set up; a line for something that is not there fails harmlessly. If you set `SCOUT_STATE_DIR`, remove scout's subfolders in that directory instead of `~/.local/state/scout`.

## Language

Default is English. scout ships professional-voice style profiles (for the report prose) and chat-voice profiles (for the compact summary it returns) in English and German. For other languages, it reads the English profile and applies the same intent in the target language.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) v2.0.12 or higher.
- That's it for the breadth layer — no Node, no Python, no Docker, and no git with the one-line installer (the marketplace route fetches through git).
- The optional depth layer adds its own requirements: `uvx` (from [uv](https://github.com/astral-sh/uv)) to run browser-use locally, an `ANTHROPIC_API_KEY` (extraction runs on Anthropic via scout's shim), and a local Chromium that browser-use manages. See **Optional depth layer (browser-use)** above. None of this is needed for breadth.
- The optional SearXNG meta backend needs `npx` (from [Node.js](https://nodejs.org)) to run the MCP, and **Docker** to run the container via `scout meta` or `/scout:meta`; the first start on mac/Linux also needs `openssl` to generate the secret. Docker is needed **only** for `meta` — never for the default `scout` path. See **Optional metasearch backend (SearXNG)** above.

## License

MIT. See [LICENSE](LICENSE).
