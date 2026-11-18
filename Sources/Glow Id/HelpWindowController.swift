import AppKit
import WebKit

/// アプリにバンドルしたヘルプブック（Glow Id Help.help）の index.html を WKWebView で表示する。
/// 表示言語はロケールに応じて ja / en を切り替える。DTP Zipper の HelpWindowController を流用（共通仕様＝
/// App-共有資料/ヘルプ仕様.md §3）。ブラウザ風の「戻る/進む」ツールバーを備える。
final class HelpWindowController: NSObject, NSToolbarDelegate, WKNavigationDelegate {

    private var window: NSWindow?
    private var webView: WKWebView?
    private let navSegment = NSSegmentedControl()
    private var canGoBackObs: NSKeyValueObservation?
    private var canGoForwardObs: NSKeyValueObservation?

    private static let navItemID = NSToolbarItem.Identifier("HelpNavigation")
    /// ツールバーぶん広げるウインドウの追加高さ（本文表示域を従来と同じに保つ）
    private static let toolbarExtraHeight: CGFloat = 38

    /// 最低OS 13.5 の deinit の互換処理で異常終了するのを避ける（HANDOFF の知見）。
    nonisolated deinit {}

    func show() {
        // すでに表示中なら前面に出すだけ
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentHeight: CGFloat = 560
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680,
                                height: contentHeight + Self.toolbarExtraHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Glow Id Help")
        win.minSize = NSSize(width: 400, height: 300 + Self.toolbarExtraHeight)
        win.isReleasedWhenClosed = false

        let webView = makeWebView()
        self.webView = webView
        win.contentView = webView

        installToolbar(on: win)
        observeNavigationState(of: webView)
        loadIndexPage(into: webView)

        positionTopLeft(win)

        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - Toolbar（戻る/進む）

    private func installToolbar(on window: NSWindow) {
        navSegment.segmentStyle = .separated
        navSegment.trackingMode = .momentary
        navSegment.segmentCount = 2
        navSegment.setImage(NSImage(systemSymbolName: "chevron.backward",
                                    accessibilityDescription: String(localized: "Back")), forSegment: 0)
        navSegment.setImage(NSImage(systemSymbolName: "chevron.forward",
                                    accessibilityDescription: String(localized: "Forward")), forSegment: 1)
        navSegment.setEnabled(false, forSegment: 0)
        navSegment.setEnabled(false, forSegment: 1)
        navSegment.target = self
        navSegment.action = #selector(navSegmentClicked(_:))

        let toolbar = NSToolbar(identifier: "HelpToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    @objc private func navSegmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: webView?.goBack()
        case 1: webView?.goForward()
        default: break
        }
    }

    /// 戻れる/進めるかを監視してセグメントの有効・無効を更新する。
    private func observeNavigationState(of webView: WKWebView) {
        canGoBackObs = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
            self?.navSegment.setEnabled(wv.canGoBack, forSegment: 0)
        }
        canGoForwardObs = webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
            self?.navSegment.setEnabled(wv.canGoForward, forSegment: 1)
        }
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.navItemID else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = navSegment
        item.visibilityPriority = .high
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navItemID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navItemID]
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
        // 日本語ローカライズ時は ja、それ以外は en。
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
