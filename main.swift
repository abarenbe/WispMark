import Cocoa
import WebKit
import Carbon

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: FloatingPanel!
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the floating window
        window = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 500),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.setFrameAutosaveName("FloatMDWindow")
        
        // Configure Window
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isFloatingPanel = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        window.hasShadow = true
        
        window.contentView = MainView(frame: window.contentView!.bounds)
        window.makeKeyAndOrderFront(nil)
        
        // Setup Status Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "FloatMD")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit FloatMD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // Register Hotkey (Cmd+Opt+I)
        HotkeyManager.shared.register()
        
        // Check Permissions
        checkAccessibilityPermissions()
    }
    
    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Needed"
            alert.informativeText = "To inject text into other apps, FloatMD needs Accessibility permissions.\n\nPlease grant access in System Settings > Privacy & Security > Accessibility, then restart the app."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Floating Panel
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}

// MARK: - Main View
class MainView: NSView, NSTextViewDelegate {
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var webView: WKWebView!
    private var modeButton: NSButton!
    private var isPreviewMode = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        loadContent()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        self.wantsLayer = true
        
        // Visual Effect View (Blur background)
        let visualEffect = NSVisualEffectView(frame: bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        addSubview(visualEffect)
        
        // Text Editor
        scrollView = NSScrollView(frame: bounds)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        
        textView = NSTextView(frame: scrollView.bounds)
        textView.delegate = self
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .white
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 15, height: 40) // Top padding for title bar
        textView.insertionPointColor = .white
        
        scrollView.documentView = textView
        addSubview(scrollView)
        
        // WebView (Preview)
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.isHidden = true
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        addSubview(webView)
        
        // Toggle Button
        modeButton = NSButton(frame: NSRect(x: bounds.width - 40, y: bounds.height - 30, width: 30, height: 20))
        modeButton.bezelStyle = .inline
        modeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Preview")
        modeButton.target = self
        modeButton.action = #selector(toggleMode)
        modeButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(modeButton)
    }
    
    @objc private func toggleMode() {
        isPreviewMode.toggle()
        
        if isPreviewMode {
            let markdown = textView.string
            let html = renderMarkdown(markdown)
            webView.loadHTMLString(html, baseURL: nil)
            
            scrollView.isHidden = true
            webView.isHidden = false
            modeButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edit")
        } else {
            scrollView.isHidden = false
            webView.isHidden = true
            modeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Preview")
            window?.makeFirstResponder(textView)
        }
    }
    
    func textDidChange(_ notification: Notification) {
        saveContent()
    }
    
    private func saveContent() {
        UserDefaults.standard.set(textView.string, forKey: "savedContent")
    }
    
    private func loadContent() {
        if let content = UserDefaults.standard.string(forKey: "savedContent") {
            textView.string = content
        }
    }
    
    // Simple Markdown Renderer
    private func renderMarkdown(_ markdown: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
            body { 
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                color: white; 
                padding: 20px; 
                padding-top: 40px;
                font-size: 14px;
                line-height: 1.6;
            }
            code { background: rgba(255,255,255,0.1); padding: 2px 4px; border-radius: 3px; font-family: monospace; }
            pre { background: rgba(0,0,0,0.3); padding: 10px; border-radius: 6px; overflow-x: auto; }
            blockquote { border-left: 3px solid #7c4dff; margin: 0; padding-left: 10px; color: #aaa; }
            a { color: #7c4dff; text-decoration: none; }
            h1, h2, h3 { border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 5px; }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        </head>
        <body>
        <div id="content"></div>
        <script>
            document.getElementById('content').innerHTML = marked.parse(`\(markdown.replacingOccurrences(of: "`", with: "\\`").replacingOccurrences(of: "$", with: "\\$"))`);
        </script>
        </body>
        </html>
        """
    }
    
    func getContent() -> String {
        return textView.string
    }
}

// MARK: - Hotkey Manager
class HotkeyManager {
    static let shared = HotkeyManager()
    private var monitor: Any?

    func register() {
        // Use NSEvent global monitor instead of Carbon API
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for Cmd+Opt+I (keyCode 34 = 'i')
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 34 && flags == [.command, .option] {
                self?.handleHotkey()
            }
        }
        print("Global hotkey monitor registered")
    }
    
    func handleHotkey() {
        print("Hotkey pressed!")
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let view = appDelegate.window.contentView as? MainView else {
            print("Could not get view")
            return
        }
        
        let content = view.getContent()
        print("Content to paste: \(content.prefix(20))...")
        
        // Visual feedback (Flash the window)
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
        
        // Simulate Cmd+V using CGEvent (more reliable than AppleScript)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("Simulating Paste via CGEvent...")

            let source = CGEventSource(stateID: .hidSystemState)

            // Key down for 'v' (keycode 9) with command modifier
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            keyDown?.flags = .maskCommand

            // Key up for 'v'
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyUp?.flags = .maskCommand

            // Post the events
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            print("Paste simulated via CGEvent.")
        }
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
