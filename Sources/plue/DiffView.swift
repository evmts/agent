import SwiftUI

struct DiffView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var gitDiff: GitDiffData = GitDiffData.mock
    @State private var diffMode: DiffDisplayMode = .unified
    @State private var showLineNumbers: Bool = true
    @State private var selectedFile: String? = nil
    @State private var isRefreshing: Bool = false
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with controls
                diffHeaderBar
                
                // Main diff area
                diffContentArea
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            refreshGitDiff()
        }
    }
    
    // MARK: - Header Bar
    
    private var diffHeaderBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Left side - Git status
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("git diff")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Text("\(gitDiff.changedFiles.count) files • \(gitDiff.totalAdditions)+/\(gitDiff.totalDeletions)-")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
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
            
            // Right side - Git actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Refresh button
                Button(action: refreshGitDiff) {
                    HStack(spacing: 4) {
                        Image(systemName: isRefreshing ? "arrow.clockwise" : "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        Text("refresh")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh git diff")
                
                // Line numbers toggle
                Button(action: { showLineNumbers.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showLineNumbers ? "list.number" : "list.bullet")
                            .font(.system(size: 11, weight: .medium))
                        Text("lines")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(showLineNumbers ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle line numbers")
                
                // Stage all button  
                Button(action: stageAll) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11, weight: .medium))
                        Text("stage")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(DesignSystem.Colors.success)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Stage all changes")
                .disabled(gitDiff.changedFiles.isEmpty)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(
            DesignSystem.Colors.surface
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignSystem.Colors.border.opacity(0.3)),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Content Area
    
    private var diffContentArea: some View {
        Group {
            if gitDiff.changedFiles.isEmpty {
                noChangesState
            } else {
                HSplitView {
                    // Left sidebar - File list
                    fileListSidebar
                    
                    // Right side - Diff view
                    switch diffMode {
                    case .sideBySide:
                        sideBySideGitDiffView
                    case .unified:
                        unifiedGitDiffView
                    }
                }
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
    
    // MARK: - File List Sidebar
    
    private var fileListSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar header
            HStack {
                Text("Changed Files")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
                
                Text("\(gitDiff.changedFiles.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DesignSystem.Colors.surface)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.surface)
            
            // File list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(gitDiff.changedFiles, id: \.path) { file in
                        GitFileRowView(
                            file: file,
                            isSelected: selectedFile == file.path,
                            onSelect: { selectedFile = file.path }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .background(DesignSystem.Colors.backgroundSecondary)
        }
        .frame(minWidth: 200, maxWidth: 300)
        .background(DesignSystem.Colors.backgroundSecondary)
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
}

// MARK: - Supporting Views

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
    
    static let mockSwiftFile = GitChangedFile(
        path: "Sources/plue/DiffView.swift",
        changeType: .modified,
        additions: 25,
        deletions: 8,
        originalContent: "import SwiftUI\n\nstruct DiffView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}",
        modifiedContent: "import SwiftUI\n\nstruct DiffView: View {\n    let appState: AppState\n    \n    var body: some View {\n        VStack {\n            Text(\"Git Diff Viewer\")\n            Text(\"Now with more features!\")\n        }\n    }\n}",
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