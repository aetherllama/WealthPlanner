import SwiftUI

struct AddBudgetView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var category: TransactionCategory = .food
    @State private var limit: Decimal = 0
    @State private var alertThreshold: Double = 80

    let onSave: (TransactionCategory, Decimal, Double) -> Void

    private var expenseCategories: [TransactionCategory] {
        TransactionCategory.allCases.filter { $0.isExpense }
    }

    var isValid: Bool {
        limit > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(expenseCategories) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Monthly Limit")
                        Spacer()
                        TextField("Limit", value: $limit, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Set the maximum amount you want to spend in this category each month.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Alert Threshold")
                            Spacer()
                            Text("\(Int(alertThreshold))%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $alertThreshold, in: 50...100, step: 5)
                    }
                } footer: {
                    Text("You'll be warned when spending reaches \(Int(alertThreshold))% of your budget.")
                }

                Section {
                    SuggestedLimits(category: category) { suggested in
                        limit = suggested
                    }
                }
            }
            .navigationTitle("Add Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(category, limit, alertThreshold / 100)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

struct SuggestedLimits: View {
    let category: TransactionCategory
    let onSelect: (Decimal) -> Void

    private var suggestions: [Decimal] {
        switch category {
        case .food:
            return [300, 500, 750, 1000]
        case .shopping:
            return [200, 400, 600, 800]
        case .transportation:
            return [150, 300, 500, 750]
        case .entertainment:
            return [100, 200, 300, 500]
        case .utilities:
            return [150, 250, 350, 500]
        case .healthcare:
            return [100, 200, 400, 600]
        case .subscriptions:
            return [50, 100, 150, 200]
        case .travel:
            return [200, 500, 1000, 2000]
        case .housing:
            return [1000, 1500, 2000, 3000]
        default:
            return [100, 250, 500, 1000]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Limits")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(suggestions, id: \.self) { amount in
                    Button {
                        onSelect(amount)
                    } label: {
                        Text(formatCurrency(amount))
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "$0"
    }
}

struct CategorySpendingView: View {
    let category: TransactionCategory
    let transactions: [Transaction]

    var filteredTransactions: [Transaction] {
        transactions
            .filter { $0.category == category }
            .sorted { $0.date > $1.date }
    }

    var totalSpent: Decimal {
        filteredTransactions.reduce(0) { $0 + abs($1.amount) }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Total Spent")
                    Spacer()
                    Text(formatCurrency(totalSpent))
                        .fontWeight(.bold)
                }
            }

            Section("Transactions") {
                if filteredTransactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "list.bullet",
                        description: Text("No transactions in this category")
                    )
                } else {
                    ForEach(filteredTransactions) { transaction in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(transaction.transactionDescription)
                                    .lineLimit(1)
                                Text(transaction.displayDate)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(transaction.displayAmount)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .navigationTitle(category.rawValue)
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

#Preview {
    AddBudgetView { _, _, _ in }
}
