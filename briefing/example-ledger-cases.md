# Labelled retrieval cases for `example-ledger.md`

**Every candidate below is invented, and so is every entry it points at.** This file
is documentation and fixture in one. It shows what the story test is up against, and
it is the set the retrieval script is measured on: for each candidate it states the
one ledger entry that is truly the same story, or `none`.

The script under test is `briefing/ledger-retrieve.sh`. It is a recall stage, not a
decision. Returning entries that turn out not to match costs the judgement behind it
a few extra lines to read. Failing to return the true match costs a duplicate in the
briefing, which is the failure these cases exist to catch.

**The measurement.** Nine candidates have a true match inside the window, namely
cases 1, 2, 3, 6, 7, 8, 9, 10 and 11. Every one of those nine entries must appear in the
output of its invocation. That is recall 1.0, and anything less is a defect to file
rather than a number to accept. Case 4 has a true match that lies outside the window, and its
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

## Case 7: a Russian entry, reached with its `entities` line in place

**Kind:** a non-Latin entry and a candidate in the same language, worded differently.

- entities: `яндекс|yandexgpt`
- text: `Яндекс выложил YandexGPT 5 в открытый доступ для бизнеса.`
- **Expected match: the entry of 2026-08-14, actor Яндекс.**

The baseline for the next case: the candidate's entity names are on the entry's
`entities` line, so this case passes as long as Cyrillic bytes survive tokenising at
all.

## Case 8: the Russian entry with its `entities` line deleted

**Kind:** a hand-edited ledger in a cased non-Latin script. This is the case that holds
the in-script case folding in place.

**Preparation.** Copy `example-ledger.md`, and in the copy delete the line
`  - entities: яндекс, yandexgpt 5` from the entry of 2026-08-14. Run this case against
the copy.

- entities: `яндекс`
- text: `Нейросеть Яндекса теперь можно скачать и запускать в продуктах компаний.`
- **Expected match: the entry of 2026-08-14, actor Яндекс, still returned from the edited copy.**

The candidate shares no content word with the entry's sentence (`Яндекса` is an
inflected form, not the same token). The only route left is the entity `яндекс`
against the capitalised `Яндекс` that opens the sentence, and that route exists only
because the retriever folds Cyrillic case itself rather than borrowing it from a
locale. Simplify `foldcase()` back to plain `tolower()` under the pinned C locale and
this case fails.

## Case 9: a Chinese entry, reached with its `entities` line in place

**Kind:** a non-Latin entry written without spaces between words, and a candidate in
the same language.

- entities: `腾讯|混元`
- text: `腾讯公开了混元模型的权重，企业可以免费用于商业产品。`
- **Expected match: the entry of 2026-08-20, actor 腾讯 (Tencent).**

The baseline for the next two cases: the names are on the `entities` line, which is
written with ASCII commas, so each name is a token of its own.

## Case 10: the Chinese entry with its `entities` line deleted

**Kind:** a hand-edited ledger in a script without spaces between words. This is the
case that holds the character-bigram fallback in place.

**Preparation.** Copy `example-ledger.md`, and in the copy delete the line
`  - entities: 腾讯, 混元, tencent, hunyuan` from the entry of 2026-08-20. Run this case
against the copy.

- entities: `腾讯|混元`
- text: `企业现在可以免费商用腾讯的混元大模型。`
- **Expected match: the entry of 2026-08-20, actor 腾讯 (Tencent), still returned from the edited copy.**

A whitespace tokeniser reads each run of Chinese between punctuation marks as a single
token, so the sentence opens with the one token `腾讯发布了混元`, and neither `腾讯` nor
`混元` exists as a token of its own — not even once the punctuation is split. The
retriever therefore also indexes every pair of adjacent Chinese or Japanese characters,
and `腾讯` is such a pair. Remove that fallback and this case fails.

## Case 11: an English candidate for the Chinese entry, `entities` line deleted

**Kind:** a Latin name embedded in Chinese text between full-width punctuation. This is
the case that holds the CJK punctuation split in place.

**Preparation.** The same edited copy as case 10.

- entities: `tencent|hunyuan`
- text: `Tencent has released open weights for its Hunyuan large model, free for commercial use.`
- **Expected match: the entry of 2026-08-20, actor 腾讯 (Tencent), still returned from the edited copy.**

The entry's sentence never spells `Tencent`; it carries the model's Latin name,
`Hunyuan`, between the full-width parentheses `（` and `）`, which are not ASCII
punctuation. Unless the normaliser splits on the CJK and full-width punctuation
blocks, `hunyuan` is glued to the Chinese around it and never becomes a token of its
own. The bigram fallback does not help here, because `hunyuan` is not Chinese.
