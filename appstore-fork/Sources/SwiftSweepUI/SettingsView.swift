import SwiftUI

struct SettingsView: View {
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false
    @AppStorage("analysisDepth") private var analysisDepth = 5
    
    var body: some View {
        TabView {
            GeneralSettingsView(showHiddenFiles: $showHiddenFiles, analysisDepth: $analysisDepth)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 250)
    }
}

struct GeneralSettingsView: View {
    @Binding var showHiddenFiles: Bool
    @Binding var analysisDepth: Int
    
    var body: some View {
        Form {
            Toggle("Show hidden files in analysis", isOn: $showHiddenFiles)
            
            Picker("Analysis depth limit", selection: $analysisDepth) {
                Text("3 levels").tag(3)
                Text("5 levels").tag(5)
                Text("10 levels").tag(10)
                Text("Unlimited").tag(0)
            }
            .pickerStyle(.menu)
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("SwiftSweep")
                .font(.title)
                .fontWeight(.bold)
            
            Text("System Monitor & Disk Analyzer")
                .foregroundColor(.secondary)
            
            Text("Version 1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("© 2024 SwiftSweep")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
