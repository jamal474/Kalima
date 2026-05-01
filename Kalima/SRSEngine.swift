import Foundation

class SRSEngine {

    // MARK: - Public API

    enum ResponseRating {
        case again
        case hard
        case good
        case easy
    }

    /// Global configuration. Override in tests by mutating `SRSEngine.config` in `setUp()`.
    static var config = SRSConfig()

    /// Processes a single review event and returns a `ReviewResult` containing the
    /// fully updated `SRSData` plus diagnostic flags (`didGraduate`, `didLapse`).
    ///
    /// - Parameters:
    ///   - currentData: The card's current SRS state.
    ///   - rating:      The user's self-assessment for this review.
    ///   - reviewedAt:  The point-in-time the review occurred. Defaults to `Date()`.
    ///                  Inject a fixed date in tests to make scheduling deterministic.
    static func processReview(
        currentData: SRSData,
        rating: ResponseRating,
        reviewedAt: Date = Date()
    ) -> ReviewResult {

        let previousInterval = currentData.safeInterval
        var newData = currentData
        var didGraduate = false
        var didLapse = false

        switch currentData.cardStatus {

        // MARK: Learning Phase (.new or .learning)
        case .new, .learning:
            let currentStep: Int
            if case .learning(let s) = currentData.cardStatus {
                currentStep = s
            } else {
                currentStep = 0
            }

            switch rating {
            case .again:
                // Reset to step 0
                newData.cardStatus = .learning(step: 0)
                newData.nextReviewDate = nextReviewDate(
                    addingMinutes: config.learningSteps[0], to: reviewedAt)

            case .hard:
                // Stay on the current step
                newData.cardStatus = .learning(step: currentStep)
                newData.nextReviewDate = nextReviewDate(
                    addingMinutes: config.learningSteps[currentStep], to: reviewedAt)

            case .good:
                let nextStep = currentStep + 1
                if nextStep < config.learningSteps.count {
                    // Advance to next step
                    newData.cardStatus = .learning(step: nextStep)
                    newData.nextReviewDate = nextReviewDate(
                        addingMinutes: config.learningSteps[nextStep], to: reviewedAt)
                } else {
                    // Graduate to review
                    newData.cardStatus = .review
                    newData.safeInterval = config.minimumInterval
                    newData.nextReviewDate = nextReviewDate(
                        addingDays: config.minimumInterval, to: reviewedAt)
                    newData.safeCCA += 1
                    didGraduate = true
                }

            case .easy:
                // Immediate graduation with an easy-first interval
                let rawInterval = config.easyFirstInterval
                let fuzzed = Int(fuzzedInterval(rawInterval))
                newData.cardStatus = .review
                newData.safeInterval = fuzzed
                newData.nextReviewDate = nextReviewDate(addingDays: fuzzed, to: reviewedAt)
                newData.safeCCA += 1
                newData.safeEaseFactor += config.easyEaseFactorDelta
                newData.safeEaseFactor = max(config.minimumEaseFactor, newData.safeEaseFactor)
                didGraduate = true
            }

        // MARK: Review Phase (.review)
        case .review:
            switch rating {
            case .again:
                newData.safeCCA = 0
                newData.safeEaseFactor -= config.againEaseFactorDelta
                newData.safeEaseFactor = max(config.minimumEaseFactor, newData.safeEaseFactor)
                didLapse = true

                if config.relearningSteps.isEmpty {
                    // Skip relearning queue — go straight back to review
                    newData.cardStatus = .review
                    newData.safeInterval = config.relearningGraduationInterval
                    newData.nextReviewDate = nextReviewDate(
                        addingDays: config.relearningGraduationInterval, to: reviewedAt)
                } else {
                    newData.cardStatus = .relearning(step: 0)
                    newData.safeInterval = config.relearningGraduationInterval
                    newData.nextReviewDate = nextReviewDate(
                        addingMinutes: config.relearningSteps[0], to: reviewedAt)
                }

            case .hard:
                newData.safeCCA += 1
                let rawInterval = Double(currentData.safeInterval) * config.hardIntervalMultiplier
                let fuzzed = Int(fuzzedInterval(rawInterval))
                newData.safeInterval = fuzzed
                newData.safeEaseFactor -= config.hardEaseFactorDelta
                newData.safeEaseFactor = max(config.minimumEaseFactor, newData.safeEaseFactor)
                newData.nextReviewDate = nextReviewDate(addingDays: fuzzed, to: reviewedAt)

            case .good:
                newData.safeCCA += 1
                let rawInterval = Double(currentData.safeInterval) * currentData.safeEaseFactor
                let fuzzed = Int(fuzzedInterval(rawInterval))
                newData.safeInterval = fuzzed
                // easeFactor does not change on .good
                newData.nextReviewDate = nextReviewDate(addingDays: fuzzed, to: reviewedAt)

            case .easy:
                newData.safeCCA += 1
                let rawInterval = Double(currentData.safeInterval) * currentData.safeEaseFactor * config.easyBonus
                let fuzzed = Int(fuzzedInterval(rawInterval))
                newData.safeInterval = fuzzed
                newData.safeEaseFactor += config.easyEaseFactorDelta
                newData.safeEaseFactor = max(config.minimumEaseFactor, newData.safeEaseFactor)
                newData.nextReviewDate = nextReviewDate(addingDays: fuzzed, to: reviewedAt)
            }

        // MARK: Relearning Phase (.relearning)
        case .relearning(let s):
            switch rating {
            case .again:
                // Reset to step 0, apply ease penalty
                newData.cardStatus = .relearning(step: 0)
                newData.nextReviewDate = nextReviewDate(
                    addingMinutes: config.relearningSteps[0], to: reviewedAt)
                newData.safeEaseFactor -= config.againEaseFactorDelta
                newData.safeEaseFactor = max(config.minimumEaseFactor, newData.safeEaseFactor)

            case .hard:
                // Stay on current step
                newData.cardStatus = .relearning(step: s)
                newData.nextReviewDate = nextReviewDate(
                    addingMinutes: config.relearningSteps[s], to: reviewedAt)

            case .good:
                let nextStep = s + 1
                if nextStep < config.relearningSteps.count {
                    // Advance to next relearning step
                    newData.cardStatus = .relearning(step: nextStep)
                    newData.nextReviewDate = nextReviewDate(
                        addingMinutes: config.relearningSteps[nextStep], to: reviewedAt)
                } else {
                    // Graduate back to review
                    let fuzzed = Int(fuzzedInterval(Double(config.relearningGraduationInterval)))
                    newData.cardStatus = .review
                    newData.safeInterval = fuzzed
                    newData.nextReviewDate = nextReviewDate(addingDays: fuzzed, to: reviewedAt)
                    newData.safeCCA += 1
                    didGraduate = true
                }

            case .easy:
                // Immediate graduation back to review
                let fuzzed = Int(fuzzedInterval(Double(config.relearningGraduationInterval)))
                newData.cardStatus = .review
                newData.safeInterval = fuzzed
                newData.nextReviewDate = nextReviewDate(addingDays: fuzzed, to: reviewedAt)
                newData.safeCCA += 1
                newData.safeEaseFactor += config.easyEaseFactorDelta
                newData.safeEaseFactor = max(config.minimumEaseFactor, newData.safeEaseFactor)
                didGraduate = true
            }
        }

        return ReviewResult(
            updatedData: newData,
            previousInterval: previousInterval,
            scheduledIntervalDays: newData.safeInterval,
            rating: rating,
            reviewedAt: reviewedAt,
            didGraduate: didGraduate,
            didLapse: didLapse
        )
    }

    // MARK: - Private Helpers

    /// Applies a small random variation to an interval to prevent cards from
    /// clustering on the same review date. Only applied to intervals greater than 2 days.
    private static func fuzzedInterval(_ interval: Double) -> Double {
        guard interval > 2 else { return interval }
        let fuzz = Double.random(in: -config.fuzzFactor...config.fuzzFactor)
        return max(Double(config.minimumInterval), (interval * (1 + fuzz)).rounded())
    }

    /// Returns a date by adding `minutes` to `date`.
    private static func nextReviewDate(addingMinutes minutes: Int, to date: Date) -> Date {
        return Calendar.current.date(byAdding: .minute, value: minutes, to: date) ?? date
    }

    /// Returns a date by adding `days` to `date`.
    private static func nextReviewDate(addingDays days: Int, to date: Date) -> Date {
        return Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}
