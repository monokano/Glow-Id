import AppKit
import Foundation

// MARK: - IconImportProblem（アイコン取込が失敗した原因）

/// 自分のバンドルにアイコンを書き込めない理由。環境設定でボタンを押せなくし、理由を表示するのに使う。
enum IconImportProblem {
    /// App Translocation（隔離属性付きで読み取り専用のランダムパスから起動）
    case translocated
    /// バンドル内ファイルが管理者（root）所有になっている
    case rootOwned
    /// その他、設置場所に書き込めない
    case notWritable
}

// MARK: - AppTranslocation（隔離起動の判定）

/// App Translocation（隔離属性付きのアプリを Finder で移動せずに起動したとき、
/// 読み取り専用の一時的な場所から実行される macOS の仕組み）の判定。
/// 共通資料 App-共有資料/AppTranslocation対策.md を参照。
enum AppTranslocation {
    private static let securityHandle =
        dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY)

    /// 隔離起動しているか。
    /// `SecTranslocateIsTranslocatedURL` を dlsym で呼び、取得できなければパスで判定する。
    static func isTranslocated(_ url: URL) -> Bool {
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
        if let handle = securityHandle,
           let sym = dlsym(handle, "SecTranslocateIsTranslocatedURL") {
            let fn = unsafeBitCast(sym, to: Fn.self)
            var isTrans = false
            var err: Unmanaged<CFError>? = nil
            if fn(url as CFURL, &isTrans, &err).boolValue { return isTrans }
            err?.release()   // 失敗時に返る CFError を解放（リーク防止）
        }
        return url.path.contains("/AppTranslocation/")
    }

    /// 隔離起動中のアプリの元の場所。
    /// `SecTranslocateCreateOriginalPathForURL`（公開ヘッダに無い）を dlsym で呼ぶ。取得できなければ nil。
    static func originalURL(of url: URL) -> URL? {
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = securityHandle,
              let sym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        var err: Unmanaged<CFError>? = nil
        guard let original = fn(url as CFURL, &err)?.takeRetainedValue() else {
            err?.release()
            return nil
        }
        return original as URL
    }

    /// 元の場所がアプリケーションフォルダ（/Applications または ~/Applications）の中か。
    /// アプリケーションフォルダの中で ZIP を展開した場合などに当たる。
    static func isInApplicationsFolder(_ url: URL) -> Bool {
        let appDirs = FileManager.default.urls(for: .applicationDirectory,
                                               in: [.localDomainMask, .userDomainMask])
        let path = url.standardizedFileURL.path
        return appDirs.contains { path.hasPrefix($0.standardizedFileURL.path + "/") }
    }
}

// MARK: - InDesignAppClass（InDesignアプリ1本分のデータモデル）

class InDesignAppClass {
    var appURL: URL
    var version: String = ""
    /// ソート用数値（major*1e9 + minor*1e6 + patch*1e3 + build）
    var versionDouble: Double = 0
    /// 正規版以外（Beta・Prerelease・Debug など）。getAppALL で isBetaFolder により決まる
    var isBeta: Bool = false
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

    /// 正規版のみ（isBeta の版を除外）、バージョン昇順
    var appClassALL: [InDesignAppClass] = []
    /// 正規版以外（Beta・Prerelease・Debug など）も含む全アプリ、バージョン昇順（同じバージョンなら正規版が先）
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

            // InDesign.app を探す（フォルダ名は "Adobe InDesign 2025" など）
            let appBundleURL = findInDesignApp(in: entry)
            guard let appURL = appBundleURL, fm.fileExists(atPath: appURL.path) else { continue }

            let ac = InDesignAppClass(appURL: appURL)
            ac.version = getAppVersion(appBundle: appURL)
            ac.versionDouble = versionToDouble(ac.version)
            ac.isBeta = InDesignApp.isBetaFolder(folderName)
            ac.isBooted = isAppBooted(appURL: appURL)
            ac.icon = NSImage.appIcon(at: appURL)
                        .resized(to: NSSize(width: 18, height: 18))

            appClassALLIncludeBeta.append(ac)
            if !ac.isBeta {
                appClassALL.append(ac)
            }
        }

        appClassALL.sort { InDesignApp.isAscending($0, $1) }
        appClassALLIncludeBeta.sort { InDesignApp.isAscending($0, $1) }
    }

    /// 正規版のフォルダ名は「Adobe InDesign」＋次のどれかだけのもの。
    ///   数字（"2026"）／ CC ＋年号（"CC 2019"）／ CC 単体 ／ CS 系（"CS6" "CS5.5" "CS"）
    /// それ以外（Beta・Prerelease・Debug・InDesign Server・Finder での複製など）はすべて Beta 扱いにする。
    /// Debug 版は Info.plist が正規版と同一のため、フォルダ名以外に手がかりがない。
    /// 年号の無い CC・CS 系は 32bit で現行 macOS では起動できないが、念のため正規版として扱う。
    private static func isBetaFolder(_ folderName: String) -> Bool {
        folderName.range(of: "^Adobe InDesign (CC( [0-9.]+)?|CS[0-9.]*|[0-9.]+)$",
                         options: .regularExpression) == nil
    }

    /// バージョン昇順。同じバージョンなら正規版を先に並べる
    /// （Debug 版や複製は正規版と同じバージョンになるため、並び順をフォルダの列挙順任せにしない）
    private static func isAscending(_ a: InDesignAppClass, _ b: InDesignAppClass) -> Bool {
        if a.versionDouble != b.versionDouble { return a.versionDouble < b.versionDouble }
        return !a.isBeta && b.isBeta
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

    /// Beta を含む中で最上位バージョン。同じバージョンなら正規版を優先する
    /// （macOS 26.4 以降の環境設定の関連付け先〔FileAssociation.Target.indesign〕が Debug 版や複製にならないように）
    func getMaximumVerAppClassIncludeBeta() -> InDesignAppClass? {
        appClassALLIncludeBeta.max { a, b in
            if a.versionDouble != b.versionDouble { return a.versionDouble < b.versionDouble }
            return a.isBeta && !b.isBeta
        }
    }

    func getMinimumVerAppClass() -> InDesignAppClass? {
        appClassALL.min { $0.versionDouble < $1.versionDouble }
    }

    // MARK: - アイコン取込（環境設定のボタンから。起動時には行わない）

    /// アイコンのファイル名（.indd／.indt／.indb／.indl／.idml の順）。
    /// InDesign 内の名前と、自分のバンドル内のコピー先（Info.plist の CFBundleTypeIconFile）は同じ
    private static let iconFileNames = [
        "ID_Document_Icon.icns",
        "ID_Stationary_Icon.icns",
        "ID_Book_Icon.icns",
        "ID_Library_CC_Icon.icns",
        "ID_IDMLFile_Icon.icns",
    ]

    /// 最上位の正規版 InDesign 内のアイコン（iconFileNames の順）。1つでも見つからなければ nil
    func latestIconSources() -> [URL]? {
        guard let latest = getMaximumVerAppClass() else { return nil }
        let resources = latest.appURL.appendingPathComponent("Contents/Resources")
        var urls: [URL] = []
        for name in Self.iconFileNames {
            let url = resources.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            urls.append(url)
        }
        return urls
    }

    /// 自分のバンドルにアイコンを書き込めない理由。書き込めるなら nil。
    /// ボタンを押す前に調べて、押せない状態にするために使う
    func iconImportProblem() -> IconImportProblem? {
        guard let myResources = Bundle.main.resourceURL else { return .notWritable }
        if isTranslocated(Bundle.main.bundleURL) { return .translocated }
        // 置き換えには Resources フォルダへの書き込み権限が要る
        if FileManager.default.isWritableFile(atPath: myResources.path) { return nil }
        let destDoc = myResources.appendingPathComponent(Self.iconFileNames[0])
        if ownerUID(destDoc.path) == 0 || ownerUID(myResources.path) == 0 { return .rootOwned }
        return .notWritable
    }

    /// 自分のバンドルのアイコンが、最上位の正規版 InDesign のものと同じか
    func iconsAreUpToDate() -> Bool {
        guard let sources = latestIconSources(),
              let myResources = Bundle.main.resourceURL else { return false }
        for (src, name) in zip(sources, Self.iconFileNames) {
            let dest = myResources.appendingPathComponent(name)
            guard let a = try? Data(contentsOf: src),
                  let b = try? Data(contentsOf: dest),
                  a == b else { return false }
        }
        return true
    }

    /// 最上位の正規版 InDesign のアイコンを自分のバンドルにコピーする（in-process の FileManager のみ。
    /// 管理者パスワードは要求しない）。成功なら true
    func importIcons() -> Bool {
        guard let sources = latestIconSources(),
              let myResources = Bundle.main.resourceURL else { return false }
        let fm = FileManager.default
        var changed = false
        do {
            for (src, name) in zip(sources, Self.iconFileNames) {
                let dest = myResources.appendingPathComponent(name)
                // 中身が同じなら触らない（無駄な書き換えで Finder のアイコン表示を乱さない）
                if let a = try? Data(contentsOf: src), let b = try? Data(contentsOf: dest), a == b { continue }
                // 削除→コピーだと一瞬ファイルが無くなり、Finder がその間に白紙のアイコンを覚えることがある。
                // 同じフォルダに一時コピーを作り、入れ替える（Glow Ai ステップ8と同じ方式）
                let temp = myResources.appendingPathComponent(".\(name).importing")
                try? fm.removeItem(at: temp)
                try fm.copyItem(at: src, to: temp)
                if fm.fileExists(atPath: dest.path) {
                    _ = try fm.replaceItemAt(dest, withItemAt: temp)
                } else {
                    try fm.moveItem(at: temp, to: dest)
                }
                changed = true
            }
        } catch {
            return false
        }
        if changed { Self.refreshIconCache() }
        return true
    }

    /// 書類アイコンを変えたことを LaunchServices と Finder に知らせる。
    /// バンドルの更新日時を変えて再登録すると、書類アイコンが読み直される
    static func refreshIconCache() {
        let bundleURL = Bundle.main.bundleURL
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: bundleURL.path)
        LSRegisterURL(bundleURL as CFURL, true)
        NSWorkspace.shared.noteFileSystemChanged(bundleURL.path)
    }

    // MARK: - 設置状態の診断

    /// App Translocation（隔離属性付きで読み取り専用のランダムパス）から起動しているか。
    private func isTranslocated(_ url: URL) -> Bool {
        AppTranslocation.isTranslocated(url)
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
    /// アプリのアイコン。Info.plist の CFBundleIconFile の .icns を直接読む。
    /// macOS 26 以降の NSWorkspace.icon(forFile:) は、Icon Composer 形式のアイコンを持たないアプリ
    ///（InDesign など）のアイコンを縮めてグレーの角丸の枠に入れて返すため、18pt のリストでは
    /// グレーの囲みが目立つ（Glow Ai ステップ12と同じ対処）。読めなければ従来どおり NSWorkspace を使う
    static func appIcon(at appURL: URL) -> NSImage {
        if let name = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           !name.isEmpty {
            let file = name.hasSuffix(".icns") ? name : name + ".icns"
            let url = appURL.appendingPathComponent("Contents/Resources").appendingPathComponent(file)
            if let image = NSImage(contentsOf: url) { return image }
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

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
