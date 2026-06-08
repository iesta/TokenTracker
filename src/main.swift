import SwiftUI
import AppKit
import Foundation

extension Notification.Name {
    static let sourcesChanged = Notification.Name("sourcesChanged")
}

// MARK: - Popover view
struct PopoverView: View {
    @ObservedObject var engine: StatsEngine
    let onQuit: () -> Void
    let onRefresh: () -> Void
    var onSettings: () -> Void = {}

    @AppStorage("currencyCode") private var currencyCode = "USD"

    @State private var tab: Tab = .overview
    @State private var hoveredTab: Tab?
    @State private var range: TimeRange = {
        let raw = UserDefaults.standard.string(forKey: "selectedRange") ?? ""
        return TimeRange(rawValue: raw) ?? .all
    }()

    private var summary: StatsSummary { engine.summary(for: range) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            tabBar
            Divider().opacity(0.5)

            if engine.loading && engine.lastUpdated == nil {
                loadingView
            } else if engine.error != nil {
                CenteredMessage(icon: "exclamationmark.triangle",
                                title: "Couldn't read opencode data",
                                subtitle: engine.error)
            } else if SourceScanner.enabledSources.isEmpty {
                CenteredMessage(icon: "t.square.fill",
                                title: "No sources enabled",
                                subtitle: "Enable at least one data source in Preferences → Data.")
            } else {
                ScrollView {
                    content
                        .padding(14)
                }
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 500, height: 672)
        .onChange(of: range) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedRange")
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "t.square.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("TokenTracker")
                    .font(.system(size: 14, weight: .bold))
                if engine.loading {
                    Text("Updating…").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if let d = engine.lastUpdated {
                    Text("Updated \(d.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            rangePicker
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Rescan sessions")
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var rangePicker: some View {
        HStack(spacing: 1) {
            ForEach(TimeRange.allCases) { r in
                Button(action: { withAnimation(.easeOut(duration: 0.15)) { range = r } }) {
                    Text(r.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .foregroundStyle(range == r ? Color.white : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(range == r ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
    }

    // MARK: Tab bar
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(visibleTabs) { t in
                Button(action: { tab = t }) {
                    Text(t.rawValue)
                        .font(.system(size: 11.5, weight: tab == t ? .bold : .medium))
                        .foregroundStyle(tab == t ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(alignment: .bottom) {
                            Rectangle()
                                .fill(tab == t ? Color.accentColor : Color.clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveredTab = hovering ? t : nil
                        }
                        .background(tab != t && hoveredTab == t ? Color.primary.opacity(0.08) : Color.clear)
                        .animation(.easeOut(duration: 0.12), value: hoveredTab)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }

    private var visibleTabs: [Tab] {
        Tab.allCases.filter { $0 != .origins || engine.origins(for: range).count > 1 }
    }

    // MARK: Content
    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview: OverviewTab(s: summary)
        case .tech: TechTab(s: summary)
        case .projects: ProjectsTab(s: summary)
        case .models: ModelsTab(s: summary)
        case .usage: UsageTab(s: summary)
        case .origins: OriginsTab(origins: engine.origins(for: range))
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Reading opencode sessions…")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer
    private var footer: some View {
        MenuRow(title: "Quit", systemImage: "power", shortcut: "⌘Q", action: onQuit)
            .padding(4)
    }
}

// MARK: - Panel (NSPanel)
final class TokenPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - App Delegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: TokenPanel!
    private let engine = StatsEngine()
    private var refreshTimer: Timer?
    private var keyMonitor: Any?

    private let panelSize = NSSize(width: 500, height: 672)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePanel(_:))
            button.target = self
            updateTitle(cost: 0, loading: true)
        }

        buildPanel()
        engine.onLoadComplete = { [weak self] in
            guard let self else { return }
            let raw = UserDefaults.standard.string(forKey: "selectedRange") ?? ""
            let r = TimeRange(rawValue: raw) ?? .all
            self.updateTitle(cost: self.engine.summary(for: r).totalCost, loading: false)
        }
        _ = SourceScanner.scan()
        engine.load()
        CurrencyRates.fetchIfNeeded()
        CurrencyRates.restoreCurrentRate()

        NotificationCenter.default.addObserver(forName: .sourcesChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.engine.load(force: true)
            }
        }

        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            CurrencyRates.fetchIfNeeded()
            CurrencyRates.restoreCurrentRate()
        }

        startTitleSync()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.engine.load() }
        }
    }

private func buildPanel() {
        panel = TokenPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.wantsLayer = true
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.2
        container.layer?.shadowRadius = 16
        container.layer?.shadowOffset = .zero

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        blur.material = .menu
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        blur.autoresizingMask = [.width, .height]

        let root = PopoverView(
            engine: engine,
            onQuit: { NSApp.terminate(nil) },
            onRefresh: { [weak self] in self?.engine.load(force: true) },
            onSettings: { SettingsWindowController.shared.show() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)

        container.addSubview(blur)
        panel.contentView = container
    }

    // MARK: Show/Hide
    @objc private func togglePanel(_ sender: AnyObject?) {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem.button, let win = button.window else { return }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let screenRect = win.convertToScreen(rectInWindow)

        let gap: CGFloat = 4
        var origin = NSPoint(x: screenRect.midX - panelSize.width / 2,
                             y: screenRect.minY - panelSize.height - gap)
        if let screen = win.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            origin.y = vf.maxY - panelSize.height - gap
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - panelSize.width - 8)
        }

        panel.setContentSize(panelSize)
        panel.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "q" {
                NSApp.terminate(nil); return nil
            }
            if event.keyCode == 53 { self.hidePanel(); return nil }
            return event
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification, object: panel)
    }

    @objc private func panelResignedKey() { hidePanel() }

    private func hidePanel() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didResignKeyNotification, object: panel)
        panel.orderOut(nil)
    }

    // MARK: Menu bar title
    private func startTitleSync() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let raw = UserDefaults.standard.string(forKey: "selectedRange") ?? ""
                let r = TimeRange(rawValue: raw) ?? .all
                let cost = self.engine.summary(for: r).totalCost
                self.updateTitle(cost: cost, loading: self.engine.loading)
            }
        }
    }

    @MainActor
    private func updateTitle(cost: Double, loading: Bool) {
        guard let button = statusItem.button else { return }
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        let text: String
        if loading && engine.lastUpdated == nil {
            text = "…"
        } else {
            text = Fmt.money(cost)
        }

        button.image = TTIcon.menuBarImage(size: 14)
        button.imagePosition = .imageLeading
        button.title = text.isEmpty ? "" : " \(text)"
    }
}

// MARK: - Entry point
@main
struct TokenTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}