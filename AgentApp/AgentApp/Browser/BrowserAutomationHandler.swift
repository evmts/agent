import Foundation
import WebKit

// MARK: - Message Types

enum BrowserMessageType: String {
    case commandResult = "commandResult"
    case commandError = "commandError"
    case navigationStarted = "navigationStarted"
    case navigationComplete = "navigationComplete"
    case pageError = "pageError"
    case consoleLog = "consoleLog"
    case elementRemoved = "elementRemoved"
    case ready = "ready"
}

struct BrowserMessage {
    let type: BrowserMessageType
    let commandId: String?
    let payload: [String: Any]
    let timestamp: Double

    init?(from dictionary: [String: Any]) {
        guard let typeString = dictionary["type"] as? String,
              let type = BrowserMessageType(rawValue: typeString) else {
            return nil
        }

        self.type = type
        self.commandId = dictionary["commandId"] as? String
        self.payload = dictionary["payload"] as? [String: Any] ?? [:]
        self.timestamp = dictionary["timestamp"] as? Double ?? Date().timeIntervalSince1970 * 1000
    }
}

// MARK: - Browser Automation Handler

class BrowserAutomationHandler: NSObject, WKScriptMessageHandler {
    weak var automation: BrowserAutomation?

    private let messageHandlerName = "plue"

    init(automation: BrowserAutomation? = nil) {
        self.automation = automation
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == messageHandlerName else { return }

        guard let body = message.body as? [String: Any],
              let browserMessage = BrowserMessage(from: body) else {
            print("[BrowserAutomation] Invalid message format: \(message.body)")
            return
        }

        handleMessage(browserMessage)
    }

    private func handleMessage(_ message: BrowserMessage) {
        switch message.type {
        case .commandResult:
            handleCommandResult(message)

        case .commandError:
            handleCommandError(message)

        case .navigationStarted:
            handleNavigationStarted(message)

        case .navigationComplete:
            handleNavigationComplete(message)

        case .pageError:
            handlePageError(message)

        case .consoleLog:
            handleConsoleLog(message)

        case .elementRemoved:
            handleElementRemoved(message)

        case .ready:
            handleReady(message)
        }
    }

    private func handleCommandResult(_ message: BrowserMessage) {
        guard let commandId = message.commandId else {
            print("[BrowserAutomation] Command result missing commandId")
            return
        }

        let success = message.payload["success"] as? Bool ?? true
        let duration = (Date().timeIntervalSince1970 * 1000 - message.timestamp) / 1000

        let resultData = parseResultData(from: message.payload)

        let result = BrowserResult(
            success: success,
            commandId: commandId,
            data: resultData,
            error: nil,
            duration: duration
        )

        automation?.handleResult(result)
    }

    private func handleCommandError(_ message: BrowserMessage) {
        guard let commandId = message.commandId else {
            print("[BrowserAutomation] Command error missing commandId")
            return
        }

        let errorMessage = message.payload["error"] as? String ?? "Unknown error"
        let duration = (Date().timeIntervalSince1970 * 1000 - message.timestamp) / 1000

        let result = BrowserResult(
            success: false,
            commandId: commandId,
            data: nil,
            error: errorMessage,
            duration: duration
        )

        automation?.handleResult(result)
    }

    private func handleNavigationStarted(_ message: BrowserMessage) {
        let url = message.payload["url"] as? String ?? ""
        print("[BrowserAutomation] Navigation started: \(url)")
        automation?.handleNavigationStarted(url: url)
    }

    private func handleNavigationComplete(_ message: BrowserMessage) {
        let url = message.payload["url"] as? String ?? ""
        let title = message.payload["title"] as? String ?? ""
        print("[BrowserAutomation] Navigation complete: \(url)")
        automation?.handleNavigationComplete(url: url, title: title)
    }

    private func handlePageError(_ message: BrowserMessage) {
        let errorMessage = message.payload["message"] as? String ?? "Unknown error"
        let source = message.payload["source"] as? String ?? ""
        let line = message.payload["line"] as? Int ?? 0
        print("[BrowserAutomation] Page error at \(source):\(line): \(errorMessage)")
    }

    private func handleConsoleLog(_ message: BrowserMessage) {
        let level = message.payload["level"] as? String ?? "log"
        let logMessage = message.payload["message"] as? String ?? ""
        print("[BrowserAutomation] Console.\(level): \(logMessage)")
    }

    private func handleElementRemoved(_ message: BrowserMessage) {
        let ref = message.payload["ref"] as? String ?? ""
        print("[BrowserAutomation] Element removed: \(ref)")
    }

    private func handleReady(_ message: BrowserMessage) {
        print("[BrowserAutomation] Automation script ready")
        automation?.handleScriptReady()
    }

    private func parseResultData(from payload: [String: Any]) -> BrowserResultData? {
        if let snapshotData = payload["snapshot"] as? [String: Any],
           let snapshot = AccessibilitySnapshot(from: snapshotData) {
            return .snapshot(snapshot)
        }

        if let text = payload["text"] as? String {
            return .text(text)
        }

        if let html = payload["html"] as? String {
            return .html(html)
        }

        if let screenshotBase64 = payload["screenshot"] as? String,
           let data = Data(base64Encoded: screenshotBase64) {
            return .screenshot(data)
        }

        if let ref = payload["ref"] as? String {
            let actionPerformed = payload["actionPerformed"] as? Bool ?? true
            let newValue = payload["newValue"] as? String
            return .interaction(InteractionResult(
                ref: ref,
                actionPerformed: actionPerformed,
                newValue: newValue
            ))
        }

        if let url = payload["url"] as? String {
            let title = payload["title"] as? String ?? ""
            let statusCode = payload["statusCode"] as? Int
            return .navigation(NavigationResult(
                url: url,
                title: title,
                statusCode: statusCode
            ))
        }

        return nil
    }
}

// MARK: - Script Message Handler Name

extension BrowserAutomationHandler {
    static let handlerName = "plue"
}
