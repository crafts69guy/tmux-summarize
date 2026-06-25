#!/usr/bin/env bash
# Shared helpers for tmux-summarize. Pure functions only (no side effects beyond
# the scratch dir) so tests/run.sh can exercise them with a stubbed tmux.

# get_opt <suffix> <default>
# Reads the user-facing option @summarize_<suffix>, falling back to <default>.
# All options flow through here so the @summarize_* namespace stays canonical.
get_opt() {
  local value
  value="$(tmux show-option -gqv "@summarize_$1" 2>/dev/null)"
  [ -n "$value" ] && { printf '%s' "$value"; return; }
  printf '%s' "$2"
}

# summarize_command -> the CLI to invoke (default: summarize). Override to point
# at a wrapper or a pinned-runtime shim, e.g. set -g @summarize_command 'npx -y @steipete/summarize'
summarize_command() { get_opt command 'summarize'; }

# build_args -> the summarize flags assembled from options, omitting anything
# unset so summarize's own config/`auto` wins. This is what keeps model routing
# "fully configurable, no default": with no @summarize_model the tool decides.
build_args() {
  local out='' v
  v="$(get_opt model '')";    [ -n "$v" ] && out="$out --model $v"
  v="$(get_opt length '')";   [ -n "$v" ] && out="$out --length $v"
  v="$(get_opt language '')"; [ -n "$v" ] && out="$out --language $v"
  v="$(get_opt extra_args '')"; [ -n "$v" ] && out="$out $v"
  printf '%s' "${out# }"
}

# is_url <string> -> 0 if the string is a single bare URL (scheme://…), so the
# caller can hand it to summarize as a positional arg to fetch, rather than
# summarizing the literal text. Anything with whitespace is rejected.
is_url() {
  case "$1" in
  *[[:space:]]*) return 1 ;;
  esac
  printf '%s' "$1" | grep -qiE '^[a-z][a-z0-9+.-]*://.+'
}

# shq <string> -> the string single-quoted for safe inclusion in a shell command
# line (each embedded ' becomes '\''). Used to quote payloads sent to the pane.
shq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# scratch_dir -> a per-user temp dir for captured pane/clipboard/digest content,
# pruning files older than a day so captures don't accumulate. Prints the path.
scratch_dir() {
  local d="${TMPDIR:-/tmp}/tmux-summarize"
  mkdir -p "$d"
  find "$d" -type f -mtime +1 -delete 2>/dev/null
  printf '%s' "$d"
}

# new_tmpfile <name> -> a fresh temp file under scratch_dir, prefixed with <name>.
new_tmpfile() { mktemp "$(scratch_dir)/${1:-tmp}.XXXXXX"; }
