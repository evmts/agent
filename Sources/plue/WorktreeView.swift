import SwiftUI

struct WorktreeView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    // Enhanced state management for worktree features
    @State private var worktrees: [GitWorktree] = GitWorktree.mockWorktrees
    @State private var selectedWorktreeId: String? = GitWorktree.mockWorktrees.first?.id
    @State private var showCreateDialog: Bool = false
    @State private var searchText: String = ""
    @State private var filterStatus: WorktreeStatusFilter = .all
    @State private var sortOrder: WorktreeSortOrder = .recentActivity
    @State private var showDeleteConfirmation: Bool = false
    @State private var worktreeToDelete: GitWorktree? = nil
    @State private var isRefreshing: Bool = false
    @State private var newWorktreeName: String = ""
    @State private var newWorktreeBranch: String = ""
    
    var body: some View {
        HSplitView {
            // Left Panel: Worktree List
            worktreeList
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
            
            // Right Panel: Stacked Diff Visualization
            stackedDiffDetail
        }
        .background(DesignSystem.Colors.backgroundSecondary(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
        .sheet(isPresented: $showCreateDialog) {
            CreateWorktreeDialog(
                newWorktreeName: $newWorktreeName,
                newWorktreeBranch: $newWorktreeBranch,
                onCancel: { showCreateDialog = false },
                onCreate: createNewWorktree
            )
        }
        .alert("Delete Worktree", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let worktree = worktreeToDelete {
                    deleteWorktree(worktree)
                }
            }
        } message: {
            if let worktree = worktreeToDelete {
                Text("Are you sure you want to delete the worktree '\\(worktree.branch)'? This action cannot be undone.")
            }
        }
    }
    
    private var worktreeList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Worktrees")
                        .font(DesignSystem.Typography.titleSmall)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("git parallel development")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Search and filter controls
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                        
                        TextField("Search worktrees...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.background(for: appState.currentTheme))
                    )
                    .frame(maxWidth: 120)
                    
                    // Filter menu
                    Menu {
                        Button("All") { filterStatus = .all }
                        Button("Clean") { filterStatus = .clean }
                        Button("Modified") { filterStatus = .modified }
                        Button("Conflicts") { filterStatus = .conflicts }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .help("Filter worktrees")
                    
                    // Sort menu
                    Menu {
                        Button("Recent Activity") { sortOrder = .recentActivity }
                        Button("Alphabetical") { sortOrder = .alphabetical }
                        Button("Status") { sortOrder = .status }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .help("Sort worktrees")
                    
                    // Refresh button
                    Button(action: refreshWorktrees) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Refresh worktrees")
                    
                    // Create new worktree
                    Button(action: { showCreateDialog = true }) { 
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Create new worktree")
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
                alignment: .bottom
            )

            // The list itself
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(worktrees.enumerated()), id: \.element.id) { index, worktree in
                        WorktreeRow(
                            worktree: worktree, 
                            isSelected: selectedWorktreeId == worktree.id,
                            theme: appState.currentTheme
                        )
                        .onTapGesture {
                            withAnimation(DesignSystem.Animation.scaleIn) {
                                selectedWorktreeId = worktree.id
                            }
                        }
                        .animation(
                            DesignSystem.Animation.slideTransition.delay(Double(index) * DesignSystem.Animation.staggerDelay),
                            value: selectedWorktreeId
                        )
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .background(DesignSystem.Colors.background(for: appState.currentTheme))
        }
    }
    
    private var stackedDiffDetail: some View {
        VStack {
            if let worktree = worktrees.first(where: { $0.id == selectedWorktreeId }) {
                // This contains the Graphite-style stacked diff view
                GraphiteStackView(worktree: worktree, appState: appState)
            } else {
                // Empty state
                VStack(spacing: DesignSystem.Spacing.xl) {
                    Circle()
                        .fill(DesignSystem.Colors.textTertiary(for: appState.currentTheme).opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 24, weight: .light))
                                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                        )
                    
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text("no worktree selected")
                            .font(DesignSystem.Typography.titleMedium)
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                        
                        Text("select a worktree to view its stack")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.background(for: appState.currentTheme))
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredAndSortedWorktrees: [GitWorktree] {
        let filtered = worktrees.filter { worktree in
            // Search filter
            let matchesSearch = searchText.isEmpty || 
                               worktree.branch.localizedCaseInsensitiveContains(searchText) ||
                               worktree.path.localizedCaseInsensitiveContains(searchText)
            
            // Status filter
            let matchesStatus: Bool
            switch filterStatus {
            case .all: matchesStatus = true
            case .clean: matchesStatus = worktree.status == .clean
            case .modified: matchesStatus = worktree.status == .modified
            case .conflicts: matchesStatus = worktree.status == .conflicts
            }
            
            return matchesSearch && matchesStatus
        }
        
        // Sort
        switch sortOrder {
        case .recentActivity:
            return filtered.sorted { $0.lastModified > $1.lastModified }
        case .alphabetical:
            return filtered.sorted { $0.branch < $1.branch }
        case .status:
            return filtered.sorted { $0.status.sortOrder < $1.status.sortOrder }
        }
    }
    
    // MARK: - Actions
    
    private func refreshWorktrees() {
        isRefreshing = true
        // Simulate refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isRefreshing = false
            // In real implementation, would reload from git
        }
    }
    
    private func createNewWorktree() {
        print("Creating worktree: \\(newWorktreeName) on branch: \\(newWorktreeBranch)")
        showCreateDialog = false
        newWorktreeName = ""
        newWorktreeBranch = ""
    }
    
    private func switchToWorktree(_ worktree: GitWorktree) {
        print("Switching to worktree: \\(worktree.branch)")
    }
    
    private func pullWorktree(_ worktree: GitWorktree) {
        print("Pulling changes for: \\(worktree.branch)")
    }
    
    private func pushWorktree(_ worktree: GitWorktree) {
        print("Pushing changes for: \\(worktree.branch)")
    }
    
    private func openInFinder(_ worktree: GitWorktree) {
        print("Opening \\(worktree.path) in Finder")
    }
    
    private func openInTerminal(_ worktree: GitWorktree) {
        print("Opening \\(worktree.path) in Terminal")
    }
    
    private func deleteWorktree(_ worktree: GitWorktree) {
        print("Deleting worktree: \\(worktree.branch)")
        worktrees.removeAll { $0.id == worktree.id }
        if selectedWorktreeId == worktree.id {
            selectedWorktreeId = worktrees.first?.id
        }
    }
}

// Redesigned Row with Apple-style spacing and subtle interactions
struct WorktreeRow: View {
    let worktree: GitWorktree
    let isSelected: Bool
    let theme: DesignSystem.Theme
    
    var body: some View {
        HStack(spacing: 16) { // Increased spacing for better breathing room
            // Simplified status indicator with glow effect
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 8)
                        .blur(radius: 4)
                        .opacity(isSelected ? 1 : 0)
                )
                .animation(DesignSystem.Animation.plueSmooth, value: isSelected)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(worktree.branch)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.85))
                    
                    if worktree.isMain {
                        Text("main")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                }
                
                Text(timeAgoString)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .animation(DesignSystem.Animation.plueStandard, value: isSelected)
    }
    
    private var statusColor: Color {
        switch worktree.status {
        case .clean: return DesignSystem.Colors.success
        case .modified: return DesignSystem.Colors.warning
        case .untracked: return DesignSystem.Colors.primary
        case .conflicts: return DesignSystem.Colors.error
        }
    }
    
    private var abbreviatedPath: String {
        let components = worktree.path.components(separatedBy: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return worktree.path
    }
    
    private var timeAgoString: String {
        let now = Date()
        let interval = now.timeIntervalSince(worktree.lastModified)
        
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// Extension for GitWorktreeStatus
extension GitWorktreeStatus {
    var displayName: String {
        switch self {
        case .clean: return "clean"
        case .modified: return "modified"
        case .untracked: return "untracked"
        case .conflicts: return "conflicts"
        }
    }
}

// The advanced Graphite-style stack view with cleaner header
struct GraphiteStackView: View {
    let worktree: GitWorktree
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Cleaner header without bottom border
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(worktree.branch)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("\(MockCommit.samples.count) commits")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Pull") {
                        print("Pull changes")
                    }
                    .buttonStyle(GhostButtonStyle())
                    
                    Button("Push") {
                        print("Push stack")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(24) // More generous padding
            
            // Stack visualization with better spacing
            ScrollView {
                VStack(spacing: 1) { // Minimal spacing
                    ForEach(MockCommit.samples) { commit in
                        CommitDiffView(
                            commit: commit, 
                            theme: appState.currentTheme
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(DesignSystem.Colors.background(for: appState.currentTheme))
        }
    }
}

// Mock commit data
struct MockCommit: Identifiable {
    let id: String
    let shortId: String
    let message: String
    let author: String
    let timestamp: Date
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
    
    static let samples: [MockCommit] = [
        MockCommit(
            id: "a1b2c3d4e5f6",
            shortId: "a1b2c3d",
            message: "feat: Add agent coordination protocol",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-3600),
            filesChanged: 3,
            insertions: 127,
            deletions: 8
        ),
        MockCommit(
            id: "b2c3d4e5f6a1",
            shortId: "b2c3d4e",
            message: "refactor: Improve the rendering engine",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-7200),
            filesChanged: 5,
            insertions: 89,
            deletions: 34
        ),
        MockCommit(
            id: "c3d4e5f6a1b2",
            shortId: "c3d4e5f",
            message: "fix: Terminal cursor positioning bug",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-10800),
            filesChanged: 1,
            insertions: 12,
            deletions: 5
        ),
        MockCommit(
            id: "d4e5f6a1b2c3",
            shortId: "d4e5f6a",
            message: "docs: Update README with new features",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-14400),
            filesChanged: 2,
            insertions: 45,
            deletions: 2
        ),
        MockCommit(
            id: "e5f6a1b2c3d4",
            shortId: "e5f6a1b",
            message: "style: Apply consistent color scheme",
            author: "Developer",
            timestamp: Date().addingTimeInterval(-18000),
            filesChanged: 8,
            insertions: 203,
            deletions: 156
        )
    ]
}

// Each commit in the stack is a collapsible diff
struct CommitDiffView: View {
    let commit: MockCommit
    let theme: DesignSystem.Theme
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { 
                withAnimation(DesignSystem.Animation.smooth) { 
                    isExpanded.toggle() 
                } 
            }) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                        .frame(width: 12)
                    
                    // Commit hash
                    Text(commit.shortId)
                        .font(DesignSystem.Typography.monoSmall)
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DesignSystem.Colors.primary.opacity(0.1))
                        )
                    
                    // Commit message
                    Text(commit.message)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Stats
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("\(commit.filesChanged)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                        
                        Text("+\(commit.insertions)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.success)
                        
                        Text("-\(commit.deletions)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.surface(for: theme))
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                // Here you would embed the actual DiffView for this commit
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Diff content for \(commit.shortId)")
                        .font(DesignSystem.Typography.monoMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: theme))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    
                    // Mock diff content with staggered lines
                    VStack(alignment: .leading, spacing: 2) {
                        let diffLines = [
                            ("- old implementation", DiffLine.DiffLineType.removed),
                            ("+ new improved implementation", DiffLine.DiffLineType.added),
                            ("  unchanged line", DiffLine.DiffLineType.context),
                            ("+ another addition", DiffLine.DiffLineType.added)
                        ]
                        
                        ForEach(Array(diffLines.enumerated()), id: \.offset) { index, line in
                            DiffLine(content: line.0, type: line.1, theme: theme)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .opacity
                                ))
                                .animation(
                                    DesignSystem.Animation.slideTransition.delay(Double(index) * DesignSystem.Animation.staggerDelay),
                                    value: isExpanded
                                )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.sm)
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.background(for: theme))
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .animation(DesignSystem.Animation.smooth, value: isExpanded)
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: theme).opacity(0.2)),
            alignment: .bottom
        )
    }
}

// Simple diff line component
struct DiffLine: View {
    let content: String
    let type: DiffLineType
    let theme: DesignSystem.Theme
    
    enum DiffLineType {
        case added, removed, context
    }
    
    var body: some View {
        Text(content)
            .font(DesignSystem.Typography.monoSmall)
            .foregroundColor(textColor)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 1)
            .background(backgroundColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var textColor: Color {
        switch type {
        case .added: return DesignSystem.Colors.success
        case .removed: return DesignSystem.Colors.error
        case .context: return DesignSystem.Colors.textSecondary(for: theme)
        }
    }
    
    private var backgroundColor: Color {
        switch type {
        case .added: return DesignSystem.Colors.success.opacity(0.1)
        case .removed: return DesignSystem.Colors.error.opacity(0.1)
        case .context: return Color.clear
        }
    }
}

// MARK: - Supporting Types

enum WorktreeStatusFilter: CaseIterable {
    case all, clean, modified, conflicts
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .clean: return "Clean"
        case .modified: return "Modified"
        case .conflicts: return "Conflicts"
        }
    }
}

enum WorktreeSortOrder: CaseIterable {
    case recentActivity, alphabetical, status
    
    var displayName: String {
        switch self {
        case .recentActivity: return "Recent Activity"
        case .alphabetical: return "Alphabetical"
        case .status: return "Status"
        }
    }
}

extension GitWorktreeStatus {
    var sortOrder: Int {
        switch self {
        case .conflicts: return 0
        case .modified: return 1
        case .untracked: return 2
        case .clean: return 3
        }
    }
}

// MARK: - CreateWorktreeDialog

struct CreateWorktreeDialog: View {
    @Binding var newWorktreeName: String
    @Binding var newWorktreeBranch: String
    let onCancel: () -> Void
    let onCreate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Create New Worktree")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Worktree Name")
                        .font(.headline)
                    
                    TextField("feature/my-awesome-feature", text: $newWorktreeName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Branch")
                        .font(.headline)
                    
                    TextField("main", text: $newWorktreeBranch)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Text("This will create a new git worktree in a parallel directory, allowing you to work on multiple branches simultaneously.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Actions
            HStack {
                Spacer()
                
                Button("Cancel", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                
                Button("Create") {
                    onCreate()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newWorktreeName.isEmpty || newWorktreeBranch.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    WorktreeView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}