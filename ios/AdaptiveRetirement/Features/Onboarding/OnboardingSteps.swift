import SwiftUI

// Each step reserves slots for the avatar / selected icon; the flow draws them above.

// MARK: - 1 · Profile

struct ProfileStep: View {
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupPrompt(heading: "Your profile", instruction: "Try a sample financial life.")
                .padding(.top, 25)

            VStack(spacing: 0) {
                Color.clear
                    .frame(width: 112, height: 112)
                    .setupSlot(Slot.avatar(for: .profile))
                Text(profile.name)
                    .font(.geist(24, .regular, relativeTo: .title2))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, Space.xl)
                Text("Sample profile")
                    .font(SetupStyle.rowDetail)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Space.s)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 52)
            .accessibilityElement(children: .combine)

            Spacer(minLength: Space.l)

            Text("Fictional profile · Not affiliated with T. Rowe Price.")
                .font(.geist(11, .regular, relativeTo: .caption2))
                .foregroundStyle(Palette.textSecondary)
                .padding(.bottom, 29)
        }
    }
}

// MARK: - 2 · Accounts

struct AccountsStep: View {
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupPrompt(heading: "Bring it together.", instruction: "Your accounts, in one place.")
                .padding(.top, 25)

            connection
                .padding(.top, 64)

            VStack(spacing: Space.xs) {
                row("Retirement", Money.whole(profile.retirementBalanceCents))
                row("Cash", Money.whole(profile.emergencyCashCents))
                if profile.totalDebtCents > 0 {
                    row(profile.debts.first?.name ?? "Debt", Money.whole(profile.totalDebtCents))
                }
            }
            .padding(.top, 34)

            Spacer(minLength: 0)
        }
    }

    /// Avatar · dotted link · account icon. Sample data only — nothing is linked.
    private var connection: some View {
        HStack(alignment: .top, spacing: 0) {
            endpoint(caption: profile.name) {
                Color.clear.setupSlot(Slot.avatar(for: .accounts))
            }
            HStack(spacing: 9) {
                ForEach(0..<8, id: \.self) { _ in
                    Circle().fill(Palette.textCaption).frame(width: 3, height: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .accessibilityHidden(true)
            endpoint(caption: "Accounts") {
                TopicDisc(symbol: "building.columns")
            }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sample accounts for \(profile.name)")
    }

    private func endpoint<Visual: View>(caption: String, @ViewBuilder visual: () -> Visual) -> some View {
        VStack(spacing: Space.m) {
            visual().frame(width: 80, height: 80)
            Text(caption)
                .font(.geist(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 80)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.geist(16, .regular, relativeTo: .body))
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Space.m)
            Text(value)
                .font(.geist(18, .medium, relativeTo: .body))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 3 · Focus

struct FocusStep: View {
    let profile: Profile
    let selection: Focus
    let select: (Focus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupPrompt(heading: "What comes first?", instruction: "Choose what you’d like to explore.")
                .padding(.top, 25)

            VStack(spacing: Space.m) {
                ForEach(Focus.allCases) { focus in
                    FocusRow(
                        focus: focus,
                        detail: focus.setupDetail(for: profile),
                        isSelected: focus == selection,
                        showsDivider: focus != Focus.allCases.last,
                        action: { select(focus) }
                    )
                }
            }
            .padding(.top, 56)

            Spacer(minLength: 0)
        }
    }
}

private struct FocusRow: View {
    let focus: Focus
    let detail: String
    let isSelected: Bool
    let showsDivider: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // The selected icon is drawn by the continuity layer so it can travel.
                TopicDisc(symbol: focus.setupSymbol)
                    .scaleEffect(48 / TopicDisc.baseSize)
                    .frame(width: 48, height: 48)
                    .opacity(isSelected ? 0 : 1)
                    .setupSlot(Slot.row(focus))
                    .padding(.leading, Space.m)
                    .frame(width: 80, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text(focus.setupTitle)
                        .font(SetupStyle.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(SetupStyle.rowDetail)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: Space.m)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isSelected ? Palette.page : Palette.textSecondary, Palette.lavender)
                    .font(.system(size: 22, weight: .regular))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.trailing, Space.m)
            }
            .frame(minHeight: 88)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(SetupStyle.divider)
                        .frame(height: 1)
                        .padding(.leading, 80)
                        .offset(y: Space.m / 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99, dim: 0.8))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - 4 · Result

struct ResultStep: View {
    let profile: Profile
    let focus: Focus

    var body: some View {
        let result = focus.result(for: profile)
        VStack(alignment: .leading, spacing: 0) {
            SetupPrompt(heading: focus.resultHeading, instruction: focus.resultInstruction)
                .padding(.top, 25)

            VStack(spacing: Space.m) {
                Color.clear
                    .frame(width: 80, height: 80)
                    .setupSlot(Slot.resultIcon)
                    .padding(.bottom, 44 - Space.m)
                Text(result.amount)
                    .font(.geist(48, .regular, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(result.unit)
                    .font(.geist(16, .regular, relativeTo: .body))
                    .foregroundStyle(Palette.textPrimary)
                Text(result.context)
                    .font(SetupStyle.rowDetail)
                    .foregroundStyle(Palette.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 64)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
        }
    }
}
