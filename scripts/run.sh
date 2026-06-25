#!/usr/bin/env bash
# Core: build the summarize command and stream it into a popup (default) or split.
# Args: <arg|stdin> <payload> [src-pane]
#   arg    payload is a URL or file path -> summarize <payload>
#   stdin  payload is a temp file        -> summarize - < <payload>
#   src-pane anchors the output's cwd and placement (default: active pane).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

mode="${1:?usage: run.sh <arg|stdin> <payload> [src-pane]}"
payload="${2:?run.sh: missing payload}"
src="${3:-}"

# Fail loudly if the CLI is missing, instead of spawning a pane/popup that just
# prints "command not found". ${bin%% *} tests the binary, not any flags.
bin="$(summarize_command)"
bin="${bin%% *}"
if ! command -v "$bin" >/dev/null 2>&1; then
  tmux display-message "summarize: '$bin' not found in PATH — install @steipete/summarize (e.g. brew install summarize)"
  exit 0
fi

base="$(summarize_command) $(build_args)"
case "$mode" in
arg) line="$base $(shq "$payload")" ;;
stdin) line="$base - < $(shq "$payload")" ;;
*)
  tmux display-message "summarize: unknown mode '$mode'"
  exit 1
  ;;
esac

# Run the summary from the source pane's directory so relative work resolves the
# same way it would in that pane.
if [ -n "$src" ]; then
  cwd="$(tmux display-message -p -t "$src" '#{pane_current_path}' 2>/dev/null)"
else
  cwd="$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)"
fi
[ -z "$cwd" ] && cwd="$PWD"
shell="${SHELL:-/bin/sh}"

case "$(get_opt output 'popup')" in
split)
  # A split pane runs the user's interactive shell, so the summary inherits the
  # same environment (routing via OPENAI_BASE_URL, API keys) as any other pane.
  # The pane returns to a prompt when summarize finishes — close it as usual.
  case "$(get_opt split 'h')" in v) sflag='-v' ;; *) sflag='-h' ;; esac
  size="$(get_opt split_size '40%')"
  new="$(tmux split-window "$sflag" -l "$size" -c "$cwd" -P -F '#{pane_id}')"
  wait_pane_ready "$new"
  tmux send-keys -t "$new" "$line" Enter
  ;;
*)
  # Popup: run through a login shell so the user's env (OPENAI_BASE_URL, keys) is
  # loaded just like a normal pane. The shell-agnostic `sh -c read` hold keeps the
  # summary on screen until Enter, regardless of which shell $SHELL is.
  read -r w h < <(popup_dims)
  hold="; printf '\n[done — press Enter to close]'; sh -c 'read REPLY'"
  tmux display-popup -E -d "$cwd" -w "$w" -h "$h" -T ' Summarize ' \
    "$shell -l -c $(shq "$line$hold")"
  ;;
esac
