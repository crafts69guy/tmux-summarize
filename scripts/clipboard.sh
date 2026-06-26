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
content="$(clipboard_text)"

if [ -z "$content" ]; then
  tmux display-message 'summarize: clipboard is empty'
  exit 0
fi

# A bare URL goes straight to summarize. A file path is resolved against the
# source pane's cwd (not run-shell's), so a relative path on the clipboard works.
if is_url "$content"; then
  exec "$DIR/run.sh" arg "$content" "$src" clip
fi
cwd="$(tmux display-message -p -t "$src" '#{pane_current_path}' 2>/dev/null)"
case "$content" in
/*) resolved="$content" ;;
*) resolved="${cwd:+$cwd/}$content" ;;
esac
if [ -f "$resolved" ]; then
  exec "$DIR/run.sh" arg "$resolved" "$src" clip
fi

tmp="$(new_tmpfile clip.txt)"
printf '%s' "$content" >"$tmp"
exec "$DIR/run.sh" stdin "$tmp" "$src" clip
