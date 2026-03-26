import Foundation

enum DictionaryError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case unprocessableData
    case wordNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The URL provided was invalid."
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .unprocessableData: return "Failed to process the dictionary response."
        case .wordNotFound: return "We couldn't find a definition for that word."
        }
    }
}

class DictionaryService {
    static let shared = DictionaryService()
    
    private var apiKey: String {
        let userKey = AuthManager.shared.merriamWebsterKey
        return userKey
    }
    private let baseURL = "https://www.dictionaryapi.com/api/v3/references/collegiate/json/"
    
    private init() {}
    
    func fetchWordDefinition(_ word: String) async throws -> [MWDictionaryResponse] {
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: baseURL + encodedWord + "?key=\(apiKey)") else {
            throw DictionaryError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 404 { throw DictionaryError.wordNotFound }
            if !(200...299).contains(httpResponse.statusCode) {
                throw DictionaryError.networkError(NSError(domain: "HTTP", code: httpResponse.statusCode))
            }
        }
        
        let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
        var parsedResponses: [MWDictionaryResponse] = []
        
        // MW sometimes returns an array of strings (suggestions) if the word isn't found exactly
        if jsonArray.first is String {
            throw DictionaryError.wordNotFound
        }
        
        for element in jsonArray {
            guard let entry = element as? [String: Any],
                  let meta = entry["meta"] as? [String: Any],
                  let id = meta["id"] as? String else { continue }
            
            let cleanWord = id.components(separatedBy: ":").first ?? word
            let stems = meta["stems"] as? [String] ?? []
            let fl = entry["fl"] as? String ?? "unknown"
            let shortdefs = entry["shortdef"] as? [String] ?? []
            
            // Audio Extraction
            var phonetic: String? = nil
            var audioURL: URL? = nil
            if let hwi = entry["hwi"] as? [String: Any],
               let prs = hwi["prs"] as? [[String: Any]],
               let firstPrs = prs.first {
                phonetic = firstPrs["mw"] as? String
                if let sound = firstPrs["sound"] as? [String: Any], let audio = sound["audio"] as? String {
                    var subdir = String(audio.prefix(1))
                    if audio.hasPrefix("bix") { subdir = "bix" }
                    else if audio.hasPrefix("gg") { subdir = "gg" }
                    else if let first = audio.first, first.isNumber || first == "_" { subdir = "number" }
                    audioURL = URL(string: "https://media.merriam-webster.com/audio/prons/en/us/mp3/\(subdir)/\(audio).mp3")
                }
            }
            
            let examples = extractExamples(from: entry)
            
            let dictionaryResponse = MWDictionaryResponse(
                id: id,
                word: cleanWord,
                phonetic: phonetic,
                audioURL: audioURL,
                partOfSpeech: fl,
                stems: stems,
                shortDefinitions: shortdefs,
                examples: examples
            )
            parsedResponses.append(dictionaryResponse)
        }
        
        // Filter out phrasal matches (like "very high frequency" when searching "very")
        let filteredResponses = parsedResponses.filter { response in
            let lowercasedSearch = word.lowercased()
            // If we didn't search for a phrase, don't include phrase definitions
            if !lowercasedSearch.contains(" ") && response.word.contains(" ") {
                return false
            }
            return response.word.lowercased() == lowercasedSearch || response.stems.map { $0.lowercased() }.contains(lowercasedSearch)
        }
        
        if filteredResponses.isEmpty { throw DictionaryError.wordNotFound }
        return filteredResponses
    }
    
    private func extractExamples(from json: Any) -> [String] {
        var results: [String] = []
        if let dict = json as? [String: Any] {
            var handled = false
            if let visArray = dict["vis"] as? [[String: Any]] { // MW specific 'vis' block for examples
                for visNode in visArray {
                    if let t = visNode["t"] as? String { results.append(cleanMWMarkup(t)) }
                }
                handled = true
            }
            if let quoteArray = dict["quotes"] as? [[String: Any]] { // MW specific 'quotes' block
                for quoteNode in quoteArray {
                    if let t = quoteNode["t"] as? String { results.append(cleanMWMarkup(t)) }
                }
                handled = true
            }
            
            if !handled {
                for value in dict.values { results.append(contentsOf: extractExamples(from: value)) }
            }
        } else if let array = json as? [Any] {
            for (index, element) in array.enumerated() {
                if let str = element as? String, (str == "vis" || str == "quotes"), index + 1 < array.count {
                    if let visArray = array[index + 1] as? [[String: Any]] {
                        for visNode in visArray {
                            if let t = visNode["t"] as? String { results.append(cleanMWMarkup(t)) }
                        }
                    }
                } else {
                    results.append(contentsOf: extractExamples(from: element))
                }
            }
        }
        return results
    }
    
    private func cleanMWMarkup(_ text: String) -> String {
        let regex = try? NSRegularExpression(pattern: "\\{.*?\\}")
        let clean = regex?.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return clean?.trimmingCharacters(in: .whitespaces) ?? text
    }
}
