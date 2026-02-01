import SwiftUI
import SwiftData

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var goal: Goal
    @State private var showEditSheet = false
    @State private var showAddProgress = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: goal.goalType.icon)
                            .font(.largeTitle)
                            .foregroundStyle(.blue)

                        Spacer()

                        VStack(alignment: .trailing) {
                            if goal.isCompleted {
                                Label("Completed", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if goal.isOnTrack {
                                Label("On Track", systemImage: "arrow.up.right")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Behind Schedule", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Text(goal.displayCurrentAmount)
                                .font(.title)
                                .fontWeight(.bold)

                            Text("of \(goal.displayTargetAmount)")
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: goal.progress)
                            .tint(goal.isOnTrack ? .green : .orange)

                        Text("\(Int(goal.progressPercent))% complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Details") {
                LabeledContent("Target Date", value: goal.displayTargetDate)

                LabeledContent("Days Remaining") {
                    Text(goal.daysRemaining > 0 ? "\(goal.daysRemaining) days" : "Past due")
                        .foregroundColor(goal.daysRemaining > 0 ? .primary : .red)
                }

                LabeledContent("Amount Remaining") {
                    Text(formatCurrency(goal.remainingAmount))
                }

                if let monthly = goal.monthlyContribution {
                    LabeledContent("Monthly Contribution", value: formatCurrency(monthly))
                }

                LabeledContent("Required Monthly") {
                    Text(formatCurrency(goal.requiredMonthlyContribution))
                        .foregroundColor(goal.isOnTrack ? .primary : .orange)
                }
            }

            if !goal.linkedAccounts.isEmpty {
                Section("Linked Accounts") {
                    ForEach(goal.linkedAccounts) { account in
                        HStack {
                            Image(systemName: account.type.icon)
                                .foregroundStyle(.blue)
                            Text(account.name)
                            Spacer()
                            Text(account.displayBalance)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let description = goal.goalDescription, !description.isEmpty {
                Section("Description") {
                    Text(description)
                }
            }

            if let notes = goal.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            Section {
                Button {
                    showAddProgress = true
                } label: {
                    Label("Update Progress", systemImage: "plus.circle")
                }

                if !goal.isCompleted {
                    Button {
                        goal.isCompleted = true
                        try? modelContext.save()
                    } label: {
                        Label("Mark as Completed", systemImage: "checkmark.circle")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    modelContext.delete(goal)
                    try? modelContext.save()
                    dismiss()
                } label: {
                    Label("Delete Goal", systemImage: "trash")
                }
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditGoalView(goal: goal)
        }
        .sheet(isPresented: $showAddProgress) {
            UpdateProgressView(goal: goal)
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

struct UpdateProgressView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: Goal

    @State private var newAmount: Decimal

    init(goal: Goal) {
        self.goal = goal
        _newAmount = State(initialValue: goal.currentAmount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Current Amount")
                        Spacer()
                        TextField("Amount", value: $newAmount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target: \(goal.displayTargetAmount)")
                        if newAmount >= goal.targetAmount {
                            Text("Goal reached!")
                                .foregroundStyle(.green)
                        } else {
                            Text("Remaining: \(formatCurrency(goal.targetAmount - newAmount))")
                        }
                    }
                }

                Section("Quick Add") {
                    ForEach([100, 250, 500, 1000], id: \.self) { amount in
                        Button {
                            newAmount += Decimal(amount)
                        } label: {
                            Text("+ \(formatCurrency(Decimal(amount)))")
                        }
                    }
                }
            }
            .navigationTitle("Update Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        goal.currentAmount = newAmount
                        if newAmount >= goal.targetAmount {
                            goal.isCompleted = true
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

struct EditGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: Goal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $goal.name)

                    TextField("Description", text: Binding(
                        get: { goal.goalDescription ?? "" },
                        set: { goal.goalDescription = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(2...4)
                }

                Section {
                    Picker("Type", selection: $goal.goalType) {
                        ForEach(GoalType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Target Amount")
                        Spacer()
                        TextField("Amount", value: $goal.targetAmount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("Target Date", selection: $goal.targetDate, displayedComponents: .date)

                    HStack {
                        Text("Monthly Contribution")
                        Spacer()
                        TextField("Monthly", value: Binding(
                            get: { goal.monthlyContribution ?? 0 },
                            set: { goal.monthlyContribution = $0 > 0 ? $0 : nil }
                        ), format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: Binding(
                        get: { goal.notes ?? "" },
                        set: { goal.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GoalDetailView(goal: Goal(
            name: "Emergency Fund",
            description: "6 months of expenses",
            goalType: .emergency,
            targetAmount: 20000,
            currentAmount: 12500,
            targetDate: Calendar.current.date(byAdding: .month, value: 6, to: Date())!,
            monthlyContribution: 1000
        ))
    }
    .modelContainer(for: [Account.self, Goal.self])
}
