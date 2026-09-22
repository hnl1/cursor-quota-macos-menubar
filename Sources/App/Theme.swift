import AppKit

enum Theme {
    static func paceColor(_ pace: UsagePace) -> NSColor {
        switch pace {
        case .onPace: .systemGreen
        case .behind: .systemOrange
        case .critical: .systemRed
        }
    }

    static func trackFill(appearance: NSAppearance) -> NSColor {
        let dark = isDark(appearance)
        return dark
            ? NSColor.white.withAlphaComponent(0.22)
            : NSColor.black.withAlphaComponent(0.12)
    }

    /// 暗色下面这两档都是 72% 白。浅色仍分开。
    static func secondaryText(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.72)
            : NSColor.black.withAlphaComponent(0.55)
    }

    static func tertiaryText(_ appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.72)
            : NSColor.black.withAlphaComponent(0.42)
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func currency(_ dollars: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: dollars)) ?? String(format: "$%.2f", dollars)
    }

    static func refreshText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return "更新于 \(formatter.string(from: date))"
    }

    static func refreshClock(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func resetText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMdjm")
        return "重置 \(formatter.string(from: date))"
    }

    static func footerReset(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(formatter.string(from: date))重置"
    }
}
