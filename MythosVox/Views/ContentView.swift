import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var presetStore = PresetStore()
    @StateObject private var audio = AudioEngineController()

    @State private var speechText = "Beyond the old gate, the forest remembers."
    @State private var isImportingAmbiance = false
    @State private var presentedError: PresentedError?

    var body: some View {
        NavigationSplitView {
            presetList
                .navigationTitle("Presets")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: presetStore.addPreset) {
                            Label("New preset", systemImage: "plus")
                        }
                        Menu {
                            Button("Duplicate", action: presetStore.duplicateSelected)
                            Button(
                                "Delete",
                                role: .destructive,
                                action: presetStore.deleteSelected
                            )
                            .disabled(presetStore.presets.count == 1)
                        } label: {
                            Label("Preset actions", systemImage: "ellipsis.circle")
                        }
                    }
                }
        } detail: {
            Form {
                liveAudioSection
                PresetEditorView(store: presetStore, onChange: audio.apply)
                volumesSection
                speechSection
                ambianceSection
            }
            .formStyle(.grouped)
            .navigationTitle(presetStore.selectedPreset.name)
            .frame(minWidth: 420, minHeight: 560)
        }
        .onAppear {
            audio.apply(presetStore.selectedPreset)
        }
        .onChange(of: presetStore.selectedPresetID) {
            audio.apply(presetStore.selectedPreset)
        }
        .fileImporter(
            isPresented: $isImportingAmbiance,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleAmbianceImport
        )
        .alert(item: $presentedError) { error in
            Alert(
                title: Text("Unable to import ambiance"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var presetList: some View {
        List(presetStore.presets) { preset in
            Button {
                presetStore.selectedPresetID = preset.id
            } label: {
                HStack {
                    Text(preset.name)
                    Spacer()
                    if preset.id == presetStore.selectedPresetID {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var liveAudioSection: some View {
        Section("Live voice") {
            HStack {
                Label(audio.state.label, systemImage: stateSymbol)
                    .foregroundStyle(stateColor)
                Spacer()
                if audio.state == .running {
                    Button("Stop", role: .destructive, action: audio.stop)
                } else {
                    Button("Start") {
                        Task {
                            await audio.start()
                        }
                    }
                    .disabled(audio.state == .starting)
                }
            }

            Label(
                "Use headphones while monitoring your microphone to prevent feedback.",
                systemImage: "headphones"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var volumesSection: some View {
        Section("Volumes") {
            volumeSlider(
                title: "Voice",
                systemImage: "waveform",
                value: $audio.voiceVolume
            )
            volumeSlider(
                title: "Speech",
                systemImage: "text.bubble",
                value: $audio.speechVolume
            )
            volumeSlider(
                title: "Ambiance",
                systemImage: "leaf",
                value: $audio.ambianceVolume
            )
            volumeSlider(
                title: "Master",
                systemImage: "speaker.wave.3",
                value: $audio.masterVolume
            )
        }
    }

    private var speechSection: some View {
        Section("Text to speech") {
            TextEditor(text: $speechText)
                .frame(minHeight: 88)

            HStack {
                Button {
                    audio.speak(speechText)
                } label: {
                    Label("Speak", systemImage: "play.fill")
                }
                .disabled(speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Stop", action: audio.stopSpeaking)
            }
        }
    }

    private var ambianceSection: some View {
        Section("Looping ambiance") {
            if let ambianceName = audio.ambianceName {
                HStack {
                    Label(ambianceName, systemImage: "music.note")
                    Spacer()
                    Button("Remove", role: .destructive, action: audio.removeAmbiance)
                }
            } else {
                Text("No audio imported")
                    .foregroundStyle(.secondary)
            }

            Button {
                isImportingAmbiance = true
            } label: {
                Label("Import audio…", systemImage: "square.and.arrow.down")
            }
        }
    }

    private func volumeSlider(
        title: String,
        systemImage: String,
        value: Binding<Float>
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .frame(width: 110, alignment: .leading)
            Slider(value: value, in: 0...1)
            Text("\(Int(value.wrappedValue * 100))%")
                .frame(width: 46, alignment: .trailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var stateSymbol: String {
        switch audio.state {
        case .stopped:
            "stop.circle"
        case .starting:
            "ellipsis.circle"
        case .running:
            "waveform.circle.fill"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var stateColor: Color {
        switch audio.state {
        case .running:
            .green
        case .failed:
            .red
        default:
            .secondary
        }
    }

    private func handleAmbianceImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }
            try audio.importAmbiance(from: url)
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}

private struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    ContentView()
}
