import SwiftUI

struct SettingsView: View {
    @AppStorage("autoCleanOnLaunch") private var autoCleanOnLaunch = false
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false
    @AppStorage("defaultCleanCategory") private var defaultCleanCategory = "all"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Configure SwiftSweep preferences")
                        .foregroundColor(.secondary)
                }
                .padding()
                
                // General Settings
                SettingsSection(title: "General", icon: "gear") {
                    Toggle("Auto-scan on launch", isOn: $autoCleanOnLaunch)
                    Toggle("Show hidden files in analyzer", isOn: $showHiddenFiles)
                }
                
                // Cleanup Settings
                SettingsSection(title: "Cleanup", icon: "sparkles") {
                    Picker("Default category", selection: $defaultCleanCategory) {
                        Text("All").tag("all")
                        Text("Cache").tag("cache")
                        Text("Logs").tag("logs")
                        Text("Browser").tag("browser")
                    }
                    .pickerStyle(.menu)
                }
                
                // About
                SettingsSection(title: "About", icon: "info.circle") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("Development")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/JadeSnow7/SwiftSweep")!) {
                        HStack {
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
                
                // Privileged Helper
                SettingsSection(title: "Privileged Helper", icon: "lock.shield") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Helper Status")
                            Text("Required for system optimization and uninstallation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Not Installed")
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                    }
                    
                    Button("Install Helper...") {
                        // TODO: Implement SMJobBless
                    }
                    .disabled(true)
                }
                
                Spacer()
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal)
        }
    }
}

#Preview {
    SettingsView()
}
