import AppKit
import SwiftUI

// MARK: - デフォルト色

/// バッジポップオーバーのデフォルト背景色（濃いグレー、α=1.0）
let badgePopoverDefaultColor = NSColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1.0)

// MARK: - 描画ビュー（丸角矩形 + 三角の尻尾）

/// バブル本体を NSBezierPath で描画する NSView。
/// `tailEdge` はバブルから見て尻尾が突き出す辺。
/// 例: tailEdge = .maxX のとき、尻尾は右側に突き出す（= アンカーがバブルの右にある）。
private final class BadgeBubbleView: NSView {

    static let cornerRadius: CGFloat = 4
    static let tailLength:   CGFloat = 8   // 尻尾の長さ
    static let tailWidth:    CGFloat = 8   // 尻尾の根元の幅
    let message: String
    let tailEdge: NSRectEdge
    let tailCenter: CGFloat
    let bgColor: NSColor

    init(message: String, tailEdge: NSRectEdge, tailCenter: CGFloat, bgColor: NSColor) {
        self.message = message
        self.tailEdge = tailEdge
        self.tailCenter = tailCenter
        self.bgColor = bgColor
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        let r = Self.cornerRadius
        let tl = Self.tailLength
        let tw = Self.tailWidth

        // バブル本体の矩形（尻尾分を内側に寄せる）
        var body = bounds
        switch tailEdge {
        case .minX: body.origin.x   += tl; body.size.width  -= tl
        case .maxX: body.size.width  -= tl
        case .minY: body.origin.y   += tl; body.size.height -= tl
        case .maxY: body.size.height -= tl
        @unknown default: break
        }

        // 角丸矩形パス
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: r, yRadius: r)

        // 尻尾パス
        let tailPath = NSBezierPath()
        switch tailEdge {
        case .maxX:
            let cy = clampTail(tailCenter, min: body.minY + r + tw/2, max: body.maxY - r - tw/2)
            tailPath.move(to: NSPoint(x: body.maxX, y: cy + tw/2))
            tailPath.line(to: NSPoint(x: body.maxX + tl, y: cy))
            tailPath.line(to: NSPoint(x: body.maxX, y: cy - tw/2))
            tailPath.close()
        case .minX:
            let cy = clampTail(tailCenter, min: body.minY + r + tw/2, max: body.maxY - r - tw/2)
            tailPath.move(to: NSPoint(x: body.minX, y: cy - tw/2))
            tailPath.line(to: NSPoint(x: body.minX - tl, y: cy))
            tailPath.line(to: NSPoint(x: body.minX, y: cy + tw/2))
            tailPath.close()
        case .maxY:
            let cx = clampTail(tailCenter, min: body.minX + r + tw/2, max: body.maxX - r - tw/2)
            tailPath.move(to: NSPoint(x: cx - tw/2, y: body.maxY))
            tailPath.line(to: NSPoint(x: cx, y: body.maxY + tl))
            tailPath.line(to: NSPoint(x: cx + tw/2, y: body.maxY))
            tailPath.close()
        case .minY:
            let cx = clampTail(tailCenter, min: body.minX + r + tw/2, max: body.maxX - r - tw/2)
            tailPath.move(to: NSPoint(x: cx + tw/2, y: body.minY))
            tailPath.line(to: NSPoint(x: cx, y: body.minY - tl))
            tailPath.line(to: NSPoint(x: cx - tw/2, y: body.minY))
            tailPath.close()
        @unknown default: break
        }

        path.append(bodyPath)
        path.append(tailPath)
        path.windingRule = .nonZero

        bgColor.setFill()
        path.fill()

        // テキスト描画
        let textRect = body.insetBy(dx: 10, dy: 7)
        let para = NSMutableParagraphStyle()
        para.alignment = (tailEdge == .minY || tailEdge == .maxY) ? .center : .left
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ]
        (message as NSString).draw(in: textRect, withAttributes: attr)
    }

    private func clampTail(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        if hi < lo { return (lo + hi) / 2 }
        return Swift.min(Swift.max(v, lo), hi)
    }

    /// メッセージから必要なバブルサイズを算出する。
    static func fittingSize(message: String, tailEdge: NSRectEdge) -> NSSize {
        let attr: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12)]
        let textBound = (message as NSString).boundingRect(
            with: NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attr)
        var w = ceil(textBound.width)  + 10 * 2
        var h = ceil(textBound.height) + 7  * 2
        switch tailEdge {
        case .minX, .maxX: w += tailLength
        case .minY, .maxY: h += tailLength
        @unknown default: break
        }
        return NSSize(width: w, height: h)
    }
}

// MARK: - バッジパネル（枠なし・透明背景の NSPanel）

private final class BadgePanel: NSPanel {

    init(contentView: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: contentView.frame.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true   // ポップオーバー越しに下のクリックを通す
        level = .floating
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - コントローラ

private final class BadgePopoverController {

    private var panel: BadgePanel?
    private weak var anchorView: NSView?
    private var observers: [NSObjectProtocol] = []

    var isShown: Bool { panel != nil }

    func show(message: String, edge: Edge, color: NSColor, relativeTo view: NSView) {
        close()
        anchorView = view

        guard let window = view.window, let screen = window.screen else { return }

        let preferred = nsRectEdge(from: edge)
        let candidates: [NSRectEdge] = [preferred, opposite(preferred)] + perpendiculars(preferred)

        for candidate in candidates {
            if let placement = placement(for: candidate, message: message,
                                         anchorView: view, window: window, screen: screen) {
                let bubble = BadgeBubbleView(message: message,
                                             tailEdge: candidate,
                                             tailCenter: placement.tailCenter,
                                             bgColor: color)
                bubble.frame = NSRect(origin: .zero, size: placement.size)
                let p = BadgePanel(contentView: bubble)
                p.setFrame(NSRect(origin: placement.origin, size: placement.size), display: true)
                window.addChildWindow(p, ordered: .above)
                p.orderFront(nil)
                self.panel = p
                installObservers(window: window, view: view)
                return
            }
        }
    }

    func close() {
        if let p = panel {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        }
        panel = nil
        anchorView = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: 配置計算

    private struct Placement {
        let origin: NSPoint     // スクリーン座標
        let size: NSSize
        let tailCenter: CGFloat // バブル座標系での尻尾中心
    }

    private func placement(for tailEdge: NSRectEdge,
                           message: String,
                           anchorView: NSView,
                           window: NSWindow,
                           screen: NSScreen) -> Placement? {
        let size = BadgeBubbleView.fittingSize(message: message, tailEdge: tailEdge)
        let visible = screen.visibleFrame

        // アンカービューの window 座標 → screen 座標
        let anchorInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorInScreen = window.convertToScreen(anchorInWindow)

        let gap: CGFloat = 0
        var origin = NSPoint.zero

        switch tailEdge {
        case .maxX: origin.x = anchorInScreen.minX - size.width - gap
        case .minX: origin.x = anchorInScreen.maxX + gap
        case .minY: origin.y = anchorInScreen.maxY + gap
        case .maxY: origin.y = anchorInScreen.minY - size.height - gap
        @unknown default: return nil
        }

        // 主軸（尻尾が突き出す方向）が画面内に収まらない場合はこの edge を不採用
        switch tailEdge {
        case .maxX: if origin.x < visible.minX { return nil }
        case .minX: if origin.x + size.width > visible.maxX { return nil }
        case .minY: if origin.y + size.height > visible.maxY { return nil }
        case .maxY: if origin.y < visible.minY { return nil }
        @unknown default: return nil
        }

        // 副軸（尻尾と平行な方向）はバブルを画面内にクランプし、
        // 尻尾の中心位置でアンカー中心を指すように補正する。
        let tailCenter: CGFloat
        switch tailEdge {
        case .maxX, .minX:
            let desiredY = anchorInScreen.midY - size.height / 2
            origin.y = clamp(desiredY, lo: visible.minY, hi: visible.maxY - size.height)
            tailCenter = anchorInScreen.midY - origin.y
        case .minY, .maxY:
            let desiredX = anchorInScreen.midX - size.width / 2
            origin.x = clamp(desiredX, lo: visible.minX, hi: visible.maxX - size.width)
            tailCenter = anchorInScreen.midX - origin.x
        @unknown default: return nil
        }

        return Placement(origin: origin, size: size, tailCenter: tailCenter)
    }

    private func clamp(_ v: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        if hi < lo { return lo }
        return Swift.min(Swift.max(v, lo), hi)
    }

    // SwiftUI Edge → 尻尾が突き出す辺（NSRectEdge）
    // edge = .leading → ポップオーバーはアンカーの左、尻尾はバブルの右辺(.maxX)
    private func nsRectEdge(from edge: Edge) -> NSRectEdge {
        switch edge {
        case .leading:  return .maxX
        case .trailing: return .minX
        case .top:      return .minY
        case .bottom:   return .maxY
        @unknown default: return .maxX
        }
    }

    private func opposite(_ e: NSRectEdge) -> NSRectEdge {
        switch e {
        case .minX: return .maxX
        case .maxX: return .minX
        case .minY: return .maxY
        case .maxY: return .minY
        @unknown default: return .maxX
        }
    }

    private func perpendiculars(_ e: NSRectEdge) -> [NSRectEdge] {
        switch e {
        case .minX, .maxX: return [.maxY, .minY]
        case .minY, .maxY: return [.maxX, .minX]
        @unknown default: return []
        }
    }

    // MARK: アンカーの追従／クローズ

    private func installObservers(window: NSWindow, view: NSView) {
        let nc = NotificationCenter.default
        let names: [NSNotification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSView.frameDidChangeNotification,
            NSView.boundsDidChangeNotification,
        ]
        view.postsFrameChangedNotifications = true
        for name in names {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reposition()
            }
            observers.append(obs)
        }
        let closeObs = nc.addObserver(forName: NSWindow.willCloseNotification,
                                      object: window, queue: .main) { [weak self] _ in
            self?.close()
        }
        observers.append(closeObs)
    }

    private func reposition() {
        guard let view = anchorView, let window = view.window, let screen = window.screen,
              let panel = panel,
              let bubble = panel.contentView as? BadgeBubbleView else { return }
        if let placement = placement(for: bubble.tailEdge, message: bubble.message,
                                     anchorView: view, window: window, screen: screen) {
            panel.setFrame(NSRect(origin: placement.origin, size: placement.size), display: true)
        }
    }
}

// MARK: - SwiftUI 用アンカービュー

private struct BadgePopoverAnchor: NSViewRepresentable {

    let message: String
    @Binding var isPresented: Bool
    let edge: Edge
    let color: NSColor

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let controller = context.coordinator.controller
        if isPresented {
            if !controller.isShown {
                DispatchQueue.main.async {
                    guard nsView.window != nil else { return }
                    controller.show(message: message, edge: edge, color: color, relativeTo: nsView)
                }
            }
        } else {
            if controller.isShown { controller.close() }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.controller.close()
    }

    final class Coordinator {
        let controller = BadgePopoverController()
    }
}

// MARK: - ViewModifier

struct BadgePopoverModifier: ViewModifier {

    let message: String
    @Binding var isPresented: Bool
    var edge: Edge = .leading
    var color: NSColor = badgePopoverDefaultColor

    func body(content: Content) -> some View {
        content.background(
            BadgePopoverAnchor(message: message, isPresented: $isPresented, edge: edge, color: color)
        )
    }
}

// MARK: - View Extension

extension View {

    /// 外側クリックで閉じないダークバッジポップオーバーを付与する。
    ///
    /// - Parameters:
    ///   - message: 表示するメッセージ
    ///   - isPresented: true のとき自動でポップオーバーを表示する
    ///   - edge: ポップオーバーが現れるビューの辺（デフォルト: .leading）
    ///
    /// 使用例:
    /// ```swift
    /// Image(systemName: "exclamationmark.triangle")
    ///     .badgePopover("同じバージョンのアプリがありません",
    ///                   isPresented: $showWarning)
    /// ```
    func badgePopover(
        _ message: String,
        isPresented: Binding<Bool>,
        edge: Edge = .leading,
        color: NSColor = badgePopoverDefaultColor
    ) -> some View {
        modifier(BadgePopoverModifier(message: message,
                                      isPresented: isPresented,
                                      edge: edge,
                                      color: color))
    }

    /// SwiftUI Color でカラーを指定するオーバーロード。
    func badgePopover(
        _ message: String,
        isPresented: Binding<Bool>,
        edge: Edge = .leading,
        color: Color
    ) -> some View {
        badgePopover(message, isPresented: isPresented, edge: edge,
                     color: NSColor(color))
    }
}
