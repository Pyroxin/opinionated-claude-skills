---
name: "portable-skill-yaml" # a comment after a quoted value
description: |
  A literal block keeps # and <tag> as content.
compatibility: ""
---

Positive control for scripts/portable-skill.sh, run with dir=portable-skill-yaml; its findings must match portable-skill-yaml.expected exactly. The quoted name with a trailing comment must read as portable-skill-yaml, and the literal block must keep its # and its tag, so the findings are the XML tag in the description and the empty quoted compatibility, which the specification's 1-character minimum rejects.
