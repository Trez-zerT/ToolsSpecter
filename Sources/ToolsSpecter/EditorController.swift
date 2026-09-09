import AppKit

extension NSPasteboard.PasteboardType {
    static let tdItem = NSPasteboard.PasteboardType("local.toolsspecter.item")
}

final class EditorController: NSObject, NSWindowDelegate,
    NSOutlineViewDataSource, NSOutlineViewDelegate {

    private var window: NSWindow!
    private var outlineView: NSOutlineView!
    private let store = ConfigStore.shared
    private var activePicker: AppPickerController?

    // MARK: - Setup

    override init() {
        super.init()
        buildWindow()
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "ToolsSpecter — Edit menu"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 300)
        self.window = window

        guard let content = window.contentView else { return }

        let addButton = NSButton()
        addButton.title = ""
        addButton.image = menuImage(named: "plus")
        addButton.bezelStyle = .texturedRounded
        addButton.target = self
        addButton.action = #selector(addMenuClicked(_:))

        let addMenu = NSMenu(title: "Add")
        addMenu.addItem(withTitle: "Add App…", action: #selector(addApp(_:)), keyEquivalent: "")
        addMenu.addItem(withTitle: "Add Folder…", action: #selector(addFolder(_:)), keyEquivalent: "")
        addMenu.addItem(withTitle: "Add URL…", action: #selector(addURL(_:)), keyEquivalent: "")
        addMenu.addItem(withTitle: "Add File…", action: #selector(addFile(_:)), keyEquivalent: "")
        addMenu.addItem(withTitle: "Add Shell Tool…", action: #selector(addShell(_:)), keyEquivalent: "")
        addMenu.addItem(.separator())
        addMenu.addItem(withTitle: "Add Separator", action: #selector(addSeparator(_:)), keyEquivalent: "")
        for item in addMenu.items { item.target = self }
        addButton.menu = addMenu

        let renameButton = NSButton(title: "Rename", target: self, action: #selector(renameItem(_:)))
        renameButton.bezelStyle = .rounded
        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeItem(_:)))
        removeButton.bezelStyle = .rounded
        let upButton = NSButton(title: "↑", target: self, action: #selector(moveUp(_:)))
        upButton.bezelStyle = .rounded
        let downButton = NSButton(title: "↓", target: self, action: #selector(moveDown(_:)))
        downButton.bezelStyle = .rounded
        upButton.toolTip = "Move up"
        downButton.toolTip = "Move down"

        let hint = NSTextField(labelWithString: "New items are added into the selected folder, or to the top level when no folder is selected.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let topBar = NSStackView(views: [addButton, renameButton, removeButton, upButton, downButton, spacer, hint])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8
        topBar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(topBar)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        outlineView = NSOutlineView()
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowHeight = 24
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.allowsEmptySelection = true
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.registerForDraggedTypes([.tdItem, .fileURL])
        outlineView.autosaveExpandedItems = false

        let scroll = NSScrollView()
        scroll.documentView = outlineView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            topBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 0),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: 0),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 0)
        ])

        scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    func show() {
        guard let window else { return }
        reloadData(expandAll: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Outline data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? Node { return node.children.count }
        return store.root.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? Node { return node.children[index] }
        return store.root[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let id = NSUserInterfaceItemIdentifier("itemCell")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id

            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image

            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text

            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 20),
                image.heightAnchor.constraint(equalToConstant: 20),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let itemConfig = node.item
        if node.isSeparator {
            cell.imageView?.image = nil
            cell.textField?.stringValue = "———————————"
            cell.textField?.textColor = .tertiaryLabelColor
        } else {
            var icon = Launcher.icon(for: itemConfig)
            if icon == nil, let folderSymbol = menuImage(named: "folder") {
                icon = folderSymbol
            }
            cell.imageView?.image = icon
            cell.imageView?.contentTintColor = itemConfig.kind == .folder ? .controlAccentColor : nil
            cell.textField?.stringValue = itemConfig.title.isEmpty ? "(untitled)" : itemConfig.title
            cell.textField?.textColor = .labelColor
        }
        return cell
    }

    // MARK: - Drag & drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? Node else { return nil }
        let pbItem = NSPasteboardItem()
        pbItem.setString(node.id.uuidString, forType: .tdItem)
        return pbItem
    }

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        let pb = info.draggingPasteboard

        if let idString = pb.string(forType: .tdItem), let id = UUID(uuidString: idString) {
            guard store.node(withID: id) != nil else { return [] }
            if let proposed = item as? Node {
                guard proposed.isFolder, proposed.id != id else { return [] }
                if store.isSubtree(id, contains: proposed.id) { return [] }
            }
            return .move
        }

        if let urls = droppedFileURLs(pb), !urls.isEmpty {
            return .copy
        }

        return []
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        let pb = info.draggingPasteboard

        if let idString = pb.string(forType: .tdItem), let id = UUID(uuidString: idString) {
            guard store.node(withID: id) != nil else { return false }
            let parentID = (item as? Node)?.id
            guard store.reparent(id, intoParentID: parentID, at: index) else { return false }
            store.save()
            reloadData(expandAll: true)
            select(nodeWithID: id)
            return true
        }

        guard let urls = droppedFileURLs(pb), !urls.isEmpty else { return false }
        let (parentID, base) = dropLocation(item: item, childIndex: index)
        var added = 0
        for url in urls {
            guard let configItem = configItem(forDroppedURL: url) else { continue }
            let node = Node(item: configItem)
            store.insert(node, intoParentID: parentID, at: base + added)
            added += 1
        }
        guard added > 0 else { return false }
        store.save()
        reloadData(expandAll: true)
        return true
    }

    private func droppedFileURLs(_ pb: NSPasteboard) -> [URL]? {
        pb.readObjects(forClasses: [NSURL.self],
                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
    }

    private func dropLocation(item: Any?, childIndex: Int) -> (parentID: UUID?, index: Int) {
        if let node = item as? Node {
            if node.isFolder {
                return (node.id, childIndex < 0 ? node.children.count : childIndex)
            }
            if let parent = store.parent(of: node.id),
               let i = parent.children.firstIndex(where: { $0.id == node.id }) {
                return (parent.id, i + 1)
            }
            if let i = store.root.firstIndex(where: { $0.id == node.id }) {
                return (nil, i + 1)
            }
        }
        if childIndex < 0 {
            return (nil, store.root.count)
        }
        return (nil, childIndex)
    }

    private func configItem(forDroppedURL url: URL) -> ConfigItem? {
        let path = url.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        if url.pathExtension.lowercased() == "app" {
            let display = AppScanner.displayName(at: path) ?? url.deletingPathExtension().lastPathComponent
            return ConfigItem(kind: .app, title: display, target: path)
        }
        guard !isDir.boolValue else { return nil }
        return ConfigItem(kind: .file, title: url.lastPathComponent, target: path)
    }

    // MARK: - Mutations

    private func selectedFolderID() -> UUID? {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node, node.isFolder else { return nil }
        return node.id
    }

    private func insert(_ configItem: ConfigItem, into folderID: UUID? = nil) {
        let resolvedFolder = folderID ?? selectedFolderID()
        let node = Node(item: configItem)
        store.insert(node, intoFolderWithID: resolvedFolder)
        store.save()
        reloadData(expandAll: true)
        if let resolvedFolder {
            select(nodeWithID: resolvedFolder)
        }
    }

    @objc private func addApp(_ sender: Any?) {
        let folderID = selectedFolderID()
        let picker = AppPickerController()
        activePicker = picker
        picker.onPick = { [weak self] app in
            self?.activePicker = nil
            self?.insert(ConfigItem(kind: .app, title: app.name, target: app.path), into: folderID)
        }
        picker.showAsSheet(on: window)
    }

    @objc private func addFolder(_ sender: Any?) {
        let folderID = selectedFolderID()
        guard let name = prompt(title: "New Folder", message: "Folder name:", initial: "New Folder"), !name.isEmpty else { return }
        insert(ConfigItem(kind: .folder, title: name), into: folderID)
    }

    @objc private func addURL(_ sender: Any?) {
        let folderID = selectedFolderID()
        guard let url = prompt(title: "Add URL", message: "URL:", initial: "https://"), !url.isEmpty else { return }
        let title = prompt(title: "Add URL", message: "Menu title (optional):", initial: "") ?? ""
        let display = title.isEmpty ? url : title
        insert(ConfigItem(kind: .url, title: display, target: url), into: folderID)
    }

    @objc private func addFile(_ sender: Any?) {
        let folderID = selectedFolderID()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        if url.pathExtension.lowercased() == "app" {
            let display = AppScanner.displayName(at: path) ?? url.deletingPathExtension().lastPathComponent
            insert(ConfigItem(kind: .app, title: display, target: path), into: folderID)
        } else {
            insert(ConfigItem(kind: .file, title: url.lastPathComponent, target: path), into: folderID)
        }
    }

    @objc private func addShell(_ sender: Any?) {
        let folderID = selectedFolderID()
        guard let command = prompt(title: "Shell Tool", message: "Command:", initial: ""), !command.isEmpty else { return }
        let title = prompt(title: "Shell Tool", message: "Menu title:", initial: command) ?? command
        insert(ConfigItem(kind: .shell, title: title, target: command), into: folderID)
    }

    @objc private func addSeparator(_ sender: Any?) {
        let folderID = selectedFolderID()
        insert(ConfigItem(kind: .separator, title: ""), into: folderID)
    }

    @objc private func renameItem(_ sender: Any?) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node, !node.isSeparator else { return }
        guard let newName = prompt(title: "Rename", message: "New title:", initial: node.item.title), !newName.isEmpty else { return }
        node.item.title = newName
        store.save()
        reloadData(expandAll: true)
    }

    @objc private func removeItem(_ sender: Any?) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return }
        store.remove(id: node.id)
        store.save()
        reloadData(expandAll: true)
    }

    @objc private func moveUp(_ sender: Any?) {
        moveSelected(offset: -1)
    }

    @objc private func moveDown(_ sender: Any?) {
        moveSelected(offset: 1)
    }

    private func moveSelected(offset: Int) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return }
        let id = node.id
        store.move(id, offset: offset)
        reloadData(expandAll: true)
        select(nodeWithID: id)
    }

    // MARK: - Popup

    @objc private func addMenuClicked(_ sender: NSButton) {
        guard let menu = sender.menu else { return }
        let point = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    // MARK: - Helpers

    private func prompt(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespaces)
    }

    private func reloadData(expandAll: Bool) {
        outlineView.reloadData()
        if expandAll {
            expand(node: nil)
        }
    }

    private func expand(node: Node?) {
        if let node {
            if node.isFolder && !node.children.isEmpty {
                outlineView.expandItem(node)
            }
            for child in node.children { expand(node: child) }
        } else {
            for child in store.root { expand(node: child) }
        }
    }

    private func select(nodeWithID id: UUID) {
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? Node, node.id == id else { continue }
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
            return
        }
    }
}
