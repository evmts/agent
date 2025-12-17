import Foundation

// MARK: - Accessibility Snapshot

struct AccessibilitySnapshot: Codable {
    let url: String
    let title: String
    let timestamp: Double
    let root: AccessibilityNode
    let elementCount: Int

    init(url: String, title: String, timestamp: Double = Date().timeIntervalSince1970, root: AccessibilityNode, elementCount: Int) {
        self.url = url
        self.title = title
        self.timestamp = timestamp
        self.root = root
        self.elementCount = elementCount
    }

    init?(from dictionary: [String: Any]) {
        guard let url = dictionary["url"] as? String,
              let title = dictionary["title"] as? String,
              let timestamp = dictionary["timestamp"] as? Double,
              let rootDict = dictionary["root"] as? [String: Any],
              let root = AccessibilityNode(from: rootDict),
              let elementCount = dictionary["elementCount"] as? Int else {
            return nil
        }
        self.url = url
        self.title = title
        self.timestamp = timestamp
        self.root = root
        self.elementCount = elementCount
    }

    func toTextTree() -> String {
        var lines = [String]()
        lines.append("page: \(title)")
        lines.append("url: \(url)")
        lines.append("")
        root.appendToTextTree(lines: &lines, indent: 0)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Accessibility Node

struct AccessibilityNode: Codable, Identifiable {
    let ref: String
    let role: String
    let name: String?
    let value: String?
    let description: String?

    // States
    let checked: Bool?
    let selected: Bool?
    let expanded: Bool?
    let disabled: Bool
    let required: Bool?
    let invalid: Bool?
    let focused: Bool
    let modal: Bool?

    // Geometry
    let boundingBox: BoundingBox?

    // Tree structure
    let children: [AccessibilityNode]

    var id: String { ref }

    init(
        ref: String,
        role: String,
        name: String? = nil,
        value: String? = nil,
        description: String? = nil,
        checked: Bool? = nil,
        selected: Bool? = nil,
        expanded: Bool? = nil,
        disabled: Bool = false,
        required: Bool? = nil,
        invalid: Bool? = nil,
        focused: Bool = false,
        modal: Bool? = nil,
        boundingBox: BoundingBox? = nil,
        children: [AccessibilityNode] = []
    ) {
        self.ref = ref
        self.role = role
        self.name = name
        self.value = value
        self.description = description
        self.checked = checked
        self.selected = selected
        self.expanded = expanded
        self.disabled = disabled
        self.required = required
        self.invalid = invalid
        self.focused = focused
        self.modal = modal
        self.boundingBox = boundingBox
        self.children = children
    }

    init?(from dictionary: [String: Any]) {
        guard let ref = dictionary["ref"] as? String,
              let role = dictionary["role"] as? String else {
            return nil
        }

        self.ref = ref
        self.role = role
        self.name = dictionary["name"] as? String
        self.value = dictionary["value"] as? String
        self.description = dictionary["description"] as? String
        self.checked = dictionary["checked"] as? Bool
        self.selected = dictionary["selected"] as? Bool
        self.expanded = dictionary["expanded"] as? Bool
        self.disabled = dictionary["disabled"] as? Bool ?? false
        self.required = dictionary["required"] as? Bool
        self.invalid = dictionary["invalid"] as? Bool
        self.focused = dictionary["focused"] as? Bool ?? false
        self.modal = dictionary["modal"] as? Bool

        if let boundsDict = dictionary["boundingBox"] as? [String: Any] {
            self.boundingBox = BoundingBox(from: boundsDict)
        } else {
            self.boundingBox = nil
        }

        if let childrenArray = dictionary["children"] as? [[String: Any]] {
            self.children = childrenArray.compactMap { AccessibilityNode(from: $0) }
        } else {
            self.children = []
        }
    }

    func appendToTextTree(lines: inout [String], indent: Int) {
        let prefix = String(repeating: "  ", count: indent) + "- "

        var parts = [String]()
        parts.append(role)

        if let name = name, !name.isEmpty {
            let truncatedName = name.count > 50 ? String(name.prefix(50)) + "..." : name
            parts.append("\"\(truncatedName)\"")
        }

        var attrs = [String]()
        if disabled { attrs.append("disabled") }
        if focused { attrs.append("focused") }
        if required == true { attrs.append("required") }
        if invalid == true { attrs.append("invalid") }
        if let checked = checked { attrs.append(checked ? "checked" : "unchecked") }
        if let selected = selected, selected { attrs.append("selected") }
        if let expanded = expanded { attrs.append(expanded ? "expanded" : "collapsed") }

        if !attrs.isEmpty {
            parts.append("[\(attrs.joined(separator: ", "))]")
        }

        parts.append("[ref=\(ref)]")

        lines.append(prefix + parts.joined(separator: " "))

        for child in children {
            child.appendToTextTree(lines: &lines, indent: indent + 1)
        }
    }

    var isInteractable: Bool {
        let interactableRoles = ["button", "link", "textbox", "checkbox", "radio",
                                  "combobox", "listbox", "menuitem", "tab", "slider",
                                  "switch", "searchbox", "spinbutton"]
        return interactableRoles.contains(role.lowercased()) && !disabled
    }

    func findNode(withRef targetRef: String) -> AccessibilityNode? {
        if ref == targetRef { return self }
        for child in children {
            if let found = child.findNode(withRef: targetRef) {
                return found
            }
        }
        return nil
    }

    func allInteractableNodes() -> [AccessibilityNode] {
        var result = [AccessibilityNode]()
        if isInteractable {
            result.append(self)
        }
        for child in children {
            result.append(contentsOf: child.allInteractableNodes())
        }
        return result
    }
}

// MARK: - Bounding Box

struct BoundingBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init?(from dictionary: [String: Any]) {
        guard let x = dictionary["x"] as? Double,
              let y = dictionary["y"] as? Double,
              let width = dictionary["width"] as? Double,
              let height = dictionary["height"] as? Double else {
            return nil
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Browser Tool Invocation

struct BrowserToolInvocation: Identifiable {
    let id: String
    let toolName: BrowserToolType
    let parameters: BrowserToolParameters
    let status: BrowserToolStatus
    let result: BrowserResult?
    let startedAt: Date
    let completedAt: Date?

    init(
        id: String = UUID().uuidString,
        toolName: BrowserToolType,
        parameters: BrowserToolParameters,
        status: BrowserToolStatus = .pending,
        result: BrowserResult? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.parameters = parameters
        self.status = status
        self.result = result
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    func withStatus(_ newStatus: BrowserToolStatus) -> BrowserToolInvocation {
        BrowserToolInvocation(
            id: id,
            toolName: toolName,
            parameters: parameters,
            status: newStatus,
            result: result,
            startedAt: startedAt,
            completedAt: newStatus == .completed || newStatus == .failed ? Date() : nil
        )
    }

    func withResult(_ newResult: BrowserResult) -> BrowserToolInvocation {
        BrowserToolInvocation(
            id: id,
            toolName: toolName,
            parameters: parameters,
            status: newResult.success ? .completed : .failed,
            result: newResult,
            startedAt: startedAt,
            completedAt: Date()
        )
    }
}

enum BrowserToolType: String, CaseIterable {
    case snapshot = "browser_snapshot"
    case click = "browser_click"
    case type = "browser_type"
    case scroll = "browser_scroll"
    case extract = "browser_extract"
    case screenshot = "browser_screenshot"
    case navigate = "browser_navigate"
    case back = "browser_back"
    case forward = "browser_forward"
    case reload = "browser_reload"

    var displayName: String {
        switch self {
        case .snapshot: return "Snapshot"
        case .click: return "Click"
        case .type: return "Type"
        case .scroll: return "Scroll"
        case .extract: return "Extract"
        case .screenshot: return "Screenshot"
        case .navigate: return "Navigate"
        case .back: return "Back"
        case .forward: return "Forward"
        case .reload: return "Reload"
        }
    }

    var iconName: String {
        switch self {
        case .snapshot: return "accessibility"
        case .click: return "cursorarrow.click"
        case .type: return "keyboard"
        case .scroll: return "scroll"
        case .extract: return "doc.text"
        case .screenshot: return "camera"
        case .navigate: return "globe"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .reload: return "arrow.clockwise"
        }
    }
}

struct BrowserToolParameters {
    let url: String?
    let ref: String?
    let text: String?
    let direction: ScrollDirection?
    let amount: Int?

    init(
        url: String? = nil,
        ref: String? = nil,
        text: String? = nil,
        direction: ScrollDirection? = nil,
        amount: Int? = nil
    ) {
        self.url = url
        self.ref = ref
        self.text = text
        self.direction = direction
        self.amount = amount
    }

    var description: String {
        var parts = [String]()
        if let url = url { parts.append("url: \(url)") }
        if let ref = ref { parts.append("ref: \(ref)") }
        if let text = text { parts.append("text: \"\(text)\"") }
        if let direction = direction { parts.append("direction: \(direction.rawValue)") }
        if let amount = amount { parts.append("amount: \(amount)px") }
        return parts.isEmpty ? "(none)" : parts.joined(separator: ", ")
    }
}

enum BrowserToolStatus {
    case pending
    case executing
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .executing: return "Executing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Web Automation State

struct WebAutomationState {
    let isConnected: Bool
    let lastSnapshot: AccessibilitySnapshot?
    let activeInvocation: BrowserToolInvocation?
    let invocationHistory: [BrowserToolInvocation]
    let lastError: String?

    static let initial = WebAutomationState(
        isConnected: false,
        lastSnapshot: nil,
        activeInvocation: nil,
        invocationHistory: [],
        lastError: nil
    )

    func withSnapshot(_ snapshot: AccessibilitySnapshot) -> WebAutomationState {
        WebAutomationState(
            isConnected: isConnected,
            lastSnapshot: snapshot,
            activeInvocation: activeInvocation,
            invocationHistory: invocationHistory,
            lastError: nil
        )
    }

    func withInvocation(_ invocation: BrowserToolInvocation) -> WebAutomationState {
        WebAutomationState(
            isConnected: isConnected,
            lastSnapshot: lastSnapshot,
            activeInvocation: invocation,
            invocationHistory: invocationHistory,
            lastError: nil
        )
    }

    func withCompletedInvocation(_ invocation: BrowserToolInvocation) -> WebAutomationState {
        var newHistory = invocationHistory
        newHistory.append(invocation)
        // Keep only last 50 invocations
        if newHistory.count > 50 {
            newHistory = Array(newHistory.suffix(50))
        }
        return WebAutomationState(
            isConnected: isConnected,
            lastSnapshot: lastSnapshot,
            activeInvocation: nil,
            invocationHistory: newHistory,
            lastError: invocation.result?.success == false ? invocation.result?.error : nil
        )
    }

    func withConnection(_ connected: Bool) -> WebAutomationState {
        WebAutomationState(
            isConnected: connected,
            lastSnapshot: connected ? lastSnapshot : nil,
            activeInvocation: activeInvocation,
            invocationHistory: invocationHistory,
            lastError: lastError
        )
    }
}
