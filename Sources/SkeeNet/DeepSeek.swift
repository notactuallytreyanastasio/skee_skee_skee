import Foundation
import SkeeCore

/// The one model client, the imperative shell around `Haggle`. It speaks
/// DeepSeek's OpenAI-style chat endpoint the way ../marginalia's
/// Marginalia.LLM does: same host, same `max_tokens` field, and a reply cut
/// off by the token limit (`finish_reason: "length"`) is a failure, never a
/// short answer.
///
/// `deepseek-chat` is the model with thinking off. A host who takes ten
/// seconds to answer "how about two nights?" is not a host; the haggle
/// wants a quick, in-character line, and the rules that matter are
/// enforced by `Haggle.hear`, not by the model's reasoning.
public struct DeepSeek: Sendable {
    public var key: String
    public var endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    public var model = "deepseek-chat"
    public var timeout: TimeInterval = 30

    public init(key: String) { self.key = key }

    public enum Failure: Error, CustomStringConvertible {
        case noKey
        case http(Int, String)
        case truncated
        case malformed(String)
        case unreadableReply(String)

        public var description: String {
            switch self {
            case .noKey: "no DeepSeek key (DEEPSEEK_API_KEY)"
            case .http(let code, let body): "DeepSeek HTTP \(code): \(body.prefix(200))"
            case .truncated: "DeepSeek reply was cut off by the token limit"
            case .malformed(let s): "DeepSeek response not understood: \(s.prefix(200))"
            case .unreadableReply(let s): "the host's reply was not the JSON asked for: \(s.prefix(200))"
            }
        }
    }

    /// One chat completion, JSON object forced. Returns the message text.
    public func chat(_ messages: [ChatMessage], maxTokens: Int = 300, temperature: Double = 0.9, jsonMode: Bool = true) async throws -> String {
        guard !key.isEmpty else { throw Failure.noKey }
        var req = URLRequest(url: endpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "max_tokens": maxTokens,
            "temperature": temperature,
        ].merging(jsonMode ? ["response_format": ["type": "json_object"]] : [:]) { a, _ in a }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code, String(decoding: data, as: UTF8.self)) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw Failure.malformed(String(decoding: data, as: UTF8.self)) }
        if choice["finish_reason"] as? String == "length" { throw Failure.truncated }
        return content
    }

    /// Ask the host for their next line in a haggle.
    ///
    /// DeepSeek's JSON mode sometimes returns empty content (their docs
    /// say so). In the first live haggles one line, "Throw in some credit
    /// and I'll sign.", got whitespace three times running, so a retry in
    /// the same mode is not enough: after two blanks the last try drops
    /// JSON mode and relies on the prompt, which asks for JSON anyway. A
    /// reply with text that isn't the object is not retried: that is a
    /// different failure, and it is thrown.
    public func reply(in haggle: Haggle) async throws -> HostReply {
        var text = ""
        for attempt in 0..<3 {
            text = try await chat(haggle.messages, jsonMode: attempt < 2)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
        }
        guard let r = Self.parse(text) else { throw Failure.unreadableReply(text) }
        return r
    }

    /// A model reply as a `HostReply`. A reply wrapped in a ``` fence is
    /// accepted; anything else that is not the object is nil.
    public static func parse(_ text: String) -> HostReply? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = body.split(separator: "\n").dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        }
        guard let r = try? JSONDecoder().decode(HostReply.self, from: Data(body.utf8)), !r.say.isEmpty else { return nil }
        return r
    }

    /// The key: the environment first, then a `.env` file (KEY=value
    /// lines) at `envFile`, the way marginalia keeps it.
    public static func key(environment: [String: String] = ProcessInfo.processInfo.environment, envFile: URL? = nil) -> String? {
        if let k = environment["DEEPSEEK_API_KEY"], !k.isEmpty { return k }
        guard let envFile, let text = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("DEEPSEEK_API_KEY=") {
            let v = line.dropFirst("DEEPSEEK_API_KEY=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if !v.isEmpty { return v }
        }
        return nil
    }
}
