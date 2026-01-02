# Opinionated Claude Skills

A collection of opinionated, experimental skills and agents for [Claude Code](https://claude.ai/code).

"Opinionated" means these skills reflect specific design philosophies and expert judgment rather than neutral, general-purpose guidance. The core influences include:

- *Structure and Interpretation of Computer Programs* (SICP) by Abelson and Sussman
- Functional and logic programming paradigms
- Test-driven development as contract-based design
- The ACM Code of Ethics and Professional Conduct

If these perspectives don't align with yours, these skills may not be for you.

These skills are also an experiment in getting Claude to write effective instructions for itself.

## How These Skills Were Created

These skills were compiled from a collection of hand-written prompts Pyroxin had previously maintained for personal use. Some skills were also augmented with bits of public documentation and research guides generated with Claude Desktop. Sources for the third-party material are available in the text of each skill, with an emphasis on things Claude can potentially look up itself.

Very few manual changes were made to the skills. The content is written by Claude after preparing a context window and ensuring that Claude is able to have a sensible discussion about the topic. Then, Claude is asked to write instructions for itself to create the skill file. Similarly, improvements to the skills are made by calling out behavioral issues while using the skills with Claude Code. Claude is told what was actually expected of it and then asked to reflect on why it did what it did and whether any of the skill instructions need to be updated. Claude is then asked to propose an update to the skill. The `expert-skill-creator` skill was made by tracking the kinds of improvements that were made while tuning the other skills and then extracting those patterns into a skill, using the above process.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on the creation process and how to contribute improvements.

## Installation

### Claude Code

Add this marketplace to Claude Code:

```
/plugin marketplace add Pyroxin/opinionated-claude-skills
```

Then install plugins:

```
/plugin add opinionated-software-engineering@opinionated-claude-skills
```

**NOTE:** You need to restart Claude Code after making changes to plugins. If you don't see the skills after restarting, you may need to disable some plugins because you're running into the system's token limit for skill information.

### Claude Desktop / Claude Web

Individual skills can be downloaded as ZIP files from the [Releases](https://github.com/Pyroxin/opinionated-claude-skills/releases) page and uploaded to Claude Desktop or Claude Web via **Settings > Capabilities**.

ZIP files are named `plugin.skill.TIMESTAMP.SHA.zip` (e.g., `opinionated-software-engineering.software-engineer.20251130-014305.c7223ee.zip`). The timestamp and commit SHA identify the exact build.

## Plugins

### opinionated-software-engineering

Core skills that form the foundation. Recommended for all users. Skills in other plugins may assume this plugin was installed!

| Component | Description |
|-----------|-------------|
| `software-engineer` | Core philosophy and design principles based on SICP |
| `functional-programmer` | Functional programming principles and patterns |
| `object-oriented-programmer` | Object-oriented design principles and patterns |
| `logic-programmer` | Logic programming and relational design |
| `test-driven-development` | TDD philosophy: tests as contracts |
| `git-version-control` | Commit standards and LLM-assisted workflows |
| `research-specialist` | Agent for multi-source research and synthesis |

### opinionated-apple-development

Apple platform development.

| Skill | Description |
|-------|-------------|
| `swift-programmer` | Swift 6+ concurrency, protocol-oriented design |
| `macos-programmer` | macOS platform patterns, SwiftUI/AppKit |

### opinionated-lisp-development

Lisp family languages.

| Skill | Description |
|-------|-------------|
| `clojure-programmer` | Data-oriented design, REPL-driven development |
| `racket-programmer` | Language-oriented programming, contracts, macros |

### opinionated-java-ecosystem

Java ecosystem development.

| Skill | Description |
|-------|-------------|
| `java-programmer` | Modern Java idioms and tooling |

### opinionated-logic-development

Logic programming.

| Skill | Description |
|-------|-------------|
| `swi-prolog-programmer` | SWI-Prolog: DCGs, constraints, PlUnit |

### opinionated-python-development

Python development.

| Skill | Description |
|-------|-------------|
| `python-programmer` | Pythonic idioms, testing, type hints |

### opinionated-fish-shell

Shell scripting.

| Skill | Description |
|-------|-------------|
| `fish-shell-scripting` | Fish shell idioms, cross-platform patterns |

### opinionated-skill-creation

Meta-skill for creating skills.

| Skill | Description |
|-------|-------------|
| `expert-skill-creator` | Expert guidance for high-quality skill creation |

## License

Copyright (c) 2025 Pyroxin and contributors. Third-party content remains the property of its respective copyright holders.

[Eclipse Public License 2.0](LICENSE)

This license allows use, modification, and distribution, even for commercial purposes. Be aware that if you distribute as part of a commercial offering, you must defend and indemnify other contributors against third-party claims arising from your distribution.

## Content Notice

Good faith steps were taken to ensure no material was plagiarized by the LLM when compiling these skills but complete accuracy cannot be guaranteed. If you identify content in these skills that you own and wish to have removed or cited, open an issue including clear evidence of ownership.