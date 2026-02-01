import Foundation
import SwiftData
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var netWorth: Decimal = 0
    @Published var totalAssets: Decimal = 0
    @Published var totalLiabilities: Decimal = 0
    @Published var accounts: [Account] = []
    @Published var recentTransactions: [Transaction] = []
    @Published var assetAllocation: [AssetType: Decimal] = [:]
    @Published var monthlyIncome: Decimal = 0
    @Published var monthlyExpenses: Decimal = 0
    @Published var isLoading = false
    @Published var error: Error?

    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() async {
        guard let modelContext = modelContext else { return }

        isLoading = true
        error = nil

        do {
            let accountRepo = AccountRepository(modelContext: modelContext)
            let transactionRepo = TransactionRepository(modelContext: modelContext)
            let holdingRepo = HoldingRepository(modelContext: modelContext)

            accounts = try accountRepo.fetchAll()
            totalAssets = try accountRepo.totalAssets()
            totalLiabilities = try accountRepo.totalLiabilities()
            netWorth = try accountRepo.netWorth()

            recentTransactions = try transactionRepo.fetchRecent(limit: 5)

            let currentMonth = transactionRepo.currentMonthDateInterval()
            monthlyIncome = try transactionRepo.totalIncome(for: currentMonth)
            monthlyExpenses = try transactionRepo.totalExpenses(for: currentMonth)

            assetAllocation = try holdingRepo.assetAllocation()

        } catch {
            self.error = error
        }

        isLoading = false
    }

    var formattedNetWorth: String {
        formatCurrency(netWorth)
    }

    var formattedAssets: String {
        formatCurrency(totalAssets)
    }

    var formattedLiabilities: String {
        formatCurrency(totalLiabilities)
    }

    var formattedMonthlyIncome: String {
        formatCurrency(monthlyIncome)
    }

    var formattedMonthlyExpenses: String {
        formatCurrency(monthlyExpenses)
    }

    var monthlySavings: Decimal {
        monthlyIncome - monthlyExpenses
    }

    var formattedMonthlySavings: String {
        formatCurrency(monthlySavings)
    }

    var savingsRate: Double {
        guard monthlyIncome > 0 else { return 0 }
        return Double(truncating: ((monthlyIncome - monthlyExpenses) / monthlyIncome * 100) as NSDecimalNumber)
    }

    var accountsByType: [AccountType: [Account]] {
        Dictionary(grouping: accounts, by: { $0.type })
    }

    var allocationChartData: [(type: AssetType, value: Double, percentage: Double)] {
        let total = assetAllocation.values.reduce(0, +)
        guard total > 0 else { return [] }

        return assetAllocation
            .map { (type: $0.key, value: Double(truncating: $0.value as NSDecimalNumber), percentage: Double(truncating: ($0.value / total * 100) as NSDecimalNumber)) }
            .sorted { $0.value > $1.value }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}
