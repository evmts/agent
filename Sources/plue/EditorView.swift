import SwiftUI

struct EditorView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var mockCode = """
    // Welcome to Plue Editor
    import SwiftUI
    
    struct ContentView: View {
        @State private var message = "Hello, World!"
        
        var body: some View {
            VStack {
                Text(message)
                    .font(.largeTitle)
                    .padding()
                
                Button("Change Message") {
                    message = "Hello from Plue!"
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    """
    
    var body: some View {
        VStack(spacing: 0) {
            // Native macOS toolbar
            editorToolbar
            
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme))
            
            // Main editor area
            HSplitView {
                // File tree sidebar
                fileTreeSidebar
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                
                // Editor pane
                editorPane
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
    }
    
    // MARK: - Editor Toolbar
    private var editorToolbar: some View {
        HStack(spacing: 16) {
            // File info
            HStack(spacing: 8) {
                Image(systemName: "swift")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.orange)
                
                Text("ContentView.swift")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(DesignSystem.Colors.success)
                
                Text("No issues")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
            }
            
            Spacer()
            
            // Editor actions
            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Format code")
                
                Button(action: {}) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Run")
                
                Button(action: {}) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle sidebar")
            }
            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .toolbarStyle(theme: appState.currentTheme)
    }
    
    // MARK: - File Tree Sidebar
    private var fileTreeSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar header
            HStack {
                Label("Files", systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme))
            
            // Mock file tree
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    fileItem("PlueApp", isFolder: true, isExpanded: true)
                    VStack(alignment: .leading, spacing: 2) {
                        fileItem("ContentView.swift", isSelected: true, indent: 1)
                        fileItem("AppDelegate.swift", indent: 1)
                        fileItem("Models", isFolder: true, indent: 1)
                        fileItem("Views", isFolder: true, indent: 1)
                    }
                    .padding(.leading, 8)
                }
                .padding(.vertical, 8)
            }
        }
        .sidebarStyle()
        .background(DesignSystem.Colors.background(for: appState.currentTheme).opacity(0.95))
    }
    
    private func fileItem(_ name: String, isFolder: Bool = false, isExpanded: Bool = false, isSelected: Bool = false, indent: Int = 0) -> some View {
        HStack(spacing: 6) {
            if isFolder {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    .frame(width: 12)
            } else {
                Spacer()
                    .frame(width: 12)
            }
            
            Image(systemName: isFolder ? "folder" : "doc.text")
                .font(.system(size: 12))
                .foregroundColor(isFolder ? DesignSystem.Colors.warning : DesignSystem.Colors.primary)
            
            Text(name)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
            
            Spacer()
        }
        .padding(.leading, CGFloat(indent * 16))
        .sidebarItem(isSelected: isSelected, theme: appState.currentTheme)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {}
    }
    
    // MARK: - Editor Pane
    private var editorPane: some View {
        VStack(spacing: 0) {
            // Editor with syntax highlighting placeholder
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(1...30, id: \.self) { lineNumber in
                            Text("\(lineNumber)")
                                .font(DesignSystem.Typography.monoSmall)
                                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 12)
                    
                    // Code content
                    Text(mockCode)
                        .font(DesignSystem.Typography.monoMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            .background(DesignSystem.Colors.background(for: appState.currentTheme))
            
            // Status bar
            editorStatusBar
        }
    }
    
    // MARK: - Status Bar
    private var editorStatusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Text("Swift")
                    .font(.system(size: 11))
                
                Text("Line 15, Column 28")
                    .font(.system(size: 11))
                
                Text("UTF-8")
                    .font(.system(size: 11))
            }
            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
            
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.success)
                
                Text("Ready")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(DesignSystem.Materials.titleBar)
        .overlay(
            Divider()
                .background(DesignSystem.Colors.border(for: appState.currentTheme)),
            alignment: .top
        )
    }
}

#Preview {
    EditorView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}