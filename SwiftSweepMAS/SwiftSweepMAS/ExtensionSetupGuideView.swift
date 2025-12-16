import SwiftUI

struct ExtensionSetupGuideView: View {
    @AppStorage("hasConfirmedExtensionEnabled", store: DirectorySyncConstants.userDefaults)
    private var hasConfirmedEnabled = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            Text("Enable Finder Extension")
                .font(.title)
                .fontWeight(.bold)
            
            if hasConfirmedEnabled {
                // Already enabled
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title)
                    VStack(alignment: .leading) {
                        Text("Extension Enabled")
                            .fontWeight(.semibold)
                        Text("Right-click folders in Finder to see the SwiftSweep menu.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                
                Button("Reset Status") {
                    hasConfirmedEnabled = false
                }
                .buttonStyle(.link)
            } else {
                // Setup guide
                VStack(alignment: .leading, spacing: 20) {
                    StepRow2(number: 1, title: "Open System Settings", 
                            description: "Click the button below to open extension settings")
                    
                    StepRow2(number: 2, title: "Enable SwiftSweep", 
                            description: "Find \"SwiftSweep\" under Finder Extensions and enable it")
                    
                    StepRow2(number: 3, title: "Test in Finder", 
                            description: "Right-click an authorized folder to see the menu")
                }
                
                Divider()
                
                HStack {
                    Button("Open System Settings") {
                        openExtensionSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                    
                    Button("I've Enabled It") {
                        hasConfirmedEnabled = true
                    }
                }
                
                // Troubleshooting
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Troubleshooting", systemImage: "questionmark.circle")
                            .fontWeight(.semibold)
                        
                        Text("""
                        If the menu doesn't appear after enabling:
                        1. Toggle the extension off and on again
                        2. Restart Finder (Option+Right-click Finder icon → Relaunch)
                        3. Make sure you've authorized at least one folder
                        """)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Extension Setup")
    }
    
    private func openExtensionSettings() {
        // macOS Ventura+ (14.0)
        if #available(macOS 14.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        
        // Monterey/Ventura
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.extensions") {
            NSWorkspace.shared.open(url)
            return
        }
        
        // Fallback
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Extensions.prefPane"))
    }
}

struct StepRow2: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
