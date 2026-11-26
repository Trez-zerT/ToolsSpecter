import AppKit

enum ItemKind: String, Codable, CaseIterable {
    case folder
    case separator
    case app
    case url
    case file
    case shell

    var label: String {
        switch self {
        case .folder: return "Folder"
        case .separator: return "Separator"
        case .app: return "App"
        case .url: return "URL"
        case .file: return "File"
        case .shell: return "Shell Tool"
        }
    }
}

struct ConfigItem: Codable, Identifiable {
    let id: UUID
    var kind: ItemKind
    var title: String
    var target: String?
    var children: [ConfigItem]

    init(id: UUID = UUID(),
         kind: ItemKind,
         title: String = "",
         target: String? = nil,
         children: [ConfigItem] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.target = target
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .app
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        target = try c.decodeIfPresent(String.self, forKey: .target)
        children = try c.decodeIfPresent([ConfigItem].self, forKey: .children) ?? []
    }
}

enum StatusItemStyle: String, Codable, CaseIterable {
    case iconAndText
    case iconOnly
    case textOnly

    var label: String {
        switch self {
        case .iconAndText: return "Icon and Text"
        case .iconOnly: return "Icon Only"
        case .textOnly: return "Text Only"
        }
    }
}

enum MenuStyle: String, Codable, CaseIterable {
    case horizontal
    case classic

    var label: String {
        switch self {
        case .horizontal: return "Amiga-style Menu"
        case .classic: return "Mac-style Menu"
        }
    }
}

struct ToolsConfig: Codable {
    private enum LegacyCodingKeys: String, CodingKey {
        case showGlyph
    }

    var root: [ConfigItem]
    var extraScanRoots: [String]
    var menuStyle: MenuStyle
    var barLabel: String
    var statusItemStyle: StatusItemStyle
    var barGap: Double

    init(root: [ConfigItem] = [],
         extraScanRoots: [String] = [],
         menuStyle: MenuStyle = .horizontal,
         barLabel: String = "Apps",
         statusItemStyle: StatusItemStyle = .iconAndText,
         barGap: Double = 0) {
        self.root = root
        self.extraScanRoots = extraScanRoots
        self.menuStyle = menuStyle
        self.barLabel = barLabel
        self.statusItemStyle = statusItemStyle
        self.barGap = barGap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        root = try c.decodeIfPresent([ConfigItem].self, forKey: .root) ?? []
        extraScanRoots = try c.decodeIfPresent([String].self, forKey: .extraScanRoots) ?? []
        menuStyle = try c.decodeIfPresent(MenuStyle.self, forKey: .menuStyle) ?? .horizontal
        barLabel = try c.decodeIfPresent(String.self, forKey: .barLabel) ?? "Apps"

        barGap = try c.decodeIfPresent(Double.self, forKey: .barGap) ?? 0
        if let style = try c.decodeIfPresent(StatusItemStyle.self, forKey: .statusItemStyle) {
            statusItemStyle = style
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            if let glyph = try legacy.decodeIfPresent(Bool.self, forKey: .showGlyph) {
                statusItemStyle = glyph ? .iconAndText : .textOnly
            } else {
                statusItemStyle = .iconAndText
            }
        }
    }
}

enum IconCatalog {

    private static var applicationsGraphic: NSImage?

    /// The Applications "A" made of a pencil, ruler and brush, drawn in the
    /// menu bar's template style so it tints with the system appearance.
    static func applicationsGlyph() -> NSImage {
        if let applicationsGraphic { return applicationsGraphic }

        if let url = Bundle.main.url(forResource: "ApplicationsA", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            let height: CGFloat = 18
            let width = max(1, height * (image.size.width / max(image.size.height, 1)))
            image.size = NSSize(width: width, height: height)
            image.isTemplate = true
            applicationsGraphic = image
            return image
        }

        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSColor.black.set()

        func stroke(_ a: NSPoint, _ b: NSPoint, _ width: CGFloat,
                    _ cap: NSBezierPath.LineCapStyle = .round) {
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineCapStyle = cap
            path.move(to: a)
            path.line(to: b)
            path.stroke()
        }

        // Pencil (left leg) with its sharpened tip.
        stroke(NSPoint(x: 3.6, y: 4.0), NSPoint(x: 7.2, y: 13.2), 1.9)
        let tip = NSBezierPath()
        tip.move(to: NSPoint(x: 6.2, y: 12.4))
        tip.line(to: NSPoint(x: 8.3, y: 15.7))
        tip.line(to: NSPoint(x: 4.9, y: 14.6))
        tip.close()
        tip.fill()

        // Ruler (right leg) with tick marks.
        stroke(NSPoint(x: 10.8, y: 14.6), NSPoint(x: 14.4, y: 3.4), 2.2, .square)
        let direction = NSPoint(x: 3.6, y: -11.2)
        let length = (direction.x * direction.x + direction.y * direction.y).squareRoot()
        let perpendicular = NSPoint(x: -direction.y / length, y: direction.x / length)
        for t in [0.28, 0.5, 0.72] {
            let base = NSPoint(x: 10.8 + direction.x * t, y: 14.6 + direction.y * t)
            let path = NSBezierPath()
            path.lineWidth = 0.8
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: base.x - perpendicular.x * 1.2,
                                  y: base.y - perpendicular.y * 1.2))
            path.line(to: NSPoint(x: base.x + perpendicular.x * 1.5,
                                  y: base.y + perpendicular.y * 1.5))
            path.stroke()
        }

        // Brush (crossbar).
        stroke(NSPoint(x: 5.8, y: 9.0), NSPoint(x: 12.2, y: 9.0), 1.5)

        image.unlockFocus()
        image.isTemplate = true
        applicationsGraphic = image
        return image
    }

}

final class Node {
    let id: UUID
    var item: ConfigItem
    weak var parent: Node?
    var children: [Node] = []

    init(item: ConfigItem) {
        self.id = item.id
        self.item = item
        for child in item.children {
            let node = Node(item: child)
            node.parent = self
            children.append(node)
        }
    }

    var isFolder: Bool { item.kind == .folder }
    var isSeparator: Bool { item.kind == .separator }

    func toConfigItem() -> ConfigItem {
        var copy = item
        copy.children = children.map { $0.toConfigItem() }
        return copy
    }
}

final class ConfigStore {
    static let shared = ConfigStore()

    let fileURL: URL
    var extraScanRoots: [String]
    var root: [Node] = []
    var menuStyle: MenuStyle
    var barLabel: String
    var statusItemStyle: StatusItemStyle
    var barGap: Double

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ToolsSpecter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            Self.migrateFromOldLocation(base: base, to: fileURL)
        }

        var loadedRoot: [ConfigItem] = []
        var loadedExtra: [String] = []
        var loadedStyle = MenuStyle.horizontal
        var loadedLabel = "Apps"
        var loadedStatusStyle = StatusItemStyle.iconAndText
        var loadedGap: Double = 0
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let config = try? JSONDecoder().decode(ToolsConfig.self, from: data) {
            loadedRoot = config.root
            loadedExtra = config.extraScanRoots
            loadedStyle = config.menuStyle
            loadedLabel = config.barLabel.trimmingCharacters(in: .whitespaces)
            loadedStatusStyle = config.statusItemStyle
            loadedGap = config.barGap
        }
        extraScanRoots = loadedExtra
        root = loadedRoot.map { Node(item: $0) }
        menuStyle = loadedStyle
        barLabel = loadedLabel
        statusItemStyle = loadedStatusStyle
        barGap = loadedGap

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            root = Self.seedRoot()
            save()
        }
    }

    private static func migrateFromOldLocation(base: URL, to fileURL: URL) {
        let oldFile = base.appendingPathComponent("Toolsdaemon", isDirectory: true)
            .appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: oldFile.path) else { return }
        try? FileManager.default.copyItem(at: oldFile, to: fileURL)
    }

    private static func seedRoot() -> [Node] {
        var items: [ConfigItem] = []
        if let safari = AppScanner.findApplication(named: "Safari") {
            items.append(ConfigItem(kind: .app, title: "Safari", target: safari.path))
        }
        if let settings = AppScanner.findApplication(named: "System Settings") {
            items.append(ConfigItem(kind: .app, title: "System Settings", target: settings.path))
        }
        var officeChildren: [ConfigItem] = []
        if let textEdit = AppScanner.findApplication(named: "TextEdit") {
            officeChildren.append(ConfigItem(kind: .app, title: "TextEdit", target: textEdit.path))
        }
        if let notes = AppScanner.findApplication(named: "Notes") {
            officeChildren.append(ConfigItem(kind: .app, title: "Notes", target: notes.path))
        }
        if !officeChildren.isEmpty {
            items.append(ConfigItem(kind: .folder, title: "Office", children: officeChildren))
        }
        if items.isEmpty {
            items.append(ConfigItem(kind: .folder, title: "Office"))
        }
        return items.map { Node(item: $0) }
    }

    func node(withID id: UUID, in nodes: [Node]? = nil) -> Node? {
        let list = nodes ?? root
        for node in list {
            if node.id == id { return node }
            if let found = node.withID(id) { return found }
        }
        return nil
    }

    func parent(of id: UUID) -> Node? {
        var stack = root
        while let node = stack.popLast() {
            if node.children.contains(where: { $0.id == id }) { return node }
            stack.append(contentsOf: node.children)
        }
        return nil
    }

    func remove(id: UUID) {
        guard let parentNode = parent(of: id) else {
            root.removeAll { $0.id == id }
            return
        }
        parentNode.children.removeAll { $0.id == id }
    }

    func move(_ id: UUID, offset: Int) {
        if let parentNode = parent(of: id) {
            guard let i = parentNode.children.firstIndex(where: { $0.id == id }) else { return }
            let j = i + offset
            guard j >= 0, j < parentNode.children.count else { return }
            let node = parentNode.children.remove(at: i)
            parentNode.children.insert(node, at: j)
        } else {
            guard let i = root.firstIndex(where: { $0.id == id }) else { return }
            let j = i + offset
            guard j >= 0, j < root.count else { return }
            let node = root.remove(at: i)
            root.insert(node, at: j)
        }
        save()
    }

    func isSubtree(_ ancestorID: UUID, contains id: UUID) -> Bool {
        guard let ancestor = node(withID: ancestorID) else { return false }
        return ancestor.subtreeContains(id)
    }

    func reparent(_ id: UUID, intoParentID parentID: UUID?, at requestedIndex: Int) -> Bool {
        guard let moved = node(withID: id) else { return false }

        if let parentID {
            guard let folder = self.node(withID: parentID), folder.isFolder else { return false }
            guard folder.id != id, !isSubtree(id, contains: parentID) else { return false }
        }

        if let oldParent = parent(of: id) {
            oldParent.children.removeAll { $0.id == id }
        } else {
            root.removeAll { $0.id == id }
        }

        let index = requestedIndex < 0 ? Int.max : requestedIndex

        if let parentID, let folder = self.node(withID: parentID) {
            moved.parent = folder
            folder.children.insert(moved, at: min(index, folder.children.count))
        } else {
            moved.parent = nil
            root.insert(moved, at: min(index, root.count))
        }
        return true
    }

    func insert(_ node: Node, intoFolderWithID folderID: UUID?) {
        insert(node, intoParentID: folderID, at: Int.max)
    }

    func insert(_ node: Node, intoParentID parentID: UUID?, at requestedIndex: Int) {
        let index = requestedIndex < 0 ? Int.max : requestedIndex
        if let parentID, let folder = self.node(withID: parentID) {
            guard folder.isFolder else { return }
            node.parent = folder
            folder.children.insert(node, at: min(index, folder.children.count))
        } else {
            node.parent = nil
            root.insert(node, at: min(index, root.count))
        }
    }

    func save() {
        let config = ToolsConfig(
            root: root.map { $0.toConfigItem() },
            extraScanRoots: extraScanRoots,
            menuStyle: menuStyle,
            barLabel: barLabel,
            statusItemStyle: statusItemStyle,
            barGap: barGap
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func addScanRoot(_ path: String) {
        let standardized = (path as NSString).standardizingPath
        guard !extraScanRoots.contains(where: { ($0 as NSString).standardizingPath == standardized }) else { return }
        extraScanRoots.append(standardized)
        save()
    }
}

extension Node {
    func withID(_ id: UUID) -> Node? {
        if self.id == id { return self }
        for child in children {
            if let found = child.withID(id) { return found }
        }
        return nil
    }

    func subtreeContains(_ id: UUID) -> Bool {
        if self.id == id { return true }
        return children.contains { $0.subtreeContains(id) }
    }
}
