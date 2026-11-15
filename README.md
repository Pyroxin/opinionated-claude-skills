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

## Leak-Scanning Experiments

The repository also serves as a testbed for automating thorough checks against accidental leaks of personal data and secrets in published content. Git hooks scan every commit, merge, and push with gitleaks and Presidio, covering each new file version in every decoding plus paths, commit messages, identities, and ref names, and reject invisible or bidirectional Unicode in tracked files. A private denylist adds terms that are always reported, and the hooks' output is filtered so those terms don't reach logs or agent transcripts. The setup is experimental and changes often; [TESTING.md](TESTING.md) describes how it works and how to test it.

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

On a paid plan (Pro, Max, Team, or Enterprise), claude.ai, the Chat tab of the Claude Desktop app, and Cowork can add this repository as a plugin marketplace: add a marketplace and enter `Pyroxin/opinionated-claude-skills`. An organization can restrict which marketplaces its members add, and skills need code execution turned on. Which plugin components load depends on the app:

- Skills load in chat, Cowork, and Claude Code.
- The `opinionated-research` agents load in Cowork and Claude Code. Chat ignores them, so `interactive-research` loads in chat but can't delegate to them there.
- Output styles, themes, and mods (`opinionated-communication`, `opinionated-themes`, `opinionated-status-band`, and `opinionated-context-management`) load only in Claude Code.

Plugins enabled on claude.ai also [load in Claude Code terminal sessions](https://code.claude.com/docs/en/plugins/loading#synced-plugins) signed in with the same claude.ai account.

**Deprecated:** individual skills can still be downloaded as ZIP files from the [Releases](https://github.com/Pyroxin/opinionated-claude-skills/releases) page and uploaded in **Customize > Skills**. This is the only route on the Free plan, which doesn't get plugins. The ZIPs are expected to be removed in favor of the marketplace, and a skill that can't be uploaded outside Claude Code is left out of them. (Also, check out the build system for the package! It automates some basic QA for publishing skills.)

ZIP files are named `plugin.skill.TIMESTAMP.SHA.zip` (e.g., `opinionated-software-engineering.software-engineer.20251130-014305.c7223ee.zip`). The timestamp and commit SHA identify the exact build the ZIP was derived from.

## Codex

The skills in this marketplace are usable by Codex. I'm still evaluating whether I want to make this a hybrid marketplace or whether Codex will get its own marketplace. In the meantime, the skills are usable with Codex but the agents will not work.

## Plugins

Each plugin tracks a need I hit while tinkering in my homelab so there's an emphasis on supporting continuous learning and experimentation. The software-engineering plugin is the base layer; several other plugins assume it's installed. The skills are internally structured using a semi-consistent XML schema to try and cause the skills to meld together in Claude's attention mechanism when they're composed.

### opinionated-software-engineering

The foundation plugin. SICP-derived design principles, paradigm guidance for functional, object-oriented, and logic programming, and two cross-cutting process skills for TDD and Git. Most other plugins depend on it for shared coding judgment.

| Component | Description |
|-----------|-------------|
| `software-engineer` | Core philosophy and design principles based on SICP |
| `functional-programmer` | Functional programming principles and patterns |
| `object-oriented-programmer` | Object-oriented design principles and patterns |
| `logic-programmer` | Logic programming and relational design |
| `test-driven-development` | TDD philosophy: tests as contracts |
| `git-version-control` | Commit standards and LLM-assisted workflows |

### opinionated-research

An alternative to investigating a topic through a single long search pass or by delegating to an external research agent. Two complementary research agents feed the `interactive-research` orchestration skill, which runs multi-source investigation through a persistent agent team (and supports research extensions after the primary task). The agents can delegate claim checks to a Haiku-based fact-checker. The `decision-analysis` skill structures option evaluation and supplies the epistemic-label and citation discipline the research agents share. Combining explicit decomposition, structured analysis, and adversarial reasoning substantially improves the result, on anecdotal evidence.

| Component | Description |
|-----------|-------------|
| `research-investigator` | Sonnet agent for methodical evidence-gathering: case-building from primary sources with procedural rigor and an explicit Audit section |
| `research-analyst` | Opus agent for judgment-led synthesis: cross-source pattern recognition and emergent insight beyond what any single source establishes |
| `fact-checker` | Haiku agent that checks one claim against one source in a fresh context, unprimed by the conversation the claim came from |
| `interactive-research` | Orchestration skill that coordinates specialist agents as a team |
| `decision-analysis` | Structured framework for evaluating options against criteria, with the epistemic-label scheme the research agents inherit |
| `deep-research` | Deprecated name kept as a notice: it points to `interactive-research` and to Claude Code's built-in deep-research workflow |

Note: these skills work best with the Kagi and Exa MCP servers added to the configuration. AWS' documentation servers are also integrated, AWS being the cloud provider these skills were built against.

Persisted research artifacts go under `{project-root}/.tmp/research/`, or wherever project or user instructions say research output belongs. Keeping them out of `.claude/` means an autonomous run doesn't need write access to the trees Claude Code loads settings, hooks, agents, and skills from. Many projects already ignore that path through the `*.tmp` pattern in gitignore.io output and in github/gitignore's `Global/Backup` template; adding `.tmp/` to `~/.config/git/ignore` covers the rest.

### opinionated-skill-creation

The `expert-skill-creator` skill was developed by having Claude reflect on the process of creating and tuning the other skills. It is updated regularly with guidance on prompting Claude-family models effectively, and it captures accumulated patterns around content depth, XML structure, directive tone, and citation practices, so each new skill benefits from what the previous ones established.

| Component | Description |
|-----------|-------------|
| `expert-skill-creator` | Expert guidance for high-quality skill creation |

### opinionated-apple-development

The Swift community has noted that Claude has trouble writing effective Swift code, especially for Swift concurrency, which launched after some of the more-recent models' knowledge cutoff dates. These skills address that deficiency, so they are more instructive and less philosophical than the others. macOS coverage follows because macOS is the primary workstation platform for this project.

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

Java as it actually exists in 2025 (records, sealed types, virtual threads, patterns). The plugin also advocates the Checker Framework for correctness guardrails that help Claude produce less buggy code automatically. The skill generally follows the features in the latest LTS, on the assumption that Java serves as an infrastructure language rather than an experimental one.

| Component | Description |
|-----------|-------------|
| `java-programmer` | Modern Java idioms and tooling |

### opinionated-python-development

Pythonic idioms, with extra attention to testing and to Jupyter. Note that Claude tends to still favor an OO-style even with this plugin due to the strong modularity preferences expressed in `software-engineer`.

| Component | Description |
|-----------|-------------|
| `python-programmer` | Pythonic idioms, testing, type hints, Jupyter guidance |

### opinionated-logic-development

SWI-Prolog: relational thinking, DCGs, constraint programming, PlUnit tests. A narrow niche, applicable when a problem is more about search than computation.

| Component | Description |
|-----------|-------------|
| `swi-prolog-programmer` | SWI-Prolog: DCGs, constraints, PlUnit |

### opinionated-fish-shell

Fish scripting with compatibility notes for macOS and Fedora, the two platforms where scripts carried between machines kept breaking.

| Component | Description |
|-----------|-------------|
| `fish-shell-scripting` | Fish shell idioms, cross-platform patterns |

### opinionated-tutoring

For sessions where Claude should teach rather than generate. It runs Socratic dialogue with the learner rather than writing the code for them.

| Component | Description |
|-----------|-------------|
| `socratic-tutor` | Pedagogical framework for teaching programming through Socratic dialogue |

### opinionated-communication

Output styles are a plugin component like skills and themes, so this plugin vends communication styles for Claude Code sessions. The first style, Plainspoken, was compiled from an analysis of the project author's own technical documents and research notes (LLM-written material excluded) rather than from generic style guides. It targets a structural problem in LLM-assisted work: Claude reads complete tool outputs while the user sees a collapsed transcript, so untended reporting assumes context the user doesn't have. The style makes messages carry their own evidence, grades each claim by how strongly it should be believed, replaces figurative wording with literal statements, and removes the devices that manufacture emphasis (e.g., staged contrast, rhythm-padded triples, hollow emphasis words). Engineering behavior is unchanged (`keep-coding-instructions: true`). Output styles apply to the main conversation only, not to subagents (forks excepted), and load at session start; select one under **Output style** in `/config`. Claude Code only; Claude Desktop's skill uploads don't have an output-style equivalent.

| Component | Description |
|-----------|-------------|
| `plainspoken` | Output style: precise, literal wording for a single-pass reader; claims graded by evidence, emphasis from content rather than structure |

### opinionated-themes

This plugin doesn't ship any instructions for Claude. Themes are a plugin component like skills and agents, so a marketplace can vend terminal color schemes the same way it vends skills. Both themes target high contrast and remain legible under warm-shift filters such as macOS Night Shift and Redshift, which reduce blue output and flatten the contrast of blue-heavy palettes. Claude Code only; Claude Desktop doesn't have a theme equivalent to package.

| Component | Description |
|-----------|-------------|
| `adwaita-inspired-light` | Full light palette drawing on the GNOME Adwaita colors |
| `nightshift-safe` | Minimal variant: the stock light theme with only the suggestion color corrected |

Plugin themes are read-only. Select one in `/theme` and press `Ctrl+E` to copy it into `~/.claude/themes/`, then edit your copy. Themes are currently an experimental plugin component, so the JSON format may change between Claude Code releases.

### opinionated-status-band

A mod is a plugin component written as code: a hooks module that Claude Code loads into a session, where it can draw in the interface and intercept the session's events. Claude Code accepts one hooks module per plugin and gives each plugin one row above the prompt, so each mod in this marketplace is a plugin of its own. This one draws a status row. Deciding when to compact, pause, or resume a long session takes knowing how full the context window is, how close the account is to its rate limits, and how long the conversation has sat idle, and the stock interface shows these in separate places or only on request. Mods are an early-access plugin component, so the API this one is written against may change between Claude Code releases. Claude Code only.

| Component | Description |
|-----------|-------------|
| `status band` | A Powerline-style status row above the terminal prompt: context left, model, project and branch, turn timing, rate limits, and cost |

The band shows a context gauge with the tokens used and the percentage left before auto-compaction, the model and reasoning effort, the project and git branch, how long the current turn has run or how long ago the last one ended, rate-limit usage with reset times, and the session's cost and turn count. The gauge updates after every model response, including during a long turn, and changes color when half the context is left and again when 15% is left. The gauge counts what responses have reported as used and doesn't predict what the next request will add; the notices of `opinionated-context-management` do add that prediction, so one can arrive slightly before the gauge reaches its threshold. The band draws in the Claude Code terminal only; Claude Code's desktop and mobile surfaces show nothing for it, because the row is built from character cells and Powerline glyphs. When the terminal is narrow, segments are removed in a fixed order and the context gauge is kept. The colors are fixed, based on the same Adwaita-inspired colors as the `adwaita-inspired-light` theme in `opinionated-themes`, with light gray blocks and dark text. Each block sets its own background and text, so the band is legible on light and dark terminal backgrounds but does not follow the session's theme.

**Font requirement:** the terminal has to be able to draw the Powerline symbols, which it can when its font includes them. The band uses three: the two segment separators (U+E0B0 and U+E0B2) and the branch glyph (U+E0A0). They are in Unicode's Private Use Area, so a font has them only if it was made or patched to include them. Without them the separators typically draw as empty boxes or question marks, while the text stays readable. If the terminal's font lacks them, [DejaVu Sans Mono for Powerline](https://github.com/powerline/fonts) is the suggested font to install; any other Powerline-patched font, or a [Nerd Font](https://www.nerdfonts.com/), also supplies them. Set it as the terminal's font, or as its fallback font for non-ASCII characters where the terminal has that setting.

### opinionated-context-management

A mod that lets Claude compact its own conversation at points it chooses. Claude Code compacts a conversation by itself as it nears the context limit, which can happen partway through a step and under a summary written without instructions from Claude, so the work that follows depends on what that summary happened to keep. With this mod, Claude keeps notes on the task in workspace files as it works, asks for a compaction when the work reaches a point it can be resumed from, and is resumed afterward with a prompt it wrote for itself, so the task carries on without the person present. Mods are an early-access plugin component, so the API this one is written against may change between Claude Code releases. Claude Code only.

| Component | Description |
|-----------|-------------|
| `context management` | A compaction tool for Claude, a system prompt section on keeping task notes and when to compact, and notices to Claude as the conversation grows |

The mod adds three things to a session. The first is a section of the system prompt that tells Claude to keep task notes in files inside the workspace, by default under `{project-root}/.tmp/notes/{task-name}/`, and to compact whenever the work is at a resumable point and the conversation's detail is in those notes. The second is a tool, `compact`, which takes Claude's instructions for the summary, the prompt to resume with, and the paths of the note files. When that turn ends with Claude's answer, the mod compacts and then submits the prompt, led by the note files' absolute paths. A turn that ends any other way (interrupted, refused, or failed) drops the request. So does a later tool call in the main conversation, a `/clear` or `/resume`, a prompt that comes after the request and before the compaction starts, or a turn that starts before it. A subagent's tool calls, and calls another plugin makes for itself, don't count; a prompt here is any the session receives, e.g., a background task's notification as well as the person's message. A reload of the mod while Claude Code is compacting also ends the request when a prompt arrived during that compaction. When Claude Code compacts the conversation by itself, the person runs `/compact`, or another plugin compacts it, while a request is scheduled, that compaction stands for the one Claude asked for: the mod doesn't compact a second time, and submits the prompt as it would have. Except after a `/clear` or `/resume`, the mod tells Claude that the request ended without a compaction: with the result of the tool call that canceled it, or otherwise by a notice added to the conversation, which names the cause and says what to do next: for most causes, to attend to what canceled the request and then to ask again. When another compaction had replaced the conversation before the request was canceled, the notice says so and lists the note files, because Claude then has the summary and not the conversation it asked from. When Claude Code declines or fails the compaction itself, the mod submits a notice in place of Claude's prompt, so the work carries on in the conversation as it stands; Claude's own prompt is submitted only after a compaction, because it was written for a reader who has just the summary. When a prompt can't be submitted, the mod tries once more and then leaves a notice in the conversation, which Claude reads with the next prompt. A line in the transcript tells the person each of these outcomes, including a compaction that ran; where Claude Code gave a reason for declining or failing a compaction, that line carries it and Claude's notice doesn't. A known limitation follows from the rule about prompts: when a background task (e.g., a subagent or a background command) finishes after the request and before the compaction starts, its notification cancels the compaction. The last notice tells Claude not to wait for background work, so the case is likeliest there. This behavior has been observed in a session: the request was canceled and Claude read the notice. The third is a notice sent to Claude when the context left before the limit falls to a threshold, saying that compacting at the next resumable point would be useful. Thresholds passed in one step send one notice. A threshold the conversation is already past at the first response after a compaction doesn't send its notice, because compacting again wouldn't make the conversation smaller; a transcript line says so, and later thresholds still send theirs. The limit is the auto-compaction threshold, or the whole window when auto-compaction is off or Claude Code hasn't yet reported whether it is on; in that last case the last notice says that the status isn't known. A line in the transcript tells the person when a notice is sent.

The mod predicts the size of Claude's next request so that a notice can go to Claude with that request. Each response reports how much context it used, and that figure is the starting point. The exception is a response in which Anthropic's API ran a tool itself (e.g., the advisor): Claude Code reports its usage summed over the several requests it made, each answered over the conversation again, so the mod doesn't take that sum as a size. It adds what the response generated to the figure it already had, and the next response made by one request reports the size exactly. A tool result that arrives afterward will be part of the next request, but a response hasn't reported it yet, so the mod adds an estimate from the result's length, at 2.5 characters per token. That ratio suits what Claude Code's tool results mostly are: published measurements of the current tokenizer put most code, logs, and structured data at roughly 2.3 to 3.1 characters per token (shell scripts and numeric CSV measured lower, near 1.8) and English prose at 3.3 to 3.6, so the estimate of tool output taken together should come out slightly over the true count. An overestimate can send one notice a little early and is discarded when the next response reports its usage, while an underestimate can delay a notice past the end of the turn; the comment on the constant in `hooks/compaction.ts` gives the sources. A notice then reaches Claude with the result that passed the threshold and not a turn later.

The gauge in `opinionated-status-band` follows a different rule on purpose: it shows only what responses have reported as used and doesn't add an estimate. A notice can therefore be sent while the band still shows slightly more room than the notice's threshold. The difference is the estimated size of the tool results since the last response, and the two agree again when the next response reports its usage. The transcript line for a notice states the figure the notice was sent on, estimate included.

The tool refuses a call unless notes are current: the call has to list at least one note file, every listed path has to be a file that exists and holds something, and the newest of them has to have been written no earlier than the start of the last tool call or submitted prompt in the main conversation. After a compaction the notes and the summary are what remains of the earlier conversation, apart from any recent messages Claude Code keeps, so the check is made by the tool and not left to the instructions. The check compares file times and does not read the notes: it does not see a tool call that started before the note was written and finished after it, or a tool that Anthropic's API runs itself, and it does not check what the notes say. A file time that falls on a whole second is allowed two seconds, because some file systems record times that coarsely, and an event inside that allowance is not seen either. Because notes are required, a task that may not write files cannot compact through the mod. The section and both notices say that their instructions about notes don't override an instruction not to write to the workspace, so such a task carries on under Claude Code's own compaction.

Except for the last notice, the texts Claude reads don't state token counts or percentages. Anthropic's [prompting guidance for Fable 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5) advises against showing the model context-budget counts where possible, because in a very long session a remaining-token countdown can occasionally lead it to trim its work or suggest a new session, which is the outcome the mod exists to prevent; the mod applies the same caution on every model. The last notice is sent once the room left before the limit is within a fixed number of tokens, states the room left, and asks for a compaction at the nearest resumable point, so that the compaction is one Claude prepared for.

Two settings change when the notices are sent: `remainingContextNoticePercents` (default 50, 30, and 15 percent of context left), entered as percentages separated by commas, and `remainingContextFinalNoticeTokens` (default 30,000 tokens), entered as a whole number. Entering `auto` for either setting restores its default, which is the way to undo a setting, because Claude Code's settings screen doesn't clear a saved value. An entry the mod can't use is ignored and named in a transcript line when the mod loads; the other entries, or the default, apply in its place. The notes folder is working material and is not meant to be committed; the README section on `opinionated-research` describes how `.tmp/` is usually already ignored by git.

## License

Copyright (c) 2025-2026 Pyroxin and contributors. Third-party content remains the property of its respective copyright holders.

[Eclipse Public License 2.0](LICENSE)

This license allows use, modification, and distribution, even for commercial purposes. Be aware that if you distribute as part of a commercial offering, you must defend and indemnify other contributors against third-party claims arising from your distribution.

## Content Notice

Good faith steps were taken to ensure no material was plagiarized by the LLM when compiling these skills but complete accuracy cannot be guaranteed. If you identify content in these skills that you own and wish to have removed or cited, open an issue including clear evidence of ownership.

---

This project is dedicated, with respect and admiration, to the spirit that lives in the computer.