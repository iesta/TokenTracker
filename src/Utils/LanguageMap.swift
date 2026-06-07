import SwiftUI

struct LangInfo {
    let name: String
    let color: Color
    let symbol: String
}

struct LangStat: Identifiable {
    var id: String { name }
    let name: String
    let count: Int
    let color: Color
    let symbol: String
}

let languageMap: [String: LangInfo] = [
    "swift":   LangInfo(name: "Swift",       color: .orange,    symbol: "swift"),
    "py":      LangInfo(name: "Python",      color: .blue,      symbol: "server.rack"),
    "js":      LangInfo(name: "JavaScript",  color: .yellow,    symbol: "chevron.left.forwardslash.chevron.right"),
    "ts":      LangInfo(name: "TypeScript",  color: .blue,      symbol: "chevron.left.forwardslash.chevron.right"),
    "jsx":     LangInfo(name: "React/JSX",   color: Color(hex: 0x61DAFB), symbol: "atom"),
    "tsx":     LangInfo(name: "React/TSX",   color: Color(hex: 0x3178C6), symbol: "atom"),
    "rs":      LangInfo(name: "Rust",        color: .brown,     symbol: "gear"),
    "go":      LangInfo(name: "Go",          color: Color(hex: 0x00ADD8), symbol: "arrow.up.arrow.down"),
    "rb":      LangInfo(name: "Ruby",        color: .red,       symbol: "gem"),
    "java":    LangInfo(name: "Java",        color: .brown,     symbol: "cup.and.saucer"),
    "kt":      LangInfo(name: "Kotlin",      color: Color(hex: 0x7F52FF), symbol: "suit.heart"),
    "svelte":  LangInfo(name: "Svelte",      color: .orange,    symbol: "sparkles"),
    "vue":     LangInfo(name: "Vue",         color: Color(hex: 0x4FC08D), symbol: "sparkles"),
    "c":       LangInfo(name: "C",           color: Color(hex: 0x555555), symbol: "cpu"),
    "cpp":     LangInfo(name: "C++",         color: .purple,    symbol: "cpu"),
    "h":       LangInfo(name: "C/C++ Header", color: .purple,   symbol: "doc.text"),
    "cs":      LangInfo(name: "C#",          color: .green,     symbol: "number"),
    "zig":     LangInfo(name: "Zig",         color: Color(hex: 0xF7A41D), symbol: "bolt"),
    "lua":     LangInfo(name: "Lua",         color: .blue,      symbol: "moon"),
    "sql":     LangInfo(name: "SQL",         color: Color(hex: 0xCC2927), symbol: "cylinder"),
    "md":      LangInfo(name: "Markdown",    color: .secondary, symbol: "doc.text"),
    "json":    LangInfo(name: "JSON",        color: .secondary, symbol: "curlybraces"),
    "yaml":    LangInfo(name: "YAML",        color: .secondary, symbol: "doc.text"),
    "toml":    LangInfo(name: "TOML",        color: .secondary, symbol: "doc.text"),
    "html":    LangInfo(name: "HTML",        color: .orange,    symbol: "globe"),
    "css":     LangInfo(name: "CSS",         color: .purple,    symbol: "paintbrush"),
    "scss":    LangInfo(name: "SCSS",        color: .pink,      symbol: "paintbrush"),
    "sh":      LangInfo(name: "Shell",       color: .green,     symbol: "terminal"),
    "bash":    LangInfo(name: "Bash",        color: .green,     symbol: "terminal"),
    "fish":    LangInfo(name: "Fish",        color: .green,     symbol: "terminal"),
    "zsh":     LangInfo(name: "Zsh",         color: .green,     symbol: "terminal"),
    "dockerfile": LangInfo(name: "Docker",   color: Color(hex: 0x2496ED), symbol: "shippingbox"),
    "plist":   LangInfo(name: "Plist",       color: .secondary, symbol: "list.bullet"),
    "entitlements": LangInfo(name: "Entitlements", color: .secondary, symbol: "lock.shield"),
    "pbxproj": LangInfo(name: "Xcode Project", color: .secondary, symbol: "hammer"),
    "xcworkspacedata": LangInfo(name: "Xcode Workspace", color: .secondary, symbol: "hammer"),
    "gradle":  LangInfo(name: "Gradle",      color: Color(hex: 0x02303A), symbol: "building.2"),
]