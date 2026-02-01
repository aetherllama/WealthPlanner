import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var account: Account
    @State private var showEditSheet = false
    @State private var showAddTransaction = false
    @State private var showAddHolding = false

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(account.displayBalance)
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    Spacer()
                    Image(systemName: account.type.icon)
                        .font(.largeTitle)
                        .foregroundStyle(.blue)
                }
                .padding(.vertical, 8)
            }

            Section("Details") {
                LabeledContent("Institution", value: account.institution.isEmpty ? "Not specified" : account.institution)
                LabeledContent("Type", value: account.type.rawValue)
                LabeledContent("Currency", value: account.currency)

                if let lastSynced = account.lastSynced {
                    LabeledContent("Last Updated", value: lastSynced, format: .dateTime)
                }

                if !account.isManual {
                    LabeledContent("Connection", value: "Linked via Plaid")
                }
            }

            if account.type == .investment || account.type == .retirement {
                Section {
                    if account.holdings.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No holdings")
                                    .foregroundStyle(.secondary)
                                Button("Add Holding") {
                                    showAddHolding = true
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding()
                            Spacer()
                        }
                    } else {
                        ForEach(account.holdings) { holding in
                            NavigationLink {
                                HoldingDetailView(holding: holding)
                            } label: {
                                HoldingRow(holding: holding)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Holdings")
                        Spacer()
                        if !account.holdings.isEmpty {
                            Button {
                                showAddHolding = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                }
            }

            Section {
                if account.transactions.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No transactions")
                                .foregroundStyle(.secondary)
                            Button("Add Transaction") {
                                showAddTransaction = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        Spacer()
                    }
                } else {
                    ForEach(account.transactions.prefix(10)) { transaction in
                        TransactionRow(transaction: transaction)
                    }

                    if account.transactions.count > 10 {
                        NavigationLink {
                            TransactionListView(account: account)
                        } label: {
                            Text("View All \(account.transactions.count) Transactions")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Recent Transactions")
                    Spacer()
                    if !account.transactions.isEmpty {
                        Button {
                            showAddTransaction = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }

            if let notes = account.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditSheet = true
                } label: {
                    Text("Edit")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditAccountView(account: account)
        }
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionView(account: account)
        }
        .sheet(isPresented: $showAddHolding) {
            AddHoldingView(account: account)
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category.icon)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.transactionDescription)
                    .lineLimit(1)

                Text(transaction.displayDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transaction.displayAmount)
                .fontWeight(.medium)
                .foregroundColor(transaction.amount >= 0 ? .green : .primary)
        }
    }
}

struct HoldingRow: View {
    let holding: Holding

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.symbol)
                    .font(.headline)

                Text(holding.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(holding.displayValue)
                    .fontWeight(.medium)

                Text(holding.displayGainLossPercent)
                    .font(.caption)
                    .foregroundColor(holding.isGain ? .green : .red)
            }
        }
    }
}

struct TransactionListView: View {
    let account: Account
    @State private var searchText = ""

    var filteredTransactions: [Transaction] {
        if searchText.isEmpty {
            return account.transactions.sorted { $0.date > $1.date }
        }
        return account.transactions
            .filter { $0.transactionDescription.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List(filteredTransactions) { transaction in
            TransactionRow(transaction: transaction)
        }
        .navigationTitle("Transactions")
        .searchable(text: $searchText, prompt: "Search transactions")
    }
}

struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var account: Account

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Account Name", text: $account.name)
                    TextField("Institution", text: $account.institution)
                }

                Section {
                    Picker("Account Type", selection: $account.type) {
                        ForEach(AccountType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if account.isManual {
                        HStack {
                            Text("Balance")
                            Spacer()
                            TextField("Balance", value: $account.balance, format: .currency(code: account.currency))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: Binding(
                        get: { account.notes ?? "" },
                        set: { account.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AccountDetailView(account: Account(
            name: "Checking Account",
            institution: "Chase Bank",
            type: .checking,
            balance: 5432.10
        ))
    }
    .modelContainer(for: [Account.self, Holding.self, Transaction.self])
}
