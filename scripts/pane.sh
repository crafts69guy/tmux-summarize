#!/usr/bin/env bash
# Summarize the current pane's scrollback. Arg: <src-pane>
# @summarize_pane_lines bounds how much history is captured (default 2000 lines)
# to keep requests cheap; set '-' for the full scrollback, or a number N for the
# last N lines, e.g. set -g @summarize_pane_lines '500'.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

src="${1:?pane.sh: missing src-pane}"
lines="$(get_opt pane_lines '2000')"
tmp="$(new_tmpfile pane.txt)"

# -J joins wrapped lines; -S - starts at the top of history (full scrollback).
if [ "$lines" = '-' ]; then
  tmux capture-pane -p -J -S - -t "$src" >"$tmp"
else
  tmux capture-pane -p -J -S "-$lines" -t "$src" >"$tmp"
fi

if [ ! -s "$tmp" ]; then
  tmux display-message 'summarize: pane has no scrollback to summarize'
  exit 0
fi
exec "$DIR/run.sh" stdin "$tmp" "$src"
