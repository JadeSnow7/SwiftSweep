import Charts
import SwiftUI

/// Result Dashboard with Trends (Commercial Frontend Showcase)
/// Features:
/// - Space savings trend chart
/// - Rule hit rate visualization
/// - Category breakdown pie chart
@available(macOS 14.0, *)
public struct ResultDashboardView: View {
  @State private var spaceSavingsData: [SpaceSavingsEntry] = []
  @State private var ruleHitData: [RuleHitEntry] = []
  @State private var categoryData: [CategoryEntry] = []

  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Header
        VStack(alignment: .leading, spacing: 4) {
          Text("Cleanup Dashboard")
            .font(.largeTitle)
            .fontWeight(.bold)
          Text("Track your space savings and cleanup trends")
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)

        // Space Savings Trend
        GroupBox("Space Saved Over Time") {
          Chart(spaceSavingsData) { entry in
            LineMark(
              x: .value("Date", entry.date),
              y: .value("GB Saved", entry.gbSaved)
            )
            .foregroundStyle(.blue.gradient)

            AreaMark(
              x: .value("Date", entry.date),
              y: .value("GB Saved", entry.gbSaved)
            )
            .foregroundStyle(.blue.opacity(0.1).gradient)
          }
          .frame(height: 200)
          .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
              AxisGridLine()
              AxisValueLabel(format: .dateTime.month().day())
            }
          }
          .chartYAxis {
            AxisMarks { value in
              AxisGridLine()
              AxisValueLabel {
                if let gb = value.as(Double.self) {
                  Text("\(gb, specifier: "%.1f") GB")
                }
              }
            }
          }
        }
        .padding(.horizontal)

        HStack(spacing: 16) {
          // Rule Hit Rate
          GroupBox("Rule Hit Rate") {
            Chart(ruleHitData) { entry in
              BarMark(
                x: .value("Hits", entry.hits),
                y: .value("Rule", entry.ruleName)
              )
              .foregroundStyle(by: .value("Category", entry.category))
            }
            .frame(height: 200)
            .chartXAxis {
              AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
              }
            }
          }

          // Category Breakdown
          GroupBox("By Category") {
            Chart(categoryData) { entry in
              SectorMark(
                angle: .value("Size", entry.sizeGB),
                innerRadius: .ratio(0.5),
                angularInset: 1.0
              )
              .foregroundStyle(by: .value("Category", entry.category))
              .cornerRadius(4)
            }
            .frame(height: 200)
          }
        }
        .padding(.horizontal)

        Spacer()
      }
      .padding(.vertical)
    }
    .onAppear { loadMockData() }
  }

  private func loadMockData() {
    // Generate mock space savings data
    let calendar = Calendar.current
    spaceSavingsData = (0..<30).map { dayOffset in
      let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
      return SpaceSavingsEntry(
        date: date,
        gbSaved: Double.random(in: 0.5...5.0) + Double(30 - dayOffset) * 0.1
      )
    }.reversed()

    // Mock rule hit data
    ruleHitData = [
      RuleHitEntry(ruleName: "Browser Cache", hits: 45, category: "Privacy"),
      RuleHitEntry(ruleName: "Old Downloads", hits: 32, category: "Storage"),
      RuleHitEntry(ruleName: "Dev Caches", hits: 28, category: "Storage"),
      RuleHitEntry(ruleName: "Large Caches", hits: 21, category: "Storage"),
      RuleHitEntry(ruleName: "Unused Apps", hits: 12, category: "Performance"),
    ]

    // Mock category data
    categoryData = [
      CategoryEntry(category: "Storage", sizeGB: 15.2),
      CategoryEntry(category: "Privacy", sizeGB: 8.4),
      CategoryEntry(category: "Performance", sizeGB: 3.1),
      CategoryEntry(category: "Security", sizeGB: 1.2),
    ]
  }
}

struct SpaceSavingsEntry: Identifiable {
  let id = UUID()
  let date: Date
  let gbSaved: Double
}

struct RuleHitEntry: Identifiable {
  let id = UUID()
  let ruleName: String
  let hits: Int
  let category: String
}

struct CategoryEntry: Identifiable {
  let id = UUID()
  let category: String
  let sizeGB: Double
}

@available(macOS 14.0, *)
#Preview {
  ResultDashboardView()
    .frame(width: 800, height: 600)
}
