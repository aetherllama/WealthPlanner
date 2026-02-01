import Foundation
import SwiftData

enum AssetType: String, Codable, CaseIterable, Identifiable {
    case stock = "Stock"
    case bond = "Bond"
    case etf = "ETF"
    case mutualFund = "Mutual Fund"
    case crypto = "Cryptocurrency"
    case cash = "Cash"
    case option = "Option"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .stock: return "chart.bar"
        case .bond: return "doc.text"
        case .etf: return "square.grid.2x2"
        case .mutualFund: return "chart.pie"
        case .crypto: return "bitcoinsign.circle"
        case .cash: return "dollarsign.circle"
        case .option: return "arrow.left.arrow.right"
        case .other: return "questionmark.circle"
        }
    }
}

@Model
final class Holding {
    var id: UUID
    var symbol: String
    var name: String
    var quantity: Decimal
    var costBasis: Decimal
    var currentPrice: Decimal
    var assetType: AssetType
    var lastPriceUpdate: Date?
    var notes: String?

    var account: Account?

    init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        quantity: Decimal,
        costBasis: Decimal,
        currentPrice: Decimal,
        assetType: AssetType = .stock,
        notes: String? = nil
    ) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.name = name
        self.quantity = quantity
        self.costBasis = costBasis
        self.currentPrice = currentPrice
        self.assetType = assetType
        self.lastPriceUpdate = Date()
        self.notes = notes
    }

    var currentValue: Decimal {
        quantity * currentPrice
    }

    var totalCost: Decimal {
        quantity * costBasis
    }

    var gainLoss: Decimal {
        currentValue - totalCost
    }

    var gainLossPercent: Double {
        guard totalCost != 0 else { return 0 }
        return Double(truncating: (gainLoss / totalCost * 100) as NSDecimalNumber)
    }

    var isGain: Bool {
        gainLoss >= 0
    }

    var displayValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: currentValue as NSDecimalNumber) ?? "$0.00"
    }

    var displayGainLoss: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        let sign = isGain ? "+" : ""
        return sign + (formatter.string(from: gainLoss as NSDecimalNumber) ?? "$0.00")
    }

    var displayGainLossPercent: String {
        let sign = isGain ? "+" : ""
        return String(format: "%@%.2f%%", sign, gainLossPercent)
    }
}
