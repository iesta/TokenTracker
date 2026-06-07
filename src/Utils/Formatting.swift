import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Fmt {
    static func money(_ v: Double, rate: Double? = nil, code: String? = nil) -> String {
        let r = rate ?? SettingsStore.currencyRate
        let c = code ?? SettingsStore.currencyCode
        let converted = v * r
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = c
        if let formatted = f.string(from: NSNumber(value: converted)) {
            return formatted
        }
        if let sym = defaultCurrencies.first(where: { $0.code == c })?.symbol {
            return "\(sym)\(String(format: "%.2f", converted))"
        }
        return String(format: "$%.2f", converted)
    }
    static func moneyShort(_ v: Double) -> String {
        let converted = v * SettingsStore.currencyRate
        let sym = SettingsStore.currencySymbol
        if converted >= 1000 { return "\(sym)\(String(format: "%.1fk", converted / 1000))" }
        return "\(sym)\(String(format: "%.0f", converted))"
    }
    static func int(_ v: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    static func tokens(_ v: Int) -> String {
        let d = Double(v)
        if d >= 1_000_000_000 { return String(format: "%.1fB", d / 1e9) }
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1e6) }
        if d >= 1_000 { return String(format: "%.1fK", d / 1e3) }
        return "\(v)"
    }
}

enum TTIcon {
    static func menuBarImage(size: CGFloat = 14) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)
            let pad = rect.width * 0.15
            let barH = rect.height * 0.18
            let barY = rect.height - barH - pad
            ctx.fill(CGRect(x: pad, y: barY, width: rect.width - 2 * pad, height: barH))
            let stemW = rect.width * 0.22
            let stemX = (rect.width - stemW) / 2
            ctx.fill(CGRect(x: stemX, y: pad, width: stemW, height: rect.height - pad - barH - pad))
            return true
        }
        img.isTemplate = true
        return img
    }
}