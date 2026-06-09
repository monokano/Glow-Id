import AppKit
import Foundation

// MARK: - IconImportProblem（アイコン取込が失敗した原因）

/// 自分のバンドルにアイコンを書き込めなかった理由。AppDelegate 側で原因別の案内に使う。
enum IconImportProblem {
    /// App Translocation（隔離属性付きで読み取り専用のランダムパスから起動）
    case translocated
    /// バンドル内ファイルが管理者（root）所有になっている
    case rootOwned
    /// その他、設置場所に書き込めない
    case notWritable
}

// MARK: - InDesignAppClass（InDesignアプリ1本分のデータモデル）

class InDesignAppClass {
    var appURL: URL
    var version: String = ""
    /// ソート用数値（major*1e9 + minor*1e6 + patch*1e3 + build）
    var versionDouble: Double = 0
    var isBooted: Bool = false
    var icon: NSImage?
    /// このアプリで開くファイルの URL 配列
    var openFileURLs: [URL] = []

    init(appURL: URL) {
        self.appURL = appURL
    }
}

// MARK: - InDesignApp（InDesignアプリ管理モジュール）

class InDesignApp {

    static let shared = InDesignApp()
    private init() {}

    /// 正規版のみ（Beta・Prerelease 除外）、バージョン昇順
    var appClassALL: [InDesignAppClass] = []
    /// Beta・Prerelease を含む全アプリ、バージョン昇順
    var appClassALLIncludeBeta: [InDesignAppClass] = []

    // MARK: - getAppALL

    func getAppALL() {
        appClassALL = []
        appClassALLIncludeBeta = []

        let fm = FileManager.default
        let appsURL = URL(fileURLWithPath: "/Applications")
        guard let entries = try? fm.contentsOfDirectory(
            at: appsURL, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }

        for entry in entries {
            guard entry.lastPathComponent.contains("Adobe InDesign") else { continue }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: entry.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            let folderName = entry.lastPathComponent
            let isBeta = folderName.contains("Beta") || folderName.contains("Prerelease")

            // InDesign.app を探す（フォルダ名は "Adobe InDesign 2025" など）
            let appBundleURL = findInDesignApp(in: entry)
            guard let appURL = appBundleURL, fm.fileExists(atPath: appURL.path) else { continue }

            let ac = InDesignAppClass(appURL: appURL)
            ac.version = getAppVersion(appBundle: appURL)
            ac.versionDouble = versionToDouble(ac.version)
            ac.isBooted = isAppBooted(appURL: appURL)
            ac.icon = NSWorkspace.shared.icon(forFile: appURL.path)
                        .resized(to: NSSize(width: 18, height: 18))

            appClassALLIncludeBeta.append(ac)
            if !isBeta {
                appClassALL.append(ac)
            }
        }

        appClassALL.sort { $0.versionDouble < $1.versionDouble }
        appClassALLIncludeBeta.sort { $0.versionDouble < $1.versionDouble }
    }

    private func findInDesignApp(in folder: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: []) else { return nil }
        return contents.first { $0.pathExtension == "app" && $0.lastPathComponent.contains("InDesign") }
    }

    // MARK: - getAppALLRefresh

    func getAppALLRefresh() {
        for ac in appClassALLIncludeBeta {
            ac.isBooted = isAppBooted(appURL: ac.appURL)
        }
    }

    // MARK: - openWithSameApp

    /// ファイルに対応するアプリを探し、自動オープン対象なら ac.openFileURLs に追加して true を返す。
    /// 通知ウィンドウが必要な場合は fc.infoWindowMode をセットして false を返す。
    @discardableResult
    func openWithSameApp(fc: FileClass, reView: Bool = false, cmdKeyDown: Bool = false) -> Bool {
        // IDML はバージョン一致判定をせず、常に通知ウィンドウを表示（警告アイコンも出さない）
        if fc.contentKind == "idml" {
            fc.infoWindowMode = 0
            return false
        }

        // アプリ未インストール
        if appClassALL.isEmpty {
            fc.infoWindowMode = appClassALLIncludeBeta.isEmpty ? 2 : 0
            return false
        }

        let myMajor = fc.versionMajor
        let myMinor = fc.versionMinor  // -1 = major のみ照合（indl CS6〜CC2018）

        // 一致するアプリを探す
        for ac in appClassALL {
            let parts = ac.version.components(separatedBy: ".")
            let appMajor = Int(parts.first ?? "") ?? 0
            let appMinor = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0

            // major が一致
            if appMajor == myMajor {
                // major のみ照合（indl CS6〜CC2018）
                if myMinor == -1 {
                    fc.infoWindowMode = 0
                    return openCommonCheck(fc: fc, ac: ac, reView: reView, cmdKeyDown: cmdKeyDown)
                }

                // major.minor で照合
                if appMinor == myMinor {
                    fc.infoWindowMode = 0
                    return openCommonCheck(fc: fc, ac: ac, reView: reView, cmdKeyDown: cmdKeyDown)
                }
            }
        }

        // 一致なし → 詳細判定
        let hasMajorMatch = appClassALL.contains { ac in
            let appMajor = Int(ac.version.components(separatedBy: ".").first ?? "") ?? 0
            return appMajor == myMajor
        }
        if hasMajorMatch {
            // major 一致するが minor 不一致 → mode 1
            fc.infoWindowMode = 1
        } else {
            // major も不一致 → mode 2
            fc.infoWindowMode = 2
        }
        return false
    }

    private func openCommonCheck(fc: FileClass, ac: InDesignAppClass, reView: Bool, cmdKeyDown: Bool) -> Bool {
        let prefs = Preferences.shared
        if fc.contentKind == "idml" { return false }
        if cmdKeyDown || prefs.alwaysShowNotificationWindow {
            return false
        }
        if isAppBooted(appURL: ac.appURL) {
            // 同バージョンが起動中 → 直接オープン
            if !reView, let fileURL = fc.file { ac.openFileURLs.append(fileURL) }
            return true
        } else if isOtherVerAppBooted(excluding: ac.appURL) {
            fc.infoWindowMode = 3
            return false
        } else {
            if !reView, let fileURL = fc.file { ac.openFileURLs.append(fileURL) }
            return true
        }
    }

    // MARK: - openWith

    func openWith(appURL: URL, fileURLs: [URL], completion: @escaping () -> Void) {
        guard !fileURLs.isEmpty else { completion(); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(fileURLs, withApplicationAt: appURL, configuration: config) { _, _ in
            DispatchQueue.main.async { completion() }
        }
    }

    // MARK: - isAppBooted

    func isAppBooted(appURL: URL) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardized == appURL.standardized
        }
    }

    func isOtherVerAppBooted(excluding targetURL: URL) -> Bool {
        for ac in appClassALLIncludeBeta {
            if ac.appURL.standardized != targetURL.standardized && isAppBooted(appURL: ac.appURL) {
                return true
            }
        }
        return false
    }

    // MARK: - getMaximum / Minimum

    func getMaximumVerAppClass() -> InDesignAppClass? {
        appClassALL.max { $0.versionDouble < $1.versionDouble }
    }

    func getMaximumVerAppClassIncludeBeta() -> InDesignAppClass? {
        appClassALLIncludeBeta.max { $0.versionDouble < $1.versionDouble }
    }

    func getMinimumVerAppClass() -> InDesignAppClass? {
        appClassALL.min { $0.versionDouble < $1.versionDouble }
    }

    // MARK: - getIconFiles（5種アイコンをコピー）

    /// onComplete は成功・失敗・中止のいずれの経路でも必ず最後に呼ばれる（後続処理の同期用）。
    /// onProblem は書き込めなかったときに原因種別を返す（管理者パスワードは要求しない）。
    func getIconFiles(onSuccess: ((String) -> Void)? = nil,
                      onProblem: ((IconImportProblem) -> Void)? = nil,
                      onComplete: (() -> Void)? = nil) {
        guard let latest = getMaximumVerAppClass() else { onComplete?(); return }
        let resources = latest.appURL.appendingPathComponent("Contents/Resources")
        let fm = FileManager.default

        let iconMap: [(srcName: String, destName: String)] = [
            ("ID_Document_Icon.icns",     "ID_Document_Icon.icns"),
            ("ID_Stationary_Icon.icns",   "ID_Stationary_Icon.icns"),
            ("ID_Book_Icon.icns",         "ID_Book_Icon.icns"),
            ("ID_Library_CC_Icon.icns",   "ID_Library_CC_Icon.icns"),
            ("ID_IDMLFile_Icon.icns",     "ID_IDMLFile_Icon.icns"),
        ]

        guard let myResources = Bundle.main.resourceURL else { onComplete?(); return }

        var pairs: [(src: URL, dest: URL)] = []
        for map in iconMap {
            let src = resources.appendingPathComponent(map.srcName)
            guard fm.fileExists(atPath: src.path) else { onComplete?(); return }  // 1つでも欠ければ中止
            pairs.append((src, myResources.appendingPathComponent(map.destName)))
        }

        do {
            for pair in pairs {
                try? fm.removeItem(at: pair.dest)
                try fm.copyItem(at: pair.src, to: pair.dest)
            }
            Preferences.shared.appIconVersion = latest.version
            Preferences.shared.save()
            onSuccess?(latest.version)
            onComplete?()
        } catch {
            // 書き込み不可 → 管理者パスワードは要求せず、原因を診断して案内する
            let problem: IconImportProblem
            if isTranslocated(Bundle.main.bundleURL) {
                problem = .translocated
            } else if ownerUID(pairs.first?.dest.path ?? "") == 0 || ownerUID(myResources.path) == 0 {
                problem = .rootOwned
            } else {
                problem = .notWritable
            }
            onProblem?(problem)
            onComplete?()
        }
    }

    // MARK: - 設置状態の診断

    /// App Translocation（隔離属性付きで読み取り専用のランダムパス）から起動しているか。
    /// 正規 API `SecTranslocateIsTranslocatedURL` を dlsym で呼び、取得できなければパスで判定する。
    private func isTranslocated(_ url: URL) -> Bool {
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
        if let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
           let sym = dlsym(handle, "SecTranslocateIsTranslocatedURL") {
            let fn = unsafeBitCast(sym, to: Fn.self)
            var isTrans = false
            var err: Unmanaged<CFError>? = nil
            if fn(url as CFURL, &isTrans, &err).boolValue { return isTrans }
        }
        return url.path.contains("/AppTranslocation/")
    }

    /// 指定パスの所有者 UID（root = 0／取得不可なら nil）
    private func ownerUID(_ path: String) -> uid_t? {
        var st = stat()
        return stat(path, &st) == 0 ? st.st_uid : nil
    }

    // MARK: - Private helpers

    private func getAppVersion(appBundle: URL) -> String {
        guard let bundle = Bundle(url: appBundle),
              let ver = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return "" }
        return ver
    }

    private func versionToDouble(_ ver: String) -> Double {
        let parts = ver.components(separatedBy: ".")
        var result: Double = 0
        let weights: [Double] = [1_000_000_000, 1_000_000, 1_000, 1]
        for (i, p) in parts.prefix(4).enumerated() {
            result += (Double(p) ?? 0) * weights[i]
        }
        return result
    }
}

// MARK: - NSImage resize helper

extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy, fraction: 1)
        img.unlockFocus()
        return img
    }
}
