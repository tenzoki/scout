#!/usr/bin/env bash
#
# scout brief — the briefing orchestrator.
#
# Reads a hand-written interest profile, runs one research process per declared
# section, then one merge process, and writes nothing itself beyond the log lines
# it prints. Every file the run produces is written by the two agents it
# dispatches: the section reports by scout:scout, the briefing and the ledger by
# scout:briefer.
#
#   scout brief /path/to/profile.md
#   bash briefing/scout-brief.sh /path/to/profile.md
#
# The profile's own directory is the run anchor: the script changes into it
# before dispatching anything, so every relative path the agents write resolves
# there regardless of the working directory the caller happened to hand us.
#
# Exit codes (a caller or a wrapper can act on these):
#   0  the merge ran and a briefing was written
#   1  the run reached the merge and no usable briefing came out of it
#   2  the run stopped before a briefing could be attempted — a bad argument, an
#      unusable profile, or a missing retrieval script
#
# Per-section outcomes never change the exit code. A run whose every section
# failed still merges, still writes a briefing and still exits 0: the briefing
# carries the failure notes, and a caller that wants to act on them reads it.
#
# Optional environment:
#   SCOUT_BRIEF_MAX_USD  per-invocation usage cap, passed as --max-budget-usd to
#                        each section and to the merge. There is deliberately no
#                        default: the number is interpretable only against a
#                        model, and scout pins none.
#
#                        What it caps is token usage priced at the published
#                        list rate and computed locally — every result object
#                        this script reads carries costBasis: "list". On a
#                        claude.ai subscription install no money is billed at
#                        all and a run spends the plan's rolling usage windows
#                        instead; on an API-key install the same figure is the
#                        bill. The flag enforces in both cases, so it is a usage
#                        cap wearing a currency sign rather than a cost bound.
#
#                        The cap is checked between turns rather than before the
#                        API call, so an invocation overshoots it by up to one
#                        whole turn. That floor is an absolute amount, not a
#                        fraction of the cap: at $0.25 the measured overshoot
#                        was 10 per cent, at $0.02 it was 854 per cent — $0.02
#                        asked, $0.19089 spent, in one turn. One turn on a large
#                        model with scout's system prompt measures about $0.19
#                        (BRIEF_ONE_TURN_USD below), so a cap of that order or
#                        under bounds almost nothing. When it fires, the
#                        section's whole report is lost — unlike the wall-clock
#                        cap, which lets the agent stop and write.
#
# Targets bash 3.2, which is what stock macOS ships.

set -euo pipefail

# --- 0. Self-location, before any directory change ----------------------------
# $0 is resolved here because everything below runs from the run anchor, which is
# the user's directory and knows nothing about where the plugin is installed.
SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SCOUT_DIR="$(cd "$SELF_DIR/.." && pwd -P)"
RETRIEVER="$SELF_DIR/ledger-retrieve.sh"

# --- Helpers ------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
# FINISHED marks the exit as chosen rather than stumbled into; see the EXIT trap.
# Assigning it before the trap exists is harmless: it is read only from there.
die2() { printf 'scout brief: %s\n' "$*" >&2; FINISHED=1; exit 2; }

usage() {
  cat >&2 <<'USAGE'
usage: scout brief <profile.md>

Runs one research process per section declared in the interest profile, then one
merge process, and writes the briefing beside the profile under scout-workbench/.
See briefing/example-profile.md for the profile format.
USAGE
}

# Modification time in epoch seconds. GNU stat first, BSD stat second; anything
# else yields 0, which makes the caller treat a candidate report as too old
# rather than claim a stale file belongs to this run.
file_mtime() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || true)"
  case "$m" in ''|*[!0-9]*) m="$(stat -f %m "$1" 2>/dev/null || true)" ;; esac
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  printf '%s\n' "$m"
}

# First value of a `key: value` line, matched at the start of a line only.
# One awk, no pipeline: a `... | head -1` here would hand sed a SIGPIPE and
# pipefail would turn a successful read into exit 141.
#
# Every awk, tr and sed stage that interprets profile text runs under LC_ALL=C.
# length(), tolower() and the character classes are locale-sensitive, the profile
# is UTF-8 whatever the machine's locale says, and a parse that reads one way on a
# German machine and another way on an English one is not a parse anyone can
# reason about.
get_field() {
  LC_ALL=C awk -v k="$1" 'index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v); print v; exit }' "$2"
}

is_uint() {
  case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# Pinned per command rather than for the function: exporting LC_ALL here would
# also hand it to the agents this script dispatches, whose text is not ours to
# recode.
slugify() {
  printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9]\{1,\}/-/g; s/^-\{1,\}//; s/-\{1,\}$//'
}

# --- 1. The profile argument --------------------------------------------------
if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  usage
  exit 2
fi
if [ "$#" -gt 1 ]; then
  warn "scout brief: ignoring extra arguments after the profile path."
fi

PROFILE_ARG="$1"
[ -f "$PROFILE_ARG" ] || die2 "no such profile file: $PROFILE_ARG"
[ -r "$PROFILE_ARG" ] || die2 "profile file is not readable: $PROFILE_ARG"

PROFILE="$(cd "$(dirname "$PROFILE_ARG")" && pwd -P)/$(basename "$PROFILE_ARG")"
ANCHOR="$(dirname "$PROFILE")"

# The retrieval script is the only way into the ledger and both agents need it by
# absolute path. Without it the story test cannot run and the briefing would
# republish everything, so a missing one stops the run rather than degrading it.
[ -f "$RETRIEVER" ] || die2 "the retrieval script is missing: $RETRIEVER"
[ -x "$RETRIEVER" ] || die2 "the retrieval script is not executable: $RETRIEVER (chmod +x it)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scout-brief.XXXXXX")"

# The three codes at the top of this file are the whole contract, so every path
# out of the script has to land on one of them — including a `set -e` or `set -u`
# abort, which names no code of its own. Two variables carry that:
#
#   FINISHED  set only where this script decides its own answer, which is die2 and
#             the two explicit exits at the end. Empty means the run stopped
#             somewhere it did not choose.
#   STAGE     the code an unchosen stop carries: 2 until the merge is dispatched,
#             1 from there on, matching the two definitions above.
#
# `$?` cannot stand in for FINISHED. Measured on bash 3.2.57: on a `set -u` abort
# the EXIT trap sees `$?` as 0, because the status still belongs to the last
# command that ran rather than to the abort. Reading it and re-exiting it hands
# the caller 0, which is the code this contract reserves for "a briefing was
# written" — the one answer a caller must never get for a morning that produced
# nothing. The trap therefore trusts `$?` only where FINISHED says it was chosen.
FINISHED=""
STAGE=2
trap 'rc=$?; rm -rf "$WORK" 2>/dev/null || true; if [ -n "$FINISHED" ]; then exit "$rc"; fi; exit "$STAGE"' EXIT

# Normalised copy for parsing only. Agents are always given $PROFILE itself.
tr -d '\r' < "$PROFILE" > "$WORK/profile.txt"

# --- 2. Parse the profile -----------------------------------------------------
# Profile-wide fields live above the first `## ` heading; below it every heading
# opens a section. Splitting first keeps a section's own `regions:` line from
# being read as a profile-wide field.
LC_ALL=C awk '/^##[ \t]/ { exit } { print }' "$WORK/profile.txt" > "$WORK/preamble.txt"

mkdir -p "$WORK/sec"
LC_ALL=C awk -v dir="$WORK/sec" '
  /^##[ \t]/ {
    n++
    line = $0
    sub(/^##[ \t]+/, "", line)
    sub(/[ \t]+$/, "", line)
    hf = sprintf("%s/%03d.heading", dir, n)
    print line > hf
    close(hf)
    bf = sprintf("%s/%03d.body", dir, n)
    printf "" > bf
    close(bf)
    next
  }
  n > 0 { print >> bf }
' "$WORK/profile.txt"

P_NAME="$(get_field name "$WORK/preamble.txt")"
P_LANGUAGE="$(get_field language "$WORK/preamble.txt")"
P_YIELD="$(get_field yield-target "$WORK/preamble.txt")"
P_PAGES="$(get_field max-pages "$WORK/preamble.txt")"
P_HOPS="$(get_field max-hops "$WORK/preamble.txt")"
P_MINUTES="$(get_field max-minutes "$WORK/preamble.txt")"
P_DEPTH="$(get_field depth "$WORK/preamble.txt")"
P_WINDOW="$(get_field ledger-window-days "$WORK/preamble.txt")"

# The starting values. They are proposals with no measurement behind them and are
# expected to be tuned; briefing/example-profile.md and the README carry the same
# six numbers.
[ -n "$P_YIELD" ]   || P_YIELD=8
[ -n "$P_PAGES" ]   || P_PAGES=40
[ -n "$P_HOPS" ]    || P_HOPS=2
[ -n "$P_MINUTES" ] || P_MINUTES=15
[ -n "$P_DEPTH" ]   || P_DEPTH=off
[ -n "$P_WINDOW" ]  || P_WINDOW=60

# --- 3. Validate --------------------------------------------------------------
MISSING=""
MISSING_N=0
if [ -z "$P_NAME" ]; then MISSING="name"; MISSING_N=1; fi
if [ -z "$P_LANGUAGE" ]; then MISSING="${MISSING:+$MISSING and }language"; MISSING_N=$((MISSING_N + 1)); fi
if [ "$MISSING_N" -eq 1 ]; then
  die2 "the required field $MISSING is missing from the profile $PROFILE"
elif [ "$MISSING_N" -gt 1 ]; then
  die2 "the required fields $MISSING are missing from the profile $PROFILE"
fi

case "$P_NAME" in
  [[:lower:][:digit:]]*) ;;
  *) die2 "name '$P_NAME' in $PROFILE must start with a lowercase letter or a digit" ;;
esac
case "$P_NAME" in
  *[![:lower:][:digit:]-]*) die2 "name '$P_NAME' in $PROFILE may hold only lowercase letters, digits and hyphens — it names the ledger and the briefing file" ;;
esac

for pair in "yield-target:$P_YIELD" "max-pages:$P_PAGES" "max-hops:$P_HOPS" "max-minutes:$P_MINUTES" "ledger-window-days:$P_WINDOW"; do
  fname="${pair%%:*}"
  fval="${pair#*:}"
  is_uint "$fval" || die2 "$fname is '$fval' in $PROFILE — it has to be a whole number of zero or more"
done

# Re-read every validated number in base 10 before anything computes with it.
# The profile is a hand-edited column of caps and padding one with a zero is an
# ordinary thing to do to a column, but bash reads a leading zero as octal, where
# 08 and 09 do not exist. Without this, `max-minutes: 08` passes the loop above
# and then breaks every $(( )) below it, taking LIMIT_SECONDS with it.
P_YIELD=$((10#$P_YIELD))
P_PAGES=$((10#$P_PAGES))
P_HOPS=$((10#$P_HOPS))
P_MINUTES=$((10#$P_MINUTES))
P_WINDOW=$((10#$P_WINDOW))

case "$P_DEPTH" in
  on|off) ;;
  *) die2 "depth is '$P_DEPTH' in $PROFILE — it has to be on or off" ;;
esac

if [ -n "${SCOUT_BRIEF_MAX_USD:-}" ]; then
  case "$SCOUT_BRIEF_MAX_USD" in
    '' | *[!0-9.]* | *.*.* | .) die2 "SCOUT_BRIEF_MAX_USD is '$SCOUT_BRIEF_MAX_USD' — it has to be a number of dollars, for example 0.50" ;;
  esac
fi

# Collect the sections in profile order.
SEC_COUNT=0
SEC_HEADING=()
SEC_SLUG=()
SEC_IDX=()
for hf in "$WORK"/sec/*.heading; do
  [ -e "$hf" ] || continue
  idx="$(basename "$hf" .heading)"
  heading="$(cat "$hf")"
  [ -n "$heading" ] || die2 "a '## ' heading in $PROFILE is empty — every section needs a name"

  body="$WORK/sec/$idx.body"
  [ -f "$body" ] || printf '' > "$body"

  # The question is the section's prose: everything but its regions line and its
  # seeds block. The block accepts the two shapes a hand-editor writes besides the
  # shipped one — an indented item, and a blank line between `seeds:` and the
  # first item — because the profile's design is that nobody is fighting a schema,
  # and because reading those as prose drops the seeds where no one can see it.
  # The two awk programs here and below read one block and must stay in step.
  LC_ALL=C awk '
    index($0, "regions:") == 1 { next }
    index($0, "seeds:") == 1   { inseeds = 1; next }
    inseeds && /^[ \t]*-[ \t]/ { next }
    inseeds && /^[ \t]*$/      { next }
    { inseeds = 0; print }
  ' "$body" > "$WORK/sec/$idx.question"
  if ! grep -q '[^[:space:]]' "$WORK/sec/$idx.question"; then
    die2 "the section '$heading' in $PROFILE carries no research question — its prose is what the run researches"
  fi

  get_field regions "$body" > "$WORK/sec/$idx.regions"

  LC_ALL=C awk '
    index($0, "seeds:") == 1   { inseeds = 1; next }
    inseeds && /^[ \t]*-[ \t]/ { line = $0; sub(/^[ \t]*-[ \t]+/, "", line); sub(/[ \t]+$/, "", line); print line; next }
    inseeds && /^[ \t]*$/      { next }
    inseeds                    { inseeds = 0 }
  ' "$body" > "$WORK/sec/$idx.seeds"

  # A shape neither program reads is still possible — an indented `seeds:` line,
  # a `*` bullet — and a section that runs without the sources you named looks
  # exactly like one you gave none. It is a warning rather than a stop because the
  # section is still researchable; it is not silence because you cannot see this
  # from the briefing.
  if grep -qE '^[[:space:]]*seeds:' "$body" && ! grep -q '[^[:space:]]' "$WORK/sec/$idx.seeds"; then
    warn "scout brief: the section '$heading' in $PROFILE carries a seeds: line but no seed URL was read from it, so it runs with none. A seeds block is a 'seeds:' line at the left margin followed by items beginning with '- '."
  fi

  slug="$(slugify "$heading")"
  [ -n "$slug" ] || slug="section-$idx"
  # A slug is half of a report filename, so two sections may not share one.
  n=1
  base="$slug"
  while [ "$n" -le "$SEC_COUNT" ]; do
    if [ "${SEC_SLUG[$((n - 1))]}" = "$slug" ]; then
      slug="$base-$idx"
      break
    fi
    n=$((n + 1))
  done

  SEC_HEADING[$SEC_COUNT]="$heading"
  SEC_SLUG[$SEC_COUNT]="$slug"
  SEC_IDX[$SEC_COUNT]="$idx"
  SEC_COUNT=$((SEC_COUNT + 1))
done

if [ "$SEC_COUNT" -eq 0 ]; then
  die2 "the profile $PROFILE declares no section — one '## ' heading opens one section, and a run needs at least one"
fi

# --- 4. The run anchor --------------------------------------------------------
cd "$ANCHOR"

TODAY="$(date +%Y-%m-%d)"
LEDGER_REL="scout-workbench/ledgers/$P_NAME.md"
BRIEFING_REL="scout-workbench/briefings/$TODAY-$P_NAME.md"
LIMIT_SECONDS=$(( (P_MINUTES + 5) * 60 ))

# --- 5. The run banner --------------------------------------------------------
# One turn's usage, in the same list-priced dollars --max-budget-usd counts.
# Measured in the S-2 spike: a $0.02 cap came back having spent $0.19089 in a
# single turn, on a large model with scout's ~18k-token cached system prompt.
# It is the floor on how far a cap can be overshot, because the cap is checked
# between turns. It is model-dependent — a smaller model makes the banner's
# worst case an over-estimate, which is the safe direction — so the banner names
# it as a measurement rather than printing a bare total, and a model change
# falsifies the figure rather than the rule above it.
BRIEF_ONE_TURN_USD=0.19

say "scout brief — $P_NAME"
say "  profile:     $PROFILE"
say "  run anchor:  $ANCHOR"
say "  sections:    $SEC_COUNT"
# The minutes half states the ceiling the watchdog actually enforces, which is
# LIMIT_SECONDS per dispatch and one dispatch more than there are sections. The
# banner is the only place the worst case is put in front of the operator before
# the run starts, so it may not name a number the run routinely exceeds.
if [ "$SEC_COUNT" -eq 1 ]; then SEC_WORD="section"; else SEC_WORD="sections"; fi
say "  worst case:  $SEC_COUNT x $P_PAGES = $((SEC_COUNT * P_PAGES)) pages; $((SEC_COUNT + 1)) x ($P_MINUTES + 5 grace) = $(( (SEC_COUNT + 1) * (P_MINUTES + 5) )) minutes ($SEC_COUNT $SEC_WORD + the merge)"
say "  model:       inherited from this environment. scout pins none, so how this launcher was started is what decides a run's usage."
# The usage half of the banner. Two things it may not do. It may not call the
# figure a cost: under the subscription auth most installs have, every result
# object carries costBasis "list" and nothing is billed in money, so the number
# is a locally computed list-price valuation of tokens. And it may not express
# the cap's overshoot as a percentage: the cap is checked between turns, so the
# floor on overshoot is one whole turn — an absolute amount that dominates any
# small cap. A $0.02 cap was measured spending $0.19089, 854 per cent, in one
# turn; the 1.25 multiplier this line used to carry was right only for caps well
# above one turn's cost.
if [ -n "${SCOUT_BRIEF_MAX_USD:-}" ]; then
  say "  usage:       SCOUT_BRIEF_MAX_USD=\$$SCOUT_BRIEF_MAX_USD caps each of $((SEC_COUNT + 1)) invocations ($SEC_COUNT $SEC_WORD + the merge)."
  say "               The cap is checked between turns, so each invocation may overshoot it by up to one whole turn — measured at about \$$BRIEF_ONE_TURN_USD on a large model with scout's prompt. Worst case is therefore about \$$(LC_ALL=C awk -v n="$SEC_COUNT" -v c="$SCOUT_BRIEF_MAX_USD" -v t="$BRIEF_ONE_TURN_USD" 'BEGIN { printf "%.2f", (n + 1) * (c + t) }'), not $((SEC_COUNT + 1)) x \$$SCOUT_BRIEF_MAX_USD."
  if LC_ALL=C awk -v c="$SCOUT_BRIEF_MAX_USD" -v t="$BRIEF_ONE_TURN_USD" 'BEGIN { exit !(c <= t) }'; then
    say "               That cap is at or below one turn, so it cannot stop an invocation until the turn that breaches it has already been spent. It bounds a runaway, not this run."
  fi
else
  say "  usage:       unbounded — no cap is set. Export SCOUT_BRIEF_MAX_USD to set one."
  say "               The only measurement that exists is about \$0.27 for one small question answered from two sources. That is a floor per section, not an estimate: a section here carries a $P_PAGES-page crawl."
fi
say "               These \$ figures are token usage priced at list rate, computed locally — not necessarily money. On a claude.ai subscription install nothing is billed and a run spends the plan's rolling usage windows; on an API-key install the same figure is the bill."
say ""

mkdir -p scout-workbench/research scout-workbench/briefings scout-workbench/ledgers

# --- Dispatch -----------------------------------------------------------------
# The command line below is the one the step-1 spike measured working, with
# --output-format json added so a failure can say whether it was the budget.
# Three parts are load-bearing and must not drift:
#   --permission-mode auto  is the only probed mode granting WebSearch, WebFetch,
#                           Write and Bash together. In a non-interactive run a
#                           permission prompt does not hang, it denies, so a
#                           wrong mode degrades the run silently.
#   no --setting-sources    user settings are where the MCP registrations live;
#                           excluding them would disable the depth and meta
#                           backends without saying so.
#   no --model              the run inherits the caller's model by decision.
# stdin is closed deliberately, for the same reason the permission mode matters.
#
# The wall-clock cap is a watchdog because no flag bounds time and neither
# timeout nor gtimeout is on a stock macOS PATH. The child finishing first yields
# its own code; the watchdog firing yields 143.
dispatch() {
  local agent="$1" prompt="$2" out="$3" err="$4" limit="$5"
  local rc cpid wpid fired
  local -a cmd

  cmd=(claude --print --output-format json --plugin-dir "$SCOUT_DIR" --agent "$agent" --permission-mode auto)
  if [ -n "${SCOUT_BRIEF_MAX_USD:-}" ]; then
    cmd=("${cmd[@]}" --max-budget-usd "$SCOUT_BRIEF_MAX_USD")
  fi
  cmd=("${cmd[@]}" "$prompt")

  # The watchdog's record that it fired, written before it signals anything.
  # `wait` reports 143 for a SIGTERM and 137 for the SIGKILL that follows it, and
  # a timeout has to read as a timeout either way, because outcome_of tells one
  # from a failure by the value 143 alone. The file says who ended the child. It
  # never says whether the child did any work: that stays the exit code's job, and
  # a child that finished on its own keeps the code it chose.
  fired="$out.watchdog-fired"
  rm -f "$fired"

  # Job control for this one command, so the child leads its own process group and
  # the watchdog can signal the group rather than one pid. Without it the child's
  # own descendants — under `depth: on` a headless browser and its MCP servers —
  # outlive the cap that exists to bound them and keep fetching and spending while
  # the next section runs.
  set -m
  "${cmd[@]}" < /dev/null > "$out" 2> "$err" &
  cpid=$!
  set +m

  # The watchdog polls rather than sleeping the whole limit in one go, and its
  # own output goes nowhere. Both matter: a single long `sleep` survives the kill
  # below as an orphan and keeps holding this script's stdout, which hangs any
  # caller that pipes us (`scout brief p.md | tee log`) for the length of the cap.
  # `trap - EXIT` so the subshell, which inherits this shell's traps, cannot
  # delete the working directory out from under the run when it exits.
  ( trap - EXIT
    SECONDS=0
    while [ "$SECONDS" -lt "$limit" ]; do
      sleep 1
      kill -0 "$cpid" 2>/dev/null || exit 0
    done
    : > "$fired"
    # The group first, the bare pid as the fallback for a child that never got a
    # group of its own. SIGTERM lets the agent stop and write what it has; the
    # SIGKILL ten seconds later is what bounds a child that ignores SIGTERM.
    # Without the escalation `wait` below has no bound at all, and a run that
    # hangs forever is worse than one that fails.
    kill -TERM -"$cpid" 2>/dev/null || kill -TERM "$cpid" 2>/dev/null || true
    grace=0
    while [ "$grace" -lt 10 ]; do
      sleep 1
      kill -0 "$cpid" 2>/dev/null || exit 0
      grace=$((grace + 1))
    done
    kill -KILL -"$cpid" 2>/dev/null || kill -KILL "$cpid" 2>/dev/null || true ) > /dev/null 2>&1 &
  wpid=$!

  rc=0
  # The redirection is on the builtin, not on the child: bash announces a job that
  # died by signal ("… Terminated: 15", "… Killed: 9") on the shell's stderr as it
  # reaps it, and that line lands on the caller's stderr on every timeout the
  # design intends, reading as a fault in this script. Redirecting `wait`
  # itself suppresses the announcement and still yields the child's status
  # (measured on bash 3.2.57; `set -m` does not suppress it).
  { wait "$cpid"; } 2>/dev/null || rc=$?
  kill -TERM "$wpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true
  # A child that beat the watchdog to the finish by a second keeps its own code:
  # the flag only renames a non-zero death the watchdog caused.
  if [ "$rc" -ne 0 ] && [ -f "$fired" ]; then
    rc=143
  fi
  rm -f "$fired"
  return "$rc"
}

# The string value of a top-level JSON key in a --output-format json result
# object, with the usual escapes flattened enough to be substring-matched.
# Prints nothing when the key is absent or its value is not a string.
#
# This exists rather than a grep over the whole file because the strings that
# identify a rate limit include "401" and "529", and those three digits occur in
# duration_ms, in num_turns, in a session id and in a cost figure. A whole-file
# grep would call a perfectly healthy run rate-limited. There is no jq on a
# stock macOS, so the extraction is done here.
json_string_field() {
  LC_ALL=C awk -v key="$1" '
    { buf = buf $0 "\n" }
    END {
      k = "\"" key "\""
      L = length(buf)
      # The first "result" in a result object is the *value* of "type", so an
      # occurrence only counts as the key when a colon follows it.
      pos = 1
      while (1) {
        n = index(substr(buf, pos), k)
        if (n == 0) exit 0
        n = pos + n - 1
        i = n + length(k)
        while (i <= L && substr(buf, i, 1) ~ /[ \t\r\n]/) i++
        if (substr(buf, i, 1) == ":") break
        pos = n + 1
      }
      i++
      while (i <= L && substr(buf, i, 1) ~ /[ \t\r\n]/) i++
      # A non-string value (null, a number, an object) is not an answer here.
      if (substr(buf, i, 1) != "\"") exit 0
      i++
      out = ""
      while (i <= L) {
        c = substr(buf, i, 1)
        if (c == "\\") {
          e = substr(buf, i + 1, 1)
          # \n \t \r become a space so a multi-line message stays one line and
          # two words never fuse into a third; \" \\ \/ keep their character.
          if (e == "n" || e == "t" || e == "r") out = out " "
          else if (e == "u") { out = out " "; i += 4 }
          else out = out e
          i += 2
          continue
        }
        if (c == "\"") break
        out = out c
        i++
      }
      print out
    }
  ' "$2" 2>/dev/null || true
}

# A section's outcome is its exit code first, and the result object only where
# the exit code cannot tell two very different failures apart. The spike recorded
# a run that exited 1 with three research tool calls denied and still wrote a
# complete report, so a file on disk is a property the failing case has too. File
# existence is never consulted here.
#
# Why the JSON is read at all: a host that cannot log in and a host that has hit
# its usage limit both exit non-zero and both used to render as a bare "failed",
# which is also what a quiet news day renders as. The operator could not tell a
# broken host from an empty web. Measured sample from the S-2 spike, an
# unauthenticated dispatch:
#
#   {"is_error": true, "subtype": "success", "terminal_reason": "api_error",
#    "api_error_status": null, "result": "Not logged in · Please run /login"}
#
# Two consequences. subtype reads "success" on that run, so it is never keyed on
# here. And the diagnosis is prose in result, so a substring test on that prose
# is the only instrument available — there is no rate-limit subtype to key on the
# way budget_exhausted can be.
#
# What is measured and what is not: terminal_reason "api_error" carrying the real
# diagnosis in result is observed. The specific phrases below are read out of the
# shipped binary's own health classifier, not provoked — forcing a 429 spends a
# real share of the user's usage window. That is why an api_error whose prose
# matches nothing known falls through to plain "failed" rather than to a guess:
# where the evidence is second-hand the code degrades to what it said before,
# and a phrase list that turns out to be wrong costs a label, never a wrong one.
outcome_of() {
  local rc="$1" out="$2" reason result
  if [ "$rc" -eq 0 ]; then
    printf 'succeeded\n'
    return 0
  fi
  if [ "$rc" -eq 143 ]; then
    printf 'timed out\n'
    return 0
  fi
  # Budget first, and still by the whole-file grep the spike verified against a
  # real error_max_budget_usd object rather than by the extractor below.
  if [ -f "$out" ] && grep -q 'budget_exhausted' "$out"; then
    printf 'failed — exceeded its budget\n'
    return 0
  fi
  if [ -f "$out" ]; then
    reason="$(json_string_field terminal_reason "$out")"
    if [ "$reason" = "api_error" ]; then
      # Case-folded once, so the phrase list below does not have to carry a
      # capitalised twin of every entry and cannot miss a third spelling.
      result="$(json_string_field result "$out" | LC_ALL=C tr 'A-Z' 'a-z')"
      case "$result" in
        *"please run /login"* | *"not logged in"* | *"invalid api key"* | *401*)
          printf 'failed — not authenticated\n'
          return 0 ;;
        *"rate limited"* | *"rate_limit"* | *"usage limit reached"* | \
        *"credit balance too low"* | *overloaded* | *529*)
          printf 'failed — rate limited or over the usage limit\n'
          return 0 ;;
      esac
    fi
  fi
  printf 'failed\n'
}

# The newest report whose name ends -<slug>.md and whose modification time is at
# or after the section's start. No filename is predicted: the prefix half of a
# report's name is the agent's, and the issue record shows it is not reliably the
# orchestrator's to set. The mtime half of the rule is not decoration. One slug
# can be the tail of another (`models` ends `small-models` too), and it is the
# start time that keeps a section from claiming an earlier section's report —
# which holds because the sections run one after another.
find_report() {
  local slug="$1" since="$2" dir="scout-workbench/research"
  local listing f m
  [ -d "$dir" ] || return 0
  listing="$(ls -t "$dir" 2>/dev/null || true)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in *"-$slug.md") ;; *) continue ;; esac
    [ -f "$dir/$f" ] || continue
    m="$(file_mtime "$dir/$f")"
    if [ "$m" -ge "$since" ]; then
      printf '%s\n' "$dir/$f"
      return 0
    fi
  done <<EOF
$listing
EOF
  return 0
}

# --- 6. The sections, one after another ---------------------------------------
SEC_OUTCOME=()
SEC_RC=()
SEC_MINUTES=()
SEC_REPORT=()

i=0
while [ "$i" -lt "$SEC_COUNT" ]; do
  heading="${SEC_HEADING[$i]}"
  slug="${SEC_SLUG[$i]}"
  idx="${SEC_IDX[$i]}"
  n=$((i + 1))

  started_at="$(date +%s)"

  {
    printf 'Research question for the briefing section "%s":\n\n' "$heading"
    cat "$WORK/sec/$idx.question"
    printf '\nCRAWL DIRECTIVE\n'
    printf 'yield-target: %s\n' "$P_YIELD"
    printf 'max-pages: %s\n' "$P_PAGES"
    printf 'max-hops: %s\n' "$P_HOPS"
    printf 'max-minutes: %s\n' "$P_MINUTES"
    printf 'started-at: %s\n' "$started_at"
    printf 'depth: %s\n' "$P_DEPTH"
    printf 'ledger: %s\n' "$LEDGER_REL"
    printf 'ledger-window-days: %s\n' "$P_WINDOW"
    printf 'retriever: %s\n' "$RETRIEVER"
    printf 'report-slug: %s\n' "$slug"
    if grep -q '[^[:space:]]' "$WORK/sec/$idx.regions"; then
      printf 'regions: %s\n' "$(cat "$WORK/sec/$idx.regions")"
    fi
    if grep -q '[^[:space:]]' "$WORK/sec/$idx.seeds"; then
      printf 'seeds:\n'
      sed 's/^/- /' "$WORK/sec/$idx.seeds"
    fi
  } > "$WORK/sec/$idx.prompt"

  say "[$n/$SEC_COUNT] $heading — researching (cap $P_MINUTES min + 5 min grace, $P_PAGES pages, $P_HOPS hops)"

  rc=0
  dispatch scout:scout "$(cat "$WORK/sec/$idx.prompt")" "$WORK/sec/$idx.stdout" "$WORK/sec/$idx.stderr" "$LIMIT_SECONDS" || rc=$?

  ended_at="$(date +%s)"
  elapsed=$((ended_at - started_at))
  outcome="$(outcome_of "$rc" "$WORK/sec/$idx.stdout")"
  report="$(find_report "$slug" "$started_at")"

  SEC_OUTCOME[$i]="$outcome"
  SEC_RC[$i]="$rc"
  SEC_MINUTES[$i]="$(LC_ALL=C awk -v s="$elapsed" 'BEGIN { printf "%.1f", s / 60 }')"
  SEC_REPORT[$i]="$report"

  say "[$n/$SEC_COUNT] $heading — $outcome (exit $rc, ${SEC_MINUTES[$i]} min, report: ${report:-none})"
  if [ "$rc" -ne 0 ] && [ -s "$WORK/sec/$idx.stderr" ]; then
    say "        last lines of its error output:"
    sed 's/^/        | /' "$WORK/sec/$idx.stderr" | tail -n 5
  fi

  i=$((i + 1))
done

say ""

# --- 6b. When the sections did not fail at research ----------------------------
# outcome_of now tells an unauthenticated or rate-limited section from one that
# simply found nothing. This says it once for the whole run, on stderr, because
# the per-section lines above scroll past and a wrapper's log keeps stderr.
#
# The exit code is deliberately NOT changed here. That per-section outcomes never
# move it is a documented contract (see the top of this file), and a run whose
# every section failed to authenticate still merges and still exits 0 — an empty
# briefing with a success code. Changing that is a decision, not a fix, and it is
# raised as one rather than taken here. What this block can do without touching
# the contract is refuse to let the failure be silent.
AUTH_FAILURES=0
LIMIT_FAILURES=0
i=0
while [ "$i" -lt "$SEC_COUNT" ]; do
  case "${SEC_OUTCOME[$i]}" in
    'failed — not authenticated')  AUTH_FAILURES=$((AUTH_FAILURES + 1)) ;;
    'failed — rate limited'*)      LIMIT_FAILURES=$((LIMIT_FAILURES + 1)) ;;
  esac
  i=$((i + 1))
done

if [ "$AUTH_FAILURES" -gt 0 ]; then
  warn "scout brief: $AUTH_FAILURES of $SEC_COUNT $SEC_WORD could not authenticate. That is this host, not a quiet day: the briefing will be thin or empty for a reason that has nothing to do with the web. Run 'claude auth status' to see whether this machine is logged in."
fi
if [ "$LIMIT_FAILURES" -gt 0 ]; then
  warn "scout brief: $LIMIT_FAILURES of $SEC_COUNT $SEC_WORD was refused for a rate or usage limit. Wait for the limit window to reset and run the profile again."
fi
if [ $((AUTH_FAILURES + LIMIT_FAILURES)) -gt 0 ]; then
  warn "scout brief: the exit code does not reflect this — per-section outcomes never change it. Each section's outcome is in the briefing."
fi

# --- 7. The merge -------------------------------------------------------------
# A failed section's report, where one exists, is passed with its outcome beside
# it rather than dropped: the spike's degraded report was honest about its own
# degradation and its one verified finding was real.
{
  printf 'Merge the section reports listed below into one briefing, following your agent contract.\n\n'
  printf 'BRIEFING MERGE\n'
  printf 'profile: %s\n' "$PROFILE"
  printf 'profile-name: %s\n' "$P_NAME"
  printf 'language: %s\n' "$P_LANGUAGE"
  printf 'run-anchor: %s\n' "$ANCHOR"
  printf 'ledger: %s\n' "$LEDGER_REL"
  printf 'ledger-window-days: %s\n' "$P_WINDOW"
  printf 'retriever: %s\n' "$RETRIEVER"
  printf 'briefing: %s\n' "$BRIEFING_REL"
  printf 'sections:\n'
  i=0
  while [ "$i" -lt "$SEC_COUNT" ]; do
    printf -- '- heading: %s\n' "${SEC_HEADING[$i]}"
    printf '  slug: %s\n' "${SEC_SLUG[$i]}"
    printf '  outcome: %s\n' "${SEC_OUTCOME[$i]}"
    printf '  exit-code: %s\n' "${SEC_RC[$i]}"
    printf '  elapsed-minutes: %s\n' "${SEC_MINUTES[$i]}"
    printf '  report: %s\n' "${SEC_REPORT[$i]:-none}"
    i=$((i + 1))
  done
} > "$WORK/merge.prompt"

say "merging $SEC_COUNT section(s) into $BRIEFING_REL"

# From here on a briefing has been attempted, so an abort is a 1 and not a 2.
STAGE=1

merge_rc=0
dispatch scout:briefer "$(cat "$WORK/merge.prompt")" "$WORK/merge.stdout" "$WORK/merge.stderr" "$LIMIT_SECONDS" || merge_rc=$?

if [ "$merge_rc" -ne 0 ] && [ -s "$WORK/merge.stderr" ]; then
  say "        last lines of its error output:"
  sed 's/^/        | /' "$WORK/merge.stderr" | tail -n 5
fi

# --- 8. The exit code ---------------------------------------------------------
FINISHED=1
if [ "$merge_rc" -eq 0 ] && [ -s "$BRIEFING_REL" ]; then
  say "briefing written: $ANCHOR/$BRIEFING_REL"
  exit 0
fi

if [ "$merge_rc" -ne 0 ]; then
  warn "scout brief: the merge exited $merge_rc and no briefing was written."
else
  warn "scout brief: the merge exited 0 but wrote no briefing at $ANCHOR/$BRIEFING_REL."
fi
exit 1
