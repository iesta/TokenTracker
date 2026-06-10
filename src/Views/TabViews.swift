import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case tech = "Tech"
    case projects = "Projects"
    case models = "Models"
    case usage = "Usage"
    case origins = "Origins"
    var id: String { rawValue }
}

struct OverviewTab: View {
    let s: StatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCard(icon: "dollarsign.circle.fill", iconColor: .green, title: "Total Cost", value: Fmt.money(s.totalCost))
                StatCard(icon: "clock.fill", iconColor: .blue, title: "Today", value: Fmt.money(s.todayCost))
                StatCard(icon: "number.fill", iconColor: .orange, title: "Sessions", value: Fmt.int(s.sessionCount))
                StatCard(icon: "message.fill", iconColor: .purple, title: "Messages", value: Fmt.int(s.messages))
                StatCard(icon: "calendar.day.fill", iconColor: .teal, title: "Days Active", value: Fmt.int(s.daysActive))
                StatCard(icon: "chart.bar.fill", iconColor: .pink, title: "Avg / Day", value: Fmt.money(s.avgCostPerDay))
            }

            if !s.hourlySpend.isEmpty {
                HourlySpendChart(data: s.hourlySpend)
                    .frame(height: 130)
            } else {
                DailySpendChart(data: s.dailySpend)
                    .frame(height: 130)
            }

            if let top = s.models.first {
                SectionHeader(title: "Top Model", trailing: "\(Fmt.int(top.count)) calls")
                BarRow(rank: 1, icon: "cpu", color: Color(hex: 0x4F46E5),
                       title: top.displayName, subtitle: "", value: Fmt.money(top.cost),
                       fraction: 1)
            }
        }
    }
}

struct TechTab: View {
    let s: StatsSummary
    var body: some View {
        if s.languages.isEmpty {
            CenteredMessage(icon: "chevron.left.forwardslash.chevron.right",
                            title: "No tech usage yet",
                            subtitle: "Languages appear once you edit files via opencode.")
        } else {
            let maxCount = max(s.languages.map { $0.count }.max() ?? 1, 1)
            let totalCount = max(s.languages.reduce(0) { $0 + $1.count }, 1)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Tech Used", trailing: "\(Fmt.int(totalCount)) calls")
                PieChart(data: s.languages.map { ($0.name, $0.count, $0.color) })
                    .frame(height: 200)
                VStack(spacing: 8) {
                    ForEach(Array(s.languages.enumerated()), id: \.element.id) { idx, l in
                        BarRow(rank: idx + 1, icon: l.symbol, color: l.color, title: l.name,
                               subtitle: "\(pct(l.count, totalCount))",
                               value: "\(Fmt.int(l.count)) calls",
                               fraction: Double(l.count) / Double(maxCount),
                               compact: true)
                    }
                }
            }
        }
    }
    private func pct(_ a: Int, _ b: Int) -> String {
        String(format: "%.0f%%", Double(a) / Double(b) * 100)
    }
}

struct ProjectsTab: View {
    let s: StatsSummary
    @State private var flashId: String?

    var body: some View {
        if s.projects.isEmpty {
            CenteredMessage(icon: "folder", title: "No projects")
        } else {
            let maxCost = max(s.projects.map { $0.cost }.max() ?? 1, 0.0001)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Projects", trailing: "by cost")
                VStack(spacing: 12) {
                    ForEach(Array(s.projects.prefix(15).enumerated()), id: \.element.id) { idx, p in
                        BarRow(rank: idx + 1, icon: "folder.fill",
                               color: projectColor(idx), title: shortName(p.name),
                               subtitle: "\(p.sessions) session\(p.sessions == 1 ? "" : "s")",
                               value: Fmt.money(p.cost),
                               fraction: p.cost / maxCost)
                        .opacity(flashId == p.name ? 0.2 : 1)
                        .animation(.easeInOut(duration: 0.08), value: flashId)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(p.name, forType: .string)
                            flashProject(p.name)
                        }
                    }
                }
            }
        }
    }

private func shortName(_ path: String) -> String {
        if path == "/" || path == "global" { return "Global / Other" }
        if path.contains("/") {
            let parts = path.split(separator: "/").filter { !$0.isEmpty }
            return parts.last.map(String.init) ?? path
        }
        return path.isEmpty ? "Unnamed" : path
    }

    private func flashProject(_ id: String) {
        flashId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { flashId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { flashId = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { flashId = nil }
            }
        }
    }

    private func projectColor(_ i: Int) -> Color {
        let palette: [Color] = [
            Color(hex: 0xFF6B6B), Color(hex: 0x4ECDC4), Color(hex: 0xFFE66D),
            Color(hex: 0xA78BFA), Color(hex: 0xFB923C), Color(hex: 0x34D399),
            Color(hex: 0xF472B6), Color(hex: 0x60A5FA), Color(hex: 0xFBBF24),
            Color(hex: 0x818CF8), Color(hex: 0x2DD4BF), Color(hex: 0xF87171),
        ]
        return palette[i % palette.count]
    }
}

struct ModelsTab: View {
    let s: StatsSummary
    @State private var flashId: String?

    var body: some View {
        if s.models.isEmpty {
            CenteredMessage(icon: "cpu", title: "No model usage")
        } else {
            let maxCost = max(s.models.map { $0.cost }.max() ?? 1, 0.0001)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Models", trailing: "by cost")
                PieChart(data: s.models.map { ($0.displayName, $0.count, modelColor($0.name)) })
                    .frame(height: 200)
                VStack(spacing: 8) {
                    ForEach(Array(s.models.enumerated()), id: \.element.id) { idx, m in
                        BarRow(rank: idx + 1, icon: "cpu", color: modelColor(m.name),
                               title: m.displayName,
                               subtitle: "\(Fmt.int(m.count)) calls",
                               value: Fmt.money(m.cost),
                               fraction: m.cost / maxCost,
                               compact: true)
                        .opacity(flashId == m.name ? 0.2 : 1)
                        .animation(.easeInOut(duration: 0.08), value: flashId)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(m.name, forType: .string)
                            flashModel(m.name)
                        }
                    }
                }
            }
        }
    }

    private func flashModel(_ id: String) {
        flashId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { flashId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { flashId = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { flashId = nil }
            }
        }
    }

    private func modelColor(_ id: String) -> Color {
        let lower = id.lowercased()
        if lower.contains("opus") { return Color(hex: 0xD97757) }
        if lower.contains("sonnet") { return Color(hex: 0xCC8B5C) }
        if lower.contains("haiku") { return Color(hex: 0xE0A971) }
        if lower.contains("gpt") { return Color(hex: 0x10A37F) }
        if lower.contains("gemini") { return Color(hex: 0x4285F4) }
        if lower.contains("deepseek") { return Color(hex: 0x4F46E5) }
        return Color(hex: 0x8E8E93)
    }
}

struct UsageTab: View {
    let s: StatsSummary
    var body: some View {
        if s.totalTokens == 0 {
            CenteredMessage(icon: "chart.pie", title: "No token usage")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Tokens", trailing: Fmt.tokens(s.totalTokens))
                VStack(spacing: 12) {
                    tokenRow("Input", s.inputTokens, .blue)
                    tokenRow("Output", s.outputTokens, .green)
                    tokenRow("Reasoning", s.reasoningTokens, .purple)
                    tokenRow("Cache Read", s.cacheRead, .orange)
                    tokenRow("Cache Write", s.cacheWrite, .indigo)
                }
            }
        }
    }

    private func tokenRow(_ name: String, _ value: Int, _ color: Color) -> some View {
        let total = max(s.totalTokens, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name).font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(Fmt.tokens(value))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06)).frame(height: 5)
                    Capsule().fill(color)
                        .frame(width: max(4, geo.size.width * Double(value) / Double(total)), height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

struct OriginsTab: View {
    let origins: [SourceSummary]

    var body: some View {
        if origins.isEmpty || origins.count == 1 {
            CenteredMessage(icon: "square.grid.3x1.filled.below.line.rectangle", title: "Single source",
                            subtitle: "Add another data source to compare origins.")
        } else {
            let maxCost = max(origins.map { $0.totalCost }.max() ?? 1, 0.0001)
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Origins", trailing: "\(origins.count) sources")
                ForEach(origins) { src in
                    VStack(alignment: .leading, spacing: 6) {
                        BarRow(rank: 0, icon: src.kind == "piSessions" ? "brain" :
                                      src.kind == "openRouter" ? "network" :
                                      src.kind == "openCodeGo" ? "arrow.triangle.swap" : "externaldrive",
                               color: originColor(src.label),
                               title: src.label,
                               subtitle: "\(src.dayCount) day\(src.dayCount == 1 ? "" : "s") · \(Fmt.int(src.sessionCount)) session\(src.sessionCount == 1 ? "" : "s") · \(Fmt.int(src.messageCount)) msg\(src.messageCount == 1 ? "" : "s")",
                               value: "\(src.totalCost > 0 ? Fmt.money(src.totalCost) : "–") · \(Fmt.tokens(src.totalTokens))",
                               fraction: src.totalCost > 0 ? src.totalCost / maxCost : 0)
                    }
                }
            }
        }
    }

    private func originColor(_ label: String) -> Color {
        let palette: [Color] = [
            Color(hex: 0xFF6B6B), Color(hex: 0x4ECDC4), Color(hex: 0xFFE66D),
            Color(hex: 0xA78BFA), Color(hex: 0xFB923C), Color(hex: 0x34D399),
            Color(hex: 0xF472B6), Color(hex: 0x60A5FA), Color(hex: 0xFBBF24),
            Color(hex: 0x818CF8), Color(hex: 0x2DD4BF), Color(hex: 0xF87171),
        ]
        let hash = abs(label.hashValue)
        return palette[hash % palette.count]
    }
}