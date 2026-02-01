import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = GoalsViewModel()
    @State private var showAddGoal = false
    @State private var showRetirementCalculator = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GoalsOverviewCard(
                        totalTarget: viewModel.formattedTotalTarget,
                        totalCurrent: viewModel.formattedTotalCurrent,
                        totalRemaining: viewModel.formattedTotalRemaining,
                        progress: viewModel.overallProgress,
                        onTrackCount: viewModel.goalsOnTrack.count,
                        offTrackCount: viewModel.goalsOffTrack.count
                    )

                    if !viewModel.goals.isEmpty {
                        GoalsListSection(
                            goals: viewModel.activeGoals,
                            onDelete: { goal in
                                Task {
                                    try await viewModel.deleteGoal(goal)
                                }
                            },
                            onComplete: { goal in
                                Task {
                                    try await viewModel.markGoalCompleted(goal)
                                }
                            }
                        )

                        if !viewModel.completedGoals.isEmpty {
                            CompletedGoalsSection(goals: viewModel.completedGoals)
                        }
                    } else if !viewModel.isLoading {
                        ContentUnavailableView {
                            Label("No Goals", systemImage: "flag")
                        } description: {
                            Text("Create savings goals to track your progress")
                        } actions: {
                            Button("Add Goal") {
                                showAddGoal = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Goals")
            .refreshable {
                await viewModel.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showAddGoal = true
                        } label: {
                            Label("Add Goal", systemImage: "plus")
                        }

                        Button {
                            showRetirementCalculator = true
                        } label: {
                            Label("Retirement Calculator", systemImage: "function")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Toggle("Show Completed", isOn: $viewModel.showCompletedGoals)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: viewModel.showCompletedGoals) {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                }
            }
            .onAppear {
                viewModel.configure(modelContext: modelContext)
                Task {
                    await viewModel.refresh()
                }
            }
            .sheet(isPresented: $showAddGoal) {
                AddGoalView { name, description, type, target, current, date, monthly in
                    Task {
                        try await viewModel.createGoal(
                            name: name,
                            description: description,
                            goalType: type,
                            targetAmount: target,
                            currentAmount: current,
                            targetDate: date,
                            monthlyContribution: monthly
                        )
                    }
                }
            }
            .sheet(isPresented: $showRetirementCalculator) {
                RetirementCalculatorView()
            }
        }
    }
}

struct GoalsOverviewCard: View {
    let totalTarget: String
    let totalCurrent: String
    let totalRemaining: String
    let progress: Double
    let onTrackCount: Int
    let offTrackCount: Int

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                VStack {
                    Text("Target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalTarget)
                        .font(.headline)
                }

                VStack {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalCurrent)
                        .font(.headline)
                        .foregroundStyle(.green)
                }

                VStack {
                    Text("Remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalRemaining)
                        .font(.headline)
                }
            }

            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .tint(.blue)

                Text("\(Int(progress * 100))% of goals achieved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                Label("\(onTrackCount) on track", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)

                Label("\(offTrackCount) behind", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct GoalsListSection: View {
    let goals: [Goal]
    let onDelete: (Goal) -> Void
    let onComplete: (Goal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Goals")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(goals) { goal in
                NavigationLink {
                    GoalDetailView(goal: goal)
                } label: {
                    GoalCard(goal: goal)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        onComplete(goal)
                    } label: {
                        Label("Mark Complete", systemImage: "checkmark.circle")
                    }

                    Button(role: .destructive) {
                        onDelete(goal)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
}

struct GoalCard: View {
    let goal: Goal

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: goal.goalType.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.headline)

                    Text(goal.goalType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(goal.displayTargetAmount)
                        .font(.headline)

                    if goal.daysRemaining > 0 {
                        Text("\(goal.daysRemaining) days left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Past due")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(goal.isOnTrack ? Color.green : Color.orange)
                            .frame(width: geometry.size.width * goal.progress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(goal.displayCurrentAmount)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(goal.progressPercent))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(goal.isOnTrack ? .green : .orange)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct CompletedGoalsSection: View {
    let goals: [Goal]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completed Goals")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(goals) { goal in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    Text(goal.name)

                    Spacer()

                    Text(goal.displayTargetAmount)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

#Preview {
    GoalsView()
        .modelContainer(for: [Account.self, Goal.self])
}
