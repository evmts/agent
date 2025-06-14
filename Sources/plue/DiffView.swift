import SwiftUI

struct DiffView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var gitDiff: GitDiffData = GitDiffData.mock
    @State private var diffMode: DiffDisplayMode = .unified
    @State private var showLineNumbers: Bool = true
    @State private var selectedFile: String? = nil
    @State private var isRefreshing: Bool = false
    @State private var sidebarCollapsed: Bool = false
    @State private var syntaxHighlighting: Bool = true
    @State private var showWhitespace: Bool = false
    @State private var contextLines: Int = 3
    @State private var searchText: String = ""
    @State private var showSearchBar: Bool = false
    @State private var conflictResolutionMode: Bool = false
    @State private var selectedConflict: ConflictSection? = nil
    @State private var stageSelections: Set<String> = []
    @State private var showFileTree: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Professional header with better controls
            professionalDiffHeader
            
            // Search bar (conditionally shown)
            if showSearchBar {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Enhanced diff content with collapsible sidebar
            enhancedDiffContent
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
        .onAppear {
            refreshGitDiff()
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
            
            TextField("Search in diff content...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Text("\(searchResultCount) results")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            DesignSystem.Colors.surface(for: appState.currentTheme)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
                    alignment: .bottom
                )
        )
    }
    
    private var searchResultCount: Int {
        // Mock implementation - would search through diff content
        searchText.isEmpty ? 0 : 12
    }
    
    // MARK: - Professional Diff Header
    
    private var professionalDiffHeader: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Left side - Sidebar toggle and Git status
            HStack(spacing: 12) {
                // Sidebar toggle
                Button(action: { 
                    withAnimation(DesignSystem.Animation.plueSmooth) {
                        sidebarCollapsed.toggle()
                    }
                }) {
                    Image(systemName: sidebarCollapsed ? "sidebar.left" : "sidebar.left.closed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Git Changes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("\(gitDiff.changedFiles.count) files • \(gitDiff.totalAdditions)+/\(gitDiff.totalDeletions)-")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
            }
            
            Spacer()
            
            // Center - Display mode toggle
            HStack(spacing: 6) {
                Button(action: { diffMode = .sideBySide }) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 10, weight: .medium))
                        Text("side")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(diffMode == .sideBySide ? .white : DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(diffMode == .sideBySide ? DesignSystem.Colors.primary : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { diffMode = .unified }) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle")
                            .font(.system(size: 10, weight: .medium))
                        Text("unified")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(diffMode == .unified ? .white : DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(diffMode == .unified ? DesignSystem.Colors.primary : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
            
            Spacer()
            
            // Right side - Enhanced controls
            HStack(spacing: 8) {
                // Search toggle
                Button(action: { showSearchBar.toggle() }) {
                    Image(systemName: showSearchBar ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(showSearchBar ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle search")
                
                // Whitespace toggle
                Button(action: { showWhitespace.toggle() }) {
                    Image(systemName: showWhitespace ? "space" : "minus.rectangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(showWhitespace ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle whitespace display")
                
                // Syntax highlighting toggle
                Button(action: { syntaxHighlighting.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: syntaxHighlighting ? "paintbrush.fill" : "paintbrush")
                            .font(.system(size: 11, weight: .medium))
                        Text("syntax")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(syntaxHighlighting ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle syntax highlighting")
                
                // Line numbers toggle
                Button(action: { showLineNumbers.toggle() }) {
                    Image(systemName: showLineNumbers ? "list.number" : "list.bullet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(showLineNumbers ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle line numbers")
                
                // Context lines stepper
                Stepper(value: $contextLines, in: 1...10) {
                    Text("\(contextLines)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .help("Context lines: \(contextLines)")
                
                Rectangle()
                    .frame(width: 0.5, height: 16)
                    .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3))
                
                // Refresh button
                Button(action: refreshGitDiff) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh git diff")
                
                // Advanced actions menu
                Menu {
                    Button("Stage Selected Lines") { stageSelectedLines() }
                        .disabled(stageSelections.isEmpty)
                    Button("Unstage Selected Lines") { unstageSelectedLines() }
                        .disabled(stageSelections.isEmpty)
                    Divider()
                    Button("View File History") { viewFileHistory() }
                    Button("Compare with Branch...") { compareBranch() }
                    Button("Create Patch File") { createPatchFile() }
                    Divider()
                    Button("Reset File Changes") { resetFileChanges() }
                        .foregroundColor(DesignSystem.Colors.error)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .help("More actions")
                
                // Stage all button
                Button("Stage All") {
                    stageAll()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(gitDiff.changedFiles.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            DesignSystem.Colors.surface(for: appState.currentTheme)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Enhanced Diff Content
    
    private var enhancedDiffContent: some View {
        Group {
            if gitDiff.changedFiles.isEmpty {
                noChangesState
            } else {
                HStack(spacing: 0) {
                    // Collapsible sidebar
                    if !sidebarCollapsed {
                        collapsibleFileListSidebar
                            .frame(width: 280)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    
                    // Enhanced diff view with syntax highlighting
                    enhancedDiffView
                }
                .animation(DesignSystem.Animation.plueSmooth, value: sidebarCollapsed)
            }
        }
    }
    
    private var noChangesState: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Git status indicator
                Circle()
                    .fill(DesignSystem.Colors.success.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(DesignSystem.Colors.success)
                    )
                
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("No Changes")
                        .font(DesignSystem.Typography.titleMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("Working directory is clean. All changes have been committed.")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                
                // Git actions
                VStack(spacing: 6) {
                    gitActionButton("Check status", icon: "list.bullet.circle")
                    gitActionButton("View commit log", icon: "clock.arrow.circlepath")
                    gitActionButton("Create new branch", icon: "arrow.triangle.branch")
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundSecondary)
    }
    
    private func gitActionButton(_ text: String, icon: String) -> some View {
        Button(action: {
            handleGitAction(text)
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .frame(width: 16)
                
                Text(text)
                    .font(DesignSystem.Typography.labelMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 280)
    }
    
    // MARK: - Collapsible File List Sidebar
    
    private var collapsibleFileListSidebar: some View {
        VStack(spacing: 0) {
            // Enhanced sidebar header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Files")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("\(gitDiff.changedFiles.count) changed")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                
                Spacer()
                
                // File stats
                HStack(spacing: 4) {
                    Text("+\(gitDiff.totalAdditions)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.success)
                    
                    Text("-\(gitDiff.totalDeletions)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.error)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            // Subtle separator
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3))
            
            // Enhanced file list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(gitDiff.changedFiles, id: \.path) { file in
                        EnhancedGitFileRow(
                            file: file,
                            isSelected: selectedFile == file.path,
                            isStaged: stageSelections.contains(file.path),
                            theme: appState.currentTheme,
                            onSelect: { selectedFile = file.path },
                            onStageToggle: { toggleFileStaging(file.path) }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            .background(DesignSystem.Colors.background(for: appState.currentTheme))
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .overlay(
            Rectangle()
                .frame(width: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
            alignment: .trailing
        )
    }
    
    // MARK: - Enhanced Diff View
    
    private var enhancedDiffView: some View {
        Group {
            if let selectedFile = selectedFile,
               let file = gitDiff.changedFiles.first(where: { $0.path == selectedFile }) {
                VStack(spacing: 0) {
                    // File header with syntax info
                    HStack {
                        HStack(spacing: 8) {
                            // File type icon
                            Image(systemName: fileTypeIcon(for: file.path))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(fileTypeColor(for: file.path))
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.path)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                                
                                Text("\(file.changeType.description) • \(fileLanguage(for: file.path))")
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                            }
                        }
                        
                        Spacer()
                        
                        // Change stats
                        HStack(spacing: 8) {
                            Text("+\(file.additions)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(DesignSystem.Colors.success)
                            
                            Text("-\(file.deletions)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(DesignSystem.Colors.error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.surface(for: appState.currentTheme))
                    
                    // Enhanced diff content
                    if conflictResolutionMode && file.hasConflicts {
                        ConflictResolutionView(
                            file: file,
                            selectedConflict: $selectedConflict,
                            theme: appState.currentTheme
                        )
                    } else {
                        SyntaxHighlightedDiffView(
                            file: file,
                            showLineNumbers: showLineNumbers,
                            syntaxHighlighting: syntaxHighlighting,
                            showWhitespace: showWhitespace,
                            contextLines: contextLines,
                            searchText: searchText,
                            theme: appState.currentTheme
                        )
                    }
                }
            } else {
                enhancedSelectFilePrompt
            }
        }
    }
    
    private var enhancedSelectFilePrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: sidebarCollapsed ? "sidebar.left" : "doc.text")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
            
            VStack(spacing: 8) {
                Text(sidebarCollapsed ? "Show sidebar to view files" : "Select a file to view diff")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                if sidebarCollapsed {
                    Button("Show Sidebar") {
                        withAnimation(DesignSystem.Animation.plueSmooth) {
                            sidebarCollapsed = false
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
    }
    
    // MARK: - Helper Functions
    
    private func fileTypeIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts": return "doc.text.fill"
        case "py": return "terminal.fill"
        case "md": return "doc.plaintext"
        case "json": return "curlybraces"
        case "yaml", "yml": return "doc.text"
        default: return "doc"
        }
    }
    
    private func fileTypeColor(for path: String) -> Color {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "ts": return .yellow
        case "py": return .blue
        case "md": return .gray
        case "json": return .green
        default: return DesignSystem.Colors.textTertiary
        }
    }
    
    private func fileLanguage(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "Swift"
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "py": return "Python"
        case "md": return "Markdown"
        case "json": return "JSON"
        case "yaml", "yml": return "YAML"
        default: return "Text"
        }
    }
    
    // MARK: - Git Diff Views
    
    private var sideBySideGitDiffView: some View {
        Group {
            if let selectedFile = selectedFile,
               let file = gitDiff.changedFiles.first(where: { $0.path == selectedFile }) {
                GitSideBySideDiffView(file: file, showLineNumbers: showLineNumbers)
            } else {
                selectFilePrompt
            }
        }
    }
    
    private var unifiedGitDiffView: some View {
        Group {
            if let selectedFile = selectedFile,
               let file = gitDiff.changedFiles.first(where: { $0.path == selectedFile }) {
                GitUnifiedDiffView(file: file, showLineNumbers: showLineNumbers)
            } else {
                selectFilePrompt
            }
        }
    }
    
    private var selectFilePrompt: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "arrow.left")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            Text("Select a file to view diff")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundSecondary)
    }
    
    // MARK: - Actions
    
    private func refreshGitDiff() {
        isRefreshing = true
        
        // Simulate git diff refresh - in real implementation, this would call git
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Mock refresh - in reality this would run `git diff` and parse output
            gitDiff = GitDiffData.mock
            isRefreshing = false
            
            // Auto-select first file if none selected
            if selectedFile == nil && !gitDiff.changedFiles.isEmpty {
                selectedFile = gitDiff.changedFiles.first?.path
            }
        }
    }
    
    private func stageAll() {
        // Mock staging all files - in reality this would run `git add .`
        print("Staging all changes...")
        
        // Show visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("All changes staged")
        }
    }
    
    private func handleGitAction(_ action: String) {
        switch action {
        case "Check status":
            print("Running git status...")
        case "View commit log":
            print("Opening git log...")
        case "Create new branch":
            print("Creating new branch...")
        default:
            break
        }
    }
    
    // MARK: - Enhanced Actions
    
    private func stageSelectedLines() {
        print("Staging selected lines...")
    }
    
    private func unstageSelectedLines() {
        print("Unstaging selected lines...")
    }
    
    private func viewFileHistory() {
        guard let selectedFile = selectedFile else { return }
        print("Viewing history for \(selectedFile)")
    }
    
    private func compareBranch() {
        print("Compare with branch...")
    }
    
    private func createPatchFile() {
        print("Creating patch file...")
    }
    
    private func resetFileChanges() {
        guard let selectedFile = selectedFile else { return }
        print("Resetting changes for \(selectedFile)")
    }
    
    private func toggleFileStaging(_ filePath: String) {
        if stageSelections.contains(filePath) {
            stageSelections.remove(filePath)
        } else {
            stageSelections.insert(filePath)
        }
    }
}

// MARK: - Supporting Views

struct EnhancedGitFileRow: View {
    let file: GitChangedFile
    let isSelected: Bool
    let isStaged: Bool
    let theme: DesignSystem.Theme
    let onSelect: () -> Void
    let onStageToggle: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Staging checkbox
                Button(action: onStageToggle) {
                    Image(systemName: isStaged ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isStaged ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary(for: theme))
                }
                .buttonStyle(PlainButtonStyle())
                .help(isStaged ? "Unstage file" : "Stage file")
                
                // File type icon
                Image(systemName: fileTypeIcon(for: file.path))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(fileTypeColor(for: file.path))
                    .frame(width: 14)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(fileName(from: file.path))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? DesignSystem.Colors.textPrimary(for: theme) : DesignSystem.Colors.textPrimary(for: theme))
                        .lineLimit(1)
                    
                    Text(filePath(from: file.path))
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                // Change indicator and stats
                HStack(spacing: 6) {
                    Circle()
                        .fill(file.changeType.color)
                        .frame(width: 6, height: 6)
                    
                    if file.additions > 0 || file.deletions > 0 {
                        HStack(spacing: 2) {
                            if file.additions > 0 {
                                Text("+\(file.additions)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(DesignSystem.Colors.success)
                            }
                            if file.deletions > 0 {
                                Text("-\(file.deletions)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(DesignSystem.Colors.error)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? DesignSystem.Colors.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
            .animation(DesignSystem.Animation.plueStandard, value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
    }
    
    private func fileName(from path: String) -> String {
        return (path as NSString).lastPathComponent
    }
    
    private func filePath(from path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "/" : dir
    }
    
    private func fileTypeIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts": return "doc.text.fill"
        case "py": return "terminal.fill"
        case "md": return "doc.plaintext"
        case "json": return "curlybraces"
        case "yaml", "yml": return "doc.text"
        default: return "doc"
        }
    }
    
    private func fileTypeColor(for path: String) -> Color {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "ts": return .yellow
        case "py": return .blue
        case "md": return .gray
        case "json": return .green
        default: return DesignSystem.Colors.textTertiary
        }
    }
}

struct SyntaxHighlightedDiffView: View {
    let file: GitChangedFile
    let showLineNumbers: Bool
    let syntaxHighlighting: Bool
    let showWhitespace: Bool
    let contextLines: Int
    let searchText: String
    let theme: DesignSystem.Theme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(file.diffLines.enumerated()), id: \.offset) { index, line in
                    SyntaxHighlightedDiffLine(
                        line: line,
                        showLineNumbers: showLineNumbers,
                        syntaxHighlighting: syntaxHighlighting,
                        theme: theme,
                        fileType: fileType(for: file.path)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(DesignSystem.Colors.background(for: theme))
    }
    
    private func fileType(for path: String) -> String {
        return (path as NSString).pathExtension.lowercased()
    }
}

struct SyntaxHighlightedDiffLine: View {
    let line: GitDiffLine
    let showLineNumbers: Bool
    let syntaxHighlighting: Bool
    let theme: DesignSystem.Theme
    let fileType: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if showLineNumbers {
                HStack(spacing: 8) {
                    Text(line.oldLineNumber.map(String.init) ?? "")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme).opacity(0.6))
                        .frame(minWidth: 30, alignment: .trailing)
                    
                    Text(line.newLineNumber.map(String.init) ?? "")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme).opacity(0.6))
                        .frame(minWidth: 30, alignment: .trailing)
                }
                .padding(.trailing, 12)
            }
            
            HStack(spacing: 8) {
                Text(line.type.prefix)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(line.type.color)
                    .frame(width: 12, alignment: .leading)
                
                if syntaxHighlighting && !line.content.trimmingCharacters(in: .whitespaces).isEmpty {
                    syntaxHighlightedText(line.content)
                } else {
                    Text(line.content)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(line.type.textColor)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 1)
        .background(line.type.backgroundColor.opacity(0.08))
    }
    
    @ViewBuilder
    private func syntaxHighlightedText(_ content: String) -> some View {
        // Simple syntax highlighting for common patterns
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        
        if fileType == "swift" {
            swiftSyntaxHighlighting(content)
        } else if fileType == "json" {
            jsonSyntaxHighlighting(content)
        } else {
            Text(content)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(line.type.textColor)
        }
    }
    
    @ViewBuilder
    private func swiftSyntaxHighlighting(_ content: String) -> some View {
        let keywords = ["import", "struct", "class", "func", "var", "let", "if", "else", "for", "while", "return", "private", "public", "internal"]
        let text = content
        
        if keywords.contains(where: text.contains) {
            Text(content)
                .font(.system(size: 12, weight: text.contains("func") || text.contains("struct") || text.contains("class") ? .semibold : .regular, design: .monospaced))
                .foregroundColor(text.contains("//") ? DesignSystem.Colors.success.opacity(0.8) : 
                               keywords.contains(where: text.contains) ? DesignSystem.Colors.primary : 
                               line.type.textColor)
        } else {
            Text(content)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(line.type.textColor)
        }
    }
    
    @ViewBuilder
    private func jsonSyntaxHighlighting(_ content: String) -> some View {
        let text = content.trimmingCharacters(in: .whitespaces)
        
        Text(content)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundColor(
                text.hasPrefix("\"") && text.hasSuffix(":") ? DesignSystem.Colors.primary :
                text.hasPrefix("\"") ? DesignSystem.Colors.success :
                ["true", "false", "null"].contains(text) ? DesignSystem.Colors.warning :
                line.type.textColor
            )
    }
}

struct GitFileRowView: View {
    let file: GitChangedFile
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Change type indicator
                Text(file.changeType.symbol)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(file.changeType.color)
                    .frame(width: 12)
                
                // File path
                Text(file.path)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Spacer()
                
                // Change stats
                HStack(spacing: 4) {
                    if file.additions > 0 {
                        Text("+\(file.additions)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.success)
                    }
                    if file.deletions > 0 {
                        Text("-\(file.deletions)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? DesignSystem.Colors.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GitSideBySideDiffView: View {
    let file: GitChangedFile
    let showLineNumbers: Bool
    
    var body: some View {
        HStack(spacing: 1) {
            // Original (left side)
            VStack(spacing: 0) {
                DiffPaneHeader(title: "Original", file: file.path)
                GitDiffPaneView(content: file.originalContent, showLineNumbers: showLineNumbers, isOriginal: true)
            }
            
            // Divider
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.3))
                .frame(width: 1)
            
            // Modified (right side)  
            VStack(spacing: 0) {
                DiffPaneHeader(title: "Modified", file: file.path)
                GitDiffPaneView(content: file.modifiedContent, showLineNumbers: showLineNumbers, isOriginal: false)
            }
        }
    }
}

struct GitUnifiedDiffView: View {
    let file: GitChangedFile
    let showLineNumbers: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Unified header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.path)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("\(file.changeType.description) • +\(file.additions)/-\(file.deletions)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                Text(file.changeType.symbol)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(file.changeType.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.surface)
            
            // Unified diff content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(file.diffLines.enumerated()), id: \.offset) { index, line in
                        GitDiffLineView(
                            line: line,
                            showLineNumbers: showLineNumbers
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            }
            .background(DesignSystem.Colors.backgroundSecondary)
        }
    }
}

struct DiffPaneHeader: View {
    let title: String
    let file: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Spacer()
            
            Text(file)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.surface)
    }
}

struct GitDiffPaneView: View {
    let content: String
    let showLineNumbers: Bool
    let isOriginal: Bool
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 8) {
                if showLineNumbers {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(content.components(separatedBy: .newlines).enumerated()), id: \.offset) { index, _ in
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.6))
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                    .padding(.leading, 8)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(content.components(separatedBy: .newlines).enumerated()), id: \.offset) { index, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(DesignSystem.Colors.backgroundSecondary)
    }
}

struct GitDiffLineView: View {
    let line: GitDiffLine
    let showLineNumbers: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showLineNumbers {
                HStack(spacing: 4) {
                    Text(line.oldLineNumber.map(String.init) ?? "")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.6))
                        .frame(minWidth: 25, alignment: .trailing)
                    
                    Text(line.newLineNumber.map(String.init) ?? "")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.6))
                        .frame(minWidth: 25, alignment: .trailing)
                }
            }
            
            HStack(spacing: 4) {
                Text(line.type.prefix)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(line.type.color)
                
                Text(line.content)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(line.type.textColor)
            }
            
            Spacer()
        }
        .padding(.vertical, 1)
        .background(line.type.backgroundColor.opacity(0.1))
    }
}

// MARK: - Supporting Types

enum DiffDisplayMode {
    case sideBySide
    case unified
}

// MARK: - New Supporting Types

struct ConflictSection: Identifiable {
    let id = UUID()
    let startLine: Int
    let endLine: Int
    let ourContent: String
    let theirContent: String
    let baseContent: String?
}

struct ConflictResolutionView: View {
    let file: GitChangedFile
    @Binding var selectedConflict: ConflictSection?
    let theme: DesignSystem.Theme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Conflict resolution header
                HStack {
                    Text("Merge Conflicts")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                    
                    Spacer()
                    
                    Text("\(file.conflicts.count) conflicts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.error)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DesignSystem.Colors.error.opacity(0.1))
                        )
                }
                .padding(.horizontal, 16)
                
                // Conflict sections
                ForEach(file.conflicts) { conflict in
                    ConflictCard(
                        conflict: conflict,
                        isSelected: selectedConflict?.id == conflict.id,
                        theme: theme,
                        onSelect: { selectedConflict = conflict }
                    )
                }
            }
            .padding(.vertical, 16)
        }
        .background(DesignSystem.Colors.background(for: theme))
    }
}

struct ConflictCard: View {
    let conflict: ConflictSection
    let isSelected: Bool
    let theme: DesignSystem.Theme
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Conflict header
            HStack {
                Text("Lines \(conflict.startLine)-\(conflict.endLine)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Accept Ours") {
                        acceptOurs()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Accept Theirs") {
                        acceptTheirs()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button("Edit") {
                        onSelect()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            
            // Conflict content
            VStack(alignment: .leading, spacing: 8) {
                // Our version
                VStack(alignment: .leading, spacing: 4) {
                    Text("HEAD (Current)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.success)
                    
                    Text(conflict.ourContent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DesignSystem.Colors.success.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(DesignSystem.Colors.success.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
                
                // Their version
                VStack(alignment: .leading, spacing: 4) {
                    Text("Incoming")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    Text(conflict.theirContent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DesignSystem.Colors.primary.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.Colors.surface(for: theme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.border(for: theme).opacity(0.3), lineWidth: isSelected ? 2 : 1)
                )
        )
        .padding(.horizontal, 16)
    }
    
    private func acceptOurs() {
        print("Accepting our version for conflict at lines \(conflict.startLine)-\(conflict.endLine)")
    }
    
    private func acceptTheirs() {
        print("Accepting their version for conflict at lines \(conflict.startLine)-\(conflict.endLine)")
    }
}

// Git diff data models
struct GitDiffData {
    let changedFiles: [GitChangedFile]
    let totalAdditions: Int
    let totalDeletions: Int
    
    static let mock = GitDiffData(
        changedFiles: [
            GitChangedFile.mockSwiftFile,
            GitChangedFile.mockReadme,
            GitChangedFile.mockConfig
        ],
        totalAdditions: 42,
        totalDeletions: 18
    )
}

struct GitChangedFile {
    let path: String
    let changeType: GitChangeType
    let additions: Int
    let deletions: Int
    let originalContent: String
    let modifiedContent: String
    let diffLines: [GitDiffLine]
    let hasConflicts: Bool
    let conflicts: [ConflictSection]
    
    static let mockSwiftFile = GitChangedFile(
        path: "Sources/plue/DiffView.swift",
        changeType: .modified,
        additions: 25,
        deletions: 8,
        originalContent: "import SwiftUI\n\nstruct DiffView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}",
        modifiedContent: "import SwiftUI\n\nstruct DiffView: View {\n    let appState: AppState\n    \n    var body: some View {\n        VStack {\n            Text(\"Git Diff Viewer\")\n            Text(\"Now with more features!\")\n        }\n    }\n}",
        hasConflicts: false,
        conflicts: [],
        diffLines: [
            GitDiffLine(type: .unchanged, content: "import SwiftUI", oldLineNumber: 1, newLineNumber: 1),
            GitDiffLine(type: .unchanged, content: "", oldLineNumber: 2, newLineNumber: 2),
            GitDiffLine(type: .unchanged, content: "struct DiffView: View {", oldLineNumber: 3, newLineNumber: 3),
            GitDiffLine(type: .added, content: "    let appState: AppState", oldLineNumber: nil, newLineNumber: 4),
            GitDiffLine(type: .added, content: "", oldLineNumber: nil, newLineNumber: 5),
            GitDiffLine(type: .unchanged, content: "    var body: some View {", oldLineNumber: 4, newLineNumber: 6),
            GitDiffLine(type: .removed, content: "        Text(\"Hello\")", oldLineNumber: 5, newLineNumber: nil),
            GitDiffLine(type: .added, content: "        VStack {", oldLineNumber: nil, newLineNumber: 7),
            GitDiffLine(type: .added, content: "            Text(\"Git Diff Viewer\")", oldLineNumber: nil, newLineNumber: 8),
            GitDiffLine(type: .added, content: "            Text(\"Now with more features!\")", oldLineNumber: nil, newLineNumber: 9),
            GitDiffLine(type: .added, content: "        }", oldLineNumber: nil, newLineNumber: 10),
            GitDiffLine(type: .unchanged, content: "    }", oldLineNumber: 6, newLineNumber: 11),
            GitDiffLine(type: .unchanged, content: "}", oldLineNumber: 7, newLineNumber: 12)
        ]
    )
    
    static let mockReadme = GitChangedFile(
        path: "README.md",
        changeType: .modified,
        additions: 12,
        deletions: 5,
        originalContent: "# Plue\nA development tool",
        modifiedContent: "# Plue\nA multi-agent coding assistant\n\n## Features\n- Git diff viewer\n- AI assistance",
        hasConflicts: false,
        conflicts: [],
        diffLines: [
            GitDiffLine(type: .unchanged, content: "# Plue", oldLineNumber: 1, newLineNumber: 1),
            GitDiffLine(type: .removed, content: "A development tool", oldLineNumber: 2, newLineNumber: nil),
            GitDiffLine(type: .added, content: "A multi-agent coding assistant", oldLineNumber: nil, newLineNumber: 2),
            GitDiffLine(type: .added, content: "", oldLineNumber: nil, newLineNumber: 3),
            GitDiffLine(type: .added, content: "## Features", oldLineNumber: nil, newLineNumber: 4),
            GitDiffLine(type: .added, content: "- Git diff viewer", oldLineNumber: nil, newLineNumber: 5),
            GitDiffLine(type: .added, content: "- AI assistance", oldLineNumber: nil, newLineNumber: 6)
        ]
    )
    
    static let mockConfig = GitChangedFile(
        path: ".gitignore",
        changeType: .added,
        additions: 5,
        deletions: 0,
        originalContent: "",
        modifiedContent: ".DS_Store\n*.xcworkspace\n.build/\nPackage.resolved\n",
        hasConflicts: false,
        conflicts: [],
        diffLines: [
            GitDiffLine(type: .added, content: ".DS_Store", oldLineNumber: nil, newLineNumber: 1),
            GitDiffLine(type: .added, content: "*.xcworkspace", oldLineNumber: nil, newLineNumber: 2),
            GitDiffLine(type: .added, content: ".build/", oldLineNumber: nil, newLineNumber: 3),
            GitDiffLine(type: .added, content: "Package.resolved", oldLineNumber: nil, newLineNumber: 4)
        ]
    )
}

struct GitDiffLine {
    let type: GitDiffLineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

enum GitChangeType {
    case added
    case modified
    case deleted
    case renamed
    
    var symbol: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"  
        case .renamed: return "R"
        }
    }
    
    var color: Color {
        switch self {
        case .added: return DesignSystem.Colors.success
        case .modified: return DesignSystem.Colors.warning
        case .deleted: return DesignSystem.Colors.error
        case .renamed: return DesignSystem.Colors.primary
        }
    }
    
    var description: String {
        switch self {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        }
    }
}

enum GitDiffLineType {
    case added
    case removed
    case unchanged
    
    var prefix: String {
        switch self {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        }
    }
    
    var color: Color {
        switch self {
        case .added: return DesignSystem.Colors.success
        case .removed: return DesignSystem.Colors.error
        case .unchanged: return DesignSystem.Colors.textTertiary
        }
    }
    
    var textColor: Color {
        switch self {
        case .added: return DesignSystem.Colors.textPrimary
        case .removed: return DesignSystem.Colors.textPrimary
        case .unchanged: return DesignSystem.Colors.textPrimary
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .added: return DesignSystem.Colors.success
        case .removed: return DesignSystem.Colors.error
        case .unchanged: return Color.clear
        }
    }
}

#Preview {
    DiffView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}