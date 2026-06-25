#!/usr/bin/env bash
# Self-contained unit tests for the pure helpers in scripts/helpers.sh.
# tmux is stubbed so behaviour is deterministic; no external test framework.
# Run:  ./tests/run.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- tmux stub -------------------------------------------------------------
# Resolves option values from TMUX_OPTS; every other tmux call is a no-op that
# returns non-zero so callers fall back to defaults. Tests populate TMUX_OPTS.
declare -A TMUX_OPTS=()
tmux() {
  if [ "${1:-}" = show-option ]; then
    # show-option -gqv <name>  ->  $3 is the name
    printf '%s' "${TMUX_OPTS[$3]-}"
    return 0
  fi
  return 1
}
export -f tmux

# shellcheck source=../scripts/helpers.sh
. "$ROOT/scripts/helpers.sh"

# --- tiny assertion harness ------------------------------------------------
pass=0 fail=0
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
  fi
}
bool() { if "$@"; then echo yes; else echo no; fi; } # run predicate -> yes/no

# --- get_opt ---------------------------------------------------------------
TMUX_OPTS=()
check 'get_opt default' 'fallback' "$(get_opt model 'fallback')"
TMUX_OPTS=([@summarize_model]='openai/gpt-5-mini')
check 'get_opt set' 'openai/gpt-5-mini' "$(get_opt model 'fallback')"

# --- summarize_command -----------------------------------------------------
TMUX_OPTS=()
check 'command default' 'summarize' "$(summarize_command)"
TMUX_OPTS=([@summarize_command]='npx -y @steipete/summarize')
check 'command override' 'npx -y @steipete/summarize' "$(summarize_command)"

# --- build_args: unset options are omitted so summarize's own config wins -----
TMUX_OPTS=()
check 'build_args empty' '' "$(build_args)"
TMUX_OPTS=([@summarize_model]='openai/gpt-5-mini' [@summarize_length]='short')
check 'build_args model+length' '--model openai/gpt-5-mini --length short' "$(build_args)"
TMUX_OPTS=([@summarize_language]='vi' [@summarize_extra_args]='--no-color')
check 'build_args language+extra' '--language vi --no-color' "$(build_args)"

# --- is_url ----------------------------------------------------------------
check 'is_url https'      yes "$(bool is_url 'https://youtu.be/dQw4w9WgXcQ')"
check 'is_url with query' yes "$(bool is_url 'https://x.com/a?b=1&c=2')"
check 'is_url plain text' no  "$(bool is_url 'just some words')"
check 'is_url path'       no  "$(bool is_url '/Users/me/notes.md')"
check 'is_url multiline'  no  "$(bool is_url $'https://a.com\nhttps://b.com')"

# --- shq: safe single-quoting, including embedded quotes -------------------
check 'shq simple'    "'plain'"            "$(shq plain)"
check 'shq url'       "'https://x?a&b'"    "$(shq 'https://x?a&b')"
check 'shq embedded'  "'it'\''s'"          "$(shq "it's")"

# --- summary ---------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
