#!/usr/bin/env bash
# Summarize the system clipboard or copy-mode selection. Arg: <src-pane>
# A bare URL or existing file path is handed to summarize to fetch/read; any
# other text is summarized as-is via stdin.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

src="${1:?clipboard.sh: missing src-pane}"

# Prefer the system clipboard (tmux-yank syncs copy-mode yanks there), then fall
# back to the most recent tmux paste buffer for setups without a clipboard tool.
content=''
if command -v pbpaste >/dev/null 2>&1; then
  content="$(pbpaste 2>/dev/null)"
elif command -v wl-paste >/dev/null 2>&1; then
  content="$(wl-paste --no-newline 2>/dev/null)"
elif command -v xclip >/dev/null 2>&1; then
  content="$(xclip -selection clipboard -o 2>/dev/null)"
fi
[ -z "$content" ] && content="$(tmux show-buffer 2>/dev/null)"

if [ -z "$content" ]; then
  tmux display-message 'summarize: clipboard is empty'
  exit 0
fi

if is_url "$content" || [ -f "$content" ]; then
  exec "$DIR/run.sh" arg "$content" "$src"
fi

tmp="$(new_tmpfile clip.txt)"
printf '%s' "$content" >"$tmp"
exec "$DIR/run.sh" stdin "$tmp" "$src"
