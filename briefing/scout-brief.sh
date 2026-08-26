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
# there regardless of the working directory cron happened to hand us.
#
# Exit codes (a cron wrapper can act on these):
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
#   SCOUT_BRIEF_MAX_USD  per-invocation cost cap, passed as --max-budget-usd to
#                        each section and to the merge. There is deliberately no
#                        default: a dollar cap is interpretable only against a
#                        model, and scout pins none. The cap is checked between
#                        turns rather than before the API call, so actual spend
#                        overshoots it by 10 to 22 per cent (measured). When it
#                        fires, the section's whole report is lost — unlike the
#                        wall-clock cap, which lets the agent stop and write.
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
die2() { printf 'scout brief: %s\n' "$*" >&2; exit 2; }

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
get_field() {
  awk -v k="$1" 'index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v); print v; exit }' "$2"
}

is_uint() {
  case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-\{1,\}//; s/-\{1,\}$//'
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
trap 'rm -rf "$WORK"' EXIT

# Normalised copy for parsing only. Agents are always given $PROFILE itself.
tr -d '\r' < "$PROFILE" > "$WORK/profile.txt"

# --- 2. Parse the profile -----------------------------------------------------
# Profile-wide fields live above the first `## ` heading; below it every heading
# opens a section. Splitting first keeps a section's own `regions:` line from
# being read as a profile-wide field.
awk '/^##[ \t]/ { exit } { print }' "$WORK/profile.txt" > "$WORK/preamble.txt"

mkdir -p "$WORK/sec"
awk -v dir="$WORK/sec" '
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
  # seeds block.
  awk '
    index($0, "regions:") == 1 { next }
    index($0, "seeds:") == 1   { inseeds = 1; next }
    inseeds && /^-[ \t]/       { next }
    { inseeds = 0; print }
  ' "$body" > "$WORK/sec/$idx.question"
  if ! grep -q '[^[:space:]]' "$WORK/sec/$idx.question"; then
    die2 "the section '$heading' in $PROFILE carries no research question — its prose is what the run researches"
  fi

  get_field regions "$body" > "$WORK/sec/$idx.regions"

  awk '
    index($0, "seeds:") == 1 { inseeds = 1; next }
    inseeds && /^-[ \t]/     { line = $0; sub(/^-[ \t]+/, "", line); sub(/[ \t]+$/, "", line); print line; next }
    inseeds                  { inseeds = 0 }
  ' "$body" > "$WORK/sec/$idx.seeds"

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
say "scout brief — $P_NAME"
say "  profile:     $PROFILE"
say "  run anchor:  $ANCHOR"
say "  sections:    $SEC_COUNT"
say "  worst case:  $SEC_COUNT x $P_PAGES = $((SEC_COUNT * P_PAGES)) pages, $SEC_COUNT x $P_MINUTES = $((SEC_COUNT * P_MINUTES)) minutes of research, plus the merge"
say "  model:       inherited from this environment. scout pins none, so the bill follows how this launcher was started."
if [ -n "${SCOUT_BRIEF_MAX_USD:-}" ]; then
  say "  cost:        bounded by SCOUT_BRIEF_MAX_USD=$SCOUT_BRIEF_MAX_USD per invocation. $((SEC_COUNT + 1)) invocations ($SEC_COUNT sections + 1 merge) x \$$SCOUT_BRIEF_MAX_USD x 1.25 measured overshoot = about \$$(LC_ALL=C awk -v n="$SEC_COUNT" -v c="$SCOUT_BRIEF_MAX_USD" 'BEGIN { printf "%.2f", (n + 1) * c * 1.25 }') worst case."
else
  say "  cost:        unbounded — no cap is set. Export SCOUT_BRIEF_MAX_USD to set one."
  say "               The only measurement that exists is about \$0.27 for one small question answered from two sources. That is a floor per section, not an estimate: a section here carries a $P_PAGES-page crawl."
fi
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
  local rc cpid wpid
  local -a cmd

  cmd=(claude --print --output-format json --plugin-dir "$SCOUT_DIR" --agent "$agent" --permission-mode auto)
  if [ -n "${SCOUT_BRIEF_MAX_USD:-}" ]; then
    cmd=("${cmd[@]}" --max-budget-usd "$SCOUT_BRIEF_MAX_USD")
  fi
  cmd=("${cmd[@]}" "$prompt")

  "${cmd[@]}" < /dev/null > "$out" 2> "$err" &
  cpid=$!
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
    kill -TERM "$cpid" 2>/dev/null || true ) > /dev/null 2>&1 &
  wpid=$!

  rc=0
  wait "$cpid" || rc=$?
  kill -TERM "$wpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true
  return "$rc"
}

# A section's outcome is its exit code and nothing else. The spike recorded a run
# that exited 1 with three research tool calls denied and still wrote a complete
# report, so a file on disk is a property the failing case has too. File
# existence is never consulted here.
outcome_of() {
  local rc="$1" out="$2"
  if [ "$rc" -eq 0 ]; then
    printf 'succeeded\n'
  elif [ "$rc" -eq 143 ]; then
    printf 'timed out\n'
  elif [ -f "$out" ] && grep -q 'budget_exhausted' "$out"; then
    printf 'failed — exceeded its budget\n'
  else
    printf 'failed\n'
  fi
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

merge_rc=0
dispatch scout:briefer "$(cat "$WORK/merge.prompt")" "$WORK/merge.stdout" "$WORK/merge.stderr" "$LIMIT_SECONDS" || merge_rc=$?

if [ "$merge_rc" -ne 0 ] && [ -s "$WORK/merge.stderr" ]; then
  say "        last lines of its error output:"
  sed 's/^/        | /' "$WORK/merge.stderr" | tail -n 5
fi

# --- 8. The exit code ---------------------------------------------------------
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
