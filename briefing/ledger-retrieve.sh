#!/usr/bin/env bash
#
# ledger-retrieve.sh — stage one of scout's story test: retrieval.
#
# THIS SCRIPT IS THE ONLY CODE IN THE REPOSITORY THAT READS A LEDGER.
# That is deliberate and load-bearing. Both agents that need the ledger reach it
# only by invoking this script, so a different retrieval backend (an embedding
# index, say) replaces this one file and touches no agent. If you are adding a
# second reader of the ledger anywhere else, stop: you are removing the seam.
#
# What it does. Given a candidate item — its normalised entity names and its
# one-sentence description — it prints the ledger entries worth judging.
# It applies, in order:
#
#   1. the date window: entries older than --window-days are not consulted.
#      An entry whose date will not parse is KEPT, never dropped. Recall first.
#   2. the overlap rule, two paths joined by "or". An entry is retrieved when it
#      shares at least one normalised entity token with --entities (matched
#      against its `entities:` line and its sentence alike), OR when it shares at
#      least two normalised content words of four characters or more with --text.
#      Both paths exist because either carries matches the other misses: the same
#      story at a second outlet is reached through its entities, and a story whose
#      actor was renamed between runs (a parent company against its subsidiary,
#      sharing no name token at all) is reached only through its words.
#   3. ranking: entity overlap descending, then word overlap descending, then date
#      descending. The first --max entries are printed.
#
# WHAT IT DOES NOT PRINT: any score, rank, count or similarity number of any kind.
# The caller sees candidate entries, verbatim, and nothing else. A number crossing
# this boundary would become a threshold in the judgement behind it, and a
# threshold is exactly what cannot separate one story at two outlets from two
# different announcements by one company. The stages are separate for that reason;
# do not "helpfully" annotate the output.
#
# The ledger stays a plain file a human reads and corrects. The `entities:` line is
# a retrieval aid, not the record: an entry whose line was deleted by hand is still
# reached through the words of its sentence. Hand-editing degrades retrieval; it
# never breaks it.
#
# Usage:
#   ledger-retrieve.sh --ledger <path> --window-days <N> \
#                      --entities "<name>|<name>|..." --text "<one sentence>" [--max <K>]
#
# Exit codes:
#   0  a well-formed call, including one that matches nothing and one whose ledger
#      file does not exist (the first morning).
#   2  a malformed call. The message names the argument at fault.
#
# Targets bash 3.2 (stock macOS). No dependency beyond awk, sort and date.

set -euo pipefail

# Every stage of this pipeline is pinned to the C locale, not just the sort.
# awk's tolower(), [[:punct:]] and length() are locale-sensitive, and length()
# is what decides the two- and four-character token minimums below; under a
# UTF-8 locale gawk counts characters and under C it counts bytes, so an
# unpinned run would tokenise a Chinese entry one way on Linux and another on
# macOS. This script processes ASCII-structured markup and never sorts or
# compares for a human reader, so C is the right collation throughout. Pinning
# it once here also means the retriever does not inherit whatever locale cron
# happened to hand it.
export LC_ALL=C

SELF="${0##*/}"

usage() {
	cat <<USAGE
Usage: $SELF --ledger <path> --window-days <N> --entities "<name>|<name>" --text "<sentence>" [--max <K>]

  --ledger       path to the ledger file. A path that does not exist prints
                 nothing and exits 0 — that is the first-morning case.
  --window-days  how far back to look, in days. Entries older than this are not
                 consulted. An entry whose date will not parse is kept anyway.
  --entities     the candidate's normalised entity names, separated by "|".
                 May be empty; then only the word path can match.
  --text         the candidate's one-sentence description. May be empty; then
                 only the entity path can match.
  --max          how many entries to print at most. Default 25. This bounds the
                 judgement's input size; it is not a preference about coverage.

Prints the matching ledger entries verbatim, in rank order, separated by blank
lines, with no score of any kind.
USAGE
}

die() {
	printf '%s: %s\n' "$SELF" "$1" >&2
	exit 2
}

LEDGER=""
WINDOW=""
ENTITIES=""
TEXT=""
MAX=25

have_ledger=0
have_window=0
have_entities=0
have_text=0

while [ $# -gt 0 ]; do
	case "$1" in
	--ledger)
		[ $# -ge 2 ] || die "--ledger needs a value: the path to the ledger file."
		LEDGER="$2"
		have_ledger=1
		shift 2
		;;
	--window-days)
		[ $# -ge 2 ] || die "--window-days needs a value: a whole number of days."
		WINDOW="$2"
		have_window=1
		shift 2
		;;
	--entities)
		[ $# -ge 2 ] || die "--entities needs a value: the candidate's entity names, separated by |."
		ENTITIES="$2"
		have_entities=1
		shift 2
		;;
	--text)
		[ $# -ge 2 ] || die "--text needs a value: the candidate's one-sentence description."
		TEXT="$2"
		have_text=1
		shift 2
		;;
	--max)
		[ $# -ge 2 ] || die "--max needs a value: a whole number of entries."
		MAX="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf '%s: unrecognised argument: %s\n' "$SELF" "$1" >&2
		usage >&2
		exit 2
		;;
	esac
done

[ "$have_ledger" -eq 1 ] || die "missing required argument --ledger."
[ "$have_window" -eq 1 ] || die "missing required argument --window-days."
[ "$have_entities" -eq 1 ] || die "missing required argument --entities (an empty value is allowed)."
[ "$have_text" -eq 1 ] || die "missing required argument --text (an empty value is allowed)."

[ -n "$LEDGER" ] || die "--ledger is empty: it needs the path to the ledger file."

case "$WINDOW" in
'' | *[!0-9]*) die "--window-days must be a whole number of days, not: $WINDOW" ;;
esac

case "$MAX" in
'' | *[!0-9]*) die "--max must be a whole number of entries, not: $MAX" ;;
esac
[ "$MAX" -ge 1 ] || die "--max must be at least 1, not: $MAX"

# A ledger that does not exist is the first morning, not an error.
[ -e "$LEDGER" ] || exit 0
[ -r "$LEDGER" ] || die "--ledger names a file that cannot be read: $LEDGER"

TODAY=$(date +%Y-%m-%d)
TAB=$(printf '\t')

# A ledger written by the briefing agent carries its entries under a `## Entries`
# heading. When that heading is present, only what follows it is scanned, which
# keeps a bullet in the file's own explanatory prose from being read as an entry.
# When a hand-edit has removed it, every top-level list item in the file is
# scanned instead: the cost is a few extra candidates for the judgement to reject,
# which is the failure direction this stage is supposed to fail in.
GATE=0
if grep -q '^##[ 	]*[Ee]ntries' "$LEDGER"; then
	GATE=1
fi

awk -v today="$TODAY" -v window="$WINDOW" -v cand_ent="$ENTITIES" -v cand_txt="$TEXT" -v gate="$GATE" '
function jdn(s,   p, dp, y, m, d, a, yy, mm) {
	# Julian day number, computed in integer arithmetic rather than through
	# date(1), because BSD and GNU date parse dates with incompatible flags and
	# this script has to run on a stock macOS.
	if (match(s, /[0-9][0-9][0-9][0-9]-[0-9]+-[0-9]+/) == 0) return -1
	p = substr(s, RSTART, RLENGTH)
	split(p, dp, "-")
	y = dp[1] + 0; m = dp[2] + 0; d = dp[3] + 0
	if (m < 1 || m > 12 || d < 1 || d > 31) return -1
	a = int((14 - m) / 12)
	yy = y + 4800 - a
	mm = m + 12 * a - 3
	return d + int((153 * mm + 2) / 5) + 365 * yy + int(yy / 4) - int(yy / 100) + int(yy / 400) - 32045
}

function utf8(cp) {
	# A code point back to its UTF-8 bytes. Used only to build the fold table.
	if (cp < 128) return sprintf("%c", cp)
	if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
	return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
}

function foldrange(lo, hi, delta,   cp) {
	for (cp = lo; cp <= hi; cp++) { FOLDN++; FU[FOLDN] = utf8(cp); FL[FOLDN] = utf8(cp + delta) }
}

function foldcase(s,   t, i) {
	# Lowercase, independent of the locale. The script is pinned to LC_ALL=C so
	# that it tokenises identically everywhere, and in C `tolower()` folds ASCII
	# and nothing else. Left at that, the lowercase entity name an agent passes
	# — `roskomnadzor` spelled in Cyrillic, say — would fail to match the
	# capitalised name that opens the sentence of the entry, which is exactly the
	# path that has to carry an entry whose `entities:` line was deleted by hand.
	# So the fold is done here from a table built once, rather than borrowed from
	# whatever locale cron happened to hand us.
	#
	# Covered: Latin-1 Supplement, Greek and Cyrillic, the three cased alphabets
	# beyond ASCII whose case pairs follow one rule. Latin Extended-A and beyond
	# are not folded, because theirs do not. An unfolded token costs a match the
	# judgement never sees, never a wrong one, and the entity path still reaches
	# such an entry through its `entities:` line, which is written lowercase.
	# Scripts without case — Chinese, Japanese, Korean, Hebrew, Arabic — are
	# untouched here and matched as they stand.
	t = tolower(s)
	if (index(t, LEADLAT) == 0 && index(t, LEADGRK) == 0 && index(t, LEADCYR) == 0) return t
	for (i = 1; i <= FOLDN; i++) if (index(t, FU[i])) gsub(FU[i], FL[i], t)
	return t
}

function norm(s,   t) {
	# Lowercase, punctuation to space, whitespace collapsed. Applied identically
	# to both sides of every comparison, so the two stay commensurable.
	t = foldcase(s)
	gsub(/[[:punct:]]/, " ", t)
	gsub(/[ \t\r\n]+/, " ", t)
	sub(/^ /, "", t)
	sub(/ $/, "", t)
	return t
}

function addtokens(s, arr, minlen,   n, i, parts, tok) {
	n = split(norm(s), parts, " ")
	for (i = 1; i <= n; i++) {
		tok = parts[i]
		if (length(tok) < minlen) continue
		if (tok in STOP) continue
		arr[tok] = 1
	}
}

function sentence_of(s,   t) {
	# The sentence is the record. Strip the list marker, the bold date and any
	# separator in front of it; what remains is what a reader would call the
	# entry. Used only for tokenising — the block is printed verbatim.
	#
	# The separator strip must never be written as "everything that is not a
	# Latin letter or digit": a byte-oriented awk reads that class as
	# "every byte above 0x7F too", which deletes a whole Chinese, Japanese,
	# Cyrillic, Greek, Hebrew or Arabic sentence and eats the first letter of a
	# German one that opens on an umlaut. What is here instead is ASCII
	# punctuation and space, which cannot be part of a multibyte character, plus
	# the dashes matched as whole UTF-8 sequences. A non-Latin sentence therefore
	# keeps every byte it arrived with, and the word path can still reach it when
	# a hand-edit has removed its `entities:` line.
	t = s
	sub(/^-[ \t]*/, "", t)
	sub(/^\*\*[^*]*\*\*/, "", t)
	sub(/^([[:punct:][:space:]]|—|–|―|−)*/, "", t)
	sub(/^[0-9][0-9][0-9][0-9]-[0-9]+-[0-9]+([[:punct:][:space:]]|—|–|―|−)*/, "", t)
	return t
}

function reset() {
	nl = 0
	sentence = ""
	entline = ""
	datejd = -1
	inblock = 0
}

function flush(   i, tok, ek, wk, entset, wordset, blk) {
	if (!inblock) return
	while (nl > 0 && L[nl] ~ /^[ \t\r]*$/) nl--
	if (nl == 0) { reset(); return }

	# The window binds first. An unparseable date (datejd -1) is kept: recall first.
	if (datejd >= 0 && (TODAYJD - datejd) > window) { reset(); return }

	split("", entset)
	split("", wordset)
	# Entity path: the entities line and the sentence alike, because the line is
	# an aid that a hand-edit may have removed.
	addtokens(sentence, entset, 2)
	addtokens(entline, entset, 2)
	# Word path: the sentence alone. That is where the record lives.
	addtokens(sentence, wordset, 4)

	ek = 0
	for (tok in CE) if (tok in entset) ek++
	wk = 0
	for (tok in CW) if (tok in wordset) wk++

	if (ek < 1 && wk < 2) { reset(); return }

	blk = L[1]
	for (i = 2; i <= nl; i++) blk = blk SEP L[i]
	# The three leading fields are the ranking key. They are consumed by the sort
	# and stripped again before anything reaches the caller: no score is printed.
	printf "%d\t%d\t%d\t%s\n", ek, wk, datejd, blk
	reset()
}

BEGIN {
	SEP = sprintf("%c", 1)
	TODAYJD = jdn(today)

	# The fold table, built before the first norm() call. The three lead bytes
	# are the only ones an uppercase letter in the covered ranges can start
	# with, so a string holding none of them skips the fold entirely and an
	# ASCII-only ledger pays nothing for this.
	LEADLAT = sprintf("%c", 195); LEADGRK = sprintf("%c", 206); LEADCYR = sprintf("%c", 208)
	foldrange(192, 214, 32)   # A-grave .. O-diaeresis
	foldrange(216, 222, 32)   # O-slash .. Thorn
	foldrange(913, 929, 32)   # Greek Alpha .. Rho
	foldrange(931, 937, 32)   # Greek Sigma .. Omega
	foldrange(1024, 1039, 80) # Cyrillic Ie-grave .. Dzhe
	foldrange(1040, 1071, 32) # Cyrillic A .. Ya

	# Function words and corporate suffixes. Dropping them keeps two entries from
	# being joined by "with" or by "inc". The list is deliberately short: every
	# word added to it can only remove a match, and recall is this stage.
	stopwords = "the and for with that this from into over under after before their there they them been have will would could should than then when where which while about also more most other such some only said says according upon onto between during against among both each every ahead like just very much many"
	suffixes = "inc incorporated corp corporation ltd limited llc gmbh mbh ag plc sa sas nv bv spa srl oyj kk"
	n = split(stopwords " " suffixes, sw, " ")
	for (i = 1; i <= n; i++) STOP[sw[i]] = 1

	addtokens(cand_ent, CE, 2)
	addtokens(cand_txt, CW, 4)

	inblock = 0
	open = (gate ? 0 : 1)
}

{
	if (!open) {
		if ($0 ~ /^##[ \t]*[Ee]ntries/) open = 1
		next
	}
	if ($0 ~ /^-[ \t]/) {
		flush()
		reset()
		inblock = 1
		sentence = sentence_of($0)
		datejd = jdn($0)
	} else if (!inblock) {
		next
	}
	L[++nl] = $0
	if ($0 ~ /^[ \t]*-[ \t]*entities[ \t]*:/) {
		v = $0
		sub(/^[ \t]*-[ \t]*entities[ \t]*:/, "", v)
		entline = entline " " v
	}
}

END { flush() }
' "$LEDGER" |
	LC_ALL=C sort -t "$TAB" -k1,1nr -k2,2nr -k3,3nr |
	awk -v max="$MAX" -F "$TAB" '
{
	n++
	if (n > max) next
	if (n > 1) print ""
	blk = $4
	for (i = 5; i <= NF; i++) blk = blk "\t" $i
	m = split(blk, lines, sprintf("%c", 1))
	for (i = 1; i <= m; i++) print lines[i]
}
'
