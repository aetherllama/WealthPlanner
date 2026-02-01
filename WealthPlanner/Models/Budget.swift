import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID
    var category: TransactionCategory
    var monthlyLimit: Decimal
    var spent: Decimal
    var periodMonth: Int
    var periodYear: Int
    var createdAt: Date
    var alertThreshold: Double
    var notes: String?

    init(
        id: UUID = UUID(),
        category: TransactionCategory,
        monthlyLimit: Decimal,
        spent: Decimal = 0,
        periodMonth: Int? = nil,
        periodYear: Int? = nil,
        alertThreshold: Double = 0.8,
        notes: String? = nil
    ) {
        self.id = id
        self.category = category
        self.monthlyLimit = monthlyLimit
        self.spent = spent

        let calendar = Calendar.current
        let now = Date()
        self.periodMonth = periodMonth ?? calendar.component(.month, from: now)
        self.periodYear = periodYear ?? calendar.component(.year, from: now)
        self.createdAt = Date()
        self.alertThreshold = alertThreshold
        self.notes = notes
    }

    var remaining: Decimal {
        monthlyLimit - spent
    }

    var progress: Double {
        guard monthlyLimit > 0 else { return 0 }
        return min(Double(truncating: (spent / monthlyLimit) as NSDecimalNumber), 1.0)
    }

    var progressPercent: Double {
        progress * 100
    }

    var isOverBudget: Bool {
        spent > monthlyLimit
    }

    var isNearLimit: Bool {
        progress >= alertThreshold && !isOverBudget
    }

    var status: BudgetStatus {
        if isOverBudget {
            return .overBudget
        } else if isNearLimit {
            return .nearLimit
        } else {
            return .onTrack
        }
    }

    var periodDate: Date {
        var components = DateComponents()
        components.year = periodYear
        components.month = periodMonth
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }

    var displayPeriod: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: periodDate)
    }

    var displayLimit: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: monthlyLimit as NSDecimalNumber) ?? "$0.00"
    }

    var displaySpent: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: spent as NSDecimalNumber) ?? "$0.00"
    }

    var displayRemaining: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: remaining as NSDecimalNumber) ?? "$0.00"
    }
}

enum BudgetStatus: String {
    case onTrack = "On Track"
    case nearLimit = "Near Limit"
    case overBudget = "Over Budget"

    var color: String {
        switch self {
        case .onTrack: return "green"
        case .nearLimit: return "orange"
        case .overBudget: return "red"
        }
    }
}
