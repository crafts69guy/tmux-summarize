# tmux-summarize

Summarize the context you already have in tmux with
[`@steipete/summarize`](https://github.com/steipete/summarize), streamed into a
popup (or split pane) — no copy-pasting into a browser.

From a single menu (`prefix + S`) you can summarize:

- **Current pane scrollback** — long logs, build output, a stack trace.
- **Clipboard / copy-mode selection** — a URL, article text, a YouTube link.
- **A typed URL or path**, or an fzf-picked file (PDFs, docs, audio, video).
- **A cross-pane digest** — every pane in the window/session at once.

The summary runs through a login shell, so it inherits your normal environment
(API keys, and any `OPENAI_BASE_URL` for routing through a local proxy like
[9router](https://github.com/decolua/9router)) — see
[Routing](#routing-through-9router-or-any-openai-compatible-proxy).

## Requirements

- [`summarize`](https://github.com/steipete/summarize) on `PATH`
  (`brew install summarize` or `npm i -g @steipete/summarize`, Node 24+).
- tmux ≥ 3.2 (`display-menu` / `display-popup`).
- `fzf` (+ `fd` recommended) — only for the empty-prompt file picker.
- At least one model provider configured for `summarize` (env var or
  `~/.summarize/config.json`).

## Install

With [TPM](https://github.com/tmux-plugins/tpm), add to `tmux.conf`:

```tmux
set -g @plugin 'crafts69guy/tmux-summarize'
```

Then `prefix + I` to install. Manually: clone the repo and
`run-shell /path/to/summarize.tmux`.

## Usage

Press **`prefix + S`** to open the menu, then:

| Key | Action |
|-----|--------|
| `p` | Summarize the current pane's scrollback |
| `c` | Summarize the clipboard / copy-mode selection |
| `i` | Prompt for a URL/path (empty → fzf file picker) |
| `d` | Digest every pane in the window (or session) |

The result streams into a centered popup; press **Enter** to close it. Prefer a
persistent pane? Set `@summarize_output 'split'` and it streams into a split that
returns to a prompt (close with your usual pane-kill binding).

## Options

All options use the `@summarize_*` namespace. Set them in `tmux.conf`.

| Option | Default | Description |
|--------|---------|-------------|
| `@summarize_menu_key` | `S` | Prefix key that opens the menu |
| `@summarize_command` | `summarize` | CLI to invoke (e.g. a wrapper/shim) |
| `@summarize_model` | *(unset)* | `--model provider/model`; unset → summarize decides |
| `@summarize_length` | *(unset)* | `--length short\|medium\|long\|xl\|xxl` |
| `@summarize_language` | *(unset)* | `--language <lang>` |
| `@summarize_extra_args` | *(unset)* | Raw flags appended verbatim |
| `@summarize_output` | `popup` | Where output goes: `popup` or `split` |
| `@summarize_shell` | *(tmux `default-shell`)* | Login shell the popup runs through (loads your env) |
| `@summarize_popup_width` | `80%` | Popup width (when `output = popup`) |
| `@summarize_popup_height` | `80%` | Popup height (when `output = popup`) |
| `@summarize_split` | `h` | Split direction `h`/`v` (when `output = split`) |
| `@summarize_split_size` | `40%` | Split size (when `output = split`) |
| `@summarize_pane_lines` | `2000` | Scrollback to capture (`-` = all, or a number) |
| `@summarize_digest_scope` | `window` | `window` or `session` |
| `@summarize_pane_key` `@summarize_clip_key` `@summarize_input_key` `@summarize_digest_key` | *(unset)* | Optional direct bindings that skip the menu |

Example:

```tmux
set -g @plugin 'crafts69guy/tmux-summarize'
set -g @summarize_length 'medium'
set -g @summarize_split_size '45%'
set -g @summarize_pane_key 'M-s'   # prefix+M-s → summarize pane directly
```

## Routing through 9router (or any OpenAI-compatible proxy)

`summarize` honours `OPENAI_BASE_URL`, so you can route summaries through a local
proxy such as [9router](https://github.com/decolua/9router) to use cheap/free
model tiers instead of burning a raw API key. The plugin is unopinionated about
this — it just inherits your shell environment. Configure routing in your shell
rc (keep keys out of version control), e.g. for fish:

```fish
# ~/.config/fish/config-local.fish  (untracked)
set -gx OPENAI_BASE_URL http://localhost:20128/v1
set -gx OPENAI_API_KEY  <your-9router-key>
```

and point the plugin at a 9router combo:

```tmux
set -g @summarize_model 'openai/cc/claude-opus-4-7'
```

With nothing set, `summarize` falls back to whatever provider is configured in
its own env/`~/.summarize/config.json`.

## Tests

```bash
./tests/run.sh
```

Pure helpers (`build_args`, `is_url`, `shq`, `get_opt`) are tested with a stubbed
tmux — no external framework required.

## License

MIT
