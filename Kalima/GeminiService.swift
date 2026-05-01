import Foundation

enum GeminiError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case unprocessableData
    case apiError(String)
    case rateLimited(retryAfter: String)   // 429 – includes human-readable wait time

    var errorDescription: String? {
        switch self {
        case .invalidURL:              return "The URL provided was invalid."
        case .networkError(let e):     return "Network error: \(e.localizedDescription)"
        case .unprocessableData:       return "Failed to process the Gemini response."
        case .apiError(let msg):       return "API Error: \(msg)"
        case .rateLimited(let after):  return "Rate limit hit. Please retry after \(after)."
        }
    }
}

class GeminiService {
    static let shared = GeminiService()
    
    private var apiKey: String {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["GEMINI_API_KEY"] as? String, !key.isEmpty, key != "YOUR_API_KEY_HERE" {
            return key
        }
        return AuthManager.shared.geminiKey
    }
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
    
    private init() {}
    
    func fetchMnemonics(for word: String, meaning: String) async throws -> [MnemonicItem] {
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }
        
        let prompt = """
        You are an expert vocabulary tutor. Create highly memorable, short mnemonics for the word '\(word)', meaning: '\(meaning)'.

        Guidelines:
        1. Provide at most 4 mnemonics.
        2. Focus on "sounds-like" wordplay, phonetic associations, vivid imagery, or humor.
        3. Keep the "mnemonic" string punchy and short (under 10 words).

        Output Requirements:
        Return ONLY a valid, raw JSON array of objects. Absolutely no markdown formatting (do NOT use ```json blocks), no preamble, and no explanations outside the JSON.

        Use this exact schema for each object in the array:
        {
        "mnemonic": "The short memory trick",
        "explanation": "How the trick connects the sound or spelling of the word to its meaning"
        }
        """
        
        let generateContentRequest: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json"
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: generateContentRequest)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = json["error"] as? [String: Any] {

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                if statusCode == 429 {
                    var retryAfter = "a moment"
                    if let details = errorObj["details"] as? [[String: Any]] {
                        for detail in details {
                            if let metadata = detail["metadata"] as? [String: Any],
                               let delay = metadata["retryDelay"] as? String {
                                retryAfter = delay
                                break
                            }
                        }
                    }
                    throw GeminiError.rateLimited(retryAfter: retryAfter)
                }

                let message = errorObj["message"] as? String ?? "Unknown API error"
                throw GeminiError.apiError(message)
            }
            throw GeminiError.networkError(NSError(domain: "HTTP", code: (response as? HTTPURLResponse)?.statusCode ?? 500))
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = jsonObject["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.unprocessableData
        }
        
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            
        guard let textData = cleanedText.data(using: .utf8) else {
            throw GeminiError.unprocessableData
        }
        let decoder = JSONDecoder()
        do {
            let items = try decoder.decode([MnemonicItem].self, from: textData)
            return items
        } catch {
            print("Failed to decode JSON from Gemini: \(error)")
            throw GeminiError.unprocessableData
        }
    }
}
