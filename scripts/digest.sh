#!/usr/bin/env bash
# Cross-pane digest: concatenate the visible content of every pane (with a header
# per pane) and summarize the lot — "what happened across my session". Arg: <src-pane>
# @summarize_digest_scope = window (default) | session.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

src="${1:?digest.sh: missing src-pane}"
scope="$(get_opt digest_scope 'window')"
tmp="$(new_tmpfile digest.md)"

case "$scope" in
session) list_args=(-s -t "$src") ;;
*) list_args=(-t "$src") ;;
esac

{
  while read -r label pid cmd; do
    [ -z "$pid" ] && continue
    printf '### pane %s (%s)\n\n' "$label" "$cmd"
    tmux capture-pane -p -J -t "$pid"
    printf '\n\n'
  done < <(tmux list-panes "${list_args[@]}" \
    -F '#{window_index}.#{pane_index} #{pane_id} #{pane_current_command}')
} >"$tmp"

if [ ! -s "$tmp" ]; then
  tmux display-message 'summarize: nothing to digest'
  exit 0
fi
exec "$DIR/run.sh" stdin "$tmp" "$src"
