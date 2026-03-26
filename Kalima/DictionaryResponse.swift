import Foundation

struct MWDictionaryResponse: Codable {
    let id: String
    let word: String
    let phonetic: String?
    let audioURL: URL?
    let partOfSpeech: String
    let stems: [String]
    let shortDefinitions: [String]
    let examples: [String]
}
