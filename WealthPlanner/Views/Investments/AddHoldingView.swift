import SwiftUI
import SwiftData

struct AddHoldingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let account: Account

    @State private var symbol = ""
    @State private var name = ""
    @State private var quantity: Decimal = 0
    @State private var costBasis: Decimal = 0
    @State private var assetType: AssetType = .stock
    @State private var notes = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?

    private let priceService = PriceService.shared

    var isValid: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        quantity > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Symbol (e.g., AAPL)", text: $symbol)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()

                        if isLookingUp {
                            ProgressView()
                        } else {
                            Button("Lookup") {
                                Task {
                                    await lookupSymbol()
                                }
                            }
                            .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    TextField("Name", text: $name)

                    if let error = lookupError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("Asset Type", selection: $assetType) {
                        ForEach(AssetType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("Quantity", value: $quantity, format: .number.precision(.fractionLength(0...6)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Cost Basis per Share")
                        Spacer()
                        TextField("Cost", value: $costBasis, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if quantity > 0 && costBasis > 0 {
                        Text("Total Cost: \(formatCurrency(quantity * costBasis))")
                    }
                }

                Section("Notes (optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Text("Account: \(account.name)")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await addHolding()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func lookupSymbol() async {
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmedSymbol.isEmpty else { return }

        isLookingUp = true
        lookupError = nil

        do {
            if assetType == .crypto {
                let quote = try await priceService.getCryptoQuote(for: trimmedSymbol)
                name = quote.name
                if costBasis == 0 {
                    costBasis = quote.price
                }
            } else {
                let quote = try await priceService.getQuote(for: trimmedSymbol)
                symbol = quote.symbol
                if name.isEmpty {
                    name = quote.symbol
                }
                if costBasis == 0 {
                    costBasis = quote.price
                }
            }
        } catch PriceServiceError.symbolNotFound {
            lookupError = "Symbol not found"
        } catch PriceServiceError.rateLimited {
            lookupError = "Rate limited. Please try again later."
        } catch {
            lookupError = "Lookup failed"
        }

        isLookingUp = false
    }

    private func addHolding() async {
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
            symbol: symbol.uppercased(),
            name: name,
            quantity: quantity,
            costBasis: costBasis,
            currentPrice: currentPrice,
            assetType: assetType,
            notes: notes.isEmpty ? nil : notes
        )

        holding.account = account
        modelContext.insert(holding)
        try? modelContext.save()
        dismiss()
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

#Preview {
    AddHoldingView(account: Account(
        name: "Brokerage",
        institution: "Fidelity",
        type: .investment
    ))
    .modelContainer(for: [Account.self, Holding.self])
}
