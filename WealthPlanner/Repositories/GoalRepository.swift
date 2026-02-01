import Foundation
import SwiftData

@MainActor
final class GoalRepository: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.targetDate)])
        return try modelContext.fetch(descriptor)
    }

    func fetchActive() throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\.targetDate)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchCompleted() throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.isCompleted },
            sortBy: [SortDescriptor(\.targetDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchByType(_ type: GoalType) throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.targetDate)])
        let goals = try modelContext.fetch(descriptor)
        return goals.filter { $0.goalType == type }
    }

    func fetchById(_ id: UUID) throws -> Goal? {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchUpcoming(days: Int = 30) throws -> [Goal] {
        let futureDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { !$0.isCompleted && $0.targetDate <= futureDate },
            sortBy: [SortDescriptor(\.targetDate)]
        )
        return try modelContext.fetch(descriptor)
    }

    func create(_ goal: Goal) {
        modelContext.insert(goal)
    }

    func delete(_ goal: Goal) {
        modelContext.delete(goal)
    }

    func save() throws {
        try modelContext.save()
    }

    func markCompleted(_ goal: Goal) throws {
        goal.isCompleted = true
        try save()
    }

    func updateProgress(_ goal: Goal, amount: Decimal) throws {
        goal.currentAmount = amount
        if goal.currentAmount >= goal.targetAmount {
            goal.isCompleted = true
        }
        try save()
    }

    func totalTargetAmount() throws -> Decimal {
        let goals = try fetchActive()
        return goals.reduce(0) { $0 + $1.targetAmount }
    }

    func totalCurrentAmount() throws -> Decimal {
        let goals = try fetchActive()
        return goals.reduce(0) { $0 + $1.currentAmount }
    }

    func overallProgress() throws -> Double {
        let total = try totalTargetAmount()
        guard total > 0 else { return 0 }
        let current = try totalCurrentAmount()
        return Double(truncating: (current / total) as NSDecimalNumber)
    }

    func goalsOnTrack() throws -> Int {
        let goals = try fetchActive()
        return goals.filter { $0.isOnTrack }.count
    }

    func goalsOffTrack() throws -> Int {
        let goals = try fetchActive()
        return goals.filter { !$0.isOnTrack }.count
    }
}
