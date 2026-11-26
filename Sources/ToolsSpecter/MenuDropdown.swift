import AppKit

// MARK: - Row

private final class MenuRowView: NSView {

    static let height: CGFloat = 24
    static let separatorHeight: CGFloat = 9

    let node: Node
    var onHover: ((MenuRowView) -> Void)?
    var onClick: ((MenuRowView) -> Void)?

    var isSticky = false
    var isHighlighted = false {
        didSet { if oldValue != isHighlighted { needsDisplay = true } }
    }

    private let title: String
    private let icon: NSImage?
    private let showsArrow: Bool
    private let font = NSFont.menuFont(ofSize: 0)

    init(node: Node) {
        self.node = node
        self.title = node.item.title.isEmpty ? "(untitled)" : node.item.title
        self.icon = node.isFolder ? menuImage(named: "folder") : Launcher.icon(for: node.item)
        self.showsArrow = node.isFolder && !node.children.isEmpty
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func width(for node: Node, font: NSFont) -> CGFloat {
        let title = node.item.title.isEmpty ? "(untitled)" : node.item.title
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        let arrow: CGFloat = (node.isFolder && !node.children.isEmpty) ? 14 : 0
        return textWidth + 34 + arrow + 22
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
        }

        if let icon {
            let rect = NSRect(x: 10, y: (bounds.height - 16) / 2, width: 16, height: 16)
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
        }

        let color: NSColor = isHighlighted ? .white : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: 34, y: (bounds.height - size.height) / 2),
                                 withAttributes: attrs)

        if showsArrow {
            let arrow = "›" as NSString
            let arrowSize = arrow.size(withAttributes: attrs)
            arrow.draw(at: NSPoint(x: bounds.width - 16 - arrowSize.width,
                                   y: (bounds.height - arrowSize.height) / 2),
                       withAttributes: attrs)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        onHover?(self)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isSticky else { return }
        isHighlighted = false
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onClick?(self)
    }
}

// MARK: - Separator

private final class MenuSeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 12, y: (bounds.height - 1) / 2, width: bounds.width - 24, height: 1).fill()
    }
}

// MARK: - List

private final class MenuListView: NSView {

    var onHover: ((MenuRowView) -> Void)?
    var onClick: ((MenuRowView) -> Void)?

    private var rowViews: [NSView] = []
    let preferredSize: NSSize

    init(nodes: [Node]) {
        let font = NSFont.menuFont(ofSize: 0)
        var width: CGFloat = 160
        var height: CGFloat = 12
        for node in nodes {
            if node.isSeparator {
                height += MenuRowView.separatorHeight
            } else {
                height += MenuRowView.height
                width = max(width, MenuRowView.width(for: node, font: font))
            }
        }
        preferredSize = NSSize(width: ceil(width), height: height)
        super.init(frame: NSRect(origin: .zero, size: preferredSize))

        for node in nodes {
            if node.isSeparator {
                let separator = MenuSeparatorView()
                addSubview(separator)
                rowViews.append(separator)
                continue
            }
            let row = MenuRowView(node: node)
            row.onHover = { [weak self] row in
                self?.highlightOnly(row)
                self?.onHover?(row)
            }
            row.onClick = { [weak self] row in
                self?.onClick?(row)
            }
            addSubview(row)
            rowViews.append(row)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        var y = bounds.height - 6
        for view in rowViews {
            let height = view is MenuSeparatorView ? MenuRowView.separatorHeight : MenuRowView.height
            y -= height
            view.frame = NSRect(x: 0, y: y, width: bounds.width, height: height)
        }
    }

    func highlightOnly(_ row: MenuRowView?) {
        for view in rowViews {
            guard let candidate = view as? MenuRowView else { continue }
            candidate.isHighlighted = (candidate === row)
        }
    }

}

// MARK: - Panel

private final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var listView: MenuListView!
    weak var parentPanel: DropdownPanel?
}

// MARK: - Controller

final class MenuDropdownController {

    private var panels: [DropdownPanel] = []
    private var submenuTimer: Timer?
    private weak var openRow: MenuRowView?

    var onLaunch: ((ConfigItem) -> Void)?

    var isOpen: Bool { !panels.isEmpty }

    func contains(window: NSWindow?) -> Bool {
        guard let window else { return false }
        return panels.contains { $0 === window }
    }

    func open(folder: Node, at screenPoint: NSPoint) {
        close()
        guard !folder.children.isEmpty else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) })
                ?? NSScreen.main else { return }

        let panel = makePanel(nodes: folder.children, parent: nil)
        let size = panel.frame.size
        var x = screenPoint.x
        var y = screenPoint.y - size.height
        if x + size.width > screen.visibleFrame.maxX {
            x = screen.visibleFrame.maxX - size.width - 1
        }
        x = max(x, screen.visibleFrame.minX + 1)
        if y < screen.visibleFrame.minY + 4 {
            y = screen.visibleFrame.minY + 4
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panels = [panel]
        panel.orderFrontRegardless()
    }

    func close() {
        submenuTimer?.invalidate()
        submenuTimer = nil
        openRow = nil
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    // MARK: Panels

    private func makePanel(nodes: [Node], parent: DropdownPanel?) -> DropdownPanel {
        let list = MenuListView(nodes: nodes)
        let panel = DropdownPanel(contentRect: NSRect(origin: .zero, size: list.preferredSize),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered,
                                  defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        let appearance = NSApp.effectiveAppearance
        panel.appearance = appearance
        panel.parentPanel = parent
        panel.listView = list

        let container = MenuContainerView(content: list, size: list.preferredSize, appearance: appearance)
        panel.contentView = container

        list.onHover = { [weak self, weak panel] row in
            guard let self, let panel else { return }
            self.hover(row, in: panel)
        }
        list.onClick = { [weak self, weak panel] row in
            guard let self, let panel else { return }
            self.click(row, in: panel)
        }
        return panel
    }

    private func hover(_ row: MenuRowView, in panel: DropdownPanel) {
        closePanels(above: panel)

        if row.node.isFolder, !row.node.children.isEmpty {
            scheduleSubmenu(for: row, in: panel)
        } else {
            submenuTimer?.invalidate()
            submenuTimer = nil
            clearOpenRow()
        }
    }

    private func click(_ row: MenuRowView, in panel: DropdownPanel) {
        if row.node.isFolder, !row.node.children.isEmpty {
            submenuTimer?.invalidate()
            submenuTimer = nil
            showSubmenu(for: row, in: panel)
        } else {
            onLaunch?(row.node.item)
        }
    }

    private func scheduleSubmenu(for row: MenuRowView, in panel: DropdownPanel) {
        guard openRow !== row else { return }
        submenuTimer?.invalidate()
        let timer = Timer(timeInterval: 0.12, repeats: false) { [weak self, weak row, weak panel] _ in
            guard let self, let row, let panel else { return }
            self.showSubmenu(for: row, in: panel)
        }
        RunLoop.main.add(timer, forMode: .common)
        submenuTimer = timer
    }

    private func showSubmenu(for row: MenuRowView, in panel: DropdownPanel) {
        submenuTimer?.invalidate()
        submenuTimer = nil

        guard row.node.isFolder, !row.node.children.isEmpty else { return }
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }

        // Already showing this row's submenu.
        if panels.count > index + 1, openRow === row { return }

        closePanels(above: panel)
        clearOpenRow()

        let submenu = makePanel(nodes: row.node.children, parent: panel)
        let size = submenu.frame.size
        let screen = panel.screen ?? NSScreen.main

        let rowRect = row.convert(row.bounds, to: nil)
        let rowOnScreen = panel.convertToScreen(rowRect)

        var x = panel.frame.maxX - 2
        if let screen, x + size.width > screen.visibleFrame.maxX {
            x = panel.frame.minX - size.width + 2
        }
        var y = rowOnScreen.maxY - size.height
        if let screen {
            y = min(max(y, screen.visibleFrame.minY + 4),
                    screen.visibleFrame.maxY - size.height - 4)
        }
        submenu.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)

        panels.append(submenu)
        submenu.orderFrontRegardless()

        row.isSticky = true
        openRow = row
    }

    private func closePanels(above panel: DropdownPanel) {
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
        let keep = index + 1
        guard panels.count > keep else { return }
        for extra in panels[keep...] {
            extra.orderOut(nil)
        }
        panels.removeSubrange(keep...)
        clearOpenRow()
    }

    private func clearOpenRow() {
        openRow?.isSticky = false
        openRow?.isHighlighted = false
        openRow = nil
    }
}

// MARK: - Container

private final class MenuContainerView: NSView {
    init(content: NSView, size: NSSize, appearance: NSAppearance) {
        super.init(frame: NSRect(origin: .zero, size: size))
        self.appearance = appearance
        wantsLayer = true
        var background: CGColor?
        var border: CGColor?
        appearance.performAsCurrentDrawingAppearance {
            background = NSColor.windowBackgroundColor.cgColor
            border = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        }
        layer?.backgroundColor = background
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = border
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
