import SwiftUI

struct MenuRow: View {
    let title: String
    var systemImage: String? = nil
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let img = systemImage {
                    Image(systemName: img)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if let sc = shortcut {
                    Text(sc)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(hovering ? Color.white.opacity(0.85) : .secondary)
                }
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            if let t = trailing {
                Text(t)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BarRow: View {
    let rank: Int
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let value: String
    let fraction: Double
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .continuous)
                    .fill(color.opacity(0.16))
                    .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                Image(systemName: icon)
                    .font(.system(size: compact ? 10 : 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                HStack {
                    Text(title)
                        .font(.system(size: compact ? 11 : 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(value)
                        .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06)).frame(height: compact ? 3 : 5)
                        Capsule().fill(color)
                            .frame(width: max(4, geo.size.width * fraction), height: compact ? 3 : 5)
                    }
                }
                .frame(height: compact ? 3 : 5)
                Text(subtitle)
                    .font(.system(size: compact ? 9 : 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct CenteredMessage: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let s = subtitle {
                Text(s)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct DailySpendChart: View {
    let data: [DaySpend]
    @State private var selectedDate: Date?

    private var maxCost: Double {
        max(data.map(\.cost).max() ?? 1, 0.01)
    }

    private var selected: DaySpend? {
        guard let selectedDate else { return nil }
        let cal = Calendar.current
        return data.first { cal.isDate($0.day, inSameDayAs: selectedDate) }
    }

    private var labelStep: Int {
        let n = data.count
        if n <= 7 { return 1 }
        if n <= 14 { return 2 }
        return n / 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let barCount = max(data.count, 1)
                let totalSpacing = CGFloat(barCount - 1) * 2
                let barW = max(4, (geo.size.width - totalSpacing) / CGFloat(barCount))

                ZStack(alignment: .bottomLeading) {
                    ForEach(0..<4) { i in
                        let y = geo.size.height * CGFloat(i) / 3
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    }

                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(data) { d in
                            let fraction = d.cost / maxCost
                            let barH = max(CGFloat(fraction) * geo.size.height, fraction > 0 ? 2 : 0)
                            let isSelected = selected.map { Calendar.current.isDate(d.day, inSameDayAs: $0.day) } ?? false

                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: 0x4ECDC4), Color(hex: 0x2DD4BF)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .frame(width: barW, height: barH)
                                .opacity(selected == nil || isSelected ? 1 : 0.35)
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        if isSelected { selectedDate = nil }
                                        else { selectedDate = d.day }
                                    }
                                }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    if let sel = selected {
                        let idx = data.firstIndex { Calendar.current.isDate($0.day, inSameDayAs: sel.day) } ?? 0
                        let x = CGFloat(idx) * (barW + 2) + barW / 2
                        let selFrac = sel.cost / maxCost
                        let selBarH = max(CGFloat(selFrac) * geo.size.height, selFrac > 0 ? 2 : 0)
                        VStack(spacing: 1) {
                            Text(sel.day, format: .dateTime.weekday(.abbreviated).month().day())
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(Fmt.money(sel.cost))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x2DD4BF))
                        }
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08)))
                        .offset(x: max(0, min(x - 50, geo.size.width - 100)))
                        .offset(y: -selBarH - 40)
                    }
                }
            }
            .frame(height: 110)
            // Date labels
            HStack(spacing: 2) {
                ForEach(Array(data.enumerated()), id: \.element.id) { idx, d in
                    if idx % labelStep == 0 || idx == data.count - 1 {
                        let dayFmt: DateFormatter = {
                            let f = DateFormatter()
                            f.locale = Locale(identifier: "en_US_POSIX")
                            f.dateFormat = "EEE\nd"
                            return f
                        }()
                        Text(dayFmt.string(from: d.day))
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)
                            .minimumScaleFactor(0.5)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct HourlySpendChart: View {
    let data: [HourSpend]
    @State private var selectedHour: Int?

    private var maxCost: Double {
        max(data.map(\.cost).max() ?? 1, 0.01)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let barCount = max(data.count, 1)
                let totalSpacing = CGFloat(barCount - 1) * 1
                let barW = max(2, (geo.size.width - totalSpacing) / CGFloat(barCount))

                ZStack(alignment: .bottomLeading) {
                    ForEach(0..<4) { i in
                        let y = geo.size.height * CGFloat(i) / 3
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    }

                    HStack(alignment: .bottom, spacing: 1) {
                        ForEach(data) { h in
                            let fraction = h.cost / maxCost
                            let barH = max(CGFloat(fraction) * geo.size.height, fraction > 0 ? 2 : 0)
                            let isSelected = selectedHour == h.hour

                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: 0x4ECDC4), Color(hex: 0x2DD4BF)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .frame(width: barW, height: barH)
                                .opacity(selectedHour == nil || isSelected ? 1 : 0.35)
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        selectedHour = isSelected ? nil : h.hour
                                    }
                                }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    if let sel = selectedHour, let selData = data.first(where: { $0.hour == sel }) {
                        let x = CGFloat(sel) * (barW + 1) + barW / 2
                        VStack(spacing: 1) {
                            Text("\(String(format: "%02d", sel)):00")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(Fmt.money(selData.cost))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x2DD4BF))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.primary.opacity(0.08)))
                        .offset(x: max(0, min(x - 40, geo.size.width - 80)))
                        .offset(y: -selData.cost / maxCost * geo.size.height - 35)
                    }
                }
            }
            .frame(height: 100)
            // Hour labels
            HStack(spacing: 1) {
                let labels = [0, 6, 12, 18, 23]
                ForEach(labels, id: \.self) { h in
                    Text("\(h)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                    if h != labels.last {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct PieChart: View {
    let data: [(label: String, value: Int, color: Color)]
    @State private var selectedIndex: Int?
    @AppStorage("displaySize") private var displaySize = DisplaySize.regular.rawValue

    private let funColors: [Color] = [
        Color(hex: 0xFF6B6B), Color(hex: 0x4ECDC4), Color(hex: 0xFFE66D),
        Color(hex: 0xA78BFA), Color(hex: 0xFB923C), Color(hex: 0x34D399),
        Color(hex: 0xF472B6), Color(hex: 0x60A5FA), Color(hex: 0xFBBF24),
        Color(hex: 0x818CF8), Color(hex: 0x2DD4BF), Color(hex: 0xF87171),
    ]

    private func sliceColor(_ idx: Int) -> Color { funColors[idx % funColors.count] }

    private var ds: DisplaySize { DisplaySize(rawValue: displaySize) ?? .regular }
    private var donutSize: CGFloat { 160 * ds.fontScale }
    private var innerSize: CGFloat { 60 * ds.fontScale }
    private var total: Int { data.reduce(0) { $0 + $1.value } }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ForEach(Array(data.enumerated()), id: \.offset) { idx, item in
                    PieSlice(
                        startAngle: startAngle(for: idx),
                        endAngle: endAngle(for: idx),
                        color: sliceColor(idx),
                        isSelected: selectedIndex == idx
                    )
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedIndex = selectedIndex == idx ? nil : idx
                        }
                    }
                }
                Circle().fill(Color(NSColor.controlBackgroundColor)).frame(width: innerSize, height: innerSize)
                if let idx = selectedIndex {
                    let item = data[idx]
                    VStack(spacing: 0) {
                        Text("\(pct(item.value))%").font(.system(size: 20 * ds.fontScale, weight: .bold)).foregroundStyle(sliceColor(idx))
                        Text("\(Fmt.int(item.value))").font(.system(size: 12 * ds.fontScale, weight: .medium)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(Fmt.int(total))").font(.system(size: 20 * ds.fontScale, weight: .bold))
                }
            }
            .frame(width: donutSize, height: donutSize)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(data.prefix(8).enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 6) {
                        Circle().fill(sliceColor(idx)).frame(width: 8, height: 8)
                        Text(item.label).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        Spacer()
                        Text("\(Fmt.int(item.value))").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .opacity(selectedIndex == nil || selectedIndex == idx ? 1 : 0.4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { selectedIndex = selectedIndex == idx ? nil : idx }
                    }
                }
                if data.count > 8 {
                    Text("+ \(data.count - 8) more...").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func startAngle(for idx: Int) -> Angle {
        let sum = data[0..<idx].reduce(0) { $0 + $1.value }
        return .degrees(Double(sum) / Double(max(total, 1)) * 360 - 90)
    }

    private func endAngle(for idx: Int) -> Angle {
        let sum = data[0...idx].reduce(0) { $0 + $1.value }
        return .degrees(Double(sum) / Double(max(total, 1)) * 360 - 90)
    }

    private func pct(_ v: Int) -> String {
        String(format: "%.0f", Double(v) / Double(max(total, 1)) * 100)
    }
}

struct PieSlice: View {
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
    let isSelected: Bool

    var body: some View {
        GeometryReader { geo in
            let mid = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = min(geo.size.width, geo.size.height) / 2
            Path { p in
                p.move(to: mid)
                p.addArc(center: mid, radius: r,
                         startAngle: startAngle, endAngle: endAngle,
                         clockwise: false)
                p.closeSubpath()
            }
            .fill(color)
            .opacity(isSelected ? 1 : 0.75)
            .scaleEffect(isSelected ? 1.04 : 1)
            .animation(.easeOut(duration: 0.12), value: isSelected)
        }
    }
}