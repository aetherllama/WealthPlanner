import Foundation
import SwiftData

@MainActor
final class GoalsViewModel: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var selectedGoal: Goal?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var showCompletedGoals = false

    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() async {
        guard let modelContext = modelContext else { return }

        isLoading = true
        error = nil

        do {
            let repo = GoalRepository(modelContext: modelContext)

            if showCompletedGoals {
                goals = try repo.fetchAll()
            } else {
                goals = try repo.fetchActive()
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func createGoal(
        name: String,
        description: String?,
        goalType: GoalType,
        targetAmount: Decimal,
        currentAmount: Decimal,
        targetDate: Date,
        monthlyContribution: Decimal?
    ) async throws {
        guard let modelContext = modelContext else { return }

        let goal = Goal(
            name: name,
            description: description,
            goalType: goalType,
            targetAmount: targetAmount,
            currentAmount: currentAmount,
            targetDate: targetDate,
            monthlyContribution: monthlyContribution
        )

        let repo = GoalRepository(modelContext: modelContext)
        repo.create(goal)
        try repo.save()

        await refresh()
    }

    func deleteGoal(_ goal: Goal) async throws {
        guard let modelContext = modelContext else { return }

        let repo = GoalRepository(modelContext: modelContext)
        repo.delete(goal)
        try repo.save()

        await refresh()
    }

    func updateGoal(_ goal: Goal) async throws {
        guard let modelContext = modelContext else { return }

        let repo = GoalRepository(modelContext: modelContext)
        try repo.save()

        await refresh()
    }

    func markGoalCompleted(_ goal: Goal) async throws {
        guard let modelContext = modelContext else { return }

        let repo = GoalRepository(modelContext: modelContext)
        try repo.markCompleted(goal)

        await refresh()
    }

    func updateGoalProgress(_ goal: Goal, amount: Decimal) async throws {
        guard let modelContext = modelContext else { return }

        let repo = GoalRepository(modelContext: modelContext)
        try repo.updateProgress(goal, amount: amount)

        await refresh()
    }

    var activeGoals: [Goal] {
        goals.filter { !$0.isCompleted }
    }

    var completedGoals: [Goal] {
        goals.filter { $0.isCompleted }
    }

    var goalsOnTrack: [Goal] {
        activeGoals.filter { $0.isOnTrack }
    }

    var goalsOffTrack: [Goal] {
        activeGoals.filter { !$0.isOnTrack }
    }

    var upcomingGoals: [Goal] {
        activeGoals.filter { $0.daysRemaining <= 30 }
    }

    var totalTargetAmount: Decimal {
        activeGoals.reduce(0) { $0 + $1.targetAmount }
    }

    var totalCurrentAmount: Decimal {
        activeGoals.reduce(0) { $0 + $1.currentAmount }
    }

    var overallProgress: Double {
        guard totalTargetAmount > 0 else { return 0 }
        return Double(truncating: (totalCurrentAmount / totalTargetAmount) as NSDecimalNumber)
    }

    var formattedTotalTarget: String {
        formatCurrency(totalTargetAmount)
    }

    var formattedTotalCurrent: String {
        formatCurrency(totalCurrentAmount)
    }

    var formattedTotalRemaining: String {
        formatCurrency(totalTargetAmount - totalCurrentAmount)
    }

    var goalsByType: [GoalType: [Goal]] {
        Dictionary(grouping: activeGoals, by: { $0.goalType })
    }

    func calculateRetirement(
        currentAge: Int,
        retirementAge: Int,
        currentSavings: Decimal,
        monthlyContribution: Decimal,
        expectedReturn: Double,
        inflationRate: Double
    ) -> RetirementProjection {
        let yearsToRetirement = retirementAge - currentAge
        let monthsToRetirement = yearsToRetirement * 12

        let monthlyReturn = expectedReturn / 12 / 100
        let monthlyInflation = inflationRate / 12 / 100

        var futureValue = Double(truncating: currentSavings as NSDecimalNumber)
        let monthlyContrib = Double(truncating: monthlyContribution as NSDecimalNumber)

        for _ in 0..<monthsToRetirement {
            futureValue = futureValue * (1 + monthlyReturn) + monthlyContrib
        }

        let realReturn = (1 + expectedReturn / 100) / (1 + inflationRate / 100) - 1
        let presentValue = futureValue / pow(1 + inflationRate / 100, Double(yearsToRetirement))

        let safeWithdrawalRate = 0.04
        let annualIncome = futureValue * safeWithdrawalRate
        let monthlyIncome = annualIncome / 12

        return RetirementProjection(
            futureValue: Decimal(futureValue),
            presentValue: Decimal(presentValue),
            yearsToRetirement: yearsToRetirement,
            projectedMonthlyIncome: Decimal(monthlyIncome),
            totalContributions: monthlyContribution * Decimal(monthsToRetirement) + currentSavings
        )
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

struct RetirementProjection {
    let futureValue: Decimal
    let presentValue: Decimal
    let yearsToRetirement: Int
    let projectedMonthlyIncome: Decimal
    let totalContributions: Decimal

    var formattedFutureValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: futureValue as NSDecimalNumber) ?? "$0.00"
    }

    var formattedPresentValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: presentValue as NSDecimalNumber) ?? "$0.00"
    }

    var formattedMonthlyIncome: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: projectedMonthlyIncome as NSDecimalNumber) ?? "$0.00"
    }
}
