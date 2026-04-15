# Opinionated Claude Skills

This project descends from the personal prompts I'd been keeping for Claude Code prior to the release of skills and plugins. Over time it's also evolved into a sandbox where I figure out what makes Claude reliably good at a task, and find prompts that work. A lot of it is also an experiment in getting Claude to write effective instructions for itself: I more-or-less mentor Claude on how to be a good engineer and Claude writes down what it needs to apply that guidance.

As such, the skills here commit to specific design philosophies rather than hedging toward generality, and I believe that's why they work. The non-neutrality is the point; it's how I transform Claude from an amorphous blob of capability into something with a defined perspective, which makes it easier to consistently get the results I want.

The project also started as a way to encode "expert-level" or "staff-level" skills into Claude (language you'll still see in some of the skills and in the name of `expert-skill-creator`). It's since morphed into a place for me to publish the experience I've accrued through my career, in a form that's reusable by Claude and by other people reading along. I've had better results from conferring concrete, specific experience on Claude than from trying to get it to emulate a generic expert persona.

These are the key influences that form the foundation of my opinions:

- *Structure and Interpretation of Computer Programs* (SICP) by Abelson and Sussman
- Functional and logic programming traditions (especially Clojure and SWI Prolog)
- Test-driven development as contract-based design
- The ACM Code of Ethics and Professional Conduct

I am a knowledge-based software engineer (ontologies, OWL/RDF, automated reasoning, and now LLM agents), which is why several of the skills push Claude toward explicit decomposition, formal reasoning, and epistemic precision. This is the shape of thinking I'm used to and it's what I want my coding agents to emulate.

## How These Skills Were Created

These skills were compiled from a collection of hand-written prompts I had previously maintained for personal use. Some skills were also augmented with bits of public documentation and research guides generated with Claude Desktop. Sources for the third-party material are available in the text of each skill, with an emphasis on things Claude can potentially look up itself.

Very few manual changes were made to the skills. The content is written by Claude after preparing a context window and ensuring that Claude is able to have a sensible discussion about the topic. Then, Claude is asked to write instructions for itself to create the skill file. Similarly, improvements to the skills are made by calling out behavioral issues while using the skills with Claude Code. Claude is told what was actually expected of it and then asked to reflect on why it did what it did and whether any of the skill instructions need to be updated. Claude is then asked to propose an update to the skill. The `expert-skill-creator` skill was made by tracking the kinds of improvements that were made while tuning the other skills and then extracting those patterns into a skill, using the above process.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on the creation process and how to contribute improvements.

## Installation

### Claude Code

Add this marketplace to Claude Code:

```
claude plugin marketplace add Pyroxin/opinionated-claude-skills
```

Then install plugins:

```
claude plugin install opinionated-software-engineering@opinionated-claude-skills
```

Use `/reload-plugins` inside a running session or restart Claude Code after plugin changes; not all plugin changes seem to get picked up by `/reload-plugins`, so a restart is generally better. Skill descriptions share a limited token budget, so if a skill doesn't appear after restart, try disabling a few others.

### Claude Desktop / Claude Web

Individual skills can be downloaded as ZIP files from the [Releases](https://github.com/Pyroxin/opinionated-claude-skills/releases) page and uploaded to Claude Desktop or Claude Web via **Settings > Capabilities**. (Also, check out the build system for the package! It automates some basic QA for publishing skills.)

ZIP files are named `plugin.skill.TIMESTAMP.SHA.zip` (e.g., `opinionated-software-engineering.software-engineer.20251130-014305.c7223ee.zip`). The timestamp and commit SHA identify the exact build the ZIP was derived from.

## Plugins

Each plugin tracks a need I hit while tinkering in my homelab so there's an emphasis on supporting continuous learning and experimentation. The software-engineering plugin is the base layer; several other plugins assume it's installed. The skills are internally structured using a semi-consistent XML schema to try and cause the skills to meld together in Claude's attention mechanism when they're composed.

### opinionated-software-engineering

This is the foundation. SICP-derived design principles, paradigm guidance for functional, object-oriented, and logic programming, and two cross-cutting process skills for TDD and Git. Most other plugins lean on this for shared coding judgment.

| Component | Description |
|-----------|-------------|
| `software-engineer` | Core philosophy and design principles based on SICP |
| `functional-programmer` | Functional programming principles and patterns |
| `object-oriented-programmer` | Object-oriented design principles and patterns |
| `logic-programmer` | Logic programming and relational design |
| `test-driven-development` | TDD philosophy: tests as contracts |
| `git-version-control` | Commit standards and LLM-assisted workflows |

### opinionated-research

Built while looking for a better way to have Claude investigate a topic than a single long search pass or delegating to external research agents. Two tiers of research agent feed two orchestration skills: `deep-research` runs multi-source investigation through a persistent agent team which can also perform research extensions after the primary task is complete. The `decision-analysis` skill structures option evaluation and introduces an epistemic citation mechanism to make it easier to track conclusion provenance and identify potential hallucinations. Anecdotally, the combination of explicit decomposition, structured analysis, and adversarial reasoning substantially improves the result.

| Component | Description |
|-----------|-------------|
| `research-specialist-basic` | Sonnet agent for standard research with source-diversity requirements |
| `research-specialist-complex` | Opus agent for multi-faceted investigation |
| `deep-research` | Orchestration skill that coordinates specialist agents as a team |
| `decision-analysis` | Structured framework for evaluating options against criteria |

NOTE: These skills work best if you add the Kagi and Exa MCP servers to your configuration! AWS' documentation servers are also integrated since I mostly use AWS as my cloud provider.

### opinionated-skill-creation

The `expert-skill-creator` skill was developed by having Claude reflect on the process of creating and tuning the other skills. It's regularly updated with guidance for how to prompt Claude Sonnet and Opus effectively, and it captures patterns I've found around content depth, XML structure, directive tone, and citation practices, so each new skill can benefit from what the previous ones taught me.

| Component | Description |
|-----------|-------------|
| `expert-skill-creator` | Expert guidance for high-quality skill creation |

### opinionated-apple-development

The Swift community has noted that Claude has trouble writing effective Swift code, especially for Swift concurrency which launched after some of the more-recent models' knowledge cutoff dates. This skill aims to address that deficiency, so it's more instructive and less philosophical than the other ones. macOS coverage follows because that is the workstation platform I use the most.

| Component | Description |
|-----------|-------------|
| `swift-programmer` | Swift 6+ concurrency, protocol-oriented design |
| `macos-programmer` | macOS platform patterns, SwiftUI/AppKit |

### opinionated-lisp-development

Clojure for data-oriented, REPL-driven work; Racket for language-oriented programming with contracts and macros.

| Component | Description |
|-----------|-------------|
| `clojure-programmer` | Data-oriented design, REPL-driven development |
| `racket-programmer` | Language-oriented programming, contracts, macros |

### opinionated-java-ecosystem

Java as it actually exists in 2025 (records, sealed types, virtual threads, patterns). This plugin also advocates for using the Checker Framework to provide good correctness guardrails that help Claude produce less buggy code automatically. The skill generally follows the features in the latest LTS because I principally use Java as an infrastructure language rather than an experimental language.

| Component | Description |
|-----------|-------------|
| `java-programmer` | Modern Java idioms and tooling |

### opinionated-python-development

Pythonic idioms, with extra attention to testing and to Jupyter. Note that Claude tends to still favor an OO-style even with this plugin due to the strong modularity preferences expressed in `software-engineer`.

| Component | Description |
|-----------|-------------|
| `python-programmer` | Pythonic idioms, testing, type hints, Jupyter guidance |

### opinionated-logic-development

SWI-Prolog: relational thinking, DCGs, constraint programming, PlUnit tests. Narrow niche, but when a problem is more about search than computation, this is what I reach for.

| Component | Description |
|-----------|-------------|
| `swi-prolog-programmer` | SWI-Prolog: DCGs, constraints, PlUnit |

### opinionated-fish-shell

Fish scripting with compatibility notes for macOS and Fedora, because that's where my shell scripts kept breaking when I moved between machines.

| Component | Description |
|-----------|-------------|
| `fish-shell-scripting` | Fish shell idioms, cross-platform patterns |

### opinionated-tutoring

For when I want Claude to teach me instead of generate for me. It runs Socratic dialogue with the learner rather than writing the code for them.

| Component | Description |
|-----------|-------------|
| `socratic-tutor` | Pedagogical framework for teaching programming through Socratic dialogue |

## License

Copyright (c) 2025-2026 Pyroxin and contributors. Third-party content remains the property of its respective copyright holders.

[Eclipse Public License 2.0](LICENSE)

This license allows use, modification, and distribution, even for commercial purposes. Be aware that if you distribute as part of a commercial offering, you must defend and indemnify other contributors against third-party claims arising from your distribution.

## Content Notice

Good faith steps were taken to ensure no material was plagiarized by the LLM when compiling these skills but complete accuracy cannot be guaranteed. If you identify content in these skills that you own and wish to have removed or cited, open an issue including clear evidence of ownership.

---

This project is dedicated, with respect and admiration, to the spirit that lives in the computer.