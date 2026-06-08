import Foundation

/// アプリ全体の設定。UserDefaults に保存。
class Preferences {

    static let shared = Preferences()
    private init() { load() }

    private let defaults = UserDefaults.standard

    // MARK: - 設定項目

    /// 常に通知ウインドウを表示する
    var alwaysShowNotificationWindow: Bool = false

    /// 起動時にファイル関連付けを自動登録する（5種）
    var autoClaimFileAssociations: Bool = true

    /// ファイルアイコン取込完了を通知しない（完了・失敗ダイアログを抑制）
    var doNotNotifyIconImport: Bool = false

    /// indd/indt のバージョン検出モード
    /// false = メジャー.マイナー（デフォルト）
    /// true  = フルバージョン（x.x.x.x）
    var useFullVersion: Bool = false

    /// フルバージョン表示時にビルド番号（4桁目）を表示しない（x.x.x.x → x.x.x）
    /// useFullVersion が true のときのみ意味を持つ
    var hideBuildNumber: Bool = true

    /// 上位バージョンで開くのを許可する
    var allowOpeningInHigherVersion: Bool = false

    /// アイコン更新判定用（非リリースバージョン番号）
    var nonReleaseVersion: Int = 0

    /// 最後にコピーしたアイコンの InDesignバージョン
    var appIconVersion: String = ""

    // MARK: - Keys

    private enum Key: String {
        case alwaysShowNotificationWindow
        case autoClaimFileAssociations
        case doNotNotifyIconImport
        case useFullVersion
        case hideBuildNumber
        case allowOpeningInHigherVersion
        case nonReleaseVersion
        case appIconVersion
    }

    // MARK: - Load / Save

    func load() {
        let d = defaults
        alwaysShowNotificationWindow = d.object(forKey: Key.alwaysShowNotificationWindow.rawValue) as? Bool ?? false
        autoClaimFileAssociations    = d.object(forKey: Key.autoClaimFileAssociations.rawValue)    as? Bool ?? true
        doNotNotifyIconImport        = d.object(forKey: Key.doNotNotifyIconImport.rawValue)        as? Bool ?? false
        useFullVersion               = d.object(forKey: Key.useFullVersion.rawValue)               as? Bool ?? false
        hideBuildNumber              = d.object(forKey: Key.hideBuildNumber.rawValue)              as? Bool ?? true
        allowOpeningInHigherVersion  = d.object(forKey: Key.allowOpeningInHigherVersion.rawValue)  as? Bool ?? false
        nonReleaseVersion            = d.object(forKey: Key.nonReleaseVersion.rawValue)            as? Int  ?? 0
        appIconVersion               = d.string(forKey:  Key.appIconVersion.rawValue)              ?? ""
    }

    func save() {
        let d = defaults
        d.set(alwaysShowNotificationWindow, forKey: Key.alwaysShowNotificationWindow.rawValue)
        d.set(autoClaimFileAssociations,    forKey: Key.autoClaimFileAssociations.rawValue)
        d.set(doNotNotifyIconImport,        forKey: Key.doNotNotifyIconImport.rawValue)
        d.set(useFullVersion,               forKey: Key.useFullVersion.rawValue)
        d.set(hideBuildNumber,              forKey: Key.hideBuildNumber.rawValue)
        d.set(allowOpeningInHigherVersion,  forKey: Key.allowOpeningInHigherVersion.rawValue)
        d.set(nonReleaseVersion,            forKey: Key.nonReleaseVersion.rawValue)
        d.set(appIconVersion,               forKey: Key.appIconVersion.rawValue)
    }
}
