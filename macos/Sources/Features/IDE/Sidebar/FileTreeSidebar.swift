import SwiftUI

/// FileTreeSidebar — visual scaffold of the IDE file tree per spec §6.2.
/// Placeholder data only; no filesystem I/O yet. Provides hover + selected
/// row states and uses design tokens for surfaces/borders.
struct FileTreeSidebar: View {
    @Environment(\.theme) private var theme
    @State private var selected: UUID? = nil

    private let items: [Node] = [
        .folder("app"),
        .file("App/SmithersApp.swift", depth: 1),
        .file("App/AppModel.swift", depth: 1),
        .folder("Features"),
        .file("Features/IDE/IDEWindowRootView.swift", depth: 1),
        .file("Features/Chat/ChatWindowRootView.swift", depth: 1),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Optional header placeholder (surface2) reserved for root section
            HStack {
                Text("WORKSPACE")
                    .font(.system(size: DS.Typography.s, weight: .medium))
                    .foregroundStyle(Color(nsColor: theme.mutedForeground))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space._12)
            .frame(height: 28)
            .background(Color(nsColor: theme.panelBackground))
            DividerLine()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        FileTreeRow(
                            item: item,
                            isSelected: item.id == selected,
                            onSelect: { selected = item.id }
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: theme.secondaryBackground))
        .accessibilityIdentifier("file_tree_sidebar")
    }

    // MARK: - Local placeholder models
    struct Node: Identifiable, Equatable {
        enum Kind { case folder, file }
        // Stable identity derived from semantic fields for predictable diffing
        var id: String { "\(kind)-\(name)" }
        let name: String
        let kind: Kind
        let depth: Int

        static func folder(_ name: String, depth: Int = 0) -> Node { .init(name: name, kind: .folder, depth: depth) }
        static func file(_ name: String, depth: Int = 0) -> Node { .init(name: name, kind: .file, depth: depth) }
    }
}

// Internal (not private) so tests can instantiate per review plan
struct FileTreeRow: View {
    let item: FileTreeSidebar.Node
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false
    // Exposed constants for tests
    static let indentPerLevel: CGFloat = DS.Space._16
    static let rowFontSize: CGFloat = DS.Typography.s

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Left accent capsule for selected state per §6.2
                Capsule()
                    .fill(Color(nsColor: theme.accent))
                    .frame(width: isSelected ? 3 : 0)
                    // full height minus 6pt inset via vertical padding 3pt
                    .padding(.vertical, 3)
                    .animation(.easeInOut(duration: 0.12), value: isSelected)

                // Row content
                if item.kind == .folder {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: DS.Color.textTertiary))
                        .frame(width: 12)
                } else {
                    // Spacer to align with folder rows that show chevrons
                    Color.clear.frame(width: 12, height: 0)
                }
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(nsColor: iconColor))
                    .frame(width: 16)
                Text(item.name.components(separatedBy: "/").last ?? item.name)
                    .font(.system(size: Self.rowFontSize))
                    .foregroundStyle(Color(nsColor: theme.foreground))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space._12)
            .padding(.leading, CGFloat(item.depth) * Self.indentPerLevel)
            .frame(height: 30)
            .background(rowBackground)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(item.name))
        .accessibilityIdentifier("filetreerow_\(item.name.replacingOccurrences(of: " ", with: "_"))")
    }

    private var iconName: String {
        switch item.kind { case .folder: return "folder"; case .file: return "doc.text" }
    }
    private var iconColor: NSColor {
        switch item.kind { case .folder: return theme.accent; case .file: return DS.Color.textSecondary }
    }
    private var rowBackground: some View {
        ZStack {
            if isSelected {
                // Current file subtle background per §6.2: accent@6%
                Color(nsColor: theme.accent.withAlphaComponent(0.06))
            } else if hovering {
                Color(nsColor: DS.Color.chatSidebarHover)
            } else {
                Color.clear
            }
        }
    }
}
