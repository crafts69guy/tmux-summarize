#!/usr/bin/env bash
# Interactive source picker, shown in a popup (prefix+S when @summarize_picker=fzf).
# A filterable, themed fzf list of the four sources with a live preview of what
# each would summarize; on enter it gathers the content and streams the summary
# INTO THE SAME POPUP (no nested popups), through a login shell so routing env is
# loaded. Theme is inherited from FZF_DEFAULT_OPTS (your Solarized Osaka setup);
# only the layout is pinned, and @summarize_fzf_opts can override anything.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

src="${1:?picker.sh: missing src-pane}"

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-summarize: fzf required for the picker (set @summarize_picker 'menu' for the key-menu)"
  exit 0
fi

# choice \t coloured-icon+label \t hint   (icon colours echo the picker palette)
rows() {
  printf '%s\t%s\t%s\n' pane $'\033[34m●\033[0m pane scrollback' 'this pane'\''s output'
  printf '%s\t%s\t%s\n' clip $'\033[36m●\033[0m clipboard' 'URL or text on the clipboard'
  printf '%s\t%s\t%s\n' url $'\033[33m●\033[0m URL or path' 'type a URL or file path'
  printf '%s\t%s\t%s\n' file $'\033[35m●\033[0m pick a file' 'fzf a file in this directory'
  printf '%s\t%s\t%s\n' digest $'\033[32m●\033[0m cross-pane digest' 'every pane at once'
}

fzf_opts=(
  --ansi --delimiter='\t' --with-nth='2,3' --no-multi
  --reverse --cycle --height=100%
  --preview="$DIR/preview.sh {1} $(shq "$src")"
  --preview-window="$(get_opt preview_window 'right,60%,wrap')"
  --bind='ctrl-/:toggle-preview'
)
# Bordered, labelled regions (fzf >= 0.53), mirroring your _fzf_opts layout.
if fzf --help 2>&1 | grep -q -- '--list-border'; then
  fzf_opts+=(
    --style=full
    --input-border --input-label=' Summarize '
    --list-border --list-label=' Source '
    --preview-border --preview-label=' Preview '
    --color='label:bold' --pointer='▶' --prompt='  '
    --header='enter: summarize · ctrl-/: toggle preview'
  )
else
  fzf_opts+=(--header='Summarize · enter: run · ctrl-/: preview')
fi
# Escape hatch (appended last so it wins). Space-split; guard keeps bash 3.2 happy.
extra="$(get_opt fzf_opts '')"
if [ -n "$extra" ]; then
  read -ra extra_arr <<<"$extra"
  fzf_opts+=("${extra_arr[@]}")
fi

sel="$(rows | fzf "${fzf_opts[@]}")" || exit 0
[ -z "$sel" ] && exit 0
choice="$(printf '%s' "$sel" | cut -f1)"

# Resolve the chosen source to a summarize mode + payload, in this same popup.
mode='' payload=''
case "$choice" in
pane)
  payload="$(new_tmpfile pane.txt)"
  lines="$(get_opt pane_lines '2000')"
  if [ "$lines" = '-' ]; then
    tmux capture-pane -p -J -S - -t "$src" >"$payload"
  else
    tmux capture-pane -p -J -S "-$lines" -t "$src" >"$payload"
  fi
  mode=stdin
  ;;
clip)
  content="$(clipboard_text)"
  [ -z "$content" ] && {
    tmux display-message 'summarize: clipboard is empty'
    exit 0
  }
  if is_url "$content"; then
    mode=arg payload="$content"
  else
    payload="$(new_tmpfile clip.txt)"
    printf '%s' "$content" >"$payload"
    mode=stdin
  fi
  ;;
url)
  printf '\n  %s' "$(printf '\033[1;33mSummarize URL or path:\033[0m ')"
  IFS= read -r payload || exit 0
  [ -z "$payload" ] && exit 0
  mode=arg
  ;;
file)
  payload="$(pick_file "$src")"
  [ -z "$payload" ] && exit 0
  mode=arg
  ;;
digest)
  payload="$(new_tmpfile digest.md)"
  build_digest "$src" >"$payload"
  [ -s "$payload" ] || {
    tmux display-message 'summarize: nothing to digest'
    exit 0
  }
  mode=stdin
  ;;
*) exit 0 ;;
esac

bin="$(summarize_command)"
if ! command -v "${bin%% *}" >/dev/null 2>&1; then
  tmux display-message "summarize: '${bin%% *}' not found in PATH — install @steipete/summarize"
  exit 0
fi

base="$(summarize_command) $(build_args)"
case "$mode" in
arg) line="$base $(shq "$payload")" ;;
stdin) line="$base - < $(shq "$payload")" ;;
esac

# Replace the picker with the summary in this same popup, via a login shell so the
# environment (OPENAI_BASE_URL, keys) matches a normal pane. The shell-agnostic
# `sh -c read` hold keeps the summary on screen until Enter.
hold="; printf '\n[done — press Enter to close]'; sh -c 'read REPLY'"
exec "$(login_shell)" -l -c "$line$hold"
