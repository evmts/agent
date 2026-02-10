import AppKit

extension NSColor {
    /// Create an NSColor from a hex string like "#RRGGBB" or "#RRGGBBAA" or "0xRRGGBB".
    /// Returns nil if parsing fails.
    static func fromHex(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.hasPrefix("0X") { s.removeFirst(2) }

        guard s.count == 6 || s.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&value) else { return nil }

        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value & 0xFF00_0000) >> 24) / 255.0
            g = CGFloat((value & 0x00FF_0000) >> 16) / 255.0
            b = CGFloat((value & 0x0000_FF00) >> 8) / 255.0
            a = CGFloat(value & 0x0000_00FF) / 255.0
        } else {
            r = CGFloat((value & 0xFF00_00) >> 16) / 255.0
            g = CGFloat((value & 0x00FF_00) >> 8) / 255.0
            b = CGFloat(value & 0x0000_FF) / 255.0
            a = 1.0
        }

        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Returns an uppercase hex string (RRGGBB or RRGGBBAA) in sRGB space.
    func toHexString(includeAlpha: Bool = false) -> String {
        guard let c = usingColorSpace(.sRGB) else { return "" }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        if includeAlpha {
            let a = Int(round(c.alphaComponent * 255))
            return String(format: "%02X%02X%02X%02X", r, g, b, a)
        } else {
            return String(format: "%02X%02X%02X", r, g, b)
        }
    }

    /// Perceptual luminance (0-1) in sRGB space.
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }

    /// Approximate equality check for colors in sRGB space.
    func isApproximatelyEqual(to other: NSColor, tolerance: CGFloat = 0.005) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) <= tolerance &&
               abs(a.greenComponent - b.greenComponent) <= tolerance &&
               abs(a.blueComponent - b.blueComponent) <= tolerance &&
               abs(a.alphaComponent - b.alphaComponent) <= tolerance
    }
}

