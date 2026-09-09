import AppKit
import Foundation

struct InstalledApp {
    let name: String
    let path: String
}

enum AppScanner {
    static var cached: [InstalledApp]?

    static func scan() -> [InstalledApp] {
        if let cached { return cached }
        var roots = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        let homeApps = NSHomeDirectory() + "/Apps"
        if FileManager.default.fileExists(atPath: homeApps) {
            roots.append(homeApps)
        }
        roots.append(contentsOf: ConfigStore.shared.extraScanRoots)

        var dict: [String: InstalledApp] = [:]
        for root in roots {
            collect(from: root, depth: 0, into: &dict)
        }

        let found = dict.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cached = found
        return found
    }

    private static func collect(from dir: String, depth: Int, into dict: inout [String: InstalledApp]) {
        guard depth <= 8 else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for entry in entries where !entry.hasPrefix(".") {
            let path = dir + "/" + entry
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            if entry.hasSuffix(".app") {
                let display = displayName(at: path) ?? String(entry.dropLast(4))
                dict[(path as NSString).standardizingPath] = InstalledApp(name: display, path: path)
                continue
            }
            if isDir.boolValue {
                collect(from: path, depth: depth + 1, into: &dict)
            }
        }
    }

    static func refresh() {
        cached = nil
        _ = scan()
    }

    static func displayName(at path: String) -> String? {
        guard let bundle = Bundle(path: path) else { return nil }
        let preferred = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
        let display = bundle.infoDictionary?["CFBundleDisplayName"] as? String
        let name = bundle.infoDictionary?["CFBundleName"] as? String
        return preferred ?? display ?? name
    }

    static func findApplication(named name: String) -> InstalledApp? {
        scan().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func icon(for path: String) -> NSImage? {
        let image = NSWorkspace.shared.icon(forFile: path)
        return image
    }
}
