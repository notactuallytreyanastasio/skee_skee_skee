import Testing
import SkeeCore
@testable import SkeeNet

@Suite("Host replies off the wire")
struct HostReplyTests {
    @Test func readsTheObject() {
        let r = DeepSeek.parse(#"{"say": "Two nights.", "offer": {"nights": 2, "tickets": 0, "credit": 0}, "mood": 1, "walk": false}"#)
        #expect(r == HostReply(say: "Two nights.", offer: .init(nights: 2, tickets: 0, credit: 0), mood: 1))
    }

    @Test func readsAFencedObject() {
        let r = DeepSeek.parse("```json\n{\"say\": \"Hi\", \"offer\": {\"nights\": 1, \"tickets\": 0, \"credit\": 0}, \"mood\": 0, \"walk\": false}\n```")
        #expect(r?.say == "Hi")
    }

    @Test func refusesProseAndBlanks() {
        #expect(DeepSeek.parse("Flattery with a marketing plan attached. Two nights it is.") == nil)
        #expect(DeepSeek.parse("   \n ") == nil)
    }

    @Test func keyComesFromTheEnvironmentFirst() {
        #expect(DeepSeek.key(environment: ["DEEPSEEK_API_KEY": "abc"]) == "abc")
        #expect(DeepSeek.key(environment: [:]) == nil)
    }
}
