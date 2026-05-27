# 🦀 clawpypaste

A macOS menu bar app that surfaces grabbable blocks from your active **Claude Code** session — fenced code, tool output, file paths, URLs, whole messages, markdown — so you can click to copy instead of mouse-selecting across wrapped lines in your terminal.

Reads the session JSONL Claude Code already writes to disk. No accessibility prompts, no terminal scraping, no plugins.

<p align="center">
  <img src="docs/screenshot.png" alt="clawpypaste popover" width="495">
</p>

## Why

Copy-pasting code out of a Claude Code conversation in the terminal is fiddly: wrapping breaks selection, the clipboard only holds one thing, and you usually want a specific code fence — not the prose around it.

clawpypaste sits in your menu bar and shows every grabbable block from the session you're actively working in, live-updating as Claude responds. Click any block → on the clipboard. Drag any block → into another app. Star any block → keep it forever.

## Features

- **Live block list** of the active Claude Code session — auto-detected by most-recent JSONL mtime, re-evaluated every 3s
- **Smart block classification** — code fences, tool inputs (`Bash.command`, `Write.content`, `Edit.new_string`), tool results, file paths, URLs, whole assistant messages, and markdown content (detected via file extension or fence language)
- **Syntax-highlighted code previews** for Swift / Python / Bash / JS/TS / Rust / Go / JSON / YAML
- **Inline-markdown rendering** in prose blocks — `**bold**`, `*italic*`, `` `code` ``, headings, lists, blockquotes
- **Global hotkey** — ⌃⌥V toggles the popover from anywhere
- **Drag-out** — drag any block straight into another app, bypassing the clipboard
- **Pin** any block to keep it on top across sessions (persisted to `~/Library/Application Support/clawpypaste/pins.json`)
- **Session switcher** — jump to one of your 5 most-recent sessions, with each session's custom title and color dot
- **Detached window** option for parking next to your terminal
- **Auto-dismiss on copy** so you can paste immediately
- **Launch at login** via `SMAppService`

## Install

macOS 13 (Ventura) or newer.

### Homebrew (recommended)

```bash
brew install --cask krisbradley/tap/clawpypaste
open /Applications/clawpypaste.app
```

### Direct download

Grab the notarized `clawpypaste.zip` from the [latest release](https://github.com/krisbradley/clawpypaste/releases/latest), unzip, drag `clawpypaste.app` into `/Applications`, double-click.

### From source

Requires the Swift toolchain (`xcode-select --install` is enough).

```bash
git clone https://github.com/krisbradley/clawpypaste.git
cd clawpypaste
make install
```

### Launch at login

After installing by any of the methods above:

```bash
/Applications/clawpypaste.app/Contents/MacOS/clawpypaste --enable-login
```

Or right-click the menu bar 🦀 → **Launch at login**.

## Usage

| Action | How |
|---|---|
| Open the popover | Click the 🦀 in the menu bar, or press **⌃⌥V** |
| Copy a block | Click it (popover auto-dismisses) |
| Drag a block to another app | Click-and-hold, then drag |
| Pin a block | Click the star on its row |
| Search blocks | Type in the search field |
| Filter by kind | Click a chip (Code / Markdown / Tool output / Path / URL / Section / Message) |
| Switch sessions | Click the session name in the header |
| Open the detached window | Right-click 🦀 → "Open window" |
| Quit | Right-click 🦀 → "Quit" |

## How it works

Claude Code writes every session to a JSONL file under `~/.claude/projects/<encoded-project-dir>/<uuid>.jsonl`. Each line is one record: a user message, an assistant message with content blocks (text / thinking / tool_use), a tool result, or a metadata record like `custom-title` / `agent-color`.

clawpypaste:

1. **Finds the active session** by scanning all JSONL files and picking the one with the most recent mtime (or whichever the user switched to)
2. **Watches that file** with a `DispatchSource` for incremental writes
3. **Re-parses the JSONL** on every change (debounced 150ms) into typed `SessionRecord`s
4. **Extracts blocks** by walking each record: code fences inside assistant text, tool inputs/outputs, file paths and URLs in prose, markdown sections under headings, and entire assistant messages
5. **Dedupes** by content hash so the same block doesn't appear twice
6. **Renders** through a SwiftUI list inside an `NSPopover`, with syntax highlighting for code and inline-markdown rendering for prose

There's no accessibility access, no key logging, no shell hooks. The Carbon `RegisterEventHotKey` API powers the global shortcut. `SMAppService.mainApp` powers Launch at Login.

## Development

```bash
make run       # swift run (no .app bundle)
make build     # release bundle
make install   # build + drop in /Applications + launch
make clean     # remove build artifacts
make uninstall # remove installed app + disable login item

# debug parsing without the GUI
.build/debug/clawpypaste --dump
```

## License

MIT. See [LICENSE](LICENSE).
