import Foundation

extension StatsEngine {
    nonisolated static func ingestOpenCodeDB(dbPath: String, dayMap: inout [String: DayAgg]) throws {
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

        let msgDayRows = try queryDB(dbPath, """
            SELECT
                m.session_id,
                date(m.time_created / 1000, 'unixepoch') as day,
                COUNT(*) as msg_count
            FROM message m
            GROUP BY m.session_id, day
            ORDER BY day
        """)

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
            if !agg.sessionIds.contains(sid) { agg.sessionIds.append(sid) }
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

        for (sid, sData) in sessionMap {
            let totalMsgs = totalMsgCounts[sid] ?? 0
            if totalMsgs > 0 { continue }
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

        // 7. Hourly breakdown from messages
        let hourRows = try queryDB(dbPath, """
            SELECT
                m.session_id,
                date(m.time_created / 1000, 'unixepoch') as day,
                cast(strftime('%H', m.time_created / 1000, 'unixepoch') as integer) as hour,
                COUNT(*) as msg_count
            FROM message m
            GROUP BY m.session_id, day, hour
            ORDER BY day, hour
        """)

        for row in hourRows {
            guard let sid = row["session_id"] as? String,
                  let day = row["day"] as? String,
                  let hour = row["hour"] as? Int,
                  let dayMsgCount = row["msg_count"] as? Int,
                  let totalMsgs = totalMsgCounts[sid], totalMsgs > 0,
                  let sData = sessionMap[sid] else { continue }

            let fraction = Double(dayMsgCount) / Double(totalMsgs)
            var ha = HourlyAgg()
            ha.cost += (sData["cost"] as? Double ?? 0) * fraction
            ha.inputTokens += Int(Double(sData["tokens_input"] as? Int ?? 0) * fraction)
            ha.outputTokens += Int(Double(sData["tokens_output"] as? Int ?? 0) * fraction)
            ha.messages += dayMsgCount

            var agg = dayMap[day] ?? DayAgg(date: day)
            agg.hours[hour, default: HourlyAgg()].cost += ha.cost
            agg.hours[hour]!.inputTokens += ha.inputTokens
            agg.hours[hour]!.outputTokens += ha.outputTokens
            agg.hours[hour]!.messages += ha.messages
            dayMap[day] = agg
        }

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
}