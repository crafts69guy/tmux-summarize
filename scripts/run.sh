#!/usr/bin/env bash
# Core: build the summarize command and stream it into a split pane.
# Args: <arg|stdin> <payload> [src-pane]
#   arg    payload is a URL or file path -> summarize <payload>
#   stdin  payload is a temp file        -> summarize - < <payload>
#   src-pane anchors the split's cwd and placement (default: active pane).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

mode="${1:?usage: run.sh <arg|stdin> <payload> [src-pane]}"
payload="${2:?run.sh: missing payload}"
src="${3:-}"

base="$(summarize_command) $(build_args)"
case "$mode" in
arg) line="$base $(shq "$payload")" ;;
stdin) line="$base - < $(shq "$payload")" ;;
*)
  tmux display-message "summarize: unknown mode '$mode'"
  exit 1
  ;;
esac

case "$(get_opt split 'h')" in v) sflag='-v' ;; *) sflag='-h' ;; esac
size="$(get_opt split_size '40%')"
cwd="$(tmux display-message -p ${src:+-t "$src"} '#{pane_current_path}' 2>/dev/null)"

# Run the summary in the new pane's *interactive shell* (via send-keys) instead
# of as the pane's command. This loads the user's normal environment — e.g.
# OPENAI_BASE_URL for routing through a local proxy like 9router, plus any API
# keys exported from their shell rc — exactly as in any other pane, and leaves
# the pane at a prompt when summarize finishes (close it with your pane-kill key).
new="$(tmux split-window "$sflag" -l "$size" ${cwd:+-c "$cwd"} -P -F '#{pane_id}')"
tmux send-keys -t "$new" "$line" Enter
