import SwiftUI

// MARK: - Hairline

/// A true 1-pixel separator.
struct Hairline: View {
    var color: Color = Palette.hairline
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

// MARK: - Avatar

/// Morgan / Jordan / Casey identity. A soft brand-gradient disc with a thin inner ring.
struct AvatarView: View {
    let profile: Profile
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: max(0.5, size / 120))
            Text(profile.initials)
                .font(.geist(size * 0.40, .light))
                .foregroundStyle(Color.white.opacity(0.94))
                .tracking(-0.2)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(profile.name)'s profile")
    }

    private var gradient: [Color] {
        switch profile.id {
        case "jordan": [Color(hex: 0x3F7A7A), Color(hex: 0x2A3F66)]
        case "casey": [Color(hex: 0x9A6A52), Color(hex: 0x4A3552)]
        default: [Color(hex: 0x7C83F2), Color(hex: 0x3A43A8)]
        }
    }
}

// MARK: - Screen header (80 pt, fading, progressive blur)

/// Matching navigation header for Overview / Plan / Explore.
/// Content scrolls beneath; a 32 pt background-to-transparent fade with a subtle blur sits under it.
struct ScreenHeader<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                leading
                Spacer(minLength: Space.m)
                trailing
            }
            .padding(.horizontal, Space.gutter)
            .frame(height: Space.headerHeight - 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    // Progressive blur: material masked from opaque to clear.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .mask(
                            LinearGradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.62),
                                .init(color: .clear, location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                        )
                    LinearGradient(stops: [
                        .init(color: Palette.page, location: 0),
                        .init(color: Palette.page.opacity(0.92), location: 0.55),
                        .init(color: Palette.page.opacity(0), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .padding(.bottom, -32)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
        }
    }
}

extension ScreenHeader where Leading == Text {
    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.leading = Text(title).font(TypeScale.title).foregroundStyle(Palette.textPrimary)
        self.trailing = trailing()
    }
}

/// Header avatar: account menu with snapshot, profile switching, and onboarding replay.
struct HeaderAvatarButton: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Menu {
            Button {
                store.sheet = .snapshot
            } label: {
                Label("Financial snapshot", systemImage: "chart.bar.doc.horizontal")
            }
            Button {
                store.sheet = .profilePicker
            } label: {
                Label("Switch profile", systemImage: "person.2")
            }
            Divider()
            Button {
                store.sheet = nil
                store.replayOnboarding()
            } label: {
                Label("Replay onboarding", systemImage: "arrow.counterclockwise")
            }
        } label: {
            AvatarView(profile: store.profile, size: 44)
        }
        .accessibilityLabel("\(store.profile.name), account menu")
    }
}

// MARK: - Buttons

/// Quiet, physical press feedback: slight scale and dim, spring back.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var dim: Double = 0.85

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? dim : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// The one primary action per screen: indigo capsule, Medium label.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                Capsule()
                    .fill(Palette.indigo)
                    .overlay {
                        // Hair-thin top highlight for material depth.
                        Capsule()
                            .strokeBorder(
                                LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.02)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.75
                            )
                    }
                    .brightness(configuration.isPressed ? -0.06 : 0)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Secondary action: text-only lavender, or a hairline capsule when `bordered`.
struct SecondaryButtonStyle: ButtonStyle {
    var bordered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(bordered ? Palette.textPrimary : Palette.lavender)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if bordered {
                    Capsule().strokeBorder(Palette.hairlineStrong, lineWidth: 1)
                        .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.06 : 0.02)))
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A small circular glass control (sheet close, playback).
struct GlassCircleButton: View {
    let systemName: String
    var size: CGFloat = 36
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: size, height: size)
                .background {
                    if #available(iOS 26.0, *) {
                        Circle().fill(.clear).glassEffect(.regular, in: Circle())
                    } else {
                        Circle().fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(Palette.hairlineStrong, lineWidth: 0.5))
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Sections and rows

/// Open section heading with optional trailing "Why?" link.
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var whyAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TypeScale.headline)
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.label)
                        .foregroundStyle(Palette.textCaption)
                }
            }
            Spacer()
            if let whyAction {
                Button("Why?", action: whyAction)
                    .font(TypeScale.labelMedium)
                    .foregroundStyle(Palette.lavender)
                    .buttonStyle(PressableStyle())
                    .frame(minHeight: 44)
            }
        }
    }
}

/// Small uppercase label.
struct Eyebrow: View {
    let text: String
    var color: Color = Palette.textCaption

    var body: some View {
        Text(text.uppercased())
            .font(TypeScale.eyebrow)
            .tracking(0.9)
            .foregroundStyle(color)
    }
}

/// Label / value row with right-aligned tabular amount and a leading marker.
struct ValueRow: View {
    let title: String
    let value: String
    var detail: String? = nil
    var marker: Color? = nil
    var hollowMarker = false
    var quiet = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            if let marker {
                Circle()
                    .strokeBorder(marker, lineWidth: hollowMarker ? 1 : 0)
                    .background(Circle().fill(hollowMarker ? .clear : marker))
                    .frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TypeScale.callout)
                    .foregroundStyle(quiet ? Palette.textCaption : Palette.textSecondary)
                if let detail {
                    Text(detail)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textCaption)
                }
            }
            Spacer(minLength: Space.m)
            Text(value)
                .font(TypeScale.amount)
                .monospacedDigit()
                .foregroundStyle(quiet ? Palette.textCaption : Palette.textPrimary)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Data-provenance badge (Saved demo calculation / Live / Last live).
struct DataModeBadge: View {
    let mode: DataMode

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mode == .live ? Palette.positive : Palette.textCaption)
                .frame(width: 5, height: 5)
            Text(mode.rawValue)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().strokeBorder(Palette.hairlineStrong, lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sheet scaffold

/// Platform sheet contents with a title and a circular glass close control.
struct SheetScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.geist(27, .semibold, relativeTo: .title))
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(TypeScale.label)
                            .foregroundStyle(Palette.textCaption)
                    }
                }
                Spacer()
                GlassCircleButton(systemName: "xmark", size: 44, accessibilityLabel: "Close") { dismiss() }
            }
            .padding(.leading, Space.xl)
            .padding(.trailing, 18)
            .padding(.top, 26)
            .padding(.bottom, Space.s)

            ScrollView {
                content
                    .padding(.horizontal, Space.xl)
                    .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.sheet.ignoresSafeArea())
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Hero amount

/// "$35,000" with smaller raised cents when non-zero (or forced).
struct HeroAmount: View {
    let cents: Int64
    var showCents = true

    var body: some View {
        let parts = Money.split(cents)
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(parts.dollars)
                .font(TypeScale.hero)
                .tracking(-1.2)
            if showCents {
                Text(".\(parts.cents)")
                    .font(TypeScale.heroCents)
                    .foregroundStyle(Palette.textCaption)
                    .baselineOffset(18)
            }
        }
        .monospacedDigit()
        .foregroundStyle(Palette.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Money.exact(cents))
    }
}
