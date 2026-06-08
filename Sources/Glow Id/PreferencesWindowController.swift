import AppKit

class PreferencesWindowController: NSWindowController {

    // MARK: - UI

    private let checkAlwaysNotify  = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let checkAutoClaim     = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let checkSuppressIcon  = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let separator          = NSBox()
    private let versionLabel       = NSTextField(labelWithString: "")
    private let radioMajorMinor    = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let radioFullVersion   = NSButton(radioButtonWithTitle: "", target: nil, action: nil)

    // MARK: - Init

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Glow Id Preferences")
        win.isReleasedWhenClosed = false
        win.center()
        super.init(window: win)
        buildUI()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // ── 常に通知ウインドウを表示
        checkAlwaysNotify.title = String(localized: "Always show notification window (do not open automatically)")
        checkAlwaysNotify.target = self
        checkAlwaysNotify.action = #selector(checkAlwaysNotifyChanged)
        checkAlwaysNotify.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(checkAlwaysNotify)

        // ── 起動時に関連付けをする
        checkAutoClaim.title = String(localized: "Associate file types on launch (.indd / .indt / .indb / .indl / .idml)")
        checkAutoClaim.target = self
        checkAutoClaim.action = #selector(checkAutoClaimChanged)
        checkAutoClaim.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(checkAutoClaim)

        // ── ファイルアイコン取込完了を通知しない
        checkSuppressIcon.title = String(localized: "Do not notify about file icon import")
        checkSuppressIcon.target = self
        checkSuppressIcon.action = #selector(checkSuppressIconChanged)
        checkSuppressIcon.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(checkSuppressIcon)

        // ── セパレータ
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(separator)

        // ── バージョン検出モードラベル
        versionLabel.stringValue = String(localized: "Version detection for InDesign documents (.indd):")
        versionLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(versionLabel)

        // ラジオボタン: メジャー.マイナー
        radioMajorMinor.title = String(localized: "Major + Minor (Header)")
        radioMajorMinor.target = self
        radioMajorMinor.action = #selector(radioChanged)
        radioMajorMinor.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(radioMajorMinor)

        // ラジオボタン: フルバージョン
        radioFullVersion.title = String(localized: "Full Version (Document History)")
        radioFullVersion.target = self
        radioFullVersion.action = #selector(radioChanged)
        radioFullVersion.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(radioFullVersion)

        setupConstraints(content: content)
    }

    private func setupConstraints(content: NSView) {
        NSLayoutConstraint.activate([
            // 常に通知ウインドウ
            checkAlwaysNotify.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            checkAlwaysNotify.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            checkAlwaysNotify.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),

            // 起動時に関連付けをする
            checkAutoClaim.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            checkAutoClaim.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            checkAutoClaim.topAnchor.constraint(equalTo: checkAlwaysNotify.bottomAnchor, constant: 10),

            // ファイルアイコン取込完了を通知しない
            checkSuppressIcon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            checkSuppressIcon.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            checkSuppressIcon.topAnchor.constraint(equalTo: checkAutoClaim.bottomAnchor, constant: 10),

            // セパレータ
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            separator.topAnchor.constraint(equalTo: checkSuppressIcon.bottomAnchor, constant: 18),
            separator.heightAnchor.constraint(equalToConstant: 1),

            // バージョン検出ラベル
            versionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            versionLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            versionLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 18),

            // ラジオ: メジャー.マイナー
            radioMajorMinor.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),
            radioMajorMinor.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 10),

            // ラジオ: フルバージョン
            radioFullVersion.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),
            radioFullVersion.topAnchor.constraint(equalTo: radioMajorMinor.bottomAnchor, constant: 8),

            // ウィンドウ下端
            content.bottomAnchor.constraint(equalTo: radioFullVersion.bottomAnchor, constant: 26),
        ])
    }

    // MARK: - Load / Update

    private func loadValues() {
        let prefs = Preferences.shared
        checkAlwaysNotify.state = prefs.alwaysShowNotificationWindow ? .on : .off
        checkAutoClaim.state    = prefs.autoClaimFileAssociations ? .on : .off
        checkSuppressIcon.state = prefs.doNotNotifyIconImport ? .on : .off
        radioMajorMinor.state   = prefs.useFullVersion ? .off : .on
        radioFullVersion.state  = prefs.useFullVersion ? .on : .off
    }

    // MARK: - Actions

    @objc private func checkAlwaysNotifyChanged() {
        Preferences.shared.alwaysShowNotificationWindow = (checkAlwaysNotify.state == .on)
        Preferences.shared.save()
    }

    @objc private func checkAutoClaimChanged() {
        let on = (checkAutoClaim.state == .on)
        Preferences.shared.autoClaimFileAssociations = on
        Preferences.shared.save()
        if on {
            AppDelegate.shared?.claimFileAssociations()
        } else {
            AppDelegate.shared?.claimFileAssociationsToTopInDesign()
        }
    }

    @objc private func checkSuppressIconChanged() {
        Preferences.shared.doNotNotifyIconImport = (checkSuppressIcon.state == .on)
        Preferences.shared.save()
    }

    @objc private func radioChanged(_ sender: NSButton) {
        Preferences.shared.useFullVersion = (sender == radioFullVersion)
        Preferences.shared.save()
        radioMajorMinor.state = Preferences.shared.useFullVersion ? .off : .on
        radioFullVersion.state = Preferences.shared.useFullVersion ? .on : .off
    }
}
