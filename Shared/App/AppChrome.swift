import SwiftUI

enum AppTheme {
    static let backgroundTop = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let backgroundBottom = Color(red: 0.015, green: 0.017, blue: 0.022)
    static let panel = Color.white.opacity(0.075)
    static let panelStrong = Color.white.opacity(0.12)
    static let pill = Color.white.opacity(0.11)
    static let pillActive = Color.white.opacity(0.88)
    static let buttonSecondary = Color(red: 0.22, green: 0.23, blue: 0.25)
    static let buttonSecondaryActive = Color.white.opacity(0.9)
    static let hairline = Color.white.opacity(0.16)
    static let hairlineStrong = Color.white.opacity(0.28)
    static let mutedText = Color.white.opacity(0.68)
    static let accent = Color(red: 0.02, green: 0.45, blue: 1.0)

    static var pagePadding: CGFloat {
        #if os(macOS)
        28
        #else
        72
        #endif
    }

    static var pageBodyTrailingReserve: CGFloat {
        pagePadding
    }

    static func pageBodyWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth - pageBodyTrailingReserve)
    }

    static var gridSpacing: CGFloat {
        #if os(macOS)
        16
        #else
        42
        #endif
    }

    static var cardCorner: CGFloat {
        #if os(macOS)
        12
        #else
        28
        #endif
    }
}

struct ScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppTheme.accent.opacity(0.34), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )

            RadialGradient(
                colors: [Color(red: 0.86, green: 0.18, blue: 0.06).opacity(0.22), .clear],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)

            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleSize: CGFloat {
        #if os(macOS)
        38
        #else
        54
        #endif
    }
}

struct LoadingPanel: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .glassEffect(in: .rect(cornerRadius: 22))
    }
}

struct AppPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(34)
            .glassEffect(in: .rect(cornerRadius: 30))
    }
}

extension View {
    func screenBackground() -> some View {
        background(ScreenBackground())
    }
}

extension Category {
    var sidebarSystemImage: String {
        switch self {
        case .films:
            "film.stack"
        case .series:
            "play.tv"
        case .cartoons:
            "theatermasks"
        case .animation:
            "sparkles.tv"
        case .general:
            "house"
        case .new:
            "clock.badge.sparkles"
        case .search:
            "magnifyingglass"
        case .none:
            "square.stack"
        case .announce:
            "megaphone"
        case .collections:
            "square.stack.3d.up"
        case .loadMore:
            "ellipsis.circle"
        }
    }
}
