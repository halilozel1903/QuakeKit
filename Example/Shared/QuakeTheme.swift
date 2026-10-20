import QuakeKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum QuakeTheme {
    /// A warm seismograph orange.
    static let accent = Color(red: 0.95, green: 0.45, blue: 0.18)

    /// An opaque background for the sidebar. On the Mac a translucent (Liquid Glass) sidebar can
    /// come out as a blank white panel in window captures; a solid color always draws.
    static var sidebarBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// Panels over the map.
    static var panelBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    /// Tiles inside a panel.
    static var tileBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

extension View {
    /// The inline title style with a visible bar on iPad (iOS 26 hides the bar background
    /// otherwise); nothing on the Mac.
    func quakeNavigationStyle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        return self
        #endif
    }
}

/// The magnitude in a colored rounded square, as in the list and the detail panel.
struct MagnitudeBadge: View {
    let magnitude: Double?
    var size: CGFloat = 44

    var body: some View {
        let color = MagnitudeScale.color(for: magnitude ?? 0)
        Text(magnitude.map { String(format: "%.1f", $0) } ?? "?")
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color.prefersDarkText ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(color.color, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityLabel(magnitude.map { String(format: "Magnitude %.1f", $0) } ?? "Magnitude unknown")
    }
}

/// A small capsule with a symbol and text.
struct InfoChip: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

/// A value that is loading, loaded or failed.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension Earthquake {
    /// `"2 hours ago"`.
    var relativeTime: String {
        time.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}
