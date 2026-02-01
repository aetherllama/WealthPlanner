import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    NetWorthCard(
                        netWorth: viewModel.formattedNetWorth,
                        assets: viewModel.formattedAssets,
                        liabilities: viewModel.formattedLiabilities
                    )

                    if !viewModel.assetAllocation.isEmpty {
                        AllocationChart(data: viewModel.allocationChartData)
                    }

                    MonthlyOverviewCard(
                        income: viewModel.formattedMonthlyIncome,
                        expenses: viewModel.formattedMonthlyExpenses,
                        savings: viewModel.formattedMonthlySavings,
                        savingsRate: viewModel.savingsRate
                    )

                    AccountsSummaryCard(accounts: viewModel.accounts)

                    if !viewModel.recentTransactions.isEmpty {
                        RecentTransactionsCard(transactions: viewModel.recentTransactions)
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await viewModel.refresh()
            }
            .onAppear {
                viewModel.configure(modelContext: modelContext)
                Task {
                    await viewModel.refresh()
                }
            }
            .overlay {
                if viewModel.isLoading && viewModel.accounts.isEmpty {
                    ProgressView()
                }
            }
        }
    }
}

struct MonthlyOverviewCard: View {
    let income: String
    let expenses: String
    let savings: String
    let savingsRate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This Month")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Income")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(income)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("Expenses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(expenses)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("Savings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(savings)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }

            HStack {
                Text("Savings Rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", savingsRate))
                    .font(.caption)
                    .fontWeight(.medium)
            }

            ProgressView(value: max(0, min(savingsRate / 100, 1)))
                .tint(savingsRate >= 20 ? .green : savingsRate >= 10 ? .orange : .red)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct AccountsSummaryCard: View {
    let accounts: [Account]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    AccountsView()
                } label: {
                    Text("See All")
                        .font(.caption)
                }
            }

            if accounts.isEmpty {
                ContentUnavailableView(
                    "No Accounts",
                    systemImage: "building.columns",
                    description: Text("Add an account to get started")
                )
                .frame(height: 100)
            } else {
                ForEach(accounts.prefix(4)) { account in
                    HStack {
                        Image(systemName: account.type.icon)
                            .foregroundStyle(.blue)
                            .frame(width: 30)

                        VStack(alignment: .leading) {
                            Text(account.name)
                                .font(.subheadline)
                            Text(account.institution)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(account.displayBalance)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(account.type.isAsset ? .primary : .red)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct RecentTransactionsCard: View {
    let transactions: [Transaction]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                Spacer()
            }

            ForEach(transactions) { transaction in
                HStack {
                    Image(systemName: transaction.category.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 30)

                    VStack(alignment: .leading) {
                        Text(transaction.transactionDescription)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(transaction.displayDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(transaction.displayAmount)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(transaction.amount >= 0 ? .green : .primary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Account.self, Holding.self, Transaction.self, Goal.self, Budget.self])
}
