import AppKit

final class AppPickerController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    private var apps: [InstalledApp]
    private var filtered: [InstalledApp]
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()
    private let okButton = NSButton(title: "Add", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let scanButton = NSButton(title: "Scan Folder…", target: nil, action: nil)

    var onPick: ((InstalledApp) -> Void)?

    init() {
        apps = AppScanner.scan()
        filtered = apps
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered,
                             defer: false)
        window.title = "Add App"
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        searchField.placeholderString = "Search applications"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.width = 350
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked(_:))

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        okButton.target = self
        okButton.action = #selector(addClicked(_:))
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked(_:))
        scanButton.target = self
        scanButton.action = #selector(scanClicked(_:))
        okButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [scanButton, spacer, cancelButton, okButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            buttons.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    func showAsSheet(on parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("appCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
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
        let app = filtered[row]
        cell.textField?.stringValue = app.name
        let icon = AppScanner.icon(for: app.path)
        cell.imageView?.image = icon
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        okButton.isEnabled = tableView.selectedRow >= 0
    }

    // MARK: - Search

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            filtered = apps
        } else {
            filtered = apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func doubleClicked(_ sender: Any?) {
        if tableView.selectedRow >= 0 { addSelected() }
    }

    @objc private func addClicked(_ sender: Any?) {
        addSelected()
    }

    private func addSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let app = filtered[row]
        window?.sheetParent?.endSheet(window!)
        onPick?(app)
    }

    @objc private func cancelClicked(_ sender: Any?) {
        window?.sheetParent?.endSheet(window!)
    }

    @objc private func scanClicked(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Add a folder to scan for applications (e.g. ~/Apps)"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ConfigStore.shared.addScanRoot(url.path)
        AppScanner.refresh()
        apps = AppScanner.scan()
        searchField.stringValue = ""
        filtered = apps
        tableView.reloadData()
    }
}
