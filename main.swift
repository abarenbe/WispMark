import Cocoa
import Carbon

// MARK: - Note Model
struct Note: Codable, Identifiable {
    let id: UUID
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var workspaces: Set<String>
    var tags: Set<String>

    var title: String {
        // Find first non-empty line
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            // Strip markdown heading prefix and whitespace
            let cleaned = line.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty {
                return String(cleaned.prefix(50))
            }
        }
        return "Untitled"
    }

    var characterCount: Int {
        return content.count
    }

    init(content: String = "", isPinned: Bool = false) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isPinned = isPinned
        self.workspaces = []
        self.tags = []
    }

    // CodingKeys for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, content, createdAt, modifiedAt, isPinned, workspaces, tags
    }

    // Custom decoder for backward compatibility with existing notes
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)

        // Default to empty sets if fields don't exist (backward compatibility)
        workspaces = try container.decodeIfPresent(Set<String>.self, forKey: .workspaces) ?? []
        tags = try container.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
    }
}

// MARK: - Notes Manager
class NotesManager {
    static let shared = NotesManager()
    private let storageKey = "floatmd_notes"
    private let activeNoteKey = "floatmd_active_note"
    private let activeWorkspaceKey = "floatmd_active_workspace"

    var notes: [Note] = []
    var activeNoteId: UUID?
    var activeWorkspace: String? {
        didSet {
            if let workspace = activeWorkspace {
                UserDefaults.standard.set(workspace, forKey: activeWorkspaceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeWorkspaceKey)
            }
        }
    }

    var activeNote: Note? {
        get { notes.first { $0.id == activeNoteId } }
        set {
            if let note = newValue, let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = note
                save()
            }
        }
    }

    init() {
        load()
        if notes.isEmpty {
            let newNote = Note(content: "")
            notes.append(newNote)
            activeNoteId = newNote.id
            save()
        }
        if activeNoteId == nil {
            activeNoteId = notes.first?.id
        }
        // Restore active workspace
        activeWorkspace = UserDefaults.standard.string(forKey: activeWorkspaceKey)
    }

    func createNote() -> Note {
        let note = Note(content: "")
        notes.insert(note, at: 0)
        activeNoteId = note.id
        save()
        return note
    }

    func deleteNote(_ note: Note) {
        // Pinned notes cannot be deleted
        guard !note.isPinned else { return }
        notes.removeAll { $0.id == note.id }
        if activeNoteId == note.id {
            activeNoteId = notes.first?.id
        }
        save()
    }

    func togglePin(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isPinned.toggle()
        save()
    }

    func updateActiveNote(content: String) {
        guard let id = activeNoteId, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].content = content
        notes[index].modifiedAt = Date()
        save()
    }

    func setActiveNote(_ note: Note) {
        activeNoteId = note.id
        UserDefaults.standard.set(note.id.uuidString, forKey: activeNoteKey)
    }

    func searchNotes(_ query: String) -> [Note] {
        if query.isEmpty { return notes }
        let lowercased = query.lowercased()
        return notes.filter { $0.content.lowercased().contains(lowercased) || $0.title.lowercased().contains(lowercased) }
    }

    func findOrCreateNote(byTitle title: String) -> Note {
        // Find existing note by title (case-insensitive)
        let lowercasedTitle = title.lowercased()
        if let existingNote = notes.first(where: { $0.title.lowercased() == lowercasedTitle }) {
            return existingNote
        }
        // Create new note with title as first line
        let note = Note(content: "# \(title)\n\n")
        notes.insert(note, at: 0)
        save()
        return note
    }

    func noteExists(byTitle title: String) -> Bool {
        let lowercasedTitle = title.lowercased()
        return notes.contains { $0.title.lowercased() == lowercasedTitle }
    }

    func getAllTags() -> [String] {
        var tags = Set<String>()
        let tagPattern = try! NSRegularExpression(pattern: "#([a-zA-Z][a-zA-Z0-9_-]*)", options: [])
        for note in notes {
            let range = NSRange(location: 0, length: note.content.utf16.count)
            let matches = tagPattern.matches(in: note.content, options: [], range: range)
            for match in matches {
                if let tagRange = Range(match.range(at: 1), in: note.content) {
                    tags.insert(String(note.content[tagRange]))
                }
            }
        }
        return tags.sorted()
    }

    func searchNotes(query: String, tags: [String]) -> [Note] {
        var results = notes
        // Filter by tags first
        for tag in tags {
            results = results.filter { $0.content.contains("#\(tag)") }
        }
        // Then filter by text query
        if !query.isEmpty {
            let lowercased = query.lowercased()
            results = results.filter { $0.content.lowercased().contains(lowercased) || $0.title.lowercased().contains(lowercased) }
        }
        return results
    }

    func getAllNoteTitles() -> [String] {
        return notes.map { $0.title }.filter { $0 != "Untitled" }
    }

    func getBacklinks(forTitle title: String) -> [Note] {
        // Find all notes that link to this title via [[title]]
        let pattern = "\\[\\[\(NSRegularExpression.escapedPattern(for: title))\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return notes.filter { note in
            let range = NSRange(location: 0, length: note.content.utf16.count)
            return regex.firstMatch(in: note.content, options: [], range: range) != nil
        }
    }

    func updateBacklinks(oldTitle: String, newTitle: String) {
        let pattern = "\\[\\[\(NSRegularExpression.escapedPattern(for: oldTitle))\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        for i in 0..<notes.count {
            let range = NSRange(location: 0, length: notes[i].content.utf16.count)
            notes[i].content = regex.stringByReplacingMatches(in: notes[i].content, options: [], range: range, withTemplate: "[[\(newTitle)]]")
        }
        save()
    }

    // MARK: - Workspace Methods

    func notesForCurrentView() -> [Note] {
        if let workspace = activeWorkspace {
            // In workspace view: return notes in this workspace OR child workspaces OR containing "."
            return notes.filter { note in
                // Check if note contains global workspace "."
                if note.workspaces.contains(".") {
                    return true
                }
                // Check if note is in the current workspace or a child workspace
                return note.workspaces.contains { ws in
                    ws == workspace || ws.hasPrefix(workspace + "/")
                }
            }
        } else {
            // Home view: return notes with empty workspaces + notes containing "."
            return notes.filter { note in
                note.workspaces.isEmpty || note.workspaces.contains(".")
            }
        }
    }

    func setActiveWorkspace(_ workspace: String?) {
        activeWorkspace = workspace
    }

    func getAllWorkspaces() -> [String] {
        var workspaces = Set<String>()
        for note in notes {
            for workspace in note.workspaces {
                workspaces.insert(workspace)
            }
        }
        return workspaces.sorted()
    }

    func addWorkspace(to noteId: UUID, workspace: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[index].workspaces.insert(workspace)
        notes[index].modifiedAt = Date()
        save()
    }

    func removeWorkspace(from noteId: UUID, workspace: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[index].workspaces.remove(workspace)
        notes[index].modifiedAt = Date()
        save()
    }

    func addTag(to noteId: UUID, tag: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[index].tags.insert(tag)
        notes[index].modifiedAt = Date()
        save()
    }

    func removeTag(from noteId: UUID, tag: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[index].tags.remove(tag)
        notes[index].modifiedAt = Date()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        if let id = activeNoteId {
            UserDefaults.standard.set(id.uuidString, forKey: activeNoteKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded.sorted { $0.modifiedAt > $1.modifiedAt }

            // Migration: Parse tags from content for notes that have empty tags field
            migrateTags()
        }
        if let idString = UserDefaults.standard.string(forKey: activeNoteKey),
           let id = UUID(uuidString: idString) {
            activeNoteId = id
        }
    }

    private func migrateTags() {
        // Parse #tags from content and populate tags field for migration
        let tagPattern = try! NSRegularExpression(pattern: "#([a-zA-Z][a-zA-Z0-9_-]*)", options: [])
        var needsSave = false

        for i in 0..<notes.count {
            // Only migrate if tags field is empty (backward compatibility)
            if notes[i].tags.isEmpty {
                let range = NSRange(location: 0, length: notes[i].content.utf16.count)
                let matches = tagPattern.matches(in: notes[i].content, options: [], range: range)

                for match in matches {
                    if let tagRange = Range(match.range(at: 1), in: notes[i].content) {
                        let tag = String(notes[i].content[tagRange])
                        notes[i].tags.insert(tag)
                        needsSave = true
                    }
                }
            }
        }

        if needsSave {
            save()
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: FloatingPanel!
    var statusItem: NSStatusItem!
    var searchField: NSSearchField!
    var currentSearchQuery: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 500),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.setFrameAutosaveName("FloatNoteWindow")
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isFloatingPanel = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        window.hasShadow = true

        window.contentView = MainView(frame: window.contentView!.bounds)
        window.makeKeyAndOrderFront(nil)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Load AppIcon from bundle and resize for menu bar
            if let appIcon = NSImage(named: "AppIcon") {
                appIcon.size = NSSize(width: 18, height: 18)
                appIcon.isTemplate = true  // Adapts to light/dark menu bar
                button.image = appIcon
            } else {
                // Fallback to SF Symbol if AppIcon not found
                button.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "FloatNote")
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Create main menu bar with Edit menu for Undo/Redo support
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        mainMenu.addItem(editMenuItem)

        HotkeyManager.shared.register()
        checkAccessibilityPermissions()
    }

    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !accessEnabled {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Needed"
            alert.informativeText = "To inject text into other apps, FloatNote needs Accessibility permissions."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc func createNewNote() {
        _ = NotesManager.shared.createNote()
        if let mainView = window.contentView as? MainView {
            mainView.loadActiveNote()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func selectNote(_ sender: NSMenuItem) {
        guard let noteId = sender.representedObject as? UUID,
              let note = NotesManager.shared.notes.first(where: { $0.id == noteId }) else { return }
        NotesManager.shared.setActiveNote(note)
        if let mainView = window.contentView as? MainView {
            mainView.loadActiveNote()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Show window when menu opens
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // New Note item
        let newNoteItem = NSMenuItem(title: "New Note", action: #selector(createNewNote), keyEquivalent: "n")
        newNoteItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        menu.addItem(newNoteItem)

        menu.addItem(NSMenuItem.separator())

        // Search field
        searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        searchField.placeholderString = "Search notes..."
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.stringValue = currentSearchQuery
        searchField.delegate = self
        // Fire action on every keystroke
        (searchField.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = true
        (searchField.cell as? NSSearchFieldCell)?.sendsWholeSearchString = false
        let searchItem = NSMenuItem()
        searchItem.view = searchField
        menu.addItem(searchItem)

        menu.addItem(NSMenuItem.separator())

        // Notes list (pinned first, then by modified date)
        var notes = NotesManager.shared.notes.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.modifiedAt > $1.modifiedAt
        }

        // Filter by search query
        if !currentSearchQuery.isEmpty {
            let query = currentSearchQuery.lowercased()

            // Check if searching for a tag (starts with #)
            if query.hasPrefix("#") {
                let tagQuery = String(query.dropFirst())  // Remove the #
                if !tagQuery.isEmpty {
                    // Filter notes that have a tag starting with the query
                    let tagPattern = try? NSRegularExpression(pattern: "#\(NSRegularExpression.escapedPattern(for: tagQuery))[a-zA-Z0-9_-]*", options: .caseInsensitive)
                    notes = notes.filter { note in
                        if let pattern = tagPattern {
                            let range = NSRange(location: 0, length: note.content.utf16.count)
                            return pattern.firstMatch(in: note.content, options: [], range: range) != nil
                        }
                        return false
                    }
                }
            } else {
                // Regular text search
                notes = notes.filter {
                    $0.title.lowercased().contains(query) ||
                    $0.content.lowercased().contains(query)
                }
            }
        }

        let activeId = NotesManager.shared.activeNote?.id

        // Show 5 notes max
        let displayLimit = 5

        if notes.isEmpty && !currentSearchQuery.isEmpty {
            let noResultsItem = NSMenuItem(title: "No results found", action: nil, keyEquivalent: "")
            noResultsItem.isEnabled = false
            menu.addItem(noResultsItem)
        } else {
            for note in notes.prefix(displayLimit) {
                let title = note.title.isEmpty ? "Untitled" : note.title
                let item = NSMenuItem(title: title, action: #selector(selectNote(_:)), keyEquivalent: "")
                item.representedObject = note.id
                if note.id == activeId {
                    item.state = .on
                }
                if note.isPinned {
                    item.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
                }
                menu.addItem(item)
            }
        }

        // Quit
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FloatNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuDidClose(_ menu: NSMenu) {
        currentSearchQuery = ""
    }

    @objc func searchChanged(_ sender: NSSearchField) {
        currentSearchQuery = sender.stringValue
        rebuildMenuItems()
    }

    private func rebuildMenuItems() {
        guard let menu = statusItem.menu else { return }

        // Remove all items except New Note (first) and separator (second) and search field (third)
        while menu.items.count > 3 {
            menu.removeItem(at: 3)
        }

        menu.addItem(NSMenuItem.separator())

        // Notes list (pinned first, then by modified date)
        var notes = NotesManager.shared.notes.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.modifiedAt > $1.modifiedAt
        }

        // Filter by search query
        if !currentSearchQuery.isEmpty {
            let query = currentSearchQuery.lowercased()

            // Check if searching for a tag (starts with #)
            if query.hasPrefix("#") {
                let tagQuery = String(query.dropFirst())
                if !tagQuery.isEmpty {
                    let tagPattern = try? NSRegularExpression(pattern: "#\(NSRegularExpression.escapedPattern(for: tagQuery))[a-zA-Z0-9_-]*", options: .caseInsensitive)
                    notes = notes.filter { note in
                        if let pattern = tagPattern {
                            let range = NSRange(location: 0, length: note.content.utf16.count)
                            return pattern.firstMatch(in: note.content, options: [], range: range) != nil
                        }
                        return false
                    }
                }
            } else {
                notes = notes.filter {
                    $0.title.lowercased().contains(query) ||
                    $0.content.lowercased().contains(query)
                }
            }
        }

        let activeId = NotesManager.shared.activeNote?.id
        let displayLimit = 5

        if notes.isEmpty && !currentSearchQuery.isEmpty {
            let noResultsItem = NSMenuItem(title: "No results found", action: nil, keyEquivalent: "")
            noResultsItem.isEnabled = false
            menu.addItem(noResultsItem)
        } else {
            for note in notes.prefix(displayLimit) {
                let title = note.title.isEmpty ? "Untitled" : note.title
                let item = NSMenuItem(title: title, action: #selector(selectNote(_:)), keyEquivalent: "")
                item.representedObject = note.id
                if note.id == activeId {
                    item.state = .on
                }
                if note.isPinned {
                    item.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
                }
                menu.addItem(item)
            }
        }

        // Quit
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FloatNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}

extension AppDelegate: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSSearchField {
            currentSearchQuery = field.stringValue
            rebuildMenuItems()
        }
    }
}

// MARK: - Theme
struct Theme {
    let name: String
    let background: NSColor
    let text: NSColor
    let secondaryText: NSColor  // For info labels, dimmed text
    let icon: NSColor  // For buttons and icons
    let syntax: NSColor
    let codeBackground: NSColor
    let blockquote: NSColor
    let link: NSColor
    let checkbox: NSColor
    let checked: NSColor
    let hr: NSColor
    let wikiLink: NSColor
    let wikiLinkMissing: NSColor
    let tag: NSColor
    let tagBackground: NSColor
    let workspaceTag: NSColor
    let workspaceTagBackground: NSColor
    let cursor: NSColor
    let visualEffectMaterial: NSVisualEffectView.Material

    static let dark = Theme(
        name: "Dark",
        background: NSColor(white: 0.1, alpha: 1.0),
        text: .white,
        secondaryText: NSColor(white: 0.6, alpha: 1.0),
        icon: NSColor(white: 0.85, alpha: 1.0),
        syntax: NSColor.white.withAlphaComponent(0.3),
        codeBackground: NSColor.white.withAlphaComponent(0.1),
        blockquote: NSColor(calibratedRed: 0.7, green: 0.7, blue: 0.8, alpha: 1.0),
        link: NSColor(calibratedRed: 0.49, green: 0.30, blue: 1.0, alpha: 1.0),
        checkbox: NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.4, alpha: 1.0),
        checked: NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
        hr: NSColor.white.withAlphaComponent(0.4),
        wikiLink: NSColor(calibratedRed: 0.3, green: 0.7, blue: 0.9, alpha: 1.0),
        wikiLinkMissing: NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.3, alpha: 1.0),
        tag: NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.6, alpha: 1.0),
        tagBackground: NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.6, alpha: 0.15),
        workspaceTag: NSColor(calibratedRed: 0.6, green: 0.5, blue: 0.9, alpha: 1.0),
        workspaceTagBackground: NSColor(calibratedRed: 0.6, green: 0.5, blue: 0.9, alpha: 0.15),
        cursor: .white,
        visualEffectMaterial: .hudWindow
    )

    static let light = Theme(
        name: "Light",
        background: NSColor(white: 0.98, alpha: 1.0),
        text: NSColor(white: 0.1, alpha: 1.0),
        secondaryText: NSColor(white: 0.45, alpha: 1.0),
        icon: NSColor(white: 0.3, alpha: 1.0),
        syntax: NSColor(white: 0.4, alpha: 0.6),
        codeBackground: NSColor(white: 0.0, alpha: 0.06),
        blockquote: NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.45, alpha: 1.0),
        link: NSColor(calibratedRed: 0.15, green: 0.1, blue: 0.75, alpha: 1.0),
        checkbox: NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.15, alpha: 1.0),
        checked: NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
        hr: NSColor.black.withAlphaComponent(0.35),
        wikiLink: NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.65, alpha: 1.0),
        wikiLinkMissing: NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.15, alpha: 1.0),
        tag: NSColor(calibratedRed: 0.15, green: 0.5, blue: 0.35, alpha: 1.0),
        tagBackground: NSColor(calibratedRed: 0.15, green: 0.5, blue: 0.35, alpha: 0.15),
        workspaceTag: NSColor(calibratedRed: 0.4, green: 0.3, blue: 0.7, alpha: 1.0),
        workspaceTagBackground: NSColor(calibratedRed: 0.4, green: 0.3, blue: 0.7, alpha: 0.12),
        cursor: NSColor(white: 0.15, alpha: 1.0),
        visualEffectMaterial: .sheet
    )

    static let nord = Theme(
        name: "Nord",
        background: NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.29, alpha: 1.0),  // Nord polar night #2E3440
        text: NSColor(calibratedRed: 0.92, green: 0.93, blue: 0.94, alpha: 1.0),  // Nord snow storm #ECEFF4
        secondaryText: NSColor(calibratedRed: 0.62, green: 0.67, blue: 0.74, alpha: 1.0),  // Nord #9DA7B8
        icon: NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.87, alpha: 1.0),  // Nord snow storm lighter
        syntax: NSColor(calibratedRed: 0.44, green: 0.51, blue: 0.60, alpha: 1.0),  // Nord polar night #4C566A
        codeBackground: NSColor(calibratedRed: 0.23, green: 0.28, blue: 0.35, alpha: 1.0),  // Nord polar night #3B4252
        blockquote: NSColor(calibratedRed: 0.51, green: 0.63, blue: 0.76, alpha: 1.0),  // Nord frost #81A1C1
        link: NSColor(calibratedRed: 0.53, green: 0.75, blue: 0.82, alpha: 1.0),  // Nord frost #88C0D0
        checkbox: NSColor(calibratedRed: 0.64, green: 0.75, blue: 0.55, alpha: 1.0),  // Nord aurora green #A3BE8C
        checked: NSColor(calibratedRed: 0.44, green: 0.51, blue: 0.60, alpha: 1.0),
        hr: NSColor(calibratedRed: 0.44, green: 0.51, blue: 0.60, alpha: 1.0),
        wikiLink: NSColor(calibratedRed: 0.56, green: 0.74, blue: 0.73, alpha: 1.0),  // Nord frost #8FBCBB
        wikiLinkMissing: NSColor(calibratedRed: 0.75, green: 0.62, blue: 0.53, alpha: 1.0),  // Nord aurora orange
        tag: NSColor(calibratedRed: 0.70, green: 0.56, blue: 0.68, alpha: 1.0),  // Nord aurora purple
        tagBackground: NSColor(calibratedRed: 0.70, green: 0.56, blue: 0.68, alpha: 0.18),
        workspaceTag: NSColor(calibratedRed: 0.51, green: 0.63, blue: 0.76, alpha: 1.0),  // Nord frost #81A1C1
        workspaceTagBackground: NSColor(calibratedRed: 0.51, green: 0.63, blue: 0.76, alpha: 0.18),
        cursor: NSColor(calibratedRed: 0.85, green: 0.87, blue: 0.91, alpha: 1.0),
        visualEffectMaterial: .hudWindow
    )

    static let solarized = Theme(
        name: "Solarized",
        background: NSColor(calibratedRed: 0.0, green: 0.17, blue: 0.21, alpha: 1.0),  // Solarized base03 #002b36
        text: NSColor(calibratedRed: 0.58, green: 0.63, blue: 0.63, alpha: 1.0),  // Solarized base0 #839496
        secondaryText: NSColor(calibratedRed: 0.46, green: 0.53, blue: 0.56, alpha: 1.0),  // Solarized base01
        icon: NSColor(calibratedRed: 0.66, green: 0.71, blue: 0.71, alpha: 1.0),  // Solarized base1
        syntax: NSColor(calibratedRed: 0.40, green: 0.48, blue: 0.51, alpha: 1.0),  // Solarized base01 #586e75
        codeBackground: NSColor(calibratedRed: 0.03, green: 0.21, blue: 0.26, alpha: 1.0),  // Solarized base02 #073642
        blockquote: NSColor(calibratedRed: 0.42, green: 0.44, blue: 0.77, alpha: 1.0),  // Solarized violet #6c71c4
        link: NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.82, alpha: 1.0),  // Solarized blue #268bd2
        checkbox: NSColor(calibratedRed: 0.52, green: 0.60, blue: 0.0, alpha: 1.0),  // Solarized green #859900
        checked: NSColor(calibratedRed: 0.40, green: 0.48, blue: 0.51, alpha: 1.0),
        hr: NSColor(calibratedRed: 0.40, green: 0.48, blue: 0.51, alpha: 1.0),
        wikiLink: NSColor(calibratedRed: 0.16, green: 0.63, blue: 0.60, alpha: 1.0),  // Solarized cyan #2aa198
        wikiLinkMissing: NSColor(calibratedRed: 0.80, green: 0.29, blue: 0.09, alpha: 1.0),  // Solarized orange #cb4b16
        tag: NSColor(calibratedRed: 0.83, green: 0.21, blue: 0.51, alpha: 1.0),  // Solarized magenta #d33682
        tagBackground: NSColor(calibratedRed: 0.83, green: 0.21, blue: 0.51, alpha: 0.18),
        workspaceTag: NSColor(calibratedRed: 0.42, green: 0.44, blue: 0.77, alpha: 1.0),  // Solarized violet #6c71c4
        workspaceTagBackground: NSColor(calibratedRed: 0.42, green: 0.44, blue: 0.77, alpha: 0.18),
        cursor: NSColor(calibratedRed: 0.58, green: 0.63, blue: 0.63, alpha: 1.0),
        visualEffectMaterial: .hudWindow
    )

    static let sepia = Theme(
        name: "Sepia",
        background: NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.88, alpha: 1.0),
        text: NSColor(calibratedRed: 0.35, green: 0.28, blue: 0.20, alpha: 1.0),
        secondaryText: NSColor(calibratedRed: 0.55, green: 0.48, blue: 0.40, alpha: 1.0),
        icon: NSColor(calibratedRed: 0.45, green: 0.38, blue: 0.30, alpha: 1.0),
        syntax: NSColor(calibratedRed: 0.55, green: 0.48, blue: 0.40, alpha: 0.5),
        codeBackground: NSColor(calibratedRed: 0.40, green: 0.32, blue: 0.22, alpha: 0.08),
        blockquote: NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.35, alpha: 1.0),
        link: NSColor(calibratedRed: 0.40, green: 0.25, blue: 0.10, alpha: 1.0),
        checkbox: NSColor(calibratedRed: 0.35, green: 0.50, blue: 0.25, alpha: 1.0),
        checked: NSColor(calibratedRed: 0.60, green: 0.55, blue: 0.50, alpha: 1.0),
        hr: NSColor(calibratedRed: 0.50, green: 0.42, blue: 0.32, alpha: 0.4),
        wikiLink: NSColor(calibratedRed: 0.30, green: 0.45, blue: 0.50, alpha: 1.0),
        wikiLinkMissing: NSColor(calibratedRed: 0.65, green: 0.40, blue: 0.25, alpha: 1.0),
        tag: NSColor(calibratedRed: 0.50, green: 0.40, blue: 0.30, alpha: 1.0),
        tagBackground: NSColor(calibratedRed: 0.50, green: 0.40, blue: 0.30, alpha: 0.12),
        workspaceTag: NSColor(calibratedRed: 0.45, green: 0.35, blue: 0.55, alpha: 1.0),
        workspaceTagBackground: NSColor(calibratedRed: 0.45, green: 0.35, blue: 0.55, alpha: 0.12),
        cursor: NSColor(calibratedRed: 0.35, green: 0.28, blue: 0.20, alpha: 1.0),
        visualEffectMaterial: .sheet
    )

    static let allThemes: [Theme] = [.dark, .light, .nord, .solarized, .sepia]
}

// MARK: - Theme Manager
class ThemeManager {
    static let shared = ThemeManager()
    private let storageKey = "floatmd_theme"

    var currentTheme: Theme {
        didSet {
            UserDefaults.standard.set(currentTheme.name, forKey: storageKey)
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

    var onThemeChange: (() -> Void)?

    init() {
        let savedName = UserDefaults.standard.string(forKey: storageKey) ?? "Dark"
        currentTheme = Theme.allThemes.first { $0.name == savedName } ?? .dark
    }

    func setTheme(_ theme: Theme) {
        currentTheme = theme
    }
}

extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
}

// MARK: - Floating Panel
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Draggable Header View
class DraggableHeaderView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

// MARK: - Draggable Title Button
// A button that allows window dragging only - does not trigger any actions
class DraggableTitleButton: NSButton {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let startingPoint = event.locationInWindow

        // Monitor events to decide between click and drag
        // We capture the event stream to delay the decision
        var keepOn = true
        while keepOn {
            guard let nextEvent = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { continue }
            
            if nextEvent.type == .leftMouseUp {
                // Mouse released without significant movement: It's a click!
                if let action = action {
                    NSApp.sendAction(action, to: target, from: self)
                }
                keepOn = false
            } else if nextEvent.type == .leftMouseDragged {
                let currentPoint = nextEvent.locationInWindow
                let distance = hypot(currentPoint.x - startingPoint.x, currentPoint.y - startingPoint.y)
                
                // If moved enough, treat as drag start
                if distance > 5 {
                    // Hand off to system window dragging
                    // We pass the ORIGINAL event to start the drag smoothly
                    window?.performDrag(with: event)
                    keepOn = false
                }
                // If distance <= 5, ignore small movement (jitter) and keep waiting
            }
        }
    }
}

// MARK: - Clickable Text View
// MARK: - Pill Background Layout Manager
class PillBackgroundLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        textStorage.enumerateAttribute(.init("tagPillBackground"), in: charRange, options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

            enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil)!) { rect, _ in
                var pillRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                pillRect = pillRect.insetBy(dx: -3, dy: -1)

                let path = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
                color.setFill()
                path.fill()
            }
        }
    }
}

class ClickableTextView: NSTextView {
    var onCheckboxClick: ((NSRange) -> Void)?
    var onWikiLinkClick: ((String) -> Void)?
    var onTagClick: ((String) -> Void)?
    var onWorkspaceClick: ((String, String) -> Void)?  // (path, editor)
    var onWorkspaceNavigate: ((String) -> Void)?  // Navigate to workspace in browser
    var onEnterPressed: (() -> Bool)?
    var onTabPressed: ((Bool) -> Bool)?  // Bool = isShiftTab
    var onArrowKey: ((Bool) -> Bool)?  // Bool = isDown
    var onEscapePressed: (() -> Bool)?
    var onTextChanged: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Escape key
        if event.keyCode == 53 {
            if let handler = onEscapePressed, handler() { return }
        }
        // Enter key
        if event.keyCode == 36 {
            if let handler = onEnterPressed, handler() { return }
        }
        // Tab key
        if event.keyCode == 48 {
            let isShift = event.modifierFlags.contains(.shift)
            if let handler = onTabPressed, handler(isShift) { return }
        }
        // Down arrow
        if event.keyCode == 125 {
            if let handler = onArrowKey, handler(true) { return }
        }
        // Up arrow
        if event.keyCode == 126 {
            if let handler = onArrowKey, handler(false) { return }
        }
        super.keyDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        onTextChanged?()
    }

    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        onTextChanged?()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        if let storage = textStorage, charIndex < storage.length {
            // Check for checkbox
            if let isCheckbox = storage.attribute(.init("isCheckbox"), at: charIndex, effectiveRange: nil) as? Bool, isCheckbox,
               let checkboxRange = storage.attribute(.init("checkboxRange"), at: charIndex, effectiveRange: nil) as? NSRange {
                onCheckboxClick?(checkboxRange)
                return
            }
            // Check for wiki link
            if let linkTarget = storage.attribute(.init("wikiLinkTarget"), at: charIndex, effectiveRange: nil) as? String {
                onWikiLinkClick?(linkTarget)
                return
            }
            // Check for tag
            if let tagName = storage.attribute(.init("tagName"), at: charIndex, effectiveRange: nil) as? String {
                onTagClick?(tagName)
                return
            }
            // Check for workspace tag (editor links like @vscode[path])
            if let workspacePath = storage.attribute(.init("workspacePath"), at: charIndex, effectiveRange: nil) as? String,
               let workspaceEditor = storage.attribute(.init("workspaceEditor"), at: charIndex, effectiveRange: nil) as? String {
                onWorkspaceClick?(workspacePath, workspaceEditor)
                return
            }
            // Check for workspace navigation pill (@workspace)
            if let workspaceTarget = storage.attribute(.init("workspaceClickTarget"), at: charIndex, effectiveRange: nil) as? String {
                onWorkspaceNavigate?(workspaceTarget)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        if let storage = textStorage, charIndex < storage.length {
            if let isCheckbox = storage.attribute(.init("isCheckbox"), at: charIndex, effectiveRange: nil) as? Bool, isCheckbox {
                NSCursor.pointingHand.set()
                return
            }
            if storage.attribute(.init("wikiLinkTarget"), at: charIndex, effectiveRange: nil) != nil {
                NSCursor.pointingHand.set()
                return
            }
            if storage.attribute(.init("tagName"), at: charIndex, effectiveRange: nil) != nil {
                NSCursor.pointingHand.set()
                return
            }
            if storage.attribute(.init("workspacePath"), at: charIndex, effectiveRange: nil) != nil {
                NSCursor.pointingHand.set()
                return
            }
            if storage.attribute(.init("workspaceClickTarget"), at: charIndex, effectiveRange: nil) != nil {
                NSCursor.pointingHand.set()
                return
            }
        }
        NSCursor.iBeam.set()
        super.mouseMoved(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
}

// MARK: - Helper Functions
func tintedSymbol(_ name: String, color: NSColor) -> NSImage? {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let config = NSImage.SymbolConfiguration(paletteColors: [color])
    return symbol.withSymbolConfiguration(config)
}

// MARK: - Main View
class MainView: NSView, NSTextViewDelegate, NSTextStorageDelegate {
    private var scrollView: NSScrollView!
    private var textView: ClickableTextView!
    private var headerView: NSView!
    private var newNoteButton: NSButton!
    private var titleButton: NSButton!
    private var workspaceIndicatorButton: NSButton!
    private var noteBrowserView: NoteBrowserView?
    private var settingsView: SettingsView?
    private var tagSearchView: TagSearchView?
    private var visualEffectView: NSVisualEffectView!
    private var backgroundView: NSView!
    private var isUpdatingFormatting = false
    private var cursorLine: Int = -1
    private var tagAutocompleteView: TagAutocompleteView?
    private var tagAutocompleteStart: Int = 0  // Position of the # character
    private var workspaceAutocompleteView: WorkspaceAutocompleteView?
    private var workspaceAutocompleteStart: Int = 0  // Position of the @ character
    private var noteLinkAutocompleteView: NoteLinkAutocompleteView?
    private var noteLinkAutocompleteStart: Int = 0  // Position of the [[ characters
    private var previousTitle: String = ""  // Track title for backlink updates
    private var metadataBarView: MetadataBarView!

    private let baseFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    private let h1Font = NSFont.systemFont(ofSize: 28, weight: .bold)
    private let h2Font = NSFont.systemFont(ofSize: 22, weight: .bold)
    private let h3Font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    private let h4Font = NSFont.systemFont(ofSize: 16, weight: .semibold)
    private let h5Font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    private let h6Font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private let hiddenColor = NSColor.clear

    // Theme colors (computed properties)
    private var theme: Theme { ThemeManager.shared.currentTheme }
    private var textColor: NSColor { theme.text }
    private var syntaxColor: NSColor { theme.syntax }
    private var codeBackground: NSColor { theme.codeBackground }
    private var blockquoteColor: NSColor { theme.blockquote }
    private var linkColor: NSColor { theme.link }
    private var checkboxColor: NSColor { theme.checkbox }
    private var checkedColor: NSColor { theme.checked }
    private var hrColor: NSColor { theme.hr }
    private var wikiLinkColor: NSColor { theme.wikiLink }
    private var wikiLinkMissingColor: NSColor { theme.wikiLinkMissing }
    private var tagColor: NSColor { theme.tag }
    private var tagBackground: NSColor { theme.tagBackground }
    private var workspaceTagColor: NSColor { theme.workspaceTag }
    private var workspaceTagBackground: NSColor { theme.workspaceTagBackground }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        loadContent()
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .themeDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func themeDidChange() {
        applyTheme()
        applyMarkdownFormatting()
    }

    private func applyTheme() {
        backgroundView.layer?.backgroundColor = theme.background.cgColor
        visualEffectView.material = theme.visualEffectMaterial
        textView.insertionPointColor = theme.cursor
        textView.typingAttributes = [.font: baseFont, .foregroundColor: textColor]

        // Update button icons with theme color
        newNoteButton.image = tintedSymbol("plus", color: theme.icon)
        titleButton.contentTintColor = theme.text

        // Update workspace indicator styling
        workspaceIndicatorButton.contentTintColor = workspaceTagColor
        workspaceIndicatorButton.bezelColor = workspaceTagBackground
    }

    private func setupUI() {
        wantsLayer = true

        // Solid background view for theme colors
        backgroundView = NSView(frame: bounds)
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = theme.background.cgColor
        backgroundView.autoresizingMask = [.width, .height]
        addSubview(backgroundView)

        // Visual effect view is only used for subtle effects on top of solid background
        visualEffectView = NSVisualEffectView(frame: bounds)
        visualEffectView.material = theme.visualEffectMaterial
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.alphaValue = 0  // Hidden - we use solid backgrounds now
        addSubview(visualEffectView)

        // Header bar
        headerView = DraggableHeaderView(frame: NSRect(x: 0, y: bounds.height - 36, width: bounds.width, height: 36))
        headerView.autoresizingMask = [.width, .minYMargin]
        headerView.wantsLayer = true
        addSubview(headerView)

        newNoteButton = NSButton(frame: NSRect(x: bounds.width - 70, y: 6, width: 28, height: 24))
        newNoteButton.bezelStyle = .inline
        newNoteButton.isBordered = false
        newNoteButton.image = tintedSymbol("plus", color: theme.icon)
        newNoteButton.target = self
        newNoteButton.action = #selector(createNewNote)
        newNoteButton.autoresizingMask = [.minXMargin]
        headerView.addSubview(newNoteButton)

        // Workspace indicator button (adaptive: full path, root, or dot)
        workspaceIndicatorButton = NSButton(frame: NSRect(x: 70, y: 6, width: 0, height: 24))
        workspaceIndicatorButton.bezelStyle = .inline
        workspaceIndicatorButton.isBordered = true
        workspaceIndicatorButton.setButtonType(.momentaryPushIn)
        workspaceIndicatorButton.font = .systemFont(ofSize: 12, weight: .medium)
        workspaceIndicatorButton.target = self
        workspaceIndicatorButton.action = #selector(showWorkspacePicker)
        workspaceIndicatorButton.isHidden = true
        workspaceIndicatorButton.toolTip = ""
        headerView.addSubview(workspaceIndicatorButton)

        // Title button (clickable title that opens browser)
        // Left margin: 70px (to avoid traffic light buttons) + workspace indicator, Right margin: 80px (to avoid newNoteButton)
        titleButton = DraggableTitleButton(frame: NSRect(x: 70, y: 6, width: bounds.width - 150, height: 24))
        titleButton.bezelStyle = .inline
        titleButton.isBordered = false
        titleButton.title = NotesManager.shared.activeNote?.title ?? "Untitled"
        titleButton.alignment = .center
        titleButton.font = .systemFont(ofSize: 14, weight: .medium)
        titleButton.contentTintColor = theme.text
        titleButton.target = self
        titleButton.action = #selector(toggleBrowseNotes)
        titleButton.autoresizingMask = [.width]
        headerView.addSubview(titleButton)

        // Text editor
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 28, width: bounds.width, height: bounds.height - 64))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]

        // Create text system with custom layout manager for pill backgrounds
        let textStorage = NSTextStorage()
        let layoutManager = PillBackgroundLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: scrollView.contentSize.width - 30, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        textView = ClickableTextView(frame: NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height), textContainer: textContainer)
        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 15, height: 15)
        textView.insertionPointColor = theme.cursor
        textView.typingAttributes = [.font: baseFont, .foregroundColor: textColor]
        textView.textStorage?.delegate = self
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)

        textView.onCheckboxClick = { [weak self] range in self?.toggleCheckbox(at: range) }
        textView.onWikiLinkClick = { [weak self] target in self?.navigateToNote(titled: target) }
        textView.onTagClick = { [weak self] tagName in self?.showTagSearch(for: tagName) }
        textView.onWorkspaceClick = { [weak self] path, editor in self?.openWorkspace(path: path, editor: editor) }
        textView.onWorkspaceNavigate = { [weak self] workspace in self?.navigateToWorkspace(workspace) }
        textView.onEnterPressed = { [weak self] in self?.handleEnterKey() ?? false }
        textView.onTabPressed = { [weak self] isShift in self?.handleTabKey(isShift: isShift) ?? false }
        textView.onArrowKey = { [weak self] isDown in self?.handleArrowKey(isDown: isDown) ?? false }
        textView.onEscapePressed = { [weak self] in self?.handleEscapeKey() ?? false }
        textView.onTextChanged = { [weak self] in self?.handleTextChanged() }

        scrollView.documentView = textView
        addSubview(scrollView)

        // Metadata bar at bottom
        metadataBarView = MetadataBarView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 28))
        metadataBarView.autoresizingMask = [.width, .maxYMargin]
        metadataBarView.onMetadataChanged = { [weak self] in
            self?.loadContent()
        }
        addSubview(metadataBarView)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Update text container width to match the scroll view's content width
        if let textContainer = textView?.textContainer {
            let newWidth = scrollView.contentSize.width - 30
            textContainer.containerSize = NSSize(width: newWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        // Update workspace indicator for adaptive display
        updateWorkspaceIndicator()
    }

    @objc private func createNewNote() {
        // Close browser view if open
        if noteBrowserView != nil {
            toggleBrowseNotes()
        }
        saveContent()
        checkForBacklinkUpdates()
        cleanupEmptyNote()
        _ = NotesManager.shared.createNote()
        loadContent()
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        window?.makeFirstResponder(textView)
    }

    private func cleanupEmptyNote() {
        // Auto-delete the current note if it's empty or only whitespace
        // Check the textView content directly to avoid race conditions
        let currentContent = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentContent.isEmpty {
            if let currentId = NotesManager.shared.activeNoteId,
               let note = NotesManager.shared.notes.first(where: { $0.id == currentId }) {
                // Only delete if there's more than one note (keep at least one)
                if NotesManager.shared.notes.count > 1 {
                    NotesManager.shared.deleteNote(note)
                }
            }
        }
    }

    @objc private func toggleBrowseNotes() {
        // Close settings if open
        if let settings = settingsView {
            settings.removeFromSuperview()
            settingsView = nil
        }

        if let browser = noteBrowserView {
            browser.removeFromSuperview()
            noteBrowserView = nil
            scrollView.isHidden = false
        } else {
            saveContent()
            checkForBacklinkUpdates()
            cleanupEmptyNote()
            scrollView.isHidden = true
            let browser = NoteBrowserView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 36))
            browser.autoresizingMask = [.width, .height]
            browser.onSelectNote = { [weak self] note in
                NotesManager.shared.setActiveNote(note)
                self?.loadContent()
                self?.toggleBrowseNotes()
            }
            browser.onDeleteNote = { [weak self] note in
                NotesManager.shared.deleteNote(note)
                browser.reloadNotes()
                if NotesManager.shared.notes.isEmpty {
                    _ = NotesManager.shared.createNote()
                }
                self?.loadContent()
            }
            browser.onPinNote = { note in
                NotesManager.shared.togglePin(note)
                browser.reloadNotes()
            }
            browser.onSettings = { [weak self] in
                self?.toggleBrowseNotes()
                self?.toggleSettings()
            }
            addSubview(browser)
            noteBrowserView = browser
        }
    }

    private func navigateToWorkspace(_ workspace: String) {
        // Set the active workspace and show the browser
        NotesManager.shared.setActiveWorkspace(workspace)
        updateWorkspaceIndicator()

        // If browser is not open, open it
        if noteBrowserView == nil {
            toggleBrowseNotes()
        } else {
            // Refresh the browser to show the new workspace
            noteBrowserView?.reloadNotes()
        }
    }

    @objc private func toggleSettings() {
        // Close other views if open
        if noteBrowserView != nil {
            toggleBrowseNotes()
        }

        if let settings = settingsView {
            settings.removeFromSuperview()
            settingsView = nil
            scrollView.isHidden = false
        } else {
            saveContent()
            scrollView.isHidden = true
            let settings = SettingsView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 36))
            settings.autoresizingMask = [.width, .height]
            settings.onDismiss = { [weak self] in
                self?.toggleSettings()
            }
            addSubview(settings)
            settingsView = settings
        }
    }

    private func handleTabKey(isShift: Bool) -> Bool {
        guard let textStorage = textView.textStorage else { return false }
        let text = textStorage.string
        let cursorPos = textView.selectedRange().location
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
        let currentLine = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)

        let listPatterns = ["^\\t*- \\[([ xX])\\] ", "^\\t*\\[([ xX])\\]", "^\\t*([-*+]) ", "^\\t*\\d+\\. ", "^\\t*> "]
        var isListLine = false
        for pattern in listPatterns {
            if currentLine.range(of: pattern, options: .regularExpression) != nil {
                isListLine = true
                break
            }
        }
        if !isListLine { return false }

        isUpdatingFormatting = true
        if isShift {
            // Outdent - remove leading tab if present
            if currentLine.hasPrefix("\t") {
                textStorage.deleteCharacters(in: NSRange(location: lineRange.location, length: 1))
                textView.setSelectedRange(NSRange(location: max(cursorPos - 1, lineRange.location), length: 0))
            }
        } else {
            // Indent - add tab at line start
            textStorage.insert(NSAttributedString(string: "\t", attributes: [.font: baseFont, .foregroundColor: textColor]), at: lineRange.location)
            textView.setSelectedRange(NSRange(location: cursorPos + 1, length: 0))
        }
        isUpdatingFormatting = false
        saveContent()
        DispatchQueue.main.async { [weak self] in self?.applyMarkdownFormatting() }
        return true
    }

    private func handleEnterKey() -> Bool {
        // If note link autocomplete is showing, confirm selection
        if let autocomplete = noteLinkAutocompleteView, autocomplete.hasResults {
            autocomplete.confirmSelection()
            return true
        }
        // If workspace autocomplete is showing, confirm selection
        if let autocomplete = workspaceAutocompleteView, autocomplete.hasResults {
            autocomplete.confirmSelection()
            return true
        }
        // If tag autocomplete is showing, confirm selection
        if let autocomplete = tagAutocompleteView, autocomplete.hasResults {
            autocomplete.confirmSelection()
            return true
        }

        guard let textStorage = textView.textStorage else { return false }
        let text = textStorage.string
        let cursorPos = textView.selectedRange().location
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
        let currentLine = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)

        var leadingWhitespace = ""
        for char in currentLine {
            if char == "\t" || char == " " { leadingWhitespace.append(char) }
            else { break }
        }
        let trimmedLine = String(currentLine.dropFirst(leadingWhitespace.count))

        var listPrefix: String? = nil
        var contentAfterPrefix: String = ""

        if let match = trimmedLine.range(of: "^- \\[([ xX])\\] ", options: .regularExpression) {
            listPrefix = "- [ ] "
            contentAfterPrefix = String(trimmedLine[match.upperBound...])
        } else if let match = trimmedLine.range(of: "^\\[([ xX])\\]", options: .regularExpression) {
            listPrefix = "[ ] "
            let after = trimmedLine[match.upperBound...]
            contentAfterPrefix = after.hasPrefix(" ") ? String(after.dropFirst()) : String(after)
        } else if let match = trimmedLine.range(of: "^([-*+]) ", options: .regularExpression) {
            listPrefix = String(trimmedLine[match])
            contentAfterPrefix = String(trimmedLine[match.upperBound...])
        } else if let match = trimmedLine.range(of: "^(\\d+)\\. ", options: .regularExpression) {
            if let dotIndex = trimmedLine.firstIndex(of: "."),
               let num = Int(String(trimmedLine[trimmedLine.startIndex..<dotIndex])) {
                listPrefix = "\(num + 1). "
                contentAfterPrefix = String(trimmedLine[match.upperBound...])
            }
        } else if trimmedLine.hasPrefix("> ") {
            listPrefix = "> "
            contentAfterPrefix = String(trimmedLine.dropFirst(2))
        }

        guard let prefix = listPrefix else { return false }

        if contentAfterPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
            let deleteRange = NSRange(location: lineRange.location, length: lineRange.length)
            isUpdatingFormatting = true
            textStorage.replaceCharacters(in: deleteRange, with: "\n")
            textView.setSelectedRange(NSRange(location: lineRange.location + 1, length: 0))
            isUpdatingFormatting = false
            saveContent()
            DispatchQueue.main.async { [weak self] in self?.applyMarkdownFormatting() }
            return true
        }

        let insertText = "\n" + leadingWhitespace + prefix
        isUpdatingFormatting = true
        textView.insertText(insertText, replacementRange: textView.selectedRange())
        isUpdatingFormatting = false
        saveContent()
        DispatchQueue.main.async { [weak self] in self?.applyMarkdownFormatting() }
        return true
    }

    private func toggleCheckbox(at range: NSRange) {
        guard let textStorage = textView.textStorage else { return }
        let text = textStorage.string as NSString
        let checkboxStr = text.substring(with: range)
        isUpdatingFormatting = true
        if checkboxStr == "[ ]" {
            textStorage.replaceCharacters(in: range, with: "[x]")
        } else if checkboxStr == "[x]" || checkboxStr == "[X]" {
            textStorage.replaceCharacters(in: range, with: "[ ]")
        }
        isUpdatingFormatting = false
        saveContent()
        DispatchQueue.main.async { [weak self] in self?.applyMarkdownFormatting() }
    }

    // MARK: - Autocomplete Handling
    private func handleTextChanged() {
        guard !isUpdatingFormatting else { return }
        let text = textView.string
        let cursorPos = textView.selectedRange().location
        let nsText = text as NSString

        // Check for [[ wiki link autocomplete first
        if cursorPos >= 2 {
            // Look backwards for [[
            var bracketPos: Int? = nil
            var filterText = ""
            for i in stride(from: cursorPos - 1, through: 0, by: -1) {
                let char = nsText.substring(with: NSRange(location: i, length: 1))
                if char == "[" && i > 0 {
                    let prevChar = nsText.substring(with: NSRange(location: i - 1, length: 1))
                    if prevChar == "[" {
                        // Found [[
                        bracketPos = i - 1
                        break
                    }
                }
                if char == "]" || char == "\n" {
                    break  // Stop at closing bracket or newline
                }
                filterText = char + filterText
            }

            if let pos = bracketPos {
                noteLinkAutocompleteStart = pos
                showNoteLinkAutocomplete(filter: filterText)
                hideTagAutocomplete()
                return
            }
        }

        // Hide note link autocomplete if no [[ found
        hideNoteLinkAutocomplete()

        // Look for @ at or before cursor (workspace autocomplete)
        if cursorPos > 0 {
            // Find the start of the current "word" (workspace)
            var atPos: Int? = nil
            var filterText = ""
            for i in stride(from: cursorPos - 1, through: 0, by: -1) {
                let char = nsText.substring(with: NSRange(location: i, length: 1))
                if char == "@" {
                    // Check if preceded by whitespace or at line start (valid workspace position)
                    let isAtLineStart = (i == 0) || (nsText.substring(with: NSRange(location: i - 1, length: 1)) == "\n")
                    if isAtLineStart || CharacterSet.whitespaces.contains(Unicode.Scalar(nsText.character(at: i - 1))!) {
                        atPos = i
                        break
                    } else {
                        break  // @ not at word boundary
                    }
                } else if char.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-/.")) ) == nil {
                    break  // Non-workspace character found (allowing / for paths and . for global)
                }
                filterText = char + filterText
            }

            if let pos = atPos {
                workspaceAutocompleteStart = pos
                showWorkspaceAutocomplete(filter: filterText)
                hideTagAutocomplete()
                return
            }
        }

        // Hide workspace autocomplete if no @ found
        hideWorkspaceAutocomplete()

        // Look for # at or before cursor (tag autocomplete)
        if cursorPos > 0 {
            // Find the start of the current "word" (tag)
            var hashPos: Int? = nil
            var filterText = ""
            for i in stride(from: cursorPos - 1, through: 0, by: -1) {
                let char = nsText.substring(with: NSRange(location: i, length: 1))
                if char == "#" {
                    let isAtLineStart = (i == 0) || (nsText.substring(with: NSRange(location: i - 1, length: 1)) == "\n")

                    if isAtLineStart {
                        // At line start - only a heading if followed by space
                        // If we have filter text (letters after #), treat as tag
                        if !filterText.isEmpty {
                            hashPos = i
                        }
                        // If just "#" with no letters yet, don't show autocomplete
                        // (could be start of heading or tag, wait for more input)
                        break
                    }

                    // Mid-line: check if preceded by whitespace (valid tag position)
                    if CharacterSet.whitespaces.contains(Unicode.Scalar(nsText.character(at: i - 1))!) {
                        hashPos = i
                        break
                    } else {
                        break  // # not at word boundary
                    }
                } else if char.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))) == nil {
                    break  // Non-tag character found
                }
                filterText = char + filterText
            }

            if let pos = hashPos {
                tagAutocompleteStart = pos
                showTagAutocomplete(filter: filterText)
                return
            }
        }

        // No valid # found, hide autocomplete
        hideTagAutocomplete()
    }

    // MARK: - Note Link Autocomplete
    private func showNoteLinkAutocomplete(filter: String) {
        let allTitles = NotesManager.shared.getAllNoteTitles()
        if allTitles.isEmpty {
            hideNoteLinkAutocomplete()
            return
        }

        if noteLinkAutocompleteView == nil {
            let autocomplete = NoteLinkAutocompleteView(frame: NSRect(x: 0, y: 0, width: 220, height: 120))
            autocomplete.onSelectTitle = { [weak self] title in
                self?.insertNoteLink(title)
            }
            autocomplete.onDismiss = { [weak self] in
                self?.hideNoteLinkAutocomplete()
            }
            addSubview(autocomplete)
            noteLinkAutocompleteView = autocomplete
        }

        noteLinkAutocompleteView?.updateTitles(allTitles: allTitles, filter: filter)

        if noteLinkAutocompleteView?.hasResults == false {
            hideNoteLinkAutocomplete()
            return
        }

        // Position below cursor
        let cursorRect = textView.firstRect(forCharacterRange: NSRange(location: noteLinkAutocompleteStart, length: 1), actualRange: nil)
        if !cursorRect.isNull {
            let windowRect = window?.convertFromScreen(cursorRect) ?? cursorRect
            let localPoint = convert(windowRect.origin, from: nil)
            noteLinkAutocompleteView?.frame = NSRect(x: max(10, localPoint.x), y: localPoint.y - 125, width: 220, height: 120)
        }
    }

    private func hideNoteLinkAutocomplete() {
        noteLinkAutocompleteView?.removeFromSuperview()
        noteLinkAutocompleteView = nil
    }

    private func insertNoteLink(_ title: String) {
        guard let textStorage = textView.textStorage else { return }
        let cursorPos = textView.selectedRange().location
        // Replace from [[ to cursor with the full link
        let replaceRange = NSRange(location: noteLinkAutocompleteStart, length: cursorPos - noteLinkAutocompleteStart)
        isUpdatingFormatting = true
        textStorage.replaceCharacters(in: replaceRange, with: "[[\(title)]]")
        textView.setSelectedRange(NSRange(location: noteLinkAutocompleteStart + title.count + 4, length: 0))
        isUpdatingFormatting = false
        hideNoteLinkAutocomplete()
        saveContent()
        DispatchQueue.main.async { [weak self] in self?.applyMarkdownFormatting() }
    }

    private func showTagAutocomplete(filter: String) {
        let allTags = NotesManager.shared.getAllTags()
        if allTags.isEmpty {
            hideTagAutocomplete()
            return
        }

        if tagAutocompleteView == nil {
            let autocomplete = TagAutocompleteView(frame: NSRect(x: 0, y: 0, width: 180, height: 120))
            autocomplete.onSelectTag = { [weak self] tag in
                self?.insertTag(tag)
            }
            autocomplete.onDismiss = { [weak self] in
                self?.hideTagAutocomplete()
            }
            addSubview(autocomplete)
            tagAutocompleteView = autocomplete
        }

        tagAutocompleteView?.updateTags(allTags: allTags, filter: filter)

        if tagAutocompleteView?.hasResults == false {
            hideTagAutocomplete()
            return
        }

        // Position below cursor
        let cursorRect = textView.firstRect(forCharacterRange: NSRange(location: tagAutocompleteStart, length: 1), actualRange: nil)
        if !cursorRect.isNull {
            let windowRect = window?.convertFromScreen(cursorRect) ?? cursorRect
            let localPoint = convert(windowRect.origin, from: nil)
            tagAutocompleteView?.frame = NSRect(x: max(10, localPoint.x), y: localPoint.y - 125, width: 180, height: 120)
        }
    }

    private func hideTagAutocomplete() {
        tagAutocompleteView?.removeFromSuperview()
        tagAutocompleteView = nil
    }

    private func insertTag(_ tag: String) {
        guard let textStorage = textView.textStorage else { return }
        let cursorPos = textView.selectedRange().location
        // Replace from # to cursor with the full tag
        let replaceRange = NSRange(location: tagAutocompleteStart, length: cursorPos - tagAutocompleteStart)
        isUpdatingFormatting = true
        textStorage.replaceCharacters(in: replaceRange, with: "#\(tag) ")
        textView.setSelectedRange(NSRange(location: tagAutocompleteStart + tag.count + 2, length: 0))
        isUpdatingFormatting = false
        hideTagAutocomplete()
        saveContent()
        DispatchQueue.main.async { [weak self] in self?.applyMarkdownFormatting() }
    }

    private func showWorkspaceAutocomplete(filter: String) {
        let allWorkspaces = NotesManager.shared.getAllWorkspaces()

        if workspaceAutocompleteView == nil {
            let autocomplete = WorkspaceAutocompleteView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
            autocomplete.onSelectWorkspace = { [weak self] workspace in
                self?.insertWorkspace(workspace)
            }
            autocomplete.onDismiss = { [weak self] in
                self?.hideWorkspaceAutocomplete()
            }
            addSubview(autocomplete)
            workspaceAutocompleteView = autocomplete
        }

        workspaceAutocompleteView?.updateWorkspaces(allWorkspaces: allWorkspaces, filter: filter)

        if workspaceAutocompleteView?.hasResults == false {
            hideWorkspaceAutocomplete()
            return
        }

        // Position below cursor
        let cursorRect = textView.firstRect(forCharacterRange: NSRange(location: workspaceAutocompleteStart, length: 1), actualRange: nil)
        if !cursorRect.isNull {
            let windowRect = window?.convertFromScreen(cursorRect) ?? cursorRect
            let localPoint = convert(windowRect.origin, from: nil)
            workspaceAutocompleteView?.frame = NSRect(x: max(10, localPoint.x), y: localPoint.y - 125, width: 200, height: 120)
        }
    }

    private func hideWorkspaceAutocomplete() {
        workspaceAutocompleteView?.removeFromSuperview()
        workspaceAutocompleteView = nil
    }

    private func insertWorkspace(_ workspace: String) {
        guard let textStorage = textView.textStorage else { return }
        let cursorPos = textView.selectedRange().location
        // Replace from @ to cursor with the full workspace
        let replaceRange = NSRange(location: workspaceAutocompleteStart, length: cursorPos - workspaceAutocompleteStart)
        isUpdatingFormatting = true
        textStorage.replaceCharacters(in: replaceRange, with: "@\(workspace) ")
        textView.setSelectedRange(NSRange(location: workspaceAutocompleteStart + workspace.count + 2, length: 0))
        isUpdatingFormatting = false
        hideWorkspaceAutocomplete()

        // Add workspace to note's metadata
        if let noteId = NotesManager.shared.activeNoteId {
            NotesManager.shared.addWorkspace(to: noteId, workspace: workspace)
        }

        saveContent()
        DispatchQueue.main.async { [weak self] in self?.applyMarkdownFormatting() }
    }

    private func handleArrowKey(isDown: Bool) -> Bool {
        // Check note link autocomplete first
        if let autocomplete = noteLinkAutocompleteView {
            if isDown {
                autocomplete.selectNext()
            } else {
                autocomplete.selectPrevious()
            }
            return true
        }
        // Then check workspace autocomplete
        if let autocomplete = workspaceAutocompleteView {
            if isDown {
                autocomplete.selectNext()
            } else {
                autocomplete.selectPrevious()
            }
            return true
        }
        // Then check tag autocomplete
        guard let autocomplete = tagAutocompleteView else { return false }
        if isDown {
            autocomplete.selectNext()
        } else {
            autocomplete.selectPrevious()
        }
        return true
    }

    private func handleEscapeKey() -> Bool {
        if noteLinkAutocompleteView != nil {
            hideNoteLinkAutocomplete()
            return true
        }
        if workspaceAutocompleteView != nil {
            hideWorkspaceAutocomplete()
            return true
        }
        if tagAutocompleteView != nil {
            hideTagAutocomplete()
            return true
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        saveContent()
        handleTextChanged()
        // Update title button with current note title
        if let note = NotesManager.shared.activeNote {
            titleButton.title = note.title
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let newCursorLine = getCurrentLine()
        if newCursorLine != cursorLine {
            cursorLine = newCursorLine
            applyMarkdownFormatting()
        }
    }

    private func getCurrentLine() -> Int {
        guard let textStorage = textView.textStorage else { return -1 }
        let cursorPos = textView.selectedRange().location
        var line = 0
        for (pos, char) in textStorage.string.enumerated() {
            if pos >= cursorPos { break }
            if char == "\n" { line += 1 }
        }
        return line
    }

    private func getLineRange(forLine lineNum: Int, in text: String) -> NSRange? {
        var currentLine = 0
        var lineStart = text.startIndex
        for (index, char) in text.enumerated() {
            if currentLine == lineNum {
                let start = text.index(text.startIndex, offsetBy: index)
                let endIndex = text[start...].firstIndex(of: "\n") ?? text.endIndex
                return NSRange(start..<endIndex, in: text)
            }
            if char == "\n" {
                currentLine += 1
                if index + 1 < text.count { lineStart = text.index(text.startIndex, offsetBy: index + 1) }
            }
        }
        if currentLine == lineNum { return NSRange(lineStart..<text.endIndex, in: text) }
        return nil
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isUpdatingFormatting else { return }
        DispatchQueue.main.async { [weak self] in self?.applyMarkdownFormatting() }
    }

    private func applyMarkdownFormatting() {
        guard let textStorage = textView.textStorage else { return }
        isUpdatingFormatting = true

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string
        let cursorLineRange = getLineRange(forLine: cursorLine, in: text)

        textStorage.addAttributes([.font: baseFont, .foregroundColor: textColor], range: fullRange)
        textStorage.removeAttribute(.init("isCheckbox"), range: fullRange)
        textStorage.removeAttribute(.init("checkboxRange"), range: fullRange)
        textStorage.removeAttribute(.init("wikiLinkTarget"), range: fullRange)
        textStorage.removeAttribute(.init("tagPillBackground"), range: fullRange)
        textStorage.removeAttribute(.init("tagName"), range: fullRange)
        textStorage.removeAttribute(.init("workspacePath"), range: fullRange)
        textStorage.removeAttribute(.init("workspaceEditor"), range: fullRange)
        textStorage.removeAttribute(.init("workspacePillBackground"), range: fullRange)
        textStorage.removeAttribute(.init("workspaceClickTarget"), range: fullRange)
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        textStorage.removeAttribute(.strikethroughStyle, range: fullRange)
        textStorage.removeAttribute(.underlineStyle, range: fullRange)

        var lineNum = 0
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[lineStart..<lineEnd])
            let lineNSRange = NSRange(lineStart..<lineEnd, in: text)
            formatLine(line, range: lineNSRange, in: textStorage, cursorOnLine: lineNum == cursorLine)
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            lineNum += 1
        }

        applyInlineFormatting(to: textStorage, in: text, cursorLineRange: cursorLineRange)
        isUpdatingFormatting = false
    }

    private func formatLine(_ line: String, range: NSRange, in textStorage: NSTextStorage, cursorOnLine: Bool) {
        let syntaxStyle = cursorOnLine ? syntaxColor : hiddenColor
        var indentLength = 0
        for char in line { if char == "\t" || char == " " { indentLength += 1 } else { break } }
        let trimmedLine = String(line.dropFirst(indentLength))
        let lineStartWithIndent = range.location + indentLength

        // Checkbox [ ] or [x]
        if trimmedLine.range(of: "^\\[([ xX])\\]", options: .regularExpression) != nil {
            let bracketLength = 3
            let hasSpace = trimmedLine.dropFirst(bracketLength).hasPrefix(" ")
            let prefixLength = bracketLength + (hasSpace ? 1 : 0)
            let isChecked = trimmedLine.hasPrefix("[x]") || trimmedLine.hasPrefix("[X]")
            let checkboxRange = NSRange(location: lineStartWithIndent, length: bracketLength)
            textStorage.addAttribute(.init("isCheckbox"), value: true, range: checkboxRange)
            textStorage.addAttribute(.init("checkboxRange"), value: checkboxRange, range: checkboxRange)
            if isChecked {
                textStorage.addAttribute(.foregroundColor, value: checkedColor, range: checkboxRange)
                let contentLength = range.length - indentLength - prefixLength
                if contentLength > 0 {
                    let contentRange = NSRange(location: lineStartWithIndent + prefixLength, length: contentLength)
                    textStorage.addAttribute(.foregroundColor, value: checkedColor, range: contentRange)
                    textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                }
            } else {
                textStorage.addAttribute(.foregroundColor, value: checkboxColor, range: checkboxRange)
            }
            if hasSpace {
                textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: lineStartWithIndent + bracketLength, length: 1))
            }
            return
        }

        // - [ ] checkbox
        if let match = trimmedLine.range(of: "^- \\[([ xX])\\] ", options: .regularExpression) {
            let prefixLength = trimmedLine.distance(from: trimmedLine.startIndex, to: match.upperBound)
            let isChecked = trimmedLine.contains("[x]") || trimmedLine.contains("[X]")
            textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: lineStartWithIndent, length: 2))
            let checkboxRange = NSRange(location: lineStartWithIndent + 2, length: 3)
            textStorage.addAttribute(.init("isCheckbox"), value: true, range: checkboxRange)
            textStorage.addAttribute(.init("checkboxRange"), value: checkboxRange, range: checkboxRange)
            if isChecked {
                textStorage.addAttribute(.foregroundColor, value: checkedColor, range: checkboxRange)
                let contentLength = range.length - indentLength - prefixLength
                if contentLength > 0 {
                    let contentRange = NSRange(location: lineStartWithIndent + prefixLength, length: contentLength)
                    textStorage.addAttribute(.foregroundColor, value: checkedColor, range: contentRange)
                    textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                }
            } else {
                textStorage.addAttribute(.foregroundColor, value: checkboxColor, range: checkboxRange)
            }
            textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: lineStartWithIndent + 5, length: 1))
            return
        }

        // Headings - require "# " followed by actual content, otherwise show the # visibly
        if let match = trimmedLine.range(of: "^(#{1,6}) ", options: .regularExpression) {
            let hashCount = trimmedLine.distance(from: match.lowerBound, to: match.upperBound) - 1
            let contentLength = range.length - indentLength - hashCount - 1
            // Only hide the # if there's actual heading content after it
            if contentLength > 0 {
                let font: NSFont = [h1Font, h2Font, h3Font, h4Font, h5Font, h6Font][min(hashCount - 1, 5)]
                textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: lineStartWithIndent, length: hashCount + 1))
                textStorage.addAttribute(.font, value: font, range: NSRange(location: lineStartWithIndent + hashCount + 1, length: contentLength))
            }
            // If no content, keep # visible so user can see and delete it
        }
        // Blockquote
        else if trimmedLine.hasPrefix("> ") {
            textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: lineStartWithIndent, length: 2))
            let contentLength = range.length - indentLength - 2
            if contentLength > 0 {
                textStorage.addAttribute(.foregroundColor, value: blockquoteColor, range: NSRange(location: lineStartWithIndent + 2, length: contentLength))
            }
        }
        // Unordered list
        else if trimmedLine.range(of: "^([-*+]) ", options: .regularExpression) != nil {
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: NSRange(location: lineStartWithIndent, length: 1))
            textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: lineStartWithIndent + 1, length: 1))
        }
        // Ordered list
        else if let match = trimmedLine.range(of: "^(\\d+)\\. ", options: .regularExpression) {
            let syntaxLength = trimmedLine.distance(from: match.lowerBound, to: match.upperBound)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: NSRange(location: lineStartWithIndent, length: syntaxLength - 1))
            textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: lineStartWithIndent + syntaxLength - 1, length: 1))
        }
        // HR (---)
        else if trimmedLine.range(of: "^-{3,}$", options: .regularExpression) != nil {
            // Create a full-width horizontal rule using strikethrough on extended text
            let hrRange = NSRange(location: lineStartWithIndent, length: range.length - indentLength)

            // Hide the original "---" text completely
            textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: hrRange)
            textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: hrRange)

            // Use strikethrough to create a visual line
            // By adding strikethrough with a thicker font size to padding characters
            // Calculate approximate width needed (use many characters to ensure full width)
            let textViewWidth = textView.bounds.width - textView.textContainerInset.width * 2
            let charWidth = (" " as NSString).size(withAttributes: [.font: baseFont]).width
            let charCount = max(100, Int(textViewWidth / charWidth) + 20)

            // Create a string of spaces that will be styled with strikethrough
            let fullWidthSpaces = String(repeating: " ", count: charCount)

            // Apply the strikethrough to a range that includes padding after the text
            // We'll use a custom NSAttributedStringKey to mark this as an HR line
            // and render it with a strikethrough effect that creates a visual line

            // For now, use strikethrough on the spaces after the HR marker
            // Create attributed string with spaces
            let paddedHR = NSMutableAttributedString(string: fullWidthSpaces)
            paddedHR.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.thick.rawValue, range: NSRange(location: 0, length: fullWidthSpaces.count))
            paddedHR.addAttribute(.strikethroughColor, value: hrColor, range: NSRange(location: 0, length: fullWidthSpaces.count))
            paddedHR.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: fullWidthSpaces.count))
            paddedHR.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: 0, length: fullWidthSpaces.count))

            // Replace the current range with our padded version
            textStorage.replaceCharacters(in: hrRange, with: paddedHR)
        }
    }

    private func applyInlineFormatting(to textStorage: NSTextStorage, in text: String, cursorLineRange: NSRange?) {
        applyPattern("\\*\\*(.+?)\\*\\*|__(.+?)__", to: textStorage, in: text) { range, _ in
            let style = self.isCursorNear(range, cursorLineRange: cursorLineRange) ? self.syntaxColor : self.hiddenColor
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location, length: 2))
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location + range.length - 2, length: 2))
            let contentRange = NSRange(location: range.location + 2, length: range.length - 4)
            if contentRange.length > 0, let font = textStorage.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont {
                textStorage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: contentRange)
            }
        }

        applyPattern("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)", to: textStorage, in: text) { range, _ in
            let style = self.isCursorNear(range, cursorLineRange: cursorLineRange) ? self.syntaxColor : self.hiddenColor
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location, length: 1))
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location + range.length - 1, length: 1))
            let contentRange = NSRange(location: range.location + 1, length: range.length - 2)
            if contentRange.length > 0, let font = textStorage.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont {
                textStorage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: contentRange)
            }
        }

        applyPattern("`([^`]+)`", to: textStorage, in: text) { range, _ in
            let style = self.isCursorNear(range, cursorLineRange: cursorLineRange) ? self.syntaxColor : self.hiddenColor
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location, length: 1))
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location + range.length - 1, length: 1))
            let contentRange = NSRange(location: range.location + 1, length: range.length - 2)
            if contentRange.length > 0 {
                textStorage.addAttribute(.font, value: self.codeFont, range: contentRange)
                textStorage.addAttribute(.backgroundColor, value: self.codeBackground, range: contentRange)
            }
        }

        applyPattern("\\[([^\\]]+)\\]\\(([^)]+)\\)", to: textStorage, in: text) { range, _ in
            let style = self.isCursorNear(range, cursorLineRange: cursorLineRange) ? self.syntaxColor : self.hiddenColor
            textStorage.addAttribute(.foregroundColor, value: style, range: range)
            let str = (text as NSString).substring(with: range)
            if let bracketEnd = str.firstIndex(of: "]") {
                let textLength = str.distance(from: str.startIndex, to: bracketEnd) - 1
                if textLength > 0 {
                    let linkRange = NSRange(location: range.location + 1, length: textLength)
                    textStorage.addAttribute(.foregroundColor, value: self.linkColor, range: linkRange)
                    textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: linkRange)
                }
            }
        }

        applyPattern("~~(.+?)~~", to: textStorage, in: text) { range, _ in
            let style = self.isCursorNear(range, cursorLineRange: cursorLineRange) ? self.syntaxColor : self.hiddenColor
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location, length: 2))
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location + range.length - 2, length: 2))
            let contentRange = NSRange(location: range.location + 2, length: range.length - 4)
            if contentRange.length > 0 {
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }
        }

        // Wiki-style links [[note name]]
        applyPattern("\\[\\[([^\\]]+)\\]\\]", to: textStorage, in: text) { range, match in
            let style = self.isCursorNear(range, cursorLineRange: cursorLineRange) ? self.syntaxColor : self.hiddenColor
            // Hide the brackets
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location, length: 2))
            textStorage.addAttribute(.foregroundColor, value: style, range: NSRange(location: range.location + range.length - 2, length: 2))
            // Style and make clickable the link text
            let contentRange = NSRange(location: range.location + 2, length: range.length - 4)
            if contentRange.length > 0 {
                let linkTarget = (text as NSString).substring(with: contentRange)
                let noteExists = NotesManager.shared.noteExists(byTitle: linkTarget)
                let color = noteExists ? self.wikiLinkColor : self.wikiLinkMissingColor
                textStorage.addAttribute(.foregroundColor, value: color, range: contentRange)
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                textStorage.addAttribute(.init("wikiLinkTarget"), value: linkTarget, range: contentRange)
            }
        }

        // Tags #tagname - must start with letter, can contain letters, numbers, underscore, hyphen
        // Only match tags that are preceded by whitespace (not at start of line to avoid heading confusion)
        // Rendered as pills with rounded background
        applyPattern("(?<=\\s)#([a-zA-Z][a-zA-Z0-9_-]*)", to: textStorage, in: text) { range, match in
            // Extract the tag name (without #)
            if match.numberOfRanges > 1, let tagNameRange = Range(match.range(at: 1), in: text) {
                let tagName = String(text[tagNameRange])
                textStorage.addAttribute(.init("tagName"), value: tagName, range: range)
            }
            textStorage.addAttribute(.foregroundColor, value: self.tagColor, range: range)
            textStorage.addAttribute(.init("tagPillBackground"), value: self.tagBackground, range: range)
        }

        // Workspace names @workspace or @workspace/subworkspace - clickable pills that navigate to workspace browser
        // Matches @. (global) or @word or @word/subword/etc
        applyPattern("(?<=\\s)@(\\.|[a-zA-Z][a-zA-Z0-9_-]*(?:/[a-zA-Z0-9_-]+)*)", to: textStorage, in: text) { range, match in
            // Extract the workspace name (without @)
            if match.numberOfRanges > 1, let workspaceRange = Range(match.range(at: 1), in: text) {
                let workspaceName = String(text[workspaceRange])
                textStorage.addAttribute(.init("workspaceClickTarget"), value: workspaceName, range: range)
            }
            textStorage.addAttribute(.foregroundColor, value: self.workspaceTagColor, range: range)
            textStorage.addAttribute(.init("workspacePillBackground"), value: self.workspaceTagBackground, range: range)
        }

        // Workspace tags @vscode[path], @cursor[path], @anti[path], @workspace[path]
        // Opens the specified path in the corresponding editor
        // Displayed as "(Editor: ProjectName)" pill when cursor is not on line
        applyPattern("@(vscode|cursor|anti|workspace)\\[([^\\]]+)\\]", to: textStorage, in: text) { range, match in
            let cursorOnLine = self.isCursorNear(range, cursorLineRange: cursorLineRange)

            // Extract editor type and path
            if match.numberOfRanges > 2,
               let editorRange = Range(match.range(at: 1), in: text),
               let pathRange = Range(match.range(at: 2), in: text) {
                let editor = String(text[editorRange])
                let path = String(text[pathRange])

                // Store metadata for click handling on the full range
                textStorage.addAttribute(.init("workspacePath"), value: path, range: range)
                textStorage.addAttribute(.init("workspaceEditor"), value: editor, range: range)

                if cursorOnLine {
                    // Show full syntax when editing
                    let syntaxStyle = self.syntaxColor
                    let prefixLength = editor.count + 2  // @ + editor + [
                    let suffixLength = 1  // ]

                    textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: range.location, length: prefixLength))
                    textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: range.location + range.length - suffixLength, length: suffixLength))

                    let pathNSRange = NSRange(location: range.location + prefixLength, length: range.length - prefixLength - suffixLength)
                    textStorage.addAttribute(.foregroundColor, value: self.workspaceTagColor, range: pathNSRange)
                } else {
                    // Display as condensed pill when not editing
                    // Show editor name + project name, hide syntax and directory path
                    // @cursor[/path/to/FloatMD.code-workspace] -> "cursor FloatMD.code-workspace"
                    let projectName = (path as NSString).lastPathComponent

                    // Calculate character positions
                    let atSignRange = NSRange(location: range.location, length: 1)  // @
                    let editorTextRange = NSRange(location: range.location + 1, length: editor.count)  // cursor
                    let openBracketRange = NSRange(location: range.location + 1 + editor.count, length: 1)  // [
                    let closeBracketRange = NSRange(location: range.location + range.length - 1, length: 1)  // ]

                    // Path range (between [ and ])
                    let pathStart = range.location + 1 + editor.count + 1
                    let pathLength = range.length - editor.count - 3  // minus @ editor [ ]

                    // Hide the @ symbol and show ( using the editor's first char position
                    // Actually, we can't change the character, only style it
                    // So let's just hide parts and show the project name nicely

                    // Hide @ and [
                    textStorage.addAttribute(.foregroundColor, value: self.hiddenColor, range: atSignRange)
                    textStorage.addAttribute(.foregroundColor, value: self.hiddenColor, range: openBracketRange)
                    textStorage.addAttribute(.foregroundColor, value: self.hiddenColor, range: closeBracketRange)

                    // Style the editor name
                    textStorage.addAttribute(.foregroundColor, value: self.workspaceTagColor.withAlphaComponent(0.7), range: editorTextRange)

                    // Hide the directory path, show only project name
                    let dirPathLength = path.count - projectName.count
                    if dirPathLength > 0 && pathLength > projectName.count {
                        // Hide directory portion
                        let dirRange = NSRange(location: pathStart, length: dirPathLength)
                        textStorage.addAttribute(.foregroundColor, value: self.hiddenColor, range: dirRange)

                        // Style project name
                        let nameRange = NSRange(location: pathStart + dirPathLength, length: projectName.count)
                        textStorage.addAttribute(.foregroundColor, value: self.workspaceTagColor, range: nameRange)
                        textStorage.addAttribute(.init("workspacePillBackground"), value: self.workspaceTagBackground, range: nameRange)
                    } else {
                        // Show full path styled
                        let fullPathRange = NSRange(location: pathStart, length: pathLength)
                        textStorage.addAttribute(.foregroundColor, value: self.workspaceTagColor, range: fullPathRange)
                        textStorage.addAttribute(.init("workspacePillBackground"), value: self.workspaceTagBackground, range: fullPathRange)
                    }
                }
            }
        }
    }

    private func isCursorNear(_ range: NSRange, cursorLineRange: NSRange?) -> Bool {
        guard let lineRange = cursorLineRange else { return false }
        return NSIntersectionRange(range, lineRange).length > 0
    }

    private func applyPattern(_ pattern: String, to textStorage: NSTextStorage, in text: String, handler: (NSRange, NSTextCheckingResult) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
            handler(match.range, match)
        }
    }

    private func saveContent() {
        NotesManager.shared.updateActiveNote(content: textView.string)
    }

    // Called when switching notes or leaving the title line
    private func checkForBacklinkUpdates() {
        let content = textView.string
        let currentTitle = getCurrentTitle(from: content)
        if !previousTitle.isEmpty && currentTitle != previousTitle && previousTitle != "Untitled" {
            let backlinks = NotesManager.shared.getBacklinks(forTitle: previousTitle)
            if !backlinks.isEmpty {
                showBacklinkUpdateAlert(oldTitle: previousTitle, newTitle: currentTitle, backlinkCount: backlinks.count)
            }
        }
        previousTitle = currentTitle
    }

    private func getCurrentTitle(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let cleaned = line.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty {
                return String(cleaned.prefix(50))
            }
        }
        return "Untitled"
    }

    private func showBacklinkUpdateAlert(oldTitle: String, newTitle: String, backlinkCount: Int) {
        let alert = NSAlert()
        alert.messageText = "Update Links?"
        alert.informativeText = "\(backlinkCount) note\(backlinkCount == 1 ? "" : "s") link to \"\(oldTitle)\". Would you like to update them to point to \"\(newTitle)\"?"
        alert.addButton(withTitle: "Update Links")
        alert.addButton(withTitle: "Keep Old Links")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NotesManager.shared.updateBacklinks(oldTitle: oldTitle, newTitle: newTitle)
        }
    }

    private func loadContent() {
        if let note = NotesManager.shared.activeNote {
            textView.string = note.content
            previousTitle = note.title
            titleButton.title = note.title
            updateWorkspaceIndicator()
            metadataBarView.updateForNote(note)
            applyMarkdownFormatting()
        } else {
            metadataBarView.updateForNote(nil)
        }
    }

    private func updateWorkspaceIndicator() {
        guard let workspace = NotesManager.shared.activeWorkspace else {
            workspaceIndicatorButton.isHidden = true
            titleButton.frame.origin.x = 70
            titleButton.frame.size.width = bounds.width - 150
            return
        }

        workspaceIndicatorButton.isHidden = false

        // Calculate available width for workspace indicator
        let availableWidth = bounds.width - 150  // Total space between traffic lights and + button
        let titleWidth = (titleButton.title as NSString).size(withAttributes: [.font: titleButton.font!]).width
        let spaceForIndicator = availableWidth - titleWidth - 20  // 20px padding between indicator and title

        var displayText = ""
        var buttonWidth: CGFloat = 0

        // Adaptive display based on available space
        if spaceForIndicator < 40 {
            // Very cramped: show colored dot only
            displayText = "●"
            buttonWidth = 30
            workspaceIndicatorButton.toolTip = "[@\(workspace)]"
        } else if spaceForIndicator < 100 {
            // Tight space: show root workspace only
            let root = workspace.components(separatedBy: "/").first ?? workspace
            displayText = "[@\(root)]"
            buttonWidth = (displayText as NSString).size(withAttributes: [.font: workspaceIndicatorButton.font!]).width + 16
            workspaceIndicatorButton.toolTip = "[@\(workspace)]"
        } else {
            // Plenty of space: show full workspace path
            displayText = "[@\(workspace)]"
            buttonWidth = (displayText as NSString).size(withAttributes: [.font: workspaceIndicatorButton.font!]).width + 16
            workspaceIndicatorButton.toolTip = ""
        }

        workspaceIndicatorButton.title = displayText
        workspaceIndicatorButton.frame.size.width = buttonWidth

        // Adjust title button position to make room for workspace indicator
        let indicatorX: CGFloat = 70
        let titleX = indicatorX + buttonWidth + 6  // 6px gap
        workspaceIndicatorButton.frame.origin.x = indicatorX
        titleButton.frame.origin.x = titleX
        titleButton.frame.size.width = bounds.width - titleX - 80
    }

    @objc private func showWorkspacePicker() {
        let menu = NSMenu()

        // Get all workspaces
        let workspaces = NotesManager.shared.getAllWorkspaces().sorted()

        // Add workspace options
        for workspace in workspaces {
            let item = NSMenuItem(title: "[@\(workspace)]", action: #selector(selectWorkspace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = workspace
            item.state = NotesManager.shared.activeWorkspace == workspace ? .on : .off
            menu.addItem(item)
        }

        // Add separator and "Exit to Home" option
        if !workspaces.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        let exitItem = NSMenuItem(title: "Exit to Home", action: #selector(exitWorkspace), keyEquivalent: "")
        exitItem.target = self
        menu.addItem(exitItem)

        // Show menu at button
        let location = NSPoint(x: workspaceIndicatorButton.frame.origin.x,
                              y: workspaceIndicatorButton.frame.origin.y)
        menu.popUp(positioning: nil, at: location, in: headerView)
    }

    @objc private func selectWorkspace(_ sender: NSMenuItem) {
        if let workspace = sender.representedObject as? String {
            NotesManager.shared.setActiveWorkspace(workspace)
            updateWorkspaceIndicator()
        }
    }

    @objc private func exitWorkspace() {
        NotesManager.shared.setActiveWorkspace(nil)
        updateWorkspaceIndicator()
    }

    private func navigateToNote(titled title: String) {
        saveContent()
        checkForBacklinkUpdates()
        let note = NotesManager.shared.findOrCreateNote(byTitle: title)
        NotesManager.shared.setActiveNote(note)
        loadContent()
        window?.makeFirstResponder(textView)
    }

    private func openWorkspace(path: String, editor: String) {
        let resolvedPath = resolvePath(path)

        // Determine which editor to use
        let editorToUse = editor == "workspace" ? InjectionSettings.shared.defaultEditor : editor

        // Build URL scheme based on editor
        let urlString: String
        switch editorToUse {
        case "vscode":
            urlString = "vscode://file\(resolvedPath)"
        case "cursor":
            urlString = "cursor://file\(resolvedPath)"
        case "anti":
            urlString = "antigravity://file\(resolvedPath)"
        default:
            urlString = "vscode://file\(resolvedPath)"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func resolvePath(_ path: String) -> String {
        var resolved = path

        // Expand ~ to home directory
        if resolved.hasPrefix("~") {
            resolved = NSString(string: resolved).expandingTildeInPath
        }
        // Handle relative paths (resolve relative to notes directory)
        else if !resolved.hasPrefix("/") {
            let notesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
            resolved = (notesDir as NSString).appendingPathComponent(resolved)
        }

        return resolved
    }

    private func showTagSearch(for tagName: String) {
        // Close other overlays
        if let browser = noteBrowserView {
            browser.removeFromSuperview()
            noteBrowserView = nil
        }
        if let settings = settingsView {
            settings.removeFromSuperview()
            settingsView = nil
        }
        if let existing = tagSearchView {
            existing.removeFromSuperview()
            tagSearchView = nil
        }

        // Create tag search view
        let searchView = TagSearchView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 36))
        searchView.autoresizingMask = [.width, .height]
        searchView.searchTag(tagName)
        searchView.onSelectNote = { [weak self] note in
            self?.tagSearchView?.removeFromSuperview()
            self?.tagSearchView = nil
            NotesManager.shared.setActiveNote(note)
            self?.loadContent()
            self?.window?.makeFirstResponder(self?.textView)
        }
        searchView.onClose = { [weak self] in
            self?.tagSearchView?.removeFromSuperview()
            self?.tagSearchView = nil
        }
        addSubview(searchView)
        tagSearchView = searchView
    }

    func getContent() -> String { textView.string }

    func getSelectedTextOrContent() -> String {
        let selectedRange = textView.selectedRange()
        if selectedRange.length > 0 {
            // There is a selection, return only the selected text
            let nsText = textView.string as NSString
            return nsText.substring(with: selectedRange)
        } else {
            // No selection, return full content
            return textView.string
        }
    }

    func deleteSelectedTextOrClearContent() {
        let selectedRange = textView.selectedRange()
        if selectedRange.length > 0 {
            // Delete only the selected text - use proper undo-aware method
            if textView.shouldChangeText(in: selectedRange, replacementString: "") {
                textView.replaceCharacters(in: selectedRange, with: "")
                textView.didChangeText()
            }
        } else {
            // Clear the entire note - use proper undo-aware method
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: fullRange, replacementString: "") {
                textView.replaceCharacters(in: fullRange, with: "")
                textView.didChangeText()
            }
        }
        // Save the changes
        NotesManager.shared.updateActiveNote(content: textView.string)
    }

    func loadActiveNote() {
        loadContent()
    }
}

// MARK: - Tag Autocomplete View
class TagAutocompleteView: NSView {
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var tags: [String] = []
    private var filteredTags: [String] = []
    var onSelectTag: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        scrollView = NSScrollView(frame: bounds.insetBy(dx: 2, dy: 2))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(tableClicked)
        tableView.intercellSpacing = NSSize(width: 0, height: 2)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tag"))
        column.width = bounds.width - 20
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        addSubview(scrollView)
    }

    func updateTags(allTags: [String], filter: String) {
        tags = allTags
        if filter.isEmpty {
            filteredTags = tags
        } else {
            let lowercased = filter.lowercased()
            filteredTags = tags.filter { $0.lowercased().hasPrefix(lowercased) }
        }
        tableView.reloadData()
        if !filteredTags.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func selectNext() {
        let current = tableView.selectedRow
        if current < filteredTags.count - 1 {
            tableView.selectRowIndexes(IndexSet(integer: current + 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(current + 1)
        }
    }

    func selectPrevious() {
        let current = tableView.selectedRow
        if current > 0 {
            tableView.selectRowIndexes(IndexSet(integer: current - 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(current - 1)
        }
    }

    func confirmSelection() {
        let row = tableView.selectedRow
        if row >= 0 && row < filteredTags.count {
            onSelectTag?(filteredTags[row])
        }
    }

    @objc private func tableClicked() {
        confirmSelection()
    }

    var hasResults: Bool { !filteredTags.isEmpty }
}

extension TagAutocompleteView: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { filteredTags.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let tag = filteredTags[row]
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 24))

        let label = NSTextField(labelWithString: "#\(tag)")
        label.font = .systemFont(ofSize: 13)
        label.textColor = NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.6, alpha: 1.0)
        label.frame = NSRect(x: 8, y: 2, width: cell.bounds.width - 16, height: 20)
        label.isEditable = false
        label.isSelectable = false
        cell.addSubview(label)

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }
}

// MARK: - Workspace Autocomplete View
class WorkspaceAutocompleteView: NSView {
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var workspaces: [String] = []
    private var filteredWorkspaces: [String] = []
    var onSelectWorkspace: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        scrollView = NSScrollView(frame: bounds.insetBy(dx: 2, dy: 2))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(tableClicked)
        tableView.intercellSpacing = NSSize(width: 0, height: 2)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("workspace"))
        column.width = bounds.width - 20
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        addSubview(scrollView)
    }

    func updateWorkspaces(allWorkspaces: [String], filter: String) {
        // Always include "." for global workspace
        var workspaceList = allWorkspaces
        if !workspaceList.contains(".") {
            workspaceList.insert(".", at: 0)
        }
        workspaces = workspaceList

        if filter.isEmpty {
            filteredWorkspaces = workspaces
        } else {
            let lowercased = filter.lowercased()
            filteredWorkspaces = workspaces.filter { $0.lowercased().hasPrefix(lowercased) }
        }
        tableView.reloadData()
        if !filteredWorkspaces.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func selectNext() {
        let current = tableView.selectedRow
        if current < filteredWorkspaces.count - 1 {
            tableView.selectRowIndexes(IndexSet(integer: current + 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(current + 1)
        }
    }

    func selectPrevious() {
        let current = tableView.selectedRow
        if current > 0 {
            tableView.selectRowIndexes(IndexSet(integer: current - 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(current - 1)
        }
    }

    func confirmSelection() {
        let row = tableView.selectedRow
        if row >= 0 && row < filteredWorkspaces.count {
            onSelectWorkspace?(filteredWorkspaces[row])
        }
    }

    @objc private func tableClicked() {
        confirmSelection()
    }

    var hasResults: Bool { !filteredWorkspaces.isEmpty }
}

extension WorkspaceAutocompleteView: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { filteredWorkspaces.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let workspace = filteredWorkspaces[row]
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 24))

        let label = NSTextField(labelWithString: "@\(workspace)")
        label.font = .systemFont(ofSize: 13)
        label.textColor = NSColor(calibratedRed: 0.6, green: 0.5, blue: 0.9, alpha: 1.0)
        label.frame = NSRect(x: 8, y: 2, width: cell.bounds.width - 16, height: 20)
        label.isEditable = false
        label.isSelectable = false
        cell.addSubview(label)

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }
}

// MARK: - Note Link Autocomplete View
class NoteLinkAutocompleteView: NSView {
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var titles: [String] = []
    private var filteredTitles: [String] = []
    var onSelectTitle: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        scrollView = NSScrollView(frame: bounds.insetBy(dx: 2, dy: 2))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(tableClicked)
        tableView.intercellSpacing = NSSize(width: 0, height: 2)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.width = bounds.width - 20
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        addSubview(scrollView)
    }

    func updateTitles(allTitles: [String], filter: String) {
        titles = allTitles
        if filter.isEmpty {
            filteredTitles = titles
        } else {
            let lowercased = filter.lowercased()
            filteredTitles = titles.filter { $0.lowercased().contains(lowercased) }
        }
        tableView.reloadData()
        if !filteredTitles.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func selectNext() {
        let current = tableView.selectedRow
        if current < filteredTitles.count - 1 {
            tableView.selectRowIndexes(IndexSet(integer: current + 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(current + 1)
        }
    }

    func selectPrevious() {
        let current = tableView.selectedRow
        if current > 0 {
            tableView.selectRowIndexes(IndexSet(integer: current - 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(current - 1)
        }
    }

    func confirmSelection() {
        let row = tableView.selectedRow
        if row >= 0 && row < filteredTitles.count {
            onSelectTitle?(filteredTitles[row])
        }
    }

    @objc private func tableClicked() {
        confirmSelection()
    }

    var hasResults: Bool { !filteredTitles.isEmpty }
}

extension NoteLinkAutocompleteView: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { filteredTitles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let title = filteredTitles[row]
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 24))

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = NSColor(calibratedRed: 0.3, green: 0.7, blue: 0.9, alpha: 1.0)
        label.frame = NSRect(x: 8, y: 2, width: cell.bounds.width - 16, height: 20)
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }
}

// MARK: - Settings View
// MARK: - Hotkey Recorder View
class HotkeyRecorderView: NSTextField {
    var onHotkeyChanged: ((UInt32, UInt32, String) -> Void)?
    private var isRecording = false
    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        isEditable = false
        isSelectable = false
        alignment = .center
        font = .systemFont(ofSize: 12)
        backgroundColor = ThemeManager.shared.currentTheme.background
        textColor = ThemeManager.shared.currentTheme.text
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.3).cgColor
        isBordered = false
        drawsBackground = true
        placeholderString = "Click to record..."
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        stringValue = "Press keys..."
        layer?.borderColor = NSColor.systemBlue.cgColor
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags

        // Convert NSEvent.ModifierFlags to Carbon modifiers
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }

        // Require at least one modifier
        guard modifiers != 0 else {
            return
        }

        currentKeyCode = keyCode
        currentModifiers = modifiers

        // Create display string
        let displayString = formatHotkey(modifiers: modifiers, keyCode: keyCode, event: event)
        stringValue = displayString

        // Finish recording
        isRecording = false
        layer?.borderColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.3).cgColor

        // Notify callback
        onHotkeyChanged?(keyCode, modifiers, displayString)

        // Release first responder
        window?.makeFirstResponder(nil)
    }

    private func formatHotkey(modifiers: UInt32, keyCode: UInt32, event: NSEvent) -> String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Opt") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }

        // Add the key character
        if let characters = event.charactersIgnoringModifiers?.uppercased() {
            parts.append(characters)
        }

        return parts.joined(separator: "+")
    }

    func setHotkey(keyCode: UInt32, modifiers: UInt32, display: String) {
        currentKeyCode = keyCode
        currentModifiers = modifiers
        stringValue = display
    }
}

// MARK: - Tag Search View
class TagSearchView: NSView {
    var onSelectNote: ((Note) -> Void)?
    var onClose: (() -> Void)?

    private var titleLabel: NSTextField!
    private var closeButton: NSButton!
    private var scrollView: NSScrollView!
    private var resultsStackView: NSStackView!
    private var currentTag: String = ""

    struct TagResult {
        let note: Note
        let contextLines: [String]  // Lines containing the tag with context
    }

    private var results: [TagResult] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        let theme = ThemeManager.shared.currentTheme

        wantsLayer = true
        layer?.backgroundColor = theme.background.cgColor

        // Header with title and close button
        let headerHeight: CGFloat = 40

        titleLabel = NSTextField(labelWithString: "#tag")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = theme.text
        titleLabel.frame = NSRect(x: 15, y: bounds.height - headerHeight + 10, width: bounds.width - 60, height: 24)
        titleLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(titleLabel)

        closeButton = NSButton(frame: NSRect(x: bounds.width - 35, y: bounds.height - headerHeight + 8, width: 28, height: 28))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = tintedSymbol("xmark", color: theme.icon)
        closeButton.target = self
        closeButton.action = #selector(closeView)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(closeButton)

        // Scroll view for results
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - headerHeight))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.contentView.drawsBackground = false

        // Stack view to hold result cards
        resultsStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 400))
        resultsStackView.orientation = .vertical
        resultsStackView.alignment = .centerX
        resultsStackView.spacing = 10
        resultsStackView.edgeInsets = NSEdgeInsets(top: 10, left: 15, bottom: 10, right: 15)

        scrollView.documentView = resultsStackView
        addSubview(scrollView)

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .themeDidChange, object: nil)
    }

    @objc private func themeDidChange() {
        let theme = ThemeManager.shared.currentTheme
        layer?.backgroundColor = theme.background.cgColor
        titleLabel.textColor = theme.text
        closeButton.image = tintedSymbol("xmark", color: theme.icon)
        refreshResults()
    }

    @objc private func closeView() {
        onClose?()
    }

    func searchTag(_ tagName: String) {
        currentTag = tagName
        titleLabel.stringValue = "#\(tagName)"

        // Find all notes containing this tag
        results = []

        // Use regex: #tagname followed by non-word-char or end of string
        let pattern = "#\(NSRegularExpression.escapedPattern(for: tagName))(?![a-zA-Z0-9_-])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            refreshResults()
            return
        }

        for note in NotesManager.shared.notes {
            let content = note.content
            let lines = content.components(separatedBy: "\n")
            var contextLines: [String] = []

            for (lineIndex, line) in lines.enumerated() {
                let lineRange = NSRange(location: 0, length: line.utf16.count)
                if regex.firstMatch(in: line, options: [], range: lineRange) != nil {
                    // Build context: line before, current line, line after
                    var context = ""
                    if lineIndex > 0 {
                        context += "..." + String(lines[lineIndex - 1].prefix(60)) + "\n"
                    }
                    context += line
                    if lineIndex < lines.count - 1 {
                        context += "\n" + String(lines[lineIndex + 1].prefix(60)) + "..."
                    }
                    if !contextLines.contains(context) {
                        contextLines.append(context)
                    }
                }
            }

            if !contextLines.isEmpty {
                results.append(TagResult(note: note, contextLines: contextLines))
            }
        }

        refreshResults()
    }
    private func refreshResults() {
        NSLog("FloatNote: refreshResults called with \(results.count) results")

        // Clear existing results
        resultsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let theme = ThemeManager.shared.currentTheme
        let contentWidth = bounds.width - 30

        if results.isEmpty {
            let noResultsLabel = NSTextField(labelWithString: "No notes found with #\(currentTag)")
            noResultsLabel.textColor = theme.secondaryText
            noResultsLabel.font = .systemFont(ofSize: 13)
            resultsStackView.addArrangedSubview(noResultsLabel)
        } else {
            for result in results {
                let card = createResultCard(for: result, theme: theme, width: contentWidth)
                resultsStackView.addArrangedSubview(card)
            }
        }

        // Update stack view frame to fit content
        let fittingHeight = max(resultsStackView.fittingSize.height, 100)
        resultsStackView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: fittingHeight)

        // Make sure scroll view's document view is properly set
        scrollView.documentView = resultsStackView
    }

    private func createResultCard(for result: TagResult, theme: Theme, width: CGFloat) -> NSView {
        // Calculate height based on content
        let cardHeight: CGFloat = 90

        let card = NSView(frame: NSRect(x: 0, y: 0, width: width, height: cardHeight))
        card.wantsLayer = true
        card.layer?.backgroundColor = theme.codeBackground.cgColor
        card.layer?.cornerRadius = 8

        // Title at top
        let titleLabel = NSTextField(labelWithString: result.note.title.isEmpty ? "Untitled" : result.note.title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = theme.text
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 12, y: cardHeight - 30, width: width - 24, height: 20)
        card.addSubview(titleLabel)

        // Context snippet below title
        let contextText = result.contextLines.first ?? ""
        let snippetLabel = NSTextField(labelWithString: contextText)
        snippetLabel.font = .systemFont(ofSize: 11)
        snippetLabel.textColor = theme.secondaryText
        snippetLabel.isBezeled = false
        snippetLabel.isEditable = false
        snippetLabel.drawsBackground = false
        snippetLabel.maximumNumberOfLines = 3
        snippetLabel.lineBreakMode = .byWordWrapping
        snippetLabel.cell?.wraps = true
        snippetLabel.frame = NSRect(x: 12, y: 8, width: width - 24, height: cardHeight - 40)
        card.addSubview(snippetLabel)

        // Make clickable
        let clickArea = ClickableView(frame: card.bounds)
        clickArea.autoresizingMask = [.width, .height]
        clickArea.onClick = { [weak self] in
            self?.onSelectNote?(result.note)
        }
        clickArea.onHover = { hovering in
            card.layer?.backgroundColor = hovering ?
                theme.codeBackground.blending(with: 0.1, of: theme.text)?.cgColor :
                theme.codeBackground.cgColor
        }
        card.addSubview(clickArea)

        // Set intrinsic content size for stack view
        card.setContentHuggingPriority(.defaultHigh, for: .vertical)

        return card
    }
}

// MARK: - Pill Close Button
class PillCloseButton: NSButton {
    var onClose: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClose?()
    }
}

// MARK: - Metadata Bar View
class MetadataBarView: NSView {
    private var tagPillsContainer: NSView!
    private var workspacePillsContainer: NSView!
    private var addButton: NSButton!
    private var currentNote: Note?
    private var autocompleteView: NSView?
    private var autocompleteTextField: NSTextField?

    var onMetadataChanged: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        let theme = ThemeManager.shared.currentTheme

        wantsLayer = true
        layer?.backgroundColor = theme.background.cgColor

        // Container for tag pills (left side)
        tagPillsContainer = NSView(frame: NSRect(x: 10, y: 2, width: bounds.width / 2 - 30, height: 24))
        tagPillsContainer.autoresizingMask = [.width]
        addSubview(tagPillsContainer)

        // Container for workspace pills (right side)
        workspacePillsContainer = NSView(frame: NSRect(x: bounds.width / 2, y: 2, width: bounds.width / 2 - 40, height: 24))
        workspacePillsContainer.autoresizingMask = [.minXMargin, .width]
        addSubview(workspacePillsContainer)

        // Add button (far right)
        addButton = NSButton(frame: NSRect(x: bounds.width - 28, y: 2, width: 24, height: 24))
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.image = tintedSymbol("plus.circle", color: theme.icon)
        addButton.target = self
        addButton.action = #selector(showAddMetadataPopup)
        addButton.autoresizingMask = [.minXMargin]
        addSubview(addButton)

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .themeDidChange, object: nil)
    }

    @objc private func themeDidChange() {
        let theme = ThemeManager.shared.currentTheme
        layer?.backgroundColor = theme.background.cgColor
        addButton.image = tintedSymbol("plus.circle", color: theme.icon)
        updateForNote(currentNote)
    }

    func updateForNote(_ note: Note?) {
        currentNote = note

        // Clear existing pills
        tagPillsContainer.subviews.forEach { $0.removeFromSuperview() }
        workspacePillsContainer.subviews.forEach { $0.removeFromSuperview() }

        guard let note = note else { return }

        let theme = ThemeManager.shared.currentTheme

        // Create tag pills
        var tagX: CGFloat = 0
        for tag in note.tags.sorted() {
            let pill = createPill(
                text: "#\(tag)",
                textColor: theme.tag,
                backgroundColor: theme.tagBackground,
                onRemove: { [weak self] in
                    self?.removeTag(tag)
                }
            )
            pill.frame.origin = CGPoint(x: tagX, y: 0)
            tagPillsContainer.addSubview(pill)
            tagX += pill.frame.width + 6
        }

        // Create workspace pills
        var workspaceX: CGFloat = 0
        for workspace in note.workspaces.sorted() {
            let pill = createPill(
                text: "@\(workspace)",
                textColor: theme.workspaceTag,
                backgroundColor: theme.workspaceTagBackground,
                onRemove: { [weak self] in
                    self?.removeWorkspace(workspace)
                }
            )
            pill.frame.origin = CGPoint(x: workspaceX, y: 0)
            workspacePillsContainer.addSubview(pill)
            workspaceX += pill.frame.width + 6
        }
    }

    private func createPill(text: String, textColor: NSColor, backgroundColor: NSColor, onRemove: @escaping () -> Void) -> NSView {
        // Create pill container
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = backgroundColor.cgColor
        pill.layer?.cornerRadius = 10

        // Create label
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = textColor
        label.frame = NSRect(x: 8, y: 2, width: 0, height: 18)
        label.sizeToFit()

        // Create close button using a clickable NSButton subclass
        let closeButton = PillCloseButton(frame: NSRect(x: label.frame.width + 10, y: 2, width: 16, height: 16))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = tintedSymbol("xmark", color: textColor.withAlphaComponent(0.7))
        closeButton.onClose = onRemove

        // Store the remove action for mouse down fallback
        objc_setAssociatedObject(pill, "removeAction", onRemove as Any, .OBJC_ASSOCIATION_RETAIN)

        // Size the pill
        let totalWidth = label.frame.width + 30
        pill.frame = NSRect(x: 0, y: 0, width: totalWidth, height: 20)
        label.frame.origin.y = 1
        closeButton.frame.origin.y = 2

        pill.addSubview(label)
        pill.addSubview(closeButton)

        return pill
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // Check if click is on any pill's close button area
        for pillContainer in [tagPillsContainer, workspacePillsContainer] {
            guard let container = pillContainer else { continue }
            let containerLocation = container.convert(location, from: self)

            for pill in container.subviews {
                let pillLocation = pill.convert(containerLocation, from: container)
                if pill.bounds.contains(pillLocation) {
                    // Check if it's in the close button area (right side of pill)
                    if pillLocation.x > pill.bounds.width - 24 {
                        if let action = objc_getAssociatedObject(pill, "removeAction") as? () -> Void {
                            action()
                            return
                        }
                    }
                }
            }
        }

        super.mouseDown(with: event)
    }

    private func removeTag(_ tag: String) {
        guard let noteId = currentNote?.id else { return }
        NotesManager.shared.removeTag(from: noteId, tag: tag)
        currentNote = NotesManager.shared.notes.first { $0.id == noteId }
        updateForNote(currentNote)
        onMetadataChanged?()
    }

    private func removeWorkspace(_ workspace: String) {
        guard let noteId = currentNote?.id else { return }
        NotesManager.shared.removeWorkspace(from: noteId, workspace: workspace)
        currentNote = NotesManager.shared.notes.first { $0.id == noteId }
        updateForNote(currentNote)
        onMetadataChanged?()
    }

    @objc private func showAddMetadataPopup() {
        guard currentNote != nil else { return }

        let theme = ThemeManager.shared.currentTheme

        // Create popup view - position ABOVE the metadata bar (y = 28 to place above this view)
        let popupView = NSView(frame: NSRect(x: bounds.width - 220, y: 28, width: 210, height: 100))
        popupView.wantsLayer = true
        popupView.layer?.backgroundColor = theme.background.cgColor
        popupView.layer?.cornerRadius = 8
        popupView.layer?.borderWidth = 1
        popupView.layer?.borderColor = theme.secondaryText.withAlphaComponent(0.3).cgColor

        // Instructions label
        let instructionsLabel = NSTextField(labelWithString: "Type # for tags, @ for workspaces")
        instructionsLabel.font = .systemFont(ofSize: 10)
        instructionsLabel.textColor = theme.secondaryText
        instructionsLabel.frame = NSRect(x: 10, y: 70, width: 190, height: 20)
        instructionsLabel.isEditable = false
        instructionsLabel.isBordered = false
        instructionsLabel.drawsBackground = false
        popupView.addSubview(instructionsLabel)

        // Text field - must be editable
        let textField = NSTextField(frame: NSRect(x: 10, y: 40, width: 190, height: 24))
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: 13)
        textField.textColor = theme.text
        textField.backgroundColor = theme.codeBackground
        textField.focusRingType = .default
        textField.placeholderString = "#tag or @workspace"
        textField.target = self
        textField.action = #selector(addMetadataFromTextField(_:))
        popupView.addSubview(textField)

        // Cancel button
        let cancelButton = NSButton(frame: NSRect(x: 10, y: 10, width: 60, height: 24))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(hideAddMetadataPopup)
        popupView.addSubview(cancelButton)

        // Add button
        let addButtonInPopup = NSButton(frame: NSRect(x: 140, y: 10, width: 60, height: 24))
        addButtonInPopup.title = "Add"
        addButtonInPopup.bezelStyle = .rounded
        addButtonInPopup.keyEquivalent = "\r"
        addButtonInPopup.target = self
        addButtonInPopup.action = #selector(addMetadataFromTextField(_:))
        popupView.addSubview(addButtonInPopup)

        // Add to superview (MainView) instead of self so it's not clipped
        if let mainView = superview {
            // Convert position to MainView coordinates
            let popupOrigin = convert(NSPoint(x: bounds.width - 220, y: bounds.height), to: mainView)
            popupView.frame.origin = popupOrigin
            mainView.addSubview(popupView)
        } else {
            addSubview(popupView)
        }

        autocompleteView = popupView
        autocompleteTextField = textField

        // Make text field first responder after a short delay to ensure window is ready
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(textField)
        }
    }

    @objc private func hideAddMetadataPopup() {
        autocompleteView?.removeFromSuperview()
        autocompleteView = nil
        autocompleteTextField = nil
    }

    @objc private func addMetadataFromTextField(_ sender: Any?) {
        guard let text = autocompleteTextField?.stringValue.trimmingCharacters(in: .whitespaces),
              !text.isEmpty,
              let noteId = currentNote?.id else {
            hideAddMetadataPopup()
            return
        }

        if text.hasPrefix("#") {
            let tag = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            if !tag.isEmpty {
                NotesManager.shared.addTag(to: noteId, tag: tag)
            }
        } else if text.hasPrefix("@") {
            let workspace = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            if !workspace.isEmpty {
                NotesManager.shared.addWorkspace(to: noteId, workspace: workspace)
            }
        } else {
            // Default to tag if no prefix
            NotesManager.shared.addTag(to: noteId, tag: text)
        }

        currentNote = NotesManager.shared.notes.first { $0.id == noteId }
        updateForNote(currentNote)
        onMetadataChanged?()
        hideAddMetadataPopup()
    }
}

// Helper for clickable cards
class ClickableView: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
}

// Extension for color blending
extension NSColor {
    func blending(with amount: CGFloat, of color: NSColor) -> NSColor? {
        guard let c1 = self.usingColorSpace(.deviceRGB),
              let c2 = color.usingColorSpace(.deviceRGB) else { return nil }

        let r = c1.redComponent * (1 - amount) + c2.redComponent * amount
        let g = c1.greenComponent * (1 - amount) + c2.greenComponent * amount
        let b = c1.blueComponent * (1 - amount) + c2.blueComponent * amount
        let a = c1.alphaComponent * (1 - amount) + c2.alphaComponent * amount

        return NSColor(red: r, green: g, blue: b, alpha: a)
    }
}

class SettingsView: NSView {
    var onDismiss: (() -> Void)?
    private var themeButtons: [NSButton] = []
    private var titleLabel: NSTextField!
    private var themeLabel: NSTextField!
    private var injectionLabel: NSTextField!
    private var hotkeyLabel: NSTextField!
    private var hotkeysLabel: NSTextField!
    private var injectionHotkeyLabel: NSTextField!
    private var injectionHotkeyRecorder: HotkeyRecorderView!
    private var toggleHotkeyLabel: NSTextField!
    private var toggleHotkeyRecorder: HotkeyRecorderView!
    private var cutInjectHotkeyLabel: NSTextField!
    private var cutInjectHotkeyRecorder: HotkeyRecorderView!
    private var ignoreTitlesCheckbox: NSButton!
    private var ignoreTagsCheckbox: NSButton!
    private var ignoreLinkFormattingCheckbox: NSButton!
    private var workspaceLabel: NSTextField!
    private var defaultEditorLabel: NSTextField!
    private var defaultEditorPopup: NSPopUpButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = ThemeManager.shared.currentTheme.background.cgColor

        // Title
        titleLabel = NSTextField(labelWithString: "Settings")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = ThemeManager.shared.currentTheme.text
        titleLabel.frame = NSRect(x: 20, y: bounds.height - 50, width: 200, height: 24)
        titleLabel.autoresizingMask = [.minYMargin]
        addSubview(titleLabel)

        // Theme section
        themeLabel = NSTextField(labelWithString: "Theme")
        themeLabel.font = .systemFont(ofSize: 14, weight: .medium)
        themeLabel.textColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.7)
        themeLabel.frame = NSRect(x: 20, y: bounds.height - 90, width: 100, height: 20)
        themeLabel.autoresizingMask = [.minYMargin]
        addSubview(themeLabel)

        // Theme buttons
        let buttonWidth: CGFloat = 80
        let buttonHeight: CGFloat = 60
        let spacing: CGFloat = 10
        var xOffset: CGFloat = 20

        for (index, theme) in Theme.allThemes.enumerated() {
            let button = createThemeButton(theme: theme, frame: NSRect(x: xOffset, y: bounds.height - 170, width: buttonWidth, height: buttonHeight))
            button.tag = index
            button.target = self
            button.action = #selector(themeSelected(_:))
            button.autoresizingMask = [.minYMargin]
            addSubview(button)
            themeButtons.append(button)
            xOffset += buttonWidth + spacing
        }

        updateSelectedTheme()

        // Hotkeys section
        hotkeysLabel = NSTextField(labelWithString: "Hotkeys")
        hotkeysLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hotkeysLabel.textColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.7)
        hotkeysLabel.frame = NSRect(x: 20, y: bounds.height - 220, width: 200, height: 20)
        hotkeysLabel.autoresizingMask = [.minYMargin]
        addSubview(hotkeysLabel)

        // Injection hotkey
        injectionHotkeyLabel = NSTextField(labelWithString: "Injection:")
        injectionHotkeyLabel.font = .systemFont(ofSize: 12)
        injectionHotkeyLabel.textColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.6)
        injectionHotkeyLabel.frame = NSRect(x: 20, y: bounds.height - 250, width: 70, height: 18)
        injectionHotkeyLabel.autoresizingMask = [.minYMargin]
        addSubview(injectionHotkeyLabel)

        injectionHotkeyRecorder = HotkeyRecorderView(frame: NSRect(x: 95, y: bounds.height - 252, width: 180, height: 22))
        injectionHotkeyRecorder.autoresizingMask = [.minYMargin]
        injectionHotkeyRecorder.setHotkey(
            keyCode: InjectionSettings.shared.injectionKeyCode,
            modifiers: InjectionSettings.shared.injectionModifiers,
            display: InjectionSettings.shared.injectionDisplay
        )
        injectionHotkeyRecorder.onHotkeyChanged = { keyCode, modifiers, display in
            InjectionSettings.shared.injectionKeyCode = keyCode
            InjectionSettings.shared.injectionModifiers = modifiers
            InjectionSettings.shared.injectionDisplay = display
            // Unregister and re-register hotkeys
            HotkeyManager.shared.unregister()
            HotkeyManager.shared.register()
        }
        addSubview(injectionHotkeyRecorder)

        // Toggle hotkey
        toggleHotkeyLabel = NSTextField(labelWithString: "Toggle:")
        toggleHotkeyLabel.font = .systemFont(ofSize: 12)
        toggleHotkeyLabel.textColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.6)
        toggleHotkeyLabel.frame = NSRect(x: 20, y: bounds.height - 280, width: 70, height: 18)
        toggleHotkeyLabel.autoresizingMask = [.minYMargin]
        addSubview(toggleHotkeyLabel)

        toggleHotkeyRecorder = HotkeyRecorderView(frame: NSRect(x: 95, y: bounds.height - 282, width: 180, height: 22))
        toggleHotkeyRecorder.autoresizingMask = [.minYMargin]
        toggleHotkeyRecorder.setHotkey(
            keyCode: InjectionSettings.shared.toggleKeyCode,
            modifiers: InjectionSettings.shared.toggleModifiers,
            display: InjectionSettings.shared.toggleDisplay
        )
        toggleHotkeyRecorder.onHotkeyChanged = { keyCode, modifiers, display in
            InjectionSettings.shared.toggleKeyCode = keyCode
            InjectionSettings.shared.toggleModifiers = modifiers
            InjectionSettings.shared.toggleDisplay = display
            // Unregister and re-register hotkeys
            HotkeyManager.shared.unregister()
            HotkeyManager.shared.register()
        }
        addSubview(toggleHotkeyRecorder)

        // Cut-inject hotkey
        cutInjectHotkeyLabel = NSTextField(labelWithString: "Cut+Inject:")
        cutInjectHotkeyLabel.font = .systemFont(ofSize: 12)
        cutInjectHotkeyLabel.textColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.6)
        cutInjectHotkeyLabel.frame = NSRect(x: 20, y: bounds.height - 310, width: 70, height: 18)
        cutInjectHotkeyLabel.autoresizingMask = [.minYMargin]
        addSubview(cutInjectHotkeyLabel)

        cutInjectHotkeyRecorder = HotkeyRecorderView(frame: NSRect(x: 95, y: bounds.height - 312, width: 180, height: 22))
        cutInjectHotkeyRecorder.autoresizingMask = [.minYMargin]
        cutInjectHotkeyRecorder.setHotkey(
            keyCode: InjectionSettings.shared.cutInjectKeyCode,
            modifiers: InjectionSettings.shared.cutInjectModifiers,
            display: InjectionSettings.shared.cutInjectDisplay
        )
        cutInjectHotkeyRecorder.onHotkeyChanged = { keyCode, modifiers, display in
            InjectionSettings.shared.cutInjectKeyCode = keyCode
            InjectionSettings.shared.cutInjectModifiers = modifiers
            InjectionSettings.shared.cutInjectDisplay = display
            // Unregister and re-register hotkeys
            HotkeyManager.shared.unregister()
            HotkeyManager.shared.register()
        }
        addSubview(cutInjectHotkeyRecorder)

        // Injection Settings section
        injectionLabel = NSTextField(labelWithString: "Injection Settings")
        injectionLabel.font = .systemFont(ofSize: 14, weight: .medium)
        injectionLabel.textColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.7)
        injectionLabel.frame = NSRect(x: 20, y: bounds.height - 350, width: 200, height: 20)
        injectionLabel.autoresizingMask = [.minYMargin]
        addSubview(injectionLabel)

        // Ignore titles checkbox
        ignoreTitlesCheckbox = NSButton(checkboxWithTitle: "Ignore titles (# headings)", target: self, action: #selector(ignoreTitlesToggled))
        ignoreTitlesCheckbox.frame = NSRect(x: 20, y: bounds.height - 375, width: 250, height: 20)
        ignoreTitlesCheckbox.state = InjectionSettings.shared.ignoreTitles ? .on : .off
        ignoreTitlesCheckbox.autoresizingMask = [.minYMargin]
        addSubview(ignoreTitlesCheckbox)

        // Ignore tags checkbox
        ignoreTagsCheckbox = NSButton(checkboxWithTitle: "Ignore tags", target: self, action: #selector(ignoreTagsToggled))
        ignoreTagsCheckbox.frame = NSRect(x: 20, y: bounds.height - 400, width: 250, height: 20)
        ignoreTagsCheckbox.state = InjectionSettings.shared.ignoreTags ? .on : .off
        ignoreTagsCheckbox.autoresizingMask = [.minYMargin]
        addSubview(ignoreTagsCheckbox)

        // Ignore link formatting checkbox
        ignoreLinkFormattingCheckbox = NSButton(checkboxWithTitle: "Ignore link formatting", target: self, action: #selector(ignoreLinkFormattingToggled))
        ignoreLinkFormattingCheckbox.frame = NSRect(x: 20, y: bounds.height - 425, width: 250, height: 20)
        ignoreLinkFormattingCheckbox.state = InjectionSettings.shared.ignoreLinkFormatting ? .on : .off
        ignoreLinkFormattingCheckbox.autoresizingMask = [.minYMargin]
        addSubview(ignoreLinkFormattingCheckbox)

        // Workspace Settings section
        workspaceLabel = NSTextField(labelWithString: "Workspace Settings")
        workspaceLabel.font = .systemFont(ofSize: 14, weight: .medium)
        workspaceLabel.textColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.7)
        workspaceLabel.frame = NSRect(x: 20, y: bounds.height - 435, width: 200, height: 20)
        workspaceLabel.autoresizingMask = [.minYMargin]
        addSubview(workspaceLabel)

        // Default editor label
        defaultEditorLabel = NSTextField(labelWithString: "Default Editor:")
        defaultEditorLabel.font = .systemFont(ofSize: 12)
        defaultEditorLabel.textColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.6)
        defaultEditorLabel.frame = NSRect(x: 20, y: bounds.height - 465, width: 100, height: 18)
        defaultEditorLabel.autoresizingMask = [.minYMargin]
        addSubview(defaultEditorLabel)

        // Default editor popup
        defaultEditorPopup = NSPopUpButton(frame: NSRect(x: 125, y: bounds.height - 468, width: 150, height: 24), pullsDown: false)
        defaultEditorPopup.addItems(withTitles: ["VS Code", "Cursor", "Antigravity"])
        defaultEditorPopup.target = self
        defaultEditorPopup.action = #selector(defaultEditorChanged)
        defaultEditorPopup.autoresizingMask = [.minYMargin]

        // Set current selection
        let currentEditor = InjectionSettings.shared.defaultEditor
        switch currentEditor {
        case "vscode": defaultEditorPopup.selectItem(at: 0)
        case "cursor": defaultEditorPopup.selectItem(at: 1)
        case "anti": defaultEditorPopup.selectItem(at: 2)
        default: defaultEditorPopup.selectItem(at: 0)
        }
        addSubview(defaultEditorPopup)
    }

    private func createThemeButton(theme: Theme, frame: NSRect) -> NSButton {
        let button = NSButton(frame: frame)
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 2
        button.layer?.borderColor = NSColor.clear.cgColor

        // Create preview view
        let preview = NSView(frame: NSRect(x: 4, y: 20, width: frame.width - 8, height: frame.height - 24))
        preview.wantsLayer = true
        preview.layer?.backgroundColor = theme.background.cgColor
        preview.layer?.cornerRadius = 4

        // Add sample text colors
        let sampleText = NSTextField(labelWithString: "Aa")
        sampleText.font = .systemFont(ofSize: 14, weight: .medium)
        sampleText.textColor = theme.text
        sampleText.frame = NSRect(x: 8, y: 8, width: 30, height: 20)
        sampleText.isEditable = false
        preview.addSubview(sampleText)

        let sampleLink = NSTextField(labelWithString: "#")
        sampleLink.font = .systemFont(ofSize: 14, weight: .medium)
        sampleLink.textColor = theme.tag
        sampleLink.frame = NSRect(x: 38, y: 8, width: 20, height: 20)
        sampleLink.isEditable = false
        preview.addSubview(sampleLink)

        button.addSubview(preview)

        // Theme name label - use identifier to find later
        let nameLabel = NSTextField(labelWithString: theme.name)
        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.textColor = ThemeManager.shared.currentTheme.text.withAlphaComponent(0.8)
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 0, y: 2, width: frame.width, height: 14)
        nameLabel.isEditable = false
        nameLabel.identifier = NSUserInterfaceItemIdentifier("themeNameLabel")
        button.addSubview(nameLabel)

        return button
    }

    @objc private func themeSelected(_ sender: NSButton) {
        let theme = Theme.allThemes[sender.tag]
        ThemeManager.shared.setTheme(theme)
        updateSelectedTheme()
        applyThemePreview()
    }

    @objc private func ignoreTitlesToggled(_ sender: NSButton) {
        InjectionSettings.shared.ignoreTitles = (sender.state == .on)
    }

    @objc private func ignoreTagsToggled(_ sender: NSButton) {
        InjectionSettings.shared.ignoreTags = (sender.state == .on)
    }

    @objc private func ignoreLinkFormattingToggled(_ sender: NSButton) {
        InjectionSettings.shared.ignoreLinkFormatting = (sender.state == .on)
    }

    @objc private func defaultEditorChanged(_ sender: NSPopUpButton) {
        let editors = ["vscode", "cursor", "anti"]
        if sender.indexOfSelectedItem >= 0 && sender.indexOfSelectedItem < editors.count {
            InjectionSettings.shared.defaultEditor = editors[sender.indexOfSelectedItem]
        }
    }

    private func updateSelectedTheme() {
        let currentName = ThemeManager.shared.currentTheme.name
        for (index, button) in themeButtons.enumerated() {
            let theme = Theme.allThemes[index]
            if theme.name == currentName {
                button.layer?.borderColor = NSColor.systemBlue.cgColor
            } else {
                button.layer?.borderColor = NSColor.clear.cgColor
            }
        }
    }

    private func applyThemePreview() {
        let theme = ThemeManager.shared.currentTheme

        // Update background
        layer?.backgroundColor = theme.background.cgColor

        // Update title and labels
        titleLabel.textColor = theme.text
        themeLabel.textColor = theme.text.withAlphaComponent(0.7)
        hotkeysLabel.textColor = theme.text.withAlphaComponent(0.7)
        injectionHotkeyLabel.textColor = theme.text.withAlphaComponent(0.6)
        toggleHotkeyLabel.textColor = theme.text.withAlphaComponent(0.6)
        injectionLabel.textColor = theme.text.withAlphaComponent(0.7)

        // Update hotkey recorder views
        injectionHotkeyRecorder.backgroundColor = theme.background
        injectionHotkeyRecorder.textColor = theme.text
        injectionHotkeyRecorder.layer?.borderColor = theme.text.withAlphaComponent(0.3).cgColor

        toggleHotkeyRecorder.backgroundColor = theme.background
        toggleHotkeyRecorder.textColor = theme.text
        toggleHotkeyRecorder.layer?.borderColor = theme.text.withAlphaComponent(0.3).cgColor

        // Update theme name labels
        for button in themeButtons {
            if let nameLabel = button.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == "themeNameLabel" }) {
                nameLabel.textColor = theme.text.withAlphaComponent(0.8)
            }
        }
    }

    @objc private func donePressed() {
        onDismiss?()
    }
}

// MARK: - Note Browser View
// Mixed data model for NoteBrowserView rows
enum BrowserRow {
    case note(Note)
    case workspace(name: String, count: Int)
    case backButton
}

class NoteBrowserView: NSView, NSTextFieldDelegate {
    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var searchField: NSTextField!
    private var tagPillsView: NSView!
    private var tagAutocompleteView: TagAutocompleteView?
    private var settingsButton: NSButton!
    private var rows: [BrowserRow] = []
    private var selectedTags: [String] = []
    private var tagAutocompleteStart: Int = 0
    var onSelectNote: ((Note) -> Void)?
    var onDeleteNote: ((Note) -> Void)?
    var onPinNote: ((Note) -> Void)?
    var onSettings: (() -> Void)?

    // Selection mode for mass-adding notes to workspace
    private var isSelectingForWorkspace: Bool = false
    private var targetWorkspace: String? = nil
    private var selectedNoteIds: Set<UUID> = []
    private var selectionBanner: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
        reloadNotes()
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .themeDidChange, object: nil)
    }

    @objc private func themeDidChange() {
        settingsButton.image = tintedSymbol("gearshape", color: ThemeManager.shared.currentTheme.icon)
        tableView.reloadData()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true

        // Tag pills container (above search field)
        tagPillsView = NSView(frame: NSRect(x: 10, y: bounds.height - 30, width: bounds.width - 20, height: 0))
        tagPillsView.autoresizingMask = [.width, .minYMargin]
        addSubview(tagPillsView)

        // Search field (below pills when they exist)
        searchField = NSTextField(frame: NSRect(x: 10, y: bounds.height - 32, width: bounds.width - 20, height: 24))
        searchField.autoresizingMask = [.width, .minYMargin]
        searchField.placeholderString = "Search notes... (type # for tags)"
        searchField.delegate = self
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        addSubview(searchField)

        // Bottom bar with settings button
        let bottomBarHeight: CGFloat = 36
        let bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bottomBarHeight))
        bottomBar.autoresizingMask = [.width, .maxYMargin]
        addSubview(bottomBar)

        settingsButton = NSButton(frame: NSRect(x: 10, y: 6, width: 28, height: 24))
        settingsButton.bezelStyle = .inline
        settingsButton.isBordered = false
        settingsButton.image = tintedSymbol("gearshape", color: ThemeManager.shared.currentTheme.icon)
        settingsButton.target = self
        settingsButton.action = #selector(settingsPressed)
        bottomBar.addSubview(settingsButton)

        scrollView = NSScrollView(frame: NSRect(x: 0, y: bottomBarHeight, width: bounds.width, height: bounds.height - 40 - bottomBarHeight))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClick)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        column.width = bounds.width - 20
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        addSubview(scrollView)
    }

    @objc private func settingsPressed() {
        onSettings?()
    }

    func controlTextDidChange(_ obj: Notification) {
        let text = searchField.stringValue
        // Check for tag autocomplete
        if let hashIndex = text.lastIndex(of: "#") {
            let afterHash = String(text[text.index(after: hashIndex)...])
            // If no space after #, show autocomplete
            if !afterHash.contains(" ") {
                tagAutocompleteStart = text.distance(from: text.startIndex, to: hashIndex)
                showTagAutocomplete(filter: afterHash)
                return
            }
        }
        hideTagAutocomplete()
        performSearch()
    }

    private func showTagAutocomplete(filter: String) {
        let allTags = NotesManager.shared.getAllTags()
        if allTags.isEmpty {
            hideTagAutocomplete()
            return
        }

        if tagAutocompleteView == nil {
            let autocomplete = TagAutocompleteView(frame: NSRect(x: 10, y: searchField.frame.origin.y - 125, width: 180, height: 120))
            autocomplete.onSelectTag = { [weak self] tag in
                self?.selectTagFromAutocomplete(tag)
            }
            addSubview(autocomplete)
            tagAutocompleteView = autocomplete
        }

        tagAutocompleteView?.updateTags(allTags: allTags.filter { !selectedTags.contains($0) }, filter: filter)

        if tagAutocompleteView?.hasResults == false {
            hideTagAutocomplete()
        }
    }

    private func hideTagAutocomplete() {
        tagAutocompleteView?.removeFromSuperview()
        tagAutocompleteView = nil
    }

    private func selectTagFromAutocomplete(_ tag: String) {
        // Remove the #... from search field
        var text = searchField.stringValue
        if tagAutocompleteStart < text.count {
            let startIndex = text.index(text.startIndex, offsetBy: tagAutocompleteStart)
            text = String(text[..<startIndex])
            searchField.stringValue = text.trimmingCharacters(in: .whitespaces)
        }

        selectedTags.append(tag)
        hideTagAutocomplete()
        updateTagPills()
        performSearch()
    }

    private func removeTag(_ tag: String) {
        selectedTags.removeAll { $0 == tag }
        updateTagPills()
        performSearch()
    }

    private func updateTagPills() {
        // Remove old pills
        tagPillsView.subviews.forEach { $0.removeFromSuperview() }

        if selectedTags.isEmpty {
            tagPillsView.frame.size.height = 0
            searchField.frame.origin.y = bounds.height - 32
            scrollView.frame.size.height = bounds.height - 40
            return
        }

        // Add pills
        var xOffset: CGFloat = 0
        let pillHeight: CGFloat = 22
        for tag in selectedTags {
            let pillWidth = CGFloat(tag.count * 8 + 30)
            let pill = createTagPill(tag: tag, x: xOffset, width: pillWidth)
            tagPillsView.addSubview(pill)
            xOffset += pillWidth + 6
        }

        tagPillsView.frame.size.height = pillHeight + 4
        tagPillsView.frame.origin.y = bounds.height - pillHeight - 6
        searchField.frame.origin.y = tagPillsView.frame.origin.y - 28
        scrollView.frame.size.height = searchField.frame.origin.y - 8
    }

    private func createTagPill(tag: String, x: CGFloat, width: CGFloat) -> NSView {
        let pill = NSView(frame: NSRect(x: x, y: 0, width: width, height: 22))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.6, alpha: 0.3).cgColor
        pill.layer?.cornerRadius = 11
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.6, alpha: 0.6).cgColor

        let label = NSTextField(labelWithString: "#\(tag)")
        label.font = .systemFont(ofSize: 12)
        label.textColor = NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.6, alpha: 1.0)
        label.frame = NSRect(x: 8, y: 2, width: width - 24, height: 18)
        label.isEditable = false
        label.isSelectable = false
        pill.addSubview(label)

        let closeBtn = NSButton(frame: NSRect(x: width - 20, y: 3, width: 16, height: 16))
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")
        closeBtn.contentTintColor = NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.6, alpha: 0.8)
        closeBtn.target = self
        closeBtn.action = #selector(removeTagPill(_:))
        closeBtn.identifier = NSUserInterfaceItemIdentifier(tag)
        pill.addSubview(closeBtn)

        return pill
    }

    @objc private func removeTagPill(_ sender: NSButton) {
        if let tag = sender.identifier?.rawValue {
            removeTag(tag)
        }
    }

    private func performSearch() {
        let searchQuery = searchField.stringValue
        let isSearching = !searchQuery.isEmpty || !selectedTags.isEmpty

        // When searching, always search globally across all notes
        if isSearching {
            let notes = NotesManager.shared.searchNotes(query: searchQuery, tags: selectedTags)
            rows = notes.map { .note($0) }
            tableView.reloadData()
            return
        }

        // Not searching - show workspace-aware view
        rows = []
        let manager = NotesManager.shared
        let currentWorkspace = manager.activeWorkspace

        if let workspace = currentWorkspace {
            // In workspace view
            // Add back button
            rows.append(.backButton)

            // Get notes for current workspace (includes children and global)
            let notes = manager.notesForCurrentView()
            rows.append(contentsOf: notes.map { .note($0) })

            // Find child workspaces
            let childWorkspaces = getChildWorkspaces(of: workspace)
            for childWorkspace in childWorkspaces {
                let count = manager.notes.filter { note in
                    note.workspaces.contains(childWorkspace)
                }.count
                rows.append(.workspace(name: childWorkspace, count: count))
            }
        } else {
            // Home view
            // Get uncategorized and global notes
            let notes = manager.notesForCurrentView()
            rows.append(contentsOf: notes.map { .note($0) })

            // Get root workspaces (those without "/" in the name, excluding ".")
            let allWorkspaces = manager.getAllWorkspaces()
            let rootWorkspaces = allWorkspaces.filter { workspace in
                !workspace.contains("/") && workspace != "."
            }

            for workspace in rootWorkspaces {
                let count = manager.notes.filter { note in
                    note.workspaces.contains { ws in
                        ws == workspace || ws.hasPrefix(workspace + "/")
                    }
                }.count
                rows.append(.workspace(name: workspace, count: count))
            }
        }

        tableView.reloadData()
    }

    private func getChildWorkspaces(of parent: String) -> [String] {
        let allWorkspaces = NotesManager.shared.getAllWorkspaces()
        let prefix = parent + "/"

        // Find direct children only (not grandchildren)
        var children = Set<String>()
        for workspace in allWorkspaces {
            if workspace.hasPrefix(prefix) {
                let remainder = String(workspace.dropFirst(prefix.count))
                if !remainder.contains("/") {
                    children.insert(workspace)
                }
            }
        }

        return children.sorted()
    }

    func reloadNotes() {
        performSearch()
    }

    // Handle special keys in search field
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if let autocomplete = tagAutocompleteView, autocomplete.hasResults {
            if commandSelector == #selector(moveDown(_:)) {
                autocomplete.selectNext()
                return true
            } else if commandSelector == #selector(moveUp(_:)) {
                autocomplete.selectPrevious()
                return true
            } else if commandSelector == #selector(insertNewline(_:)) {
                autocomplete.confirmSelection()
                return true
            } else if commandSelector == #selector(cancelOperation(_:)) {
                hideTagAutocomplete()
                return true
            }
        }
        return false
    }
}

extension NoteBrowserView: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0 && row < rows.count else { return 50 }
        let browserRow = rows[row]

        switch browserRow {
        case .backButton:
            return 40
        case .workspace:
            return 40
        case .note:
            return 50
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 && row < rows.count else { return nil }
        let browserRow = rows[row]
        let theme = ThemeManager.shared.currentTheme

        switch browserRow {
        case .backButton:
            return createBackButtonCell(theme: theme)
        case .workspace(let name, let count):
            return createWorkspaceCell(name: name, count: count, theme: theme)
        case .note(let note):
            return createNoteCell(note: note, row: row, theme: theme)
        }
    }

    private func createBackButtonCell(theme: Theme) -> NSView {
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 40))

        let workspace = NotesManager.shared.activeWorkspace ?? "Home"
        let label = NSTextField(labelWithString: "← \(workspace)")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = theme.secondaryText
        label.frame = NSRect(x: 10, y: 10, width: cell.bounds.width - 20, height: 20)
        label.autoresizingMask = [.width]
        cell.addSubview(label)

        let clickButton = NSButton(frame: cell.bounds)
        clickButton.autoresizingMask = [.width, .height]
        clickButton.bezelStyle = .inline
        clickButton.isBordered = false
        clickButton.isTransparent = true
        clickButton.title = ""
        clickButton.target = self
        clickButton.action = #selector(exitWorkspace)
        cell.addSubview(clickButton)

        return cell
    }

    private func createWorkspaceCell(name: String, count: Int, theme: Theme) -> NSView {
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 40))

        let icon = NSTextField(labelWithString: "📁")
        icon.font = .systemFont(ofSize: 16)
        icon.frame = NSRect(x: 10, y: 10, width: 20, height: 20)
        cell.addSubview(icon)

        let label = NSTextField(labelWithString: "@\(name) (\(count))")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = theme.workspaceTag
        label.frame = NSRect(x: 35, y: 10, width: cell.bounds.width - 100, height: 20)
        label.autoresizingMask = [.width]
        cell.addSubview(label)

        // Add "+" button for mass-add mode
        let addBtn = NSButton(frame: NSRect(x: cell.bounds.width - 55, y: 10, width: 20, height: 20))
        addBtn.autoresizingMask = [.minXMargin]
        addBtn.bezelStyle = .inline
        addBtn.isBordered = false
        addBtn.image = tintedSymbol("plus.circle", color: theme.icon)
        addBtn.target = self
        addBtn.action = #selector(startAddingToWorkspace(_:))
        addBtn.identifier = NSUserInterfaceItemIdentifier(name)
        addBtn.toolTip = "Add notes to this workspace"
        cell.addSubview(addBtn)

        let arrow = NSTextField(labelWithString: "▶")
        arrow.font = .systemFont(ofSize: 12)
        arrow.textColor = theme.secondaryText
        arrow.frame = NSRect(x: cell.bounds.width - 30, y: 10, width: 20, height: 20)
        arrow.autoresizingMask = [.minXMargin]
        cell.addSubview(arrow)

        let clickButton = NSButton(frame: NSRect(x: 0, y: 0, width: cell.bounds.width - 60, height: 40))
        clickButton.autoresizingMask = [.width, .height]
        clickButton.bezelStyle = .inline
        clickButton.isBordered = false
        clickButton.isTransparent = true
        clickButton.title = ""
        clickButton.target = self
        clickButton.action = #selector(enterWorkspace(_:))
        clickButton.identifier = NSUserInterfaceItemIdentifier(name)
        cell.addSubview(clickButton)

        return cell
    }

    private func createNoteCell(note: Note, row: Int, theme: Theme) -> NSView {
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 50))

        // Check if note is global
        let isGlobal = note.workspaces.contains(".")

        // Add globe icon for global notes (or checkbox in selection mode)
        var titleX: CGFloat = 10
        if isSelectingForWorkspace {
            // Show checkbox
            let isSelected = selectedNoteIds.contains(note.id)
            let checkboxIcon = NSTextField(labelWithString: isSelected ? "☑" : "☐")
            checkboxIcon.font = .systemFont(ofSize: 16)
            checkboxIcon.frame = NSRect(x: 10, y: 25, width: 18, height: 20)
            checkboxIcon.isEditable = false
            checkboxIcon.isSelectable = false
            cell.addSubview(checkboxIcon)
            titleX = 32
        } else if isGlobal {
            let globeIcon = NSTextField(labelWithString: "🌐")
            globeIcon.font = .systemFont(ofSize: 12)
            globeIcon.frame = NSRect(x: 10, y: 25, width: 18, height: 20)
            globeIcon.isEditable = false
            globeIcon.isSelectable = false
            cell.addSubview(globeIcon)
            titleX = 32
        }

        // Highlight background if selected in selection mode
        if isSelectingForWorkspace && selectedNoteIds.contains(note.id) {
            cell.wantsLayer = true
            cell.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.2).cgColor
        }

        // Labels first (at back)
        let titleLabel = NSTextField(labelWithString: note.title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = theme.text
        titleLabel.frame = NSRect(x: titleX, y: 25, width: cell.bounds.width - titleX - 60, height: 20)
        titleLabel.autoresizingMask = [.width]
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        cell.addSubview(titleLabel)

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let dateStr = formatter.localizedString(for: note.modifiedAt, relativeTo: Date())
        let infoLabel = NSTextField(labelWithString: "\(dateStr) • \(note.characterCount) chars")
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = theme.secondaryText
        infoLabel.frame = NSRect(x: titleX, y: 5, width: cell.bounds.width - titleX - 60, height: 16)
        infoLabel.autoresizingMask = [.width]
        infoLabel.isEditable = false
        infoLabel.isSelectable = false
        cell.addSubview(infoLabel)

        if isSelectingForWorkspace {
            // In selection mode, clicking anywhere toggles selection
            let selectBtn = NSButton(frame: cell.bounds)
            selectBtn.autoresizingMask = [.width, .height]
            selectBtn.bezelStyle = .inline
            selectBtn.isBordered = false
            selectBtn.isTransparent = true
            selectBtn.title = ""
            selectBtn.tag = row
            selectBtn.target = self
            selectBtn.action = #selector(toggleNoteSelection(_:))
            cell.addSubview(selectBtn)
        } else {
            // Normal mode - select button and action buttons
            let selectBtn = NSButton(frame: NSRect(x: 0, y: 0, width: cell.bounds.width - 60, height: 50))
            selectBtn.autoresizingMask = [.width]
            selectBtn.bezelStyle = .inline
            selectBtn.isBordered = false
            selectBtn.isTransparent = true
            selectBtn.title = ""
            selectBtn.tag = row
            selectBtn.target = self
            selectBtn.action = #selector(selectNote(_:))
            cell.addSubview(selectBtn)

            // Pin button - on top of select button
            let pinBtn = NSButton(frame: NSRect(x: cell.bounds.width - 55, y: 15, width: 20, height: 20))
            pinBtn.autoresizingMask = [.minXMargin]
            pinBtn.bezelStyle = .inline
            pinBtn.isBordered = false
            let pinIcon = note.isPinned ? "pin.fill" : "pin"
            let pinColor = note.isPinned ? NSColor.systemYellow : theme.icon
            pinBtn.image = tintedSymbol(pinIcon, color: pinColor)
            pinBtn.tag = row
            pinBtn.target = self
            pinBtn.action = #selector(pinNote(_:))
            cell.addSubview(pinBtn)

            // Delete button - on top of everything, hidden if pinned
            let deleteBtn = NSButton(frame: NSRect(x: cell.bounds.width - 30, y: 15, width: 20, height: 20))
            deleteBtn.autoresizingMask = [.minXMargin]
            deleteBtn.bezelStyle = .inline
            deleteBtn.isBordered = false
            deleteBtn.image = tintedSymbol("trash", color: theme.icon)
            deleteBtn.tag = row
            deleteBtn.target = self
            deleteBtn.action = #selector(deleteNote(_:))
            deleteBtn.isHidden = note.isPinned
            cell.addSubview(deleteBtn)
        }

        return cell
    }

    @objc private func selectNote(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < rows.count else { return }
        if case .note(let note) = rows[row] {
            onSelectNote?(note)
        }
    }

    @objc private func tableDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0 && row < rows.count else { return }
        if case .note(let note) = rows[row] {
            onSelectNote?(note)
        }
    }

    @objc private func deleteNote(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < rows.count else { return }
        if case .note(let note) = rows[row] {
            onDeleteNote?(note)
        }
    }

    @objc private func pinNote(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < rows.count else { return }
        if case .note(let note) = rows[row] {
            onPinNote?(note)
        }
    }

    @objc private func exitWorkspace() {
        NotesManager.shared.setActiveWorkspace(nil)
        performSearch()
    }

    @objc private func enterWorkspace(_ sender: NSButton) {
        guard let workspaceName = sender.identifier?.rawValue else { return }
        NotesManager.shared.setActiveWorkspace(workspaceName)
        performSearch()
    }

    // MARK: - Mass Add to Workspace
    @objc private func startAddingToWorkspace(_ sender: NSButton) {
        guard let workspaceName = sender.identifier?.rawValue else { return }
        isSelectingForWorkspace = true
        targetWorkspace = workspaceName
        selectedNoteIds.removeAll()
        showSelectionBanner()
        tableView.reloadData()
    }

    @objc private func toggleNoteSelection(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < rows.count else { return }
        if case .note(let note) = rows[row] {
            if selectedNoteIds.contains(note.id) {
                selectedNoteIds.remove(note.id)
            } else {
                selectedNoteIds.insert(note.id)
            }
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        }
    }

    private func showSelectionBanner() {
        guard let workspace = targetWorkspace else { return }

        // Remove existing banner if any
        selectionBanner?.removeFromSuperview()

        let bannerHeight: CGFloat = 40
        let banner = NSView(frame: NSRect(x: 0, y: scrollView.frame.maxY, width: bounds.width, height: bannerHeight))
        banner.autoresizingMask = [.width, .minYMargin]
        banner.wantsLayer = true
        banner.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor

        let label = NSTextField(labelWithString: "Select notes to add to @\(workspace)")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = ThemeManager.shared.currentTheme.text
        label.frame = NSRect(x: 10, y: 10, width: bounds.width - 180, height: 20)
        label.autoresizingMask = [.width]
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        banner.addSubview(label)

        let doneBtn = NSButton(frame: NSRect(x: bounds.width - 95, y: 7, width: 60, height: 26))
        doneBtn.autoresizingMask = [.minXMargin]
        doneBtn.bezelStyle = .rounded
        doneBtn.title = "Done"
        doneBtn.target = self
        doneBtn.action = #selector(finishAddingToWorkspace)
        banner.addSubview(doneBtn)

        let cancelBtn = NSButton(frame: NSRect(x: bounds.width - 165, y: 7, width: 60, height: 26))
        cancelBtn.autoresizingMask = [.minXMargin]
        cancelBtn.bezelStyle = .rounded
        cancelBtn.title = "Cancel"
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelAddingToWorkspace)
        banner.addSubview(cancelBtn)

        addSubview(banner)
        selectionBanner = banner

        // Adjust scroll view height
        scrollView.frame.size.height = bounds.height - 40 - 36 - bannerHeight
    }

    private func hideSelectionBanner() {
        selectionBanner?.removeFromSuperview()
        selectionBanner = nil

        // Restore scroll view height
        let searchFieldY = searchField.frame.origin.y
        scrollView.frame.size.height = searchFieldY - 8 - 36
    }

    @objc private func finishAddingToWorkspace() {
        guard let workspace = targetWorkspace else { return }

        // Add workspace to all selected notes
        for noteId in selectedNoteIds {
            NotesManager.shared.addWorkspace(to: noteId, workspace: workspace)
        }

        // Exit selection mode
        isSelectingForWorkspace = false
        targetWorkspace = nil
        selectedNoteIds.removeAll()
        hideSelectionBanner()

        // Reload the view
        performSearch()
    }

    @objc private func cancelAddingToWorkspace() {
        isSelectingForWorkspace = false
        targetWorkspace = nil
        selectedNoteIds.removeAll()
        hideSelectionBanner()
        tableView.reloadData()
    }
}

// MARK: - Injection Settings Manager
class InjectionSettings {
    static let shared = InjectionSettings()

    private let ignoreTitlesKey = "FloatNote.InjectionSettings.IgnoreTitles"
    private let ignoreTagsKey = "FloatNote.InjectionSettings.IgnoreTags"
    private let ignoreLinkFormattingKey = "FloatNote.InjectionSettings.IgnoreLinkFormatting"
    private let hotkeyDisplayKey = "FloatNote.InjectionSettings.HotkeyDisplay"

    // Injection hotkey settings
    private let injectionKeyCodeKey = "FloatNote.Hotkey.Injection.KeyCode"
    private let injectionModifiersKey = "FloatNote.Hotkey.Injection.Modifiers"
    private let injectionDisplayKey = "FloatNote.Hotkey.Injection.Display"

    // Toggle hotkey settings
    private let toggleKeyCodeKey = "FloatNote.Hotkey.Toggle.KeyCode"
    private let toggleModifiersKey = "FloatNote.Hotkey.Toggle.Modifiers"
    private let toggleDisplayKey = "FloatNote.Hotkey.Toggle.Display"

    // Cut-inject hotkey settings
    private let cutInjectKeyCodeKey = "FloatNote.Hotkey.CutInject.KeyCode"
    private let cutInjectModifiersKey = "FloatNote.Hotkey.CutInject.Modifiers"
    private let cutInjectDisplayKey = "FloatNote.Hotkey.CutInject.Display"

    // Workspace tag settings
    private let defaultEditorKey = "FloatNote.Workspace.DefaultEditor"

    var ignoreTitles: Bool {
        get { UserDefaults.standard.bool(forKey: ignoreTitlesKey) }
        set { UserDefaults.standard.set(newValue, forKey: ignoreTitlesKey) }
    }

    var ignoreTags: Bool {
        get { UserDefaults.standard.bool(forKey: ignoreTagsKey) }
        set { UserDefaults.standard.set(newValue, forKey: ignoreTagsKey) }
    }

    var ignoreLinkFormatting: Bool {
        get { UserDefaults.standard.bool(forKey: ignoreLinkFormattingKey) }
        set { UserDefaults.standard.set(newValue, forKey: ignoreLinkFormattingKey) }
    }

    var hotkeyDisplay: String {
        get { UserDefaults.standard.string(forKey: hotkeyDisplayKey) ?? "Cmd+Opt+I" }
        set { UserDefaults.standard.set(newValue, forKey: hotkeyDisplayKey) }
    }

    // Injection hotkey configuration
    var injectionKeyCode: UInt32 {
        get {
            let stored = UserDefaults.standard.integer(forKey: injectionKeyCodeKey)
            return stored == 0 ? 34 : UInt32(stored) // Default: 34 = 'i'
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: injectionKeyCodeKey) }
    }

    var injectionModifiers: UInt32 {
        get {
            let stored = UserDefaults.standard.integer(forKey: injectionModifiersKey)
            return stored == 0 ? UInt32(cmdKey | optionKey) : UInt32(stored) // Default: Cmd+Opt
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: injectionModifiersKey) }
    }

    var injectionDisplay: String {
        get { UserDefaults.standard.string(forKey: injectionDisplayKey) ?? "Cmd+Opt+I" }
        set { UserDefaults.standard.set(newValue, forKey: injectionDisplayKey) }
    }

    // Toggle hotkey configuration
    var toggleKeyCode: UInt32 {
        get {
            let stored = UserDefaults.standard.integer(forKey: toggleKeyCodeKey)
            return stored == 0 ? 44 : UInt32(stored) // Default: 44 = '/'
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: toggleKeyCodeKey) }
    }

    var toggleModifiers: UInt32 {
        get {
            let stored = UserDefaults.standard.integer(forKey: toggleModifiersKey)
            return stored == 0 ? UInt32(cmdKey | optionKey | controlKey) : UInt32(stored) // Default: Ctrl+Cmd+Opt
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: toggleModifiersKey) }
    }

    var toggleDisplay: String {
        get { UserDefaults.standard.string(forKey: toggleDisplayKey) ?? "Ctrl+Cmd+Opt+/" }
        set { UserDefaults.standard.set(newValue, forKey: toggleDisplayKey) }
    }

    // Cut-inject hotkey configuration
    var cutInjectKeyCode: UInt32 {
        get {
            let stored = UserDefaults.standard.integer(forKey: cutInjectKeyCodeKey)
            return stored == 0 ? 7 : UInt32(stored) // Default: 7 = 'x'
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: cutInjectKeyCodeKey) }
    }

    var cutInjectModifiers: UInt32 {
        get {
            let stored = UserDefaults.standard.integer(forKey: cutInjectModifiersKey)
            return stored == 0 ? UInt32(cmdKey | optionKey) : UInt32(stored) // Default: Cmd+Opt
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: cutInjectModifiersKey) }
    }

    var cutInjectDisplay: String {
        get { UserDefaults.standard.string(forKey: cutInjectDisplayKey) ?? "Cmd+Opt+X" }
        set { UserDefaults.standard.set(newValue, forKey: cutInjectDisplayKey) }
    }

    // Default editor for @workspace[path] tags
    var defaultEditor: String {
        get { UserDefaults.standard.string(forKey: defaultEditorKey) ?? "vscode" }
        set { UserDefaults.standard.set(newValue, forKey: defaultEditorKey) }
    }

    func processContent(_ content: String) -> String {
        var processed = content

        // Remove titles (# headings)
        if ignoreTitles {
            processed = processed.split(separator: "\n").filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("#")
            }.joined(separator: "\n")
        }

        // Remove tags (#tag)
        if ignoreTags {
            processed = processed.replacingOccurrences(
                of: #"#\w+"#,
                with: "",
                options: .regularExpression
            )
        }

        // Remove link formatting [text](url) -> text or [[wiki]] -> wiki
        if ignoreLinkFormatting {
            // Convert [text](url) to text
            processed = processed.replacingOccurrences(
                of: #"\[([^\]]+)\]\([^\)]+\)"#,
                with: "$1",
                options: .regularExpression
            )
            // Convert [[wiki]] to wiki
            processed = processed.replacingOccurrences(
                of: #"\[\[([^\]]+)\]\]"#,
                with: "$1",
                options: .regularExpression
            )
        }

        return processed
    }
}

// MARK: - Hotkey Manager
// Carbon hotkey callback
private var hotkeyHandlerRef: EventHandlerRef?

func hotkeyCallback(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event = event else { return noErr }

    // Get the hotkey ID from the event
    var hotkeyID = EventHotKeyID()
    let result = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )

    if result == noErr {
        HotkeyManager.shared.handleHotkey(id: hotkeyID.id)
    }

    return noErr
}

class HotkeyManager {
    static let shared = HotkeyManager()
    private var pasteHotkeyRef: EventHotKeyRef?
    private var toggleHotkeyRef: EventHotKeyRef?
    private var newNoteHotkeyRef: EventHotKeyRef?
    private var cutPasteHotkeyRef: EventHotKeyRef?

    func unregister() {
        // Unregister existing hotkeys
        if let pasteRef = pasteHotkeyRef {
            UnregisterEventHotKey(pasteRef)
            pasteHotkeyRef = nil
        }
        if let toggleRef = toggleHotkeyRef {
            UnregisterEventHotKey(toggleRef)
            toggleHotkeyRef = nil
        }
        if let newNoteRef = newNoteHotkeyRef {
            UnregisterEventHotKey(newNoteRef)
            newNoteHotkeyRef = nil
        }
        if let cutPasteRef = cutPasteHotkeyRef {
            UnregisterEventHotKey(cutPasteRef)
            cutPasteHotkeyRef = nil
        }
        NSLog("FloatNote: Hotkeys unregistered")
    }

    func register() {
        // Unregister first to avoid duplicates
        unregister()

        // Use Carbon API for reliable global hotkey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &eventType,
            nil,
            &hotkeyHandlerRef
        )

        if status != noErr {
            NSLog("FloatNote: ERROR - Failed to install event handler: \(status)")
            return
        }

        // Register hotkey 1: Injection hotkey (read from settings)
        let injectionKeyCode = InjectionSettings.shared.injectionKeyCode
        let injectionModifiers = InjectionSettings.shared.injectionModifiers
        let injectionDisplay = InjectionSettings.shared.injectionDisplay

        let pasteHotKeyID = EventHotKeyID(signature: OSType(0x464D4420), id: 1) // "FMD " signature
        let pasteStatus = RegisterEventHotKey(
            injectionKeyCode,
            injectionModifiers,
            pasteHotKeyID,
            GetApplicationEventTarget(),
            0,
            &pasteHotkeyRef
        )

        if pasteStatus == noErr {
            NSLog("FloatNote: Global hotkey \(injectionDisplay) registered successfully (Carbon API)")
        } else {
            NSLog("FloatNote: ERROR - Failed to register injection hotkey: \(pasteStatus)")
        }

        // Register hotkey 2: Toggle hotkey (read from settings)
        let toggleKeyCode = InjectionSettings.shared.toggleKeyCode
        let toggleModifiers = InjectionSettings.shared.toggleModifiers
        let toggleDisplay = InjectionSettings.shared.toggleDisplay

        let toggleHotKeyID = EventHotKeyID(signature: OSType(0x464D4420), id: 2) // "FMD " signature
        let toggleStatus = RegisterEventHotKey(
            toggleKeyCode,
            toggleModifiers,
            toggleHotKeyID,
            GetApplicationEventTarget(),
            0,
            &toggleHotkeyRef
        )

        if toggleStatus == noErr {
            NSLog("FloatNote: Global hotkey \(toggleDisplay) registered successfully (Carbon API)")
        } else {
            NSLog("FloatNote: ERROR - Failed to register toggle hotkey: \(toggleStatus)")
        }

        // Register hotkey 3: New Note hotkey (Cmd+N)
        let newNoteKeyCode: UInt32 = 45 // 'n' key
        let newNoteModifiers: UInt32 = UInt32(cmdKey) // Cmd modifier

        let newNoteHotKeyID = EventHotKeyID(signature: OSType(0x464D4420), id: 3) // "FMD " signature
        let newNoteStatus = RegisterEventHotKey(
            newNoteKeyCode,
            newNoteModifiers,
            newNoteHotKeyID,
            GetApplicationEventTarget(),
            0,
            &newNoteHotkeyRef
        )

        if newNoteStatus == noErr {
            NSLog("FloatNote: Global hotkey Cmd+N registered successfully (Carbon API)")
        } else {
            NSLog("FloatNote: ERROR - Failed to register new note hotkey: \(newNoteStatus)")
        }

        // Register hotkey 4: Cut and Paste hotkey (configurable, default Cmd+Opt+X)
        let cutPasteKeyCodeSetting = InjectionSettings.shared.cutInjectKeyCode
        let cutPasteModifiersSetting = InjectionSettings.shared.cutInjectModifiers

        let cutPasteHotKeyID = EventHotKeyID(signature: OSType(0x464D4420), id: 4) // "FMD " signature
        let cutPasteStatus = RegisterEventHotKey(
            cutPasteKeyCodeSetting,
            cutPasteModifiersSetting,
            cutPasteHotKeyID,
            GetApplicationEventTarget(),
            0,
            &cutPasteHotkeyRef
        )

        if cutPasteStatus == noErr {
            NSLog("FloatNote: Global hotkey \(InjectionSettings.shared.cutInjectDisplay) registered successfully (Carbon API)")
        } else {
            NSLog("FloatNote: ERROR - Failed to register cut and paste hotkey: \(cutPasteStatus)")
        }
    }

    func handleHotkey(id: UInt32) {
        if id == 1 {
            handlePasteHotkey()
        } else if id == 2 {
            handleToggleHotkey()
        } else if id == 3 {
            handleNewNoteHotkey()
        } else if id == 4 {
            handleCutPasteHotkey()
        }
    }

    func handlePasteHotkey() {
        NSLog("FloatNote: Hotkey Opt+Cmd+I pressed!")
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let view = appDelegate.window.contentView as? MainView else {
            NSLog("FloatNote: ERROR - Could not get MainView")
            return
        }

        let rawContent = view.getSelectedTextOrContent()
        let content = InjectionSettings.shared.processContent(rawContent)
        NSLog("FloatNote: Content to paste: \(content.prefix(50))...")

        // Visual feedback
        DispatchQueue.main.async {
            appDelegate.window.contentView?.layer?.backgroundColor = NSColor.white.cgColor
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                appDelegate.window.contentView?.animator().layer?.backgroundColor = NSColor.clear.cgColor
            }
        }

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        NSLog("FloatNote: Content copied to clipboard")

        // Use CGEvent to simulate Cmd+V - more reliable than AppleScript
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Check accessibility permission first
            let trusted = AXIsProcessTrusted()
            NSLog("FloatNote: Accessibility trusted: \(trusted)")

            if !trusted {
                NSLog("FloatNote: ERROR - Not trusted for accessibility. Please grant permission in System Settings → Privacy & Security → Accessibility")
                // Show alert on main thread
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Accessibility Permission Required"
                    alert.informativeText = "FloatMD needs Accessibility permission to inject text. Please add it in System Settings → Privacy & Security → Accessibility"
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
                return
            }

            NSLog("FloatNote: Simulating Cmd+V paste...")

            // Create key down event for 'v' with command modifier
            guard let source = CGEventSource(stateID: .hidSystemState) else {
                NSLog("FloatNote: ERROR - Could not create CGEventSource")
                return
            }

            // Key code 9 = 'v'
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) else {
                NSLog("FloatNote: ERROR - Could not create keyDown event")
                return
            }
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            NSLog("FloatNote: keyDown posted")

            // Key up event
            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                NSLog("FloatNote: ERROR - Could not create keyUp event")
                return
            }
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)

            NSLog("FloatNote: Paste event posted successfully")
        }
    }

    func handleToggleHotkey() {
        NSLog("FloatNote: Toggle hotkey pressed!")
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            NSLog("FloatNote: ERROR - Could not get AppDelegate")
            return
        }

        DispatchQueue.main.async {
            guard let window = appDelegate.window else {
                NSLog("FloatNote: ERROR - Window is nil")
                return
            }

            if window.isVisible && window.isKeyWindow {
                // Window is visible and active - hide it
                NSLog("FloatNote: Hiding window")
                window.orderOut(nil)
            } else {
                // Window is hidden or not key - bring it back
                NSLog("FloatNote: Showing and activating window")
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func handleNewNoteHotkey() {
        NSLog("FloatNote: Hotkey Cmd+N pressed!")
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            NSLog("FloatNote: ERROR - Could not get AppDelegate")
            return
        }

        DispatchQueue.main.async {
            // Create new note
            _ = NotesManager.shared.createNote()
            if let mainView = appDelegate.window.contentView as? MainView {
                mainView.loadActiveNote()
            }

            // Show and activate window
            appDelegate.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSLog("FloatNote: New note created and window activated")
        }
    }

    func handleCutPasteHotkey() {
        NSLog("FloatNote: Hotkey Cmd+Opt+X pressed!")
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let view = appDelegate.window.contentView as? MainView else {
            NSLog("FloatNote: ERROR - Could not get MainView")
            return
        }

        // Get the content to paste (selected or full)
        let rawContent = view.getSelectedTextOrContent()
        let content = InjectionSettings.shared.processContent(rawContent)
        NSLog("FloatNote: Content to cut and paste: \(content.prefix(50))...")

        // Visual feedback (yellow to indicate "cut" instead of just "paste")
        DispatchQueue.main.async {
            appDelegate.window.contentView?.layer?.backgroundColor = NSColor.yellow.cgColor
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                appDelegate.window.contentView?.animator().layer?.backgroundColor = NSColor.clear.cgColor
            }
        }

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        NSLog("FloatNote: Content copied to clipboard")

        // Use CGEvent to simulate Cmd+V - more reliable than AppleScript
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSLog("FloatNote: Simulating Cmd+V paste...")

            // Create key down event for 'v' with command modifier
            let source = CGEventSource(stateID: .hidSystemState)

            // Key code 9 = 'v'
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) {
                keyDown.flags = .maskCommand
                keyDown.post(tap: .cghidEventTap)
            }

            // Key up event
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
                keyUp.flags = .maskCommand
                keyUp.post(tap: .cghidEventTap)
            }

            NSLog("FloatNote: Paste event posted")

            // After pasting, delete the content from the note
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSLog("FloatNote: Deleting content from note")
                view.deleteSelectedTextOrClearContent()
                NSLog("FloatNote: Content deleted from note and saved")
            }
        }
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
