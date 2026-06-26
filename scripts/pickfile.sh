#!/usr/bin/env bash
# Thin wrapper around helpers' pick_file, so the empty-input file picker (input.sh)
# and the source picker's "file" choice (picker.sh) share one themed fzf layout.
# Prints the chosen path to stdout; empty if nothing was picked. Arg: <src-pane>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

pick_file "${1:?pickfile.sh: missing src-pane}"
