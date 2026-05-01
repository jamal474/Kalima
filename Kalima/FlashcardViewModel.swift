import Foundation
import SwiftData
import SwiftUI

@Observable
class FlashcardViewModel {
    var dueCards: [Word] = []
    var currentIndex: Int = 0
    var isShowingAnswer: Bool = false
    
    // Status Trackers
    var sessionCompleted: Bool = false
    
    /// Constructs the daily queue prioritizing Reviews > Learning > New (capped at 20)
    func getDailyQueue(deckId: UUID? = nil, context: ModelContext) {
        let descriptor = FetchDescriptor<Word>()
        let now = Date()
        
        do {
            var allWords = try context.fetch(descriptor)
            
            // Filter by deck if provided
            if let targetDeckId = deckId {
                allWords = allWords.filter { $0.deck?.id == targetDeckId }
            }
            
            // Priority 1: Overdue/Due Reviews
            let reviews = allWords.filter {
                if case .review = $0.srsData.cardStatus { return ($0.srsData.nextReviewDate ?? Date()) <= now }
                return false
            }.sorted { ($0.srsData.nextReviewDate ?? Date()) < ($1.srsData.nextReviewDate ?? Date()) }
            
            // Priority 2: Learning / Relearning
            let learning = allWords.filter {
                switch $0.srsData.cardStatus {
                case .learning, .relearning: return ($0.srsData.nextReviewDate ?? Date()) <= now
                default: return false
                }
            }.sorted { ($0.srsData.nextReviewDate ?? Date()) < ($1.srsData.nextReviewDate ?? Date()) }
            
            // Priority 3: New Cards (Hard capped at 20)
            let newCards = allWords.filter { $0.srsData.isNew }
                .prefix(20)
            
            // Create final queue
            self.dueCards = reviews + learning + Array(newCards)
            
            self.currentIndex = 0
            self.isShowingAnswer = false
            self.sessionCompleted = self.dueCards.isEmpty
        } catch {
            print("Failed to fetch due cards: \(error.localizedDescription)")
        }
    }
    
    var currentCard: Word? {
        guard currentIndex < dueCards.count else { return nil }
        return dueCards[currentIndex]
    }
    
    func revealAnswer() {
        isShowingAnswer = true
    }
    
    func submitRating(_ rating: SRSEngine.ResponseRating, context: ModelContext) {
        guard let card = currentCard else { return }
        
        // Execute the Spaced Repetition Logic on this card
        let result = SRSEngine.processReview(currentData: card.srsData, rating: rating)
        card.srsData = result.updatedData
        
        // Log graduation / lapse events for debugging / future analytics
        if result.didGraduate {
            print("🎓 '\(card.term)' graduated to review (interval: \(result.scheduledIntervalDays)d)")
        }
        if result.didLapse {
            print("😓 '\(card.term)' lapsed back to relearning")
        }
        
        // Save Context
        do {
            try context.save()
        } catch {
            print("Error saving SRS rating: \(error.localizedDescription)")
        }
        
        advanceToNextCard()
    }
    
    private func advanceToNextCard() {
        currentIndex += 1
        isShowingAnswer = false
        
        if currentIndex >= dueCards.count {
            sessionCompleted = true
        }
    }
}
