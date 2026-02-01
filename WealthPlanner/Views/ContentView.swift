import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(0)

            AccountsView()
                .tabItem {
                    Label("Accounts", systemImage: "building.columns")
                }
                .tag(1)

            InvestmentsView()
                .tabItem {
                    Label("Invest", systemImage: "chart.pie")
                }
                .tag(2)

            BudgetView()
                .tabItem {
                    Label("Budget", systemImage: "chart.bar")
                }
                .tag(3)

            GoalsView()
                .tabItem {
                    Label("Goals", systemImage: "flag")
                }
                .tag(4)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(5)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationManager())
        .modelContainer(for: [Account.self, Holding.self, Transaction.self, Goal.self, Budget.self])
}
