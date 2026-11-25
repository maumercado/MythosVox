import Foundation

struct VoicePreset: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var pitchCents: Float
    var distortionMix: Float
    var reverbMix: Float

    init(
        id: UUID = UUID(),
        name: String,
        pitchCents: Float = 0,
        distortionMix: Float = 0,
        reverbMix: Float = 0
    ) {
        self.id = id
        self.name = name
        self.pitchCents = pitchCents
        self.distortionMix = distortionMix
        self.reverbMix = reverbMix
    }
}

extension VoicePreset {
    static let defaults: [VoicePreset] = [
        VoicePreset(
            id: UUID(uuidString: "A7545D9B-4935-42B4-AC0A-9008E6EEB4B8")!,
            name: "Natural"
        ),
        VoicePreset(
            id: UUID(uuidString: "77186E67-905B-4AE1-BA32-F9C7AE5C9028")!,
            name: "Deep Space",
            pitchCents: -450,
            distortionMix: 18,
            reverbMix: 42
        ),
        VoicePreset(
            id: UUID(uuidString: "DAB58AC0-AC1E-4A81-9946-58561900C862")!,
            name: "Fae Echo",
            pitchCents: 320,
            distortionMix: 4,
            reverbMix: 58
        )
    ]
}
