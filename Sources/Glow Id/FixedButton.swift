import AppKit
import SwiftUI

/// 幅を固定値で指定できるボタン（NSButton ラッパー）。
///
/// SwiftUI の Button は内容に合わせて横幅が決まるが、
/// このコンポーネントは任意の固定幅を指定できる。
///
/// 使用例:
///   FixedButton("実行", width: 80) { vm.run() }
///   FixedButton("OK", width: 80, isDefault: true) { dismiss() }
///   FixedButton("キャンセル", width: 90, isCancel: true) { dismiss() }
///   FixedButton("絞込み", width: 80, style: .recessed) { filter() }
struct FixedButton: View {

    // MARK: - ボタンの形状

    /// NSButton.BezelStyle に対応するスタイル列挙型。
    /// AppKit をインポートしていない SwiftUI ファイルからも使用できる。
    enum Style {
        /// 標準の角丸ボタン。ダイアログの OK / キャンセルなど（デフォルト）
        case rounded
        /// へこんだフラットボタン。ツールバーのフィルター切替など
        case recessed
        /// 四角いボタン。画像付きボタンなど
        case regularSquare
        /// 小さな四角いボタン
        case smallSquare
        /// 丸いボタン。アイコンボタンなど
        case circular
        /// インライン小型ボタン。リスト内のアクションなど
        case inline
        /// テクスチャ付き四角いボタン。ツールバーボタンなど
        case texturedSquare

        var nsBezelStyle: NSButton.BezelStyle {
            switch self {
            case .rounded:        return .rounded
            case .recessed:       return .recessed
            case .regularSquare:  return .regularSquare
            case .smallSquare:    return .smallSquare
            case .circular:       return .circular
            case .inline:         return .inline
            case .texturedSquare: return .texturedSquare
            }
        }
    }

    // MARK: - プロパティ

    var label: String
    var width: CGFloat
    var style: Style = .rounded
    /// true にすると Return キーでもボタンが実行される
    var isDefault: Bool = false
    /// true にすると Escape キーでもボタンが実行される
    var isCancel: Bool = false
    var isEnabled: Bool = true
    /// true にすると NSFont.smallSystemFontSize を使用する
    var isSmall: Bool = false
    var action: () -> Void

    init(
        _ label: String,
        width: CGFloat,
        style: Style = .rounded,
        isDefault: Bool = false,
        isCancel: Bool = false,
        isEnabled: Bool = true,
        isSmall: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.width = width
        self.style = style
        self.isDefault = isDefault
        self.isCancel = isCancel
        self.isEnabled = isEnabled
        self.isSmall = isSmall
        self.action = action
    }

    // MARK: - Body

    var body: some View {
        _FixedButtonNSView(
            label: label, width: width, style: style,
            isDefault: isDefault, isCancel: isCancel,
            isSmall: isSmall, action: action
        )
        .disabled(!isEnabled)
    }
}

// MARK: - NSViewRepresentable（内部実装）

private struct _FixedButtonNSView: NSViewRepresentable {

    var label: String
    var width: CGFloat
    var style: FixedButton.Style = .rounded
    var isDefault: Bool = false
    var isCancel: Bool = false
    var isSmall: Bool = false
    var action: () -> Void

    // .disabled() によって設定される SwiftUI 環境値を参照する
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = label
        button.bezelStyle = style.nsBezelStyle
        button.controlSize = isSmall ? .small : .regular
        button.target = context.coordinator
        button.action = #selector(Coordinator.buttonTapped)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = label
        button.bezelStyle = style.nsBezelStyle
        button.isEnabled = isEnabled
        button.keyEquivalent = isDefault ? "\r" : (isCancel ? "\u{1B}" : "")
        button.controlSize = isSmall ? .small : .regular
        context.coordinator.action = action
    }

    /// SwiftUI レイアウトに対して固定幅を返す（macOS 13+）
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        nsView.controlSize = isSmall ? .small : .regular
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func buttonTapped() { action() }
    }
}
