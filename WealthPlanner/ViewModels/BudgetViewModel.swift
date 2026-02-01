import Foundation
import SwiftData

@MainActor
final class BudgetViewModel: ObservableObject {
    @Published var budgets: [Budget] = []
    @Published var transactions: [Transaction] = []
    @Published var selectedBudget: Budget?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var selectedMonth: Date = Date()

    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() async {
        guard let modelContext = modelContext else { return }

        isLoading = true
        error = nil

        do {
            let budgetRepo = BudgetRepository(modelContext: modelContext)
            let transactionRepo = TransactionRepository(modelContext: modelContext)

            let calendar = Calendar.current
            let month = calendar.component(.month, from: selectedMonth)
            let year = calendar.component(.year, from: selectedMonth)

            budgets = try budgetRepo.fetchByPeriod(month: month, year: year)

            let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!

            transactions = try transactionRepo.fetchByDateRange(start: startOfMonth, end: endOfMonth)

            try budgetRepo.syncWithTransactions(transactionRepo)
            budgets = try budgetRepo.fetchByPeriod(month: month, year: year)

        } catch {
            self.error = error
        }

        isLoading = false
    }

    func createBudget(
        category: TransactionCategory,
        limit: Decimal,
        alertThreshold: Double = 0.8
    ) async throws {
        guard let modelContext = modelContext else { return }

        let calendar = Calendar.current
        let month = calendar.component(.month, from: selectedMonth)
        let year = calendar.component(.year, from: selectedMonth)

        let budget = Budget(
            category: category,
            monthlyLimit: limit,
            periodMonth: month,
            periodYear: year,
            alertThreshold: alertThreshold
        )

        let repo = BudgetRepository(modelContext: modelContext)
        repo.create(budget)
        try repo.save()

        await refresh()
    }

    func deleteBudget(_ budget: Budget) async throws {
        guard let modelContext = modelContext else { return }

        let repo = BudgetRepository(modelContext: modelContext)
        repo.delete(budget)
        try repo.save()

        await refresh()
    }

    func updateBudget(_ budget: Budget) async throws {
        guard let modelContext = modelContext else { return }

        let repo = BudgetRepository(modelContext: modelContext)
        try repo.save()

        await refresh()
    }

    func goToPreviousMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: -1, to: selectedMonth) {
            selectedMonth = newDate
            Task {
                await refresh()
            }
        }
    }

    func goToNextMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: 1, to: selectedMonth) {
            selectedMonth = newDate
            Task {
                await refresh()
            }
        }
    }

    var selectedMonthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    var totalBudgeted: Decimal {
        budgets.reduce(0) { $0 + $1.monthlyLimit }
    }

    var totalSpent: Decimal {
        budgets.reduce(0) { $0 + $1.spent }
    }

    var totalRemaining: Decimal {
        totalBudgeted - totalSpent
    }

    var overallProgress: Double {
        guard totalBudgeted > 0 else { return 0 }
        return Double(truncating: (totalSpent / totalBudgeted) as NSDecimalNumber)
    }

    var formattedTotalBudgeted: String {
        formatCurrency(totalBudgeted)
    }

    var formattedTotalSpent: String {
        formatCurrency(totalSpent)
    }

    var formattedTotalRemaining: String {
        formatCurrency(totalRemaining)
    }

    var budgetsOverLimit: [Budget] {
        budgets.filter { $0.isOverBudget }
    }

    var budgetsNearLimit: [Budget] {
        budgets.filter { $0.isNearLimit }
    }

    var budgetsOnTrack: [Budget] {
        budgets.filter { !$0.isOverBudget && !$0.isNearLimit }
    }

    var spendingByCategory: [(category: TransactionCategory, amount: Decimal)] {
        var spending: [TransactionCategory: Decimal] = [:]

        for transaction in transactions where transaction.amount < 0 {
            spending[transaction.category, default: 0] += abs(transaction.amount)
        }

        return spending
            .map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var unbugdetedCategories: [TransactionCategory] {
        let budgetedCategories = Set(budgets.map { $0.category })
        let spentCategories = Set(spendingByCategory.map { $0.category })
        return Array(spentCategories.subtracting(budgetedCategories))
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}
