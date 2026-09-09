import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var editorController: EditorController?
    private var pickerController: AppPickerController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "ToolsSpecter"
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        item.menu = menu

        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        guard let image = IconCatalog.image(named: ConfigStore.shared.iconName) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let configured = image.withSymbolConfiguration(config) ?? image
        configured.isTemplate = true
        button.image = configured
    }

    // MARK: - Menu building

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        menu.removeAllItems()
        let store = ConfigStore.shared

        for node in store.root {
            append(node: node, to: menu)
        }

        if menu.numberOfItems > 0 {
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: "")
        settingsItem.image = menuImage(named: "gearshape")
        let settingsMenu = NSMenu(title: "Settings…")
        settingsItem.submenu = settingsMenu

        let edit = NSMenuItem(title: "Edit menu…", action: #selector(openEditor(_:)), keyEquivalent: ",")
        edit.target = self
        edit.image = menuImage(named: "slider.horizontal.3")
        settingsMenu.addItem(edit)

        let iconItem = NSMenuItem(title: "Status Icon", action: nil, keyEquivalent: "")
        let iconMenu = NSMenu(title: "Status Icon")
        for name in IconCatalog.all {
            let symbol = IconCatalog.image(named: name)
            let configured = symbol.flatMap { $0.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)) } ?? symbol
            let mi = NSMenuItem(title: displayName(forSymbol: name),
                                action: #selector(selectIcon(_:)),
                                keyEquivalent: "")
            mi.target = self
            mi.representedObject = name
            mi.image = configured
            mi.state = (name == store.iconName) ? .on : .off
            iconMenu.addItem(mi)
        }
        iconItem.submenu = iconMenu
        settingsMenu.addItem(iconItem)

        let login = NSMenuItem(title: "Open at Login",
                               action: #selector(toggleLogin(_:)),
                               keyEquivalent: "")
        login.target = self
        login.isEnabled = LoginItem.isInApplications
        login.toolTip = LoginItem.isInApplications ? nil : "Move ToolsSpecter.app to /Applications to enable"
        login.state = LoginItem.isEnabled ? .on : .off
        settingsMenu.addItem(login)

        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ToolsSpecter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func append(node: Node, to menu: NSMenu) {
        let item = node.item
        if node.isSeparator {
            menu.addItem(.separator())
            return
        }
        let mi = NSMenuItem(title: item.title.isEmpty ? "(untitled)" : item.title,
                            action: node.isFolder ? nil : #selector(launchItem(_:)),
                            keyEquivalent: "")
        if !node.isFolder {
            mi.target = self
            mi.representedObject = item
        }
        if let icon = Launcher.icon(for: item) {
            mi.image = icon
            mi.image?.size = NSSize(width: 16, height: 16)
        }
        if node.isFolder {
            let submenu = NSMenu(title: item.title)
            for child in node.children {
                append(node: child, to: submenu)
            }
            mi.submenu = submenu
        }
        menu.addItem(mi)
    }

    private func displayName(forSymbol name: String) -> String {
        name
    }

    // MARK: - Actions

    @objc private func launchItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ConfigItem else { return }
        Launcher.open(item)
    }

    @objc private func openEditor(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        if editorController == nil {
            editorController = EditorController()
        }
        editorController?.show()
    }

    @objc private func selectIcon(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        ConfigStore.shared.iconName = name
        ConfigStore.shared.save()
        updateStatusIcon()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let wantEnabled = !LoginItem.isEnabled
        do {
            try LoginItem.setEnabled(wantEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change login item"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
        sender.state = LoginItem.isEnabled ? .on : .off
    }
}
