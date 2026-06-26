# docs/ — demo assets

The main README embeds two stills:

- `picker.png` — the `prefix + S` source picker with its live preview.
- `result.png` — the rendered summary in a centred, paper-width popup.

Replace either by overwriting the file with a fresh capture of the same view.
For an animated walkthrough, add `docs/demo.gif` and embed it in the README too.

## Recording a GIF

### Option A — [vhs](https://github.com/charmbracelet/vhs) (scripted, reproducible)

`brew install vhs`, then create `docs/demo.tape`:

```tape
Output docs/demo.gif
Set FontSize 16
Set Width 1200
Set Height 700
Set Padding 20

Type "tmux new-session -A -s demo"   Enter
Sleep 1s
# run something worth summarizing in the pane
Type "curl -s https://example.com | head -40"   Enter
Sleep 1s
# prefix (C-t here) + S opens the Summarize menu, then 'p' for pane scrollback
Ctrl+t
Type "S"
Sleep 1s
Type "p"
Sleep 8s          # let the summary stream into the popup
Enter             # close the popup
Sleep 1s
```

Render with `vhs docs/demo.tape`. Adjust the prefix key (`Ctrl+t` above) to yours,
and the `Sleep` after `p` to however long your model takes.

### Option B — asciinema + agg (lightweight, terminal-native)

```bash
asciinema rec docs/demo.cast        # do the prefix+S → p flow, then exit
agg docs/demo.cast docs/demo.gif    # https://github.com/asciinema/agg
```

### Option C — screen recording

QuickTime / macOS `⌘⇧5` to record the terminal window, then convert to GIF
(`ffmpeg -i demo.mov -vf "fps=12,scale=1000:-1" docs/demo.gif`). Keep it under
~5 MB so it loads fast on GitHub.

## Tips

- Trigger the flow you want to feature: pane scrollback (`p`), a clipboard URL
  (`c`), or the cross-pane digest (`d`).
- A short, fast model (e.g. `@summarize_length 'short'`) keeps the GIF snappy.
- Strip any private paths/keys from the recorded terminal before committing.
