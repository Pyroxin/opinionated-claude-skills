# shellcheck shell=bash
#
# portable_skill_findings FILE DIR
#
# Prints one line for each reason the SKILL.md at FILE couldn't be uploaded
# outside Claude Code, and doesn't print anything when it can be; returns 0 in
# both cases. DIR is the name of the skill's directory, which the skill's name
# has to match.
# Returns 2, with the reason on standard error, when the check itself fails
# (e.g., FILE can't be read, dasel fails for a reason other than unreadable
# YAML, or dasel returns output this function doesn't recognize), so callers
# stop instead of treating a broken check as a finding. Requires dasel v3.
#
# Sourced by install-and-verify.sh, which reports each line as a warning, and by
# build-skills.sh, which skips the skill instead of building a ZIP that would
# fail to upload. Keeping the rules in this one file keeps the two from drifting.
#
# The frontmatter is the block between a "---" line at the top of the file and
# the next "---" line; dasel parses it as YAML, so quoting, escapes, block
# scalars, nulls, and collections are read the way YAML defines them.
#
# The rules, as of October 2026:
#   - claude.ai skill uploads, the Skills API, and skill-creator's
#     package_skill.py accept only the frontmatter fields name, description,
#     license, compatibility, metadata, and allowed-tools, and fail with an error
#     on any other key; enabling a personal skill for Cowork is an upload too
#     (Claude Code docs, skills page, "Using skill frontmatter outside Claude
#     Code"). Inside Claude Code, a plugin skill can use every field in that
#     page's frontmatter table, so a skill this check flags still works there.
#   - name: 1-64 characters of lowercase letters, numbers, and hyphens, not
#     starting or ending with a hyphen, without consecutive hyphens, matching
#     the skill's directory name (Agent Skills specification, agentskills.io,
#     "name field"; claude.com docs, skills how-to, "Required fields"); no
#     reserved words "anthropic" or "claude" (Claude Platform docs, skills
#     guide, "Request limits").
#   - description: 1-1,024 characters (specification, "description field");
#     no XML tags (skills guide, "Request limits"), checked as any run of the
#     form <...> whose first character isn't whitespace, which also flags
#     comparisons such as "a <= b >= c".
#   - compatibility: optional, but if the key is present, a string of 1-500
#     characters (specification, "compatibility field"). A present key with a
#     YAML null (e.g., "compatibility:" with nothing after it) or an empty
#     string is reported as empty, because the specification counts the field
#     as provided once the key is there; an absent key is fine.
#
# The query returns a YAML list of finding codes, which this function turns into
# messages. Every code is a plain token (a field name with characters other than
# letters, digits, "_", ".", and "-" is reported without its name), so dasel
# prints each as one "- code" line and no YAML quoting has to be undone. Behaviors of dasel 3.11.2 that shape the query, each confirmed by
# running it: len() counts bytes, so character counts use len(split("")); &&
# evaluates both sides, so guards on a value that may be missing use the ternary
# operator, which doesn't; after a ";", a bare property is read from the
# previous statement's result, so fields are read through $root; inside
# filter(), a method call such as contains($this) rebinds $this, so keys are
# compared with != instead; a regex literal can't contain "/", so \x2F stands
# for it; and consecutive "//" comment lines fail to parse, which is why the
# query's explanation lives here rather than in the query.

# shellcheck disable=SC2016 # a dasel query; its $ names are dasel variables
PORTABLE_SKILL_QUERY='
$isMap = typeOf($root) == "map";

$fieldCodes = $isMap ? $root.keys().filter(
  (toString($this) != "name") && (toString($this) != "description") &&
  (toString($this) != "license") && (toString($this) != "compatibility") &&
  (toString($this) != "metadata") && (toString($this) != "allowed-tools")
).map((toString($this) =~ r/^[A-Za-z0-9_.-]+$/) ? ("field " + toString($this)) : "field-unusual") : [];

$name = $isMap ? ($root.has("name") ? $root.name : null) : null;
$nameType = typeOf($name);
$nameCodes = ($nameType == "null") ? ["name-missing"] : (
  ($nameType != "string") ? ["name-not-text"] : (
    (len($name) == 0) ? ["name-missing"] : [
      ($name =~ r/^[a-z0-9-]+$/) ? [] : ["name-chars"],
      ($name =~ r/^-|-$|--/) ? ["name-hyphens"] : [],
      (len($name.split("")) > 64) ? ["name-length " + toString(len($name.split("")))] : [],
      ($name =~ r/anthropic|claude/) ? ["name-reserved"] : [],
      ($name == $PORTABLE_SKILL_DIR) ? [] : ["name-dir"]
    ].flatten()
  )
);

$description = $isMap ? ($root.has("description") ? $root.description : null) : null;
$descriptionType = typeOf($description);
$descriptionCodes = ($descriptionType == "null") ? ["description-missing"] : (
  ($descriptionType != "string") ? ["description-not-text"] : (
    (len($description) == 0) ? ["description-missing"] : [
      (len($description.split("")) > 1024) ? ["description-length " + toString(len($description.split("")))] : [],
      ($description =~ r/<[^\s<>][^<>]*>/) ? ["description-xml"] : []
    ].flatten()
  )
);

$hasCompatibility = $isMap ? $root.has("compatibility") : false;
$compatibility = $hasCompatibility ? $root.compatibility : null;
$compatibilityType = typeOf($compatibility);
$compatibilityCodes = $hasCompatibility ? (
  ($compatibilityType == "null") ? ["compatibility-empty"] : (
    ($compatibilityType != "string") ? ["compatibility-not-text"] : (
      (len($compatibility) == 0) ? ["compatibility-empty"] : (
        (len($compatibility.split("")) > 500) ? ["compatibility-length " + toString(len($compatibility.split("")))] : []
      )
    )
  )
) : [];

$isMap ? [$fieldCodes, $nameCodes, $descriptionCodes, $compatibilityCodes].flatten() : ["not-map"]
'

portable_skill_findings() {
  local file="$1" dir="$2" line count=0 closed=0 frontmatter="" output code
  # A file the loop below can't open reads as empty, which would be reported
  # as "no frontmatter" and make the build skip the skill (deleting its old
  # ZIPs) instead of stopping. Fail instead, so callers treat it as an error.
  if [[ ! -r "$file" ]]; then
    echo "portable_skill_findings: can't read ${file}" >&2
    return 2
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    count=$((count + 1))
    if [[ "$count" -eq 1 ]]; then
      if [[ ! "$line" =~ ^---[[:space:]]*$ ]]; then
        echo "no frontmatter block on line 1"
        return 0
      fi
      continue
    fi
    if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
      closed=1
      break
    fi
    frontmatter+="${line}"$'\n'
  done < "$file"
  if [[ "$count" -eq 0 ]]; then
    echo "no frontmatter block on line 1"
    return 0
  fi
  if [[ "$closed" -eq 0 ]]; then
    echo "frontmatter block isn't terminated"
    return 0
  fi

  if ! output=$(printf '%s' "$frontmatter" | PORTABLE_SKILL_DIR="$dir" dasel query -i yaml -o yaml "$PORTABLE_SKILL_QUERY" 2>&1); then
    output="${output#dasel: error: }"
    # dasel reports a YAML parse failure as "error reading input"; anything
    # else (e.g., a query error from an incompatible dasel) is a broken check.
    if [[ "$output" == "error reading input"* ]]; then
      echo "frontmatter isn't valid YAML (${output%%$'\n'*})"
      return 0
    fi
    echo "portable_skill_findings: dasel failed on ${file}: ${output}" >&2
    return 2
  fi

  # The output is "[]" or one "- code" line per finding; anything else means
  # the query or dasel changed, so the check fails rather than guessing.
  # A pipe rather than process substitution, which some sandboxes forbid; the
  # loop runs in a subshell, so its exit status carries the verdict.
  [[ "$output" == "[]" ]] && return 0
  if ! printf '%s\n' "$output" | while IFS= read -r line; do
    [[ "$line" =~ ^-\ [a-z][a-z0-9-]*(\ [A-Za-z0-9_.-]+)?$ ]] || exit 1
  done; then
    echo "portable_skill_findings: unexpected dasel output for ${file}: ${output}" >&2
    return 2
  fi

  printf '%s\n' "$output" | while IFS= read -r line; do
    code="${line#- }"
    case "$code" in
      "field "*) echo "frontmatter field \"${code#field }\" isn't accepted outside Claude Code" ;;
      field-unusual) echo "a frontmatter field whose name has characters other than letters, digits, \"_\", \".\", and \"-\" isn't accepted outside Claude Code" ;;
      not-map) echo "frontmatter isn't a mapping of fields" ;;
      name-missing) echo "frontmatter doesn't have a name" ;;
      name-not-text) echo "name isn't text" ;;
      name-chars) echo "name has characters other than lowercase letters, numbers, and hyphens" ;;
      name-hyphens) echo "name starts or ends with a hyphen or has consecutive hyphens" ;;
      "name-length "*) echo "name is ${code#name-length } characters; the limit is 64" ;;
      name-reserved) echo "name contains a reserved word (\"anthropic\" or \"claude\")" ;;
      name-dir) echo "name doesn't match the directory name \"${dir}\"" ;;
      description-missing) echo "frontmatter doesn't have a description" ;;
      description-not-text) echo "description isn't text" ;;
      "description-length "*) echo "description is ${code#description-length } characters; the limit is 1,024" ;;
      description-xml) echo "description contains an XML tag" ;;
      compatibility-empty) echo "compatibility is empty; give it 1-500 characters or remove the key" ;;
      compatibility-not-text) echo "compatibility isn't text" ;;
      "compatibility-length "*) echo "compatibility is ${code#compatibility-length } characters; the limit is 500" ;;
      *)
        echo "portable_skill_findings: unrecognized finding code from the query: ${code}" >&2
        exit 2
        ;;
    esac
  done
}
