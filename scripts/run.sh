#!/usr/bin/env bash
# Core: build the summarize command and stream it into a popup (default) or split.
# Args: <arg|stdin> <payload> [src-pane] [label]
#   arg    payload is a URL or file path -> summarize <payload>
#   stdin  payload is a temp file        -> summarize - < <payload>
#   src-pane anchors the output's cwd and placement (default: active pane).
#   label    source keyword (pane|clip|url|file|digest) for the summary header.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

mode="${1:?usage: run.sh <arg|stdin> <payload> [src-pane] [label]}"
payload="${2:?run.sh: missing payload}"
src="${3:-}"
label="${4:-}"

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
shell="$(login_shell)"

case "$(get_opt output 'popup')" in
split)
  # A split pane runs the user's interactive shell, so the summary inherits the
  # same environment (routing via OPENAI_BASE_URL, API keys) as any other pane.
  # The pane returns to a prompt when summarize finishes — close it as usual.
  case "$(get_opt split 'h')" in v) sflag='-v' ;; *) sflag='-h' ;; esac
  size="$(get_opt split_size '40%')"
  new="$(tmux split-window "$sflag" -l "$size" -c "$cwd" -P -F '#{pane_id}')"
  wait_pane_ready "$new"
  # frame_command (hold=no) prepends the shared header and returns to the prompt
  # when summarize finishes. send-keys can't carry raw ESC bytes, so the split
  # header is plain text; the popup path below keeps the full coloured chrome.
  hdr="$(printf '▌ Summarize — %s' "$(source_label_plain "$label")")"
  tmux send-keys -t "$new" "printf '%s\\n\\n' $(shq "$hdr"); $line" Enter
  ;;
*)
  # Popup: run through a login shell so the user's env (OPENAI_BASE_URL, keys) is
  # loaded just like a normal pane. frame_command adds the shared header/footer and
  # holds the summary on screen until Enter, regardless of which shell $SHELL is.
  read -r w h < <(popup_dims)
  wrapped="$(frame_command "$line" "$label" yes)"
  tmux display-popup -E -d "$cwd" -w "$w" -h "$h" \
    -b "$(border_lines)" -S "$(border_style)" -T "$(popup_title)" \
    "$shell -l -c $(shq "$wrapped")"
  ;;
esac
