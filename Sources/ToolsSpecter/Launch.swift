import AppKit
import Foundation

enum Launcher {
    static func open(_ item: ConfigItem) {
        switch item.kind {
        case .app:
            openApp(item)
        case .file:
            openFile(item)
        case .url:
            openURL(item)
        case .shell:
            runShell(item)
        case .folder, .separator:
            break
        }
    }

    static func icon(for item: ConfigItem) -> NSImage? {
        switch item.kind {
        case .folder:
            return symbol("folder", fallback: nil)
        case .url:
            return symbol("globe", fallback: nil)
        case .file:
            if let path = item.target, FileManager.default.fileExists(atPath: path) {
                return AppScanner.icon(for: path)
            }
            return symbol("doc", fallback: nil)
        case .shell:
            return symbol("terminal", fallback: nil)
        case .separator:
            return nil
        case .app:
            guard let path = item.target, FileManager.default.fileExists(atPath: path) else {
                return symbol("questionmark.app", fallback: nil)
            }
            return AppScanner.icon(for: path)
        }
    }

    private static func symbol(_ name: String, fallback: NSImage?) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? fallback
    }

    private static func openApp(_ item: ConfigItem) {
        var path: String?
        if let target = item.target, FileManager.default.fileExists(atPath: target) {
            path = target
        }
        if path == nil, let resolved = AppScanner.findApplication(named: item.title) {
            path = resolved.path
        }
        guard let path else {
            NSSound.beep()
            return
        }
        let url = URL(fileURLWithPath: path)
        let ok = NSWorkspace.shared.open(url)
        if !ok { NSSound.beep() }
    }

    private static func openFile(_ item: ConfigItem) {
        guard let path = item.target else { NSSound.beep(); return }
        let url = URL(fileURLWithPath: path)
        if !NSWorkspace.shared.open(url) { NSSound.beep() }
    }

    private static func openURL(_ item: ConfigItem) {
        guard let raw = item.target,
              let url = URL(string: raw) else { NSSound.beep(); return }
        if !NSWorkspace.shared.open(url) { NSSound.beep() }
    }

    private static func runShell(_ item: ConfigItem) {
        guard let command = item.target, !command.isEmpty else { NSSound.beep(); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        do {
            try process.run()
        } catch {
            NSSound.beep()
        }
    }
}

func menuImage(named systemName: String) -> NSImage? {
    guard let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else { return nil }
    image.isTemplate = true
    return image
}
