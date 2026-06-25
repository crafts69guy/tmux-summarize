#!/usr/bin/env bash
# Summarize a typed URL/path, or fzf-pick a file when the prompt is left empty.
# Args: <src-pane> [stage]
#   stage 'prompt' (default) opens a command-prompt; on submit it re-invokes this
#   script with stage 'submit'. The typed text is passed through a tmux option
#   (not interpolated into the callback), so URLs with shell metacharacters are safe.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

src="${1:?input.sh: missing src-pane}"
stage="${2:-prompt}"

if [ "$stage" = prompt ]; then
  tmux command-prompt -p 'summarize (URL/path; empty = pick file):' \
    "set -g @summarize_query '%%' ; run-shell '$DIR/input.sh $src submit'"
  exit 0
fi

value="$(tmux show-option -gqv @summarize_query 2>/dev/null)"
tmux set -gu @summarize_query 2>/dev/null || true

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
