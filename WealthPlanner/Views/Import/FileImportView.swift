import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FileImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var importService = ImportService.shared

    @State private var showFilePicker = false
    @State private var importResult: ImportResult?
    @State private var error: Error?

    @Query private var accounts: [Account]

    @State private var selectedAccount: Account?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if importService.isImporting {
                    ImportProgressView(
                        progress: importService.progress,
                        status: importService.statusMessage
                    )
                } else if let result = importResult {
                    ImportResultView(result: result) {
                        dismiss()
                    }
                } else {
                    ImportOptionsView(
                        onSelectFile: {
                            showFilePicker = true
                        },
                        onConnectBank: {
                            // Plaid connection would go here
                        },
                        onLoadSampleHoldings: {
                            loadSampleFile(named: "sample_holdings", type: "csv")
                        },
                        onLoadSampleTransactions: {
                            loadSampleFile(named: "sample_transactions", type: "csv")
                        }
                    )
                }

                if let error = error {
                    ErrorView(error: error) {
                        self.error = nil
                    }
                }
            }
            .padding()
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: ImportService.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await importFile(url)
            }

        case .failure(let error):
            self.error = error
        }
    }

    private func importFile(_ url: URL) async {
        do {
            let result = try await importService.importFile(
                at: url,
                into: modelContext,
                targetAccount: selectedAccount
            )
            importResult = result
        } catch {
            self.error = error
        }
    }

    private func loadSampleFile(named name: String, type: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: type) else {
            self.error = NSError(
                domain: "FileImport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Sample file not found in app bundle"]
            )
            return
        }

        Task {
            await importFile(url)
        }
    }
}

struct ImportOptionsView: View {
    let onSelectFile: () -> Void
    let onConnectBank: () -> Void
    var onLoadSampleHoldings: (() -> Void)?
    var onLoadSampleTransactions: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Import Financial Data")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import transactions and holdings from your bank or brokerage")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onSelectFile()
                } label: {
                    HStack {
                        Image(systemName: "doc")
                        Text("Import from File")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("Supports CSV, OFX, QFX, QIF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Sample Files Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Sample Files")
                    .font(.headline)
                    .padding(.top, 8)

                Text("Try importing these sample files to see how it works")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        onLoadSampleHoldings?()
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar")
                            Text("Sample Holdings")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green.opacity(0.1))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        onLoadSampleTransactions?()
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("Sample Transactions")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.1))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
    }
}

struct ImportProgressView: View {
    let progress: Double
    let status: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 200)

            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

struct ImportResultView: View {
    let result: ImportResult
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Import Complete")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                if result.accountsCreated > 0 {
                    Label("\(result.accountsCreated) account(s) created", systemImage: "building.columns")
                }

                if result.transactionsImported > 0 {
                    Label("\(result.transactionsImported) transaction(s) imported", systemImage: "list.bullet")
                }

                if result.holdingsImported > 0 {
                    Label("\(result.holdingsImported) holding(s) imported", systemImage: "chart.bar")
                }
            }
            .font(.subheadline)

            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warnings:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(result.errors, id: \.self) { error in
                        Text("- \(error)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            Button {
                onDone()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct ErrorView: View {
    let error: Error
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.red)

            Text("Import Failed")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                onDismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    FileImportView()
        .modelContainer(for: [Account.self, Transaction.self])
}
