# TokenTracker

A macOS menu bar app that tracks AI coding tool usage from local databases. Displays costs, tokens, models, projects, languages, and origin breakdowns across multiple sources.

## Features

- **Menu bar cost display** — shows total cost for the selected time range (1d / 7d / 30d / 3m / All)
- **Popover panel** with 6 tabs:
  - Overview — cost summary, daily spend chart, top model
  - Tech — language breakdown by tool call count
  - Projects — project costs with copy-on-tap + double-blink feedback
  - Models — model costs with copy-on-tap + double-blink feedback
  - Usage — token distribution (input, output, reasoning, cache)
  - Origins — per-source breakdown (appears when 2+ sources active)
- **Multi-source support** — scans for data from:
  - OpenCode (local SQLite)
  - Pi Agent (JSONL sessions)
  - OpenCode Go
  - OpenRouter (via API key)
- **Per-source aggregation** — data from each source is collected separately, then merged by day
- **Message-level attribution** — costs and tokens are distributed proportionally across days based on message timestamps, so ongoing sessions spanning multiple days are correctly attributed
- **Live currency conversion** — rates fetched from Frankfurter API, cached, refreshable
- **Auto-refresh** — rescans every 60 seconds

## Requirements

- macOS 14.0+ (arm64)
- [opencode](https://opencode.ai) (for its local database)

## Build

```bash
make build   # compiles with swiftc
make run     # builds + launches
```

No Xcode or SPM required — single-file SwiftUI + AppKit app (~2300 lines).

## Settings

The preferences window provides a macOS-style sidebar with:

- **General** — app behavior info
- **Currencies** — pick a display currency, custom rate, live update button
- **Data** — toggle discovered sources on/off, rescan for new ones
- **One tab per source** — path, size, last modified, enable/disable, API key (OpenRouter)
- **About** — version info

## Data Sources

| Source | Format | Location / Method |
|---|---|---|
| OpenCode | SQLite | `~/.local/share/opencode/opencode.db` |
| Pi Agent | JSONL | `~/.pi/agent/sessions/` |
| OpenCode Go | SQLite | `~/.local/share/opencode-go/opencode.db` |
| OpenRouter | API | `https://openrouter.ai/api/v1/auth/key` (API key required) |

Sources are auto-detected on launch. Enable or disable any source from the Data tab.

## Keyboard

| Shortcut | Action |
|---|---|
| `⌘,` | Open Preferences |
| `⌘Q` | Quit |

## How it works

TokenTracker queries `/usr/bin/sqlite3 -json` with piped SQL (for SQLite sources), reads JSONL files (for Pi), or fetches from REST APIs (for OpenRouter). Results are collected per-source into separate day maps, then merged into a single daily aggregate. Each day's data includes costs, tokens, messages, models, projects, and languages.

The merged aggregate is cached to `~/.local/share/opencode/trackercache.json` keyed by source modification time. The cache invalidates automatically when any source changes.

## License

MIT