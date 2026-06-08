# TokenTracker

A macOS menu bar app that tracks AI coding tool usage from local databases. Displays costs, tokens, models, projects, languages, and per-origin breakdowns across multiple sources.

## Features

- **Menu bar cost** — shows total spend for the selected time range (1d / 7d / 30d / 3m / All)
- **6 tabs** in the popover panel:
  - Overview — cost cards, daily or hourly spend chart, top model
  - Tech — language breakdown by tool call count
  - Projects — project costs with tap-to-copy + double-blink
  - Models — model costs with tap-to-copy + double-blink
  - Usage — token distribution (input, output, reasoning, cache)
  - Origins — per-source breakdown (appears with 2+ sources)
- **Hourly chart** in 1d view — see spend broken down by hour
- **Multi-source** — data from OpenCode, Pi, Oh My Pi, OpenClaw, Hermes, OpenRouter, and more
- **Message-level attribution** — costs distributed proportionally across days by message timestamp
- **Live currency** — rates from Frankfurter API, cached with hourly refresh
- **Auto-refresh** — rescans every 60 seconds

## Requirements

- macOS 14.0+ (Apple Silicon or Intel)
- At least one supported AI tool to track

## Build

```bash
make build   # compile with swiftc
make run     # build + launch
```

No Xcode needed — single-project SwiftUI + AppKit, compiled via Makefile.

## Data Sources

| Source | Format | Location |
|---|---|---|
| OpenCode | SQLite | `~/.local/share/opencode/opencode.db` |
| Pi Agent | JSONL | `~/.pi/agent/sessions/` |
| Oh My Pi | JSONL | `~/.omp/agent/sessions/` |
| OpenClaw | JSONL | `~/.openclaw/agents/main/sessions/` |
| Hermes | SQLite | `~/.hermes/state.db` |
| OpenRouter | REST API | `api.openrouter.ai` (API key + optional mgmt key) |
| OpenCode Go | SQLite | `~/.local/share/opencode-go/opencode.db` |

Sources are auto-detected on each launch. Toggle any source on/off from Settings → Sources.

## Preferences

The macOS-style sidebar preferences window (720×560):

- **General** — app info, auto-refresh details
- **Currencies** — pick display currency, custom rate, live update button
- **Sources** — list of discovered sources with on/off toggles and Rescan
- **One tab per source** — path, size, last modified, enable/disable, API key fields
- **About** — version

## Shortcuts

| Key | Action |
|---|---|
| Click menu bar icon | Toggle panel |
| `⌘,` | Open Preferences |
| `⌘Q` | Quit |
| `Esc` | Close panel |

## Architecture

TokenTracker is a single-file SwiftUI + AppKit project split into 13 source files under `src/`:

```
src/
  main.swift              — AppDelegate, PopoverView, panel, entry point
  Models.swift            — DayAgg, Aggregate, StatsSummary, TimeRange
  Engine.swift            — StatsEngine, buildAggregate, summarize, queryDB
  Sources/
    SourceScanner.swift   — source auto-detection and persistence
    OpenCodeSource.swift  — opencode SQLite ingester
    PiSource.swift        — Pi / Oh My Pi / OpenClaw JSONL ingester
    HermesSource.swift    — Hermes SQLite ingester
    OpenRouterSource.swift — OpenRouter REST API ingester
  Views/
    Components.swift      — BarRow, StatCard, DailySpendChart, HourlySpendChart
    TabViews.swift        — Overview, Tech, Projects, Models, Usage, Origins
    SettingsView.swift    — sidebar preferences
  Utils/
    Currency.swift        — SettingsStore, CurrencyRates, defaultCurrencies
    Formatting.swift      — Fmt helpers, Color hex, TTIcon
    LanguageMap.swift     — extension → language mapping
```

Each data source has its own `ingest*` function that reads from its native format (SQLite via piped `/usr/bin/sqlite3 -json`, JSONL stream parsing, or REST API) and produces the same `DayAgg` structure. Results are merged into a per-source day map, cached to `~/.local/share/opencode/trackercache.json`, and filtered/summarised on request.

## License

MIT