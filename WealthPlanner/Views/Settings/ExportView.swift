import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var exportService = ExportService.shared

    @State private var selectedFormat: ExportFormat = .csv
    @State private var selectedDataType: ExportDataType = .transactions
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
    @State private var endDate = Date()
    @State private var useDateFilter = false

    @State private var isExporting = false
    @State private var exportedData: Data?
    @State private var exportedFilename: String?
    @State private var showShareSheet = false
    @State private var error: Error?

    @Query private var accounts: [Account]
    @State private var selectedAccounts: Set<UUID> = []

    var body: some View {
        Form {
            Section {
                Picker("Data Type", selection: $selectedDataType) {
                    ForEach(ExportDataType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                Picker("Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
            }

            if selectedDataType == .transactions {
                Section("Date Range") {
                    Toggle("Filter by Date", isOn: $useDateFilter)

                    if useDateFilter {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }
            }

            if selectedDataType != .fullBackup && !accounts.isEmpty {
                Section("Accounts") {
                    ForEach(accounts) { account in
                        HStack {
                            Image(systemName: account.type.icon)
                                .foregroundStyle(.blue)

                            Text(account.name)

                            Spacer()

                            if selectedAccounts.contains(account.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedAccounts.contains(account.id) {
                                selectedAccounts.remove(account.id)
                            } else {
                                selectedAccounts.insert(account.id)
                            }
                        }
                    }

                    Button(selectedAccounts.isEmpty ? "Select All" : "Clear Selection") {
                        if selectedAccounts.isEmpty {
                            selectedAccounts = Set(accounts.map { $0.id })
                        } else {
                            selectedAccounts.removeAll()
                        }
                    }
                }
            }

            Section {
                Button {
                    Task {
                        await performExport()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("Export")
                        Spacer()
                    }
                }
                .disabled(isExporting)
            }

            if let error = error {
                Section {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Info") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Formats:")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("CSV - Compatible with Excel, Numbers, Google Sheets")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("JSON - Full data backup, can be re-imported")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("PDF - Printable report format")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Export")
        .sheet(isPresented: $showShareSheet) {
            if let data = exportedData, let filename = exportedFilename {
                ShareSheet(data: data, filename: filename, format: selectedFormat)
            }
        }
    }

    private func performExport() async {
        isExporting = true
        error = nil

        var options = ExportOptions()
        options.format = selectedFormat
        options.dataType = selectedDataType

        if useDateFilter {
            options.startDate = startDate
            options.endDate = endDate
        }

        if !selectedAccounts.isEmpty {
            options.selectedAccounts = accounts.filter { selectedAccounts.contains($0.id) }
        }

        do {
            let result = try await exportService.export(
                modelContext: modelContext,
                options: options
            )

            exportedData = result.data
            exportedFilename = result.filename
            showShareSheet = true
        } catch {
            self.error = error
        }

        isExporting = false
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let data: Data
    let filename: String
    let format: ExportFormat

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

struct SecuritySettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @AppStorage("useBiometricAuth") private var useBiometricAuth = false
    @AppStorage("autoLockTimeout") private var autoLockTimeout = 0

    var body: some View {
        Form {
            Section("Authentication") {
                Toggle(isOn: $useBiometricAuth) {
                    HStack {
                        Image(systemName: biometricIcon)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(biometricLabel)
                            Text("Require authentication to open app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(authManager.biometricType == .none)

                if authManager.biometricType == .none {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Biometric authentication not available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Auto-Lock") {
                Picker("Lock After", selection: $autoLockTimeout) {
                    Text("Immediately").tag(0)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("Never").tag(-1)
                }
            }

            Section("Data Security") {
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Local Storage Only")
                        Text("Your data never leaves your device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "key")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Encrypted Credentials")
                        Text("Plaid tokens stored in Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Security")
    }

    private var biometricLabel: String {
        switch authManager.biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .none: return "Biometric Auth"
        }
    }

    private var biometricIcon: String {
        switch authManager.biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock"
        }
    }
}

#Preview {
    NavigationStack {
        ExportView()
    }
    .modelContainer(for: [Account.self, Transaction.self, Holding.self])
}
