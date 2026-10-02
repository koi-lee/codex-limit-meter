import Foundation

enum PetCharacter: String, CaseIterable {
    case reader, archivist
    static let preferenceKey = "pet.character.v1"
    static func selected(in preferences: UserDefaults) -> PetCharacter {
        PetCharacter(rawValue: preferences.string(forKey: preferenceKey) ?? "") ?? .reader
    }
    var assetDirectory: String { self == .reader ? "Reader" : "Archivist" }
    func title(chinese: Bool) -> String {
        if chinese { return self == .reader ? "月夜 · 女生" : "星辰 · 男生" }
        return self == .reader ? "Moon · Female" : "Star · Male"
    }
}

/// Mirrors the existing menu bar choice: weekly first, then the short window.
struct PetState: Equatable, Codable {
    let remaining: Int?
    let loading: Bool
    let label: String
    let color: String
    let resetsAt: Int64?
    var isDemo = false
    var lamps: Int { remaining.map { $0 == 0 ? 0 : ($0 * 3 + 99) / 100 } ?? 0 }

    init(_ usage: UsageData, chinese: Bool = true) {
        let state = QuotaIconState(usage)
        loading = state == .loading
        if case .value(let value) = state {
            remaining = value
            let window = usage.secondary ?? usage.primary
            let name = (window?.windowDurationMins ?? 0) >= 1440
                ? (chinese ? "周额度" : "Weekly") : (chinese ? "短期额度" : "Short-term")
            resetsAt = (window?.resetsAt ?? 0) > 0 ? window?.resetsAt : nil
            label = "\(name) \(value)%"
            switch quotaLevel(remaining: value) {
            case .healthy: color = "#30D158"
            case .warning: color = "#FF9F0A"
            case .critical: color = "#FF453A"
            }
        } else {
            remaining = nil
            resetsAt = nil
            label = loading ? (chinese ? "读取中…" : "Loading…") : (chinese ? "额度未知 ?" : "Quota unknown ?")
            color = "#A0A0A0"
        }
    }
}

/// Shared by both characters; invalid or missing preferences use the daily size.
enum PetDisplaySize: String, CaseIterable {
    case small, medium, large
    static let preferenceKey = "pet.displaySize.v1"
    var scale: Double { self == .small ? 0.75 : self == .medium ? 0.85 : 1 }
    static func selected(in preferences: UserDefaults) -> Self {
        Self(rawValue: preferences.string(forKey: preferenceKey) ?? "") ?? .medium
    }
    func title(chinese: Bool) -> String {
        chinese ? (self == .small ? "小" : self == .medium ? "中（推荐）" : "大")
            : (self == .small ? "Small" : self == .medium ? "Medium (Recommended)" : "Large")
    }
}

extension PetDisplaySize {
    var detailWidth: Double { self == .small ? 260 : self == .medium ? 286 : 310 }
    var detailMaxHeight: Double { self == .small ? 330 : self == .medium ? 366 : 410 }
    func detailHeight(page: String, count: Int) -> Double {
        if page == "changes" {
            return min(detailMaxHeight, count == 0 ? 210 : 170 + Double(max(1, count)) * 28)
        }
        return count == 0 ? (self == .small ? 286 : self == .medium ? 278 : 270) : detailMaxHeight
    }
}
