import SwiftUI

enum SettingsPage: Hashable {
    case general, currencies, data, about
    case source(OpenCodeSource)

    var label: String {
        switch self {
        case .general: return "General"
        case .currencies: return "Currencies"
        case .data: return "Sources"
        case .source(let s): return s.label
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .currencies: return "dollarsign.circle"
        case .data: return "cylinder"
        case .source(let s):
            switch s.kind {
            case .piSessions, .omPiSessions: return "brain"
            case .hermesSessions: return "figure.run"
            case .openClawSessions: return "pawprint"
            case .openRouter: return "network"
            case .openCodeGo: return "arrow.triangle.swap"
            case .opencodeDB: return "externaldrive"
            }
        case .about: return "info.circle"
        }
    }

    static func allPages(sources: [OpenCodeSource]) -> [SettingsPage] {
        var pages: [SettingsPage] = [.general, .currencies, .data]
        for src in sources { pages.append(.source(src)) }
        pages.append(.about)
        return pages
    }
}

struct SettingsView: View {
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @State private var customRate: String = ""
    @State private var refreshing = false
    @State private var lastFetchText: String = ""
    @State private var sources: [OpenCodeSource] = SourceScanner.storedSources
    @State private var selectedPage: SettingsPage = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                ForEach(SettingsPage.allPages(sources: sources), id: \.self) { page in
                    Label(page.label, systemImage: page.icon)
                        .font(.system(size: 12.5))
                        .tag(page)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 170, maxWidth: 200)
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 200)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 720, height: 560)
        .onAppear {
            customRate = String(format: "%.4f", SettingsStore.currencyRate)
            lastFetchText = CurrencyRates.lastFetchLabel
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedPage {
        case .general: generalPane
        case .currencies: currenciesPane
        case .data: dataPane
        case .source(let src): sourceDetailPane(src)
        case .about: aboutPane
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General").font(.system(size: 15, weight: .bold))
            Text("TokenTracker displays usage data from opencode's local database.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Divider()
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto-refresh every 60 seconds").font(.system(size: 12))
                    Text("The app rescans the database automatically. Click ↻ in the panel to force-refresh.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var currenciesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Currencies").font(.system(size: 15, weight: .bold))
            Text("Choose a display currency and optionally set a custom rate.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Currency").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("", selection: $currencyCode) {
                        ForEach(defaultCurrencies, id: \.code) { c in
                            Text("\(c.symbol)  \(c.code)  –  \(c.name)").tag(c.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 220)
                }
                HStack {
                    Text("1 USD =").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("", text: $customRate)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit {
                            if let val = Double(customRate), val > 0 {
                                SettingsStore.currencyRate = val
                            } else {
                                customRate = String(format: "%.4f", SettingsStore.currencyRate)
                            }
                        }
                    Text(currencyCode).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                }
                HStack {
                    Button(action: refreshRates) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                            Text(refreshing ? "Updating…" : "Update rates")
                        }
                        .font(.system(size: 11))
                    }
                    .disabled(refreshing)
                    Text("Last updated: \(lastFetchText)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
}
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var dataPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Data Sources").font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Rescan") { sources = SourceScanner.scan() }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            Text("Discovered opencode databases. Disable a source to exclude its data.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Divider()

            if sources.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 16))
                    Text("No opencode databases found.")
                        .font(.system(size: 12))
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            } else {
                ForEach(sources) { src in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { src.enabled },
                            set: { newVal in
                                if let idx = sources.firstIndex(where: { $0.id == src.id }) {
                                    sources[idx].enabled = newVal
                                    SourceScanner.storedSources = sources
                                    NotificationCenter.default.post(name: .sourcesChanged, object: nil)
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(src.label).font(.system(size: 12.5, weight: .medium))
                            Text(src.path)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sourceDetailPane(_ src: OpenCodeSource) -> some View {
        let current = sources.first { $0.id == src.id } ?? src
        return VStack(alignment: .leading, spacing: 16) {
            Text(current.label).font(.system(size: 15, weight: .bold))
            Divider()
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
detailRow("Type", current.kind == .opencodeDB ? "OpenCode DB" :
                            current.kind == .piSessions ? "Pi Sessions (JSONL)" :
                            current.kind == .omPiSessions ? "Oh My Pi Sessions (JSONL)" :
                            current.kind == .openClawSessions ? "OpenClaw Sessions (JSONL)" :
                            current.kind == .hermesSessions ? "Hermes Sessions (SQLite)" :
                            current.kind == .openRouter ? "OpenRouter API" : "OpenCode Go DB")
                    detailRow("Path", current.path)
                    if current.kind == .opencodeDB || current.kind == .openCodeGo {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: current.path) {
                            detailRow("Size", ByteCountFormatter.string(fromByteCount: Int64(attrs[.size] as? Int64 ?? 0), countStyle: .file))
                            if let mod = attrs[.modificationDate] as? Date {
                                detailRow("Last modified", mod.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                    } else if current.kind == .piSessions {
                        let count = (try? FileManager.default.contentsOfDirectory(atPath: current.path).count) ?? 0
                        detailRow("Session files", "\(count)")
                    } else if current.kind == .openRouter {
                        let hasKey = current.apiKey != nil && !current.apiKey!.isEmpty
                        let hasMgmt = current.mgmtKey != nil && !current.mgmtKey!.isEmpty
                        detailRow("API Key", hasKey ? "✓ Set" : "Not set")
                        detailRow("Endpoint", "api.openrouter.ai/v1/auth/key (totals)")
                        keyField("sk-or-v1-...", currentKey: current.apiKey ?? "") { newKey in
                            if let idx = sources.firstIndex(where: { $0.id == current.id }) {
                                sources[idx].apiKey = newKey
                                SourceScanner.storedSources = sources
                                NotificationCenter.default.post(name: .sourcesChanged, object: nil)
                            }
                        }
                        Divider().padding(.vertical, 4)
                        detailRow("Mgmt Key", hasMgmt ? "✓ Set (detailed)" : "Not set")
                        detailRow("Endpoint", "api.openrouter.ai/v1/activity (per-generation)")
                        keyField("sk-or-mgmt-...", currentKey: current.mgmtKey ?? "") { newKey in
                            if let idx = sources.firstIndex(where: { $0.id == current.id }) {
                                sources[idx].mgmtKey = newKey
                                SourceScanner.storedSources = sources
                                NotificationCenter.default.post(name: .sourcesChanged, object: nil)
                            }
                        }
                    }
                }
                .padding(10)
            }
            HStack {
                Toggle("Enabled", isOn: Binding(
                    get: { current.enabled },
                    set: { newVal in
                        if let idx = sources.firstIndex(where: { $0.id == current.id }) {
                            sources[idx].enabled = newVal
                            SourceScanner.storedSources = sources
                            NotificationCenter.default.post(name: .sourcesChanged, object: nil)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var aboutPane: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "t.square.fill")
                .font(.system(size: 50))
                .foregroundStyle(.tint)
            Text("TokenTracker").font(.title).bold()
            Text("Version 1.0.0").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Reads opencode session data from local SQLite databases to show usage costs, tokens, projects, models, and languages.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300).lineSpacing(4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 11.5, weight: .medium))
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value).font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func refreshRates() {
        refreshing = true
        Task {
            await CurrencyRates.fetch()
            await MainActor.run {
                refreshing = false
                lastFetchText = CurrencyRates.lastFetchLabel
                let code = SettingsStore.currencyCode
                if code != "USD", let liveRate = CurrencyRates.cachedRates[code] {
                    customRate = String(format: "%.4f", liveRate)
                    SettingsStore.currencyRate = liveRate
                }
            }
        }
    }

    private func keyField(_ placeholder: String, currentKey: String, onSet: @escaping (String) -> Void) -> some View {
        SecureField(placeholder, text: Binding(
            get: { currentKey },
            set: { newKey in
                let trimmed = newKey.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { onSet(trimmed) }
            }
        ))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity)
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isMovable = true
        self.init(window: window)
    }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }
}