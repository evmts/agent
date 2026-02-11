import Testing
@testable import Smithers

@Suite @MainActor struct ChatModelTests {
    @Test func appendUser_addsMessage() {
        let m = ChatModel()
        m.appendUserMessage("Hi")
        #expect(m.messages.count == 1)
        #expect(m.messages.first?.role == .user)
    }

    @Test func appendDelta_createsAssistantWhenNoneStreaming() {
        let m = ChatModel()
        m.appendDelta("Hello ")
        #expect(m.messages.count == 1)
        #expect(m.messages[0].role == .assistant)
        #expect(m.isStreaming)
    }

    @Test func appendDelta_appendsToExistingStreaming() {
        let m = ChatModel()
        m.appendDelta("A ")
        m.appendDelta("B")
        #expect(m.messages.count == 1)
        #expect(m.messages[0].text == "A B")
    }

    @Test func completeTurn_marksNotStreaming() {
        let m = ChatModel()
        m.appendDelta("X")
        m.completeTurn()
        #expect(m.isStreaming == false)
        #expect(m.messages.last?.isStreaming == false)
    }
}

