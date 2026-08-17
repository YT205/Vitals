import Foundation
import SwiftData

/// One drink you logged.
///
/// Every entry is also written to HealthKit as `dietaryWater`. SwiftData is what
/// the UI reads (it's fast and works even if you deny Health access); HealthKit
/// is what makes the data outlive the app.
@Model
final class WaterEntry {
    var amountML: Double = 0
    var loggedAt: Date = Date.now
    /// `true` once mirrored into HealthKit, so failed writes can be retried.
    var savedToHealthKit: Bool = false

    init(amountML: Double, loggedAt: Date = .now) {
        self.amountML = amountML
        self.loggedAt = loggedAt
    }
}
