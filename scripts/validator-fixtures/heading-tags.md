# Heading-tag check fixture

<heading_tags_fixture_scope>
Positive control for the heading-tag check in install-and-verify.sh, which must report exactly 1 finding here: the untagged section.
</heading_tags_fixture_scope>

## Tagged section

<tagged_section>
Content.
</tagged_section>

## Untagged section

Content without its own tag.

```markdown
## A heading inside a fence is ignored
```
