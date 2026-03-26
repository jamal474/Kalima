import Foundation

class SRSEngine {
    
    enum ResponseRating {
        case again
        case hard
        case good
        case easy
    }
    
    /// Processes a review and returns an updated SRSData struct based on the SM-2 algorithm.
    static func processReview(currentData: SRSData, rating: ResponseRating) -> SRSData {
        var newData = currentData
        var newInterval: Double = Double(newData.interval)
        var newEaseFactor: Double = newData.easeFactor
        
        switch rating {
        case .again: // Grade 1
            newData.consecutiveCorrectAnswers = 0
            newInterval = 1.0 // Resets interval to 1 day
            newEaseFactor -= 0.20
            newData.status = .relearning
            
        case .hard: // Grade 2
            newData.consecutiveCorrectAnswers += 1
            if currentData.interval == 0 {
                newInterval = 1.0
            } else {
                newInterval = Double(currentData.interval) * 1.2
            }
            newEaseFactor -= 0.15
            newData.status = .review
            
        case .good: // Grade 3
            newData.consecutiveCorrectAnswers += 1
            if currentData.interval == 0 {
                newInterval = 1.0
            } else {
                newInterval = Double(currentData.interval) * currentData.easeFactor
            }
            // EF remains practically unchanged
            newData.status = .review
            
        case .easy: // Grade 4
            newData.consecutiveCorrectAnswers += 1
            if currentData.interval == 0 {
                newInterval = 4.0
            } else {
                newInterval = Double(currentData.interval) * currentData.easeFactor * 1.3
            }
            newEaseFactor += 0.15
            newData.status = .review
        }
        
        // Enforce boundary logic: easeFactor should never drop below 1.3
        newEaseFactor = max(1.3, newEaseFactor)
        
        newData.interval = Int(round(newInterval))
        newData.easeFactor = newEaseFactor
        
        // Calculate and assign the new nextReviewDate
        if let nextDate = Calendar.current.date(byAdding: .day, value: newData.interval, to: Date()) {
            newData.nextReviewDate = nextDate
        }
        
        return newData
    }
}
