import Foundation

extension StatsEngine {
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
            var currentModel: String?
            var msgCount = 0
            var fileExts: [String] = []
            var perModelCost: [String: Double] = [:]
            var perModelInput: [String: Int] = [:]
            var perModelOutput: [String: Int] = [:]
            var perModelCacheRead: [String: Int] = [:]
            var perModelCacheWrite: [String: Int] = [:]
            var perModelTokens: [String: Int] = [:]
            var hourlyMessages: [Int: Int] = [:]

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
                        currentModel = model
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
                    if let ts = data["timestamp"] as? String, ts.count >= 13 {
                        let hourStr = String(ts[ts.index(ts.startIndex, offsetBy: 11)..<ts.index(ts.startIndex, offsetBy: 13)])
                        let hour = Int(hourStr) ?? -1
                        if hour >= 0 {
                            hourlyMessages[hour, default: 0] += 1
                        }
                    }
                    if let msg = data["message"] as? [String: Any],
                       let usage = msg["usage"] as? [String: Any] {
                        let model = currentModel ?? "unknown"
                        if let tc = usage["totalTokens"] as? Int {
                            perModelTokens[model, default: 0] += tc
                        }
                        if let inp = usage["input"] as? Int {
                            perModelInput[model, default: 0] += inp
                        }
                        if let out = usage["output"] as? Int {
                            perModelOutput[model, default: 0] += out
                        }
                        if let cr = usage["cacheRead"] as? Int {
                            perModelCacheRead[model, default: 0] += cr
                        }
                        if let cw = usage["cacheWrite"] as? Int {
                            perModelCacheWrite[model, default: 0] += cw
                        }
                        if let costObj = usage["cost"] as? [String: Any],
                           let totalCost = costObj["total"] as? Double {
                            perModelCost[model, default: 0] += totalCost
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
            for (m, cost) in perModelCost {
                agg.cost += cost
                agg.modelCost[m, default: 0] += cost
                agg.inputTokens += perModelInput[m] ?? 0
                agg.outputTokens += perModelOutput[m] ?? 0
                agg.cacheRead += perModelCacheRead[m] ?? 0
                agg.cacheWrite += perModelCacheWrite[m] ?? 0
            }
            if let proj = sessionProject {
                let totalCost = perModelCost.values.reduce(0, +)
                agg.projectCost[proj, default: 0] += totalCost
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
            // Attribute hourly costs proportionally by message count
            let totalHourMsgs = hourlyMessages.values.reduce(0, +)
            if totalHourMsgs > 0 {
                let totalCost = perModelCost.values.reduce(0, +)
                for (hour, count) in hourlyMessages {
                    let fraction = Double(count) / Double(totalHourMsgs)
                    let ha = HourlyAgg(
                        cost: totalCost * fraction,
                        inputTokens: 0,
                        outputTokens: 0,
                        messages: count
                    )
                    agg.hours[hour] = ha
                }
            }
            dayMap[day] = agg
        }
    }
}