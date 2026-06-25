#!/usr/bin/env bash
# tmux-summarize
#
# Summarize the context you already have in tmux — the current pane's scrollback,
# the clipboard / copy-mode selection, a typed/picked URL or file, or a digest of
# every pane in the window/session — with @steipete/summarize, streamed into a
# split pane. tpm runs this file as an executable on tmux startup; it reads user
# options (with sensible defaults) and installs the key bindings.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

scripts="$CURRENT_DIR/scripts"
menu_key="$(get_opt menu_key 'S')"

# One menu under a single key keeps the top-level prefix space uncluttered and
# avoids colliding with other plugins' bindings. p/c/i/d choose the input source.
# #{pane_id} is expanded by tmux before the script runs, so each action targets
# the pane that was focused when the menu opened.
tmux bind-key "$menu_key" display-menu -T ' Summarize ' -x C -y C \
  'Current pane scrollback' p "run-shell \"$scripts/pane.sh '#{pane_id}'\"" \
  'Clipboard / selection'   c "run-shell \"$scripts/clipboard.sh '#{pane_id}'\"" \
  'URL or file…'            i "run-shell \"$scripts/input.sh '#{pane_id}'\"" \
  'Cross-pane digest'       d "run-shell \"$scripts/digest.sh '#{pane_id}'\""

# Optional direct bindings — unset by default, bound only when the user opts in,
# e.g.  set -g @summarize_pane_key 'M-s'
bind_optional() { # <option-suffix> <script>
  local key
  key="$(get_opt "$1" '')"
  [ -n "$key" ] && tmux bind-key "$key" run-shell "$scripts/$2 '#{pane_id}'"
}
bind_optional pane_key   pane.sh
bind_optional clip_key   clipboard.sh
bind_optional input_key  input.sh
bind_optional digest_key digest.sh

exit 0
