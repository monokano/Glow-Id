import AppKit
import SwiftUI
import UniformTypeIdentifiers


class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    // MARK: - State

    private var dropItems: [URL] = []
    private var countDrop: Int = 0
    private var cmdKeyDownAtDrop: Bool = false
    /// applicationDidFinishLaunching が終わったか
    private var launchFinished: Bool = false
    /// 起動処理の完了を待って runStart() を実行するための保留フラグ
    private var pendingRunStart: Bool = false
    var infoWindowController: InfoWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var helpWindowController: HelpWindowController?

    // MARK: - applicationWillFinishLaunching

    func applicationWillFinishLaunching(_ notification: Notification) {
        if #unavailable(macOS 13.0) { return }
        InDesignApp.shared.getAppALL()
    }

    // MARK: - applicationDidFinishLaunching

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        if #unavailable(macOS 13.0) {
            showAlertAndQuit(
                message: NSLocalizedString("System Requirement", comment: ""),
                info: "macOS 13.0 or later is required."
            )
            return
        }

        NSApp.delegate = self

        // ファイルの関連付けは起動時には変更しない（環境設定の「関連付ける」ボタンから。FileAssociation.swift）

        // 不要なメニューを削除
        DispatchQueue.main.async {
            let removes = ["表示", "View", "ウインドウ", "Window"]
            NSApp.mainMenu?.items
                .filter { removes.contains($0.title) }
                .forEach { NSApp.mainMenu?.removeItem($0) }
        }

        // 隔離起動（App Translocation）中なら、Finder での移動を案内する。
        // 移動すれば出なくなるので毎回出す。「終了」ならドロップされたファイルも開かずに終了する。
        if AppTranslocation.isTranslocated(Bundle.main.bundleURL) {
            if !showTranslocationAlert() {
                appQuit()
                return
            }
        }

        // アイコン取込は起動時には行わない（環境設定の「アイコンを取り込む」ボタンから）
        launchFinished = true
        if pendingRunStart {
            pendingRunStart = false
            runStart()
        }
    }

    // MARK: - Dock メニュー

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let prefsItem = NSMenuItem(
            title: String(localized: "Preferences…"),
            action: #selector(openPreferences),
            keyEquivalent: ""
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        // ヘルプ（Glow Ai と同じ。ウインドウのタイトルはヘルプメニューから開いたときと同じ）
        let helpItem = NSMenuItem(
            title: String(localized: "Help"),
            action: #selector(dockHelpClicked(_:)),
            keyEquivalent: ""
        )
        helpItem.target = self
        menu.addItem(helpItem)

        return menu
    }

    // MARK: - メニューバー

    @objc func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func dockHelpClicked(_ sender: Any?) {
        openHelp()
    }

    func openHelp() {
        if helpWindowController == nil {
            helpWindowController = HelpWindowController()
        }
        helpWindowController?.show()
    }

    // MARK: - application(_:open:)

    func application(_ application: NSApplication, open urls: [URL]) {
        countDrop += 1

        if countDrop == 1 {
            cmdKeyDownAtDrop = NSEvent.modifierFlags.contains(.command)
        }

        for url in urls {
            var resolved = url
            if let r = try? URL(resolvingAliasFileAt: url) { resolved = r }
            guard FileManager.default.fileExists(atPath: resolved.path) else { continue }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir)
            guard !isDir.boolValue else { continue }
            dropItems.append(resolved)
        }

        guard !dropItems.isEmpty else { appQuit(); return }

        if countDrop == 1 {
            // applicationDidFinishLaunching より先に来た場合は、起動処理が終わるまで保留する。
            if launchFinished {
                runStart()
            } else {
                pendingRunStart = true
            }
        }
    }

    // MARK: - applicationShouldTerminateAfterLastWindowClosed

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - applicationWillTerminate

    func applicationWillTerminate(_ notification: Notification) {
        Preferences.shared.save()
    }

    // MARK: - RunStart

    private func runStart() {
        let prefs = Preferences.shared

        for url in dropItems {
            let fc = FileInfo.parse(url: url, useFullVersion: prefs.useFullVersion, hideBuildNumber: prefs.hideBuildNumber)

            let needsWindow = evaluateInfoWindowMode(fc: fc, cmdKeyDown: cmdKeyDownAtDrop)
            if needsWindow {
                showInfoWindow(fc: fc)
            }
        }

        let group = DispatchGroup()
        for ac in InDesignApp.shared.appClassALLIncludeBeta where !ac.openFileURLs.isEmpty {
            group.enter()
            InDesignApp.shared.openWith(appURL: ac.appURL, fileURLs: ac.openFileURLs) {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.appQuit()
        }
    }

    // MARK: - showInfoWindow

    func showInfoWindow(fc: FileClass) {
        let controller = InfoWindowController(fc: fc)
        controller.onEvaluate = { [weak self] newFC in
            self?.evaluateInfoWindowMode(fc: newFC)
        }
        infoWindowController = controller
        controller.showModal()
        infoWindowController = nil
    }

    // MARK: - evaluateInfoWindowMode

    @discardableResult
    func evaluateInfoWindowMode(fc: FileClass, cmdKeyDown: Bool = false) -> Bool {
        // InDesign ファイルではない
        if fc.isNotInDesign {
            fc.infoWindowMode = 0  // 種類バルーンで表示
            return true
        }
        // バージョン未検出
        if fc.isVersionUndetected {
            fc.infoWindowMode = 4
            return true
        }
        // 正常な InDesign ファイル
        let opened = InDesignApp.shared.openWithSameApp(fc: fc, cmdKeyDown: cmdKeyDown)
        return !opened
    }

    // MARK: - 隔離起動の案内

    /// 隔離起動の案内を出す。「このまま続ける」なら true、「終了」なら false。
    /// 元の場所がアプリケーションフォルダの中（そこで ZIP を展開した場合など）なら、
    /// 「いったん外へ出して戻す」案内にする。元の場所が分からなければ両方に効く文言にする。
    private func showTranslocationAlert() -> Bool {
        let original = AppTranslocation.originalURL(of: Bundle.main.bundleURL)
        let title: String
        let action: String
        switch original.map({ AppTranslocation.isInApplicationsFolder($0) }) {
        case true?:
            title = String(localized: "Move Glow Id again in the Finder")
            action = String(localized: "Glow Id is in the Applications folder, but it was moved there in a way that doesn't meet Apple's requirements. Quit Glow Id, move it to the Desktop in the Finder, move it back to the Applications folder, and then open it again. Also, make sure to move it by itself, not together with other apps.")
        case false?:
            title = String(localized: "Move Glow Id to the Applications folder")
            action = String(localized: "Quit Glow Id, move it to the Applications folder in the Finder, and then open it again. Also, make sure to move it by itself, not together with other apps.")
        case nil:
            title = String(localized: "Move Glow Id to the Applications folder")
            action = String(localized: "Quit Glow Id, move it to the Applications folder in the Finder, and then open it again. If it's already in the Applications folder, move it to the Desktop and back again in the Finder. Also, make sure to move it by itself, not together with other apps.")
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = [
            String(localized: "Glow Id is running from a temporary location because it was opened right after being downloaded."),
            String(localized: "For security, macOS runs apps obtained from the internet from a copy in a temporary location until you move them in the Finder."),
            action,
        ].joined(separator: "\n\n")
        alert.addButton(withTitle: String(localized: "Quit"))             // 既定（Return）
        let continueButton = alert.addButton(withTitle: String(localized: "Continue Anyway"))
        continueButton.keyEquivalent = "\u{1b}"                           // Esc
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }

    // MARK: - appQuit

    func appQuit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func showAlertAndQuit(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .critical
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
        alert.runModal()
        appQuit()
    }
}
