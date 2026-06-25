#!/usr/bin/env bash
# Summarize a typed URL/path, or fzf-pick a file when the prompt is left empty.
# Args: <src-pane> [value]
#   With no <value> it opens a tmux command-prompt and re-invokes itself with the
#   typed text. An empty value falls back to an fzf file picker in the pane's cwd.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

src="${1:?input.sh: missing src-pane}"

# First call (no value arg): ask for input, then re-enter with the typed text.
# tmux substitutes %% with what the user typed; it is single-quoted so URL query
# strings (?a&b) reach this script intact.
if [ "$#" -lt 2 ]; then
  tmux command-prompt -p 'summarize (URL/path; empty = pick file):' \
    "run-shell \"$DIR/input.sh $src '%%'\""
  exit 0
fi

value="$2"
if [ -n "$value" ]; then
  exec "$DIR/run.sh" arg "$value" "$src"
fi

# Empty input -> fzf file picker. display-popup -E blocks until fzf exits, so we
# stash the selection in a temp file and read it back here.
cwd="$(tmux display-message -p -t "$src" '#{pane_current_path}' 2>/dev/null)"
out="$(new_tmpfile pick.txt)"
tmux display-popup -d "${cwd:-$PWD}" -E \
  "${FZF_DEFAULT_COMMAND:-find . -type f -not -path '*/.git/*'} | fzf > '$out'"
file="$(cat "$out" 2>/dev/null)"
rm -f "$out"

[ -z "$file" ] && exit 0
exec "$DIR/run.sh" arg "$file" "$src"
