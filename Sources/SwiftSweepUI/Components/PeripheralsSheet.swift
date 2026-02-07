import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

struct PeripheralsSheet: View {
  let snapshot: PeripheralSnapshot
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("\(L10n.Status.displays.localized) (\(snapshot.displays.count))") {
          if snapshot.displays.isEmpty {
            Text(L10n.Status.noDisplayInfo.localized)
              .foregroundColor(.secondary)
          } else {
            ForEach(snapshot.displays) { display in
              DisplayRow(display: display)
            }
          }
        }

        Section("\(L10n.Status.inputDevices.localized) (\(snapshot.inputDevices.count))") {
          if snapshot.inputDevices.isEmpty {
            Text(L10n.Status.noInputInfo.localized)
              .foregroundColor(.secondary)
          } else {
            ForEach(snapshot.inputDevices) { device in
              InputDeviceRow(device: device)
            }
          }
        }
      }
      .navigationTitle(L10n.Status.peripherals.localized)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.Common.done.localized) { dismiss() }
        }
      }
    }
    .frame(minWidth: 620, minHeight: 420)
  }
}

private struct DisplayRow: View {
  let display: DisplayInfo

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(display.name ?? L10n.Status.unknownDisplay.localized)
        .font(.headline)

      HStack(spacing: 10) {
        if let width = display.pixelsWidth, let height = display.pixelsHeight {
          Badge(text: "\(width)x\(height)")
        } else {
          Badge(text: L10n.Status.na.localized)
        }

        if display.isMain == true {
          Badge(text: L10n.Status.mainDisplay.localized)
        }

        if display.isBuiltin == true {
          Badge(text: L10n.Status.builtIn.localized)
        } else if display.isBuiltin == false {
          Badge(text: L10n.Status.external.localized)
        }
      }
      .font(.caption)
      .foregroundColor(.secondary)
    }
    .padding(.vertical, 4)
  }
}

private struct InputDeviceRow: View {
  let device: InputDeviceInfo

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(device.name ?? L10n.Status.unknownDevice.localized)
        .font(.headline)

      HStack(spacing: 10) {
        Badge(text: localizedDeviceKindLabel(device.kind))
        Badge(text: device.transport ?? L10n.Status.na.localized)
        if device.isBuiltin == true {
          Badge(text: L10n.Status.builtIn.localized)
        } else if device.isBuiltin == false {
          Badge(text: L10n.Status.external.localized)
        }
      }
      .font(.caption)
      .foregroundColor(.secondary)
    }
    .padding(.vertical, 4)
  }
}

private struct Badge: View {
  let text: String

  var body: some View {
    Text(text)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(Color.secondary.opacity(0.12))
      .clipShape(Capsule())
  }
}

struct DiagnosticsGuideSheet: View {
  let guide: AppleDiagnosticsGuide
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(L10n.Status.appleDiagnostics.localized)
            .font(.title3)
            .fontWeight(.semibold)

          Text("\(L10n.Status.architecture.localized): \(architectureLabel)")
            .font(.subheadline)
            .foregroundColor(.secondary)

          Divider()

          ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: 8) {
              Text("\(index + 1).")
                .foregroundColor(.secondary)
              Text(step)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }

          if !guide.notes.isEmpty {
            Divider()
            ForEach(guide.notes, id: \.self) { note in
              HStack(alignment: .top, spacing: 6) {
                Text("•")
                  .foregroundColor(.secondary)
                Text(note)
              }
            }
          }
        }
        .padding(20)
      }
      .navigationTitle(L10n.Status.diagnosticsGuide.localized)
      .toolbar {
        ToolbarItem(placement: .automatic) {
          Button(L10n.Status.openSupport.localized) {
            openURL(guide.supportURL)
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.Common.done.localized) {
            dismiss()
          }
        }
      }
    }
    .frame(minWidth: 640, minHeight: 420)
  }

  private var architectureLabel: String {
    switch guide.architecture {
    case .appleSilicon: return L10n.Status.architectureAppleSilicon.localized
    case .intel: return L10n.Status.architectureIntel.localized
    case .unknown: return L10n.Status.architectureUnknown.localized
    }
  }
}
func localizedDeviceKindLabel(_ kind: InputDeviceKind) -> String {
  switch kind {
  case .keyboard: return L10n.Status.deviceKindKeyboard.localized
  case .mouse: return L10n.Status.deviceKindMouse.localized
  case .trackpad: return L10n.Status.deviceKindTrackpad.localized
  case .other: return L10n.Status.deviceKindOther.localized
  }
}
