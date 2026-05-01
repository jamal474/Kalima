import XCTest
@testable import Kalima

/// Tests for SRSEngine.
///
/// All tests use a fixed `reviewedAt` date so scheduling results are deterministic.
/// Fuzzing is disabled via `SRSEngine.config.fuzzFactor = 0.0` in setUp().
final class SRSEngineTests: XCTestCase {

    // A fixed point in time used across all tests
    let t0 = Date(timeIntervalSince1970: 0)

    override func setUp() {
        super.setUp()
        // Reset config to defaults, then disable fuzz for determinism
        SRSEngine.config = SRSConfig()
        SRSEngine.config.fuzzFactor = 0.0
    }

    // MARK: - Helpers

    private func newCard() -> SRSData {
        SRSData(status: .new)
    }

    private func reviewCard(interval: Int, easeFactor: Double = 2.5) -> SRSData {
        SRSData(status: .review, nextReviewDate: Date(), interval: interval, easeFactor: easeFactor)
    }

    private func learningCard(step: Int) -> SRSData {
        SRSData(status: .learning(step: step))
    }

    private func relearningCard(step: Int, interval: Int = 10, easeFactor: Double = 2.5) -> SRSData {
        SRSData(status: .relearning(step: step), interval: interval, easeFactor: easeFactor)
    }

    private func process(_ data: SRSData, rating: SRSEngine.ResponseRating) -> ReviewResult {
        SRSEngine.processReview(currentData: data, rating: rating, reviewedAt: t0)
    }

    // MARK: - Learning Phase Tests

    func testNewCard_again_staysAtLearningStep0() {
        let result = process(newCard(), rating: .again)
        XCTAssertEqual(result.updatedData.cardStatus, .learning(step: 0))
        // Should be due 1 minute from t0
        let expected = Calendar.current.date(byAdding: .minute, value: 1, to: t0)!
        XCTAssertEqual(result.updatedData.nextReviewDate, expected)
        XCTAssertFalse(result.didGraduate)
        XCTAssertFalse(result.didLapse)
    }

    func testNewCard_good_advancesToLearningStep1() {
        let result = process(newCard(), rating: .good)
        XCTAssertEqual(result.updatedData.cardStatus, .learning(step: 1))
        // Should be due 10 minutes from t0
        let expected = Calendar.current.date(byAdding: .minute, value: 10, to: t0)!
        XCTAssertEqual(result.updatedData.nextReviewDate, expected)
        XCTAssertFalse(result.didGraduate)
    }

    func testNewCard_good_good_graduatesToReview() {
        let after1Good = process(newCard(), rating: .good).updatedData
        let result = process(after1Good, rating: .good)
        XCTAssertEqual(result.updatedData.cardStatus, .review)
        XCTAssertEqual(result.updatedData.interval, SRSEngine.config.minimumInterval)
        XCTAssertTrue(result.didGraduate)
    }

    func testNewCard_easy_immediatelyGraduatesToReview() {
        let result = process(newCard(), rating: .easy)
        XCTAssertEqual(result.updatedData.cardStatus, .review)
        XCTAssertEqual(result.updatedData.interval, 4) // easy first interval, fuzz=0
        XCTAssertTrue(result.didGraduate)
        // easeFactor should increase
        XCTAssertEqual(result.updatedData.easeFactor, 2.5 + SRSEngine.config.easyEaseFactorDelta, accuracy: 0.001)
    }

    func testLearningCard_hard_staysOnCurrentStep() {
        let result = process(learningCard(step: 0), rating: .hard)
        XCTAssertEqual(result.updatedData.cardStatus, .learning(step: 0))
        let expected = Calendar.current.date(byAdding: .minute, value: SRSEngine.config.learningSteps[0], to: t0)!
        XCTAssertEqual(result.updatedData.nextReviewDate, expected)
    }

    // MARK: - Review Phase Tests

    func testReviewCard_again_transitionsToRelearning() {
        let card = reviewCard(interval: 10)
        let result = process(card, rating: .again)
        XCTAssertEqual(result.updatedData.cardStatus, .relearning(step: 0))
        XCTAssertEqual(result.updatedData.consecutiveCorrectAnswers, 0)
        let expectedEF = max(SRSEngine.config.minimumEaseFactor, 2.5 - SRSEngine.config.againEaseFactorDelta)
        XCTAssertEqual(result.updatedData.easeFactor, expectedEF, accuracy: 0.001)
        XCTAssertTrue(result.didLapse)
        XCTAssertFalse(result.didGraduate)
        XCTAssertEqual(result.previousInterval, 10)
    }

    func testReviewCard_again_emptyRelearningSteps_staysReview() {
        SRSEngine.config.relearningSteps = []
        let card = reviewCard(interval: 10)
        let result = process(card, rating: .again)
        XCTAssertEqual(result.updatedData.cardStatus, .review)
        XCTAssertEqual(result.updatedData.interval, SRSEngine.config.relearningGraduationInterval)
        XCTAssertTrue(result.didLapse)
    }

    func testReviewCard_hard_multipliesIntervalByHardMultiplier() {
        let card = reviewCard(interval: 10, easeFactor: 2.5)
        let result = process(card, rating: .hard)
        XCTAssertEqual(result.updatedData.cardStatus, .review)
        // 10 * 1.2 = 12 (fuzz=0)
        XCTAssertEqual(result.updatedData.interval, 12)
        XCTAssertEqual(result.updatedData.easeFactor, 2.5 - SRSEngine.config.hardEaseFactorDelta, accuracy: 0.001)
    }

    func testReviewCard_good_multipliesIntervalByEaseFactor() {
        let card = reviewCard(interval: 10, easeFactor: 2.5)
        let result = process(card, rating: .good)
        XCTAssertEqual(result.updatedData.cardStatus, .review)
        // 10 * 2.5 = 25 (fuzz=0)
        XCTAssertEqual(result.updatedData.interval, 25)
        // easeFactor unchanged on .good
        XCTAssertEqual(result.updatedData.easeFactor, 2.5, accuracy: 0.001)
    }

    func testReviewCard_easy_appliesEasyBonus() {
        let card = reviewCard(interval: 10, easeFactor: 2.5)
        let result = process(card, rating: .easy)
        XCTAssertEqual(result.updatedData.cardStatus, .review)
        // 10 * 2.5 * 1.3 = 32.5 → 33 when rounded (fuzz=0)
        let expected = Int((10.0 * 2.5 * SRSEngine.config.easyBonus).rounded())
        XCTAssertEqual(result.updatedData.interval, expected)
        XCTAssertEqual(result.updatedData.easeFactor, 2.5 + SRSEngine.config.easyEaseFactorDelta, accuracy: 0.001)
    }

    func testReviewCard_repeatedAgain_easeFactorNeverDropsBelowMinimum() {
        var card = reviewCard(interval: 10, easeFactor: SRSEngine.config.minimumEaseFactor)
        for _ in 0..<20 {
            let result = process(card, rating: .again)
            card = result.updatedData
            // Re-set status to .review so we keep hitting review logic
            card.cardStatus = .review
        }
        XCTAssertGreaterThanOrEqual(card.easeFactor, SRSEngine.config.minimumEaseFactor)
    }

    // MARK: - Relearning Phase Tests

    func testRelearningCard_again_staysAtStep0_andDecreaseEase() {
        let card = relearningCard(step: 0, easeFactor: 2.5)
        let result = process(card, rating: .again)
        XCTAssertEqual(result.updatedData.cardStatus, .relearning(step: 0))
        XCTAssertEqual(result.updatedData.easeFactor, max(SRSEngine.config.minimumEaseFactor, 2.5 - SRSEngine.config.againEaseFactorDelta), accuracy: 0.001)
    }

    func testRelearningCard_good_advancesToNextStep() {
        // Default relearningSteps = [10], so there's only 1 step
        // Add an extra step so we can test mid-step advancement
        SRSEngine.config.relearningSteps = [10, 20]
        let card = relearningCard(step: 0)
        let result = process(card, rating: .good)
        XCTAssertEqual(result.updatedData.cardStatus, .relearning(step: 1))
        let expected = Calendar.current.date(byAdding: .minute, value: 20, to: t0)!
        XCTAssertEqual(result.updatedData.nextReviewDate, expected)
        XCTAssertFalse(result.didGraduate)
    }

    func testRelearningCard_good_finalStep_graduatesBackToReview() {
        // Default has 1 step ([10]), so rating .good on step 0 should graduate
        let card = relearningCard(step: 0)
        let result = process(card, rating: .good)
        XCTAssertEqual(result.updatedData.cardStatus, .review)
        XCTAssertEqual(result.updatedData.interval, SRSEngine.config.relearningGraduationInterval)
        XCTAssertTrue(result.didGraduate)
    }

    func testRelearningCard_easy_immediatelyGraduates() {
        let card = relearningCard(step: 0, easeFactor: 2.5)
        let result = process(card, rating: .easy)
        XCTAssertEqual(result.updatedData.cardStatus, .review)
        XCTAssertEqual(result.updatedData.interval, SRSEngine.config.relearningGraduationInterval)
        XCTAssertTrue(result.didGraduate)
        XCTAssertEqual(result.updatedData.easeFactor, 2.5 + SRSEngine.config.easyEaseFactorDelta, accuracy: 0.001)
    }

    // MARK: - Fuzz Factor Tests

    func testFuzzFactor_producesVariation() {
        SRSEngine.config.fuzzFactor = 0.05
        let card = reviewCard(interval: 10)
        var intervals = Set<Int>()
        for _ in 0..<1000 {
            let result = SRSEngine.processReview(currentData: card, rating: .good, reviewedAt: t0)
            intervals.insert(result.updatedData.interval)
        }
        XCTAssertGreaterThan(intervals.count, 1, "Fuzz should produce some variation across 1000 runs")
    }

    func testFuzzFactor_staysWithinBounds() {
        SRSEngine.config.fuzzFactor = 0.05
        let card = reviewCard(interval: 10, easeFactor: 2.5)
        let unfuzzed = Int((Double(10) * 2.5).rounded()) // = 25
        let lower = Int(Double(unfuzzed) * 0.90)
        let upper = Int(Double(unfuzzed) * 1.10) + 1
        for _ in 0..<1000 {
            let result = SRSEngine.processReview(currentData: card, rating: .good, reviewedAt: t0)
            XCTAssertTrue((lower...upper).contains(result.updatedData.interval),
                          "Interval \(result.updatedData.interval) outside ±10% of \(unfuzzed)")
        }
    }

    // MARK: - ReviewResult Tests

    func testReviewResult_didGraduate_setWhenLearningCardPassesFinalStep() {
        var card = newCard()
        // Move through all learning steps
        for _ in SRSEngine.config.learningSteps.indices.dropLast() {
            card = process(card, rating: .good).updatedData
        }
        let result = process(card, rating: .good)
        XCTAssertTrue(result.didGraduate)
    }

    func testReviewResult_didLapse_setWhenReviewCardRatedAgain() {
        let card = reviewCard(interval: 10)
        let result = process(card, rating: .again)
        XCTAssertTrue(result.didLapse)
        XCTAssertFalse(result.didGraduate)
    }

    func testReviewResult_previousInterval_matchesCardBeforeCall() {
        let card = reviewCard(interval: 42)
        let result = process(card, rating: .good)
        XCTAssertEqual(result.previousInterval, 42)
    }

    func testReviewResult_reviewedAt_matchesInjectedDate() {
        let card = reviewCard(interval: 10)
        let result = process(card, rating: .good)
        XCTAssertEqual(result.reviewedAt, t0)
    }
}
