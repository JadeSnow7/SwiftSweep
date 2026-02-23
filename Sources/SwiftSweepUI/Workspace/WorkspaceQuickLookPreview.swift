import QuickLookUI
import SwiftUI

struct WorkspaceQuickLookPreview: NSViewRepresentable {
  let url: URL?

  func makeNSView(context: Context) -> QLPreviewView {
    let view = QLPreviewView(frame: .zero, style: .normal)!
    view.autostarts = true
    return view
  }

  func updateNSView(_ nsView: QLPreviewView, context: Context) {
    nsView.previewItem = url as NSURL?
  }
}
