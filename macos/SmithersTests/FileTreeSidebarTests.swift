import Testing
@testable import Smithers

@Suite struct FileTreeSidebarTests {
    @Test func instantiateSidebar_viewTypeExists() {
        // Smoke: ensure the view type exists and can be constructed.
        let view = FileTreeSidebar()
        #expect(String(describing: type(of: view)) == "FileTreeSidebar")
    }

    @Test func fileTreeRow_instantiation_publicForTests() {
        // Verify FileTreeRow is instantiable (not private) per plan.
        let node = FileTreeSidebar.Node.file("Sources/Main.swift")
        let row = FileTreeRow(item: node, isSelected: false, onSelect: {})
        #expect(String(describing: type(of: row)) == "FileTreeRow")
    }

    @Test func indent_isSixteenPoints_perDesignToken() {
        // Spec §6.2: indent 16pt per level (DS.Space._16)
        #expect(FileTreeRow.indentPerLevel == DS.Space._16)
    }

    @Test func typography_isElevenPoints_perDesignToken() {
        // Row text uses DS.Typography.s (11pt)
        #expect(FileTreeRow.rowFontSize == DS.Typography.s)
        #expect(DS.Typography.s == 11)
    }

    @Test func hoverToken_hasAlphaComponent() {
        // DS.Color.chatSidebarHover should be white@4% => alpha ~0.04
        let color = DS.Color.chatSidebarHover.usingColorSpace(.extendedSRGB) ?? DS.Color.chatSidebarHover
        var alpha: CGFloat = -1
        color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        #expect(alpha > 0 && alpha <= 1)
    }
}
