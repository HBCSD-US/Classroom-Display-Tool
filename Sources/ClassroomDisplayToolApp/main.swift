import AppKit

private enum AppPalette {
    static let appearance = NSAppearance(named: .aqua)
    static let background = NSColor(calibratedWhite: 1.0, alpha: 1)
    static let panelBackground = NSColor(calibratedWhite: 0.985, alpha: 1)
    static let selectedBackground = NSColor(calibratedRed: 0.94, green: 0.98, blue: 1.0, alpha: 1)
    static let primaryText = NSColor(calibratedWhite: 0.14, alpha: 1)
    static let secondaryText = NSColor(calibratedWhite: 0.45, alpha: 1)
    static let separator = NSColor(calibratedWhite: 0.86, alpha: 1)
    static let accentBlue = NSColor(calibratedRed: 0.0, green: 0.45, blue: 0.95, alpha: 1)
}

struct DisplayPreset {
    let id: String
    let title: String
    let backendDescription: String
    let imageName: String

    func teacherDescription(displayCount: Int) -> String {
        switch id {
        case "mirror":
            return displayCount >= 3
                ? "Show the same content on all three displays."
                : "Show the same content on both displays."
        case "private":
            return displayCount >= 3
                ? "Keep your laptop private while students see the presentation on both screens."
                : "Keep your laptop private while students see the presentation on the classroom screen."
        case "extend":
            return "Use each display independently for maximum workspace."
        default:
            return backendDescription
        }
    }

    var titleColor: NSColor {
        switch id {
        case "mirror":
            return .systemBlue
        case "private":
            return .systemGreen
        case "extend":
            return .systemPurple
        default:
            return AppPalette.primaryText
        }
    }
}

struct ExternalDisplay {
    let name: String
    let connection: String

    var displayText: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConnection = connection.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedConnection.isEmpty else {
            return trimmedName.isEmpty ? "External Display" : trimmedName
        }

        if trimmedName.localizedCaseInsensitiveContains(trimmedConnection) {
            return trimmedName
        }

        return "\(trimmedName.isEmpty ? "External Display" : trimmedName) - \(trimmedConnection)"
    }
}

struct DisplayState {
    var displayCount: Int = 0
    var builtinCount: Int = 0
    var externalCount: Int = 0
    var heading: String = ""
    var message: String = ""
    var logFile: String = ""
    var externalDisplays: [ExternalDisplay] = []
    var presets: [DisplayPreset] = []

    var topologySignature: String {
        let externalSignature = externalDisplays
            .map { display in
                let name = display.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let connection = display.connection.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(name)@\(connection)"
            }
            .joined(separator: "|")

        return "\(displayCount)|\(builtinCount)|\(externalCount)|\(externalSignature)"
    }
}

struct BackendResult {
    let status: String
    let message: String
    let logFile: String
    let exitCode: Int32
}

final class BackendClient {
    private let scriptURL: URL

    init() throws {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("display_backend.sh"))
        }

        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        if let executableDirectory {
            candidates.append(executableDirectory.deletingLastPathComponent().appendingPathComponent("Resources/display_backend.sh"))
        }

        guard let script = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw NSError(
                domain: "HBCSDDisplayTool",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The display backend script was not found in the app bundle."]
            )
        }

        scriptURL = script
    }

    func loadState() throws -> DisplayState {
        let output = try run(arguments: ["--ui-state"]).output
        var state = DisplayState()

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first else { continue }

            switch key {
            case "display_count":
                state.displayCount = Int(parts[safe: 1] ?? "0") ?? 0
            case "builtin_count":
                state.builtinCount = Int(parts[safe: 1] ?? "0") ?? 0
            case "external_count":
                state.externalCount = Int(parts[safe: 1] ?? "0") ?? 0
            case "display_heading":
                state.heading = parts[safe: 1] ?? ""
            case "message":
                state.message = parts[safe: 1] ?? ""
            case "log_file":
                state.logFile = parts[safe: 1] ?? ""
            case "external_display":
                let name = parts[safe: 1] ?? ""
                let connection = parts[safe: 2] ?? ""
                state.externalDisplays.append(ExternalDisplay(name: name, connection: connection))
            case "preset":
                if parts.count >= 5 {
                    state.presets.append(
                        DisplayPreset(
                            id: parts[1],
                            title: parts[2],
                            backendDescription: parts[3],
                            imageName: parts[4]
                        )
                    )
                }
            default:
                continue
            }
        }

        return state
    }

    func applyPreset(id: String) throws -> BackendResult {
        let processResult = try run(arguments: ["--ui-apply", id])
        var status = processResult.exitCode == 0 ? "ok" : "error"
        var message = ""
        var logFile = ""

        for line in processResult.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { continue }

            switch parts[0] {
            case "status":
                status = parts[1]
            case "message":
                message = parts[1]
            case "log_file":
                logFile = parts[1]
            default:
                continue
            }
        }

        return BackendResult(status: status, message: message, logFile: logFile, exitCode: processResult.exitCode)
    }

    private func run(arguments: [String]) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = scriptURL
        process.arguments = arguments
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        var output = String(data: outputData, encoding: .utf8) ?? ""

        if !errorData.isEmpty, let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
            output += "\n" + errorOutput
        }

        return (process.terminationStatus, output)
    }
}

final class PresetCardView: NSControl {
    let preset: DisplayPreset
    private let activeBadgeView = NSStackView()
    private var isHovering = false

    var selected = false {
        didSet {
            updateStyle()
        }
    }

    var keyboardHighlighted = false {
        didSet {
            updateStyle()
        }
    }

    init(preset: DisplayPreset, displayCount: Int) {
        self.preset = preset
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.03
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 5

        let titleLabel = NSTextField(labelWithString: preset.title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 23, weight: .bold)
        titleLabel.textColor = preset.titleColor
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2

        let descriptionLabel = NSTextField(labelWithString: preset.teacherDescription(displayCount: displayCount))
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .systemFont(ofSize: 14, weight: .regular)
        descriptionLabel.textColor = AppPalette.primaryText
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 3

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = Self.loadImage(named: preset.imageName)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let activeIcon = NSImageView()
        activeIcon.translatesAutoresizingMaskIntoConstraints = false
        activeIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Active")
        activeIcon.contentTintColor = .white

        let activeLabel = NSTextField(labelWithString: "ACTIVE NOW")
        activeLabel.translatesAutoresizingMaskIntoConstraints = false
        activeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        activeLabel.textColor = .white

        activeBadgeView.translatesAutoresizingMaskIntoConstraints = false
        activeBadgeView.orientation = .horizontal
        activeBadgeView.alignment = .centerY
        activeBadgeView.spacing = 7
        activeBadgeView.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 11)
        activeBadgeView.wantsLayer = true
        activeBadgeView.layer?.cornerRadius = 7
        activeBadgeView.layer?.backgroundColor = AppPalette.accentBlue.cgColor
        activeBadgeView.isHidden = true
        activeBadgeView.setContentHuggingPriority(.required, for: .horizontal)
        activeBadgeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        activeBadgeView.addArrangedSubview(activeIcon)
        activeBadgeView.addArrangedSubview(activeLabel)

        addSubview(titleLabel)
        addSubview(descriptionLabel)
        addSubview(imageView)
        addSubview(activeBadgeView)

        let cardHeight: CGFloat = displayCount >= 3 ? 205 : 285
        let imageTopOffset: CGFloat = displayCount >= 3 ? 75 : 74
        let imageSize = displayCount >= 3
            ? NSSize(width: 550, height: 105)
            : NSSize(width: 520, height: 195)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: cardHeight),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: activeBadgeView.leadingAnchor, constant: -18),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),

            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),

            activeBadgeView.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            activeBadgeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            activeBadgeView.heightAnchor.constraint(equalToConstant: 28),

            activeIcon.widthAnchor.constraint(equalToConstant: 15),
            activeIcon.heightAnchor.constraint(equalToConstant: 15),

            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: imageTopOffset),
            imageView.widthAnchor.constraint(equalToConstant: imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: imageSize.height)
        ])

        setAccessibilityRole(.button)
        setAccessibilityLabel("\(preset.title). \(preset.teacherDescription(displayCount: displayCount))")
        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateStyle()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        sendAction(action, to: target)
    }

    private func updateStyle() {
        let emphasized = selected || keyboardHighlighted || isHovering

        activeBadgeView.isHidden = !selected
        layer?.backgroundColor = emphasized
            ? AppPalette.selectedBackground.cgColor
            : AppPalette.background.cgColor
        layer?.borderWidth = emphasized ? 6 : 1
        layer?.borderColor = emphasized
            ? AppPalette.accentBlue.cgColor
            : AppPalette.separator.cgColor
        layer?.shadowOpacity = emphasized ? 0.2 : 0.03
        layer?.shadowOffset = emphasized
            ? CGSize(width: 0, height: -5)
            : CGSize(width: 0, height: -2)
        layer?.shadowRadius = emphasized ? 15 : 5
        layer?.zPosition = emphasized ? 10 : 0
        layer?.setAffineTransform(emphasized
            ? CGAffineTransform(scaleX: 1.018, y: 1.018)
            : .identity)
    }

    private static func loadImage(named name: String) -> NSImage? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        return NSImage(contentsOf: resourceURL.appendingPathComponent("assets").appendingPathComponent(name))
    }
}

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private enum AppShortcut {
    static func shouldTerminateApp(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              !modifiers.contains(.control),
              !modifiers.contains(.option),
              let key = event.charactersIgnoringModifiers?.lowercased()
        else {
            return false
        }

        return key == "w" || key == "q"
    }
}

private enum KeyboardKeyCode {
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
}

final class ShortcutWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if AppShortcut.shouldTerminateApp(for: event) {
            NSApp.terminate(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if AppShortcut.shouldTerminateApp(for: event) {
            NSApp.terminate(nil)
            return
        }

        super.keyDown(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var backend: BackendClient?
    private var contentStack: NSStackView!
    private var statusLabel: NSTextField!
    private var cardsByPreset: [String: PresetCardView] = [:]
    private var selectedPresetID: String?
    private var highlightedPresetID: String?
    private var currentState = DisplayState()
    private var keyboardShortcutMonitor: Any?
    private var screenChangeObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var currentTopologySignature: String?
    private var stateLoadRequestID = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = AppPalette.appearance
        buildMainMenu()
        installKeyboardShortcuts()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        do {
            backend = try BackendClient()
        } catch {
            showFatalError(error.localizedDescription)
            return
        }

        buildWindow()
        installDisplayRefreshObservers()
        loadState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingRefreshWorkItem?.cancel()

        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }

        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }

        if let keyboardShortcutMonitor {
            NSEvent.removeMonitor(keyboardShortcutMonitor)
        }
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: appName)
        appMenuItem.submenu = appMenu

        let quitItem = NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        quitItem.keyEquivalentModifierMask = .command
        appMenu.addItem(quitItem)

        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let closeItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "w"
        )
        closeItem.target = NSApp
        closeItem.keyEquivalentModifierMask = .command
        fileMenu.addItem(closeItem)

        NSApp.mainMenu = mainMenu
    }

    private func installKeyboardShortcuts() {
        keyboardShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if AppShortcut.shouldTerminateApp(for: event) {
                NSApp.terminate(nil)
                return nil
            }

            if self?.handlePresetKeyboardEvent(event) == true {
                return nil
            }

            return event
        }
    }

    private func installDisplayRefreshObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleDisplayRefresh(after: 1.0)
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleDisplayRefresh(after: 0.2)
        }
    }

    private func buildWindow() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 820, height: 928)
        let windowWidth = min(820, max(680, visibleFrame.width - 56))
        let windowHeight = min(928, max(720, visibleFrame.height - 20))

        window = ShortcutWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = ""
        window.appearance = AppPalette.appearance
        window.backgroundColor = AppPalette.background
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 680, height: 700)
        window.contentView = loadingView(message: "Detecting displays...")
        window.makeKeyAndOrderFront(nil)
    }

    private func scheduleDisplayRefresh(after delay: TimeInterval) {
        pendingRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRefreshWorkItem = nil
            self.loadState(statusMessage: "Refreshing displays...")
        }

        pendingRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func loadState(statusMessage: String = "Detecting displays...") {
        stateLoadRequestID += 1
        let requestID = stateLoadRequestID

        statusLabel?.stringValue = statusMessage
        statusLabel?.isHidden = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let backend = self.backend else { return }

            do {
                let state = try backend.loadState()
                DispatchQueue.main.async {
                    guard requestID == self.stateLoadRequestID else { return }
                    let topologyChanged = self.currentTopologySignature != nil
                        && self.currentTopologySignature != state.topologySignature

                    let selectedPresetUnavailable = self.selectedPresetID.map { selectedPresetID in
                        !state.presets.contains(where: { $0.id == selectedPresetID })
                    } ?? false

                    if topologyChanged || selectedPresetUnavailable {
                        self.selectedPresetID = nil
                    }

                    let highlightedPresetUnavailable = self.highlightedPresetID.map { highlightedPresetID in
                        !state.presets.contains(where: { $0.id == highlightedPresetID })
                    } ?? false

                    if topologyChanged || highlightedPresetUnavailable {
                        self.highlightedPresetID = nil
                    }

                    self.currentTopologySignature = state.topologySignature
                    self.currentState = state
                    self.render(state: state)
                }
            } catch {
                DispatchQueue.main.async {
                    guard requestID == self.stateLoadRequestID else { return }
                    self.showFatalError(error.localizedDescription)
                }
            }
        }
    }

    private func render(state: DisplayState) {
        cardsByPreset.removeAll()

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = state.displayCount >= 3
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AppPalette.background

        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = AppPalette.background.cgColor
        scrollView.documentView = documentView

        contentStack = NSStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = state.displayCount >= 3 ? 14 : 20
        contentStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        documentView.addSubview(contentStack)

        func fillStackWidth(_ view: NSView) {
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor)
            ])
        }

        let header = headerView(message: state.message)
        contentStack.addArrangedSubview(header)
        fillStackWidth(header)

        let topology = topologyView(state: state)
        contentStack.addArrangedSubview(topology)
        fillStackWidth(topology)

        if state.presets.isEmpty {
            let emptyState = emptyStateView(message: state.message)
            contentStack.addArrangedSubview(emptyState)
            fillStackWidth(emptyState)
        } else {
            for preset in state.presets {
                let card = PresetCardView(preset: preset, displayCount: state.displayCount)
                card.target = self
                card.action = #selector(applyPresetFromCard(_:))
                card.selected = preset.id == selectedPresetID
                card.keyboardHighlighted = preset.id == highlightedPresetID
                cardsByPreset[preset.id] = card
                contentStack.addArrangedSubview(card)
                fillStackWidth(card)
            }
        }

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = AppPalette.secondaryText
        statusLabel.isHidden = true
        contentStack.addArrangedSubview(statusLabel)
        fillStackWidth(statusLabel)

        let preferredStackWidth = contentStack.widthAnchor.constraint(equalTo: documentView.widthAnchor, constant: -68)
        preferredStackWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 10),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
            preferredStackWidth,
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: documentView.leadingAnchor, constant: 34),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor, constant: -34),
            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        window.contentView = scrollView
    }

    private func headerView(message: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = AppPalette.background.cgColor

        let title = NSTextField(labelWithString: "Choose Your Display Mode")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = AppPalette.primaryText
        title.alignment = .center
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 2

        let subtitle = NSTextField(labelWithString: message)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = .systemFont(ofSize: 17)
        subtitle.textColor = AppPalette.secondaryText
        subtitle.alignment = .center
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2

        container.addSubview(title)
        container.addSubview(subtitle)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 78),

            title.topAnchor.constraint(equalTo: container.topAnchor),
            title.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 80),
            title.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -80),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitle.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 70),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -70),
            subtitle.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func topologyView(state: DisplayState) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = AppPalette.separator.cgColor
        container.layer?.backgroundColor = AppPalette.panelBackground.cgColor

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "display", accessibilityDescription: "External displays")
        icon.contentTintColor = AppPalette.secondaryText

        let eyebrowLabel = NSTextField(labelWithString: "External Display(s)")
        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        eyebrowLabel.font = .systemFont(ofSize: 13, weight: .medium)
        eyebrowLabel.textColor = AppPalette.secondaryText

        let displayLabel = NSTextField(labelWithString: externalDisplaySummary(from: state))
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        displayLabel.font = .systemFont(ofSize: 16, weight: .regular)
        displayLabel.textColor = AppPalette.primaryText
        displayLabel.lineBreakMode = .byTruncatingTail
        displayLabel.maximumNumberOfLines = 2
        displayLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [eyebrowLabel, displayLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = AppPalette.separator.cgColor

        let settingsButton = NSButton(title: "Display Settings", target: self, action: #selector(openDisplaySettings(_:)))
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Display Settings")
        settingsButton.imagePosition = .imageLeading
        settingsButton.font = .systemFont(ofSize: 14, weight: .semibold)
        settingsButton.contentTintColor = AppPalette.accentBlue
        settingsButton.attributedTitle = NSAttributedString(
            string: "Display Settings",
            attributes: [
                .foregroundColor: AppPalette.accentBlue,
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
            ]
        )
        settingsButton.setContentHuggingPriority(.required, for: .horizontal)
        settingsButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshDisplays(_:)))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.isBordered = false
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.imagePosition = .imageLeading
        refreshButton.font = .systemFont(ofSize: 14, weight: .semibold)
        refreshButton.contentTintColor = AppPalette.accentBlue
        refreshButton.attributedTitle = NSAttributedString(
            string: "Refresh",
            attributes: [
                .foregroundColor: AppPalette.accentBlue,
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
            ]
        )
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let actionStack = NSStackView(views: [refreshButton, settingsButton])
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 14
        actionStack.setContentHuggingPriority(.required, for: .horizontal)
        actionStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        container.addSubview(icon)
        container.addSubview(textStack)
        container.addSubview(separator)
        container.addSubview(actionStack)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 78),

            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),

            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 20),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14),

            separator.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 24),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),

            actionStack.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 20),
            actionStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            actionStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func externalDisplaySummary(from state: DisplayState) -> String {
        guard !state.externalDisplays.isEmpty else {
            return state.externalCount == 0 ? "No external display connected" : state.heading
        }

        return state.externalDisplays.map(\.displayText).joined(separator: "   |   ")
    }

    private func emptyStateView(message: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = AppPalette.separator.cgColor
        container.layer?.backgroundColor = AppPalette.background.cgColor

        let label = NSTextField(labelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = AppPalette.primaryText
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 4

        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 220),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 44),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -44),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func loadingView(message: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = AppPalette.background.cgColor

        let label = NSTextField(labelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = AppPalette.secondaryText
        label.alignment = .center

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    @objc private func refreshDisplays(_ sender: Any?) {
        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil
        loadState(statusMessage: "Refreshing displays...")
    }

    @objc private func openDisplaySettings(_ sender: Any?) {
        let workspace = NSWorkspace.shared
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.Displays-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.displays"
        ]

        for urlString in settingsURLs {
            if let url = URL(string: urlString), workspace.open(url) {
                return
            }
        }

        workspace.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane"))
    }

    private func handlePresetKeyboardEvent(_ event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true,
              window.attachedSheet == nil,
              !currentState.presets.isEmpty
        else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.contains(.command),
              !modifiers.contains(.control),
              !modifiers.contains(.option)
        else {
            return false
        }

        switch event.keyCode {
        case KeyboardKeyCode.downArrow:
            moveHighlightedPreset(by: 1)
            return true
        case KeyboardKeyCode.upArrow:
            moveHighlightedPreset(by: -1)
            return true
        case KeyboardKeyCode.tab:
            moveHighlightedPreset(by: modifiers.contains(.shift) ? -1 : 1)
            return true
        case KeyboardKeyCode.returnKey, KeyboardKeyCode.keypadEnter, KeyboardKeyCode.space:
            guard !isFocusedActionControl else {
                return false
            }

            return applyHighlightedPreset()
        default:
            return false
        }
    }

    private var presetCardsAreEnabled: Bool {
        !cardsByPreset.isEmpty && cardsByPreset.values.allSatisfy { $0.isEnabled }
    }

    private var isFocusedActionControl: Bool {
        guard let focusedView = window.firstResponder as? NSView else {
            return false
        }

        return focusedView is NSButton
    }

    private func moveHighlightedPreset(by offset: Int) {
        guard presetCardsAreEnabled, !currentState.presets.isEmpty else {
            return
        }

        let presets = currentState.presets
        let currentPresetID = highlightedPresetID ?? selectedPresetID
        let currentIndex = currentPresetID.flatMap { presetID in
            presets.firstIndex { $0.id == presetID }
        }

        let nextIndex: Int
        if let currentIndex {
            nextIndex = (currentIndex + offset + presets.count) % presets.count
        } else {
            nextIndex = offset >= 0 ? 0 : presets.count - 1
        }

        let nextPresetID = presets[nextIndex].id
        highlightedPresetID = nextPresetID
        updateCardSelection()

        if let card = cardsByPreset[nextPresetID] {
            card.scrollToVisible(card.bounds)
        }
    }

    private func applyHighlightedPreset() -> Bool {
        guard presetCardsAreEnabled,
              let highlightedPresetID,
              let preset = currentState.presets.first(where: { $0.id == highlightedPresetID })
        else {
            return false
        }

        applyPreset(preset)
        return true
    }

    @objc private func applyPresetFromCard(_ sender: PresetCardView) {
        highlightedPresetID = sender.preset.id
        updateCardSelection()
        applyPreset(sender.preset)
    }

    private func applyPreset(_ preset: DisplayPreset) {
        let presetID = preset.id
        setCardsEnabled(false)
        statusLabel.isHidden = false
        statusLabel.stringValue = "Applying \(preset.title)..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let backend = self.backend else { return }

            do {
                let result = try backend.applyPreset(id: presetID)
                DispatchQueue.main.async {
                    self.handleApplyResult(result, presetID: presetID)
                }
            } catch {
                DispatchQueue.main.async {
                    self.setCardsEnabled(true)
                    self.statusLabel.stringValue = ""
                    self.statusLabel.isHidden = true
                    self.showAlert(title: "Display Mode Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func handleApplyResult(_ result: BackendResult, presetID: String) {
        setCardsEnabled(true)

        if result.status == "ok" || result.status == "warning" {
            selectedPresetID = presetID
            highlightedPresetID = presetID
            updateCardSelection()
            statusLabel.stringValue = result.status == "warning" ? "Applied with warning" : "Applied"
        } else {
            statusLabel.stringValue = ""
            statusLabel.isHidden = true
        }

        if result.status == "warning" {
            showAlert(title: "Display Mode Applied With Warning", message: alertMessage(from: result))
        } else if result.status == "error" || result.status == "unavailable" || result.exitCode != 0 {
            showAlert(title: "Display Mode Not Applied", message: alertMessage(from: result))
        }
    }

    private func updateCardSelection() {
        for (presetID, card) in cardsByPreset {
            card.selected = presetID == selectedPresetID
            card.keyboardHighlighted = presetID == highlightedPresetID
        }
    }

    private func setCardsEnabled(_ enabled: Bool) {
        cardsByPreset.values.forEach { $0.isEnabled = enabled }
    }

    private func alertMessage(from result: BackendResult) -> String {
        var message = result.message.isEmpty ? "IT can review the display log for details." : result.message
        if !result.logFile.isEmpty {
            message += "\n\nLog file:\n\(result.logFile)"
        }
        return message
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func showFatalError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "HBCSD Display Tool Could Not Open"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.terminate(nil)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
