import SwiftUI
import UIKit

struct PlaidLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var plaidService = PlaidService.shared

    @State private var isLoading = false
    @State private var error: Error?
    @State private var showPlaidLink = false
    @State private var linkToken: String?

    let onSuccess: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isLoading {
                    ProgressView("Preparing secure connection...")
                } else if let error = error {
                    ErrorStateView(error: error) {
                        self.error = nil
                        Task {
                            await createLinkToken()
                        }
                    }
                } else if !plaidService.isConfigured {
                    PlaidNotConfiguredView()
                } else {
                    PlaidInfoView {
                        Task {
                            await createLinkToken()
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Connect Bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPlaidLink) {
                if let token = linkToken {
                    PlaidLinkWebView(linkToken: token) { publicToken in
                        Task {
                            await exchangeToken(publicToken)
                        }
                    } onExit: {
                        showPlaidLink = false
                    }
                }
            }
        }
    }

    private func createLinkToken() async {
        isLoading = true
        error = nil

        do {
            let userId = UUID().uuidString
            linkToken = try await plaidService.createLinkToken(userId: userId)
            showPlaidLink = true
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func exchangeToken(_ publicToken: String) async {
        isLoading = true

        do {
            let accessToken = try await plaidService.exchangePublicToken(publicToken)
            onSuccess(accessToken.itemId)
            dismiss()
        } catch {
            self.error = error
        }

        isLoading = false
    }
}

struct PlaidInfoView: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "building.columns.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Connect Your Bank")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "lock.shield",
                    title: "Bank-Level Security",
                    description: "Your credentials are never stored on your device"
                )

                FeatureRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Automatic Sync",
                    description: "Transactions update automatically"
                )

                FeatureRow(
                    icon: "eye.slash",
                    title: "Read-Only Access",
                    description: "We can only view transactions, not move money"
                )
            }
            .padding()

            Spacer()

            Button {
                onConnect()
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text("Connect with Plaid")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text("Powered by Plaid")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
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
    }
}

struct PlaidNotConfiguredView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Plaid Not Configured")
                .font(.headline)

            Text("Bank connection requires Plaid API credentials. This feature is available in sandbox mode for development.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Configure your Plaid credentials in PlaidService.swift to enable this feature.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }
}

struct ErrorStateView: View {
    let error: Error
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text("Connection Failed")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct PlaidLinkWebView: UIViewControllerRepresentable {
    let linkToken: String
    let onSuccess: (String) -> Void
    let onExit: () -> Void

    func makeUIViewController(context: Context) -> PlaidLinkViewController {
        PlaidLinkViewController(
            linkToken: linkToken,
            onSuccess: onSuccess,
            onExit: onExit
        )
    }

    func updateUIViewController(_ uiViewController: PlaidLinkViewController, context: Context) {}
}

class PlaidLinkViewController: UIViewController {
    let linkToken: String
    let onSuccess: (String) -> Void
    let onExit: () -> Void

    init(linkToken: String, onSuccess: @escaping (String) -> Void, onExit: @escaping () -> Void) {
        self.linkToken = linkToken
        self.onSuccess = onSuccess
        self.onExit = onExit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Plaid Link would open here.\nIn production, integrate the Plaid Link SDK."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.onSuccess("sandbox-public-token-\(UUID().uuidString)")
        }
    }
}

#Preview {
    PlaidLinkView { _ in }
}
