import SwiftUI

/// Personal numbers stay on this device; the build endpoint validates them and returns a
/// complete profile. One confirmed target-date fund may be attached to the balance.
struct ManualProfileView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var age = ""
    @State private var retirementAge = "67"
    @State private var salary = ""
    @State private var takeHome = ""
    @State private var living = ""
    @State private var contribution = ""
    @State private var balance = ""
    @State private var cash = ""
    @State private var matchKind = "none"
    @State private var matchUpTo = ""
    @State private var matchPerDollar = "100"
    @State private var fundID = ""
    @State private var account: API.Funds.AccountType = .k401
    @State private var balanceConfirmed = false
    @State private var menuConfirmed = false
    @State private var catalog: [API.Funds.CatalogEntry] = []
    @State private var debts: [DebtDraft] = []
    @State private var error: String?
    @State private var saving = false
    @State private var deleting = false

    private struct DebtDraft: Identifiable {
        let id = UUID()
        var type = "credit_card"
        var balance = ""
        var apr = ""
        var minimum = ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    TextField("Name", text: $name)
                    amount("Age", $age)
                    amount("Retirement age", $retirementAge)
                }
                Section("Income and savings") {
                    amount("Annual salary ($)", $salary)
                    amount("Monthly take-home ($)", $takeHome)
                    amount("Monthly living costs ($)", $living)
                    amount("Current contribution (%)", $contribution)
                    amount("Retirement balance ($)", $balance)
                    amount("Emergency cash ($)", $cash)
                }
                Section("One target-date fund") {
                    Picker("Fund", selection: $fundID) {
                        Text("I don't know yet").tag("")
                        ForEach(catalog) { fund in Text(fund.name).tag(fund.fundID) }
                    }
                    if !fundID.isEmpty {
                        Picker("Account", selection: $account) {
                            Text("401(k)").tag(API.Funds.AccountType.k401)
                            Text("IRA").tag(API.Funds.AccountType.ira)
                        }
                        Toggle("This balance is in this one fund", isOn: $balanceConfirmed)
                        if account == .k401 {
                            Toggle("I confirmed it is in my plan menu", isOn: $menuConfirmed)
                        }
                    }
                    Text("If you don't know your fund, ARM uses a generic glide path until you add it.")
                        .font(.caption)
                }
                Section("Employer match") {
                    Picker("Match", selection: $matchKind) {
                        Text("No match").tag("none")
                        Text("Employer matches").tag("match")
                        Text("Not sure").tag("unknown")
                    }
                    if matchKind == "match" {
                        amount("Matches up to (%)", $matchUpTo)
                        amount("Adds per dollar (%)", $matchPerDollar)
                    }
                }
                Section("Debts") {
                    ForEach($debts) { $debt in
                        VStack(alignment: .leading) {
                            Picker("Type", selection: $debt.type) {
                                Text("Credit card").tag("credit_card")
                                Text("Student loan").tag("student_loan")
                                Text("Other").tag("other")
                            }
                            amount("Balance ($)", $debt.balance)
                            amount("APR (%)", $debt.apr)
                            amount("Minimum per month ($)", $debt.minimum)
                        }
                    }
                    .onDelete { debts.remove(atOffsets: $0) }
                    Button("Add a debt") { debts.append(DebtDraft()) }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Button(saving ? "Checking…" : "Build my plan") { Task { await save() } }
                        .disabled(saving || store.apiClient == nil)
                    if store.apiClient == nil {
                        Text("Connect to the live server in Modeling assumptions to enter your numbers.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Your numbers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if store.manualProfile != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(deleting ? "Deleting…" : "Delete saved profile", role: .destructive) {
                            Task { await deleteSavedProfile() }
                        }
                        .disabled(deleting || store.apiClient == nil)
                    }
                }
            }
        }
        .task {
            if let saved = store.manualProfile {
                populate(saved)
            } else if let message = await store.loadManualProfileFromServer() {
                // An unavailable database should not prevent a local entry.
                error = message
            } else if let saved = store.manualProfile {
                populate(saved)
            }
            guard let client = store.apiClient else { return }
            catalog = (try? await client.fundCatalog().funds) ?? []
        }
    }

    private func amount(_ label: String, _ value: Binding<String>) -> some View {
        TextField(label, text: value).keyboardType(.decimalPad)
    }

    private func dollars(_ text: String) -> Int64? {
        guard let value = Double(text), value >= 0, value.isFinite, value < 100_000_000_000 else { return nil }
        return Int64((value * 100).rounded())
    }

    private func makeInput() -> API.ManualProfileInput? {
        guard let age = Int(age), let retirementAge = Int(retirementAge),
              let salary = dollars(salary), let takeHome = dollars(takeHome),
              let living = dollars(living), let balance = dollars(balance), let cash = dollars(cash),
              let contribution = Double(contribution), contribution >= 0, contribution <= 100 else { return nil }
        let match: API.ManualProfileInput.Match
        if matchKind == "match" {
            guard let upTo = Double(matchUpTo), let perDollar = Double(matchPerDollar) else { return nil }
            match = .init(kind: "match", upToRate: upTo / 100, matchPerDollar: perDollar / 100)
        } else {
            match = .init(kind: matchKind, upToRate: nil, matchPerDollar: nil)
        }
        var debtInputs: [API.ManualProfileInput.Debt] = []
        for debt in debts {
            guard let amount = dollars(debt.balance), let apr = Double(debt.apr),
                  let minimum = dollars(debt.minimum) else { return nil }
            debtInputs.append(.init(type: debt.type, balanceCents: amount, apr: apr / 100,
                                    minimumPaymentCents: minimum))
        }
        return .init(name: name.isEmpty ? "You" : name, age: age, retirementAge: retirementAge,
                     annualGrossSalaryCents: salary, monthlyTakeHomeCents: takeHome,
                     monthlyLivingExpensesCents: living, employeeContributionRate: contribution / 100,
                     retirementBalanceCents: balance, emergencyCashCents: cash, match: match, debts: debtInputs,
                     fundID: fundID.isEmpty ? nil : fundID,
                     fundBalanceConfirmed: !fundID.isEmpty && balanceConfirmed,
                     fundAccountType: fundID.isEmpty ? nil : account,
                     planMenuFundIDs: !fundID.isEmpty && account == .k401 && menuConfirmed ? [fundID] : nil)
    }

    private func save() async {
        guard let input = makeInput() else { error = "Complete each amount with a valid number."; return }
        guard let client = store.apiClient else { error = "Connect to the live server first."; return }
        saving = true
        defer { saving = false }
        do {
            let result: API.ProfileBuild
            do {
                result = try await client.saveProfile(input)
            } catch APIError.server(let status, _) where status == 503 {
                result = try await client.buildProfile(input)
            }
            store.useManualProfile(result.profile)
            dismiss()
        } catch { self.error = APIError.userMessage(for: error) }
    }

    private func deleteSavedProfile() async {
        deleting = true
        defer { deleting = false }
        do {
            try await store.deleteManualProfile()
            dismiss()
        } catch {
            self.error = APIError.userMessage(for: error)
        }
    }

    private func populate(_ input: API.FinancialProfile) {
        name = input.name; age = String(input.age); retirementAge = String(input.retirementAge)
        salary = String(Double(input.annualGrossSalaryCents) / 100)
        takeHome = String(Double(input.monthlyTakeHomeCents) / 100)
        living = String(Double(input.monthlyLivingExpensesCents) / 100)
        contribution = String(input.employeeContributionRate * 100)
        balance = String(Double(input.retirementBalanceCents) / 100)
        cash = String(Double(input.emergencyCashCents) / 100)
        fundID = input.fundID ?? ""; account = input.fundAccountType ?? .k401
        balanceConfirmed = input.fundBalanceConfirmed
        menuConfirmed = input.planMenuFundIDs?.contains(fundID) ?? false
        matchKind = input.employerMatch.status.rawValue
        matchUpTo = String((input.employerMatch.tiers.first?.employeeRateTo ?? 0) * 100)
        matchPerDollar = String((input.employerMatch.tiers.first?.matchPerEmployeeDollar ?? 1) * 100)
        debts = input.debts.map { item in
            DebtDraft(type: item.type.rawValue, balance: String(Double(item.balanceCents) / 100),
                      apr: String(item.apr * 100), minimum: String(Double(item.minimumPaymentCents) / 100))
        }
    }
}
