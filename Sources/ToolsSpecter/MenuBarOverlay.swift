import AppKit

// MARK: - Panel

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Title

private final class BarTitleView: NSView {

    let node: Node
    let title: String
    let font: NSFont

    var onClick: ((BarTitleView) -> Void)?
    var isHighlighted = false {
        didSet {
            if oldValue != isHighlighted { needsDisplay = true }
        }
    }

    private var isPressed = false

    static let horizontalPadding: CGFloat = 10

    init(node: Node, font: NSFont) {
        self.node = node
        self.title = node.item.title.isEmpty ? "(untitled)" : node.item.title
        self.font = font
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var preferredWidth: CGFloat {
        let size = (title as NSString).size(withAttributes: [.font: font])
        return ceil(size.width) + Self.horizontalPadding * 2
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            let inset = NSRect(x: 2, y: 3, width: bounds.width - 4, height: bounds.height - 6)
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: inset, xRadius: 5, yRadius: 5).fill()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        let point = NSPoint(x: Self.horizontalPadding,
                            y: (bounds.height - size.height) / 2)
        (title as NSString).draw(at: point, withAttributes: attrs)
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isPressed else { return }
        isHighlighted = true
    }

    override func mouseExited(with event: NSEvent) {
        guard !isPressed else { return }
        isHighlighted = false
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        isHighlighted = true
        (superview as? MenuBarBarView)?.updateDrag(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        (superview as? MenuBarBarView)?.updateDrag(at: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let bar = superview as? MenuBarBarView
        guard let target = bar?.title(at: event.locationInWindow) else {
            isHighlighted = false
            return
        }
        target.onClick?(target)
    }
}

// MARK: - Divider

private final class BarDividerView: NSView {
    var preferredWidth: CGFloat { 9 }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        let rect = NSRect(x: (bounds.width - 1) / 2,
                          y: bounds.height * 0.22,
                          width: 1,
                          height: bounds.height * 0.56)
        rect.fill()
    }
}

// MARK: - Bar

private final class MenuBarBarView: NSView {

    var onActivate: ((BarTitleView) -> Void)?
    var onClose: (() -> Void)?

    private let font: NSFont = NSFont.menuBarFont(ofSize: 0)
    private var rows: [NSView] = []
    private var titles: [BarTitleView] = []
    private var selectedIndex: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.menuBar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    func rebuild(nodes: [Node]) {
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        titles.removeAll()
        selectedIndex = nil

        for node in nodes {
            if node.isSeparator {
                let divider = BarDividerView()
                addSubview(divider)
                rows.append(divider)
                continue
            }
            let view = BarTitleView(node: node, font: font)
            view.onClick = { [weak self] title in
                self?.onActivate?(title)
            }
            addSubview(view)
            rows.append(view)
            titles.append(view)
        }
        needsLayout = true
    }

    var preferredWidth: CGFloat {
        var total: CGFloat = 6
        for row in rows {
            if let title = row as? BarTitleView {
                total += title.preferredWidth
            } else if let divider = row as? BarDividerView {
                total += divider.preferredWidth
            }
        }
        return total
    }

    override func layout() {
        super.layout()
        var x = bounds.width - 2
        for row in rows {
            let width: CGFloat
            if let title = row as? BarTitleView {
                width = title.preferredWidth
            } else if let divider = row as? BarDividerView {
                width = divider.preferredWidth
            } else {
                width = 0
            }
            row.frame = NSRect(x: x - width, y: 0, width: width, height: bounds.height)
            x -= width
        }
    }

    // MARK: Hit testing

    /// The screen's top edge is the window's maximum Y, which NSRect.contains
    /// treats as outside. Extend each title upwards so the last pixel row of
    /// the menu bar still counts as a hit.
    private func hitRect(for title: BarTitleView) -> NSRect {
        var rect = title.convert(title.bounds, to: nil)
        rect.size.height += 24
        return rect
    }

    func title(at windowPoint: NSPoint) -> BarTitleView? {
        titles.first { hitRect(for: $0).contains(windowPoint) }
    }

    func updateDrag(at windowPoint: NSPoint) {
        for title in titles {
            title.isHighlighted = hitRect(for: title).contains(windowPoint)
        }
    }

    func highlightOnly(_ title: BarTitleView?) {
        for view in titles {
            view.isHighlighted = (view === title)
        }
    }

    func clearSelection() {
        selectedIndex = nil
        for view in titles {
            view.isHighlighted = false
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onClose?()
        case 123: // Left arrow -> leftwards, i.e. next index
            moveSelection(by: 1)
        case 124: // Right arrow -> rightwards, i.e. previous index
            moveSelection(by: -1)
        case 125, 36, 49: // Down arrow, Return, Space
            activateSelection()
        default:
            super.keyDown(with: event)
        }
    }

    private func moveSelection(by delta: Int) {
        guard !titles.isEmpty else { return }
        let current = selectedIndex ?? (delta > 0 ? -1 : 0)
        let next = min(max(current + delta, 0), titles.count - 1)
        select(next)
    }

    private func activateSelection() {
        guard !titles.isEmpty else { return }
        let index = selectedIndex ?? 0
        select(index)
        onActivate?(titles[index])
    }

    private func select(_ index: Int) {
        for (i, view) in titles.enumerated() {
            view.isHighlighted = (i == index)
        }
        selectedIndex = index
    }
}

// MARK: - Controller

final class MenuBarOverlayController: NSObject {

    private weak var anchor: NSStatusBarButton?
    private var panel: OverlayPanel?
    private var barView: MenuBarBarView?
    private let dropdown = MenuDropdownController()

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    private weak var openTitle: BarTitleView?
    private var hoverTimer: Timer?
    private var hoverCandidate: BarTitleView?
    private var hoverCandidateSince: TimeInterval = 0

    private var wordRect: NSRect?
    private var suppressStatusClickUntil: Date?
    private var openedAt = Date()

    private(set) var isOpen = false
    var onVisibilityChange: ((Bool) -> Void)?

    override init() {
        super.init()
        dropdown.onLaunch = { [weak self] item in
            Launcher.open(item)
            self?.hide()
        }
    }

    // MARK: Show / hide

    func toggle(anchor: NSStatusBarButton, event: NSEvent?) {
        if isOpen {
            hide()
        } else {
            show(anchor: anchor, event: event)
        }
    }

    func show(anchor: NSStatusBarButton, event: NSEvent?) {
        self.anchor = anchor
        dropdown.close()

        // Status item windows report no usable geometry on recent macOS, so
        // derive the item's screen position from the click that opened the bar.
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                ?? anchor.window?.screen
                ?? NSScreen.main else { return }

        let itemWidth = max(anchor.bounds.width, 20)
        var localX = itemWidth / 2
        if let event {
            let point = anchor.convert(event.locationInWindow, from: nil)
            if point.x.isFinite, point.x >= 0, point.x <= itemWidth {
                localX = point.x
            }
        }

        let rightEdge = min(max(mouse.x - localX, screen.frame.minX + 80), screen.frame.maxX)
        let availableWidth = rightEdge - screen.frame.minX
        guard availableWidth > 80 else { return }

        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let height = menuBarHeight >= 20
            ? menuBarHeight
            : max(NSStatusBar.system.thickness + 8, 24)

        let panel = makePanel()
        guard let barView else { return }
        barView.rebuild(nodes: ConfigStore.shared.root)

        // Only cover as much of the menu bar as the titles actually need.
        let width = min(availableWidth, max(barView.preferredWidth, 120))
        let frame = NSRect(x: rightEdge - width,
                           y: screen.frame.maxY - height,
                           width: width,
                           height: height)
        panel.setFrame(frame, display: true)
        barView.layoutSubtreeIfNeeded()
        barView.needsDisplay = true

        wordRect = NSRect(x: rightEdge - itemWidth,
                          y: screen.frame.maxY - height,
                          width: itemWidth * 3,
                          height: height)

        panel.appearance = Self.systemAppearance()
        barView.appearance = anchor.effectiveAppearance

        openedAt = Date()
        isOpen = true
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(barView)
        installMonitors()
        startPointerTracking()
        onVisibilityChange?(true)
    }

    func hide() {
        guard isOpen else { return }
        isOpen = false
        dropdown.close()
        removeMonitors()
        stopPointerTracking()

        openTitle?.isHighlighted = false
        openTitle = nil
        wordRect = nil

        barView?.clearSelection()
        panel?.orderOut(nil)
        onVisibilityChange?(false)
    }

    // MARK: Panel construction

    private func makePanel() -> OverlayPanel {
        if let panel {
            return panel
        }

        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 24),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let content = NSView()
        panel.contentView = content

        let bar = MenuBarBarView(frame: content.bounds)
        bar.autoresizingMask = [.width, .height]
        bar.onActivate = { [weak self] title in
            self?.activate(title)
        }
        bar.onClose = { [weak self] in
            self?.hide()
        }
        content.addSubview(bar)

        self.panel = panel
        self.barView = bar
        return panel
    }

    private static func systemAppearance() -> NSAppearance {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        return NSAppearance(named: isDark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance
    }

    // MARK: Activation

    private func activate(_ title: BarTitleView) {
        let node = title.node
        guard node.isFolder else {
            Launcher.open(node.item)
            hide()
            return
        }

        if openTitle === title, dropdown.isOpen {
            return
        }

        openTitle?.isHighlighted = false
        openTitle = title
        title.isHighlighted = true

        guard let panel, let barView else { return }
        let point = barView.convert(NSPoint(x: title.frame.minX, y: 0), to: nil)
        let screenPoint = panel.convertPoint(toScreen: point)
        dropdown.open(folder: node, at: screenPoint)
    }

    // MARK: Pointer tracking

    private func startPointerTracking() {
        stopPointerTracking()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.pollPointer()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopPointerTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverCandidate = nil
    }

    private func pollPointer() {
        guard isOpen, let panel, let barView else { return }

        // A click on the trigger word can land while the bar is already open;
        // close everything. Ignore the press that opened the bar.
        if Date().timeIntervalSince(openedAt) > 0.25,
           NSEvent.pressedMouseButtons != 0,
           let wordRect,
           wordRect.contains(NSEvent.mouseLocation) {
            suppressStatusClickUntil = Date().addingTimeInterval(0.6)
            hide()
            return
        }

        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        guard let hovered = barView.title(at: windowPoint) else {
            hoverCandidate = nil
            return
        }

        if hovered.node.isFolder {
            if hovered === openTitle { return }
            if hoverCandidate !== hovered {
                hoverCandidate = hovered
                hoverCandidateSince = ProcessInfo.processInfo.systemUptime
                barView.highlightOnly(hovered)
                return
            }
            guard ProcessInfo.processInfo.systemUptime - hoverCandidateSince >= 0.05 else { return }
            hoverCandidate = nil
            activate(hovered)
            return
        }

        // Top-level launcher: no dropdown, run it directly on click.
        hoverCandidate = nil
        barView.highlightOnly(hovered)
        if dropdown.isOpen {
            dropdown.close()
            openTitle?.isHighlighted = false
            openTitle = nil
        }
    }

    // MARK: Monitors

    private func installMonitors() {
        removeMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved]) { [weak self] event in
            guard let self else { return event }
            if event.type == .mouseMoved {
                self.pollPointer()
                return event
            }

            let mouse = NSEvent.mouseLocation
            if self.dropdown.contains(window: event.window) {
                return event
            }
            if let wordRect = self.wordRect, wordRect.contains(mouse) {
                self.suppressStatusClickUntil = Date().addingTimeInterval(0.6)
                self.hide()
                return nil
            }
            if event.window === self.anchor?.window {
                if self.dropdown.isOpen || self.openTitle != nil {
                    self.suppressStatusClickUntil = Date().addingTimeInterval(0.6)
                    self.hide()
                    return nil
                }
                return event
            }
            if event.window === self.panel {
                return event
            }
            self.suppressStatusClickUntil = Date().addingTimeInterval(0.4)
            self.hide()
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            if let wordRect = self.wordRect, wordRect.contains(mouse) {
                return
            }
            self.suppressStatusClickUntil = Date().addingTimeInterval(0.4)
            self.hide()
        }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                           object: nil,
                                           queue: .main) { [weak self] _ in
            self?.hide()
        })

        let defaultCenter = NotificationCenter.default
        observers.append(defaultCenter.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                   object: nil,
                                                   queue: .main) { [weak self] _ in
            self?.hide()
        })
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: Status item click suppression

    /// True when the click that just reached the status item was actually the
    /// click we used to dismiss the bar, so it must not reopen it.
    func consumeDismissedStatusClick() -> Bool {
        guard let until = suppressStatusClickUntil, Date() < until else {
            suppressStatusClickUntil = nil
            return false
        }
        suppressStatusClickUntil = nil
        return true
    }
}
