import SwiftUI
import SwiftData
import Charts

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = BudgetViewModel()
    @State private var showAddBudget = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MonthSelector(
                        month: viewModel.selectedMonthString,
                        onPrevious: viewModel.goToPreviousMonth,
                        onNext: viewModel.goToNextMonth
                    )

                    BudgetOverviewCard(
                        budgeted: viewModel.formattedTotalBudgeted,
                        spent: viewModel.formattedTotalSpent,
                        remaining: viewModel.formattedTotalRemaining,
                        progress: viewModel.overallProgress
                    )

                    if !viewModel.budgets.isEmpty {
                        BudgetSpendingChart(spending: viewModel.spendingByCategory)

                        BudgetCategoriesSection(
                            budgets: viewModel.budgets,
                            onDelete: { budget in
                                Task {
                                    try await viewModel.deleteBudget(budget)
                                }
                            }
                        )
                    } else if !viewModel.isLoading {
                        ContentUnavailableView {
                            Label("No Budgets", systemImage: "chart.bar")
                        } description: {
                            Text("Create budget categories to track your spending")
                        } actions: {
                            Button("Create Budget") {
                                showAddBudget = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Budget")
            .refreshable {
                await viewModel.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddBudget = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                viewModel.configure(modelContext: modelContext)
                Task {
                    await viewModel.refresh()
                }
            }
            .sheet(isPresented: $showAddBudget) {
                AddBudgetView { category, limit, threshold in
                    Task {
                        try await viewModel.createBudget(
                            category: category,
                            limit: limit,
                            alertThreshold: threshold
                        )
                    }
                }
            }
        }
    }
}

struct MonthSelector: View {
    let month: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button {
                onPrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }

            Spacer()

            Text(month)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button {
                onNext()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
        }
        .padding(.horizontal)
    }
}

struct BudgetOverviewCard: View {
    let budgeted: String
    let spent: String
    let remaining: String
    let progress: Double

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 30) {
                VStack {
                    Text("Budgeted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(budgeted)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                VStack {
                    Text("Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(spent)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(progress > 1 ? .red : .primary)
                }

                VStack {
                    Text("Remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(remaining)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(progress > 1 ? .red : .green)
                }
            }

            VStack(spacing: 4) {
                ProgressView(value: min(progress, 1))
                    .tint(progress > 0.9 ? .red : progress > 0.7 ? .orange : .green)

                Text("\(Int(progress * 100))% of budget used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct BudgetSpendingChart: View {
    let spending: [(category: TransactionCategory, amount: Decimal)]

    private let colors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint, .red, .yellow
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending by Category")
                .font(.headline)

            if spending.isEmpty {
                ContentUnavailableView(
                    "No Spending",
                    systemImage: "cart",
                    description: Text("No transactions this month")
                )
                .frame(height: 150)
            } else {
                Chart(Array(spending.prefix(6).enumerated()), id: \.element.category) { index, item in
                    BarMark(
                        x: .value("Amount", Double(truncating: item.amount as NSDecimalNumber)),
                        y: .value("Category", item.category.rawValue)
                    )
                    .foregroundStyle(colors[index % colors.count])
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(formatCurrency(amount))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(min(spending.count, 6) * 40 + 20))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

struct BudgetCategoriesSection: View {
    let budgets: [Budget]
    let onDelete: (Budget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget Categories")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(budgets) { budget in
                BudgetCategoryCard(budget: budget)
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(budget)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }
}

struct BudgetCategoryCard: View {
    let budget: Budget

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: budget.category.icon)
                    .foregroundStyle(.blue)
                    .frame(width: 30)

                Text(budget.category.rawValue)
                    .font(.headline)

                Spacer()

                VStack(alignment: .trailing) {
                    Text(budget.displaySpent)
                        .fontWeight(.medium)
                    Text("of \(budget.displayLimit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(budget.isOverBudget ? .red : budget.isNearLimit ? .orange : .green)
                            .frame(width: geometry.size.width * min(budget.progress, 1))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(budget.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(statusColor)

                    Spacer()

                    Text(budget.displayRemaining)
                        .font(.caption)
                        .foregroundColor(budget.isOverBudget ? .red : .secondary)

                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var statusColor: Color {
        switch budget.status {
        case .onTrack: return .green
        case .nearLimit: return .orange
        case .overBudget: return .red
        }
    }
}

#Preview {
    BudgetView()
        .modelContainer(for: [Account.self, Transaction.self, Budget.self])
}
