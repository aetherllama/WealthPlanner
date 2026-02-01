import Foundation
import SwiftData

enum TransactionCategory: String, Codable, CaseIterable, Identifiable {
    case income = "Income"
    case salary = "Salary"
    case investment = "Investment"
    case transfer = "Transfer"
    case food = "Food & Dining"
    case shopping = "Shopping"
    case transportation = "Transportation"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case healthcare = "Healthcare"
    case education = "Education"
    case travel = "Travel"
    case housing = "Housing"
    case insurance = "Insurance"
    case subscriptions = "Subscriptions"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .income: return "arrow.down.circle"
        case .salary: return "briefcase"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .transfer: return "arrow.left.arrow.right"
        case .food: return "fork.knife"
        case .shopping: return "cart"
        case .transportation: return "car"
        case .utilities: return "bolt"
        case .entertainment: return "tv"
        case .healthcare: return "heart"
        case .education: return "book"
        case .travel: return "airplane"
        case .housing: return "house"
        case .insurance: return "shield"
        case .subscriptions: return "repeat"
        case .other: return "ellipsis.circle"
        }
    }

    var isExpense: Bool {
        switch self {
        case .income, .salary, .investment, .transfer:
            return false
        default:
            return true
        }
    }
}

@Model
final class Transaction {
    var id: UUID
    var date: Date
    var transactionDescription: String
    var amount: Decimal
    var category: TransactionCategory
    var merchantName: String?
    var isRecurring: Bool
    var plaidTransactionId: String?
    var notes: String?

    var account: Account?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        description: String,
        amount: Decimal,
        category: TransactionCategory = .other,
        merchantName: String? = nil,
        isRecurring: Bool = false,
        plaidTransactionId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.transactionDescription = description
        self.amount = amount
        self.category = category
        self.merchantName = merchantName
        self.isRecurring = isRecurring
        self.plaidTransactionId = plaidTransactionId
        self.notes = notes
    }

    var isExpense: Bool {
        amount < 0
    }

    var absoluteAmount: Decimal {
        abs(amount)
    }

    var displayAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
