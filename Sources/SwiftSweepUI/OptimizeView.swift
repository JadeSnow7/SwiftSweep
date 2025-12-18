import SwiftUI
#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif

struct OptimizeView: View {
    @StateObject private var viewModel = OptimizeViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("System Optimizer")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Maintain and optimize your Mac")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    Button(action: { viewModel.runAll() }) {
                        Label("Run All", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 16) {
                    ForEach(viewModel.tasks) { task in
                        OptimizationCard(task: task, viewModel: viewModel)
                    }
                }
                .padding()
                
                Spacer()
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
                    .foregroundColor(task.color)
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
                } else if task.lastResult != nil {
                    Image(systemName: task.lastResult! ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(task.lastResult! ? .green : .red)
                }
                
                Button("Run") {
                    viewModel.runTask(task)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
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
