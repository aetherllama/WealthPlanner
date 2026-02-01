import Foundation

enum PriceServiceError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case symbolNotFound(String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from price service"
        case .symbolNotFound(let symbol):
            return "Symbol not found: \(symbol)"
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        }
    }
}

struct StockQuote {
    let symbol: String
    let price: Decimal
    let change: Decimal
    let changePercent: Double
    let previousClose: Decimal
    let open: Decimal?
    let high: Decimal?
    let low: Decimal?
    let volume: Int?
    let marketCap: Decimal?
    let timestamp: Date
}

struct CryptoQuote {
    let symbol: String
    let name: String
    let price: Decimal
    let change24h: Decimal
    let changePercent24h: Double
    let marketCap: Decimal?
    let volume24h: Decimal?
    let timestamp: Date
}

actor PriceCache {
    private var cache: [String: (quote: StockQuote, timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 60

    func get(_ symbol: String) -> StockQuote? {
        guard let cached = cache[symbol.uppercased()] else { return nil }

        if Date().timeIntervalSince(cached.timestamp) > cacheTimeout {
            cache.removeValue(forKey: symbol.uppercased())
            return nil
        }

        return cached.quote
    }

    func set(_ quote: StockQuote) {
        cache[quote.symbol.uppercased()] = (quote, Date())
    }

    func clear() {
        cache.removeAll()
    }
}

@MainActor
final class PriceService: ObservableObject {
    static let shared = PriceService()

    @Published var isLoading = false
    @Published var lastError: Error?

    private let cache = PriceCache()

    private init() {}

    func getQuote(for symbol: String) async throws -> StockQuote {
        if let cached = await cache.get(symbol) {
            return cached
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let quote = try await fetchYahooFinanceQuote(symbol: symbol)
            await cache.set(quote)
            return quote
        } catch {
            lastError = error
            throw error
        }
    }

    func getQuotes(for symbols: [String]) async throws -> [String: StockQuote] {
        var results: [String: StockQuote] = [:]
        var symbolsToFetch: [String] = []

        for symbol in symbols {
            if let cached = await cache.get(symbol) {
                results[symbol.uppercased()] = cached
            } else {
                symbolsToFetch.append(symbol)
            }
        }

        if !symbolsToFetch.isEmpty {
            isLoading = true
            defer { isLoading = false }

            let quotes = try await fetchYahooFinanceQuotes(symbols: symbolsToFetch)

            for quote in quotes {
                results[quote.symbol] = quote
                await cache.set(quote)
            }
        }

        return results
    }

    private func fetchYahooFinanceQuote(symbol: String) async throws -> StockQuote {
        let quotes = try await fetchYahooFinanceQuotes(symbols: [symbol])

        guard let quote = quotes.first else {
            throw PriceServiceError.symbolNotFound(symbol)
        }

        return quote
    }

    private func fetchYahooFinanceQuotes(symbols: [String]) async throws -> [StockQuote] {
        let symbolList = symbols.map { $0.uppercased() }.joined(separator: ",")

        guard let url = URL(string: "https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(symbolList)") else {
            throw PriceServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PriceServiceError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw PriceServiceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw PriceServiceError.invalidResponse
        }

        return try parseYahooFinanceResponse(data)
    }

    private func parseYahooFinanceResponse(_ data: Data) throws -> [StockQuote] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quoteResponse = json["quoteResponse"] as? [String: Any],
              let result = quoteResponse["result"] as? [[String: Any]] else {
            throw PriceServiceError.invalidResponse
        }

        var quotes: [StockQuote] = []

        for item in result {
            guard let symbol = item["symbol"] as? String else { continue }

            let regularMarketPrice = item["regularMarketPrice"] as? Double ?? 0
            let regularMarketChange = item["regularMarketChange"] as? Double ?? 0
            let regularMarketChangePercent = item["regularMarketChangePercent"] as? Double ?? 0
            let regularMarketPreviousClose = item["regularMarketPreviousClose"] as? Double ?? 0
            let regularMarketOpen = item["regularMarketOpen"] as? Double
            let regularMarketDayHigh = item["regularMarketDayHigh"] as? Double
            let regularMarketDayLow = item["regularMarketDayLow"] as? Double
            let regularMarketVolume = item["regularMarketVolume"] as? Int
            let marketCap = item["marketCap"] as? Double

            let quote = StockQuote(
                symbol: symbol,
                price: Decimal(regularMarketPrice),
                change: Decimal(regularMarketChange),
                changePercent: regularMarketChangePercent,
                previousClose: Decimal(regularMarketPreviousClose),
                open: regularMarketOpen.map { Decimal($0) },
                high: regularMarketDayHigh.map { Decimal($0) },
                low: regularMarketDayLow.map { Decimal($0) },
                volume: regularMarketVolume,
                marketCap: marketCap.map { Decimal($0) },
                timestamp: Date()
            )

            quotes.append(quote)
        }

        return quotes
    }

    func getCryptoQuote(for symbol: String) async throws -> CryptoQuote {
        let coinId = mapCryptoSymbolToCoinGeckoId(symbol)

        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(coinId)&vs_currencies=usd&include_24hr_change=true&include_market_cap=true&include_24hr_vol=true") else {
            throw PriceServiceError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PriceServiceError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw PriceServiceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw PriceServiceError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let coinData = json[coinId] as? [String: Any],
              let price = coinData["usd"] as? Double else {
            throw PriceServiceError.symbolNotFound(symbol)
        }

        let change24h = coinData["usd_24h_change"] as? Double ?? 0
        let marketCap = coinData["usd_market_cap"] as? Double
        let volume24h = coinData["usd_24h_vol"] as? Double

        return CryptoQuote(
            symbol: symbol.uppercased(),
            name: coinId.capitalized,
            price: Decimal(price),
            change24h: Decimal(price * change24h / 100),
            changePercent24h: change24h,
            marketCap: marketCap.map { Decimal($0) },
            volume24h: volume24h.map { Decimal($0) },
            timestamp: Date()
        )
    }

    private func mapCryptoSymbolToCoinGeckoId(_ symbol: String) -> String {
        let mapping: [String: String] = [
            "BTC": "bitcoin",
            "ETH": "ethereum",
            "USDT": "tether",
            "BNB": "binancecoin",
            "SOL": "solana",
            "XRP": "ripple",
            "USDC": "usd-coin",
            "ADA": "cardano",
            "AVAX": "avalanche-2",
            "DOGE": "dogecoin",
            "DOT": "polkadot",
            "TRX": "tron",
            "MATIC": "matic-network",
            "LINK": "chainlink",
            "TON": "the-open-network",
            "SHIB": "shiba-inu",
            "LTC": "litecoin",
            "BCH": "bitcoin-cash",
            "XLM": "stellar",
            "UNI": "uniswap"
        ]

        return mapping[symbol.uppercased()] ?? symbol.lowercased()
    }

    func refreshPrices(for holdings: [Holding]) async throws {
        var stockSymbols: [String] = []
        var cryptoSymbols: [String] = []

        for holding in holdings {
            if holding.assetType == .crypto {
                cryptoSymbols.append(holding.symbol)
            } else if holding.assetType != .cash {
                stockSymbols.append(holding.symbol)
            }
        }

        if !stockSymbols.isEmpty {
            let quotes = try await getQuotes(for: stockSymbols)

            for holding in holdings where quotes[holding.symbol.uppercased()] != nil {
                if let quote = quotes[holding.symbol.uppercased()] {
                    holding.currentPrice = quote.price
                    holding.lastPriceUpdate = quote.timestamp
                }
            }
        }

        for symbol in cryptoSymbols {
            do {
                let quote = try await getCryptoQuote(for: symbol)

                for holding in holdings where holding.symbol.uppercased() == symbol.uppercased() {
                    holding.currentPrice = quote.price
                    holding.lastPriceUpdate = quote.timestamp
                }
            } catch {
                continue
            }
        }
    }

    func clearCache() async {
        await cache.clear()
    }
}
