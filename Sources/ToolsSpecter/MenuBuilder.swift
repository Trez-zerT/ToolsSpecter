import AppKit

/// Builds the launcher menus from the config tree. Shared by the classic
/// status-item menu and the horizontal menu bar overlay so both stay in sync.
final class MenuBuilder: NSObject {

    weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
        super.init()
    }

    // MARK: - Launcher tree

    private func append(_ node: Node, to menu: NSMenu) {
        if node.isSeparator {
            menu.addItem(.separator())
            return
        }
        let item = node.item
        let mi = NSMenuItem(title: item.title.isEmpty ? "(untitled)" : item.title,
                            action: node.isFolder ? nil : #selector(AppDelegate.launchItem(_:)),
                            keyEquivalent: "")
        if !node.isFolder {
            mi.target = target
            mi.representedObject = item
        }
        if let icon = Launcher.icon(for: item) {
            mi.image = icon
            mi.image?.size = NSSize(width: 16, height: 16)
        }
        if node.isFolder {
            let submenu = NSMenu(title: item.title)
            for child in node.children {
                append(child, to: submenu)
            }
            mi.submenu = submenu
        }
        menu.addItem(mi)
    }

    // MARK: - Status menus

    /// The full classic menu: launcher tree, settings, quit.
    func statusMenu() -> NSMenu {
        let menu = NSMenu()
        for node in ConfigStore.shared.root {
            append(node, to: menu)
        }
        if menu.numberOfItems > 0 {
            menu.addItem(.separator())
        }
        menu.addItem(settingsItem())
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ToolsSpecter",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    /// Settings only, shown on right-click.
    func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        let vertical = NSMenuItem(title: "Use Vertical Menu",
                                  action: #selector(AppDelegate.toggleVerticalMenu(_:)),
                                  keyEquivalent: "")
        vertical.target = target
        vertical.state = ConfigStore.shared.menuStyle == .classic ? .on : .off
        menu.addItem(vertical)
        menu.addItem(.separator())
        menu.addItem(settingsItem())
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ToolsSpecter",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    private func settingsItem() -> NSMenuItem {
        let store = ConfigStore.shared
        let root = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: "")
        root.image = menuImage(named: "gearshape")
        let settings = NSMenu(title: "Settings…")

        let edit = NSMenuItem(title: "Edit Menu…",
                              action: #selector(AppDelegate.openEditor(_:)),
                              keyEquivalent: ",")
        edit.target = target
        edit.image = menuImage(named: "slider.horizontal.3")
        settings.addItem(edit)

        settings.addItem(menuBarItem(store: store))

        let login = NSMenuItem(title: "Open at Login",
                               action: #selector(AppDelegate.toggleLogin(_:)),
                               keyEquivalent: "")
        login.target = target
        login.isEnabled = LoginItem.isInApplications
        login.toolTip = LoginItem.isInApplications ? nil : "Move ToolsSpecter.app to /Applications to enable"
        login.state = LoginItem.isEnabled ? .on : .off
        settings.addItem(login)

        root.submenu = settings
        return root
    }

    private func menuBarItem(store: ConfigStore) -> NSMenuItem {
        let root = NSMenuItem(title: "Menu Bar", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Menu Bar")

        for style in MenuStyle.allCases {
            let mi = NSMenuItem(title: style.label,
                                action: #selector(AppDelegate.selectMenuStyle(_:)),
                                keyEquivalent: "")
            mi.target = target
            mi.representedObject = style.rawValue
            mi.state = (style == store.menuStyle) ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())

        let label = NSMenuItem(title: "Label…",
                               action: #selector(AppDelegate.renameBarLabel(_:)),
                               keyEquivalent: "")
        label.target = target
        menu.addItem(label)

        let styleItem = NSMenuItem(title: "Status Item", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu(title: "Status Item")
        for style in StatusItemStyle.allCases {
            let mi = NSMenuItem(title: style.label,
                                action: #selector(AppDelegate.selectStatusItemStyle(_:)),
                                keyEquivalent: "")
            mi.target = target
            mi.representedObject = style.rawValue
            mi.state = (style == store.statusItemStyle) ? .on : .off
            styleMenu.addItem(mi)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        root.submenu = menu
        return root
    }
}
