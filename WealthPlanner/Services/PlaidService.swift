import Foundation

enum PlaidEnvironment: String {
    case sandbox = "sandbox"
    case development = "development"
    case production = "production"

    var baseURL: String {
        switch self {
        case .sandbox:
            return "https://sandbox.plaid.com"
        case .development:
            return "https://development.plaid.com"
        case .production:
            return "https://production.plaid.com"
        }
    }
}

struct PlaidConfig {
    let clientId: String
    let secret: String
    let environment: PlaidEnvironment

    static var sandbox: PlaidConfig {
        PlaidConfig(
            clientId: "YOUR_CLIENT_ID",
            secret: "YOUR_SANDBOX_SECRET",
            environment: .sandbox
        )
    }
}

enum PlaidError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case apiError(String, String)
    case noAccessToken
    case configurationError

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Plaid"
        case .apiError(let code, let message):
            return "Plaid error [\(code)]: \(message)"
        case .noAccessToken:
            return "No access token available"
        case .configurationError:
            return "Plaid is not configured"
        }
    }
}

struct PlaidLinkToken: Codable {
    let linkToken: String
    let expiration: String

    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
        case expiration
    }
}

struct PlaidAccessToken: Codable {
    let accessToken: String
    let itemId: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case itemId = "item_id"
    }
}

struct PlaidAccount: Codable {
    let accountId: String
    let name: String
    let officialName: String?
    let type: String
    let subtype: String?
    let mask: String?
    let balances: PlaidBalances

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case name
        case officialName = "official_name"
        case type
        case subtype
        case mask
        case balances
    }
}

struct PlaidBalances: Codable {
    let available: Double?
    let current: Double?
    let limit: Double?
    let isoCurrencyCode: String?

    enum CodingKeys: String, CodingKey {
        case available
        case current
        case limit
        case isoCurrencyCode = "iso_currency_code"
    }
}

struct PlaidTransaction: Codable {
    let transactionId: String
    let accountId: String
    let amount: Double
    let date: String
    let name: String
    let merchantName: String?
    let category: [String]?
    let pending: Bool

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case accountId = "account_id"
        case amount
        case date
        case name
        case merchantName = "merchant_name"
        case category
        case pending
    }
}

struct PlaidHolding: Codable {
    let accountId: String
    let securityId: String
    let quantity: Double
    let institutionPrice: Double
    let institutionValue: Double
    let costBasis: Double?

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case securityId = "security_id"
        case quantity
        case institutionPrice = "institution_price"
        case institutionValue = "institution_value"
        case costBasis = "cost_basis"
    }
}

struct PlaidSecurity: Codable {
    let securityId: String
    let name: String?
    let tickerSymbol: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case securityId = "security_id"
        case name
        case tickerSymbol = "ticker_symbol"
        case type
    }
}

@MainActor
final class PlaidService: ObservableObject {
    static let shared = PlaidService()

    @Published var isConfigured = false
    @Published var isLoading = false

    private var config: PlaidConfig?
    private let keychain = KeychainManager.shared

    private init() {
        #if DEBUG
        configure(with: .sandbox)
        #endif
    }

    func configure(with config: PlaidConfig) {
        self.config = config
        self.isConfigured = config.clientId != "YOUR_CLIENT_ID"
    }

    func createLinkToken(userId: String) async throws -> String {
        guard let config = config else {
            throw PlaidError.configurationError
        }

        let body: [String: Any] = [
            "client_id": config.clientId,
            "secret": config.secret,
            "user": ["client_user_id": userId],
            "client_name": "WealthPlanner",
            "products": ["auth", "transactions", "investments"],
            "country_codes": ["US"],
            "language": "en"
        ]

        let data = try await makeRequest(
            endpoint: "/link/token/create",
            body: body
        )

        let response = try JSONDecoder().decode(PlaidLinkToken.self, from: data)
        return response.linkToken
    }

    func exchangePublicToken(_ publicToken: String) async throws -> PlaidAccessToken {
        guard let config = config else {
            throw PlaidError.configurationError
        }

        let body: [String: Any] = [
            "client_id": config.clientId,
            "secret": config.secret,
            "public_token": publicToken
        ]

        let data = try await makeRequest(
            endpoint: "/item/public_token/exchange",
            body: body
        )

        let response = try JSONDecoder().decode(PlaidAccessToken.self, from: data)

        try keychain.savePlaidAccessToken(response.accessToken, forItemId: response.itemId)

        return response
    }

    func getAccounts(itemId: String) async throws -> [PlaidAccount] {
        guard let config = config else {
            throw PlaidError.configurationError
        }

        let accessToken = try keychain.getPlaidAccessToken(forItemId: itemId)

        let body: [String: Any] = [
            "client_id": config.clientId,
            "secret": config.secret,
            "access_token": accessToken
        ]

        let data = try await makeRequest(
            endpoint: "/accounts/get",
            body: body
        )

        struct Response: Codable {
            let accounts: [PlaidAccount]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.accounts
    }

    func getTransactions(
        itemId: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [PlaidTransaction] {
        guard let config = config else {
            throw PlaidError.configurationError
        }

        let accessToken = try keychain.getPlaidAccessToken(forItemId: itemId)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let body: [String: Any] = [
            "client_id": config.clientId,
            "secret": config.secret,
            "access_token": accessToken,
            "start_date": dateFormatter.string(from: startDate),
            "end_date": dateFormatter.string(from: endDate)
        ]

        let data = try await makeRequest(
            endpoint: "/transactions/get",
            body: body
        )

        struct Response: Codable {
            let transactions: [PlaidTransaction]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.transactions
    }

    func getHoldings(itemId: String) async throws -> (holdings: [PlaidHolding], securities: [PlaidSecurity]) {
        guard let config = config else {
            throw PlaidError.configurationError
        }

        let accessToken = try keychain.getPlaidAccessToken(forItemId: itemId)

        let body: [String: Any] = [
            "client_id": config.clientId,
            "secret": config.secret,
            "access_token": accessToken
        ]

        let data = try await makeRequest(
            endpoint: "/investments/holdings/get",
            body: body
        )

        struct Response: Codable {
            let holdings: [PlaidHolding]
            let securities: [PlaidSecurity]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.holdings, response.securities)
    }

    func removeItem(itemId: String) async throws {
        guard let config = config else {
            throw PlaidError.configurationError
        }

        let accessToken = try keychain.getPlaidAccessToken(forItemId: itemId)

        let body: [String: Any] = [
            "client_id": config.clientId,
            "secret": config.secret,
            "access_token": accessToken
        ]

        _ = try await makeRequest(
            endpoint: "/item/remove",
            body: body
        )

        try keychain.deletePlaidAccessToken(forItemId: itemId)
    }

    private func makeRequest(endpoint: String, body: [String: Any]) async throws -> Data {
        guard let config = config else {
            throw PlaidError.configurationError
        }

        guard let url = URL(string: config.environment.baseURL + endpoint) else {
            throw PlaidError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaidError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(PlaidErrorResponse.self, from: data) {
                throw PlaidError.apiError(
                    errorResponse.errorCode,
                    errorResponse.errorMessage
                )
            }
            throw PlaidError.invalidResponse
        }

        return data
    }

    func mapAccountType(_ plaidType: String, subtype: String?) -> AccountType {
        switch plaidType.lowercased() {
        case "depository":
            if subtype?.lowercased() == "savings" {
                return .savings
            }
            return .checking
        case "credit":
            return .credit
        case "loan":
            return .loan
        case "investment":
            return .investment
        case "brokerage":
            return .investment
        default:
            return .other
        }
    }

    func mapAssetType(_ plaidType: String?) -> AssetType {
        guard let type = plaidType?.lowercased() else {
            return .other
        }

        switch type {
        case "equity", "stock":
            return .stock
        case "etf":
            return .etf
        case "mutual fund":
            return .mutualFund
        case "fixed income", "bond":
            return .bond
        case "cash":
            return .cash
        case "cryptocurrency":
            return .crypto
        case "derivative":
            return .option
        default:
            return .other
        }
    }
}

struct PlaidErrorResponse: Codable {
    let errorCode: String
    let errorMessage: String
    let errorType: String

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case errorType = "error_type"
    }
}
