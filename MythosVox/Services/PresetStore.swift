import Combine
import Foundation

@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [VoicePreset]
    @Published var selectedPresetID: VoicePreset.ID {
        didSet {
            defaults.set(selectedPresetID.uuidString, forKey: Keys.selectedPresetID)
        }
    }

    private enum Keys {
        static let presets = "voicePresets"
        static let selectedPresetID = "selectedVoicePresetID"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let decodedPresets = defaults.data(forKey: Keys.presets)
            .flatMap { try? JSONDecoder().decode([VoicePreset].self, from: $0) }
        let availablePresets = decodedPresets.flatMap { presets in
            presets.isEmpty ? nil : presets
        } ?? VoicePreset.defaults

        presets = availablePresets

        let storedSelection = defaults.string(forKey: Keys.selectedPresetID)
            .flatMap(UUID.init(uuidString:))
        selectedPresetID = storedSelection.flatMap { selection in
            availablePresets.contains { $0.id == selection } ? selection : nil
        } ?? availablePresets[0].id
    }

    var selectedPreset: VoicePreset {
        presets.first { $0.id == selectedPresetID } ?? presets[0]
    }

    func updateSelected(_ transform: (inout VoicePreset) -> Void) {
        guard let index = presets.firstIndex(where: { $0.id == selectedPresetID }) else {
            return
        }

        transform(&presets[index])
        persist()
    }

    func addPreset() {
        let preset = VoicePreset(
            name: "New Preset",
            pitchCents: selectedPreset.pitchCents,
            distortionMix: selectedPreset.distortionMix,
            reverbMix: selectedPreset.reverbMix
        )
        presets.append(preset)
        selectedPresetID = preset.id
        persist()
    }

    func duplicateSelected() {
        let sourcePreset = selectedPreset
        let copy = VoicePreset(
            name: "\(sourcePreset.name) Copy",
            pitchCents: sourcePreset.pitchCents,
            distortionMix: sourcePreset.distortionMix,
            reverbMix: sourcePreset.reverbMix
        )
        presets.append(copy)
        selectedPresetID = copy.id
        persist()
    }

    func deleteSelected() {
        guard presets.count > 1,
              let index = presets.firstIndex(where: { $0.id == selectedPresetID })
        else {
            return
        }

        presets.remove(at: index)
        selectedPresetID = presets[min(index, presets.count - 1)].id
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(presets) else {
            return
        }
        defaults.set(data, forKey: Keys.presets)
    }
}
