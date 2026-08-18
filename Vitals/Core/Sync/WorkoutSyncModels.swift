import Foundation

// The wire format between iPhone and watch. Plain Codable structs, versioned
// by key, so either side can evolve without SwiftData models crossing devices.
//
// Phone -> watch: the full template library plus unit preferences, sent as
// WCSession application context (latest state wins, delivered even if the
// watch app was closed).
// Watch -> phone: each finished workout, sent as queued user info (survives
// the phone being unreachable mid-workout).

enum SyncKeys {
    static let templates = "templates"
    static let weightUnit = "weightUnit"
    static let volumeUnit = "volumeUnit"
    static let waterGoalML = "waterGoalML"
    static let pushedAt = "pushedAt"
    static let finishedWorkout = "finishedWorkout"
}

// MARK: - Phone -> Watch

struct SyncTemplate: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let sortOrder: Int
    let items: [SyncTemplateItem]
}

struct SyncTemplateItem: Codable, Hashable {
    let exerciseName: String
    let muscleGroupRaw: String
    let restSeconds: Int
    let sets: [SyncPlanSet]
}

struct SyncPlanSet: Codable, Hashable {
    let setNumber: Int
    let reps: Int
    let weightKg: Double
}

// MARK: - Watch -> Phone

struct SyncFinishedWorkout: Codable {
    let title: String
    let startedAt: Date
    let endedAt: Date
    let sets: [SyncPerformedSet]
}

struct SyncPerformedSet: Codable {
    let exerciseName: String
    let muscleGroupRaw: String
    let exerciseOrder: Int
    let setNumber: Int
    let weightKg: Double
    let reps: Int
    let durationSeconds: Double
    let restSeconds: Int
}

// MARK: - Coding helpers

enum SyncCoder {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
