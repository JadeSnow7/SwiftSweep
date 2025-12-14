import SwiftUI

struct DirectoryAuthorizationView: View {
    @StateObject private var bookmarkManager = BookmarkManager.shared
    @State private var showingOpenPanel = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Authorized Folders")
                .font(.title)
                .fontWeight(.bold)
            
            Text("SwiftSweep can only show menus for folders you authorize below.")
                .foregroundColor(.secondary)
            
            // Warning if approaching limit
            if bookmarkManager.authorizedDirectories.count >= DirectorySyncConstants.recommendedDirectories {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Consider authorizing parent folders instead of many subfolders for better Finder performance.")
                        .font(.caption)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Directory list
            List {
                ForEach(bookmarkManager.authorizedDirectories) { dir in
                    DirectoryRow(
                        directory: dir,
                        onAnalyze: {
                            NavigationManager.shared.navigateToAnalysis(path: dir.url.path)
                        },
                        onRemove: {
                        bookmarkManager.removeAuthorizedDirectory(dir.url)
                        }
                    )
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 200)
            
            // Add button
            HStack {
                Button {
                    showingOpenPanel = true
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }
                .disabled(bookmarkManager.authorizedDirectories.count >= DirectorySyncConstants.maxDirectories)
                
                Spacer()
                
                Text("\(bookmarkManager.authorizedDirectories.count)/\(DirectorySyncConstants.maxDirectories)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .navigationTitle("Authorized Folders")
        .fileImporter(
            isPresented: $showingOpenPanel,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        try bookmarkManager.addAuthorizedDirectory(url)
                    } catch {
                        print("Failed to add directory: \(error)")
                    }
                }
            case .failure(let error):
                print("File importer error: \(error)")
            }
        }
    }
}

struct DirectoryRow: View {
    let directory: BookmarkManager.ResolvedDirectory
    let onAnalyze: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(directory.name)
                    .fontWeight(.medium)
                Text(directory.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if directory.isStale {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Re-authorize")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Button(action: onAnalyze) {
                Image(systemName: "chart.pie")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .disabled(directory.isStale)
            .help(directory.isStale ? "Re-authorize this folder first" : "Analyze")
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
