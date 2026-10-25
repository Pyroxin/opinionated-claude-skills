# /// script
# requires-python = ">=3.10,<3.15"
# dependencies = [
#     "presidio-analyzer>=2.2.365",
#     "regex>=2023.0.0",
#     "tldextract>=5.4",
#     "en-core-web-lg @ https://github.com/explosion/spacy-models/releases/download/en_core_web_lg-3.8.0/en_core_web_lg-3.8.0-py3-none-any.whl",
# ]
# ///
"""Scan repository content for personal data before it is published.

Detects credit card numbers, US social security and taxpayer numbers, email
addresses, phone numbers, IBANs, and person names with Presidio
(https://github.com/data-privacy-stack/presidio), which combines patterns,
checksums, and context with a spaCy named-entity model. Analysis runs on this
machine. The script doesn't make network requests of its own and disables
tldextract's Public Suffix List download; the gate also runs it without
network access where the platform allows.

Run it with ``uv run scripts/pii-scan.py``; uv supplies a compatible Python and
the dependencies declared above from its cache. Modes:

- ``--rev REV`` scans every tracked file as it is at ``REV``.
- ``--staged`` scans the files staged for the next commit, as they are in the
  index rather than the working tree, so the pre-commit hook checks exactly
  what the commit will record.
- ``--commit SHA`` (repeatable) scans, for each commit, the files that commit
  added, copied, modified, renamed, or type-changed, as they are in that
  commit, and the commit's author, committer, and message, plus the tagger and
  message of any signed tag a merge commit embeds. A pushed commit
  stays retrievable by its own hash, so each one must be clean on its own,
  not only the branch tip.
- ``--tag SHA`` (repeatable) scans an annotated tag object's name, tagger,
  and message, which a push publishes along with the commit it points at.
- ``--ref NAME`` (repeatable) scans a ref name as it will appear on the
  remote (e.g., ``refs/heads/topic``). ``--commit``, ``--tag``, and ``--ref``
  combine, so the pre-push hook scans everything one pushed ref publishes in
  one run.
- ``--message-file PATH`` scans a commit message and the author and committer
  identities Git will record, for the commit-msg hook.
- ``--control`` scans the positive-control fixture and fails unless every
  entity type the scan checks is detected in it, so a clean result elsewhere
  means the detectors responded rather than silently failing to match.
- ``--check-isolation`` exits 0 only when this process doesn't have network
  access, so the gate can confirm its sandbox took effect before scanning. On
  macOS a reachable proxy named in the environment (e.g., ``HTTPS_PROXY``)
  counts as network access (see :func:`network_isolated`).
- ``--check-sandboxed`` (macOS only) exits 0 when this process already runs
  inside a Seatbelt sandbox, 1 when it doesn't, and 2 when it can't tell. The
  gate asks this when ``sandbox-exec`` fails to start, because macOS doesn't
  let it start inside another sandbox (e.g., Claude Code's sandboxed Bash).
- ``--redact-stream`` copies stdin to stdout line by line, with each
  denylist term replaced as in a label (see below and :func:`redact_stream`).
  The commit and push hooks pipe everything they print through it (see
  ``scripts/git-hooks/run-redacted.sh``). It doesn't import Presidio, so it
  starts in a fraction of a second. It exits 2 when the denylist is missing,
  empty, or unusable, when a pattern can't finish on a line, when a line is
  longer than ``MAX_STREAM_LINE`` bytes, and on any unexpected error; the rest
  of the input is then not written. Its messages don't name a path (a denylist
  entry is named by line number only) and don't print a traceback, and the known
  limits of its matching are listed at :func:`redact_stream`.

Every file mode also scans the paths themselves, because a filename is
published as much as the file's content.

``--export-to DIR`` changes what a scan does: instead of analyzing, it writes
every text the scan would analyze (each decoding of each file, the paths, and
any commit, tag, or ref text) into ``DIR``, so the gate can run gitleaks over
the same content the PII scan sees (see ``export_texts``).

Findings matched by the allowlist (``scripts/presidio-pii-allowlist.tsv``) are
suppressed. The allowlist is read as committed, not from the working tree, so
an uncommitted edit to it can't approve content: ``--staged`` and
``--message-file`` read the version staged in the index; ``--rev`` reads the
version at that revision; ``--commit``, ``--tag``, and ``--ref`` read the
version at ``--allowlist-rev`` (default ``HEAD``), which the pre-push hook sets
to the tip of the ref being pushed, so a push is judged by the allowlist it
publishes. ``--allowlist PATH`` reads a file instead, for testing an edit
before staging it. Exit status: 0 when nothing unallowed is found, 1 when
something is, 2 on a usage or environment error or a crash (an unexpected
exception, reported as ``FATAL: pii-scan crashed: {type}`` without its
message unless that message can't quote scanned text or a denylist pattern;
see :func:`run`).

A private denylist adds terms that are always reported, read from
``$PII_SCAN_DENYLIST`` or ``~/.config/pii-scan/denylist.txt``. It lives
outside the repository because a committed list of private names would
publish them. A scan stops with exit status 2 when that file is missing or
doesn't have any term patterns, unless ``PII_SCAN_DENYLIST`` is ``none``, which runs it
without a denylist (e.g., for a contributor who doesn't keep one). Each line is a
regular expression in the syntax of the ``regex`` module
(https://pypi.org/project/regex/), matched without regard to case and
anywhere in the text, so a whole word is written with ``\\b`` (e.g.,
``\\bAl\\b``); see :func:`load_denylist` for the rest of the format. An entry
that doesn't compile, that matches an empty string, or that runs longer than
``DENYLIST_TIMEOUT`` stops the scan with exit status 2, and the message names
the entry by line number, never by its text, so the terms stay out of logs and
transcripts.

Each finding is printed as one line: its source label, the line of the
scanned text it's on, its entity type and score, and its matched text in
quotes (e.g., ``staged:notes/x.md:4: EMAIL_ADDRESS 1.00 "{address}"``),
with a newline or carriage return in the text written as ``\\n`` or ``\\r``.
A denylist finding gives the line of the denylist entry that matched instead
of its text (e.g., ``staged:notes/x.md:4: DENYLIST 1.00 (denylist line 7)``).
Gate output lands in LLM agent transcripts, and a private term sent in a model
request can trip the model's safety checks and derail the session that's
running the scan, so no denylist term is printed anywhere. Any other finding
whose match overlaps a term (e.g., an ``EMAIL_ADDRESS`` whose local part is
the term) is shown the same way, with its entity type and score but not its
text. A source label (a path, a ``(path)`` text, or a ref or tag name) is
printed with each term match inside it replaced by the entry's line (e.g.,
``staged:notes/[denylist line 7]_list.md:4``), so the rest of the label still
locates the file to rename. Terms an exception phrase excuses are hidden too:
the exception decides what may be published, not what may be printed. The
hooks also pass their whole output through ``--redact-stream``, which catches
text this script doesn't print (e.g., gitleaks' and git's own messages); a
script run by hand, outside the hooks, isn't filtered that way.

``--gitleaks-report REPORT`` prints the findings in a gitleaks JSON report
the same way, giving each one's rule, location, and commit and nothing else,
so the gate never has to print gitleaks' own report; with ``--exported DIR``,
a finding in a text exported to ``DIR`` is located by that text's label.
"""

from __future__ import annotations

import argparse
import csv
import ctypes
import fnmatch
import io
import json
import os
import re
import socket
import subprocess
import sys
import time
import traceback
import urllib.parse
import urllib.request
from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, BinaryIO

import regex

# Presidio validates email domains with tldextract, whose default extractor
# downloads the Public Suffix List on first use. An empty
# TLDEXTRACT_PUBLIC_SUFFIX_LIST_URLS makes it use the snapshot bundled with the
# package instead; it must be set before tldextract is first imported, which
# happens when Presidio is (tldextract's README, "Or set the default for new
# extractors with an empty environment variable"). It's assigned rather than
# defaulted so a value inherited from the environment can't re-enable the
# download. The dependency floor above is the version this was verified with.
os.environ["TLDEXTRACT_PUBLIC_SUFFIX_LIST_URLS"] = ""

# Presidio is imported where an analyzer is built (see analyzer_engine), not
# here: importing it loads spaCy and takes about a second, and
# --redact-stream, which filters the output of every commit and push hook,
# doesn't need either. Annotations are postponed (the __future__ import above), so
# the names below are only needed by type checkers.
if TYPE_CHECKING:
    from presidio_analyzer import AnalyzerEngine, RecognizerResult

REPO_ROOT = Path(__file__).resolve().parent.parent
ALLOWLIST_PATH = "scripts/presidio-pii-allowlist.tsv"
DEFAULT_DENYLIST = Path.home() / ".config" / "pii-scan" / "denylist.txt"
# The PII_SCAN_DENYLIST value that runs the scan without a denylist.
DENYLIST_OPT_OUT = "none"
CONTROL_FIXTURE = REPO_ROOT / "scripts" / "validator-fixtures" / "pii-control.md"
CONTROL_DENYLIST = REPO_ROOT / "scripts" / "validator-fixtures" / "pii-control-denylist.txt"
CONTROL_EXPECTED = REPO_ROOT / "scripts" / "validator-fixtures" / "pii-control.expected"

# Entity label for denylist matches; not a Presidio entity type.
DENYLIST_ENTITY = "DENYLIST"

# The forms of a person's name that a PERSON match is checked against, one for
# cased scripts (e.g., Latin, Greek, Cyrillic) and one for scripts without
# case (e.g., Han, kana, Hangul, Arabic, Hebrew). Letter classes are Unicode
# properties.
#
# A cased name is two or more capitalized words separated by single spaces.
# Any word but the last may instead be initials, written spaced (``J. R.``) or
# run together (``J.R.``), and words between the first and last may be short
# lowercase particles (e.g., ``de la``). The name may end in a generational or
# academic suffix. The suffixes are listed rather than matched by shape (e.g.,
# any capitalized word ending in a period), so a sentence's next word or an
# abbreviation isn't taken for part of a name. Forms Presidio reports that
# don't fit, such as ``Smith, John``, all-lowercase names, and words separated
# by two spaces, are discarded, because in this repository they're more often
# code or prose than names.
_CASED_WORD = r"\p{Lu}[\p{L}\p{M}'’-]*"
_INITIALS = r"(?:\p{Lu}\.)+"
NAME_SUFFIXES = ("Jr.", "Jr", "Sr.", "Sr", "II", "III", "IV", "PhD", "MD")
CASED_NAME = regex.compile(
    rf"(?:{_CASED_WORD}|{_INITIALS})"
    rf"(?: (?:{_CASED_WORD}|{_INITIALS}|\p{{Ll}}{{1,3}}))*"
    rf" {_CASED_WORD}"
    rf"(?: (?:{'|'.join(regex.escape(suffix) for suffix in NAME_SUFFIXES)}))?"
)
UNCASED_NAME = regex.compile(r"[\p{Lo}\p{M}]+(?:[ ·・][\p{Lo}\p{M}]+)*")
POSSESSIVE = re.compile(r"(?:'s|’s|'|’)$")


def looks_like_name(text: str) -> bool:
    """Report whether a PERSON match has the form of a person's name."""
    if CASED_NAME.fullmatch(text):
        return True
    return bool(UNCASED_NAME.fullmatch(text)) and len(regex.findall(r"\p{Lo}", text)) >= 2


ENTITIES = [
    "CREDIT_CARD",
    "US_SSN",
    "US_ITIN",
    "EMAIL_ADDRESS",
    "PHONE_NUMBER",
    "IBAN_CODE",
    "PERSON",
]

DEFAULT_MIN_SCORE = 0.4


def printable(text: str) -> str:
    """Return ``text`` safe to print.

    Paths and messages that aren't valid UTF-8 are decoded with
    ``surrogateescape``, and printing a lone surrogate raises; this shows each
    one as an escape instead.
    """
    return text.encode("utf-8", "backslashreplace").decode("utf-8")


def one_line(text: str) -> str:
    """Return ``text`` safe to print on one line: :func:`printable`, with a
    newline or carriage return written as ``\\n`` or ``\\r``, since a
    filename can hold either.
    """
    return printable(text).replace("\n", "\\n").replace("\r", "\\r")


@dataclass(frozen=True, slots=True)
class Finding:
    """One detected entity in one file.

    :ivar source: Where the text came from: a path, or ``commit:path``.
    :ivar path: Repository-relative path, used for allowlist path globs.
    :ivar line: 1-based line number of the match in the scanned text.
    :ivar entity: Presidio entity type, e.g., ``EMAIL_ADDRESS``.
    :ivar text: The matched text. Kept for denylist findings too, because
        deduplication and the allowlist compare it, but never printed when
        ``denylist_line`` is set (see :meth:`render`).
    :ivar score: Presidio's confidence score, 0 to 1.
    :ivar quoted: True when the finding is the allowlist quoting one of its own
        entries (see :func:`quotes_own_entry`).
    :ivar denylist_line: The 1-based line of the denylist entry that matched,
        for a denylist finding, or of the first term entry whose match the
        finding overlaps, for any other; ``None`` when it doesn't overlap any.
    """

    source: str
    path: str
    line: int
    entity: str
    text: str
    score: float
    quoted: bool = False
    denylist_line: int | None = None

    def render(self, denylist: "Denylist | None") -> str:
        """Format the finding as one report line.

        A finding with a ``denylist_line`` names that denylist entry's line
        instead of quoting the match, because the match is or holds a private
        term and this output is read by LLM agents (see the module
        docstring). Any other match is quoted with ``\\n`` and ``\\r``
        escaped (see :func:`one_line`), so a match a regular expression found
        across lines still prints as one line. The label is escaped the same
        way, then redacted (see :func:`redact`). Redaction and the check of
        the quoted text run on the escaped forms, because those are what's
        printed, and escaping can make a term appear (e.g., ``\\nx`` printed
        from a newline before ``x``).

        :raises DenylistError: If a term pattern can't finish on the label or
            the matched text.
        """
        hidden = self.denylist_line
        if hidden is None and denylist is not None:
            spans = denylist.term_spans(one_line(self.text))
            hidden = spans[0][2] if spans else None
        shown = f'"{one_line(self.text)}"' if hidden is None else f"(denylist line {hidden})"
        label = redact(one_line(self.source), denylist)
        return f"{label}:{self.line}: {self.entity} {self.score:.2f} {shown}"


@dataclass(frozen=True, slots=True)
class AllowRule:
    """An accepted finding: an entity type and exact text, optionally per path.

    :ivar entity: Entity type, or ``*`` for any type.
    :ivar text: Exact matched text, or ``*`` for any text.
    :ivar path_glob: ``fnmatch`` pattern for the path; ``*`` for any path.
    """

    entity: str
    text: str
    path_glob: str

    def allows(self, finding: Finding) -> bool:
        """Report whether this rule accepts ``finding``.

        Denylist findings are never accepted here: the allowlist is public, so
        an entry for a denylisted term would publish it. Only exception phrases
        in the private denylist itself excuse a denylist match.
        """
        if finding.entity == DENYLIST_ENTITY:
            return False
        return (
            self.entity in ("*", finding.entity)
            and self.text in ("*", finding.text)
            and fnmatch.fnmatchcase(finding.path, self.path_glob)
        )


@dataclass(frozen=True, slots=True)
class AllowlistRow:
    """One entry row of the allowlist and the lines it was read from.

    :ivar first_line: 1-based line the row starts on, counted as
        :func:`analyze` counts a finding's line.
    :ivar last_line: 1-based line the row ends on; later than ``first_line``
        only when a quoted field spans lines.
    :ivar fields: The row's fields as the csv module splits them.
    """

    first_line: int
    last_line: int
    fields: list[str]


def allowlist_rows(content: str) -> Iterator[AllowlistRow]:
    """Yield the allowlist's entry rows, skipping blank and comment rows.

    The loader (:func:`parse_allowlist`) and the self-quote check
    (:func:`quotes_own_entry`) both read the file through this, so they agree
    on quoting, on quoted fields that span lines, and on which rows are
    comments; e.g., a line ``"#x"<TAB>Jane Roe`` is a comment to both. A row
    is a comment when its first field, after csv unquoting, starts with ``#``,
    and blank when its first field is empty or whitespace.

    The csv module counts lines as ``io.StringIO`` with ``newline=""`` splits
    them, where a lone ``\\r`` also ends a line, while :func:`analyze` counts
    ``\\n`` only. So each physical line csv reads is mapped to the
    ``\\n``-counted line it starts on, which makes a row's range comparable
    with a finding's line. ``\\r\\n`` is one line under both counts.

    :param content: The allowlist's text.
    :raises csv.Error: If the csv module can't parse the text.
    """
    starts: list[int] = []

    def physical_lines() -> Iterator[str]:
        line = 1
        for piece in io.StringIO(content, newline=""):
            starts.append(line)
            # Each piece ends at its first line ending, so a "\n" can only be
            # its last character.
            if piece.endswith("\n"):
                line += 1
            yield piece

    reader = csv.reader(physical_lines(), delimiter="\t")
    read = 0
    for fields in reader:
        # line_num is the number of physical lines read so far, so this row
        # came from the lines after the previous row's last one through
        # line_num.
        first, read = read + 1, reader.line_num
        if not fields or not fields[0].strip() or fields[0].startswith("#"):
            continue
        yield AllowlistRow(starts[min(first, read) - 1], starts[read - 1], fields)


def parse_allowlist(content: str, origin: str) -> list[AllowRule]:
    """Read allow rules from tab-separated text.

    Each row (see :func:`allowlist_rows`) holds an entity type, the exact
    matched text, and an optional path glob, separated by tabs. A rule whose
    text is ``*`` must name a path glob other than ``*``: without one it turns
    off detection of its entity type (or, with entity ``*``, of everything) in
    every path, which no single accepted finding justifies.

    :param content: The allowlist's text.
    :param origin: Where the text came from, for error messages.
    :returns: The rules in file order.
    :raises ValueError: If a row has fewer than two fields, or is a ``*`` text
        rule without a path glob.
    """
    rules: list[AllowRule] = []
    for row in allowlist_rows(content):
        fields = row.fields
        if len(fields) < 2:
            raise ValueError(f"{origin}:{row.first_line}: expected ENTITY<TAB>TEXT[<TAB>PATH_GLOB]")
        glob = fields[2] if len(fields) > 2 and fields[2] else "*"
        if fields[1] == "*" and glob == "*":
            raise ValueError(f'{origin}:{row.first_line}: a "*" TEXT needs a PATH_GLOB other than "*", '
                             "or the rule accepts every such finding in every path")
        rules.append(AllowRule(entity=fields[0], text=fields[1], path_glob=glob))
    return rules


def object_spec(rev: str, path: str) -> str:
    """Return the git object name for ``path`` at a revision, or in the index.

    The index is named with its stage number, ``:0:{path}``, rather than as
    ``:{path}``, because git reads ``:{n}:{rest}`` as stage ``n`` of
    ``rest``, so a file named ``1:foo`` would otherwise name stage 1 of
    ``foo``, which a commit's index doesn't hold.

    :param rev: A revision; the empty string means the index.
    """
    return f":0:{path}" if rev == "" else f"{rev}:{path}"


def load_allowlist_at(rev: str) -> list[AllowRule]:
    """Read the allowlist as recorded at a revision, or in the index.

    :param rev: A revision; the empty string means the index.
    :returns: The rules, or none when the allowlist isn't recorded there.
    """
    spec = object_spec(rev, ALLOWLIST_PATH)
    exists = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "cat-file", "-e", spec], capture_output=True,
    ).returncode == 0
    if not exists:
        return []
    return parse_allowlist(git("show", spec), spec)


def git_bytes(*args: str) -> bytes:
    """Run a git command in the repository and return its standard output.

    :param args: Arguments after ``git``.
    :raises subprocess.CalledProcessError: If git exits non-zero.
    """
    return subprocess.run(
        ["git", "-C", str(REPO_ROOT), *args],
        check=True,
        capture_output=True,
    ).stdout


def git(*args: str) -> str:
    """Run a git command and return its output as text.

    Decoded with ``surrogateescape``, so a path or message that isn't valid
    UTF-8 keeps its exact bytes: passing such a path back to git (which
    subprocess encodes with the same handler) names the same file.
    """
    return git_bytes(*args).decode("utf-8", "surrogateescape")


# The share of printable characters a UTF-16 decoding needs to be scanned, so
# binary content (e.g., an image) isn't passed to gitleaks' entropy rules as
# random-looking text.
MIN_PRINTABLE_SHARE = 0.9
UTF16_BOMS = (b"\xff\xfe", b"\xfe\xff")


def _mostly_printable(text: str) -> bool:
    if not text:
        return False
    shown = sum(1 for ch in text if ch.isprintable() or ch in "\t\n\r")
    return shown / len(text) >= MIN_PRINTABLE_SHARE


def decodings(raw: bytes) -> list[str]:
    """Return the texts to scan for a file's bytes.

    The UTF-8 reading is always one of them. Other likely decodings are added,
    because a term written in another encoding doesn't match in the UTF-8
    reading.
    """
    texts = [raw.decode("utf-8", errors="replace")]
    try:
        raw.decode("utf-8")
        valid_utf8 = True
    except UnicodeDecodeError:
        valid_utf8 = False
    if raw.startswith(UTF16_BOMS):
        texts.append(raw.decode("utf-16", errors="replace"))
    elif not valid_utf8 or b"\x00" in raw:
        for codec in ("utf-16-le", "utf-16-be"):
            text = raw.decode(codec, errors="replace")
            if _mostly_printable(text):
                texts.append(text)
    if not valid_utf8 and b"\x00" not in raw:
        texts.append(raw.decode("latin-1"))
    return texts


# Label used as the path of findings in commit metadata, so allowlist path
# globs can scope entries to it.
METADATA_PATH = "(commit metadata)"
TAG_PATH = "(tag metadata)"
REF_PATH = "(ref name)"
# The start of an exported text's first line, which names its source (see
# export_texts).
EXPORT_HEADER = "# source: "
IDENT_TIMESTAMP = re.compile(r" \d+ [+-]\d{4}$")
# A signature block, removed only when it ends the message and holds only
# armor: optional "Name: value" header lines, an optional blank line, and
# base64 lines. Any other text in or after such a block keeps the whole message
# in the scan. Header lines are free text (e.g., ``Comment: ...``), so
# strip_signature keeps them in the scanned text and removes only the BEGIN and
# END lines and the base64 payload.
SIGNATURE = re.compile(
    r"(?P<lead>\A|\n)-----BEGIN (?P<kind>[A-Z ]*SIGNATURE)-----\n"
    r"(?P<headers>(?:[A-Za-z][A-Za-z-]*: [^\n]*\n)*)\n?"
    r"(?:[A-Za-z0-9+/=]+\n)*"
    r"-----END (?P=kind)-----\n?\Z"
)


def strip_signature(message: str) -> str:
    """Return ``message`` without a trailing armored signature block (see
    ``SIGNATURE``), keeping the block's header lines.
    """
    return SIGNATURE.sub(lambda m: m["lead"] + m["headers"] if m["headers"] else "", message)


def commit_metadata(commit: str) -> str:
    """Return a commit's author, committer, and message as one text, followed
    by the text of each tag a merge embedded (see :func:`merge_tags`).

    The embedded tags are appended after the message, rather than rendered
    from the raw commit with everything else, so the rest of the text, and the
    line numbers of its findings, are what ``git log`` has always produced.

    ``--no-show-signature`` overrides ``log.showSignature``, which would
    otherwise put the signature check's output (e.g., ``Good "git"
    signature for {signer}``) before the format, shifting every line number
    and scanning the signer's identity as if the commit recorded it.
    """
    text = git("log", "-1", "--no-show-signature", "--format=%an <%ae>%n%cn <%ce>%n%n%B", commit)
    tags = [tag_text(raw) for raw in merge_tags(commit)]
    return "\n".join([text, *tags]) if tags else text


def merge_tags(commit: str) -> list[str]:
    """Return the raw text of each tag object a merge commit embeds.

    Merging a signed tag (e.g., ``git merge v1.0``) copies the whole tag
    object into the merge commit's header as a ``mergetag`` header, one per
    merged tag, so pushing the merge publishes the tag's tagger and message
    even though no tag ref is pushed. ``git log`` formats don't show it. A
    header's first line follows its name and a space; each continuation line
    starts with a single space, which is removed. The tag's own blank line
    between header and message is stored as a line holding only that space,
    so the result separates them with an empty line as ``git cat-file tag``
    does.
    """
    header = git("cat-file", "commit", commit).partition("\n\n")[0]
    tags: list[list[str]] = []
    current: list[str] | None = None
    for line in header.split("\n"):
        if line.startswith(" "):
            if current is not None:
                current.append(line[1:])
            continue
        current = None
        if line.startswith("mergetag "):
            current = [line[len("mergetag "):]]
            tags.append(current)
    return ["\n".join(lines) for lines in tags]


def tag_metadata(tag: str) -> str:
    """Return the text an annotated tag's author wrote: its name, tagger, and
    message, without the object hashes and the armor of a trailing signature
    block, whose header lines are kept (see :func:`strip_signature`).
    """
    return tag_text(git("cat-file", "tag", tag))


def tag_text(raw: str) -> str:
    """Return the scanned text of a tag object given as ``git cat-file tag``
    prints it; see :func:`tag_metadata`.
    """
    header, _, message = raw.partition("\n\n")
    kept = [
        IDENT_TIMESTAMP.sub("", line)
        for line in header.splitlines()
        if not line.startswith(("object ", "type "))
    ]
    return "\n".join([*kept, "", strip_signature(message)])


def pending_commit_metadata(message_file: Path) -> str:
    """Return the identities and message the next commit will record.

    The whole message file is scanned, comment lines included, because
    whether Git strips them depends on the cleanup mode (e.g.,
    ``--cleanup=verbatim`` keeps them). The timestamps Git appends to
    identities are removed.

    The message is decoded as :func:`git` decodes output, with
    ``surrogateescape``, because Git records it byte for byte and a message in
    a legacy encoding (e.g., Latin-1 under ``i18n.commitEncoding``) isn't
    valid UTF-8. Replacing such bytes with U+FFFD would leave an accented
    term unmatchable; kept as surrogates, :func:`analyzable` also reads them
    as Latin-1.

    :param message_file: The message file Git passes to the commit-msg hook.
    """
    identities = [
        IDENT_TIMESTAMP.sub("", git("var", name).strip())
        for name in ("GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT")
    ]
    message = message_file.read_bytes().decode("utf-8", "surrogateescape")
    return "\n".join([*identities, "", message])


def nul_separated(output: str) -> list[str]:
    """Return the paths in NUL-separated (``-z``) output, which isn't quoted."""
    return [path for path in output.split("\0") if path]


# Added, copied, modified, renamed, or type-changed (e.g., a file replaced by a
# symlink): every status that records new content. Deletions don't record any.
CONTENT_STATUSES = "--diff-filter=ACMRT"

# Passed to every diff that lists what to scan. Without it, a staged or
# committed submodule pointer change (a gitlink) is left out of the list, and
# its path goes unscanned, whenever a setting tells git to ignore submodules:
# `git diff --cached` honors diff.ignoreSubmodules and
# submodule.{name}.ignore, and `git diff-tree` honors
# submodule.{name}.ignore, read from the repository's configuration or from
# the working tree's .gitmodules (verified with git 2.56.0), so an uncommitted
# .gitmodules edit could otherwise change what a push scans.
SHOW_SUBMODULES = "--ignore-submodules=none"


def files_at(rev: str) -> list[str]:
    """List every tracked path at a revision."""
    return nul_separated(git("ls-tree", "-r", "-z", "--name-only", rev))


def files_staged() -> list[str]:
    """List the staged paths that record new content."""
    return nul_separated(git("diff", "--cached", "-z", "--name-only", SHOW_SUBMODULES, CONTENT_STATUSES))


def files_changed_in(commit: str) -> list[str]:
    """List the paths whose content a commit records anew.

    A merge commit is compared with each parent (``-m``), so content introduced
    while resolving a merge is included. A root commit is compared with the
    empty tree.
    """
    output = git(
        "diff-tree", "-m", "--root", "--no-commit-id", "-z", "--name-only", "-r",
        SHOW_SUBMODULES, CONTENT_STATUSES, commit,
    )
    return list(dict.fromkeys(nul_separated(output)))


# The longest one denylist pattern may spend searching one text, in seconds. A
# pattern prone to catastrophic backtracking (e.g., ``(a|a)+$``) can otherwise
# run for hours on an ordinary file and stall every commit, so running out of
# time stops the scan rather than skipping the pattern, which would let the
# text through unchecked.
DENYLIST_TIMEOUT = 3.0

# Strings every denylist pattern is tried against when loaded. A pattern that
# matches an empty string in any of them (e.g., ``Tailor|``, ``a*``, or a
# bare ``\b``) would match at nearly every position of every text.
EMPTY_MATCH_PROBES = ("", " ", "a", "A b_1.\n-")


class DenylistError(Exception):
    """A denylist that can't be used, or a scan it can't finish.

    Messages name a denylist entry by its line number only, never by its
    pattern, by the text being scanned, or by the denylist's path, because
    they're printed where an LLM transcript or CI log can capture them, and
    the path is chosen by the user and can hold a term (e.g., a directory
    named after the person the list protects).
    """


@dataclass(frozen=True, slots=True)
class DenylistEntry:
    """One compiled denylist line.

    :ivar line: The entry's 1-based line in the file, for error messages and
        for the findings it matches, which print it in place of the term.
    :ivar pattern: The compiled pattern.
    """

    line: int
    pattern: regex.Pattern[str]

    def spans(self, text: str) -> Iterator[tuple[int, int]]:
        """Yield the ``(start, end)`` of each non-overlapping match in ``text``.

        Matches are found one ``search`` at a time with the time left until a
        shared deadline, because the ``regex`` module's ``timeout`` restarts
        with each match a ``finditer`` yields, so a pattern with many slow
        matches would never reach it.

        :raises DenylistError: If the pattern runs past ``DENYLIST_TIMEOUT``
            on ``text``, or matches an empty string in it.
        """
        deadline = time.monotonic() + DENYLIST_TIMEOUT
        pos = 0
        while True:
            remaining = deadline - time.monotonic()
            try:
                if remaining <= 0:
                    raise TimeoutError
                match = self.pattern.search(text, pos, timeout=remaining)
            except TimeoutError:
                raise DenylistError(f"denylist line {self.line}: the pattern ran longer than "
                                    f"{DENYLIST_TIMEOUT:g} seconds") from None
            if match is None:
                return
            # Load-time probing can't rule out every empty match (e.g., a
            # lookahead alone matches only before its own text), and an
            # empty match would also stop this loop from advancing.
            if match.start() == match.end():
                raise DenylistError(f"denylist line {self.line}: the pattern matched an empty string")
            yield match.span()
            pos = match.end()


@dataclass(frozen=True, slots=True)
class Denylist:
    """Private terms that are always reported, and phrases that excuse them.

    :ivar terms: Patterns for the denylisted terms.
    :ivar exceptions: Patterns for exception phrases. A term match that lies
        inside an exception match isn't reported as a finding, though it's
        still redacted from printed output (see :func:`redact`). Exceptions
        live in the private file, not the public allowlist, because an
        allowlist entry for a denylist match would publish the denylisted
        term.
    """

    terms: tuple[DenylistEntry, ...]
    exceptions: tuple[DenylistEntry, ...]

    def term_spans(self, text: str) -> list[tuple[int, int, int]]:
        """Return ``(start, end, entry_line)`` for each term match, excused or
        not, sorted, where ``entry_line`` is the matching entry's line in the
        denylist, which output prints in place of the matched text.

        Each term is searched for separately, so overlapping terms (e.g., a
        surname and the full name containing it) each give a span; a span two
        terms match identically is given once, with the earlier entry's line.

        :raises DenylistError: See :meth:`DenylistEntry.spans`.
        """
        found: dict[tuple[int, int], int] = {}
        for entry in self.terms:  # in file order, so setdefault keeps the earlier line
            for span in entry.spans(text):
                found.setdefault(span, entry.line)
        return sorted((start, end, line) for (start, end), line in found.items())

    def unexcused(self, text: str, spans: list[tuple[int, int, int]]) -> list[tuple[int, int, int]]:
        """Return the spans of :meth:`term_spans` (for ``text``) that no
        exception match covers: the term matches reported as findings.

        :raises DenylistError: See :meth:`DenylistEntry.spans`.
        """
        excused = [span for entry in self.exceptions for span in entry.spans(text)]
        return [
            (start, end, line) for start, end, line in spans
            if not any(lo <= start and end <= hi for lo, hi in excused)
        ]


def redact(text: str, denylist: Denylist | None) -> str:
    """Return ``text`` with each denylist term match replaced by
    ``[denylist line N]``, ``N`` being the matching entry's line.

    Overlapping matches are replaced as one run, named by the first entry
    that matched in it. Exceptions don't apply (see the module docstring).
    Used for every label the scanner prints, which can hold a path or a ref
    name.

    :raises DenylistError: See :meth:`DenylistEntry.spans`.
    """
    if denylist is None:
        return text
    pieces: list[str] = []
    pos = 0
    for start, end, line in denylist.term_spans(text):
        if start < pos:  # overlaps the run just replaced, so extend it
            pos = max(pos, end)
            continue
        pieces += [text[pos:start], f"[denylist line {line}]"]
        pos = end
    pieces.append(text[pos:])
    return "".join(pieces)


# The longest line --redact-stream accepts, in bytes including its newline. A
# line is held whole while it's redacted, so without a limit a tool printing
# megabytes with no newline would grow the filter's memory without bound (a
# 50 MB line took about 290 MB); a hook's output lines are far shorter.
MAX_STREAM_LINE = 1 << 20


class OverlongLineError(Exception):
    """A line of ``--redact-stream`` input longer than ``MAX_STREAM_LINE``."""


def redact_stream(source: io.BufferedIOBase, sink: BinaryIO, denylist: Denylist | None) -> None:
    """Copy ``source`` to ``sink`` line by line, each line passed through
    :func:`redact`, flushing after each line so a hook's progress shows as it
    happens. With no denylist (``PII_SCAN_DENYLIST=none``), the input is
    copied unchanged in chunks as it arrives, since nothing needs a whole
    line, so no line length limit applies.

    Lines are read as bytes, because a hook's output can hold any bytes (e.g.,
    a path or a textconv driver's output that isn't valid UTF-8), and a filter
    that crashed on one would fail every commit that printed it. Each line is
    decoded as UTF-8 with ``surrogateescape``, which keeps every byte, so a
    line with no term is written back byte for byte. A line that isn't
    valid UTF-8 is then redacted again as Latin-1, which reads every byte as
    one character, as the scan does (see :func:`analyzable`), so a term
    written in a single-byte legacy encoding is hidden too; the
    ``[denylist line N]`` this writes is ASCII, so it's the same in both
    readings. Lines end at ``\\n`` only, so a line that redraws itself with
    ``\\r`` (e.g., a progress counter) is written once it ends. Each read is
    bounded by ``MAX_STREAM_LINE``, and a longer line stops the copy without
    writing any of it, so the filter fails closed rather than passing a line it
    can't hold.

    These aren't hidden:

    - a non-ASCII term in Git's octal ``core.quotePath`` form (e.g.,
      ``z\\303\\266rblax`` for ``zörblax``), though none of the tools the hooks
      run prints a path that way;
    - a term split by ANSI escape codes or zero-width characters, and a match
      that would span a line break, because each line is matched on its own;
    - output a program writes directly to ``/dev/tty``, which never enters the
      pipe, though none of the tools the hooks run does that;
    - text of the placeholder ``[denylist line N]`` that a denylist entry
      matches (e.g., an entry ``denylist``), which is written as is.

    Scripts run by hand, outside the hooks, aren't filtered at all.

    :raises DenylistError: If a term pattern can't finish on a line (see
        :meth:`DenylistEntry.spans`). Nothing of that line is written.
    :raises OverlongLineError: If a line is longer than ``MAX_STREAM_LINE``.
        Nothing of that line is written.
    """
    if denylist is None:
        while chunk := source.read1(MAX_STREAM_LINE):
            sink.write(chunk)
            sink.flush()
        return
    while raw := source.readline(MAX_STREAM_LINE + 1):
        if len(raw) > MAX_STREAM_LINE:
            raise OverlongLineError(f"a line of the input was longer than {MAX_STREAM_LINE} bytes")
        text = redact(raw.decode("utf-8", "surrogateescape"), denylist)
        raw = text.encode("utf-8", "surrogateescape")
        if any("\udc80" <= ch <= "\udcff" for ch in text):
            raw = redact(raw.decode("latin-1"), denylist).encode("latin-1")
        sink.write(raw)
        sink.flush()


def analyzer_engine() -> AnalyzerEngine:
    """Build a Presidio analyzer, importing Presidio first (see the note at
    the imports)."""
    from presidio_analyzer import AnalyzerEngine  # noqa: PLC0415  (deferred; see the imports)

    return AnalyzerEngine()


def _compile_entry(line: int, source: str) -> DenylistEntry:
    """Compile one denylist line, or explain by line number why it can't be used.

    :raises DenylistError: If the pattern doesn't compile or matches an empty
        string. The ``regex`` module's own message is left out, because some
        of its messages quote the pattern (e.g., ``bad escape \\q``); only the
        error's position in the pattern is given.
    """
    where = f"denylist line {line}"
    try:
        pattern = regex.compile(source, regex.IGNORECASE)
    except regex.error as error:
        position = f" at position {error.pos}" if isinstance(error.pos, int) else ""
        raise DenylistError(f"{where}: the pattern isn't a valid regular expression (error{position}; "
                            "the regex module's message is withheld because it can quote the pattern)") from None
    # Anything else compile raises (e.g., OverflowError for a huge repeat
    # count) is reported without its message for the same reason.
    except Exception as error:  # noqa: BLE001
        raise DenylistError(f"{where}: the pattern couldn't be compiled ({type(error).__name__})") from None
    try:
        empty = any(
            match.start() == match.end()
            for probe in EMPTY_MATCH_PROBES
            for match in pattern.finditer(probe, timeout=DENYLIST_TIMEOUT)
        )
    except TimeoutError:
        raise DenylistError(f"{where}: the pattern ran longer than {DENYLIST_TIMEOUT:g} seconds "
                            "on a short test string") from None
    if empty:
        raise DenylistError(f"{where}: the pattern matches an empty string, so it would match "
                            "nearly everywhere")
    return DenylistEntry(line, pattern)


def load_denylist(path: Path) -> Denylist | None:
    """Read denylist patterns and exception patterns from a private file.

    :param path: One entry per line; blank lines and lines starting with ``#``
        are ignored, and whitespace around an entry is removed (match an
        edge space with ``\\s`` or ``[ ]``, and a leading ``#`` with ``\\#``).
        A line starting with ``!`` is an exception pattern; every other line
        is a term pattern. Each is a ``regex`` module pattern, compiled on its
        own with ``regex.IGNORECASE``; ``(?-i)`` at its start makes it match
        case. A pattern matches anywhere, including inside a word (e.g.,
        ``tailor`` matches ``tailor_notes.md``); write ``\\b`` for a word
        boundary. The file is UTF-8, with or without a byte order mark.
    :returns: The denylist, or ``None`` when the file is missing or doesn't
        have any term patterns.
    :raises DenylistError: If an entry doesn't compile, or matches an empty
        string (see ``EMPTY_MATCH_PROBES``).
    """
    if not path.exists():
        return None
    terms: list[DenylistEntry] = []
    exceptions: list[DenylistEntry] = []
    # utf-8-sig drops a byte order mark (e.g., from Windows editors), which
    # utf-8 would keep as U+FEFF at the start of the first entry, so that
    # entry would never match.
    for number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), start=1):
        entry = raw.strip()
        if not entry or entry.startswith("#"):
            continue
        if entry.startswith("!"):
            if entry[1:].strip():
                exceptions.append(_compile_entry(number, entry[1:].strip()))
        else:
            terms.append(_compile_entry(number, entry))
    if not terms:
        return None
    return Denylist(terms=tuple(terms), exceptions=tuple(exceptions))


# spaCy refuses a text longer than its nlp.max_length (1,000,000 characters by
# default), so a long file (e.g., generated JSON) would stop every commit that
# adds it. Raising the limit isn't the fix: spaCy's error message says the
# parser and NER need roughly 1 GB of memory per 100,000 characters. A long
# text is analyzed in chunks of CHUNK_SIZE characters instead, each starting
# CHUNK_SIZE - CHUNK_OVERLAP characters after the last (see presidio_results).
# Peak memory follows the chunk, not the text: on a 1.1-million-character JSON
# file, the scan peaked at about 1.4 GB with 50,000-character chunks, 2.0 GB
# with 100,000, and 7.2 GB with 500,000 (0.8 GB with the model loaded and a
# one-line file), and took the same time with each.
CHUNK_SIZE = 50_000
# Twice the longest match the chunking is guaranteed to see whole, with half
# this much context on each side.
CHUNK_OVERLAP = 1_000


def presidio_results(engine: AnalyzerEngine, text: str) -> list[RecognizerResult]:
    """Return Presidio's results for ``text``, with offsets into ``text``.

    A text up to ``CHUNK_SIZE`` characters is analyzed whole. A longer one is
    analyzed in overlapping chunks, and each chunk's results are shifted by
    the chunk's start. Each overlap is split at its midpoint: a chunk keeps
    only results that start between the midpoints of its overlaps with the
    chunks before and after it. So every position belongs to exactly one
    chunk, which reports a match at most ``CHUNK_OVERLAP // 2`` characters
    long whole, with at least that much text around it, and a match the
    neighboring chunk also sees isn't reported twice. Keeping only results
    with identical spans wouldn't do: the chunk that cuts a match off can
    report a shorter match there (e.g., the first two words of a three-word
    name), which a span comparison counts as different.
    """
    if len(text) <= CHUNK_SIZE:
        return engine.analyze(text=text, entities=ENTITIES, language="en")
    step = CHUNK_SIZE - CHUNK_OVERLAP
    half = CHUNK_OVERLAP // 2
    results: list[RecognizerResult] = []
    for start in range(0, len(text) - CHUNK_OVERLAP, step):
        end = min(start + CHUNK_SIZE, len(text))
        # The first chunk owns from the text's start, and the last to its end.
        owned_from = start + half if start > 0 else 0
        owned_to = end - half if end < len(text) else len(text)
        for result in engine.analyze(text=text[start:end], entities=ENTITIES, language="en"):
            result.start += start
            result.end += start
            if owned_from <= result.start < owned_to:
                results.append(result)
    return results


def analyze(
    engine: AnalyzerEngine,
    text: str,
    min_score: float,
    denylist: Denylist | None,
) -> Iterator[tuple[int, str, str, float, int | None]]:
    """Yield ``(line, entity, matched_text, score, denylist_line)`` for each
    detection. ``denylist_line`` is the matching denylist entry's line for a
    denylist match; for any other detection, it's the line of the first term
    entry whose match overlaps it, excused or not, so the finding prints
    without its text (see :meth:`Finding.render`), and ``None`` when no term
    match overlaps it.

    PERSON results are kept only when :func:`looks_like_name` accepts them; a
    trailing possessive is removed first, so "Alan Perlis's" is reported, and
    allowlisted, as "Alan Perlis".

    :param engine: A configured Presidio analyzer.
    :param text: The text to scan.
    :param min_score: Minimum score to report.
    :param denylist: Private terms always reported, or ``None``.
    :raises DenylistError: If a denylist pattern times out or matches an
        empty string in ``text``.
    """
    # Searched before Presidio runs, because its results are checked against
    # these spans.
    terms = denylist.term_spans(text) if denylist is not None else []
    for result in presidio_results(engine, text):
        if result.score < min_score:
            continue
        matched = text[result.start:result.end]
        if result.entity_type == "PERSON":
            matched = POSSESSIVE.sub("", matched)
            if not looks_like_name(matched):
                continue
        line = text.count("\n", 0, result.start) + 1
        overlapping = next((entry_line for start, end, entry_line in terms
                            if start < result.end and result.start < end), None)
        yield line, result.entity_type, matched, result.score, overlapping
    if denylist is not None:
        for start, end, entry_line in denylist.unexcused(text, terms):
            line = text.count("\n", 0, start) + 1
            yield line, DENYLIST_ENTITY, text[start:end], 1.0, entry_line


@dataclass(frozen=True, slots=True)
class Text:
    """One text to analyze or export.

    :ivar label: Where it came from, as findings report it.
    :ivar path: The path allowlist globs are matched against.
    :ivar content: The text.
    """

    label: str
    path: str
    content: str


def path_variants(path: str) -> str:
    """Return the text scanned for a path: the path, and its components.

    Components are listed again with their last extension removed, so a name
    such as ``someone@example.org.txt`` presents the address without the
    ``.txt`` that would make its domain invalid.
    """
    parts = path.split("/")
    stems = [part.rsplit(".", 1)[0] if "." in part else part for part in parts]
    return "\n".join([path, *parts, *stems])


# The mode Git records for a submodule's entry (a gitlink), which names a
# commit in the submodule's repository rather than a file.
GITLINK_MODE = "160000"


def gitlinks_at(rev: str) -> set[str]:
    """Return the paths of the submodule entries (gitlinks) at a revision.

    The whole tree, or the whole index, is listed rather than each target
    path, because a path given to ``ls-tree`` or ``ls-files`` is a pathspec,
    and one starting with ``:`` would be read as pathspec magic.

    :param rev: A revision; the empty string means the index.
    """
    if rev == "":
        # Each entry is "MODE OID STAGE<TAB>PATH".
        output = git("ls-files", "-s", "-z")
    else:
        # Each entry is "MODE TYPE OID<TAB>PATH".
        output = git("ls-tree", "-r", "-z", rev)
    return {
        entry.split("\t", 1)[1]
        for entry in nul_separated(output)
        if entry.startswith(f"{GITLINK_MODE} ")
    }


def collect_texts(targets: Iterable[tuple[str, str, str]], label_prefix: str) -> Iterator[Text]:
    """Yield each decoding of each ``(rev, path, label)`` target, then each path.

    A submodule entry (see :func:`gitlinks_at`) yields only its path.

    A blob is read once per path; the same content at a path several commits
    share is labeled with the first commit that carried it. The path is part
    of the key because allowlist entries can be scoped to a path, so identical
    content can be acceptable in one file and not in another.
    """
    seen: set[tuple[str, str]] = set()
    paths: list[str] = []
    gitlinks: dict[str, set[str]] = {}
    for rev, path, label in targets:
        if path not in paths:
            paths.append(path)
        # A submodule's content is published by its own repository, and the
        # commit its entry records is usually absent from this one, so reading
        # that commit would fail. Its path is still scanned with the others.
        if rev not in gitlinks:
            gitlinks[rev] = gitlinks_at(rev)
        if path in gitlinks[rev]:
            continue
        oid = git("rev-parse", object_spec(rev, path)).strip()
        if (oid, path) in seen:
            continue
        seen.add((oid, path))
        if git("cat-file", "-t", oid).strip() != "blob":
            continue
        for content in decodings(git_bytes("cat-file", "blob", oid)):
            yield Text(label, path, content)
    for path in paths:
        yield Text(f"{label_prefix}(path) {path}", path, path_variants(path))


def scan_text(engine: AnalyzerEngine, text: Text, min_score: float, denylist: Denylist | None) -> list[Finding]:
    """Analyze one text and label its findings.

    A path's text lists the path several ways (see :func:`path_variants`), so
    its findings are reported once each, on line 1, rather than once per
    variant.

    :raises DenylistError: If the denylist can't finish scanning the text; the
        message gains the text's label, redacted, so the gate's output says
        where.
    """
    try:
        return _scan_text(engine, text, min_score, denylist)
    except DenylistError as error:
        raise DenylistError(f"{error} while scanning {safe_label(text.label, denylist)}") from None


def safe_label(label: str, denylist: Denylist | None) -> str:
    """Return ``label`` escaped (see :func:`one_line`) and redacted (see
    :func:`redact`), or a placeholder when a term pattern can't finish on it,
    for messages that report a denylist failure and so can't raise another.
    """
    try:
        return redact(one_line(label), denylist)
    except DenylistError:
        return "(a label withheld because the denylist couldn't finish on it)"


def _scan_text(engine: AnalyzerEngine, text: Text, min_score: float, denylist: Denylist | None) -> list[Finding]:
    is_path = text.label.endswith(f"(path) {text.path}")
    in_allowlist = text.path == ALLOWLIST_PATH and not is_path
    findings: dict[tuple[str, str], Finding] = {}
    for content in analyzable(text.content):
        entries: list[AllowlistRow] = []
        if in_allowlist:
            try:
                entries = list(allowlist_rows(content))
            except csv.Error:
                # A decoding csv can't parse (e.g., one holding NUL, which
                # Python 3.10's csv rejects) doesn't quote any entry, so nothing in it
                # is excused.
                entries = []
        for line, entity, matched, score, denylist_line in analyze(engine, content, min_score, denylist):
            key = (entity, matched.casefold()) if is_path else (str(len(findings)), "")
            quoted = in_allowlist and quotes_own_entry(entries, line, entity, matched)
            findings.setdefault(key, Finding(text.label, text.path, 1 if is_path else line, entity, matched,
                                             score, quoted, denylist_line))
    return list(findings.values())


def quotes_own_entry(entries: list[AllowlistRow], line: int, entity: str, matched: str) -> bool:
    """Report whether a finding in the allowlist is the text of the entry on its line.

    The allowlist has to quote what it accepts, including path-scoped entries
    that don't apply to the allowlist's own path. Only a match inside the text
    field of an entry whose lines include the finding's counts, so a name added
    in a comment, or in another field, is reported like anywhere else. Entries
    come from :func:`allowlist_rows`, the parsing the loader uses, so a line
    the loader reads as a comment (e.g., ``"#x"<TAB>Jane Roe``) doesn't
    excuse anything here either. The entry's type isn't compared, because one
    value can match several detectors (e.g., a sample ITIN also scores as an SSN).
    Denylist matches never count, because the allowlist can't excuse them.

    :param entries: The allowlist's entry rows, from the text as scanned.
    :param line: The finding's 1-based line.
    :param entity: The finding's entity type.
    :param matched: The finding's matched text.
    """
    if entity == DENYLIST_ENTITY:
        return False
    return any(
        row.first_line <= line <= row.last_line and len(row.fields) >= 2 and matched in row.fields[1]
        for row in entries
    )


def analyzable(content: str) -> list[str]:
    """Return ``content`` in forms the analyzer accepts.

    Paths and messages read from git keep bytes that aren't valid UTF-8 as
    lone surrogates (see :func:`git`), which spaCy can't process. Such text is
    analyzed with those bytes replaced, and again read as Latin-1, so a name
    written in a single-byte legacy encoding still matches.
    """
    if not any("\udc80" <= ch <= "\udcff" for ch in content):
        return [content]
    raw = content.encode("utf-8", "surrogateescape")
    return [raw.decode("utf-8", "replace"), raw.decode("latin-1")]


def export_texts(texts: Iterable[Text], directory: Path) -> int:
    """Write each text to its own file under ``directory`` for gitleaks.

    Every file is ``{n}/content.txt``, where ``{n}`` is the text's number
    (e.g., ``000001``), so no part of the repository path or label is in the
    file's path. gitleaks' default configuration skips files by name (e.g.,
    images, documents, lock files, node_modules), and a lock file can carry
    registry credentials; and gitleaks reports the file's path, which would
    otherwise print a denylisted term in a label. The first line of each file
    names where the text came from (e.g., ``# source: 1a2b3c4:path/to/file``),
    which ``--gitleaks-report`` reads back to locate a finding; the text's own
    line numbers are one higher in gitleaks' report. The line also keeps
    gitleaks reading the file: gitleaks skips a file whose first bytes are a
    binary format's signature (e.g., ``%PDF`` or ``MZ``), and a text can start
    with one. It's always one line (see :func:`one_line`). No file is written
    at the top of ``directory``, where gitleaks would read a ``.gitleaks.toml``
    as its configuration.

    :returns: The number of files written.
    """
    count = 0
    for count, text in enumerate(texts, start=1):
        target = directory / f"{count:06d}" / "content.txt"
        target.parent.mkdir(parents=True, exist_ok=True)
        header = f"{EXPORT_HEADER}{one_line(text.label)}\n"
        target.write_text(header + text.content, encoding="utf-8", errors="surrogateescape")
    return count


def gitleaks_findings(report: Path, exported: Path | None, denylist: Denylist | None) -> list[str]:
    """Return one line for each finding in a gitleaks JSON report.

    Each line gives the finding's rule, location, and commit, and nothing
    else from the report: the gate runs gitleaks without ``--verbose``,
    whose output prints the matched line's surrounding text and, in Git
    mode, the commit's author and email unredacted, and any of those can hold
    a denylisted term. Each whole line is redacted (see :func:`redact`), not
    only its path, because the rule ID and commit come from the report too.

    :param report: The report (``--report-format json``).
    :param exported: The directory :func:`export_texts` wrote, when the
        report is of that directory; a finding in one of its files is then
        located by the label in the file's first line, with the line number
        the text itself has. A finding on that first line is in the label.
    :raises DenylistError: If a term pattern can't finish on a line.
    """
    lines = []
    for leak in json.loads(report.read_text(encoding="utf-8")):
        where, line = leak.get("File") or "(stdin)", int(leak.get("StartLine") or 0)
        labelled = False
        if exported is not None and where != "(stdin)":
            path = Path(where)
            if not path.is_absolute():
                path = Path.cwd() / path
            if path.is_relative_to(exported.resolve()) or path.is_relative_to(exported.absolute()):
                with path.open(encoding="utf-8", errors="surrogateescape") as file:
                    first = file.readline().rstrip("\n")
                if first.startswith(EXPORT_HEADER):
                    # The header is already one line (see export_texts).
                    where, labelled = first[len(EXPORT_HEADER):], True
        if line <= 0:
            # gitleaks didn't give a line (StartLine 0 or missing).
            at = ":(line not reported)"
        elif labelled:
            at = ":(the source label itself)" if line == 1 else f":{line - 1}"
        else:
            at = f":{line}"
        commit = leak.get("Commit") or ""
        rendered = (f"{one_line(leak.get('RuleID') or '(no rule)')} at {one_line(where)}{at}"
                    + (f" in commit {one_line(commit[:12])}" if commit else ""))
        lines.append(redact(rendered, denylist))
    return lines


def network_isolated() -> bool:
    """Report whether this process is cut off from the network.

    Neither check sends anything off the machine:

    - On macOS, sandbox-exec's network deny makes connecting to a local port
      fail with a permission error, where an unsandboxed process gets the
      connection (or a refusal). Each proxy the environment names (e.g.,
      ``HTTPS_PROXY``) must fail the same way, because a sandbox can deny
      other connections while leaving its own proxy open: Claude Code's
      sandbox denies 127.0.0.1:1 but accepts connections to the local proxy
      in ``HTTPS_PROXY``, which forwards to the internet, and the scanner
      inherits that variable. A probe that connects closes at once without
      writing anything.
    - On Linux, bubblewrap's own network namespace holds only the loopback
      interface, which is listed without connecting anywhere.
    """
    if sys.platform == "darwin":
        return all(connection_denied(endpoint)
                   for endpoint in [("127.0.0.1", 1), *proxy_endpoints()])
    return [name for _, name in socket.if_nameindex()] == ["lo"]


def connection_denied(endpoint: tuple[str, int]) -> bool:
    """Report whether a sandbox refuses this process a connection to ``endpoint``.

    Only a permission error counts: a refusal or a timeout means the
    connection attempt got through. A host name that doesn't resolve counts
    as denied, because a client can't use it either, and macOS's network deny
    blocks name resolution too.
    """
    try:
        with socket.create_connection(endpoint, timeout=2):
            return False
    except PermissionError:
        return True
    except socket.gaierror:
        return True
    except OSError:
        return False


def proxy_endpoints() -> list[tuple[str, int]]:
    """List the host and port of every proxy the environment names.

    ``getproxies_environment`` reads every ``{scheme}_proxy`` variable in
    either case, as Python's own HTTP clients do. A value without a scheme
    (e.g., ``127.0.0.1:3128``) is parsed as a host and port, and one without
    a usable port gets port 80, which only has to be a port the probe can
    try; a sandbox that denies the network denies every port.
    """
    endpoints = set()
    for scheme, value in urllib.request.getproxies_environment().items():
        if scheme == "no":
            continue
        parsed = urllib.parse.urlsplit(value if "://" in value else f"//{value}")
        try:
            port = parsed.port or 80
        except ValueError:  # a port that isn't a number or is out of range
            port = 80
        if parsed.hostname:
            endpoints.add((parsed.hostname, port))
    return sorted(endpoints)


def already_sandboxed() -> int:
    """Report whether this process already runs inside a Seatbelt sandbox.

    The gate asks this only after ``sandbox-exec`` fails to start, to tell an
    outer sandbox (inside which macOS won't start another) from any other
    failure. ``sandbox_check`` from libSystem, given this process ID, no
    operation, and no filter, returns 1 when the process is sandboxed and 0
    when it isn't (verified on 2026-11-04 inside Claude Code's sandbox, under
    the gate's own ``sandbox-exec`` profile, and unsandboxed). It's private
    API, so its absence or any other answer means "can't tell", which the gate
    never treats as sandboxed.

    :returns: 0 when sandboxed, 1 when not, 2 when the check can't be made.
    """
    if sys.platform != "darwin":
        return 2
    try:
        check = ctypes.CDLL(None).sandbox_check
    except (AttributeError, OSError):
        return 2
    check.restype = ctypes.c_int
    check.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
    return {1: 0, 0: 1}.get(check(os.getpid(), None, 0), 2)


def run_control(engine: AnalyzerEngine, min_score: float) -> int:
    """Check that each detector finds its own sample in the control fixture.

    ``pii-control.expected`` pairs every entity type with the exact sample text
    that type must detect. Matching on the pair, not on the type alone, matters
    because one sample can trigger several detectors (the ITIN sample also
    scores as a US_SSN), which would let a detector whose own sample is missing
    or broken appear to work. The denylist is exercised with the fixture's own
    term list, so the check holds whether or not the user has a private
    denylist.

    Each result line quotes the expected sample from ``pii-control.expected``,
    including the denylist samples, unlike a denylist finding elsewhere (see
    :meth:`Finding.render`): those are the fixture's own invented, public
    terms, and naming them shows which sample a miss concerns.

    :returns: 0 when every expected pair is detected, 1 when one is missed,
        2 when the control denylist can't be used.
    """
    text = CONTROL_FIXTURE.read_text(encoding="utf-8")
    try:
        denylist = load_denylist(CONTROL_DENYLIST)
        detected = {(entity, matched) for _, entity, matched, _, _ in analyze(engine, text, min_score, denylist)}
    except DenylistError as error:
        print(f"FATAL: {error}", file=sys.stderr)
        return 2
    expected = [
        tuple(line.split("\t", 1))
        for line in CONTROL_EXPECTED.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    failed = False
    for entity in [*ENTITIES, DENYLIST_ENTITY]:
        samples = [pair for pair in expected if pair[0] == entity]
        if not samples:
            print(f"  control {entity}: NO SAMPLE in {CONTROL_EXPECTED.name}")
            failed = True
            continue
        for pair in samples:
            found = pair in detected
            failed = failed or not found
            print(f'  control {entity} "{pair[1]}": {"ok" if found else "MISSED"}')
    if failed:
        print("FATAL: the PII scan failed its own control; its other results can't be trusted.",
              file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    """Parse arguments, run the requested scan, and report findings."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rev", help="scan every tracked file at this revision")
    parser.add_argument("--staged", action="store_true", help="scan the files staged for the next commit")
    parser.add_argument("--commit", action="append", default=[],
                        help="scan the files this commit changed, and its metadata (repeatable)")
    parser.add_argument("--tag", action="append", default=[],
                        help="scan an annotated tag's name, tagger, and message (repeatable)")
    parser.add_argument("--ref", action="append", default=[],
                        help="scan a ref name as published, e.g., refs/heads/topic (repeatable)")
    parser.add_argument("--message-file", type=Path,
                        help="scan a pending commit message and the identities Git will record")
    parser.add_argument("--control", action="store_true", help="check detection against the control fixture")
    parser.add_argument("--check-isolation", action="store_true",
                        help="exit 0 only when this process doesn't have network access")
    parser.add_argument("--check-sandboxed", action="store_true",
                        help="exit 0 when this process already runs in a macOS sandbox, 1 when it "
                             "doesn't, 2 when that can't be checked")
    parser.add_argument("--allowlist", type=Path, default=None,
                        help="read the allowlist from this file instead of as committed")
    parser.add_argument("--allowlist-rev", default="HEAD",
                        help="revision whose allowlist judges --commit, --tag, and --ref (default HEAD)")
    parser.add_argument("--denylist", type=Path, default=None,
                        help="private denylist; overrides $PII_SCAN_DENYLIST and the default path "
                             "(set PII_SCAN_DENYLIST=none, not this option, to scan without one)")
    parser.add_argument("--export-to", type=Path, default=None,
                        help="write the texts to this directory for gitleaks instead of analyzing them")
    parser.add_argument("--gitleaks-report", type=Path, default=None,
                        help="print the findings of this gitleaks JSON report without their text")
    parser.add_argument("--exported", type=Path, default=None,
                        help="with --gitleaks-report: the --export-to directory the report covers")
    parser.add_argument("--min-score", type=float, default=DEFAULT_MIN_SCORE)
    parser.add_argument("--show-allowed", action="store_true", help="also list allowlisted findings")
    parser.add_argument("--redact-stream", action="store_true",
                        help="copy stdin to stdout with each denylist term replaced by its entry's line")
    args = parser.parse_args(argv)

    history = bool(args.commit or args.tag or args.ref)
    modes = [bool(args.rev), args.staged, bool(args.message_file), args.control, args.check_isolation,
             args.check_sandboxed, history, args.gitleaks_report is not None, args.redact_stream]
    if sum(modes) != 1:
        parser.error("give exactly one of --rev, --staged, --message-file, --control, --check-isolation, "
                     "--check-sandboxed, --gitleaks-report, --redact-stream, or any of --commit, --tag, and --ref")
    if args.exported is not None and args.gitleaks_report is None:
        parser.error("--exported needs --gitleaks-report")

    if args.check_isolation:
        isolated = network_isolated()
        print(f"PII scan: network {'isolated' if isolated else 'NOT isolated'}.")
        return 0 if isolated else 1
    if args.check_sandboxed:
        status = already_sandboxed()
        state = ["already sandboxed", "NOT sandboxed", "can't tell whether sandboxed"][status]
        print(f"PII scan: process {state}.")
        return status
    if args.redact_stream:
        # Everything this mode prints must stay free of paths, because the
        # hooks can't filter the filter's own messages, and a path (the
        # denylist's, or a source file's in a traceback) can hold a term. So
        # an unexpected error is named by its type alone, without the message
        # or traceback that run() would print (e.g., an unreadable denylist
        # raises a PermissionError whose message is the denylist's path).
        try:
            denylist, status = required_denylist(args.denylist)
            if status:
                return status
            redact_stream(sys.stdin.buffer, sys.stdout.buffer, denylist)
        except (DenylistError, OverlongLineError) as error:
            print(f"FATAL: {error}; the rest of the input was withheld.", file=sys.stderr)
            return 2
        except Exception as error:  # noqa: BLE001  (see above)
            print(f"FATAL: the output filter stopped on an unexpected {_exception_name(error)}; its message is "
                  "withheld because it can name a path, and the rest of the input was withheld.", file=sys.stderr)
            return 2
        return 0
    if args.control:
        return run_control(analyzer_engine(), args.min_score)
    if args.gitleaks_report is not None:
        denylist, status = required_denylist(args.denylist)
        if status:
            return status
        try:
            for line in gitleaks_findings(args.gitleaks_report, args.exported, denylist):
                print(f"  secret: {line}")
        except DenylistError as error:
            print(f"FATAL: {error}", file=sys.stderr)
            return 2
        return 0

    texts: list[Text] = []
    if args.rev:
        texts += collect_texts(((args.rev, p, p) for p in files_at(args.rev)), "")
    elif args.staged:
        texts += collect_texts((("", p, f"staged:{p}") for p in files_staged()), "staged:")
    elif args.message_file:
        texts.append(Text(f"pending:{METADATA_PATH}", METADATA_PATH,
                          pending_commit_metadata(args.message_file)))
    else:
        texts += collect_texts(
            ((c, p, f"{c[:7]}:{p}") for c in args.commit for p in files_changed_in(c)), "")
        texts += [Text(f"{c[:7]}:{METADATA_PATH}", METADATA_PATH, commit_metadata(c)) for c in args.commit]
        texts += [Text(f"{t[:7]}:{TAG_PATH}", TAG_PATH, tag_metadata(t)) for t in args.tag]
        texts += [Text(f"{REF_PATH} {r}", REF_PATH, r) for r in args.ref]

    if args.export_to is not None:
        written = export_texts(texts, args.export_to)
        print(f"Exported {written} text(s) for the secret scan.")
        return 0

    try:
        if args.allowlist is not None:
            rules = parse_allowlist(args.allowlist.read_text(encoding="utf-8"), str(args.allowlist))
        else:
            rev = "" if (args.staged or args.message_file) else (args.rev or args.allowlist_rev)
            rules = load_allowlist_at(rev)
    # csv.Error covers malformed quoting (e.g., a NUL under Python 3.10), which
    # should stop the gate with this message rather than a traceback.
    except (ValueError, OSError, csv.Error, subprocess.CalledProcessError) as error:
        print(f"FATAL: couldn't read the allowlist: {error}", file=sys.stderr)
        return 2

    # Loaded before the analyzer, whose model takes seconds to load, so a
    # broken entry is reported at once.
    denylist, status = required_denylist(args.denylist)
    if status:
        return status
    try:
        engine = analyzer_engine()
        findings = [f for text in texts for f in scan_text(engine, text, args.min_score, denylist)]
        blocked = [
            f for f in findings
            if not f.quoted and not any(rule.allows(f) for rule in rules)
        ]
        allowed = [f for f in findings if f not in blocked]
        # Rendered before anything is printed, so a term pattern that can't
        # finish on a label stops the scan without a partial report.
        report = [finding.render(denylist) for finding in blocked]
        if args.show_allowed:
            report += [f"  (allowed) {finding.render(denylist)}" for finding in allowed]
    except DenylistError as error:
        print(f"FATAL: {error}", file=sys.stderr)
        return 2

    for line in report:
        print(line)
    files = len({t.path for t in texts if not t.path.startswith("(")})
    metadata = len(args.commit) + len(args.tag) + (1 if args.message_file else 0)
    print(f"PII scan: {files} file(s), {metadata} commit or tag message(s), and {len(args.ref)} "
          f"ref name(s) examined, {len(blocked)} finding(s), {len(allowed)} allowlisted.")
    return 1 if blocked else 0


def required_denylist(override: Path | None) -> tuple[Denylist | None, int]:
    """Load the private denylist, or explain why it can't be used.

    A denylist is required unless ``PII_SCAN_DENYLIST`` is the literal
    ``none``. A missing or empty file otherwise stops the scan, because a
    mistyped path, a moved file, or an emptied one would silently turn the
    denylist off while every scan still passed. The opt-out is read from the
    environment only, not from ``--denylist``, so a file named ``none`` can't
    be mistaken for it.

    :param override: The ``--denylist`` path, if given.
    :returns: The denylist (``None`` when opted out) and 0, or ``None`` and
        exit status 2 after printing a FATAL line.
    """
    env_denylist = os.environ.get("PII_SCAN_DENYLIST")
    opted_out = override is None and env_denylist == DENYLIST_OPT_OUT
    path = override or (Path(env_denylist) if env_denylist else DEFAULT_DENYLIST)
    if opted_out:
        return None, 0
    try:
        denylist = load_denylist(path)
    except DenylistError as error:
        print(f"FATAL: {error}", file=sys.stderr)
        return None, 2
    if denylist is None:
        problem = ("doesn't have any term patterns (exception lines alone don't count)" if path.exists()
                   else "doesn't exist")
        # The path is described by where it came from rather than printed,
        # because the user chooses it and it can hold a term (see
        # DenylistError); the default's description is the literal "~" form,
        # which doesn't name an account.
        source = ("given with --denylist" if override else
                  "named by PII_SCAN_DENYLIST" if env_denylist else "~/.config/pii-scan/denylist.txt")
        print(f"FATAL: the denylist ({source}) {problem}. Create it with one regular expression per line "
              f"(see load_denylist in scripts/pii-scan.py), or set PII_SCAN_DENYLIST={DENYLIST_OPT_OUT} "
              "to scan without a denylist.", file=sys.stderr)
        return None, 2
    return denylist, 0


def _exception_name(error: BaseException) -> str:
    cls = type(error)
    return cls.__qualname__ if cls.__module__ == "builtins" else f"{cls.__module__}.{cls.__qualname__}"


def _message_is_safe(error: BaseException) -> bool:
    """Tell whether an exception's message can be printed.

    Only messages whose content is known are: a :class:`DenylistError` names
    entries by line number by design; and a built-in ``OSError`` carrying an
    ``errno`` was raised by the operating system, whose message is its error
    text and a file name. Any other message, from this script or a library
    (e.g., a ``ValueError``, a ``UnicodeError``, a ``regex`` error, or a spaCy
    or Presidio error, which can embed the text being analyzed), might quote
    scanned text or a denylist pattern. A ``CalledProcessError``'s message
    holds the git command, whose arguments can name a repository path (e.g.,
    ``:0:{path}``) that holds a term, so :func:`_describe` gives only the git
    subcommand and exit status for it.
    """
    if isinstance(error, DenylistError):
        return True
    return isinstance(error, OSError) and type(error).__module__ == "builtins" and error.errno is not None


def _describe(error: BaseException) -> str:
    """Name an exception, with its message only when that's safe to print."""
    if isinstance(error, subprocess.CalledProcessError):
        # Commands are ["git", "-C", {root}, {subcommand}, ...] (see git_bytes).
        command = error.cmd if isinstance(error.cmd, list) else []
        what = f"git {command[3]}" if len(command) > 3 and command[0] == "git" else "a command"
        return f"{_exception_name(error)}: {what} exited with status {error.returncode} (arguments withheld: " \
               "they can name a path)"
    if _message_is_safe(error):
        return f"{_exception_name(error)}: {error}"
    frames = traceback.extract_tb(error.__traceback__)
    where = f" at {frames[-1].filename}:{frames[-1].lineno} in {frames[-1].name}" if frames else ""
    return f"{_exception_name(error)}{where} (message withheld: it may quote scanned text or a denylist pattern)"


def report_crash(error: Exception) -> None:
    """Print a crash as a FATAL line, then its traceback, to stderr.

    The traceback is built here rather than with ``traceback.print_exc``,
    which ends each exception in the chain (``__cause__`` and
    ``__context__``) with its message, so it would print what the FATAL line
    withholds. Each frame's file, line, and source line are printed, and each
    exception is named as in the FATAL line.
    """
    print(f"FATAL: pii-scan crashed: {_describe(error)}", file=sys.stderr)
    chain: list[BaseException] = []
    current: BaseException | None = error
    while current is not None and not any(current is seen for seen in chain):
        chain.append(current)
        current = current.__cause__ or (None if current.__suppress_context__ else current.__context__)
    for position, exception in enumerate(reversed(chain)):
        if position:
            joined = ("The above exception was the direct cause of the following exception:"
                      if exception.__cause__ is not None else
                      "During handling of the above exception, another exception occurred:")
            print(f"\n{joined}\n", file=sys.stderr)
        print("Traceback (most recent call last):", file=sys.stderr)
        traceback.print_tb(exception.__traceback__, file=sys.stderr)
        print(_describe(exception), file=sys.stderr)


def run(argv: list[str] | None = None) -> int:
    """Run :func:`main`, reporting an unexpected exception as exit status 2.

    Python exits 1 on an uncaught exception, the status that means findings
    were reported, so a crash would read as findings. Exit status 2 is the
    status for an environment error, and the FATAL line says what happened.
    Only ``Exception`` is caught: ``SystemExit`` (e.g., from argparse) keeps
    its status, and ``KeyboardInterrupt`` still ends the process the default
    way (by SIGINT, status 130 in a shell). A failing Presidio import is
    caught here, because Presidio is imported when an analyzer is built (see
    :func:`analyzer_engine`); an exception raised while the module itself is
    imported (e.g., by the ``regex`` import) happens before this runs and
    still exits 1.
    """
    try:
        return main(argv)
    except Exception as error:  # noqa: BLE001  (any crash must exit 2, not 1)
        report_crash(error)
        return 2


if __name__ == "__main__":
    sys.exit(run())
