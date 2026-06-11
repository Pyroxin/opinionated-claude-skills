# Prompting Sonnet-Tier Models: Notes for Skill Authors

<sonnet_reference_scope>
This document is for skill authors targeting Sonnet-tier models, typically as subagent workers orchestrated by Opus or Fable. It consolidates official guidance that is scattered across the cited sources (which describe Sonnet 4.6; see `<sources>`) and adds what those sources don't say: which claims hold for Sonnet by name versus by inference, and which prior claims were retired for lack of sources. Where a paraphrase here disagrees with current documentation, the documentation wins — no Sonnet-specific prompting page existed when this was written; if one exists now, prefer it and flag this file for revision. Parametric recall of newer Sonnet versions wins nothing; verify before deviating. The sources:

- Prompting best practices: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Migration guide (Sonnet section): https://platform.claude.com/docs/en/about-claude/models/migration-guide
- Adaptive thinking: https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking
</sonnet_reference_scope>

## What the documentation says, by provenance

<sonnet_documented_behavior>
**Documented for the current model family, Sonnet included by the page's scope statement:**[^1]

- Models are "trained for precise instruction following" and "benefit from explicit direction to use specific tools" ("Change this function..." rather than "Can you suggest some changes...").
- Concise, natural communication style: "more direct and grounded", less verbose than previous generations.
- Few-shot examples: 3-5 diverse examples for best results, wrapped in `<example>` tags — the same recommendation as larger tiers.
- Directive intensity: "Claude 4.6 models are significantly more proactive and may overtrigger on instructions that were needed for previous models."[^1] Dial back aggressive and anti-laziness language in skill prose, the same as for Opus targets.

**Documented for Sonnet by name (migration guide; version-bound):**[^2]

- `effort` defaults to `high`. Set it explicitly; callers migrating from earlier Sonnet versions may otherwise see unexpected latency.
- Prefilled assistant messages on the last turn return a 400 error. Skills relying on prefill-style output forcing must migrate to structured outputs, system-prompt instruction, or `output_config.format`.
- Extended thinking with `budget_tokens` is deprecated; use adaptive thinking (`thinking: {type: "adaptive"}`). Thinking triggering is steerable by prompt.[^3]
- Context awareness: current-generation models, Sonnet included, track their remaining context window — relevant when prompting long-running workers about compaction and wrap-up behavior.[^1]

**Inferred, not documented — verify empirically before relying on it:**

- Strict literalism ("interprets prompts more literally and explicitly [than its predecessor]... will not silently generalize an instruction from one item to another") is documented by name for Opus, not for Sonnet.[^2] Treat it as a plausible proxy for Sonnet behavior, not an established property.
- `xhigh` effort appears unavailable on Sonnet: the effort availability table lists it only for Fable-, Mythos-, and Opus-tier models.[^3] This is an absence-based inference from a table, not a stated limitation.
</sonnet_documented_behavior>

## Retired claim — do not reintroduce

<sonnet_retired_claims>
A prior version of the parent skill stated: "Sonnet models tend to follow instructions literally and precisely — aggressive language won't cause overtriggering, but it adds no value over calm, direct statements." Verification against the documentation found the overtriggering half of this claim *inverted*: Anthropic states that current models, Sonnet included, may overtrigger on aggressive prompting, and the fix is to remove it.[^1] The literalism half is documented only for Opus. If this claim resurfaces in a draft, it is training-data residue, not a sourced fact.
</sonnet_retired_claims>

## Sources

<sources>
[^1]: Anthropic. 2026. Prompting best practices. Claude API Documentation. Retrieved June 10, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

[^2]: Anthropic. 2026. Migration guide. Claude API Documentation. Retrieved June 10, 2026 from https://platform.claude.com/docs/en/about-claude/models/migration-guide

[^3]: Anthropic. 2026. Adaptive thinking. Claude API Documentation. Retrieved June 10, 2026 from https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking
</sources>
