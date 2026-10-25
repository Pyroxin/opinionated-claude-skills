# Testing

This document records local validation procedures for this repository. It is
organized by testing topic so new checks can be added without reshaping the
file.

## Standard Validation

Run the fast structural validation before committing:

```bash
./scripts/install-and-verify.sh --validate-only
```

This checks JSON validity, verifies declared plugin components exist, runs
ShellCheck over the repository's shell scripts, and checks skill, agent, and
output-style Markdown for the conventions `expert-skill-creator` defines:
placeholder notation, footnotes resolving in both directions within each file,
and instructions that ask the model to put its reasoning in the output. Heading
tags and bracket placeholders are reported as warnings with counts until the
existing skills come into line. A skill that couldn't be uploaded outside
Claude Code (`scripts/portable-skill.sh` lists the rules; it needs dasel v3) is also reported as a
warning, and `build-skills.sh` leaves it out of the ZIPs. A `SKILL.md` that
can't be read (e.g., mode 000) stops both the validation and the build with an
error, rather than being reported as lacking frontmatter and left out.

Each content check first runs against a fixture in
`scripts/validator-fixtures/` holding a known instance of every pattern it
applies, and fails the run if it reports a different number of findings. When
you change a check, update its fixture and the expected count passed to
`self_test` in the same change. The portability check is the exception: each
`portable-skill*.md` fixture has a `.expected` file with its exact findings, so
update those files instead.

Run the full validation path when you need to exercise the Claude Code plugin
installation flow in an isolated config directory:

```bash
./scripts/install-and-verify.sh
```

Full mode also checks that every link to Anthropic's documentation sites
resolves to a real page. Those sites return HTTP 200 for missing pages, so the
check reads each page's Markdown, and it runs only after a missing control page
on each site is reported missing and a known page is reported present.

Build the release ZIPs when changing skill packaging or release behavior. The
ZIP builds are deprecated and expected to be removed:

```bash
./scripts/build-skills.sh
```

## PII and Secret Scans

The `pre-commit`, `pre-merge-commit`, `commit-msg`, and `pre-push` hooks run
`scripts/pii-and-secret-gate.sh`. The `pre-commit` hook scans what is staged,
as recorded in the index, and the `commit-msg` hook scans the message and the
author and committer identities, so the scans run before anything enters a
commit. A merge that completes without conflicts runs `pre-merge-commit`
instead of `pre-commit`, so that hook runs the `pre-commit` hook's checks.
The `pre-push` hook scans everything each pushed ref publishes: every
commit being pushed (files, paths, and metadata), annotated tag objects, and
the ref's name, not only the branch tip. Commits can be made with hooks
bypassed (`git commit --no-verify`) or before the hooks were active, and a
pushed commit stays retrievable by its hash even after later commits change
the content. Every mode scans file paths as well as contents, because a
filename is published too.

These scans are the automated gate. They work alongside the full read of each
commit's content by an LLM that [CONTRIBUTING.md](CONTRIBUTING.md#pre-commit-validation)
asks for before committing, which looks for problems a pattern doesn't
describe, such as details from a real scenario; they don't replace it.

Secrets are found with gitleaks, which runs locally, in two passes: its own
Git scan, and a scan of a temporary directory holding the texts the PII scan
analyzes (see `--export-to` in `scripts/pii-scan.py`), each saved as
`{n}/content.txt` with a first line naming its source. Every gitleaks call uses a
configuration the gate writes (gitleaks' default rules), an empty ignore
directory, and `--ignore-gitleaks-allow`, so a `.gitleaks.toml`,
`.gitleaksignore`, or `gitleaks:allow` comment in the repository doesn't
change what the gate reports. gitleaks runs with `--redact` and writes a JSON
report, and `scripts/pii-scan.py --gitleaks-report` prints each leak's rule,
location, and commit from it, without the secret. gitleaks' `--verbose` output
isn't used, because it prints the matched line's surrounding text and a
commit's author and email. Personal data (credit
card numbers, US social security and taxpayer numbers, email addresses, phone
numbers, IBANs, and person names) is found with Presidio
(https://github.com/data-privacy-stack/presidio) through
`scripts/pii-scan.py`. Each scanner first runs a positive control: gitleaks
must detect a GitHub-format token generated at run time (so no file in the
repository holds a planted secret), and the PII scanner must pass its fixture
control described below.

`uv` installs the PII scanner's dependencies (with network access; if that
fails, the gate retries from uv's cache with `--offline`, so it still runs
offline once they're installed), then the
control and the scan run with `uv run --offline`. Where `sandbox-exec`
(macOS) or a working bubblewrap (`bwrap`, which Claude Code's sandbox also
uses on Linux) is available, they run inside a sandbox with no network access,
so the scanned text can't leave the machine. The scanner first confirms from
inside the sandbox that it doesn't have network access (`--check-isolation`), and the gate
stops if it does. On macOS that check connects to 127.0.0.1:1 and to every
proxy the environment names (e.g., `HTTPS_PROXY`), and passes only when each
connection is denied with a permission error, because a sandbox can block
other connections while leaving its proxy open (Claude Code's does). Without
either tool, the gate warns and scans offline without a sandbox.

macOS doesn't let `sandbox-exec` start inside another sandbox: from Claude
Code's sandboxed Bash it exits 71 with `sandbox-exec: sandbox_apply:
Operation not permitted`. The gate probes it with a no-op, and when that
fails, asks the scanner whether the process is already sandboxed
(`--check-sandboxed`, which calls `sandbox_check` from libSystem and exits 0
for sandboxed, 1 for not, and 2 when it can't tell). Only a positive answer
lets the scan run without a wrapper, within the outer sandbox, and only if
`--check-isolation` passes there too; otherwise the gate stops. Claude Code's
sandbox fails that check. Where that sandbox lets uv write its cache, a commit
or push from it stops with a message to run it from an unsandboxed shell;
where it doesn't, the gate stops earlier, at `uv sync`, with uv's own error.

Run it by hand the same way, so a manual scan gets the same guarantee:

```bash
# Install the dependencies; the only step that uses the network.
uv sync --script scripts/pii-scan.py

# Run the scanner offline, without network access, as the gate does. Both
# tools are probed with a no-op first: bwrap can be installed but unable to
# start (e.g., where user namespaces are restricted), and sandbox-exec can't
# start inside another sandbox. In that case pii_sandbox stays empty, and the
# check below decides whether the outer sandbox isolates the scan; the gate
# also requires `--check-sandboxed` to exit 0 first. GIT_NO_REPLACE_OBJECTS=1
# makes git read the objects a push sends rather than replace refs'
# substitutes.
pii_sandbox=()
profile='(version 1)(allow default)(deny network*)'
if command -v sandbox-exec >/dev/null; then
  if sandbox-exec -p "$profile" true; then
    pii_sandbox=(sandbox-exec -p "$profile")
  else
    uv run --quiet --offline scripts/pii-scan.py --check-sandboxed
  fi
elif command -v bwrap >/dev/null \
    && bwrap --dev-bind / / --unshare-net --die-with-parent true >/dev/null 2>&1; then
  pii_sandbox=(bwrap --dev-bind / / --unshare-net --die-with-parent)
fi
pii_scan() {
  GIT_NO_REPLACE_OBJECTS=1 ${pii_sandbox[@]+"${pii_sandbox[@]}"} \
    uv run --quiet --offline scripts/pii-scan.py "$@"
}

# Confirm the sandbox took effect: prints "network isolated". Without a
# working sandbox (or an outer one that removes network access) this check
# fails, and the scans below aren't isolated.
pii_scan --check-isolation

# Every tracked file at a revision (current findings):
pii_scan --rev HEAD --show-allowed

# Specific commits, as the hook does:
pii_scan --commit "$(git rev-parse HEAD)"

# The positive control: every detector must fire on its fixture.
pii_scan --control

# An allowlist edit not yet staged, before staging it:
pii_scan --rev HEAD --allowlist scripts/presidio-pii-allowlist.tsv
```

Handle a finding by removing the data, or, if the match is public or invented
(e.g., a cited author, a product name, an `example.com` address, a digit run
inside a DOI), by adding it to `scripts/presidio-pii-allowlist.tsv` in the
section that says why. Path-scope entries for matches that are only acceptable
in one file.

The scans read the allowlist as committed, never from the working tree, so an
edit to it that isn't staged doesn't affect a hook. This keeps an
uncommitted allowlist entry from approving content the commit records without
that entry:

| Scan | Allowlist read from |
| --- | --- |
| `pre-commit`, `commit-msg` (`--staged`, `--message-file`) | The index, i.e., the version staged for the commit |
| `pre-push` (`--commit`, `--tag`, `--ref`) | The tip of each pushed ref (`--allowlist-rev`), so a push is judged by the allowlist it publishes |
| `--rev REV` | `REV` |
| Any mode with `--allowlist PATH` | `PATH`, for trying an edit before staging it |

So stage an allowlist entry in the same commit as the content it accepts, or
an earlier one. A pre-push scan judges older commits in the push by the tip's
allowlist, because what the push publishes is that allowlist, not the ones
before it. Put terms that must always be reported in a private denylist,
`~/.config/pii-scan/denylist.txt` or the file `$PII_SCAN_DENYLIST` names (see
`load_denylist` in `scripts/pii-scan.py` for the format). Keep it out of the
repository, because committing it would publish it. Each line is a regular
expression in the `regex` module's syntax, matched without regard to case
(`(?-i)` turns that off) and anywhere in the text, including inside a word:
`{surname}` also matches `{surname}_notes.md`, and `\b{name}\b` matches only
the whole word. A line starting with `!` is an exception pattern, which
excuses a term match it covers. An entry that doesn't compile, that matches an
empty string, or that runs longer than three seconds on one text stops the
scan with exit status 2; the message names the entry's line number but never
its text or the denylist's path, since gate output can end up in logs and LLM
transcripts. A
denylist finding is reported the same way, by the line of the entry that
matched (e.g., `staged:notes/x.md:4: DENYLIST 1.00 (denylist line 7)`),
never by the matched text: a private term sent to a model in an agent's
transcript can trip its safety checks and derail the session running the
scan. So no term is printed anywhere: any other finding whose match overlaps
a term is printed with its entity type and score but not its text; a term in a
source label (a path or a ref or tag name) is replaced by
`[denylist line N]`, keeping the rest of the label so the file can still be
found; and the gate counts git's stderr instead of printing it and names a
pushed ref by its pre-push line. A term an `!` exception excuses isn't
reported, but it's still redacted.

The commit and push hooks also pass everything they print through
`scripts/pii-scan.py --redact-stream` (see `scripts/git-hooks/run-redacted.sh`),
which replaces each term on each line with `[denylist line N]`. That covers
text no script here controls, such as gitleaks' own log lines, git's error
messages, and a textconv driver's stderr. A hook's stdout and stderr are
merged into one pipe before the filter, so their lines can come out in a
different order relative to each other, and everything reaches git on one
stream. The filter runs in the PII scanner's uv environment, which the hook
installs first if it's missing, and doesn't load Presidio, so it adds about
0.2 seconds to a hook run. The hook fails when the filter can't start (e.g.,
uv can't write its cache, the environment can't be installed, or the
denylist is missing or has an entry that doesn't compile) and when it stops
partway (e.g., a pattern runs past its time limit on a line, or a line is
longer than 1 MiB; nothing from that line on is printed). In each case the
hook prints a fixed message with the exit status, and neither uv's output
nor the filter's own message is shown, because either can name a path (e.g.,
the denylist's, or a source file's in a traceback) that nothing filters; run
`uv run --offline scripts/pii-scan.py --redact-stream </dev/null` by hand to
see why the filter can't start.

The filter matches each line on its own, as it reaches the pipe, so it
doesn't hide:

- a non-ASCII term in git's octal `core.quotePath` form (e.g.,
  `z\303\266rblax` for `zörblax`), though none of the tools the hooks run
  prints a path that way;
- a term split by ANSI escape codes or zero-width characters, or a match a
  pattern would make across a line break;
- output a program writes directly to `/dev/tty`, which bypasses the pipe,
  though none of the tools the hooks run does that;
- text of the placeholder `[denylist line N]` that a denylist entry matches
  (e.g., an entry `denylist`), which stays as is.

A script run by hand, outside the hooks, isn't filtered, which is why the
scripts still redact what they print.

The denylist is required: a scan stops with exit status 2 when the file is
missing or doesn't hold any term patterns (`!` exception lines alone don't count), so
a mistyped path or an emptied file can't silently turn it off. If you don't
keep one, set `PII_SCAN_DENYLIST=none` in the environment the hooks run in
(e.g., your shell profile) to scan without it. The `--control` check and
`--export-to` don't read it.

The control scans `scripts/validator-fixtures/pii-control.md` (with
`pii-control-denylist.txt` standing in for a private denylist; one of its
entries uses `\b`, so the control also fails if entries stop being read as
regular expressions) and fails the hook unless every pair in
`pii-control.expected` (an entity type and its sample's exact text) is
detected, and every entity type the scan checks has a pair. Matching the pair rather than the type matters because one sample can
trigger several detectors: the ITIN sample also scores as a US_SSN, so a check
by type alone passes with the SSN sample missing. When you add a detected
entity type, add its sample to the fixture and its pair to the `.expected` file
in the same change.

Cover these regression cases when changing the scanner or the gate:

- The control passes, fails when an entity type's sample is removed from the
  fixture (including the US_SSN sample, which the ITIN sample would otherwise
  mask), and fails when an entity type doesn't have a pair in `pii-control.expected`.
- In `pre-commit` mode, a staged secret and a staged non-allowlisted PII
  finding each fail the gate; the PII finding is reported as `staged:{path}`
  with its line.
- In `pre-push` mode, a commit that adds a non-allowlisted finding fails the
  gate, and the finding is reported with its commit, path, and line.
- A secret or PII finding that appears only in an earlier commit of the pushed
  range (e.g., committed with `--no-verify`), and is removed by a later one,
  still fails the gate.
- The gate finishes when run the way Git runs hooks, with SIGPIPE ignored, e.g.,
  `( trap '' PIPE; timeout 120 ./scripts/pii-and-secret-gate.sh pre-commit )`.
  A pipeline that relies on SIGPIPE to stop a producer (such as
  `tr </dev/urandom | head`) passes when run directly and hangs as a hook.
- With a denylist holding a term and an `!` exception phrase containing it, a
  file with the term both inside and outside that phrase reports only the
  occurrence outside it.
- Denylist entries are regular expressions, each matched on its own: with
  invented terms, `{first}\s+{surname}` matches the two names separated by
  several spaces or a tab; `\b{short}\b` matches the short name alone but not
  a longer name that starts with it; a bare lowercase `{surname}` matches
  inside `{surname}_notes.md` and a capitalized `{Surname}Family`; and
  `(?-i){Surname}` matches the capitalized form but not the lowercase one.
- A denylist entry that doesn't compile (e.g., `{surname}(` with an unclosed
  group) fails the scan with exit status 2 and a message naming the file, the
  line number, and the error's position, but not the pattern or the `regex`
  module's message, which can quote it.
- A denylist entry that matches an empty string (e.g., `{surname}|`, `a*`,
  or a bare `\b`) fails the scan when loaded; a lookahead alone (e.g.,
  `(?={surname})`), which matches empty only where its text appears, fails
  the scan of a text containing that text. Both name the line, not the
  pattern.
- A denylist entry that backtracks catastrophically (e.g., `(a+)+$` against
  100,000 `a`s followed by `b`) fails the scan with exit status 2 after about
  three seconds, naming the entry's line and the source label, rather than
  hanging or passing.
- A finding in `scripts/presidio-pii-allowlist.tsv` that quotes one of its own
  entries is accepted; a real name added in a comment there fails the gate,
  including a name that is part of an existing entry's text.
- The self-quote check reads `scripts/presidio-pii-allowlist.tsv` as the
  loader does: a line `"#x"<TAB>Jane Roe` there, a comment once csv unquotes
  it, still reports `Jane Roe`. A name in a comment that shares a line with
  an entry through a lone carriage return (e.g.,
  `# Thanks to {name}.\rPERSON<TAB>{other name}<TAB>notes/x.md`) is
  reported, while the entry's own text, and a path-scoped entry whose quoted
  text field spans two lines, are accepted.
- An allowlist rule whose TEXT is `*` without a path glob (e.g.,
  `PERSON<TAB>*`, `*<TAB>*`, or either with an empty or `*` glob) fails the
  scan with exit status 2 and `FATAL: couldn't read the allowlist:
  {origin}:{line}: a "*" TEXT needs a PATH_GLOB other than "*"`, which stops
  the gate. A `*` TEXT with a specific glob (e.g.,
  `PERSON<TAB>*<TAB>notes/x.md`) still accepts a name in `notes/x.md` and
  reports the same name in `notes/y.md`.
- A tag message reports a finding placed inside a signature block or after
  one, or in one of its header lines (e.g., `Comment:`); only the armor of a
  trailing block (its BEGIN and END lines and base64 payload) is skipped.
- A pre-push line whose local ref contains a space (as from
  `git push origin ':/fix 0:refs/heads/x'`) is parsed from the right and the
  commit is scanned; a line without two object IDs stops the gate.
- A secret on a line ending in `# gitleaks:allow` is still reported, and a
  `.gitleaks.toml` or `.gitleaksignore` in the working tree (tracked or not)
  doesn't change what any gitleaks pass reports, including the commit-msg scan.
- A secret in a text file whose name gitleaks skips by default (e.g.,
  `package-lock.json`, `logo.svg`, `node_modules/x.js`) is reported.
- A secret in a text file whose first bytes are a binary format's signature
  (e.g., a file starting with `%PDF-1.7` or `MZ`), which gitleaks skips without
  reading, is reported.
- After `git replace A B`, the gate scans commit A's own content and message.
- A merge that completes without conflicts runs the `pre-merge-commit` hook,
  and a secret in the merged content fails it.
- The gate runs with `TMPDIR` pointing at a directory other than the system
  default (as in Claude Code's sandbox).
- A commit whose message or author identity contains a non-allowlisted finding
  fails the commit-msg hook and, if committed with hooks bypassed, the
  pre-push gate; the finding is reported as `{commit}:(commit metadata)`.
- A file that isn't valid UTF-8 is still scanned, and a denylisted term in a
  UTF-16 file (e.g., made with `iconv -t UTF-16LE`) is reported, including a
  file with no byte-order mark that holds only CJK text (and so doesn't hold any NUL bytes).
- A secret in a UTF-16 file fails `pre-commit` and `pre-push`, although
  gitleaks' own staged or Git scan of it exits 0.
- A merge commit whose conflict resolution adds a finding is reported, and a
  secret added in a merge resolution and removed by a later commit fails
  `pre-push`.
- An annotated tag pushed on a commit the remote already has is scanned: an
  email address in its message, and its tagger's name and email, are
  reported.
- A merge of a signed tag (e.g., signed with a throwaway key through
  `-c gpg.format=ssh -c user.signingkey={key}.pub`), which Git records in the
  merge commit as a `mergetag` header, is scanned with the merge: a denylisted
  `{tagger}` name and its email address, and a name in the tag's message, are
  reported as `{commit}:(commit metadata)`, and the tag's signature armor
  isn't. Without signing, write the commit object by hand with a `mergetag`
  header and store it with `git hash-object -t commit -w`. A commit without a
  `mergetag` header exports the same text as before (compare `--export-to`
  output of the old and new scanner over the same commits).
- A filename that holds a finding (e.g., an empty
  `someone@example.org.txt`, or a denylisted term) is reported once, as
  `(path)`.
- A filename that isn't valid UTF-8 (staged with
  `git update-index --add --cacheinfo`) is scanned rather than failing, and a
  denylisted name in a Latin-1 filename is reported.
- An allowlist entry that isn't staged doesn't suppress a staged finding; the
  same entry staged does.
- A finding added to a control fixture is reported; only the fixtures' own
  samples are allowlisted.
- A PERSON result in a script without case (e.g., `山田 太郎`, `김민준`) isn't
  discarded by the name filter.
- The name filter (`looks_like_name`) keeps a cased name that starts with
  initials (`{I}. {Surname}`, `{I}. {I}. {Surname}`, `{I}.{I}. {Surname}`) or
  ends in a listed suffix (`{First} {Surname}` followed by `Jr.`, `Jr`, `Sr.`,
  `Sr`, `II`, `III`, `IV`, `PhD`, or `MD`), and still discards
  `{Surname}, {First}`, an all-lowercase name, two words separated by two
  spaces, and a single word followed by a suffix (`{Surname} Jr.`).
- The same content committed at a path-scoped allowlisted path and at another
  path is reported at the other path.
- A file replaced by a symlink (a type change) is scanned, and a filename
  containing a tab is scanned rather than failing.
- A denylisted term on a `#` line of a pending commit message is reported.
- A pending commit message in Latin-1 bytes (as written under
  `i18n.commitEncoding=latin1`, e.g., with `printf '\xfc'` for `ü`) is read
  with its invalid UTF-8 bytes kept, so an accented `{Surname}` that the
  denylist holds in UTF-8 form, and an accented `{First} {Surname}` that
  Presidio takes for a person, are each reported in `--message-file` mode and
  through the commit-msg hook. The same message in UTF-8 exports the same
  text as before.
- A nonexistent denylist fails the scan with exit status 2 and a message
  saying how to create one or opt out, whether its path comes from
  `$PII_SCAN_DENYLIST`, `--denylist`, or the default
  (`~/.config/pii-scan/denylist.txt`, e.g., with `HOME` pointing at an empty
  directory and `UV_CACHE_DIR` kept at the real cache). So does a denylist
  that is empty or holds only `!` exception lines. With
  `PII_SCAN_DENYLIST=none` the scan runs without a denylist and passes;
  `--denylist none` is read as a path and fails, and `--control` passes
  either way.
- A denylisted term is reported even in a file an allowlist entry exempts.
- A denylist finding never prints the matched text. With a scratch denylist
  of invented terms (e.g., `{Surname}` on line 3 and `\b{Other}\b` on line 5),
  a staged file at a path without either term that holds both on line 2
  reports `staged:{path}:2: DENYLIST 1.00 (denylist line 3)` and
  `(denylist line 5)`, and a case-insensitive grep of the scan's combined
  stdout and stderr doesn't find either term. The same holds for a pending
  commit message in `--message-file` mode (including a `#` line) and through
  the commit-msg hook, where only the control's lines name the fixture's own
  terms (pick scratch terms the fixture doesn't use so the grep is clean). A
  staged file named `notes/{surname}_list.md` is reported as
  `staged:(path) notes/[denylist line 3]_list.md:1: DENYLIST 1.00 (denylist line 3)`.
- No denylist term reaches the gate's stdout or stderr. With a scratch
  denylist holding an invented `{term}`, run each case below through the gate
  (in a scratch clone, with the edited scripts copied in) and grep its
  combined output case-insensitively for `{term}`: no grep matches, and the
  gate still exits 1 with the finding reported. Before the change, each
  printed the term.
  - A staged `notes/{term}_list.md` holding an email address whose local part
    is `{term}` and a capitalized `{Term} {Surname}`: the `EMAIL_ADDRESS` and
    `PERSON` findings print `(denylist line N)` in place of their text, and
    every label prints `notes/[denylist line N]_list.md`. With `--staged`, an
    `--allowlist` accepting both, and `--show-allowed`, the `(allowed)` lines
    are redacted the same way.
  - A staged `notes/{term}_keys.md` with a gitleaks test token on a line that
    also holds `{term}`: the staged-changes pass prints
    `github-pat at notes/[denylist line N]_keys.md:2`. The same text in a
    UTF-16 file, which git's diff treats as binary, is found only by the
    exported pass, which prints the source label and the text's own line
    (`staged:notes/[denylist line N]_wide.txt:2`), not the scratch path.
  - A pushed commit authored as `{Term} {Surname}` that adds a token: the
    history pass prints `github-pat at {path}:1 in commit {sha}`, without the
    author and email `--verbose` printed.
  - A commit message holding a token beside `{term}`, through `commit-msg`:
    `github-pat at (stdin):{line}`.
  - A `.git/info/attributes` textconv driver that writes `{term}` to stderr,
    with a matching file staged (`pre-commit`) or pushed (`pre-push`): the
    gate stops with the FATAL giving git's exit status and stderr line counts,
    without the stderr text. The gate's own "anything staged" check runs with
    `--no-textconv`, so the driver doesn't run there.
  - A push to `refs/heads/{term}-topic` reports
    `(ref name) refs/heads/[denylist line N]-topic`, and an unparsable
    pre-push line holding `{term}` stops the gate with
    `couldn't parse pre-push line 1`.
  - `--commit {term}deadbeef` crashes with `git diff-tree exited with status
    128 (arguments withheld ...)` rather than the git command.
  - In `--gitleaks-report` output (try a hand-written JSON report), `{term}`
    in a rule ID, path, or commit prints `[denylist line N]`, and a finding
    without a `StartLine` prints `:(line not reported)`; only a finding on
    an exported text's first line prints `:(the source label itself)`.
- No denylist term reaches a hook's output, including text the gate doesn't
  print itself. With a scratch denylist holding `{term}`, run each case below
  through the hook in a scratch clone (the `pre-push` hook directly, e.g.,
  `printf 'refs/heads/x {sha} refs/heads/x {zeros}\n' | scripts/git-hooks/pre-push origin`,
  so nothing is pushed) and grep its combined output case-insensitively for
  `{term}`: no grep matches, and each prints `[denylist line N]` where the term
  was.
  - A textconv driver that writes `{term}` to stderr only on its second run
    (count runs in a file), so the gate's own `git diff` passes and gitleaks'
    run gets the line: gitleaks' `ERR` log line shows the redacted text, with
    no color escape codes (`--no-color`).
    gitleaks still exits 0 here, as `check_gitleaks_git` in the gate explains.
  - A fetch refspec `git remote` rejects (e.g.,
    `refs/heads/{term}*/*:refs/x/*`) with a new branch pushed: git's
    `fatal: invalid refspec` line is redacted, and the hook exits 128.
- The hooks' output filter fails closed and doesn't change anything but terms:
  - With `PII_SCAN_DENYLIST=none`, a hook prints exactly what
    `{hook} --redacted-body`, which skips the filter, prints.
  - None of the hook's own failure messages names a path. Keep the scratch
    denylist in a directory whose name holds `{term}`, run each case below,
    and grep the hook's combined output for `{term}`: no grep matches.
    - A denylist entry that doesn't compile, a denylist that's unreadable
      (`chmod 000`) or isn't valid UTF-8, or one that doesn't exist fails the
      hook with exit status 2 before its checks run. Run by hand,
      `uv run --offline scripts/pii-scan.py --redact-stream </dev/null` gives
      the entry's line number but not its pattern, or the exception's type
      without its message.
    - A pattern that runs past its time limit on a line of the hook's output
      (e.g., `(a|a)+$` against 30,000 `a`s and an `X`) fails the hook; nothing
      from that line on is printed.
    - A 5 MiB line without a newline in the hook's output fails the hook;
      nothing from that line on is printed.
    - With uv's cache emptied (`UV_CACHE_DIR` set to an empty directory) and
      its package index unreachable, the hook says it's installing the
      environment, then fails with exit status 1 and uv's exit status before
      running any check. With a cache uv can't write (e.g., in Claude Code's
      sandboxed Bash), it says so instead.
    - With `run-redacted.sh` removed or not executable, the hook fails with
      exit status 1; so does `pre-merge-commit` with `pre-commit` removed.
    - `pre-merge-commit` run outside a repository, or in a directory under a
      path holding `{term}` whose `.git` file points to a missing directory,
      fails with exit status 128 and git's error redacted.
  - The filter doesn't stop on bytes that aren't valid UTF-8, and a term
    written in Latin-1 on such a line is redacted.
  - `PYTHONPROFILEIMPORTTIME=1 uv run --offline scripts/pii-scan.py --redact-stream </dev/null`
    doesn't list `presidio` or `spacy`.
- A span two denylist entries both match is reported once, with the earlier
  entry's line, and an entry matching across lines (e.g., `{First}\s+{Other}`
  against `{First}`, a newline, and `{Other}`) reports the line of the
  scanned text where the match starts.
- A non-denylist finding still quotes its matched text (e.g.,
  `EMAIL_ADDRESS 1.00 "{address}"`), with a newline or carriage return in it
  written as `\n` or `\r` so the finding stays on one line; check this by
  calling `Finding.render(None)` on a finding whose text is `Jane\nRoe\r`,
  because Presidio's detectors rarely match across a line break.
- A denylist saved with a UTF-8 byte order mark matches its first entry: a
  staged file holding the line-1 term reports `(denylist line 1)`. Before the
  change, the mark joined the pattern and nothing matched.
- A commit's metadata findings keep their line numbers under
  `log.showSignature=true` (given to pii-scan.py's own git calls through
  `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=log.showSignature
  GIT_CONFIG_VALUE_0=true`). For an SSH-signed commit (a scratch key, with
  `gpg.format=ssh`, `user.signingkey`, and `gpg.ssh.allowedSignersFile` set in
  the scratch clone) whose message holds a scratch-denylist term on its body
  line, `--commit` reports the same line with and without the setting; before
  the change, the `Good "git" signature` line shifted it down by one.
- An unexpected exception in the scanner exits 2, not 1 (the status for
  findings), and prints `FATAL: pii-scan crashed: {type}` followed by a
  traceback on stderr. `--message-file {directory}` raises an
  `IsADirectoryError`, whose operating-system message is printed. With a
  temporary local patch (not committed) that raises a `ValueError`, a
  `regex` compile error, or a `RuntimeError` chained from a `KeyError`, each
  with a message read at run time from a scratch file holding `{term}(`, the
  FATAL line and every traceback entry give the type and location with the
  message withheld, and a case-insensitive grep of stderr doesn't find `{term}`.
  Through the `pre-commit` gate, the same patch applied to `--staged` alone
  stops the gate with that FATAL and exit status 2. A `KeyboardInterrupt`
  still exits 130, and an argparse usage error still exits 2 with its own
  message.
- The gate requires the remote argument in `pre-push` mode
  (`pii-and-secret-gate.sh pre-push REMOTE`, as the hook passes `$1`). It doesn't
  find any commits to scan for a branch deletion (40- or 64-digit all-zeros ID), and
  scans `remote..local` for an update. For a new branch, or a remote commit
  this repository doesn't have (e.g., the input line
  `refs/heads/main $(git rev-parse main) refs/heads/main 1234567890123456789012345678901234567890`),
  it scans every commit the destination remote's tracking refs don't hold, so
  a commit fetched only from a different remote is scanned.
- When the remote's push URLs differ from its fetch URL, a new branch's whole
  history is scanned, because the tracking refs describe the fetch URL's
  repository. With bare repositories `A.git` and `B.git`, fetch from `A.git`
  commits whose file and message hold a denylisted `{name}`, set
  `remote.origin.pushurl` to `B.git`, and feed the gate a pre-push line for a
  new branch built on them: `{name}` is reported, and the scan header shows
  `{tip} and its history`. A second `url` entry
  (`git remote set-url --add`) scans the whole history the same way. With
  `pushurl` unset, the same push scans only the new commit (the header shows
  `{tip}, without the {n} commit(s) origin's tracking refs name and their
  history`, one commit message examined).
- A remote whose name holds a space, configured with
  `git config 'remote.{a b}.url' {path of a bare repository}` (which
  `git remote add` refuses but `git remote` lists), still gets a gitleaks
  history pass for a new branch: a secret committed on the branch is reported
  by the `Secret scan: {tip} and its history` pass, not only by the exported
  pass. Its tracking refs can't hold the name: a `fetch` refspec naming
  `refs/remotes/{a b}/*` makes every remote command (`git remote` included)
  fail with `invalid refspec`, and `git update-ref 'refs/remotes/{a b}/main'`
  refuses the name. With a refspec writing elsewhere (e.g.,
  `+refs/heads/*:refs/remotes/{ab}/*`) and a fetch, the same push scans only
  the new commit. Before the change, the gate passed `--remotes={a b}` in
  `--log-opts`, gitleaks split it into two arguments, its `git log` failed,
  and the history pass didn't report anything and exited 0.
- A remote's tracking refs are the refs under `refs/remotes/` that its
  `remote.{name}.fetch` destinations match and no other remote's do, so a
  remote name holding `/` doesn't take another remote's refs. Configure
  remote `a` (`git remote add`) and remote `a/b` (`git config
  remote.a/b.url {url}` and `git config remote.a/b.fetch
  '+refs/heads/*:refs/remotes/a/b/*'`, since `git remote add` refuses a name
  that is a subset or superset of an existing one), fetch both, with a commit
  only `a/b` holds whose file and message hold a scratch-denylist term, and
  feed the gate a pre-push line for a new branch to `a` built on that commit:
  the term is reported in the file and in the commit metadata. Before the change, the
  `refs/remotes/a/` prefix matched `refs/remotes/a/b/*`, so the push excluded
  that commit and passed. A new branch to `a/b` scans `{tip} and its
  history`, because `a`'s refspec also covers `refs/remotes/a/b/*`. These
  scan only the new commit (`{tip}, without the 1 commit(s) {remote}'s
  tracking refs name and their history`): `origin` with its default
  refspec; remote `x` with only `+refs/heads/*:refs/remotes/mirror-x/*`
  (before the change, the whole history); and `x` with a negative refspec
  (`^refs/heads/{branch}`), one without a destination (`refs/heads/main`),
  and one with an empty destination (`refs/heads/main:`) added. A remote
  with only a `url` scans `{tip} and its history`, as does `x` once another
  remote's refspec writes into `refs/remotes/mirror-x/*`. A refspec with two
  `*` makes `git remote` fail with `invalid refspec`, and the gate stops.
- gitleaks exits 0 when its own `git log` fails, so the gate checks each
  `--log-opts` value first (`check_log_opts`): split on single spaces as
  gitleaks splits it, it must list exactly the commits the PII scan reads.
  With the value replaced for testing (e.g., in a scratch copy of the gate)
  by `no-such-ref`, by `{tip}  ^{id}` (two spaces, so gitleaks gets an empty
  argument), or by a valid range naming other commits (e.g., the tip alone
  where tracking refs exclude its parents), the gate stops with a FATAL
  before the history pass. Unchanged pushes still pass, with the same commits
  as before: a new branch to a remote with tracking refs (several refs naming
  one commit, e.g., `origin/HEAD` and `origin/main`, are listed once), a new
  branch pushed to a URL (the whole history), and an update
  (`{remote sha}..{tip}`).
- gitleaks' `pre-commit` pass also exits 0 when its own
  `git diff -U0 --no-ext-diff --staged .` fails or writes anything to stderr
  other than its rename-limit and auto-packing notices, so the gate runs that
  diff first (`check_staged_diff`). In a scratch repository with
  `*.{ext} diff={driver}` in `.gitattributes` and a staged `{file}.{ext}`, set
  `diff.{driver}.textconv` to a command that fails (git exits 128 with
  `unable to read files to diff`) or to one that prints a warning on stderr
  and succeeds: the gate stops with the FATAL counting git's stderr lines
  before the staged-changes pass. Before the change, with the warning-only textconv and a
  gitleaks test token staged in another file, the staged-changes pass printed
  only `[git] {warning}` and didn't report any leaks, and only the exported pass
  found the token. Without a textconv, the same staged changes pass, and the
  token is reported by the staged-changes pass.
- The pre-push history pass has the same weakness: gitleaks'
  `git -C . log -p -U0 {log-opts}` honors textconv, while `check_log_opts`'
  `git rev-list` doesn't build a diff, so `check_log_opts` also runs gitleaks' git
  log first and applies the same rule (`check_gitleaks_git`). In a scratch
  repository whose commits are `{init}`, then `{token}` adding a gitleaks test
  token in `b.txt`, then `{dat}` adding `*.dat diff={driver}` in
  `.gitattributes` and an `a.dat`, run the pre-push form without `git push`
  (e.g., `printf 'refs/heads/main {dat} refs/heads/main {old}\n' |
  scripts/pii-and-secret-gate.sh pre-push {remote}`). With
  `diff.{driver}.textconv` set to a command that fails, or to one that prints
  a warning on stderr and succeeds, the gate stops with the FATAL counting
  git's stderr lines before the history pass, both for a new branch (`{old}` all zeros)
  and for an update from `{init}`. Before the change, the failing textconv
  made the history pass print only `[git] fatal: unable to read files to
  diff` and not report any leaks; with the warning-only textconv, the update's
  history pass (`{init}..{dat}`, where `b.txt` comes last in git log's output)
  printed only `[git] {warning}` and didn't report any leaks. Only the exported pass
  found the token. In the new-branch form, where the larger `{init}` diff
  comes last, the warning-only run still found the token, so whether the
  warning loses a finding depends on where the file falls in the output.
  Without a textconv, the history pass reports the token in both forms.
  Pushes without a token pass with the same scan lines as before: a new
  branch to a URL, an update, and a new branch to a remote whose tracking ref
  names `{init}`.
- An invalid local commit ID fails the gate instead of reporting nothing to
  scan.
- A gitleaks failure while scanning the control (e.g., a `gitleaks` script
  earlier on `PATH` that exits 2) fails the gate with an error rather than
  counting as a detection.
- With the PII scanner's dependencies already installed and no network, the
  gate still runs: the online `uv sync` fails and the `--offline` retry
  succeeds. With neither, the gate fails.
- A file whose name contains a newline is exported for gitleaks with a
  one-line `# source:` header, the newline written as `\n`.
- Under `sandbox-exec` on macOS and under `bwrap --unshare-net` on Linux, the
  control and the scan still run once dependencies are installed, and
  `--check-isolation` exits 0; run without a sandbox, it exits 1. On Linux
  without a working `bwrap`, the gate prints a warning and still scans.
- On macOS, `--check-isolation` exits 1 inside Claude Code's sandboxed Bash,
  where 127.0.0.1:1 is denied but the proxy in `HTTPS_PROXY` accepts a
  connection, and exits 0 under the gate's own `sandbox-exec` profile with
  `HTTPS_PROXY`, `ALL_PROXY`, and `http_proxy` set to local and unresolvable
  proxies (e.g., `http://127.0.0.1:{port}`, `socks5://proxy.example.invalid:1080`,
  `127.0.0.1:3128`). `--check-sandboxed` exits 0 inside either sandbox and 1
  without one.
- The gate's macOS branches, each run as `pre-commit` in a scratch repository
  holding copies of `scripts/pii-scan.py`, the gate, the allowlist, and the
  control fixtures, with a staged file and `PII_SCAN_DENYLIST=none`. Inside a
  sandbox uv can't lock its cache, so those runs put a `uv` shim first on
  `PATH` that treats `sync` as a no-op and runs `run --quiet --offline
  {script} {args}` with the interpreter of the scanner's existing uv
  environment; the gate's own logic runs unchanged.
  - Unsandboxed, with the real `uv`: the `sandbox-exec` probe succeeds,
    `--check-isolation` prints `network isolated` under it, and the scan
    passes.
  - From Claude Code's sandboxed Bash: the probe exits 71,
    `--check-sandboxed` reports the process sandboxed, `--check-isolation`
    fails because of the proxy, and the gate stops with the FATAL telling the
    user to commit or push from a shell outside that sandbox.
  - Under an outer `sandbox-exec` started from an unsandboxed shell with
    `(version 1)(deny default)` and every operation class allowed except
    `network*` (`file*`, `process*`, `mach*`, `sysctl*`, `signal`, `ipc*`,
    `iokit*`, `system*`, `user-preference*`, `pseudo-tty`): the probe exits
    71, `--check-sandboxed` and `--check-isolation` both pass, the gate prints
    that an outer sandbox removes network access, and the control and scan
    run and pass. An outer profile of `(allow default)(deny network*)` doesn't
    reproduce this, because `sandbox-exec` does start inside it. Adding
    `(allow network*)` to the outer profile makes the gate stop with the same
    FATAL as in Claude Code's sandbox.
  - Unsandboxed, with a `sandbox-exec` shim earlier on `PATH` that prints an
    error and exits 1: `--check-sandboxed` reports the process not sandboxed,
    and the gate stops with `FATAL: sandbox-exec failed to start (exit 1:
    {its first stderr line})` without scanning. A `uv` shim that makes
    `--check-sandboxed` exit 2 stops the gate with the same FATAL.
- A staged file longer than spaCy's default `nlp.max_length` (1,000,000
  characters; e.g., 1.3 MB of filler lines) passes the `pre-commit` gate
  rather than failing with spaCy's error `E088`, because a text longer than
  `CHUNK_SIZE` is analyzed in overlapping chunks. In a 150,000-character file
  of filler lines with invented two-word names (each in a sentence such as
  `Yesterday {First} {Surname} called.`) whose space falls at index 49,000
  (the second chunk's start), 49,200 (inside the overlap), 49,500 (the
  overlap's midpoint), 50,000 (the first chunk's end), 98,000, and 99,000,
  each name is reported once, on the same line an unchunked scan of the same
  file reports (compare with the scanner before chunking, which analyzes a
  file this size whole).
- A submodule (added with
  `git -c protocol.file.allow=always submodule add {absolute path of a scratch repository} vendor/{name}`),
  whose entry records a commit this repository doesn't have, is scanned
  rather than failing in `pre-commit`, `pre-push`, and `--rev HEAD`: its
  path is scanned and its commit isn't read. With a scratch denylist holding
  `{name}`, each form reports `(path) vendor/{name}` and both lines of
  `.gitmodules`, which is scanned as a file; with a name the denylist doesn't
  hold, each passes.
- A submodule pointer change is scanned when settings tell git to ignore
  submodules. With a scratch denylist holding `{name}` and a committed
  gitlink at `vendor/{name}-lib` (e.g., made with
  `git update-index --add --cacheinfo 160000,{commit},vendor/{name}-lib`),
  stage a new pointer and set `diff.ignoreSubmodules=all`: `pre-commit`
  reports `staged:(path) vendor/{name}-lib` rather than exiting at its
  "nothing staged" check. With `submodule.{submodule}.ignore=all` instead and
  another file staged, `--staged` still lists the gitlink. After committing
  the pointer change, an uncommitted `ignore = all` in the working tree's
  `.gitmodules` doesn't hide it from `pre-push` (`git diff-tree` honors that
  setting, though not `diff.ignoreSubmodules`): the update reports
  `(path) vendor/{name}-lib`.
- A staged file whose name looks like a merge stage (e.g., `1:foo`, which
  git reads in `:1:foo` as stage 1 of `foo`) holding an invented
  `{First} {Surname}` is reported as `staged:1:foo:1: PERSON`, in
  `--staged` mode and through the `pre-commit` gate, rather than failing,
  because the index is read as `:0:{path}`. The staged allowlist is read the
  same way: an entry for that name scoped to `1:foo` suppresses it once
  staged, and not before.
- An annotated tag whose message is over 200 KB (more than a pipe's buffer),
  pushed as a new tag (the `pre-push` line
  `refs/tags/{tag} {tag object ID} refs/tags/{tag} {all-zeros ID}`, with
  SIGPIPE ignored as Git runs hooks), is peeled and scanned rather than
  stopping the gate with exit status 141: a scratch-denylist term on the
  message's last line is reported as `{tag}:(tag metadata):{line}`, and the
  same message without it passes. A tag of that tag is scanned as two tag
  messages.

## CI Workflow Smoke Tests

Use `act push` to catch workflow issues before pushing:

```bash
act push
```

This repository includes `.actrc` so `act` uses an Ubuntu image with the tools
expected by `.github/workflows/release.yml`. The container architecture is not
pinned, so the job runs natively on the host: amd64 on an Intel machine, arm64
on Apple Silicon. `release.yml` picks its ShellCheck and dasel downloads from
`uname -m`, so both architectures get working binaries.

Do not add `--container-architecture linux/amd64` back to run an arm64 host's
job as amd64. Under the resulting emulation the Bun-compiled Claude Code
installer that `install-and-verify.sh` fetches dies with SIGSEGV, so the job
fails at the "Install and verify plugins" step for a reason unrelated to the
change under test.

`act push` is not a perfect recreation of GitHub Actions. Treat it as a local
smoke test for the workflow, not as a proof that GitHub Actions will behave
identically. Two known divergences: the release-publishing step is skipped under
`act` because the workflow guards it with `if: ${{ !env.ACT }}`, and the job
occasionally exits 137 with act reporting `no such container` during cleanup.
That exit is a container-lifecycle failure, not a workflow failure; re-run
before investigating it.

## Script Tests

Use temporary directories for scripts that mutate Claude Code configuration or
other user state; never aim test runs at `~/.claude/settings.json`.

### `extras/harden-claude-config.sh`

The script edits Claude Code settings files. Test it only against temporary
files:

```bash
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

printf '{"env":{"KEEP":"yes"}}\n' > "$cfg"
./extras/harden-claude-config.sh --write --no-backup "$cfg"
jq -S . "$cfg"
```

Cover these regression cases when changing the script:

- Normal merge preserves unrelated top-level keys and unrelated `.env` entries.
- Base hardening writes `attribution.commit=""`, `attribution.pr=""`, and
  `attribution.sessionUrl=false`.
- `--allow-model-attribution` removes the `attribution.commit` and
  `attribution.pr` overrides while keeping `attribution.sessionUrl=false`.
- `--allow-session-attribution` removes only the session URL override; when
  combined with `--allow-model-attribution`, the managed `attribution` object
  is removed entirely.
- `--allow-only-plugin-updates` keeps `DISABLE_AUTOUPDATER=1` even when
  combined with `--allow-updates`, and writes `FORCE_AUTOUPDATE_PLUGINS=1`.
- `--disable-nonessential-traffic` wins after `--allow-updates` and
  `--allow-feedback`, while `--allow-only-plugin-updates` still writes
  `FORCE_AUTOUPDATE_PLUGINS=1`. WebFetch preflight remains controlled by
  `--allow-webfetch-preflight`, matching Claude Code's separate WebFetch
  preflight setting.
- Base hardening writes `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, adds the managed
  `sandbox.credentials` entries (`files` by path, `envVars` by name), and keeps
  hand-added sibling `sandbox` keys such as `excludedCommands`. A user's own
  credentials entries (e.g., `~/.kube`, `GITHUB_TOKEN`) are kept; an entry for
  a managed path or name with another mode (e.g., `~/.ssh` `allow`, or
  `AWS_ACCESS_KEY_ID` `mask` with `injectHosts`) keeps its position and its
  other fields, gets `mode: "deny"`, and shows in the preview as
  `~ AWS_ACCESS_KEY_ID: mask -> deny`; a managed-path entry already set to
  `deny` with an extra field shows as `=`; a rerun doesn't change anything. A
  file that holds every managed entry with a user entry placed between two of
  them is a no-op under `--write` (no rewrite, no backup), so the merge doesn't
  reorder entries. `--disable-sandbox` leaves an existing credentials block as it is
  and doesn't create one. A non-object `credentials` or a non-array `files` or
  `envVars` is rejected with a clear error.
- The `envVars` deny list names exactly the variables in
  `extras/harden-codex-config.sh`'s `CREDENTIAL_ENV_VARS`, so both scripts
  strip the same credentials. Compare them when changing either list:

  ```bash
  diff <(grep -o '"name": "[A-Z_]*"' extras/harden-claude-config.sh | cut -d'"' -f4 | sort) \
       <(sed -n '/^CREDENTIAL_ENV_VARS = (/,/^)$/p' extras/harden-codex-config.sh \
           | grep -v '^ *#' | grep -o '"[A-Z_]*"' | tr -d '"' | sort)
  ```
- Base hardening adds the five cloud metadata endpoints to
  `sandbox.network.deniedDomains`, keeping existing `allowedDomains` and
  `deniedDomains` entries; a rerun doesn't add duplicates.
- `--allow-metadata-endpoints` removes only those five entries, keeps entries
  the user added, and doesn't create a `network` block in a file that has none.
- `--allow-cloud-credential-files` removes the `deny` entries for `~/.aws`,
  `~/.config/gcloud`, and `~/.azure` from `sandbox.credentials.files` (the
  preview shows each as `-`), keeps `~/.ssh`, `~/.gnupg`, `~/.netrc`, and the
  user's own entries, and a later base run adds them back.
- A non-object `.sandbox.network` or non-array `deniedDomains` is rejected with
  a clear error.
- `--allow-feature-flags` deletes `DISABLE_TELEMETRY` (setting it to `"0"`
  would still opt out) and writes `DO_NOT_TRACK=0`; the preview reports the
  deletion as a `-` line. Run after `--disable-nonessential-traffic`, it also
  deletes `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`. Run from a shell that
  exports either variable (e.g., `DISABLE_TELEMETRY=1 ./extras/...`), it warns
  on stderr; without the flag, or with neither variable set, it doesn't.
- `--dnt-prefix PATH` writes `CLAUDE_CODE_SHELL_PREFIX` verbatim, including a
  path with spaces, and is rejected without `--allow-feature-flags`, with a
  relative path, with an empty value (`--dnt-prefix=""`), or when the target
  isn't an executable file. A target inside a git working tree (e.g., the
  checkout's `extras/claude-dnt-prefix.sh`) prints a warning on stderr, and so
  does a symlink outside any working tree that resolves to that file, directly
  or through a chain of links; a copy outside any working tree, and a symlink
  to such a copy, don't. Check the symlink cases with GNU coreutils first on
  `PATH` too.
- `--allow-feature-flags` with `--disable-nonessential-traffic` is rejected.
- `--allow-subprocess-credentials` writes `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=0`.
- A top-level non-object JSON value, e.g., `[]`, is rejected with a clear error.
- A non-object `.env` value is rejected with a clear error.
- A symlinked settings path updates the target file and preserves the symlink.
- A symlink chain updates the final target file and preserves every symlink in
  the chain.
- A dangling symlinked settings path creates the missing target file and
  preserves the symlink.
- A second write against an already-hardened file is a semantic no-op and does
  not create a backup.
- Existing file mode is preserved on a changing write.
- Directory and unreadable-file targets are rejected with a clear error.

Useful focused probes:

```bash
# Top-level non-object rejection.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"
printf '[]\n' > "$cfg"
./extras/harden-claude-config.sh --write --no-backup "$cfg"
```

```bash
# Dangling symlink creation without replacing the link.
tmpdir="$(mktemp -d)"
target="$tmpdir/missing.json"
link="$tmpdir/settings.json"
ln -s "$target" "$link"

./extras/harden-claude-config.sh --write --no-backup "$link"
test -L "$link"
test -e "$target"
jq -S . "$target"
```

```bash
# Plugin-only updates should override --allow-updates for the binary updater.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-updates \
  --allow-only-plugin-updates \
  "$cfg"

jq -S '.env | {
  DISABLE_AUTOUPDATER,
  FORCE_AUTOUPDATE_PLUGINS
}' "$cfg"
```

```bash
# Nonessential traffic should re-pin relaxed optional channels.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-updates \
  --allow-feedback \
  --allow-webfetch-preflight \
  --allow-only-plugin-updates \
  --disable-nonessential-traffic \
  "$cfg"

jq -S '.env | {
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC,
  DISABLE_AUTOUPDATER,
  DISABLE_FEEDBACK_COMMAND,
  CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY,
  FORCE_AUTOUPDATE_PLUGINS
}' "$cfg"
jq -e '.skipWebFetchPreflight == false' "$cfg"
```

```bash
# Model/tool attribution can be allowed while session URL attribution stays off.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-model-attribution \
  "$cfg"

jq -e '
  (.attribution | has("commit") | not)
  and (.attribution | has("pr") | not)
  and (.attribution.sessionUrl == false)
' "$cfg"
```

```bash
# Full attribution relaxation removes the managed attribution object.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-model-attribution \
  --allow-session-attribution \
  "$cfg"

jq -e 'has("attribution") | not' "$cfg"
```

```bash
# Feature flags: DISABLE_TELEMETRY is deleted, and the DNT prefix path keeps
# its spaces.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"
mkdir "$tmpdir/dir with space"
cp ./extras/claude-dnt-prefix.sh "$tmpdir/dir with space/prefix.sh"

./extras/harden-claude-config.sh --write --no-backup "$cfg"
./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-feature-flags \
  --dnt-prefix "$tmpdir/dir with space/prefix.sh" \
  "$cfg"

jq -e --arg p "$tmpdir/dir with space/prefix.sh" '
  (.env | has("DISABLE_TELEMETRY") | not)
  and (.env.DO_NOT_TRACK == "0")
  and (.env.CLAUDE_CODE_SHELL_PREFIX == $p)
' "$cfg"

# The wrapper restores DO_NOT_TRACK=1 for the command it runs.
DO_NOT_TRACK=0 "$tmpdir/dir with space/prefix.sh" 'test "$DO_NOT_TRACK" = 1'

# It re-runs the command under SHELL when that names bash or zsh, the shell
# Claude Code assembled the command for, and under /bin/bash otherwise
# (e.g., fish, unset, or a path that doesn't exist).
SHELL="$(command -v zsh)" "$tmpdir/dir with space/prefix.sh" 'test -n "$ZSH_VERSION"'
SHELL="$(command -v bash)" "$tmpdir/dir with space/prefix.sh" 'test -n "$BASH_VERSION"'
SHELL=/usr/bin/fish "$tmpdir/dir with space/prefix.sh" 'test -n "$BASH_VERSION"'
SHELL=/nonexistent/zsh "$tmpdir/dir with space/prefix.sh" 'test -n "$BASH_VERSION"'
env -u SHELL "$tmpdir/dir with space/prefix.sh" 'test -n "$BASH_VERSION"'

# Any argument count other than one is refused (exit 2) rather than dropping
# arguments.
"$tmpdir/dir with space/prefix.sh" true extra; test $? -eq 2
"$tmpdir/dir with space/prefix.sh"; test $? -eq 2
```

### `extras/harden-codex-config.sh`

The script edits Codex TOML configuration files. Test it only against temporary
files:

```bash
tmpdir="$(mktemp -d)"
cfg="$tmpdir/config.toml"

printf 'model = "gpt-5.5"\n\n[analytics]\nenabled = true\n' > "$cfg"
./extras/harden-codex-config.sh --write --no-backup "$cfg"
./extras/harden-codex-config.sh --write --no-backup "$cfg"
```

Cover these regression cases when changing the script:

- Normal merge preserves unrelated keys, including MCP server configuration and
  plugin settings.
- Empty arrays are preserved, including `args = []` under an MCP server.
- Written files semantically round-trip: parse the written TOML and compare it
  with the intended merged data.
- Base hardening writes `sandbox_mode="read-only"`,
  `approval_policy="on-request"`, `web_search="disabled"`,
  `analytics.enabled=false`, `feedback.enabled=false`, OTel exporters set to
  `"none"`, and `otel.log_user_prompt=false`.
- Base hardening writes `shell_environment_policy.inherit="core"` and keeps
  `shell_environment_policy.ignore_default_excludes=false` so spawned command
  environments remain filtered for likely secrets.
- Base hardening writes `features.apps=false`,
  `features.codex_git_commit=false`, and `features.memories=false`.
- Base hardening writes `features.shell_snapshot=false` (openai/codex#22124)
  and prints a note on stderr about tools found only through shell startup
  files when it changes the setting; a rerun on an already-hardened config
  doesn't print a note. `--allow-shell-snapshot` writes `true`. `codex features list`
  with that config as `CODEX_HOME` reports `shell_snapshot` as `false`.
- Base hardening writes the credential names as
  `shell_environment_policy.filters` entries, or into a legacy `exclude` array
  when the config already has `exclude` or `include_only`; Codex loads each
  result. A config mixing `filters` with either legacy array, or a legacy
  value that isn't a list of strings, stops the script with an error naming
  the key. A credential name in `shell_environment_policy.set` (any case) is
  removed, the preview shows the removal without the value, and other `set`
  entries stay.
- Base hardening writes `cli_auth_credentials_store="keyring"`;
  `--allow-file-credentials` writes `"auto"` instead. With an `auth.json` next
  to the target and keyring storage selected, the script warns on stderr.
- Base hardening writes
  `plugins."unified-computer-use@openai-bundled".enabled=false` and removes a
  `notify` command that runs `SkyComputerUseClient`, but keeps any other
  `notify` command; `--allow-computer-use` writes `enabled=true` and leaves
  `notify` alone. A second run is a no-op. The client is recognized by its
  file name, directly, behind `/usr/bin/env` with options and assignments, and
  inside `sh -c`. A shell running a script (e.g., `bash notify.sh`) is kept
  without a warning; a program whose name only contains the client's (e.g.,
  `SkyComputerUseClient-status-reporter`) is kept,
  with a warning on stderr.
- `--allow-workspace-write`, `--allow-network`, `--allow-web-search`,
  `--allow-live-web-search`, `--allow-login-shell`, `--allow-updates`,
  `--allow-feedback`, `--allow-analytics`, `--allow-otel-metrics`,
  `--allow-apps`, `--allow-codex-git-commit`, and `--allow-memories` write
  explicit relaxed values.
- A managed path that collides with a non-table value, e.g.,
  `analytics = true`, is rejected with a clear error.
- Invalid TOML is rejected with a clear error.
- Directory and unreadable-file targets are rejected with a clear error rather
  than a traceback.
- A symlinked config path updates the target file and preserves the symlink.
- A dangling symlinked config path creates the missing target file and
  preserves the symlink.
- A second write against an already-hardened file is a semantic no-op and does
  not create a backup.
- The default target respects `CODEX_HOME`.
- TOML date, time, datetime, and empty-list values remain valid after a write.
- Comments and formatting are not preserved on a write that changes values.
