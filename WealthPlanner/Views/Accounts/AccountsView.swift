import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = AccountsViewModel()
    @StateObject private var syncService = PlaidSyncService.shared
    @State private var showAddAccount = false
    @State private var showImport = false
    @State private var showConnectBank = false
    @State private var accountToDelete: Account?
    @State private var showDeleteConfirmation = false
    @State private var showSyncResult = false
    @State private var syncResult: SyncResult?

    var body: some View {
        NavigationStack {
            List {
                // Connected Accounts Sync Section
                if hasConnectedAccounts {
                    Section {
                        Button {
                            Task {
                                await syncConnectedAccounts()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.blue)
                                Text("Sync Connected Accounts")
                                Spacer()
                                if syncService.isSyncing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(syncService.isSyncing)
                    }
                }

                if !viewModel.assetAccounts.isEmpty {
                    Section("Assets") {
                        ForEach(viewModel.assetAccounts) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                AccountRow(account: account)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    accountToDelete = account
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if !viewModel.liabilityAccounts.isEmpty {
                    Section("Liabilities") {
                        ForEach(viewModel.liabilityAccounts) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                AccountRow(account: account)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    accountToDelete = account
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if viewModel.accounts.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView {
                        Label("No Accounts", systemImage: "building.columns")
                    } description: {
                        Text("Add accounts manually or connect to your bank")
                    } actions: {
                        VStack(spacing: 12) {
                            Button {
                                showConnectBank = true
                            } label: {
                                Label("Connect Bank", systemImage: "link")
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Add Manually") {
                                showAddAccount = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .searchable(text: $viewModel.searchText, prompt: "Search accounts")
            .refreshable {
                await viewModel.refresh()
                if hasConnectedAccounts {
                    await syncConnectedAccounts()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showConnectBank = true
                        } label: {
                            Label("Connect Bank", systemImage: "link")
                        }

                        Divider()

                        Button {
                            showAddAccount = true
                        } label: {
                            Label("Add Manually", systemImage: "plus")
                        }

                        Button {
                            showImport = true
                        } label: {
                            Label("Import File", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                viewModel.configure(modelContext: modelContext)
                Task {
                    await viewModel.refresh()
                }
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountView { name, institution, type, balance in
                    Task {
                        try await viewModel.createAccount(
                            name: name,
                            institution: institution,
                            type: type,
                            balance: balance
                        )
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                FileImportView()
            }
            .sheet(isPresented: $showConnectBank) {
                PlaidLinkView { itemId in
                    Task {
                        let result = try? await syncService.syncItem(
                            itemId: itemId,
                            modelContext: modelContext
                        )
                        syncResult = result
                        showSyncResult = true
                        await viewModel.refresh()
                    }
                }
            }
            .alert("Sync Complete", isPresented: $showSyncResult) {
                Button("OK") {}
            } message: {
                if let result = syncResult {
                    Text(result.summary)
                }
            }
            .confirmationDialog(
                "Delete Account",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let account = accountToDelete {
                        Task {
                            try await viewModel.deleteAccount(account)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this account? All associated transactions and holdings will also be deleted.")
            }
        }
    }

    private var hasConnectedAccounts: Bool {
        !KeychainManager.shared.getAllPlaidItemIds().isEmpty
    }

    private func syncConnectedAccounts() async {
        do {
            syncResult = try await syncService.syncAllAccounts(modelContext: modelContext)
            showSyncResult = true
            await viewModel.refresh()
        } catch {
            syncResult = SyncResult(
                accountsSynced: 0,
                transactionsSynced: 0,
                holdingsSynced: 0,
                errors: [error.localizedDescription]
            )
            showSyncResult = true
        }
    }
}

struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    Text(account.institution)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !account.isManual {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(account.displayBalance)
                    .font(.headline)
                    .foregroundColor(account.type.isAsset ? .primary : .red)

                if let lastSynced = account.lastSynced {
                    Text("Updated \(lastSynced, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AccountsView()
        .modelContainer(for: [Account.self, Holding.self, Transaction.self])
}
