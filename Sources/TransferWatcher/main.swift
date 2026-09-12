import AppKit
import Foundation

struct WatchedFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var path: String
    var enabled: Bool
    var bookmark: Data?
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

final class SyncController: @unchecked Sendable {
    let destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("TRANSFER MAC M3 14", isDirectory: true)
    var onStatus: ((String) -> Void)?
    var onFoldersChanged: (([WatchedFolder]) -> Void)?

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "salon.das.jogaprom3.sync", qos: .utility)
    private let defaultsKey = "watchedFolders.v1"
    private var timer: DispatchSourceTimer?
    private var folders: [WatchedFolder]
    private var knownFiles = Set<String>()
    private var securityScopedURLs: [UUID: URL] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([WatchedFolder].self, from: data) {
            folders = saved
        } else {
            folders = [WatchedFolder(id: UUID(), path: fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path, enabled: true, bookmark: nil)]
        }
        restoreSecurityScopedAccess()
    }

    func start() {
        queue.async {
            do {
                try self.fileManager.createDirectory(at: self.destination, withIntermediateDirectories: true)
                self.knownFiles = Set(self.candidateFiles().map(\.path))
                self.publishFolders()
                self.publishStatus("Ativo — esperando arquivo novo")
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
                timer.setEventHandler { [weak self] in self?.transferNewFiles(manual: false) }
                self.timer = timer
                timer.resume()
            } catch {
                self.publishStatus("Erro ao preparar a pasta de destino")
            }
        }
    }

    func snapshot() -> [WatchedFolder] { queue.sync { folders } }

    func addFolders(_ urls: [URL]) {
        queue.async {
            for url in urls {
                let path = url.standardizedFileURL.path
                guard !self.folders.contains(where: { $0.path == path }) else { continue }
                let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                let folder = WatchedFolder(id: UUID(), path: path, enabled: true, bookmark: bookmark)
                self.folders.append(folder)
                _ = url.startAccessingSecurityScopedResource()
                self.securityScopedURLs[folder.id] = url
                self.knownFiles.formUnion(self.files(in: url).map(\.path))
            }
            self.saveAndPublish()
            self.publishStatus("Pasta adicionada — observando agora")
        }
    }

    func remove(id: UUID) {
        queue.async {
            self.securityScopedURLs.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
            self.folders.removeAll { $0.id == id }
            self.saveAndPublish()
        }
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        queue.async {
            guard let index = self.folders.firstIndex(where: { $0.id == id }) else { return }
            self.folders[index].enabled = enabled
            if enabled { self.knownFiles.formUnion(self.files(in: self.folders[index].url).map(\.path)) }
            self.saveAndPublish()
        }
    }

    func scanNow() { queue.async { self.transferNewFiles(manual: true) } }

    private func files(in folder: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return contents.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    private func candidateFiles() -> [URL] {
        let desktopPath = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
        return folders
            .filter { $0.enabled && ($0.path == desktopPath || $0.bookmark != nil) }
            .flatMap { files(in: $0.url) }
    }

    private func transferNewFiles(manual: Bool) {
        let newFiles = candidateFiles().filter { !knownFiles.contains($0.path) }
        guard !newFiles.isEmpty else {
            if manual { publishStatus("Nada novo agora") }
            return
        }

        var copied = 0
        var failed = 0
        for source in newFiles {
            do {
                if isVideo(source), !isStable(source) { continue }
                try fileManager.copyItem(at: source, to: uniqueDestination(for: source))
                knownFiles.insert(source.path)
                copied += 1
            } catch { failed += 1 }
        }
        if copied > 0 && failed == 0 {
            publishStatus("Jogou \(copied) item(ns) pro M3 ✓")
        } else if copied > 0 || failed > 0 {
            publishStatus("Jogou \(copied) • falharam \(failed)")
        }
    }

    private func isVideo(_ url: URL) -> Bool {
        ["mov", "mp4", "m4v", "avi", "mkv"].contains(url.pathExtension.lowercased())
    }

    private func isStable(_ url: URL) -> Bool {
        guard let first = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return false }
        Thread.sleep(forTimeInterval: 0.4)
        guard let second = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return false }
        return first.fileSize == second.fileSize && first.contentModificationDate == second.contentModificationDate
    }

    private func uniqueDestination(for source: URL) -> URL {
        var target = destination.appendingPathComponent(source.lastPathComponent)
        var index = 2
        while fileManager.fileExists(atPath: target.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            target = destination.appendingPathComponent(ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)")
            index += 1
        }
        return target
    }

    private func saveAndPublish() {
        if let data = try? JSONEncoder().encode(folders) { UserDefaults.standard.set(data, forKey: defaultsKey) }
        publishFolders()
    }

    private func restoreSecurityScopedAccess() {
        for index in folders.indices {
            guard let bookmark = folders[index].bookmark else { continue }
            var stale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            folders[index].path = resolved.path
            _ = resolved.startAccessingSecurityScopedResource()
            securityScopedURLs[folders[index].id] = resolved
            if stale {
                folders[index].bookmark = try? resolved.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
        }
    }

    private func publishFolders() {
        let value = folders
        DispatchQueue.main.async { self.onFoldersChanged?(value) }
    }

    private func publishStatus(_ value: String) {
        DispatchQueue.main.async { self.onStatus?(value) }
    }
}

@MainActor
final class ConfigurationWindowController: NSWindowController {
    private let controller: SyncController
    private let rows = NSStackView()
    private let status = NSTextField(labelWithString: "Iniciando…")

    init(controller: SyncController) {
        self.controller = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 470), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "PISCOU, COPIOU"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    func refresh(_ folders: [WatchedFolder]) {
        rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
        if folders.isEmpty {
            let empty = NSTextField(labelWithString: "Nenhuma pasta. Adiciona uma aqui embaixo 👇")
            empty.textColor = .secondaryLabelColor
            rows.addArrangedSubview(empty)
        } else {
            folders.forEach { rows.addArrangedSubview(makeRow($0)) }
        }
    }

    func updateStatus(_ value: String) { status.stringValue = value }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "Piscou numa pasta, copiou.")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Tudo que nascer nas pastas ligadas é copiado automaticamente.")
        subtitle.textColor = .secondaryLabelColor
        let destinationTitle = NSTextField(labelWithString: "DESTINO")
        destinationTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        destinationTitle.textColor = .secondaryLabelColor
        let destination = NSButton(title: "~/TRANSFER MAC M3 14", target: self, action: #selector(openDestination))
        destination.bezelStyle = .inline
        destination.alignment = .left
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10
        let add = NSButton(title: "＋ Adicionar pasta…", target: self, action: #selector(addFolder))
        add.bezelStyle = .rounded
        add.controlSize = .large
        status.textColor = .secondaryLabelColor

        let root = NSStackView(views: [title, subtitle, destinationTitle, destination, separator(), rows, add, status])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            rows.widthAnchor.constraint(equalTo: root.widthAnchor),
            destination.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        refresh(controller.snapshot())
    }

    private func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }

    private func makeRow(_ folder: WatchedFolder) -> NSView {
        let toggle = NSButton(checkboxWithTitle: folder.url.lastPathComponent, target: self, action: #selector(toggleFolder(_:)))
        toggle.state = folder.enabled ? .on : .off
        toggle.identifier = NSUserInterfaceItemIdentifier(folder.id.uuidString)
        toggle.font = .systemFont(ofSize: 15, weight: .medium)
        let path = NSTextField(labelWithString: folder.path)
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let labels = NSStackView(views: [toggle, path])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        let remove = NSButton(title: "−", target: self, action: #selector(removeFolder(_:)))
        remove.identifier = NSUserInterfaceItemIdentifier(folder.id.uuidString)
        remove.bezelStyle = .circular
        let row = NSStackView(views: [labels, remove])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.widthAnchor.constraint(equalToConstant: 620).isActive = true
        return row
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Escolhe as pastas que vão pro M3"
        panel.message = "Desktop, Photo Booth/Originals ou qualquer outra pasta."
        panel.prompt = "Adicionar"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK else { return }
        controller.addFolders(panel.urls)
    }

    @objc private func toggleFolder(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        controller.setEnabled(sender.state == .on, id: id)
    }

    @objc private func removeFolder(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        controller.remove(id: id)
    }

    @objc private func openDestination() { NSWorkspace.shared.open(controller.destination) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = SyncController()
    private var settings: ConfigurationWindowController!
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Iniciando…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = ConfigurationWindowController(controller: controller)
        configureMenu()
        controller.onFoldersChanged = { [weak self] in self?.settings.refresh($0) }
        controller.onStatus = { [weak self] value in
            self?.statusLine.title = value
            self?.settings.updateStatus(value)
        }
        controller.start()
        showSettings()
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.right.circle.fill", accessibilityDescription: "PISCOU, COPIOU")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Configurar pastas…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Abrir TRANSFER MAC M3 14", action: #selector(openDestination), keyEquivalent: "")
        menu.addItem(withTitle: "Verificar agora", action: #selector(scanNow), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
    }
    @objc private func openDestination() { NSWorkspace.shared.open(controller.destination) }
    @objc private func scanNow() { controller.scanNow() }
}

@main
struct JogaProM3Main {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
