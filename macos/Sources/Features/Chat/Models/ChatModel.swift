import Observation

@Observable @MainActor
final class ChatModel {
    var messages: [ChatMessage] = []
    var isStreaming: Bool = false
    // Cache the index of the currently-streaming assistant message to avoid O(n) scans.
    private var streamingIndex: Int? = nil
    // Test aid: deltas received during the current turn.
    var deltaCountThisTurn: Int = 0

    func appendUserMessage(_ text: String) {
        messages.append(ChatMessage(role: .user, text: text, isStreaming: false))
    }

    func appendDelta(_ text: String) {
        if let idx = streamingIndex {
            messages[idx].text += text
        } else if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            streamingIndex = idx
            messages[idx].text += text
        } else {
            messages.append(ChatMessage(role: .assistant, text: text, isStreaming: true))
            streamingIndex = messages.count - 1
            isStreaming = true
        }
        deltaCountThisTurn += 1
    }

    func completeTurn() {
        if let idx = streamingIndex {
            messages[idx].isStreaming = false
        } else if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[idx].isStreaming = false
        }
        streamingIndex = nil
        isStreaming = false
    }
}
