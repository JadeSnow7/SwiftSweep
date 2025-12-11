import SwiftUI

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
    
    func runTask(_ task: OptimizationTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        
        if task.requiresPrivilege {
            // 使用 AppleScript 弹出密码框运行特权命令
            runPrivilegedTask(task, at: index)
        } else {
            tasks[index].isRunning = true
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
        }
    }
    
    private func runPrivilegedTask(_ task: OptimizationTask, at index: Int) {
        tasks[index].isRunning = true
        
        let command: String
        switch task.title {
        case "Flush DNS Cache":
            command = "dscacheutil -flushcache && killall -HUP mDNSResponder"
        case "Rebuild Spotlight":
            command = "mdutil -E /"
        case "Clear Memory":
            command = "purge"
        case "Clear Font Cache":
            command = "atsutil databases -remove"
        default:
            tasks[index].isRunning = false
            return
        }
        
        DispatchQueue.global().async { [weak self] in
            let script = """
            do shell script "\(command)" with administrator privileges
            """
            
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                _ = appleScript.executeAndReturnError(&error)
                
                DispatchQueue.main.async {
                    self?.tasks[index].isRunning = false
                    self?.tasks[index].lastResult = (error == nil)
                    
                    if error == nil {
                        // 可选: 显示成功消息
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self?.tasks[index].isRunning = false
                    self?.tasks[index].lastResult = false
                }
            }
        }
    }
    
    func runAll() {
        for task in tasks {
            runTask(task)
        }
    }
}
