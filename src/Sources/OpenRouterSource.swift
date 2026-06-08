import Foundation

extension StatsEngine {
    nonisolated static func ingestOpenRouter(apiKey: String, dayMap: inout [String: DayAgg], mgmtKey: String? = nil) async throws {
        if let mk = mgmtKey, !mk.isEmpty {
            do {
                try await ingestOpenRouterActivity(mgmtKey: mk, dayMap: &dayMap)
            } catch {
                NSLog("OpenRouter activity failed, falling back to totals: \(error.localizedDescription)")
                try await ingestOpenRouterTotals(apiKey: apiKey, dayMap: &dayMap)
            }
        } else {
            try await ingestOpenRouterTotals(apiKey: apiKey, dayMap: &dayMap)
        }
    }

    nonisolated static func ingestOpenRouterActivity(mgmtKey: String, dayMap: inout [String: DayAgg]) async throws {
        guard let url = URL(string: "https://openrouter.ai/api/v1/activity?limit=200") else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(mgmtKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let httpResp = resp as? HTTPURLResponse else {
            throw NSError(domain: "OpenRouter", code: 0, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NSError(domain: "OpenRouter", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: "Status \(httpResp.statusCode): \(body.prefix(200))"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw NSError(domain: "OpenRouter", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
        }

        for item in items {
            guard let dateStr = item["date"] as? String, dateStr.count >= 10 else { continue }
            let day = String(dateStr.prefix(10))

            let cost = item["usage"] as? Double ?? 0
            let model = item["model"] as? String ?? "unknown"
            let tokensIn = item["prompt_tokens"] as? Int ?? 0
            let tokensOut = item["completion_tokens"] as? Int ?? 0
            let reasoningTokens = item["reasoning_tokens"] as? Int ?? 0
            let requests = item["requests"] as? Int ?? 1

            if cost <= 0, tokensIn == 0, tokensOut == 0 { continue }

            var agg = dayMap[day] ?? DayAgg(date: day)
            agg.cost += cost
            agg.inputTokens += tokensIn
            agg.outputTokens += tokensOut
            agg.reasoningTokens += reasoningTokens
            agg.modelCost[model, default: 0] += cost
            agg.modelCount[model, default: 0] += 1
            agg.messages += requests

            let sid = "openrouter:\(model)-\(day)"
            if !agg.sessionIds.contains(sid) { agg.sessionIds.append(sid) }

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