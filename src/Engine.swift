import Foundation

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

        if sources.isEmpty {
            return Aggregate(dbSignature: "no-sources", days: [], generatedAt: Date(), sourceSummaries: [:])
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
            do {
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
            } catch {
                NSLog("TokenTracker source '\(src.label)' failed: \(error.localizedDescription)")
            }
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

        // Hourly or daily spend
        if range == .day, !filtered.isEmpty, !filtered[0].hours.isEmpty {
            for hour in 0..<24 {
                if let ha = filtered[0].hours[hour] {
                    s.hourlySpend.append(HourSpend(date: todayKey, hour: hour, cost: ha.cost))
                } else {
                    s.hourlySpend.append(HourSpend(date: todayKey, hour: hour, cost: 0))
                }
            }
        } else {
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
        }

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