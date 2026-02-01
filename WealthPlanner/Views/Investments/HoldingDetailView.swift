import SwiftUI
import SwiftData

struct HoldingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var holding: Holding
    @State private var showEditSheet = false
    @State private var isRefreshing = false

    private let priceService = PriceService.shared

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(holding.symbol)
                                .font(.largeTitle)
                                .fontWeight(.bold)

                            Text(holding.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: holding.assetType.icon)
                            .font(.title)
                            .foregroundStyle(.blue)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Current Value")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(holding.displayValue)
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Gain/Loss")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: holding.isGain ? "arrow.up.right" : "arrow.down.right")
                                Text(holding.displayGainLoss)
                            }
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(holding.isGain ? .green : .red)

                            Text(holding.displayGainLossPercent)
                                .font(.caption)
                                .foregroundColor(holding.isGain ? .green : .red)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Position Details") {
                LabeledContent("Quantity") {
                    Text("\(holding.quantity, format: .number.precision(.fractionLength(0...6)))")
                }

                LabeledContent("Current Price") {
                    HStack {
                        Text(formatCurrency(holding.currentPrice))

                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button {
                                Task {
                                    await refreshPrice()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                        }
                    }
                }

                LabeledContent("Cost Basis") {
                    Text(formatCurrency(holding.costBasis))
                }

                LabeledContent("Total Cost") {
                    Text(formatCurrency(holding.totalCost))
                }
            }

            Section("Additional Info") {
                LabeledContent("Asset Type", value: holding.assetType.rawValue)

                if let account = holding.account {
                    LabeledContent("Account", value: account.name)
                }

                if let lastUpdate = holding.lastPriceUpdate {
                    LabeledContent("Price Updated") {
                        Text(lastUpdate, style: .relative)
                    }
                }
            }

            if let notes = holding.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            Section {
                Button(role: .destructive) {
                    modelContext.delete(holding)
                    try? modelContext.save()
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Holding")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Holding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditHoldingView(holding: holding)
        }
    }

    private func refreshPrice() async {
        isRefreshing = true

        do {
            if holding.assetType == .crypto {
                let quote = try await priceService.getCryptoQuote(for: holding.symbol)
                holding.currentPrice = quote.price
            } else {
                let quote = try await priceService.getQuote(for: holding.symbol)
                holding.currentPrice = quote.price
            }
            holding.lastPriceUpdate = Date()
            try modelContext.save()
        } catch {
            // Handle error silently for now
        }

        isRefreshing = false
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

struct EditHoldingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var holding: Holding

    @State private var symbol: String
    @State private var name: String
    @State private var quantity: Decimal
    @State private var costBasis: Decimal
    @State private var assetType: AssetType
    @State private var notes: String

    init(holding: Holding) {
        self.holding = holding
        _symbol = State(initialValue: holding.symbol)
        _name = State(initialValue: holding.name)
        _quantity = State(initialValue: holding.quantity)
        _costBasis = State(initialValue: holding.costBasis)
        _assetType = State(initialValue: holding.assetType)
        _notes = State(initialValue: holding.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Symbol", text: $symbol)
                        .textInputAutocapitalization(.characters)

                    TextField("Name", text: $name)
                }

                Section {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("Quantity", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Cost Basis")
                        Spacer()
                        TextField("Cost Basis", value: $costBasis, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("Asset Type", selection: $assetType) {
                        ForEach(AssetType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        holding.symbol = symbol.uppercased()
                        holding.name = name
                        holding.quantity = quantity
                        holding.costBasis = costBasis
                        holding.assetType = assetType
                        holding.notes = notes.isEmpty ? nil : notes
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HoldingDetailView(holding: Holding(
            symbol: "AAPL",
            name: "Apple Inc.",
            quantity: 100,
            costBasis: 150,
            currentPrice: 175,
            assetType: .stock
        ))
    }
    .modelContainer(for: [Account.self, Holding.self])
}
