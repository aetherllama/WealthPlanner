import SwiftUI
import SwiftData
import LocalAuthentication

@main
struct WealthPlannerApp: App {
    @StateObject private var authManager = AuthenticationManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Account.self,
            Holding.self,
            Transaction.self,
            Goal.self,
            Budget.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(authManager)
                    .onAppear {
                        loadSampleDataIfNeeded()
                    }
            } else {
                AuthenticationView()
                    .environmentObject(authManager)
            }
        }
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func loadSampleDataIfNeeded() {
        let context = sharedModelContainer.mainContext
        SampleDataService.shared.loadSampleDataIfNeeded(into: context)
    }
}

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var biometricType: BiometricType = .none

    @AppStorage("useBiometricAuth") var useBiometricAuth = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

    enum BiometricType {
        case none
        case faceID
        case touchID
    }

    init() {
        checkBiometricType()
        if !useBiometricAuth || !hasCompletedOnboarding {
            isAuthenticated = true
        }
    }

    func checkBiometricType() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            default:
                biometricType = .none
            }
        } else {
            biometricType = .none
        }
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fall back to passcode
            return await authenticateWithPasscode()
        }

        do {
            let reason = "Authenticate to access your financial data"
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            await MainActor.run {
                isAuthenticated = success
            }
            return success
        } catch {
            return await authenticateWithPasscode()
        }
    }

    private func authenticateWithPasscode() async -> Bool {
        let context = LAContext()

        do {
            let reason = "Authenticate to access your financial data"
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )

            await MainActor.run {
                isAuthenticated = success
            }
            return success
        } catch {
            return false
        }
    }

    func lock() {
        isAuthenticated = false
    }
}

struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var isAuthenticating = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("WealthPlanner")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your financial data is protected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task {
                    isAuthenticating = true
                    _ = await authManager.authenticate()
                    isAuthenticating = false
                }
            } label: {
                HStack {
                    if isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: authManager.biometricType == .faceID ? "faceid" : "touchid")
                        Text("Unlock")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isAuthenticating)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .onAppear {
            if authManager.useBiometricAuth {
                Task {
                    _ = await authManager.authenticate()
                }
            }
        }
    }
}
