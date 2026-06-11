# Prompting Haiku-Tier Models: Notes for Skill Authors

<haiku_reference_scope>
This document is for skill authors targeting Haiku-tier models, typically as fast, inexpensive subagent workers orchestrated by Opus or Fable. It consolidates official guidance that is scattered across the cited sources (which describe Haiku 4.5; see `<sources>`) and adds what those sources don't say: where the documentation is silent on Haiku specifics, and which prior claims were retired for lack of sources. Where a paraphrase here disagrees with current documentation, the documentation wins — no Haiku-specific prompting page existed when this was written; if one exists now, prefer it and flag this file for revision. Parametric recall of newer Haiku versions wins nothing; verify before deviating. The sources:

- Prompting best practices: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Choosing a model: https://platform.claude.com/docs/en/about-claude/models/choosing-a-model
- Haiku 4.5 announcement: https://www.anthropic.com/news/claude-haiku-4-5
</haiku_reference_scope>

## No separate prompting dialect is documented

<haiku_documented_behavior>
The central finding: Anthropic documents Haiku as a fully capable member of the current model family, not a constrained tier requiring compensatory prompting. The best-practices page scopes its general sections — clarity, examples, XML structure, tool use — to all current models, Haiku included, with no Haiku-specific carve-outs for instruction following, verbosity, or tool triggering.[^1] Write skills for Haiku in the same calm, explicit register as for larger tiers.

What is documented:

- **Few-shot examples: 3-5 diverse examples**, the same recommendation as every other current tier.[^1]
- **Intended role:** the model-selection guidance lists sub-agent tasks among Haiku's primary use cases;[^2] the launch announcement calls it "a leap forward for agentic coding, particularly for sub-agent orchestration and computer use tasks".[^3] Tool use is a documented strength, not a weakness to prompt around.
- **Context awareness:** current-generation models, Haiku included, track their remaining context window — relevant when prompting long-running Haiku workers about compaction behavior.[^1]
</haiku_documented_behavior>

## Documented gaps — absence is not license

<haiku_documentation_gaps>
The documentation is silent on whether Haiku differs from Sonnet or Opus in instruction-following precision, sensitivity to prompt phrasing, or tool-triggering thresholds. That silence is a gap, not evidence of equivalence: test Haiku-targeted skills empirically (see `<empirical_validation>` in the parent skill) rather than assuming either parity or deficiency.
</haiku_documentation_gaps>

## Retired claim — do not reintroduce

<haiku_retired_claims>
A prior version of the parent skill stated: "For skills targeting Haiku in multi-tier systems, scaling to 10 examples can close the performance gap with higher tiers." A search across Anthropic's documentation, the Anthropic Cookbook, and the Anthropic engineering blog found no source for this claim; the official recommendation is 3-5 examples with no tier-based scaling.[^1] If this claim resurfaces in a draft, it is training-data residue, not a sourced fact.
</haiku_retired_claims>

## Sources

<sources>
[^1]: Anthropic. 2026. Prompting best practices. Claude API Documentation. Retrieved June 10, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

[^2]: Anthropic. 2026. Choosing a model. Claude API Documentation. Retrieved June 11, 2026 from https://platform.claude.com/docs/en/about-claude/models/choosing-a-model

[^3]: Anthropic. 2025. Introducing Claude Haiku 4.5. Retrieved June 10, 2026 from https://www.anthropic.com/news/claude-haiku-4-5
</sources>
