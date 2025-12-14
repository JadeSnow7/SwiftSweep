import SwiftUI
import AppKit
import AppInventoryUI

struct ContentView: View {
    @StateObject private var notificationManager = NotificationPermissionManager()
    @StateObject private var navigationManager = NavigationManager.shared
    @StateObject private var bookmarkManager = BookmarkManager.shared
    
    @AppStorage("hasCompletedOnboarding", store: UserDefaults(suiteName: DirectorySyncConstants.suiteName))
    private var hasCompletedOnboarding = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                NavigationLink {
                    DirectoryAuthorizationView()
                } label: {
                    Label("Authorized Folders", systemImage: "folder.badge.plus")
                }
                
                NavigationLink {
                    ExtensionSetupGuideView()
                } label: {
                    Label("Extension Setup", systemImage: "puzzlepiece.extension")
                }
                
                NavigationLink {
                    AppInventoryUI.ApplicationsView(
                        defaults: UserDefaults(suiteName: DirectorySyncConstants.suiteName) ?? .standard
                    )
                } label: {
                    Label("Applications", systemImage: "square.grid.2x2")
                }
                
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("SwiftSweep")
        } detail: {
            // Main content
            if !hasCompletedOnboarding {
                OnboardingView(hasCompleted: $hasCompletedOnboarding)
            } else if navigationManager.showingAnalysis, let path = navigationManager.currentAnalysisPath {
                AnalysisResultView(path: path)
            } else {
                WelcomeView()
            }
        }
        .task {
            await notificationManager.checkCurrentStatus()
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "externaldrive.fill.badge.checkmark")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            Text("SwiftSweep")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Disk Space Analyzer for Finder")
                .font(.title3)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "folder.badge.plus", 
                          text: "Authorize folders to enable Finder menu")
                FeatureRow(icon: "chart.pie", 
                          text: "Analyze folder sizes directly in Finder")
                FeatureRow(icon: "bell.badge", 
                          text: "Get quick results via notifications")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
        .padding(40)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            Text(text)
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var hasCompleted: Bool
    @StateObject private var notificationManager = NotificationPermissionManager()
    @State private var currentStep = 0
    
    var body: some View {
        VStack(spacing: 32) {
            // Progress
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            
            // Content
            switch currentStep {
            case 0:
                OnboardingStepView(
                    icon: "hand.wave.fill",
                    title: "Welcome to SwiftSweep",
                    description: "Analyze disk space directly from Finder"
                )
            case 1:
                OnboardingStepView(
                    icon: "bell.badge.fill",
                    title: "Enable Notifications",
                    description: "Get quick analysis results in Finder",
                    action: {
                        Task { await notificationManager.requestPermission() }
                    },
                    actionTitle: "Allow Notifications"
                )
            case 2:
                OnboardingStepView(
                    icon: "checkmark.circle.fill",
                    title: "You're All Set!",
                    description: "Add folders and enable the extension in System Settings"
                )
            default:
                EmptyView()
            }
            
            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                }
                
                Spacer()
                
                Button(currentStep == 2 ? "Get Started" : "Next") {
                    if currentStep == 2 {
                        hasCompleted = true
                    } else {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: 500)
    }
}

struct OnboardingStepView: View {
    let icon: String
    let title: String
    let description: String
    var action: (() -> Void)?
    var actionTitle: String?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            
            Text(description)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let action = action, let actionTitle = actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "1")
            }
            
            Section {
                Link(destination: URL(string: "https://github.com/JadeSnow7/SwiftSweep")!) {
                    Label("GitHub Repository", systemImage: "link")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}


