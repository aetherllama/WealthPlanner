import Foundation

enum OFXParserError: Error, LocalizedError {
    case invalidFile
    case parsingFailed(String)
    case missingRequiredElement(String)
    case invalidDateFormat(String)
    case invalidNumberFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "The file is not a valid OFX/QFX file"
        case .parsingFailed(let message):
            return "Parsing failed: \(message)"
        case .missingRequiredElement(let element):
            return "Missing required element: \(element)"
        case .invalidDateFormat(let value):
            return "Invalid date format: \(value)"
        case .invalidNumberFormat(let value):
            return "Invalid number format: \(value)"
        }
    }
}

struct OFXAccount {
    let accountId: String
    let accountType: String
    let bankId: String?
    let branchId: String?
    let balance: Decimal?
    let balanceDate: Date?
    let transactions: [OFXTransaction]
}

struct OFXTransaction {
    let id: String
    let type: String
    let date: Date
    let amount: Decimal
    let name: String?
    let memo: String?
    let checkNumber: String?
}

struct OFXHolding {
    let symbol: String
    let name: String?
    let units: Decimal
    let unitPrice: Decimal
    let marketValue: Decimal
    let priceDate: Date?
}

final class OFXParser {
    static let shared = OFXParser()

    private init() {}

    func parseFile(at url: URL) throws -> [OFXAccount] {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            do {
                content = try String(contentsOf: url, encoding: .isoLatin1)
            } catch {
                throw OFXParserError.invalidFile
            }
        }

        return try parse(content: content)
    }

    func parse(content: String) throws -> [OFXAccount] {
        let normalized = normalizeOFX(content)

        var accounts: [OFXAccount] = []

        if let bankStatements = extractElements(from: normalized, tag: "STMTRS") {
            for statement in bankStatements {
                if let account = try parseBankStatement(statement) {
                    accounts.append(account)
                }
            }
        }

        if let ccStatements = extractElements(from: normalized, tag: "CCSTMTRS") {
            for statement in ccStatements {
                if let account = try parseCreditCardStatement(statement) {
                    accounts.append(account)
                }
            }
        }

        if let invStatements = extractElements(from: normalized, tag: "INVSTMTRS") {
            for statement in invStatements {
                if let account = try parseInvestmentStatement(statement) {
                    accounts.append(account)
                }
            }
        }

        return accounts
    }

    private func normalizeOFX(_ content: String) -> String {
        var result = content

        let headerPattern = #"^[\s\S]*?<OFX>"#
        if let range = result.range(of: headerPattern, options: .regularExpression) {
            let header = String(result[range])
            if !header.contains("<?xml") {
                result = result.replacingCharacters(in: result.startIndex..<range.upperBound, with: "<OFX>")
            }
        }

        let tagPattern = #"<([A-Z0-9.]+)>([^<\n\r]+)"#
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            let nsRange = NSRange(result.startIndex..., in: result)
            var matches: [(NSRange, String, String)] = []

            regex.enumerateMatches(in: result, options: [], range: nsRange) { match, _, _ in
                if let match = match,
                   let tagRange = Range(match.range(at: 1), in: result),
                   let valueRange = Range(match.range(at: 2), in: result) {
                    let tag = String(result[tagRange])
                    let value = String(result[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    matches.append((match.range, tag, value))
                }
            }

            for (range, tag, value) in matches.reversed() {
                if let swiftRange = Range(range, in: result) {
                    result.replaceSubrange(swiftRange, with: "<\(tag)>\(value)</\(tag)>")
                }
            }
        }

        return result
    }

    private func extractElements(from content: String, tag: String) -> [String]? {
        let pattern = "<\(tag)>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        var results: [String] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: content) {
                results.append(String(content[range]))
            }
        }

        return results.isEmpty ? nil : results
    }

    private func extractElement(from content: String, tag: String) -> String? {
        let pattern = "<\(tag)>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        if let match = regex.firstMatch(in: content, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: content) {
            return String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func parseBankStatement(_ content: String) throws -> OFXAccount? {
        guard let bankAcctFrom = extractElements(from: content, tag: "BANKACCTFROM")?.first else {
            return nil
        }

        let accountId = extractElement(from: bankAcctFrom, tag: "ACCTID") ?? ""
        let accountType = extractElement(from: bankAcctFrom, tag: "ACCTTYPE") ?? "CHECKING"
        let bankId = extractElement(from: bankAcctFrom, tag: "BANKID")
        let branchId = extractElement(from: bankAcctFrom, tag: "BRANCHID")

        var balance: Decimal?
        var balanceDate: Date?

        if let ledgerBal = extractElements(from: content, tag: "LEDGERBAL")?.first {
            if let balAmt = extractElement(from: ledgerBal, tag: "BALAMT") {
                balance = Decimal(string: balAmt)
            }
            if let dtAsOf = extractElement(from: ledgerBal, tag: "DTASOF") {
                balanceDate = parseOFXDate(dtAsOf)
            }
        }

        let transactions = try parseTransactions(from: content)

        return OFXAccount(
            accountId: accountId,
            accountType: accountType,
            bankId: bankId,
            branchId: branchId,
            balance: balance,
            balanceDate: balanceDate,
            transactions: transactions
        )
    }

    private func parseCreditCardStatement(_ content: String) throws -> OFXAccount? {
        guard let ccAcctFrom = extractElements(from: content, tag: "CCACCTFROM")?.first else {
            return nil
        }

        let accountId = extractElement(from: ccAcctFrom, tag: "ACCTID") ?? ""

        var balance: Decimal?
        var balanceDate: Date?

        if let ledgerBal = extractElements(from: content, tag: "LEDGERBAL")?.first {
            if let balAmt = extractElement(from: ledgerBal, tag: "BALAMT") {
                balance = Decimal(string: balAmt)
            }
            if let dtAsOf = extractElement(from: ledgerBal, tag: "DTASOF") {
                balanceDate = parseOFXDate(dtAsOf)
            }
        }

        let transactions = try parseTransactions(from: content)

        return OFXAccount(
            accountId: accountId,
            accountType: "CREDITCARD",
            bankId: nil,
            branchId: nil,
            balance: balance,
            balanceDate: balanceDate,
            transactions: transactions
        )
    }

    private func parseInvestmentStatement(_ content: String) throws -> OFXAccount? {
        guard let invAcctFrom = extractElements(from: content, tag: "INVACCTFROM")?.first else {
            return nil
        }

        let accountId = extractElement(from: invAcctFrom, tag: "ACCTID") ?? ""
        let brokerId = extractElement(from: invAcctFrom, tag: "BROKERID")

        let transactions = try parseTransactions(from: content)

        return OFXAccount(
            accountId: accountId,
            accountType: "INVESTMENT",
            bankId: brokerId,
            branchId: nil,
            balance: nil,
            balanceDate: nil,
            transactions: transactions
        )
    }

    private func parseTransactions(from content: String) throws -> [OFXTransaction] {
        var transactions: [OFXTransaction] = []

        if let stmtTrns = extractElements(from: content, tag: "STMTTRN") {
            for trn in stmtTrns {
                if let transaction = try parseTransaction(trn) {
                    transactions.append(transaction)
                }
            }
        }

        return transactions
    }

    private func parseTransaction(_ content: String) throws -> OFXTransaction? {
        guard let trnType = extractElement(from: content, tag: "TRNTYPE") else {
            return nil
        }

        guard let dtPosted = extractElement(from: content, tag: "DTPOSTED"),
              let date = parseOFXDate(dtPosted) else {
            throw OFXParserError.invalidDateFormat(extractElement(from: content, tag: "DTPOSTED") ?? "missing")
        }

        guard let trnAmt = extractElement(from: content, tag: "TRNAMT"),
              let amount = Decimal(string: trnAmt) else {
            throw OFXParserError.invalidNumberFormat(extractElement(from: content, tag: "TRNAMT") ?? "missing")
        }

        let fitId = extractElement(from: content, tag: "FITID") ?? UUID().uuidString
        let name = extractElement(from: content, tag: "NAME")
        let memo = extractElement(from: content, tag: "MEMO")
        let checkNum = extractElement(from: content, tag: "CHECKNUM")

        return OFXTransaction(
            id: fitId,
            type: trnType,
            date: date,
            amount: amount,
            name: name,
            memo: memo,
            checkNumber: checkNum
        )
    }

    func parseHoldings(from content: String) throws -> [OFXHolding] {
        var holdings: [OFXHolding] = []

        if let posStocks = extractElements(from: content, tag: "POSSTOCK") {
            for pos in posStocks {
                if let holding = try parseStockPosition(pos) {
                    holdings.append(holding)
                }
            }
        }

        if let posMFs = extractElements(from: content, tag: "POSMF") {
            for pos in posMFs {
                if let holding = try parseMutualFundPosition(pos) {
                    holdings.append(holding)
                }
            }
        }

        if let posOthers = extractElements(from: content, tag: "POSOTHER") {
            for pos in posOthers {
                if let holding = try parseOtherPosition(pos) {
                    holdings.append(holding)
                }
            }
        }

        return holdings
    }

    private func parseStockPosition(_ content: String) throws -> OFXHolding? {
        guard let invPos = extractElements(from: content, tag: "INVPOS")?.first else {
            return nil
        }

        return try parseInvestmentPosition(invPos, type: "STOCK")
    }

    private func parseMutualFundPosition(_ content: String) throws -> OFXHolding? {
        guard let invPos = extractElements(from: content, tag: "INVPOS")?.first else {
            return nil
        }

        return try parseInvestmentPosition(invPos, type: "MUTUALFUND")
    }

    private func parseOtherPosition(_ content: String) throws -> OFXHolding? {
        guard let invPos = extractElements(from: content, tag: "INVPOS")?.first else {
            return nil
        }

        return try parseInvestmentPosition(invPos, type: "OTHER")
    }

    private func parseInvestmentPosition(_ content: String, type: String) throws -> OFXHolding? {
        guard let secId = extractElements(from: content, tag: "SECID")?.first,
              let uniqueId = extractElement(from: secId, tag: "UNIQUEID") else {
            return nil
        }

        guard let unitsStr = extractElement(from: content, tag: "UNITS"),
              let units = Decimal(string: unitsStr) else {
            throw OFXParserError.invalidNumberFormat(extractElement(from: content, tag: "UNITS") ?? "missing")
        }

        guard let unitPriceStr = extractElement(from: content, tag: "UNITPRICE"),
              let unitPrice = Decimal(string: unitPriceStr) else {
            throw OFXParserError.invalidNumberFormat(extractElement(from: content, tag: "UNITPRICE") ?? "missing")
        }

        guard let mktValStr = extractElement(from: content, tag: "MKTVAL"),
              let mktVal = Decimal(string: mktValStr) else {
            throw OFXParserError.invalidNumberFormat(extractElement(from: content, tag: "MKTVAL") ?? "missing")
        }

        var priceDate: Date?
        if let dtPriceAsOf = extractElement(from: content, tag: "DTPRICEASOF") {
            priceDate = parseOFXDate(dtPriceAsOf)
        }

        return OFXHolding(
            symbol: uniqueId,
            name: nil,
            units: units,
            unitPrice: unitPrice,
            marketValue: mktVal,
            priceDate: priceDate
        )
    }

    private func parseOFXDate(_ dateString: String) -> Date? {
        let cleanDate = dateString.prefix(14)

        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyyMMddHHmmss"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyyMMdd"
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: String(cleanDate)) {
                return date
            }
            if cleanDate.count >= 8,
               let date = formatter.date(from: String(cleanDate.prefix(8))) {
                return date
            }
        }

        return nil
    }

    func mapToAccountType(_ ofxType: String) -> AccountType {
        switch ofxType.uppercased() {
        case "CHECKING":
            return .checking
        case "SAVINGS":
            return .savings
        case "CREDITCARD", "CREDITLINE":
            return .credit
        case "INVESTMENT":
            return .investment
        case "MONEYMRKT", "CD":
            return .savings
        default:
            return .other
        }
    }

    func mapTransactionCategory(_ ofxType: String) -> TransactionCategory {
        switch ofxType.uppercased() {
        case "CREDIT", "DEP", "DIRECTDEP":
            return .income
        case "INT", "DIV":
            return .investment
        case "XFER":
            return .transfer
        case "ATM", "CASH":
            return .other
        case "CHECK":
            return .other
        case "PAYMENT", "DEBIT", "POS":
            return .shopping
        case "FEE", "SRVCHG":
            return .other
        default:
            return .other
        }
    }
}
