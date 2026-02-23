import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

struct FileOperationQueueSheet: View {
  let items: [FileOperationProgress]
  let onPause: (UUID) -> Void
  let onResume: (UUID) -> Void
  let onCancel: (UUID) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List(items, id: \.requestID) { item in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(item.requestID.uuidString)
              .font(.caption.monospaced())
              .lineLimit(1)
            Spacer()
            Text(statusText(item.status))
              .font(.caption)
              .foregroundStyle(statusColor(item.status))
          }

          ProgressView(
            value: item.totalCount > 0 ? Double(item.processedCount) / Double(item.totalCount) : 0
          )

          HStack {
            Text("\(item.processedCount)/\(item.totalCount)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: item.transferredBytes, countStyle: .file))
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          HStack(spacing: 8) {
            switch item.status {
            case .running:
              Button("Pause") { onPause(item.requestID) }
                .buttonStyle(.bordered)
            case .paused:
              Button("Resume") { onResume(item.requestID) }
                .buttonStyle(.borderedProminent)
            default:
              EmptyView()
            }

            if case .completed = item.status {
              EmptyView()
            } else {
              Button("Cancel", role: .destructive) {
                onCancel(item.requestID)
              }
              .buttonStyle(.bordered)
            }
          }
        }
        .padding(.vertical, 4)
      }
      .navigationTitle("File Operation Queue")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            dismiss()
          }
        }
      }
    }
    .frame(minWidth: 560, minHeight: 420)
  }

  private func statusText(_ status: FileOperationProgress.Status) -> String {
    switch status {
    case .queued:
      return "Queued"
    case .running:
      return "Running"
    case .paused:
      return "Paused"
    case .completed:
      return "Completed"
    case .failed(let message):
      return "Failed: \(message)"
    case .cancelled:
      return "Cancelled"
    }
  }

  private func statusColor(_ status: FileOperationProgress.Status) -> Color {
    switch status {
    case .queued:
      return .secondary
    case .running:
      return .blue
    case .paused:
      return .orange
    case .completed:
      return .green
    case .failed:
      return .red
    case .cancelled:
      return .secondary
    }
  }
}
