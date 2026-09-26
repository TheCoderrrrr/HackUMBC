import SwiftUI

/// "Use my accounts" during setup. Linking is honestly unavailable in this demo;
/// the only way forward is sample data.
struct AccountPreviewSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Connect your accounts.")
                    .font(.geist(32, .regular, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Account linking isn’t available in this demo.")
                    .font(.geist(16, .regular, relativeTo: .body))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.top, 44)

            ConnectionGraphic()
                .padding(.top, 56)

            Text("Retirement · Cash · Credit cards")
                .font(.geist(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 58)

            Spacer(minLength: Space.xl)

            Button("Try with sample data") {
                dismiss()
                if store.onboardingStep == .profile {
                    withAnimation(Motion.respecting(reduceMotion, Motion.smart)) {
                        store.onboardingStep = .accounts
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Back") { dismiss() }
                .font(.geist(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(PressableStyle())
                .padding(.top, Space.s)
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.s)
        .background {
            ZStack {
                AtmosphereView()
                FrostedSetupSurface()
            }
        }
        .presentationBackground(Palette.page)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }
}

/// You · · · · · · · · Accounts
private struct ConnectionGraphic: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            node(symbol: "person", label: "You")
            HStack(spacing: 9) {
                ForEach(0..<8, id: \.self) { _ in
                    Circle().fill(Palette.textCaption).frame(width: 3, height: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            node(symbol: "building.columns", label: "Accounts")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your accounts are not connected")
    }

    private func node(symbol: String, label: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Palette.accent)
                .frame(width: 80, height: 80)
                .background(Circle().fill(Palette.raised))
            Text(label)
                .font(.geist(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(width: 80)
    }
}
