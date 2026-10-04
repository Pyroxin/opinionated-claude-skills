# Citations and Resources

<citations_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file. This file is a reference for the `expert-skill-creator` skill and extends its `SKILL.md`. A tag this file names but does not contain is in `SKILL.md` or in the file that `SKILL.md`'s `<reference_files>` table lists for it.

**Contents:**
- [Formal Citation Format](#formal-citation-format)
- [Citation Accuracy](#citation-accuracy)
- [Source Verification](#source-verification)
- [Common Citation Mistakes](#common-citation-mistakes)
- [Resources Section](#resources-section)
</citations_reference_scope>

## Formal Citation Format

<citation_format>
**When a formal citation is warranted (see `<citation_scope>`), use ACM style with Markdown footnote syntax.**

**In-text citation:** Use Markdown footnote references (e.g., `[^1]`, `[^2]`).

**Reference list format:**
```markdown
## Sources

<sources>
[^1]: Author Name. Year. Title. Publication venue. URL or DOI

[^2]: Organization. Year. Document Title. Retrieved [Date] from URL
</sources>
```

**Example citations:**
```markdown
Rich Hickey's "Simple Made Easy" talk[^1] distinguishes simplicity from ease...

## Sources

<sources>
[^1]: Rich Hickey. 2011. Simple Made Easy. Strange Loop Conference. Retrieved November 24, 2025 from https://www.infoq.com/presentations/Simple-Made-Easy/

[^2]: ACM. 2023. Reference Formatting. Retrieved November 24, 2025 from https://www.acm.org/publications/authors/reference-formatting
</sources>
```

**Why Markdown footnotes:** Footnote syntax (`[^1]`) renders as a footnote in Markdown viewers, creates clickable links to sources, and distinguishes citations from array indexing and other uses of brackets in technical content.
</citation_format>

## Citation Accuracy

<citation_accuracy>
**Never fabricate bibliographic details.**

- Verify that each DOI resolves to the cited work before including it
- Use actual access dates, not invented dates (when adding citations retroactively, use the date the content was originally retrieved, not the current date)
- If you have a value for a field but are unsure of it, keep the value and record the doubt as a bracketed query on that field (e.g., `[Third edition?]`), so the reader gets both the value and its status
- If you have no basis for a value, omit the field rather than guess
- Prefer an incomplete, accurate citation over a complete, fabricated one
</citation_accuracy>

## Source Verification

<source_verification>
**Use tools to confirm sources before citing them; recall from training is not verification.**

Treat what you recall from training as a hypothesis, not a fact. Before adding any citation:

1. **Verify that URLs exist**: fetch the URL to confirm it resolves and contains content on the cited subject
2. **Verify that quotes are accurate**: search for the exact quote, because a quote recalled from memory often differs from the original
3. **Verify attributions**: confirm who said something, because community interpretations are often misattributed to authoritative sources (e.g., "Apple says..." for a statement that comes from a blog post)
4. **Verify that the content matches the claim**: read the source to confirm it supports what you're citing it for

**When verification tools are available (e.g., WebFetch, WebSearch, Kagi, Exa), use them.** A few tool calls cost far less than publishing an incorrect citation.

**Common verification failures include:**
- Attributing secondary interpretations to primary sources (e.g., a blogger's synthesis cited as official documentation)
- URLs constructed from memory that return 404 or redirect elsewhere
- Quotes that are paraphrases or composites of what was actually said
- Version-specific claims stated as fact without verification

**Verification workflow:**
1. Draft citations from memory
2. Before finalizing, verify each citation with the available tools
3. Correct or remove citations that fail verification
4. Note in the commit message that sources were verified
</source_verification>

## Common Citation Mistakes

<citation_mistakes>
**Mistakes found during skill validation:**

- **"Unknown" attributions**: Verify such an attribution before accepting it. Quotes attributed to "Unknown" often have identifiable sources (e.g., "Time is a device..." is from Ray Cummings, 1922)
- **Incomplete quotes without ellipses**: When quoting a sentence fragment, end it with `...` to show that the quote is incomplete
- **Unsourced statistics**: Specific numbers (e.g., "58% adoption", "100x slower") require sources. If a number has no source, find one, remove the claim, or qualify it (e.g., "significant performance issues" instead of "100x slower")
- **Informal documentation references**: Replace an informal reference such as "From the X documentation" with a formal citation: `[^1]: Author. Title. URL`
- **Paraphrased official guidance without disclosure**: If a skill substantially paraphrases official documentation (e.g., a style guide), add a disclosure at the start: "This skill synthesizes and paraphrases the official X guidelines."
- **Assuming well-known means no attribution is needed**: Named concepts (e.g., Liskov Substitution Principle, Test Pyramid) should acknowledge their originators. Informal attribution is enough when the name itself attributes the concept (e.g., "Liskov Substitution Principle" names Liskov); use a formal citation when the source would be useful to look up.
- **Citing a source the content never referenced**: This mistake is the converse of the item above and is harder to notice, because the citation passes verification. Guidance derived independently does not become third-party content because a reviewer recognizes what it resembles; a citation records a reference, so where the content made no reference there is nothing to record (see `<citation_provenance>`)
</citation_mistakes>

## Resources Section

<resources_guidelines>
**Resources serve two purposes: pointing Claude to content it can read at runtime, and naming works that activate trained knowledge.** Both kinds are valuable; distinguish them in the Resources section (e.g., by labeling which purpose each resource serves).

**Fetchable resources**, which Claude can read at runtime, include:
- Written documentation (e.g., HTML, Markdown, PDF)
- API references and generated docs
- GitHub repositories (especially those with .md files)
- Local file paths (e.g., Xcode docs, language references)
- Style guides and written tutorials

**Training-data resources**: Claude can't fetch these, but naming them activates its parametric knowledge of their content. This use applies the retrieval-trigger philosophy in `<skill_scope>`: a book title in a Resources section is a retrieval trigger, not a URL to fetch. Include works that originated or define the concepts the skill relies on (e.g., the book that introduced a technique), when Claude's training plausibly covers them. Label these as training-data resources so users understand that Claude is drawing on trained knowledge, not on a retrieved source.

**Never include:**
- Video resources (e.g., WWDC sessions, YouTube), because Claude cannot watch videos
- Paywalled or recent content that is neither fetchable nor likely in training data
- Resources requiring authentication
- Quotes or paraphrases from content that neither permits reuse nor would clearly be fair use

**Local documentation is especially valuable, for these reasons:**
- Can be read without network calls
- Available in air-gapped environments
- Often more stable than web URLs
- Usually faster to access

**Format:**
```markdown
## Resources

<resources>
**Official:**
- [Language Documentation](https://docs.example.com/)
- [Style Guide](https://github.com/example/style-guide)

**Local:**
- `/path/to/local/docs/`
- Man pages: `/usr/share/man/man1/tool*.1`

**Foundational (training-data):**
- Author. Year. *Title*. Publisher. — Brief note on why this activates relevant knowledge
</resources>
```
</resources_guidelines>
