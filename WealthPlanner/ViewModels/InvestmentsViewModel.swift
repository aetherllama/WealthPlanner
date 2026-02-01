import Foundation
import SwiftData

@MainActor
final class InvestmentsViewModel: ObservableObject {
    @Published var holdings: [Holding] = []
    @Published var selectedHolding: Holding?
    @Published var isLoading = false
    @Published var isRefreshingPrices = false
    @Published var error: Error?
    @Published var searchText = ""

    private var modelContext: ModelContext?
    private let priceService = PriceService.shared

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() async {
        guard let modelContext = modelContext else { return }

        isLoading = true
        error = nil

        do {
            let repo = HoldingRepository(modelContext: modelContext)
            holdings = try repo.fetchAll()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func refreshPrices() async {
        guard !holdings.isEmpty else { return }

        isRefreshingPrices = true

        do {
            try await priceService.refreshPrices(for: holdings)

            if let modelContext = modelContext {
                try modelContext.save()
            }
        } catch {
            self.error = error
        }

        isRefreshingPrices = false
    }

    func createHolding(
        symbol: String,
        name: String,
        quantity: Decimal,
        costBasis: Decimal,
        assetType: AssetType,
        account: Account
    ) async throws {
        guard let modelContext = modelContext else { return }

        var currentPrice = costBasis

        do {
            if assetType == .crypto {
                let quote = try await priceService.getCryptoQuote(for: symbol)
                currentPrice = quote.price
            } else if assetType != .cash {
                let quote = try await priceService.getQuote(for: symbol)
                currentPrice = quote.price
            }
        } catch {
            // Use cost basis if price fetch fails
        }

        let holding = Holding(
            symbol: symbol,
            name: name,
            quantity: quantity,
            costBasis: costBasis,
            currentPrice: currentPrice,
            assetType: assetType
        )

        holding.account = account
        modelContext.insert(holding)
        try modelContext.save()

        await refresh()
    }

    func deleteHolding(_ holding: Holding) async throws {
        guard let modelContext = modelContext else { return }

        let repo = HoldingRepository(modelContext: modelContext)
        repo.delete(holding)
        try repo.save()

        await refresh()
    }

    func updateHolding(_ holding: Holding) async throws {
        guard let modelContext = modelContext else { return }

        try modelContext.save()
        await refresh()
    }

    var filteredHoldings: [Holding] {
        if searchText.isEmpty {
            return holdings
        }
        return holdings.filter {
            $0.symbol.localizedCaseInsensitiveContains(searchText) ||
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var holdingsByAssetType: [AssetType: [Holding]] {
        Dictionary(grouping: filteredHoldings, by: { $0.assetType })
    }

    var totalValue: Decimal {
        holdings.reduce(0) { $0 + $1.currentValue }
    }

    var totalCost: Decimal {
        holdings.reduce(0) { $0 + $1.totalCost }
    }

    var totalGainLoss: Decimal {
        holdings.reduce(0) { $0 + $1.gainLoss }
    }

    var totalGainLossPercent: Double {
        guard totalCost > 0 else { return 0 }
        return Double(truncating: (totalGainLoss / totalCost * 100) as NSDecimalNumber)
    }

    var formattedTotalValue: String {
        formatCurrency(totalValue)
    }

    var formattedTotalGainLoss: String {
        let sign = totalGainLoss >= 0 ? "+" : ""
        return sign + formatCurrency(totalGainLoss)
    }

    var formattedTotalGainLossPercent: String {
        let sign = totalGainLoss >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", sign, totalGainLossPercent)
    }

    var allocationData: [(type: AssetType, value: Double, percentage: Double)] {
        let total = totalValue
        guard total > 0 else { return [] }

        var allocation: [AssetType: Decimal] = [:]

        for holding in holdings {
            allocation[holding.assetType, default: 0] += holding.currentValue
        }

        return allocation
            .map { (type: $0.key, value: Double(truncating: $0.value as NSDecimalNumber), percentage: Double(truncating: ($0.value / total * 100) as NSDecimalNumber)) }
            .sorted { $0.value > $1.value }
    }

    var topHoldings: [Holding] {
        Array(holdings.sorted { $0.currentValue > $1.currentValue }.prefix(5))
    }

    var topGainers: [Holding] {
        Array(holdings.sorted { $0.gainLossPercent > $1.gainLossPercent }.prefix(5))
    }

    var topLosers: [Holding] {
        Array(holdings.sorted { $0.gainLossPercent < $1.gainLossPercent }.prefix(5))
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}
