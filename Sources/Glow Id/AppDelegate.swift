import AppKit
import SwiftUI
import UniformTypeIdentifiers


class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    // MARK: - State

    private var dropItems: [URL] = []
    private var countDrop: Int = 0
    private var cmdKeyDownAtDrop: Bool = false
    /// アイコン取込（および完了ダイアログ）が終わったか
    private var iconImportDone: Bool = false
    /// アイコン取込完了を待って runStart() を実行するための保留フラグ
    private var pendingRunStart: Bool = false
    var infoWindowController: InfoWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var changeLogWindowController: ChangeLogWindowController?
    private var helpWindowController: HelpWindowController?

    // MARK: - applicationWillFinishLaunching

    func applicationWillFinishLaunching(_ notification: Notification) {
        if #unavailable(macOS 13.0) { return }
        InDesignApp.shared.getAppALL()
    }

    // MARK: - applicationDidFinishLaunching

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let prefs = Preferences.shared

        if #unavailable(macOS 13.0) {
            showAlertAndQuit(
                message: NSLocalizedString("System Requirement", comment: ""),
                info: "macOS 13.0 or later is required."
            )
            return
        }

        NSApp.delegate = self

        // ファイル関連付けを明示的に再登録
        if prefs.autoClaimFileAssociations {
            claimFileAssociations()
        } else {
            claimFileAssociationsToTopInDesign()
        }

        // 不要なメニューを削除
        DispatchQueue.main.async {
            let removes = ["表示", "View", "ウインドウ", "Window"]
            NSApp.mainMenu?.items
                .filter { removes.contains($0.title) }
                .forEach { NSApp.mainMenu?.removeItem($0) }
        }

        // アイコンファイルのコピー（最新 InDesign.app から）。
        // 完了ダイアログを真っ先に表示するため、取込完了まで runStart() を保留する。
        importIconsIfNeeded { [weak self] in
            guard let self else { return }
            self.iconImportDone = true
            if self.pendingRunStart {
                self.pendingRunStart = false
                self.runStart()
            }
        }
    }

    // MARK: - アイコン取込

    /// アイコン取込が必要なら実行し、完了ダイアログ（抑制設定でない場合）を表示してから
    /// completion を呼ぶ。取込不要・中止の場合も必ず completion を呼ぶ。
    private func importIconsIfNeeded(completion: @escaping () -> Void) {
        let prefs = Preferences.shared
        guard !InDesignApp.shared.appClassALL.isEmpty else { completion(); return }

        let bundleBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0

        let needImport: Bool
        if prefs.nonReleaseVersion != bundleBuild {
            prefs.nonReleaseVersion = bundleBuild
            prefs.save()
            needImport = true
        } else if let latest = InDesignApp.shared.getMaximumVerAppClass(),
                  latest.version != prefs.appIconVersion {
            needImport = true
        } else {
            needImport = false
        }

        guard needImport else { completion(); return }

        InDesignApp.shared.getIconFiles(onSuccess: { [weak self] version in
            self?.showIconImportedAlert(version: version)
        }, onProblem: { [weak self] problem in
            self?.showIconImportProblemAlert(problem)
        }, onComplete: {
            completion()
        })
    }

    // MARK: - ファイル関連付け再登録

    func claimFileAssociations() {
        let appURL = Bundle.main.bundleURL
        for utiString in indesignUTIs {
            guard let utType = UTType(utiString) else { continue }
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: utType) { _ in }
        }
    }

    func claimFileAssociationsToTopInDesign() {
        guard let top = InDesignApp.shared.getMaximumVerAppClassIncludeBeta() else { return }
        for utiString in indesignUTIs {
            guard let utType = UTType(utiString) else { continue }
            NSWorkspace.shared.setDefaultApplication(at: top.appURL, toOpen: utType) { _ in }
        }
    }

    private var indesignUTIs: [String] {
        [
            "com.adobe.indesign-document",
            "com.adobe.indesign-template",
            "com.adobe.indesign-book",
            "com.adobe.indesign-library",
            "com.adobe.indesign.idml",
        ]
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

        let changeLogItem = NSMenuItem(
            title: String(localized: "Change Log"),
            action: #selector(openChangeLog),
            keyEquivalent: ""
        )
        changeLogItem.target = self
        menu.addItem(changeLogItem)

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

    @objc func openChangeLog() {
        if changeLogWindowController == nil {
            changeLogWindowController = ChangeLogWindowController()
        }
        changeLogWindowController?.show()
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
            // アイコン取込の完了ダイアログを先に出すため、未完了なら保留する。
            if iconImportDone {
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

    // MARK: - appQuit

    func appQuit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func showIconImportedAlert(version: String) {
        guard !Preferences.shared.doNotNotifyIconImport else { return }
        let name = FileInfo.appName(Int(version.components(separatedBy: ".").first ?? "") ?? 0, 0)
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "Icon files imported from InDesign %@"), name)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// アイコンを自分のバンドルに書き込めなかったとき、原因に応じた是正案内を表示する。
    /// 管理者パスワードは要求しない（旧来の管理者コピーを廃止した代替）。
    private func showIconImportProblemAlert(_ problem: IconImportProblem) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch problem {
        case .translocated:
            alert.messageText = String(localized: "Please move Glow Id to the Applications folder")
            alert.informativeText = String(localized: "Glow Id is running from a temporary, read-only location, so it cannot update its file icons. Quit Glow Id, move it to the Applications folder using the Finder, and open it again.")
        case .rootOwned:
            alert.messageText = String(localized: "Please reinstall Glow Id")
            alert.informativeText = String(localized: "Part of Glow Id is owned by the administrator, so it cannot update its file icons. Move Glow Id to the Trash, download the latest version, and install it again.")
        case .notWritable:
            alert.messageText = String(localized: "Glow Id could not update its file icons")
            alert.informativeText = String(localized: "Glow Id cannot write to its current location. Move it to the Applications folder (or the Applications folder in your home folder) and open it again.")
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

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
