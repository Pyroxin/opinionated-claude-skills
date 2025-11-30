#!/bin/bash

set -euo pipefail

# Build skill ZIPs for Claude Desktop distribution
#
# Usage: ./scripts/build-skills.sh [output_dir]
#   output_dir: Directory for ZIP files (default: dist)
#
# Environment variables:
#   BUILD_VERSION: Version string to inject (e.g., "20251129-173045.a1b2c3d")
#                  If not set, generates from current timestamp and git SHA
#
# Output format: plugin.skill.VERSION.zip
# Each skill is packaged as:
#   skill-name/
#   ├── SKILL.md  (with version injected into frontmatter)
#   └── resources/  (if present)

OUTPUT_DIR="${1:-dist}"
mkdir -p "$OUTPUT_DIR"

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

echo "Build version: ${BUILD_VERSION}"

# Inject version into SKILL.md frontmatter
# Adds version line after name line (name is mandatory, description is optional)
inject_version() {
  local src="$1"
  local dst="$2"
  local version="$3"

  # Insert version: line after the name: line in frontmatter
  awk -v ver="$version" '
    /^name:/ { print; print "version: " ver; next }
    { print }
  ' "$src" > "$dst"
}

count=0

for plugin_dir in */; do
  [[ -f "${plugin_dir}plugin.json" ]] || continue
  plugin_name=$(basename "$plugin_dir")

  for skill_dir in "${plugin_dir}skills/"*/; do
    [[ -f "${skill_dir}SKILL.md" ]] || continue
    skill_name=$(basename "$skill_dir")

    zip_name="${plugin_name}.${skill_name}.${BUILD_VERSION}.zip"

    # Create temp structure: skill-name/SKILL.md
    temp_dir=$(mktemp -d)
    mkdir -p "${temp_dir}/${skill_name}"

    # Copy SKILL.md with version injected
    inject_version "${skill_dir}SKILL.md" "${temp_dir}/${skill_name}/SKILL.md" "$BUILD_VERSION"

    # Copy resources if present
    if [[ -d "${skill_dir}resources" ]]; then
      cp -r "${skill_dir}resources" "${temp_dir}/${skill_name}/"
    fi

    # Create ZIP with folder as root (required by Claude Desktop)
    (cd "$temp_dir" && zip -rq "${OLDPWD}/${OUTPUT_DIR}/${zip_name}" "${skill_name}")
    rm -rf "$temp_dir"

    echo "Built: ${zip_name}"
    count=$((count + 1))
  done
done

echo "Done. Built ${count} skill ZIPs in ${OUTPUT_DIR}/"
