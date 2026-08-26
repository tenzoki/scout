# Labelled retrieval cases for `example-ledger.md`

**Every candidate below is invented, and so is every entry it points at.** This file
is documentation and fixture in one. It shows what the story test is up against, and
it is the set the retrieval script is measured on: for each candidate it states the
one ledger entry that is truly the same story, or `none`.

The script under test is `briefing/ledger-retrieve.sh`. It is a recall stage, not a
decision. Returning entries that turn out not to match costs the judgement behind it
a few extra lines to read. Failing to return the true match costs a duplicate in the
briefing, which is the failure these cases exist to catch.

**The measurement.** Four candidates have a true match inside the window, namely
cases 1, 2, 3 and 6. Every one of those four entries must appear in the output of its
invocation. That is recall 1.0, and anything less is a defect to file rather than a
number to accept. Case 4 has a true match that lies outside the window, and its
expectation is the reverse: the entry must not appear. Case 5 has no true match at
all.

**Dates.** The fixture is written against a reference date of 2026-08-26 and a window
of 60 days, which reaches back to 2026-06-27. Run these checks with the machine clock
near that reference date. When you run them later, re-base the fixture first: add the
number of days between 2026-08-26 and today to every date in a copy of
`example-ledger.md`. The spacing between entries is what the cases depend on, so every
expected answer below survives that shift unchanged.

**How to run one case.** Each case gives the two candidate arguments verbatim. The
invocation is:

```
briefing/ledger-retrieve.sh --ledger briefing/example-ledger.md --window-days 60 --entities "<the entities line below>" --text "<the text line below>"
```

Read the output and check it against the expected answer. Each expected answer names
its entry by date and actor, which is enough to check by eye and enough for a script
to grep for.

## Case 1: verbatim

**Kind:** the candidate repeats the ledger sentence word for word.

- entities: `nvidia|rubin ultra`
- text: `Nvidia began sampling its Rubin Ultra accelerator to hyperscale customers ahead of a first-quarter shipping date.`
- **Expected match: the entry of 2026-08-21, actor Nvidia.**

The easy end of the range, and the case that fails only if something is broken
outright. It is here as the floor.

## Case 2: the same event in a second outlet's wording

**Kind:** same story, different headline, different URL, almost no shared phrasing.

- entities: `openai`
- text: `OpenAI has made a downloadable build of its lightweight reasoning system available to researchers, its first open-weight release in two years.`
- **Expected match: the entry of 2026-07-29, actor OpenAI.**

Retrieval reaches it through the shared entity `openai`, which is why the entity path
exists at all: the two sentences share almost no content words. The hard part of this
case belongs to the judgement stage, which has to see one event behind
"published the weights of its smallest reasoning model" and "made a downloadable
build of its lightweight reasoning system available".

## Case 3: the actor named differently

**Kind:** the candidate names a parent company where the ledger entry names its
subsidiary.

- entities: `softbank`
- text: `SoftBank's chip unit has licensed Neoverse server cores to a third Chinese cloud provider.`
- **Expected match: the entry of 2026-08-11, actor Arm Holdings.**

The candidate and the entry share no entity token: `softbank` is nowhere in the entry
and `arm` is nowhere in the candidate. Retrieval therefore rests entirely on the word
path, which finds `licensed`, `neoverse`, `server`, `chinese` and `cloud` shared
between the candidate text and the entry's sentence. Drop the word path and this case
fails, the judgement never sees the entry, and the story publishes a second time. It
is the case the retrieval decision record names as the known weakness of a lexical
prefilter, and it is here so that the weakness is measured rather than assumed.

## Case 4: the true match lies outside the window

**Kind:** the story was reported, but longer ago than `ledger-window-days` allows the
test to look.

- entities: `anthropic|claude`
- text: `Anthropic switched on EU data residency for Claude customers in three further member states.`
- **Expected match: none inside the window. The entry of 2026-06-19, actor Anthropic, is the true match and must NOT appear in the output**, because it is 68 days before the reference date.

No other entry shares two content words with this candidate either, so the output on
this fixture is expected to be empty. The consequence is the intended one: the item
publishes a second time, and the reader sees a duplicate they can skip rather than an
omission they cannot see. Widen `ledger-window-days` past 68 and this same case
returns the entry, which is the check that the window is what bound it.

## Case 5: no match at all

**Kind:** a genuinely new story, with a near neighbour in the ledger that is not it.

- entities: `cerebras`
- text: `Cerebras Systems opened a wafer-scale inference datacentre in Norway for European customers.`
- **Expected match: none. No entry in the ledger is this story.**

The retriever is expected to return the entry of 2026-08-05, the European Commission
consultation, because it shares the words `european` and `opened` with the candidate.
That is not a failure of retrieval. The stage returns candidates and the judgement
rejects them, and the exact set of near neighbours may shift with the stoplist. What
is load-bearing here is that no entry is labelled as a true match, so the item
publishes as new.

## Case 6: an entry whose `entities` line was deleted by hand

**Kind:** a hand-edited ledger, checking that the retrieval aid degrades rather than
breaks.

**Preparation.** Copy `example-ledger.md`, and in the copy delete the line
`  - entities: sk hynix, hbm4, icheon` from the entry of 2026-07-17. Run this case
against the copy.

- entities: `sk hynix|hbm4`
- text: `SK Hynix has begun volume production of HBM4 stacks at Icheon.`
- **Expected match: the entry of 2026-07-17, actor SK Hynix, still returned from the edited copy.**

The `entities` line is a retrieval aid, not the record. With it gone, the entry is
still reachable because its names and its words are in its sentence, which is where
the record actually lives. A user who tidies their ledger by hand loses some
retrieval quality and loses nothing else.
