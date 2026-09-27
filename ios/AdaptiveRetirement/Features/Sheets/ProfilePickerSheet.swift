import SwiftUI

/// Choose between the three fictional profiles. Selecting a row switches instantly;
/// the primary action returns to that profile's plan.
struct ProfilePickerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(title: "Choose a profile") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Profile.all) { profile in
                    ProfileOptionRow(profile: profile, isSelected: profile.id == store.profile.id) {
                        withAnimation(Motion.select) { store.select(profile) }
                    }
                }
                if let manual = store.manualProfile {
                    ProfileOptionRow(profile: .personal(manual), isSelected: store.profile.id == manual.id) {
                        store.select(.personal(manual))
                    }
                }
                Button("Enter your own numbers and fund") { store.sheet = .manualProfile }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, Space.m)

                // The saved cash-first demonstration (FRONTEND.md §7): Morgan's inputs with a
                // cash_security preference and a saved, reviewed AI decision (REPORT B7).
                // Not a fourth customer — the picker still lists the three default profiles.
                Button {
                    withAnimation(Motion.select) {
                        store.select(store.profile.id == Profile.morganCashSecurity.id
                                     ? .morgan : .morganCashSecurity)
                    }
                } label: {
                    EmphasizedText(store.profile.id == Profile.morganCashSecurity.id
                                   ? "Back to Morgan’s balanced plan"
                                   : "See Morgan with a **cash-first** preference — a saved AI demonstration",
                                   size: 13, style: .footnote, color: Palette.accent, lineSpacing: 2)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 1, dim: 0.7))
                .padding(.top, Space.m)

                Button("Explore \(store.profile.name)’s plan") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, Space.l)

                Text("Fictional profiles · Synthetic data\nNot affiliated with or endorsed by T. Rowe Price.")
                    .font(.geist(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(Palette.textCaption)
                    .lineSpacing(3)
                    .padding(.top, 15)
            }
            .padding(.top, 20)
        }
        .sensoryFeedback(.selection, trigger: store.profile.id)
    }
}

private struct ProfileOptionRow: View {
    let profile: Profile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.m) {
                    Text(profile.initials)
                        .font(.geist(15.2, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Palette.raised))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name)
                            .font(.geist(19, .medium, relativeTo: .title3))
                            .foregroundStyle(Palette.textPrimary)
                        EmphasizedText("**\(profile.age)** · Retiring at **\(profile.retirementAge)**",
                                       size: 13, style: .footnote)
                    }

                    Spacer(minLength: Space.m)

                    SelectionIndicator(isSelected: isSelected)
                }
                .frame(minHeight: 46)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(profile.pickerSummary, id: \.self) { line in
                        EmphasizedText(line, size: 14, style: .subheadline, lineSpacing: 2)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 13)

                Hairline(color: Palette.hairlineStrong)
            }
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99, dim: 0.8))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle().fill(isSelected ? Palette.accentStrong : Palette.raised)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

private extension Profile {
    /// Two short lines describing the situation and the plan's stance.
    var pickerSummary: [String] {
        let threshold = ModelAssumptions.illustrative.highInterestAPRThreshold
        let debtPhrase: String
        if let debt = debts.first {
            debtPhrase = debt.apr >= threshold
                ? "**\(Money.whole(totalDebtCents))** \(debt.kindPhrase) debt"
                : "Low-rate \(debt.kindPhrase) debt"
        } else {
            debtPhrase = "No debt"
        }
        let months = Int(emergencyMonths.rounded())
        let reserves = "**\(months)** \(months == 1 ? "month" : "months") of reserves"
        let stance = primaryActionAmountCents != nil
            ? "Preserve the match. Prioritize debt."
            : "Maintain a **\(SheetCopy.percent(adaptiveEmployeeRate))** contribution."
        return ["\(debtPhrase) · \(reserves)", stance]
    }
}

private extension Debt {
    /// "Credit card" → "credit card", "Student loan" → "student".
    var kindPhrase: String {
        name.lowercased().replacingOccurrences(of: " loan", with: "")
    }
}
