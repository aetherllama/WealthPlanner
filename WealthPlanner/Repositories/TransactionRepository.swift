import Foundation
import SwiftData

@MainActor
final class TransactionRepository: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return try modelContext.fetch(descriptor)
    }

    func fetchByAccount(_ account: Account) throws -> [Transaction] {
        let accountId = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account?.id == accountId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchByCategory(_ category: TransactionCategory) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let transactions = try modelContext.fetch(descriptor)
        return transactions.filter { $0.category == category }
    }

    func fetchByDateRange(start: Date, end: Date) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchRecent(limit: Int = 10) throws -> [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    func fetchById(_ id: UUID) throws -> Transaction? {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func create(_ transaction: Transaction) {
        modelContext.insert(transaction)
    }

    func delete(_ transaction: Transaction) {
        modelContext.delete(transaction)
    }

    func save() throws {
        try modelContext.save()
    }

    func totalIncome(for period: DateInterval? = nil) throws -> Decimal {
        let transactions: [Transaction]

        if let period = period {
            transactions = try fetchByDateRange(start: period.start, end: period.end)
        } else {
            transactions = try fetchAll()
        }

        return transactions
            .filter { $0.amount > 0 }
            .reduce(0) { $0 + $1.amount }
    }

    func totalExpenses(for period: DateInterval? = nil) throws -> Decimal {
        let transactions: [Transaction]

        if let period = period {
            transactions = try fetchByDateRange(start: period.start, end: period.end)
        } else {
            transactions = try fetchAll()
        }

        return transactions
            .filter { $0.amount < 0 }
            .reduce(0) { $0 + abs($1.amount) }
    }

    func spendingByCategory(for period: DateInterval? = nil) throws -> [TransactionCategory: Decimal] {
        let transactions: [Transaction]

        if let period = period {
            transactions = try fetchByDateRange(start: period.start, end: period.end)
        } else {
            transactions = try fetchAll()
        }

        let expenses = transactions.filter { $0.amount < 0 }
        var spending: [TransactionCategory: Decimal] = [:]

        for transaction in expenses {
            let category = transaction.category
            spending[category, default: 0] += abs(transaction.amount)
        }

        return spending
    }

    func currentMonthDateInterval() -> DateInterval {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        return DateInterval(start: startOfMonth, end: endOfMonth)
    }

    func previousMonthDateInterval() -> DateInterval {
        let calendar = Calendar.current
        let now = Date()
        let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let startOfPreviousMonth = calendar.date(byAdding: .month, value: -1, to: startOfCurrentMonth)!
        let endOfPreviousMonth = calendar.date(byAdding: .day, value: -1, to: startOfCurrentMonth)!
        return DateInterval(start: startOfPreviousMonth, end: endOfPreviousMonth)
    }

    func searchTransactions(query: String) throws -> [Transaction] {
        let lowercaseQuery = query.lowercased()
        let transactions = try fetchAll()

        return transactions.filter { transaction in
            transaction.transactionDescription.lowercased().contains(lowercaseQuery) ||
            transaction.merchantName?.lowercased().contains(lowercaseQuery) == true ||
            transaction.category.rawValue.lowercased().contains(lowercaseQuery)
        }
    }
}
