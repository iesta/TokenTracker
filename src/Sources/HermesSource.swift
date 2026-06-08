import Foundation

extension StatsEngine {
    nonisolated static func ingestHermesSessions(dbPath: String, dayMap: inout [String: DayAgg]) throws {
        // 1. All sessions with cost/token/model/project data
        let sessionRows = try queryDB(dbPath, """
            SELECT
                id as session_id,
                model,
                cwd,
                started_at,
                input_tokens,
                output_tokens,
                cache_read_tokens,
                cache_write_tokens,
                reasoning_tokens,
                COALESCE(actual_cost_usd, estimated_cost_usd, 0) as cost,
                message_count,
                tool_call_count
            FROM sessions
            WHERE archived = 0
        """)

        var sessionMap: [String: [String: Any]] = [:]
        for row in sessionRows {
            if let sid = row["session_id"] as? String {
                sessionMap[sid] = row
            }
        }

        // 2. Messages per day per session
        let msgDayRows = try queryDB(dbPath, """
            SELECT
                m.session_id,
                date(m.timestamp, 'unixepoch') as day,
                COUNT(*) as msg_count
            FROM messages m
            JOIN sessions s ON m.session_id = s.id
            WHERE s.archived = 0
            GROUP BY m.session_id, day
            ORDER BY day
        """)

        // 3. Total messages per session
        let totalMsgRows = try queryDB(dbPath, """
            SELECT session_id, COUNT(*) as total
            FROM messages
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
            agg.inputTokens += Int(Double(sData["input_tokens"] as? Int ?? 0) * fraction)
            agg.outputTokens += Int(Double(sData["output_tokens"] as? Int ?? 0) * fraction)
            agg.reasoningTokens += Int(Double(sData["reasoning_tokens"] as? Int ?? 0) * fraction)
            agg.cacheRead += Int(Double(sData["cache_read_tokens"] as? Int ?? 0) * fraction)
            agg.cacheWrite += Int(Double(sData["cache_write_tokens"] as? Int ?? 0) * fraction)

            if !agg.sessionIds.contains(sid) { agg.sessionIds.append(sid) }
            agg.messages += dayMsgCount

            let modelId = (sData["model"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            if !modelId.isEmpty {
                agg.modelCost[modelId, default: 0] += (sData["cost"] as? Double ?? 0) * fraction
                agg.modelCount[modelId, default: 0] += 1
            }

            let projName: String
            if let cwd = sData["cwd"] as? String, !cwd.isEmpty {
                projName = String(cwd.split(separator: "/").last ?? "")
            } else {
                projName = "hermes"
            }
            agg.projectCost[projName, default: 0] += (sData["cost"] as? Double ?? 0) * fraction
            if !(agg.projectSessions[projName]?.contains(sid) ?? false) {
                agg.projectSessions[projName, default: []].append(sid)
            }
            agg.projectName[projName] = projName

            dayMap[day] = agg
        }

        // 5. Hourly breakdown from messages
        let hourRows = try queryDB(dbPath, """
            SELECT
                m.session_id,
                date(m.timestamp, 'unixepoch') as day,
                cast(strftime('%H', m.timestamp, 'unixepoch') as integer) as hour,
                COUNT(*) as msg_count
            FROM messages m
            JOIN sessions s ON m.session_id = s.id
            WHERE s.archived = 0
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
            var agg = dayMap[day] ?? DayAgg(date: day)
            agg.hours[hour, default: HourlyAgg()].cost += (sData["cost"] as? Double ?? 0) * fraction
            agg.hours[hour]!.inputTokens += Int(Double(sData["input_tokens"] as? Int ?? 0) * fraction)
            agg.hours[hour]!.outputTokens += Int(Double(sData["output_tokens"] as? Int ?? 0) * fraction)
            agg.hours[hour]!.messages += dayMsgCount
            dayMap[day] = agg
        }
    }
}