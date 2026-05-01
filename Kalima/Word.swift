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
    
    var mnemonics: String?
    var personalMnemonics: [MnemonicItem]?
    var fetchedMnemonics: [MnemonicItem]?
    var tags: [String]
    var isFavorite: Bool
    
    // Learning Status
    var srsData: SRSData
    var createdAt: Date
    var lastSyncedAt: Date?
    
    init(id: UUID? = nil, userId: String = "local_user", term: String, partOfSpeech: String, phoneticSpelling: String? = nil, pronunciationUrl: URL? = nil, meaning: String, examples: [String] = [], synonyms: [String] = [], antonyms: [String] = [], detailedMeanings: [MeaningDetails]? = nil, mnemonics: String? = nil, personalMnemonics: [MnemonicItem]? = nil, fetchedMnemonics: [MnemonicItem]? = nil, tags: [String] = [], deck: Deck? = nil, isFavorite: Bool = false, srsData: SRSData = SRSData(), createdAt: Date = Date(), lastSyncedAt: Date? = nil) {
        self.id = id ?? UUID()
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

        func stringArray(_ arr: [String]) -> [String: Any] {
            ["arrayValue": ["values": arr.map { ["stringValue": $0] }]]
        }
        if !examples.isEmpty  { fields["examples"]  = stringArray(examples) }
        if !synonyms.isEmpty  { fields["synonyms"]  = stringArray(synonyms) }
        if !antonyms.isEmpty  { fields["antonyms"]  = stringArray(antonyms) }
        if !tags.isEmpty      { fields["tags"]       = stringArray(tags) }

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

        if let fm = fetchedMnemonics, !fm.isEmpty {
            let encoded = (try? JSONSerialization.data(withJSONObject:
                fm.map { ["mnemonic": $0.mnemonic, "explanation": $0.explanation] }
            )).flatMap { String(data: $0, encoding: .utf8) }
            if let json = encoded {
                fields["fetchedMnemonics"] = ["stringValue": json]
            }
        }

        if let pm = personalMnemonics, !pm.isEmpty {
            let encoded = (try? JSONSerialization.data(withJSONObject:
                pm.map { ["mnemonic": $0.mnemonic, "explanation": $0.explanation] }
            )).flatMap { String(data: $0, encoding: .utf8) }
            if let json = encoded {
                fields["personalMnemonics"] = ["stringValue": json]
            }
        }

        let srsDict: [String: Any] = [
            "status":         ["stringValue":   srsData.status ?? "new"],
            "nextReviewDate": ["timestampValue": iso.string(from: srsData.nextReviewDate ?? Date())],
            "interval":       ["integerValue":  "\(srsData.interval ?? 0)"],
            "easeFactor":     ["doubleValue":   srsData.easeFactor ?? 2.5],
            "consecutiveCorrectAnswers": ["integerValue": "\(srsData.consecutiveCorrectAnswers ?? 0)"]
        ]
        fields["srsData"] = ["mapValue": ["fields": srsDict]]

        return fields
    }
}


/// Tracks precisely which queue and step a flashcard is in.
enum CardStatus: Equatable {
    /// The card has never been reviewed. Not yet in any queue.
    case new

    /// The card is in the initial learning phase.
    /// `step` is the index into SRSConfig.learningSteps the card is currently at.
    /// When step reaches learningSteps.count, the card graduates to .review.
    case learning(step: Int)

    /// The card is in the main spaced repetition review queue.
    case review

    /// The card was failed during a review session and is being relearned.
    /// `step` is the index into SRSConfig.relearningSteps.
    /// When step reaches relearningSteps.count, the card returns to .review.
    case relearning(step: Int)

    // MARK: - Display Helpers

    /// A human-readable label suitable for display in the UI.
    var displayName: String {
        switch self {
        case .new:               return "New"
        case .learning:          return "Learning"
        case .review:            return "Review"
        case .relearning:        return "Relearning"
        }
    }

    // MARK: - Firestore Serialisation

    /// Encodes the status as a flat string for Firestore storage.
    /// Examples: "new", "learning_0", "review", "relearning_1"
    var firestoreValue: String {
        switch self {
        case .new:                  return "new"
        case .learning(let step):   return "learning_\(step)"
        case .review:               return "review"
        case .relearning(let step): return "relearning_\(step)"
        }
    }

    /// Decodes a Firestore string back to a CardStatus.
    init(firestoreValue: String) {
        switch firestoreValue {
        case "new":                                  self = .new
        case "review", "reviewing":                  self = .review
        case let s where s.hasPrefix("learning_"):
            let step = Int(s.dropFirst("learning_".count)) ?? 0
            self = .learning(step: step)
        case let s where s.hasPrefix("relearning_"):
            let step = Int(s.dropFirst("relearning_".count)) ?? 0
            self = .relearning(step: step)
        // Legacy mappings from the old LearningStatus enum
        case "learning":                             self = .learning(step: 0)
        case "graduated":                            self = .relearning(step: 0)
        default:                                     self = .new
        }
    }
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
    var status: String?
    var nextReviewDate: Date?
    var interval: Int?
    var easeFactor: Double?
    var consecutiveCorrectAnswers: Int?

    // Computed property for typed access to the status
    var cardStatus: CardStatus {
        get { CardStatus(firestoreValue: status ?? "new") }
        set { status = newValue.firestoreValue }
    }

    /// True when the card has never been reviewed.
    var isNew: Bool {
        if case .new = cardStatus { return true }
        return false
    }

    init(status: CardStatus = .new, nextReviewDate: Date = Date(), interval: Int = 0, easeFactor: Double = 2.5, consecutiveCorrectAnswers: Int = 0) {
        self.status = status.firestoreValue
        self.nextReviewDate = nextReviewDate
        self.interval = interval
        self.easeFactor = easeFactor
        self.consecutiveCorrectAnswers = consecutiveCorrectAnswers
    }

    var safeInterval: Int {
        get { interval ?? 0 }
        set { interval = newValue }
    }
    
    var safeEaseFactor: Double {
        get { easeFactor ?? 2.5 }
        set { easeFactor = newValue }
    }
    
    var safeCCA: Int {
        get { consecutiveCorrectAnswers ?? 0 }
        set { consecutiveCorrectAnswers = newValue }
    }
}
