# Briefing: AI models and AI hardware

name: ai-morning
language: en
yield-target: 8
max-pages: 40
max-hops: 2
max-minutes: 15
depth: off
ledger-window-days: 60

Copy this file, change the title, change `name`, then rewrite the section headings
and the question under each one. That is the whole edit. There is no schema, no
validation pass and no wizard: the file is written and edited by hand, and a
mistyped field name is found by the run rather than by a checker.

**The format.** Everything above the first `##` heading is profile-wide. Each `##`
heading below opens one section, whose prose is one research question and whose
optional `regions` and `seeds` lines follow it. One section becomes one research
run, and one research run becomes one heading in the briefing.

**Required and optional fields.** `name` and `language` are required. A run that
finds either one missing stops with a message naming the field and this file, and
writes no briefing. `name` is the short identifier that names the ledger and the
briefing file, so keep it to lowercase letters, digits and hyphens. `language` is
the language the briefing is written in, whatever language you wrote this file in.
The other six profile-wide fields are optional and carry the values shown above
when you leave them out: `yield-target` 8, `max-pages` 40, `max-hops` 2,
`max-minutes` 15, `depth` `off`, `ledger-window-days` 60. Those starting values are
proposals with no measurement behind them, and you are expected to tune them once
you have read a few mornings.

This prose is ignored. The run reads the `key: value` lines above and the sections
below, and nothing else, so you can write as much explanation into a profile as you
like. Two rules keep it ignorable: no explanatory line may begin with a word
followed by a colon, and no explanation may sit under a `##` heading, because a
`##` heading is a section and its prose is a research question.

**What makes a section sufficient.** A briefing run is unattended. The research
agent cannot ask you what you meant, so every term you leave open is a term it
resolves for itself, in a direction you find out about only when you read the
briefing.

A section is sufficient when its own text answers four questions. What counts as an
item, in concrete kinds rather than in a topic word. What is out of scope, stated as
exclusions, because a broad heading is otherwise read broadly. What each item has to
state, so that two items about different companies are comparable. And where the
boundary of a judgement call sits, as a number or a rule wherever one exists: "at or
below 15 billion parameters" is researchable, "small models" is not. The three
sections below are written to that standard, so read one before you write your own.

**What the caps bound.** The four caps bound one section, not one morning. A profile
with three sections and `max-pages` at 40 can fetch 120 pages in a run, and one with
`max-minutes` at 15 can take 45 minutes plus the merge. The worst case is the number
of sections times the cap, and the run prints that arithmetic before it starts, so
the number is in front of you rather than in your head.

`yield-target` is how many genuinely new items a section aims for, and reaching it
ends that section early. `max-hops` is how far the agent may follow links away from a
page it already holds: 0 means seeds and search results only, which is what scout did
before briefings existed. `depth` set to `on` allows the browser-driven layer on
pages plain fetching cannot read, and that layer needs a separate setup step, so
leave it `off` until you have run one.

**What regions do.** `regions` ranks, it does not exclude. An item from a region you
did not name still appears in the briefing, below the items from the regions you did.
A hard filter would drop a major development from a fourth region silently, and a
briefing whose gaps you cannot see is worse than one carrying a few items you skip.
The line is per section, so a hardware section may reasonably add Taiwan and South
Korea to the three regions below while a policy section does not.

**What seeds do.** `seeds` lists sources you already trust, one URL per line under
the line `seeds:`. They are visited before anything the agent searches for. A section
with no `seeds` line finds its own starting points, which is what the middle section
below demonstrates.

**What `ledger-window-days` does.** The briefing tells you what it has not told you
before. Every published item goes into a ledger, and each candidate in the next run
is tested against it. `ledger-window-days` decides how far back that test looks:
entries older than the window are not consulted, so a story first reported more than
60 days ago can be reported a second time.

That failure direction is the safe one. A window too short produces a duplicate you
can see and skip. A window too long produces no omission either, only a larger set
for the test to read, so widening it costs reading time and nothing else. Set it to
the cadence of your topic: model releases turn over in weeks, regulatory processes in
months.

## Generative models

Report new generative language, image, video and multimodal models at the frontier
and just below it. An item is one of: an announced or shipped model release, a weight
publication, a capability or benchmark claim made by the developer or by an
independent evaluator, a change to a model's licence or price, or a change to who may
access a model. A model is in scope from its first public announcement onwards,
including a preview, a waitlist or a staged rollout. Out of scope: product launches
that ship an existing model in a new application, funding rounds, personnel moves,
and partnership announcements that name no model. State for each item the developer,
the model name, the parameter count or the size class where the developer published
one, the modalities in and out, the licence, the announcement date, and whether the
capability claim comes from the developer or from an independent evaluation.

regions: USA, China, EU
seeds:
- https://openai.com/news/
- https://www.anthropic.com/news
- https://blog.google/technology/ai/
- https://huggingface.co/blog

## Small and on-device models

Report generative models small enough to run on a phone, a laptop, a single consumer
GPU or an embedded board. An item is one of: a release or weight publication at or
below 15 billion parameters, or one the developer itself calls small or on-device; a
quantised, distilled or pruned version of a larger model; an on-device inference
runtime together with the chips it targets; or a measured performance figure such as
tokens per second, memory footprint or energy per token on named hardware. A
manufacturer shipping a model inside an operating system, a handset or a car is in
scope. Out of scope: small models offered only as a hosted API with no downloadable
weights, and research papers with neither released weights nor a runnable artifact.
State for each item the developer, the model name, the parameter count, the
quantisation where there is one, the device or chip the figures were measured on, and
who measured them.

regions: USA, China, EU

## AI-specific hardware

Report hardware built for AI training and inference. An item is one of: an
accelerator announcement, tape-out, sampling or shipping milestone from a GPU, TPU,
NPU or custom-silicon vendor; a high-bandwidth memory, interconnect or networking
product aimed at these systems; a fabrication capacity or process-node milestone at a
plant that makes these parts; or an export control, procurement rule or licence
decision that changes who may buy them. A datacentre buildout is in scope when the
item names the accelerator or the power capacity. Out of scope: consumer device
launches whose AI content is a software feature, and stock-price, analyst-rating and
market-forecast stories. State for each item the vendor, the part or plant, the
process node or memory generation where published, the customer or region affected,
the shipping or production date, and whether the figures come from the vendor, from a
regulator or from an independent teardown.

regions: USA, China, EU
seeds:
- https://blogs.nvidia.com/
- https://www.eetimes.com/
