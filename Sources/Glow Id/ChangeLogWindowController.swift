
import AppKit
import SwiftUI
import WebKit

// MARK: - ChangeLogWindowController

class ChangeLogWindowController: NSObject {

    private var window: NSWindow?

    func show() {
        // すでに表示中なら前面に出すだけ
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Change Log")
        win.contentView = NSHostingView(rootView: ChangeLogRootView())
        win.minSize = NSSize(width: 300, height: 200)
        win.isReleasedWhenClosed = false

        positionTopLeft(win)

        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func positionTopLeft(_ win: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let gap: CGFloat = 18
        let visible = screen.visibleFrame
        let x = visible.minX + gap
        let y = visible.maxY - win.frame.height - gap
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - ChangeLogRootView

/// 上部に外部リンク（GitHub Releases）、その下に更新履歴の WebView を配置する。
/// 外部リンクをリモートHTML側ではなくアプリのネイティブUIに置くことで、
/// 旧バージョンでの不適切な挙動（ウィンドウ内遷移など）を避ける。
private struct ChangeLogRootView: View {

    private let releasesURL = URL(string: "https://github.com/monokano/Glow-Id/releases")!

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Link("GitHub Releases", destination: releasesURL)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ChangeLogView()
        }
    }
}

// MARK: - ChangeLogView

private struct ChangeLogView: NSViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // 右クリックコンテキストメニューを無効化
        let script = WKUserScript(
            source: "document.addEventListener('contextmenu', function(e){ e.preventDefault(); }, false);",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // 日本語ローカライズ時は ja、それ以外は en
        let lang = Locale.current.language.languageCode?.identifier == "ja" ? "ja" : "en"
        // キャッシュを避けるためクエリにUUIDを付与
        let urlStr = "https://tama-san.com/glee-glow-id/change-log-\(lang).html?\(UUID().uuidString)"
        if let url = URL(string: urlStr) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    /// HTML内のリンクをクリックしたら WebView 内で遷移させず、デフォルトブラウザで開く。
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
