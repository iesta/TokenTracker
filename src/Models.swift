import Foundation

struct HourlyAgg: Codable {
    var cost: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var messages: Int = 0
}

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
    var hours: [Int: HourlyAgg] = [:]
}

struct Aggregate: Codable {
    var dbSignature: String
    var days: [DayAgg]
    var generatedAt: Date
    var sourceSummaries: [String: SourceSummary] = [:]
    var perSourceDays: [String: [DayAgg]] = [:]
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

struct HourSpend: Identifiable {
    var id: String { "\(date)-\(hour)" }
    let date: String
    let hour: Int
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
    var hourlySpend: [HourSpend] = []
    var totalTokens: Int { inputTokens + outputTokens + reasoningTokens + cacheRead + cacheWrite }
}

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

enum DisplaySize: String, CaseIterable, Identifiable {
    case regular = "Regular"
    case large = "Large"
    var id: String { rawValue }
    var panelWidth: CGFloat {
        switch self {
        case .regular: return 500
        case .large: return 640
        }
    }
    var panelHeight: CGFloat {
        switch self {
        case .regular: return 672
        case .large: return 860
        }
    }
    var fontScale: CGFloat {
        switch self {
        case .regular: return 1.0
        case .large: return 1.2
        }
    }
}