import Cocoa
import Carbon

// MARK: - Note Model
struct Note: Codable, Identifiable {
    let id: UUID
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool

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
    }
}

// MARK: - Notes Manager
class NotesManager {
    static let shared = NotesManager()
    private let storageKey = "floatmd_notes"
    private let activeNoteKey = "floatmd_active_note"

    var notes: [Note] = []
    var activeNoteId: UUID?

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
        }
        if let idString = UserDefaults.standard.string(forKey: activeNoteKey),
           let id = UUID(uuidString: idString) {
            activeNoteId = id
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: FloatingPanel!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 500),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.setFrameAutosaveName("FloatMDWindow")
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
            button.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "FloatMD")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit FloatMD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        HotkeyManager.shared.register()
        checkAccessibilityPermissions()
    }

    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !accessEnabled {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Needed"
            alert.informativeText = "To inject text into other apps, FloatMD needs Accessibility permissions."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Floating Panel
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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

// MARK: - Main View
class MainView: NSView, NSTextViewDelegate, NSTextStorageDelegate {
    private var scrollView: NSScrollView!
    private var textView: ClickableTextView!
    private var headerView: NSView!
    private var newNoteButton: NSButton!
    private var browseButton: NSButton!
    private var noteBrowserView: NoteBrowserView?
    private var isUpdatingFormatting = false
    private var cursorLine: Int = -1
    private var tagAutocompleteView: TagAutocompleteView?
    private var tagAutocompleteStart: Int = 0  // Position of the # character
    private var noteLinkAutocompleteView: NoteLinkAutocompleteView?
    private var noteLinkAutocompleteStart: Int = 0  // Position of the [[ characters
    private var previousTitle: String = ""  // Track title for backlink updates

    private let baseFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    private let h1Font = NSFont.systemFont(ofSize: 28, weight: .bold)
    private let h2Font = NSFont.systemFont(ofSize: 22, weight: .bold)
    private let h3Font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    private let h4Font = NSFont.systemFont(ofSize: 16, weight: .semibold)
    private let h5Font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    private let h6Font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private let textColor = NSColor.white
    private let syntaxColor = NSColor.white.withAlphaComponent(0.3)
    private let hiddenColor = NSColor.clear
    private let codeBackground = NSColor.white.withAlphaComponent(0.1)
    private let blockquoteColor = NSColor(calibratedRed: 0.7, green: 0.7, blue: 0.8, alpha: 1.0)
    private let linkColor = NSColor(calibratedRed: 0.49, green: 0.30, blue: 1.0, alpha: 1.0)
    private let checkboxColor = NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.4, alpha: 1.0)
    private let checkedColor = NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    private let hrColor = NSColor.white.withAlphaComponent(0.4)
    private let wikiLinkColor = NSColor(calibratedRed: 0.3, green: 0.7, blue: 0.9, alpha: 1.0)
    private let wikiLinkMissingColor = NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.3, alpha: 1.0)
    private let tagColor = NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.6, alpha: 1.0)
    private let tagBackground = NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.6, alpha: 0.15)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        loadContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        wantsLayer = true

        let visualEffect = NSVisualEffectView(frame: bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        addSubview(visualEffect)

        // Header bar
        headerView = NSView(frame: NSRect(x: 0, y: bounds.height - 36, width: bounds.width, height: 36))
        headerView.autoresizingMask = [.width, .minYMargin]
        headerView.wantsLayer = true
        addSubview(headerView)

        newNoteButton = NSButton(frame: NSRect(x: bounds.width - 70, y: 6, width: 28, height: 24))
        newNoteButton.bezelStyle = .inline
        newNoteButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Note")
        newNoteButton.target = self
        newNoteButton.action = #selector(createNewNote)
        newNoteButton.autoresizingMask = [.minXMargin]
        headerView.addSubview(newNoteButton)

        browseButton = NSButton(frame: NSRect(x: bounds.width - 38, y: 6, width: 28, height: 24))
        browseButton.bezelStyle = .inline
        browseButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Browse Notes")
        browseButton.target = self
        browseButton.action = #selector(toggleBrowseNotes)
        browseButton.autoresizingMask = [.minXMargin]
        headerView.addSubview(browseButton)

        // Text editor
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 36))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        // Create text system with custom layout manager for pill backgrounds
        let textStorage = NSTextStorage()
        let layoutManager = PillBackgroundLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: scrollView.bounds.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        textView = ClickableTextView(frame: scrollView.bounds, textContainer: textContainer)
        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 15, height: 15)
        textView.insertionPointColor = .white
        textView.typingAttributes = [.font: baseFont, .foregroundColor: textColor]
        textView.textStorage?.delegate = self

        textView.onCheckboxClick = { [weak self] range in self?.toggleCheckbox(at: range) }
        textView.onWikiLinkClick = { [weak self] target in self?.navigateToNote(titled: target) }
        textView.onEnterPressed = { [weak self] in self?.handleEnterKey() ?? false }
        textView.onTabPressed = { [weak self] isShift in self?.handleTabKey(isShift: isShift) ?? false }
        textView.onArrowKey = { [weak self] isDown in self?.handleArrowKey(isDown: isDown) ?? false }
        textView.onEscapePressed = { [weak self] in self?.handleEscapeKey() ?? false }
        textView.onTextChanged = { [weak self] in self?.handleTextChanged() }

        scrollView.documentView = textView
        addSubview(scrollView)
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
            addSubview(browser)
            noteBrowserView = browser
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
        if tagAutocompleteView != nil {
            hideTagAutocomplete()
            return true
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        saveContent()
        handleTextChanged()
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

        // Headings
        if let match = trimmedLine.range(of: "^(#{1,6}) ", options: .regularExpression) {
            let hashCount = trimmedLine.distance(from: match.lowerBound, to: match.upperBound) - 1
            let font: NSFont = [h1Font, h2Font, h3Font, h4Font, h5Font, h6Font][min(hashCount - 1, 5)]
            textStorage.addAttribute(.foregroundColor, value: syntaxStyle, range: NSRange(location: lineStartWithIndent, length: hashCount + 1))
            let contentLength = range.length - indentLength - hashCount - 1
            if contentLength > 0 {
                textStorage.addAttribute(.font, value: font, range: NSRange(location: lineStartWithIndent + hashCount + 1, length: contentLength))
            }
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
            // Replace the dashes with a visual horizontal rule
            textStorage.addAttribute(.foregroundColor, value: hrColor, range: NSRange(location: lineStartWithIndent, length: range.length - indentLength))
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: lineStartWithIndent, length: range.length - indentLength))
            textStorage.addAttribute(.strikethroughColor, value: hrColor, range: NSRange(location: lineStartWithIndent, length: range.length - indentLength))
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
        // Use word boundary to avoid matching headings (# followed by space)
        // Rendered as pills with rounded background
        applyPattern("(?<=\\s|^)#([a-zA-Z][a-zA-Z0-9_-]*)", to: textStorage, in: text) { range, _ in
            textStorage.addAttribute(.foregroundColor, value: self.tagColor, range: range)
            textStorage.addAttribute(.init("tagPillBackground"), value: self.tagBackground, range: range)
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
            applyMarkdownFormatting()
        }
    }

    private func navigateToNote(titled title: String) {
        saveContent()
        checkForBacklinkUpdates()
        let note = NotesManager.shared.findOrCreateNote(byTitle: title)
        NotesManager.shared.setActiveNote(note)
        loadContent()
        window?.makeFirstResponder(textView)
    }

    func getContent() -> String { textView.string }
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

// MARK: - Note Browser View
class NoteBrowserView: NSView, NSTextFieldDelegate {
    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var searchField: NSTextField!
    private var tagPillsView: NSView!
    private var tagAutocompleteView: TagAutocompleteView?
    private var notes: [Note] = []
    private var selectedTags: [String] = []
    private var tagAutocompleteStart: Int = 0
    var onSelectNote: ((Note) -> Void)?
    var onDeleteNote: ((Note) -> Void)?
    var onPinNote: ((Note) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
        reloadNotes()
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

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 40))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = 50
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
        notes = NotesManager.shared.searchNotes(query: searchField.stringValue, tags: selectedTags)
        tableView.reloadData()
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
    func numberOfRows(in tableView: NSTableView) -> Int { notes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let note = notes[row]
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 50))

        // Labels first (at back)
        let titleLabel = NSTextField(labelWithString: note.title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 10, y: 25, width: cell.bounds.width - 70, height: 20)
        titleLabel.autoresizingMask = [.width]
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        cell.addSubview(titleLabel)

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let dateStr = formatter.localizedString(for: note.modifiedAt, relativeTo: Date())
        let infoLabel = NSTextField(labelWithString: "\(dateStr) • \(note.characterCount) chars")
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = NSColor(white: 0.6, alpha: 1.0)
        infoLabel.frame = NSRect(x: 10, y: 5, width: cell.bounds.width - 70, height: 16)
        infoLabel.autoresizingMask = [.width]
        infoLabel.isEditable = false
        infoLabel.isSelectable = false
        cell.addSubview(infoLabel)

        // Select button - covers left side, on top of labels
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
        let pinIcon = note.isPinned ? "pin.fill" : "pin"
        pinBtn.image = NSImage(systemSymbolName: pinIcon, accessibilityDescription: "Pin")
        pinBtn.contentTintColor = note.isPinned ? .systemYellow : .white
        pinBtn.tag = row
        pinBtn.target = self
        pinBtn.action = #selector(pinNote(_:))
        cell.addSubview(pinBtn)

        // Delete button - on top of everything, hidden if pinned
        let deleteBtn = NSButton(frame: NSRect(x: cell.bounds.width - 30, y: 15, width: 20, height: 20))
        deleteBtn.autoresizingMask = [.minXMargin]
        deleteBtn.bezelStyle = .inline
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteBtn.tag = row
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteNote(_:))
        deleteBtn.isHidden = note.isPinned
        cell.addSubview(deleteBtn)

        return cell
    }

    @objc private func selectNote(_ sender: NSButton) {
        let row = sender.tag
        if row >= 0 && row < notes.count {
            onSelectNote?(notes[row])
        }
    }

    @objc private func tableDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0 && row < notes.count else { return }
        onSelectNote?(notes[row])
    }

    @objc private func deleteNote(_ sender: NSButton) {
        let row = sender.tag
        if row >= 0 && row < notes.count {
            onDeleteNote?(notes[row])
        }
    }

    @objc private func pinNote(_ sender: NSButton) {
        let row = sender.tag
        if row >= 0 && row < notes.count {
            onPinNote?(notes[row])
        }
    }
}

// MARK: - Hotkey Manager
// Carbon hotkey callback
private var hotkeyHandlerRef: EventHandlerRef?

func hotkeyCallback(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    HotkeyManager.shared.handleHotkey()
    return noErr
}

class HotkeyManager {
    static let shared = HotkeyManager()
    private var hotkeyRef: EventHotKeyRef?

    func register() {
        // Use Carbon API for reliable global hotkey
        let hotKeyID = EventHotKeyID(signature: OSType(0x464D4420), id: 1) // "FMD " signature

        // Register the hotkey: Cmd+Opt+I (keycode 34 = 'i')
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
            NSLog("FloatMD: ERROR - Failed to install event handler: \(status)")
            return
        }

        // Register Cmd+Opt+I: keycode 34, modifiers: cmdKey (0x100) + optionKey (0x800)
        let modifiers = UInt32(cmdKey | optionKey)
        let registerStatus = RegisterEventHotKey(
            34, // 'i' key
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if registerStatus == noErr {
            NSLog("FloatMD: Global hotkey Opt+Cmd+I registered successfully (Carbon API)")
        } else {
            NSLog("FloatMD: ERROR - Failed to register hotkey: \(registerStatus)")
        }
    }

    func handleHotkey() {
        NSLog("FloatMD: Hotkey Opt+Cmd+I pressed!")
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let view = appDelegate.window.contentView as? MainView else {
            NSLog("FloatMD: ERROR - Could not get MainView")
            return
        }

        let content = view.getContent()
        NSLog("FloatMD: Content to paste: \(content.prefix(50))...")

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
        NSLog("FloatMD: Content copied to clipboard")

        // Use CGEvent to simulate Cmd+V - more reliable than AppleScript
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSLog("FloatMD: Simulating Cmd+V paste...")

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

            NSLog("FloatMD: Paste event posted")
        }
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
