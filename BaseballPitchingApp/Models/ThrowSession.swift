import Foundation
import SwiftData

@Model
final class ThrowSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var videoURL: String
    private var metricsData: Data
    private var landmarksData: Data

    init(
        id: UUID = UUID(),
        date: Date = .now,
        videoURL: String = "",
        metrics: ThrowMetrics = ThrowMetrics(),
        landmarks: [PerFrameLandmarks] = []
    ) {
        self.id = id
        self.date = date
        self.videoURL = videoURL
        self.metricsData = Self.encode(metrics)
        self.landmarksData = Self.encode(landmarks)
    }

    var metrics: ThrowMetrics {
        get { Self.decode(ThrowMetrics.self, from: metricsData) ?? ThrowMetrics() }
        set { metricsData = Self.encode(newValue) }
    }

    var landmarks: [PerFrameLandmarks] {
        get { Self.decode([PerFrameLandmarks].self, from: landmarksData) ?? [] }
        set { landmarksData = Self.encode(newValue) }
    }
}

private extension ThrowSession {
    static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(value) else {
            return Data()
        }

        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }
}
