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
#       cli_auth_credentials_store="keyring"
#                                           keep login credentials in the OS credential
#                                           store, never in a plaintext auth.json, so the
#                                           Codex home doesn't hold anything for a sandboxed
#                                           tool (e.g., another agent's commands) to read. An
#                                           auth.json left by an earlier file-based login
#                                           isn't removed; the script warns when one exists.
#     shell_environment_policy:
#       inherit="core", ignore_default_excludes=false
#                                           pass a small env and keep secret filters
#       filters.<NAME>="exclude"            exclude the Anthropic, OpenAI/Codex, AWS,
#                                           Google, and Azure credential variables by
#                                           name, the same list harden-claude-config.sh
#                                           denies to Claude Code (CREDENTIAL_ENV_VARS
#                                           below); a config already using the legacy
#                                           exclude or include_only arrays gets the
#                                           names in its exclude array instead, and
#                                           one mixing both forms stops the script.
#                                           Any of these names in
#                                           shell_environment_policy.set is removed,
#                                           since `set` applies after the excludes.
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
#       shell_snapshot=false                Codex's shell snapshot (on by default) puts
#                                           variables shell_environment_policy removed
#                                           back into the environment of commands the
#                                           model runs, so the excludes above don't hold
#                                           with it on
#                                           (https://github.com/openai/codex/issues/22124).
#                                           Cost: commands no longer get the snapshot's
#                                           shell environment, so a tool found only
#                                           through shell startup files (e.g., a PATH
#                                           entry added in ~/.zshrc) may not be found;
#                                           the script prints a note when it turns the
#                                           snapshot off. Revisit when #22124 is fixed.
#     computer use:
#       plugins."unified-computer-use@openai-bundled".enabled=false
#                                           disable the bundled Computer Use plugin, which
#                                           lets Codex operate desktop apps
#       notify                              removed when it runs the Computer Use client
#                                           (SkyComputerUseClient), which the plugin's
#                                           installer sets to run at the end of every turn,
#                                           including behind env, nohup, or exec, or as a
#                                           command inside sh -c (e.g., after ; or &&);
#                                           any other notify command is left alone, with
#                                           a warning when it mentions the client but
#                                           doesn't plainly run it (e.g., the name as an
#                                           argument to echo, after a # comment, or in
#                                           a heredoc)
#     A trusted project's own config can turn the plugin back on, because Codex
#     lets trusted-project settings override user settings for plugins. To block
#     Computer Use and its reinstallation everywhere, an administrator can set
#     [features] computer_use = false in /etc/codex/requirements.toml, which users
#     and projects can't override; this script doesn't write system files.
#
#   RELAX flags:
#     --allow-workspace-write     sandbox_mode="workspace-write".
#     --allow-network             sandbox_workspace_write.network_access=true.
#                                Useful only with workspace-write permissions.
#                                Commands that need the network then run without
#                                asking, git push included: with on-request
#                                approvals Codex asks only when a command needs to
#                                leave the sandbox, and in the base posture a push
#                                asks only because it can't reach the network.
#                                Without [features.network_proxy] and a domain
#                                allowlist (not managed by this script), the access
#                                is unrestricted. See
#                                https://learn.chatgpt.com/docs/agent-approvals-security
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
#     --allow-shell-snapshot      features.shell_snapshot=true. Restores tools found
#                                only through shell startup files, at the cost of
#                                the environment excludes (openai/codex#22124).
#     --allow-file-credentials    cli_auth_credentials_store="auto": use the OS
#                                credential store when available, otherwise fall
#                                back to a plaintext auth.json. For headless Linux
#                                hosts without a keyring, where "keyring" makes
#                                login fail.
#     --allow-computer-use        plugins."unified-computer-use@openai-bundled"
#                                .enabled=true, and notify is left as it is.
#
#   CONTEXT WINDOW AND COMPACTION (removed unless a flag keeps or sets them):
#     By default the script removes model_context_window and
#     model_auto_compact_token_limit, so both come from Codex's model metadata.
#     Top-level keys only: these flags read and write the top-level
#     model_context_window and model_auto_compact_token_limit, and the match
#     flag reads only the top-level model. The same keys in a
#     [profiles.<name>] table are left as they are, with a warning, and apply
#     when that profile is selected.
#     The catalog bundled with Codex gives GPT-6.1 Sol a 272,000-token
#     context_window (the default) and an 872,000-token max_context_window
#     (codex-rs/models-manager/models.json; at a09812981de7,
#     https://github.com/openai/codex/blob/a09812981de703f18f38015cd5d500ab373f616c/codex-rs/models-manager/models.json#L177-L211).
#     OpenAI's model page says Sol uses a 500K default window in Codex
#     (https://developers.openai.com/api/docs/models/gpt-6.1-sol), which
#     doesn't match the bundled catalog's 272,000.
#     Each flag states an intent; a value is given only with the flag that
#     allows an arbitrary one.
#
#     model_context_window is the ceiling Codex plans against, and a request
#     past the model's real limit fails. model_auto_compact_token_limit is the
#     point where Codex summarizes history. Neither changes how the model
#     computes; they decide how much history Codex sends. Codex's config
#     reference doesn't say how the two interact. Codex clamps a configured
#     window to the model metadata's max_context_window (with_config_overrides
#     in codex-rs/models-manager/src/model_info.rs,
#     https://github.com/openai/codex/blob/a09812981de703f18f38015cd5d500ab373f616c/codex-rs/models-manager/src/model_info.rs#L19-L28;
#     https://github.com/openai/codex/issues/19185) and compacts at the lower
#     of the limit and 90% of the clamped window
#     (https://github.com/openai/codex/issues/11805).
#
#     --match-context-window-to-input-limit
#                                model_context_window = the configured model's
#                                maximum input tokens (window minus maximum
#                                output), the most history a request can carry.
#                                Codex may use a lower window whether or not
#                                this flag is given: it caps any window at the
#                                model metadata's max_context_window, which for
#                                the four models in the bundled catalog is
#                                872,000, below their 922,000-token input limit.
#                                The script writes the input limit anyway, so
#                                the setting gains capacity when Codex raises
#                                its cap.
#                                Fails when the top-level `model` isn't set or
#                                isn't in the script's table of limits derived
#                                from OpenAI's published figures; use
#                                --allow-arbitrary-context-window with
#                                --context-window-size for other models.
#     --allow-arbitrary-context-window
#                                Keep model_context_window as it is, e.g., a value
#                                set for a Bedrock or other provider's model.
#     --context-window-size N    model_context_window = N; requires
#                                --allow-arbitrary-context-window, to confirm the
#                                intent; contradicts
#                                --match-context-window-to-input-limit. Each
#                                value flag may be given once. A compaction
#                                limit at or above the window set here (or by
#                                the match flag, or kept by
#                                --allow-arbitrary-context-window) draws a
#                                warning, since it then never takes effect.
#     --allow-arbitrary-compaction-limit
#                                Keep model_auto_compact_token_limit as it is.
#     --compaction-limit N       model_auto_compact_token_limit = N; requires
#                                --allow-arbitrary-compaction-limit. Useful with a
#                                large window when tokens are billed per request:
#                                OpenAI's API prices a request to each model in
#                                the table below with more than 272,000 input
#                                tokens at a higher rate for the whole request
#                                (see each model's page), so compacting below
#                                that keeps normal turns cheap while a single
#                                large turn can still complete instead of failing.
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
#
#   Two other controls are left out on purpose:
#     Per-path read denies (e.g., ~/.ssh, ~/.aws): sandbox_mode can't express
#     them. Permission profiles can (a filesystem "deny" entry), but they are in
#     beta, and Codex ignores them whenever sandbox_mode is set in any loaded
#     config, so this script stays on sandbox_mode. Revisit when profiles leave
#     beta: https://learn.chatgpt.com/docs/permissions
#     Command rules (.rules files, e.g., a "prompt" rule for git push): the
#     rules page calls them experimental, and a prompt rule for git push is
#     reported not to fire under danger-full-access
#     (https://github.com/openai/codex/issues/25312), so
#     this script doesn't write any: https://learn.chatgpt.com/docs/agent-configuration/rules
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
import shlex
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
  --allow-shell-snapshot
  --allow-file-credentials
  --allow-computer-use

Context window and compaction (removed unless one of these is given):
  --match-context-window-to-input-limit
      Request the model's input limit (context window minus maximum output).
  --allow-arbitrary-context-window [--context-window-size N]
  --allow-arbitrary-compaction-limit [--compaction-limit N]

  Codex may use a lower context window than the one requested, with or
  without these flags: it caps any window at its model metadata's
  max_context_window. See CONTEXT WINDOW AND COMPACTION in this script's
  header comment.

Path:
  Defaults to ${CODEX_HOME:-$HOME/.codex}/config.toml; override with one path.
"""

SAFE_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")

# The bundled Computer Use plugin's config key, and the client program its
# installer registers as the notify command.
COMPUTER_USE_PLUGIN = "unified-computer-use@openai-bundled"
COMPUTER_USE_CLIENT = "SkyComputerUseClient"

# Programs that run another program named in their arguments, so the program a
# notify command really runs can sit behind them.
ENV_LAUNCHER = "env"
WRAPPERS = {"exec", "nohup"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish"}

# env's options, so an option's argument isn't mistaken for the program (e.g.,
# the NAME in `env -u NAME prog`). GNU and BSD env differ: -C is GNU's, -P is
# BSD's; both are accepted, since either env may be the one installed. An
# option outside these sets makes the command unreadable rather than guessed.
ENV_SHORT_FLAGS = "0iv"
ENV_SHORT_WITH_ARG = "uCPS"
ENV_LONG_FLAGS = {"--ignore-environment", "--null", "--debug"}
ENV_LONG_WITH_ARG = {"--unset": "u", "--chdir": "C", "--split-string": "S"}

# A shell assignment prefix (NAME=value before the program). env's own rule is
# looser (any word with "="), so env's arguments are checked separately.
SHELL_ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")

# Characters shlex returns as operator tokens in a -c command. A newline ends a
# command like ";" does, so it's an operator here rather than whitespace.
SHELL_PUNCTUATION = "();<>|&\n"

# Credential variables excluded by name from the environment of commands Codex
# runs: the same list harden-claude-config.sh denies to Claude Code's sandboxed
# commands, so the two hardening scripts strip the same names. inherit="core"
# already starts from a short allowlist; the names are excluded as well because
# filters merge across config layers, so they stay excluded even where a
# profile or project config widens inheritance (e.g., inherit="all").
CREDENTIAL_ENV_VARS = (
    # Anthropic
    "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
    "ANTHROPIC_FOUNDRY_API_KEY", "ANTHROPIC_FOUNDRY_AUTH_TOKEN", "ANTHROPIC_AWS_API_KEY",
    "AWS_BEARER_TOKEN_BEDROCK",
    # OpenAI and Codex, including Codex's own launch context
    # (NON_INHERITABLE_ENV_VARS in
    # https://github.com/openai/codex/blob/main/codex-rs/protocol/src/shell_environment.rs).
    # Codex removes these from the commands it starts; naming them here also
    # covers a session started in the same environment as Codex (e.g., a
    # container where they're set).
    "OPENAI_API_KEY", "OPENAI_ADMIN_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN",
    "CODEX_EXEC_SERVER_NOISE_AUTH_TOKEN", "NODE_REPL_AUTH_TOKEN",
    "CODEX_GUARDIAN_DECISIONS_API_KEY", "OPENAI_FEDERATION_RULE_ID",
    "OPENAI_IDENTITY_TOKEN_FILE", "OPENAI_WORKLOAD_IDENTITY_CONTEXT",
    # AWS
    "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_ACCESS_KEY",
    "AWS_SECRET_KEY", "AWS_CONTAINER_AUTHORIZATION_TOKEN",
    "AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE", "AWS_CONTAINER_CREDENTIALS_FULL_URI",
    "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "AWS_WEB_IDENTITY_TOKEN_FILE", "AWS_PROFILE",
    # Google
    "GOOGLE_API_KEY", "GEMINI_API_KEY",
    # Azure
    "AZURE_CLIENT_SECRET", "AZURE_CLIENT_CERTIFICATE_PASSWORD", "AZURE_OPENAI_API_KEY",
    "AZURE_OPENAI_AD_TOKEN",
)


def skip_env_arguments(words, index):
    """Skip env's options and assignments, starting at ``words[index]``.

    An option's argument is consumed whether it's attached (``-uNAME``,
    ``--unset=NAME``) or the next word. A ``-S`` string is split into words
    that replace it, and scanning continues through them, since env treats
    them as more of its own arguments.

    :returns: ``(words, index)`` with ``index`` at the program, or None when
        an option isn't one env is known to take.
    """
    while index < len(words):
        word = words[index]
        if word == "--":
            index += 1
            break
        if word == "-":
            index += 1
            continue
        if word.startswith("--"):
            name, has_value, value = word.partition("=")
            if name in ENV_LONG_FLAGS and not has_value:
                index += 1
                continue
            if name not in ENV_LONG_WITH_ARG:
                return None
            option = ENV_LONG_WITH_ARG[name]
            if has_value:
                argument, index = value, index + 1
            elif index + 1 < len(words):
                argument, index = words[index + 1], index + 2
            else:
                return None
        elif word.startswith("-"):
            option = None
            for position, letter in enumerate(word[1:], start=1):
                if letter in ENV_SHORT_FLAGS:
                    continue
                if letter not in ENV_SHORT_WITH_ARG:
                    return None
                option = letter
                break
            if option is None:
                index += 1
                continue
            attached = word[position + 1:]
            if attached:
                argument, index = attached, index + 1
            elif index + 1 < len(words):
                argument, index = words[index + 1], index + 2
            else:
                return None
        else:
            break
        if option == "S":
            try:
                split = shlex.split(argument)
            except ValueError:
                return None
            words = words[:index] + split + words[index:]
    while index < len(words) and "=" in words[index]:
        index += 1
    return words, index


def skip_wrapper_options(name, words, index):
    """Skip a wrapper's options, returning the program's index or None.

    nohup doesn't take any options a notify command would use; the shell's
    exec takes -c, -l, and -a NAME. Anything else is unreadable rather than guessed.
    """
    if index < len(words) and words[index] == "--":
        return index + 1
    while name == "exec" and index < len(words) and words[index].startswith("-"):
        word = words[index]
        if word == "-a":
            index += 2
        elif set(word[1:]) <= {"c", "l"}:
            index += 1
        else:
            return None
    if index < len(words) and words[index].startswith("-"):
        return None
    return index


def shell_command_string(args):
    """Return the command string a shell runs with -c, or None.

    The shell's options come first: -c may be combined with others (e.g.,
    ``-lc``, ``-ec``), and -o, -O, --rcfile, and --init-file take an argument.
    The command string is the first word after the options. Without -c the
    shell runs a script file, which this script doesn't read.
    """
    index = 0
    runs_string = False
    while index < len(args):
        arg = args[index]
        if arg == "--":
            index += 1
            break
        if arg.startswith("--"):
            index += 2 if arg in ("--rcfile", "--init-file") else 1
            continue
        if len(arg) > 1 and arg[0] in "-+":
            letters = arg[1:]
            if arg[0] == "-" and "c" in letters:
                runs_string = True
            index += 2 if ("o" in letters or "O" in letters) else 1
            continue
        break
    if not runs_string or index >= len(args):
        return None
    return args[index]


def simple_commands(command):
    """Split a shell command string into the words of each simple command.

    Commands are separated by ``;``, ``&&``, ``||``, ``|``, ``&``, and
    newlines. A redirection and the word after it are dropped, since that word
    is a file, not a program. Parentheses stay as words, so a command inside a
    subshell is never read as being in command position.

    shlex in POSIX mode returns a quoted ``";"`` the same as an operator, so
    the string is also split in non-POSIX mode, which keeps the quotes: a token
    counts as an operator only when both splits agree on it.

    Two constructs make the string unreadable instead of being parsed. A word
    starting with an unquoted ``#`` begins a comment, and a heredoc (``<<``,
    ``<<-``) or here-string (``<<<``) feeds the lines or word after it to the
    command as input. Reading either as code could find the client in text
    the shell never runs and delete a notify command the user wrote, and
    modeling them exactly (where a comment ends, which lines a heredoc spans)
    adds parsing that can itself be wrong; reporting them unreadable keeps
    notify in place with a warning instead.

    :raises ValueError: when the string can't be split (e.g., an unbalanced
        quote), the two splits don't line up, or it holds a comment, a
        heredoc, or a here-string.
    """
    def tokens(posix):
        lexer = shlex.shlex(command, posix=posix, punctuation_chars=SHELL_PUNCTUATION)
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        lexer.commenters = ""
        return list(lexer)

    words, raw = tokens(True), tokens(False)
    if len(words) != len(raw):
        raise ValueError("ambiguous quoting")
    commands = [[]]
    skip_operand = False
    for word, raw_word in zip(words, raw):
        is_operator = word == raw_word and word != "" and all(ch in SHELL_PUNCTUATION for ch in word)
        # The raw token is checked, so a quoted "#" (raw '#') stays a word.
        # An operator splits off from the word after it, so `true;#x` still
        # yields a token starting with "#".
        if not is_operator and raw_word.startswith("#"):
            raise ValueError("comment")
        if is_operator and "<<" in word:
            raise ValueError("heredoc or here-string")
        if skip_operand:
            skip_operand = False
        elif is_operator and ("<" in word or ">" in word):
            skip_operand = True
        elif is_operator and "(" not in word and ")" not in word:
            commands.append([])
        else:
            commands[-1].append(word)
    return commands


def shell_runs_client(args):
    """Report whether a shell's -c command runs the client in command position.

    The client counts as run only as the program of a simple command; any
    other mention (e.g., an argument to echo, printf, or test) is unreadable,
    so the caller warns and leaves notify in place.
    """
    command = shell_command_string(args)
    if command is None:
        return None
    try:
        commands = simple_commands(command)
    except ValueError:
        return None
    results = [program_runs_client(words, shell_words=True) for words in commands]
    if True in results:
        return True
    if None in results or COMPUTER_USE_CLIENT in command:
        return None
    return False


def notify_runs_computer_use(notify):
    """Report whether a notify command runs the Computer Use client.

    The program is identified by its file name, not by a substring of the
    command, so another program whose name merely contains the client's (e.g.,
    a status reporter) is left alone. The program is found behind ``env`` (with
    its options, their arguments, and VAR=value assignments), ``nohup``, and
    ``exec``, and inside a shell's ``-c`` command, where it must be in command
    position.

    :returns: True when the client is the program run, False when another
        program is, and None when the command can't be read with confidence
        (e.g., a shell running a script, or an unparseable ``-c`` command),
        so the caller leaves notify in place instead of guessing.
    """
    return program_runs_client([str(arg) for arg in notify])


def program_runs_client(words, shell_words=False):
    """Apply notify_runs_computer_use's rules to one command's words.

    ``shell_words`` marks a simple command from a shell string, where leading
    NAME=value words are assignments rather than the program.
    """
    index = 0
    while index < len(words):
        word = words[index]
        if shell_words and SHELL_ASSIGNMENT.match(word):
            index += 1
            continue
        shell_words = False
        name = os.path.basename(word)
        if name == ENV_LAUNCHER:
            skipped = skip_env_arguments(words, index + 1)
            if skipped is None:
                return None
            words, index = skipped
            continue
        if name in WRAPPERS:
            index = skip_wrapper_options(name, words, index + 1)
            if index is None:
                return None
            continue
        if name in SHELLS:
            return shell_runs_client(words[index + 1:])
        return name == COMPUTER_USE_CLIENT
    return False

# Maximum input tokens per model, for --match-context-window-to-input-limit,
# derived as the context window minus the maximum output. Each model's page
# (https://developers.openai.com/api/docs/models/<model>, e.g.,
# https://developers.openai.com/api/docs/models/gpt-6.1-sol) lists a
# 1,050,000-token context window and 128,000 maximum output tokens for all
# four, as of 2026-11-01. These are API figures; Codex clamps the configured
# window to its own max_context_window (see CONTEXT WINDOW AND COMPACTION in
# the header).
# Add a model only with a source for both numbers; a model missing here makes
# the option fail rather than guess.
MODEL_INPUT_TOKEN_LIMITS = {
    "gpt-6-astra": 922_000,
    "gpt-6.1-sol": 922_000,
    "gpt-6.1-terra": 922_000,
    "gpt-6-luna": 922_000,
}


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
        "allow_shell_snapshot": False,
        "allow_file_credentials": False,
        "allow_computer_use": False,
        "match_context_window_to_input_limit": False,
        "allow_arbitrary_context_window": False,
        "context_window_size": None,
        "allow_arbitrary_compaction_limit": False,
        "compaction_limit": None,
    }

    def token_count(option, value):
        # isdigit() accepts any Unicode decimal digit (e.g., "٣"), which int()
        # converts and the config stores in ASCII. It also accepts digits int()
        # rejects (e.g., the superscript "²"), so that ValueError becomes the
        # same usage error instead of a traceback.
        if value is None or not value.isdigit():
            die(f"{option} needs a positive whole number of tokens")
        try:
            count = int(value)
        except ValueError:
            die(f"{option} needs a positive whole number of tokens")
        if count <= 0:
            die(f"{option} needs a positive whole number of tokens")
        return count

    def set_token_count(key, option, value):
        # A second value would silently replace the first, so which one the
        # user meant is unclear; refuse rather than pick.
        if flags[key] is not None:
            die(f"{option} given more than once")
        flags[key] = token_count(option, value)
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
        elif arg == "--allow-shell-snapshot":
            flags["allow_shell_snapshot"] = True
        elif arg == "--allow-file-credentials":
            flags["allow_file_credentials"] = True
        elif arg == "--allow-computer-use":
            flags["allow_computer_use"] = True
        elif arg == "--match-context-window-to-input-limit":
            flags["match_context_window_to_input_limit"] = True
        elif arg == "--allow-arbitrary-context-window":
            flags["allow_arbitrary_context_window"] = True
        elif arg == "--context-window-size":
            set_token_count("context_window_size", arg, next(iterator, None))
        elif arg.startswith("--context-window-size="):
            set_token_count("context_window_size", "--context-window-size", arg.split("=", 1)[1])
        elif arg == "--allow-arbitrary-compaction-limit":
            flags["allow_arbitrary_compaction_limit"] = True
        elif arg == "--compaction-limit":
            set_token_count("compaction_limit", arg, next(iterator, None))
        elif arg.startswith("--compaction-limit="):
            set_token_count("compaction_limit", "--compaction-limit", arg.split("=", 1)[1])
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

    # The contradiction is checked first: with it, adding the flag a "requires"
    # error asks for would only lead to this error next.
    if flags["match_context_window_to_input_limit"]:
        for option, given in (
            ("--allow-arbitrary-context-window", flags["allow_arbitrary_context_window"]),
            ("--context-window-size", flags["context_window_size"] is not None),
        ):
            if given:
                die(f"--match-context-window-to-input-limit and {option} contradict each other")
    # A value is accepted only with the flag that allows an arbitrary one, so a
    # stray number can't pin a setting the user meant to leave to the catalog.
    if flags["context_window_size"] is not None and not flags["allow_arbitrary_context_window"]:
        die("--context-window-size requires --allow-arbitrary-context-window")
    if flags["compaction_limit"] is not None and not flags["allow_arbitrary_compaction_limit"]:
        die("--compaction-limit requires --allow-arbitrary-compaction-limit")

    if target is None:
        codex_home = os.environ.get("CODEX_HOME", os.path.join(os.path.expanduser("~"), ".codex"))
        target = os.path.join(codex_home, "config.toml")

    return flags, pathlib.Path(target).expanduser()


def warn_about_profile_overrides(flags, current):
    """Warn about profile keys the context window handling doesn't read.

    The script manages only the top-level model_context_window and
    model_auto_compact_token_limit, and the match flag reads only the
    top-level model. A profile's own values apply when that profile is
    selected, so they're named here rather than silently left in force.
    """
    profiles, _ = get_path(current, ("profiles",))
    if not isinstance(profiles, dict):
        return
    keys = ["model_context_window", "model_auto_compact_token_limit"]
    if flags["match_context_window_to_input_limit"]:
        keys.append("model")
    for name, profile in profiles.items():
        if not isinstance(profile, dict):
            continue
        for key in keys:
            if key in profile:
                print(
                    f"warning: profiles.{quote_key(name)}.{key} is left as it is; this "
                    "script reads and manages only the top-level key.",
                    file=sys.stderr,
                )


def desired_settings(flags, current):
    settings = {
        ("approval_policy",): "on-request",
        ("approvals_reviewer",): "user",
        ("sandbox_mode",): "read-only",
        ("allow_login_shell",): False,
        ("check_for_update_on_startup",): False,
        ("web_search",): "disabled",
        ("cli_auth_credentials_store",): "keyring",
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
        # Off because the snapshot overlay restores variables the environment
        # policy removed (openai/codex#22124); see the header for the cost.
        ("features", "shell_snapshot"): False,
        ("plugins", COMPUTER_USE_PLUGIN, "enabled"): False,
    }

    # Name the credential variables as excludes. Codex rejects the canonical
    # `filters` table in a layer that also has the legacy `exclude` or
    # `include_only` arrays, so a config already using either gets the names
    # added to its legacy `exclude` array instead. Entries the user added stay.
    # A config that already mixes the two forms, or holds a legacy value that
    # isn't a list of strings, can't be merged into correctly, so the script
    # stops and names the keys rather than writing a config Codex won't load.
    policy, _ = get_path(current, ("shell_environment_policy",))
    legacy = [key for key in ("exclude", "include_only") if isinstance(policy, dict) and key in policy]
    if legacy and "filters" in policy:
        die("shell_environment_policy mixes `filters` with the legacy "
            + " and ".join(f"`{key}`" for key in legacy)
            + "; Codex refuses to load that, so convert one form to the other first")
    for key in legacy:
        value = policy[key]
        if not (isinstance(value, list) and all(isinstance(item, str) for item in value)):
            die(f"shell_environment_policy.{key} isn't a list of strings; fix it before hardening")
    if legacy:
        existing = policy.get("exclude", [])
        settings[("shell_environment_policy", "exclude")] = existing + [
            name for name in CREDENTIAL_ENV_VARS if name not in existing
        ]
    else:
        for name in CREDENTIAL_ENV_VARS:
            settings[("shell_environment_policy", "filters", name)] = "exclude"

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
    if flags["allow_shell_snapshot"]:
        settings[("features", "shell_snapshot")] = True
    if flags["allow_file_credentials"]:
        settings[("cli_auth_credentials_store",)] = "auto"
    if flags["allow_computer_use"]:
        settings[("plugins", COMPUTER_USE_PLUGIN, "enabled")] = True
    warn_about_profile_overrides(flags, current)
    if flags["match_context_window_to_input_limit"]:
        model, exists = get_path(current, ("model",))
        if not exists:
            die("--match-context-window-to-input-limit needs the top-level `model` set in "
                "the config, because the limit depends on the model")
        if model not in MODEL_INPUT_TOKEN_LIMITS:
            die(f"no known input limit for model {model!r}; use "
                "--allow-arbitrary-context-window --context-window-size N for it")
        settings[("model_context_window",)] = MODEL_INPUT_TOKEN_LIMITS[model]
    if flags["context_window_size"] is not None:
        settings[("model_context_window",)] = flags["context_window_size"]
    if flags["compaction_limit"] is not None:
        settings[("model_auto_compact_token_limit",)] = flags["compaction_limit"]
        # Codex compacts at the lower of the limit and 90% of the window (see
        # the header), so a limit at or above the window never takes effect.
        # The window is the one this run writes, or the one
        # --allow-arbitrary-context-window keeps.
        window = settings.get(("model_context_window",))
        if window is None and flags["allow_arbitrary_context_window"]:
            window, _ = get_path(current, ("model_context_window",))
        # bool is a subclass of int, and a non-integer kept value can't be
        # compared with the limit, so either is skipped rather than misread.
        if (isinstance(window, int) and not isinstance(window, bool)
                and flags["compaction_limit"] >= window):
            print(
                f"warning: the compaction limit ({flags['compaction_limit']}) is at or above "
                f"the context window ({window}), so it won't take effect: Codex compacts at "
                "the lower of the limit and 90% of the window.",
                file=sys.stderr,
            )

    return settings


def removals(flags, current):
    """Return the key paths to delete from the config.

    A notify command that runs the Computer Use client is removed unless
    Computer Use is allowed; any other notify command is the user's and stays.
    The context window and compaction limit are removed unless a flag keeps or
    sets them, so by default both come from the model catalog. A credential
    variable named in shell_environment_policy.set is removed from it, because
    Codex applies `set` after its excludes, so a value there would reach every
    command despite them.
    """
    paths = []
    env_set, _ = get_path(current, ("shell_environment_policy", "set"))
    if isinstance(env_set, dict):
        managed = {name.upper() for name in CREDENTIAL_ENV_VARS}
        paths += [("shell_environment_policy", "set", key) for key in env_set if key.upper() in managed]
    notify, exists = get_path(current, ("notify",))
    if not flags["allow_computer_use"] and exists and isinstance(notify, list) and notify:
        runs_client = notify_runs_computer_use(notify)
        if runs_client:
            paths.append(("notify",))
        # Only a command that names the client draws the warning. One that
        # can't be read but doesn't name it (e.g., a shell running a script)
        # is the user's, and warning on it at every run would teach the user
        # to ignore the warning.
        elif any(COMPUTER_USE_CLIENT in str(arg) for arg in notify):
            print(
                f"warning: notify mentions {COMPUTER_USE_CLIENT} but doesn't plainly run it, "
                "so it was left in place; remove it by hand if it starts Computer Use.",
                file=sys.stderr,
            )
    window_kept = flags["match_context_window_to_input_limit"] or flags["allow_arbitrary_context_window"]
    for key, kept in (("model_context_window", window_kept),
                      ("model_auto_compact_token_limit", flags["allow_arbitrary_compaction_limit"])):
        if not kept and get_path(current, (key,))[1]:
            paths.append((key,))
    return paths


def note_shell_snapshot_off(current, settings):
    """Explain the cost when this run turns the shell snapshot off.

    Printed only when the setting changes, so a rerun on an already-hardened
    config stays quiet.
    """
    path = ("features", "shell_snapshot")
    current_value, exists = get_path(current, path)
    if settings.get(path) is False and (not exists or current_value is not False):
        print(
            "note: features.shell_snapshot=false keeps the environment excludes in force "
            "(openai/codex#22124), but commands no longer get the snapshot's shell "
            "environment, so a tool found only through shell startup files (e.g., a PATH "
            "entry added in ~/.zshrc) may not be found. Use --allow-shell-snapshot to "
            "turn it back on.",
            file=sys.stderr,
        )


def warn_about_plaintext_credentials(target, settings):
    """Warn when keyring storage is set but a plaintext auth.json remains.

    Switching the store doesn't delete credentials an earlier file-based login
    wrote, and those stay readable to anything that can read the Codex home.
    """
    if settings.get(("cli_auth_credentials_store",)) != "keyring":
        return
    auth_file = target.parent / "auth.json"
    if auth_file.exists():
        print(
            f"warning: {auth_file} holds plaintext credentials from a file-based login. "
            "After confirming Codex works with the keyring store, delete it.",
            file=sys.stderr,
        )


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
    settings = desired_settings(flags, current)

    for path, value in settings.items():
        set_path(merged, path, value)
    to_remove = removals(flags, current)
    for path in to_remove:
        parent, _ = get_path(merged, path[:-1]) if len(path) > 1 else (merged, True)
        parent.pop(path[-1], None)

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
    for path in to_remove:
        current_value, _ = get_path(current, path)
        # A removed credential value isn't echoed, so the preview can't print a secret.
        if path[:2] == ("shell_environment_policy", "set"):
            print(f"  - {'.'.join(path)} (removed)")
        else:
            print(f"  - {'.'.join(path)} (removed, was {preview_value(current_value)})")
    warn_about_plaintext_credentials(target, settings)
    note_shell_snapshot_off(current, settings)

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
