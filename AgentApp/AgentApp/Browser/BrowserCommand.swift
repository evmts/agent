import Foundation

// MARK: - Browser Commands

enum BrowserCommand {
    // Navigation
    case goto(url: String, waitUntil: WaitCondition)
    case back
    case forward
    case reload

    // Observation
    case snapshot(options: SnapshotOptions)
    case screenshot(options: ScreenshotOptions)
    case extractText(ref: String)
    case getHTML(ref: String, outer: Bool)

    // Interactions
    case click(ref: String, options: ClickOptions)
    case type(ref: String, text: String, options: TypeOptions)
    case press(ref: String, key: String, modifiers: [KeyModifier])
    case scroll(ref: String?, direction: ScrollDirection, amount: Int)
    case selectOption(ref: String, values: [String])
    case hover(ref: String)
    case focus(ref: String)

    // Utility
    case waitForSelector(selector: String, state: ElementState, timeout: Int)
    case evaluate(script: String)

    func toJavaScript(commandId: String) -> String {
        switch self {
        case .goto(let url, _):
            return "window.location.href = '\(url.escapedForJS)';"

        case .back:
            return "window.history.back();"

        case .forward:
            return "window.history.forward();"

        case .reload:
            return "window.location.reload();"

        case .snapshot(let options):
            let optionsJSON = options.toJSON()
            return "__plue.buildSnapshot('\(commandId)', \(optionsJSON));"

        case .screenshot:
            return "__plue.screenshot('\(commandId)');"

        case .extractText(let ref):
            return "__plue.extractText('\(commandId)', '\(ref)');"

        case .getHTML(let ref, let outer):
            return "__plue.getHTML('\(commandId)', '\(ref)', \(outer));"

        case .click(let ref, let options):
            let optionsJSON = options.toJSON()
            return "__plue.click('\(commandId)', '\(ref)', \(optionsJSON));"

        case .type(let ref, let text, let options):
            let optionsJSON = options.toJSON()
            return "__plue.type('\(commandId)', '\(ref)', '\(text.escapedForJS)', \(optionsJSON));"

        case .press(let ref, let key, let modifiers):
            let modifiersArray = modifiers.map { "'\($0.rawValue)'" }.joined(separator: ", ")
            return "__plue.press('\(commandId)', '\(ref)', '\(key)', [\(modifiersArray)]);"

        case .scroll(let ref, let direction, let amount):
            let refArg = ref.map { "'\($0)'" } ?? "null"
            return "__plue.scroll('\(commandId)', \(refArg), '\(direction.rawValue)', \(amount));"

        case .selectOption(let ref, let values):
            let valuesArray = values.map { "'\($0.escapedForJS)'" }.joined(separator: ", ")
            return "__plue.selectOption('\(commandId)', '\(ref)', [\(valuesArray)]);"

        case .hover(let ref):
            return "__plue.hover('\(commandId)', '\(ref)');"

        case .focus(let ref):
            return "__plue.focus('\(commandId)', '\(ref)');"

        case .waitForSelector(let selector, let state, let timeout):
            return "__plue.waitForSelector('\(commandId)', '\(selector.escapedForJS)', '\(state.rawValue)', \(timeout));"

        case .evaluate(let script):
            return "__plue.evaluate('\(commandId)', `\(script)`);"
        }
    }
}

// MARK: - Command Options

struct SnapshotOptions {
    var includeHidden: Bool = false
    var includeBounds: Bool = true
    var maxDepth: Int = 50

    func toJSON() -> String {
        """
        {"includeHidden":\(includeHidden),"includeBounds":\(includeBounds),"maxDepth":\(maxDepth)}
        """
    }

    static let `default` = SnapshotOptions()
}

struct ScreenshotOptions {
    var fullPage: Bool = false
    var quality: Int = 80

    func toJSON() -> String {
        """
        {"fullPage":\(fullPage),"quality":\(quality)}
        """
    }

    static let `default` = ScreenshotOptions()
}

struct ClickOptions {
    var button: MouseButton = .left
    var clickCount: Int = 1
    var delay: Int = 0
    var position: CGPoint? = nil
    var force: Bool = false
    var timeout: Int = 5000

    func toJSON() -> String {
        var parts = [String]()
        parts.append("\"button\":\"\(button.rawValue)\"")
        parts.append("\"clickCount\":\(clickCount)")
        parts.append("\"delay\":\(delay)")
        parts.append("\"force\":\(force)")
        parts.append("\"timeout\":\(timeout)")
        if let pos = position {
            parts.append("\"position\":{\"x\":\(pos.x),\"y\":\(pos.y)}")
        }
        return "{\(parts.joined(separator: ","))}"
    }

    static let `default` = ClickOptions()
}

struct TypeOptions {
    var clear: Bool = false
    var delay: Int = 50
    var timeout: Int = 5000

    func toJSON() -> String {
        """
        {"clear":\(clear),"delay":\(delay),"timeout":\(timeout)}
        """
    }

    static let `default` = TypeOptions()
}

// MARK: - Enums

enum WaitCondition: String {
    case load = "load"
    case domContentLoaded = "domcontentloaded"
    case networkIdle = "networkidle"
}

enum ScrollDirection: String {
    case up = "up"
    case down = "down"
    case left = "left"
    case right = "right"
}

enum MouseButton: String {
    case left = "left"
    case right = "right"
    case middle = "middle"
}

enum KeyModifier: String {
    case alt = "Alt"
    case control = "Control"
    case meta = "Meta"
    case shift = "Shift"
}

enum ElementState: String {
    case attached = "attached"
    case detached = "detached"
    case visible = "visible"
    case hidden = "hidden"
}

// MARK: - Browser Result

struct BrowserResult {
    let success: Bool
    let commandId: String
    let data: BrowserResultData?
    let error: String?
    let duration: TimeInterval
}

enum BrowserResultData {
    case snapshot(AccessibilitySnapshot)
    case screenshot(Data)
    case text(String)
    case html(String)
    case interaction(InteractionResult)
    case navigation(NavigationResult)
    case evaluation(Any?)
}

struct InteractionResult {
    let ref: String
    let actionPerformed: Bool
    let newValue: String?
}

struct NavigationResult {
    let url: String
    let title: String
    let statusCode: Int?
}

// MARK: - Browser Error

enum BrowserError: Error {
    case elementNotFound(ref: String)
    case elementNotActionable(ref: String, reason: String)
    case timeout(operation: String, timeoutMs: Int)
    case navigationFailed(url: String, reason: String)
    case scriptError(message: String)
    case disconnected
    case invalidCommand(String)

    var localizedDescription: String {
        switch self {
        case .elementNotFound(let ref):
            return "Element \(ref) not found in DOM"
        case .elementNotActionable(let ref, let reason):
            return "Element \(ref) not actionable: \(reason)"
        case .timeout(let op, let ms):
            return "Operation \(op) timed out after \(ms)ms"
        case .navigationFailed(let url, let reason):
            return "Navigation to \(url) failed: \(reason)"
        case .scriptError(let msg):
            return "Script error: \(msg)"
        case .disconnected:
            return "WebView disconnected"
        case .invalidCommand(let msg):
            return "Invalid command: \(msg)"
        }
    }
}

// MARK: - String Extension

private extension String {
    var escapedForJS: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
