---
name: portable-skill-clean
description: 'A portable skill whose quoted value holds "double quotes", it''s apostrophe, a colon: here, and a spaced comparison x < y.'
license: EPL-2.0
compatibility: Requires bash 3.2 or later.
metadata:
  version: "1.0"
allowed-tools: [Read, Grep]
---

Negative control for scripts/portable-skill.sh, run with dir=portable-skill-clean; portable-skill-clean.expected is empty, because a portable skill must not produce any findings. It guards against a regression that reports findings on every skill, which the other fixtures, all of which expect findings, would not catch.
