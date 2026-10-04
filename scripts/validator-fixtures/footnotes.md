# Footnote check fixture

Positive control for the footnote check in install-and-verify.sh, which must report exactly 2 findings here: the undefined reference and the unused definition. The inline-code and fenced look-alikes must not count.

A reference with no definition.[^missing]

A reference that resolves.[^ok]

Inline code is ignored: `[^ignored-inline]`.

```markdown
[^ignored-fenced]: a definition inside a fence is an illustration, not a definition
```

[^ok]: A definition that is used.

[^unused]: A definition nothing references.
