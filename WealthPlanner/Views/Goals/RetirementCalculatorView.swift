import SwiftUI
import Charts

struct RetirementCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = GoalsViewModel()

    @State private var currentAge = 30
    @State private var retirementAge = 65
    @State private var currentSavings: Decimal = 50000
    @State private var monthlyContribution: Decimal = 1000
    @State private var expectedReturn: Double = 7.0
    @State private var inflationRate: Double = 3.0
    @State private var showAdvanced = false

    var projection: RetirementProjection {
        viewModel.calculateRetirement(
            currentAge: currentAge,
            retirementAge: retirementAge,
            currentSavings: currentSavings,
            monthlyContribution: monthlyContribution,
            expectedReturn: expectedReturn,
            inflationRate: inflationRate
        )
    }

    var projectionData: [(age: Int, value: Double)] {
        var data: [(age: Int, value: Double)] = []
        var balance = Double(truncating: currentSavings as NSDecimalNumber)
        let monthlyReturn = expectedReturn / 12 / 100
        let monthlyContrib = Double(truncating: monthlyContribution as NSDecimalNumber)

        for age in currentAge...retirementAge {
            data.append((age: age, value: balance))
            for _ in 0..<12 {
                balance = balance * (1 + monthlyReturn) + monthlyContrib
            }
        }

        return data
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ProjectionResultCard(projection: projection)

                    ProjectionChart(data: projectionData)

                    InputSection(
                        currentAge: $currentAge,
                        retirementAge: $retirementAge,
                        currentSavings: $currentSavings,
                        monthlyContribution: $monthlyContribution
                    )

                    if showAdvanced {
                        AdvancedInputSection(
                            expectedReturn: $expectedReturn,
                            inflationRate: $inflationRate
                        )
                    }

                    Button {
                        withAnimation {
                            showAdvanced.toggle()
                        }
                    } label: {
                        HStack {
                            Text(showAdvanced ? "Hide Advanced" : "Show Advanced")
                            Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Retirement Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProjectionResultCard: View {
    let projection: RetirementProjection

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Projected Retirement Savings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(projection.formattedFutureValue)
                    .font(.system(size: 32, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Divider()

            HStack(spacing: 30) {
                VStack {
                    Text("Today's Value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(projection.formattedPresentValue)
                        .font(.headline)
                }

                VStack {
                    Text("Years")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(projection.yearsToRetirement)")
                        .font(.headline)
                }

                VStack {
                    Text("Monthly Income")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(projection.formattedMonthlyIncome)
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }

            Text("Based on 4% safe withdrawal rate")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.green.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ProjectionChart: View {
    let data: [(age: Int, value: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Growth Over Time")
                .font(.headline)

            Chart(data, id: \.age) { item in
                AreaMark(
                    x: .value("Age", item.age),
                    y: .value("Value", item.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Age", item.age),
                    y: .value("Value", item.value)
                )
                .foregroundStyle(.blue)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 5)) { value in
                    AxisValueLabel {
                        if let age = value.as(Int.self) {
                            Text("\(age)")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(formatShort(amount))
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func formatShort(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
}

struct InputSection: View {
    @Binding var currentAge: Int
    @Binding var retirementAge: Int
    @Binding var currentSavings: Decimal
    @Binding var monthlyContribution: Decimal

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Current Age")
                    Spacer()
                    Text("\(currentAge)")
                        .fontWeight(.medium)
                }
                Slider(value: Binding(
                    get: { Double(currentAge) },
                    set: { currentAge = Int($0) }
                ), in: 18...80, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Retirement Age")
                    Spacer()
                    Text("\(retirementAge)")
                        .fontWeight(.medium)
                }
                Slider(value: Binding(
                    get: { Double(retirementAge) },
                    set: { retirementAge = Int($0) }
                ), in: Double(currentAge + 1)...85, step: 1)
            }

            Divider()

            HStack {
                Text("Current Savings")
                Spacer()
                TextField("Amount", value: $currentSavings, format: .currency(code: "USD"))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 150)
            }

            HStack {
                Text("Monthly Contribution")
                Spacer()
                TextField("Amount", value: $monthlyContribution, format: .currency(code: "USD"))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 150)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct AdvancedInputSection: View {
    @Binding var expectedReturn: Double
    @Binding var inflationRate: Double

    var body: some View {
        VStack(spacing: 16) {
            Text("Advanced Settings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Expected Return")
                    Spacer()
                    Text("\(expectedReturn, specifier: "%.1f")%")
                        .fontWeight(.medium)
                }
                Slider(value: $expectedReturn, in: 1...15, step: 0.5)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Inflation Rate")
                    Spacer()
                    Text("\(inflationRate, specifier: "%.1f")%")
                        .fontWeight(.medium)
                }
                Slider(value: $inflationRate, in: 0...10, step: 0.5)
            }

            Text("Historical S&P 500 average: ~10%. After inflation: ~7%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    RetirementCalculatorView()
}
