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

# login_shell -> the shell to run a popup summary through. Prefers an explicit
# @summarize_shell, then tmux's default-shell (what panes actually use), then
# $SHELL. This matters when the interactive shell differs from $SHELL — e.g. fish
# panes under a zsh $SHELL: run as a login shell it loads the same environment as
# a normal pane, including any OPENAI_BASE_URL used for proxy routing.
login_shell() {
  local s
  s="$(get_opt shell '')"
  [ -n "$s" ] && { printf '%s' "$s"; return; }
  s="$(tmux show-option -gv default-shell 2>/dev/null)"
  [ -n "$s" ] && { printf '%s' "$s"; return; }
  printf '%s' "${SHELL:-/bin/sh}"
}

# popup_dims -> "<width> <height>" for display-popup, from @summarize_popup_width /
# @summarize_popup_height (defaults 80%/80%). Read with: read -r w h < <(popup_dims)
popup_dims() {
  printf '%s %s' \
    "$(get_opt popup_width '80%')" \
    "$(get_opt popup_height '80%')"
}

# wait_pane_ready <pane-id>
# Best-effort wait until a freshly split pane's interactive shell has started, so
# send-keys isn't swallowed by shell startup. Polls #{pane_current_command} for a
# known shell name, then settles briefly. Bounded (~2s) and always returns 0.
wait_pane_ready() {
  local p="$1" cmd _
  for _ in $(seq 1 40); do
    cmd="$(tmux display-message -p -t "$p" '#{pane_current_command}' 2>/dev/null)"
    case "$cmd" in
    fish | bash | zsh | sh | dash | -fish | -bash | -zsh)
      sleep 0.05
      return 0
      ;;
    esac
    sleep 0.05
  done
  return 0
}

# ---------------------------------------------------------------------------
# Shared content capture (reused by the direct-key scripts and the fzf picker)
# ---------------------------------------------------------------------------

# clipboard_text -> system clipboard (then most-recent tmux buffer) as-is.
clipboard_text() {
  local c=''
  if command -v pbpaste >/dev/null 2>&1; then
    c="$(pbpaste 2>/dev/null)"
  elif command -v wl-paste >/dev/null 2>&1; then
    c="$(wl-paste --no-newline 2>/dev/null)"
  elif command -v xclip >/dev/null 2>&1; then
    c="$(xclip -selection clipboard -o 2>/dev/null)"
  fi
  [ -z "$c" ] && c="$(tmux show-buffer 2>/dev/null)"
  printf '%s' "$c"
}

# build_digest <src-pane> -> markdown concatenation of every pane's visible
# content to stdout. Scope from @summarize_digest_scope (window|session).
build_digest() {
  local src="$1" scope label pid cmd
  scope="$(get_opt digest_scope 'window')"
  local list_args
  case "$scope" in
  session) list_args=(-s -t "$src") ;;
  *) list_args=(-t "$src") ;;
  esac
  while read -r label pid cmd; do
    [ -z "$pid" ] && continue
    printf '### pane %s (%s)\n\n' "$label" "$cmd"
    tmux capture-pane -p -J -t "$pid"
    printf '\n\n'
  done < <(tmux list-panes "${list_args[@]}" \
    -F '#{window_index}.#{pane_index} #{pane_id} #{pane_current_command}')
}

# pick_file <src-pane> -> a file chosen via fzf (bat preview when available) from
# the pane's cwd, printed to stdout. Runs in the current TTY (popup); empty if none.
pick_file() {
  local src="$1" cwd preview find_cmd
  cwd="$(tmux display-message -p -t "$src" '#{pane_current_path}' 2>/dev/null)"
  # Best-effort: list from the pane's cwd; if the cd fails just use the current one.
  # shellcheck disable=SC2164
  [ -n "$cwd" ] && cd "$cwd" 2>/dev/null || true
  preview='cat {}'
  command -v bat >/dev/null 2>&1 && preview='bat --color=always --style=numbers {}'
  local fopts=(--ansi --reverse --cycle --height=100% --preview="$preview"
    --preview-window="$(get_opt preview_window 'right,60%,wrap')"
    --bind='ctrl-/:toggle-preview')
  # Mirror the source picker's layout (picker.sh) so both file/source screens match.
  if fzf --help 2>&1 | grep -q -- '--list-border'; then
    fopts+=(--style=full
      --input-border   --input-label=' File '
      --list-border    --list-label=' Files '
      --preview-border --preview-label=' Preview '
      --color='label:bold' --pointer='▶' --prompt='  '
      --header='enter: summarize · ctrl-/: toggle preview')
  fi
  find_cmd="${FZF_DEFAULT_COMMAND:-find . -type f -not -path '*/.git/*'}"
  sh -c "$find_cmd" | fzf "${fopts[@]}"
}

# ---------------------------------------------------------------------------
# Chrome / theming. Defaults are Solarized Osaka (yellow #b58900 accent, matching
# the active-window highlight); every value is overridable via @summarize_*.
# ---------------------------------------------------------------------------
border_lines() { get_opt border_lines 'rounded'; }
border_style() { get_opt border_style 'fg=#b58900'; }
popup_title() { get_opt title '#[fg=#b58900,bold] Summarize '; }
menu_body_style() { get_opt menu_style 'fg=#839496,bg=#002b36'; }
menu_selected_style() { get_opt menu_selected 'fg=#002b36,bg=#b58900,bold'; }

# ---------------------------------------------------------------------------
# Source identity + output chrome — the single source of truth so every screen
# (fzf picker, key-menu, popup/split summary) names a source identically and the
# run stage matches the picker. ANSI escapes (not tmux #[...] tags) because the
# summary runs inside a shell, not a tmux format context.
# ---------------------------------------------------------------------------

# accent_ansi / dim_ansi / reset_ansi -> the output palette. The accent default
# is Solarized Osaka yellow (#b58900 ≈ 256-colour 136), echoing the picker border;
# override with @summarize_accent_color / @summarize_dim_color (256-colour codes).
accent_ansi() { printf '\033[1;38;5;%sm' "$(get_opt accent_color '136')"; }
dim_ansi()    { printf '\033[38;5;%sm'  "$(get_opt dim_color '240')"; }
reset_ansi()  { printf '\033[0m'; }

# source_label_plain <choice> -> the bare source name. Unknown -> the choice
# verbatim (or 'source' when empty), so callers always get something printable.
source_label_plain() {
  case "$1" in
  pane)   printf 'pane scrollback' ;;
  clip)   printf 'clipboard' ;;
  url)    printf 'URL or path' ;;
  file)   printf 'file' ;;
  digest) printf 'cross-pane digest' ;;
  *)      printf '%s' "${1:-source}" ;;
  esac
}

# source_label <choice> -> the coloured "● name" used in picker rows AND the
# summary header, so the icon palette lives in exactly one place.
source_label() {
  local r icon
  r="$(reset_ansi)"
  case "$1" in
  pane)   icon=$'\033[34m●' ;;
  clip)   icon=$'\033[36m●' ;;
  url)    icon=$'\033[33m●' ;;
  file)   icon=$'\033[35m●' ;;
  digest) icon=$'\033[32m●' ;;
  *)      icon=$'\033[1;33m●' ;;
  esac
  printf '%s%s %s' "$icon" "$r" "$(source_label_plain "$1")"
}

# summary_header <coloured-label> -> banner printed before a summary streams,
# echoing the chosen source and the resolved model.
summary_header() {
  local a d r model
  a="$(accent_ansi)" d="$(dim_ansi)" r="$(reset_ansi)"
  model="$(get_opt model '')"; [ -n "$model" ] || model='auto'
  printf '%s▌ Summarize%s\n' "$a" "$r"
  printf '  %s\n' "$1"
  printf '  %smodel%s  %s\n\n' "$d" "$r" "$model"
}

# summary_footer -> themed hold line printed after a summary.
summary_footer() {
  local a r
  a="$(accent_ansi)" r="$(reset_ansi)"
  printf '\n%s──── done ────%s  %senter%s close\n' "$a" "$r" "$a" "$r"
}

# summary_header_md <choice> -> the header as Markdown, so it can be fed through
# glow/bat and scroll together with the summary (a tmux popup has no scrollback of
# its own, so the body is paged; an ANSI header printed before the pager would be
# hidden on the pager's alternate screen).
summary_header_md() {
  local model
  model="$(get_opt model '')"; [ -n "$model" ] || model='auto'
  # The backticks are literal Markdown (inline code), not command substitution.
  # shellcheck disable=SC2016
  printf '## ▌ Summarize · %s\n\n`model: %s`\n\n---\n\n' "$(source_label_plain "$1")" "$model"
}

# resolve_renderer -> glow | bat | none, honouring @summarize_render
# (auto = glow → bat → raw) and actual availability. A named-but-missing renderer
# degrades to none rather than erroring.
resolve_renderer() {
  local choice r
  choice="$(get_opt render 'auto')"
  case "$choice" in
  none) printf none; return ;;
  glow | bat) r="$choice" ;;
  auto)
    if command -v glow >/dev/null 2>&1; then r=glow
    elif command -v bat >/dev/null 2>&1; then r=bat
    else printf none; return; fi ;;
  *) printf none; return ;;
  esac
  command -v "$r" >/dev/null 2>&1 && printf '%s' "$r" || printf none
}

# render_fragment <renderer> <paged:yes|no> -> the inline pipe fragment that
# renders the summary markdown (no header), for screens that already scroll: the
# split pane (real scrollback) and the no-pager popup. Empty for raw passthrough.
# Kept availability-free so the shape is testable without glow/bat installed.
render_fragment() {
  local r="$1" paged="${2:-no}"
  case "$r" in
  glow) [ "$paged" = yes ] && printf '| glow -p' || printf '| glow -' ;;
  bat)
    if [ "$paged" = yes ]; then
      printf '| bat --language=markdown --style=plain --color=always --paging=always'
    else
      printf '| bat --language=markdown --style=plain --color=always --paging=never'
    fi ;;
  *) : ;;
  esac
}

# frame_command <inner-cmd> <choice> -> the popup command line. By default the
# summary is shown in the renderer's own pager (glow -p / bat --paging) so it is
# scrollable — the header is prepended as Markdown into the same stream so it
# scrolls too. Set @summarize_pager 'off' for the old read-hold (not scrollable).
# Header/body are assembled here (bash) and embedded as literal printf args, so the
# line works whatever login shell runs it (fish/zsh). The split path renders inline
# via render_fragment instead (real panes already scroll) — see run.sh.
frame_command() {
  local inner="$1" choice="$2" r hdr ftr
  # printf-x trick preserves the trailing blank lines that $() would strip.
  if [ "$(get_opt pager 'on')" = off ]; then
    inner="$inner $(render_fragment "$(resolve_renderer)" no)"
    hdr="$(summary_header "$(source_label "$choice")"; printf x)"; hdr="${hdr%x}"
    ftr="$(summary_footer; printf x)"; ftr="${ftr%x}"
    printf '%s' "printf '%s' $(shq "$hdr"); $inner; printf '%s' $(shq "$ftr"); sh -c 'read REPLY'"
    return
  fi
  r="$(resolve_renderer)"
  case "$r" in
  glow | bat)
    hdr="$(summary_header_md "$choice"; printf x)"; hdr="${hdr%x}"
    printf '%s' "{ printf '%s' $(shq "$hdr"); $inner; } $(render_fragment "$r" yes)" ;;
  *)
    # Raw: keep the ANSI header and page through less (-R passes the colours).
    hdr="$(summary_header "$(source_label "$choice")"; printf x)"; hdr="${hdr%x}"
    printf '%s' "{ printf '%s' $(shq "$hdr"); $inner; } | less -R" ;;
  esac
}
