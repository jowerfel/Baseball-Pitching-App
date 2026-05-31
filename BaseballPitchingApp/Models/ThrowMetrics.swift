import Foundation

struct ThrowMetrics: Codable, Hashable, Sendable {
    var relativeStridePixels: Double?
    var releasePointHeight: Double?
    var shoulderAngleDegrees: Double?
    var armSlotDegrees: Double?
    var armSlotLabel: String
    var pitchingHand: PitchingHand?
    var estimatedPitchSpeedMPH: Double?

    init(
        relativeStridePixels: Double? = nil,
        releasePointHeight: Double? = nil,
        shoulderAngleDegrees: Double? = nil,
        armSlotDegrees: Double? = nil,
        armSlotLabel: String = "Not Calculated",
        pitchingHand: PitchingHand? = nil,
        estimatedPitchSpeedMPH: Double? = nil
    ) {
        self.relativeStridePixels = relativeStridePixels
        self.releasePointHeight = releasePointHeight
        self.shoulderAngleDegrees = shoulderAngleDegrees
        self.armSlotDegrees = armSlotDegrees
        self.armSlotLabel = armSlotLabel
        self.pitchingHand = pitchingHand
        self.estimatedPitchSpeedMPH = estimatedPitchSpeedMPH
    }
}

extension ThrowMetrics {
    var relativeStrideDisplayValue: String {
        formatted(relativeStridePixels, suffix: "px")
    }

    var releasePointHeightDisplayValue: String {
        formatted(releasePointHeight, suffix: "")
    }

    var shoulderAngleDisplayValue: String {
        formatted(shoulderAngleDegrees, suffix: "deg")
    }

    var armSlotDegreesDisplayValue: String {
        formatted(armSlotDegrees, suffix: "deg")
    }

    var armSlotDisplayValue: String {
        guard let armSlotDegrees else {
            return armSlotLabel
        }

        return "\(armSlotLabel) (\(formatted(armSlotDegrees, suffix: "deg")))"
    }

    var pitchingHandDisplayValue: String {
        pitchingHand?.displayName ?? "Not Set"
    }

    var estimatedPitchSpeedDisplayValue: String {
        guard let estimatedPitchSpeedMPH else {
            return "Not Calculated"
        }

        return "\(estimatedPitchSpeedMPH.formatted(.number.precision(.fractionLength(0...1)))) mph"
    }

    private func formatted(_ value: Double?, suffix: String) -> String {
        guard let value else {
            return "Not Calculated"
        }

        let number = value.formatted(
            .number
                .precision(.fractionLength(0...2))
        )

        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }
}
