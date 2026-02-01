import SwiftUI

struct AddGoalView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var goalType: GoalType = .savings
    @State private var targetAmount: Decimal = 0
    @State private var currentAmount: Decimal = 0
    @State private var targetDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
    @State private var monthlyContribution: Decimal = 0

    let onSave: (String, String?, GoalType, Decimal, Decimal, Date, Decimal?) -> Void

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        targetAmount > 0 &&
        targetDate > Date()
    }

    var monthsUntilTarget: Int {
        let calendar = Calendar.current
        let months = calendar.dateComponents([.month], from: Date(), to: targetDate).month ?? 0
        return max(months, 1)
    }

    var requiredMonthly: Decimal {
        let remaining = targetAmount - currentAmount
        guard remaining > 0, monthsUntilTarget > 0 else { return 0 }
        return remaining / Decimal(monthsUntilTarget)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal Name", text: $name)

                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Picker("Goal Type", selection: $goalType) {
                        ForEach(GoalType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Target Amount")
                        Spacer()
                        TextField("Amount", value: $targetAmount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Current Savings")
                        Spacer()
                        TextField("Amount", value: $currentAmount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("Target Date", selection: $targetDate, in: Date()..., displayedComponents: .date)
                }

                Section {
                    HStack {
                        Text("Monthly Contribution")
                        Spacer()
                        TextField("Monthly", value: $monthlyContribution, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if targetAmount > currentAmount {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("To reach your goal, save \(formatCurrency(requiredMonthly))/month")

                            if monthlyContribution > 0 {
                                if monthlyContribution >= requiredMonthly {
                                    Text("You're on track!")
                                        .foregroundStyle(.green)
                                } else {
                                    Text("You need \(formatCurrency(requiredMonthly - monthlyContribution)) more/month")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }

                Section("Quick Goals") {
                    QuickGoalButton(
                        title: "Emergency Fund",
                        description: "3-6 months expenses",
                        icon: "cross.circle"
                    ) {
                        name = "Emergency Fund"
                        goalType = .emergency
                        targetAmount = 10000
                    }

                    QuickGoalButton(
                        title: "Vacation",
                        description: "Dream trip fund",
                        icon: "airplane"
                    ) {
                        name = "Vacation Fund"
                        goalType = .vacation
                        targetAmount = 3000
                    }

                    QuickGoalButton(
                        title: "Home Down Payment",
                        description: "20% down payment",
                        icon: "house"
                    ) {
                        name = "Home Down Payment"
                        goalType = .home
                        targetAmount = 50000
                    }
                }
            }
            .navigationTitle("Add Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(
                            name,
                            description.isEmpty ? nil : description,
                            goalType,
                            targetAmount,
                            currentAmount,
                            targetDate,
                            monthlyContribution > 0 ? monthlyContribution : nil
                        )
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

struct QuickGoalButton: View {
    let title: String
    let description: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    AddGoalView { _, _, _, _, _, _, _ in }
}
