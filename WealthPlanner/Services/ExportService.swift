import Foundation
import SwiftData
import UniformTypeIdentifiers
import PDFKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case pdf = "PDF"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .pdf: return "pdf"
        }
    }

    var utType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .pdf: return .pdf
        }
    }

    var mimeType: String {
        switch self {
        case .csv: return "text/csv"
        case .json: return "application/json"
        case .pdf: return "application/pdf"
        }
    }
}

enum ExportDataType: String, CaseIterable, Identifiable {
    case transactions = "Transactions"
    case holdings = "Holdings"
    case accounts = "Accounts"
    case fullBackup = "Full Backup"

    var id: String { rawValue }
}

struct ExportOptions {
    var format: ExportFormat = .csv
    var dataType: ExportDataType = .transactions
    var startDate: Date?
    var endDate: Date?
    var selectedAccounts: [Account] = []
    var includeHiddenAccounts: Bool = false
}

@MainActor
final class ExportService: ObservableObject {
    static let shared = ExportService()

    @Published var isExporting = false
    @Published var progress: Double = 0

    private let csvParser = CSVParser.shared

    private init() {}

    func export(
        modelContext: ModelContext,
        options: ExportOptions
    ) async throws -> (data: Data, filename: String) {
        isExporting = true
        progress = 0

        defer {
            isExporting = false
            progress = 1.0
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let filename: String
        let data: Data

        switch options.dataType {
        case .transactions:
            filename = "transactions_\(dateString).\(options.format.fileExtension)"
            data = try await exportTransactions(modelContext: modelContext, options: options)

        case .holdings:
            filename = "holdings_\(dateString).\(options.format.fileExtension)"
            data = try await exportHoldings(modelContext: modelContext, options: options)

        case .accounts:
            filename = "accounts_\(dateString).\(options.format.fileExtension)"
            data = try await exportAccounts(modelContext: modelContext, options: options)

        case .fullBackup:
            filename = "wealthplanner_backup_\(dateString).\(options.format.fileExtension)"
            data = try await exportFullBackup(modelContext: modelContext, options: options)
        }

        return (data, filename)
    }

    private func exportTransactions(
        modelContext: ModelContext,
        options: ExportOptions
    ) async throws -> Data {
        progress = 0.2

        var descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])

        let transactions = try modelContext.fetch(descriptor)

        var filtered = transactions

        if let startDate = options.startDate {
            filtered = filtered.filter { $0.date >= startDate }
        }

        if let endDate = options.endDate {
            filtered = filtered.filter { $0.date <= endDate }
        }

        if !options.selectedAccounts.isEmpty {
            let accountIds = Set(options.selectedAccounts.map { $0.id })
            filtered = filtered.filter { transaction in
                guard let accountId = transaction.account?.id else { return false }
                return accountIds.contains(accountId)
            }
        }

        progress = 0.5

        switch options.format {
        case .csv:
            let csv = csvParser.exportTransactions(filtered)
            return csv.data(using: .utf8) ?? Data()

        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let exportData = filtered.map { transaction in
                TransactionExport(
                    date: transaction.date,
                    description: transaction.transactionDescription,
                    amount: Double(truncating: transaction.amount as NSDecimalNumber),
                    category: transaction.category.rawValue,
                    accountName: transaction.account?.name
                )
            }

            return try encoder.encode(exportData)

        case .pdf:
            return try generateTransactionsPDF(filtered)
        }
    }

    private func exportHoldings(
        modelContext: ModelContext,
        options: ExportOptions
    ) async throws -> Data {
        progress = 0.2

        let descriptor = FetchDescriptor<Holding>()
        let holdings = try modelContext.fetch(descriptor)

        var filtered = holdings

        if !options.selectedAccounts.isEmpty {
            let accountIds = Set(options.selectedAccounts.map { $0.id })
            filtered = filtered.filter { holding in
                guard let accountId = holding.account?.id else { return false }
                return accountIds.contains(accountId)
            }
        }

        progress = 0.5

        switch options.format {
        case .csv:
            let csv = csvParser.exportHoldings(filtered)
            return csv.data(using: .utf8) ?? Data()

        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let exportData = filtered.map { holding in
                HoldingExport(
                    symbol: holding.symbol,
                    name: holding.name,
                    quantity: Double(truncating: holding.quantity as NSDecimalNumber),
                    costBasis: Double(truncating: holding.costBasis as NSDecimalNumber),
                    currentPrice: Double(truncating: holding.currentPrice as NSDecimalNumber),
                    currentValue: Double(truncating: holding.currentValue as NSDecimalNumber),
                    gainLoss: Double(truncating: holding.gainLoss as NSDecimalNumber),
                    assetType: holding.assetType.rawValue,
                    accountName: holding.account?.name
                )
            }

            return try encoder.encode(exportData)

        case .pdf:
            return try generateHoldingsPDF(filtered)
        }
    }

    private func exportAccounts(
        modelContext: ModelContext,
        options: ExportOptions
    ) async throws -> Data {
        progress = 0.3

        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)])
        let accounts = try modelContext.fetch(descriptor)

        progress = 0.6

        switch options.format {
        case .csv:
            var csv = "Name,Institution,Type,Balance,Currency\n"

            for account in accounts {
                csv += "\(escapeCSV(account.name)),\(escapeCSV(account.institution)),\(account.type.rawValue),\(account.effectiveBalance),\(account.currency)\n"
            }

            return csv.data(using: .utf8) ?? Data()

        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let exportData = accounts.map { account in
                AccountExport(
                    name: account.name,
                    institution: account.institution,
                    type: account.type.rawValue,
                    balance: Double(truncating: account.effectiveBalance as NSDecimalNumber),
                    currency: account.currency
                )
            }

            return try encoder.encode(exportData)

        case .pdf:
            return try generateAccountsPDF(accounts)
        }
    }

    private func exportFullBackup(
        modelContext: ModelContext,
        options: ExportOptions
    ) async throws -> Data {
        progress = 0.1

        let accountsDescriptor = FetchDescriptor<Account>()
        let accounts = try modelContext.fetch(accountsDescriptor)

        progress = 0.3

        let holdingsDescriptor = FetchDescriptor<Holding>()
        let holdings = try modelContext.fetch(holdingsDescriptor)

        progress = 0.5

        let transactionsDescriptor = FetchDescriptor<Transaction>()
        let transactions = try modelContext.fetch(transactionsDescriptor)

        progress = 0.7

        let goalsDescriptor = FetchDescriptor<Goal>()
        let goals = try modelContext.fetch(goalsDescriptor)

        let budgetsDescriptor = FetchDescriptor<Budget>()
        let budgets = try modelContext.fetch(budgetsDescriptor)

        progress = 0.8

        let backup = FullBackup(
            exportDate: Date(),
            version: "1.0",
            accounts: accounts.map { AccountExport(
                name: $0.name,
                institution: $0.institution,
                type: $0.type.rawValue,
                balance: Double(truncating: $0.effectiveBalance as NSDecimalNumber),
                currency: $0.currency
            )},
            holdings: holdings.map { HoldingExport(
                symbol: $0.symbol,
                name: $0.name,
                quantity: Double(truncating: $0.quantity as NSDecimalNumber),
                costBasis: Double(truncating: $0.costBasis as NSDecimalNumber),
                currentPrice: Double(truncating: $0.currentPrice as NSDecimalNumber),
                currentValue: Double(truncating: $0.currentValue as NSDecimalNumber),
                gainLoss: Double(truncating: $0.gainLoss as NSDecimalNumber),
                assetType: $0.assetType.rawValue,
                accountName: $0.account?.name
            )},
            transactions: transactions.map { TransactionExport(
                date: $0.date,
                description: $0.transactionDescription,
                amount: Double(truncating: $0.amount as NSDecimalNumber),
                category: $0.category.rawValue,
                accountName: $0.account?.name
            )},
            goals: goals.map { GoalExport(
                name: $0.name,
                targetAmount: Double(truncating: $0.targetAmount as NSDecimalNumber),
                currentAmount: Double(truncating: $0.currentAmount as NSDecimalNumber),
                targetDate: $0.targetDate,
                goalType: $0.goalType.rawValue
            )},
            budgets: budgets.map { BudgetExport(
                category: $0.category.rawValue,
                monthlyLimit: Double(truncating: $0.monthlyLimit as NSDecimalNumber),
                spent: Double(truncating: $0.spent as NSDecimalNumber),
                month: $0.periodMonth,
                year: $0.periodYear
            )}
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return try encoder.encode(backup)
    }

    private func generateTransactionsPDF(_ transactions: [Transaction]) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            context.beginPage()

            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let headerFont = UIFont.boldSystemFont(ofSize: 12)
            let bodyFont = UIFont.systemFont(ofSize: 10)

            var yPosition: CGFloat = 50

            let title = "Transactions Report"
            let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont]
            title.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40

            let dateStr = "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
            dateStr.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: bodyFont])
            yPosition += 30

            let headers = ["Date", "Description", "Category", "Amount"]
            let columnWidths: [CGFloat] = [80, 220, 100, 100]
            var xPosition: CGFloat = 50

            for (index, header) in headers.enumerated() {
                header.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: headerFont])
                xPosition += columnWidths[index]
            }
            yPosition += 20

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .currency

            for transaction in transactions {
                if yPosition > 720 {
                    context.beginPage()
                    yPosition = 50
                }

                xPosition = 50

                let date = dateFormatter.string(from: transaction.date)
                date.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])
                xPosition += columnWidths[0]

                let desc = String(transaction.transactionDescription.prefix(40))
                desc.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])
                xPosition += columnWidths[1]

                let category = transaction.category.rawValue
                category.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])
                xPosition += columnWidths[2]

                let amount = numberFormatter.string(from: transaction.amount as NSDecimalNumber) ?? "$0.00"
                amount.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])

                yPosition += 15
            }
        }

        return data
    }

    private func generateHoldingsPDF(_ holdings: [Holding]) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            context.beginPage()

            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let headerFont = UIFont.boldSystemFont(ofSize: 10)
            let bodyFont = UIFont.systemFont(ofSize: 9)

            var yPosition: CGFloat = 50

            let title = "Holdings Report"
            title.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: titleFont])
            yPosition += 40

            let totalValue = holdings.reduce(Decimal(0)) { $0 + $1.currentValue }
            let totalGainLoss = holdings.reduce(Decimal(0)) { $0 + $1.gainLoss }

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .currency

            let summaryText = "Total Value: \(numberFormatter.string(from: totalValue as NSDecimalNumber) ?? "$0") | Total Gain/Loss: \(numberFormatter.string(from: totalGainLoss as NSDecimalNumber) ?? "$0")"
            summaryText.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: bodyFont])
            yPosition += 30

            let headers = ["Symbol", "Name", "Qty", "Cost", "Price", "Value", "G/L"]
            let columnWidths: [CGFloat] = [60, 140, 50, 70, 70, 80, 80]
            var xPosition: CGFloat = 30

            for (index, header) in headers.enumerated() {
                header.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: headerFont])
                xPosition += columnWidths[index]
            }
            yPosition += 15

            for holding in holdings {
                if yPosition > 720 {
                    context.beginPage()
                    yPosition = 50
                }

                xPosition = 30

                holding.symbol.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])
                xPosition += columnWidths[0]

                String(holding.name.prefix(25)).draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])
                xPosition += columnWidths[1]

                "\(holding.quantity)".draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])
                xPosition += columnWidths[2]

                (numberFormatter.string(from: holding.costBasis as NSDecimalNumber) ?? "").draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])
                xPosition += columnWidths[3]

                (numberFormatter.string(from: holding.currentPrice as NSDecimalNumber) ?? "").draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])
                xPosition += columnWidths[4]

                (numberFormatter.string(from: holding.currentValue as NSDecimalNumber) ?? "").draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])
                xPosition += columnWidths[5]

                holding.displayGainLoss.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: [.font: bodyFont])

                yPosition += 15
            }
        }

        return data
    }

    private func generateAccountsPDF(_ accounts: [Account]) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            context.beginPage()

            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let headerFont = UIFont.boldSystemFont(ofSize: 12)
            let bodyFont = UIFont.systemFont(ofSize: 11)

            var yPosition: CGFloat = 50

            let title = "Accounts Summary"
            title.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: titleFont])
            yPosition += 40

            let totalAssets = accounts.filter { $0.type.isAsset }.reduce(Decimal(0)) { $0 + $1.effectiveBalance }
            let totalLiabilities = accounts.filter { !$0.type.isAsset }.reduce(Decimal(0)) { $0 + abs($1.effectiveBalance) }
            let netWorth = totalAssets - totalLiabilities

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .currency

            "Net Worth: \(numberFormatter.string(from: netWorth as NSDecimalNumber) ?? "$0")".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: headerFont])
            yPosition += 25

            "Assets: \(numberFormatter.string(from: totalAssets as NSDecimalNumber) ?? "$0") | Liabilities: \(numberFormatter.string(from: totalLiabilities as NSDecimalNumber) ?? "$0")".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: bodyFont])
            yPosition += 40

            for account in accounts {
                if yPosition > 720 {
                    context.beginPage()
                    yPosition = 50
                }

                "\(account.name) (\(account.type.rawValue))".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: [.font: headerFont])
                yPosition += 18

                "Institution: \(account.institution)".draw(at: CGPoint(x: 70, y: yPosition), withAttributes: [.font: bodyFont])
                yPosition += 15

                "Balance: \(account.displayBalance)".draw(at: CGPoint(x: 70, y: yPosition), withAttributes: [.font: bodyFont])
                yPosition += 25
            }
        }

        return data
    }

    private func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}

// MARK: - Export Models

struct TransactionExport: Codable {
    let date: Date
    let description: String
    let amount: Double
    let category: String
    let accountName: String?
}

struct HoldingExport: Codable {
    let symbol: String
    let name: String
    let quantity: Double
    let costBasis: Double
    let currentPrice: Double
    let currentValue: Double
    let gainLoss: Double
    let assetType: String
    let accountName: String?
}

struct AccountExport: Codable {
    let name: String
    let institution: String
    let type: String
    let balance: Double
    let currency: String
}

struct GoalExport: Codable {
    let name: String
    let targetAmount: Double
    let currentAmount: Double
    let targetDate: Date
    let goalType: String
}

struct BudgetExport: Codable {
    let category: String
    let monthlyLimit: Double
    let spent: Double
    let month: Int
    let year: Int
}

struct FullBackup: Codable {
    let exportDate: Date
    let version: String
    let accounts: [AccountExport]
    let holdings: [HoldingExport]
    let transactions: [TransactionExport]
    let goals: [GoalExport]
    let budgets: [BudgetExport]
}
