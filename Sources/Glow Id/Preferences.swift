import Foundation

/// アプリ全体の設定。UserDefaults に保存。
class Preferences {

    static let shared = Preferences()
    private init() { load() }

    private let defaults = UserDefaults.standard

    // MARK: - 設定項目
    // 起動時の関連付け（autoClaimFileAssociations）・アイコン取込の通知（doNotNotifyIconImport）・
    // 起動時のアイコン取込判定（nonReleaseVersion・appIconVersion）は 2026-11-08 に廃止。
    // 既存ユーザーの UserDefaults に残る値は読まれないだけで無害

    /// 常に通知ウインドウを表示する
    var alwaysShowNotificationWindow: Bool = false

    /// indd/indt のバージョン検出モード
    /// false = メジャー.マイナー（デフォルト）
    /// true  = フルバージョン（x.x.x.x）
    var useFullVersion: Bool = false

    /// フルバージョン表示時にビルド番号（4桁目）を表示しない（x.x.x.x → x.x.x）
    /// useFullVersion が true のときのみ意味を持つ
    var hideBuildNumber: Bool = true

    /// 上位バージョンで開くのを許可する
    var allowOpeningInHigherVersion: Bool = false

    // MARK: - Keys

    private enum Key: String {
        case alwaysShowNotificationWindow
        case useFullVersion
        case hideBuildNumber
        case allowOpeningInHigherVersion
    }

    // MARK: - Load / Save

    func load() {
        let d = defaults
        alwaysShowNotificationWindow = d.object(forKey: Key.alwaysShowNotificationWindow.rawValue) as? Bool ?? false
        useFullVersion               = d.object(forKey: Key.useFullVersion.rawValue)               as? Bool ?? false
        hideBuildNumber              = d.object(forKey: Key.hideBuildNumber.rawValue)              as? Bool ?? true
        allowOpeningInHigherVersion  = d.object(forKey: Key.allowOpeningInHigherVersion.rawValue)  as? Bool ?? false
    }

    func save() {
        let d = defaults
        d.set(alwaysShowNotificationWindow, forKey: Key.alwaysShowNotificationWindow.rawValue)
        d.set(useFullVersion,               forKey: Key.useFullVersion.rawValue)
        d.set(hideBuildNumber,              forKey: Key.hideBuildNumber.rawValue)
        d.set(allowOpeningInHigherVersion,  forKey: Key.allowOpeningInHigherVersion.rawValue)
    }
}
