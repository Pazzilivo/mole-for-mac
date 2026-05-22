import SwiftUI

// MARK: - Shared Visual Style Tokens

/// Shared corner radii used across the app.
enum MoleRadius {
    static let pill: CGFloat = 6
    static let card: CGFloat = 8
    static let feature: CGFloat = 10
}

/// Adaptive card/pane background that respects platform capabilities.
///
/// On macOS 26+ with Liquid Glass, this uses `.ultraThinMaterial` for
/// a native translucent look. On older systems it falls back to a subtle
/// tinted fill.
///
/// **Usage** (replace all `compatibleCardFill` / `compatiblePaneFill`):
/// ```swift
/// .background(MoleFill.card, in: RoundedRectangle(cornerRadius: MoleRadius.card))
/// ```
enum MoleFill {
    /// Standard card/row background.
    static var card: Color {
        Color.secondary.opacity(0.08)
    }

    /// Elevated pane/section background — slightly more prominent than `card`.
    static var pane: Color {
        Color.secondary.opacity(0.08)
    }

    /// Tinted background for informational banners.
    static func tinted(_ color: Color, opacity: Double = 0.06) -> Color {
        color.opacity(opacity)
    }
}

// MARK: - Glass-compatible Background ViewModifier

/// Applies a material background on macOS 26+, or a flat fallback on older systems.
///
/// Use on toolbar, key action buttons, and temporary banners only.
/// Do **not** apply to content-layer cards to avoid "glass on glass".
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = MoleRadius.card

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    /// Apply a glass-compatible background. On macOS 26+ this uses `.ultraThinMaterial`,
    /// on older macOS it falls back to a flat tinted fill.
    ///
    /// Reserve for control/navigation layer only (toolbar, action buttons, banners).
    func moleGlassBackground(cornerRadius: CGFloat = MoleRadius.card) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}
