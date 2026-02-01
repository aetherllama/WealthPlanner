import Foundation
import SwiftData

@MainActor
final class BudgetRepository: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [Budget] {
        let descriptor = FetchDescriptor<Budget>()
        let budgets = try modelContext.fetch(descriptor)
        return budgets.sorted { $0.category.rawValue < $1.category.rawValue }
    }

    func fetchCurrentMonth() throws -> [Budget] {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.periodMonth == month && $0.periodYear == year }
        )
        let budgets = try modelContext.fetch(descriptor)
        return budgets.sorted { $0.category.rawValue < $1.category.rawValue }
    }

    func fetchByPeriod(month: Int, year: Int) throws -> [Budget] {
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.periodMonth == month && $0.periodYear == year }
        )
        let budgets = try modelContext.fetch(descriptor)
        return budgets.sorted { $0.category.rawValue < $1.category.rawValue }
    }

    func fetchByCategory(_ category: TransactionCategory) throws -> [Budget] {
        let descriptor = FetchDescriptor<Budget>()
        let budgets = try modelContext.fetch(descriptor)
        return budgets
            .filter { $0.category == category }
            .sorted { ($0.periodYear, $0.periodMonth) > ($1.periodYear, $1.periodMonth) }
    }

    func fetchById(_ id: UUID) throws -> Budget? {
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchCurrentMonthByCategory(_ category: TransactionCategory) throws -> Budget? {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.periodMonth == month && $0.periodYear == year }
        )
        let budgets = try modelContext.fetch(descriptor)
        return budgets.first { $0.category == category }
    }

    func create(_ budget: Budget) {
        modelContext.insert(budget)
    }

    func delete(_ budget: Budget) {
        modelContext.delete(budget)
    }

    func save() throws {
        try modelContext.save()
    }

    func updateSpent(_ budget: Budget, amount: Decimal) throws {
        budget.spent = amount
        try save()
    }

    func totalBudgeted(for period: (month: Int, year: Int)? = nil) throws -> Decimal {
        let budgets: [Budget]

        if let period = period {
            budgets = try fetchByPeriod(month: period.month, year: period.year)
        } else {
            budgets = try fetchCurrentMonth()
        }

        return budgets.reduce(0) { $0 + $1.monthlyLimit }
    }

    func totalSpent(for period: (month: Int, year: Int)? = nil) throws -> Decimal {
        let budgets: [Budget]

        if let period = period {
            budgets = try fetchByPeriod(month: period.month, year: period.year)
        } else {
            budgets = try fetchCurrentMonth()
        }

        return budgets.reduce(0) { $0 + $1.spent }
    }

    func totalRemaining(for period: (month: Int, year: Int)? = nil) throws -> Decimal {
        try totalBudgeted(for: period) - totalSpent(for: period)
    }

    func overallProgress(for period: (month: Int, year: Int)? = nil) throws -> Double {
        let budgeted = try totalBudgeted(for: period)
        guard budgeted > 0 else { return 0 }
        let spent = try totalSpent(for: period)
        return Double(truncating: (spent / budgeted) as NSDecimalNumber)
    }

    func budgetsOverLimit() throws -> [Budget] {
        let budgets = try fetchCurrentMonth()
        return budgets.filter { $0.isOverBudget }
    }

    func budgetsNearLimit() throws -> [Budget] {
        let budgets = try fetchCurrentMonth()
        return budgets.filter { $0.isNearLimit }
    }

    func createOrUpdateForCurrentMonth(
        category: TransactionCategory,
        limit: Decimal,
        alertThreshold: Double = 0.8
    ) throws -> Budget {
        if let existing = try fetchCurrentMonthByCategory(category) {
            existing.monthlyLimit = limit
            existing.alertThreshold = alertThreshold
            try save()
            return existing
        } else {
            let budget = Budget(
                category: category,
                monthlyLimit: limit,
                alertThreshold: alertThreshold
            )
            create(budget)
            try save()
            return budget
        }
    }

    func syncWithTransactions(_ transactionRepo: TransactionRepository) throws {
        let budgets = try fetchCurrentMonth()
        let period = transactionRepo.currentMonthDateInterval()
        let spending = try transactionRepo.spendingByCategory(for: period)

        for budget in budgets {
            if let spent = spending[budget.category] {
                budget.spent = spent
            } else {
                budget.spent = 0
            }
        }

        try save()
    }

    func copyBudgetsToNextMonth() throws {
        let currentBudgets = try fetchCurrentMonth()
        let calendar = Calendar.current
        let now = Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now)!
        let month = calendar.component(.month, from: nextMonth)
        let year = calendar.component(.year, from: nextMonth)

        let existingNextMonth = try fetchByPeriod(month: month, year: year)
        guard existingNextMonth.isEmpty else { return }

        for budget in currentBudgets {
            let newBudget = Budget(
                category: budget.category,
                monthlyLimit: budget.monthlyLimit,
                periodMonth: month,
                periodYear: year,
                alertThreshold: budget.alertThreshold
            )
            create(newBudget)
        }

        try save()
    }
}
