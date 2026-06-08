import Foundation

extension StatsEngine {
    nonisolated static func ingestClineSessions(dbPath: String, dayMap: inout [String: DayAgg]) throws {
        let sessionRows = try queryDB(dbPath, """
            SELECT
                session_id,
                model,
                provider,
                cwd,
                started_at,
                json_extract(metadata_json, '$.usage.inputTokens') as input_tokens,
                json_extract(metadata_json, '$.usage.outputTokens') as output_tokens,
                json_extract(metadata_json, '$.usage.cacheReadTokens') as cache_read,
                json_extract(metadata_json, '$.usage.cacheWriteTokens') as cache_write,
                json_extract(metadata_json, '$.totalCost') as cost,
                json_extract(metadata_json, '$.usage.totalCost') as usage_cost
            FROM sessions
            WHERE is_subagent = 0
        """)

        for row in sessionRows {
            guard let sid = row["session_id"] as? String,
                  let ts = row["started_at"] as? String, ts.count >= 10 else { continue }

            let day = String(ts.prefix(10))
            let cost = (row["cost"] as? Double) ?? (row["usage_cost"] as? Double) ?? 0
            let tokensIn = row["input_tokens"] as? Int ?? 0
            let tokensOut = row["output_tokens"] as? Int ?? 0
            let cacheRead = row["cache_read"] as? Int ?? 0
            let cacheWrite = row["cache_write"] as? Int ?? 0
            let model = row["model"] as? String ?? "unknown"
            let proj: String
            if let cwd = row["cwd"] as? String, !cwd.isEmpty {
                proj = String(cwd.split(separator: "/").last ?? "")
            } else {
                proj = "cline"
            }

            if cost <= 0, tokensIn == 0, tokensOut == 0 { continue }

            var agg = dayMap[day] ?? DayAgg(date: day)
            agg.cost += cost
            agg.inputTokens += tokensIn
            agg.outputTokens += tokensOut
            agg.cacheRead += cacheRead
            agg.cacheWrite += cacheWrite
            if !agg.sessionIds.contains(sid) { agg.sessionIds.append(sid) }

            agg.modelCost[model, default: 0] += cost
            agg.modelCount[model, default: 0] += 1
            agg.messages += 1

            agg.projectCost[proj, default: 0] += cost
            if !(agg.projectSessions[proj]?.contains(sid) ?? false) {
                agg.projectSessions[proj, default: []].append(sid)
            }
            agg.projectName[proj] = proj

            // Extract hour from ISO timestamp
            if ts.count >= 16 {
                let hourStr = String(ts[ts.index(ts.startIndex, offsetBy: 11)..<ts.index(ts.startIndex, offsetBy: 13)])
                if let hour = Int(hourStr) {
                    agg.hours[hour, default: HourlyAgg()].cost += cost
                    agg.hours[hour]!.inputTokens += tokensIn
                    agg.hours[hour]!.outputTokens += tokensOut
                    agg.hours[hour]!.messages += 1
                }
            }

            dayMap[day] = agg
        }
    }
}