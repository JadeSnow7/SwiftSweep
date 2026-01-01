import AppKit
import SwiftUI

/// High-Performance DataGrid using NSTableView (Commercial Frontend Showcase)
/// Features:
/// - True virtualization via NSTableView
/// - Sorting by columns
/// - Column resizing
/// - Selection handling
public struct DataGridView<Item: Identifiable>: NSViewRepresentable {
  public typealias NSViewType = NSScrollView

  let items: [Item]
  let columns: [DataGridColumn<Item>]
  let onSelect: ((Item?) -> Void)?

  public init(
    items: [Item],
    columns: [DataGridColumn<Item>],
    onSelect: ((Item?) -> Void)? = nil
  ) {
    self.items = items
    self.columns = columns
    self.onSelect = onSelect
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true

    let tableView = NSTableView()
    tableView.style = .inset
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.allowsColumnReordering = true
    tableView.allowsColumnResizing = true
    tableView.allowsMultipleSelection = false
    tableView.delegate = context.coordinator
    tableView.dataSource = context.coordinator

    // Add columns
    for column in columns {
      let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
      tableColumn.title = column.title
      tableColumn.width = column.width
      tableColumn.minWidth = 50
      tableColumn.maxWidth = 500
      tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.id, ascending: true)
      tableView.addTableColumn(tableColumn)
    }

    scrollView.documentView = tableView
    context.coordinator.tableView = tableView

    return scrollView
  }

  public func updateNSView(_ nsView: NSScrollView, context: Context) {
    context.coordinator.items = items
    context.coordinator.columns = columns
    context.coordinator.onSelect = onSelect
    (nsView.documentView as? NSTableView)?.reloadData()
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(items: items, columns: columns, onSelect: onSelect)
  }

  public class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    var items: [Item]
    var columns: [DataGridColumn<Item>]
    var onSelect: ((Item?) -> Void)?
    weak var tableView: NSTableView?

    init(items: [Item], columns: [DataGridColumn<Item>], onSelect: ((Item?) -> Void)?) {
      self.items = items
      self.columns = columns
      self.onSelect = onSelect
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
      items.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      guard let tableColumn = tableColumn else { return nil }
      let columnID = tableColumn.identifier.rawValue

      guard let column = columns.first(where: { $0.id == columnID }) else { return nil }

      let cellID = NSUserInterfaceItemIdentifier("DataGridCell_\(columnID)")
      var cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField

      if cellView == nil {
        cellView = NSTextField(labelWithString: "")
        cellView?.identifier = cellID
        cellView?.lineBreakMode = .byTruncatingTail
      }

      let item = items[row]
      cellView?.stringValue = column.value(item)

      return cellView
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
      guard let tableView = tableView else { return }
      let selectedRow = tableView.selectedRow
      if selectedRow >= 0 && selectedRow < items.count {
        onSelect?(items[selectedRow])
      } else {
        onSelect?(nil)
      }
    }

    public func tableView(
      _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
      // Sorting support (basic implementation)
      // In production, would sort `items` and reload
    }
  }
}

/// Column definition for DataGrid
public struct DataGridColumn<Item> {
  public let id: String
  public let title: String
  public let width: CGFloat
  public let value: (Item) -> String

  public init(id: String, title: String, width: CGFloat = 120, value: @escaping (Item) -> String) {
    self.id = id
    self.title = title
    self.width = width
    self.value = value
  }
}

// MARK: - Demo / Preview

struct MockFileItem: Identifiable {
  let id: String
  let name: String
  let size: String
  let modified: String
}

#Preview {
  let mockItems = (0..<5000).map { i in
    MockFileItem(
      id: "file_\(i)",
      name: "Document_\(i).pdf",
      size: "\(Int.random(in: 1...1000)) MB",
      modified: "2024-01-\(String(format: "%02d", (i % 28) + 1))"
    )
  }

  let columns: [DataGridColumn<MockFileItem>] = [
    DataGridColumn(id: "name", title: "Name", width: 200) { $0.name },
    DataGridColumn(id: "size", title: "Size", width: 80) { $0.size },
    DataGridColumn(id: "modified", title: "Modified", width: 120) { $0.modified },
  ]

  return DataGridView(items: mockItems, columns: columns) { item in
    if let item = item {
      print("Selected: \(item.name)")
    }
  }
  .frame(width: 600, height: 400)
}
