# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Report invisible and bidirectional Unicode in repository content.

Text in a plugin becomes instructions to a model, and some code points change
what a model reads without changing what a reviewer sees: Unicode tag
characters carry an invisible copy of ASCII ("ASCII smuggling"), variation
selectors can carry arbitrary bytes after an emoji ("emoji smuggling"), and
bidirectional controls reorder how text displays, so the order a reviewer reads
differs from the order a parser or model reads ("Trojan Source",
CVE-2021-42574). Legitimate content doesn't use them, so each one is a
finding. The rules (see :func:`flagged`):

- every format character (general category Cf). That covers the bidi
  embedding, override, and isolate controls (U+202A-U+202E, U+2066-U+2069),
  LRM, RLM, and ALM (U+200E, U+200F, U+061C), the zero-width characters
  (U+200B, U+200C, U+2060), the assigned tag characters, the soft hyphen
  (U+00AD), and U+FEFF. Rejecting the whole category, rather than listing the
  characters above, also catches the ones nobody thought to list (e.g., the
  invisible math operators U+2061-U+2064). The cost is that it would also
  reject the Arabic number signs (U+0600-U+0605) if a skill ever needs them;
  none does yet.
- U+FEFF even as a file's first character: a BOM there would hide the
  frontmatter's opening "---" from portable-skill.sh and from the output-style
  check in install-and-verify.sh, both of which compare line 1 with "---".
- U+200D (zero width joiner), which is Cf too. It's legitimate inside emoji
  sequences (e.g., a profession emoji), but no content uses one, and allowing
  it only between pictographs would need a table of them; relax this when a
  skill needs such an emoji.
- the whole tag block U+E0000-U+E007F, including its unassigned code points,
  which are category Cn rather than Cf.
- the variation selector supplement U+E0100-U+E01EF (category Mn), which no
  emoji uses.
- a variation selector U+FE00-U+FE0F that starts a line or follows another
  variation selector. One selector after an emoji is how text picks emoji or
  text presentation (e.g., the warning sign in decision-analysis), so a single
  one stays allowed; a run of them is how emoji smuggling encodes bytes, and a
  selector with nothing before it doesn't modify anything.

Every mode except explicit paths covers every tracked file, not only plugin
content: Trojan Source targets code, and a hook or script that a bidi control
makes read differently from how it runs is as much a problem as a skill that
does. Only the check's own fixture (``FIXTURE``) is skipped. Modes:

- no arguments: every tracked file as it is in the working tree, for the
  standalone validation (``install-and-verify.sh``). A tracked path missing
  from the working tree doesn't have anything to scan and is skipped.
- ``PATH ...``: the named files, fixture included; the positive control.
- ``--staged``: every file in the index, read from its staged blob, so the
  pre-commit hook checks what the commit will record rather than the working
  tree, which can differ in both directions.
- ``--rev REV``: every file at a revision.
- ``--commits``: commit IDs on standard input, one or more per line; scans the
  files each commit added, copied, modified, renamed, or type-changed, as that
  commit records them, comparing a merge with each parent. A pushed commit
  stays retrievable by its own hash after later commits change it, so each one
  must be clean on its own, not only the tip.
- ``--pre-push REMOTE``: Git's pre-push lines on standard input; scans the
  commits each pushed ref publishes, worked out as
  ``pii-and-secret-gate.sh pre-push`` works them out (see
  :func:`pushed_commits`), then as ``--commits``.

Each finding prints as ``path:line:column: U+XXXX NAME`` on standard output,
with the column counted in code points, and never echoes the line: printing
the text would pass the hidden characters on to whoever reads the output,
including an LLM agent. Paths are escaped for the same reason. A blob scanned
for a commit is named as ``COMMIT:path`` (the first 12 hex digits of the
commit), Git's own notation for a file in a commit. Content that isn't valid
UTF-8 is still scanned, with each malformed sequence read as U+FFFD (Python's
``replace`` handler, which can count a malformed sequence as more than one
column), so a stray byte can't hide the rest of its line.

Exit status: 0 when nothing was found, 1 when findings were printed, and 2
when the scan couldn't finish (e.g., an unreadable file, a missing blob, or a
git failure), with the reason on standard error. Content that can't be read is
an error rather than a pass, so a broken input can't report as clean.

Run it with ``uv run scripts/unicode-scan.py``. It doesn't have
third-party dependencies; it runs under uv, as ``pii-scan.py`` does, so the
repository doesn't need an interpreter beyond the one uv supplies, and ``unicodedata`` gives the
categories and names. They follow the Unicode version of whichever Python uv
picks, so a newer Python can report a format character a newer Unicode version
assigned (e.g., U+0890, added in Unicode 14) that an older one reports as
unassigned and passes.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import unicodedata
from collections.abc import Iterable, Iterator

# The check's own fixture holds one instance of every rule, so it's skipped
# everywhere except when named as a path (the positive control).
FIXTURE = b"scripts/validator-fixtures/invisible-unicode.md"

TAG_BLOCK = range(0xE0000, 0xE0080)
SELECTORS = range(0xFE00, 0xFE10)
SELECTOR_SUPPLEMENT = range(0xE0100, 0xE01F0)

# A gitlink (a submodule's commit) doesn't have content in this repository.
GITLINK_MODE = "160000"

# Git's plumbing follows replace refs (refs/replace/*) by default, so a scan
# would read replacement objects while a commit or push records the originals.
# pii-and-secret-gate.sh sets the same for the same reason.
os.environ["GIT_NO_REPLACE_OBJECTS"] = "1"


class ScanError(Exception):
    """Content that couldn't be listed or read; the scan exits 2."""


def shown(path: bytes) -> str:
    """Escape every byte outside printable ASCII as ``\\xNN``.

    A path is printed where a reviewer or an LLM agent reads it, so a hidden
    character in a filename mustn't reach them any more than one in content.
    """
    return "".join(chr(b) if 0x20 <= b <= 0x7E else f"\\x{b:02X}" for b in path)


def flagged(cp: int, previous: int | None) -> bool:
    """Say whether code point ``cp`` is a finding, given the one before it.

    :param previous: The preceding code point on the line, or ``None`` at the
        start of a line.
    """
    if cp in TAG_BLOCK or cp in SELECTOR_SUPPLEMENT:
        return True
    if cp in SELECTORS:
        return previous is None or previous in SELECTORS or previous in SELECTOR_SUPPLEMENT
    return unicodedata.category(chr(cp)) == "Cf"


def name_of(cp: int) -> str:
    """Name a flagged code point for a finding."""
    if cp in TAG_BLOCK:
        # Not the per-character name: "TAG LATIN SMALL LETTER A" and so on
        # would spell out the smuggled text, one finding per letter.
        return "TAG CHARACTER"
    name = unicodedata.name(chr(cp), "UNASSIGNED")
    if cp in SELECTORS:
        name += " (starts a line or follows another variation selector)"
    return name


def findings(data: bytes) -> Iterator[tuple[int, int, int]]:
    """Yield ``(line, column, code point)`` for each finding in ``data``.

    Lines end at ``\\n`` only, as Git and the editors count them; Python's
    ``splitlines`` would also break at U+2028, U+0085, and form feeds and shift
    every later line number. Every flagged code point is outside ASCII, so a
    line that's all ASCII doesn't need decoding, which skips most of the
    repository.
    """
    if data.isascii():
        return
    for number, raw in enumerate(data.split(b"\n"), start=1):
        if raw.isascii():
            continue
        previous = None
        for column, char in enumerate(raw.decode("utf-8", "replace"), start=1):
            cp = ord(char)
            if cp > 0x7F and flagged(cp, previous):
                yield number, column, cp
            previous = cp


def report(label: str, data: bytes) -> int:
    """Print the findings in ``data`` under ``label`` and return their count."""
    count = 0
    for line, column, cp in findings(data):
        sys.stdout.write(f"{label}:{line}:{column}: U+{cp:04X} {name_of(cp)}\n")
        count += 1
    return count


def git(*args: str, stdin: bytes | None = None) -> bytes:
    """Run git in the repository and return its standard output.

    :raises ScanError: If git exits non-zero, because a listing that failed
        would otherwise read as an empty one, i.e., as nothing to scan.
    """
    result = subprocess.run(["git", *args], input=stdin, capture_output=True)
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip()
        raise ScanError(f"git {args[0]} failed (exit {result.returncode}): {shown(message.encode())}")
    return result.stdout


def nul_fields(output: bytes) -> list[bytes]:
    """Return the fields of ``-z`` output, which git ends with NUL bytes and doesn't quote."""
    return [field for field in output.split(b"\0") if field]


def read_blobs(blobs: dict[str, bytes]) -> Iterator[tuple[bytes, bytes]]:
    """Yield ``(label, content)`` for each blob ID in ``blobs`` (ID -> label).

    One ``git cat-file --batch`` process reads them all, rather than one
    process per file, which would dominate the scan's time.

    :raises ScanError: If an object is missing or isn't a blob.
    """
    if not blobs:
        return
    output = git("cat-file", "--batch", stdin="".join(f"{oid}\n" for oid in blobs).encode())
    position = 0
    for oid, label in blobs.items():
        end = output.index(b"\n", position)
        header = output[position:end].split()
        if len(header) != 3 or header[1] != b"blob":
            raise ScanError(f"can't read {shown(label)} (object {oid}: {shown(b' '.join(header[1:]))})")
        size = int(header[2])
        start = end + 1
        yield label, output[start:start + size]
        position = start + size + 1


def scan_blobs(blobs: dict[str, bytes]) -> int:
    """Report the findings in each blob and return their total."""
    return sum(report(shown(label), content) for label, content in read_blobs(blobs))


def scan_files(paths: Iterable[bytes]) -> int:
    """Report the findings in each file on disk and return their total.

    :raises ScanError: If a file can't be read; a file skipped silently would
        pass unchecked.
    """
    total = 0
    for path in paths:
        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError:
            raise ScanError(f"can't read {shown(path)}") from None
        total += report(shown(path), data)
    return total


def worktree_paths() -> list[bytes]:
    """List the tracked files present in the working tree, fixture excluded.

    ``isfile`` follows symlinks, so a link to a tracked file's content is read
    through the link, and a path deleted from the working tree but still in
    the index is skipped, because there's nothing on disk to scan.
    """
    paths = dict.fromkeys(nul_fields(git("ls-files", "-z")))
    return [path for path in paths if path != FIXTURE and os.path.isfile(path)]


def blobs_from_listing(output: bytes, oid_field: int) -> dict[str, bytes]:
    """Map blob IDs to paths from ``ls-files -s -z`` or ``ls-tree -r -z`` output.

    Both print ``<fields>\\t<path>`` per entry with the mode first; the blob ID
    is field ``oid_field``. Gitlinks and the fixture are skipped, and a blob
    shared by several paths is scanned once, under the first path.
    """
    blobs: dict[str, bytes] = {}
    for entry in nul_fields(output):
        meta, _, path = entry.partition(b"\t")
        fields = meta.decode("ascii").split()
        if fields[0] == GITLINK_MODE or path == FIXTURE:
            continue
        blobs.setdefault(fields[oid_field], path)
    return blobs


def changed_blobs(commits: Iterable[str]) -> dict[str, bytes]:
    """Map the blob IDs each commit records anew to ``COMMIT:path`` labels.

    Mirrors ``files_changed_in`` in ``pii-scan.py``: a merge is compared with
    each parent (``-m``), so content introduced while resolving it is
    included; a root commit is compared with the empty tree; and
    ``--ignore-submodules=none`` keeps a setting that ignores submodules from
    changing the list. ``--raw`` gives each new blob's ID directly.
    """
    blobs: dict[str, bytes] = {}
    for commit in dict.fromkeys(commits):
        output = git(
            "diff-tree", "-m", "--root", "--no-commit-id", "-r", "-z", "--raw",
            "--ignore-submodules=none", "--diff-filter=ACMRT", commit,
        )
        fields = output.split(b"\0")
        index = 0
        # Each entry is ":<old mode> <new mode> <old ID> <new ID> <status>",
        # then the path, or the source and destination paths for a rename or
        # copy.
        while index < len(fields) and fields[index]:
            meta = fields[index].decode("ascii").lstrip(":").split()
            paths = 2 if meta[4][0] in "RC" else 1
            path = fields[index + paths]
            index += paths + 1
            if meta[1] == GITLINK_MODE or path == FIXTURE:
                continue
            blobs.setdefault(meta[3], commit[:12].encode() + b":" + path)
    return blobs


def is_object_id(text: str) -> bool:
    """Say whether ``text`` is a full SHA-1 or SHA-256 object ID."""
    return len(text) in (40, 64) and all(c in "0123456789abcdef" for c in text)


def fetch_destinations(remote: str) -> list[str]:
    """Return where a remote's fetch refspecs store refs.

    Same rules as ``fetch_destinations`` in ``pii-and-secret-gate.sh``: a
    negative refspec, one without a destination, and a pattern with more than
    one ``*`` don't store tracking refs.
    """
    result = subprocess.run(["git", "config", "--get-all", f"remote.{remote}.fetch"], capture_output=True)
    if result.returncode == 1:
        return []  # the key is absent: no fetch refspecs
    if result.returncode != 0:
        raise ScanError(f"couldn't read the fetch refspecs of remote {shown(remote.encode())}")
    destinations = []
    for spec in result.stdout.decode("utf-8", "surrogateescape").splitlines():
        spec = spec.removeprefix("+")
        if spec.startswith("^") or ":" not in spec:
            continue
        destination = spec.partition(":")[2]
        if destination and destination.count("*") <= 1:
            destinations.append(destination)
    return destinations


def matches_destination(ref: str, destination: str) -> bool:
    """Say whether a ref is one a refspec destination (one ``*`` at most) names."""
    if "*" not in destination:
        return ref == destination
    prefix, _, suffix = destination.partition("*")
    return len(ref) >= len(prefix) + len(suffix) and ref.startswith(prefix) and ref.endswith(suffix)


def trusted_tracking_ids(remote: str) -> list[str]:
    """Return the commit IDs the remote's own tracking refs name.

    The pre-push gate excludes these, with their history, from a push whose
    remote tip can't anchor a range, and so does this scan; see the gate's
    comment above that branch for why each condition is needed. In short:
    only a configured remote whose push goes to its fetch URL alone has
    trustworthy tracking refs; only refs under refs/remotes/ that its fetch
    refspecs write count; and a ref another remote's refspecs could also write
    doesn't.
    """
    remotes = git("remote").decode("utf-8", "surrogateescape").splitlines()
    if remote not in remotes:
        return []
    fetch_url = git("remote", "get-url", "--", remote).decode("utf-8", "surrogateescape").rstrip("\n")
    push_urls = git("remote", "get-url", "--push", "--all", "--", remote).decode("utf-8", "surrogateescape").rstrip("\n")
    if not fetch_url or push_urls != fetch_url:
        return []
    own = fetch_destinations(remote)
    others = [d for name in remotes if name and name != remote for d in fetch_destinations(name)]
    tracking = git("for-each-ref", "--format=%(objectname) %(refname)", "refs/remotes/")
    ids = []
    for line in tracking.decode("utf-8", "surrogateescape").splitlines():
        oid, _, ref = line.partition(" ")
        if (oid and any(matches_destination(ref, d) for d in own)
                and not any(matches_destination(ref, d) for d in others)):
            ids.append(oid)
    return list(dict.fromkeys(ids))


def pushed_commits(remote: str, lines: Iterable[str]) -> list[str]:
    """List the commits a push publishes, as ``pii-and-secret-gate.sh`` does.

    For each pre-push line: a deletion doesn't publish anything; a tag is
    peeled to its commit; a remote tip this repository has anchors
    ``remote..local``; otherwise (a new ref, or a tip never fetched) the pushed
    commit's history without what :func:`trusted_tracking_ids` names. The
    gate's own copy of this logic is authoritative; keep the two in step when
    either changes.

    :raises ScanError: If a line doesn't parse or a ref isn't a commit, rather
        than skipping it.
    """
    commits: list[str] = []
    for line in lines:
        if not line:
            continue
        # Parsed from the right: Git writes the local ref as the user typed
        # it, which can contain spaces, while the other three fields can't.
        fields = line.rsplit(" ", 3)
        if len(fields) != 4 or not is_object_id(fields[1]) or not is_object_id(fields[3]):
            raise ScanError(f"couldn't parse the pre-push line {shown(line.encode())}")
        _, local, remote_ref, remote_tip = fields
        if set(local) == {"0"}:
            continue
        tip = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", f"{local}^{{commit}}"], capture_output=True,
        )
        if tip.returncode != 0:
            raise ScanError(f"{shown(remote_ref.encode())} doesn't point at a commit or a tag of one")
        tip_id = tip.stdout.decode("ascii").strip()
        known = set(remote_tip) != {"0"} and subprocess.run(
            ["git", "cat-file", "-e", f"{remote_tip}^{{commit}}"], capture_output=True,
        ).returncode == 0
        if known:
            span = [f"{remote_tip}..{tip_id}"]
        else:
            span = [tip_id, *(f"^{oid}" for oid in trusted_tracking_ids(remote))]
        commits += git("rev-list", *span).decode("ascii").split()
    return list(dict.fromkeys(commits))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Report invisible and bidirectional Unicode; exits 1 on findings, 2 on errors.",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true", help="scan the index rather than the working tree")
    mode.add_argument("--rev", metavar="REV", help="scan every tracked file at REV")
    mode.add_argument("--commits", action="store_true", help="scan what the commits on stdin record anew")
    mode.add_argument("--pre-push", metavar="REMOTE", help="scan what a push publishes, from pre-push lines on stdin")
    parser.add_argument("paths", nargs="*", help="files to scan instead of the tracked files")
    args = parser.parse_args(argv)
    if args.paths and (args.staged or args.rev or args.commits or args.pre_push):
        parser.error("paths can't be combined with a mode")

    if args.paths:
        found = scan_files(os.fsencode(path) for path in args.paths)
    else:
        os.chdir(git("rev-parse", "--show-toplevel").decode("utf-8", "surrogateescape").rstrip("\n"))
        if args.staged:
            found = scan_blobs(blobs_from_listing(git("ls-files", "-s", "-z"), 1))
        elif args.rev:
            found = scan_blobs(blobs_from_listing(git("ls-tree", "-r", "-z", "--full-tree", args.rev), 2))
        elif args.commits:
            found = scan_blobs(changed_blobs(sys.stdin.read().split()))
        elif args.pre_push:
            found = scan_blobs(changed_blobs(pushed_commits(args.pre_push, sys.stdin.read().split("\n"))))
        else:
            paths = worktree_paths()
            if not paths:
                raise ScanError("no tracked files to scan")
            found = scan_files(paths)
    return 1 if found else 0


def run() -> int:
    """Run :func:`main`, turning any failure into exit status 2.

    Python exits 1 on an uncaught exception, the status that means findings
    were printed, so a crash would otherwise read as findings rather than as
    a scan that didn't finish.
    """
    try:
        return main()
    except ScanError as error:
        print(f"unicode-scan.py: {error}", file=sys.stderr)
    except Exception as error:  # noqa: BLE001  (any crash must exit 2, not 1)
        print(f"unicode-scan.py: {type(error).__name__}: {error}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(run())
