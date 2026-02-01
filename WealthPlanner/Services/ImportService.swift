import Foundation
import SwiftData
import UniformTypeIdentifiers

enum ImportError: Error, LocalizedError {
    case unsupportedFileType
    case parsingFailed(String)
    case noDataFound
    case accountNotFound
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "This file type is not supported"
        case .parsingFailed(let message):
            return "Failed to parse file: \(message)"
        case .noDataFound:
            return "No data found in the file"
        case .accountNotFound:
            return "Target account not found"
        case .saveFailed(let error):
            return "Failed to save data: \(error.localizedDescription)"
        }
    }
}

enum ImportFileType {
    case csv
    case ofx
    case qfx
    case qif

    var utType: UTType {
        switch self {
        case .csv:
            return .commaSeparatedText
        case .ofx, .qfx:
            return UTType(filenameExtension: "ofx") ?? .data
        case .qif:
            return UTType(filenameExtension: "qif") ?? .data
        }
    }

    static func fromURL(_ url: URL) -> ImportFileType? {
        switch url.pathExtension.lowercased() {
        case "csv":
            return .csv
        case "ofx":
            return .ofx
        case "qfx":
            return .qfx
        case "qif":
            return .qif
        default:
            return nil
        }
    }
}

struct ImportResult {
    let accountsCreated: Int
    let transactionsImported: Int
    let holdingsImported: Int
    let errors: [String]
}

@MainActor
final class ImportService: ObservableObject {
    static let shared = ImportService()

    @Published var isImporting = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""

    private let csvParser = CSVParser.shared
    private let ofxParser = OFXParser.shared

    private init() {}

    func importFile(
        at url: URL,
        into modelContext: ModelContext,
        targetAccount: Account? = nil
    ) async throws -> ImportResult {
        isImporting = true
        progress = 0
        statusMessage = "Reading file..."

        defer {
            isImporting = false
            progress = 1.0
            statusMessage = ""
        }

        // Try to access security scoped resource (for files from file picker)
        let hasAccess = url.startAccessingSecurityScopedResource()

        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let fileType = ImportFileType.fromURL(url) else {
            throw ImportError.unsupportedFileType
        }

        switch fileType {
        case .csv:
            return try await importCSV(
                at: url,
                into: modelContext,
                targetAccount: targetAccount
            )
        case .ofx, .qfx:
            return try await importOFX(at: url, into: modelContext)
        case .qif:
            return try await importQIF(at: url, into: modelContext, targetAccount: targetAccount)
        }
    }

    private func importCSV(
        at url: URL,
        into modelContext: ModelContext,
        targetAccount: Account?
    ) async throws -> ImportResult {
        statusMessage = "Parsing CSV..."
        progress = 0.2

        let (headers, rows) = try csvParser.parseFile(at: url)

        guard !rows.isEmpty else {
            throw ImportError.noDataFound
        }

        let mapping = csvParser.detectColumnMappings(headers: headers)

        progress = 0.4

        // Determine if this is holdings or transactions data
        if mapping.dataType == .holdings {
            return try await importCSVHoldings(
                headers: headers,
                rows: rows,
                mapping: mapping,
                into: modelContext,
                targetAccount: targetAccount,
                fileName: url.deletingPathExtension().lastPathComponent
            )
        } else {
            return try await importCSVTransactions(
                headers: headers,
                rows: rows,
                mapping: mapping,
                into: modelContext,
                targetAccount: targetAccount,
                fileName: url.deletingPathExtension().lastPathComponent
            )
        }
    }

    private func importCSVTransactions(
        headers: [String],
        rows: [[String]],
        mapping: CSVColumnMapping,
        into modelContext: ModelContext,
        targetAccount: Account?,
        fileName: String
    ) async throws -> ImportResult {
        statusMessage = "Importing transactions..."

        let parsedTransactions = try csvParser.parseTransactions(
            headers: headers,
            rows: rows,
            mapping: mapping
        )

        guard !parsedTransactions.isEmpty else {
            throw ImportError.noDataFound
        }

        var transactionsImported = 0

        let account: Account

        if let targetAccount = targetAccount {
            account = targetAccount
        } else {
            account = Account(
                name: fileName,
                institution: "Imported",
                type: .checking,
                isManual: true
            )
            modelContext.insert(account)
        }

        progress = 0.6

        for (index, parsed) in parsedTransactions.enumerated() {
            let category = parsed.category.flatMap { categorize($0) } ?? .other

            let transaction = Transaction(
                date: parsed.date,
                description: parsed.description,
                amount: parsed.amount,
                category: category
            )

            transaction.account = account
            modelContext.insert(transaction)

            transactionsImported += 1

            if index % 100 == 0 {
                progress = 0.6 + 0.3 * Double(index) / Double(parsedTransactions.count)
            }
        }

        progress = 0.95
        statusMessage = "Saving..."

        do {
            try modelContext.save()
        } catch {
            throw ImportError.saveFailed(error)
        }

        return ImportResult(
            accountsCreated: targetAccount == nil ? 1 : 0,
            transactionsImported: transactionsImported,
            holdingsImported: 0,
            errors: []
        )
    }

    private func importCSVHoldings(
        headers: [String],
        rows: [[String]],
        mapping: CSVColumnMapping,
        into modelContext: ModelContext,
        targetAccount: Account?,
        fileName: String
    ) async throws -> ImportResult {
        statusMessage = "Importing holdings..."

        let parsedHoldings = try csvParser.parseHoldings(
            headers: headers,
            rows: rows,
            mapping: mapping
        )

        guard !parsedHoldings.isEmpty else {
            throw ImportError.noDataFound
        }

        var holdingsImported = 0

        let account: Account

        if let targetAccount = targetAccount {
            account = targetAccount
        } else {
            account = Account(
                name: fileName,
                institution: "Imported",
                type: .investment,
                isManual: true
            )
            modelContext.insert(account)
        }

        progress = 0.6

        for (index, parsed) in parsedHoldings.enumerated() {
            let assetType = mapAssetType(parsed.assetType)
            let costBasis = parsed.costBasis ?? parsed.price
            let currentPrice = parsed.price > 0 ? parsed.price : costBasis

            let holding = Holding(
                symbol: parsed.symbol.uppercased(),
                name: parsed.name ?? parsed.symbol,
                quantity: parsed.quantity,
                costBasis: costBasis,
                currentPrice: currentPrice,
                assetType: assetType
            )

            holding.account = account
            modelContext.insert(holding)

            holdingsImported += 1

            if index % 50 == 0 {
                progress = 0.6 + 0.3 * Double(index) / Double(parsedHoldings.count)
            }
        }

        progress = 0.95
        statusMessage = "Saving..."

        do {
            try modelContext.save()
        } catch {
            throw ImportError.saveFailed(error)
        }

        return ImportResult(
            accountsCreated: targetAccount == nil ? 1 : 0,
            transactionsImported: 0,
            holdingsImported: holdingsImported,
            errors: []
        )
    }

    private func mapAssetType(_ typeString: String?) -> AssetType {
        guard let type = typeString?.lowercased() else { return .stock }

        if type.contains("stock") || type.contains("equity") {
            return .stock
        } else if type.contains("bond") {
            return .bond
        } else if type.contains("etf") {
            return .etf
        } else if type.contains("mutual") || type.contains("fund") {
            return .mutualFund
        } else if type.contains("crypto") || type.contains("bitcoin") || type.contains("ethereum") {
            return .crypto
        } else if type.contains("cash") || type.contains("money market") {
            return .cash
        } else if type.contains("option") {
            return .option
        }

        return .stock
    }

    private func importOFX(
        at url: URL,
        into modelContext: ModelContext
    ) async throws -> ImportResult {
        statusMessage = "Parsing OFX..."
        progress = 0.2

        let accounts = try ofxParser.parseFile(at: url)

        guard !accounts.isEmpty else {
            throw ImportError.noDataFound
        }

        progress = 0.4

        var accountsCreated = 0
        var transactionsImported = 0
        var errors: [String] = []

        for (index, ofxAccount) in accounts.enumerated() {
            statusMessage = "Importing account \(index + 1) of \(accounts.count)..."

            let accountType = ofxParser.mapToAccountType(ofxAccount.accountType)

            let account = Account(
                name: "Account \(ofxAccount.accountId.suffix(4))",
                institution: ofxAccount.bankId ?? "Unknown",
                type: accountType,
                balance: ofxAccount.balance ?? 0,
                isManual: true
            )

            modelContext.insert(account)
            accountsCreated += 1

            for ofxTransaction in ofxAccount.transactions {
                let category = ofxParser.mapTransactionCategory(ofxTransaction.type)

                let description = [ofxTransaction.name, ofxTransaction.memo]
                    .compactMap { $0 }
                    .joined(separator: " - ")

                let transaction = Transaction(
                    date: ofxTransaction.date,
                    description: description.isEmpty ? ofxTransaction.type : description,
                    amount: ofxTransaction.amount,
                    category: category
                )

                transaction.account = account
                modelContext.insert(transaction)

                transactionsImported += 1
            }

            progress = 0.4 + 0.5 * Double(index + 1) / Double(accounts.count)
        }

        progress = 0.95
        statusMessage = "Saving..."

        do {
            try modelContext.save()
        } catch {
            throw ImportError.saveFailed(error)
        }

        return ImportResult(
            accountsCreated: accountsCreated,
            transactionsImported: transactionsImported,
            holdingsImported: 0,
            errors: errors
        )
    }

    private func importQIF(
        at url: URL,
        into modelContext: ModelContext,
        targetAccount: Account?
    ) async throws -> ImportResult {
        statusMessage = "Parsing QIF..."
        progress = 0.2

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var transactions: [(date: Date, description: String, amount: Decimal, category: String?)] = []
        var currentDate: Date?
        var currentAmount: Decimal?
        var currentPayee: String?
        var currentCategory: String?

        let dateFormats = ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy", "yyyy-MM-dd"]

        for line in lines {
            guard !line.isEmpty else { continue }

            let code = line.prefix(1)
            let value = String(line.dropFirst())

            switch code {
            case "D":
                let cleanDate = value
                    .replacingOccurrences(of: "'", with: "/20")
                    .replacingOccurrences(of: " ", with: "")

                for format in dateFormats {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = format
                    if let date = dateFormatter.date(from: cleanDate) {
                        currentDate = date
                        break
                    }
                }
            case "T", "U":
                let cleanAmount = value
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "$", with: "")
                currentAmount = Decimal(string: cleanAmount)
            case "P":
                currentPayee = value
            case "L":
                currentCategory = value
            case "^":
                if let date = currentDate, let amount = currentAmount {
                    transactions.append((
                        date: date,
                        description: currentPayee ?? "Unknown",
                        amount: amount,
                        category: currentCategory
                    ))
                }
                currentDate = nil
                currentAmount = nil
                currentPayee = nil
                currentCategory = nil
            default:
                break
            }
        }

        guard !transactions.isEmpty else {
            throw ImportError.noDataFound
        }

        progress = 0.5

        let account: Account
        if let targetAccount = targetAccount {
            account = targetAccount
        } else {
            let fileName = url.deletingPathExtension().lastPathComponent
            account = Account(
                name: fileName,
                institution: "Imported",
                type: .checking,
                isManual: true
            )
            modelContext.insert(account)
        }

        var transactionsImported = 0

        for parsed in transactions {
            let category = parsed.category.flatMap { categorize($0) } ?? .other

            let transaction = Transaction(
                date: parsed.date,
                description: parsed.description,
                amount: parsed.amount,
                category: category
            )

            transaction.account = account
            modelContext.insert(transaction)
            transactionsImported += 1
        }

        progress = 0.95
        statusMessage = "Saving..."

        do {
            try modelContext.save()
        } catch {
            throw ImportError.saveFailed(error)
        }

        return ImportResult(
            accountsCreated: targetAccount == nil ? 1 : 0,
            transactionsImported: transactionsImported,
            holdingsImported: 0,
            errors: []
        )
    }

    private func categorize(_ categoryString: String) -> TransactionCategory? {
        let lower = categoryString.lowercased()

        if lower.contains("income") || lower.contains("salary") || lower.contains("paycheck") {
            return .salary
        } else if lower.contains("food") || lower.contains("restaurant") || lower.contains("dining") || lower.contains("grocery") {
            return .food
        } else if lower.contains("shop") || lower.contains("retail") {
            return .shopping
        } else if lower.contains("transport") || lower.contains("gas") || lower.contains("fuel") || lower.contains("uber") || lower.contains("lyft") {
            return .transportation
        } else if lower.contains("utility") || lower.contains("electric") || lower.contains("water") || lower.contains("internet") {
            return .utilities
        } else if lower.contains("entertainment") || lower.contains("movie") || lower.contains("game") {
            return .entertainment
        } else if lower.contains("health") || lower.contains("medical") || lower.contains("doctor") || lower.contains("pharmacy") {
            return .healthcare
        } else if lower.contains("education") || lower.contains("school") || lower.contains("tuition") {
            return .education
        } else if lower.contains("travel") || lower.contains("hotel") || lower.contains("flight") || lower.contains("airline") {
            return .travel
        } else if lower.contains("rent") || lower.contains("mortgage") || lower.contains("housing") {
            return .housing
        } else if lower.contains("insurance") {
            return .insurance
        } else if lower.contains("subscription") || lower.contains("netflix") || lower.contains("spotify") {
            return .subscriptions
        } else if lower.contains("transfer") {
            return .transfer
        } else if lower.contains("invest") || lower.contains("dividend") {
            return .investment
        }

        return nil
    }

    static var supportedTypes: [UTType] {
        [
            .commaSeparatedText,
            UTType(filenameExtension: "ofx") ?? .data,
            UTType(filenameExtension: "qfx") ?? .data,
            UTType(filenameExtension: "qif") ?? .data
        ]
    }
}
