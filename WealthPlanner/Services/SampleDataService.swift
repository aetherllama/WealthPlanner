import Foundation
import SwiftData

@MainActor
class SampleDataService {
    static let shared = SampleDataService()

    private let hasLoadedSampleDataKey = "hasLoadedSampleData"

    var hasLoadedSampleData: Bool {
        get { UserDefaults.standard.bool(forKey: hasLoadedSampleDataKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasLoadedSampleDataKey) }
    }

    func loadSampleDataIfNeeded(into modelContext: ModelContext) {
        guard !hasLoadedSampleData else { return }

        loadSampleData(into: modelContext)
        hasLoadedSampleData = true
    }

    func loadSampleData(into modelContext: ModelContext) {
        // Create sample accounts
        let checkingAccount = Account(
            name: "Primary Checking",
            institution: "Chase Bank",
            type: .checking,
            balance: 5432.18,
            lastSynced: Date()
        )

        let savingsAccount = Account(
            name: "Emergency Fund",
            institution: "Marcus by Goldman Sachs",
            type: .savings,
            balance: 15000.00,
            lastSynced: Date()
        )

        let investmentAccount = Account(
            name: "Brokerage Account",
            institution: "Fidelity",
            type: .investment,
            balance: 0, // Will be calculated from holdings
            lastSynced: Date()
        )

        let retirementAccount = Account(
            name: "401(k)",
            institution: "Vanguard",
            type: .retirement,
            balance: 0, // Will be calculated from holdings
            lastSynced: Date()
        )

        let cryptoAccount = Account(
            name: "Crypto Wallet",
            institution: "Coinbase",
            type: .crypto,
            balance: 0, // Will be calculated from holdings
            lastSynced: Date()
        )

        let creditCard = Account(
            name: "Sapphire Reserve",
            institution: "Chase",
            type: .credit,
            balance: -2156.43,
            lastSynced: Date()
        )

        // Insert accounts
        modelContext.insert(checkingAccount)
        modelContext.insert(savingsAccount)
        modelContext.insert(investmentAccount)
        modelContext.insert(retirementAccount)
        modelContext.insert(cryptoAccount)
        modelContext.insert(creditCard)

        // Create holdings for brokerage account
        let brokerageHoldings: [Holding] = [
            Holding(symbol: "AAPL", name: "Apple Inc.", quantity: 50, costBasis: 142.50, currentPrice: 178.25, assetType: .stock),
            Holding(symbol: "MSFT", name: "Microsoft Corporation", quantity: 30, costBasis: 285.00, currentPrice: 378.50, assetType: .stock),
            Holding(symbol: "GOOGL", name: "Alphabet Inc.", quantity: 20, costBasis: 98.50, currentPrice: 141.75, assetType: .stock),
            Holding(symbol: "VOO", name: "Vanguard S&P 500 ETF", quantity: 25, costBasis: 380.00, currentPrice: 425.30, assetType: .etf),
            Holding(symbol: "VTI", name: "Vanguard Total Stock Market ETF", quantity: 40, costBasis: 205.00, currentPrice: 235.80, assetType: .etf),
        ]

        for holding in brokerageHoldings {
            holding.account = investmentAccount
            modelContext.insert(holding)
        }

        // Create holdings for 401(k)
        let retirementHoldings: [Holding] = [
            Holding(symbol: "VFIAX", name: "Vanguard 500 Index Fund Admiral", quantity: 150, costBasis: 350.00, currentPrice: 425.50, assetType: .mutualFund),
            Holding(symbol: "VBTLX", name: "Vanguard Total Bond Market Index", quantity: 200, costBasis: 10.50, currentPrice: 9.85, assetType: .bond),
            Holding(symbol: "VTIAX", name: "Vanguard Total International Stock", quantity: 100, costBasis: 28.50, currentPrice: 32.15, assetType: .mutualFund),
        ]

        for holding in retirementHoldings {
            holding.account = retirementAccount
            modelContext.insert(holding)
        }

        // Create crypto holdings
        let cryptoHoldings: [Holding] = [
            Holding(symbol: "BTC", name: "Bitcoin", quantity: 0.5, costBasis: 35000.00, currentPrice: 43250.00, assetType: .crypto),
            Holding(symbol: "ETH", name: "Ethereum", quantity: 3.5, costBasis: 1800.00, currentPrice: 2350.00, assetType: .crypto),
        ]

        for holding in cryptoHoldings {
            holding.account = cryptoAccount
            modelContext.insert(holding)
        }

        // Create sample transactions for checking account
        let calendar = Calendar.current
        let today = Date()

        let checkingTransactions: [(String, Decimal, TransactionCategory, Int)] = [
            ("Direct Deposit - Salary", 4500.00, .salary, -1),
            ("Whole Foods Market", -87.43, .food, -2),
            ("Chevron Gas Station", -52.18, .transportation, -3),
            ("Netflix Subscription", -15.99, .subscriptions, -4),
            ("Amazon.com", -156.78, .shopping, -5),
            ("Uber Eats", -34.50, .food, -6),
            ("Electric Bill - PG&E", -125.00, .utilities, -7),
            ("Spotify Premium", -9.99, .subscriptions, -8),
            ("Target", -89.23, .shopping, -10),
            ("Starbucks", -7.85, .food, -11),
            ("Transfer to Savings", -500.00, .transfer, -12),
            ("Direct Deposit - Salary", 4500.00, .salary, -15),
            ("Costco", -234.56, .shopping, -16),
            ("CVS Pharmacy", -28.99, .healthcare, -18),
            ("Restaurant - Dinner", -78.50, .food, -20),
        ]

        for (description, amount, category, daysAgo) in checkingTransactions {
            if let date = calendar.date(byAdding: .day, value: daysAgo, to: today) {
                let transaction = Transaction(
                    date: date,
                    description: description,
                    amount: amount,
                    category: category
                )
                transaction.account = checkingAccount
                modelContext.insert(transaction)
            }
        }

        // Create sample transactions for credit card
        let creditTransactions: [(String, Decimal, TransactionCategory, Int)] = [
            ("Apple Store", -999.00, .shopping, -1),
            ("Uber Rides", -45.67, .transportation, -2),
            ("DoorDash", -42.30, .food, -3),
            ("HBO Max", -15.99, .subscriptions, -5),
            ("Airlines - Flight", -387.00, .travel, -8),
            ("Hotel Booking", -245.00, .travel, -8),
            ("Amazon Prime", -14.99, .subscriptions, -10),
            ("Gym Membership", -49.99, .healthcare, -12),
            ("Gas Station", -48.50, .transportation, -14),
        ]

        for (description, amount, category, daysAgo) in creditTransactions {
            if let date = calendar.date(byAdding: .day, value: daysAgo, to: today) {
                let transaction = Transaction(
                    date: date,
                    description: description,
                    amount: amount,
                    category: category
                )
                transaction.account = creditCard
                modelContext.insert(transaction)
            }
        }

        // Create sample budgets
        let budgets: [(TransactionCategory, Decimal, Double)] = [
            (.food, 600, 0.8),
            (.shopping, 400, 0.8),
            (.transportation, 300, 0.8),
            (.entertainment, 200, 0.8),
            (.utilities, 250, 0.8),
            (.subscriptions, 100, 0.8),
        ]

        for (category, limit, threshold) in budgets {
            let budget = Budget(
                category: category,
                monthlyLimit: limit,
                alertThreshold: threshold
            )
            modelContext.insert(budget)
        }

        // Create sample goals
        let emergencyGoal = Goal(
            name: "Emergency Fund",
            goalType: .emergency,
            targetAmount: 30000,
            currentAmount: 15000,
            targetDate: calendar.date(byAdding: .month, value: 12, to: today)!
        )
        emergencyGoal.linkedAccounts.append(savingsAccount)
        modelContext.insert(emergencyGoal)

        let vacationGoal = Goal(
            name: "Hawaii Vacation",
            goalType: .vacation,
            targetAmount: 5000,
            currentAmount: 1250,
            targetDate: calendar.date(byAdding: .month, value: 8, to: today)!
        )
        modelContext.insert(vacationGoal)

        let houseGoal = Goal(
            name: "House Down Payment",
            goalType: .home,
            targetAmount: 80000,
            currentAmount: 22500,
            targetDate: calendar.date(byAdding: .year, value: 3, to: today)!
        )
        modelContext.insert(houseGoal)

        // Save all data
        try? modelContext.save()
    }

    func resetSampleData() {
        hasLoadedSampleData = false
    }
}
