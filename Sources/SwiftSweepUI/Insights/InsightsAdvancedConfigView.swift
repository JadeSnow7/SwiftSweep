#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif
import SwiftUI

/// Advanced Insights Configuration View (Commercial Frontend Showcase)
/// Features:
/// - Grouping by Category
/// - Drag-and-drop Priority reordering
/// - Gray-release / Feature Flag toggles
/// - Local persistence
public struct InsightsAdvancedConfigView: View {
  @State private var rulesByCategory: [RuleCategory: [RuleConfigItem]] = [:]
  @State private var expandedCategories: Set<RuleCategory> = Set(RuleCategory.allCases)

  public init() {}

  public var body: some View {
    List {
      ForEach(RuleCategory.allCases, id: \.self) { category in
        Section {
          if let items = rulesByCategory[category] {
            ForEach(items) { item in
              RuleConfigRow(
                item: item,
                onUpdate: { updatedItem in
                  updateItem(updatedItem, in: category)
                })
            }
            .onMove { indices, newOffset in
              moveItems(in: category, from: indices, to: newOffset)
            }
          }
        } header: {
          HStack {
            Image(systemName: category.icon)
              .foregroundColor(.accentColor)
            Text(category.rawValue)
              .font(.headline)
          }
        }
      }
    }
    .listStyle(.sidebar)
    .onAppear { loadRules() }
    .toolbar {
      ToolbarItem {
        Button("Reset") {
          RuleSettings.shared.resetToDefaults()
          loadRules()
        }
      }
    }
  }

  private func loadRules() {
    var grouped: [RuleCategory: [RuleConfigItem]] = [:]
    for category in RuleCategory.allCases {
      let ruleIDs = RuleSettings.rules(in: category)
      let items = ruleIDs.map { ruleID in
        RuleConfigItem(
          id: ruleID,
          name: RuleSettings.displayName(for: ruleID),
          description: RuleSettings.description(for: ruleID),
          isEnabled: RuleSettings.shared.isRuleEnabled(ruleID),
          priority: RuleSettings.shared.priority(forRule: ruleID),
          isGrayRelease: RuleSettings.shared.isGrayRelease(forRule: ruleID)
        )
      }.sorted { $0.priority > $1.priority }
      grouped[category] = items
    }
    rulesByCategory = grouped
  }

  private func updateItem(_ item: RuleConfigItem, in category: RuleCategory) {
    RuleSettings.shared.setRuleEnabled(item.id, enabled: item.isEnabled)
    RuleSettings.shared.setPriority(forRule: item.id, value: item.priority)
    RuleSettings.shared.setGrayRelease(forRule: item.id, isGray: item.isGrayRelease)

    if var items = rulesByCategory[category],
      let index = items.firstIndex(where: { $0.id == item.id })
    {
      items[index] = item
      rulesByCategory[category] = items
    }
  }

  private func moveItems(in category: RuleCategory, from source: IndexSet, to destination: Int) {
    guard var items = rulesByCategory[category] else { return }
    items.move(fromOffsets: source, toOffset: destination)

    // Update priorities based on new order (higher index = lower priority)
    for (index, item) in items.enumerated() {
      let newPriority = 100 - index * 10
      RuleSettings.shared.setPriority(forRule: item.id, value: newPriority)
      items[index].priority = newPriority
    }
    rulesByCategory[category] = items
  }
}

struct RuleConfigItem: Identifiable {
  let id: String
  let name: String
  let description: String
  var isEnabled: Bool
  var priority: Int
  var isGrayRelease: Bool
}

struct RuleConfigRow: View {
  let item: RuleConfigItem
  let onUpdate: (RuleConfigItem) -> Void

  @State private var isEnabled: Bool = true
  @State private var isGrayRelease: Bool = false

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(item.name)
            .font(.body)
          if isGrayRelease {
            Text("BETA")
              .font(.caption2)
              .fontWeight(.bold)
              .foregroundColor(.orange)
              .padding(.horizontal, 4)
              .padding(.vertical, 2)
              .background(Color.orange.opacity(0.15))
              .cornerRadius(4)
          }
        }
        Text(item.description)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()

      // Gray Release Toggle (simulated A/B)
      Button {
        isGrayRelease.toggle()
        var updated = item
        updated.isGrayRelease = isGrayRelease
        onUpdate(updated)
      } label: {
        Image(systemName: isGrayRelease ? "testtube.2" : "testtube.2")
          .foregroundColor(isGrayRelease ? .orange : .gray)
      }
      .buttonStyle(.plain)
      .help("Toggle Gray Release (A/B Test)")

      Toggle("", isOn: $isEnabled)
        .labelsHidden()
        .onChange(of: isEnabled) { newValue in
          var updated = item
          updated.isEnabled = newValue
          onUpdate(updated)
        }
    }
    .padding(.vertical, 4)
    .onAppear {
      isEnabled = item.isEnabled
      isGrayRelease = item.isGrayRelease
    }
  }
}

#Preview {
  InsightsAdvancedConfigView()
    .frame(width: 500, height: 600)
}
