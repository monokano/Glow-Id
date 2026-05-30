import Foundation

class FileClass {

    // MARK: - ファイル本体
    var file: URL?

    // MARK: - ファイル種別（コンテンツベース判定）
    /// "indd" / "indt" / "indb" / "indl" / "idml"
    var contentKind: String = ""
    /// コンテンツベースで判定した拡張子と実際の拡張子が一致しない
    var isExtMismatch: Bool = false
    /// マジックバイト・種別文字列でも InDesign ファイルと認識できない
    var isNotInDesign: Bool = false

    // MARK: - バージョン判定結果
    /// 照合用 major（常に確定値）
    var versionMajor: Int = 0
    /// 照合用 minor（-1 = major のみで照合。indl の CS6〜CC2018 が該当）
    var versionMinor: Int = -1
    /// 表示用バージョン文字列（設定に応じて "x.x" / "x.x.x.x" / "x"）
    var versionDisplay: String = ""
    /// バージョン表示行全体（例: "InDesign 2025 (20.5)"）
    var versionLabel: String = ""
    /// バージョン情報を検出できなかった
    var isVersionUndetected: Bool = false

    // MARK: - InfoWindow 表示モード（警告バルーン用）
    /// 0: 正常（手動表示）
    /// 1: 一致する major.minor の InDesign がインストールされていない
    /// 2: 一致する major の InDesign がインストールされていない
    /// 3: 別バージョンの InDesign が起動中
    /// 4: バージョン情報を検出できない
    var infoWindowMode: Int = 0
}
