import Foundation

struct ReviewResult {
    let updatedData: SRSData

    let previousInterval: Int

    let scheduledIntervalDays: Int

    let rating: SRSEngine.ResponseRating

    let reviewedAt: Date

    let didGraduate: Bool

    let didLapse: Bool
}
