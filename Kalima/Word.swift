import Foundation
import SwiftData
import SwiftUI

@Model
final class Word {
    @Attribute(.unique) var id: UUID
    var userId: String
    var term: String
    var partOfSpeech: String
    var phoneticSpelling: String?
    var pronunciationUrl: URL?
    
    // Linguistic Data
    var meaning: String
    var examples: [String]
    var synonyms: [String]
    var antonyms: [String]
    var detailedMeanings: [MeaningDetails]?
    
    // Categorization
    var deck: Deck?
    
    // User Context
    var mnemonics: String?          // Legacy single-string field (kept for backward compat)
    var personalMnemonics: [MnemonicItem]?  // Structured personal mnemonics with description
    var fetchedMnemonics: [MnemonicItem]?
    var tags: [String]
    var isFavorite: Bool
    
    // Learning Status -- SwiftData supports struct properties if they conform to Codable
    var srsData: SRSData
    var createdAt: Date
    var lastSyncedAt: Date?
    
    init(userId: String = "local_user", term: String, partOfSpeech: String, phoneticSpelling: String? = nil, pronunciationUrl: URL? = nil, meaning: String, examples: [String] = [], synonyms: [String] = [], antonyms: [String] = [], detailedMeanings: [MeaningDetails]? = nil, mnemonics: String? = nil, personalMnemonics: [MnemonicItem]? = nil, fetchedMnemonics: [MnemonicItem]? = nil, tags: [String] = [], deck: Deck? = nil, isFavorite: Bool = false, srsData: SRSData = SRSData(), createdAt: Date = Date(), lastSyncedAt: Date? = nil) {
        self.id = UUID()
        self.userId = userId
        self.term = term
        self.partOfSpeech = partOfSpeech
        self.phoneticSpelling = phoneticSpelling
        self.pronunciationUrl = pronunciationUrl
        self.meaning = meaning
        self.examples = examples
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.detailedMeanings = detailedMeanings
        self.mnemonics = mnemonics
        self.personalMnemonics = personalMnemonics
        self.fetchedMnemonics = fetchedMnemonics
        self.tags = tags
        self.deck = deck
        self.isFavorite = isFavorite
        self.srsData = srsData
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
    }
    
    /// Convert to Firestore REST API "fields" format — stores ALL word data
    func toFirestoreFields() -> [String: Any] {
        let iso = ISO8601DateFormatter()

        // ── Core fields ────────────────────────────────────────────────
        var fields: [String: Any] = [
            "term":         ["stringValue": term],
            "meaning":      ["stringValue": meaning],
            "partOfSpeech": ["stringValue": partOfSpeech],
            "userId":       ["stringValue": userId],
            "isFavorite":   ["booleanValue": isFavorite],
            "createdAt":    ["timestampValue": iso.string(from: createdAt)]
        ]

        if let phonetic = phoneticSpelling {
            fields["phoneticSpelling"] = ["stringValue": phonetic]
        }
        if let url = pronunciationUrl {
            fields["pronunciationUrl"] = ["stringValue": url.absoluteString]
        }

        // ── Arrays (examples / synonyms / antonyms / tags) ─────────────
        func stringArray(_ arr: [String]) -> [String: Any] {
            ["arrayValue": ["values": arr.map { ["stringValue": $0] }]]
        }
        if !examples.isEmpty  { fields["examples"]  = stringArray(examples) }
        if !synonyms.isEmpty  { fields["synonyms"]  = stringArray(synonyms) }
        if !antonyms.isEmpty  { fields["antonyms"]  = stringArray(antonyms) }
        if !tags.isEmpty      { fields["tags"]       = stringArray(tags) }

        // ── Detailed meanings (part-of-speech → definitions + examples) ─
        if let dm = detailedMeanings, !dm.isEmpty {
            let encoded = (try? JSONSerialization.data(withJSONObject:
                dm.map { ["partOfSpeech": $0.partOfSpeech,
                          "definitions": $0.definitions,
                          "examples": $0.examples] }
            )).flatMap { String(data: $0, encoding: .utf8) }
            if let json = encoded {
                fields["detailedMeanings"] = ["stringValue": json]
            }
        }

        // ── AI-fetched mnemonics (Groq / Gemini) ───────────────────────
        if let fm = fetchedMnemonics, !fm.isEmpty {
            let encoded = (try? JSONSerialization.data(withJSONObject:
                fm.map { ["mnemonic": $0.mnemonic, "explanation": $0.explanation] }
            )).flatMap { String(data: $0, encoding: .utf8) }
            if let json = encoded {
                fields["fetchedMnemonics"] = ["stringValue": json]
            }
        }

        // ── Personal mnemonics (user-written — must not be lost) ───────
        if let pm = personalMnemonics, !pm.isEmpty {
            let encoded = (try? JSONSerialization.data(withJSONObject:
                pm.map { ["mnemonic": $0.mnemonic, "explanation": $0.explanation] }
            )).flatMap { String(data: $0, encoding: .utf8) }
            if let json = encoded {
                fields["personalMnemonics"] = ["stringValue": json]
            }
        }

        // ── SRS scheduling data ────────────────────────────────────────
        let srsDict: [String: Any] = [
            "status":         ["stringValue":   srsData.status.rawValue],
            "nextReviewDate": ["timestampValue": iso.string(from: srsData.nextReviewDate)],
            "interval":       ["integerValue":  "\(srsData.interval)"],
            "easeFactor":     ["doubleValue":   srsData.easeFactor],
            "consecutiveCorrectAnswers": ["integerValue": "\(srsData.consecutiveCorrectAnswers)"]
        ]
        fields["srsData"] = ["mapValue": ["fields": srsDict]]

        return fields
    }
}


enum LearningStatus: String, Codable {
    case new
    case learning
    case review = "reviewing" // Maps to legacy database state
    case relearning = "graduated" // Maps to legacy database state
}

extension Color {
    // Custom Major Theme Color
    static let theme = Color(red: 0.384, green: 0.564, blue: 0.764)
}

struct MeaningDetails: Codable, Hashable {
    var partOfSpeech: String
    var definitions: [String]
    var examples: [String]
}

struct MnemonicItem: Codable, Hashable {
    var mnemonic: String
    var explanation: String
}

struct SRSData: Codable {
    var status: LearningStatus
    var nextReviewDate: Date
    var interval: Int // In days
    var easeFactor: Double
    var consecutiveCorrectAnswers: Int // Keeping this internal metric for future gamification if needed
    
    init(status: LearningStatus = .new, nextReviewDate: Date = Date(), interval: Int = 0, easeFactor: Double = 2.5, consecutiveCorrectAnswers: Int = 0) {
        self.status = status
        self.nextReviewDate = nextReviewDate
        self.interval = interval
        self.easeFactor = easeFactor
        self.consecutiveCorrectAnswers = consecutiveCorrectAnswers
    }
}
