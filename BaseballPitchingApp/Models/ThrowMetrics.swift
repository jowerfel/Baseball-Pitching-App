import Foundation

struct ThrowMetrics: Codable, Hashable, Sendable {
    var relativeStridePixels: Double?
    var releasePointHeight: Double?
    var shoulderAngleDegrees: Double?
    var armSlotDegrees: Double?
    var armSlotLabel: String
    var pitchingHand: PitchingHand?
    var estimatedPitchSpeedMPH: Double?
    var strideLengthFeet: Double?

    init(
        relativeStridePixels: Double? = nil,
        releasePointHeight: Double? = nil,
        shoulderAngleDegrees: Double? = nil,
        armSlotDegrees: Double? = nil,
        armSlotLabel: String = "Not Calculated",
        pitchingHand: PitchingHand? = nil,
        estimatedPitchSpeedMPH: Double? = nil,
        strideLengthFeet: Double? = nil
    ) {
        self.relativeStridePixels = relativeStridePixels
        self.releasePointHeight = releasePointHeight
        self.shoulderAngleDegrees = shoulderAngleDegrees
        self.armSlotDegrees = armSlotDegrees
        self.armSlotLabel = armSlotLabel
        self.pitchingHand = pitchingHand
        self.estimatedPitchSpeedMPH = estimatedPitchSpeedMPH
        self.strideLengthFeet = strideLengthFeet
    }
}

extension ThrowMetrics {
    var relativeStrideDisplayValue: String {
        guard let pixels = relativeStridePixels else { return "Not Calculated" }
        // We'll store the converted value in a new property or calculate it here if we have a scale
        // For now, let's assume we'll add a 'strideLengthFeet' property
        return strideLengthDisplayValue ?? "\(formatted(pixels, suffix: "px"))"
    }

    var strideLengthDisplayValue: String? {
        guard let feet = strideLengthFeet else { return nil }
        let totalInches = Int(round(feet * 12))
        let ft = totalInches / 12
        let inch = totalInches % 12
        return "\(ft)' \(inch)\""
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
