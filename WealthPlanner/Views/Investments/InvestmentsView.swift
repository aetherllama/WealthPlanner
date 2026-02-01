import SwiftUI
import SwiftData
import Charts

struct InvestmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = InvestmentsViewModel()
    @StateObject private var exportService = ExportService.shared
    @State private var showAddHolding = false
    @State private var selectedAccount: Account?
    @State private var showExportSheet = false
    @State private var exportData: Data?
    @State private var exportFilename: String?

    @Query(sort: [SortDescriptor(\Account.name)]) private var allAccounts: [Account]

    private var investmentAccounts: [Account] {
        allAccounts.filter { $0.type == .investment || $0.type == .retirement || $0.type == .crypto }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PortfolioSummaryCard(
                        totalValue: viewModel.formattedTotalValue,
                        totalGainLoss: viewModel.formattedTotalGainLoss,
                        totalGainLossPercent: viewModel.formattedTotalGainLossPercent,
                        isGain: viewModel.totalGainLoss >= 0
                    )

                    if !viewModel.allocationData.isEmpty {
                        InvestmentAllocationChart(data: viewModel.allocationData)
                    }

                    if !viewModel.holdings.isEmpty {
                        HoldingsListSection(
                            holdings: viewModel.filteredHoldings,
                            onDelete: { holding in
                                Task {
                                    try await viewModel.deleteHolding(holding)
                                }
                            }
                        )
                    } else if !viewModel.isLoading {
                        ContentUnavailableView {
                            Label("No Holdings", systemImage: "chart.line.uptrend.xyaxis")
                        } description: {
                            Text("Add your first investment holding to track your portfolio")
                        } actions: {
                            Button("Add Holding") {
                                if let account = investmentAccounts.first {
                                    selectedAccount = account
                                    showAddHolding = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(investmentAccounts.isEmpty)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Investments")
            .searchable(text: $viewModel.searchText, prompt: "Search holdings")
            .refreshable {
                await viewModel.refresh()
                await viewModel.refreshPrices()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            if let account = investmentAccounts.first {
                                selectedAccount = account
                                showAddHolding = true
                            }
                        } label: {
                            Label("Add Holding", systemImage: "plus")
                        }
                        .disabled(investmentAccounts.isEmpty)

                        Button {
                            Task {
                                await viewModel.refreshPrices()
                            }
                        } label: {
                            Label("Refresh Prices", systemImage: "arrow.clockwise")
                        }
                        .disabled(viewModel.holdings.isEmpty || viewModel.isRefreshingPrices)

                        Divider()

                        Button {
                            Task {
                                await exportHoldings(format: .csv)
                            }
                        } label: {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.holdings.isEmpty)

                        Button {
                            Task {
                                await exportHoldings(format: .json)
                            }
                        } label: {
                            Label("Export JSON", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.holdings.isEmpty)

                        Button {
                            Task {
                                await exportHoldings(format: .pdf)
                            }
                        } label: {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }
                        .disabled(viewModel.holdings.isEmpty)
                    } label: {
                        if viewModel.isRefreshingPrices {
                            ProgressView()
                        } else {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let data = exportData, let filename = exportFilename {
                    ExportShareSheet(data: data, filename: filename)
                }
            }
            .onAppear {
                viewModel.configure(modelContext: modelContext)
                Task {
                    await viewModel.refresh()
                }
            }
            .sheet(isPresented: $showAddHolding) {
                if let account = selectedAccount ?? investmentAccounts.first {
                    AddHoldingView(account: account)
                }
            }
        }
    }

    private func exportHoldings(format: ExportFormat) async {
        var options = ExportOptions()
        options.format = format
        options.dataType = .holdings

        do {
            let result = try await exportService.export(
                modelContext: modelContext,
                options: options
            )
            exportData = result.data
            exportFilename = result.filename
            showExportSheet = true
        } catch {
            print("Export error: \(error)")
        }
    }
}

struct PortfolioSummaryCard: View {
    let totalValue: String
    let totalGainLoss: String
    let totalGainLossPercent: String
    let isGain: Bool

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Portfolio Value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(totalValue)
                    .font(.system(size: 36, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Image(systemName: isGain ? "arrow.up.right" : "arrow.down.right")
                    .foregroundColor(isGain ? .green : .red)

                Text(totalGainLoss)
                    .fontWeight(.semibold)
                    .foregroundColor(isGain ? .green : .red)

                Text("(\(totalGainLossPercent))")
                    .foregroundColor(isGain ? .green : .red)
            }
            .font(.title3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct InvestmentAllocationChart: View {
    let data: [(type: AssetType, value: Double, percentage: Double)]

    private let colors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allocation")
                .font(.headline)

            HStack(spacing: 20) {
                Chart(data, id: \.type) { item in
                    SectorMark(
                        angle: .value("Value", item.value),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Type", item.type.rawValue))
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(data.enumerated()), id: \.element.type) { index, item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colors[index % colors.count])
                                .frame(width: 8, height: 8)

                            Text(item.type.rawValue)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            Text(String(format: "%.1f%%", item.percentage))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct HoldingsListSection: View {
    let holdings: [Holding]
    let onDelete: (Holding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Holdings")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(holdings) { holding in
                NavigationLink {
                    HoldingDetailView(holding: holding)
                } label: {
                    HoldingCard(holding: holding)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        onDelete(holding)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
}

struct HoldingCard: View {
    let holding: Holding

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(holding.symbol)
                        .font(.headline)

                    Image(systemName: holding.assetType.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(holding.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(holding.quantity, format: .number.precision(.fractionLength(0...4))) shares")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(holding.displayValue)
                    .font(.headline)

                HStack(spacing: 4) {
                    Image(systemName: holding.isGain ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)

                    Text(holding.displayGainLoss)
                        .font(.caption)
                }
                .foregroundColor(holding.isGain ? .green : .red)

                Text(holding.displayGainLossPercent)
                    .font(.caption2)
                    .foregroundColor(holding.isGain ? .green : .red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ExportShareSheet: UIViewControllerRepresentable {
    let data: Data
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)

        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        return activityVC
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    InvestmentsView()
        .modelContainer(for: [Account.self, Holding.self, Transaction.self])
}
