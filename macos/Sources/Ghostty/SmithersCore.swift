import SmithersKit
import Foundation

@MainActor
final class SmithersCore {
    // Box frees the C handle in its own deinit, avoiding actor-isolated deinit issues.
    final class AppHandleBox: @unchecked Sendable {
        var app: smithers_app_t?
        init(_ app: smithers_app_t?) { self.app = app }
        deinit { if let app = app { smithers_app_free(app) } }
    }
    private let appBox: AppHandleBox
    private let chat: ChatModel
    // Optional event hooks set by AppModel for persistence and analytics.
    var onAssistantDelta: ((String) -> Void)?
    var onTurnComplete: (() -> Void)?

    init(chat: ChatModel) throws {
        self.chat = chat
        // All stored properties (including optional `app`) are initialized; safe to reference `self` now.
        let runtime = smithers_runtime_config_s(
            wakeup: { userdata in
                guard let userdata = userdata else { return }
                let token = UInt(bitPattern: userdata)
                Task { @MainActor in
                    guard let ptr = UnsafeMutableRawPointer(bitPattern: token) else { return }
                    let core = Unmanaged<SmithersCore>.fromOpaque(ptr).takeUnretainedValue()
                    core.handleWakeup()
                }
            },
            action: { userdata, tag, data, len in
                guard let userdata = userdata else { return }
                let token = UInt(bitPattern: userdata)
                // Copy bytes immediately on callback thread.
                let text: String? = {
                    guard let data = data, len > 0 else { return nil }
                    let buf = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: len)
                    return String(bytes: buf, encoding: .utf8)
                }()
                Task { @MainActor in
                    guard let ptr = UnsafeMutableRawPointer(bitPattern: token) else { return }
                    let core = Unmanaged<SmithersCore>.fromOpaque(ptr).takeUnretainedValue()
                    core.handleAction(tag: tag, text: text)
                }
            },
            userdata: Unmanaged.passUnretained(self).toOpaque()
        )
        var cfg = smithers_config_s(runtime: runtime)
        guard let handle = smithers_app_new(&cfg) else {
            throw NSError(domain: "SmithersCore", code: -1, userInfo: [NSLocalizedDescriptionKey: "smithers_app_new failed"])
        }
        self.appBox = AppHandleBox(handle)
    }

    func sendChatMessage(_ text: String) {
        var payload = smithers_action_payload_u()
        // Safety: The stub streamer discards the message argument immediately.
        // Production path must arena-dupe before spawning background work.
        guard let app = appBox.app else { return }
        text.withCString { cStr in
            payload.chat_send = smithers_string_s(ptr: UnsafeRawPointer(cStr)?.assumingMemoryBound(to: UInt8.self), len: text.utf8.count)
            smithers_app_action(app, SMITHERS_ACTION_CHAT_SEND, payload)
        }
    }

    // MARK: Callbacks
    // No deinit needed; AppHandleBox frees the handle.

    @MainActor private func handleWakeup() {
        // No-op for now; reserved for future polling.
    }

    @MainActor private func handleAction(tag: smithers_action_tag_e, text: String?) {
        switch tag {
        case SMITHERS_EVENT_CHAT_DELTA:
            if let t = text {
                chat.appendDelta(t)
                onAssistantDelta?(t)
            }
        case SMITHERS_EVENT_TURN_COMPLETE:
            chat.completeTurn()
            onTurnComplete?()
        default:
            break
        }
    }
}

// Backward-compat for existing smoke test sites (kept minimal).
enum SmithersCoreBridge {
    static func smokeInitAndFree() {
        var cfg = smithers_config_s(runtime: smithers_runtime_config_s(wakeup: nil, action: nil, userdata: nil))
        if let h = smithers_app_new(&cfg) { smithers_app_free(h) }
    }
}
