import Foundation
import SwiftData

enum GoalType: String, Codable, CaseIterable, Identifiable {
    case savings = "Savings"
    case retirement = "Retirement"
    case emergency = "Emergency Fund"
    case home = "Home Purchase"
    case education = "Education"
    case vacation = "Vacation"
    case car = "Vehicle"
    case debtPayoff = "Debt Payoff"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .savings: return "banknote"
        case .retirement: return "sunset"
        case .emergency: return "cross.circle"
        case .home: return "house"
        case .education: return "graduationcap"
        case .vacation: return "airplane"
        case .car: return "car"
        case .debtPayoff: return "creditcard"
        case .other: return "flag"
        }
    }
}

@Model
final class Goal {
    var id: UUID
    var name: String
    var goalDescription: String?
    var goalType: GoalType
    var targetAmount: Decimal
    var currentAmount: Decimal
    var targetDate: Date
    var createdAt: Date
    var monthlyContribution: Decimal?
    var isCompleted: Bool
    var notes: String?

    var linkedAccounts: [Account]

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        goalType: GoalType = .savings,
        targetAmount: Decimal,
        currentAmount: Decimal = 0,
        targetDate: Date,
        monthlyContribution: Decimal? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.goalDescription = description
        self.goalType = goalType
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.createdAt = Date()
        self.monthlyContribution = monthlyContribution
        self.isCompleted = false
        self.notes = notes
        self.linkedAccounts = []
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(Double(truncating: (currentAmount / targetAmount) as NSDecimalNumber), 1.0)
    }

    var progressPercent: Double {
        progress * 100
    }

    var remainingAmount: Decimal {
        max(targetAmount - currentAmount, 0)
    }

    var daysRemaining: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
        return max(days, 0)
    }

    var monthsRemaining: Int {
        let calendar = Calendar.current
        let months = calendar.dateComponents([.month], from: Date(), to: targetDate).month ?? 0
        return max(months, 0)
    }

    var requiredMonthlyContribution: Decimal {
        guard monthsRemaining > 0 else { return remainingAmount }
        return remainingAmount / Decimal(monthsRemaining)
    }

    var isOnTrack: Bool {
        guard let monthly = monthlyContribution else { return progress >= expectedProgress }
        return monthly >= requiredMonthlyContribution
    }

    var expectedProgress: Double {
        let calendar = Calendar.current
        let totalDays = calendar.dateComponents([.day], from: createdAt, to: targetDate).day ?? 1
        let elapsedDays = calendar.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
        guard totalDays > 0 else { return 1.0 }
        return Double(elapsedDays) / Double(totalDays)
    }

    var displayTargetAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: targetAmount as NSDecimalNumber) ?? "$0.00"
    }

    var displayCurrentAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: currentAmount as NSDecimalNumber) ?? "$0.00"
    }

    var displayTargetDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: targetDate)
    }
}
