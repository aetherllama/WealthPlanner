import Foundation
import SwiftData

@MainActor
final class HoldingRepository: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [Holding] {
        let descriptor = FetchDescriptor<Holding>(sortBy: [SortDescriptor(\.symbol)])
        return try modelContext.fetch(descriptor)
    }

    func fetchByAccount(_ account: Account) throws -> [Holding] {
        let accountId = account.id
        let descriptor = FetchDescriptor<Holding>(
            predicate: #Predicate { $0.account?.id == accountId },
            sortBy: [SortDescriptor(\.symbol)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchByAssetType(_ type: AssetType) throws -> [Holding] {
        let descriptor = FetchDescriptor<Holding>(sortBy: [SortDescriptor(\.symbol)])
        let holdings = try modelContext.fetch(descriptor)
        return holdings.filter { $0.assetType == type }
    }

    func fetchBySymbol(_ symbol: String) throws -> [Holding] {
        let upperSymbol = symbol.uppercased()
        let descriptor = FetchDescriptor<Holding>(
            predicate: #Predicate { $0.symbol == upperSymbol }
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchById(_ id: UUID) throws -> Holding? {
        let descriptor = FetchDescriptor<Holding>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func create(_ holding: Holding) {
        modelContext.insert(holding)
    }

    func delete(_ holding: Holding) {
        modelContext.delete(holding)
    }

    func save() throws {
        try modelContext.save()
    }

    func totalValue() throws -> Decimal {
        let holdings = try fetchAll()
        return holdings.reduce(0) { $0 + $1.currentValue }
    }

    func totalGainLoss() throws -> Decimal {
        let holdings = try fetchAll()
        return holdings.reduce(0) { $0 + $1.gainLoss }
    }

    func totalCost() throws -> Decimal {
        let holdings = try fetchAll()
        return holdings.reduce(0) { $0 + $1.totalCost }
    }

    func holdingsByAssetType() throws -> [AssetType: [Holding]] {
        let holdings = try fetchAll()
        return Dictionary(grouping: holdings, by: { $0.assetType })
    }

    func assetAllocation() throws -> [AssetType: Decimal] {
        let grouped = try holdingsByAssetType()
        var allocation: [AssetType: Decimal] = [:]

        for (type, holdings) in grouped {
            allocation[type] = holdings.reduce(0) { $0 + $1.currentValue }
        }

        return allocation
    }

    func uniqueSymbols() throws -> [String] {
        let holdings = try fetchAll()
        return Array(Set(holdings.map { $0.symbol })).sorted()
    }

    func aggregatedHoldings() throws -> [String: (quantity: Decimal, value: Decimal, cost: Decimal)] {
        let holdings = try fetchAll()
        var aggregated: [String: (quantity: Decimal, value: Decimal, cost: Decimal)] = [:]

        for holding in holdings {
            let symbol = holding.symbol
            if let existing = aggregated[symbol] {
                aggregated[symbol] = (
                    quantity: existing.quantity + holding.quantity,
                    value: existing.value + holding.currentValue,
                    cost: existing.cost + holding.totalCost
                )
            } else {
                aggregated[symbol] = (
                    quantity: holding.quantity,
                    value: holding.currentValue,
                    cost: holding.totalCost
                )
            }
        }

        return aggregated
    }
}
