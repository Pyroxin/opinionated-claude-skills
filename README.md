# Opinionated Claude Skills

A collection of opinionated, experimental skills and agents for [Claude Code](https://claude.ai/code).

"Opinionated" means these skills reflect specific design philosophies and expert judgment rather than neutral, general-purpose guidance. The core influences include:

- *Structure and Interpretation of Computer Programs* (SICP) by Abelson and Sussman
- Functional and logic programming paradigms
- Test-driven development as contract-based design
- The ACM Code of Ethics and Professional Conduct

If these perspectives don't align with yours, these skills may not be for you.

These skills are also an experiment in getting Claude to write effective instructions for itself. Very few direct manual edits were made.

## Installation

Add this marketplace to Claude Code:

```
/plugin marketplace add https://github.com/Pyroxin/opinionated-claude-skills
```

Then install plugins:

```
/plugin add opinionated-software-engineering@opinionated-claude-skills
```

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

[Eclipse Public License 2.0](LICENSE)

This license allows use, modification, and distribution. If you distribute as part of a commercial product, you must defend and indemnify other contributors against third-party claims arising from your distribution.

-----

Good faith steps were taken to ensure no material was plagiarized by the LLM when compiling these skills but complete accuracy cannot be guaranteed. If you identify content in these skills that you own and wish to have removed or cited, open an issue including clear evidence of ownership.