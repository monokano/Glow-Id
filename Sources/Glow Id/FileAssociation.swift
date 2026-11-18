import AppKit
import UniformTypeIdentifiers

/// .indd / .indt / .indb / .indl / .idml のファイル関連付け（環境設定の「関連付ける」ボタンからだけ使う）。
/// Glow Ai の FileAssociation（同 HANDOFF ステップ6・10）を InDesign 用に移植したもの。
///
/// 起動時に自動で関連付けることはしない（仕様を知らないユーザーが混乱するため。Glow Ai ステップ3と同じ方針）。
///
/// macOS 26.4 以降、NSWorkspace.setDefaultApplication(at:toOpen:) は確認の仕組みに回される
/// （2026-11-08、macOS 27.2 で実測。App-共有資料/ファイル関連付け_macOS26.4以降.md）：
/// - 現在の関連付け先と同じ Bundle ID への変更は「変更なし」とみなされ、何も起きない（ダイアログも出ない）
/// - Bundle ID が違うアプリへの変更は、種類ごとに確認ダイアログが出る。許可しても保存されるのは
///   Bundle ID だけで、バージョンは選べない（同じ Bundle ID の最新版になる）
/// - 「変更しない」を押すと userCanceledErr が返る。それ以外はエラーなしでも反映されたとは限らないので読み直す
/// secure.plist を直接書き換える方法は lsd がクラッシュを繰り返すことがあるので使わない。
///
/// InDesign は Beta も正式版と同じ Bundle ID（com.adobe.InDesign）。26.4 以降の API は同じ Bundle ID の最新版を選ぶので、
/// Beta の方が新しいと Beta に関連付く（2026-11-08 実機で確認：確認メッセージは「“InDesign (Beta)”に変更」）。
/// そのため 26.4 以降の InDesign 側の選択肢は、Beta などの正規版以外も含めた最上位の版（実際に関連付けられる版）にする。
/// 26.3 までは URL で指定した版にそのまま関連付く（macOS 15 で実測）ので、正式版の最上位にする（HANDOFF ステップ12）。
/// 判定は Bundle ID ではなくアプリの場所で行う（別の版に関連付いているときに「（現在）」としない）。
enum FileAssociation {

    static let types: [UTType] = [
        "com.adobe.indesign-document",
        "com.adobe.indesign-template",
        "com.adobe.indesign-book",
        "com.adobe.indesign-library",
        "com.adobe.indesign.idml",
    ].compactMap { UTType($0) }

    /// 関連付け先の選択肢
    enum Target {
        /// Glow Id 自身
        case glowId
        /// インストール済みの InDesign の最上位。
        /// macOS 26.4 以降は Beta などの正規版以外も含む（同じバージョンなら正規版）。26.3 までは正式版のみ
        case indesign

        /// 関連付けに使うアプリの URL。InDesign が1つも無ければ nil
        var appURL: URL? {
            switch self {
            case .glowId:   return Bundle.main.bundleURL
            case .indesign: return FileAssociation.inDesignTarget()?.appURL
            }
        }

        /// 画面に出す名前（例：「Adobe InDesign 2027 (Beta)」）
        var displayName: String? {
            switch self {
            case .glowId:   return "Glow Id"
            case .indesign: return appURL.map(FileAssociation.inDesignName(for:))
            }
        }

        /// 現在の関連付け先 current が、このターゲットに当たるか。
        /// Glow Id は Bundle ID で比べる（Debug ビルドなど別の場所の Glow Id も同じとみなす）。
        /// InDesign は Beta も同じ Bundle ID なので、アプリの場所で比べる
        func matches(_ current: URL) -> Bool {
            guard let appURL else { return false }
            switch self {
            case .glowId:
                guard let targetID = Bundle(url: appURL)?.bundleIdentifier,
                      let currentID = Bundle(url: current)?.bundleIdentifier else { return false }
                return currentID.caseInsensitiveCompare(targetID) == .orderedSame
            case .indesign:
                return current.resolvingSymlinksInPath().standardizedFileURL.path
                    == appURL.resolvingSymlinksInPath().standardizedFileURL.path
            }
        }
    }

    /// 関連付け先にする InDesign。
    /// 26.4 以降は API が同じ Bundle ID の最新版にしか関連付けないので、Beta も含めた最上位（実際に関連付く版）。
    /// 26.3 までは指定した版に関連付くので、正式版の最上位。正式版が無ければ Beta も含めた最上位
    private static func inDesignTarget() -> InDesignAppClass? {
        let app = InDesignApp.shared
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)) {
            return app.getMaximumVerAppClassIncludeBeta()
        }
        return app.getMaximumVerAppClass() ?? app.getMaximumVerAppClassIncludeBeta()
    }

    /// InDesign の画面上の名前。親フォルダ名（「Adobe InDesign 2026」）を使う。想定外の置き方ならアプリ名
    nonisolated static func inDesignName(for appURL: URL) -> String {
        let folder = appURL.deletingLastPathComponent().lastPathComponent
        return folder.hasPrefix("Adobe InDesign")
            ? folder
            : appURL.deletingPathExtension().lastPathComponent
    }

    /// 5種類とも target のアプリに関連付けられているか
    static func isAssociated(with target: Target) -> Bool {
        guard target.appURL != nil else { return false }
        return typesNeedingChange(to: target).isEmpty
    }

    /// 現在の関連付け先が target ではない種類
    static func typesNeedingChange(to target: Target) -> [UTType] {
        types.filter { type in
            guard let current = NSWorkspace.shared.urlForApplication(toOpen: type) else { return true }
            return !target.matches(current)
        }
    }

    /// apply の結果
    enum Outcome {
        /// すべて反映された
        case applied
        /// 確認ダイアログで「“〜”のままにする」が押された。changedSome は、それより前の種類で変わったものがあるか
        case kept(changedSome: Bool)
        /// エラーなしでも反映されなかった（Finder の手順を案内する）
        case notApplied
    }

    /// 種類を target のアプリに関連付け、結果を返す（反映は関連付け先を読み直して確かめる）。
    /// 確認ダイアログが出た場合は、ユーザーが答えるまで完了しない
    static func apply(_ targets: [UTType], to target: Target, completion: @escaping (Outcome) -> Void) {
        guard let appURL = target.appURL else { completion(.notApplied); return }
        Task {
            var canceled = false
            for type in targets {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
                } catch {
                    // 確認ダイアログで「“〜”のままにする」を押すと userCanceledErr（-128）が返る（macOS 27.2 で実測）。
                    // ユーザーの選択なので失敗扱いにしない。残りの種類でダイアログを出し続けないよう、そこで止める
                    if isUserCanceled(error) { canceled = true; break }
                }
            }
            // 反映の遅れで誤判定しないよう、変わっていなければ少し待って読み直す
            var remaining = typesNeedingChange(to: target).filter { targets.contains($0) }
            if !remaining.isEmpty {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining = typesNeedingChange(to: target).filter { targets.contains($0) }
            }
            if remaining.isEmpty {
                completion(.applied)
            } else if canceled {
                completion(.kept(changedSome: remaining.count < targets.count))
            } else {
                completion(.notApplied)
            }
        }
    }

    /// NSCocoaErrorDomain 256 の中に userCanceledErr（-128）が入っている形で返る
    private static func isUserCanceled(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain, nsError.code == userCanceledErr { return true }
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isUserCanceled(underlying)
        }
        return false
    }

    /// 関連付けが反映されなかったときの案内
    static func showNotAppliedAlert(for window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "The file association was not changed.")
        alert.informativeText = String(localized: "macOS security may prevent this change. In the Finder, select a .indd, .indt, .indb, .indl, or .idml file, choose Get Info, choose the app in \"Open with\", and click \"Change All…\".")
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
