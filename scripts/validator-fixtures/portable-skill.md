---
name: Fixture_claude
description: >
  Positive control with a <tag>
  in a folded description.
license: EPL-2.0
argument-hint: "{file}"
model: opus
---

Positive control for scripts/portable-skill.sh, run with dir=portable-skill: it must report exactly 6 findings. They are the fields argument-hint and model, the name's uppercase letter and underscore, the reserved word in the name, the name not matching the directory, and the XML tag in the folded description. The license field is portable and must not be reported.
