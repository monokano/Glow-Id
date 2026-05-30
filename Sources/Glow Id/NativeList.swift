import SwiftUI
import AppKit

// MARK: - NativeListColumn

/// NativeList の列定義。
struct NativeListColumn<Item> {
    let title: String
    let value: (Item) -> String
    var isBold: (Item) -> Bool
    var textColor: (Item) -> NSColor
    var icon: ((Item) -> NSImage?)?
    var iconSize: CGFloat
    var customView: ((Item, _ isSelected: Bool) -> NSView?)?
    var resizable: Bool
    var fitLastColumn: Bool
    var minWidth: CGFloat
    var width: CGFloat?
    var alignment: NSTextAlignment

    init(_ title: String,
         _ value: @escaping (Item) -> String,
         isBold: @escaping (Item) -> Bool = { _ in false },
         textColor: @escaping (Item) -> NSColor = { _ in .labelColor },
         icon: ((Item) -> NSImage?)? = nil,
         iconSize: CGFloat = 16,
         customView: ((Item, _ isSelected: Bool) -> NSView?)? = nil,
         resizable: Bool = false,
         fitLastColumn: Bool = false,
         minWidth: CGFloat = 60,
         width: CGFloat? = nil,
         alignment: NSTextAlignment = .natural) {
        self.title = title
        self.value = value
        self.isBold = isBold
        self.textColor = textColor
        self.icon = icon
        self.iconSize = iconSize
        self.customView = customView
        self.resizable = resizable
        self.fitLastColumn = fitLastColumn
        self.minWidth = minWidth
        self.width = width
        self.alignment = alignment
    }
}

extension NativeListColumn {
    /// KeyPath を使った便利イニシャライザ。
    init<V: CustomStringConvertible>(_ title: String,
                                     _ keyPath: KeyPath<Item, V>,
                                     isBold: @escaping (Item) -> Bool = { _ in false },
                                     textColor: @escaping (Item) -> NSColor = { _ in .labelColor },
                                     icon: ((Item) -> NSImage?)? = nil,
                                     iconSize: CGFloat = 16,
                                     customView: ((Item, _ isSelected: Bool) -> NSView?)? = nil,
                                     resizable: Bool = false,
                                     fitLastColumn: Bool = false,
                                     minWidth: CGFloat = 60,
                                     width: CGFloat? = nil,
                                     alignment: NSTextAlignment = .natural) {
        self.init(title, { $0[keyPath: keyPath].description },
                  isBold: isBold, textColor: textColor,
                  icon: icon, iconSize: iconSize, customView: customView,
                  resizable: resizable, fitLastColumn: fitLastColumn,
                  minWidth: minWidth, width: width, alignment: alignment)
    }
}

// MARK: - NativeList

/// NSTableView を直接ラップした SwiftUI ビュー。
/// - ヘッダ表示・複数列・Finder 風ソート（localizedStandardCompare）に対応。
/// - showHeader: false でヘッダを非表示。
/// - bounces: false でスクロールバウンスを無効。
/// - hasBorder: true でベゼルボーダーを表示。
struct NativeList<Item: Identifiable>: NSViewRepresentable {
    let columns: [NativeListColumn<Item>]
    let items: [Item]
    @Binding var selection: Item.ID?
    var onDoubleClick: ((Item) -> Void)?
    var showHeader: Bool = true
    var showCompactHeader: Bool = false
    var rowHeight: CGFloat = 22
    var fontSize: CGFloat = NSFont.systemFontSize
    var bounces: Bool = true
    var hasBorder: Bool = false
    var showColumnDividers: Bool = false
    var showRowDividers: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(columns: columns) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NSTableView()
        tv.dataSource = context.coordinator
        tv.delegate = context.coordinator
        tv.usesAlternatingRowBackgroundColors = true
        tv.style = .fullWidth
        tv.intercellSpacing = .zero
        tv.focusRingType = .none
        tv.rowHeight = rowHeight
        tv.allowsMultipleSelection = false
        tv.columnAutoresizingStyle = columns.last?.fitLastColumn == true
            ? .lastColumnOnlyAutoresizingStyle
            : .noColumnAutoresizing
        tv.allowsColumnReordering = false
        tv.target = context.coordinator
        tv.doubleAction = #selector(Coordinator.doubleClicked(_:))

        for col in columns {
            let tc = NSTableColumn(identifier: .init(col.title))
            tc.title = col.title
            tc.minWidth = col.minWidth
            if let w = col.width { tc.width = w }
            tc.headerCell.alignment = col.alignment
            tc.resizingMask = col.resizable ? .autoresizingMask : []
            tv.addTableColumn(tc)
        }

        if !showHeader          { tv.headerView = nil }
        else if showCompactHeader { tv.headerView = CompactHeaderView() }
        var grid: NSTableView.GridLineStyle = []
        if showColumnDividers { grid.insert(.solidVerticalGridLineMask) }
        if showRowDividers    { grid.insert(.solidHorizontalGridLineMask) }
        tv.gridStyleMask = grid

        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.verticalScrollElasticity = bounces ? .automatic : .none
        sv.horizontalScrollElasticity = .none
        sv.borderType = hasBorder ? .bezelBorder : .noBorder
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        context.coordinator.fontSize = fontSize
        context.coordinator.tableView = tv
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.onDoubleClick = onDoubleClick
        coord.selectionChanged = { newID in DispatchQueue.main.async { selection = newID } }

        let newIDs = items.map(\.id)
        if newIDs != coord.sourceIDs {
            coord.sourceItems = items
            coord.sourceIDs = newIDs
            coord.isUpdating = true
            coord.applySorting()
            coord.tableView?.reloadData()
            coord.isUpdating = false
        }

        guard let tv = coord.tableView else { return }
        let targetRow = selection.flatMap { sel in
            coord.sortedItems.firstIndex(where: { $0.id == sel })
        }
        let currentRow = tv.selectedRow >= 0 ? tv.selectedRow : nil
        if targetRow != currentRow {
            if let row = targetRow {
                tv.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tv.scrollRowToVisible(row)
            } else {
                tv.deselectAll(nil)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let columns: [NativeListColumn<Item>]
        var sourceItems: [Item] = []
        var sourceIDs: [Item.ID] = []
        var sortedItems: [Item] = []
        var onDoubleClick: ((Item) -> Void)?
        var selectionChanged: ((Item.ID?) -> Void)?
        var isUpdating = false
        var fontSize: CGFloat = NSFont.systemFontSize
        weak var tableView: NSTableView?

        init(columns: [NativeListColumn<Item>]) { self.columns = columns }

        @_optimize(none) deinit {}

        func applySorting() {
            guard let tv = tableView, !tv.sortDescriptors.isEmpty else {
                sortedItems = sourceItems; return
            }
            sortedItems = sorted(sourceItems, by: tv.sortDescriptors)
        }

        private func sorted(_ items: [Item], by descriptors: [NSSortDescriptor]) -> [Item] {
            guard let desc = descriptors.first, let key = desc.key,
                  let col = columns.first(where: { $0.title == key }) else { return items }
            return items.sorted {
                let cmp = col.value($0).localizedStandardCompare(col.value($1))
                return desc.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { sortedItems.count }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
            isUpdating = true
            sortedItems = sorted(sourceItems, by: tableView.sortDescriptors)
            tableView.reloadData()
            isUpdating = false
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tc = tableColumn,
                  let col = columns.first(where: { $0.title == tc.identifier.rawValue }),
                  row < sortedItems.count else { return nil }
            let item = sortedItems[row]

            // カスタムビューが指定されていればそれを使う（セル再利用なし）
            if let makeCustom = col.customView {
                let isSelected = tableView.isRowSelected(row)
                let wrapper = NSTableCellView()
                if let custom = makeCustom(item, isSelected) {
                    custom.translatesAutoresizingMaskIntoConstraints = false
                    wrapper.addSubview(custom)
                    var cs: [NSLayoutConstraint] = [
                        custom.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                        custom.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                    ]
                    if custom.frame.width  > 0 { cs.append(custom.widthAnchor.constraint(equalToConstant:  custom.frame.width)) }
                    if custom.frame.height > 0 { cs.append(custom.heightAnchor.constraint(equalToConstant: custom.frame.height)) }
                    NSLayoutConstraint.activate(cs)
                }
                return wrapper
            }

            // アイコン付きセル
            if col.icon != nil { return makeIconCell(tc: tc, col: col, item: item, in: tableView) }

            // テキストのみ
            return makeTextCell(tc: tc, col: col, item: item, in: tableView)
        }

        private func makeTextCell(tc: NSTableColumn, col: NativeListColumn<Item>,
                                   item: Item, in tableView: NSTableView) -> NSView {
            let cellID = NSUserInterfaceItemIdentifier("cell_\(tc.identifier.rawValue)")
            let cellView: NSTableCellView
            let field: NSTextField
            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
               let tf = reused.textField {
                cellView = reused; field = tf
            } else {
                cellView = NSTableCellView(); cellView.identifier = cellID
                field = NSTextField(labelWithString: "")
                field.lineBreakMode = .byTruncatingTail
                field.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(field); cellView.textField = field
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                    field.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                    field.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                ])
            }
            field.alignment   = col.alignment
            field.stringValue = col.value(item)
            field.textColor   = col.textColor(item)
            field.font = col.isBold(item)
                ? .boldSystemFont(ofSize: fontSize)
                : .systemFont(ofSize: fontSize)
            return cellView
        }

        private func makeIconCell(tc: NSTableColumn, col: NativeListColumn<Item>,
                                   item: Item, in tableView: NSTableView) -> NSView {
            let cellID = NSUserInterfaceItemIdentifier("icon_\(tc.identifier.rawValue)")
            let cellView: NSTableCellView; let imageView: NSImageView; let field: NSTextField
            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
               let iv = reused.imageView, let tf = reused.textField {
                cellView = reused; imageView = iv; field = tf
            } else {
                cellView = NSTableCellView(); cellView.identifier = cellID
                imageView = NSImageView()
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                field = NSTextField(labelWithString: "")
                field.lineBreakMode = .byTruncatingTail
                field.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(imageView); cellView.addSubview(field)
                cellView.imageView = imageView; cellView.textField = field
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: col.iconSize),
                    imageView.heightAnchor.constraint(equalToConstant: col.iconSize),
                    field.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                    field.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                    field.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                ])
            }
            imageView.image   = col.icon?(item)
            field.alignment   = col.alignment
            field.stringValue = col.value(item)
            field.textColor   = col.textColor(item)
            field.font = col.isBold(item)
                ? .boldSystemFont(ofSize: fontSize)
                : .systemFont(ofSize: fontSize)
            return cellView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTableView else { return }
            let row = tv.selectedRow
            selectionChanged?(row >= 0 && row < sortedItems.count ? sortedItems[row].id : nil)
            // customView の選択表示を更新するため再描画
            let customColIndices = columns.indices.filter { columns[$0].customView != nil }
            if !customColIndices.isEmpty {
                let allRows = IndexSet(integersIn: 0..<tv.numberOfRows)
                let colSet = IndexSet(customColIndices)
                tv.reloadData(forRowIndexes: allRows, columnIndexes: colSet)
            }
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < sortedItems.count else { return }
            onDoubleClick?(sortedItems[row])
        }
    }
}

// MARK: - CompactHeaderView

private class CompactHeaderView: NSTableHeaderView {
    private let headerHeight: CGFloat = 17
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: headerHeight)
    }
    override func layout() {
        super.layout()
        if frame.height != headerHeight { frame.size.height = headerHeight }
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
}
