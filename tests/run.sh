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

# --- login_shell: @summarize_shell > default-shell > $SHELL ----------------
TMUX_OPTS=([default-shell]='/opt/homebrew/bin/fish')
check 'login_shell from default-shell' '/opt/homebrew/bin/fish' "$(login_shell)"
TMUX_OPTS=([@summarize_shell]='/usr/bin/zsh' [default-shell]='/opt/homebrew/bin/fish')
check 'login_shell override wins' '/usr/bin/zsh' "$(login_shell)"

# --- popup_dims: defaults and overrides ------------------------------------
TMUX_OPTS=()
check 'popup_dims defaults' '80% 80%' "$(popup_dims)"
TMUX_OPTS=([@summarize_popup_width]='70%' [@summarize_popup_height]='60%')
check 'popup_dims overrides' '70% 60%' "$(popup_dims)"

# --- theming helpers: Osaka defaults, overridable --------------------------
TMUX_OPTS=()
check 'border_lines default' 'rounded' "$(border_lines)"
check 'border_style default' 'fg=#b58900' "$(border_style)"
check 'popup_title default' '#[fg=#b58900,bold] Summarize ' "$(popup_title)"
check 'menu_selected default' 'fg=#002b36,bg=#b58900,bold' "$(menu_selected_style)"
TMUX_OPTS=([@summarize_border_lines]='double' [@summarize_border_style]='fg=#268bd2')
check 'border_lines override' 'double' "$(border_lines)"
check 'border_style override' 'fg=#268bd2' "$(border_style)"

# --- shq: safe single-quoting, including embedded quotes -------------------
check 'shq simple'    "'plain'"            "$(shq plain)"
check 'shq url'       "'https://x?a&b'"    "$(shq 'https://x?a&b')"
check 'shq embedded'  "'it'\''s'"          "$(shq "it's")"

# --- source_label_plain: one place names every source ----------------------
TMUX_OPTS=()
check 'label pane'    'pane scrollback'    "$(source_label_plain pane)"
check 'label clip'    'clipboard'          "$(source_label_plain clip)"
check 'label digest'  'cross-pane digest'  "$(source_label_plain digest)"
check 'label empty'   'source'             "$(source_label_plain '')"

# has_substr <haystack> <needle> -> yes/no, for asserting on chrome that carries
# ANSI escapes we don't want to pin byte-for-byte.
has_substr() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

# --- summary_header: echoes the chosen source + resolved model -------------
TMUX_OPTS=([@summarize_model]='openai/gpt-5-mini')
hdr="$(summary_header "$(source_label pane)")"
check 'header has model'  yes "$(has_substr "$hdr" 'openai/gpt-5-mini')"
check 'header has source' yes "$(has_substr "$hdr" 'pane scrollback')"
TMUX_OPTS=()
check 'header model auto'  yes "$(has_substr "$(summary_header x)" 'auto')"

# --- frame_command: wraps inner cmd; holds only when asked -----------------
TMUX_OPTS=()
frm="$(frame_command 'summarize -' pane yes)"
check 'frame keeps inner' yes "$(has_substr "$frm" 'summarize -')"
check 'frame holds'       yes "$(has_substr "$frm" 'read REPLY')"
frm="$(frame_command 'summarize -' pane no)"
check 'frame no-hold'     no  "$(has_substr "$frm" 'read REPLY')"

# --- render: glow/bat by default, opt out with none ------------------------
check 'render frag glow' '| glow -' "$(render_fragment glow)"
check 'render frag bat'  '| bat --language=markdown --style=plain --color=always --paging=never' "$(render_fragment bat)"
check 'render frag none' '' "$(render_fragment '')"
TMUX_OPTS=([@summarize_render]='none')
check 'render none opt'  '' "$(render_pipe)"

# --- summary ---------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
