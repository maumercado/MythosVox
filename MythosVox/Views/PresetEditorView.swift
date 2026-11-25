import SwiftUI

struct PresetEditorView: View {
    @ObservedObject var store: PresetStore
    let onChange: (VoicePreset) -> Void

    var body: some View {
        Section("Voice effect") {
            TextField("Preset name", text: nameBinding)

            effectSlider(
                title: "Pitch",
                value: pitchBinding,
                range: -1_200...1_200,
                step: 10,
                formattedValue: "\(Int(store.selectedPreset.pitchCents)) cents"
            )

            effectSlider(
                title: "Distortion",
                value: distortionBinding,
                range: 0...100,
                step: 1,
                formattedValue: "\(Int(store.selectedPreset.distortionMix))%"
            )

            effectSlider(
                title: "Reverb",
                value: reverbBinding,
                range: 0...100,
                step: 1,
                formattedValue: "\(Int(store.selectedPreset.reverbMix))%"
            )
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.selectedPreset.name },
            set: { newName in
                updatePreset { $0.name = newName }
            }
        )
    }

    private var pitchBinding: Binding<Float> {
        Binding(
            get: { store.selectedPreset.pitchCents },
            set: { newValue in
                updatePreset { $0.pitchCents = newValue }
            }
        )
    }

    private var distortionBinding: Binding<Float> {
        Binding(
            get: { store.selectedPreset.distortionMix },
            set: { newValue in
                updatePreset { $0.distortionMix = newValue }
            }
        )
    }

    private var reverbBinding: Binding<Float> {
        Binding(
            get: { store.selectedPreset.reverbMix },
            set: { newValue in
                updatePreset { $0.reverbMix = newValue }
            }
        )
    }

    private func updatePreset(_ transform: (inout VoicePreset) -> Void) {
        store.updateSelected(transform)
        onChange(store.selectedPreset)
    }

    private func effectSlider(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        formattedValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
        .accessibilityElement(children: .combine)
    }
}
