import Foundation

// Groq uses the OpenAI-compatible Chat Completions API.
class GroqService {
    static let shared = GroqService()
    private init() {}

    private var apiKey: String {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["GROQ_API_KEY"] as? String, !key.isEmpty, key != "YOUR_API_KEY_HERE" {
            return key
        }
        return AuthManager.shared.groqKey
    }
    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"
    private let model   = "llama-3.3-70b-versatile"

    func fetchMnemonics(for word: String, meaning: String) async throws -> [MnemonicItem] {
        guard !apiKey.isEmpty else {
            throw GeminiError.apiError("No Groq API key set.")
        }
        guard let url = URL(string: baseURL) else { throw GeminiError.invalidURL }

        let systemPrompt = """
            You are an expert vocabulary tutor. Your goal is to create clever, short, and highly memorable mnemonics using phonetic wordplay, rhymes, or vivid imagery.

            CRITICAL INSTRUCTIONS:
            1. Keep mnemonics punchy and short (strictly under 10 words).
            2. Always respond with ONLY a raw, valid JSON array. 
            3. Do NOT include markdown formatting, backticks, preambles, or postambles. Just the raw JSON text.
            4. Each element in the array MUST have exactly two string keys: "mnemonic" (the short trick) and "explanation" (how it connects the word's sound to its meaning).
            """

        let userPrompt = """
            Create at most 4 short, memorable mnemonics for the word '\(word)', which means: '\(meaning)'. 
            Remember: Output ONLY the raw JSON array.
            """

        let body: [String: Any] = [
            "model":       model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userPrompt]
            ],
            "temperature": 0.7,
            "max_tokens":  800
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errorBody = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let errorMsg  = ((errorBody["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            print("Groq API error (\(http.statusCode)): \(errorMsg)")

            if http.statusCode == 429 {
                let retryAfter = extractRetryDelay(from: errorMsg)
                throw GeminiError.rateLimited(retryAfter: retryAfter)
            }
            throw GeminiError.apiError("Groq: \(errorMsg)")
        }

        guard let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices     = json["choices"] as? [[String: Any]],
              let msgContent  = (choices.first?["message"] as? [String: Any])?["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "no body"
            print("Groq parse error – raw response: \(raw)")
            throw GeminiError.unprocessableData
        }

        print("Groq raw content: \(msgContent)")
        return try parseMnemonicArray(from: msgContent)
    }

    private func parseMnemonicArray(from text: String) throws -> [MnemonicItem] {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiError.unprocessableData
        }

        do {
            return try JSONDecoder().decode([MnemonicItem].self, from: data)
        } catch {
            print("Groq JSON decode failed: \(error)\nRaw cleaned: \(cleaned)")
            throw GeminiError.unprocessableData
        }
    }

    private func extractRetryDelay(from message: String) -> String {
        // Groq messages say "Please try again in 10.5s" or "try again in 1m30s"
        if let range = message.range(of: #"in [\d.]+[ms]"#, options: .regularExpression) {
            return String(message[range])
        }
        return "a moment"
    }
}
