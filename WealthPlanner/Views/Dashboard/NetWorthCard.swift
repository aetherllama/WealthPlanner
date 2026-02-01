import SwiftUI

struct NetWorthCard: View {
    let netWorth: String
    let assets: String
    let liabilities: String

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Net Worth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(netWorth)
                    .font(.system(size: 36, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text("Assets")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(assets)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }

                VStack(spacing: 4) {
                    Text("Liabilities")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(liabilities)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    NetWorthCard(
        netWorth: "$125,430.52",
        assets: "$150,000.00",
        liabilities: "$24,569.48"
    )
    .padding()
}
