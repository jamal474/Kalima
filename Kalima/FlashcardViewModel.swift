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
    
    /// Constructs the SM-2 daily queue prioritizing Reviews > Learning > New (capped at 20)
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
            let reviews = allWords.filter { $0.srsData.status == .review && $0.srsData.nextReviewDate <= now }
                .sorted { $0.srsData.nextReviewDate < $1.srsData.nextReviewDate }
            
            // Priority 2: Learning / Relearning
            let learning = allWords.filter { ($0.srsData.status == .learning || $0.srsData.status == .relearning) && $0.srsData.nextReviewDate <= now }
                .sorted { $0.srsData.nextReviewDate < $1.srsData.nextReviewDate }
            
            // Priority 3: New Cards (Hard capped at 20)
            let newCards = allWords.filter { $0.srsData.status == .new }
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
        let newSRSData = SRSEngine.processReview(currentData: card.srsData, rating: rating)
        card.srsData = newSRSData
        
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
