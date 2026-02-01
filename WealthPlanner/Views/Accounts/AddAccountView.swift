import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var institution = ""
    @State private var type: AccountType = .checking
    @State private var balance: Decimal = 0
    @State private var currency = "USD"

    let onSave: (String, String, AccountType, Decimal) -> Void

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Account Name", text: $name)

                    TextField("Institution (optional)", text: $institution)
                }

                Section {
                    Picker("Account Type", selection: $type) {
                        ForEach(AccountType.allCases) { accountType in
                            Label(accountType.rawValue, systemImage: accountType.icon)
                                .tag(accountType)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Balance")
                        Spacer()
                        TextField("Balance", value: $balance, format: .currency(code: currency))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("Currency", selection: $currency) {
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                        Text("CAD").tag("CAD")
                        Text("AUD").tag("AUD")
                        Text("JPY").tag("JPY")
                    }
                } footer: {
                    if !type.isAsset {
                        Text("For credit cards and loans, enter the amount owed as a positive number.")
                    }
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let effectiveBalance = type.isAsset ? balance : -abs(balance)
                        onSave(name, institution, type, effectiveBalance)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let account: Account

    @State private var date = Date()
    @State private var description = ""
    @State private var amount: Decimal = 0
    @State private var isExpense = true
    @State private var category: TransactionCategory = .other

    var isValid: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty && amount != 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    TextField("Description", text: $description)
                }

                Section {
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .currency(code: account.currency))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("Category", selection: $category) {
                        ForEach(TransactionCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let effectiveAmount = isExpense ? -abs(amount) : abs(amount)

                        let transaction = Transaction(
                            date: date,
                            description: description,
                            amount: effectiveAmount,
                            category: category
                        )

                        transaction.account = account
                        modelContext.insert(transaction)

                        if account.isManual {
                            account.balance += effectiveAmount
                        }

                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

#Preview {
    AddAccountView { _, _, _, _ in }
}
