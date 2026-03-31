import SwiftUI
#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif

private extension OptimizationEngine.OptimizationTask.ColorToken {
    var swiftUIColor: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .cyan: return .cyan
        case .pink: return .pink
        }
    }
}

struct OptimizeView: View {
    @StateObject private var viewModel = OptimizeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Info banner explaining password prompt
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Privileged tasks will prompt for your password when run.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)

                // Optimization Tasks
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: Spacing.lg) {
                    ForEach(viewModel.tasks) { task in
                        OptimizationCard(task: task, viewModel: viewModel)
                    }
                }
                .padding()

                Spacer()
            }
        }
        .navigationTitle("System Optimizer")
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button(action: { viewModel.runAll() }) {
              Label("Run All", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
          }
        }
    }
}

struct OptimizationCard: View {
    let task: OptimizationEngine.OptimizationTask
    @ObservedObject var viewModel: OptimizeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: task.icon)
                    .font(.title2)
                    .foregroundColor(task.color.swiftUIColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .fontWeight(.semibold)
                    Text(task.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            Divider()

            HStack {
                if task.requiresPrivilege {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Requires admin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if task.isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let result = task.lastResult {
                    Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result ? .green : .red)
                }

                Button("Run") {
                    viewModel.runTask(task)
                }
                .buttonStyle(.bordered)
            }
        }
        .cardStyle()
    }
}

@MainActor
class OptimizeViewModel: ObservableObject {
    @Published var tasks: [OptimizationEngine.OptimizationTask] = []
    private let engine = OptimizationEngine.shared

    init() {
        self.tasks = engine.availableTasks
    }

    func runTask(_ task: OptimizationEngine.OptimizationTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        tasks[index].isRunning = true

        Task {
            let success = await engine.run(task)
            tasks[index].isRunning = false
            tasks[index].lastResult = success
        }
    }

    func runAll() {
        for task in tasks {
            runTask(task)
        }
    }
}
