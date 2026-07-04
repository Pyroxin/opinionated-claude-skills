#!/usr/bin/env bash

###
#   harden-codex-config.sh
#
#   Merge Codex hardening into config.toml. MERGES, never overwrites:
#   unrelated settings, MCP servers, plugins, project trust entries, and unknown
#   future keys are preserved; only the keys this tool manages are touched.
#
#   Previews by default - writes nothing unless you pass --write (-w).
#
#   Symlink-safe: if the target is a symlink, the file it points at is updated and
#   the link is preserved. A run that would change nothing writes nothing.
#
#   A changing write re-emits TOML from parsed values. Semantic values are
#   preserved, but comments, blank lines, and original key ordering are not.
#
#   The model is compositional. The base is the full hardening set; each flag
#   relaxes a channel by writing an explicit value, so the config stays robust to
#   future default changes.
#
#   BASE (no flags) - maximum local lockdown:
#     top-level:
#       approval_policy="on-request"        ask before crossing sandbox limits
#       approvals_reviewer="user"           keep approval decisions with the user
#       sandbox_mode="read-only"            no autonomous writes or command side effects
#       allow_login_shell=false             reject login-shell requests
#       check_for_update_on_startup=false   suppress startup update checks
#       web_search="disabled"               disable the web search tool
#     shell_environment_policy:
#       inherit="core", ignore_default_excludes=false
#                                           pass a small env and keep secret filters
#     sandbox_workspace_write:
#       network_access=false                keep spawned commands offline if relaxed
#     analytics / feedback:
#       enabled=false                       disable analytics and /feedback submission
#     otel:
#       exporter="none", trace_exporter="none", metrics_exporter="none",
#       log_user_prompt=false               disable telemetry export and prompt logging
#     features:
#       apps=false, codex_git_commit=false, memories=false
#                                           disable connector/apps, commit attribution,
#                                           and persisted memories
#
#   RELAX flags:
#     --allow-workspace-write     sandbox_mode="workspace-write".
#     --allow-network             sandbox_workspace_write.network_access=true.
#                                Useful only with workspace-write permissions.
#     --allow-web-search          web_search="cached" (OpenAI-maintained cache).
#     --allow-live-web-search     web_search="live"; overrides --allow-web-search.
#     --allow-login-shell         allow_login_shell=true.
#     --allow-updates             check_for_update_on_startup=true.
#     --allow-feedback            feedback.enabled=true.
#     --allow-analytics           analytics.enabled=true.
#     --allow-otel-metrics        otel.metrics_exporter="statsig". Log and trace
#                                exporters remain disabled unless configured later.
#     --allow-apps                features.apps=true.
#     --allow-codex-git-commit    features.codex_git_commit=true.
#     --allow-memories            features.memories=true.
#
#   Operational:
#     -w, --write       Apply the changes. Without it the script only previews.
#     -n, --dry-run     Preview only (the default; wins over --write if both are given).
#         --no-backup   Skip the timestamped backup of the target.
#     -h, --help        Show this help and exit.
#
#   Path: defaults to ${CODEX_HOME:-$HOME/.codex}/config.toml; override by passing
#   one path argument.
#
#   Requires: python3 with tomllib (Python 3.11+). Runs on macOS and Linux.
#
#   Codex may also read ${CODEX_HOME:-$HOME/.codex}/.env for environment values in
#   desktop and IDE contexts. This script does not manage .env because current
#   documented privacy and execution controls are durable config.toml keys.
###

set -euo pipefail

if [ "${PYTHON:-}" ]; then
  python_bin="$PYTHON"
  command -v "$python_bin" >/dev/null 2>&1 || {
    printf 'error: PYTHON points to %s, but it was not found\n' "$python_bin" >&2
    exit 1
  }
  "$python_bin" -c 'import tomllib' >/dev/null 2>&1 || {
    printf 'error: %s does not provide tomllib; use Python 3.11+\n' "$python_bin" >&2
    exit 1
  }
else
  python_bin=""
  for candidate in python3.13 python3.12 python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1 \
      && "$candidate" -c 'import tomllib' >/dev/null 2>&1; then
      python_bin="$candidate"
      break
    fi
  done
  [ -n "$python_bin" ] || {
    printf 'error: Python 3.11+ with tomllib is required but was not found\n' >&2
    exit 1
  }
fi

exec "$python_bin" - "$@" <<'PY'
import copy
import datetime as _datetime
import json
import os
import pathlib
import re
import shutil
import sys
import tempfile

try:
    import tomllib
except ModuleNotFoundError:
    print("error: Python 3.11+ with tomllib is required", file=sys.stderr)
    raise SystemExit(1)

USAGE = """harden-codex-config.sh

Merge Codex hardening into config.toml. Previews by default; pass --write to apply.

Operational:
  -w, --write       Apply the changes
  -n, --dry-run     Preview only (default; wins over --write)
      --no-backup   Skip timestamped backup
  -h, --help        Show this help

Relax flags:
  --allow-workspace-write
  --allow-network
  --allow-web-search
  --allow-live-web-search
  --allow-login-shell
  --allow-updates
  --allow-feedback
  --allow-analytics
  --allow-otel-metrics
  --allow-apps
  --allow-codex-git-commit
  --allow-memories

Path:
  Defaults to ${CODEX_HOME:-$HOME/.codex}/config.toml; override with one path.
"""

SAFE_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")


def die(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def quote_key(key):
    if SAFE_KEY.match(key):
        return key
    return json.dumps(key)


def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (_datetime.datetime, _datetime.date, _datetime.time)):
        return value.isoformat()
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    if isinstance(value, dict):
        items = ", ".join(f"{quote_key(k)} = {toml_value(v)}" for k, v in value.items())
        return "{ " + items + " }"
    die(f"unsupported TOML value type for serialization: {type(value).__name__}")


def is_plain_table(value):
    return isinstance(value, dict)


def is_array_of_tables(value):
    return isinstance(value, list) and bool(value) and all(isinstance(item, dict) for item in value)


def emit_table(lines, path, table, emit_header=True):
    scalar_items = []
    child_tables = []
    array_tables = []

    for key, value in table.items():
        if is_plain_table(value):
            child_tables.append((key, value))
        elif is_array_of_tables(value):
            array_tables.append((key, value))
        else:
            scalar_items.append((key, value))

    if path and emit_header:
        lines.append(f"[{'.'.join(quote_key(part) for part in path)}]")

    for key, value in scalar_items:
        lines.append(f"{quote_key(key)} = {toml_value(value)}")

    for key, value in child_tables:
        if lines and lines[-1] != "":
            lines.append("")
        emit_table(lines, path + [key], value)

    for key, tables in array_tables:
        for item in tables:
            if lines and lines[-1] != "":
                lines.append("")
            lines.append(f"[[{'.'.join(quote_key(part) for part in path + [key])}]]")
            emit_table(lines, path + [key], item, emit_header=False)


def dump_toml(data):
    lines = []
    emit_table(lines, [], data)
    return "\n".join(lines).rstrip() + "\n"


def set_path(data, path, value):
    cursor = data
    for part in path[:-1]:
        existing = cursor.get(part)
        if existing is None:
            existing = {}
            cursor[part] = existing
        if not isinstance(existing, dict):
            dotted = ".".join(path[:-1])
            die(f"existing {dotted} is a {type(existing).__name__}, not a table; refusing to merge")
        cursor = existing
    cursor[path[-1]] = value


def get_path(data, path):
    cursor = data
    for part in path:
        if not isinstance(cursor, dict) or part not in cursor:
            return None, False
        cursor = cursor[part]
    return cursor, True


def preview_value(value):
    return toml_value(value)


def canonical(data):
    return json.dumps(data, sort_keys=True, separators=(",", ":"), default=str)


def parse_args(argv):
    flags = {
        "write": False,
        "dry_run": False,
        "backup": True,
        "allow_workspace_write": False,
        "allow_network": False,
        "allow_web_search": False,
        "allow_live_web_search": False,
        "allow_login_shell": False,
        "allow_updates": False,
        "allow_feedback": False,
        "allow_analytics": False,
        "allow_otel_metrics": False,
        "allow_apps": False,
        "allow_codex_git_commit": False,
        "allow_memories": False,
    }
    target = None
    iterator = iter(argv)
    for arg in iterator:
        if arg in ("-h", "--help"):
            print(USAGE)
            raise SystemExit(0)
        if arg in ("-w", "--write"):
            flags["write"] = True
        elif arg in ("-n", "--dry-run"):
            flags["dry_run"] = True
        elif arg == "--no-backup":
            flags["backup"] = False
        elif arg == "--allow-workspace-write":
            flags["allow_workspace_write"] = True
        elif arg == "--allow-network":
            flags["allow_network"] = True
        elif arg == "--allow-web-search":
            flags["allow_web_search"] = True
        elif arg == "--allow-live-web-search":
            flags["allow_live_web_search"] = True
        elif arg == "--allow-login-shell":
            flags["allow_login_shell"] = True
        elif arg == "--allow-updates":
            flags["allow_updates"] = True
        elif arg == "--allow-feedback":
            flags["allow_feedback"] = True
        elif arg == "--allow-analytics":
            flags["allow_analytics"] = True
        elif arg == "--allow-otel-metrics":
            flags["allow_otel_metrics"] = True
        elif arg == "--allow-apps":
            flags["allow_apps"] = True
        elif arg == "--allow-codex-git-commit":
            flags["allow_codex_git_commit"] = True
        elif arg == "--allow-memories":
            flags["allow_memories"] = True
        elif arg == "--":
            rest = list(iterator)
            if len(rest) > 1 or (rest and target is not None):
                die("more than one path given")
            if rest:
                target = rest[0]
            break
        elif arg.startswith("-"):
            print(USAGE, file=sys.stderr)
            die(f"unknown option: {arg}")
        else:
            if target is not None:
                die(f"more than one path given ('{target}' and '{arg}')")
            target = arg

    if flags["dry_run"]:
        flags["write"] = False

    if target is None:
        codex_home = os.environ.get("CODEX_HOME", os.path.join(os.path.expanduser("~"), ".codex"))
        target = os.path.join(codex_home, "config.toml")

    return flags, pathlib.Path(target).expanduser()


def desired_settings(flags):
    settings = {
        ("approval_policy",): "on-request",
        ("approvals_reviewer",): "user",
        ("sandbox_mode",): "read-only",
        ("allow_login_shell",): False,
        ("check_for_update_on_startup",): False,
        ("web_search",): "disabled",
        ("shell_environment_policy", "inherit"): "core",
        ("shell_environment_policy", "ignore_default_excludes"): False,
        ("sandbox_workspace_write", "network_access"): False,
        ("analytics", "enabled"): False,
        ("feedback", "enabled"): False,
        ("otel", "exporter"): "none",
        ("otel", "trace_exporter"): "none",
        ("otel", "metrics_exporter"): "none",
        ("otel", "log_user_prompt"): False,
        ("features", "apps"): False,
        ("features", "codex_git_commit"): False,
        ("features", "memories"): False,
    }

    if flags["allow_workspace_write"]:
        settings[("sandbox_mode",)] = "workspace-write"
    if flags["allow_network"]:
        settings[("sandbox_workspace_write", "network_access")] = True
    if flags["allow_web_search"]:
        settings[("web_search",)] = "cached"
    if flags["allow_live_web_search"]:
        settings[("web_search",)] = "live"
    if flags["allow_login_shell"]:
        settings[("allow_login_shell",)] = True
    if flags["allow_updates"]:
        settings[("check_for_update_on_startup",)] = True
    if flags["allow_feedback"]:
        settings[("feedback", "enabled")] = True
    if flags["allow_analytics"]:
        settings[("analytics", "enabled")] = True
    if flags["allow_otel_metrics"]:
        settings[("otel", "metrics_exporter")] = "statsig"
    if flags["allow_apps"]:
        settings[("features", "apps")] = True
    if flags["allow_codex_git_commit"]:
        settings[("features", "codex_git_commit")] = True
    if flags["allow_memories"]:
        settings[("features", "memories")] = True

    return settings


def load_config(target, write):
    if target.exists():
        try:
            with target.open("rb") as handle:
                data = tomllib.load(handle)
        except OSError as exc:
            die(f"could not read {target}: {exc}")
        except tomllib.TOMLDecodeError as exc:
            die(f"{target} exists but is not valid TOML: {exc}")
        if not isinstance(data, dict):
            die(f"{target} did not parse to a TOML table; refusing to merge")
        return data

    if write:
        print(f"note: {target} does not exist; it will be created.")
    else:
        print(f"note: {target} does not exist; re-run with --write to create it.")
    return {}


def resolve_symlink_target(path):
    link_target = os.readlink(path)
    if os.path.isabs(link_target):
        return pathlib.Path(link_target)
    return path.parent.joinpath(link_target).absolute()


def parse_toml_file(path):
    try:
        with open(path, "rb") as handle:
            return tomllib.load(handle)
    except OSError as exc:
        die(f"could not read merged result {path}: {exc}")
    except tomllib.TOMLDecodeError as exc:
        die(f"merged result was not valid TOML: {exc}")


def main(argv):
    flags, target = parse_args(argv)
    current = load_config(target, flags["write"])
    merged = copy.deepcopy(current)
    settings = desired_settings(flags)

    for path, value in settings.items():
        set_path(merged, path, value)

    print(f"Hardening changes for {target}:")
    for path, desired in settings.items():
        current_value, exists = get_path(current, path)
        dotted = ".".join(path)
        if not exists:
            print(f"  + {dotted} = {preview_value(desired)}")
        elif current_value != desired:
            print(f"  ~ {dotted}: {preview_value(current_value)} -> {preview_value(desired)}")
        else:
            print(f"  = {dotted} (unchanged)")

    if not flags["write"]:
        print("\n(preview only - nothing written; re-run with --write to apply)")
        return

    if canonical(current) == canonical(merged):
        print("\n(no changes needed - already hardened)")
        return

    write_target = target
    seen_symlinks = set()
    while write_target.is_symlink():
        if write_target in seen_symlinks:
            die(f"symlink cycle detected while resolving {target}")
        seen_symlinks.add(write_target)
        write_target = resolve_symlink_target(target)
        print(f"note: {target} is a symlink -> writing through to {write_target} (link preserved)")
        target = write_target

    write_target.parent.mkdir(parents=True, exist_ok=True)

    if flags["backup"] and write_target.exists():
        stamp = _datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        backup = write_target.with_name(write_target.name + f".bak.{stamp}")
        shutil.copy2(write_target, backup)
        print(f"backup: {backup}")

    rendered = dump_toml(merged)
    fd, tmp_name = tempfile.mkstemp(
        prefix=write_target.name + ".tmp.",
        dir=str(write_target.parent),
        text=True,
    )
    tmp_path = pathlib.Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(rendered)
        reparsed = parse_toml_file(tmp_path)
        if canonical(reparsed) != canonical(merged):
            die("merged result did not round-trip through TOML serialization; target left unchanged")
        if write_target.exists():
            shutil.copymode(write_target, tmp_path)
        os.replace(tmp_path, write_target)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()

    print(f"wrote: {write_target}")


if __name__ == "__main__":
    main(sys.argv[1:])
PY
