import Foundation
import SwiftData

@MainActor
final class AccountsViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var selectedAccount: Account?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var searchText = ""

    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refresh() async {
        guard let modelContext = modelContext else { return }

        isLoading = true
        error = nil

        do {
            let repo = AccountRepository(modelContext: modelContext)
            accounts = try repo.fetchAll()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func createAccount(
        name: String,
        institution: String,
        type: AccountType,
        balance: Decimal,
        currency: String = "USD"
    ) async throws {
        guard let modelContext = modelContext else { return }

        let account = Account(
            name: name,
            institution: institution,
            type: type,
            balance: balance,
            currency: currency,
            isManual: true
        )

        let repo = AccountRepository(modelContext: modelContext)
        repo.create(account)
        try repo.save()

        await refresh()
    }

    func deleteAccount(_ account: Account) async throws {
        guard let modelContext = modelContext else { return }

        let repo = AccountRepository(modelContext: modelContext)
        repo.delete(account)
        try repo.save()

        await refresh()
    }

    func updateAccount(_ account: Account) async throws {
        guard let modelContext = modelContext else { return }

        let repo = AccountRepository(modelContext: modelContext)
        try repo.save()

        await refresh()
    }

    var filteredAccounts: [Account] {
        if searchText.isEmpty {
            return accounts
        }
        return accounts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.institution.localizedCaseInsensitiveContains(searchText)
        }
    }

    var accountsByType: [AccountType: [Account]] {
        Dictionary(grouping: filteredAccounts, by: { $0.type })
    }

    var assetAccounts: [Account] {
        filteredAccounts.filter { $0.type.isAsset }
    }

    var liabilityAccounts: [Account] {
        filteredAccounts.filter { !$0.type.isAsset }
    }

    var totalBalance: Decimal {
        accounts.reduce(0) { $0 + $1.effectiveBalance }
    }

    var formattedTotalBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: totalBalance as NSDecimalNumber) ?? "$0.00"
    }
}
