import Foundation

public final class DiagnosticsGuideService {
  public static let shared = DiagnosticsGuideService()

  private init() {}

  public func getGuide() -> AppleDiagnosticsGuide {
    let architecture = detectArchitecture()
    let supportURL = URL(string: "https://support.apple.com/en-us/102550")!

    let steps: [String]
    switch architecture {
    case .appleSilicon:
      steps = [
        "Shut down your Mac and disconnect non-essential external devices.",
        "Press and hold the power button until startup options appear.",
        "When \"Options\" appears, release the power button.",
        "Press and hold Command (⌘)-D to start Apple Diagnostics."
      ]
    case .intel:
      steps = [
        "Shut down your Mac and disconnect non-essential external devices.",
        "Turn on your Mac and immediately press and hold D.",
        "Release D when Apple Diagnostics starts.",
        "If local diagnostics is unavailable, try Option-D for internet diagnostics."
      ]
    case .unknown:
      steps = [
        "Shut down your Mac and disconnect non-essential external devices.",
        "Turn on your Mac and try holding D.",
        "If that does not work, restart and try Command (⌘)-D from startup options.",
      ]
    }

    let notes = [
      "Apple Diagnostics focuses on built-in Mac hardware and may not validate all external peripherals.",
      "On macOS Tahoe 26 and newer, diagnostics can prompt for specific hardware categories (display, keyboard, trackpad).",
      "Update macOS to the latest version before running diagnostics when possible."
    ]

    return AppleDiagnosticsGuide(
      architecture: architecture,
      steps: steps,
      supportURL: supportURL,
      notes: notes
    )
  }

  private func detectArchitecture() -> MachineArchitecture {
    #if arch(arm64)
      return .appleSilicon
    #elseif arch(x86_64)
      return .intel
    #else
      return .unknown
    #endif
  }
}
