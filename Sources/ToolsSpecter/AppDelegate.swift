import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var builder: MenuBuilder!
    private var overlay: MenuBarOverlayController!
    private var editorController: EditorController?
    private var pickerController: AppPickerController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        builder = MenuBuilder(target: self)
        overlay = MenuBarOverlayController()
        overlay.onVisibilityChange = { [weak self] visible in
            self?.statusItem.button?.highlight(visible)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "ToolsSpecter"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        updateStatusItem()
        warmIconCacheSoon()
    }

    /// Loading app icons from disk is the slow part of building a dropdown.
    /// Warm the cache once at launch, one icon per run loop turn.
    private func warmIconCacheSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            var paths: [String] = []
            func walk(_ nodes: [Node]) {
                for node in nodes {
                    if let target = node.item.target,
                       node.item.kind == .app || node.item.kind == .file {
                        paths.append(target)
                    }
                    walk(node.children)
                }
            }
            walk(ConfigStore.shared.root)
            self?.warmIcon(at: 0, paths: paths)
        }
    }

    private func warmIcon(at index: Int, paths: [String]) {
        guard index < paths.count else { return }
        _ = AppScanner.icon(for: paths[index])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            self?.warmIcon(at: index + 1, paths: paths)
        }
    }

    // MARK: - Status item

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let store = ConfigStore.shared

        let label = store.barLabel.isEmpty ? "Apps" : store.barLabel
        button.font = NSFont.menuBarFont(ofSize: 0)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown

        switch store.statusItemStyle {
        case .iconAndText:
            button.title = label
            button.image = IconCatalog.applicationsGlyph()
        case .iconOnly:
            button.title = ""
            button.image = IconCatalog.applicationsGlyph()
        case .textOnly:
            button.title = label
            button.image = nil
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
        let isOptionClick = NSEvent.modifierFlags.contains(.option)
            || (event?.modifierFlags.contains(.option) ?? false)

        let suppressed = overlay.consumeDismissedStatusClick()
        if suppressed {
            return
        }

        if isRightClick {
            overlay.hide()
            popUp(builder.settingsMenu(), from: sender)
            return
        }
        if isOptionClick {
            overlay.hide()
            popUp(builder.statusMenu(), from: sender)
            return
        }

        if ConfigStore.shared.menuStyle == .classic {
            popUp(builder.statusMenu(), from: sender)
        } else {
            overlay.toggle(anchor: sender, event: event)
        }
    }

    private func popUp(_ menu: NSMenu, from button: NSStatusBarButton) {
        // Status item windows have no usable geometry on recent macOS, so anchor
        // menus to the click position instead.
        let mouse = NSEvent.mouseLocation
        menu.popUp(positioning: nil,
                   at: NSPoint(x: mouse.x - 12, y: mouse.y - 8),
                   in: nil)
    }

    // MARK: - Actions

    @objc func launchItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ConfigItem else { return }
        Launcher.open(item)
        if overlay.isOpen {
            // Let the menu finish tracking before tearing the bar down.
            DispatchQueue.main.async { [weak self] in
                self?.overlay.hide()
            }
        }
    }

    @objc func openEditor(_ sender: Any?) {
        if overlay.isOpen {
            overlay.hide()
        }
        NSApp.activate(ignoringOtherApps: true)
        if editorController == nil {
            editorController = EditorController()
        }
        editorController?.show()
    }

    @objc func selectStatusItemStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = StatusItemStyle(rawValue: raw) else { return }
        let store = ConfigStore.shared
        store.statusItemStyle = style
        store.save()
        sender.state = .on
        updateStatusItem()
    }

    @objc func toggleVerticalMenu(_ sender: NSMenuItem) {
        let store = ConfigStore.shared
        store.menuStyle = store.menuStyle == .classic ? .horizontal : .classic
        store.save()
        sender.state = store.menuStyle == .classic ? .on : .off
        updateStatusItem()
        if store.menuStyle == .classic {
            overlay.hide()
        }
    }

    @objc func selectMenuStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = MenuStyle(rawValue: raw) else { return }
        overlay.hide()
        ConfigStore.shared.menuStyle = style
        ConfigStore.shared.save()
        updateStatusItem()
    }

    @objc func renameBarLabel(_ sender: Any?) {
        overlay.hide()
        let store = ConfigStore.shared
        let alert = NSAlert()
        alert.messageText = "Menu Bar Label"
        alert.informativeText = "The word shown in the menu bar. The Status Item setting controls whether the icon, the word, or both are shown."
        alert.alertStyle = .informational
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = store.barLabel
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        store.barLabel = trimmed
        store.save()
        updateStatusItem()
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        let wantEnabled = !LoginItem.isEnabled
        do {
            try LoginItem.setEnabled(wantEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change login item"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        sender.state = LoginItem.isEnabled ? .on : .off
    }
}
