import SwiftUI
import Charts

struct AllocationChart: View {
    let data: [(type: AssetType, value: Double, percentage: Double)]

    private let colors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Asset Allocation")
                .font(.headline)

            if data.isEmpty {
                ContentUnavailableView(
                    "No Holdings",
                    systemImage: "chart.pie",
                    description: Text("Add investments to see allocation")
                )
                .frame(height: 200)
            } else {
                HStack(spacing: 20) {
                    Chart(data, id: \.type) { item in
                        SectorMark(
                            angle: .value("Value", item.value),
                            innerRadius: .ratio(0.5),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Type", item.type.rawValue))
                        .cornerRadius(4)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 140, height: 140)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(data.enumerated()), id: \.element.type) { index, item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(colors[index % colors.count])
                                    .frame(width: 10, height: 10)

                                Text(item.type.rawValue)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer()

                                Text(String(format: "%.1f%%", item.percentage))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct PerformanceChart: View {
    let data: [(date: Date, value: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Portfolio Performance")
                .font(.headline)

            if data.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Performance data will appear here")
                )
                .frame(height: 200)
            } else {
                Chart(data, id: \.date) { item in
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(.blue)

                    AreaMark(
                        x: .value("Date", item.date),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formatCurrency(doubleValue))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0

        if value >= 1_000_000 {
            return (formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "") + "M"
        } else if value >= 1_000 {
            return (formatter.string(from: NSNumber(value: value / 1_000)) ?? "") + "K"
        }

        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

#Preview {
    VStack {
        AllocationChart(data: [
            (type: .stock, value: 50000, percentage: 50),
            (type: .bond, value: 20000, percentage: 20),
            (type: .etf, value: 15000, percentage: 15),
            (type: .cash, value: 10000, percentage: 10),
            (type: .crypto, value: 5000, percentage: 5)
        ])

        PerformanceChart(data: [
            (date: Calendar.current.date(byAdding: .month, value: -6, to: Date())!, value: 80000),
            (date: Calendar.current.date(byAdding: .month, value: -5, to: Date())!, value: 85000),
            (date: Calendar.current.date(byAdding: .month, value: -4, to: Date())!, value: 82000),
            (date: Calendar.current.date(byAdding: .month, value: -3, to: Date())!, value: 90000),
            (date: Calendar.current.date(byAdding: .month, value: -2, to: Date())!, value: 95000),
            (date: Calendar.current.date(byAdding: .month, value: -1, to: Date())!, value: 92000),
            (date: Date(), value: 100000)
        ])
    }
    .padding()
}
