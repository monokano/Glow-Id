
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
        win.contentView = NSHostingView(rootView: ChangeLogView())
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

// MARK: - ChangeLogView

private struct ChangeLogView: NSViewRepresentable {

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
}
