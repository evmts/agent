import Testing
import AppKit

@Suite struct DesignSystemTests {
    @Test func accentIsCorrect() {
        let hex = DS.Color.accent.toHexString()
        #expect(hex == "4C8DFF")
    }

    @Test func baseIsCorrect() {
        let hex = DS.Color.base.toHexString()
        #expect(hex == "0F111A")
    }

    @Test func darkThemeUsesSpecTokens() {
        #expect(AppTheme.dark.accent.isApproximatelyEqual(to: DS.Color.accent))
    }

    @Test func lightThemeHasHighLuminance() {
        #expect(AppTheme.light.background.luminance > 0.55)
    }

    @Test func typographyBaseIs13() { #expect(DS.Type.base == 13) }

    @Test func spacingGridValues() {
        #expect(DS.Space._4 == 4)
        #expect(DS.Space._8 == 8)
        #expect(DS.Space._32 == 32)
    }

    @Test func radiusValues() {
        #expect(DS.Radius._4 == 4)
        #expect(DS.Radius._12 == 12)
        #expect(DS.Radius._16 == 16)
    }

    @Test func hexParsingRoundTrip() {
        let c = NSColor.fromHex("#123456")!
        #expect(c.toHexString() == "123456")
        let c2 = NSColor.fromHex("123456FF")!
        #expect(c2.toHexString(includeAlpha: true) == "123456FF")
    }

    @Test func userBubbleUsesAccentTint() {
        // v2 spec: chat.bubble.user = accent@12%, not white@8%
        let expected = DS.Color.accent.withAlphaComponent(0.12)
        #expect(DS.Color.chatBubbleUser.isApproximatelyEqual(to: expected))
    }
    @Test func hexParsingInvalidReturnsNil() {
        #expect(NSColor.fromHex("ZZZZZZ") == nil)
        #expect(NSColor.fromHex("#12345") == nil)
        #expect(NSColor.fromHex("") == nil)
    }

    @Test func approximateEqualityRejectsDifferentColors() {
        let red = NSColor.fromHex("#FF0000")!
        let blue = NSColor.fromHex("#0000FF")!
        #expect(!red.isApproximatelyEqual(to: blue))
    }

    @Test func lightThemeKeepsAccent() {
        #expect(AppTheme.light.accent.isApproximatelyEqual(to: AppTheme.dark.accent))
    }
}
