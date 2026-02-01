import Foundation
import SwiftData

/// Service to sync data from Plaid-connected financial institutions
@MainActor
final class PlaidSyncService: ObservableObject {
    static let shared = PlaidSyncService()

    @Published var isSyncing = false
    @Published var syncProgress: Double = 0
    @Published var syncStatus = ""
    @Published var lastSyncError: Error?

    private let plaidService = PlaidService.shared
    private let keychain = KeychainManager.shared

    private init() {}

    /// Sync all connected accounts
    func syncAllAccounts(modelContext: ModelContext) async throws -> SyncResult {
        let itemIds = keychain.getAllPlaidItemIds()

        guard !itemIds.isEmpty else {
            return SyncResult(accountsSynced: 0, transactionsSynced: 0, holdingsSynced: 0, errors: ["No connected accounts"])
        }

        isSyncing = true
        syncProgress = 0
        lastSyncError = nil

        defer {
            isSyncing = false
            syncProgress = 1.0
            syncStatus = ""
        }

        var totalAccountsSynced = 0
        var totalTransactionsSynced = 0
        var totalHoldingsSynced = 0
        var errors: [String] = []

        for (index, itemId) in itemIds.enumerated() {
            do {
                let result = try await syncItem(itemId: itemId, modelContext: modelContext)
                totalAccountsSynced += result.accountsSynced
                totalTransactionsSynced += result.transactionsSynced
                totalHoldingsSynced += result.holdingsSynced
                errors.append(contentsOf: result.errors)
            } catch {
                errors.append("Failed to sync item: \(error.localizedDescription)")
            }

            syncProgress = Double(index + 1) / Double(itemIds.count)
        }

        return SyncResult(
            accountsSynced: totalAccountsSynced,
            transactionsSynced: totalTransactionsSynced,
            holdingsSynced: totalHoldingsSynced,
            errors: errors
        )
    }

    /// Sync a specific Plaid item (linked institution)
    func syncItem(itemId: String, modelContext: ModelContext) async throws -> SyncResult {
        var accountsSynced = 0
        var transactionsSynced = 0
        var holdingsSynced = 0
        var errors: [String] = []

        syncStatus = "Fetching accounts..."

        // Get accounts from Plaid
        let plaidAccounts = try await plaidService.getAccounts(itemId: itemId)

        for plaidAccount in plaidAccounts {
            // Find or create account in local database
            let account = try await findOrCreateAccount(
                plaidAccount: plaidAccount,
                itemId: itemId,
                modelContext: modelContext
            )
            accountsSynced += 1

            // Update balance
            account.balance = Decimal(plaidAccount.balances.current ?? 0)
            account.lastSynced = Date()
        }

        syncStatus = "Fetching transactions..."

        // Get transactions for the last 30 days
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!

        do {
            let plaidTransactions = try await plaidService.getTransactions(
                itemId: itemId,
                startDate: startDate,
                endDate: endDate
            )

            for plaidTransaction in plaidTransactions where !plaidTransaction.pending {
                let imported = try await importTransaction(
                    plaidTransaction: plaidTransaction,
                    itemId: itemId,
                    modelContext: modelContext
                )
                if imported {
                    transactionsSynced += 1
                }
            }
        } catch {
            errors.append("Failed to sync transactions: \(error.localizedDescription)")
        }

        syncStatus = "Fetching holdings..."

        // Get investment holdings if available
        do {
            let (holdings, securities) = try await plaidService.getHoldings(itemId: itemId)

            let securityMap = Dictionary(uniqueKeysWithValues: securities.map { ($0.securityId, $0) })

            for plaidHolding in holdings {
                let imported = try await importHolding(
                    plaidHolding: plaidHolding,
                    security: securityMap[plaidHolding.securityId],
                    itemId: itemId,
                    modelContext: modelContext
                )
                if imported {
                    holdingsSynced += 1
                }
            }
        } catch {
            // Investment holdings may not be available for all accounts
            if !error.localizedDescription.contains("PRODUCTS_NOT_SUPPORTED") {
                errors.append("Failed to sync holdings: \(error.localizedDescription)")
            }
        }

        try modelContext.save()

        return SyncResult(
            accountsSynced: accountsSynced,
            transactionsSynced: transactionsSynced,
            holdingsSynced: holdingsSynced,
            errors: errors
        )
    }

    private func findOrCreateAccount(
        plaidAccount: PlaidAccount,
        itemId: String,
        modelContext: ModelContext
    ) async throws -> Account {
        // Try to find existing account by Plaid account ID
        let descriptor = FetchDescriptor<Account>()
        let accounts = try modelContext.fetch(descriptor)

        if let existing = accounts.first(where: { $0.plaidAccountId == plaidAccount.accountId }) {
            return existing
        }

        // Create new account
        let accountType = plaidService.mapAccountType(plaidAccount.type, subtype: plaidAccount.subtype)

        let account = Account(
            name: plaidAccount.officialName ?? plaidAccount.name,
            institution: "Connected Bank",
            type: accountType,
            balance: Decimal(plaidAccount.balances.current ?? 0),
            currency: plaidAccount.balances.isoCurrencyCode ?? "USD",
            plaidItemId: itemId,
            plaidAccountId: plaidAccount.accountId,
            lastSynced: Date(),
            isManual: false
        )

        modelContext.insert(account)
        return account
    }

    private func importTransaction(
        plaidTransaction: PlaidTransaction,
        itemId: String,
        modelContext: ModelContext
    ) async throws -> Bool {
        // Check if transaction already exists
        let descriptor = FetchDescriptor<Transaction>()
        let transactions = try modelContext.fetch(descriptor)

        if transactions.contains(where: { $0.plaidTransactionId == plaidTransaction.transactionId }) {
            return false // Already imported
        }

        // Find the account
        let accountDescriptor = FetchDescriptor<Account>()
        let accounts = try modelContext.fetch(accountDescriptor)

        guard let account = accounts.first(where: { $0.plaidAccountId == plaidTransaction.accountId }) else {
            return false
        }

        // Parse date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = dateFormatter.date(from: plaidTransaction.date) else {
            return false
        }

        // Map category
        let category = mapPlaidCategory(plaidTransaction.category)

        let transaction = Transaction(
            date: date,
            description: plaidTransaction.merchantName ?? plaidTransaction.name,
            amount: Decimal(-plaidTransaction.amount), // Plaid uses positive for debits
            category: category,
            merchantName: plaidTransaction.merchantName,
            plaidTransactionId: plaidTransaction.transactionId
        )

        transaction.account = account
        modelContext.insert(transaction)

        return true
    }

    private func importHolding(
        plaidHolding: PlaidHolding,
        security: PlaidSecurity?,
        itemId: String,
        modelContext: ModelContext
    ) async throws -> Bool {
        // Find the account
        let accountDescriptor = FetchDescriptor<Account>()
        let accounts = try modelContext.fetch(accountDescriptor)

        guard let account = accounts.first(where: { $0.plaidAccountId == plaidHolding.accountId }) else {
            return false
        }

        let symbol = security?.tickerSymbol ?? "UNKNOWN"
        let name = security?.name ?? symbol

        // Check if holding already exists for this account and symbol
        if let existingHolding = account.holdings.first(where: { $0.symbol == symbol }) {
            // Update existing holding
            existingHolding.quantity = Decimal(plaidHolding.quantity)
            existingHolding.currentPrice = Decimal(plaidHolding.institutionPrice)
            if let costBasis = plaidHolding.costBasis {
                existingHolding.costBasis = Decimal(costBasis) / Decimal(plaidHolding.quantity)
            }
            existingHolding.lastPriceUpdate = Date()
            return false // Not a new holding
        }

        // Create new holding
        let assetType = plaidService.mapAssetType(security?.type)
        let costBasis = plaidHolding.costBasis.map { Decimal($0) / Decimal(plaidHolding.quantity) } ?? Decimal(plaidHolding.institutionPrice)

        let holding = Holding(
            symbol: symbol,
            name: name,
            quantity: Decimal(plaidHolding.quantity),
            costBasis: costBasis,
            currentPrice: Decimal(plaidHolding.institutionPrice),
            assetType: assetType
        )

        holding.account = account
        modelContext.insert(holding)

        return true
    }

    private func mapPlaidCategory(_ categories: [String]?) -> TransactionCategory {
        guard let categories = categories, let primary = categories.first?.lowercased() else {
            return .other
        }

        switch primary {
        case "food and drink":
            return .food
        case "shops":
            return .shopping
        case "travel":
            return .travel
        case "transfer":
            return .transfer
        case "payment":
            return .other
        case "recreation":
            return .entertainment
        case "service":
            return .other
        case "community":
            return .other
        case "healthcare":
            return .healthcare
        case "bank fees":
            return .other
        default:
            if primary.contains("income") || primary.contains("payroll") {
                return .salary
            } else if primary.contains("food") || primary.contains("restaurant") {
                return .food
            } else if primary.contains("transport") || primary.contains("gas") {
                return .transportation
            } else if primary.contains("utilities") {
                return .utilities
            }
            return .other
        }
    }
}

struct SyncResult {
    let accountsSynced: Int
    let transactionsSynced: Int
    let holdingsSynced: Int
    let errors: [String]

    var hasErrors: Bool {
        !errors.isEmpty
    }

    var summary: String {
        var parts: [String] = []
        if accountsSynced > 0 {
            parts.append("\(accountsSynced) account(s)")
        }
        if transactionsSynced > 0 {
            parts.append("\(transactionsSynced) transaction(s)")
        }
        if holdingsSynced > 0 {
            parts.append("\(holdingsSynced) holding(s)")
        }
        return parts.isEmpty ? "No new data" : "Synced: " + parts.joined(separator: ", ")
    }
}
