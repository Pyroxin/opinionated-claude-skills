---
name: portable-skill-edge-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # an inline comment
description: "————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————"
metadata:
  name: nested-key-not-top-level
allowed-tools:
- Bash(git status:*)
version: 2
---

Positive control for scripts/portable-skill.sh with Windows line endings, run with dir=portable-skill-edge; its findings must match portable-skill-edge.expected exactly. It checks that carriage returns and inline comments are stripped, that a 600-character description of em-dashes is not counted in bytes, that a nested metadata key and a column-0 list item are not read as top-level keys, and that the 65-character name and the version field are reported.
