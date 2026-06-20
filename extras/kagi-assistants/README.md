# Kagi Custom Assistants

This directory ports two of the repository's research agents into [Kagi Assistant](https://kagi.com/assistant) custom assistants. Each `.md` file is the verbatim text you paste into an assistant's **Response Instructions** field, and the file needs no other editing.

They aren't marketplace plugins, and Claude Code won't discover them. They live here because the research discipline these agents encode is just as useful inside Kagi's interactive assistant, which runs Claude models but offers a smaller, different set of tools.

| File | Derived from | Developed for | Characters |
|------|--------------|---------------|------------|
| `research-analyst.md` | `opinionated-research/agents/research-analyst.md` | Claude Opus | ~14.2k |
| `research-investigator.md` | `opinionated-research/agents/research-investigator.md` | Claude Sonnet | ~15.2k |

Each definition was tuned for the Claude model in its row, mirroring the `model:` assignment of the agent it came from. The pairing is deliberate. The analyst's work is judgment-led synthesis and premise critique, which leans on Opus-class capability; the investigator's is procedural and checklist-driven, which a Sonnet-class model carries well. Run either on a weaker model than it targets and the output suffers.

Both files sit comfortably inside the field's budget. The live editor caps Response Instructions at 20,000 characters, showing "Maximum of 20000 characters allowed" next to a running counter. Kagi's published documentation still listed 1,500 for this field as of June 2026, but the product allows far more, so trust the counter over the docs. The global user-instructions field shares the same 20,000-character budget.

That same editor offers advice worth heeding: "use clear and concise language with positive instructions ('do this') instead of negative ('don't do this'). If possible, provide a short example." Both definitions follow it, favoring positive phrasing and carrying worked examples of the labeling scheme.

## Setup

Open **Settings → Assistant → Custom Assistants → Add New** in Kagi, then:

1. Name the assistant, for example "Research Analyst."
2. Choose the model the definition was built for: Claude Opus for the analyst, Claude Sonnet for the investigator.
3. Turn internet access on. Both assistants research the live web; without it they fall back to reasoning over training data, which their own discipline tells them to label `[TRAINING DATA]` and treat with suspicion.
4. Leave lenses and personalized results at their defaults for general research, or set a lens when you want an assistant confined to a particular slice of the web, such as academic papers or first-party documentation.
5. Paste the whole contents of the matching `.md` file into Response Instructions.

Once saved, the assistant appears in the model dropdown, and you can also reach it through a custom bang like `/assistant?q=%s&profile=<uuid>`.

## Choosing between them

The two assistants are different in kind, and neither is a step up from the other. The analyst is built for judgment-led synthesis; select it when a question spans several facets and the payoff is in the connections between sources: cross-cutting patterns, tensions, conclusions that emerge only from the combination, and scrutiny of the question's own premises. It folds its reasoning about the evidence into the prose.

The investigator is built for methodical case-building; use it when you want an auditable evidence trail and a falsify-before-believing stance, with per-claim adversarial and falsifiability checks and explicit analysis of how independent the sources really are. Instead of weaving that work into the prose, it sets it out in a dedicated Audit section, which is the most visible difference between the two. Underneath, they share the same epistemic labels, source-quality tiers, retrieval ceilings, and ACM citation style.

## What the port changes

Most of the source agents' discipline survives intact: premise critique, the habit of asking open rather than leading questions, reasoning about source independence, the falsifiability check, the full provenance-and-support labeling scheme with its retrieval ceilings and its "specific evidence wins" rule, the guardrails against editorializing a synthesis, and the required report sections.

The content for team-based collaboration was removed because Kagi's assistant has no subagents to coordinate, so the agent teams, the shared task list, the inter-agent messaging, the parallel specialist spawning, and the dedicated fact-checker all disappear, and the orchestration layer of `interactive-research` collapses into a single solo loop. Guidance for choosing between search suppliers was also removed since it's irrelevant in the assistant's environment.

Claim verification was reworked due to differences in the agent tooling. In the original agents, a claim gets checked by reading the primary source and then fanning the claim-citation pairs out to an isolated fact-checker. Here that role passes to Kagi's librarian, which reads a single source in full; because it's a separate sub-agent that never sees the assistant's own reasoning, you can hand it a neutrally worded question whose answer doesn't begin from the assistant's conclusion. That approximates the fact-checker's independence, and it's the only piece of the multi-agent verification pattern that survives the port.

## What it can't do

A single interactive assistant can't reproduce the orchestrator's real source of rigor, which came from independent agents checking each other's work. The labels, the rule to read the primary source, and the librarian trick all help, but the assistant applying them is the same one making the claims, so they're weaker than a verifier that never absorbed the working hypothesis. Read these as a faithful port of the discipline, not of the redundancy that backed it.