import SwiftUI

/// Legacy compatibility wrapper.
/// The applications module has been moved to LauncherView in Workspace.
struct MainApplicationsView: View {
  var body: some View {
    LauncherView()
  }
}
