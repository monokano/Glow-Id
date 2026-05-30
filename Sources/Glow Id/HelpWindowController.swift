
import AppKit
import WebKit

// MARK: - HelpWindowController

class HelpWindowController: NSObject, WKNavigationDelegate {

    private var window: NSWindow?

    func show() {
        // すでに表示中なら前面に出すだけ
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Glow Id Help")
        win.minSize = NSSize(width: 400, height: 300)
        win.isReleasedWhenClosed = false

        let webView = makeWebView()
        win.contentView = webView
        loadIndexPage(into: webView)

        positionTopLeft(win)

        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - Private

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()

        // 右クリックコンテキストメニューを無効化
        let script = WKUserScript(
            source: "document.addEventListener('contextmenu', function(e){ e.preventDefault(); }, false);",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        return webView
    }

    private func loadIndexPage(into webView: WKWebView) {
        let lang = Locale.current.language.languageCode?.identifier == "ja" ? "ja" : "en"
        let subdir = "Glow Id Help.help/Contents/Resources/\(lang).lproj"

        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: subdir) else {
            return
        }

        // CSS（../shared/）も読めるよう Resources フォルダへのアクセスを許可
        let resourcesURL = indexURL
            .deletingLastPathComponent()   // ja.lproj/
            .deletingLastPathComponent()   // Resources/

        webView.loadFileURL(indexURL, allowingReadAccessTo: resourcesURL)
    }

    private func positionTopLeft(_ win: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let gap: CGFloat = 18
        let visible = screen.visibleFrame
        let x = visible.minX + gap
        let y = visible.maxY - win.frame.height - gap
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // ローカルファイル間のリンク（ページ内ナビゲーション）は許可
        // 外部URL（http/https）はデフォルトブラウザで開く
        if let url = navigationAction.request.url, url.isFileURL {
            decisionHandler(.allow)
        } else if let url = navigationAction.request.url {
            decisionHandler(.cancel)
            NSWorkspace.shared.open(url)
        } else {
            decisionHandler(.allow)
        }
    }
}
