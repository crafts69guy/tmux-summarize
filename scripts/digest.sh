#!/usr/bin/env bash
# Cross-pane digest: concatenate the visible content of every pane (with a header
# per pane) and summarize the lot — "what happened across my session". Arg: <src-pane>
# @summarize_digest_scope = window (default) | session.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

src="${1:?digest.sh: missing src-pane}"
tmp="$(new_tmpfile digest.md)"

build_digest "$src" >"$tmp"

if [ ! -s "$tmp" ]; then
  tmux display-message 'summarize: nothing to digest'
  exit 0
fi
exec "$DIR/run.sh" stdin "$tmp" "$src"
