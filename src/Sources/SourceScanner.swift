import Foundation

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
    var mgmtKey: String?
}

enum SourceKind: String, Codable {
    case opencodeDB
    case piSessions
    case omPiSessions
    case openClawSessions
    case hermesSessions
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

        let piSessions = home.appendingPathComponent(".pi/agent/sessions").path
        if FileManager.default.fileExists(atPath: piSessions), !existingPaths.contains(piSessions) {
            newlyFound.append(OpenCodeSource(path: piSessions, label: "Pi Agent", kind: .piSessions, enabled: true))
            existingPaths.insert(piSessions)
        }

        // Oh My Pi agent sessions (same JSONL format, stored in ~/.omp)
        let ompSessions = home.appendingPathComponent(".omp/agent/sessions").path
        if FileManager.default.fileExists(atPath: ompSessions), !existingPaths.contains(ompSessions) {
            newlyFound.append(OpenCodeSource(path: ompSessions, label: "Oh My Pi", kind: .omPiSessions, enabled: true))
            existingPaths.insert(ompSessions)
        }

        // Hermes sessions (SQLite state.db)
        let hermesDB = home.appendingPathComponent(".hermes/state.db").path
        if FileManager.default.fileExists(atPath: hermesDB), !existingPaths.contains(hermesDB) {
            newlyFound.append(OpenCodeSource(path: hermesDB, label: "Hermes", kind: .hermesSessions, enabled: true))
            existingPaths.insert(hermesDB)
        }

        // OpenClaw sessions (JSONL format, same as Pi)
        let openClawDir = home.appendingPathComponent(".openclaw/agents/main/sessions").path
        if FileManager.default.fileExists(atPath: openClawDir), !existingPaths.contains(openClawDir) {
            newlyFound.append(OpenCodeSource(path: openClawDir, label: "OpenClaw", kind: .openClawSessions, enabled: true))
            existingPaths.insert(openClawDir)
        }

        let goDB = home.appendingPathComponent(".local/share/opencode-go/opencode.db").path
        if FileManager.default.fileExists(atPath: goDB), !existingPaths.contains(goDB) {
            newlyFound.append(OpenCodeSource(path: goDB, label: "OpenCode Go", kind: .openCodeGo, enabled: true))
            existingPaths.insert(goDB)
        }

        let orPath = home.appendingPathComponent(".openrouter").path
        if FileManager.default.fileExists(atPath: orPath), !existingPaths.contains(orPath) {
            newlyFound.append(OpenCodeSource(path: orPath, label: "OpenRouter", kind: .openRouter, enabled: true))
            existingPaths.insert(orPath)
        }
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