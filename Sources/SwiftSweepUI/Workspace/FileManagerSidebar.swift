import SwiftUI

struct FileManagerSidebar: View {
  let favorites: [URL]
  let recentLocations: [URL]
  let mountedVolumes: [URL]
  let onOpen: (URL) -> Void

  var body: some View {
    List {
      Section("Favorites") {
        ForEach(favorites, id: \.path) { url in
          sidebarButton(url: url, icon: "star.fill")
        }
      }

      Section("Recent") {
        ForEach(recentLocations, id: \.path) { url in
          sidebarButton(url: url, icon: "clock")
        }
      }

      Section("Volumes") {
        ForEach(mountedVolumes, id: \.path) { url in
          sidebarButton(url: url, icon: "externaldrive")
        }
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Locations")
  }

  private func sidebarButton(url: URL, icon: String) -> some View {
    Button {
      onOpen(url)
    } label: {
      Label(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, systemImage: icon)
    }
    .buttonStyle(.plain)
    .help(url.path)
  }
}
