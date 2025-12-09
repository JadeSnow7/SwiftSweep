import SwiftUI
import SwiftSweepCore

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
                    .disabled(!viewModel.helperInstalled)
                }
                .padding()
                
                // Helper Status
                if !viewModel.helperInstalled {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("Privileged Helper Required")
                                    .fontWeight(.medium)
                                Text("System optimization requires administrator privileges.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        
                        Button(action: { Task { await viewModel.installHelper() }}) {
                            Label(viewModel.isInstallingHelper ? "Installing..." : "Install Helper", 
                                  systemImage: "lock.shield")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isInstallingHelper)
                        
                        if let error = viewModel.installError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
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
    let task: OptimizationTask
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
                .disabled(!viewModel.helperInstalled && task.requiresPrivilege)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct OptimizationTask: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
    let command: String
    let requiresPrivilege: Bool
    var isRunning: Bool = false
    var lastResult: Bool? = nil
}

@MainActor
class OptimizeViewModel: ObservableObject {
    @Published var tasks: [OptimizationTask] = [
        OptimizationTask(
            title: "Flush DNS Cache",
            description: "Clear DNS resolver cache to fix network issues",
            icon: "network",
            color: .blue,
            command: "dscacheutil -flushcache",
            requiresPrivilege: true
        ),
        OptimizationTask(
            title: "Rebuild Spotlight",
            description: "Rebuild search index if Spotlight is slow",
            icon: "magnifyingglass",
            color: .purple,
            command: "mdutil -E /",
            requiresPrivilege: true
        ),
        OptimizationTask(
            title: "Clear Memory",
            description: "Purge inactive memory to free up RAM",
            icon: "memorychip",
            color: .green,
            command: "purge",
            requiresPrivilege: true
        ),
        OptimizationTask(
            title: "Reset Dock",
            description: "Restart Dock to fix UI glitches",
            icon: "dock.rectangle",
            color: .orange,
            command: "killall Dock",
            requiresPrivilege: false
        ),
        OptimizationTask(
            title: "Reset Finder",
            description: "Restart Finder to refresh file system",
            icon: "folder",
            color: .cyan,
            command: "killall Finder",
            requiresPrivilege: false
        ),
        OptimizationTask(
            title: "Clear Font Cache",
            description: "Remove cached fonts to fix font issues",
            icon: "textformat",
            color: .pink,
            command: "atsutil databases -remove",
            requiresPrivilege: true
        ),
    ]
    
    @Published var helperInstalled = false
    @Published var isInstallingHelper = false
    @Published var installError: String?
    
    init() {
        checkHelperStatus()
    }
    
    func checkHelperStatus() {
        helperInstalled = SMJobBlessClient.shared.isHelperInstalled()
    }
    
    func installHelper() async {
        isInstallingHelper = true
        installError = nil
        
        do {
            try SMJobBlessClient.shared.installHelper()
            checkHelperStatus()
        } catch {
            installError = error.localizedDescription
        }
        
        isInstallingHelper = false
    }
    
    func runTask(_ task: OptimizationTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        
        if task.requiresPrivilege && !helperInstalled {
            return
        }
        
        tasks[index].isRunning = true
        
        if !task.requiresPrivilege {
            DispatchQueue.global().async { [weak self] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", task.command]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    DispatchQueue.main.async {
                        self?.tasks[index].isRunning = false
                        self?.tasks[index].lastResult = process.terminationStatus == 0
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.tasks[index].isRunning = false
                        self?.tasks[index].lastResult = false
                    }
                }
            }
        } else {
            // 使用 SMJobBlessClient 运行特权任务
            Task {
                do {
                    switch task.title {
                    case "Flush DNS Cache":
                        _ = try await SMJobBlessClient.shared.flushDNS()
                    case "Rebuild Spotlight":
                        _ = try await SMJobBlessClient.shared.rebuildSpotlight()
                    case "Clear Memory":
                        _ = try await SMJobBlessClient.shared.clearMemory()
                    default:
                        break
                    }
                    await MainActor.run {
                        self.tasks[index].isRunning = false
                        self.tasks[index].lastResult = true
                    }
                } catch {
                    await MainActor.run {
                        self.tasks[index].isRunning = false
                        self.tasks[index].lastResult = false
                    }
                }
            }
        }
    }
    
    func runAll() {
        for task in tasks {
            if !task.requiresPrivilege || helperInstalled {
                runTask(task)
            }
        }
    }
}
