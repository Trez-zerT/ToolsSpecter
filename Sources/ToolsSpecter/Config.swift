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

struct ToolsConfig: Codable {
    var iconName: String
    var root: [ConfigItem]
    var extraScanRoots: [String]

    init(iconName: String = "list.bullet.indent",
         root: [ConfigItem] = [],
         extraScanRoots: [String] = []) {
        self.iconName = iconName
        self.root = root
        self.extraScanRoots = extraScanRoots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "list.bullet.indent"
        root = try c.decodeIfPresent([ConfigItem].self, forKey: .root) ?? []
        extraScanRoots = try c.decodeIfPresent([String].self, forKey: .extraScanRoots) ?? []
    }
}

enum IconCatalog {
    static let all: [String] = [
        "list.bullet.indent",
        "line.3.horizontal",
        "line.3.horizontal.decrease",
        "list.bullet",
        "list.bullet.rectangle",
        "menucard",
        "flowchart",
        "menubar.arrow.down.rectangle"
    ]

    static func image(named name: String) -> NSImage? {
        guard !all.contains(name) else {
            return NSImage(systemSymbolName: name, accessibilityDescription: "ToolsSpecter")
        }
        return NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: "ToolsSpecter")
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
    var iconName: String
    var extraScanRoots: [String]
    var root: [Node] = []

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ToolsSpecter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            Self.migrateFromOldLocation(base: base, to: fileURL)
        }

        let defaults = (iconName: "list.bullet.indent", root: [ConfigItem](), extra: [String]())
        var loaded = defaults
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL),
               let config = try? JSONDecoder().decode(ToolsConfig.self, from: data) {
                loaded = (config.iconName, config.root, config.extraScanRoots)
            }
        }
        iconName = loaded.iconName.isEmpty ? defaults.iconName : loaded.iconName
        extraScanRoots = loaded.extra
        root = loaded.root.map { Node(item: $0) }

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
            iconName: iconName,
            root: root.map { $0.toConfigItem() },
            extraScanRoots: extraScanRoots
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
