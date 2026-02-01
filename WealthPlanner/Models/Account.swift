import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case checking = "Checking"
    case savings = "Savings"
    case investment = "Investment"
    case crypto = "Crypto"
    case credit = "Credit Card"
    case loan = "Loan"
    case retirement = "Retirement"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .checking: return "banknote"
        case .savings: return "building.columns"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .crypto: return "bitcoinsign.circle"
        case .credit: return "creditcard"
        case .loan: return "doc.text"
        case .retirement: return "chart.pie"
        case .other: return "folder"
        }
    }

    var isAsset: Bool {
        switch self {
        case .credit, .loan:
            return false
        default:
            return true
        }
    }
}

@Model
final class Account {
    var id: UUID
    var name: String
    var institution: String
    var type: AccountType
    var balance: Decimal
    var currency: String
    var plaidItemId: String?
    var plaidAccountId: String?
    var lastSynced: Date?
    var createdAt: Date
    var isManual: Bool
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    var holdings: [Holding]

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]

    @Relationship(inverse: \Goal.linkedAccounts)
    var linkedGoals: [Goal]

    init(
        id: UUID = UUID(),
        name: String,
        institution: String = "",
        type: AccountType = .checking,
        balance: Decimal = 0,
        currency: String = "USD",
        plaidItemId: String? = nil,
        plaidAccountId: String? = nil,
        lastSynced: Date? = nil,
        isManual: Bool = true,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.institution = institution
        self.type = type
        self.balance = balance
        self.currency = currency
        self.plaidItemId = plaidItemId
        self.plaidAccountId = plaidAccountId
        self.lastSynced = lastSynced
        self.createdAt = Date()
        self.isManual = isManual
        self.notes = notes
        self.holdings = []
        self.transactions = []
        self.linkedGoals = []
    }

    var totalHoldingsValue: Decimal {
        holdings.reduce(0) { $0 + $1.currentValue }
    }

    var effectiveBalance: Decimal {
        if type == .investment || type == .retirement {
            return totalHoldingsValue
        }
        return balance
    }

    var displayBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: effectiveBalance as NSDecimalNumber) ?? "$0.00"
    }
}
