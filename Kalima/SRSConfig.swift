import Foundation

/// All tunable parameters for the SRS algorithm.
struct SRSConfig {
    // The minimum number of days before a card is shown again after any correct answer.
    var minimumInterval: Int = 1

    // For .easy responses: the interval is multiplied by (easeFactor × easyBonus).
    var easyBonus: Double = 1.3

    // The initial interval assigned when a card skips learning via an .easy response.
    var easyFirstInterval: Double = 4.0

    // For .hard responses: the interval is multiplied by this fixed value instead of easeFactor.
    var hardIntervalMultiplier: Double = 1.2

    // The easeFactor can never fall below this floor.
    var minimumEaseFactor: Double = 1.3

    // How much easeFactor increases on an .easy response.
    var easyEaseFactorDelta: Double = 0.15

    // How much easeFactor decreases on a .hard response.
    var hardEaseFactorDelta: Double = 0.15

    // How much easeFactor decreases on an .again response.
    var againEaseFactorDelta: Double = 0.20

    // The interval (in days) assigned when a card fails review and enters relearning.
    var relearningGraduationInterval: Int = 1

    // Learning steps in minutes. A new card must pass through all steps before entering review.
    var learningSteps: [Int] = [1, 10]

    // Relearning steps in minutes. Applied when a review card is rated .again.
    var relearningSteps: [Int] = [10]

    // The upper bound of the random fuzz factor applied to intervals greater than 2 days.
    // A value of 0.05 means the interval can vary by ±5%.
    var fuzzFactor: Double = 0.05
}
