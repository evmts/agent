import Foundation
import AppKit

// MARK: - ANSI Color Codes
enum ANSIColor: Int {
    case black = 30
    case red = 31
    case green = 32
    case yellow = 33
    case blue = 34
    case magenta = 35
    case cyan = 36
    case white = 37
    case defaultColor = 39
    
    // Bright colors
    case brightBlack = 90
    case brightRed = 91
    case brightGreen = 92
    case brightYellow = 93
    case brightBlue = 94
    case brightMagenta = 95
    case brightCyan = 96
    case brightWhite = 97
    
    func toNSColor() -> NSColor {
        switch self {
        case .black, .brightBlack: return .black
        case .red: return NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        case .brightRed: return NSColor(red: 1, green: 0, blue: 0, alpha: 1)
        case .green: return NSColor(red: 0, green: 0.8, blue: 0, alpha: 1)
        case .brightGreen: return NSColor(red: 0, green: 1, blue: 0, alpha: 1)
        case .yellow: return NSColor(red: 0.8, green: 0.8, blue: 0, alpha: 1)
        case .brightYellow: return NSColor(red: 1, green: 1, blue: 0, alpha: 1)
        case .blue: return NSColor(red: 0, green: 0, blue: 0.8, alpha: 1)
        case .brightBlue: return NSColor(red: 0, green: 0, blue: 1, alpha: 1)
        case .magenta: return NSColor(red: 0.8, green: 0, blue: 0.8, alpha: 1)
        case .brightMagenta: return NSColor(red: 1, green: 0, blue: 1, alpha: 1)
        case .cyan: return NSColor(red: 0, green: 0.8, blue: 0.8, alpha: 1)
        case .brightCyan: return NSColor(red: 0, green: 1, blue: 1, alpha: 1)
        case .white: return NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        case .brightWhite, .defaultColor: return .white
        }
    }
}

// MARK: - ANSI Parser
class ANSIParser {
    private var currentAttributes: [NSAttributedString.Key: Any] = [:]
    private let defaultFont: NSFont
    private let defaultForeground: NSColor
    private let defaultBackground: NSColor
    
    init(font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular),
         foregroundColor: NSColor = .white,
         backgroundColor: NSColor = .black) {
        self.defaultFont = font
        self.defaultForeground = foregroundColor
        self.defaultBackground = backgroundColor
        
        // Set default attributes
        currentAttributes = [
            .font: defaultFont,
            .foregroundColor: defaultForeground,
            .backgroundColor: defaultBackground
        ]
    }
    
    /// Parse text with ANSI escape sequences and return attributed string
    func parse(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        // Regular expression to match ANSI escape sequences
        let pattern = "\\x1b\\[(\\d+(?:;\\d+)*)m"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        
        var lastIndex = text.startIndex
        let nsString = text as NSString
        
        // Find all ANSI escape sequences
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            // Add text before the escape sequence
            if let range = Range(match.range, in: text) {
                let beforeText = String(text[lastIndex..<range.lowerBound])
                if !beforeText.isEmpty {
                    result.append(NSAttributedString(string: beforeText, attributes: currentAttributes))
                }
                
                // Parse the escape sequence
                let escapeSequence = String(text[range])
                processEscapeSequence(escapeSequence)
                
                lastIndex = range.upperBound
            }
        }
        
        // Add remaining text
        if lastIndex < text.endIndex {
            let remainingText = String(text[lastIndex...])
            result.append(NSAttributedString(string: remainingText, attributes: currentAttributes))
        }
        
        return result
    }
    
    /// Process a single ANSI escape sequence
    private func processEscapeSequence(_ sequence: String) {
        // Extract the numbers from the sequence
        let numbers = sequence
            .replacingOccurrences(of: "\u{1b}[", with: "")
            .replacingOccurrences(of: "m", with: "")
            .split(separator: ";")
            .compactMap { Int($0) }
        
        for code in numbers {
            switch code {
            case 0: // Reset
                currentAttributes = [
                    .font: defaultFont,
                    .foregroundColor: defaultForeground,
                    .backgroundColor: defaultBackground
                ]
                
            case 1: // Bold
                if let currentFont = currentAttributes[.font] as? NSFont {
                    currentAttributes[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                }
                
            case 2: // Dim
                if let currentColor = currentAttributes[.foregroundColor] as? NSColor {
                    currentAttributes[.foregroundColor] = currentColor.withAlphaComponent(0.6)
                }
                
            case 3: // Italic
                if let currentFont = currentAttributes[.font] as? NSFont {
                    currentAttributes[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                }
                
            case 4: // Underline
                currentAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                
            case 7: // Reverse
                let fg = currentAttributes[.foregroundColor] ?? defaultForeground
                let bg = currentAttributes[.backgroundColor] ?? defaultBackground
                currentAttributes[.foregroundColor] = bg
                currentAttributes[.backgroundColor] = fg
                
            case 30...37, 90...97: // Foreground colors
                if let color = ANSIColor(rawValue: code) {
                    currentAttributes[.foregroundColor] = color.toNSColor()
                }
                
            case 39: // Default foreground
                currentAttributes[.foregroundColor] = defaultForeground
                
            case 40...47, 100...107: // Background colors
                if let color = ANSIColor(rawValue: code - 10) {
                    currentAttributes[.backgroundColor] = color.toNSColor()
                }
                
            case 49: // Default background
                currentAttributes[.backgroundColor] = defaultBackground
                
            default:
                // Ignore unsupported codes
                break
            }
        }
    }
    
    /// Reset all attributes to defaults
    func reset() {
        currentAttributes = [
            .font: defaultFont,
            .foregroundColor: defaultForeground,
            .backgroundColor: defaultBackground
        ]
    }
}