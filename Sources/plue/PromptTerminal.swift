import SwiftUI
import AppKit

// MARK: - Prompt Terminal Model
class PromptTerminal: ObservableObject {
    @Published var currentContent: String = ""
    @Published var isConnected: Bool = false
    @Published var needsRedraw: Bool = false
    
    private var _tempFileURL: URL?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private let workingDirectory: URL
    
    init() {
        // Set up working directory in user's Documents/plue
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.workingDirectory = documentsURL.appendingPathComponent("plue", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    }
    
    deinit {
        stopFileWatcher()
        cleanupTempFile()
    }
    
    func startSession() {
        // Create or update the prompt file
        setupPromptFile()
        startFileWatcher()
        isConnected = true
    }
    
    private func setupPromptFile() {
        let promptFile = workingDirectory.appendingPathComponent("current_prompt.md")
        _tempFileURL = promptFile
        
        // Create initial content if file doesn't exist
        if !FileManager.default.fileExists(atPath: promptFile.path) {
            let initialContent = """
            # Prompt
            
            Write your prompt here using Markdown...
            
            ## Example
            
            You can use:
            - **Bold text**
            - *Italic text*
            - `Code blocks`
            - Lists
            - Headers
            
            ```python
            # Code examples
            def hello_world():
                print("Hello, World!")
            ```
            
            """
            
            try? initialContent.write(to: promptFile, atomically: true, encoding: .utf8)
            currentContent = initialContent
        } else {
            // Load existing content
            currentContent = (try? String(contentsOf: promptFile)) ?? ""
        }
    }
    
    private func startFileWatcher() {
        guard let tempFileURL = _tempFileURL else { return }
        
        let fileDescriptor = open(tempFileURL.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }
        
        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )
        
        fileWatcher?.setEventHandler { [weak self] in
            self?.loadFileContent()
        }
        
        fileWatcher?.setCancelHandler {
            close(fileDescriptor)
        }
        
        fileWatcher?.resume()
    }
    
    private func loadFileContent() {
        guard let tempFileURL = _tempFileURL else { return }
        
        do {
            let newContent = try String(contentsOf: tempFileURL)
            if newContent != currentContent {
                currentContent = newContent
                needsRedraw = true
            }
        } catch {
            print("Failed to read prompt file: \(error)")
        }
    }
    
    private func stopFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }
    
    private func cleanupTempFile() {
        // Don't delete the file - keep it for persistence
        _tempFileURL = nil
    }
    
    func openInEditor() {
        guard let tempFileURL = _tempFileURL else { return }
        
        // Try to open with various editors in order of preference
        let editors = [
            "/usr/local/bin/ghostty", // Ghostty terminal
            "/usr/local/bin/code",    // VS Code
            "/usr/local/bin/nvim",    // Neovim
            "/usr/local/bin/vim",     // Vim
            "/usr/bin/nano"           // Nano as fallback
        ]
        
        for editor in editors {
            if FileManager.default.fileExists(atPath: editor) {
                launchEditor(executablePath: editor, filePath: tempFileURL.path)
                return
            }
        }
        
        // Fallback to system default
        NSWorkspace.shared.open(tempFileURL)
    }
    
    private func launchEditor(executablePath: String, filePath: String) {
        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                
                if executablePath.contains("ghostty") {
                    // For Ghostty, open a new window with the editor
                    process.arguments = ["-e", "vim", filePath]
                } else if executablePath.contains("code") {
                    // For VS Code
                    process.arguments = [filePath]
                } else {
                    // For terminal editors, open in Terminal
                    process.arguments = [filePath]
                }
                
                try process.run()
                print("Launched \(executablePath) with file: \(filePath)")
            } catch {
                print("Failed to launch \(executablePath): \(error)")
            }
        }
    }
}

// MARK: - Prompt Terminal View
struct PromptTerminalView: NSViewRepresentable {
    let terminal: PromptTerminal
    let core: PlueCoreInterface
    
    func makeNSView(context: Context) -> PromptTerminalNSView {
        return PromptTerminalNSView(terminal: terminal, core: core)
    }
    
    func updateNSView(_ nsView: PromptTerminalNSView, context: Context) {
        nsView.updateContent()
    }
}

// MARK: - NSView Implementation
class PromptTerminalNSView: NSView {
    private let terminal: PromptTerminal
    private let core: PlueCoreInterface
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var headerView: NSView!
    
    init(terminal: PromptTerminal, core: PlueCoreInterface) {
        self.terminal = terminal
        self.core = core
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        // Create header with file info and buttons
        setupHeader()
        
        // Create text view for content display
        setupTextView()
        
        // Layout
        setupLayout()
        
        // Update content initially
        updateContent()
    }
    
    private func setupHeader() {
        headerView = NSView()
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.1).cgColor
        
        // File path label
        let fileLabel = NSTextField(labelWithString: "~/Documents/plue/current_prompt.md")
        fileLabel.textColor = NSColor.secondaryLabelColor
        fileLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        
        // Edit button
        let editButton = NSButton(title: "Open in Editor", target: self, action: #selector(openInEditor))
        editButton.bezelStyle = .rounded
        editButton.controlSize = .small
        
        // Terminal button
        let terminalButton = NSButton(title: "Open Terminal", target: self, action: #selector(openTerminal))
        terminalButton.bezelStyle = .rounded
        terminalButton.controlSize = .small
        
        // Add to header
        headerView.addSubview(fileLabel)
        headerView.addSubview(editButton)
        headerView.addSubview(terminalButton)
        
        // Layout header content
        fileLabel.translatesAutoresizingMaskIntoConstraints = false
        editButton.translatesAutoresizingMaskIntoConstraints = false
        terminalButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            fileLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            fileLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            terminalButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            terminalButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            editButton.trailingAnchor.constraint(equalTo: terminalButton.leadingAnchor, constant: -8),
            editButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
        
        addSubview(headerView)
    }
    
    private func setupTextView() {
        // Create scroll view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.backgroundColor = NSColor.black
        
        // Create text view
        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor.black
        textView.textColor = NSColor.textColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        
        // Set up text container
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        
        scrollView.documentView = textView
        addSubview(scrollView)
    }
    
    private func setupLayout() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func updateContent() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let content = self.terminal.currentContent
            
            // Create syntax highlighted attributed string
            let attributedString = self.syntaxHighlight(content)
            self.textView.textStorage?.setAttributedString(attributedString)
        }
    }
    
    private func syntaxHighlight(_ content: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: content)
        let fullRange = NSRange(location: 0, length: content.count)
        
        // Base attributes
        attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
        
        // Simple markdown highlighting
        let lines = content.components(separatedBy: .newlines)
        var currentLocation = 0
        
        for line in lines {
            let lineRange = NSRange(location: currentLocation, length: line.count)
            
            // Headers
            if line.hasPrefix("# ") {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: lineRange)
                attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold), range: lineRange)
            } else if line.hasPrefix("## ") {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: lineRange)
                attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 16, weight: .bold), range: lineRange)
            } else if line.hasPrefix("### ") {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: lineRange)
                attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold), range: lineRange)
            }
            
            // Code blocks
            if line.hasPrefix("```") {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: lineRange)
                attributedString.addAttribute(.backgroundColor, value: NSColor.controlBackgroundColor.withAlphaComponent(0.3), range: lineRange)
            }
            
            // Inline code
            if line.contains("`") {
                // Simple regex for inline code
                let codeRegex = try? NSRegularExpression(pattern: "`([^`]+)`", options: [])
                codeRegex?.enumerateMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) { match, _, _ in
                    if let matchRange = match?.range {
                        let adjustedRange = NSRange(location: currentLocation + matchRange.location, length: matchRange.length)
                        attributedString.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: adjustedRange)
                        attributedString.addAttribute(.backgroundColor, value: NSColor.controlBackgroundColor.withAlphaComponent(0.3), range: adjustedRange)
                    }
                }
            }
            
            currentLocation += line.count + 1 // +1 for newline
        }
        
        return attributedString
    }
    
    @objc private func openInEditor() {
        terminal.openInEditor()
    }
    
    @objc private func openTerminal() {
        guard let url = terminal.tempFileURL?.deletingLastPathComponent() else { return }
        
        // Open terminal in the working directory
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(url.path)'"
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
        }
    }
}

// MARK: - Extensions
extension PromptTerminal {
    var tempFileURL: URL? {
        return workingDirectory.appendingPathComponent("current_prompt.md")
    }
}