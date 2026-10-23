# Ledger: ai-morning (worked example)

**Every entry below is invented.** The companies are real, the events are not. This
file exists to show the entry format and to serve as the fixture the retrieval
script is measured against. Do not read it as news, and do not cite it. The `sources`
links point at `example.com` for exactly that reason.

**Reference date: 2026-08-26.** With the profile default of `ledger-window-days` 60,
the window reaches back to 2026-06-27. The eleven entries from that date onwards are
inside the window and the four before it are outside, which is what makes this file
usable for checking that the window binds.

**Two entries are not in English**, on purpose: one in Russian (2026-08-14) and one in
Chinese (2026-08-20). They keep the retriever's non-Latin handling under the same
regression check as the rest — the in-script case folding a Cyrillic capital needs, the
CJK punctuation that separates names, and the character-bigram fallback for Chinese and
Japanese text written without spaces between words.

A real ledger is written by the briefing agent, one entry appended per published
item, oldest at the top. You are meant to be able to open it, read it and correct
it. Correcting it is the only remedy when a story was wrongly suppressed, because a
suppressed story leaves no trace in the briefing itself.

**The sentence is the record.** The first line of an entry says who did what to
what, in one sentence, and that sentence is what the story test compares a new
candidate against. Everything under it is supporting detail.

**What each field carries.** `entities` is the retrieval aid: the normalised names
the entry is about, lowercased and stripped of corporate suffixes, so the prefilter
does not have to pull names out of prose at run time. It is a convenience and not the
record. Delete it by hand and the entry is still found through the words of its
sentence; the retrieval gets weaker, it does not break. `sources` is where the story
was read, one or more links. `section` is the profile section heading the item was
published under, spelled exactly as the profile spells it. `marker` is what the story
test decided when the item was published: `new` for an item with no match, or
`possibly covered on <date>` for one published with an uncertain match, naming the
date it may have been reported before.

**Deleting an entry makes its story eligible again.** Nothing else indexes this file,
nothing is derived from it and nothing is rebuilt elsewhere, so removing an entry is
the whole of the operation. The next run will treat that story as new.

## Entries

- **2026-04-30** — Baidu open-sourced a 7-billion-parameter Ernie variant tuned for Chinese-language edge devices.
  - entities: baidu, ernie
  - sources: https://newsroom.example.com/2026/04/baidu-ernie-edge
  - section: Small and on-device models
  - marker: new

- **2026-05-22** — Microsoft deployed its Maia 3 accelerator across two Azure regions in the United States.
  - entities: microsoft, maia 3, azure
  - sources: https://newsroom.example.com/2026/05/microsoft-maia-3-azure, https://wire.example.com/maia-3-rollout
  - section: AI-specific hardware
  - marker: new

- **2026-06-04** — TSMC brought its second Arizona fab to volume production on a 2 nm process.
  - entities: tsmc, arizona
  - sources: https://wire.example.com/tsmc-arizona-2nm
  - section: AI-specific hardware
  - marker: new

- **2026-06-19** — Anthropic extended EU data residency for Claude to three additional member states.
  - entities: anthropic, claude
  - sources: https://newsroom.example.com/2026/06/anthropic-eu-residency
  - section: Generative models
  - marker: new

- **2026-06-30** — Google DeepMind released Gemini 3.5 Flash and cut the published price of cached input by half.
  - entities: google deepmind, gemini 3.5 flash
  - sources: https://newsroom.example.com/2026/06/gemini-3-5-flash, https://wire.example.com/gemini-flash-pricing
  - section: Generative models
  - marker: new

- **2026-07-02** — Meta released a 1-billion-parameter multilingual model licensed for on-device use on Android handsets.
  - entities: meta, android
  - sources: https://newsroom.example.com/2026/07/meta-1b-android
  - section: Small and on-device models
  - marker: new

- **2026-07-17** — SK Hynix started volume production of HBM4 memory stacks for AI accelerators at its Icheon plant.
  - entities: sk hynix, hbm4, icheon
  - sources: https://wire.example.com/sk-hynix-hbm4-volume, https://teardown.example.com/hbm4-first-look
  - section: AI-specific hardware
  - marker: new

- **2026-07-29** — OpenAI published the weights of its smallest reasoning model for local deployment under a research licence.
  - entities: openai
  - sources: https://newsroom.example.com/2026/07/openai-small-reasoning-weights
  - section: Small and on-device models
  - marker: new

- **2026-08-05** — The European Commission opened a consultation on compute-reporting thresholds for general-purpose AI models.
  - entities: european commission
  - sources: https://register.example.com/2026/consultation-compute-thresholds, https://wire.example.com/eu-compute-threshold-consultation
  - section: Generative models
  - marker: possibly covered on 2026-07-30

- **2026-08-11** — Arm Holdings licensed its Neoverse server core design to three Chinese cloud providers.
  - entities: arm, neoverse
  - sources: https://wire.example.com/arm-neoverse-china-licences
  - section: AI-specific hardware
  - marker: new

- **2026-08-14** — Яндекс открыл веса модели YandexGPT 5 для коммерческого использования.
  - entities: яндекс, yandexgpt 5
  - sources: https://newsroom.example.com/2026/08/yandexgpt-5-open-weights
  - section: Generative models
  - marker: new

- **2026-08-18** — Mistral released a 3-billion-parameter on-device model under Apache 2.0 with published phone benchmarks.
  - entities: mistral
  - sources: https://newsroom.example.com/2026/08/mistral-3b-on-device
  - section: Small and on-device models
  - marker: new

- **2026-08-20** — 腾讯发布了混元（Hunyuan）大模型的开源权重，允许企业免费商用。
  - entities: 腾讯, 混元, tencent, hunyuan
  - sources: https://newsroom.example.com/2026/08/tencent-hunyuan-open-weights
  - section: Generative models
  - marker: new

- **2026-08-21** — Nvidia began sampling its Rubin Ultra accelerator to hyperscale customers ahead of a first-quarter shipping date.
  - entities: nvidia, rubin ultra
  - sources: https://wire.example.com/nvidia-rubin-ultra-sampling, https://teardown.example.com/rubin-ultra-package
  - section: AI-specific hardware
  - marker: new

- **2026-08-24** — Alibaba published the weights of Qwen4-Max under a permissive licence for commercial use.
  - entities: alibaba, qwen4-max
  - sources: https://newsroom.example.com/2026/08/alibaba-qwen4-max-weights
  - section: Generative models
  - marker: new
