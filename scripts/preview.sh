#!/usr/bin/env bash
# Live preview for the source picker: given a choice + source pane, show what
# that source would feed to summarize. Args: <choice> <src-pane>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

choice="${1:-}"
src="${2:-}"

case "$choice" in
pane)
  # -e keeps colours; fzf renders them via --ansi.
  tmux capture-pane -ep -t "$src" 2>/dev/null | tail -n 200
  ;;
clip)
  content="$(clipboard_text)"
  if [ -z "$content" ]; then
    printf '(clipboard is empty)'
  else
    printf '%s' "$content" | head -n 200
  fi
  ;;
url)
  printf 'Type a URL (https://…, a YouTube/podcast link) or a file path\nafter selecting this row, then press Enter.'
  ;;
file)
  printf 'Pick a file in this directory via fzf (with a bat preview),\nthen it is summarized.'
  ;;
digest)
  printf '# panes that will be summarized\n\n'
  scope="$(get_opt digest_scope 'window')"
  case "$scope" in
  session) args=(-s -t "$src") ;;
  *) args=(-t "$src") ;;
  esac
  tmux list-panes "${args[@]}" \
    -F '  #{window_index}.#{pane_index}  #{pane_current_command}  (#{pane_width}x#{pane_height})' 2>/dev/null
  ;;
*) : ;;
esac
