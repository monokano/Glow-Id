import AppKit
import Combine
import SwiftUI

// MARK: - AppListRow

struct AppListRow: Identifiable {
    let id = UUID()
    var appClass: InDesignAppClass
    var name: String
    var version: String
    var icon: NSImage?
    var isBooted: Bool
    var canOpen: Bool
    var isBeta: Bool

    var appURL: URL { appClass.appURL }
}

// MARK: - InfoViewModel

@MainActor
final class InfoViewModel: ObservableObject {

    var fc: FileClass

    @Published var tableRows: [AppListRow] = []
    @Published var selectedID: AppListRow.ID? = nil
    @Published var openHigher: Bool {
        didSet { Preferences.shared.allowOpeningInHigherVersion = openHigher; Preferences.shared.save(); rebuild() }
    }
    private var terminationObserver: NSObjectProtocol?

    var selectedRow: AppListRow? {
        guard let id = selectedID else { return nil }
        return tableRows.first { $0.id == id }
    }

    // MARK: 警告バルーン（アイコンの上）

    var hasBalloon: Bool { !balloonMessage.isEmpty }

    var balloonMessage: String {
        if fc.contentKind == "idml" { return "" }
        switch fc.infoWindowMode {
        case 1: return String(localized: "No InDesign.app with matching minor version")
        case 2: return String(localized: "No InDesign.app with matching major version")
        case 3: return String(localized: "Another InDesign.app is already running")
        case 4: return String(localized: "Version info cannot be detected")
        default: return ""
        }
    }

    // MARK: 種類バルーン（アイコンの左）

    var hasKindBalloon: Bool { !kindBalloonMessage.isEmpty }

    var kindBalloonMessage: String {
        if fc.isNotInDesign { return String(localized: "Not an InDesign file") }
        if fc.isExtMismatch  { return String(localized: "Extension does not match") }
        return ""
    }

    // MARK: ヘッダー表示

    /// ファイルの種類行（例: "InDesign ドキュメント (.indd)"）
    var kindLabel: String {
        switch fc.contentKind {
        case "indd": return String(localized: "InDesign Document (.indd)")
        case "indt": return String(localized: "InDesign Template (.indt)")
        case "indb": return String(localized: "InDesign Book (.indb)")
        case "indl": return String(localized: "InDesign Library (.indl)")
        case "idml": return String(localized: "InDesign Markup (.idml)")
        default:     return ""
        }
    }

    // MARK: 開くボタン

    var openEnabled: Bool { selectedRow?.canOpen == true }

    var openTitle: String {
        guard let row = selectedRow, row.canOpen else { return String(localized: "Open") }
        let verName = FileInfo.versionName(row.version)
        return String(format: String(localized: "Open with %@"), verName)
    }

    // MARK: 終了ボタン

    var quitEnabled: Bool { selectedRow?.isBooted == true }

    // MARK: 「上位で開く」チェックボックス

    var showOpenHigher: Bool {
        // ファイルの major より上位バージョンのアプリが存在する場合に活性化
        let myMajor = fc.versionMajor
        return tableRows.contains { row in
            let appMajor = Int(row.version.components(separatedBy: ".").first ?? "") ?? 0
            return appMajor > myMajor && !row.isBeta
        }
    }

    // MARK: Init

    init(fc: FileClass) {
        self.fc = fc
        self.openHigher = Preferences.shared.allowOpeningInHigherVersion
        buildTableRows()
        selectedID = defaultSelectionID()
    }

    // MARK: テーブル構築

    func buildTableRows() {
        tableRows = []
        let myMajor = fc.versionMajor
        let minAppMajor = InDesignApp.shared.getMinimumVerAppClass()
            .flatMap { Int($0.version.components(separatedBy: ".").first ?? "") } ?? 0

        InDesignApp.shared.getAppALLRefresh()
        for ac in InDesignApp.shared.appClassALLIncludeBeta {
            let parts = ac.version.components(separatedBy: ".")
            let appMajor = Int(parts.first ?? "") ?? 0
            let appMinor = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
            let folder = ac.appURL.deletingLastPathComponent().lastPathComponent
            let isBeta = folder.contains("Beta") || folder.contains("Prerelease")

            var canOpen = false
            if !isBeta {
                if fc.contentKind == "idml" {
                    canOpen = true
                } else if appMajor < myMajor {
                    canOpen = false
                } else if appMajor == myMajor {
                    canOpen = true  // major 一致なら minor 不一致でも活性化（通知のみで判断）
                } else {
                    // appMajor > myMajor
                    canOpen = openHigher
                }
                if minAppMajor > myMajor { canOpen = true }
                if fc.isExtMismatch { canOpen = false }  // 拡張子不一致は全行グレーアウト
            }
            _ = appMinor
            tableRows.append(AppListRow(
                appClass: ac,
                name: folder,
                version: ac.version,
                icon: ac.icon,
                isBooted: ac.isBooted,
                canOpen: canOpen,
                isBeta: isBeta
            ))
        }
    }

    private func defaultSelectionID() -> AppListRow.ID? {
        let myMajor = fc.versionMajor
        let myMinor = fc.versionMinor

        // 1. major.minor 完全一致（非 Beta）
        if myMinor >= 0 {
            if let row = tableRows.first(where: { row in
                !row.isBeta && row.canOpen &&
                Int(row.version.components(separatedBy: ".").first ?? "") == myMajor &&
                (row.version.components(separatedBy: ".").dropFirst().first.flatMap { Int($0) } ?? -1) == myMinor
            }) { return row.id }
        }
        // 2. major 一致の最初の非 Beta 行
        if let row = tableRows.first(where: { row in
            !row.isBeta &&
            Int(row.version.components(separatedBy: ".").first ?? "") == myMajor
        }) { return row.id }
        // 3. 起動中のアプリ（拡張子不一致時は選択しない）
        if fc.isExtMismatch { return nil }
        return tableRows.first(where: { $0.isBooted && !$0.isBeta })?.id
    }

    func update(fc newFC: FileClass) {
        fc = newFC
        let prevURL = selectedRow?.appURL
        buildTableRows()
        selectedID = prevURL.flatMap { url in tableRows.first { $0.appURL == url }?.id }
            ?? defaultSelectionID()
    }

    func rebuild() {
        let prevURL = selectedRow?.appURL
        buildTableRows()
        selectedID = prevURL.flatMap { url in tableRows.first { $0.appURL == url }?.id }
    }

    // MARK: アクション

    func openFile(onClose: @escaping () -> Void, forced: Bool = false) {
        guard let item = selectedRow, (forced || item.canOpen), let fileURL = fc.file else { return }
        item.appClass.openFileURLs.append(fileURL)
        onClose()
    }

    func quitAction() {
        guard let item = selectedRow, item.isBooted else { return }
        let appURL = item.appURL
        NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardized == appURL.standardized
        }.forEach {
            $0.activate(options: .activateIgnoringOtherApps)
            $0.terminate()
        }
        observeTermination(of: appURL)
    }

    private func observeTermination(of appURL: URL) {
        let center = NSWorkspace.shared.notificationCenter
        if let prev = terminationObserver { center.removeObserver(prev) }
        terminationObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleURL?.standardized == appURL.standardized else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                center.removeObserver(self.terminationObserver as Any)
                self.terminationObserver = nil
                InDesignApp.shared.openWithSameApp(fc: self.fc, reView: true)
                self.buildTableRows()
                self.selectedID = self.defaultSelectionID()
            }
        }
    }

    // MARK: グレーアウト行の強制オープン（右クリック）

    @MainActor
    func showForceOpenMenu(for row: AppListRow, onClose: @escaping () -> Void) {
        let menu = NSMenu()
        let handler = ClosureMenuItem { [weak self] in
            self?.selectedID = row.id
            self?.openFile(onClose: onClose, forced: true)
        }
        let item = NSMenuItem(title: String(localized: "Open"),
                              action: #selector(ClosureMenuItem.invoke(_:)),
                              keyEquivalent: "")
        item.target = handler
        item.representedObject = handler
        menu.addItem(item)
        if let event = NSApp.currentEvent, let view = NSApp.keyWindow?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
    }
}

// MARK: - ClosureMenuItem

private final class ClosureMenuItem: NSObject {
    let closure: () -> Void
    init(_ closure: @escaping () -> Void) { self.closure = closure }
    @objc func invoke(_ sender: Any?) { closure() }
}

// MARK: - InfoView

struct InfoView: View {

    @ObservedObject var vm: InfoViewModel
    let onClose: () -> Void
    @State private var balloonVisible = false

    private var minTableHeight: CGFloat {
        max(26, CGFloat(max(1, min(vm.tableRows.count, 3))) * 26 - 134)
    }

    private var minContentHeight: CGFloat {
        let extraRows = max(0, vm.tableRows.count - 3)
        return 277 + CGFloat(extraRows) * 26 + 26
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            appTableSection
            buttonBar
            Divider()
                .padding(.horizontal, 16)
            checkboxSection
        }
        .frame(width: 420)
        .frame(minHeight: minContentHeight)
        .offset(y: -6)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                balloonVisible = true
            }
        }
    }

    // MARK: ── ヘッダー ──────────────────────────────────

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            iconCluster
                .offset(y: -2)
            VStack(alignment: .leading, spacing: 7) {
                // ファイル名
                Text(vm.fc.file?.lastPathComponent ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // ファイルの種類
                if !vm.kindLabel.isEmpty {
                    Text(vm.kindLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // 作成バージョン
                if !vm.fc.versionLabel.isEmpty {
                    Text(vm.fc.versionLabel)
                        .font(.system(size: 16, weight: .medium))
                        .textSelection(.enabled)
                }
            }
            .padding(.leading, -6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var iconCluster: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = vm.fc.file {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)
                        .resized(to: NSSize(width: 56, height: 56)))
                        .resizable()
                        .frame(width: 56, height: 56)
                } else {
                    Color.clear.frame(width: 56, height: 56)
                }
            }
            if vm.fc.infoWindowMode > 0 {
                alertBadge.offset(x: -7, y: 11)
            }
        }
        .badgePopover(vm.balloonMessage,
                      isPresented: .constant(vm.hasBalloon && balloonVisible),
                      edge: .top,
                      color: badgePopoverDefaultColor)
        .badgePopover(vm.kindBalloonMessage,
                      isPresented: .constant(vm.hasKindBalloon && balloonVisible),
                      edge: .leading,
                      color: NSColor(red: 0.698, green: 0.0, blue: 0.008, alpha: 1.0))
    }

    @ViewBuilder
    private var alertBadge: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.multicolor)
            .font(.system(size: 36, weight: .bold))
    }

    // MARK: ── アプリ一覧（NativeList） ────────────────────

    private var appTableSection: some View {
        NativeList(
            columns: [
                NativeListColumn(
                    String(localized: "Application"),
                    { $0.name },
                    textColor: { $0.canOpen ? .labelColor : .secondaryLabelColor },
                    icon: { $0.icon },
                    iconSize: 20,
                    resizable: true,
                    minWidth: 150,
                    width: 255
                ),
                NativeListColumn(
                    String(localized: "Version"),
                    { $0.version },
                    textColor: { $0.canOpen ? .labelColor : .secondaryLabelColor },
                    minWidth: 75,
                    width: 75,
                    alignment: .center
                ),
                NativeListColumn(
                    String(localized: "Status"),
                    { _ in "" },
                    customView: { row, isSelected in
                        guard row.isBooted else { return nil }
                        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
                        dot.wantsLayer = true
                        dot.layer?.backgroundColor = (isSelected ? NSColor.white : NSColor.controlAccentColor).cgColor
                        dot.layer?.cornerRadius = 4
                        return dot
                    },
                    fitLastColumn: true,
                    minWidth: 53,
                    width: 53,
                    alignment: .center
                ),
            ],
            items: vm.tableRows,
            selection: $vm.selectedID,
            onDoubleClick: { [vm] row in
                vm.selectedID = row.id
                if row.canOpen {
                    vm.openFile(onClose: onClose)
                } else {
                    vm.showForceOpenMenu(for: row, onClose: onClose)
                }
            },
            showHeader: false,
            rowHeight: 26,
            fontSize: NSFont.systemFontSize,
            bounces: false,
            hasBorder: true,
            showColumnDividers: true,
            showRowDividers: true
        )
        .frame(minHeight: minTableHeight, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    // MARK: ── ボタン行 ──────────────────────────────────

    private var buttonBar: some View {
        HStack(spacing: 8) {
            FixedButton(String(localized: "Quit"), width: 100,
                        isDefault: false,
                        isEnabled: vm.quitEnabled) { vm.quitAction() }
            Spacer()
            FixedButton(String(localized: "Cancel"), width: 100,
                        isCancel: true) { onClose() }
            FixedButton(vm.openTitle, width: 140,
                        isDefault: true,
                        isEnabled: vm.openEnabled) { vm.openFile(onClose: onClose) }
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    // MARK: ── チェックボックス行 ─────────────────────────

    private var checkboxSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Allow opening in higher version", isOn: $vm.openHigher)
                .disabled(!vm.showOpenHigher)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: NSFont.systemFontSize))
        .padding(.leading, 17)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - InfoWindowController

class InfoWindowController: NSWindowController {

    var fc: FileClass
    private var viewModel: InfoViewModel?
    var onEvaluate: ((FileClass) -> Void)?

    init(fc: FileClass) {
        self.fc = fc
        let win = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 304),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Glow Id - Notification")
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.standardWindowButton(.closeButton)?.isHidden = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        win.maxSize = NSSize(width: 420, height: 1994)
        super.init(window: win)

        let vm = InfoViewModel(fc: fc)
        viewModel = vm
        let content = InfoView(
            vm: vm,
            onClose: { [weak self] in self?.closeModal() }
        )
        win.contentView = NSHostingView(rootView: content)
    }

    required init?(coder: NSCoder) { fatalError() }

    func showModal() {
        guard let win = window else { return }
        let rowCount = viewModel?.tableRows.count ?? 0
        let extraRows = max(0, rowCount - 3)
        let targetHeight = 304 + CGFloat(extraRows) * 26 + 26
        win.setContentSize(NSSize(width: 420, height: targetHeight))
        win.minSize = win.frame.size
        centerWindow(win)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: win)
    }

    private func centerWindow(_ win: NSWindow) {
        if let screen = NSScreen.main {
            let sx = screen.visibleFrame
            let wx = win.frame
            let x = sx.minX + (sx.width  - wx.width)  / 2
            let y = sx.minY + (sx.height - wx.height) * 0.6
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    internal func closeModal() {
        window?.orderOut(nil)
        NSApp.stopModal()
    }
}
