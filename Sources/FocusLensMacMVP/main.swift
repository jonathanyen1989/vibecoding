import AppKit
import Carbon
import CoreImage
import ImageIO
import ScreenCaptureKit

private let minSelectionSize: CGFloat = 40
private let cornerRadius: CGFloat = 18
private let zoomDuration: TimeInterval = 0.55
private let exitDuration: TimeInterval = 0.38

private enum BorderStyle: Int, CaseIterable {
    case solid = 0
    case rainbow = 1
    case breathing = 2
    case rainbowFlow = 3

    static let displayOrder: [BorderStyle] = [.solid, .breathing, .rainbow, .rainbowFlow]

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .rainbow: return "Rainbow gradient"
        case .breathing: return "Breathing highlight"
        case .rainbowFlow: return "Rainbow flow"
        }
    }

    var usesBorderColor: Bool {
        switch self {
        case .solid, .breathing: return true
        case .rainbow, .rainbowFlow: return false
        }
    }
}

private struct Shortcut: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    static let defaultShortcut = Shortcut(keyCode: UInt16(kVK_ANSI_W), modifiers: [.control])

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let allowed = flags.intersection([.control, .shift, .option, .command])
        guard !allowed.isEmpty else { return nil }
        guard event.keyCode != UInt16(kVK_Escape) else { return nil }
        self.init(keyCode: event.keyCode, modifiers: allowed)
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    var displayName: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.command) { parts.append("Command") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: " + ")
    }

    func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == keyCode
            && flags.contains(modifiers)
            && flags.intersection([.control, .shift, .option, .command]) == modifiers
    }

    private static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        default: return "Key \(keyCode)"
        }
    }
}

private struct FocusLensConfig {
    var maskOpacity: CGFloat
    var backgroundBlur: CGFloat
    var featherStrength: CGFloat
    var borderColor: NSColor
    var borderStyle: BorderStyle
    var borderOpacity: CGFloat
    var maxZoom: CGFloat
    var shortcut: Shortcut

    static let defaults = FocusLensConfig(
        maskOpacity: 0.59,
        backgroundBlur: 4,
        featherStrength: 0.60,
        borderColor: NSColor(calibratedRed: 246 / 255, green: 201 / 255, blue: 69 / 255, alpha: 1),
        borderStyle: .solid,
        borderOpacity: 1.0,
        maxZoom: 2.5,
        shortcut: .defaultShortcut
    )

    static func load() -> FocusLensConfig {
        let defaults = UserDefaults.standard
        let fallback = Self.defaults

        let maskOpacity = defaults.object(forKey: "maskOpacity") as? Double ?? Double(fallback.maskOpacity)
        let backgroundBlur = defaults.object(forKey: "backgroundBlur") as? Double ?? Double(fallback.backgroundBlur)
        let featherStrength = defaults.object(forKey: "featherStrength") as? Double ?? Double(fallback.featherStrength)
        let maxZoom = defaults.object(forKey: "maxZoom") as? Double ?? Double(fallback.maxZoom)
        let keyCode = defaults.object(forKey: "shortcutKeyCode") as? Int ?? Int(fallback.shortcut.keyCode)
        let modifierRaw = defaults.object(forKey: "shortcutModifiers") as? Int ?? Int(fallback.shortcut.modifiers.rawValue)
        var shortcut = Shortcut(keyCode: UInt16(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifierRaw)))
        if shortcut == Shortcut(keyCode: UInt16(kVK_ANSI_R), modifiers: [.control])
            || shortcut == Shortcut(keyCode: UInt16(kVK_Space), modifiers: [.control])
            || shortcut == Shortcut(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.option]) {
            shortcut = fallback.shortcut
        }

        let red = defaults.object(forKey: "borderRed") as? Double ?? 246 / 255
        let green = defaults.object(forKey: "borderGreen") as? Double ?? 201 / 255
        let blue = defaults.object(forKey: "borderBlue") as? Double ?? 69 / 255
        let borderStyleRaw = defaults.object(forKey: "borderStyle") as? Int ?? fallback.borderStyle.rawValue
        let borderStyle = BorderStyle(rawValue: borderStyleRaw) ?? fallback.borderStyle
        let borderOpacity = defaults.object(forKey: "borderOpacity") as? Double ?? Double(fallback.borderOpacity)

        return FocusLensConfig(
            maskOpacity: CGFloat(maskOpacity).clamped(to: 0.20...0.85),
            backgroundBlur: CGFloat(backgroundBlur).clamped(to: 0...12),
            featherStrength: CGFloat(featherStrength).clamped(to: 0...1),
            borderColor: NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1),
            borderStyle: borderStyle,
            borderOpacity: CGFloat(borderOpacity).clamped(to: 0.10...1.0),
            maxZoom: CGFloat(maxZoom).clamped(to: 1.2...4.0),
            shortcut: shortcut
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Double(maskOpacity), forKey: "maskOpacity")
        defaults.set(Double(backgroundBlur), forKey: "backgroundBlur")
        defaults.set(Double(featherStrength), forKey: "featherStrength")
        defaults.set(borderStyle.rawValue, forKey: "borderStyle")
        defaults.set(Double(borderOpacity), forKey: "borderOpacity")
        defaults.set(Double(maxZoom), forKey: "maxZoom")
        defaults.set(Int(shortcut.keyCode), forKey: "shortcutKeyCode")
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: "shortcutModifiers")

        let color = borderColor.usingColorSpace(.deviceRGB) ?? borderColor
        defaults.set(Double(color.redComponent), forKey: "borderRed")
        defaults.set(Double(color.greenComponent), forKey: "borderGreen")
        defaults.set(Double(color.blueComponent), forKey: "borderBlue")
    }
}

private enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private enum DisplayDiagnostics {
    private static let logURL = URL(fileURLWithPath: "/tmp/focuslens-display.log")

    static func logSelectedScreen(_ screen: NSScreen) {
        let displayID = screen.displayID ?? 0
        let mouse = CGEvent(source: nil)?.location ?? .zero
        let displayBounds = displayID == 0 ? .zero : CGDisplayBounds(displayID)
        append("trigger mouse=\(mouse) selectedDisplay=\(displayID) screenFrame=\(screen.frame) overlayFrame=\(screen.focusLensOverlayFrame) visibleFrame=\(screen.visibleFrame) scale=\(screen.backingScaleFactor) displayBounds=\(displayBounds)")
    }

    static func logCapturedImage(_ image: CGImage, for screen: NSScreen) {
        append("capture selectedDisplay=\(screen.displayID ?? 0) imagePixels=\(image.width)x\(image.height) screenPoints=\(screen.frame.width)x\(screen.frame.height) scale=\(screen.backingScaleFactor)")
        writeCapturedImage(image, displayID: screen.displayID ?? 0)
    }

    static func logShareableContent(displayID: CGDirectDisplayID, windowCount: Int, appCount: Int) {
        append("shareable selectedDisplay=\(displayID) windowsOnDisplay=\(windowCount) applications=\(appCount)")
    }

    private static func append(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }

    private static func writeCapturedImage(_ image: CGImage, displayID: CGDirectDisplayID) {
        let url = URL(fileURLWithPath: "/tmp/focuslens-capture-display-\(displayID).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = FocusLensConfig.load()
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var overlayWindow: OverlayWindow?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var didShowScreenRecordingAlert = false

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = FocusLensIconFactory.appIcon()
        setupStatusItem()
        registerHotKey()
        promptForScreenRecordingIfNeeded()

        if CommandLine.arguments.contains("--show-now") {
            Task { @MainActor [weak self] in
                await self?.showOverlayOnMouseScreen()
            }
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotKey()
    }

    @MainActor
    func showOverlayOnMouseScreen() async {
        if let existingWindow = overlayWindow {
            if existingWindow.isVisible {
                return
            }
            overlayWindow = nil
        }

        guard let screen = NSScreen.screenContainingMouse() else {
            fputs("FocusLens could not find the screen containing the mouse\n", stderr)
            NSSound.beep()
            return
        }
        DisplayDiagnostics.logSelectedScreen(screen)

        let isRunningAsAppBundle = Bundle.main.bundlePath.hasSuffix(".app")
        guard !isRunningAsAppBundle || ScreenRecordingPermission.isGranted else {
            fputs("FocusLens Screen Recording permission is missing; overlay will not be shown.\n", stderr)
            _ = ScreenRecordingPermission.requestAccess()
            showScreenRecordingPermissionAlert()
            return
        }

        let image: CGImage
        if let captured = await screen.captureDisplayImage() {
            image = captured
        } else {
            fputs("FocusLens could not capture real screen content; overlay will not be shown.\n", stderr)
            showScreenRecordingPermissionAlert()
            return
        }
        DisplayDiagnostics.logCapturedImage(image, for: screen)

        let window = OverlayWindow(screen: screen, screenshot: image, config: config) { [weak self] in
            self?.overlayWindow = nil
            self?.rebuildMenu()
        }
        overlayWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        rebuildMenu()
    }

    @MainActor
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = FocusLensIconFactory.statusIcon(color: config.borderColor)
        item.button?.imagePosition = .imageOnly
        statusItem = item
        rebuildMenu()
    }

    @MainActor
    private func rebuildMenu() {
        let menu = NSMenu()
        let isFocusActive = overlayWindow?.isVisible == true
        let startItem = NSMenuItem(title: isFocusActive ? "Focus Active" : "Start Focus", action: #selector(startFocusFromMenu), keyEquivalent: "")
        startItem.target = self
        startItem.isEnabled = !isFocusActive
        menu.addItem(startItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let shortcutItem = NSMenuItem(title: "Shortcut: \(config.shortcut.displayName)", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        let permissionTitle = ScreenRecordingPermission.isGranted
            ? "Screen Recording: Granted"
            : "Screen Recording: Missing"
        let permissionItem = NSMenuItem(title: permissionTitle, action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit FocusLens", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @MainActor
    @objc private func startFocusFromMenu() {
        Task { @MainActor in
            await showOverlayOnMouseScreen()
        }
    }

    @MainActor
    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(config: config) { [weak self] updated in
                self?.applyConfig(updated)
            }
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    @objc private func openScreenRecordingSettings() {
        ScreenRecordingPermission.openSystemSettings()
    }

    @MainActor
    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @MainActor
    private func applyConfig(_ updated: FocusLensConfig) {
        let shortcutChanged = updated.shortcut != config.shortcut
        config = updated
        config.save()
        statusItem?.button?.image = FocusLensIconFactory.statusIcon(color: config.borderColor)
        rebuildMenu()
        if shortcutChanged {
            registerHotKey()
        }
    }

    @MainActor
    private func registerHotKey() {
        unregisterHotKey()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in
                    await FocusLensRuntime.appDelegate.showOverlayOnMouseScreen()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &hotKeyHandler
        )
        if handlerStatus != noErr {
            fputs("FocusLens failed to install hotkey handler. Carbon status: \(handlerStatus)\n", stderr)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x464C4E53), id: 1)
        let status = RegisterEventHotKey(
            UInt32(config.shortcut.keyCode),
            config.shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            fputs("FocusLens failed to register \(config.shortcut.displayName). Carbon status: \(status)\n", stderr)
        } else {
            print("FocusLens registered hotkey: \(config.shortcut.displayName)")
            fflush(stdout)
        }
    }

    @MainActor
    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }
    }

    @MainActor
    private func promptForScreenRecordingIfNeeded() {
        guard !ScreenRecordingPermission.isGranted else { return }
        if ScreenRecordingPermission.requestAccess() {
            rebuildMenu()
            return
        }
        showScreenRecordingPermissionAlert()
    }

    @MainActor
    private func showScreenRecordingPermissionAlert() {
        guard !ScreenRecordingPermission.isGranted else {
            rebuildMenu()
            return
        }
        didShowScreenRecordingAlert = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording permission is required"
        alert.informativeText = "FocusLens needs Screen Recording permission to capture the current screen for presentation focus. Grant access to the app or the terminal used to run it, then restart FocusLens if macOS asks."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenRecordingPermission.openSystemSettings()
        }
        rebuildMenu()
    }
}

private final class SettingsWindowController: NSWindowController {
    private var config: FocusLensConfig
    private let onChange: (FocusLensConfig) -> Void
    private let maskValue = NSTextField(labelWithString: "")
    private let blurValue = NSTextField(labelWithString: "")
    private let featherValue = NSTextField(labelWithString: "")
    private let zoomValue = NSTextField(labelWithString: "")
    private let borderOpacityValue = NSTextField(labelWithString: "")
    private let shortcutRecorder = ShortcutRecorderButton()
    private let colorWell = NSColorWell()
    private let borderStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let maskSlider = NSSlider(value: 0, minValue: 0.20, maxValue: 0.85, target: nil, action: nil)
    private let blurSlider = NSSlider(value: 0, minValue: 0, maxValue: 12, target: nil, action: nil)
    private let featherSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let zoomSlider = NSSlider(value: 0, minValue: 1.2, maxValue: 4.0, target: nil, action: nil)
    private let borderOpacitySlider = NSSlider(value: 1.0, minValue: 0.10, maxValue: 1.0, target: nil, action: nil)

    init(config: FocusLensConfig, onChange: @escaping (FocusLensConfig) -> Void) {
        self.config = config
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "FocusLens Settings"
        window.center()
        super.init(window: window)
        buildContent()
        refreshControls()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        window?.contentView = root

        let title = NSTextField(labelWithString: "Presentation Focus Settings")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        root.addArrangedSubview(title)

        root.addArrangedSubview(settingRow(title: "Mask opacity", slider: maskSlider, valueLabel: maskValue))
        root.addArrangedSubview(settingRow(title: "Background blur", slider: blurSlider, valueLabel: blurValue))
        root.addArrangedSubview(settingRow(title: "Feather strength", slider: featherSlider, valueLabel: featherValue))
        root.addArrangedSubview(settingRow(title: "Max zoom", slider: zoomSlider, valueLabel: zoomValue))

        root.addArrangedSubview(settingRow(title: "Border opacity", slider: borderOpacitySlider, valueLabel: borderOpacityValue))

        let colorRow = NSStackView()
        colorRow.orientation = .horizontal
        colorRow.alignment = .centerY
        colorRow.spacing = 12
        colorRow.addArrangedSubview(label("Border color"))
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorRow.addArrangedSubview(colorWell)
        root.addArrangedSubview(colorRow)

        let borderStyleRow = NSStackView()
        borderStyleRow.orientation = .horizontal
        borderStyleRow.alignment = .centerY
        borderStyleRow.spacing = 12
        borderStyleRow.addArrangedSubview(label("Border style"))
        BorderStyle.displayOrder.forEach { borderStylePopup.addItem(withTitle: $0.title) }
        borderStylePopup.target = self
        borderStylePopup.action = #selector(borderStyleChanged)
        borderStylePopup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        borderStyleRow.addArrangedSubview(borderStylePopup)
        root.addArrangedSubview(borderStyleRow)

        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal
        shortcutRow.alignment = .centerY
        shortcutRow.spacing = 12
        shortcutRow.addArrangedSubview(label("Shortcut"))
        shortcutRecorder.onShortcut = { [weak self] shortcut in
            self?.config.shortcut = shortcut
            self?.commit()
            self?.refreshControls()
        }
        shortcutRow.addArrangedSubview(shortcutRecorder)
        root.addArrangedSubview(shortcutRow)

        let hint = NSTextField(labelWithString: "Tune these before presenting. Control + W starts focus only when FocusLens is idle; Esc exits the current focus.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        hint.widthAnchor.constraint(equalToConstant: 420).isActive = true
        root.addArrangedSubview(hint)

        maskSlider.target = self
        maskSlider.action = #selector(maskChanged)
        blurSlider.target = self
        blurSlider.action = #selector(blurChanged)
        featherSlider.target = self
        featherSlider.action = #selector(featherChanged)
        zoomSlider.target = self
        zoomSlider.action = #selector(zoomChanged)
        borderOpacitySlider.target = self
        borderOpacitySlider.action = #selector(borderOpacityChanged)
    }

    private func settingRow(title: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.addArrangedSubview(label(title))
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        row.addArrangedSubview(slider)
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 62).isActive = true
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        return label
    }

    private func refreshControls() {
        maskSlider.doubleValue = Double(config.maskOpacity)
        blurSlider.doubleValue = Double(config.backgroundBlur)
        featherSlider.doubleValue = Double(config.featherStrength * 100)
        zoomSlider.doubleValue = Double(config.maxZoom)
        borderOpacitySlider.doubleValue = Double(config.borderOpacity)
        colorWell.color = config.borderColor
        borderStylePopup.selectItem(at: BorderStyle.displayOrder.firstIndex(of: config.borderStyle) ?? 0)
        colorWell.isEnabled = config.borderStyle.usesBorderColor
        shortcutRecorder.shortcut = config.shortcut
        maskValue.stringValue = "\(Int(round(config.maskOpacity * 100)))%"
        blurValue.stringValue = String(format: "%.0f", Double(config.backgroundBlur))
        featherValue.stringValue = "\(Int(round(config.featherStrength * 100)))"
        zoomValue.stringValue = String(format: "%.1fx", Double(config.maxZoom))
        borderOpacityValue.stringValue = "\(Int(round(config.borderOpacity * 100)))%"
    }

    private func commit() {
        onChange(config)
    }

    @objc private func maskChanged() {
        config.maskOpacity = CGFloat(maskSlider.doubleValue)
        maskValue.stringValue = "\(Int(round(config.maskOpacity * 100)))%"
        commit()
    }

    @objc private func blurChanged() {
        config.backgroundBlur = CGFloat(blurSlider.doubleValue)
        blurValue.stringValue = String(format: "%.0f", Double(config.backgroundBlur))
        commit()
    }

    @objc private func featherChanged() {
        config.featherStrength = CGFloat(featherSlider.doubleValue / 100)
        featherValue.stringValue = "\(Int(round(config.featherStrength * 100)))"
        commit()
    }

    @objc private func zoomChanged() {
        config.maxZoom = CGFloat(zoomSlider.doubleValue)
        zoomValue.stringValue = String(format: "%.1fx", Double(config.maxZoom))
        commit()
    }

    @objc private func colorChanged() {
        config.borderColor = colorWell.color
        commit()
    }

    @objc private func borderOpacityChanged() {
        config.borderOpacity = CGFloat(borderOpacitySlider.doubleValue)
        borderOpacityValue.stringValue = "\(Int(round(config.borderOpacity * 100)))%"
        commit()
    }

    @objc private func borderStyleChanged() {
        let selectedIndex = borderStylePopup.indexOfSelectedItem
        config.borderStyle = BorderStyle.displayOrder.indices.contains(selectedIndex)
            ? BorderStyle.displayOrder[selectedIndex]
            : .solid
        colorWell.isEnabled = config.borderStyle.usesBorderColor
        commit()
    }
}

private final class ShortcutRecorderButton: NSButton {
    var shortcut = Shortcut.defaultShortcut {
        didSet { if !isRecording { title = shortcut.displayName } }
    }
    var onShortcut: ((Shortcut) -> Void)?
    private var isRecording = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 170, height: 30))
        title = shortcut.displayName
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        widthAnchor.constraint(equalToConstant: 170).isActive = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        title = "Press shortcut..."
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            title = shortcut.displayName
            return
        }
        guard let next = Shortcut(event: event) else {
            NSSound.beep()
            return
        }
        shortcut = next
        isRecording = false
        onShortcut?(next)
    }
}

private final class OverlayWindow: NSWindow {
    private let onClose: () -> Void
    private var didNotifyClose = false

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.onClose = {}
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    init(screen: NSScreen, screenshot: CGImage, config: FocusLensConfig, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let overlayFrame = screen.focusLensOverlayFrame
        let screenLocalFrame = NSRect(origin: .zero, size: overlayFrame.size)
        super.init(
            contentRect: screenLocalFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        isReleasedWhenClosed = false
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = OverlayView(
            frame: screenLocalFrame,
            screenshot: screenshot,
            config: config
        ) { [weak self] in
            self?.close()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func close() {
        if !didNotifyClose {
            didNotifyClose = true
            onClose()
        }
        super.close()
    }
}

private final class OverlayView: NSView {
    private enum Mode {
        case selecting
        case animatingIn
        case focused
        case animatingOut
    }

    private let screenshot: CGImage
    private let blurredScreenshot: CGImage?
    private let config: FocusLensConfig
    private let onExit: () -> Void
    private var mode: Mode = .selecting
    private var dragStart: CGPoint?
    private var selectionRect: CGRect?
    private var originalRect: CGRect?
    private var targetRect: CGRect?
    private var currentHole: CGRect?
    private var focusRect = CGRect.zero
    private var targetScale: CGFloat = 1
    private var currentScale: CGFloat = 1
    private var targetTx: CGFloat = 0
    private var targetTy: CGFloat = 0
    private var currentTx: CGFloat = 0
    private var currentTy: CGFloat = 0
    private var timer: Timer?
    private var borderTimer: Timer?
    private var animationStart = Date()
    private var borderAnimationStart = Date()
    private var animationFromHole = CGRect.zero
    private var animationToHole = CGRect.zero
    private var animationFromScale: CGFloat = 1
    private var animationToScale: CGFloat = 1
    private var animationFromTx: CGFloat = 0
    private var animationFromTy: CGFloat = 0
    private var animationToTx: CGFloat = 0
    private var animationToTy: CGFloat = 0
    private var animationToFocused = true

    init(frame: NSRect, screenshot: CGImage, config: FocusLensConfig, onExit: @escaping () -> Void) {
        self.screenshot = screenshot
        self.config = config
        self.onExit = onExit
        self.blurredScreenshot = config.backgroundBlur > 0.1
            ? CGImage.blurredImage(from: screenshot, radius: config.backgroundBlur)
            : nil
        super.init(frame: frame)
        wantsLayer = true
        if config.borderStyle == .breathing || config.borderStyle == .rainbowFlow {
            startBorderTimer()
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            timer?.invalidate()
            timer = nil
            borderTimer?.invalidate()
            borderTimer = nil
        }
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        drawScreenshot(focusHole: activeHole)

        if let hole = activeHole, hole.width > 1, hole.height > 1 {
            drawMask(excluding: hole)
            drawFrame(around: hole)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard mode == .selecting else { return }
        let point = clamp(convert(event.locationInWindow, from: nil))
        dragStart = point
        selectionRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .selecting, let dragStart else { return }
        let point = clamp(convert(event.locationInWindow, from: nil))
        selectionRect = rect(from: dragStart, to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .selecting, let selectionRect else { return }
        let normalized = selectionRect.standardized
        if normalized.width < minSelectionSize || normalized.height < minSelectionSize {
            self.selectionRect = nil
            currentHole = nil
            needsDisplay = true
            return
        }

        originalRect = normalized
        currentHole = normalized
        calculateFocusTransform(from: normalized)
        animate(toFocused: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            if mode == .focused || mode == .animatingIn {
                animate(toFocused: false)
            } else {
                onExit()
            }
        }
    }

    private var activeHole: CGRect? {
        switch mode {
        case .selecting:
            return selectionRect?.standardized
        case .animatingIn, .focused, .animatingOut:
            return currentHole
        }
    }

    private func drawScreenshot(focusHole: CGRect?) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high

        let destination = screenshotDestination()

        guard let focusHole, focusHole.width > 1, focusHole.height > 1, let blurredScreenshot else {
            draw(screenshot, in: destination, context: context)
            return
        }

        draw(blurredScreenshot, in: destination, context: context)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: focusHole, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
        draw(screenshot, in: destination, context: context)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ image: CGImage, in destination: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let cgDestination = CGRect(
            x: destination.minX,
            y: bounds.height - destination.maxY,
            width: destination.width,
            height: destination.height
        )
        context.draw(image, in: cgDestination)
        context.restoreGState()
    }

    private func screenshotDestination() -> CGRect {
        if mode == .selecting {
            return bounds
        }
        return CGRect(
            x: currentTx,
            y: currentTy,
            width: bounds.width * currentScale,
            height: bounds.height * currentScale
        )
    }

    private func drawMask(excluding hole: CGRect?) {
        let path = NSBezierPath(rect: bounds)
        if let hole {
            path.append(NSBezierPath(roundedRect: hole, xRadius: cornerRadius, yRadius: cornerRadius))
        }
        path.windingRule = .evenOdd
        NSColor(calibratedWhite: 0, alpha: config.maskOpacity).setFill()
        path.fill()
    }

    private func drawFrame(around rect: CGRect) {
        let strength = config.featherStrength.clamped(to: 0...1)
        if strength > 0 {
            strokeRounded(rect, width: 16 * strength, alpha: 0.15 * strength)
            strokeRounded(rect, width: 10 * strength, alpha: 0.23 * strength)
            strokeRounded(rect, width: 7 * strength, alpha: 0.33 * strength)
        }
        strokeRounded(rect, width: 3.5, alpha: 1)
    }

    private func strokeRounded(_ rect: CGRect, width: CGFloat, alpha: CGFloat) {
        guard width > 0.1 else { return }
        let baseAlpha = alpha * config.borderOpacity
        if config.borderStyle == .rainbow || config.borderStyle == .rainbowFlow {
            drawRainbowRounded(rect, width: width, alpha: baseAlpha)
            return
        }

        let pulse = config.borderStyle == .breathing ? breathingPulse : 0
        let effectiveWidth = width * (0.85 + 0.90 * pulse)
        let effectiveAlpha = baseAlpha * (0.38 + 0.62 * pulse)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = effectiveWidth
        (config.borderColor.usingColorSpace(.deviceRGB) ?? config.borderColor).withAlphaComponent(effectiveAlpha).setStroke()
        path.stroke()
    }

    private var breathingPulse: CGFloat {
        let elapsed = Date().timeIntervalSince(borderAnimationStart)
        return CGFloat((sin(elapsed * .pi) + 1) / 2)
    }

    private func startBorderTimer() {
        borderAnimationStart = Date()
        borderTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(borderTick(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func borderTick(_ timer: Timer) {
        guard config.borderStyle == .breathing || config.borderStyle == .rainbowFlow else {
            timer.invalidate()
            borderTimer = nil
            return
        }
        needsDisplay = true
    }

    private func drawRainbowRounded(_ rect: CGRect, width: CGFloat, alpha: CGFloat) {
        let outerRect = rect.insetBy(dx: -width / 2, dy: -width / 2)
        let innerRect = rect.insetBy(dx: width / 2, dy: width / 2)
        guard outerRect.width > 1, outerRect.height > 1, innerRect.width > 1, innerRect.height > 1 else { return }

        let path = NSBezierPath(roundedRect: outerRect, xRadius: cornerRadius + width / 2, yRadius: cornerRadius + width / 2)
        path.append(NSBezierPath(roundedRect: innerRect, xRadius: max(1, cornerRadius - width / 2), yRadius: max(1, cornerRadius - width / 2)))
        path.windingRule = .evenOdd

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: rainbowColors(alpha: alpha, phase: rainbowPhase))?.draw(in: outerRect, angle: rainbowAngle)
        NSGraphicsContext.restoreGraphicsState()
    }

    private var rainbowPhase: CGFloat {
        guard config.borderStyle == .rainbowFlow else { return 0 }
        let elapsed = Date().timeIntervalSince(borderAnimationStart)
        return CGFloat(elapsed.truncatingRemainder(dividingBy: 3.2) / 3.2)
    }

    private var rainbowAngle: CGFloat {
        guard config.borderStyle == .rainbowFlow else { return 0 }
        return rainbowPhase * 360
    }

    private func rainbowColors(alpha: CGFloat, phase: CGFloat) -> [NSColor] {
        let stops: [CGFloat] = [0.00, 0.10, 0.20, 0.34, 0.55, 0.72, 0.88, 1.00]
        return stops.map { stop in
            NSColor(calibratedHue: (stop + phase).truncatingRemainder(dividingBy: 1), saturation: 0.82, brightness: 1.0, alpha: alpha)
        }
    }

    private func animate(toFocused: Bool) {
        timer?.invalidate()
        mode = toFocused ? .animatingIn : .animatingOut
        animationStart = Date()

        if toFocused {
            currentScale = 1
            currentTx = 0
            currentTy = 0
        } else {
            targetScale = 1
            targetTx = 0
            targetTy = 0
        }

        animationFromHole = toFocused ? (originalRect ?? .zero) : focusRect
        animationToHole = toFocused ? focusRect : (originalRect ?? focusRect)
        animationFromScale = currentScale
        animationToScale = toFocused ? targetScale : 1
        animationFromTx = currentTx
        animationFromTy = currentTy
        animationToTx = toFocused ? targetTx : 0
        animationToTy = toFocused ? targetTy : 0
        animationToFocused = toFocused

        timer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(animationTick(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func animationTick(_ timer: Timer) {
        let elapsed = Date().timeIntervalSince(animationStart)
        let duration = animationToFocused ? zoomDuration : exitDuration
        let progress = min(1, elapsed / duration)
        let eased = animationToFocused ? easeInQuickOutSlow(progress) : easeOutCubic(progress)

        currentHole = interpolate(animationFromHole, animationToHole, eased)
        currentScale = animationFromScale + (animationToScale - animationFromScale) * eased
        currentTx = animationFromTx + (animationToTx - animationFromTx) * eased
        currentTy = animationFromTy + (animationToTy - animationFromTy) * eased
        needsDisplay = true

        if progress >= 1 {
            timer.invalidate()
            self.timer = nil
            if animationToFocused {
                mode = .focused
                currentHole = animationToHole
                currentScale = animationToScale
                currentTx = animationToTx
                currentTy = animationToTy
            } else {
                onExit()
            }
        }
    }

    private func calculateFocusTransform(from selected: CGRect) {
        let anchor = anchorPoint(for: selected)
        let left = abs(anchor.x - selected.minX) < 0.1
        let top = abs(anchor.y - selected.minY) < 0.1
        let maxX = left ? (bounds.width - anchor.x) / max(selected.width, 1) : anchor.x / max(selected.width, 1)
        let maxY = top ? (bounds.height - anchor.y) / max(selected.height, 1) : anchor.y / max(selected.height, 1)

        targetScale = max(1, min(config.maxZoom, maxX, maxY))
        targetTx = anchor.x - anchor.x * targetScale
        targetTy = anchor.y - anchor.y * targetScale
        targetTx = min(max(targetTx, bounds.width - bounds.width * targetScale), 0)
        targetTy = min(max(targetTy, bounds.height - bounds.height * targetScale), 0)

        focusRect = clamp(
            CGRect(
                x: selected.minX * targetScale + targetTx,
                y: selected.minY * targetScale + targetTy,
                width: selected.width * targetScale,
                height: selected.height * targetScale
            )
        )
        targetRect = focusRect
    }

    private func anchorPoint(for rect: CGRect) -> CGPoint {
        let left = rect.midX <= bounds.midX
        let top = rect.midY <= bounds.midY

        switch (left, top) {
        case (true, true):
            return CGPoint(x: rect.minX, y: rect.minY)
        case (false, true):
            return CGPoint(x: rect.maxX, y: rect.minY)
        case (true, false):
            return CGPoint(x: rect.minX, y: rect.maxY)
        case (false, false):
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func clamp(_ rect: CGRect) -> CGRect {
        let x = min(max(rect.minX, bounds.minX), bounds.maxX)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY)
        let right = min(max(rect.maxX, bounds.minX), bounds.maxX)
        let bottom = min(max(rect.maxY, bounds.minY), bounds.maxY)
        return CGRect(x: x, y: y, width: max(0, right - x), height: max(0, bottom - y))
    }

    private func interpolate(_ from: CGRect, _ to: CGRect, _ progress: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (to.minX - from.minX) * progress,
            y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress
        )
    }

    private func easeInQuickOutSlow(_ progress: CGFloat) -> CGFloat {
        progress < 0.3 ? (progress / 0.3) * 0.66 : 0.66 + (1 - pow(1 - ((progress - 0.3) / 0.7), 3)) * 0.34
    }

    private func easeOutCubic(_ progress: CGFloat) -> CGFloat {
        1 - pow(1 - progress, 3)
    }
}

private enum FocusLensIconFactory {
    static func statusIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 2, y: 2, width: 14, height: 14)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        color.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2.2
        path.stroke()

        color.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5.5, y: 5.5, width: 7, height: 7)).fill()
        image.isTemplate = false
        return image
    }

    static func appIcon() -> NSImage {
        if let asset = NSImage(contentsOfFile: "Assets/focuslens-app-icon.png") {
            return asset
        }

        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(x: 0, y: 0, width: 256, height: 256)
        NSGradient(colors: [
            NSColor(calibratedWhite: 0.06, alpha: 1),
            NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.10, alpha: 1)
        ])?.draw(in: NSBezierPath(roundedRect: bounds.insetBy(dx: 20, dy: 20), xRadius: 52, yRadius: 52), angle: 90)

        let glow = NSBezierPath(roundedRect: NSRect(x: 52, y: 76, width: 152, height: 104), xRadius: 26, yRadius: 26)
        NSColor(calibratedRed: 246 / 255, green: 201 / 255, blue: 69 / 255, alpha: 0.20).setStroke()
        glow.lineWidth = 26
        glow.stroke()

        let frame = NSBezierPath(roundedRect: NSRect(x: 54, y: 78, width: 148, height: 100), xRadius: 24, yRadius: 24)
        NSColor(calibratedRed: 246 / 255, green: 201 / 255, blue: 69 / 255, alpha: 1).setStroke()
        frame.lineWidth = 10
        frame.stroke()

        NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
        NSBezierPath(roundedRect: NSRect(x: 75, y: 99, width: 106, height: 58), xRadius: 14, yRadius: 14).fill()
        return image
    }
}

private extension NSScreen {
    static func screenContainingMouse() -> NSScreen? {
        if let event = CGEvent(source: nil) {
            let point = event.location
            var matchingDisplay = CGDirectDisplayID()
            var displayCount: UInt32 = 0
            let error = CGGetDisplaysWithPoint(point, 1, &matchingDisplay, &displayCount)
            if error == .success, displayCount > 0,
               let screen = screens.first(where: { $0.displayID == matchingDisplay }) {
                return screen
            }
        }
        return main ?? screens.first
    }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var focusLensOverlayFrame: NSRect {
        guard let displayID else { return frame }
        let displayBounds = CGDisplayBounds(displayID)
        guard !displayBounds.isEmpty else { return frame }
        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        return NSRect(
            x: displayBounds.minX,
            y: mainBounds.height - displayBounds.maxY,
            width: displayBounds.width,
            height: displayBounds.height
        )
    }

    func captureDisplayImage() async -> CGImage? {
        guard let screenID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        let displayBounds = CGDisplayBounds(screenID)
        if let image = CGWindowListCreateImage(
            displayBounds,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) {
            return image
        }

        if #available(macOS 14.0, *), let image = await ScreenCaptureKitScreenshot.captureDisplayImage(for: self) {
            return image
        }

        return CGDisplayCreateImage(screenID)
    }
}

@available(macOS 14.0, *)
private enum ScreenCaptureKitScreenshot {
    static func captureDisplayImage(for screen: NSScreen) async -> CGImage? {
        guard let displayID = screen.displayID else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }

            let windowsOnDisplay = content.windows.filter { window in
                window.isOnScreen && window.frame.intersects(display.frame)
            }
            DisplayDiagnostics.logShareableContent(
                displayID: displayID,
                windowCount: windowsOnDisplay.count,
                appCount: content.applications.count
            )

            let currentProcessID = ProcessInfo.processInfo.processIdentifier
            let excludedApplications = content.applications.filter { application in
                application.processID == currentProcessID
                    || application.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = true
            configuration.scalesToFit = false
            configuration.backgroundColor = CGColor.black
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            fputs("FocusLens ScreenCaptureKit capture failed: \(error)\n", stderr)
            return nil
        }
    }
}

private extension CGImage {
    static func blurredImage(from source: CGImage, radius: CGFloat) -> CGImage? {
        guard radius > 0.1 else { return nil }
        let input = CIImage(cgImage: source)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext(options: nil).createCGImage(output, from: input.extent)
    }

    static func blackImage(size: CGSize, scale: CGFloat) -> CGImage {
        let width = max(1, Int(size.width * scale))
        let height = max(1, Int(size.height * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(NSColor.black.cgColor)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context!.makeImage()!
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

@MainActor
private enum FocusLensRuntime {
    static let appDelegate = AppDelegate()
}

let application = NSApplication.shared
MainActor.assumeIsolated {
    application.delegate = FocusLensRuntime.appDelegate
}
application.run()
