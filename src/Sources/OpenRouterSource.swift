import Foundation

extension StatsEngine {
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

        if let daily = d["usage_daily"] as? Double, daily > 0 {
            agg.cost += daily
        }
        if let weekly = d["usage_weekly"] as? Double, weekly > 0 {
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
}