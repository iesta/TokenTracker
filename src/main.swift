import SwiftUI
import AppKit
import Foundation

// MARK: - Color hex init
extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Formatting helpers
let defaultCurrencies: [(code: String, symbol: String, rate: Double, name: String)] = [
    ("USD", "$", 1.0, "US Dollar"),
    ("EUR", "€", 0.92, "Euro"),
    ("GBP", "£", 0.79, "British Pound"),
    ("JPY", "¥", 149.0, "Japanese Yen"),
    ("CAD", "CA$", 1.36, "Canadian Dollar"),
    ("AUD", "A$", 1.53, "Australian Dollar"),
    ("CHF", "Fr", 0.88, "Swiss Franc"),
    ("CNY", "¥", 7.24, "Chinese Yuan"),
    ("INR", "₹", 83.0, "Indian Rupee"),
]

enum SettingsStore {
    static var currencyCode: String {
        get { UserDefaults.standard.string(forKey: "currencyCode") ?? "USD" }
        set { UserDefaults.standard.set(newValue, forKey: "currencyCode") }
    }
    static var currencyRate: Double {
        get {
            let rate = UserDefaults.standard.double(forKey: "currencyRate")
            return rate > 0 ? rate : 1.0
        }
        set { UserDefaults.standard.set(newValue, forKey: "currencyRate") }
    }
    static var currencySymbol: String {
        let match = defaultCurrencies.first { $0.code == currencyCode }
        return match?.symbol ?? "$"
    }
}

// MARK: - OpenCode source scanner
struct OpenCodeSource: Codable, Identifiable, Equatable, Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
    var id: String { path }
    let path: String
    let label: String
    let kind: SourceKind
    var enabled: Bool
    var apiKey: String?
}

enum SourceKind: String, Codable {
    case opencodeDB
    case piSessions
    case openRouter
    case openCodeGo
}

enum SourceScanner {
    static let sourcesKey = "opencodeSources"

    static var storedSources: [OpenCodeSource] {
        get {
            guard let data = UserDefaults.standard.data(forKey: sourcesKey),
                  let sources = try? JSONDecoder().decode([OpenCodeSource].self, from: data) else {
                return []
            }
            return sources
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: sourcesKey)
        }
    }

    static func scan() -> [OpenCodeSource] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [(String, String, SourceKind)] = [
            (home.appendingPathComponent(".local/share/opencode/opencode.db").path,
             "OpenCode Local", .opencodeDB),
            (home.appendingPathComponent("Library/Application Support/opencode/opencode.db").path,
             "OpenCode macOS", .opencodeDB),
            (home.appendingPathComponent(".opencode/opencode.db").path,
             "OpenCode Legacy", .opencodeDB),
        ]

        var existingPaths = Set(storedSources.map { $0.path })
        var newlyFound: [OpenCodeSource] = []

        for (path, label, kind) in candidates {
            if FileManager.default.fileExists(atPath: path), !existingPaths.contains(path) {
                newlyFound.append(OpenCodeSource(path: path, label: label, kind: kind, enabled: true))
                existingPaths.insert(path)
            }
        }

        if let envPath = ProcessInfo.processInfo.environment["OPENCODE_DATA_DIR"], !envPath.isEmpty {
            let dbPath = (envPath as NSString).appendingPathComponent("opencode.db")
            if FileManager.default.fileExists(atPath: dbPath), !existingPaths.contains(dbPath) {
                newlyFound.append(OpenCodeSource(path: dbPath, label: "OPENCODE_DATA_DIR", kind: .opencodeDB, enabled: true))
            }
        }

        // Pi agent sessions
        let piSessions = home.appendingPathComponent(".pi/agent/sessions").path
        if FileManager.default.fileExists(atPath: piSessions), !existingPaths.contains(piSessions) {
            newlyFound.append(OpenCodeSource(path: piSessions, label: "Pi Agent", kind: .piSessions, enabled: true))
            existingPaths.insert(piSessions)
        }

        // OpenCode Go
        let goDB = home.appendingPathComponent(".local/share/opencode-go/opencode.db").path
        if FileManager.default.fileExists(atPath: goDB), !existingPaths.contains(goDB) {
            newlyFound.append(OpenCodeSource(path: goDB, label: "OpenCode Go", kind: .openCodeGo, enabled: true))
            existingPaths.insert(goDB)
        }

        // OpenRouter (placeholder — no local data, reserved for future API integration)
        let orPath = home.appendingPathComponent(".openrouter").path
        if FileManager.default.fileExists(atPath: orPath), !existingPaths.contains(orPath) {
            newlyFound.append(OpenCodeSource(path: orPath, label: "OpenRouter", kind: .openRouter, enabled: true))
            existingPaths.insert(orPath)
        }
        // Also try to auto-detect OpenRouter key from env
        if let envKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !envKey.isEmpty {
            let virtualPath = "openrouter:env"
            if !existingPaths.contains(virtualPath) {
                newlyFound.append(OpenCodeSource(path: virtualPath, label: "OpenRouter", kind: .openRouter, enabled: true, apiKey: envKey))
                existingPaths.insert(virtualPath)
            } else if let idx = newlyFound.firstIndex(where: { $0.path == virtualPath }) {
                newlyFound[idx].apiKey = envKey
            }
        }

        if !newlyFound.isEmpty {
            var current = storedSources
            current.append(contentsOf: newlyFound)
            storedSources = current
        }

        return storedSources
    }

    static var enabledSources: [OpenCodeSource] {
        storedSources.filter { $0.enabled }
    }

    static func signature(for sources: [OpenCodeSource]) -> String {
        let parts: [String] = sources.map { src in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: src.path),
                  let mod = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int64 else {
                return "\(src.path):missing"
            }
            return "\(src.path):\(mod.timeIntervalSince1970)-\(size)"
        }
        return parts.sorted().joined(separator: "|")
    }
}

// MARK: - Currency rate fetching
enum CurrencyRates {
    static var cachedRates: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: "cachedRates") as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "cachedRates") }
    }
    static var lastFetch: Date? {
        get { UserDefaults.standard.object(forKey: "lastRateFetch") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastRateFetch") }
    }

    static var lastFetchLabel: String {
        guard let d = lastFetch else { return "never" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func shouldFetch() -> Bool {
        guard let last = lastFetch else { return true }
        return Date().timeIntervalSince(last) > 86400
    }

    static func fetchIfNeeded() {
        guard shouldFetch() else { return }
        Task { await fetch() }
    }

    static func fetch() async {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json["rates"] as? [String: Double] else { return }
            await MainActor.run {
                cachedRates = rates
                lastFetch = Date()
                // Update the currently selected rate
                let code = SettingsStore.currencyCode
                if code != "USD", let liveRate = rates[code] {
                    SettingsStore.currencyRate = liveRate
                }
            }
        } catch {
            NSLog("CurrencyRates fetch failed: \(error.localizedDescription)")
        }
    }
}

enum Fmt {
    static func money(_ v: Double, rate: Double? = nil, code: String? = nil) -> String {
        let r = rate ?? SettingsStore.currencyRate
        let c = code ?? SettingsStore.currencyCode
        let converted = v * r
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = c
        if let formatted = f.string(from: NSNumber(value: converted)) {
            return formatted
        }
        if let sym = defaultCurrencies.first(where: { $0.code == c })?.symbol {
            return "\(sym)\(String(format: "%.2f", converted))"
        }
        return String(format: "$%.2f", converted)
    }
    static func moneyShort(_ v: Double) -> String {
        let converted = v * SettingsStore.currencyRate
        let sym = SettingsStore.currencySymbol
        if converted >= 1000 { return "\(sym)\(String(format: "%.1fk", converted / 1000))" }
        return "\(sym)\(String(format: "%.0f", converted))"
    }
    static func int(_ v: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    static func tokens(_ v: Int) -> String {
        let d = Double(v)
        if d >= 1_000_000_000 { return String(format: "%.1fB", d / 1e9) }
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1e6) }
        if d >= 1_000 { return String(format: "%.1fK", d / 1e3) }
        return "\(v)"
    }
}

// MARK: - Time range
enum TimeRange: String, CaseIterable, Identifiable {
    case day = "1d"
    case week = "7d"
    case month = "30d"
    case months3 = "3m"
    case all = "All"
    var id: String { rawValue }
    var label: String { rawValue }
    var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .months3: return 90
        case .all: return nil
        }
    }
}

// MARK: - Data models
struct DayAgg: Codable {
    var date: String
    var cost: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var reasoningTokens: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var sessionIds: [String] = []
    var modelCost: [String: Double] = [:]
    var modelCount: [String: Int] = [:]
    var projectCost: [String: Double] = [:]
    var projectSessions: [String: [String]] = [:]
    var projectName: [String: String] = [:]
    var messages: Int = 0
    var langCounts: [String: Int] = [:]
}

struct Aggregate: Codable {
    var dbSignature: String
    var days: [DayAgg]
    var generatedAt: Date
    var sourceSummaries: [String: SourceSummary] = [:]
}

struct SourceSummary: Codable, Identifiable {
    var id: String { label }
    let label: String
    let kind: String
    let totalCost: Double
    let totalTokens: Int
    let sessionCount: Int
    let messageCount: Int
    let dayCount: Int
}

struct ProjectStat: Identifiable {
    var id: String { name }
    let name: String
    let cost: Double
    let sessions: Int
}

struct ModelStat: Identifiable {
    var id: String { name }
    let name: String
    let displayName: String
    let cost: Double
    let count: Int
}

struct ToolStat: Identifiable {
    var id: String { name }
    let name: String
    let count: Int
}

struct DaySpend: Identifiable {
    var id: String { date }
    let date: String
    let day: Date
    let cost: Double
}

struct StatsSummary {
    var totalCost: Double = 0
    var inputTokens = 0, outputTokens = 0, reasoningTokens = 0, cacheRead = 0, cacheWrite = 0
    var sessionCount = 0
    var messages = 0
    var daysActive = 0
    var todayCost: Double = 0
    var avgCostPerDay: Double = 0
    var projects: [ProjectStat] = []
    var models: [ModelStat] = []
    var languages: [LangStat] = []
    var tools: [ToolStat] = []
    var dailySpend: [DaySpend] = []
    var totalTokens: Int { inputTokens + outputTokens + reasoningTokens + cacheRead + cacheWrite }
}

// MARK: - SQLite helper (via /usr/bin/sqlite3 -json)
func queryDB(_ dbPath: String, _ sql: String) throws -> [[String: Any]] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    task.arguments = ["-json", dbPath]

    let inputPipe = Pipe()
    let outputPipe = Pipe()
    task.standardInput = inputPipe
    task.standardOutput = outputPipe

    var outputData = Data()
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if !data.isEmpty { outputData.append(data) }
    }

    try task.run()
    inputPipe.fileHandleForWriting.write(sql.data(using: .utf8)!)
    inputPipe.fileHandleForWriting.closeFile()
    task.waitUntilExit()
    outputPipe.fileHandleForReading.readabilityHandler = nil

    try outputPipe.fileHandleForReading.close()

    guard !outputData.isEmpty,
          let json = try JSONSerialization.jsonObject(with: outputData) as? [[String: Any]] else {
        return []
    }
    return json
}

// MARK: - Engine
@MainActor
final class StatsEngine: ObservableObject {
    @Published var loading = true
    @Published var progress: Double = 0
    @Published var error: String?
    @Published var lastUpdated: Date?

    var onLoadComplete: (() -> Void)?

    private var days: [DayAgg] = []
    private var sourceSummaries: [String: SourceSummary] = [:]

    var origins: [SourceSummary] {
        sourceSummaries.values.sorted { $0.totalCost > $1.totalCost }
    }

    nonisolated static var cacheURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".local/share/opencode/trackercache.json")
    }

    nonisolated static func dbSignature(for sources: [OpenCodeSource]) -> String {
        SourceScanner.signature(for: sources)
    }

    func load(force: Bool = false) {
        loading = true
        progress = 0
        error = nil

        Task.detached(priority: .userInitiated) {
            do {
                let agg = try await Self.buildAggregate(force: force)
                await MainActor.run {
                    self.days = agg.days
                    self.sourceSummaries = agg.sourceSummaries
                    self.lastUpdated = agg.generatedAt
                    self.loading = false
                    self.progress = 1
                    self.onLoadComplete?()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.loading = false
                    self.onLoadComplete?()
                }
            }
        }
    }

    func summary(for range: TimeRange) -> StatsSummary {
        Self.summarize(days: days, range: range)
    }

    nonisolated static func buildAggregate(force: Bool) async throws -> Aggregate {
        let cacheURL = Self.cacheURL
        let sources = SourceScanner.enabledSources
        guard !sources.isEmpty else {
            throw NSError(domain: "TokenTracker", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No opencode databases found. Use opencode first."])
        }
        let sig = Self.dbSignature(for: sources)

        if !force {
            if let data = try? Data(contentsOf: cacheURL),
               let agg = try? JSONDecoder().decode(Aggregate.self, from: data),
               agg.dbSignature == sig {
                return agg
            }
        }

        var dayMap: [String: DayAgg] = [:]
        var perSourceDayMaps: [String: [String: DayAgg]] = [:]

        for src in sources {
            var srcDayMap: [String: DayAgg] = [:]
            switch src.kind {
            case .opencodeDB, .openCodeGo:
                try ingestOpenCodeDB(dbPath: src.path, dayMap: &srcDayMap)
            case .piSessions:
                try ingestPiSessions(dirPath: src.path, dayMap: &srcDayMap)
            case .openRouter:
                if let key = src.apiKey, !key.isEmpty {
                    try await ingestOpenRouter(apiKey: key, dayMap: &srcDayMap)
                }
            }
            // Merge into global dayMap
            for (day, agg) in srcDayMap {
                if let existing = dayMap[day] {
                    var merged = existing
                    merged.cost += agg.cost
                    merged.inputTokens += agg.inputTokens
                    merged.outputTokens += agg.outputTokens
                    merged.reasoningTokens += agg.reasoningTokens
                    merged.cacheRead += agg.cacheRead
                    merged.cacheWrite += agg.cacheWrite
                    merged.messages += agg.messages
                    merged.sessionIds.append(contentsOf: agg.sessionIds.filter { !merged.sessionIds.contains($0) })
                    for (k, v) in agg.modelCost { merged.modelCost[k, default: 0] += v }
                    for (k, v) in agg.modelCount { merged.modelCount[k, default: 0] += v }
                    for (k, v) in agg.projectCost { merged.projectCost[k, default: 0] += v }
                    for (k, ids) in agg.projectSessions {
                        merged.projectSessions[k, default: []].append(contentsOf: ids.filter { !(merged.projectSessions[k]?.contains($0) ?? false) })
                    }
                    for (k, v) in agg.projectName { merged.projectName[k] = v }
                    for (k, v) in agg.langCounts { merged.langCounts[k, default: 0] += v }
                    dayMap[day] = merged
                } else {
                    dayMap[day] = agg
                }
            }
            perSourceDayMaps[src.label] = srcDayMap
        }

        let days = dayMap.keys.sorted().compactMap { dayMap[$0] }

        // Compute per-source summaries
        var sourceSummaries: [String: SourceSummary] = [:]
        for src in sources {
            guard let srcMap = perSourceDayMaps[src.label], !srcMap.isEmpty else { continue }
            let srcDays = srcMap.keys.sorted().compactMap { srcMap[$0] }
            let totalCost = srcDays.reduce(0) { $0 + $1.cost }
            let totalTokens = srcDays.reduce(0) { $0 + $1.inputTokens + $1.outputTokens + $1.reasoningTokens + $1.cacheRead + $1.cacheWrite }
            let sessionCount = Set(srcDays.flatMap { $0.sessionIds }).count
            let messageCount = srcDays.reduce(0) { $0 + $1.messages }
            sourceSummaries[src.label] = SourceSummary(
                label: src.label,
                kind: src.kind.rawValue,
                totalCost: totalCost,
                totalTokens: totalTokens,
                sessionCount: sessionCount,
                messageCount: messageCount,
                dayCount: srcDays.count
            )
        }

        let agg = Aggregate(dbSignature: sig, days: days, generatedAt: Date(), sourceSummaries: sourceSummaries)
        if let data = try? JSONEncoder().encode(agg) {
            try? data.write(to: cacheURL, options: .atomic)
        }

        return agg
    }

    nonisolated static func ingestOpenCodeDB(dbPath: String, dayMap: inout [String: DayAgg]) throws {
        // 1. All sessions with cost/token/model/project data (keyed by session_id)
        let sessionRows = try queryDB(dbPath, """
            SELECT
                s.id as session_id,
                CASE WHEN json_valid(s.model) THEN json_extract(s.model, '$.id') ELSE s.model END as model_id,
                CASE WHEN json_valid(s.model) THEN json_extract(s.model, '$.providerID') ELSE '' END as provider,
                COALESCE(p.name, p.worktree, 'global') as project_name,
                s.cost,
                s.tokens_input,
                s.tokens_output,
                s.tokens_reasoning,
                s.tokens_cache_read,
                s.tokens_cache_write,
                s.project_id,
                date(s.time_created / 1000, 'unixepoch') as session_day
            FROM session s
            LEFT JOIN project p ON s.project_id = p.id
        """)

        var sessionMap: [String: [String: Any]] = [:]
        for row in sessionRows {
            if let sid = row["session_id"] as? String {
                sessionMap[sid] = row
            }
        }

        // 2. Messages per day per session (for day attribution)
        let msgDayRows = try queryDB(dbPath, """
            SELECT
                m.session_id,
                date(m.time_created / 1000, 'unixepoch') as day,
                COUNT(*) as msg_count
            FROM message m
            GROUP BY m.session_id, day
            ORDER BY day
        """)

        // 3. Total messages per session
        let totalMsgRows = try queryDB(dbPath, """
            SELECT session_id, COUNT(*) as total
            FROM message
            GROUP BY session_id
        """)
        var totalMsgCounts: [String: Int] = [:]
        for row in totalMsgRows {
            if let sid = row["session_id"] as? String, let cnt = row["total"] as? Int {
                totalMsgCounts[sid] = cnt
            }
        }

        // 4. Build dayMap from message-day attribution
        for row in msgDayRows {
            guard let sid = row["session_id"] as? String,
                  let day = row["day"] as? String,
                  let dayMsgCount = row["msg_count"] as? Int,
                  let totalMsgs = totalMsgCounts[sid], totalMsgs > 0,
                  let sData = sessionMap[sid] else { continue }

            let fraction = Double(dayMsgCount) / Double(totalMsgs)

            var agg = dayMap[day] ?? DayAgg(date: day)

            agg.cost += (sData["cost"] as? Double ?? 0) * fraction
            agg.inputTokens += Int(Double(sData["tokens_input"] as? Int ?? 0) * fraction)
            agg.outputTokens += Int(Double(sData["tokens_output"] as? Int ?? 0) * fraction)
            agg.reasoningTokens += Int(Double(sData["tokens_reasoning"] as? Int ?? 0) * fraction)
            agg.cacheRead += Int(Double(sData["tokens_cache_read"] as? Int ?? 0) * fraction)
            agg.cacheWrite += Int(Double(sData["tokens_cache_write"] as? Int ?? 0) * fraction)

            if !agg.sessionIds.contains(sid) {
                agg.sessionIds.append(sid)
            }
            agg.messages += dayMsgCount

            let modelId = (sData["model_id"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            if !modelId.isEmpty {
                agg.modelCost[modelId, default: 0] += (sData["cost"] as? Double ?? 0) * fraction
                agg.modelCount[modelId, default: 0] += 1
            }

            let projName = sData["project_name"] as? String ?? "global"
            agg.projectCost[projName, default: 0] += (sData["cost"] as? Double ?? 0) * fraction
            if !(agg.projectSessions[projName]?.contains(sid) ?? false) {
                agg.projectSessions[projName, default: []].append(sid)
            }
            agg.projectName[projName] = projName

            dayMap[day] = agg
        }

        // 5. Fallback: sessions with no messages attributed via session_day
        for (sid, sData) in sessionMap {
            let totalMsgs = totalMsgCounts[sid] ?? 0
            if totalMsgs > 0 { continue } // already handled by message-based attribution

            guard let day = sData["session_day"] as? String else { continue }
            var agg = dayMap[day] ?? DayAgg(date: day)
            agg.cost += sData["cost"] as? Double ?? 0
            agg.inputTokens += sData["tokens_input"] as? Int ?? 0
            agg.outputTokens += sData["tokens_output"] as? Int ?? 0
            agg.reasoningTokens += sData["tokens_reasoning"] as? Int ?? 0
            agg.cacheRead += sData["tokens_cache_read"] as? Int ?? 0
            agg.cacheWrite += sData["tokens_cache_write"] as? Int ?? 0
            if !agg.sessionIds.contains(sid) { agg.sessionIds.append(sid) }

            let modelId = (sData["model_id"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            if !modelId.isEmpty {
                agg.modelCost[modelId, default: 0] += sData["cost"] as? Double ?? 0
                agg.modelCount[modelId, default: 0] += 1
            }
            let projName = sData["project_name"] as? String ?? "global"
            agg.projectCost[projName, default: 0] += sData["cost"] as? Double ?? 0
            if !(agg.projectSessions[projName]?.contains(sid) ?? false) {
                agg.projectSessions[projName, default: []].append(sid)
            }
            agg.projectName[projName] = projName
            dayMap[day] = agg
        }

        // 6. Language counts from part tool calls (use message time_created for day attribution)
        let partRows = try queryDB(dbPath, """
            SELECT
                date(m.time_created / 1000, 'unixepoch') as day,
                json_extract(pr.data, '$.state.input.filePath') as path
            FROM part pr
            JOIN message m ON pr.message_id = m.id
            WHERE json_extract(pr.data, '$.state.input.filePath') IS NOT NULL
              AND json_extract(pr.data, '$.state.input.filePath') LIKE '%.%'
              AND json_extract(pr.data, '$.tool') IS NOT NULL
            ORDER BY day
        """)

        for row in partRows {
            guard let day = row["day"] as? String,
                  let path = row["path"] as? String else { continue }
            let ext = String(path.split(separator: ".").last ?? "").lowercased()
            guard let lang = languageMap[ext] else { continue }
            var agg = dayMap[day] ?? DayAgg(date: day)
            agg.langCounts[lang.name, default: 0] += 1
            dayMap[day] = agg
        }
    }

    nonisolated static func ingestPiSessions(dirPath: String, dayMap: inout [String: DayAgg]) throws {
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: dirPath),
                                              includingPropertiesForKeys: nil) else { return }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            var sessionDate: String?
            var sessionProject: String?
            var sessionId: String?
            var models: Set<String> = []
            var msgCount = 0
            var fileExts: [String] = []

            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      let data = try? JSONSerialization.jsonObject(with: trimmed.data(using: .utf8)!) as? [String: Any] else { continue }
                let type = data["type"] as? String ?? ""

                switch type {
                case "session":
                    if let ts = data["timestamp"] as? String {
                        sessionDate = String(ts.prefix(10))
                    }
                    sessionId = data["id"] as? String
                    if let cwd = data["cwd"] as? String {
                        sessionProject = String(cwd.split(separator: "/").last ?? "")
                    }
                case "model_change":
                    if let model = data["modelId"] as? String {
                        models.insert(model)
                    }
                case "message":
                    msgCount += 1
                    if let msg = data["message"] as? [String: Any],
                       let content = msg["content"] as? [[String: Any]] {
                        for block in content {
                            if block["type"] as? String == "toolCall",
                               let args = block["arguments"] as? [String: Any],
                               let path = args["path"] as? String {
                                let ext = String(path.split(separator: ".").last ?? "").lowercased()
                                if !ext.isEmpty { fileExts.append(ext) }
                            }
                        }
                    }
                default:
                    break
                }
            }

            guard let day = sessionDate else { continue }
            var agg = dayMap[day] ?? DayAgg(date: day)
            agg.messages += msgCount
            if let sid = sessionId, !agg.sessionIds.contains(sid) {
                agg.sessionIds.append(sid)
            }
            for m in models {
                agg.modelCount[m, default: 0] += 1
            }
            if let proj = sessionProject {
                agg.projectCost[proj, default: 0] += 1
                if !(agg.projectSessions[proj]?.contains(sessionId ?? "") ?? false) {
                    agg.projectSessions[proj, default: []].append(sessionId ?? "")
                }
                agg.projectName[proj] = proj
            }
            for ext in fileExts {
                if let lang = languageMap[ext] {
                    agg.langCounts[lang.name, default: 0] += 1
                }
            }
            dayMap[day] = agg
        }
    }

    nonisolated static func ingestOpenRouter(apiKey: String, dayMap: inout [String: DayAgg]) async throws {
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/key") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = json["data"] as? [String: Any] else { return }

        let todayKey: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        var agg = dayMap[todayKey] ?? DayAgg(date: todayKey)

        // usage_daily = today's cost from OpenRouter
        if let daily = d["usage_daily"] as? Double, daily > 0 {
            agg.cost += daily
        }
        if let weekly = d["usage_weekly"] as? Double, weekly > 0 {
            // Attribute weekly usage proportionally to today
            // (rough estimate — 1/7th of weekly)
            let dailyEstimate = weekly / 7
            agg.cost += dailyEstimate
        }

        if agg.cost > 0 {
            let modelId = "openrouter"
            agg.modelCost[modelId, default: 0] += agg.cost
            agg.modelCount[modelId, default: 0] += 1
            agg.messages += 1
            if !agg.sessionIds.contains("openrouter:auth") {
                agg.sessionIds.append("openrouter:auth")
            }
            dayMap[todayKey] = agg
        }
    }

    nonisolated static func summarize(days: [DayAgg], range: TimeRange) -> StatsSummary {
        let cal = Calendar.current
        let todayKey = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        let filtered: [DayAgg]
        if let nDays = range.days {
            // 1d includes yesterday so it's never empty when there's recent data
            let offset = -(nDays - 1)
            let cutoff = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
            let dayFmt: DateFormatter = {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone.current
                f.dateFormat = "yyyy-MM-dd"
                return f
            }()
            filtered = days.filter { d in
                guard let dt = dayFmt.date(from: d.date) else { return false }
                return dt >= cutoff
            }
        } else {
            filtered = days
        }

        var s = StatsSummary()
        var sessionSet = Set<String>()
        var modelCost: [String: Double] = [:]
        var modelCount: [String: Int] = [:]
        var projCost: [String: Double] = [:]
        var projSessions: [String: Set<String>] = [:]
        var langCounts: [String: Int] = [:]
        var spend: [DaySpend] = []

        let dayFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()

        for d in filtered {
            s.totalCost += d.cost
            s.inputTokens += d.inputTokens
            s.outputTokens += d.outputTokens
            s.reasoningTokens += d.reasoningTokens
            s.cacheRead += d.cacheRead
            s.cacheWrite += d.cacheWrite
            s.messages += d.messages
            sessionSet.formUnion(d.sessionIds)
            for (k, v) in d.modelCost { modelCost[k, default: 0] += v }
            for (k, v) in d.modelCount { modelCount[k, default: 0] += v }
            for (k, v) in d.projectCost { projCost[k, default: 0] += v }
            for (k, ids) in d.projectSessions { projSessions[k, default: []].formUnion(ids) }
            for (k, v) in d.langCounts { langCounts[k, default: 0] += v }
            if d.date == todayKey { s.todayCost += d.cost }
            if let dt = dayFmt.date(from: d.date) {
                spend.append(DaySpend(date: d.date, day: dt, cost: d.cost))
            }
        }

        s.sessionCount = sessionSet.count
        s.daysActive = filtered.filter { $0.cost > 0 || $0.messages > 0 }.count
        s.avgCostPerDay = s.daysActive > 0 ? s.totalCost / Double(s.daysActive) : 0

        s.models = modelCount.map { (name, count) in
            ModelStat(name: name, displayName: prettyModel(name), cost: modelCost[name] ?? 0, count: count)
        }.sorted { $0.cost > $1.cost }

        s.projects = projCost.map { (name, cost) in
            ProjectStat(name: name, cost: cost, sessions: projSessions[name]?.count ?? 0)
        }.sorted { $0.cost > $1.cost }

        s.languages = langCounts.map { (name, count) in
            let info = languageMap.values.first { $0.name == name } ?? LangInfo(name: name, color: .secondary, symbol: "doc.text")
            return LangStat(name: name, count: count, color: info.color, symbol: info.symbol)
        }.sorted { $0.count > $1.count }

        // Daily spend with gap filling
        var filledSpend: [DaySpend] = []
        let startDate: Date
        let endDate = cal.startOfDay(for: Date())

        if let nDays = range.days {
            let offset = -(nDays - 1)
            startDate = cal.date(byAdding: .day, value: offset, to: endDate)!
        } else if let earliest = spend.map({ $0.day }).min() {
            startDate = earliest
        } else {
            startDate = endDate
        }

        var cur = startDate
        let spendMap = Dictionary(uniqueKeysWithValues: spend.map { ($0.date, $0) })
        while cur <= endDate {
            let curKey = dayFmt.string(from: cur)
            if let existing = spendMap[curKey] {
                filledSpend.append(existing)
            } else {
                filledSpend.append(DaySpend(date: curKey, day: cur, cost: 0))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cur) else { break }
            cur = next
        }
        s.dailySpend = filledSpend

        return s
    }

    nonisolated static func prettyModel(_ id: String) -> String {
        var n = id
        n = n.replacingOccurrences(of: "claude-", with: "Claude ")
        n = n.replacingOccurrences(of: "gpt-", with: "GPT-")
        if let r = n.range(of: #"-\d{8}$"#, options: .regularExpression) {
            n.removeSubrange(r)
        }
        n = n.replacingOccurrences(of: "opus", with: "Opus", options: .caseInsensitive)
        n = n.replacingOccurrences(of: "sonnet", with: "Sonnet", options: .caseInsensitive)
        n = n.replacingOccurrences(of: "haiku", with: "Haiku", options: .caseInsensitive)
        n = n.replacingOccurrences(of: "deepseek/", with: "", options: .caseInsensitive)
        n = n.replacingOccurrences(of: "-free", with: " (Free)")
        return n
    }

    // MARK: - Menu bar values
    private var todayAgg: DayAgg? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        let key = f.string(from: Date())
        return days.first { $0.date == key }
    }

    var todayCost: Double { todayAgg?.cost ?? 0 }
    var todayTokens: Int { (todayAgg?.inputTokens ?? 0) + (todayAgg?.outputTokens ?? 0) }
    var todaySessions: Int { todayAgg?.sessionIds.count ?? 0 }
    var totalCostAll: Double { days.reduce(0) { $0 + $1.cost } }
}

// MARK: - Language map
struct LangInfo {
    let name: String
    let color: Color
    let symbol: String
}

let languageMap: [String: LangInfo] = [
    "swift":   LangInfo(name: "Swift",       color: .orange,    symbol: "swift"),
    "py":      LangInfo(name: "Python",      color: .blue,      symbol: "server.rack"),
    "js":      LangInfo(name: "JavaScript",  color: .yellow,    symbol: "chevron.left.forwardslash.chevron.right"),
    "ts":      LangInfo(name: "TypeScript",  color: .blue,      symbol: "chevron.left.forwardslash.chevron.right"),
    "jsx":     LangInfo(name: "React/JSX",   color: Color(hex: 0x61DAFB), symbol: "atom"),
    "tsx":     LangInfo(name: "React/TSX",   color: Color(hex: 0x3178C6), symbol: "atom"),
    "rs":      LangInfo(name: "Rust",        color: .brown,     symbol: "gear"),
    "go":      LangInfo(name: "Go",          color: Color(hex: 0x00ADD8), symbol: "arrow.up.arrow.down"),
    "rb":      LangInfo(name: "Ruby",        color: .red,       symbol: "gem"),
    "java":    LangInfo(name: "Java",        color: .brown,     symbol: "cup.and.saucer"),
    "kt":      LangInfo(name: "Kotlin",      color: Color(hex: 0x7F52FF), symbol: "suit.heart"),
    "svelte":  LangInfo(name: "Svelte",      color: .orange,    symbol: "sparkles"),
    "vue":     LangInfo(name: "Vue",         color: Color(hex: 0x4FC08D), symbol: "sparkles"),
    "c":       LangInfo(name: "C",           color: Color(hex: 0x555555), symbol: "cpu"),
    "cpp":     LangInfo(name: "C++",         color: .purple,    symbol: "cpu"),
    "h":       LangInfo(name: "C/C++ Header", color: .purple,   symbol: "doc.text"),
    "cs":      LangInfo(name: "C#",          color: .green,     symbol: "number"),
    "zig":     LangInfo(name: "Zig",         color: Color(hex: 0xF7A41D), symbol: "bolt"),
    "lua":     LangInfo(name: "Lua",         color: .blue,      symbol: "moon"),
    "sql":     LangInfo(name: "SQL",         color: Color(hex: 0xCC2927), symbol: "cylinder"),
    "md":      LangInfo(name: "Markdown",    color: .secondary, symbol: "doc.text"),
    "json":    LangInfo(name: "JSON",        color: .secondary, symbol: "curlybraces"),
    "yaml":    LangInfo(name: "YAML",        color: .secondary, symbol: "doc.text"),
    "toml":    LangInfo(name: "TOML",        color: .secondary, symbol: "doc.text"),
    "html":    LangInfo(name: "HTML",        color: .orange,    symbol: "globe"),
    "css":     LangInfo(name: "CSS",         color: .purple,    symbol: "paintbrush"),
    "scss":    LangInfo(name: "SCSS",        color: .pink,      symbol: "paintbrush"),
    "sh":      LangInfo(name: "Shell",       color: .green,     symbol: "terminal"),
    "bash":    LangInfo(name: "Bash",        color: .green,     symbol: "terminal"),
    "fish":    LangInfo(name: "Fish",        color: .green,     symbol: "terminal"),
    "zsh":     LangInfo(name: "Zsh",         color: .green,     symbol: "terminal"),
    "dockerfile": LangInfo(name: "Docker",   color: Color(hex: 0x2496ED), symbol: "shippingbox"),
    "plist":   LangInfo(name: "Plist",       color: .secondary, symbol: "list.bullet"),
    "entitlements": LangInfo(name: "Entitlements", color: .secondary, symbol: "lock.shield"),
    "pbxproj": LangInfo(name: "Xcode Project", color: .secondary, symbol: "hammer"),
    "xcworkspacedata": LangInfo(name: "Xcode Workspace", color: .secondary, symbol: "hammer"),
    "gradle":  LangInfo(name: "Gradle",      color: Color(hex: 0x02303A), symbol: "building.2"),
]

struct LangStat: Identifiable {
    var id: String { name }
    let name: String
    let count: Int
    let color: Color
    let symbol: String
}

// MARK: - Menu bar icon
enum TTIcon {
    static func menuBarImage(size: CGFloat = 14) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)

            // Simple "T" letter mark
            let pad = rect.width * 0.15
            let barH = rect.height * 0.18
            let barY = rect.height - barH - pad

            // Top bar
            ctx.fill(CGRect(x: pad, y: barY, width: rect.width - 2 * pad, height: barH))

            // Vertical stem
            let stemW = rect.width * 0.22
            let stemX = (rect.width - stemW) / 2
            ctx.fill(CGRect(x: stemX, y: pad, width: stemW, height: rect.height - pad - barH - pad))

            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: - UI Components
struct MenuRow: View {
    let title: String
    var systemImage: String? = nil
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let img = systemImage {
                    Image(systemName: img)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if let sc = shortcut {
                    Text(sc)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(hovering ? Color.white.opacity(0.85) : .secondary)
                }
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            if let t = trailing {
                Text(t)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BarRow: View {
    let rank: Int
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let value: String
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(value)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06)).frame(height: 5)
                        Capsule().fill(color)
                            .frame(width: max(4, geo.size.width * fraction), height: 5)
                    }
                }
                .frame(height: 5)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct CenteredMessage: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let s = subtitle {
                Text(s)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

// MARK: - Daily spend bar chart (pure SwiftUI, no Charts framework)
struct DailySpendChart: View {
    let data: [DaySpend]
    @State private var selectedDate: Date?

    private var maxCost: Double {
        max(data.map(\.cost).max() ?? 1, 0.01)
    }

    private var selected: DaySpend? {
        guard let selectedDate else { return nil }
        let cal = Calendar.current
        return data.first { cal.isDate($0.day, inSameDayAs: selectedDate) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let barCount = max(data.count, 1)
                let totalSpacing = CGFloat(barCount - 1) * 2
                let barW = max(4, (geo.size.width - totalSpacing) / CGFloat(barCount))

                ZStack(alignment: .bottomLeading) {
                    // Grid lines
                    ForEach(0..<4) { i in
                        let y = geo.size.height * CGFloat(i) / 3
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    }

                    // Bars
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(data) { d in
                            let fraction = d.cost / maxCost
                            let barH = max(CGFloat(fraction) * geo.size.height, fraction > 0 ? 2 : 0)
                            let isSelected = selected.map { Calendar.current.isDate(d.day, inSameDayAs: $0.day) } ?? false

                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: 0x6FCF73), Color(hex: 0x4CAF50)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .frame(width: barW, height: barH)
                                .opacity(selected == nil || isSelected ? 1 : 0.35)
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        if isSelected {
                                            selectedDate = nil
                                        } else {
                                            selectedDate = d.day
                                        }
                                    }
                                }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    // Tooltip for selected
                    if let sel = selected {
                        let idx = data.firstIndex { Calendar.current.isDate($0.day, inSameDayAs: sel.day) } ?? 0
                        let x = CGFloat(idx) * (barW + 2) + barW / 2
                        VStack(spacing: 1) {
                            Text(sel.day, format: .dateTime.weekday(.abbreviated).month().day())
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(Fmt.money(sel.cost))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x4CAF50))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08)))
                        .position(x: min(max(x, 50), geo.size.width - 50),
                                  y: max(25, geo.size.height - CGFloat(data[idx].cost / maxCost) * geo.size.height - 20))
                    }
                }
            }

            // X-axis labels
            HStack(spacing: 2) {
                let labels = axisLabels(for: data)
                ForEach(labels, id: \.offset) { label in
                    Text(label.text)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: label.offset == 0 ? .leading : label.offset == labels.last?.offset ? .trailing : .center)
                }
            }
        }
    }

    private struct AxisLabel {
        let offset: Int
        let text: String
    }

    private func axisLabels(for data: [DaySpend]) -> [AxisLabel] {
        guard data.count > 1 else { return [AxisLabel(offset: 0, text: data.first.map { fmtDay($0.day) } ?? "")] }
        let count = min(4, data.count)
        let step = (data.count - 1) / max(count - 1, 1)
        var labels: [AxisLabel] = []
        for i in stride(from: 0, to: data.count, by: step) {
            labels.append(AxisLabel(offset: i, text: fmtDay(data[i].day)))
        }
        if labels.last?.offset != data.count - 1 {
            labels.append(AxisLabel(offset: data.count - 1, text: fmtDay(data.last!.day)))
        }
        return labels
    }

    private func fmtDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: d)
    }
}

// MARK: - Tabs
enum Tab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case tech = "Tech"
    case projects = "Projects"
    case models = "Models"
    case usage = "Usage"
    case origins = "Origins"
    var id: String { rawValue }
}

// Overview
struct OverviewTab: View {
    let s: StatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                StatCard(icon: "dollarsign.circle.fill", iconColor: .green,
                         title: "Total", value: Fmt.money(s.totalCost))
                StatCard(icon: "bubble.left.and.bubble.right.fill", iconColor: .blue,
                         title: "Sessions", value: Fmt.int(s.sessionCount))
                StatCard(icon: "ellipsis.message.fill", iconColor: .purple,
                         title: "Messages", value: Fmt.int(s.messages))
                StatCard(icon: "calendar", iconColor: .orange,
                         title: "Active Days", value: Fmt.int(s.daysActive))
                StatCard(icon: "chart.line.uptrend.xyaxis", iconColor: .teal,
                         title: "Avg/Day", value: Fmt.money(s.avgCostPerDay))
                StatCard(icon: "clock.fill", iconColor: .red,
                         title: "Today", value: Fmt.money(s.todayCost))
            }

            if !s.dailySpend.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Daily Spend",
                                  trailing: "\(s.dailySpend.count) days")
                    DailySpendChart(data: s.dailySpend)
                        .frame(height: 140)
                }
            }

            if let topModel = s.models.first {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Top Model")
                    BarRow(rank: 1, icon: "cpu", color: .blue, title: topModel.displayName,
                           subtitle: "\(Fmt.int(topModel.count)) calls",
                           value: Fmt.money(topModel.cost), fraction: 1)
                }
            }
        }
    }
}

// Projects
struct ProjectsTab: View {
    let s: StatsSummary
    @State private var flashId: String?

    var body: some View {
        if s.projects.isEmpty {
            CenteredMessage(icon: "folder", title: "No projects")
        } else {
            let maxCost = max(s.projects.map { $0.cost }.max() ?? 1, 0.0001)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Projects", trailing: "by cost")
                VStack(spacing: 12) {
                    ForEach(Array(s.projects.prefix(15).enumerated()), id: \.element.id) { idx, p in
                        BarRow(rank: idx + 1, icon: "folder.fill",
                               color: projectColor(idx), title: shortName(p.name),
                               subtitle: "\(p.sessions) session\(p.sessions == 1 ? "" : "s")",
                               value: Fmt.money(p.cost),
                               fraction: p.cost / maxCost)
                        .opacity(flashId == p.name ? 0.2 : 1)
                        .animation(.easeInOut(duration: 0.08), value: flashId)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(p.name, forType: .string)
                            flashProject(p.name)
                        }
                    }
                }
            }
        }
    }

    private func shortName(_ path: String) -> String {
        if path.contains("/") {
            return String(path.split(separator: "/").last ?? "")
        }
        return path
    }

    private func flashProject(_ id: String) {
        flashId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            flashId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                flashId = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    flashId = nil
                }
            }
        }
    }

    private func projectColor(_ i: Int) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red, .cyan, .mint, .yellow, .brown]
        return palette[i % palette.count]
    }
}

// Tech
struct TechTab: View {
    let s: StatsSummary
    var body: some View {
        if s.languages.isEmpty {
            CenteredMessage(icon: "chevron.left.forwardslash.chevron.right",
                            title: "No tech usage yet",
                            subtitle: "Languages appear once you edit files via opencode.")
        } else {
            let maxCount = max(s.languages.map { $0.count }.max() ?? 1, 1)
            let totalCount = max(s.languages.reduce(0) { $0 + $1.count }, 1)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Tech Used", trailing: "\(Fmt.int(totalCount)) calls")
                VStack(spacing: 12) {
                    ForEach(Array(s.languages.enumerated()), id: \.element.id) { idx, l in
                        BarRow(rank: idx + 1, icon: l.symbol, color: l.color, title: l.name,
                               subtitle: "\(pct(l.count, totalCount))",
                               value: "\(Fmt.int(l.count)) calls",
                               fraction: Double(l.count) / Double(maxCount))
                    }
                }
            }
        }
    }
    private func pct(_ a: Int, _ b: Int) -> String {
        String(format: "%.0f%%", Double(a) / Double(b) * 100)
    }
}

// Models
struct ModelsTab: View {
    let s: StatsSummary
    @State private var flashId: String?

    var body: some View {
        if s.models.isEmpty {
            CenteredMessage(icon: "cpu", title: "No model usage")
        } else {
            let maxCost = max(s.models.map { $0.cost }.max() ?? 1, 0.0001)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Models", trailing: "by cost")
                VStack(spacing: 12) {
                    ForEach(Array(s.models.enumerated()), id: \.element.id) { idx, m in
                        BarRow(rank: idx + 1, icon: "cpu", color: modelColor(m.name),
                               title: m.displayName,
                               subtitle: "\(Fmt.int(m.count)) calls",
                               value: Fmt.money(m.cost),
                               fraction: m.cost / maxCost)
                        .opacity(flashId == m.name ? 0.2 : 1)
                        .animation(.easeInOut(duration: 0.08), value: flashId)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(m.name, forType: .string)
                            flashModel(m.name)
                        }
                    }
                }
            }
        }
    }

    private func flashModel(_ id: String) {
        flashId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            flashId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                flashId = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    flashId = nil
                }
            }
        }
    }

    private func modelColor(_ id: String) -> Color {
        let lower = id.lowercased()
        if lower.contains("opus") { return Color(hex: 0xD97757) }
        if lower.contains("sonnet") { return Color(hex: 0xCC8B5C) }
        if lower.contains("haiku") { return Color(hex: 0xE0A971) }
        if lower.contains("gpt") { return Color(hex: 0x10A37F) }
        if lower.contains("gemini") { return Color(hex: 0x4285F4) }
        if lower.contains("deepseek") { return Color(hex: 0x4F46E5) }
        return Color(hex: 0x8E8E93)
    }
}

// Usage
struct UsageTab: View {
    let s: StatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Tokens", trailing: Fmt.tokens(s.totalTokens))
            VStack(spacing: 9) {
                tokenRow("Input", s.inputTokens, .blue)
                tokenRow("Output", s.outputTokens, .green)
                tokenRow("Reasoning", s.reasoningTokens, .purple)
                tokenRow("Cache Read", s.cacheRead, .orange)
                tokenRow("Cache Write", s.cacheWrite, .indigo)
            }
        }
    }

    private func tokenRow(_ name: String, _ value: Int, _ color: Color) -> some View {
        let total = max(s.totalTokens, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name).font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(Fmt.tokens(value))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06)).frame(height: 5)
                    Capsule().fill(color)
                        .frame(width: max(4, geo.size.width * Double(value) / Double(total)), height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Origins tab
struct OriginsTab: View {
    let origins: [SourceSummary]

    var body: some View {
        if origins.isEmpty {
            CenteredMessage(icon: "square.grid.3x1.filled.below.line.rectangle", title: "Single source",
                            subtitle: "Origins appear when multiple sources are active.")
        } else if origins.count == 1 {
            CenteredMessage(icon: "square.grid.3x1.filled.below.line.rectangle", title: "Single source",
                            subtitle: "Add another data source to compare origins.")
        } else {
            let maxCost = max(origins.map { $0.totalCost }.max() ?? 1, 0.0001)
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Origins", trailing: "\(origins.count) sources")

                ForEach(origins) { src in
                    VStack(alignment: .leading, spacing: 6) {
                        BarRow(rank: 0, icon: src.kind == "piSessions" ? "brain" :
                                      src.kind == "openRouter" ? "network" :
                                      src.kind == "openCodeGo" ? "arrow.triangle.swap" : "externaldrive",
                               color: originColor(src.label),
                               title: src.label,
                               subtitle: "\(src.dayCount) day\(src.dayCount == 1 ? "" : "s") · \(Fmt.int(src.sessionCount)) session\(src.sessionCount == 1 ? "" : "s") · \(Fmt.int(src.messageCount)) msg\(src.messageCount == 1 ? "" : "s")",
                               value: "\(src.totalCost > 0 ? Fmt.money(src.totalCost) : "–") · \(Fmt.tokens(src.totalTokens))",
                               fraction: src.totalCost > 0 ? src.totalCost / maxCost : 0)
                    }
                }
            }
        }
    }

    private func originColor(_ label: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red, .cyan, .mint]
        let hash = abs(label.hashValue)
        return palette[hash % palette.count]
    }
}

// MARK: - Settings view
enum SettingsPage: Hashable {
    case general, currencies, data, about
    case source(OpenCodeSource)

    var label: String {
        switch self {
        case .general: return "General"
        case .currencies: return "Currencies"
        case .data: return "Data"
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
            case .piSessions: return "brain"
            case .openRouter: return "network"
            case .openCodeGo: return "arrow.triangle.swap"
            case .opencodeDB: return "externaldrive"
            }
        case .about: return "info.circle"
        }
    }

    static func allPages(sources: [OpenCodeSource]) -> [SettingsPage] {
        var pages: [SettingsPage] = [.general, .currencies, .data]
        for src in sources {
            pages.append(.source(src))
        }
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
        .frame(width: 600, height: 440)
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

    // MARK: General
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
        }
        .padding(24)
    }

    // MARK: Currencies
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
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
        .padding(24)
    }

    // MARK: Data
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
                    Text("No opencode databases found. Use opencode first to generate data.")
                        .font(.system(size: 12))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }
            }
        }
        .padding(24)
    }

    // MARK: Source detail
    private func sourceDetailPane(_ src: OpenCodeSource) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(src.label).font(.system(size: 15, weight: .bold))
            Divider()
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Type", src.kind == .opencodeDB ? "OpenCode DB" :
                                    src.kind == .piSessions ? "Pi Sessions (JSONL)" :
                                    src.kind == .openRouter ? "OpenRouter API" : "OpenCode Go DB")
                    detailRow("Path", src.path)
                    if src.kind == .opencodeDB || src.kind == .openCodeGo {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: src.path) {
                            detailRow("Size", ByteCountFormatter.string(fromByteCount: Int64(attrs[.size] as? Int64 ?? 0), countStyle: .file))
                            if let mod = attrs[.modificationDate] as? Date {
                                detailRow("Last modified", mod.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                    } else if src.kind == .piSessions {
                        let count = (try? FileManager.default.contentsOfDirectory(atPath: src.path).count) ?? 0
                        detailRow("Session files", "\(count)")
                    } else if src.kind == .openRouter {
                        let hasKey = src.apiKey != nil && !src.apiKey!.isEmpty
                        detailRow("API Key", hasKey ? "✓ Configured" : "Not set")
                        detailRow("Endpoint", "api.openrouter.ai/v1/auth/key")
                        if !hasKey {
                            SecureField("sk-or-v1-...", text: Binding(
                                get: { "" },
                                set: { newKey in
                                    let trimmed = newKey.trimmingCharacters(in: .whitespaces)
                                    if !trimmed.isEmpty, let idx = sources.firstIndex(where: { $0.id == src.id }) {
                                        sources[idx].apiKey = trimmed
                                        SourceScanner.storedSources = sources
                                    }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(10)
            }
            HStack {
                Toggle("Enabled", isOn: Binding(
                    get: { src.enabled },
                    set: { newVal in
                        if let idx = sources.firstIndex(where: { $0.id == src.id }) {
                            sources[idx].enabled = newVal
                            SourceScanner.storedSources = sources
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
            }
        }
        .padding(24)
    }

    // MARK: About
    private var aboutPane: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "t.square.fill")
                .font(.system(size: 50))
                .foregroundStyle(.tint)
            Text("TokenTracker").font(.title).bold()
            Text("Version 1.0.0")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Reads opencode session data from local SQLite databases to show usage costs, tokens, projects, models, and languages.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .lineSpacing(4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Helpers
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
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
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

// MARK: - Popover view
struct PopoverView: View {
    @ObservedObject var engine: StatsEngine
    let onQuit: () -> Void
    let onRefresh: () -> Void
    var onSettings: () -> Void = {}

    @AppStorage("currencyCode") private var currencyCode = "USD"

    @State private var tab: Tab = .overview
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
            } else {
                ScrollView {
                    content
                        .padding(14)
                }
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 500, height: 560)
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
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }

    private var visibleTabs: [Tab] {
        Tab.allCases.filter { $0 != .origins || engine.origins.count > 1 }
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
        case .origins: OriginsTab(origins: engine.origins)
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

    private let panelSize = NSSize(width: 500, height: 560)

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

        // Daily rate refresh timer (check every hour if 24h passed)
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            CurrencyRates.fetchIfNeeded()
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

        // Container view provides the shadow (no masksToBounds so shadow renders)
        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.wantsLayer = true
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.2
        container.layer?.shadowRadius = 16
        container.layer?.shadowOffset = .zero

        // Blur view provides the rounded background (masksToBounds clips the blur)
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
