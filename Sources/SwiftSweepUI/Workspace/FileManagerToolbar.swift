import SwiftUI

struct FileManagerToolbar: View {
  let currentLocation: URL?
  let isDualPane: Bool
  let onToggleDualPane: () -> Void
  let onGoToPath: (URL) -> Void
  let onRefresh: () -> Void
  let onShowQueue: () -> Void
  let onNewTab: () -> Void
  let onCopy: () -> Void
  let onMove: () -> Void
  let onRename: () -> Void
  let onTrash: () -> Void

  @State private var pathInput: String = ""

  var body: some View {
    HStack(spacing: 10) {
      TextField("Path", text: $pathInput)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          let url = URL(fileURLWithPath: pathInput)
          onGoToPath(url)
        }

      Button {
        onRefresh()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }

      Button {
        onToggleDualPane()
      } label: {
        Label(isDualPane ? "Single Pane" : "Dual Pane", systemImage: "rectangle.split.2x1")
      }

      Button {
        onNewTab()
      } label: {
        Label("New Tab", systemImage: "plus.rectangle.on.rectangle")
      }

      Divider()

      Button {
        onCopy()
      } label: {
        Label("Copy", systemImage: "doc.on.doc")
      }

      Button {
        onMove()
      } label: {
        Label("Move", systemImage: "arrow.right.doc.on.clipboard")
      }

      Button {
        onRename()
      } label: {
        Label("Rename", systemImage: "pencil")
      }

      Button(role: .destructive) {
        onTrash()
      } label: {
        Label("Trash", systemImage: "trash")
      }

      Spacer()

      Button {
        onShowQueue()
      } label: {
        Label("Queue", systemImage: "list.bullet.rectangle")
      }
    }
    .padding(10)
    .onAppear {
      pathInput = currentLocation?.path ?? ""
    }
    .onChange(of: currentLocation?.path) { newPath in
      pathInput = newPath ?? ""
    }
  }
}
