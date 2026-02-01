import Foundation
import SwiftData

@MainActor
final class AccountRepository: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor)
    }

    func fetchByType(_ type: AccountType) throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)])
        let accounts = try modelContext.fetch(descriptor)
        return accounts.filter { $0.type == type }
    }

    func fetchAssets() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)])
        let accounts = try modelContext.fetch(descriptor)
        return accounts.filter { $0.type.isAsset }
    }

    func fetchLiabilities() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)])
        let accounts = try modelContext.fetch(descriptor)
        return accounts.filter { !$0.type.isAsset }
    }

    func fetchById(_ id: UUID) throws -> Account? {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchByPlaidItemId(_ itemId: String) throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.plaidItemId == itemId }
        )
        return try modelContext.fetch(descriptor)
    }

    func create(_ account: Account) {
        modelContext.insert(account)
    }

    func delete(_ account: Account) {
        modelContext.delete(account)
    }

    func save() throws {
        try modelContext.save()
    }

    func totalAssets() throws -> Decimal {
        let accounts = try fetchAssets()
        return accounts.reduce(0) { $0 + $1.effectiveBalance }
    }

    func totalLiabilities() throws -> Decimal {
        let accounts = try fetchLiabilities()
        return accounts.reduce(0) { $0 + abs($1.effectiveBalance) }
    }

    func netWorth() throws -> Decimal {
        try totalAssets() - totalLiabilities()
    }

    func accountsByInstitution() throws -> [String: [Account]] {
        let accounts = try fetchAll()
        return Dictionary(grouping: accounts, by: { $0.institution })
    }
}
