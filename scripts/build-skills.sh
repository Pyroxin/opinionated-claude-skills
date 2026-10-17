#!/bin/bash

set -euo pipefail
# Set DEBUG=1 in the environment to enable xtrace for diagnosing
# CI failures or local issues without editing the script.
[[ -n "${DEBUG:-}" ]] && set -x

# Build skill ZIPs for Claude Desktop distribution
#
# DEPRECATED: this script and the ZIP releases it feeds are expected to be
# removed. Claude Code, and on paid plans claude.ai, the Claude Desktop app, and
# Cowork, can add this repository as a plugin marketplace and install its
# plugins directly, so per-skill ZIPs now serve Free-plan users, who don't get
# plugins, and users who upload a single skill by hand.
#
# A skill that couldn't be uploaded outside Claude Code (see
# scripts/portable-skill.sh for the rules and their sources) is skipped with
# its reasons, rather than built into a ZIP that would fail to upload. The check
# needs dasel v3.
#
# Usage: ./scripts/build-skills.sh [output_dir]
#   output_dir: Directory for ZIP files (default: dist)
#
# Environment variables:
#   BUILD_VERSION: Version string used in the ZIP filename (e.g., "20251129-173045.a1b2c3d")
#                  If not set, generates from current timestamp and git SHA
#
# Output format: plugin.skill.VERSION.zip
# Each skill ships as its whole source directory:
#   skill-name/
#   ├── SKILL.md
#   └── every other file the skill bundles

OUTPUT_DIR="${1:-dist}"
mkdir -p "$OUTPUT_DIR"

# Resolve the output directory to an absolute path once. The packaging step runs
# from inside each skill's parent directory so that the ZIP's entries are rooted
# at the skill name; a relative output path would otherwise resolve against that
# directory rather than the caller's.
OUTPUT_ABS="$(cd "$OUTPUT_DIR" && pwd)"

# Generate version if not provided
if [[ -z "${BUILD_VERSION:-}" ]]; then
  timestamp=$(date -u '+%Y%m%d-%H%M%S')
  if git rev-parse --git-dir > /dev/null 2>&1; then
    short_sha=$(git rev-parse --short=7 HEAD)
    BUILD_VERSION="${timestamp}.${short_sha}"
  else
    BUILD_VERSION="${timestamp}"
  fi
fi

echo "DEPRECATED: skill ZIPs are expected to be removed; install the plugins from this repository's marketplace instead." >&2
echo "Build version: ${BUILD_VERSION}"

if ! command -v dasel >/dev/null 2>&1; then
  echo "FATAL: dasel v3 is required but not found on \$PATH." >&2
  exit 1
fi
# shellcheck source-path=SCRIPTDIR source=portable-skill.sh
source "$(cd "$(dirname "$0")" && pwd)/portable-skill.sh"
count=0
skipped=0

for plugin_dir in */; do
  [[ -f "${plugin_dir}.claude-plugin/plugin.json" ]] || continue
  plugin_name=$(basename "$plugin_dir")

  for skill_dir in "${plugin_dir}skills/"*/; do
    [[ -f "${skill_dir}SKILL.md" ]] || continue
    skill_name=$(basename "$skill_dir")

    if ! problems=$(portable_skill_findings "${skill_dir}SKILL.md" "$skill_name"); then
      echo "FATAL: the portability check failed to run on ${skill_dir}SKILL.md; no ZIPs were changed for it" >&2
      exit 1
    fi
    if [[ -n "$problems" ]]; then
      echo "Skipped: ${plugin_name}.${skill_name} (can't be uploaded outside Claude Code)" >&2
      printf '%s\n' "$problems" | sed 's/^/  /' >&2
      # Remove this skill's ZIPs from earlier builds into the same directory,
      # so a skipped skill isn't still published from a stale archive.
      rm -f "${OUTPUT_ABS}/${plugin_name}.${skill_name}."*.zip
      skipped=$((skipped + 1))
      continue
    fi

    zip_name="${plugin_name}.${skill_name}.${BUILD_VERSION}.zip"

    # Remove any existing archive first. zip updates an archive in place rather
    # than replacing it, so a rebuild after a file is deleted from a skill would
    # otherwise keep shipping the deleted file.
    rm -f "${OUTPUT_ABS}/${zip_name}"

    # Package the skill's whole directory. Enumerating a fixed set of "standard"
    # subdirectory names silently drops anything a skill bundles under any other
    # name, so the directory itself is the unit that ships.
    #
    # Which files count as source is delegated to git, so .gitignore stays the
    # single definition of what is not: Emacs backups, autosave and swap files,
    # and OS metadata are all listed there already, and this script does not
    # maintain a competing list that would drift from it. The file set is the
    # union of tracked files and untracked-but-not-ignored ones, so a reference
    # file added to a skill but not yet `git add`ed still ships in a local test
    # build -- listing tracked files alone would reintroduce the silent-drop
    # failure this change exists to remove.
    #
    # This reads git state only; the working tree is never modified. Outside a
    # git checkout (an extracted source archive, say) there is no ignore
    # information to consult, so the directory ships as-is.
    if git rev-parse --git-dir >/dev/null 2>&1; then
      (
        cd "${plugin_dir}skills" &&
          {
            git ls-files -- "$skill_name"
            git ls-files --others --exclude-standard -- "$skill_name"
          } | zip -q "${OUTPUT_ABS}/${zip_name}" -@
      )
    else
      (cd "${plugin_dir}skills" && zip -rq "${OUTPUT_ABS}/${zip_name}" "$skill_name")
    fi

    echo "Built: ${zip_name}"
    count=$((count + 1))
  done
done

echo "Done. Built ${count} skill ZIPs in ${OUTPUT_DIR}/; skipped ${skipped} that can't be uploaded outside Claude Code"
