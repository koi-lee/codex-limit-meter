import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var tracker: UsageTracker

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: 0x1C1C1E))
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Codex Limit Meter")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    if let plan = tracker.usage.planType {
                        Text(plan.capitalized)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: 0xFFD60A))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(hex: 0xFFD60A).opacity(0.15))
                            )
                    }

                    Spacer()

                    // Refresh button
                    Button(action: { tracker.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("刷新数据")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 2)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                // Primary window (5-hour)
                UsageSection(
                    title: tracker.usage.primaryWindowLabel + "额度",
                    usedPercent: tracker.usage.primaryUsedPercent,
                    remainingPercent: tracker.usage.primaryRemainingPercent,
                    resetFormatted: tracker.usage.primaryResetFormatted,
                    hasData: tracker.usage.primary != nil,
                    isLoading: tracker.usage.dataSource == .loading
                )
                .padding(.horizontal, 16)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                // Secondary window (weekly)
                UsageSection(
                    title: tracker.usage.secondaryWindowLabel + "额度",
                    usedPercent: tracker.usage.secondaryUsedPercent,
                    remainingPercent: tracker.usage.secondaryRemainingPercent,
                    resetFormatted: tracker.usage.secondaryResetFormatted,
                    hasData: tracker.usage.secondary != nil,
                    isLoading: tracker.usage.dataSource == .loading
                )
                .padding(.horizontal, 16)

                Spacer()

                // Footer — merged into single clickable line
                Button(action: { tracker.refresh() }) {
                    HStack(spacing: 4) {
                        if tracker.usage.dataSource == .loading {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                                .modifier(PulseEffect())
                        } else {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                        }

                        Text(footerText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(statusColor.opacity(0.8))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 260, height: 172)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var statusColor: Color {
        switch tracker.usage.dataSource {
        case .loading:
            return Color(hex: 0x0A84FF)
        case .appServer:
            return Color(hex: 0x30D158)
        case .config:
            return Color(hex: 0xFF9F0A)
        case .error:
            return Color(hex: 0xFF453A)
        }
    }

    private var footerText: String {
        switch tracker.usage.dataSource {
        case .loading:
            return "正在更新…"
        case .appServer:
            return "已同步 · \(timeString(from: tracker.usage.lastUpdated))"
        case .config:
            return "手动配置 · \(timeString(from: tracker.usage.lastUpdated))"
        case .error:
            return "更新失败 · 点击重试"
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct UsageSection: View {
    let title: String
    let usedPercent: Double      // 0.0 - 1.0
    let remainingPercent: Double // 0.0 - 1.0
    let resetFormatted: String
    let hasData: Bool
    let isLoading: Bool

    init(title: String, usedPercent: Double, remainingPercent: Double, resetFormatted: String, hasData: Bool, isLoading: Bool = false) {
        self.title = title
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetFormatted = resetFormatted
        self.hasData = hasData
        self.isLoading = isLoading
    }

    // Color based on REMAINING percentage
    private var barColor: Color {
        if remainingPercent < 0.20 {
            return Color(hex: 0xFF453A)   // red — critical
        } else if remainingPercent < 0.40 {
            return Color(hex: 0xFF9F0A)   // orange — warning
        } else {
            return Color(hex: 0x30D158)   // green — healthy
        }
    }

    @State private var shimmerOffset: CGFloat = -228

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Row 1: title (left) + remaining % (right, prominent)
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.gray.opacity(0.85))

                Spacer()

                if hasData {
                    Text("剩余 \(Int(remainingPercent * 100))%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(barColor)
                } else if isLoading {
                    Text("加载中...")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: 0x0A84FF).opacity(0.8))
                } else {
                    Text("--")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.gray.opacity(0.4))
                }
            }

            // Row 2: progress bar — shows REMAINING (green fill = available)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)

                if hasData {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(0, CGFloat(remainingPercent) * 228), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: remainingPercent)
                } else if isLoading {
                    // Shimmer effect for loading
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0x0A84FF).opacity(0.1),
                                    Color(hex: 0x0A84FF).opacity(0.5),
                                    Color(hex: 0x0A84FF).opacity(0.1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 80, height: 6)
                        .offset(x: shimmerOffset)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                shimmerOffset = 228
                            }
                        }
                }
            }

            // Row 3: used % (left) + reset time (right)
            HStack {
                if hasData {
                    Text("已用 \(Int(usedPercent * 100))%")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color.gray.opacity(0.5))
                }

                Spacer()

                if hasData && !resetFormatted.isEmpty {
                    Text(resetFormatted)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color.gray.opacity(0.5))
                }
            }
        }
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// Pulsing animation for loading indicator dot
struct PulseEffect: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .scaleEffect(isPulsing ? 0.8 : 1.2)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}
