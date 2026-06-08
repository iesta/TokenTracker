import Foundation

extension StatsEngine {
    nonisolated static func ingestOpenRouter(apiKey: String, dayMap: inout [String: DayAgg], mgmtKey: String? = nil) async throws {
        if let mk = mgmtKey, !mk.isEmpty {
            try await ingestOpenRouterActivity(mgmtKey: mk, dayMap: &dayMap)
        } else {
            try await ingestOpenRouterTotals(apiKey: apiKey, dayMap: &dayMap)
        }
    }

    nonisolated static func ingestOpenRouterActivity(mgmtKey: String, dayMap: inout [String: DayAgg]) async throws {
        var allItems: [[String: Any]] = []
        var cursor: String?

        repeat {
            var urlStr = "https://openrouter.ai/api/v1/activity?limit=100"
            if let c = cursor { urlStr += "&cursor=\(c)" }
            guard let url = URL(string: urlStr) else { break }

            var req = URLRequest(url: url)
            req.setValue("Bearer \(mgmtKey)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 15

            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [[String: Any]] else { break }

            allItems.append(contentsOf: items)
            cursor = json["cursor"] as? String
        } while cursor != nil && !cursor!.isEmpty

        for item in allItems {
            guard let ts = item["created_at"] as? String, ts.count >= 10 else { continue }
            let day = String(ts.prefix(10))
            let hourStr = ts.count >= 16 ? String(ts[ts.index(ts.startIndex, offsetBy: 11)..<ts.index(ts.startIndex, offsetBy: 13)]) : "0"
            let hour = Int(hourStr) ?? 0

            let cost = item["cost"] as? Double ?? 0
            let model = item["model"] as? String ?? "unknown"
            let tokensIn = item["tokens_prompt"] as? Int ?? 0
            let tokensOut = item["tokens_completion"] as? Int ?? 0
            let tokensReasoning = item["tokens_reasoning"] as? Int ?? 0

            if cost <= 0, tokensIn == 0, tokensOut == 0 { continue }

            var agg = dayMap[day] ?? DayAgg(date: day)
            agg.cost += cost
            agg.inputTokens += tokensIn
            agg.outputTokens += tokensOut
            agg.reasoningTokens += tokensReasoning
            agg.modelCost[model, default: 0] += cost
            agg.modelCount[model, default: 0] += 1
            let sid = "openrouter:\(item["id"] as? String ?? "gen")"
            if !agg.sessionIds.contains(sid) { agg.sessionIds.append(sid) }

            var ha = agg.hours[hour] ?? HourlyAgg()
            ha.cost += cost
            ha.inputTokens += tokensIn
            ha.outputTokens += tokensOut
            ha.messages += 1
            agg.hours[hour] = ha

            dayMap[day] = agg
        }
    }

    nonisolated static func ingestOpenRouterTotals(apiKey: String, dayMap: inout [String: DayAgg]) async throws {
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

        if let daily = d["usage_daily"] as? Double, daily > 0 {
            agg.cost += daily
        }
        if let weekly = d["usage_weekly"] as? Double, weekly > 0 {
            agg.cost += weekly / 7
        }

        if agg.cost > 0 {
            agg.modelCost["openrouter", default: 0] += agg.cost
            agg.modelCount["openrouter", default: 0] += 1
            agg.messages += 1
            if !agg.sessionIds.contains("openrouter:auth") {
                agg.sessionIds.append("openrouter:auth")
            }
            dayMap[todayKey] = agg
        }
    }
}