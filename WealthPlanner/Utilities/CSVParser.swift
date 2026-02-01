import Foundation

enum CSVParserError: Error, LocalizedError {
    case invalidFile
    case emptyFile
    case invalidEncoding
    case missingRequiredColumn(String)
    case invalidDateFormat(String)
    case invalidNumberFormat(String)
    case rowParsingError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "The file could not be read as CSV"
        case .emptyFile:
            return "The file is empty"
        case .invalidEncoding:
            return "The file encoding is not supported"
        case .missingRequiredColumn(let column):
            return "Required column '\(column)' is missing"
        case .invalidDateFormat(let value):
            return "Invalid date format: '\(value)'"
        case .invalidNumberFormat(let value):
            return "Invalid number format: '\(value)'"
        case .rowParsingError(let row, let message):
            return "Error parsing row \(row): \(message)"
        }
    }
}

enum CSVDataType {
    case transactions
    case holdings
    case unknown
}

struct CSVColumnMapping {
    var dateColumn: String?
    var descriptionColumn: String?
    var amountColumn: String?
    var categoryColumn: String?
    var debitColumn: String?
    var creditColumn: String?
    var balanceColumn: String?
    var symbolColumn: String?
    var nameColumn: String?
    var quantityColumn: String?
    var priceColumn: String?
    var costBasisColumn: String?
    var assetTypeColumn: String?

    var dateFormat: String?
    var hasHeaderRow: Bool = true
    var delimiter: Character = ","
    var dataType: CSVDataType = .unknown
}

struct ParsedTransaction {
    let date: Date
    let description: String
    let amount: Decimal
    let category: String?
}

struct ParsedHolding {
    let symbol: String
    let name: String?
    let quantity: Decimal
    let price: Decimal
    let costBasis: Decimal?
    let assetType: String?
}

final class CSVParser {
    static let shared = CSVParser()

    // Common date formats to try
    private let dateFormats = [
        "yyyy-MM-dd",
        "MM/dd/yyyy",
        "MM-dd-yyyy",
        "dd/MM/yyyy",
        "dd-MM-yyyy",
        "M/d/yyyy",
        "M/d/yy",
        "MM/dd/yy",
        "yyyy/MM/dd",
        "MMM dd, yyyy",
        "MMMM dd, yyyy",
        "dd MMM yyyy",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss"
    ]

    private init() {}

    func parseFile(at url: URL) throws -> (headers: [String], rows: [[String]]) {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            do {
                content = try String(contentsOf: url, encoding: .isoLatin1)
            } catch {
                throw CSVParserError.invalidEncoding
            }
        }

        return try parse(content: content)
    }

    func parse(content: String, delimiter: Character = ",") throws -> (headers: [String], rows: [[String]]) {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw CSVParserError.emptyFile
        }

        let headers = parseLine(lines[0], delimiter: delimiter)
        var rows: [[String]] = []

        for i in 1..<lines.count {
            let row = parseLine(lines[i], delimiter: delimiter)
            if row.count == headers.count {
                rows.append(row)
            } else if row.count > 0 {
                var paddedRow = row
                while paddedRow.count < headers.count {
                    paddedRow.append("")
                }
                rows.append(Array(paddedRow.prefix(headers.count)))
            }
        }

        return (headers, rows)
    }

    private func parseLine(_ line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == delimiter && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }

        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    // MARK: - Date Parsing

    func parseDate(_ dateString: String, preferredFormat: String? = nil) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try preferred format first
        if let preferred = preferredFormat {
            formatter.dateFormat = preferred
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        // Try all common formats
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    func detectDateFormat(from samples: [String]) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in dateFormats {
            formatter.dateFormat = format
            var matchCount = 0

            for sample in samples.prefix(5) {
                let trimmed = sample.trimmingCharacters(in: .whitespaces)
                if formatter.date(from: trimmed) != nil {
                    matchCount += 1
                }
            }

            // If most samples match this format, use it
            if matchCount >= min(3, samples.count) {
                return format
            }
        }

        return nil
    }

    // MARK: - Transaction Parsing

    func parseTransactions(
        headers: [String],
        rows: [[String]],
        mapping: CSVColumnMapping
    ) throws -> [ParsedTransaction] {
        guard let dateCol = mapping.dateColumn,
              let descCol = mapping.descriptionColumn else {
            throw CSVParserError.missingRequiredColumn("date or description")
        }

        guard let dateIndex = findColumnIndex(dateCol, in: headers) else {
            throw CSVParserError.missingRequiredColumn(dateCol)
        }

        guard let descIndex = findColumnIndex(descCol, in: headers) else {
            throw CSVParserError.missingRequiredColumn(descCol)
        }

        let amountIndex = mapping.amountColumn.flatMap { findColumnIndex($0, in: headers) }
        let debitIndex = mapping.debitColumn.flatMap { findColumnIndex($0, in: headers) }
        let creditIndex = mapping.creditColumn.flatMap { findColumnIndex($0, in: headers) }
        let categoryIndex = mapping.categoryColumn.flatMap { findColumnIndex($0, in: headers) }

        // Detect date format from sample data
        let dateSamples = rows.prefix(10).compactMap { $0.indices.contains(dateIndex) ? $0[dateIndex] : nil }
        let detectedFormat = mapping.dateFormat ?? detectDateFormat(from: dateSamples)

        var transactions: [ParsedTransaction] = []

        for (rowIndex, row) in rows.enumerated() {
            guard row.indices.contains(dateIndex), row.indices.contains(descIndex) else {
                continue
            }

            guard let date = parseDate(row[dateIndex], preferredFormat: detectedFormat) else {
                // Skip rows with invalid dates instead of failing
                continue
            }

            let description = row[descIndex]

            var amount: Decimal

            if let amountIdx = amountIndex, row.indices.contains(amountIdx) {
                guard let parsed = parseDecimal(row[amountIdx]) else {
                    continue
                }
                amount = parsed
            } else if let debitIdx = debitIndex, let creditIdx = creditIndex,
                      row.indices.contains(debitIdx), row.indices.contains(creditIdx) {
                let debit = parseDecimal(row[debitIdx]) ?? 0
                let credit = parseDecimal(row[creditIdx]) ?? 0
                amount = credit - debit
            } else {
                continue
            }

            let category = categoryIndex.flatMap { row.indices.contains($0) ? row[$0] : nil }

            transactions.append(ParsedTransaction(
                date: date,
                description: description,
                amount: amount,
                category: category
            ))
        }

        return transactions
    }

    // MARK: - Holdings Parsing

    func parseHoldings(
        headers: [String],
        rows: [[String]],
        mapping: CSVColumnMapping
    ) throws -> [ParsedHolding] {
        guard let symbolCol = mapping.symbolColumn,
              let quantityCol = mapping.quantityColumn else {
            throw CSVParserError.missingRequiredColumn("symbol or quantity")
        }

        guard let symbolIndex = findColumnIndex(symbolCol, in: headers) else {
            throw CSVParserError.missingRequiredColumn(symbolCol)
        }

        guard let quantityIndex = findColumnIndex(quantityCol, in: headers) else {
            throw CSVParserError.missingRequiredColumn(quantityCol)
        }

        let priceIndex = mapping.priceColumn.flatMap { findColumnIndex($0, in: headers) }
        let costBasisIndex = mapping.costBasisColumn.flatMap { findColumnIndex($0, in: headers) }
        let nameIndex = mapping.nameColumn.flatMap { findColumnIndex($0, in: headers) }
        let assetTypeIndex = mapping.assetTypeColumn.flatMap { findColumnIndex($0, in: headers) }

        var holdings: [ParsedHolding] = []

        for row in rows {
            guard row.indices.contains(symbolIndex), row.indices.contains(quantityIndex) else {
                continue
            }

            let symbol = row[symbolIndex].trimmingCharacters(in: .whitespaces)
            guard !symbol.isEmpty else { continue }

            guard let quantity = parseDecimal(row[quantityIndex]) else {
                continue
            }

            let price: Decimal
            if let priceIdx = priceIndex, row.indices.contains(priceIdx) {
                price = parseDecimal(row[priceIdx]) ?? 0
            } else {
                price = 0
            }

            let costBasis: Decimal?
            if let costIdx = costBasisIndex, row.indices.contains(costIdx) {
                costBasis = parseDecimal(row[costIdx])
            } else {
                costBasis = nil
            }

            let name = nameIndex.flatMap { row.indices.contains($0) ? row[$0] : nil }
            let assetType = assetTypeIndex.flatMap { row.indices.contains($0) ? row[$0] : nil }

            holdings.append(ParsedHolding(
                symbol: symbol,
                name: name,
                quantity: quantity,
                price: price,
                costBasis: costBasis,
                assetType: assetType
            ))
        }

        return holdings
    }

    // MARK: - Column Detection

    private func findColumnIndex(_ column: String, in headers: [String]) -> Int? {
        // Try exact match first
        if let index = headers.firstIndex(of: column) {
            return index
        }
        // Try case-insensitive match
        let lowerColumn = column.lowercased()
        return headers.firstIndex { $0.lowercased() == lowerColumn }
    }

    func detectColumnMappings(headers: [String]) -> CSVColumnMapping {
        var mapping = CSVColumnMapping()

        let headerLower = headers.map { $0.lowercased() }

        for (index, header) in headerLower.enumerated() {
            // Date column detection
            if mapping.dateColumn == nil {
                if header == "date" || header == "transaction date" || header == "trans date" ||
                   header == "posted date" || header == "posting date" || header == "trade date" {
                    mapping.dateColumn = headers[index]
                }
            }

            // Description column detection
            if mapping.descriptionColumn == nil {
                if header == "description" || header == "desc" || header == "memo" ||
                   header == "payee" || header == "merchant" || header == "transaction" ||
                   header == "details" || header == "narration" {
                    mapping.descriptionColumn = headers[index]
                }
            }

            // Amount column detection
            if header == "amount" || header == "transaction amount" || header == "value" {
                mapping.amountColumn = headers[index]
            }

            // Debit/Credit detection
            if header.contains("debit") || header == "withdrawal" || header == "withdrawals" {
                mapping.debitColumn = headers[index]
            }
            if header.contains("credit") || header == "deposit" || header == "deposits" {
                mapping.creditColumn = headers[index]
            }

            // Category detection
            if header == "category" || header == "type" || header == "transaction type" {
                mapping.categoryColumn = headers[index]
            }

            // Balance detection
            if header == "balance" || header == "running balance" {
                mapping.balanceColumn = headers[index]
            }

            // Holdings-specific columns
            if header == "symbol" || header == "ticker" || header == "stock symbol" {
                mapping.symbolColumn = headers[index]
            }
            if header == "name" || header == "security name" || header == "stock name" ||
               header == "holding name" || header == "security" {
                mapping.nameColumn = headers[index]
            }
            if header == "quantity" || header == "shares" || header == "qty" || header == "units" {
                mapping.quantityColumn = headers[index]
            }
            if header == "price" || header == "current price" || header == "market price" ||
               header == "last price" || header == "share price" {
                mapping.priceColumn = headers[index]
            }
            if header == "cost basis" || header == "cost" || header == "average cost" ||
               header == "purchase price" || header == "avg cost" {
                mapping.costBasisColumn = headers[index]
            }
            if header == "asset type" || header == "type" || header == "security type" ||
               header == "asset class" {
                mapping.assetTypeColumn = headers[index]
            }
        }

        // Determine data type based on detected columns
        if mapping.symbolColumn != nil && mapping.quantityColumn != nil {
            mapping.dataType = .holdings
        } else if mapping.dateColumn != nil && mapping.descriptionColumn != nil {
            mapping.dataType = .transactions
        }

        return mapping
    }

    // MARK: - Number Parsing

    private func parseDecimal(_ string: String) -> Decimal? {
        let cleaned = string
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespaces)

        if cleaned.isEmpty { return nil }

        return Decimal(string: cleaned)
    }
}

// MARK: - Export

extension CSVParser {
    func exportTransactions(_ transactions: [Transaction]) -> String {
        var csv = "Date,Description,Amount,Category,Account\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for transaction in transactions {
            let date = dateFormatter.string(from: transaction.date)
            let desc = escapeCSVField(transaction.transactionDescription)
            let amount = "\(transaction.amount)"
            let category = transaction.category.rawValue
            let account = transaction.account?.name ?? ""

            csv += "\(date),\(desc),\(amount),\(category),\(escapeCSVField(account))\n"
        }

        return csv
    }

    func exportHoldings(_ holdings: [Holding]) -> String {
        var csv = "Symbol,Name,Quantity,Cost Basis,Current Price,Current Value,Gain/Loss,Account\n"

        for holding in holdings {
            let symbol = holding.symbol
            let name = escapeCSVField(holding.name)
            let quantity = "\(holding.quantity)"
            let costBasis = "\(holding.costBasis)"
            let price = "\(holding.currentPrice)"
            let value = "\(holding.currentValue)"
            let gainLoss = "\(holding.gainLoss)"
            let account = holding.account?.name ?? ""

            csv += "\(symbol),\(name),\(quantity),\(costBasis),\(price),\(value),\(gainLoss),\(escapeCSVField(account))\n"
        }

        return csv
    }

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}
