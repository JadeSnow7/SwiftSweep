import SwiftUI
#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif

struct CleanView: View {
    @StateObject private var viewModel = CleanupViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("System Cleanup")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Remove junk files, caches, and temporary data to free up disk space.")
                    .foregroundColor(.secondary)
                
                // Scan Control
                if !viewModel.isScanning && !viewModel.scanComplete {
                    Button(action: {
                        Task { await viewModel.startScan() }
                    }) {
                        Label("Start Scan", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                
                // Scanning Progress
                if viewModel.isScanning {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Scanning system...")
                                .font(.headline)
                        }
                        
                        Text("Found \(viewModel.items.count) items...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                // Results
                if viewModel.scanComplete {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title)
                            VStack(alignment: .leading) {
                                Text("Scan Complete")
                                    .font(.headline)
                                Text("Found \(viewModel.formattedTotalSize)")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        
                        Divider()
                        
                        if viewModel.items.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 10) {
                                    Image(systemName: "sparkles")
                                        .font(.largeTitle)
                                        .foregroundColor(.green)
                                    Text("Your system is clean!")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 40)
                        } else {
                            List {
                                ForEach($viewModel.items) { $item in
                                    CleanupItemRow(item: $item)
                                        .padding(.vertical, 4)
                                }
                            }
                            .listStyle(.plain)
                            .frame(minHeight: 300)
                        }
                        
                        Divider()
                        
                        // Action Buttons
                        HStack {
                            Button("Scan Again") {
                                viewModel.reset()
                            }
                            .keyboardShortcut("r", modifiers: .command)
                            
                            Spacer()
                            
                            if !viewModel.items.isEmpty {
                                Button(action: {
                                    Task { await viewModel.cleanSelected() }
                                }) {
                                    Label("Clean Selected", systemImage: "trash")
                                        .padding(.horizontal)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(viewModel.selectedSize == 0)
                            }
                        }
                        .padding()
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

struct CleanupItemRow: View {
    @Binding var item: CleanupEngine.CleanupItem
    
    var body: some View {
        HStack {
            Toggle("", isOn: $item.isSelected)
                .labelsHidden()
            
            Image(systemName: iconForCategory(item.category))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .fontWeight(.medium)
                Text(item.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text(formatBytes(item.size))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .font(.monospacedDigit(.body)())
        }
    }
    
    func iconForCategory(_ category: CleanupEngine.CleanupCategory) -> String {
        switch category {
        case .userCache, .systemCache: return "folder.fill"
        case .logs: return "doc.text.fill"
        case .trash: return "trash.fill"
        case .browserCache: return "globe"
        case .developerTools: return "hammer.fill"
        case .applications: return "app.fill"
        case .other: return "doc.fill"
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }
}

@MainActor
class CleanupViewModel: ObservableObject {
    @Published var items: [CleanupEngine.CleanupItem] = []
    @Published var isScanning = false
    @Published var scanComplete = false
    
    var selectedSize: Int64 {
        items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    var formattedTotalSize: String {
        let bytes = items.reduce(0) { $0 + $1.size }
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }
    
    func startScan() async {
        isScanning = true
        scanComplete = false
        items = []
        
        do {
            // Artificial delay for better UX if scan is too fast
            try? await Task.sleep(nanoseconds: 500_000_000) 
            
            let foundItems = try await CleanupEngine.shared.scanForCleanableItems()
            
            withAnimation {
                self.items = foundItems
                self.isScanning = false
                self.scanComplete = true
            }
        } catch {
            print("Scan failed: \(error)")
            self.isScanning = false
            self.scanComplete = true
        }
    }
    
    func cleanSelected() async {
        // TODO: Implement actual cleaning alert/confirmation
        let selectedItems = items.filter { $0.isSelected }
        guard !selectedItems.isEmpty else { return }
        
        do {
            let _ = try await CleanupEngine.shared.performCleanup(items: selectedItems, dryRun: false) // Warning: Real Deletion
            await startScan() // Rescan after clean
        } catch {
            print("Cleanup failed: \(error)")
        }
    }
    
    func reset() {
        items = []
        scanComplete = false
        isScanning = false
    }
}
