import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("useBiometricAuth") private var useBiometricAuth = false
    @AppStorage("defaultCurrency") private var defaultCurrency = "USD"
    @AppStorage("priceRefreshInterval") private var priceRefreshInterval = 60

    @State private var showExport = false
    @State private var showPlaidManagement = false
    @State private var showAbout = false
    @State private var showReloadSampleDataAlert = false
    @State private var showDeleteAllDataAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("Security") {
                    Toggle(isOn: $useBiometricAuth) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(biometricLabel)
                                Text("Require authentication to open app")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: biometricIcon)
                        }
                    }
                    .disabled(authManager.biometricType == .none)

                    if authManager.biometricType == .none {
                        Text("Biometric authentication is not available on this device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Data") {
                    NavigationLink {
                        ExportView()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

                    NavigationLink {
                        PlaidManagementView()
                    } label: {
                        Label("Connected Accounts", systemImage: "link")
                    }

                    Button {
                        showReloadSampleDataAlert = true
                    } label: {
                        Label("Reload Sample Data", systemImage: "arrow.clockwise")
                    }
                }

                Section("Preferences") {
                    Picker(selection: $defaultCurrency) {
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                        Text("CAD").tag("CAD")
                        Text("AUD").tag("AUD")
                        Text("JPY").tag("JPY")
                    } label: {
                        Label("Default Currency", systemImage: "dollarsign.circle")
                    }

                    Picker(selection: $priceRefreshInterval) {
                        Text("1 minute").tag(60)
                        Text("5 minutes").tag(300)
                        Text("15 minutes").tag(900)
                        Text("1 hour").tag(3600)
                    } label: {
                        Label("Price Refresh", systemImage: "arrow.clockwise")
                    }
                }

                Section("About") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About WealthPlanner", systemImage: "info.circle")
                    }

                    Link(destination: URL(string: "https://plaid.com/legal")!) {
                        Label("Plaid Terms of Service", systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteAllDataAlert = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Reload Sample Data", isPresented: $showReloadSampleDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reload") {
                    reloadSampleData()
                }
            } message: {
                Text("This will add sample accounts, holdings, transactions, budgets, and goals to the app. Existing data will be preserved.")
            }
            .alert("Delete All Data", isPresented: $showDeleteAllDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This will permanently delete all accounts, transactions, holdings, budgets, and goals. This action cannot be undone.")
            }
        }
    }

    private func reloadSampleData() {
        SampleDataService.shared.resetSampleData()
        SampleDataService.shared.loadSampleDataIfNeeded(into: modelContext)
    }

    private func deleteAllData() {
        do {
            try modelContext.delete(model: Account.self)
            try modelContext.delete(model: Transaction.self)
            try modelContext.delete(model: Holding.self)
            try modelContext.delete(model: Budget.self)
            try modelContext.delete(model: Goal.self)
            try modelContext.save()
            SampleDataService.shared.resetSampleData()
        } catch {
            print("Failed to delete data: \(error)")
        }
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

struct PlaidManagementView: View {
    @State private var connectedItems: [String] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if connectedItems.isEmpty {
                ContentUnavailableView(
                    "No Connected Accounts",
                    systemImage: "link.badge.plus",
                    description: Text("Connect a bank to automatically sync transactions")
                )
            } else {
                ForEach(connectedItems, id: \.self) { itemId in
                    HStack {
                        Image(systemName: "building.columns")
                        Text("Connected Bank")
                        Spacer()
                        Text(String(itemId.suffix(8)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            // Disconnect
                        } label: {
                            Label("Disconnect", systemImage: "link.badge.minus")
                        }
                    }
                }
            }
        }
        .navigationTitle("Connected Accounts")
        .onAppear {
            connectedItems = KeychainManager.shared.getAllPlaidItemIds()
        }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)

                        Text("WealthPlanner")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Version 1.0.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical)
            }

            Section("Features") {
                FeatureListItem(
                    icon: "building.columns",
                    title: "Bank Connection",
                    description: "Securely connect to 10,000+ financial institutions via Plaid"
                )

                FeatureListItem(
                    icon: "chart.pie",
                    title: "Portfolio Tracking",
                    description: "Track stocks, ETFs, crypto, and more with real-time prices"
                )

                FeatureListItem(
                    icon: "chart.bar",
                    title: "Budget Management",
                    description: "Set budgets by category and track spending"
                )

                FeatureListItem(
                    icon: "flag",
                    title: "Financial Goals",
                    description: "Create and track savings goals with progress monitoring"
                )

                FeatureListItem(
                    icon: "lock.shield",
                    title: "Privacy First",
                    description: "All data stored locally on your device"
                )
            }

            Section("Credits") {
                Text("Built with SwiftUI and SwiftData")
                Text("Price data from Yahoo Finance")
                Text("Bank connections powered by Plaid")
            }
        }
        .navigationTitle("About")
    }
}

struct FeatureListItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationManager())
}
